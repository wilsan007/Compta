-- ═══════════════════════════════════════════════════════════════════════════
-- 496 — L16 · le chaînage interne des PROJETS : la CLÔTURE cesse d'être muette
-- ═══════════════════════════════════════════════════════════════════════════
-- Numéro pris via migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) »,
-- branche plan6/a3-l16-projets).
--
-- Le référentiel (§B.3) décrit le chaînage interne attendu du module Projets —
-- « devis ↔ projet ↔ budget ↔ temps ↔ coût ↔ facturation ↔ marge ↔ clôture » —
-- et nomme le tronçon manquant : « `calculate_project_profitability` (4/7) ;
-- **clôture de projet muette (`R-040`)** ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `projects.status` admet bien `'completed'` (CHECK : active, completed,
--     on_hold, cancelled) — la clôture EXISTE comme état ;
--   * **une seule** fonction du schéma mentionne `projects` ET `completed` :
--     `calculate_project_profitability` — et elle ne se déclenche pas ;
--   * **aucun déclencheur** ne s'exécute sur le passage à `'completed'` :
--     l'état change, rien n'est tracé, personne n'est prévenu. C'est
--     littéralement « muet » ;
--   * `projects` n'est PAS au registre `chain_document_types` (27 types, sans
--     les projets), et aucun contrat ne se nomme pour cet effet.
--
-- CE QUE CE FICHIER POSE : le type `projects` au registre, le contrat d'effet
-- `project.closure.finalized`, et le maillon `chain_l16_project_closure` — un
-- déclencheur `AFTER UPDATE`, donc il couvre **tous** les chemins de clôture
-- (écran, import, RPC), pas seulement celui qu'on aurait câblé à la main.
--
-- ⚠️ LA MARGE EST GELÉE DANS L'ÉVÉNEMENT, ET LA CLÔTURE N'EST JAMAIS BLOQUÉE.
-- Le calcul de rentabilité est tenté ; s'il échoue (projet sans temps ni coût),
-- on l'ÉCRIT (« marge indisponible » + la raison) au lieu de faire échouer la
-- clôture métier. Un maillon ne bloque pas le geste qu'il instrumente — c'est
-- la doctrine du socle (252), et c'est ici la seule façon honnête de procéder.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre des types de documents accueille les PROJETS ────────────
-- (le même geste que 450 pour les 27 types : un upsert, donc rejouable)
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('projects', 'projects', NULL, 'Projet')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
-- La clôture n'écrit AUCUNE comptabilité (elle ne fait que tracer et annoncer) :
-- le contrat le DIT, comme le veut la doctrine M-05 (« déclarer même un effet
-- aucun »). Effet réversible par construction : un projet rouvert puis reclos
-- ne rejoue pas l'effet (idempotence du socle).
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'projects', 'completed', 'project.closure.finalized', false, NULL,
       false, false, true, true, true,
       'L16/496 : la clôture d''un projet est désormais TRACÉE et annoncée (événement projects.completed portant la marge gelée). Aucune écriture comptable directe : la marge est calculée par calculate_project_profitability, jamais recalculée ici.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'projects' AND evenement = 'completed' AND effet = 'project.closure.finalized'
);

-- ── 3. Le MAILLON : `chain_l16_project_closure` ────────────────────────────
-- Un déclencheur AFTER UPDATE : il n'empêche rien, il TRACE ce qui vient d'être
-- fait et l'ANNONCE. Le geste métier (passage à 'completed') a déjà eu lieu —
-- c'est pourquoi il couvre tous les chemins de clôture, écran compris.
CREATE OR REPLACE FUNCTION public.chain_l16_project_closure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_marge jsonb;
  v_note  text := NULL;
BEGIN
  -- 1. Le seul fait qui compte : le STATUT VIENT de passer à 'completed'.
  --    Un UPDATE qui ne change pas le statut ne produit donc rien.
  IF NEW.status <> 'completed' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;

  -- 2. IDEMPOTENCE — et ici elle est EXPLICITE, pour une raison MESURÉE :
  --    `chain_deja_fait` du socle détecte le rejeu par `document_links` (lu
  --    dans la 252), et ce maillon ne produit AUCUN document d'aval — la
  --    clôture n'en crée pas. C'est donc l'ANNONCE qui atteste que l'effet a eu
  --    lieu, et le rejeu est DIT (trace « ignore »), comme le veut la convention.
  IF EXISTS (
    SELECT 1 FROM domain_events de
    WHERE de.tenant_id = NEW.tenant_id
      AND de.event_name = 'projects.completed'
      AND de.aggregate_id = NEW.id
  ) THEN
    PERFORM chain_trace(NEW.tenant_id, 'project.closure.finalized', 'projects', NEW.id,
                        0, 0, NULL, 'ignore', 'Clôture déjà annoncée — rejeu sans effet.', NULL);
    RETURN NULL;
  END IF;

  -- 3. La marge finale est TENTÉE, jamais imposée : un projet sans temps ni
  --    coût reste clôturable, et la raison de l'absence est ÉCRITE.
  BEGIN
    v_marge := calculate_project_profitability(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    v_marge := NULL;
    v_note  := 'marge indisponible : ' || SQLERRM;
  END;

  -- 3. ENTRÉE du maillon — rejeu (rend false et trace « ignore »), puis contrat.
  IF NOT chain_avant(NEW.tenant_id, 'projects', 'completed',
                     'project.closure.finalized', 'projects', NEW.id, NULL,
                     format('Projet « %s » : la clôture n''a pas été tracée (règle project.closure.finalized, module projets).', NEW.name)) THEN
    RETURN NULL;
  END IF;

  -- 4. L'ÉVÉNEMENT — il PORTE la marge gelée : c'est la pièce qui permet de
  --    répondre plus tard à « combien ce projet a-t-il rapporté, et quand
  --    l'a-t-on su ? » sans rien recalculer.
  PERFORM emit_domain_event(
    NEW.tenant_id, 'projects.completed', 'projects', NEW.id,
    jsonb_build_object('name', NEW.name, 'status', NEW.status,
                       'budget', NEW.budget, 'actual_cost', NEW.actual_cost,
                       'end_date', NEW.end_date, 'marge', v_marge, 'note', v_note),
    NULL);

  -- 5. LA MESURE (§3.4) — un maillon de trace, budget ≤ 50 ms.
  PERFORM chain_apres(NEW.tenant_id, 'project.closure.finalized', 'projects', NEW.id,
                      v_debut, 1, 'applique', v_note);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l16_project_closure() IS
  'L16/496 : maillon de la clôture de projet — l''état « completed » cesse d''être muet. Trace (chain_apres « applique »), annonce (projects.completed) et gèle la marge rendue par calculate_project_profitability dans la charge utile de l''événement. Ne bloque jamais la clôture : une marge indisponible est ÉCRITE, pas levée.';

DROP TRIGGER IF EXISTS zz_l16_project_closure ON projects;
CREATE TRIGGER zz_l16_project_closure
  AFTER UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION public.chain_l16_project_closure();

REVOKE ALL ON FUNCTION public.chain_l16_project_closure() FROM PUBLIC, anon, authenticated;
-- Numéro pris le 2026-10-05T21:02:54.257Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-l16-projets).
