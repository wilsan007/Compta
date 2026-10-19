-- 767 — chain_l18_fabrication_projet
-- Numéro pris le 2026-10-19T16:41:19.880Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 767_chain_l18_fabrication_projet.sql — L18 · TRANCHE 2 : LA FABRICATION
--       À LA COMMANDE (un projet commande un OF — production ↔ projets)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- LE LOT. L18 du plan §5 Phase F relie « Stock ↔ Projets ET Production ↔
-- Projets » : sortie de stock sur projet (tranche 1, 418 ✅), fabrication
-- à la commande (CECI), réintégration du coût matière dans la marge.
--
-- DÉFAUT MESURÉ (rouge d'abord — suite 767 avant cette migration :
-- « column "project_id" of relation "manufacturing_orders" does not
-- exist ») :
--   * `manufacturing_orders` n'a AUCUN porteur projet — ni colonne, ni
--     champ libre : `origin` est un champ de PROVENANCE sous CHECK
--     (manual/mrp/sub_level), il ne dit pas POUR QUI l'OF se fabrique ;
--   * aucun lien projects → manufacturing_orders : le couple
--     `production ↔ projets` fait partie des 12 couples de modules VIDE
--     (référentiel §A.4) ;
--   * les consommations d'OF (`stock_movements.reference_type =
--     'production'`, la valeur que 176/229/241/302/315 lisent tous)
--     n'atteignent jamais `projects.actual_cost` : pour un projet
--     FABRIQUÉ, la marge reste à 0 quoi que le chantier fasse fabriquer —
--     le même « faux affiché comme vrai » que D3/D4 de la tranche 1.
--
-- CE QUE CE FICHIER POSE :
--   1. LE PORTEUR : `manufacturing_orders.project_id` + clé composite
--      ISO-02 `(tenant_id, project_id) → projects(tenant_id, id)` — le
--      miroir exact de `invoices_project_fk`. (Contrairement à la 418,
--      où `reference_type` existait déjà en 11 valeurs, aucun porteur
--      n'existait ici : la colonne n'est pas un second porteur, c'est le
--      SEUL.)
--   2. LE CONTRAT (porte G2) : l'effet `project.to_manufacturing_order`
--      déclaré dans `document_effects` ET produit par le déclencheur —
--      les deux sens dans le même fichier.
--   3. LE COÛT : `chain_l18_imputer_cout` (déclencheur de la tranche 1,
--      ses trois TEMPS déjà posés) est RÉÉCRIT pour résoudre aussi le
--      projet PAR L'OF : mouvement `production` → l'OF référencé → son
--      `project_id`. Aucun second moteur : `project_stock_cost` reste le
--      seul chemin d'imputation (doctrine W5).
--   4. LE LIEN : déclencheur `link_mo_to_project` (après INSERT, ou
--      UPDATE du porteur) — trace le lien par `link_documents` (fusion
--      sur rejeu) et referme l'ancien lien par `chain_lien_remplacer` si
--      le porteur change. Un UPDATE qui ne touche PAS `project_id` ne
--      touche pas au lien (`UPDATE OF project_id`).
--      LA GARDE DU PORTEUR EST LA CLÉ COMPOSITE ELLE-MÊME : projet
--      fantôme ou projet d'une autre société → refus 23503 nommé par
--      `manufacturing_orders_project_fk` (T07/T08). Un contrôle en
--      déclencheur serait MORT : la contrainte RI lève AVANT les
--      déclencheurs AFTER (ordre alphabétique — RI avant zz_, mesuré au
--      premier passage de la suite), il ne serait jamais le premier à
--      parler. C'est la clé qui appartient au dépôt, pas un IF.
--
-- SENS UNIQUE, COMME LA TRANCHE 1 : seules les SORTIES imputent —
-- l'entrée de produit fini sur l'OF est du stock, pas du coût de chantier
-- (T03). Le cas ordinaire reste MUET : un OF sans projet consomme sans
-- rien imputer ni lier (T06).
--
-- LIMITES DITES :
--   * l'écran « commander une fabrication depuis le projet » est la
--     partie D (écrans) — ce fichier livre la BASE : porteur, gardes,
--     lien, coût ; l'OF peut naître de l'écran, d'une RPC ou du MRP, le
--     déclencheur couvre tous les chemins ;
--   * le coût imputé est la MATIÈRE (quantité × coût unitaire du
--     mouvement), comme la tranche 1 : main-d'œuvre et frais indirects
--     de l'OF (`cost_labor`/`cost_overhead`) ne sont pas réintégrés
--     (limite héritée de 418 §5.1, dite) ;
--   * aucun lien n'est tracé PAR CONSOMMATION (le lien EST la commande) :
--     la frise montre projet → OF, pas le détail des sorties.
--
-- ROUGE D'ABORD — suite 767 (T01→T10) : le lien (actif, created_from),
-- le coût (4 × 5 = 20), le sens (entrée = 0), l'UPDATE remplace (30),
-- le DELETE rend (0), le cas ordinaire muet, le projet fantôme refusé,
-- le projet d'une autre société refusé, le contrat (déclaré + produit),
-- le changement de projet (remplace + actif — et l'UPDATE sans
-- changement de porteur n'y touche pas).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. LE PORTEUR : la colonne projet de l'OF ───────────────────────────────
-- Clé composite ISO-02 (le miroir exact de `invoices_project_fk`) : une
-- clé mono-colonne vers `projects` serait refusée par la porte
-- `check_composite_fks` — et elle lierait la ligne d'UNE société au
-- projet d'UNE AUTRE (défaut ISO-02, W1).
ALTER TABLE public.manufacturing_orders
  ADD COLUMN IF NOT EXISTS project_id uuid;

ALTER TABLE public.manufacturing_orders
  DROP CONSTRAINT IF EXISTS manufacturing_orders_project_fk;

ALTER TABLE public.manufacturing_orders
  ADD CONSTRAINT manufacturing_orders_project_fk
  FOREIGN KEY (tenant_id, project_id)
  REFERENCES public.projects (tenant_id, id)
  ON DELETE SET NULL (project_id);

COMMENT ON COLUMN public.manufacturing_orders.project_id IS
  'L18/767 — le porteur du couple production ↔ projets : l''OF fabriqué POUR un projet. Clé composite ISO-02 (tenant_id, project_id) — c''est elle qui refuse le projet fantôme ou étranger (23503). Écrit par qui crée l''OF (écran, RPC, MRP — l''écran vient en partie D) ; le déclencheur link_mo_to_project trace le lien projects → manufacturing_orders (effet project.to_manufacturing_order) et referme l''ancien lien si le porteur change.';

-- ── 2. LE CONTRAT D'EFFET (porte G2) ────────────────────────────────────────
-- Un appelant de `link_documents` avec un effet LITTÉRAL doit être
-- déclaré (L7) : la porte G2 refuse un maillon neuf non déclaré ET une
-- déclaration sans producteur. Déclaration et producteur arrivent dans
-- le même fichier.
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'projects', 'fabrication', 'project.to_manufacturing_order',
       false, NULL, false, false, true, false, true,
       'L18/767 : un projet commande un OF — le lien projects → manufacturing_orders naît avec l''OF portant le projet, se referme (remplace) si le porteur change ou saute. La consommation de l''OF impute le coût matière par project_stock_cost (tranche 1) — ce lien ne dit que la COMMANDE.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
   WHERE document_type = 'projects'
     AND effet = 'project.to_manufacturing_order');

-- ── 3. LE COÛT : la réécriture du compagnon de la tranche 1 ─────────────────
-- UN seul moteur, UN seul déclencheur (doctrine W5) : le corps des trois
-- TEMPS est conservé tel quel pour `reference_type = 'project'` — et la
-- résolution du projet s'ouvre à `reference_type = 'production'` : le
-- mouvement nomme l'OF, l'OF porte son projet. Un OF sans projet ne
-- résout rien et reste muet (T06).
CREATE OR REPLACE FUNCTION public.chain_l18_imputer_cout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_projet uuid;
BEGIN
  -- LE RETRAIT d'abord, sur `OLD`. Sans ce geste, un UPDATE imputerait
  -- le nouveau coût EN PLUS de l'ancien : la correction d'une quantité
  -- gonflerait la marge au lieu de la corriger (T04).
  IF TG_OP IN ('UPDATE', 'DELETE')
     AND OLD.reference_type IS NOT NULL
     AND OLD.reference_id IS NOT NULL
     AND COALESCE(OLD.movement_type, OLD.type) = 'out'
  THEN
    v_projet := CASE
      WHEN OLD.reference_type = 'project'   THEN OLD.reference_id
      WHEN OLD.reference_type = 'production' THEN (
        SELECT mo.project_id FROM manufacturing_orders mo
         WHERE mo.id = OLD.reference_id
           AND mo.tenant_id = OLD.tenant_id)
      ELSE NULL END;
    IF v_projet IS NOT NULL THEN
      PERFORM project_stock_cost(OLD.id, v_projet,
                                -(COALESCE(OLD.quantity, 0) * COALESCE(OLD.unit_cost, 0)));
    END IF;
  END IF;

  -- L'IMPUTATION ensuite, sur `NEW`. Une entrée qui référence un projet
  -- (directement ou par son OF) n'est pas une consommation : rien n'est
  -- imputé (T03).
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND NEW.reference_type IS NOT NULL
     AND NEW.reference_id IS NOT NULL
     AND COALESCE(NEW.movement_type, NEW.type) = 'out'
  THEN
    v_projet := CASE
      WHEN NEW.reference_type = 'project'   THEN NEW.reference_id
      WHEN NEW.reference_type = 'production' THEN (
        SELECT mo.project_id FROM manufacturing_orders mo
         WHERE mo.id = NEW.reference_id
           AND mo.tenant_id = NEW.tenant_id)
      ELSE NULL END;
    IF v_projet IS NOT NULL THEN
      PERFORM project_stock_cost(NEW.id, v_projet,
                                (COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_cost, 0)));
    END IF;
  END IF;

  RETURN NULL;   -- AFTER : la valeur de retour est sans effet
END $fn$;

COMMENT ON FUNCTION public.chain_l18_imputer_cout() IS
  'L18 (418 tranche 1, 767 tranche 2) — le compagnon du couple stock ↔ projets : impute, ou retire, le coût matière d''une sortie de stock au projet désigné SOIT directement (reference_type = ''project''), SOIT PAR L''OF qu''elle consomme (reference_type = ''production'' → manufacturing_orders.project_id). Couvre les TROIS temps du mouvement : sans le retrait, une correction ajoute ; sans le delete, une sortie annulée laisse son coût. Seules les SORTIES imputent — l''entrée de produit fini reste du stock. Le cas ordinaire (aucun des deux porteurs) ne fait rien.';

REVOKE ALL ON FUNCTION public.chain_l18_imputer_cout() FROM PUBLIC, anon, authenticated;

-- ── 4. LE LIEN : le déclencheur « un projet commande un OF » ─────────────────
-- AFTER INSERT, ou AFTER UPDATE **OF project_id** : un UPDATE qui ne
-- touche pas au porteur (quantité, statut, dates — la vie courante d'un
-- OF) ne touche à rien côté chaînage.
--
-- LE NOM EST UNE PROPRIÉTÉ DU DÉPÔT, ET IL A ÉTÉ MESURÉ ROUGE AVANT
-- LE RENOMMAGE (suite 401 T11) : sur une table qui porte un compagnon
-- `zz_l1?_…` — ici `zz_l16_production_start` ET `zz_l1_manufacturing_order`,
-- le `_` du motif `zz_l1_%` étant un caractère REMPLACEMENT (même piège
-- que la 418 §3.3) — AUCUN autre déclencheur AFTER ne peut trier APRÈS
-- eux : la propriété de la suite 401 exige que « frères après » reste à 0.
-- Un `zz_p5_of_projet_lien` triait après les deux (p > l1) : le décompte
-- est passé de 0 à 2, mesuré. Le déclencheur prend donc un nom de maillon
-- ORDINAIRE, sans préfixe `zz_` (comme `create_stock_out_on_delivery`),
-- qui trie devant les deux compagnons — et qui ne répond surtout pas au
-- motif `zz_l1_%`, ce qui en ferait un compagnon avec son décompte à
-- nourrir.
CREATE OR REPLACE FUNCTION public.chain_l18_of_projet_lien()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $fn$
BEGIN
  -- 1. LA GARDE DU PORTEUR N'EST PAS ICI — c'est la clé composite
  --    `manufacturing_orders_project_fk` (la clause §1) : un projet
  --    fantôme ou étranger est refusé par la contrainte, qui lève AVANT
  --    ce déclencheur (RI avant zz_ dans l'ordre alphabétique des AFTER
  --    — mesuré). Un IF ici ne se serait jamais exécuté : code mort.

  -- 2. LE PORTEUR CHANGE : l'ancien lien est FERMÉ (remplace, motif
  --    nommé) avant d'en ouvrir un autre. `chain_lien_actif` dit s'il y
  --    a quelque chose à fermer — un OF dont le porteur apparaît sans
  --    lien antérieur ne ferme rien (et ne lève pas).
  IF TG_OP = 'UPDATE'
     AND OLD.project_id IS NOT NULL
     AND OLD.project_id IS DISTINCT FROM NEW.project_id
     AND chain_lien_actif(OLD.tenant_id, 'projects', OLD.project_id,
                          'project.to_manufacturing_order', NULL) IS NOT NULL
  THEN
    PERFORM chain_lien_remplacer(
      OLD.tenant_id, 'projects', OLD.project_id,
      'project.to_manufacturing_order',
      'le projet porté par l''OF ' || NEW.number || ' a changé', NULL);
  END IF;

  -- 3. LE LIEN VERS LE PROJET PORTÉ. `link_documents` fusionne un rejeu
  --    sur le même couple (clé partielle `etat = 'actif'`) : replanter
  --    le même projet ne double rien (T10).
  IF NEW.project_id IS NOT NULL THEN
    PERFORM link_documents(
      NEW.tenant_id, 'projects', NEW.project_id,
      'manufacturing_orders', NEW.id,
      'project.to_manufacturing_order', 'created_from',
      jsonb_build_object('of', NEW.number,
                         'quantite', NEW.quantity,
                         'produit', NEW.product_id));
  END IF;

  RETURN NULL;   -- AFTER : la valeur de retour est sans effet
END $fn$;

COMMENT ON FUNCTION public.chain_l18_of_projet_lien() IS
  'L18/767 — le compagnon du couple production ↔ projets : trace le lien projects → manufacturing_orders (effet project.to_manufacturing_order, type created_from) à la naissance d''OF portant un projet, et referme l''ancien lien (remplace, motif nommé) si le porteur change. La garde du porteur (même société) est la clé composite manufacturing_orders_project_fk, pas ce déclencheur — la contrainte lèverait avant lui.';

-- (L'ancien nom `zz_p5_of_projet_lien` — mesuré rouge en 401 T11 pour
--  avoir trié APRÈS les compagnons — est retiré au passage.)
DROP TRIGGER IF EXISTS zz_p5_of_projet_lien ON public.manufacturing_orders;
DROP TRIGGER IF EXISTS link_mo_to_project ON public.manufacturing_orders;
CREATE TRIGGER link_mo_to_project
  AFTER INSERT OR UPDATE OF project_id ON public.manufacturing_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.chain_l18_of_projet_lien();

REVOKE ALL ON FUNCTION public.chain_l18_of_projet_lien() FROM PUBLIC, anon, authenticated;

