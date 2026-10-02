-- ============================================================
-- 323_eu_customer_reverse_charge_tests.sql — B3 (ven-009)
--
-- Recette /qa du 29/09/2026. Une facture à un client UE assujetti était une
-- facture française ordinaire : 20 % proposé, écriture 411 D 250 / **707000**
-- C 250 sans aucun `vat_code`, Factur-X `CategoryCode>Z` sans motif.
--
-- Mesuré sur la base de recette à la 322, AVANT la 323 (les quatre premières
-- échouent à l'exécution : la fonction, la colonne ou le déclencheur n'existe
-- pas — c'est le défaut même) :
--   T01 ❌ `resolve_fiscal_regime` n'existe pas
--   T02 ❌ `is_eu_country` n'existe pas
--   T03 ❌ `customers.fiscal_position_id` n'existe pas
--   T04 ❌ `ensure_standard_fiscal_position` n'existe pas
--   T05 ❌ la ligne part en FR20 : 411 D **300**, 1 ligne 445x de **50,00**
--   T06 ❌ la CA3 déclare **50,00** de TVA collectée sur une vente intracom.
--   T07 ❌ le client hors UE part aussi en FR20 à 20 %
-- Après la 323 : 7/7 verts.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '323', false);
DELETE FROM _audit_results WHERE file = '323';

-- Une société avec un client par régime, une prestation et une facture validée.
CREATE OR REPLACE FUNCTION _mk_facture323(p_nom text, p_pays text, p_tva text,
  OUT t uuid, OUT facture uuid, OUT ligne uuid, OUT client uuid)
LANGUAGE plpgsql AS $$
DECLARE p uuid; inv uuid; l uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name, country, vat_number)
  VALUES (t, 'Client ' || p_nom, p_pays, NULLIF(p_tva, '')) RETURNING id INTO client;

  INSERT INTO products (tenant_id, name, sku, type, sale_price, vat_rate)
  VALUES (t, 'Prestation ' || p_nom, 'S-' || p_nom, 'service', 250, 20) RETURNING id INTO p;

  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (t, client, 'Client ' || p_nom, '2026-03-15', '2026-04-15', 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (t, inv, p, 'Prestation', 1, 250, 20, 0) RETURNING id INTO l;

  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  PERFORM set_config('role', 'postgres', true);

  facture := inv; ligne := l;
END $$;

-- T01 : la déduction du régime, pays × n° de TVA
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (VALUES
    ('FR', 'FR12345678901', 'fr'),
    ('BE', 'BE0123456789',  'eu_vat'),
    ('DE', '',              'non_eu'),   -- UE sans n° de TVA : pas d'assujetti
    ('US', 'US99',          'non_eu'),
    ('GB', 'GB99',          'non_eu'),   -- sorti de l'UE
    (NULL, 'FR99',          NULL),       -- pays inconnu : on ne devine pas
    ('',   '',              NULL)
  ) AS v(pays, tva, attendu)
  WHERE resolve_fiscal_regime(v.pays, v.tva) IS DISTINCT FROM v.attendu;

  PERFORM _rec('T01', 'le régime se déduit du pays et du n° de TVA (7 cas)', n = 0,
    format('%s cas discordants (0 attendu)', n));
END $$;

-- T02 : l'Union européenne, et rien de plus
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (VALUES
    ('FR', true), ('DE', true), ('IT', true), ('ES', true), ('BE', true), ('NL', true), ('SE', true),
    ('CH', false), ('MA', false), ('US', false), ('GB', false), ('DJ', false), ('fr', true), (' DE ', true)
  ) AS v(code, attendu)
  WHERE is_eu_country(v.code) IS DISTINCT FROM v.attendu;

  PERFORM _rec('T02', 'is_eu_country : 27 États membres, et rien d''autre', n = 0,
    format('%s cas discordants (0 attendu)', n));
END $$;

-- T03 : un client UE assujetti reçoit la position « UE assujetti »
DO $$
DECLARE v record; regime text; nom text; pos_id uuid;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_facture323('T03', 'BE', 'BE0123456789')) x;
  SELECT fp.regime, fp.name INTO regime, nom
  FROM customers c JOIN fiscal_positions fp ON fp.id = c.fiscal_position_id AND fp.tenant_id = c.tenant_id
  WHERE c.id = v.client;
  SELECT fiscal_position_id INTO pos_id FROM customers WHERE id = v.client;

  PERFORM _rec('T03', 'un client belge assujetti reçoit la position « UE assujetti »',
    pos_id IS NOT NULL AND regime = 'eu_vat' AND nom = 'UE assujetti',
    format('position=%s régime=%s nom=%s', COALESCE(pos_id::text, 'aucune'), COALESCE(regime, '—'), COALESCE(nom, '—')));
END $$;

-- T04 : un choix explicite n'est jamais écrasé
DO $$
DECLARE v record; pos_fr uuid; pos_apres uuid; regime text;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_facture323('T04', 'BE', 'BE0123456789')) x;
  pos_fr := ensure_standard_fiscal_position(v.t, 'fr');
  UPDATE customers SET fiscal_position_id = pos_fr WHERE id = v.client;
  -- Le pays et la TVA disent toujours « UE assujetti », mais le choix est figé
  UPDATE customers SET country = 'BE', vat_number = 'BE0123456789' WHERE id = v.client;

  SELECT c.fiscal_position_id, fp.regime INTO pos_apres, regime
  FROM customers c LEFT JOIN fiscal_positions fp ON fp.id = c.fiscal_position_id
  WHERE c.id = v.client;

  PERFORM _rec('T04', 'une position fiscale choisie à la main n''est pas remplacée',
    pos_apres = pos_fr AND regime = 'fr',
    format('régime=%s (fr attendu, conservé)', COALESCE(regime, '—')));
END $$;

-- T05 : la ligne d'une vente à un client UE ne porte pas de TVA française
DO $$
DECLARE v record; code text; taux numeric; tva numeric; c411 numeric; c70 numeric; c445 int;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_facture323('T05', 'BE', 'BE0123456789')) x;
  SELECT l.vat_code, l.vat_rate, l.vat_total INTO code, taux, tva
  FROM invoice_lines l WHERE l.id = v.ligne;

  -- Le compte de vente exact dépend du type de l'article (706000 pour une
  -- prestation, depuis B2) : ce qui compte ici est la classe 70 et l'absence
  -- de toute ligne de TVA.
  SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '411000'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code ~ '^7'), 0),
         count(*) FILTER (WHERE jl.account_code ~ '^445')
    INTO c411, c70, c445
  FROM journal_lines jl JOIN invoices i ON i.transferred_entry_id = jl.journal_id
  WHERE i.id = v.facture;

  PERFORM _rec('T05', 'vente à un client UE : code UE, 0 % de TVA, 411 D 250 / 70x C 250 sans 445x',
    code = 'UE' AND taux = 0 AND tva = 0 AND c411 = 250 AND c70 = 250 AND c445 = 0,
    format('code=%s taux=%s TVA=%s | 411=%s credits 70x=%s lignes 445x=%s', COALESCE(code, '—'), taux, tva, c411, c70, c445));
END $$;

-- T06 : le CA déclaré porte l'opération, mais pas de TVA collectée
DO $$
DECLARE v record; ca3 jsonb;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_facture323('T06', 'BE', 'BE0123456789')) x;
  PERFORM _as_user();
  ca3 := calculate_vat_ca3(DATE '2026-03-01', DATE '2026-03-31');
  PERFORM set_config('role', 'postgres', true);

  PERFORM _rec('T06', 'CA3 : le CA non taxé est déclaré, la TVA collectée reste nulle',
    (ca3->>'total_sales')::numeric = 250 AND (ca3->>'vat_collected')::numeric = 0,
    format('CA=%s (250 attendu) TVA collectée=%s (0 attendu)', ca3->>'total_sales', ca3->>'vat_collected'));
END $$;

-- T07 : non-régression — un client français reste taxé, un client hors UE exonéré
DO $$
DECLARE v_fr record; v_us record; code_fr text; taux_fr numeric; tva_fr numeric; code_us text; taux_us numeric;
BEGIN
  SELECT * INTO v_fr FROM (SELECT * FROM _mk_facture323('T07FR', 'FR', 'FR12345678901')) x;
  SELECT l.vat_code, l.vat_rate, l.vat_total INTO code_fr, taux_fr, tva_fr FROM invoice_lines l WHERE l.id = v_fr.ligne;

  SELECT * INTO v_us FROM (SELECT * FROM _mk_facture323('T07US', 'US', 'US99')) x;
  SELECT l.vat_code, l.vat_rate INTO code_us, taux_us FROM invoice_lines l WHERE l.id = v_us.ligne;

  PERFORM _rec('T07', 'client français : FR20 à 20 % ; client hors UE : EXO à 0 %',
    code_fr = 'FR20' AND taux_fr = 20 AND tva_fr = 50 AND code_us = 'EXO' AND taux_us = 0,
    format('FR : %s / %s %% / TVA %s | US : %s / %s %%', COALESCE(code_fr, '—'), taux_fr, tva_fr, COALESCE(code_us, '—'), taux_us));
END $$;

DROP FUNCTION _mk_facture323(text, text, text);
SELECT _audit_assert('323');