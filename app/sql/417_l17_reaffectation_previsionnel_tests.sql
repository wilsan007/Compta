-- ============================================================
-- 417_l17_reaffectation_previsionnel_tests.sql — L17 (tranche 2) :
--   LA PROPOSITION DE RÉAFFECTATION et le prévisionnel RH en sens
--   inverse — les deux exigences du lot que la 416 a laissées ouvertes
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L17**, troisième et quatrième exigence :
-- « alerte sur les créneaux orphelins, **proposition de réaffectation** ;
-- à l'inverse, **une charge de production planifiée apparaît dans le
-- prévisionnel RH** ». La 416 (tranche 1) a livré le porteur, le
-- constat, la garde et la capacité ajustée — et a dit dans sa preuve
-- (§6, points 2 et 3) que ces deux exigences restaient entières.
--
-- ⚠️ MESURÉ AVANT LA 417, SUR BASE NEUVE (280 migrations, 0 erreur) :
--
--   * **AUCUNE proposition de remplacement n'existe.** Mesuré : 0
--     fonction dont le nom porte « réaffect », « remplac », « candidat »
--     ou « disponib » — la seule qui s approaches est
--     `chain_lien_remplacer`, qui est le CYCLE DU LIEN du socle
--     (402) et n'a rien à voir. Le chef d'atelier voit donc un
--     créneau marqué « opérateur absent » et… rien pour l'aider.
--
--   * **AUCUN prévisionnel RH ne lit la production.** Mesuré : 0
--     fonction de prévision ou de charge lit `planning_slots`. Le
--     sens inverse du couple est donc lui aussi vide : rien ne dit au
--     RH « cette personne a 7 h de production planifiées la semaine
--     prochaine ».
--
--   * `employees.position` est un **texte libre** : mesuré, aucune
--     contrainte sur la colonne. C'est le seul critère de
--     qualification qui existe entre un opérateur et un poste — et
--     il n'est pas qualifiant au sens fort. La fonction le dit au
--     lieu de le faire croire.
--
--   * `work_center_calendars` (disponible_hours, is_holiday, is_closed)
--     existe et n'est lu par personne pour une capacité d'opérateur.
--
--   T01  **la proposition existe et elle est JUSTIFIÉE** — un créneau
--        orphelin rend des candidats, et chacun avec son motif.
--   T02  **un candidat absent n'est JAMAIS proposé** — c'est le défaut
--        que la proposition créerait si elle ignorait le registre.
--   T03  **le candidat le moins chargé vient en premier** — l'ordre
--        est une décision, pas un effet de bord.
--   T04  **sans qualification portée, on ne devine pas** — le contrat
--        dit « aucun critère » plutôt que de renvoyer les 40 employés.
--   T05  **le prévisionnel RH en sens inverse** — la charge de
--        production d'un salarié, en heures, sur une période.
--   T06  **T-4 / D-8, l'isolation tient sur les DEUX sens** — un
--        utilisateur de A ne lit ni les candidats ni la charge de B.
--   T07  **point 6 de §4.1, refus explicite** — un créneau qui
--        n'existe pas, ou d'une autre société, est refusé par NOM.
--   T08  **point 8 de §4.1, performance mesurée** — p95 des deux
--        lectures sur 200 créneaux, budget §3.3 (≤ 50 ms).
--
-- Les scénarios s'exécutent en superutilisateur avec le contexte de
-- société posé par `_mk_tenant` : les deux lectures sont des
-- `SECURITY DEFINER`, et c'est leur **propre** isolation (T06) qui
-- est prouvée, non celle de la session.
-- ==========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '417', false);
DELETE FROM _audit_results WHERE file = '417';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────
-- Un jour ouvré fixe, commun aux scénarios (comme la 416).
CREATE OR REPLACE FUNCTION _l417_jour() RETURNS date
LANGUAGE sql IMMUTABLE AS $$ SELECT DATE '2026-03-10' $$;

-- Un salarié, avec une POSITION — c'est le seul critère de
-- qualification qui existe, et le scénario qui s'en sert doit le
-- porter explicitement.
CREATE OR REPLACE FUNCTION _l417_employe(p_t uuid, p_nom text, p_position text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid; v_courriel text;
BEGIN
  v_courriel := regexp_replace(lower(p_nom), '[^a-z0-9]+', '.', 'g')
             || '.' || left(p_t::text, 8) || '@audit.test';
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours, position)
  VALUES (p_t, p_nom, v_courriel, 'active', 3000, 35, p_position)
  RETURNING id INTO e;
  RETURN e;
END $$;

-- Article + nomenclature + OF, comme la 416 : le déclencheur
-- `manufacturing_order_product_from_bom` refuse une OF sans article.
CREATE OR REPLACE FUNCTION _l417_of(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE o uuid; pf uuid; comp uuid; b uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock', 10) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'Composant ' || p_nom, 'CO-' || p_nom, 'stock', 2) RETURNING id INTO comp;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
  VALUES (p_t, 'B-' || p_nom, 'Nomenclature ' || p_nom, pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity) VALUES (p_t, b, comp, 2);
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status)
  VALUES (p_t, 'OF-' || p_nom, b, pf, 10, 'planned') RETURNING id INTO o;
  RETURN o;
END $$;

CREATE OR REPLACE FUNCTION _l417_creneau(p_t uuid, p_of uuid, p_emp uuid, p_wc uuid,
                                        p_start timestamptz, p_run numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE s uuid;
BEGIN
  INSERT INTO planning_slots (tenant_id, manufacturing_order_id, employee_id, work_center_id,
                              planned_start, planned_end, setup_time, run_time,
                              status, material_available)
  VALUES (p_t, p_of, p_emp, p_wc, p_start,
          p_start + make_interval(mins => (p_run + 30)::int),
          30, p_run, 'scheduled', true)
  RETURNING id INTO s;
  RETURN s;
END $$;

CREATE OR REPLACE FUNCTION _l417_absence(p_t uuid, p_emp uuid, p_day date, p_kind text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d uuid;
BEGIN
  INSERT INTO employee_absence_days (tenant_id, employee_id, day, absence_kind,
                                     origin, justification_state, blocks_work)
  VALUES (p_t, p_emp, p_day, p_kind, 'leave_request', 'provided',
          (SELECT x.blocks_work FROM absence_kind_flags(p_kind) x))
  RETURNING day_uid INTO d;
  RETURN d;
END $$;
-- ═════════════════════════════════════════════════════════════
-- T01 — LA PROPOSITION EXISTE, ET ELLE EST JUSTIFIÉE
--   Un créneau marqué « opérateur absent » doit rendre des
--   candidats. On mesure le nombre ET le MOTIF : une liste sans
--   raison n'aide personne à décider.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; of1 uuid; absent1 uuid; s1 uuid; j date; ts timestamptz;
        n int; motif text; noms text;
BEGIN
  t := _mk_tenant('L17T01'); j := _l417_jour();
  ts := (j::text || ' 08:00+01')::timestamptz;
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;
  of1 := _l417_of(t, 'T01');

  absent1 := _l417_employe(t, 'Kader T01', 'Tourneur');
  -- un confrère QUALIFIÉ et présent : sans lui, zéro candidat
  -- serait le comportement CORRECT (personne ne peut faire le poste)
  -- et le scénario ne prouverait rien.
  PERFORM _l417_employe(t, 'Rachid T01', 'Tourneur');
  s1 := _l417_creneau(t, of1, absent1, wc, ts, 210);
  PERFORM _l417_absence(t, absent1, j, 'annual');

  -- la fonction renvoie DÉJÀ le nom et le motif : pas besoin de
  -- joindre `employees` — et surtout pas de le faire, sinon
  -- `nom` devient ambigu entre la fonction et la table.
  SELECT count(*), min(c.motif), string_agg(c.nom, ', ' ORDER BY c.nom)
    INTO n, motif, noms
  FROM planning_slot_candidats(t, s1) c;

  PERFORM _rec('T01', 'un créneau orphelin rend des candidats, et chacun avec son motif',
    n >= 1 AND motif IS NOT NULL AND btrim(motif) <> '',
    format('candidats=%s [%s] | motif du premier=« %s »', n, coalesce(noms, '—'),
           left(coalesce(motif, 'NULL'), 90)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'un créneau orphelin rend des candidats', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — UN CANDIDAT ABSENT N'EST JAMAIS PROPOSÉ
--   Le défaut que la proposition créerait si elle ignorait le
--   registre d'absences : on remplace un absent par un autre
--   absent. C'est aussi ce que W9 a appris à toutes les autres
--   gardes (tâche, pointage, temps projet, note de frais).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; of1 uuid; absent1 uuid; autre_absent uuid; s1 uuid;
        j date; ts timestamptz; n int; ids text;
BEGIN
  t := _mk_tenant('L17T02'); j := _l417_jour();
  ts := (j::text || ' 08:00+01')::timestamptz;
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;
  of1 := _l417_of(t, 'T02');

  absent1      := _l417_employe(t, 'Kader T02', 'Tourneur');
  autre_absent := _l417_employe(t, 'Sofiane T02', 'Tourneur');
  PERFORM _l417_employe(t, 'Rachid T02', 'Tourneur');   -- le seul disponible
  s1 := _l417_creneau(t, of1, absent1, wc, ts, 210);

  -- les DEUX touredeurs du jour sont absents : il ne doit rester que
  -- celui qui est là.
  PERFORM _l417_absence(t, absent1,      j, 'annual');
  PERFORM _l417_absence(t, autre_absent, j, 'sick');

  SELECT count(*), string_agg(c.employee_id::text, ' ')
    INTO n, ids
  FROM planning_slot_candidats(t, s1) c;

  PERFORM _rec('T02', 'un candidat lui-même absent n''est jamais proposé',
    n = 1 AND ids NOT LIKE '%' || autre_absent::text || '%',
    format('candidats=%s (1 attendu : le seul présent) | absent exclu=%s',
           n, (ids IS NULL OR ids NOT LIKE '%' || autre_absent::text || '%')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'un candidat lui-même absent n''est jamais proposé', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — LE MOINS CHARGÉ VIENT EN PREMIER
--   L'ordre est une DÉCISION, pas un effet de bord : proposer
--   d'abord celui qui est déjà saturé serait proposer le pire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; of1 uuid; absent1 uuid; charge uuid; libre uuid; s1 uuid;
        j date; ts2 timestamptz; premier uuid; libre_id uuid; n int;
BEGIN
  t := _mk_tenant('L17T03'); j := _l417_jour();
  ts2 := (j::text || ' 14:00+01')::timestamptz;
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;
  of1 := _l417_of(t, 'T03');

  absent1 := _l417_employe(t, 'Kader T03', 'Tourneur');
  charge  := _l417_employe(t, 'Amine T03', 'Tourneur');
  libre   := _l417_employe(t, 'Nabil T03', 'Tourneur');
  libre_id := libre;

  -- le créneau orphelin, le matin
  s1 := _l417_creneau(t, of1, absent1, wc, (j::text || ' 08:00+01')::timestamptz, 210);
  -- Amine a DÉJÀ 6 h ce jour-là ; Nabil n'a rien.
  PERFORM _l417_creneau(t, of1, charge, wc, (j::text || ' 07:00+01')::timestamptz, 330);
  PERFORM _l417_absence(t, absent1, j, 'annual');

  SELECT c.employee_id INTO premier
  FROM planning_slot_candidats(t, s1) c LIMIT 1;
  SELECT count(*) INTO n FROM planning_slot_candidats(t, s1);

  PERFORM _rec('T03', 'le candidat le MOINS chargé vient en premier',
    n = 2 AND premier = libre_id,
    format('candidats=%s | premier=%s (Nabil, 0 h) | Amine (6 h) vient après=%s',
           n, CASE WHEN premier = libre_id THEN 'Nabil' ELSE 'autre' END,
           (SELECT bool_or(c.employee_id = charge) FROM planning_slot_candidats(t, s1) c)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'le candidat le moins chargé vient en premier', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T04 — SANS QUALIFICATION PORTÉE, ON NE DEVINE PAS
--   `employees.position` est un texte libre (mesuré : aucune
--   contrainte). Quand l'opérateur absent n'en porte pas, la
--   fonction NE RENVOIE PAS les 40 employés de la société — elle
--   ne renvoie personne, et le dit. Une liste sans critère est
--   une liste sans information.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; of1 uuid; sans_pos uuid; s1 uuid; j date; n int; n_avec int;
        avec_pos uuid; s2 uuid;
BEGIN
  t := _mk_tenant('L17T04'); j := _l417_jour();
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;
  of1 := _l417_of(t, 'T04');

  -- l'opérateur absent N'A PAS de qualification...
  sans_pos := _l417_employe(t, 'Zinedine T04', NULL);
  s1 := _l417_creneau(t, of1, sans_pos, wc, (j::text || ' 08:00+01')::timestamptz, 210);
  -- ...alors que la société compte des employés, dont des tourneurs
  PERFORM _l417_employe(t, 'Rachid T04', 'Tourneur');
  PERFORM _l417_employe(t, 'Sofiane T04', 'Tourneur');
  PERFORM _l417_absence(t, sans_pos, j, 'annual');

  SELECT count(*) INTO n FROM planning_slot_candidats(t, s1);

  -- le CONTRE-EXEMPLE : le même créneau, un opérateur qui porte une
  -- qualification, DOIT rendre des candidats. Sans lui, T04 proving
  -- « toujours 0 » serait aussi vert.
  avec_pos := _l417_employe(t, 'Kader T04b', 'Tourneur');
  s2 := _l417_creneau(t, of1, avec_pos, wc, (j::text || ' 13:00+01')::timestamptz, 210);
  PERFORM _l417_absence(t, avec_pos, j, 'annual');
  SELECT count(*) INTO n_avec FROM planning_slot_candidats(t, s2);

  PERFORM _rec('T04', 'sans qualification portée, AUCUN candidat n''est proposé — et avec qualification, la proposition revient',
    n = 0 AND n_avec >= 1,
    format('opérateur SANS position → %s candidats (0 attendu) | opérateur AVEC position → %s candidats (1 minimum)',
           n, n_avec));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'sans qualification portée, aucun candidat n''est proposé', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T05 — LE PRÉVISIONNEL RH, EN SENS INVERSE
--   « à l'inverse, une charge de production planifiée apparaît dans
--   le prévisionnel RH ». Concretement : combien d'heures de
--   production sont planifiées sur CE salarié, sur CETTE période ?
--   Les créneaux que l'absence a bloqués en sont RETIRÉS : on ne
--   prévisionne pas du travail que personne ne peut faire.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; of1 uuid; e1 uuid; e2 uuid; j date;
        charge_e1 numeric; charge_e2 numeric;
BEGIN
  t := _mk_tenant('L17T05'); j := _l417_jour();
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;
  of1 := _l417_of(t, 'T05');

  e1 := _l417_employe(t, 'Kader T05', 'Tourneur');
  e2 := _l417_employe(t, 'Amine T05', 'Tourneur');

  -- Amine : 4 h (240 min + 30 de setup)
  PERFORM _l417_creneau(t, of1, e2, wc, (j::text || ' 07:00+01')::timestamptz, 210);
  -- Kader : 2 h, puis il tombe absent et ce créneau est retiré
  PERFORM _l417_creneau(t, of1, e1, wc, (j::text || ' 08:00+01')::timestamptz, 90);
  -- une PÉRIODE qui ne contient rien ne doit rien rendre
  PERFORM _l417_creneau(t, of1, e2, wc, ((j + 30)::text || ' 08:00+01')::timestamptz, 300);

  charge_e1 := employee_planned_load(t, e1, j, j);
  charge_e2 := employee_planned_load(t, e2, j, j);

  PERFORM _l417_absence(t, e1, j, 'annual');   -- son créneau devient inexploitable
  charge_e1 := employee_planned_load(t, e1, j, j);

  PERFORM _rec('T05', 'le prévisionnel RH lit la charge de production, et en RETIRE ce que l''absence rend inexploitable',
    charge_e2 = 4 AND charge_e1 = 0,
    format('Amine (présent) = %s h attendues (4) | Kader : 2 h avant son absence, %s h après (0 attendu)',
           coalesce(charge_e2::text, 'NULL'), coalesce(charge_e1::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'le prévisionnel RH lit la charge de production', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T06 — T-4 / D-8, L'ISOLATION TIENT SUR LES DEUX SENS
--   Les deux lectures sont `SECURITY DEFINER` : sans cloisonnement
--   explicite, un utilisateur de A lirait les candidats et la charge
--   de B. On pose le contexte sur B et on interroge A.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; oa uuid; ob uuid; sa uuid; sb uuid; ea uuid; eb uuid;
        j date; ctx uuid; cand_a int; cand_b int; charge_b numeric;
BEGIN
  ta := _mk_tenant('L17T06A'); tb := _mk_tenant('L17T06B'); j := _l417_jour();
  oa := _l417_of(ta, 'T06A'); ob := _l417_of(tb, 'T06B');
  ea := _l417_employe(ta, 'Kader T06A', 'Tourneur');
  eb := _l417_employe(tb, 'Sofiane T06B', 'Tourneur');
  sa := _l417_creneau(ta, oa, ea, NULL, (j::text || ' 08:00+01')::timestamptz, 210);
  sb := _l417_creneau(tb, ob, eb, NULL, (j::text || ' 08:00+01')::timestamptz, 210);
  -- On pose brièvement le contexte sur A pour y écrire l'absence :
  -- c'est la garde W9 `assert_absence_tenant` qui l'exige, et elle a
  -- raison — écrire une absence dans une société qu'on ne consulte
  -- pas est ce que la 236 a interdit. Ce que l'on mesure ici n'est
  -- donc pas le contexte, mais le fait que les DEUX LECTURES
  -- travaillent sur la société demandée et jamais sur celle de la
  -- session.
  PERFORM set_config('app.active_tenant_id', ta::text, true);
  PERFORM _l417_absence(ta, ea, j, 'annual');
  PERFORM set_config('app.active_tenant_id', tb::text, true);
  PERFORM _l417_absence(tb, eb, j, 'annual');
  -- un candidat pour chaque côté, de la bonne société
  PERFORM _l417_employe(ta, 'Rachid T06A', 'Tourneur');
  PERFORM _l417_employe(tb, 'Amine T06B', 'Tourneur');

  ctx := current_tenant_id();   -- le contexte de session est B
  -- on interroge A alors que la session est B : c'est le cas le
  -- plus défavorable, le GUC et la ligne disant des choses
  -- différentes.
  SELECT count(*) INTO cand_a FROM planning_slot_candidats(ta, sa);
  SELECT count(*) INTO cand_b FROM planning_slot_candidats(tb, sb);
  -- la charge de B est lue DEPUIS A : elle doit dire 0 (son
  -- opérateur est absent) et non 4. Si l'isolation cédait, la
  -- fonction verrait les créneaux de B et renverrait une charge.
  SELECT employee_planned_load(ta, eb, j, j) INTO charge_b;

  PERFORM _rec('T06', 'les candidats et la charge de A ne sont pas lus depuis une session B — les DEUX sens',
    ctx = tb AND cand_a >= 1 AND cand_b >= 1 AND coalesce(charge_b, 0) = 0,
    format('contexte=%s | candidats A=%s B=%s (les deux doivent répondre) | charge de B lue depuis A = %s h (0 attendu : son opérateur est absent)',
           CASE WHEN ctx = tb THEN 'B' ELSE coalesce(ctx::text, 'NULL') END,
           cand_a, cand_b, coalesce(charge_b::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'l''isolation tient sur les deux sens', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — point 6 de §4.1, LE REFUS EST EXPLICITE ET NOMMÉ
--   Un créneau inexistant, ou d'une autre société, ne rend pas une
--   liste vide : il est REFUSÉ, et le message nomme ce qui manque.
--   Une liste vide se lit comme « personne n'est disponible », ce
--   qui est une autre information.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; o1 uuid; e1 uuid; s1 uuid; j date;
        refuse boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('L17T07'); j := _l417_jour();
  o1 := _l417_of(t, 'T07');
  e1 := _l417_employe(t, 'Kader T07', 'Tourneur');
  s1 := _l417_creneau(t, o1, e1, NULL, (j::text || ' 08:00+01')::timestamptz, 210);

  BEGIN
    SELECT count(*) INTO n FROM planning_slot_candidats(t, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    refuse := true; err := SQLERRM;
  END;

  PERFORM _rec('T07', 'un créneau inexistant est REFUSÉ, en nommant le motif',
    refuse AND err LIKE '%%' AND err ILIKE '%créneau%',
    format('refusé=%s | message=%s', refuse, left(err, 120)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'un créneau inexistant est refusé', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — point 8 de §4.1, LE SURCOÛT EST MESURÉ
--   200 créneaux orphelins, p95 des DEUX lectures rapporté au
--   budget d'une lecture simple (§3.3, ≤ 50 ms). Le chiffre est
--   dans le verdict : un « ça va vite » sans nombre ne prouve rien.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; e1 uuid; o1 uuid; j date; i int;
        p95cand double precision; p95charge double precision; budget double precision := 50;
        t0 timestamptz; d1 double precision[] := '{}'; d2 double precision[] := '{}';
        n int; total int := 0;
BEGIN
  t := _mk_tenant('L17T08'); j := _l417_jour();
  e1 := _l417_employe(t, 'Kader T08', 'Tourneur');
  o1 := _l417_of(t, 'T08');
  PERFORM _l417_absence(t, e1, j, 'annual');
  -- un faisceau ouvert de candidats
  FOR i IN 1..200 LOOP
    PERFORM _l417_employe(t, 'Cand' || i || ' T08', 'Tourneur');
  END LOOP;
  PERFORM set_config('role', 'postgres', true);

  FOR i IN 1..200 LOOP
    -- `make_interval` évite de choisir un format de date à la main :
    -- c'est ce qui faisait échouer la concaténation.
    PERFORM _l417_creneau(t, o1, e1, NULL,
                          (DATE '2026-04-01' + i)::timestamptz + interval '8 hours', 90);
  END LOOP;

  FOR i IN 1..200 LOOP
    t0 := clock_timestamp();
    SELECT count(*) INTO n FROM planning_slot_candidats(t, (
      SELECT id FROM planning_slots WHERE tenant_id = t AND employee_id = e1
      ORDER BY planned_start LIMIT 1));
    total := total + n;
    d1 := d1 || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  FOR i IN 1..200 LOOP
    t0 := clock_timestamp();
    PERFORM employee_planned_load(t, e1, DATE '2026-04-01', DATE '2026-12-31');
    d2 := d2 || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95cand FROM unnest(d1) AS x;
  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95charge FROM unnest(d2) AS x;

  PERFORM _rec('T08', 'les deux lectures tiennent le budget de §3.3 — 200 appels chacune, p95 mesuré',
    p95cand IS NOT NULL AND p95cand <= budget
      AND p95charge IS NOT NULL AND p95charge <= budget,
    format('candidats p95=%s ms | prévisionnel p95=%s ms (budget %s ms)',
           round(p95cand::numeric, 3), round(p95charge::numeric, 3), budget));
END $$;

DROP FUNCTION _l417_jour();
DROP FUNCTION _l417_employe(uuid, text, text);
DROP FUNCTION _l417_of(uuid, text);
DROP FUNCTION _l417_creneau(uuid, uuid, uuid, uuid, timestamptz, numeric);
DROP FUNCTION _l417_absence(uuid, uuid, date, text);
SELECT _audit_assert('417');
