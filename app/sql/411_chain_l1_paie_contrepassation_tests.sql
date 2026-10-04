-- ============================================================
-- 321_chain_l1_paie_contrepassation_tests.sql — L1 (tranche 6) : ce que le
--   traçage de la CONTRAPASSATION DE PAIE garantit
--
-- Source : doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md §2 — la
-- ligne 22 (`payroll_reverse_posted_run`, verdict « candidat direct »), laissée
-- de côté par la tranche 5. Le maillon (248) est un déclencheur APRÈS dont
-- l'aval est identifiable par la clé qu'il écrit lui-même
-- (`journal_entries.reference = 'PAYROLL-REV-' || <numéro du lot>`).
--
--   T01  lot comptabilisé puis annulé → un lien pay_runs → journal_entries
--        (`reversed_by`), un événement, une trace `applique` — et la
--        contrepassation du maillon existe bien ;
--   T02  lot annulé SANS avoir été comptabilisé → aucun lien, AUCUNE trace : le
--        cas ordinaire ne se trace pas ;
--   T03  l'anomalie SE TRACE : une écriture de paie pointée « posted » sans
--        contrepassation → trace `sans_effet` (valeur de la 315), zéro ligne ;
--   T04  annuler deux fois ne lie ni ne trace qu'une fois (rejeu = `ignore`) ;
--   T05  structure : un contrat actif, un compagnon SECURITY DEFINER non exposé,
--        qui s'exécute APRÈS son maillon métier ;
--   T06  la société voisine ne voit ni lien, ni événement, ni trace (RLS).
--
-- Ce fichier s'exécute comme les autres suites d'audit : contexte de société
-- posé, puis rôle `authenticated` — un utilisateur réel, sous RLS.
-- ============================================================
\ir ci/audit_helpers.sql
-- ⚠️ Ce fichier s'annonçait `321` (`audit.file` et `_audit_assert`), alors
-- qu'il ne rejoue AUCUN scénario de la 321 : ses fixtures sont R6A…R6F et ne
-- comportent ni titre-restaurant ni indemnité de transport. Ses verdicts
-- écrasaient donc ceux de la vraie 321 sous la même clé — et c'est ainsi que le
-- 02/10/2026 on a cru, sur la foi de « 411 verte », que les défauts `321 T02`,
-- `T03` et `T05` étaient corrigés, et on les a retirés du registre. Ils ne
-- l'étaient pas : la 321 est rouge sur ces trois lignes. Chaque suite doit
-- réponse de SON fichier.
SELECT set_config('audit.file', '411', false);
DELETE FROM _audit_results WHERE file = '321';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Un lot de paie approuvé avec un bulletin type (brut 3 000, net 2 340,
-- patronales 1 260), repris de la suite 247 : c'est le décor que
-- `post_payroll_journal` exige pour comptabiliser.
CREATE OR REPLACE FUNCTION _l321_lot(p_t uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid;
BEGIN
  -- `uuid_generate_v4()` n'est pas exécutable par le rôle `authenticated` (mesuré :
  -- `permission denied for function uuid_generate_v4` au premier passage) — les
  -- identifiants dérivés du numéro de lot, unique par scénario, suffisent.
  INSERT INTO employees (tenant_id, name, email, status, base_salary, salary, hire_date, employee_number)
  VALUES (p_t, 'Salarie ' || p_num, lower(p_num) || '@audit.test', 'active',
          3000, 3000, '2025-01-01', 'M-' || p_num)
  RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_num, '2026-03-01', '2026-03-31', '2026-03-31', 'draft', 3000, 660, 2340, 1)
  RETURNING id INTO r;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
    gross_salary, total_gross, social_security_employee, income_tax, other_deductions, total_deductions,
    net_salary, employer_contributions, status, calc_inputs)
  VALUES (p_t, p_num || '-BS', r, e, '2026-03-01', '2026-03-31',
    3000, 3000, 400, 60, 200, 660, 2340, 1260, 'draft',
    '{"csgDeductible": 120, "csgNonDeductible": 60, "crds": 20, "advanceDeduction": 0, "otherDeductions": 0}');
  UPDATE pay_runs SET status = 'approved' WHERE id = r;
  RETURN r;
END $$;

-- Les liens d'un document, leur effet, leur type et l'aval.
CREATE OR REPLACE FUNCTION _l321_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, aval_type text, aval_id uuid, link_type text, payload jsonb)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.aval_type, dl.aval_id, dl.link_type, dl.payload
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet
$$;

CREATE OR REPLACE FUNCTION _l321_evt(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;

CREATE OR REPLACE FUNCTION _l321_traces(p_t uuid, p_effet text)
RETURNS TABLE(resultat text, duree_ms integer, lignes_ecrites integer, message text)
LANGUAGE sql AS $$
  SELECT ct.resultat, ct.duree_ms, ct.lignes_ecrites, ct.message FROM chain_traces ct
  WHERE ct.tenant_id = p_t AND ct.effet = p_effet ORDER BY ct.id
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — Lot comptabilisé puis annulé : le lien, l'événement, la trace
--   Le maillon (248) porte une contrepassation au journal PAIE, référencée
--   `PAYROLL-REV-<numéro du lot>` ; le compagnon la LIE au lot.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('R6A'); r uuid; res jsonb; v record; v_rev record;
        n_liens int; n_evt int; n_app int; n_rev int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _l321_lot(t, 'PAIE-R6A');
    res := post_payroll_journal(r);
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT * INTO v_rev FROM journal_entries WHERE tenant_id = t AND reference = 'PAYROLL-REV-PAIE-R6A';
    SELECT * INTO v FROM _l321_liens(t, 'pay_runs', r) WHERE effet = 'payroll.run.reversed' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l321_liens(t, 'pay_runs', r) WHERE effet = 'payroll.run.reversed';
    n_evt := _l321_evt(t, 'pay_runs.reversed', r);
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app FROM _l321_traces(t, 'payroll.run.reversed');
    SELECT count(*) INTO n_rev FROM journal_entries WHERE tenant_id = t AND reference = 'PAYROLL-REV-PAIE-R6A';

    PERFORM _rec('T01', 'lot comptabilisé puis annulé → UN lien pay_runs → journal_entries (`reversed_by`) vers la contrepassation, un événement `pay_runs.reversed`, UNE trace `applique`',
      n_liens = 1 AND v.aval_type = 'journal_entries' AND v.link_type = 'reversed_by'
        AND v.aval_id = v_rev.id
        AND (v.payload->>'reference') = 'PAYROLL-REV-PAIE-R6A'
        AND n_evt = 1 AND n_app = 1 AND n_rev = 1,
      format('liens=%s aval=%s type=%s id=contrepassation? %s payload=%s événements=%s applique=%s contrepassations=%s',
             n_liens, v.aval_type, v.link_type, v.aval_id = v_rev.id, v.payload, n_evt, n_app, n_rev));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'lot comptabilisé puis annulé → UN lien pay_runs → journal_entries (`reversed_by`) vers la contrepassation, un événement `pay_runs.reversed`, UNE trace `applique`', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Lot annulé SANS avoir été comptabilisé : le cas ordinaire
--   Aucune contrepassation n'est possible (le pont n'existe pas) : le compagnon
--   ne lie pas et NE TRACE PAS — `sans_effet` est réservé à l'anomalie (T03).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('R6B'); r uuid; n_liens int; n_traces int; n_rev int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _l321_lot(t, 'PAIE-R6B');
    -- jamais comptabilisé (aucun appel à post_payroll_journal)
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT count(*) INTO n_liens FROM _l321_liens(t, 'pay_runs', r) WHERE effet = 'payroll.run.reversed';
    SELECT count(*) INTO n_traces FROM _l321_traces(t, 'payroll.run.reversed');
    SELECT count(*) INTO n_rev FROM journal_entries WHERE tenant_id = t AND reference LIKE 'PAYROLL-REV-%';

    PERFORM _rec('T02', 'lot annulé sans avoir été comptabilisé : aucun lien et AUCUNE trace — le cas ordinaire ne se trace pas (`sans_effet` est réservé à l''anomalie)',
      n_liens = 0 AND n_traces = 0 AND n_rev = 0,
      format('liens=%s (0 attendu), traces=%s (0 attendue), contrepassations=%s (0 attendue)', n_liens, n_traces, n_rev));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'lot annulé sans avoir été comptabilisé : aucun lien et AUCUNE trace — le cas ordinaire ne se trace pas (`sans_effet` est réservé à l''anomalie)', false, SQLERRM);
  END;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T03 — L'anomalie, elle, SE TRACE : `sans_effet` (valeur de la 315)
--   Un lot dont l'écriture de paie est POINTÉE (« posted ») mais dont le pont
--   n'est PAS « transferred » : la garde du maillon 248 exige « transferred »,
--   il ne contrepasse donc pas — et pourtant l'écriture existe. C'est l'effet
--   attendu et absent que le vocabulaire ne savait pas dire avant la 315.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('R6C'); r uuid; v record; n_liens int; n_rev int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _l321_lot(t, 'PAIE-R6C');
    PERFORM post_payroll_journal(r);
    -- Le pont passe à « cancelled » SANS contrepassation (l'annulation ne le
    -- contrepasse pas), alors que l'écriture de paie reste « posted ».
    UPDATE payroll_accounting_entries SET status = 'cancelled' WHERE tenant_id = t AND pay_run_id = r;
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT * INTO v FROM _l321_traces(t, 'payroll.run.reversed') LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l321_liens(t, 'pay_runs', r) WHERE effet = 'payroll.run.reversed';
    SELECT count(*) INTO n_rev FROM journal_entries WHERE tenant_id = t AND reference = 'PAYROLL-REV-PAIE-R6C';

    PERFORM _rec('T03', 'écriture de paie « posted » et pont non transféré : l''annulation ne contrepasse pas, le compagnon trace `sans_effet` (zéro ligne) et NE POSE AUCUN lien — l''anomalie est visible au lieu d''être muette',
      n_liens = 0 AND n_rev = 0 AND v.resultat = 'sans_effet' AND v.lignes_ecrites = 0
        AND v.message LIKE '%aucune contrepassation%',
      format('liens=%s contrepassations=%s trace=%s (%s ligne(s)) — %s',
             n_liens, n_rev, v.resultat, v.lignes_ecrites, left(COALESCE(v.message, ''), 90)));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'écriture de paie « posted » et pont non transféré : l''annulation ne contrepasse pas, le compagnon trace `sans_effet` (zéro ligne) et NE POSE AUCUN lien — l''anomalie est visible au lieu d''être muette', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — Annuler DEUX fois : un seul lien, une seule trace `applique`
--   Le lot repasse par « approved » puis « cancelled » : le maillon ne
--   contrepasse pas deux fois (sa garde d'idempotence) et le compagnon ne relie
--   pas deux fois (chain_avant détecte le rejeu et trace `ignore`).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('R6D'); r uuid; n_liens int; n_app int; n_ign int; n_rev int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _l321_lot(t, 'PAIE-R6D');
    PERFORM post_payroll_journal(r);
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;
    UPDATE pay_runs SET status = 'approved' WHERE id = r;
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT count(*) INTO n_liens FROM _l321_liens(t, 'pay_runs', r) WHERE effet = 'payroll.run.reversed';
    SELECT count(*) FILTER (WHERE resultat = 'applique') INTO n_app FROM _l321_traces(t, 'payroll.run.reversed');
    SELECT count(*) FILTER (WHERE resultat = 'ignore') INTO n_ign FROM _l321_traces(t, 'payroll.run.reversed');
    SELECT count(*) INTO n_rev FROM journal_entries WHERE tenant_id = t AND reference = 'PAYROLL-REV-PAIE-R6D';

    PERFORM _rec('T04', 'annuler deux fois : UN seul lien, UNE seule trace `applique` (le rejeu écrit `ignore`) et UNE SEULE contrepassation — le rejeu ne double rien',
      n_liens = 1 AND n_app = 1 AND n_ign = 1 AND n_rev = 1,
      format('liens=%s applique=%s ignore=%s contrepassations=%s', n_liens, n_app, n_ign, n_rev));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'annuler deux fois : UN seul lien, UNE seule trace `applique` (le rejeu écrit `ignore`) et UNE SEULE contrepassation — le rejeu ne double rien', false, SQLERRM);
  END;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T05 — Structure : un contrat, un compagnon, et le dernier mot
--   Le contrat est déclaré et actif ; la fonction est SECURITY DEFINER et non
--   exposée ; le déclencheur `zz_l1_` s'exécute APRÈS son maillon métier
--   (`payroll_reverse_posted_run_trg`) — PostgreSQL trie les déclencheurs par
--   ordre ASCII du nom, donc aucun déclencheur métier de `pay_runs` ne trie
--   après lui. C'est la condition pour que le compagnon voie ce que le maillon
--   vient d'écrire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_effet text := 'payroll.run.reversed';
  v_fonction text := 'chain_l1_payroll_run_reversal';
  v_trigger text := 'zz_l1_payroll_run_reversal';
  n_contrats int; n_comp int; n_definer int; n_exposes int; n_apres_metier int; n_metier_apres int;
BEGIN
  SELECT count(*) INTO n_contrats FROM document_effects
   WHERE tenant_id IS NULL AND actif AND effet = v_effet
     AND document_type = 'pay_runs' AND evenement = 'cancelled';

  SELECT count(*), count(*) FILTER (WHERE p.prosecdef)
    INTO n_comp, n_definer
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname = v_fonction;

  SELECT count(*) INTO n_exposes
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace AND ns.nspname = 'public'
  WHERE p.proname = v_fonction AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  -- Mon déclencheur trie après TOUS les déclencheurs métier de `pay_runs`.
  SELECT count(*) INTO n_apres_metier
  FROM pg_trigger t
  WHERE NOT t.tgisinternal AND t.tgname = v_trigger AND t.tgrelid = 'pay_runs'::regclass
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger t2
      WHERE t2.tgrelid = t.tgrelid AND NOT t2.tgisinternal
        AND t2.tgname > t.tgname
        AND t2.tgname NOT LIKE 'zz_l1\_%'
    );

  -- Contre-épreuve : aucun déclencheur métier de `pay_runs` ne trie après le mien.
  SELECT count(*) INTO n_metier_apres
  FROM pg_trigger t
  WHERE NOT t.tgisinternal AND t.tgrelid = 'pay_runs'::regclass
    AND t.tgname NOT LIKE 'zz_l1\_%'
    AND t.tgname > v_trigger;

  PERFORM _rec('T05', 'structure : un contrat actif, un compagnon SECURITY DEFINER non exposé à `authenticated`, qui s''exécute APRÈS son maillon métier — aucun déclencheur métier de `pay_runs` ne trie après lui',
    n_contrats = 1 AND n_comp = 1 AND n_definer = 1 AND n_exposes = 0
      AND n_apres_metier = 1 AND n_metier_apres = 0,
    format('contrats=%s/1 compagnons=%s/1 SECURITY DEFINER=%s exposés=%s après-le-métier=%s/1 métier-après-moi=%s',
           n_contrats, n_comp, n_definer, n_exposes, n_apres_metier, n_metier_apres));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — Isolation : la société voisine ne voit ni lien, ni événement, ni trace
--   Les trois lectures se font SANS clause de société — c'est la RLS seule qui
--   doit cacher les lignes de l'autre société. Contrôle positif : la société
--   propriétaire, elle, voit bien son lien, son événement et sa trace.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; ra uuid;
        n_liens_a int; n_ev_a int; n_tr_a int;
        n_liens_voisin int; n_ev_voisin int; n_tr_voisin int;
BEGIN
  BEGIN
    ta := _mk_tenant('R6E');
    PERFORM _as_user();
    ra := _l321_lot(ta, 'PAIE-R6E');
    PERFORM post_payroll_journal(ra);
    UPDATE pay_runs SET status = 'cancelled' WHERE id = ra;

    SELECT count(*) INTO n_liens_a FROM _l321_liens(ta, 'pay_runs', ra) WHERE effet = 'payroll.run.reversed';
    n_ev_a := _l321_evt(ta, 'pay_runs.reversed', ra);
    SELECT count(*) INTO n_tr_a FROM _l321_traces(ta, 'payroll.run.reversed');

    -- La société voisine se connecte (utilisateur, JWT et contexte à elle).
    PERFORM set_config('role', 'postgres', true);
    tb := _mk_tenant('R6F');
    PERFORM _as_user();

    -- Lectures SANS filtre de société : la RLS doit suffire.
    SELECT count(*) INTO n_liens_voisin FROM document_links WHERE amont_id = ra;
    SELECT count(*) INTO n_ev_voisin FROM domain_events WHERE aggregate_id = ra;
    SELECT count(*) INTO n_tr_voisin FROM chain_traces WHERE tenant_id = ta;

    PERFORM _rec('T06', 'isolation : la société voisine ne voit ni le lien, ni l''événement, ni la trace de la contrepassation — et la société propriétaire les voit tous les trois (contrôle positif)',
      n_liens_a = 1 AND n_ev_a = 1 AND n_tr_a = 1
        AND n_liens_voisin = 0 AND n_ev_voisin = 0 AND n_tr_voisin = 0,
      format('propriétaire : liens=%s événements=%s traces=%s | voisine : liens=%s événements=%s traces=%s',
             n_liens_a, n_ev_a, n_tr_a, n_liens_voisin, n_ev_voisin, n_tr_voisin));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'isolation : la société voisine ne voit ni le lien, ni l''événement, ni la trace de la contrepassation — et la société propriétaire les voit tous les trois (contrôle positif)', false, SQLERRM);
  END;
END $$;

SELECT _audit_assert('411');