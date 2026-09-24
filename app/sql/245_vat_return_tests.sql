-- ============================================================
-- 245_vat_return_tests.sql — M-10 : la déclaration de TVA (CA3)
--
-- Module jamais audité par exécution (phase 3 du reste-à-faire, § 6 ;
-- `vat_returns` figure en tête des tables « logique écrite jamais traversée »
-- de doc/audit/COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md).
--
-- Deux chemins produisent la CA3, et l'écran « Déclarations de TVA » offre les
-- deux boutons côte à côte :
--   1. « Calculer la TVA CA3 » / « Générer »  → calculate_vat_ca3 puis
--      generate_vat_return, qui lisent les SOLDES des comptes 445x ;
--   2. « Calculer automatiquement » du formulaire → get_vat_summary_by_code,
--      qui lit les LIGNES portant un code de TVA, bornées par un exercice.
-- Ce fichier confronte les deux aux mêmes écritures et vérifie ce que la
-- déclaration enregistrée contient réellement, colonne par colonne, par rapport
-- à ce que VatReturnsPage.tsx en affiche.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '245', false);
DELETE FROM _audit_results WHERE file = '245';

-- Compte du paramétrage global pour un code et un sens
CREATE OR REPLACE FUNCTION _tva_acc(p_code text, p_dir text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT account_code FROM vat_account_mapping
  WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND vat_code = p_code AND direction = p_dir
$$;

-- Facture de vente validée (comme l'écran : en-tête brouillon + lignes, puis validation)
CREATE OR REPLACE FUNCTION _tva_invoice(p_t uuid, p_c uuid, p_date date, p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, 'FAC-' || left(uuid_generate_v4()::text, 8), p_c, 'Client', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, inv, 'Ligne', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2),
         round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

-- Facture fournisseur approuvée
CREATE OR REPLACE FUNCTION _tva_purchase(p_t uuid, p_s uuid, p_date date, p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FRN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, pi, 'Achat', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2),
         round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  RETURN pi;
END $$;

CREATE OR REPLACE FUNCTION _tva_parties(p_t uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO customers (tenant_id, name) VALUES (p_t, 'Client TVA');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (p_t, 'Fournisseur TVA', 'F0001');
$$;

-- Mars : vente 1 000 HT à 20 % (TVA 200), achat 500 HT à 20 % (TVA 100) → à payer 100
CREATE OR REPLACE FUNCTION _tva_mars(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c uuid; s uuid;
BEGIN
  SELECT id INTO c FROM customers WHERE tenant_id = p_t LIMIT 1;
  SELECT id INTO s FROM suppliers WHERE tenant_id = p_t LIMIT 1;
  PERFORM _tva_invoice(p_t, c, '2026-03-05', '[{"q":1,"p":1000,"r":20}]');
  PERFORM _tva_purchase(p_t, s, '2026-03-10', '[{"q":1,"p":500,"r":20}]');
END $$;

-- T01 — repère : la CA3 lue sur les soldes des comptes rend les bons chiffres
DO $$
DECLARE t uuid := _mk_tenant('TVA01'); r jsonb;
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    PERFORM _tva_mars(t);
    r := calculate_vat_ca3('2026-03-01', '2026-03-31');
    PERFORM _rec('T01', 'CA3 de mars sur les soldes : collectée 200, déductible 100, à payer 100',
      (r->>'vat_collected')::numeric = 200 AND (r->>'vat_deductible')::numeric = 100
        AND (r->>'vat_to_pay')::numeric = 100 AND (r->>'vat_credit')::numeric = 0,
      r::text);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T01', 'CA3 de mars sur les soldes : collectée 200, déductible 100, à payer 100', false, SQLERRM); END;
END $$;

-- T02 — la déclaration enregistrée porte les chiffres que l'écran affiche.
-- VatReturnsPage.tsx lit box5_net_vat (« TVA nette »), total_sales et
-- total_purchases ; generate_vat_return ne renseigne que box1/box2/box3.
DO $$
DECLARE t uuid := _mk_tenant('TVA02'); g jsonb; v record;
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    PERFORM _tva_mars(t);
    g := generate_vat_return('2026-03-01', '2026-03-31');
    SELECT box1_output_vat, box2_input_vat, box3_vat_due, box4_repayment_due, box5_net_vat,
           total_sales, total_purchases, vat_collected, vat_deductible, vat_to_pay
      INTO v FROM vat_returns WHERE id = (g->>'id')::uuid;
    PERFORM _rec('T02', 'déclaration générée : les colonnes lues par l''écran (nette 100, CA 1 000, achats 500) sont renseignées',
      v.box1_output_vat = 200 AND v.box2_input_vat = 100 AND v.box3_vat_due = 100
        AND v.box5_net_vat = 100 AND v.total_sales = 1000 AND v.total_purchases = 500,
      format('box1=%s box2=%s box3=%s box4=%s box5=%s CA=%s achats=%s (colonnes doubles : collectée=%s déductible=%s à payer=%s)',
             v.box1_output_vat, v.box2_input_vat, v.box3_vat_due, v.box4_repayment_due, v.box5_net_vat,
             v.total_sales, v.total_purchases, v.vat_collected, v.vat_deductible, v.vat_to_pay));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T02', 'déclaration générée : les colonnes lues par l''écran (nette 100, CA 1 000, achats 500) sont renseignées', false, SQLERRM); END;
END $$;

-- T03 — crédit de TVA : déductible > collectée. La CA3 doit porter un crédit
-- (case 4) et une TVA due nulle. L'écran affiche box5_net_vat en vert s'il est
-- négatif : encore faut-il qu'il soit écrit.
DO $$
DECLARE t uuid := _mk_tenant('TVA03'); g jsonb; v record; c uuid; s uuid;
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    SELECT id INTO c FROM customers WHERE tenant_id = t LIMIT 1;
    SELECT id INTO s FROM suppliers WHERE tenant_id = t LIMIT 1;
    PERFORM _tva_invoice(t, c, '2026-04-05', '[{"q":1,"p":100,"r":20}]');      -- collectée 20
    PERFORM _tva_purchase(t, s, '2026-04-10', '[{"q":1,"p":1000,"r":20}]');    -- déductible 200
    g := generate_vat_return('2026-04-01', '2026-04-30');
    SELECT box1_output_vat, box2_input_vat, box3_vat_due, box4_repayment_due, box5_net_vat
      INTO v FROM vat_returns WHERE id = (g->>'id')::uuid;
    PERFORM _rec('T03', 'crédit de TVA 180 : due 0, crédit 180 en case 4, nette -180',
      v.box1_output_vat = 20 AND v.box2_input_vat = 200 AND v.box3_vat_due = 0
        AND v.box4_repayment_due = 180 AND v.box5_net_vat = -180,
      format('box1=%s box2=%s box3=%s box4=%s box5=%s', v.box1_output_vat, v.box2_input_vat, v.box3_vat_due, v.box4_repayment_due, v.box5_net_vat));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T03', 'crédit de TVA 180 : due 0, crédit 180 en case 4, nette -180', false, SQLERRM); END;
END $$;

-- T04 — idempotence : le bouton « Générer » relancé sur la même période ne doit
-- pas créer une deuxième déclaration (motif des chemins d'annulation / doublons
-- relevé le 24/09). Une période déjà déposée ne doit pas non plus être réécrite.
DO $$
DECLARE t uuid := _mk_tenant('TVA04'); g1 jsonb; g2 jsonb; n int; err text := 'aucune';
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    PERFORM _tva_mars(t);
    g1 := generate_vat_return('2026-03-01', '2026-03-31');
    BEGIN
      g2 := generate_vat_return('2026-03-01', '2026-03-31');
    EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
    SELECT count(*) INTO n FROM vat_returns WHERE tenant_id = t AND period_start = '2026-03-01' AND period_end = '2026-03-31';
    PERFORM _rec('T04', 'générer deux fois la même période laisse UNE déclaration',
      n = 1, format('%s déclaration(s) pour mars ; deuxième appel : %s', n, err));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T04', 'générer deux fois la même période laisse UNE déclaration', false, SQLERRM); END;
END $$;

-- T05 — les deux chemins de l'écran rendent le même total. Une écriture de TVA
-- saisie à la main (OD) n'a pas de code de TVA sur ses lignes : get_vat_summary_by_code
-- filtre sur `vat_code IS NOT NULL`, calculate_vat_ca3 non.
DO $$
DECLARE t uuid := _mk_tenant('TVA05'); fy uuid; r jsonb; s_coll numeric;
  fr_c text := _tva_acc('FR20', 'collected');
BEGIN
  PERFORM _tva_parties(t);
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t;
  PERFORM _as_user();
  BEGIN
    PERFORM _tva_mars(t);
    -- régularisation saisie à la main : 60 de TVA collectée de plus
    PERFORM _entry(t, 'OD-TVA-REGUL', '2026-03-20',
      format('[{"a":"411000","d":360,"c":0},{"a":"706000","d":0,"c":300},{"a":"%s","d":0,"c":60}]', fr_c)::jsonb);
    r := calculate_vat_ca3('2026-03-01', '2026-03-31');
    SELECT COALESCE(sum(vat_amount), 0) INTO s_coll
      FROM get_vat_summary_by_code(fy, '2026-03-01', '2026-03-31') WHERE direction = 'collected';
    PERFORM _rec('T05', 'les deux chemins de l''écran donnent la même TVA collectée (260)',
      (r->>'vat_collected')::numeric = 260 AND s_coll = 260,
      format('soldes des comptes : %s ; synthèse par code : %s', r->>'vat_collected', s_coll));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T05', 'les deux chemins de l''écran donnent la même TVA collectée (260)', false, SQLERRM); END;
END $$;

-- T06 — déclarer décembre en janvier. Le formulaire passe l'exercice COURANT
-- (accounting.ts:172, getCurrentFiscalYearId : celui qui contient la date du jour)
-- et get_vat_summary_by_code borne la période à cet exercice (GREATEST/LEAST).
-- La déclaration de décembre préparée en janvier doit rendre décembre, pas zéro.
DO $$
DECLARE t uuid := _mk_tenant('TVA06', false); fy2026 uuid; c uuid; s uuid; s_coll numeric; n int;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open'), (t, '2026', '2026-01-01', '2026-12-31', 'open');
  SELECT id INTO fy2026 FROM fiscal_years WHERE tenant_id = t AND code = '2026';
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    SELECT id INTO c FROM customers WHERE tenant_id = t LIMIT 1;
    PERFORM _tva_invoice(t, c, '2025-12-10', '[{"q":1,"p":1000,"r":20}]');
    SELECT count(*), COALESCE(sum(vat_amount), 0) INTO n, s_coll
      FROM get_vat_summary_by_code(fy2026, '2025-12-01', '2025-12-31') WHERE direction = 'collected';
    PERFORM _rec('T06', 'décembre préparé en janvier : la synthèse rend 200 de TVA collectée, ou refuse — jamais zéro en silence',
      s_coll = 200, format('%s ligne(s), TVA collectée rendue = %s (exercice passé : 2026, période demandée : décembre 2025)', n, s_coll));
  EXCEPTION WHEN OTHERS THEN
    -- un refus explicite est acceptable : c'est le silence qui est fautif
    PERFORM _rec('T06', 'décembre préparé en janvier : la synthèse rend 200 de TVA collectée, ou refuse — jamais zéro en silence',
      true, 'refus explicite : ' || SQLERRM);
  END;
END $$;

-- T07 — « synthèse par code » : une ligne par code et par sens, pas une par
-- ligne d'écriture. L'écran appelle cette fonction par PostgREST, plafonné à
-- 1 000 lignes (PGRST_DB_MAX_ROWS) : au-delà, la CA3 du formulaire est tronquée
-- sans un mot, et la TVA déclarée est sous-évaluée.
DO $$
DECLARE t uuid := _mk_tenant('TVA07'); fy uuid; c uuid; n int; tot numeric; i int;
BEGIN
  PERFORM _tva_parties(t);
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t;
  PERFORM _as_user();
  BEGIN
    SELECT id INTO c FROM customers WHERE tenant_id = t LIMIT 1;
    FOR i IN 1..5 LOOP
      PERFORM _tva_invoice(t, c, ('2026-05-0' || i)::date, '[{"q":1,"p":100,"r":20}]');
    END LOOP;
    SELECT count(*), COALESCE(sum(vat_amount), 0) INTO n, tot
      FROM get_vat_summary_by_code(fy, '2026-05-01', '2026-05-31') WHERE direction = 'collected';
    PERFORM _rec('T07', 'synthèse par code : 5 factures au même taux rendent UNE ligne FR20 collectée de 100',
      n = 1 AND tot = 100, format('%s ligne(s) rendues, total %s — une par ligne d''écriture au lieu d''une par code', n, tot));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T07', 'synthèse par code : 5 factures au même taux rendent UNE ligne FR20 collectée de 100', false, SQLERRM); END;
END $$;

-- T08 — chiffre d'affaires non taxé. La base hors taxe de la CA3 est
-- reconstituée depuis la TVA (montant ÷ taux) : une vente exonérée, un export
-- ou une livraison intracommunautaire, qui ne portent aucune TVA, n'y entrent
-- pas. Les cases A2, E1 et E2 de la CA3 réclament pourtant cette base.
-- Défaut connu et ouvert : la corriger demande de tirer la base des comptes de
-- produits par code de TVA, pas des comptes de TVA.
DO $$
DECLARE t uuid := _mk_tenant('TVA08'); g jsonb; v record; c uuid;
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    SELECT id INTO c FROM customers WHERE tenant_id = t LIMIT 1;
    PERFORM _tva_invoice(t, c, '2026-06-05', '[{"q":1,"p":1000,"r":20}]');            -- taxée
    PERFORM _tva_invoice(t, c, '2026-06-08', '[{"q":1,"p":500,"r":0,"c":"EXO"}]');    -- exonérée
    g := generate_vat_return('2026-06-01', '2026-06-30');
    SELECT total_sales, box1_output_vat INTO v FROM vat_returns WHERE id = (g->>'id')::uuid;
    PERFORM _rec('T08', 'chiffre d''affaires déclaré : 1 500 (1 000 taxés + 500 exonérés), TVA 200',
      v.total_sales = 1500 AND v.box1_output_vat = 200,
      format('CA déclaré = %s pour 1 500 facturés ; TVA = %s', v.total_sales, v.box1_output_vat));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T08', 'chiffre d''affaires déclaré : 1 500 (1 000 taxés + 500 exonérés), TVA 200', false, SQLERRM); END;
END $$;

-- T09 — une déclaration déposée ne se recalcule pas en silence : relancer
-- « Générer » dessus doit être refusé, pas écraser les chiffres déposés.
DO $$
DECLARE t uuid := _mk_tenant('TVA09'); g jsonb; refused boolean := false; v record;
BEGIN
  PERFORM _tva_parties(t);
  PERFORM _as_user();
  BEGIN
    PERFORM _tva_mars(t);
    g := generate_vat_return('2026-03-01', '2026-03-31');
    UPDATE vat_returns SET status = 'submitted', submitted_date = '2026-04-15' WHERE id = (g->>'id')::uuid;
    -- une écriture de plus arrive après le dépôt
    PERFORM _tva_invoice(t, (SELECT id FROM customers WHERE tenant_id = t LIMIT 1), '2026-03-25', '[{"q":1,"p":2000,"r":20}]');
    BEGIN
      PERFORM generate_vat_return('2026-03-01', '2026-03-31');
    EXCEPTION WHEN OTHERS THEN refused := true; END;
    SELECT box1_output_vat, status INTO v FROM vat_returns WHERE id = (g->>'id')::uuid;
    PERFORM _rec('T09', 'déclaration déposée : « Générer » est refusé et les chiffres déposés (200) ne bougent pas',
      refused AND v.box1_output_vat = 200 AND v.status = 'submitted',
      format('refus=%s box1=%s statut=%s', refused, v.box1_output_vat, v.status));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T09', 'déclaration déposée : « Générer » est refusé et les chiffres déposés (200) ne bougent pas', false, SQLERRM); END;
END $$;

SELECT _audit_assert('245');
