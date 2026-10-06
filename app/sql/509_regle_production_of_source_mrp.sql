-- ============================================================
-- 509_regle_production_of_source_mrp.sql — partie B, lot Production, règle R-046
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 46) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-046 = ⬜).
--
-- R-046 — `manufacturing_orders.origin = mrp` → « traçabilité amont : quel besoin,
-- quelle proposition, quelle règle a créé cet ordre ».
--
-- MESURÉ (B.1). Un OF né d'un calcul MRP ne l'annonçait nulle part : aucune trace,
-- aucun événement. `manufacturing_orders.origin` porte la valeur `mrp`, mais rien ne
-- la rendait observable.
--
-- CE QUE CE FICHIER FAIT — un maillon « événement »
--   * à la CRÉATION d'un OF d'origine `mrp` : émet `manufacturing_orders.mrp_sourced`
--     (numéro, produit, nomenclature, quantité, OF parent éventuel) et trace le maillon.
--     C'est le point d'accroche de la traçabilité amont demandée par R-046 ;
--   * IDEMPOTENT (garde propre : ce maillon ne pose aucun lien).
--
-- LE TROU DE SCHÉMA, DIT. R-046 demande « quel besoin, quelle PROPOSITION, quelle
-- règle ». Le schéma ne le porte pas : `mrp_proposals` n'a **aucune** colonne vers
-- l'OF qu'elle a fait naître (`mrp_pending_docs` fait le pont `doc_type`/`doc_id`,
-- mais sans le `mrp_run_id` ni la proposition). L'événement dit donc QUE l'OF vient
-- d'un MRP, avec son produit et sa nomenclature — pas encore DE quelle proposition.
-- Combler ce trou (colonnes `mrp_run_id` / `mrp_proposal_id` sur l'OF, puis le lien)
-- est un ajout de schéma à coordonner (module production, partagé) : ce n'est PAS
-- écrit ici. R-046 est donc **partielle** : l'origine est tracée, la proposition non.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r046_…`).
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'manufacturing_orders', 'mrp', 'production.order.mrp_sourced',
        false, NULL, false, false, true, false, true,
        'R-046 : ordre de fabrication d''origine MRP — traçabilité amont. Partie B, lot Production.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : OF d'origine MRP → événement ──
CREATE OR REPLACE FUNCTION public.regle_r046_of_source_mrp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.origin IS DISTINCT FROM 'mrp' THEN
    RETURN NULL;
  END IF;
  -- Sur UPDATE, ne réagir qu'au passage À `mrp` (l'INSERT est toujours générateur).
  IF TG_OP = 'UPDATE' AND OLD.origin IS NOT DISTINCT FROM 'mrp' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence propre (ce maillon ne pose aucun lien).
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'manufacturing_orders.mrp_sourced'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'mrp', 'production.order.mrp_sourced',
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s : son origine MRP n''a pas été tracée (règle production.order.mrp_sourced, module production).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.mrp_sourced', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'product_id', NEW.product_id,
                                               'bom_id', NEW.bom_id, 'quantity', NEW.quantity,
                                               'parent_mo_id', NEW.parent_mo_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'production.order.mrp_sourced', 'manufacturing_orders', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r046_of_source_mrp ON manufacturing_orders;
CREATE TRIGGER zz_b2r046_of_source_mrp
AFTER INSERT OR UPDATE ON manufacturing_orders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r046_of_source_mrp();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r046_of_source_mrp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r046_of_source_mrp() TO service_role;
