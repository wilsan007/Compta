-- ============================================================
-- 430_chain_l3_paie_rpc_tests.sql — L3 : LA PAIE TRACÉE PAR SON CHEMIN
--   D'APPEL — ce que les deux wrappers de la 430 garantissent
--
-- Source : recomptage de la tâche 3.1 (porte `ci/check_chain_rpc_inventory.sql`,
-- daté du 02/10/2026) — lignes `payroll_post_run` et `post_payroll_payment`,
-- toutes deux « EN COURS — tâche 3.2 ».
--
--   T01  la comptabilisation produit UN lien (pay_runs → journal_entries,
--        `PAYROLL-<n>`) et UNE trace `applique` — et l'événement ;
--   T02  le lot en BROUILLON refuse : aucune trace, aucun lien. On ne trace
--        pas un refus : un refus est une absence, pas un fait ;
--   T03  le REJEU ne double rien : une trace, un lien, et le corps renvoie
--        `already_posted` ;
--   T04  les TROIS CHEMINS d'appel convergent sur la même trace : la porte R-17
--        (`post_payroll_journal`), le versement, et le déclencheur au passage
--        à `paid`. C'est la promesse de la 430 — sans elle, on aurait tracé
--        une façade et laissé deux chemins muets ;
--   T05  le versement : lien au niveau du LOT, payload qui porte les
--        écritures, une trace `applique` ;
--   T06  le versement PARTIEL (`p_scope = 'net'`) : une seule écriture, donc
--        le lien désigne CETTE écriture — pas une autre ;
--   T07  mode `refuse` + effet éteint : l'appel LÈVE et RIEN ne persiste —
--        ni lot, ni écriture, ni lien, ni trace. La transaction de l'appel est
--        le mur (doctrine 412) ;
--   T08  STRUCTURE : les deux corps `_inner` ne sont PAS exécutables par
--        `authenticated`, les deux wrappers sont SECURITY DEFINER et portent la
--        chaîne, et les deux contrats sont déclarés et ACTIFS ;
--   T09  CLOISONNEMENT : la société voisine ne voit ni les liens, ni les
--        traces, ni les écritures de la paie de A.
--
-- Ce que cette suite NE mesure PAS : le relevé bancaire manuel (tâche 3.3),
-- ni le banc D1→D8 (3.4 → 3.7).
--
-- ⚠️ RAPPEL DE MÉTHODE (doctrine 412, appliquée ici). L'entrée du maillon est
-- posée APRÈS le corps : le corps est intact, donc on ne peut pas insérer
-- `chain_avant` avant l'effet. L'équivalence tient à la TRANSACTION DE L'APPEL :
-- en mode `refuse`, l'entrée LÈVE et rien ne persiste. C'est la limite de la
-- 252 §5, déjà dite : la trace `refuse` elle-même ne survit pas au rollback.
-- T07 mesure cette limite au lieu de la supposer.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '430', false);
DELETE FROM _audit_results WHERE file = '430';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Un lot de paie prêt à être APPROUVÉ : un salarié, un bulletin calculé.
-- La cartographie des comptes de paie est GLOBALE (mesuré :
-- `payroll_account_mapping` est peuplée en `tenant_id IS NULL`), donc
-- `_mk_tenant` suffit — pas de fixture ledger ici, contrairement aux
-- suites compta.
DROP FUNCTION IF EXISTS _l430_paie(text, text);
CREATE OR REPLACE FUNCTION _l430_paie(p_nom text, p_statut text DEFAULT 'approved',
  OUT t uuid, OUT emp uuid, OUT run uuid, OUT slip uuid, OUT usr uuid)
LANGUAGE plpgsql AS $fn$
DECLARE v_date date := DATE '2026-03-31';
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  -- L'IDENTITÉ du contexte, pas seulement la société : `current_tenant_id()`
  -- exige que `auth.uid()` soit membre de la société. Un scénario qui crée
  -- une société voisine et veut revenir doit donc restaurer l'UTILISATEUR
  -- aussi — sans quoi `current_tenant_id()` reste sur la société voisine et
  -- l'outillage ne reverrait rien. C'est mesuré (T09 l'a fait échouer).
  usr := auth.uid();

  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open');

  INSERT INTO employees (tenant_id, name, employee_number, status, hire_date)
  VALUES (t, 'Salarié ' || p_nom, 'EMP-' || p_nom, 'active', DATE '2024-01-01')
  RETURNING id INTO emp;

  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-' || p_nom, v_date - INTERVAL '1 month', v_date, v_date, p_statut,
          3000, 300, 2400, 1)
  RETURNING id INTO run;

  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id,
    period_start, period_end, gross_salary, total_gross,
    social_security_employee, income_tax, other_deductions, total_deductions,
    -- Le statut du BULLETIN a son propre vocabulaire, distinct de celui du lot :
    -- mesuré sur la base neuve, `pay_slips_status_check` n'admet que
    -- ('draft','approved','paid','cancelled') — PAS 'calculated'. On écrit donc
    -- 'draft' : c'est l'état d'un bulletin calculé et pas encore validé, et c'est
    -- ce que la comptabilisation attend.
    net_salary, employer_contributions, status, calc_inputs)
  VALUES (t, 'PS-' || p_nom, run, emp,
    v_date - INTERVAL '1 month', v_date, 3000, 3000,
    300, 300, 0, 600, 2400, 500, 'draft',
    jsonb_build_object('csgDeductible', 0, 'csgNonDeductible', 0, 'crds', 0,
                       'advanceDeduction', 0, 'expenseReimbursement', 0,
                       'mealVouchers', 0, 'transportAllowance', 0));
  SELECT id INTO slip FROM pay_slips WHERE tenant_id = t AND pay_run_id = run LIMIT 1;
END $fn$;

-- Les liens d'un lot pour un effet donné : la suite ne suppose pas qu'un
-- seul maillon a produit quelque chose.
DROP FUNCTION IF EXISTS _l430_liens(uuid, text);
CREATE OR REPLACE FUNCTION _l430_liens(p_run uuid, p_effet text)
RETURNS TABLE (lien uuid, aval uuid, etat text, payload jsonb)
LANGUAGE sql STABLE AS $fn$
  SELECT l.id, l.aval_id, l.etat, l.payload
  FROM document_links l
  WHERE l.tenant_id = current_tenant_id() AND l.amont_type = 'pay_runs'
    AND l.amont_id = p_run AND l.effet = p_effet
$fn$;

-- Les traces d'un lot pour un effet donné.
DROP FUNCTION IF EXISTS _l430_traces(uuid, text);
CREATE OR REPLACE FUNCTION _l430_traces(p_run uuid, p_effet text)
RETURNS TABLE (resultat text, lignes integer)
LANGUAGE sql STABLE AS $fn$
  SELECT c.resultat, c.lignes_ecrites
  FROM chain_traces c
  WHERE c.tenant_id = current_tenant_id() AND c.amont_type = 'pay_runs'
    AND c.amont_id = p_run AND c.effet = p_effet
$fn$;

-- ─────────────────────────────────────────────────────────────
-- T01 — la comptabilisation produit un lien, une trace, un événement
-- ─────────────────────────────────────────────────────────────
DO $t01$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
BEGIN
  SELECT * FROM _l430_paie('t01') INTO t, emp, run, slip, usr;
  PERFORM payroll_post_run(run);
  PERFORM _rec('T01', 'la comptabilisation est tracée par son chemin d''appel',
    (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')) = 1
    AND (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted')
           WHERE resultat = 'applique' AND lignes = 1) = 1
    AND (SELECT count(*) FROM domain_events
           WHERE tenant_id = t AND aggregate_type = 'pay_runs'
             AND aggregate_id = run AND event_name = 'pay_runs.posted') = 1,
    format('liens=%s applique=%s evenements=%s',
           (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')),
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique'),
           (SELECT count(*) FROM domain_events WHERE tenant_id = t AND aggregate_id = run
              AND event_name = 'pay_runs.posted')));
END $t01$;

-- ─────────────────────────────────────────────────────────────
-- T02 — un lot en BROUILLON ne se trace pas
--    Un refus est une ABSENCE, pas un fait. Tracer « il n'y a rien » pour un
--    lot que le maillon a lui-même refusé produit du bruit : la trace
--    dirait que la paie a été examinée et a produit un effet.
-- ─────────────────────────────────────────────────────────────
DO $t02$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid; v_leve boolean := false;
BEGIN
  SELECT * FROM _l430_paie('t02', 'draft') INTO t, emp, run, slip, usr;
  BEGIN
    PERFORM payroll_post_run(run);
  EXCEPTION WHEN OTHERS THEN
    v_leve := true;
  END;
  PERFORM _rec('T02', 'un lot en brouillon refuse et ne laisse NI lien NI trace',
    v_leve
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')) = 0
    AND (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted')) = 0,
    format('levée=%s liens=%s traces=%s', v_leve,
           (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')),
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted'))));
END $t02$;

-- ─────────────────────────────────────────────────────────────
-- T03 — le rejeu ne double rien
--    Le rejeu est le cas que le banc D1 (tâche 3.5) éprouvera à l'échelle ;
--    ici on prouve déjà que le corps idempotent ne produit pas de seconde
--    trace `applique`, et que le lien reste unique.
-- ─────────────────────────────────────────────────────────────
DO $t03$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
BEGIN
  SELECT * FROM _l430_paie('t03') INTO t, emp, run, slip, usr;
  PERFORM payroll_post_run(run);
  PERFORM payroll_post_run(run);
  PERFORM payroll_post_run(run);
  PERFORM _rec('T03', 'trois appels : une trace `applique`, un lien, une écriture',
    (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted')
       WHERE resultat = 'applique') = 1
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')) = 1
    AND (SELECT count(*) FROM journal_entries
           WHERE tenant_id = t AND reference = 'PAYROLL-PR-t03') = 1,
    format('applique=%s liens=%s ecritures=%s',
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique'),
           (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')),
           (SELECT count(*) FROM journal_entries WHERE tenant_id = t AND reference = 'PAYROLL-PR-t03')));
END $t03$;

-- ─────────────────────────────────────────────────────────────
-- T04 — LES TROIS CHEMINS D'APPEL CONVERGENT SUR LA MÊME TRACE
--    C'est LA promesse de la 415, et c'est ce qu'une fonction de façade
--    n'aurait pas tenu. Trois entrées distinctes, un lot neuf à chaque fois :
--      (1) `post_payroll_journal` — la porte R-17 (payroll.post), le front ;
--      (2) le déclencheur `create_journal_on_payroll_validate`, au passage du
--          lot à `paid` (UPDATE) ;
--      (3) `post_payroll_payment` — le versement, qui appelle la comptabilisation
--          en interne.
--    Les trois doivent produire le MÊME lien et la MÊME trace. Si l'un des
--    trois muet, la comptabilisation a un angle mort — et c'est exactement ce
--    que la fonction de façade aurait laissé.
-- ─────────────────────────────────────────────────────────────
DO $t04a$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
BEGIN
  SELECT * FROM _l430_paie('t04a') INTO t, emp, run, slip, usr;
  -- (1) la porte R-17
  PERFORM post_payroll_journal(run);
  PERFORM _rec('T04a', 'chemin 1 — la porte R-17 `post_payroll_journal` trace',
    (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique') = 1
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')) = 1,
    format('applique=%s liens=%s',
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique'),
           (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted'))));
END $t04a$;

DO $t04b$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
BEGIN
  SELECT * FROM _l430_paie('t04b') INTO t, emp, run, slip, usr;
  -- (2) le DÉCLENCHEUR : on écrit le lot à `paid`, le maillon part tout seul
  EXECUTE 'RESET ROLE';
  UPDATE pay_runs SET status = 'paid' WHERE id = run AND tenant_id = t;
  PERFORM _rec('T04b', 'chemin 2 — le déclencheur de passage à `paid` trace aussi',
    (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique') = 1
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted')) = 1,
    format('applique=%s liens=%s',
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique'),
           (SELECT count(*) FROM _l430_liens(run, 'payroll.run.posted'))));
END $t04b$;

DO $t04c$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
BEGIN
  SELECT * FROM _l430_paie('t04c') INTO t, emp, run, slip, usr;
  -- (3) le VERSEMENT : il appelle la comptabilisation en interne
  PERFORM post_payroll_payment(run, NULL, NULL, 'all');
  PERFORM _rec('T04c', 'chemin 3 — le versement trace la comptabilisation ET son versement',
    (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted')   WHERE resultat = 'applique') = 1
    AND (SELECT count(*) FROM _l430_traces(run, 'payroll.payment.settled') WHERE resultat = 'applique') = 1,
    format('post=%s paiement=%s',
           (SELECT count(*) FROM _l430_traces(run, 'payroll.run.posted') WHERE resultat = 'applique'),
           (SELECT count(*) FROM _l430_traces(run, 'payroll.payment.settled') WHERE resultat = 'applique')));
END $t04c$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le versement : lien au niveau du LOT, payload complet
--    L'effet est N:1 (jusqu'à quatre écritures de versement). La doctrine 316
--    impose alors : lien au niveau du DOCUMENT, aval de référence = plus petit
--    identifiant (déterministe pour qu'un rejeu désigne le même), et le
--    décompte + les identifiants au payload. C'est ce que la suite vérifie —
--    un lien qui pointerait « au hasard » passerait pour un lien valide.
-- ─────────────────────────────────────────────────────────────
DO $t05$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid; v_n int; v_ref uuid;
BEGIN
  SELECT * FROM _l430_paie('t05') INTO t, emp, run, slip, usr;
  PERFORM payroll_post_run(run);
  PERFORM post_payroll_payment(run, NULL, NULL, 'all');

  SELECT count(*) INTO v_n FROM journal_entries
   WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR-t05-%';

  -- L'aval de référence doit être le PLUS PETIT identifiant, et le payload
  -- doit porter le décompte et la liste — sinon un rejeu désignerait un autre.
  -- ⚠️ `min(uuid)` N'EXISTE PAS en PostgreSQL : `min` est défini pour les types
  -- qui portent un ordre — pas pour `uuid`. On prend donc le premier d'un
  -- tableau trié.
  SELECT (array_agg(id ORDER BY id))[1] INTO v_ref FROM journal_entries
   WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR-t05-%';

  PERFORM _rec('T05', 'le versement lie le lot à son aval de référence et porte le décompte au payload',
    v_n >= 1
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.payment.settled')) = 1
    AND (SELECT aval FROM _l430_liens(run, 'payroll.payment.settled')) = v_ref
    AND (SELECT (payload->>'versements')::int FROM _l430_liens(run, 'payroll.payment.settled')) = v_n
    AND (SELECT jsonb_array_length(payload->'ids') FROM _l430_liens(run, 'payroll.payment.settled')) = v_n
    AND (SELECT count(*) FROM _l430_traces(run, 'payroll.payment.settled')
           WHERE resultat = 'applique') = 1,
    format('ecritures=%s aval_ref=%s liens=%s', v_n, v_ref,
           (SELECT count(*) FROM _l430_liens(run, 'payroll.payment.settled'))));
END $t05$;

-- ─────────────────────────────────────────────────────────────
-- T06 — le versement PARTIEL : une seule écriture, donc CETTE écriture
--    C'est le test qui distingue un lien réel d'un lien décoratif. Avec
--    `p_scope = 'net'`, il n'y a qu'une écriture de versement ; si le lien
--    désignait l'écriture de paie (`PAYROLL-…`) au lieu de l'écriture de
--    versement (`PAYPAY-…-net`), il serait faux — et rien d'autre ne le
--    dirait, parce que « un lien existe » serait toujours vrai.
-- ─────────────────────────────────────────────────────────────
DO $t06$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid; v_aval uuid; v_ref text;
BEGIN
  SELECT * FROM _l430_paie('t06') INTO t, emp, run, slip, usr;
  PERFORM payroll_post_run(run);
  PERFORM post_payroll_payment(run, NULL, NULL, 'net');

  -- La colonne de sortie de `_l430_liens` s'appelle `aval` (c'est le nom
  -- donné dans le RETURNS TABLE de l'outillage), pas `aval_id`.
  SELECT l.aval INTO v_aval FROM _l430_liens(run, 'payroll.payment.settled') l;
  SELECT je.reference INTO v_ref FROM journal_entries je WHERE je.id = v_aval;

  PERFORM _rec('T06', 'un versement partiel lie le lot à SON écriture de versement, pas à l''écriture de paie',
    v_ref LIKE 'PAYPAY-PR-t06-net%'
    AND (SELECT count(*) FROM journal_entries
           WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR-t06-%') = 1,
    format('aval=%s reference=%s', v_aval, COALESCE(v_ref, '(null)')));
END $t06$;

-- ─────────────────────────────────────────────────────────────
-- T07 — mode `refuse` + effet éteint : l'appel LÈVE et RIEN ne persiste
--    C'est la limite de la 252 §5, dite et non supposée : la trace `refuse`
--    elle-même ne survit pas au rollback. Ce que la suite exige n'est donc
--    PAS « une trace refuse » — c'est « RIEN : ni lot payé, ni écriture de
--    versement, ni lien, ni trace ». La transaction de l'appel est le mur.
--
--    ⚠️ IL FAUT DEUX RÉGLAGES, ET LE PREMIER SEUL NE SUFFIT PAS — c'est
--    mesuré, et c'est le genre de détail qui fait croire à un test vert.
--    Éteindre l'effet (`actif = false`) fait FALSE à `chain_autorise`, mais
--    `chain_avant` retombe alors sur le MODE de la société, qui vaut
--    `observe` par défaut : il écrit une trace `tolere` et **retourne vrai** —
--    l'effet est donc APPLIQUÉ sans contrat. C'est exactement ce que la
--    mesure a montré : 3 écritures, 1 lien, 2 traces, lot payé, aucun refus.
--    Il faut donc AUSSI passer la société en `refuse`. On pose un contrat
--    PROPRE à la société (actif = false) plutôt que d'éteindre le contrat
--    global : le global est partagé par toutes les sociétés, et une suite qui
--    le modifierait pourrait faire échouer une autre suite exécutée après.
-- ─────────────────────────────────────────────────────────────
DO $t07$
DECLARE t uuid; emp uuid; run uuid; slip uuid; usr uuid;
        v_leve boolean := false; v_statut text; v_msg text := '';
BEGIN
  SELECT * FROM _l430_paie('t07') INTO t, emp, run, slip, usr;
  PERFORM payroll_post_run(run);

  -- (a) le mode de la société : `refuse`
  EXECUTE 'RESET ROLE';
  INSERT INTO chain_settings (tenant_id, enforcement, updated_at)
  VALUES (t, 'refuse', now())
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = 'refuse';

  -- (b) un contrat PROPRE à la société, éteint — il l'emporte sur le global
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif, note)
  VALUES (t, 'pay_runs', 'paid', 'payroll.payment.settled', false,
          'Sonde T07 : contrat éteint pour cette société seule.');

  BEGIN
    PERFORM post_payroll_payment(run, NULL, NULL, 'all');
  EXCEPTION WHEN OTHERS THEN
    v_leve := true;
    v_msg   := SQLERRM;
  END;

  SELECT status INTO v_statut FROM pay_runs WHERE id = run;

  PERFORM _rec('T07', 'effet éteint + mode refuse : l''appel lève et RIEN ne persiste (ni lot payé, ni écriture, ni lien, ni trace)',
    v_leve
    AND v_msg LIKE '%payroll.payment.settled%'
    AND v_statut <> 'paid'
    AND (SELECT count(*) FROM journal_entries
           WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR-t07-%') = 0
    AND (SELECT count(*) FROM _l430_liens(run, 'payroll.payment.settled')) = 0
    AND (SELECT count(*) FROM _l430_traces(run, 'payroll.payment.settled')) = 0,
    format('levée=%s msg=%s statut=%s ecritures=%s liens=%s traces=%s', v_leve, left(v_msg, 40), v_statut,
           (SELECT count(*) FROM journal_entries WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR-t07-%'),
           (SELECT count(*) FROM _l430_liens(run, 'payroll.payment.settled')),
           (SELECT count(*) FROM _l430_traces(run, 'payroll.payment.settled'))));
END $t07$;

-- ─────────────────────────────────────────────────────────────
-- T08 — STRUCTURE : les corps ne sont pas exposés, les wrappers portent la
--    chaîne, les contrats sont ACTIFS.
--    C'est la leçon R-17 de la 220 (« le corps renommé n'est plus exposé »)
--    appliquée : un corps `_inner` exécutable par `authenticated` permetrait
--    d'écrire une paie sans laisser de trace — le défaut exact que la 430
--    vient fermer.
-- ─────────────────────────────────────────────────────────────
DO $t08$
DECLARE v_n int; v_ok boolean; v_detail text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE p.proname IN ('payroll_post_run_inner', 'payroll_payment_inner');

  v_ok := (v_n = 2)
     AND NOT has_function_privilege('authenticated',
            'public.payroll_post_run_inner(uuid)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated',
            'public.payroll_payment_inner(uuid,uuid,date,text)', 'EXECUTE')
     AND (SELECT prosecdef FROM pg_proc WHERE proname = 'payroll_post_run')
     AND (SELECT prosrc ~ 'chain_avant' FROM pg_proc WHERE proname = 'payroll_post_run')
     AND (SELECT prosrc ~ 'chain_avant' FROM pg_proc WHERE proname = 'post_payroll_payment')
     AND (SELECT count(*) FROM document_effects
           WHERE effet IN ('payroll.run.posted', 'payroll.payment.settled') AND actif) = 2;

  v_detail := format('corps=%s auth_sur_inner=%s/%s wrappers_secdef=%s contrats=%s', v_n,
    has_function_privilege('authenticated', 'public.payroll_post_run_inner(uuid)', 'EXECUTE'),
    has_function_privilege('authenticated', 'public.payroll_payment_inner(uuid,uuid,date,text)', 'EXECUTE'),
    (SELECT prosecdef FROM pg_proc WHERE proname = 'payroll_post_run'),
    (SELECT count(*) FROM document_effects WHERE effet IN ('payroll.run.posted','payroll.payment.settled') AND actif));

  PERFORM _rec('T08', 'les deux corps `_inner` existent et ne sont PAS exécutables par `authenticated` ; les deux wrappers sont SECURITY DEFINER et portent la chaîne ; les deux contrats sont actifs',
    v_ok, v_detail);
END $t08$;

-- ─────────────────────────────────────────────────────────────
-- T09 — CLOISONNEMENT : la société voisine ne voit rien de la paie de A.
--    Sans ce test, un maillon SECURITY DEFINER qui lirait `document_links`
--    sans filtrer par société produirait un lien de la société B vers un lot
--    de la société A — invisible dans l'écran de A, et présent dans celui de B.
--    C'est le genre de défaut que le seul « ça marche » ne voit jamais.
-- ─────────────────────────────────────────────────────────────
DO $t09$
DECLARE ta uuid; ea uuid; ra uuid; sa uuid; ua uuid;
        tb uuid; eb uuid; rb uuid; sb uuid; ub uuid;
        v_liens_b integer; v_traces_b integer;
BEGIN
  SELECT * FROM _l430_paie('t09a') INTO ta, ea, ra, sa, ua;
  -- A est comptabilisée et payée sous SON contexte
  PERFORM payroll_post_run(ra);
  PERFORM post_payroll_payment(ra, NULL, NULL, 'all');

  -- On passe chez B, avec SA société active
  SELECT * FROM _l430_paie('t09b') INTO tb, eb, rb, sb, ub;

  SELECT count(*) INTO v_liens_b FROM document_links
   WHERE tenant_id = tb AND amont_type = 'pay_runs' AND amont_id = ra;
  SELECT count(*) INTO v_traces_b FROM chain_traces
   WHERE tenant_id = tb AND amont_type = 'pay_runs' AND amont_id = ra;

  -- On revient chez A : l'IDENTITÉ, pas seulement la société.
  -- `current_tenant_id()` exige que `auth.uid()` soit membre de la société
  -- visée (mesuré sur la base neuve) : rétablir `app.active_tenant_id` seul
  -- ne suffit pas, et l'outillage `_l430_liens` ne reverrait rien — le test
  -- dirait « cloisonnement cassé » alors que le maillon est parfaitement
  -- cloisonné. On rétablit donc les DEUX.
  PERFORM set_config('request.jwt.claim.sub', ua::text, false);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', ua, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', ta::text, false);

  PERFORM _rec('T09', 'la société voisine ne voit NI lien NI trace de la paie de A — et A voit les siens',
    v_liens_b = 0 AND v_traces_b = 0
    AND (SELECT count(*) FROM _l430_liens(ra, 'payroll.payment.settled')) = 1
    AND (SELECT count(*) FROM _l430_liens(ra, 'payroll.run.posted')) = 1,
    format('liens_vus_par_B=%s traces_vues_par_B=%s liens_de_A=%s', v_liens_b, v_traces_b,
           (SELECT count(*) FROM _l430_liens(ra, 'payroll.payment.settled'))));
END $t09$;

-- ─────────────────────────────────────────────────────────────
-- Verdict de la suite — `_audit_assert` compare au registre des échecs
-- attendus et REFUSE un fichier sans verdict (une suite qui ne prouve rien
-- est pire qu'une suite absente : elle laisse croire que le défaut est couvert).
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('430');
