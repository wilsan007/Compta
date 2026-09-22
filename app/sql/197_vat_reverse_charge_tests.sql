-- ============================================================
-- 197_vat_reverse_charge_tests.sql — TVA autoliquidée distincte de la TVA ordinaire
--
-- Défaut repéré le 21/09/2026 (vague V3, § 6 du plan correctif) : dans
-- vat_account_mapping, FR20 et AUTOLIQ imputaient les mêmes comptes (445711 /
-- 445661), que le plan semé intitulait « TVA collectée AUTOLIQ » / « TVA
-- déductible AUTOLIQ ». Une déclaration bâtie sur les soldes de comptes ne
-- pouvait pas séparer la TVA à 20 % de l'autoliquidation.
--
-- Autoliquidation (art. 283 CGI) et acquisitions intracommunautaires : le
-- fournisseur facture hors taxe ; l'acheteur déclare lui-même la TVA due et la
-- déduit. Écriture attendue : D 6 HT, D TVA déductible autoliquidée,
-- C TVA due autoliquidée, C 401 HT. Le vendeur, lui, ne facture pas de TVA.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '197', false);
DELETE FROM _audit_results WHERE file = '197';

-- Compte du paramétrage global pour un code et un sens
CREATE OR REPLACE FUNCTION _vat_acc(p_code text, p_dir text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT account_code FROM vat_account_mapping
  WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND vat_code = p_code AND direction = p_dir
$$;

-- Facture fournisseur approuvée : lignes [{"q":, "p":, "r":, "c":}], en-tête posé comme l'écran
CREATE OR REPLACE FUNCTION _vat_purchase(p_t uuid, p_s uuid, p_date date, p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FOURN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, pi, 'Achat', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2), round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  RETURN pi;
END $$;

-- Facture de vente validée
CREATE OR REPLACE FUNCTION _vat_invoice(p_t uuid, p_c uuid, p_date date, p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, 'SAISIE-' || left(uuid_generate_v4()::text, 8), p_c, 'Client', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, inv, 'Ligne', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2), round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

CREATE OR REPLACE FUNCTION _vat_parties(p_t uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO customers (tenant_id, name) VALUES (p_t, 'Client V');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (p_t, 'Fournisseur FR', 'F0001'), (p_t, 'Sous-traitant BTP', 'F0002');
$$;

-- Mois de mars : vente 1 000 HT à 20 %, achat 500 HT à 20 %, achat autoliquidé 300 HT (TVA 60)
CREATE OR REPLACE FUNCTION _vat_month(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c uuid; s uuid; s2 uuid;
BEGIN
  SELECT id INTO c FROM customers WHERE tenant_id = p_t LIMIT 1;
  SELECT id INTO s FROM suppliers WHERE tenant_id = p_t AND name = 'Fournisseur FR';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = p_t AND name = 'Sous-traitant BTP';
  PERFORM _vat_invoice(p_t, c, '2026-03-05', '[{"q":1,"p":1000,"r":20}]');
  PERFORM _vat_purchase(p_t, s, '2026-03-10', '[{"q":1,"p":500,"r":20}]');
  PERFORM _vat_purchase(p_t, s2, '2026-03-12', '[{"q":1,"p":300,"r":20,"c":"AUTOLIQ"}]');
END $$;

-- V01 — paramétrage : un code autoliquidé (AUTOLIQ, UE) n'a aucun compte en commun
-- avec un autre code, dans un sens comme dans l'autre, et possède ses deux comptes
DO $$
DECLARE shared text; missing text;
BEGIN
  SELECT string_agg(DISTINCT a.direction || ' ' || a.account_code || ' : ' || a.vat_code || '/' || b.vat_code, ', ')
    INTO shared
  FROM vat_account_mapping a
  JOIN vat_account_mapping b ON b.tenant_id = a.tenant_id AND b.direction = a.direction
                            AND b.account_code = a.account_code AND b.vat_code > a.vat_code
  WHERE a.tenant_id = '00000000-0000-0000-0000-000000000000'
    AND (a.vat_code IN ('AUTOLIQ', 'UE') OR b.vat_code IN ('AUTOLIQ', 'UE'));
  SELECT string_agg(c.code || ' ' || d.dir, ', ') INTO missing
  FROM (VALUES ('AUTOLIQ'), ('UE')) c(code), (VALUES ('collected'), ('deductible')) d(dir)
  WHERE _vat_acc(c.code, d.dir) IS NULL;
  PERFORM _rec('V01', 'AUTOLIQ et UE : comptes propres (aucun partagé avec FR20 ni entre eux), collectée et déductible',
    shared IS NULL AND missing IS NULL,
    format('partagés : %s ; absents : %s', COALESCE(shared, 'aucun'), COALESCE(missing, 'aucun')));
END $$;

-- V02 — plan semé : libellés conformes à la nature de chaque compte
DO $$
DECLARE t uuid := _mk_tenant('V02'); r record;
BEGIN
  SELECT (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('FR20', 'collected')) fr20_c,
         (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('FR20', 'deductible')) fr20_d,
         (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('AUTOLIQ', 'collected')) al_c,
         (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('AUTOLIQ', 'deductible')) al_d,
         (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('UE', 'collected')) ue_c,
         (SELECT name FROM chart_accounts WHERE tenant_id = t AND code = _vat_acc('UE', 'deductible')) ue_d
    INTO r;
  PERFORM _rec('V02', 'plan semé : FR20 intitulé « 20 % » sans AUTOLIQ ; comptes autoliquidés et intracommunautaires intitulés comme tels',
    r.fr20_c ILIKE '%20 %%' AND r.fr20_c NOT ILIKE '%autoliq%' AND r.fr20_c ILIKE '%collect%'
      AND r.fr20_d ILIKE '%20 %%' AND r.fr20_d NOT ILIKE '%autoliq%' AND r.fr20_d ILIKE '%déductible%'
      AND r.al_c ILIKE '%autoliquid%' AND r.al_d ILIKE '%autoliquid%'
      AND r.ue_c ILIKE '%intracommunautaire%' AND r.ue_d ILIKE '%intracommunautaire%',
    format('FR20 « %s » / « %s » ; AUTOLIQ « %s » / « %s » ; UE « %s » / « %s »',
           r.fr20_c, r.fr20_d, r.al_c, r.al_d, r.ue_c, r.ue_d));
END $$;

-- V03 — achat autoliquidé : le fournisseur est dû du HT ; TVA due et déductible sur les comptes autoliquidés
DO $$
DECLARE t uuid := _mk_tenant('V03'); s uuid; pi uuid; h record; v record;
  al_c text := _vat_acc('AUTOLIQ', 'collected'); al_d text := _vat_acc('AUTOLIQ', 'deductible');
  fr_c text := _vat_acc('FR20', 'collected');  fr_d text := _vat_acc('FR20', 'deductible');
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Sous-traitant BTP', 'F0002') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _vat_purchase(t, s, '2026-03-12', '[{"q":1,"p":300,"r":20,"c":"AUTOLIQ"}]');
    SELECT subtotal, vat_total, total, transferred_entry_id INTO h FROM purchase_invoices WHERE id = pi;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^6') d6,
           sum(debit - credit) FILTER (WHERE account_code = al_d) d_al,
           sum(credit - debit) FILTER (WHERE account_code = al_c) c_al,
           sum(credit - debit) FILTER (WHERE account_code ~ '^401') c401,
           count(*) FILTER (WHERE account_code IN (fr_c, fr_d)) n_fr20,
           sum(debit) d, sum(credit) c
      INTO v FROM journal_lines WHERE journal_id = h.transferred_entry_id;
    PERFORM _rec('V03', 'achat autoliquidé 300 HT : en-tête 300/0/300 ; D 6 300 + D déductible autoliq. 60 = C due autoliq. 60 + C 401 300 ; rien sur les comptes FR20',
      h.subtotal = 300 AND h.vat_total = 0 AND h.total = 300
        AND v.d6 = 300 AND v.d_al = 60 AND v.c_al = 60 AND v.c401 = 300 AND v.n_fr20 = 0 AND v.d = v.c
        AND al_c IS DISTINCT FROM fr_c AND al_d IS DISTINCT FROM fr_d,
      format('en-tête %s/%s/%s ; D6=%s D %s=%s C %s=%s C401=%s lignes FR20=%s D=%s C=%s',
             h.subtotal, h.vat_total, h.total, v.d6, al_d, v.d_al, al_c, v.c_al, v.c401, v.n_fr20, v.d, v.c));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V03', 'achat autoliquidé 300 HT : en-tête 300/0/300 ; D 6 300 + D déductible autoliq. 60 = C due autoliq. 60 + C 401 300 ; rien sur les comptes FR20', false, SQLERRM); END;
END $$;

-- V04 — déclaration de mars (calculate_vat_ca3, soldes des comptes de TVA) :
-- TVA brute 260 dont 60 autoliquidée, déductible 160 dont 60 autoliquidée, à payer 100 ;
-- les comptes FR20 portent 200 et 100, sans l'autoliquidation
DO $$
DECLARE t uuid := _mk_tenant('V04'); r jsonb; s_c numeric; s_d numeric;
  -- lu avant _as_user() : le paramétrage global n'est pas visible d'un utilisateur (RLS)
  fr_c text := _vat_acc('FR20', 'collected'); fr_d text := _vat_acc('FR20', 'deductible');
BEGIN
  PERFORM _vat_parties(t);
  PERFORM _as_user();
  BEGIN
    PERFORM _vat_month(t);
    r := calculate_vat_ca3('2026-03-01', '2026-03-31');
    SELECT COALESCE(sum(credit - debit), 0) INTO s_c FROM journal_lines WHERE tenant_id = t AND account_code = fr_c;
    SELECT COALESCE(sum(debit - credit), 0) INTO s_d FROM journal_lines WHERE tenant_id = t AND account_code = fr_d;
    PERFORM _rec('V04', 'CA3 de mars : brute 260 (dont autoliq. 60), déductible 160 (dont 60), à payer 100 ; soldes FR20 200 / 100',
      (r->>'vat_collected')::numeric = 260 AND (r->>'vat_deductible')::numeric = 160 AND (r->>'vat_to_pay')::numeric = 100
        AND (r->>'reverse_charge_due')::numeric = 60 AND (r->>'reverse_charge_deductible')::numeric = 60
        AND s_c = 200 AND s_d = 100,
      format('CA3 %s ; soldes FR20 collectée=%s déductible=%s', r, s_c, s_d));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V04', 'CA3 de mars : brute 260 (dont autoliq. 60), déductible 160 (dont 60), à payer 100 ; soldes FR20 200 / 100', false, SQLERRM); END;
END $$;

-- V05 — synthèse par code (écran « TVA » : get_vat_summary_by_code) : chaque code dans
-- son sens, aucun « unknown », pas de double compte quand la société surcharge un code
DO $$
DECLARE t uuid := _mk_tenant('V05'); fy uuid; got text;
BEGIN
  PERFORM _vat_parties(t);
  -- surcharge société du code FR20 collecté (même compte) : ne doit pas doubler les montants
  INSERT INTO vat_account_mapping (tenant_id, vat_code, rate, direction, account_code, ca3_box)
  SELECT t, vat_code, rate, direction, account_code, ca3_box FROM vat_account_mapping
  WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND vat_code = 'FR20' AND direction = 'collected';
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t;
  PERFORM _as_user();
  BEGIN
    PERFORM _vat_month(t);
    SELECT string_agg(vat_code || ' ' || direction || ' ' || amt, ', ' ORDER BY vat_code, direction) INTO got
    FROM (SELECT vat_code, direction, sum(vat_amount)::numeric(18,2) amt
          FROM get_vat_summary_by_code(fy, '2026-03-01', '2026-03-31') GROUP BY 1, 2) x;
    PERFORM _rec('V05', 'synthèse par code : AUTOLIQ collectée 60 et déductible 60, FR20 collectée 200 et déductible 100',
      got = 'AUTOLIQ collected 60.00, AUTOLIQ deductible 60.00, FR20 collected 200.00, FR20 deductible 100.00',
      COALESCE(got, 'vide'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V05', 'synthèse par code : AUTOLIQ collectée 60 et déductible 60, FR20 collectée 200 et déductible 100', false, SQLERRM); END;
END $$;

-- V06 — avoir fournisseur autoliquidé : contre-passation symétrique, facture soldée
DO $$
DECLARE t uuid := _mk_tenant('V06'); s uuid; pi uuid; cn uuid; h record; v record; due numeric;
  al_c text := _vat_acc('AUTOLIQ', 'collected'); al_d text := _vat_acc('AUTOLIQ', 'deductible');
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Sous-traitant BTP', 'F0002') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _vat_purchase(t, s, '2026-03-12', '[{"q":1,"p":300,"r":20,"c":"AUTOLIQ"}]');
    INSERT INTO purchase_credit_notes (tenant_id, number, supplier_id, supplier_name, date, status, subtotal, vat_total, total, purchase_invoice_id, reason)
    VALUES (t, 'AVF-SAISIE', s, 'Sous-traitant BTP', '2026-03-20', 'draft', 0, 0, 0, pi, 'Annulation') RETURNING id INTO cn;
    INSERT INTO purchase_credit_lines (tenant_id, purchase_credit_id, description, quantity, unit_price, vat_rate, vat_code)
    VALUES (t, cn, 'Annulation', 1, 300, 20, 'AUTOLIQ');
    UPDATE purchase_credit_notes SET status = 'applied' WHERE id = cn;
    EXECUTE 'SELECT subtotal, vat_total, total, transferred_entry_id FROM purchase_credit_notes WHERE id = $1' INTO h USING cn;
    SELECT sum(debit - credit) FILTER (WHERE account_code ~ '^401') d401,
           sum(credit - debit) FILTER (WHERE account_code ~ '^6') c6,
           sum(credit - debit) FILTER (WHERE account_code = al_d) c_al,
           sum(debit - credit) FILTER (WHERE account_code = al_c) d_al,
           sum(debit) d, sum(credit) c
      INTO v FROM journal_lines WHERE journal_id = h.transferred_entry_id;
    SELECT amount_due INTO due FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('V06', 'avoir autoliquidé 300 HT : en-tête 300/0/300 ; D 401 300 + D due autoliq. 60 = C 6 300 + C déductible autoliq. 60 ; facture soldée',
      h.subtotal = 300 AND h.vat_total = 0 AND h.total = 300
        AND v.d401 = 300 AND v.c6 = 300 AND v.c_al = 60 AND v.d_al = 60 AND v.d = v.c AND due = 0,
      format('en-tête %s/%s/%s ; D401=%s C6=%s C %s=%s D %s=%s D=%s C=%s ; reste dû=%s',
             h.subtotal, h.vat_total, h.total, v.d401, v.c6, al_d, v.c_al, al_c, v.d_al, v.d, v.c, due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V06', 'avoir autoliquidé 300 HT : en-tête 300/0/300 ; D 401 300 + D due autoliq. 60 = C 6 300 + C déductible autoliq. 60 ; facture soldée', false, SQLERRM); END;
END $$;

-- V07 — vente en autoliquidation : le vendeur ne facture pas de TVA et n'en déclare pas
DO $$
DECLARE t uuid := _mk_tenant('V07'); c uuid; inv uuid; h record; v record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Entreprise générale') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _vat_invoice(t, c, '2026-03-05', '[{"q":1,"p":1000,"r":20,"c":"AUTOLIQ"}]');
    SELECT subtotal, vat_total, total, transferred_entry_id INTO h FROM invoices WHERE id = inv;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^411') d411, sum(credit) FILTER (WHERE account_code ~ '^70') c70,
           COALESCE(sum(credit - debit) FILTER (WHERE account_code ~ '^445'), 0) c445
      INTO v FROM journal_lines WHERE journal_id = h.transferred_entry_id;
    PERFORM _rec('V07', 'vente autoliquidée 1 000 HT : en-tête 1 000/0/1 000 ; D 411 1 000 = C 70 1 000, aucune TVA',
      h.subtotal = 1000 AND h.vat_total = 0 AND h.total = 1000 AND v.d411 = 1000 AND v.c70 = 1000 AND v.c445 = 0,
      format('en-tête %s/%s/%s ; D411=%s C70=%s C445=%s', h.subtotal, h.vat_total, h.total, v.d411, v.c70, v.c445));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('V07', 'vente autoliquidée 1 000 HT : en-tête 1 000/0/1 000 ; D 411 1 000 = C 70 1 000, aucune TVA', false, SQLERRM); END;
END $$;

SELECT _audit_assert('197');
