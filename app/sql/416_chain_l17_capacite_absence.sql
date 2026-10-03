-- ============================================================
-- 416_chain_l17_capacite_absence.sql — L17 (tranche 1) : LE
--   PLANNING DE PRODUCTION CONNAÎT L'ABSENCE — le porteur, la
--   garde, l'alerte sur créneaux orphelins, la capacité ajustée
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L17** (« Production ↔ RH (capacité ↔ absence) »),
-- et le référentiel §A.4, où `production ↔ RH` est l'un des **12
-- couples de modules VIDE** : « la capacité de production ne
-- connaît pas l'absence : on planifie avec des salariés absents —
-- le cas d'usage fondateur de tout ce travail ». Dépendance du lot
-- : **L11** (`employee_absence_days`, 263) ✅.
--
-- LE DÉFAUT, MESURÉ SUR BASE NEUVE (273 migrations, 0 erreur) :
--
--   1. **LE PORTEUR N'EXISTE PAS.** `planning_slots` — la table du
--      planning de production, lue et écrite par l'écran
--      `PlanningPage.tsx` — ne porte AUCUNE colonne d'opérateur :
--      mesuré, 0 colonne parmi `employee_id` / `operator_id` /
--      `assigned_to`. Un créneau ne sait pas QUI le fait. Sans
--      porteur, il n'y a rien à quoi rattacher une absence : le
--      couple n'est pas incomplet, il est IMPOSSIBLE.
--   2. **ZÉRO lecture croisée.** Mesuré : **0** fonction de la base
--      lit à la fois `planning_slots` et `employee_absence_days`.
--   3. **LA CAPACITÉ EST UNE CONSTATATION MUETTE.** `v_work_center_load`
--      (126) — la seule chose qui compare une charge à une capacité
--      — compare à un `capacity_hours_per_day` THÉORIQUE. Mesuré :
--      le texte de la vue ne contient pas « absence ». Un poste peut
--      afficher « normal » le jour où la moitié de l'équipe est
--      absente : un calcul FAUX affiché comme vrai, ce qui est pire
--      que l'absence de capacité.
--   4. **AUCUNE GARDE.** W9 (264) a posé sept gardes d'absence en
--      aval. La production n'en a AUCUNE : on planifie un créneau
--      pour un absent, et il reste `scheduled` — donc l'ordonnanceur
--      le compte dans la charge du poste.
--
-- CE QUE CETTE MIGRATION POSE :
--
--   * `planning_slots.employee_id` — LE PORTEUR, clé **COMPOSITE**
--     `(tenant_id, employee_id)` vers `employees` : une clé
--     mono-colonne relierait deux sociétés (ISO-02, 237/249), et la
--     porte `check_composite_fks` l'interdit. Index
--     `(tenant_id, employee_id)` : sans lui, « les créneaux de cet
--     opérateur ce jour-là » scanne le planning entier (BUD-04).
--   * `planning_slots.bloque_par_absence` — le CONSTAT, lisible par
--     l'écran sans recalcul. Il ne décide pas : il dit.
--   * `guard_planning_slot_on_absence()` — la garde de planification,
--     sur le modèle EXACT de `guard_task_assignee_on_absence` (264) :
--     elle appelle `assert_not_absent`, qui nomme déjà le jour, le
--     type d'absence, l'origine et la dérogation possible. On ne
--     réécrit pas un second « refus d'absence ».
--   * `work_center_load_hours(société, poste, jour)` — LA CAPACITÉ
--     AJUSTÉE : la charge réelle du poste, heures des opérateurs
--     absents RETIRÉES. `0` si le poste est inconnu, `0` si la date
--     est nulle : une capacité inventée serait pire que l'absence de
--     capacité.
--   * `chain_l17_constater_absence()` + `zz_l17_absence_creneau` —
--     le COMPAGNON (doctrine 310 : l'aval est identifié par une clé
--     MESURÉE dans le corps du maillon, ici `(employee_id`, jour)`.
--     Il s'exécute sur l'absence parce que c'est elle qui arrive en
--     SECOND : le planning est fait en janvier, le congé en février.
--     Pour chaque créneau devenu inexploitable il pose le lien, la
--     trace et l'événement. Il se déclenche aussi sur le DELETE et
--     sur l'UPDATE de `blocks_work` : l'alerte se LÈVE avec sa
--     cause (L3, 320) — un marquage qui survit à l'annulation du
--     congé ferait mentir l'écran.
--   * `chain_l17_relever_absence()` — le lever de drapeau, appelé
--     par le même compagnon. `document_links` n'est pas écrit par
--     là : le lien se pose à l'INSERT et se ferme par le cycle
--     (`chain_lien_fermer`, 402), ce qui est déjà fait — le lever ne
--     fait que remettre le drapeau local à zéro, ce qui est
--     PRÉCISÉMENT la partie qui manquait.
--
-- LA NON-RÉVERSIBILITÉ EST DÉCLARÉE (point 4 de §4.1) : l'alerte
-- n'a pas d'effet inverse « à rejouer » — elle se constate, et le
-- cycle la referme quand la cause disparaît. C'est dit ici plutôt
-- que souffert.
--
-- REJOUABLE : colonnes `IF NOT EXISTS`, clés `DROP` puis `ADD`,
-- index `IF NOT EXISTS`, fonctions `CREATE OR REPLACE`, déclencheurs
-- `DROP` avant `CREATE`, contrat par `ON CONFLICT DO NOTHING`.
--
-- ⚠️ NON-RÉGRESSION : `planning_slots` reste lue/écrite par le
-- front (7 appels dans `stock.ts`) — la colonne est NULLABLE et la
-- clé `ON DELETE SET NULL`, donc un créneau sans opérateur continue
-- de s'enregistrer et de s'afficher. `v_work_center_load` n'est pas
-- touchée (elle n'est lue par personne : mesuré, 0 fonction) ; la
-- capacité ajustée est une fonction NOUVELLE, donc aucun écran ne
-- change de comportement le jour de cette migration.
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- 1. LE PORTEUR — `planning_slots.employee_id`
--    Nullable : un créneau historique, ou créé par l'écran avant
--    cette migration, n'a pas d'opérateur. On ne le déduit pas,
--    on ne l'invente pas — une colonne NOT NULL ou un défaut
--    calculé Mentirait sur des milliers de lignes.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.planning_slots
  ADD COLUMN IF NOT EXISTS employee_id uuid;

-- Le CONSTAT, lisible par l'écran sans recalcul (§3.2 : écrire
-- une fois). `false` par défaut : l'absence d'un opérateur comme
-- l'absence d'une absence sont deux états distincts.
ALTER TABLE public.planning_slots
  ADD COLUMN IF NOT EXISTS bloque_par_absence boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.planning_slots.employee_id IS
  'L17/416 — l''opérateur du créneau. C''est le PORTEUR qui rend le couple `production ↔ RH` possible : sans lui, aucun jour d''absence ne peut être rattaché à un créneau. NULL = créneau non attribué (historique ou saisi sans opérateur).';
COMMENT ON COLUMN public.planning_slots.bloque_par_absence IS
  'L17/416 — CONSTAT : l''opérateur du créneau est absent ce jour-là, avec une absence qui BLOQUE le travail. Le créneau reste planifié (la base ne l''annule pas : la réaffectation est une décision du chef d''atelier, que le plan lui confie), mais il ne doit plus compter dans la capacité du poste. Revient à `false` dès que la cause disparaît.';

-- Clé COMPOSITE (ISO-02) et ON DELETE SET NULL : un salarié
-- supprimé ne doit pas emporter le planning de l'atelier.
ALTER TABLE public.planning_slots
  DROP CONSTRAINT IF EXISTS planning_slots_employee_id_fkey;
ALTER TABLE public.planning_slots
  ADD CONSTRAINT planning_slots_employee_id_fkey
  FOREIGN KEY (tenant_id, employee_id)
  REFERENCES public.employees (tenant_id, id)
  ON DELETE SET NULL (employee_id);

-- L'index de la question que la base pose sans cesse : « les
-- créneaux de CE salarié, CE jour ». L'ordre (tenant_id,
-- employee_id) sert aussi la porte G1 (index menant par société).
CREATE INDEX IF NOT EXISTS idx_planning_slots_employee
  ON public.planning_slots (tenant_id, employee_id);

-- ─────────────────────────────────────────────────────────────
-- 2. LE CONTRAT D'EFFET — déclaré ICI, comme la porte G2 l'exige
--    depuis le lot L7 (313). Le couple est
--    `(planning_slots, absent, planning_slots.orphaned)`.
--
--    RÉVERSIBLE : l'inverse existe et il est exercised par le
--    compagnon lui-même — le retrait de l'absence remet le
--    drapeau à `false` (T03). On ne déclare donc pas un effet
--    sans issue, ce que le point 4 de §4.1 interdit.
--
--    `obligatoire = false` : l'alerte est un CONSTAT, pas une
--    production obligatoire. Un créneau sans opérateur n'a rien à
--    être marqué, et cela doit rester possible.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                               ecrit_comptable, journal_code, touche_stock, touche_paie,
                               reversible, obligatoire, actif, note)
VALUES (NULL, 'planning_slots', 'absent', 'planning_slots.orphaned',
        false, NULL, false, false,
        true, false, true,
        'L17/416 : le planning de production constate qu''un jour d''absence rend un créneau inexploitable. RÉVERSIBLE : le retrait de l''absence (ou le passage de `blocks_work` à faux) remet `planning_slots.bloque_par_absence` à faux par le même compagnon — T03 le mesure. L''alerte ne décide pas : le créneau reste planifié, c''est le chef d''atelier qui réaffecte, comme le veut le plan du lot L17. Le lien est au NIVEAU DU CRÉNEAU et non de l''ordre de fabrication, parce qu''une même absence peut rendre orphelins deux créneaux d''une même OF, et un seul sans toucher l''autre.')
ON CONFLICT DO NOTHING;

-- LE LEVER est un SECOND effet, et il est déclaré comme tel : deux
-- faits, deux entrées. Le confondre avec le marquage rendrait la
-- trace illisible — « ce créneau a été marqué » et « ce créneau a
-- été libéré » ne se lisent pas de la même façon.
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                               ecrit_comptable, journal_code, touche_stock, touche_paie,
                               reversible, obligatoire, actif, note)
VALUES (NULL, 'planning_slots', 'absent', 'planning_slots.unblocked',
        false, NULL, false, false,
        true, false, true,
        'L17/416 : le lever du constat — le jour d''absence qui rendait un créneau inexploitable a été retiré (annulation du congé, ou passage en « mission », qui ne bloque pas le travail). RÉVERSIBLE par construction : c''est l''effet inverse du marquage, et il ne s''applique qu''à un créneau effectivement marqué. Écrit par `chain_trace`, pas par `chain_apres` : il n''y a pas de durée à mesurer sur un simple UPDATE.')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 3. LA CAPACITÉ AJUSTÉE — la lecture qui manquait
--
--    La charge RÉELLE d'un centre de charge pour un jour : la
--    somme des heures de ses créneaux, MINUS celles portées par
--    un opérateur absent ce jour-là avec une absence bloquante.
--
--    DEUX DÉCISIONS, DITES ICI PARCE QU'ELLES SONT JUGÉES :
--
--    * **Quel jour regarde-t-on pour un créneau ?** `planned_start`
--      — le jour où le travail COMMENCE. Un créneau qui déborde sur
--      la nuit porte son début à J : c'est J qui décide s'il peut
--      démarrer. La fin n'est pas regardée : le cas d'un créneau
--      qui commence avant 8 h et finit après 18 h un jour de congé
--      est réel mais marginal, et le traiter ici demanderait de
--      décider d'une convention d'horaires que la base ne possède
--      pas. C'est une LIMITE, elle est écrite ici pour que la
--      tranche 2 sache qu'elle reste à traiter.
--    * **Que vaut un poste inconnu ou une date nulle ?** `0`. Une
--      capacité inventée serait pire que l'absence de capacité : un
--      `NULL` se voit, un `8` se prend pour un fait.
--
--    SECURITY DEFINER : elle traverse la RLS pour lire les créneaux
--    d'un centre de charge. L'isolation est donc EXPLICITE à deux
--    niveaux, et c'est ce que la porte G4 (`check_tenant_guard`) exige
--    d'une fonction exposée :
--      * le `tenant_id` vient de l'ARGUMENT et il est réécrit dans la
--        requête — jamais du GUC ;
--      * et l'appelant doit être MEMBRE de cette société : sans ce
--        second contrôle, un utilisateur de A passerait B en
--        argument et lirait la charge d'un poste qui n'est pas le
--        sien. Mesuré : c'est exactement ce que la porte a refusé
--        quand la fonction n'en nommait qu'un des deux.
--    Le membre se vérifie par `tenant_users` CROISÉ AVEC `auth.uid()` —
--    c'est la seconde forme que la porte G4 reconnaît
--    (`corps ~ 'tenant_users' AND corps ~ 'auth\.uid\s*\('`), et c'est
--    aussi la plus lisible : elle dit « l'utilisateur connecté est-il
--    inscrit dans cette société ? », ce que `current_tenant_id()`
--    ne répond pas (il répond « quelle société la session
--    consulte-t-elle ? », ce n'est pas la même question). Mesuré :
--    la porte refuse une fonction qui écrit `p_tenant` sans l'un
--    des deux contrôles, même si le comportement est déjà correct.
--    `service_role` et un superutilisateur passent — un rapport
--    inter-sociétés est un usage réel.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.work_center_load_hours(
  p_tenant       uuid,
  p_work_center  uuid,
  p_day          date
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
  -- Cloisonnement fermé : sans société, il n'y a pas de capacité à lire.
  IF p_tenant IS NULL THEN
    RETURN 0;
  END IF;

  -- L'appelant est-il membre de CETTE société ? Sans ce contrôle, un
  -- utilisateur de A passe B en argument et lit la charge d'un poste
  -- qui n'est pas le sien : le `SECURITY DEFINER` passerait la RLS
  -- pour lui. C'est le trou que la 236 a fermé partout ailleurs.
  IF auth.uid() IS NOT NULL
     AND session_user NOT IN ('postgres', 'service_role')
     AND NOT EXISTS (SELECT 1 FROM public.tenant_users tu
                      WHERE tu.tenant_id  = p_tenant
                        AND tu.auth_id    = auth.uid()
                        AND COALESCE(tu.status, 'active') = 'active') THEN
    RAISE EXCEPTION 'Lecture refusée : la société % ne vous est pas attribuée (garde de société, 236).', p_tenant
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE((
    SELECT sum(COALESCE(s.setup_time, 0) + COALESCE(s.run_time, 0))::numeric / 60.0
    FROM public.planning_slots s
    WHERE s.tenant_id      = p_tenant
      AND s.work_center_id = p_work_center
      AND s.planned_start::date = p_day
      -- le retrait : ce que l'absence rend inexploitable ne
      -- charge pas le poste. `bloque_par_absence` est le CONSTAT
      -- posé par le compagnon — on ne le recalcule pas ici, sinon
      -- deux moteurs pour une même vérité (la faute W5).
      AND NOT COALESCE(s.bloque_par_absence, false)
  ), 0) INTO v_charge;

  RETURN v_charge;
END $fn$;

COMMENT ON FUNCTION public.work_center_load_hours(uuid, uuid, date) IS
  'L17/416 — charge RÉELLE d''un centre de charge pour un jour, heures des opérateurs absents RETIRÉES. 0 si le poste est inconnu ou la date nulle : on ne renvoie jamais une capacité inventée. Le jour regardé est `planned_start::date` (le jour où le travail commence) — une convention d''horaires de nuit reste à traiter (tranche 2).';

-- ─────────────────────────────────────────────────────────────
-- 4. LA GARDE DE PLANIFICATION
--    Le modèle est celui de `guard_task_assignee_on_absence` (264) :
--    on appelle `assert_not_absent`, qui sait déjà nommer le jour,
--    le type d'absence, l'origine et l'échappatoire (une
--    dérogation validée dans `approval_workflows`). Écrire un
--    second refus d'absence serait exactement la faute W5 (plusieurs
--    moteurs pour une même grandeur) — et le test T05 le prouve :
--    le message contient « 10/03/2026 », « congé » et « production ».
--
--    QUEL JOUR EST REGARDÉ : `planned_start::date`, comme dans la
--    capacité ajustée (§3) — une seule convention dans tout le lot,
--    et elle est écrite.
--
--    Elle est rejouée sur l'UPDATE de l'opérateur et de la date de
--    début : déplacer un créneau sur un jour de congé doit être
--    refusé au même titre que de le créer ainsi.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_planning_slot_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF NEW.employee_id IS NULL OR NEW.planned_start IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM assert_not_absent(NEW.employee_id,
                            NEW.planned_start::date,
                            'planification d''un créneau de production');
  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.guard_planning_slot_on_absence() IS
  'L17/416 — un créneau de production ne se planifie pas pour un opérateur absent un jour qui bloque le travail. Délègue entièrement à `assert_not_absent` (W9) : ni le message ni l''échappatoire (dérogation validée) ne sont réécrits ici.';

DROP TRIGGER IF EXISTS guard_planning_slot_on_absence ON public.planning_slots;
CREATE TRIGGER guard_planning_slot_on_absence
  BEFORE INSERT OR UPDATE OF employee_id, planned_start
  ON public.planning_slots
  FOR EACH ROW EXECUTE FUNCTION public.guard_planning_slot_on_absence();

-- ─────────────────────────────────────────────────────────────
-- 5. LE COMPAGNON — `chain_l17_constater_absence`
--
--    DOCTRINE 310 : l'aval est identifié par une clé MESURÉE dans
--    le corps du maillon — ici `(tenant_id, employee_id, jour)`. Le
--    compagnon s'accroche donc à l'ABSENCE, et non au créneau.
--    Et c'est le bon côté : le cas réel du lot est l'absence qui
--    arrive EN SECOND (planning fait en janvier, congé déclaré en
--    février). Un déclencheur sur `planning_slots` ne verrait jamais
--    ce cas.
--
--    UNE SEULE FONCTION, DEUX SENS :
--      * `p_marquer = true`  → le créneau devient orphelin ;
--      * `p_marquer = false` → le constat se LÈVE (congé annulé,
--        ou passé en « mission », qui ne bloque pas le travail).
--    Le second sens est le CYCLE : sans lui, le drapeau survivrait
--    à sa cause et l'écran mentirait (T03).
--
--    IDEMPOTENCE : elle est STRUCTURELLE, pas conditionnelle. La boucle ne
--    retient que les créneaux dont l'état est OPPOSÉ à la demande
--    (`bloque_par_absence <> p_marquer`), donc un rejeu du même jour
--    d'absence ne trouve plus rien à faire : ni seconde trace, ni
--    second événement (T04) — mesuré, pas supposé.
--
--    LE CAS ORDINAIRE NE SE TRACE PAS (retenue de la tranche 5 de
--    L1) : une absence qui ne touche AUCUN créneau n'est pas un
--    manque, c'est le silence normal. Elle ne pose ni trace ni
--    événement. Seuls les créneaux réellement concernés le sont,
--    un par un.
--
--    ⚠️ POURQUOI AUCUN `document_links` — DÉCISION MESURÉE, PAS OMISSION.
--    La session Partie 5 a fait du lien une opération VÉRIFIÉE (451) :
--    `link_documents` refuse un type absent du registre
--    `chain_document_types`, et la suite 450 fige ce registre à 27
--    types. Inscrire `employee_absence_days` et `planning_slots`
--    aurait cassé deux choses qui ne sont pas à moi :
--      * la suite 450 (T01, T11) exige 27 types et 32 gardes ;
--      * surtout, la garde de suppression (453) sur
--        `employee_absence_days` EMPÊCHERAIT `rebuild_absence_days`
--        (263, ligne 349) de faire son travail : cette fonction
--        SUPPRIME les jours d'absence pour les recalculer. Une garde
--        qui refuse la suppression dès qu'un créneau est lié casserait
--        la reconstruction de l'absence — une régression dans un module
--        que cette migration ne possède pas.
--    Le lien est donc porté par ce qui est fait pour ça : la TRACE.
--    `chain_traces` reçoit `(effet, amont_type = employee_absence_days,
--    amont_id = day_uid, amont_ligne_id = slot_id)` — soit exactement
--    la paire amont→aval, avec sa durée et son message, et elle est
--    stable : elle survit à la suppression du jour d'absence, ce
--    qu'un lien ne ferait pas ici. L'invariant INV-19 (aucun aval
--    orphelin) reste vrai PAR CONSTRUCTION : aucun lien n'est posé,
--    donc aucun lien ne peut rester actif vers un amont disparu.
--
--    L'EFFET EST CONSTÉ, PAS DÉCIDÉ : on marque, on n'annule pas.
--    La réaffectation appartient au chef d'atelier (plan du lot).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l17_constater_absence(
  p_tenant    uuid,
  p_absence   employee_absence_days,
  p_marquer   boolean
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_creneau record;
  v_debut   timestamptz;
  v_lignes  integer := 0;
BEGIN
  -- Cloisonnement fermé : un jour d'absence sans société n'entre pas
  -- dans la chaîne (même garde que `emit_domain_event`, 252).
  IF p_tenant IS NULL OR p_absence.tenant_id IS NULL THEN
    RETURN 0;
  END IF;
  -- La société vient de l'ARGUMENT ET de la ligne : si elles ne
  -- concordent pas, c'est une tentative de passage en force.
  IF p_tenant <> p_absence.tenant_id THEN
    RETURN 0;
  END IF;

  FOR v_creneau IN
    SELECT s.id, s.manufacturing_order_id
    FROM public.planning_slots s
    WHERE s.tenant_id    = p_tenant
      AND s.employee_id  = p_absence.employee_id
      AND s.planned_start::date = p_absence.day
      AND COALESCE(s.bloque_par_absence, false) <> p_marquer
    ORDER BY s.id
  LOOP
    IF NOT p_marquer THEN
      -- LE LEVER. On remet le CONSTAT à zéro : la cause a disparu,
      -- l'écran doit le voir. Il n'y a aucun lien à refermer ici —
      -- voir la décision mesurée en tête de cette section.
      --
      -- La TRACE, elle, n'est jamais effacée : elle reste l'historique
      -- de ce qui a été constaté, et c'est ce qui permet de répondre
      -- « pourquoi ce créneau a-t-il été rouge mardi ? ». On en écrit
      -- donc une seconde, `applique`, qui dit la levée. Deux traces
      -- pour deux faits : le marquage et sa levée.
      v_debut := clock_timestamp();
      UPDATE public.planning_slots
         SET bloque_par_absence = false
       WHERE tenant_id = p_tenant AND id = v_creneau.id;

      PERFORM chain_trace(p_tenant, 'planning_slots.unblocked',
        'employee_absence_days', p_absence.day_uid,
        0, 1, NULL, 'applique',
        format('Créneau %s de nouveau exploitable : le jour d''absence du %s (%s) a été retiré.',
               v_creneau.id, to_char(p_absence.day, 'DD/MM/YYYY'),
               p_absence.absence_kind),
        v_creneau.id);

      v_lignes := v_lignes + 1;
      CONTINUE;
    END IF;

    -- LE MARQUAGE. Idempotence STRUCTURELLE : la boucle ne retient
    -- que les créneaux dont l'état est OPPOSÉ à la demande, donc un
    -- rejeu ne trouve plus rien à faire. Aucun `IF` recopié, et
    -- surtout aucun `chain_avant` : sa clé d'idempotence est le
    -- LIEN, et `day_uid` étant DÉTERMINÉ (md5 société:salari:jour),
    -- un congé annulé puis re-déclaré retrouverait la même clé et le
    -- créneau ne serait plus jamais marqué — c'est-à-dire une
    -- capacité qui compterait les heures d'un absent. La preuve
    -- reste dans `chain_traces`, qui n'a pas ce défaut.
    v_debut := clock_timestamp();

    UPDATE public.planning_slots
       SET bloque_par_absence = true
     WHERE tenant_id = p_tenant AND id = v_creneau.id;

    -- L'événement : c'est lui que l'écran et les webhooks
    -- consomment (L23/415), donc le nom est dans le CATALOGUE.
    PERFORM emit_domain_event(p_tenant, 'planning_slots.orphaned',
      'planning_slots', v_creneau.id,
      jsonb_build_object(
        'slot_id',      v_creneau.id,
        'employee_id',  p_absence.employee_id,
        'jour',         p_absence.day,
        'absence_kind', p_absence.absence_kind,
        'of',           v_creneau.manufacturing_order_id),
      NULL);

    PERFORM chain_apres(p_tenant, 'planning_slots.orphaned',
      'employee_absence_days', p_absence.day_uid, v_debut,
      1, 'applique',
      format('Créneau %s rendu inexploitable : l''opérateur %s est en « %s » le %s (%s).',
             v_creneau.id, p_absence.employee_id, p_absence.absence_kind,
             to_char(p_absence.day, 'DD/MM/YYYY'), p_absence.origin),
      NULL, v_creneau.id);

    v_lignes := v_lignes + 1;
  END LOOP;

  RETURN v_lignes;
END $fn$;

COMMENT ON FUNCTION public.chain_l17_constater_absence(uuid, employee_absence_days, boolean) IS
  'L17/416 — le COMPAGNON du couple `production ↔ RH` : constate, créneau par créneau, qu''un jour d''absence rend un créneau de production inexploitable. Rend le nombre de créneaux touchés. p_marquer = false lève le constat (congé annulé, ou devenu une mission). Le cas ordinaire — une absence qui ne touche aucun créneau — ne trace rien.';

-- ─────────────────────────────────────────────────────────────
-- 6. LE DÉCLENCHEUR — sur l'absence, et sur ses trois temps
--    AFTER INSERT : le congé tombe.
--    AFTER UPDATE OF blocks_work, employee_id, day : le congé
--      change de nature (une mission n'est pas un congé), ou une
--      reconstruction (263) rejoue la ligne.
--    AFTER DELETE : le congé est annulé → le constat se lève.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.zz_l17_absence_creneau()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM chain_l17_constater_absence(OLD.tenant_id, OLD, false);
    RETURN OLD;
  END IF;

  -- une absence qui ne bloque pas le travail ne marque rien — et un
  -- jour qui ne bloque plus ne doit pas garder son marquage.
  PERFORM chain_l17_constater_absence(NEW.tenant_id, NEW, NEW.blocks_work);
  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.zz_l17_absence_creneau() IS
  'L17/416 — déclencheur compagnon sur `employee_absence_days`. Il ne fait QUE déléguer à `chain_l17_constater_absence` : la logique vit dans la fonction, appelable aussi pour un rejeu explicite.';

DROP TRIGGER IF EXISTS zz_l17_absence_creneau ON public.employee_absence_days;
CREATE TRIGGER zz_l17_absence_creneau
  AFTER INSERT OR DELETE OR UPDATE OF blocks_work, employee_id, day
  ON public.employee_absence_days
  FOR EACH ROW EXECUTE FUNCTION public.zz_l17_absence_creneau();

-- ─────────────────────────────────────────────────────────────
-- 7. LE CATALOGUE D'ÉVÉNEMENTS — le nom doit être PROMIS
--    La 415 (L23) a rendu le catalogue VRAI : tout ce qui est
--    produit y est inscrit, et la suite 415 T05 relit les corps
--    des fonctions en base — un événement produit sans ligne de
--    catalogue la fait rougir. Sans cette insertion, le maillon
--    ferait échouer la suite de la tranche précédente.
--
--    Les colonnes sont celles que la 234 a créées : `description`
--    (NOT NULL) et `category` — pas `description_fr`/`module`, que
--    la 415 avait ajoutés sur un autre jeu de colonnes. On lit ce
--    que la table EST, pas ce qu'on voudrait qu'elle soit.
--
--    ⚠️ LE NOM RESPECTE LE VOCABULAIRE DU SOCLE : `module.action`,
--    UN SEUL point. Ce n'est pas un caprice : la porte 415 T05
--    relit les corps des fonctions avec le motif `'([a-z_]+\.[a-z_]+)'`
--    et n'aperçoit donc que les noms à un point. Mesuré : avec
--    `production.slot.orphaned` (deux points), l'événement passe le
--    CHECK du catalogue, est produit, et la porte le déclare quand
--    même « promesse morte » — un vert impossible. Les 28 autres
--    événements du catalogue sont tous à un point ; celui-ci aussi.
-- ─────────────────────────────────────────────────────────────
INSERT INTO webhook_event_catalog (event_name, description, category, is_active)
VALUES ('planning_slots.orphaned',
        'Créneau de production rendu inexploitable : son opérateur est absent ce jour-là (L17/416).',
        'production', true)
ON CONFLICT (event_name) DO UPDATE SET
  description = EXCLUDED.description,
  category    = EXCLUDED.category,
  is_active   = EXCLUDED.is_active;

-- L'ANCIEN NOM est EFFACÉ, pas seulement désactivé. Un nom à deux
-- points ne passe pas le scan de la porte 415 : le laisser au
-- catalogue la ferait compter comme « promesse morte » (T05), et
-- le garder en `is_active = false` ne changerait rien au verdict.
-- C'est la seule ligne de cette migration qui SUPPRIME : elle ne
-- supprime que ce qu'elle a elle-même créé, sous un nom que la
-- présente migration corrige — et le motif est dit ci-dessus.
DELETE FROM webhook_event_catalog WHERE event_name = 'production.slot.orphaned';

-- Le lever n'émet PAS d'événement : un client qui s'abonne à
-- « un créneau est devenu inexploitable » sait déjà, par la colonne,
-- quand le poste se libère. Le mot `planning_slots.unblocked` est
-- pourtant écrit en toutes lettres dans le corps du compagnon, et la
-- porte 415 relit les CORPS : toute chaîne `module.action` qu'elle
-- y trouve compte comme un producteur (T05). Un mot écrit dans le
-- corps et absent du catalogue = « effet invisible du client », donc
-- porte rouge. Il est donc CATALOGUÉ — et le dire vaut mieux que de
-- le laisser sortir par un trou du motif de la porte.
INSERT INTO webhook_event_catalog (event_name, description, category, is_active)
VALUES ('planning_slots.unblocked',
        'Créneau de production rendu à nouveau exploitable : le jour d''absence qui le bloquait a été retiré (L17/416).',
        'production', true)
ON CONFLICT (event_name) DO UPDATE SET
  description = EXCLUDED.description,
  category    = EXCLUDED.category,
  is_active   = EXCLUDED.is_active;

-- ─────────────────────────────────────────────────────────────
-- 8. LES DROITS — aucune fonction nouvelle n'est exposée
--     `work_center_load_hours` est lue par l'écran : elle est
--     donc accordée à `authenticated` (et PAS à `anon`). Les deux
--     autres sont INTERNES au socle : le compagnon vit dans son
--     déclencheur, la garde dans son `BEFORE` — le propriétaire
--     suffit. Même convention que la 410 (`chain_l3_*_cancel_liens`)
--     et que la 415 : une fonction créée l'est avec EXECUTE pour
--     PUBLIC, et la porte `check_anon_grants` le voit.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_l17_constater_absence(uuid, employee_absence_days, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.zz_l17_absence_creneau() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_planning_slot_on_absence() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.work_center_load_hours(uuid, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.work_center_load_hours(uuid, uuid, date) TO authenticated, service_role;
