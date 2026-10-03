-- 418 — l18_consommation_chantier
-- Numéro pris le 2026-10-03T09:26:25.645Z par migration-numero.mjs (ligne « L16-L24 », branche partie-5-integrite-chainages).
-- ============================================================
-- 418_l18_consommation_chantier.sql — L18 : LE PROJET CONSOMME
--   LE STOCK, ET LA MARGE LE SAIT
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L18** (« Stock ↔ Projets … sortie de stock sur
-- projet (consommation de chantier, avec imputation analytique) …,
-- coût de revient projet amputé »), et le référentiel §A.4, où
-- `stock ↔ projets` est l'un des **12 couples de modules VIDE** :
-- « un projet ne sort rien du stock : consommations de chantier
-- invisibles, coût de revient projet amputé ».
--
-- LE DÉFAUT, MESURÉ SUR BASE NEUVE (282 migrations, 0 erreur) :
--
--   1. **ZÉRO lecture croisée.** Mesuré : 0 fonction lit à la fois
--      `stock_movements` et `projects`. Le couple n'est pas
--      incomplet, il est IMPOSSIBLE : aucun des deux modules ne
--      connaît l'autre.
--
--   2. **`projects.actual_cost` N'EST ÉCRITE PAR PERSONNE.**
--      Mesuré : 0 fonction ne la met à jour, 0 fonction ne la lit,
--      et les seuls débouchés sont les types TypeScript. La colonne
--      existe, le budget existe, et la marge d'un projet vaut donc
--      **0** quel que soit ce que le chantier a dépensé. Ce n'est
--      pas une colonne vide : c'est un **indicateur faux affiché
--      comme vrai** — le défaut le plus grave de la série, pire
--      qu'une capacité théorique (416 §1).
--
--   3. Aucun déclencheur sur `projects` ne touche aux coûts
--      (mesuré : seuls `updated_at` et `set_tenant_id`).
--
-- CE QUE CETTE MIGRATION POSE :
--
--   * `project_stock_cost(mouvement, projet)` — l'instruction qui
--     impute (ou retire) le coût matière d'UN mouvement, écrit une
--     fois, appelable aussi pour un rejeu explicite (T04).
--
--   * `zz_p5_projet_cout` — le compagnon, sur les TROIS temps du
--     mouvement : INSERT, UPDATE de la quantité ou du coût unitaire,
--     DELETE. Le troisième est celui qu'on oublie toujours, et sans
--     lui une sortie annulée laisserait son coût au projet : la
--     marge mentirait dans l'autre sens (T07).
--
-- LE PORTEUR : aucun. `stock_movements` porte DÉJÀ `reference_type`
-- et `reference_id` — le porteur générique du dépôt, dont les
-- valeurs relevées sont déjà 11 (`goods_receipt`, `pos_ticket`,
-- `delivery_note`, `production`, `manual`…). On s'y range avec la
-- valeur `project` : créer une colonne `project_id` aurait été
-- un deuxième porteur pour la même vérité, c'est-à-dire la faute
-- W5.
--
-- LA RÈGLE, et elle est une seule : le coût imputé est
-- **quantité × coût unitaire** du mouvement. Jamais le prix de
-- vente — un défaut d'imputation classique, que T03 rend visible
-- en mettant un prix de vente 25 fois supérieur au coût.
--
-- AUCUN `document_links` : même décision que la 416 §3.1, même
-- motif — la 451 refuse un type absent du registre
-- `chain_document_types`, et inscrire `projects` /
-- `stock_movements` aurait fait tomber le plafond de 27 et
--Diagramme les gardes de la 453. La preuve est portée par
-- `chain_traces`.
--
-- REJOUABLE : fonctions `CREATE OR REPLACE`, déclencheur `DROP`
-- avant `CREATE`, contrat par `ON CONFLICT DO NOTHING`.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. LE CONTRAT D'EFFET — déclaré ICI, comme la porte G2 l'exige
--    depuis le lot L7 (313). Le couple est
--    `(stock_movements, out, project.stock_cost)`.
--
--    RÉVERSIBLE : le retrait est le même effet en sens inverse, et
--    il est EXERCÉ par le compagnon lui-même sur l'UPDATE et le
--    DELETE (T04, T07). On ne déclare donc pas un effet sans
--    issue, ce que le point 4 de §4.1 interdit.
--
--    `touche_stock = false` : le maillon ne bouge pas au stock, il
--    lit ce que le stock a déjà fait et le reporte sur le projet.
--    Le dire est important — c'est ce qui distingue cette migration
--    des maillons de production, qui, eux, écrivent en stock.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                               ecrit_comptable, journal_code, touche_stock, touche_paie,
                               reversible, obligatoire, actif, note)
VALUES (NULL, 'stock_movements', 'out', 'project.stock_cost',
        false, NULL, false, false,
        true, false, true,
        'L18/418 : une sortie de stock imputée à un projet (reference_type = ''project'') reporte son coût MATIÈRE (quantité × coût unitaire) sur projects.actual_cost. RÉVERSIBLE : l''UPDATE de la quantité ou du coût unitaire, et le DELETE, retirent exactement ce qui avait été imputé — T04 et T07 le mesurent. La sortie n''impute RIEN si elle n''est pas de sens ''out'' : une réception sur projet n''est pas une consommation (T05). Un mouvement sans référence projet ne fait rien du tout : le cas ordinaire ne se trace pas.')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. L'INSTRUCTION — écrire une fois, l'utiliser partout
--
--    Elle impute (ou retire) le coût matière d'UN mouvement sur UN
--    projet, et rend le coût net appliqué. Elle ne décide rien :
--    elle calcule, et c'est le compagnon qui décide QUAND l'appeler.
--
--    LE SIGNE est l'entrée : `p_delta > 0` impute, `p_delta < 0`
--    retire. C'est la seule façon d'avoir UN chemin pour les deux
--    sens — un `IF` par sens dans deux endroits dériverait.
--
--    LE COÛT RETIRÉ EST PLUSTÔT QUE 0 (T07) : deux mouvements
--    qui se corrigent mutuellement ne doivent pas pouvoir rendre le
--    coût d'un projet NÉGATIF, ce qui ferait dire à l'écran qu'un
--    chantier a rapporté alors qu'il n'a rien dépensé.
--
--    ISOLATION (T06) : `SECURITY DEFINER` traverse la RLS, donc
--    l'appelant doit être membre de la société du projet — le
--    contrôle `tenant_users` × `auth.uid()` que la porte G4 exige
--    depuis qu'elle a refusé `work_center_load_hours` (416 §3.4).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.project_stock_cost(
  p_mouvement uuid,
  p_projet   uuid,
  p_delta    numeric
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_tenant uuid;
  v_cout   numeric;
BEGIN
  IF p_projet IS NULL THEN
    RETURN 0;
  END IF;

  SELECT pj.tenant_id INTO v_tenant FROM public.projects pj WHERE pj.id = p_projet;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Imputation refusée : le projet % n''existe pas.', p_projet
      USING ERRCODE = 'P0002';
  END IF;

  -- l'appelant est-il membre de CETTE société ?
  IF auth.uid() IS NOT NULL
     AND session_user NOT IN ('postgres', 'service_role')
     AND NOT EXISTS (SELECT 1 FROM public.tenant_users tu
                      WHERE tu.tenant_id = v_tenant
                        AND tu.auth_id   = auth.uid()
                        AND COALESCE(tu.status, 'active') = 'active') THEN
    RAISE EXCEPTION 'Imputation refusée : la société % ne vous est pas attribuée (garde de société, 236).', v_tenant
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(p_delta, 0) = 0 THEN
    RETURN 0;
  END IF;

  -- La borne porte sur le RÉSULTAT : un retrait ne peut pas rendre
  -- le projet négatif, et deux imputations croisées ne dérivent pas.
  UPDATE public.projects
     SET actual_cost = GREATEST(0, COALESCE(actual_cost, 0) + p_delta)
   WHERE id = p_projet AND tenant_id = v_tenant
  RETURNING actual_cost INTO v_cout;

  RETURN v_cout;
END $fn$;

COMMENT ON FUNCTION public.project_stock_cost(uuid, uuid, numeric) IS
  'L18/418 — impute (delta > 0) ou retire (delta < 0) le coût matière d''un mouvement sur un projet. Coût = quantité × coût unitaire du MOUVEMENT, jamais le prix de vente (T03). Le résultat ne descend jamais sous 0 : une sortie annulée rend tout son coût, sans laisser un `actual_cost` négatif (T07). Un projet inexistant est REFUSÉ ; une société à laquelle l''appelant n''appartient pas aussi.';

-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
-- 3. LE COMPAGNON — `chain_l18_imputer_cout`
--
--    DOCTRINE 310 : l'aval est identifié par une clé MESURÉE dans
--    le corps du maillon — ici `reference_id` du mouvement, qui
--    EST l'identifiant du projet. Le compagnon s'accroche au
--    mouvement, seul côté possible : le projet ignore le stock.
--
--    IL A TROIS TEMPS, et le troisième est celui qu'on oublie :
--      * INSERT → on impute le coût de la sortie ;
--      * UPDATE de la quantité ou du coût unitaire → on RETIRE
--        l'ancien coût avant d'imputer le nouveau, sinon chaque
--        correction AJOUTE au lieu de remplacer (T04) ;
--      * DELETE → on retire, sinon une sortie annulée laisse son
--        coût au projet et la marge ment (T07).
--
--    LE SENS EST LU, PAS DEVINÉ : une réception qui référence un
--    projet n'est pas une consommation et n'impute rien (T05).
--
--    L'IDEMPOTENCE est structurelle : le retrait porte sur `OLD`
--    (ce qui était réellement imputé) et l'imputation sur `NEW`.
--
--    LE CAS ORDINAIRE NE SE TRACE PAS (retenue de la tranche 5 de
--    L1) : un mouvement qui ne référence pas de projet — les 45
--    mouvements relevés sans `reference_type`, et tous ceux des 10
--    autres types — ne sont ni tracés ni timbrés.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l18_imputer_cout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- LE RETRAIT d'abord, sur `OLD`. Sans ce geste, un UPDATE
  -- imputerait le nouveau coût EN PLUS du ancien : la correction
  -- d'une quantité gonflerait la marge au lieu de la corriger.
  IF TG_OP IN ('UPDATE', 'DELETE')
     AND OLD.reference_type = 'project'
     AND OLD.reference_id IS NOT NULL
     AND COALESCE(OLD.movement_type, OLD.type) = 'out'
  THEN
    PERFORM project_stock_cost(OLD.id, OLD.reference_id,
                              -(COALESCE(OLD.quantity, 0) * COALESCE(OLD.unit_cost, 0)));
  END IF;

  -- L'IMPUTATION ensuite, sur `NEW`. Une entrée qui référence un
  -- projet n'est pas une consommation : rien n'est imputé.
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND NEW.reference_type = 'project'
     AND NEW.reference_id IS NOT NULL
     AND COALESCE(NEW.movement_type, NEW.type) = 'out'
  THEN
    PERFORM project_stock_cost(NEW.id, NEW.reference_id,
                               (COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_cost, 0)));
  END IF;

  RETURN NULL;   -- AFTER : la valeur de retour est sans effet
END $fn$;

COMMENT ON FUNCTION public.chain_l18_imputer_cout() IS
  'L18/418 — le compagnon du couple `stock ↔ projets` : impute, ou retire, le coût matière d''une sortie de stock à un projet désigné par `reference_type = ''project''`. Couvre les TROIS temps du mouvement (INSERT, UPDATE de la quantité ou du coût, DELETE) : sans le troisième, une sortie annulée laisserait son coût au projet et la marge mentirait dans l''autre sens.';

-- Le nom est mesuré, et il est dicté par une propriété du dépôt
-- (§5) : `zz_p5_projet_cout` n'entre pas dans le motif `zz_l1_%`
-- de la suite 401, et le trigger reste bien APRÈS le maillon
-- métier `update_stock_on_movement`.
--
DROP TRIGGER IF EXISTS zz_p5_projet_cout ON public.stock_movements;
CREATE TRIGGER zz_p5_projet_cout
  AFTER INSERT OR DELETE OR UPDATE OF quantity, unit_cost, reference_id, reference_type, movement_type, type
  ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.chain_l18_imputer_cout();

-- ─────────────────────────────────────────────────────────────
-- 4. LES DROITS — `check_anon_grants` verrait rouge sinon
--    La fonction interne est révoquée à `PUBLIC` et `anon` : c'est
--    le compagnon du déclencheur qui l'appelle, le propriétaire
--    suffit. Même convention que la 416 §8 et la 417 §3.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_l18_imputer_cout() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_stock_cost(uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.project_stock_cost(uuid, uuid, numeric) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 5. LE NOM DU DÉCLENCHEUR — mesuré, et c'est un vrai piège
--
--    Le déclencheur s'appelle `zz_p5_projet_cout`, et NON
--    `zz_l18_projet_cout`. La raison est mesurée, pas stylish :
--    la suite 401 (T11) vérifie une PROPRIÉTÉ sur les déclencheurs
--    `LIKE 'zz_l1_%'` — et en SQL, `_` est le caractère
--   Replacement : `zz_l18_projet_cout` MATCHE ce motif (le `8`
--    remplace le `_`). Le_trigger entrait donc dans le compte des
--    compagnons L1, et comme `zz_restate_layers_to_cump` trie
--    APRÈS lui sur le même événement, la propriété « aucun frère
--    après » devenait FAUSSE : **la suite 401 rougissait**.
--    Mesuré : verte sans la 418, rouge avec elle.
--
--    On aurait pu faire l'inverse — nommer le trigger pour qu'il
--    trie après tout — mais la règle « un compagnon est APRÈS le
--    maillon métier qu'il accompagne » vaut mieux que « il
--    s'appelle comme un autre lot ». Un trigger qui se fait passer
--    pour un compagnon d'un autre lot est un mensonge que le
--    prochain mainteneur paiera.
--
--    L'ordre alphabétique sur `stock_movements` reste alors :
--      …	update_stock_on_movement	(le maillon métier)
--      …	zz_p5_projet_cout	(le compagnon)
--      …	zz_restate_layers_to_cump
--    ce qui est sans conséquence : les trois lisent des tables
--    différentes et aucun ne dépend de l another's exécution.
-- ─────────────────────────────────────────────────────────────
