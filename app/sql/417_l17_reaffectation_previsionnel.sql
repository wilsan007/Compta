-- 417 — l17_reaffectation_previsionnel
-- Numéro pris le 2026-10-03T08:21:30.884Z par migration-numero.mjs (ligne « L16-L24 », branche partie-5-integrite-chainages).
-- ============================================================
-- 417_l17_reaffectation_previsionnel.sql — L17 (tranche 2) : LA
--   PROPOSITION DE RÉAFFECTATION et le PRÉVISIONNEL RH en sens
--   inverse — les deux exigences que la 416 a laissées ouvertes
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L17**, troisième et quatrième exigence :
-- « alerte sur les créneaux orphelins, **proposition de
-- réaffectation** ; à l'inverse, **une charge de production
-- planifiée apparaît dans le prévisionnel RH** ». La 416 a livré le
-- porteur, le constat, la garde et la capacité ajustée, et a dit
-- dans sa preuve (§6, points 2 et 3) que ces deux exigences
-- restaient entières. Elles sont livrées ici.
--
-- LE DÉFAUT, MESURÉ SUR BASE NEUVE (280 migrations, 0 erreur) :
--
--   1. **AUCUNE proposition de remplacement n'existe.** Mesuré : 0
--      fonction dont le nom porte « réaffect », « remplac »,
--      « candidat » ou « disponib ». La seule qui s'en approche est
--      `chain_lien_remplacer`, qui est le CYCLE DU LIEN du socle
--      (402) et n'a rien à voir. Le chef d'atelier voit donc un
--      créneau marqué « opérateur absent » — et rien pour l'aider.
--      La 416 a rendu le PROBLÈME visible ; elle n'a pas rendu la
--      SOLUTION possible.
--
--   2. **AUCUN prévisionnel RH ne lit la production.** Mesuré : 0
--      fonction de prévision ou de charge lit `planning_slots`. Le
--      sens inverse du couple est donc lui aussi vide.
--
--   3. **`employees.position` est un texte libre** : mesuré, aucune
--      contrainte sur la colonne. C'est le seul critère de
--      qualification qui existe entre un opérateur et un poste, et
--      il n'est pas qualifiant au sens fort. Cette migration le
--      DIT au lieu de le faire croire (§2).
--
-- CE QUE CETTE MIGRATION POSE — deux lectures, aucun schéma :
--
--   * `planning_slot_candidats(société, créneau)` — QUI PEUT PRENDRE
--     CE CRÉNEAU, du plus disponible au moins disponible, chacun avec
--     son MOTIF. Trois filtres, tous mesurables :
--       (a) actif ;
--       (b) **absent ce jour-là avec une absence bloquante** — le
--           filtre qui manque le plus : sans lui, on remplace un
--           absent par un autre absent ;
--       (c) **même `position`** que l'opérateur absent.
--     Ordonné par charge du jour croissante : proposer d'abord celui
--     qui est déjà saturé serait proposer le pire.
--
--   * `employee_planned_load(société, salarié, du, au)` — la charge
--     de production planifiée, en heures. Les créneaux que l'absence
--     a bloqués en sont RETIRÉS : on ne prévisionne pas du travail
--     que personne ne peut faire.
--
-- AUCUNE ÉCRITURE, AUCUNE COLONNE, AUCUN DÉCLENCHEUR. Cette
-- migration ne fait que LIRE, et le dit. La réaffectation elle-même
-- est déjà possible depuis la 416 : il suffit d'écrire le nouvel
-- `employee_id` sur le créneau, et la garde rejoue. Cette migration
-- rend la DÉCISION faisable ; elle ne la prend pas — comme le veut
-- le plan, qui confie la réaffectation au chef d'atelier.
--
-- ============================================================
-- ─────────────────────────────────────────────────────────────
-- 1. LA PROPOSITION DE RÉAFFECTATION
--
--    Qui peut prendre ce créneau ? Trois filtres, et le troisième
--    est celui qui décide de tout :
--
--    (a) L'OPÉRATEUR ABSENT EST-IL QUALIFIÉ ? On lit sa `position`.
--        Mesuré : c'est un TEXTE LIBRE (aucune contrainte). Deux
--        conséquences, et la fonction les applique :
--          * si elle est VIDE, on ne renvoie PERSONNE — pas les 40
--            employés de la société. Une liste sans critère est une
--            liste sans information (T04) ;
--          * l'égalité est une égalité de texte. « Tourneur » et
--            « tourneur » ne se rejoignent pas. On ne normalise
--            PAS : normaliser ici supposerait une convention
--            d'écriture que la base ne possède pas. C'est une
--            LIMITE, elle est dite dans la fonction.
--
--    (b) LE CANDIDAT EST-IL LUI MÊME ABSENT ? Non — jamais.
--        C'est le registre d'absences (263) qui fait foi, et on
--        pose la question au jour du CRÉNEAU, pas au jour de la
--        lecture : un candidat absent dans trois jours n'est pas un
--        candidat indisponible aujourd'hui.
--
--    (c) L'ORDRE EST UNE DÉCISION. Du moins chargé au plus chargé
--        sur la journée. Proposer d'abord celui qui est déjà
--        saturé serait proposer le pire.
--
--    LA CHARGE DU JOUR se mesure sur `planning_slots` — la seule
--    vérité qui existe — et elle EXCLUT les créneaux bloqués par
--    une absence : on ne compte pas comme chargé un opérateur dont
--    le travail ne peut pas se faire.
--
--    ISOLATION (T06) : `SECURITY DEFINER` traverse la RLS, donc
--    l'appelant doit être membre de la société demandée — le
--    contrôle `tenant_users` × `auth.uid()` que la porte G4 exige
--    depuis qu'elle a refusé `work_center_load_hours` (416 §3.4).
--
--    UN CRÉNEAU INCONNU EST REFUSÉ, pas rendu vide : une liste
--    vide se lit « personne n'est disponible », ce qui est une
--    autre information que « ce créneau n'existe pas » (T07).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.planning_slot_candidats(
  p_tenant  uuid,
  p_slot    uuid
)
RETURNS TABLE (
  employee_id          uuid,
  nom                  text,
  qualification        text,
  charge_du_jour_min   numeric,
  motif                text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_creneau record;
  v_pos     text;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Proposition refusée : aucune société (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;

  -- l'appelant est-il membre de CETTE société ?
  IF auth.uid() IS NOT NULL
     AND session_user NOT IN ('postgres', 'service_role')
     AND NOT EXISTS (SELECT 1 FROM public.tenant_users tu
                      WHERE tu.tenant_id  = p_tenant
                        AND tu.auth_id    = auth.uid()
                        AND COALESCE(tu.status, 'active') = 'active') THEN
    RAISE EXCEPTION 'Proposition refusée : la société % ne vous est pas attribuée (garde de société, 236).', p_tenant
      USING ERRCODE = '42501';
  END IF;

  -- Le créneau doit EXISTER et être de CETTE société.
  SELECT s.id, s.employee_id, s.planned_start, s.work_center_id, s.manufacturing_order_id
    INTO v_creneau
    FROM public.planning_slots s
   WHERE s.id = p_slot AND s.tenant_id = p_tenant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposition de réaffectation refusée : le créneau % n''existe pas dans la société %.', p_slot, p_tenant
      USING ERRCODE = 'P0002';
  END IF;

  -- (a) la qualification requise : celle de l'opérateur à remplacer.
  --     Absente → AUCUN candidat. On ne devine pas qui sait faire quoi.
  --     `position` est un MOT RÉSERVÉ en SQL (l'opérateur `POSITION`) :
  --     en sortir le nom de la variable et de la colonne de retour est
  --     donc nécessaire, et le nom retenu dit ce que la colonne est.
  SELECT NULLIF(btrim(e.position), '') INTO v_pos
    FROM public.employees e
   WHERE e.id = v_creneau.employee_id AND e.tenant_id = p_tenant;

  IF v_pos IS NULL THEN
    RETURN;   -- aucun critère, donc aucune proposition
  END IF;

  RETURN QUERY
  WITH jour AS (
    SELECT v_creneau.planned_start::date AS d
  )
  SELECT c.id,
         c.name,
         c.position,
         COALESCE(charge.min, 0),
         -- le MOTIF : ce qui rend ce candidat PROPOSABLE. Une liste
         -- sans raison n'aide personne à décider (T01).
         format('Même qualification (%s), %s h déjà planifiées ce jour-là.',
                v_pos,
                round(COALESCE(charge.min, 0)::numeric / 60.0, 2))
    FROM public.employees c
    CROSS JOIN jour j
    LEFT JOIN LATERAL (
      -- la charge du jour, HORS créneaux que l'absence a bloqués
      SELECT sum(COALESCE(s2.setup_time, 0) + COALESCE(s2.run_time, 0)) AS min
        FROM public.planning_slots s2
       WHERE s2.tenant_id = p_tenant
         AND s2.employee_id = c.id
         AND s2.planned_start::date = j.d
         AND NOT COALESCE(s2.bloque_par_absence, false)
    ) charge ON true
   WHERE c.tenant_id = p_tenant
     AND c.id <> v_creneau.employee_id          -- pas l'absent lui-même
     AND c.status = 'active'
     AND NULLIF(btrim(c.position), '') = v_pos
     -- (b) ABSENT LE JOUR DU CRÉNEAU ? Jamais proposé.
     AND NOT EXISTS (SELECT 1 FROM public.employee_absence_days d
                      WHERE d.tenant_id = p_tenant
                        AND d.employee_id = c.id
                        AND d.day = j.d
                        AND d.blocks_work)
   ORDER BY COALESCE(charge.min, 0), c.name;   -- (c) le moins chargé d'abord
END $fn$;

COMMENT ON FUNCTION public.planning_slot_candidats(uuid, uuid) IS
  'L17/417 — QUI PEUT PRENDRE ce créneau : actif, présent ce jour-là (absent bloquant exclu), même `position` que l''opérateur à remplacer — et rendu du MOINS chargé au plus chargé, avec son motif. Si l''opérateur à remplacer ne porte aucune `position`, AUCUN candidat n''est rendu : on ne devine pas une qualification qui n''est pas écrite. `position` étant un texte libre, l''égalité est une égalité de texte (pas de normalisation). Un créneau inexistant est REFUSÉ, pas rendu vide.';

-- ============================================================
-- ─────────────────────────────────────────────────────────────
-- 2. LE PRÉVISIONNEL RH, EN SENS INVERSE
--
--    « à l'inverse, une charge de production planifiée apparaît
--    dans le prévisionnel RH ». Concrètement : combien d'heures de
--    production sont planifiées sur CE salarié, sur CETTE période ?
--
--    LA RÈGLE, et elle est le cœur de la fonction : les créneaux
--    que l'absence a bloqués en sont **RETIRÉS**. On ne prévisionne
--    pas du travail que personne ne peut faire — sinon le
--    prévisionnel RH mentirait sur la disponibilité de la personne,
--    exactement comme `v_work_center_load` mentait sur la capacité
--    du poste (défaut mesuré en 416 §1).
--
--    L'INVERSE DE `work_center_load_hours` (416), et c'est
--    volontaire : les deux se lisent ensemble. La capacité d'un poste
--    et la charge d'une personne sont les deux faces de la même
--    question, et il n'y a qu'une seule règle de retrait — celle du
--    constat `bloque_par_absence`, écrit UNE fois par le compagnon.
--
--    `p_from` et `p_to` sont BORNÉS par le créneau lu : un créneau
--    qui commence avant la période n'en compte que la fraction
--    Tombée dedans. C'est plus exact, et c'est plus cher à écrire ;
--    on le fait parce qu'un prévisionnel mensuel qui compterait des
--    heures de la veille serait faux.
--
--    ISOLATION (T06) : même garde que §1.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.employee_planned_load(
  p_tenant   uuid,
  p_employee uuid,
  p_from     date,
  p_to       date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_charge numeric;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Prévisionnel refusé : aucune société (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;

  IF auth.uid() IS NOT NULL
     AND session_user NOT IN ('postgres', 'service_role')
     AND NOT EXISTS (SELECT 1 FROM public.tenant_users tu
                      WHERE tu.tenant_id  = p_tenant
                        AND tu.auth_id    = auth.uid()
                        AND COALESCE(tu.status, 'active') = 'active') THEN
    RAISE EXCEPTION 'Prévisionnel refusé : la société % ne vous est pas attribuée (garde de société, 236).', p_tenant
      USING ERRCODE = '42501';
  END IF;

  -- Période vide : 0, pas d'erreur. Une période inversée est une
  -- faute de saisie de l'écran, pas une absence de donnée — on
  -- renvoie 0 et l'appelant peut l'afficher sans erreur.
  IF p_employee IS NULL OR p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RETURN 0;
  END IF;

  -- La charge = somme des minutes DÉCLARÉES, PROPORTIONNELLES à la
  -- fraction du créneau réellement tombée dans la période. Un créneau
  -- à cheval n'en compte que sa part — un prévisionnel mensuel qui
  -- compterait des heures de la veille serait faux.
  --
  -- On lit la durée RÉELLE (planned_end − planned_start) comme
  -- dénominateur, et les minutes DÉCLARÉES (run_time + setup_time)
  -- comme numérateur : c'est le seul endroit du dépôt où les deux
  -- coexistent, et la 416 a déjà tranché pour le créneau entier.
  WITH bornes AS (
    SELECT COALESCE(s.run_time, 0) + COALESCE(s.setup_time, 0) AS minutes_total,
           EXTRACT(EPOCH FROM (
             COALESCE(s.planned_end, s.planned_start)
             - COALESCE(s.planned_start, s.planned_end)
           )) AS secondes_total,
           -- la part du créneau réellement DANS la période, en
           -- secondes. `EXTRACT` est indispensable : la soustraction
           -- de deux `timestamptz` donne un INTERVAL, pas un nombre.
           EXTRACT(EPOCH FROM (
             LEAST(COALESCE(s.planned_end, s.planned_start), (p_to + 1)::timestamptz)
           - GREATEST(COALESCE(s.planned_start, s.planned_end), p_from::timestamptz)
           )) AS secondes_dans
      FROM public.planning_slots s
     WHERE s.tenant_id   = p_tenant
       AND s.employee_id = p_employee
       AND s.planned_start::date BETWEEN p_from AND p_to
       -- le retrait : ce que l'absence rend inexploitable ne se
       -- prévisionne pas. Même constat que §1 et que la capacité.
       AND NOT COALESCE(s.bloque_par_absence, false)
       -- un créneau qui se termine avant la période ne compte rien,
       -- et un créneau entièrement après non plus
       AND COALESCE(s.planned_end, s.planned_start) > p_from::timestamptz
       AND COALESCE(s.planned_start, s.planned_end) < (p_to + 1)::timestamptz
  )
  -- `NULLIF(0, 0)` : un créneau sans durée (début = fin) ne peut pas
  -- être réparti ; ses minutes DÉCLARÉES comptent entières, sinon un
  -- créneau planifié à l'instant exact serait perdu du prévisionnel.
  SELECT COALESCE(sum(
           CASE WHEN COALESCE(secondes_total, 0) <= 0
                THEN minutes_total
                ELSE minutes_total * secondes_dans / secondes_total
           END), 0) / 60.0
    INTO v_charge
  FROM bornes;

  RETURN v_charge;
END $fn$;

COMMENT ON FUNCTION public.employee_planned_load(uuid, uuid, date, date) IS
  'L17/417 — charge de PRODUCTION planifiée sur un salarié, en heures, sur une
  période : le sens inverse du couple `production ↔ RH`. Les créneaux que
  l''absence a bloqués en sont RETIRÉS — on ne prévisionne pas du travail que
  personne ne peut faire. Bornée au créneau lu : un créneau à cheval ne
  compte que sa fraction dans la période. 0 pour un salarié inconnu, une
  période vide ou inversée : jamais d''exception pour une absence de donnée.';
-- ============================================================
-- 3. LES DROITS — la porte `check_anon_grants` a vu rouge, et elle
--    avait raison
--
--    Une fonction créée l'est avec EXECUTE pour `PUBLIC`, donc un
--    visiteur NON connecté pouvait appeler les deux lectures. Ce
--    n'était pas une question de style : les deux traversent la RLS
--    (`SECURITY DEFINER`) et l'une d'elles rend la charge de
--    production d'un salarié — une donnée de planning.
--
--    Elles sont révoquées à `PUBLIC` et `anon`, et accordées à
--    `authenticated` + `service_role` : ce sont des lectures
--    d'écran. Même convention que `work_center_load_hours` (416 §8),
--    et c'est exactement pour cela que la porte existe.
-- ============================================================
REVOKE ALL ON FUNCTION public.planning_slot_candidats(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.planning_slot_candidats(uuid, uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.employee_planned_load(uuid, uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_planned_load(uuid, uuid, date, date) TO authenticated, service_role;
