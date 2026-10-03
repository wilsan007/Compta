-- ============================================================
-- 436_chain_banc_six_maillons_tests.sql — le banc éprouvé sur
--   SIX maillons, et non sur un seul
--
--   T01  STRUCTURE : les six maillons portent un gabarit, et le
--        compte des `%s` y est égal à celui des types — la garde
--        de la 436, rejouée ici en LECTURE ;
--   T02  CAISSE.TICKET : D1 SANS OBJET (c'est une création), D4
--        tenu par le geste dédié, D6 tenu, D7 tenu sur 20 stimuli
--        distincts ;
--   T03  CAISSE.AVOIR : D1 tenu — le rejeu est REFUSÉ, en 42501,
--        et un refus est une tenue aussi valide que le silence ;
--        D4 non joué faute de geste, avec sa raison ; D6, D7 tenus ;
--   T04  PAIE.COMPTABILISEE : D1 tenu, D4 non joué, D6 tenu, D7 tenu ;
--   T05  PAIE.VERSEMENT : D1 tenu, D4 non joué, D6 tenu, D7 tenu ;
--   T06  RELEVE.POINTAGE : D1, D4, D6 et D7 TENUS — le seul des
--        six dont le geste d'annulation est à la fois dédié et de
--        la même signature que l'appel nominal ;
--   T07  RELEVE.DELETTRAGE : D1 tenu, D6 tenu, et D4 NON JOUÉ —
--        le re-pointage a été joué et il a levé, c'est dit ;
--   T08  LE RAPPORT EST DATÉ ET COMPLET : huit verdicts par
--        maillon, sur les SEPT du catalogue ;
--   T09  AUCUN `tenu` SANS MESURE, et D2/D3/D5 jamais tenues.
--
-- Ce que cette suite NE mesure pas : D2 (concurrence), D3 (panne
-- partielle), D5 (réouverture) et D8 (isolation). Elles restent
-- `non_joue` avec leur raison, et T09 vérifie qu'aucune ne soit
-- verte par défaut.
--
-- ⚠️ UNE SOCIÉTÉ PAR ÉPREUVE, ET C'EST MESURÉ. Les épreuves D1,
-- D4 et D6 comptent les liens et les traces DU MAILLON DANS LA
-- SOCIÉTÉ. Un décor qui produit deux documents en laisse un que le
-- geste ne touche pas : l'épreuve conclut alors `rompu` sur son
-- propre décor. Les six maillons ci-dessous ont d'abord été mesurés
-- dans une société partagée, et ce sont ces faux `rompu` que cette
-- suite remplace.
--
-- ⚠️ LE DÉCOR DE VOLUME EST DANS LA MÊME SOCIÉTÉ. Vingt tours de
-- D7 doivent être vingt ACCEPTATIONS du chemin nominal : vingt
-- stimuli dans vingt sociétés, c'est vingt fois le même refus vu
-- d'une autre adresse.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '436', false);
DELETE FROM _audit_results WHERE file = '436';

-- ─────────────────────────────────────────────────────────────
-- Outillage : les trois décors, les deux helpers de service
-- ─────────────────────────────────────────────────────────────

-- Une société, une caisse, un client, et N tickets produits PAR LE
-- MAILLON — le décor doit créer les liens que l'épreuve va compter,
-- donc pas un INSERT direct.
DROP FUNCTION IF EXISTS _l436_caisse(text, int);
CREATE OR REPLACE FUNCTION _l436_caisse(p_nom text, p_n int DEFAULT 1,
  OUT t uuid, OUT wh uuid, OUT prod uuid, OUT sess uuid,
  OUT tks uuid[], OUT cli uuid)
LANGUAGE plpgsql AS $fn$
DECLARE term uuid; tk uuid; i int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  PERFORM ensure_standard_journals(t);
  PERFORM _ledger_fixture(t, ARRAY['530000','511200','531000','707000','445710','445711',
                                   '658000','758000','411000']);
  INSERT INTO warehouses (tenant_id, code, name)
    VALUES (t, 'W-'||p_nom, 'Magasin') RETURNING id INTO wh;
  -- ⚠️ LE CLIENT EST DANS LE DÉCOR, ET C'EST NÉCESSAIRE : mesuré, un avoir
  -- refuse une vente de comptoir sans client (« un avoir crédite une personne »).
  -- Sans lui, D1 de `caisse.avoir` ne tournait pas — et une épreuve qui ne
  -- tourne pas n'est pas une épreuve tenue.
  INSERT INTO customers (tenant_id, name)
    VALUES (t, 'Client '||p_nom) RETURNING id INTO cli;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, vat_rate)
    VALUES (t, 'Article '||p_nom, 'SKU-'||p_nom, 'stock', 10, 5, 20) RETURNING id INTO prod;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type,
                               quantity, unit_cost, reference)
    VALUES (t, prod, wh, 'initial', 500, 5, 'Stock initial');
  INSERT INTO pos_terminals (tenant_id, name, warehouse_id)
    VALUES (t, 'Caisse '||p_nom, wh) RETURNING id INTO term;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caisse@audit.test', 100, 'open') RETURNING id INTO sess;

  FOR i IN 1..p_n LOOP
    SELECT (create_pos_ticket(
      jsonb_build_object('session_id', sess, 'number', 'C-'||i,
                         'payment_method', 'cash', 'customer_id', cli),
      jsonb_build_array(jsonb_build_object('product_id', prod, 'description', 'Article',
                                           'quantity', 1, 'unit_price', 10, 'vat_rate', 20))
    )).id INTO tk;
    tks := tks || tk;
  END LOOP;
END $fn$;

-- Une société, un compte bancaire, et N LOTS DE PAIE — tous dans
-- cette société, pour la raison dite en tête de fichier.
DROP FUNCTION IF EXISTS _l436_paie(text, int, text);
CREATE OR REPLACE FUNCTION _l436_paie(p_nom text, p_n int DEFAULT 1, p_statut text DEFAULT 'approved',
  OUT t uuid, OUT run uuid, OUT runs uuid[], OUT bank uuid, OUT usr uuid)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_date date := DATE '2026-03-31';
  emp uuid; i int;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  usr := auth.uid();
  -- ⚠️ PAS D'EXERCICE POSÉ ICI : `_ledger_fixture` en pose un (le « TEST » de
  -- 2026) et le poser une seconde fois viole la non-chevauchement — mesuré,
  -- l'erreur tuait la suite avant le premier scénario.
  PERFORM _ledger_fixture(t, ARRAY['512100','627000','768000','401000']);
  INSERT INTO employees (tenant_id, name, employee_number, status, hire_date)
    VALUES (t, 'Salarié '||p_nom, 'EMP-'||p_nom, 'active', DATE '2024-01-01') RETURNING id INTO emp;

  FOR i IN 1..p_n LOOP
    INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                          gross_total, tax_total, net_total, employee_count)
      VALUES (t, 'PR-'||p_nom||'-'||i, v_date - INTERVAL '1 month', v_date, v_date, p_statut,
              3000, 300, 2400, 1) RETURNING id INTO run;
    runs := runs || run;
    -- Le statut du BULLETIN a son propre vocabulaire : mesuré sur la base neuve,
    -- `pay_slips_status_check` n'admet que draft/approved/paid/cancelled — PAS
    -- 'calculated'. On écrit ce qu'un bulletin calculé et non validé est.
    INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id,
      period_start, period_end, gross_salary, total_gross, social_security_employee,
      income_tax, other_deductions, total_deductions, net_salary, employer_contributions,
      status, calc_inputs)
      VALUES (t, 'PS-'||p_nom||'-'||i, run, emp, v_date - INTERVAL '1 month', v_date,
              3000, 3000, 300, 300, 0, 600, 2400, 500, 'draft',
              jsonb_build_object('csgDeductible', 0, 'csgNonDeductible', 0, 'crds', 0,
                                 'advanceDeduction', 0, 'expenseReimbursement', 0,
                                 'mealVouchers', 0, 'transportAllowance', 0));
  END LOOP;

  -- Vingt comptabilisations écrivent vingt écritures : le compteur banque part
  -- à 5000, sinon `uniq_journal_entry_number_tenant` fait disparaître la moitié
  -- des tours du rapport — un test qu'on n'a pas pu faire n'est pas un test passé.
  UPDATE journals SET next_number = 5000 WHERE tenant_id = t AND code = 'BQ';
  INSERT INTO bank_accounts (tenant_id, name, account_number, sort_code, balance,
                             currency, account_code, journal_code, type)
    VALUES (t, 'Banque '||p_nom, '00000999', '123', 0, 'EUR', '512100', 'BQ', 'chequing')
    RETURNING id INTO bank;
END $fn$;

-- Une société, une banque, et N LIGNES DE RELEVÉ, chacune avec son
-- écriture de pointage — le décor du maillon `releve.pointage`.
DROP FUNCTION IF EXISTS _l436_releve(text, int);
CREATE OR REPLACE FUNCTION _l436_releve(p_nom text, p_n int DEFAULT 1,
  OUT t uuid, OUT ba uuid, OUT txs uuid[], OUT jls uuid[], OUT usr uuid)
LANGUAGE plpgsql AS $fn$
DECLARE v_date date := DATE '2026-03-15'; i int; one uuid; je uuid; jl uuid;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  usr := auth.uid();
  PERFORM _ledger_fixture(t, ARRAY['512100','627000','768000','411000','401000']);
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (t, 'BQ', 'Banque', 'bank', 'active', 5000) ON CONFLICT DO NOTHING;
  UPDATE journals SET next_number = 5000 WHERE tenant_id = t AND code = 'BQ';
  INSERT INTO bank_accounts (tenant_id, name, account_number, sort_code, balance,
                             currency, account_code, journal_code, type)
    VALUES (t, 'Banque '||p_nom, '00000888', '123', 0, 'EUR', '512100', 'BQ', 'chequing')
    RETURNING id INTO ba;

  FOR i IN 1..p_n LOOP
    INSERT INTO bank_transactions (tenant_id, bank_account_id, date, description,
                                   amount, type, kind, matched, reconciled)
      VALUES (t, ba, v_date, 'Ligne '||p_nom||' n°'||i, 10.00 * i, 'debit', 'statement', false, false)
      RETURNING id INTO one;
    txs := txs || one;
    je := _entry(t, 'ECH-'||p_nom||'-'||i, v_date - 1,
            jsonb_build_array(jsonb_build_object('a','627000','d',10.00*i,'c',0),
                              jsonb_build_object('a','512100','d',0,'c',10.00*i)), true, 'BQ');
    SELECT id INTO jl FROM journal_lines
     WHERE journal_id = je AND account_code = '512100' LIMIT 1;
    jls := jls || jl;
  END LOOP;
END $fn$;

-- Poser les VALEURS d'un maillon pour une société de test — le
-- gabarit, lui, est écrit par la 436 et n'est jamais touché ici.
DROP FUNCTION IF EXISTS _l436_poser(text, jsonb, jsonb, jsonb);
CREATE OR REPLACE FUNCTION _l436_poser(p_code text, p_vals jsonb, p_annul jsonb DEFAULT NULL,
                                       p_series jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  UPDATE chain_banc_maillons
     SET arg_valeurs       = p_vals,
         arg_valeurs_annul = p_annul,
         arg_series        = COALESCE(p_series, '[]'::jsonb)
   WHERE code = p_code;
END $fn$;

-- L'en-tête d'un ticket, et ses LIGNES : les deux arguments de
-- contenu que le gabarit de `caisse.ticket` rend en littéraux.
DROP FUNCTION IF EXISTS _l436_ticket(uuid, uuid, text);
CREATE OR REPLACE FUNCTION _l436_ticket(p_sess uuid, p_prod uuid, p_num text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  SELECT jsonb_build_object(
           'session_id', p_sess, 'number', p_num, 'payment_method', 'cash')
$fn$;

DROP FUNCTION IF EXISTS _l436_lignes(uuid);
CREATE OR REPLACE FUNCTION _l436_lignes(p_prod uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  SELECT jsonb_build_array(jsonb_build_object(
           'product_id', p_prod, 'description', 'Article',
           'quantity', 1, 'unit_price', 10, 'vat_rate', 20))
$fn$;


-- ─────────────────────────────────────────────────────────────
-- T01 — STRUCTURE : les SIX maillons portent un gabarit cohérent
--
-- Ce n'est pas une formalité : c'est la condition qui fait que le
-- rapport ne contient pas de `non_joue` pour une raison triviale. La
-- garde est rejouée ici EN LECTURE — le compte des `%s` contre
-- celui des types — parce qu'une garde qui ne vit que dans la
-- migration disparaît au premier `UPDATE` du catalogue.
-- ─────────────────────────────────────────────────────────────
DO $t01$
DECLARE b record; n_ok int; pb text;
BEGIN
  n_ok := 0;
  pb := '';
  FOR b IN
    SELECT code, appat, arg_types, appat_annul, arg_types_annul
      FROM chain_banc_maillons
     WHERE code IN ('caisse.ticket','caisse.avoir','paie.comptabilisee','paie.versement',
                    'releve.pointage','releve.delettrage')
  LOOP
    IF b.appat IS NULL THEN
      pb := pb || b.code || ' sans gabarit ; ';
      CONTINUE;
    END IF;
    IF (length(b.appat) - length(replace(b.appat, '%s', ''))) / 2
       IS DISTINCT FROM COALESCE(array_length(b.arg_types, 1), 0) THEN
      pb := pb || b.code || ' : %s et types désaccordés ; ';
      CONTINUE;
    END IF;
    -- Un geste, s'il existe, se compare à SES types, ou à défaut à ceux
    -- du nominal : c'est le chemin qu'emprunte la suite 434, qui n'en
    -- décrit pas.
    IF b.appat_annul IS NOT NULL
       AND (length(b.appat_annul) - length(replace(b.appat_annul, '%s', ''))) / 2
           IS DISTINCT FROM COALESCE(array_length(b.arg_types_annul, 1),
                                    (length(b.appat) - length(replace(b.appat, '%s', ''))) / 2) THEN
      pb := pb || b.code || ' : geste et types de geste désaccordés ; ';
      CONTINUE;
    END IF;
    n_ok := n_ok + 1;
  END LOOP;

  PERFORM _rec('T01', 'les SIX maillons portent un gabarit, et le compte des %s y égale celui des types',
    n_ok = 6, format('maillons_cohérents=%s/6 %s', n_ok, COALESCE(NULLIF(pb, ''), '')));
END $t01$;

-- ─────────────────────────────────────────────────────────────
-- T02 — CAISSE.TICKET : une création n'a pas de rejeu, mais elle
--        s'annule, revient en arrière, et tient en volume
--
-- ⚠️ D1 EST `non_joue`, ET C'EST LE SEUL VERDICT HONNÈTE. Le
-- maillon rend le CONTENU du ticket ; le rejouer crée un second
-- ticket (mesuré : +1 lien, +1 trace), et son `sequential_number`
-- lui est attribué par un déclencheur. Rendre cela `rompu`
-- publierait un défaut inexistant ; on le déclare donc sans objet,
-- et la raison est dans le rapport.
-- ─────────────────────────────────────────────────────────────
DO $t02$
DECLARE
  v_d1 record; v_d4 record; v_d6 record; v_d7 record;
  va record; vb record; vc record; vd record;
  ser jsonb; tk uuid; n_actif int;
BEGIN
  va := _l436_caisse('T02-D1', 1);
  PERFORM _l436_poser('caisse.ticket', jsonb_build_array(
    _l436_ticket(va.sess, va.prod, 'C-1'), _l436_lignes(va.prod), NULL::jsonb));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'caisse.ticket', 'D1');

  -- D4 : le décor a produit le lien (son premier ticket), le geste dédié l'annule
  vb := _l436_caisse('T02-D4', 1);
  tk  := vb.tks[1];
  PERFORM _l436_poser('caisse.ticket', jsonb_build_array(), jsonb_build_array(tk::text));
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'caisse.ticket', 'D4');
  SELECT count(*) INTO n_actif FROM document_links
   WHERE tenant_id = vb.t AND amont_type = 'pos_tickets'
     AND effet = 'pos.ticket.stock_out' AND etat = 'actif';

  -- D6 : le retour arrière, sur un ticket que le décor n'a pas produit
  vc := _l436_caisse('T02-D6', 1);
  PERFORM _l436_poser('caisse.ticket', jsonb_build_array(
    _l436_ticket(vc.sess, vc.prod, 'X-1'), _l436_lignes(vc.prod), NULL::jsonb));
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'caisse.ticket', 'D6');

  -- D7 : vingt tickets DISTINCTS, dans cette société
  vd := _l436_caisse('T02-D7', 21);
  SELECT jsonb_agg(jsonb_build_array(
           _l436_ticket(vd.sess, vd.prod, 'V-'||g), _l436_lignes(vd.prod), NULL::jsonb))
    INTO ser FROM generate_series(1, 20) g;
  PERFORM _l436_poser('caisse.ticket', jsonb_build_array(
    _l436_ticket(vd.sess, vd.prod, 'V-0'), _l436_lignes(vd.prod), NULL::jsonb),
    NULL::jsonb, ser);
  SELECT * INTO v_d7 FROM chain_banc_epreuve(vd.t, 'caisse.ticket', 'D7');

  PERFORM _rec('T02', 'caisse.ticket : D1 SANS OBJET (création), D4 tenu par le geste dédié, D6 tenu, D7 tenu sur 20 stimuli distincts',
    v_d1.verdict = 'non_joue' AND btrim(COALESCE(v_d1.raison, '')) <> ''
    AND v_d4.verdict = 'tenu' AND n_actif = 0
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0
    AND v_d7.verdict = 'tenu' AND v_d7.mesure IS NOT NULL,
    format('D1=%s (%s) | D4=%s liens_actifs_restants=%s | D6=%s (%s) | D7=%s p95=%s ms',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 60), v_d4.verdict, n_actif,
           v_d6.verdict, COALESCE(v_d6.obtenu, ''), v_d7.verdict, v_d7.mesure));
END $t02$;

-- ─────────────────────────────────────────────────────────────
-- T03 — CAISSE.AVOIR : le rejeu est REFUSÉ, et un refus est une
--        tenue ; l'annulation, elle, n'a pas de geste
--
-- ⚠️ LE REFUS EST EN `42501`. Mesuré : le dépôt écrit ses refus
-- d'affaires en `42501` (« statut refunded — un avoir ne peut… »),
-- en `P0002` (« ligne introuvable ») et en `23503`, autant de codes
-- que le moteur ne connaissait pas. La 434 n'acceptait que
-- `23514`/`23505` : elle rendait donc `rompu` un maillon qui
-- refusait CORRECTEMENT. Une preuve d'instrument fausse fait
-- corriger un maillon qui marche — c'est le défaut le plus cher.
-- ─────────────────────────────────────────────────────────────
DO $t03$
DECLARE
  v_d1 record; v_d4 record; v_d6 record; v_d7 record;
  va record; vb record; vc record; vd record; ser jsonb;
BEGIN
  va := _l436_caisse('T03-D1', 1);
  UPDATE pos_sessions SET status = 'closed', closed_at = now() WHERE id = va.sess;
  PERFORM _l436_poser('caisse.avoir', jsonb_build_array(va.tks[1]::text));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'caisse.avoir', 'D1');

  -- D4 : aucun geste n'est décrit, et l'épreuve le DIT
  vb := _l436_caisse('T03-D4', 1);
  PERFORM _l436_poser('caisse.avoir', jsonb_build_array());
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'caisse.avoir', 'D4');

  vc := _l436_caisse('T03-D6', 1);
  UPDATE pos_sessions SET status = 'closed', closed_at = now() WHERE id = vc.sess;
  PERFORM _l436_poser('caisse.avoir', jsonb_build_array(vc.tks[1]::text));
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'caisse.avoir', 'D6');

  -- D7 : vingt avoirs sur vingt ventes DISTINCTES
  vd := _l436_caisse('T03-D7', 21);
  UPDATE pos_sessions SET status = 'closed', closed_at = now() WHERE id = vd.sess;
  SELECT jsonb_agg(jsonb_build_array(x::text)) INTO ser
    FROM unnest(vd.tks) WITH ORDINALITY u(x, n) WHERE n > 1;
  PERFORM _l436_poser('caisse.avoir', jsonb_build_array(vd.tks[1]::text), NULL::jsonb, ser);
  SELECT * INTO v_d7 FROM chain_banc_epreuve(vd.t, 'caisse.avoir', 'D7');

  PERFORM _rec('T03', 'caisse.avoir : D1 tenu par un REFUS (42501), D4 non joué faute de geste, D6 tenu, D7 tenu sur 20 ventes distinctes',
    v_d1.verdict = 'tenu' AND v_d1.mesure = 0
    AND v_d4.verdict = 'non_joue' AND btrim(COALESCE(v_d4.raison, '')) <> ''
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0
    AND v_d7.verdict = 'tenu' AND v_d7.mesure IS NOT NULL,
    format('D1=%s (%s) | D4=%s | D6=%s | D7=%s p95=%s ms',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 80), v_d4.verdict,
           v_d6.verdict, v_d7.verdict, v_d7.mesure));
END $t03$;

-- ─────────────────────────────────────────────────────────────
-- T04 — PAIE.COMPTABILISEE : le rejeu n'écrit qu'une trace `ignore`
--
-- ⚠️ C'EST LA MESURE QUI A CHANGÉ, ET ELLE AVAIT TORT. La 434
-- comptait TOUTES les traces : le rejeu de `payroll_post_run`
-- n'ajoute ni lien ni ligne écrite, mais il laisse une trace
-- `ignore` — le maillon qui DÉCLARE avoir fait rien. Compter
-- cette déclaration comme une duplication rendait `rompu` un rejeu
-- parfaitement tenu. On ne compte donc que les traces `applique`, et
-- le nombre de non-effets est DIT dans le verdict.
-- ─────────────────────────────────────────────────────────────
DO $t04$
DECLARE
  v_d1 record; v_d4 record; v_d6 record; v_d7 record;
  va record; vb record; vc record; vd record; ser jsonb;
BEGIN
  va := _l436_paie('T04-D1', 1);
  PERFORM _l436_poser('paie.comptabilisee', jsonb_build_array(va.runs[1]::text));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'paie.comptabilisee', 'D1');

  vb := _l436_paie('T04-D4', 1);
  PERFORM _l436_poser('paie.comptabilisee', jsonb_build_array());
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'paie.comptabilisee', 'D4');

  vc := _l436_paie('T04-D6', 1);
  PERFORM _l436_poser('paie.comptabilisee', jsonb_build_array(vc.runs[1]::text));
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'paie.comptabilisee', 'D6');

  -- D7 : vingt lots dans CETTE société
  vd := _l436_paie('T04-D7', 20);
  SELECT jsonb_agg(jsonb_build_array(x::text)) INTO ser FROM unnest(vd.runs) x;
  PERFORM _l436_poser('paie.comptabilisee', jsonb_build_array(vd.runs[1]::text), NULL::jsonb, ser);
  SELECT * INTO v_d7 FROM chain_banc_epreuve(vd.t, 'paie.comptabilisee', 'D7');

  PERFORM _rec('T04', 'paie.comptabilisee : D1 tenu (0 lien, 0 trace applique), D4 non joué, D6 tenu, D7 tenu sur 20 lots distincts',
    v_d1.verdict = 'tenu' AND v_d1.mesure = 0
    AND v_d4.verdict = 'non_joue' AND btrim(COALESCE(v_d4.raison, '')) <> ''
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0
    AND v_d7.verdict = 'tenu' AND v_d7.mesure IS NOT NULL,
    format('D1=%s (%s) | D4=%s | D6=%s | D7=%s p95=%s ms',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 80), v_d4.verdict,
           v_d6.verdict, v_d7.verdict, v_d7.mesure));
END $t04$;



-- ─────────────────────────────────────────────────────────────
-- T05 — PAIE.VERSEMENT : le geste le plus large des six (deux
--        identifiants, une date, une portée), et le seul dont le
--        décor porte un compte bancaire
-- ─────────────────────────────────────────────────────────────
DO $t05$
DECLARE
  v_d1 record; v_d4 record; v_d6 record; v_d7 record;
  va record; vb record; vc record; vd record; ser jsonb;
BEGIN
  va := _l436_paie('T05-D1', 1);
  PERFORM _l436_poser('paie.versement',
    jsonb_build_array(va.runs[1]::text, va.bank::text, DATE '2026-03-31', 'all'));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'paie.versement', 'D1');

  vb := _l436_paie('T05-D4', 1);
  PERFORM _l436_poser('paie.versement', jsonb_build_array());
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'paie.versement', 'D4');

  vc := _l436_paie('T05-D6', 1);
  PERFORM _l436_poser('paie.versement',
    jsonb_build_array(vc.runs[1]::text, vc.bank::text, DATE '2026-03-31', 'all'));
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'paie.versement', 'D6');

  -- D7 : vingt versements réels, dans CETTE société
  vd := _l436_paie('T05-D7', 21);
  SELECT jsonb_agg(jsonb_build_array(x::text, vd.bank::text, '2026-03-31'::text, 'all'))
    INTO ser FROM unnest(vd.runs) WITH ORDINALITY u(x, n) WHERE n > 1;
  PERFORM _l436_poser('paie.versement',
    jsonb_build_array(vd.runs[1]::text, vd.bank::text, DATE '2026-03-31', 'all'), NULL::jsonb, ser);
  SELECT * INTO v_d7 FROM chain_banc_epreuve(vd.t, 'paie.versement', 'D7');

  PERFORM _rec('T05', 'paie.versement : D1 tenu, D4 non joué faute de geste dédié, D6 tenu, D7 tenu sur 20 versements distincts',
    v_d1.verdict = 'tenu' AND v_d1.mesure = 0
    AND v_d4.verdict = 'non_joue' AND btrim(COALESCE(v_d4.raison, '')) <> ''
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0
    AND v_d7.verdict = 'tenu' AND v_d7.mesure IS NOT NULL,
    format('D1=%s (%s) | D4=%s | D6=%s | D7=%s p95=%s ms',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 80), v_d4.verdict,
           v_d6.verdict, v_d7.verdict, v_d7.mesure));
END $t05$;

-- ─────────────────────────────────────────────────────────────
-- T06 — RELEVE.POINTAGE : le seul des six dont D4 est tenu
--
-- Le geste d'annulation est le dé-lettrage du maillon voisin, et il
-- consomme le MÊME premier argument que l'appel nominal (la ligne de
-- relevé) : c'est la signature qui rend l'épreuve possible, et le §2
-- de la 436 le dit.
-- ─────────────────────────────────────────────────────────────
DO $t06$
DECLARE
  v_d1 record; v_d4 record; v_d6 record; v_d7 record;
  va record; vb record; vc record; vd record; ser jsonb;
BEGIN
  va := _l436_releve('T06-D1', 1);
  PERFORM _l436_poser('releve.pointage', jsonb_build_array(va.txs[1]::text, va.jls[1]::text));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'releve.pointage', 'D1');

  -- D4 : le décor POINTE d'abord (le lien actif), le geste le retire
  vb := _l436_releve('T06-D4', 1);
  PERFORM reconcile_bank_statement_line(vb.txs[1], vb.jls[1]);
  PERFORM _l436_poser('releve.pointage', jsonb_build_array(), jsonb_build_array(vb.txs[1]::text));
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'releve.pointage', 'D4');

  vc := _l436_releve('T06-D6', 2);
  PERFORM _l436_poser('releve.pointage',
    jsonb_build_array(vc.txs[1]::text, vc.jls[1]::text), NULL::jsonb, '[]'::jsonb);
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'releve.pointage', 'D6');

  -- D7 : vingt pointages sur vingt lignes et vingt écritures DISTINCTES
  vd := _l436_releve('T06-D7', 20);
  SELECT jsonb_agg(jsonb_build_array(u.t, u.j)) INTO ser
    FROM unnest(vd.txs, vd.jls) AS u(t, j);
  PERFORM _l436_poser('releve.pointage',
    jsonb_build_array(vd.txs[1]::text, vd.jls[1]::text), NULL::jsonb, ser);
  SELECT * INTO v_d7 FROM chain_banc_epreuve(vd.t, 'releve.pointage', 'D7');

  PERFORM _rec('T06', 'releve.pointage : D1, D4, D6 et D7 TENUS — le geste dédié consomme le même argument que l''appel nominal',
    v_d1.verdict = 'tenu' AND v_d1.mesure = 0
    AND v_d4.verdict = 'tenu' AND v_d4.mesure = 0
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0
    AND v_d7.verdict = 'tenu' AND v_d7.mesure IS NOT NULL,
    format('D1=%s (%s) | D4=%s (%s) | D6=%s | D7=%s p95=%s ms',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 70), v_d4.verdict,
           COALESCE(v_d4.obtenu, ''), v_d6.verdict, v_d7.verdict, v_d7.mesure));
END $t06$;


-- ─────────────────────────────────────────────────────────────
-- T07 — RELEVE.DELETTRAGE : un maillon qui ne PRODUIT rien, et
--        une annulation qui n'existe pas
--
-- ⚠️ LE RE-POINTAGE A ÉTÉ JOUÉ ET IL A LEVÉ. C'est le geste que
-- tout le monde proposerait ; mesuré, il répond « ligne déjà
-- pointée ». On ne le décrit donc pas : le banc rend `non_joue`
-- avec cette raison, et la suite le vérifie.
-- ─────────────────────────────────────────────────────────────
DO $t07$
DECLARE v_d1 record; v_d4 record; v_d6 record; va record; vb record; vc record;
BEGIN
  va := _l436_releve('T07-D1', 1);
  PERFORM post_bank_statement_line(va.txs[1], '627000', 'Frais bancaires');
  PERFORM _l436_poser('releve.delettrage', jsonb_build_array(va.txs[1]::text));
  SELECT * INTO v_d1 FROM chain_banc_epreuve(va.t, 'releve.delettrage', 'D1');

  vb := _l436_releve('T07-D4', 1);
  PERFORM post_bank_statement_line(vb.txs[1], '627000', 'Frais bancaires');
  PERFORM _l436_poser('releve.delettrage', jsonb_build_array());
  SELECT * INTO v_d4 FROM chain_banc_epreuve(vb.t, 'releve.delettrage', 'D4');

  vc := _l436_releve('T07-D6', 1);
  PERFORM post_bank_statement_line(vc.txs[1], '627000', 'Frais bancaires');
  PERFORM _l436_poser('releve.delettrage', jsonb_build_array(vc.txs[1]::text), NULL::jsonb, '[]'::jsonb);
  SELECT * INTO v_d6 FROM chain_banc_epreuve(vc.t, 'releve.delettrage', 'D6');

  PERFORM _rec('T07', 'releve.delettrage : D1 tenu, D6 tenu, et D4 NON JOUÉ — le re-pointage a été joué, il refuse la ligne déjà pointée',
    v_d1.verdict = 'tenu' AND v_d1.mesure = 0
    AND v_d4.verdict = 'non_joue' AND btrim(COALESCE(v_d4.raison, '')) <> ''
    AND v_d6.verdict = 'tenu' AND v_d6.mesure = 0,
    format('D1=%s (%s) | D4=%s : %s | D6=%s',
           v_d1.verdict, left(COALESCE(v_d1.obtenu, ''), 70), v_d4.verdict,
           left(COALESCE(v_d4.raison, ''), 80), v_d6.verdict));
END $t07$;


-- ─────────────────────────────────────────────────────────────
-- T08 — LE RAPPORT EST DATÉ ET COMPLET
--
-- `chain_banc_lancer` parcourt le catalogue et JOUE les huit
-- épreuves : le rapport compte alors 7 × 8 verdicts, tous datés.
-- C'est la preuve attendue de la tâche 3.7 (« un chaînage déclaré
-- = 8 verdicts datés »), appliquée au catalogue entier et non à un
-- maillon.
--
-- ⚠️ ON JOUE SUR UNE SEULE SOCIÉTÉ, ET ON NE COMPTE QUE CELLE-LÀ.
-- Les verdicts des autres sociétés restent en base : c'est
-- l'historique, et il ne doit pas être confondu avec le passage.
-- ─────────────────────────────────────────────────────────────
DO $t08$
DECLARE v record; n_maillons int; n_lignes int; n_couples int; n_sans_date int;
BEGIN
  v := _l436_caisse('T08', 1);
  UPDATE pos_sessions SET status = 'closed', closed_at = now() WHERE id = v.sess;
  PERFORM _l436_poser('caisse.avoir', jsonb_build_array(v.tks[1]::text));

  -- la campagne : les SEPT maillons du catalogue, pas seulement les six
  SELECT count(*) INTO n_maillons FROM chain_banc_lancer(v.t);

  SELECT count(*), count(DISTINCT (code, epreuve)), count(*) FILTER (WHERE joue_le IS NULL)
    INTO n_lignes, n_couples, n_sans_date
    FROM chain_banc_resultats WHERE tenant_id = v.t;

  PERFORM _rec('T08', 'la campagne rend 8 verdicts DATÉS par maillon sur les sept du catalogue, sans doublon',
    n_maillons = 7 AND n_lignes = 56 AND n_couples = 56 AND n_sans_date = 0,
    format('maillons=%s lignes=%s couples_(maillon,épreuve)=%s verdicts_sans_date=%s',
           n_maillons, n_lignes, n_couples, n_sans_date));
END $t08$;


-- ─────────────────────────────────────────────────────────────
-- T09 — AUCUN `tenu` SANS MESURE, ET D2/D3/D5 JAMAIS VERTES
--
-- Le contrôle que la 434 pose pour UN maillon, posé ici pour la
-- campagne entière. Deux choses qui ne se déduisent pas du décompte :
--
--   • un verdict `tenu` porte TOUJOURS une mesure. Un `tenu` sans
--     nombre serait un verdict d'opinion — ce qu'une chaîne de
--     rapport finit par afficher comme un fait ;
--   • D2 (concurrence), D3 (panne partielle) et D5 (réouverture)
--     restent `non_joue` AVEC leur raison, pour tout maillon.
--
-- ⚠️ LA COLONNE `nature` EST VÉRIFIÉE ICI : c'est elle qui empêche
-- D1 de publier un `rompu` sur une création.
-- ─────────────────────────────────────────────────────────────
DO $t09$
DECLARE
  v record; n_sans_mesure int; n_d235_tenu int; n_nj_sans_raison int;
  n_creation int; n_colonnes int;
BEGIN
  v := _l436_releve('T09', 1);
  PERFORM _l436_poser('releve.comptabilise', jsonb_build_array(v.txs[1]::text));
  PERFORM chain_banc_lancer(v.t);

  SELECT count(*) INTO n_sans_mesure
    FROM chain_banc_resultats
   WHERE tenant_id = v.t AND verdict = 'tenu' AND mesure IS NULL;

  SELECT count(*) INTO n_d235_tenu
    FROM chain_banc_resultats
   WHERE tenant_id = v.t AND epreuve IN ('D2','D3','D5') AND verdict = 'tenu';

  SELECT count(*) INTO n_nj_sans_raison
    FROM chain_banc_resultats
   WHERE tenant_id = v.t AND verdict = 'non_joue' AND btrim(COALESCE(raison, '')) = '';

  SELECT count(*) INTO n_creation
    FROM chain_banc_maillons WHERE nature = 'creation';

  SELECT count(*) INTO n_colonnes
    FROM information_schema.columns
   WHERE table_name = 'chain_banc_maillons'
     AND column_name IN ('arg_valeurs_annul','arg_types_annul',
                         'arg_valeurs_reouverture','arg_types_reouverture','nature');

  PERFORM _rec('T09', 'aucun `tenu` sans mesure, D2/D3/D5 jamais tenues, et toute épreuve non jouée porte sa raison',
    n_sans_mesure = 0 AND n_d235_tenu = 0 AND n_nj_sans_raison = 0
    AND n_creation = 1 AND n_colonnes = 5,
    format('tenus_sans_mesure=%s D2_D3_D5_tenus=%s non_joués_sans_raison=%s maillons_création=%s colonnes=%s',
           n_sans_mesure, n_d235_tenu, n_nj_sans_raison, n_creation, n_colonnes));
END $t09$;

-- ─────────────────────────────────────────────────────────────
-- Verdict de la suite
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('436');
