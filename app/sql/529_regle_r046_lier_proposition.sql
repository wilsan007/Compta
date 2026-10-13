-- ============================================================
-- 529_regle_r046_lier_proposition.sql — partie B, lot Production, règle R-046 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 46) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-046 = 🟨).
--
-- R-046 — `manufacturing_orders.origin = mrp` → « traçabilité amont : quel besoin, quelle
-- PROPOSITION, quelle règle a créé cet ordre ».
--
-- MESURÉ : la `509` a rendu l'origine MRP OBSERVABLE (événement + trace). Ce qui manquait,
-- c'est le lien vers la PROPOSITION qui a créé l'OF — le schéma ne le portait nulle part.
--
-- CE QUE CE FICHIER FAIT — le LIEN vers la proposition MRP
--   * ajoute deux colonnes à l'OF : `mrp_run_id` et `mrp_proposal_id` (additif, `IF NOT EXISTS`) ;
--   * à la création d'un OF d'origine `mrp` : LIE l'OF à sa PROPOSITION MRP — soit celle
--     déjà posée dans `mrp_proposal_id`, soit la **dernière proposition `converted`** du
--     même article (et même nomenclature quand elle est posée) — et renseigne les colonnes ;
--   * émet `manufacturing_orders.mrp_linked` ; idempotent (le lien garde).
--
-- LE SENS DE « converted », dit : une proposition MRP passée à `converted` est une
-- proposition DEVENUE un document — c'est notre ancre. L'inférence (même article, même
-- nomenclature, `converted`, la plus récente) est **nommée** : elle vaut traçabilité
-- best-effort, et le jour où l'écrivain MRP pose `mrp_proposal_id` lui-même, la valeur
-- POSÉE prime (le trigger ne résout que si elle est absente).
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r046_…`).
-- ============================================================

-- ── 1. Les colonnes (additif) + le contrat + le registre ──
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS mrp_run_id uuid;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS mrp_proposal_id uuid;

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'manufacturing_orders', 'mrp_linked', 'production.order.mrp_linked',
        false, NULL, false, false, true, false, true,
        'R-046 : OF lié à sa proposition MRP. Partie B, lot Production.')
ON CONFLICT DO NOTHING;

INSERT INTO chain_document_types (code, table_name, ligne_table, libelle_fr)
VALUES ('mrp_proposals', 'mrp_proposals', NULL, 'Proposition CBN/MRP')
ON CONFLICT DO NOTHING;

-- ── 2. RÉSOUDRE la proposition (BEFORE : renseigne les colonnes) ──
CREATE OR REPLACE FUNCTION public.regle_r046_resoudre_proposition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
BEGIN
  IF NEW.origin IS DISTINCT FROM 'mrp' OR NEW.tenant_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.mrp_proposal_id IS NOT NULL THEN
    RETURN NEW;   -- la valeur POSÉE prime
  END IF;

  SELECT p.id, p.mrp_run_id INTO NEW.mrp_proposal_id, NEW.mrp_run_id
  FROM mrp_proposals p
  WHERE p.tenant_id = NEW.tenant_id AND p.product_id = NEW.product_id
    AND p.status = 'converted'
    AND (NEW.bom_id IS NULL OR p.bom_id IS NOT DISTINCT FROM NEW.bom_id)
  ORDER BY p.created_at DESC NULLS LAST, p.id
  LIMIT 1;

  RETURN NEW;
END $garde$;

-- ── 3. LIER l'OF à sa proposition (AFTER : lien + événement + trace) ──
CREATE OR REPLACE FUNCTION public.regle_r046_lier_proposition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.origin IS DISTINCT FROM 'mrp' OR NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'mrp_linked', 'production.order.mrp_linked',
                     'manufacturing_orders', NEW.id, NULL,
                     format('OF %s : le lien à sa proposition MRP n''a pas été posé (règle production.order.mrp_linked, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;

  IF NEW.mrp_proposal_id IS NULL THEN
    PERFORM chain_apres(NEW.tenant_id, 'production.order.mrp_linked', 'manufacturing_orders', NEW.id,
                        v_debut, 0, 'sans_effet', 'Aucune proposition MRP convertie retrouvée pour cet article.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'manufacturing_orders', NEW.id, 'mrp_proposals', NEW.mrp_proposal_id,
                         'production.order.mrp_linked', 'created_from',
                         jsonb_build_object('order_number', NEW.number, 'mrp_run_id', NEW.mrp_run_id));

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.mrp_linked', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'mrp_proposal_id', NEW.mrp_proposal_id,
                                               'mrp_run_id', NEW.mrp_run_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'production.order.mrp_linked', 'manufacturing_orders', NEW.id,
                      v_debut, 1, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r046_resoudre_proposition ON manufacturing_orders;
CREATE TRIGGER zz_b2r046_resoudre_proposition
BEFORE INSERT OR UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_r046_resoudre_proposition();

DROP TRIGGER IF EXISTS zz_b2r046_lier_proposition ON manufacturing_orders;
CREATE TRIGGER zz_b2r046_lier_proposition
AFTER INSERT OR UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_r046_lier_proposition();

REVOKE ALL ON FUNCTION public.regle_r046_resoudre_proposition() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r046_lier_proposition() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r046_resoudre_proposition() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r046_lier_proposition() TO service_role;
