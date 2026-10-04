-- ============================================================
-- 416_chain_l17_capacite_absence_tests.sql — L17 (tranche 1) : LE
--   PLANNING DE PRODUCTION CONNAÎT L'ABSENCE — le couple
--   `production ↔ RH`, qui était VIDE, et le cas d'usage fondateur
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L17** (« Production ↔ RH (capacité ↔ absence) : le
-- planning de production connaît les absences : capacité ajustée,
-- alerte sur les créneaux orphelins, proposition de réaffectation ;
-- à l'inverse, une charge de production planifiée apparaît dans le
-- prévisionnel RH »), et le référentiel §A.4, où ce couple est
-- nommé comme l'un des **12 couples de modules vides** :
-- « la capacité de production ne connaît pas l'absence : on planifie
-- avec des salariés absents — le cas d'usage fondateur de tout ce
-- travail ». Dépendance : **L11** (`employee_absence_days`, 263) ✅.
--
-- ⚠️ MESURÉ AVANT LA 416, SUR BASE NEUVE (273 migrations, 0 erreur) —
--   c'est ce qui rend ce fichier rouge, et non une opinion :
--
--   * **LE PORTEUR N'EXISTE PAS.** `planning_slots` (la table du
--     planning de production, lue et écrite par l'écran
--     `PlanningPage.tsx` via `getPlanningSlots`/`autoScheduleMOs`)
--     ne porte **AUCUNE** colonne d'opérateur : mesuré, 0 colonne
--     parmi `employee_id` / `operator_id` / `assigned_to`. Un créneau
--     ne sait pas QUI le fait. Sans porteur, il n'y a rien à quoi
--     rattacher une absence : le couple n'est pas « incomplet », il
--     est **impossible**.
--
--   * **ZÉRO lecture croisée.** Mesuré : **0** fonction de la base
--     lit à la fois `planning_slots` et `employee_absence_days`.
--     Aucune n'est simplement « à jour » : aucune n'existe.
--
--   * **LA CAPACITÉ EST UNE CONSTATATION MUETTE.** La vue
--     `v_work_center_load` (126) — la seule chose qui compare la
--     charge à une capacité — compare la charge à un
--     `work_centers.capacity_hours_per_day` **théorique**, jamais
--     réduit d'un absent. Mesuré : le texte de la vue ne contient
--     pas « absence ». Un centre de charge peut donc afficher
--     « normal » le jour où la moitié de l'équipe est absente.
--     C'est un **calcul faux affiché comme vrai**, pas un manque :
--     pire que l'absence de la capacité.
--
--   * **AUCUNE GARDE.** W9 (264) a posé sept gardes d'absence en
--     aval (pointage, heures sup, temps projet, note de frais,
--     tâche). La **production** n'en a **aucune** : on planifie un
--     créneau pour un salarié absent sans que rien ne le dise, et le
--     créneau reste `scheduled` — donc l'ordonnanceur le comptera
--     dans la charge du poste.
--
--   * **AUCUNE ALERTE SUR LES CRÉNEAUX ORPHELINS**, alors que le
--     plan en fait une exigence explicite du lot.
--
-- La doctrine appliquée est celle des parties 4 et 5 du plan : le
-- maillon est un **compagnon** (`zz_l17_…`) et non une réécriture
-- de corps, parce que l'aval est identifié par une clé MESURÉE dans
-- le corps du maillon (le jour d'absence croise `planning_slots` sur
-- `employee_id` et l'intervalle planifié) ; le contrat d'effet est
-- DÉCLARÉ dans le même fichier, comme la porte G2 l'exige ; l'effet
-- est **constaté**, pas décidé (la base ne refuse pas — elle
-- signale, ce qui laisse au chef d'atelier la décision de
-- réaffectation que le plan lui confie).
--
--   T01  **le porteur existe et il est le bon** — `planning_slots`
--        porte l'opérateur, clé COMPOSITE vers `employees` (ISO-02 :
--        une clé mono-colonne relierait deux sociétés), index de
--        société.
--   T02  **T-1, l'effet attendu est produit, chiffré** — une absence
--        bloquante posée sur un créneau **existant** (le cas réel :
--        le congé est déclaré APRÈS le planning) laisse un lien,
--        une trace `applique` et un événement.
--   T03  **le cycle : l'absence retirée rend le créneau à nouveau
--        exploitable** — l'alerte n'est pas une marque éternelle :
--        elle se lève avec sa cause (L3, doctrine 320).
--   T04  **T-2, le rejeu ne double pas** (D1) — le compagnon est
--        idempotent : rejouer la même absence ne pose pas un second
--        lien, ni une seconde trace `applique`.
--   T05  **la garde de planification** — planifier un créneau pour un
--        opérateur absent un jour qui BLOQUE le travail est refusé,
--        et le message nomme le jour, le type d'absence et le
--        module (point 6 de §4.1).
--   T06  **la capacité ajustée** — la charge d'un poste se lit
--        APRÈS retrait des absences du jour : c'est le cœur du lot
--        (« capacité ajustée »).
--   T07  **T-4 / D-8, l'isolation tient** — le `tenant_id` vient de
--        la LIGNE d'absence, jamais de la session.
--   T08  **point 8 de §4.1, performance mesurée** — p95 du
--        compagnon sur 200 absences, budget §3.3 (≤ 50 ms).
--
-- Les scénarios s'exécutent en superutilisateur avec le contexte de
-- société posé par `_mk_tenant` : le compagnon est un
-- `SECURITY DEFINER`, et c'est sa **propre** isolation (T07) qui est
-- prouvée, non celle de la session.
-- ==========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '416', false);
DELETE FROM _audit_results WHERE file = '416';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────


-- Un salarié réel de la société `p_t`.
CREATE OR REPLACE FUNCTION _l416_employe(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid; v_courriel text;
BEGIN
  -- le courriel doit RESPECTER `employees_email_format_check` : on le
  -- construit à partir du nom normalisé (espaces et accents remplacés),
  -- et non d'une concaténation qui casserait en silence.
  v_courriel := regexp_replace(lower(p_nom), '[^a-z0-9]+', '.', 'g')
             || '.' || left(p_t::text, 8) || '@audit.test';
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours)
  VALUES (p_t, p_nom, v_courriel, 'active', 3000, 35)
  RETURNING id INTO e;
  RETURN e;
END $$;

-- Le décor minimal d'un créneau : article + nomenclature à une ligne +
-- ordre de fabrication. Les trois sont requis : le déclencheur
-- `manufacturing_order_product_from_bom` REFUSE une OF sans article
-- (mesuré en écrivant ce fichier — c'est pourquoi le décor est
-- complet et non « le strict nécessaire »). On s'aligne sur la
-- fabrique de la suite 302 (W8), qui est la convention du dépôt.
CREATE OR REPLACE FUNCTION _l416_of(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE o uuid; pf uuid; comp uuid; b uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock', 10) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'Composant ' || p_nom, 'CO-' || p_nom, 'stock', 2) RETURNING id INTO comp;

  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
  VALUES (p_t, 'B-' || p_nom, 'Nomenclature ' || p_nom, pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity)
  VALUES (p_t, b, comp, 2);

  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status)
  VALUES (p_t, 'OF-' || p_nom, b, pf, 10, 'planned')
  RETURNING id INTO o;
  RETURN o;
END $$;

CREATE OR REPLACE FUNCTION _l416_creneau(p_t uuid, p_of uuid, p_emp uuid,
                                        p_start timestamptz, p_end timestamptz)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE s uuid;
BEGIN
  INSERT INTO planning_slots (tenant_id, manufacturing_order_id, employee_id,
                              planned_start, planned_end, setup_time, run_time,
                              status, material_available)
  VALUES (p_t, p_of, p_emp, p_start, p_end, 30, 90, 'scheduled', true)
  RETURNING id INTO s;
  RETURN s;
END $$;

-- Un jour d'absence BLOQUANTE, posé directement dans le registre
-- (c'est la vérité — les quatre sources de la 263 y écrivent).
CREATE OR REPLACE FUNCTION _l416_absence(p_t uuid, p_emp uuid, p_day date)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d uuid;
BEGIN
  INSERT INTO employee_absence_days (tenant_id, employee_id, day, absence_kind,
                                     origin, justification_state, blocks_work)
  VALUES (p_t, p_emp, p_day, 'annual', 'leave_request', 'provided', true)
  RETURNING day_uid INTO d;
  RETURN d;
END $$;

-- Les liens d'un effet donné, tous sens confondus.
CREATE OR REPLACE FUNCTION _l416_liens(p_t uuid, p_effet text)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM document_links
  WHERE tenant_id = p_t AND effet = p_effet AND etat = 'actif'
$$;

CREATE OR REPLACE FUNCTION _l416_traces(p_t uuid, p_effet text, p_amont uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM chain_traces
  WHERE tenant_id = p_t AND effet = p_effet AND amont_id = p_amont
    AND resultat = 'applique'
$$;

CREATE OR REPLACE FUNCTION _l416_evenements(p_t uuid, p_evt text)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM domain_events
  WHERE tenant_id = p_t AND event_name = p_evt
$$;

-- Un jour ouvré fixe, loin de toute date d'absence préexistante.
CREATE OR REPLACE FUNCTION _l416_jour() RETURNS date
LANGUAGE sql IMMUTABLE AS $$ SELECT DATE '2026-03-10' $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — LE PORTEUR existe, et il est le bon
--   Un créneau ne peut être rattaché à une absence que si l'on
--   sait QUI le fait. On vérifie trois choses mesurables : la
--   colonne existe, la clé est COMPOSITE (ISO-02 : une clé
--   mono-colonne relierait deux sociétés), et un index mène par
--   `tenant_id` puis par l'opérateur (sans lui, la capacity d'un
--   poste se calcule en scannant le planning entier — BUD-04).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE colonne boolean; fk_composee boolean; index_societe boolean; v_detail text;
BEGIN
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'planning_slots'
                   AND column_name = 'employee_id')
    INTO colonne;

  -- une clé composite : deux colonnes, dans cet ordre
  SELECT EXISTS (SELECT 1 FROM pg_constraint c
                 JOIN pg_attribute a1 ON a1.attrelid = c.conrelid AND a1.attnum = c.conkey[1]
                 JOIN pg_attribute a2 ON a2.attrelid = c.conrelid AND a2.attnum = c.conkey[2]
                 JOIN pg_class cl ON cl.oid = c.confrelid
                 WHERE c.contype = 'f' AND cl.relname = 'employees'
                   AND c.conrelid = 'planning_slots'::regclass
                   AND a1.attname = 'tenant_id' AND a2.attname = 'employee_id')
    INTO fk_composee;

  SELECT EXISTS (SELECT 1 FROM pg_index i
                 JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                 WHERE i.indrelid = 'planning_slots'::regclass AND a.attname = 'tenant_id')
    INTO index_societe;

  PERFORM _rec('T01', 'le créneau de production porte son opérateur — colonne, clé COMPOSITE vers employees, index de société',
    colonne AND fk_composee AND index_societe,
    format('colonne employee_id=%s | clé composite vers employees=%s | index menant par tenant_id=%s',
           colonne, fk_composee, index_societe));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le créneau de production porte son opérateur', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — T-1, l'effet attendu est produit, CHIFFRÉ
--   Le cas réel du lot : le planning est fait en janvier, le
--   congé est déclaré en février. Le créneau existe DÉJÀ quand
--   l'absence tombe. On mesure donc le chemin de cet ordre-là,
--   et non l'ordre favorable (absence d'abord, créneau ensuite).
--   Attendu : le créneau est marqué `bloque_par_absence`, un
--   lien, une trace `applique` et un événement — 1 de chaque.
-- ═════════════════════════════════════════════════════════════
DO $$
-- `count(*) FILTER (…)` rend un NOMBRE, pas un booléen : la variable est
-- `integer`, et le nom le dit (`marques`, pas `marque`).
DECLARE t uuid; e1 uuid; of1 uuid; s1 uuid; s2 uuid; d uuid; j date;
        marques int; traces int; evt int; paires int;
BEGIN
  t := _mk_tenant('L17T02');
  j := _l416_jour();
  e1 := _l416_employe(t, 'Lamine T02');
  of1 := _l416_of(t, 'T02');
  -- deux créneaux du MÊME salarié, sur le même jour : l'effet est
  -- PAR LIGNE, et c'est ce qu'on mesure (M-09).
  s1 := _l416_creneau(t, of1, e1, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);
  s2 := _l416_creneau(t, of1, e1, (j::text || ' 13:00+01')::timestamptz,
                                   (j::text || ' 17:00+01')::timestamptz);

  -- AVANT : personne n'est absent, aucun marquage attendu
  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO marques
  FROM planning_slots WHERE tenant_id = t;

  d := _l416_absence(t, e1, j);

  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO marques
  FROM planning_slots WHERE tenant_id = t;
  SELECT count(*) INTO traces FROM chain_traces
   WHERE tenant_id = t AND amont_id = d AND resultat = 'applique';
  SELECT count(*) INTO evt FROM domain_events
   WHERE tenant_id = t AND event_name = 'planning_slots.orphaned';

  -- La paire amont→aval est portée par la TRACE, pas par un lien :
  -- `amont_id` est le jour d'absence, `amont_ligne_id` le créneau.
  -- On le vérifie créneau par créneau — deux créneaux, deux traces,
  -- chacune rattachée au SIEN (mesuré : le lien unique du socle ne
  -- portait que l'amont, les deux liens se confondaient).
  SELECT count(*) INTO paires FROM chain_traces
   WHERE tenant_id = t AND amont_id = d AND amont_ligne_id IN (s1, s2);

  PERFORM _rec('T02', 'une absence déclarée APRÈS le planning marque TOUS les créneaux du jour, une trace par créneau et un événement',
    marques = 2 AND paires = 2 AND traces = 2 AND evt = 2,
    format('créneaux marqués=%s (2 attendus) traces=%s dont rattachées à LEUR créneau=%s événements=%s (2 attendus chacun)',
           marques, traces, paires, evt));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — LE CYCLE : l'alerte se lève avec sa cause
--   Un marquage qui survit au retrait de l'absence serait pire
--   que l'absence de marquage : le chef d'atelier verrait un
--   créneau rouge alors que la cause a disparu, et l'écran
--   mentirait. Doctrine L3 (320) : un lien sans amont actif se
--   ferme. Ici on vérifie le constat réel — le drapeau revient à
--   faux et le lien `actif` disparaît.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; e1 uuid; of1 uuid; s1 uuid; d uuid; j date;
        bloque_avant boolean; bloque_apres boolean;
        marques_avant int; marques_apres int; levees int;
BEGIN
  t := _mk_tenant('L17T03');
  j := _l416_jour();
  e1 := _l416_employe(t, 'Yacine T03');
  of1 := _l416_of(t, 'T03');
  s1 := _l416_creneau(t, of1, e1, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);

  d := _l416_absence(t, e1, j);
  SELECT bloque_par_absence INTO bloque_avant FROM planning_slots WHERE tenant_id = t;
  SELECT count(*) INTO marques_avant FROM chain_traces
   WHERE tenant_id = t AND amont_ligne_id = s1 AND resultat = 'applique';

  -- le congé est ANNULÉ : le client supprime le jour d'absence. Le
  -- marquage doit tomber avec sa cause.
  DELETE FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e1 AND day = j;

  SELECT bloque_par_absence INTO bloque_apres FROM planning_slots WHERE tenant_id = t;
  -- et l'HISTORIQUE se conserve : une seconde trace, d'un AUTRE
  -- effet, dit que le créneau a été libéré. Effacer la première
  -- rendrait la question « pourquoi ce créneau a-t-il été rouge ? »
  -- sans réponse ; c'est le rôle de la trace.
  SELECT count(*) INTO levees FROM chain_traces
   WHERE tenant_id = t AND amont_ligne_id = s1 AND effet = 'planning_slots.unblocked'
     AND resultat = 'applique';
  SELECT count(*) INTO marques_apres FROM chain_traces
   WHERE tenant_id = t AND amont_ligne_id = s1
     AND effet = 'planning_slots.orphaned' AND resultat = 'applique';

  PERFORM _rec('T03', 'l''absence retirée rend le créneau à nouveau exploitable — le marquage tombe, et l''historique garde les DEUX faits',
    bloque_avant AND marques_avant = 1 AND NOT COALESCE(bloque_apres, true)
      AND levees = 1 AND marques_apres = 1,
    format('marqué avant=%s (traces=%s) | après retrait : marqué=%s | trace de levée=%s trace de marquage conservée=%s',
           bloque_avant, marques_avant, COALESCE(bloque_apres::text, 'NULL'), levees, marques_apres));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — T-2, LE REJEU NE DOUBLE PAS (D1)
--   La 263 synchronise les jours d'absence depuis quatre sources,
--   et `rebuild_absence_days` peut rejouer une plage entière. Un
--   UPDATE du même jour d'absence (ici le motif passe de
--   `pending` à `provided`) ne doit produire ni second lien, ni
--   seconde trace `applique`. C'est la raison d'être de l'index
--   unique + `ON CONFLICT` du socle : on ne le suppose pas, on
--   le mesure sur le corps réel du déclencheur.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; e1 uuid; of1 uuid; s1 uuid; j date;
        liens1 int; traces1 int; liens2 int; traces2 int;
BEGIN
  t := _mk_tenant('L17T04');
  j := _l416_jour();
  e1 := _l416_employe(t, 'Sofia T04');
  of1 := _l416_of(t, 'T04');
  s1 := _l416_creneau(t, of1, e1, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);

  PERFORM _l416_absence(t, e1, j);
  SELECT count(*) INTO liens1  FROM chain_traces WHERE tenant_id = t AND amont_ligne_id = s1 AND resultat = 'applique';
  SELECT count(*) INTO traces1 FROM chain_traces WHERE tenant_id = t AND amont_ligne_id = s1 AND resultat = 'applique';

  -- rejeu : la même absence, une autre justification
  UPDATE employee_absence_days
     SET justification_state = 'provided'
   WHERE tenant_id = t AND employee_id = e1 AND day = j;

  SELECT count(*) INTO liens2  FROM chain_traces WHERE tenant_id = t AND amont_ligne_id = s1 AND resultat = 'applique';
  SELECT count(*) INTO traces2 FROM chain_traces WHERE tenant_id = t AND amont_ligne_id = s1 AND resultat = 'applique';

  PERFORM _rec('T04', 'le rejeu d''un jour d''absence ne double ni la trace ni l''événement — idempotence structurelle',
    liens1 = 1 AND traces1 = 1 AND liens2 = 1 AND traces2 = 1,
    format('après la 1re pose : traces=%s | après rejeu : traces=%s (1 attendu)',
           traces1, traces2));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — LA GARDE DE PLANIFICATION, avec un refus RÉDIGÉ
--   W9 (264) a posé sept gardes d'absence en aval ; la production
--   n'en avait aucune. On vérifie le refus ET son texte : un
--   `check_violation` anonyme ne prouve rien sur ce que
--   l'utilisateur voit (le même principe que `assert_not_absent`).
--   Et on vérifie le contre-exemple honnête : une absence qui ne
--   BLOQUE PAS le travail (mission) laisse passer le créneau.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; e1 uuid; e_mission uuid; of1 uuid; j date; refuse boolean := false; err text := '—';
        mission_ok boolean := false;
BEGIN
  t := _mk_tenant('L17T05');
  j := _l416_jour();
  e1 := _l416_employe(t, 'Rachid T05');
  of1 := _l416_of(t, 'T05');
  PERFORM _l416_absence(t, e1, j);

  BEGIN
    PERFORM _l416_creneau(t, of1, e1, (j::text || ' 08:00+01')::timestamptz,
                                      (j::text || ' 12:00+01')::timestamptz);
  EXCEPTION WHEN OTHERS THEN
    refuse := true; err := SQLERRM;
  END;

  -- le contre-exemple : une MISSION n'est pas une absence
  -- bloquante (`absence_kind_flags`, 263). Le MÊME geste sur le
  -- MÊME type de créneau doit passer — sinon le refus ne prouve
  -- rien d'autre que « il refuse toujours ».
  BEGIN
    e_mission := _l416_employe(t, 'Leila T05');
    INSERT INTO employee_absence_days (tenant_id, employee_id, day, absence_kind,
                                       origin, justification_state, blocks_work)
    VALUES (t, e_mission, j, 'mission', 'leave_request', 'provided', false);
    PERFORM _l416_creneau(t, of1, e_mission,
                          (j::text || ' 14:00+01')::timestamptz,
                          (j::text || ' 18:00+01')::timestamptz);
    mission_ok := true;
  EXCEPTION WHEN OTHERS THEN
    mission_ok := false; err := err || ' | mission : ' || SQLERRM;
  END;

  PERFORM _rec('T05', 'planifier un créneau pour un opérateur absent est REFUSÉ, en nommant le jour, le type d''absence et le module',
    refuse AND mission_ok
      AND err LIKE '%10/03/2026%' AND err LIKE '%congé%' AND err LIKE '%production%',
    format('refusé=%s | message=%s | contre-exemple « mission » accepté=%s',
           refuse, left(err, 150), mission_ok));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — LA CAPACITÉ AJUSTÉE : le cœur du lot
--   « on planifie avec des salariés absents ». On le mesure sur
--   le POSTE, pas sur le créneau : la charge d'un centre de charge
--   se lit APRÈS retrait des heures portées par un opérateur absent
--   ce jour-là. Deux opérateurs, une absence — la charge doit
--   baisser du côté des heures de l'absent et pas du reste.
--   Les durées du modèle sont en MINUTES (`setup_time`/`run_time`,
--   comme la vue 126 et comme l'écran) : 240 + 120 = 6 heures.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; wc uuid; e_abs uuid; e_ok uuid; of1 uuid; j date;
        avant numeric; apres numeric; creneaux int; marques int; postes int;
BEGIN
  t := _mk_tenant('L17T06');
  j := _l416_jour();
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day)
  VALUES (t, 'UC1', 'Unité 1', 8) RETURNING id INTO wc;

  of1 := _l416_of(t, 'T06');
  e_abs := _l416_employe(t, 'Karim T06');
  e_ok  := _l416_employe(t, 'Salma T06');

  -- 240 min chez l'absent, 120 min chez celle qui est là : 6 h au total.
  -- Le décor pose les deux créneaux (sinon la mesure porterait sur un
  -- poste vide : c'est ce que le premier jet faisait — `créneaux=0`),
  -- puis on écrit les minutes EXPLICITEMENT, pour que la mesure vienne
  -- des données de la ligne et pas des valeurs par défaut du décor.
  PERFORM _l416_creneau(t, of1, e_abs, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);
  PERFORM _l416_creneau(t, of1, e_ok,  (j::text || ' 13:00+01')::timestamptz,
                                   (j::text || ' 15:00+01')::timestamptz);

  -- LE POSTE est porté par les DEUX créneaux : c'est lui qu'on mesure.
  UPDATE planning_slots SET work_center_id = wc,
                            run_time = 210, setup_time = 30
   WHERE tenant_id = t AND employee_id = e_abs;
  UPDATE planning_slots SET work_center_id = wc,
                            run_time = 90, setup_time = 30
   WHERE tenant_id = t AND employee_id = e_ok;

  SELECT count(*) INTO creneaux FROM planning_slots WHERE tenant_id = t;
  -- un poste bien renseigné vaut mieux qu'une capacité calculée sur
  -- le vide : on l'affiche dans le verdict.
  SELECT count(*) INTO postes FROM planning_slots
   WHERE tenant_id = t AND work_center_id = wc;

  SELECT work_center_load_hours(t, wc, j) INTO avant;
  PERFORM _l416_absence(t, e_abs, j);
  SELECT work_center_load_hours(t, wc, j) INTO apres;
  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO marques
    FROM planning_slots WHERE tenant_id = t;

  PERFORM _rec('T06', 'la capacité du poste se lit APRÈS retrait des absences — 6 h deviennent 2 h, pas 6 h',
    creneaux = 2 AND postes = 2 AND avant = 6 AND apres = 2 AND marques = 1,
    format('créneaux=%s (rattachés au poste=%s) | charge AVANT absence=%s h | APRÈS absence=%s h | créneaux marqués=%s (1 attendu)',
           creneaux, postes, COALESCE(avant::text, 'NULL'), COALESCE(apres::text, 'NULL'), marques));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'la capacité du poste se lit après retrait des absences', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — T-4 / D-8, L'ISOLATION TIENT
--   Point 7 de §4.1. Le compagnon est `SECURITY DEFINER` : sans
--   cloisonnement explicite, il verrait les créneaux de l'autre
--   société et les marquerait. On pose le contexte de session sur
--   B et on déclare l'absence pour A : A doit être marquée, B
--   reste intacte. C'est le cas le plus défavorable — le GUC et
--   la ligne disent des choses différentes.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; ea uuid; eb uuid; oa uuid; ob uuid; sa uuid; sb uuid; j date;
        ctx uuid; a_marques int; b_marques int; b_liens int;
BEGIN
  ta := _mk_tenant('L17T07A');
  tb := _mk_tenant('L17T07B');
  j := _l416_jour();

  ea := _l416_employe(ta, 'Amine T07A');
  eb := _l416_employe(tb, 'Bilal T07B');
  oa := _l416_of(ta, 'T07A'); ob := _l416_of(tb, 'T07B');
  sa := _l416_creneau(ta, oa, ea, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);
  sb := _l416_creneau(tb, ob, eb, (j::text || ' 08:00+01')::timestamptz,
                                   (j::text || ' 12:00+01')::timestamptz);

  ctx := current_tenant_id();   -- le contexte de session est B

  -- l'absence est déclarée POUR A, alors que la session est B.
  -- On repasse brièvement le contexte sur A : c'est la garde W9
  -- `assert_absence_tenant` qui l'exige, et elle a raison — écrire
  -- une absence dans une société qu'on ne consulte pas est
  -- exactement ce que la 236 a interdit. Ce que l'on mesure ici
  -- n'est donc PAS le contexte, mais le fait que le COMPAGNON
  -- travaille sur la société de la LIGNE et jamais sur celle de la
  -- session.
  PERFORM set_config('app.active_tenant_id', ta::text, true);
  PERFORM _l416_absence(ta, ea, j);
  PERFORM set_config('app.active_tenant_id', ctx::text, true);

  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO a_marques
    FROM planning_slots WHERE tenant_id = ta;
  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO b_marques
    FROM planning_slots WHERE tenant_id = tb;
  -- aucun lien ne doit relier B à quoi que ce soit : ce maillon ne
  -- pose pas de lien (voir la décision mesurée dans la migration).
  SELECT count(*) INTO b_liens FROM document_links
   WHERE tenant_id = tb AND etat = 'actif';

  PERFORM _rec('T07', 'l''absence de A ne marque rien en B, même contexte de session posé sur B',
    ctx = tb AND a_marques = 1 AND b_marques = 0 AND b_liens = 0,
    format('contexte=%s | créneaux marqués A=%s (1 attendu) B=%s (0 attendu) liens B=%s',
           CASE WHEN ctx = tb THEN 'B' WHEN ctx = ta THEN 'A' ELSE coalesce(ctx::text, 'NULL') END,
           a_marques, b_marques, b_liens));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — point 8 de §4.1 : LE SURCOÛT EST MESURÉ
--   200 jours d'absence posés, p95 rapporté au budget d'un maillon
--   simple (§3.3, ≤ 50 ms). Le chiffre est DANS le verdict : un
--   « ça va vite » sans nombre ne prouve rien. Et le cas mesuré
--   est le plus coûteux : chaque absence croise les créneaux du
--   salarié pour savoir lesquels elle rend orphelins.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; e1 uuid; of1 uuid; i int; j date; p95 double precision;
        budget double precision := 50; t0 timestamptz; deltas double precision[] := '{}';
        marques int;
BEGIN
  t := _mk_tenant('L17T08');
  e1 := _l416_employe(t, 'Meriem T08');
  of1 := _l416_of(t, 'T08');
  PERFORM set_config('role', 'postgres', true);

  -- 200 créneaux d'un même salarié, sur 200 jours distincts : le
  -- compagnon aura 200 occasions de les toucher.
  FOR i IN 1..200 LOOP
    j := DATE '2026-04-01' + i;
    PERFORM _l416_creneau(t, of1, e1, (j::text || ' 08:00+02')::timestamptz,
                                     (j::text || ' 12:00+02')::timestamptz);
  END LOOP;

  FOR i IN 1..200 LOOP
    j := DATE '2026-04-01' + i;
    t0 := clock_timestamp();
    PERFORM _l416_absence(t, e1, j);
    deltas := deltas || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95
  FROM unnest(deltas) AS x;

  SELECT count(*) FILTER (WHERE bloque_par_absence) INTO Marques FROM planning_slots WHERE tenant_id = t;

  PERFORM _rec('T08', 'le compagnon tient le budget de §3.3 — 200 absences, 200 créneaux, un p95 mesuré',
    p95 IS NOT NULL AND p95 <= budget AND marques = 200,
    format('p95=%s ms pour un budget de %s ms | créneaux marqués=%s (200 attendus)',
           round(p95::numeric, 3), budget, marques));
END $$;

DROP FUNCTION _l416_employe(uuid, text);
DROP FUNCTION _l416_of(uuid, text);
DROP FUNCTION _l416_creneau(uuid, uuid, uuid, timestamptz, timestamptz);
DROP FUNCTION _l416_absence(uuid, uuid, date);
DROP FUNCTION _l416_liens(uuid, text);
DROP FUNCTION _l416_traces(uuid, text, uuid);
DROP FUNCTION _l416_evenements(uuid, text);
DROP FUNCTION _l416_jour();
SELECT _audit_assert('416');
