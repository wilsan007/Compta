-- ============================================================
-- 511_regle_achats_reception_et_facture.sql — partie B, lot Achats, règles R-013, R-015, R-016
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 13, 15, 16) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-013/015/016 = ⬜).
--
--   R-013 — `goods_receipts.status = partial` → stock partiel, engagement partiellement
--           consommé, reliquat de commande, alerte ;
--   R-015 — `goods_receipts.status = pending` → contrôle qualité obligatoire avant
--           entrée en stock valorisé ;
--   R-016 — `purchase_invoices.status = cancelled` → contre-passation charge / TVA,
--           restitution du règlement, sortie du lettrage et de l'état de TVA.
--
-- MESURÉ (B.1). Aucun déclencheur ne testait `partial`, `pending` (réception) ni
-- `cancelled` (facture fournisseur) : ces trois états ne produisaient rien.
--
-- CE QUE CE FICHIER FAIT — trois maillons « événement » (aucune écriture métier)
--   * `goods_receipts.partial`  : émet `goods_receipts.partial` (reliquat de commande) ;
--   * `goods_receipts.pending`  : émet `goods_receipts.pending` (contrôle qualité requis) ;
--   * `purchase_invoices.cancelled` : émet `purchase_invoices.cancelled` (contre-passation).
--   IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUI EST LAISSÉ À LA COORDINATION (et pourquoi)
--   * R-013 — l'ENTRÉE EN STOCK d'une réception partielle n'est PAS écrite ici :
--     `create_stock_on_goods_receipt` ne réagit QU'À `received` (et refuse de doubler).
--     Une réception partielle `partial → received` ferait alors DEUX sorties si un
--     second déclencheur entrait le stock dès `partial`. Ce correctif touche un
--     déclencheur de STOCK partagé (R7, parties E) : à écrire d'un seul tenant.
--   * R-015 — le CONTRÔLE QUALITÉ obligatoire est une GARDE, pas un événement ; la
--     poser seule bloquerait les réceptions qui n'ont pas de contrôle — décision
--     métier (faut-il l'exiger partout ?) à trancher avant.
--   * R-016 — la CONTRE-PASSATION (écriture inverse + sortie de lettrage) est
--     comptable : le geste existe côté avoir fournisseur (`purchase_credit_notes`),
--     le chaîner d'une annulation est un travail comptable coordonné.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_*`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'goods_receipts', 'partial', 'purchase.receipt.partial',
        false, NULL, false, false, true, false, true,
        'R-013 : réception partielle — reliquat, alerte. Partie B, lot Achats.'),
       (NULL, 'goods_receipts', 'pending', 'purchase.receipt.pending',
        false, NULL, false, false, true, false, true,
        'R-015 : réception en attente — contrôle qualité requis. Partie B, lot Achats.'),
       (NULL, 'purchase_invoices', 'cancelled', 'purchase.invoice.cancelled',
        false, NULL, false, false, true, false, true,
        'R-016 : facture fournisseur annulée — contre-passation. Partie B, lot Achats.')
ON CONFLICT DO NOTHING;

-- ── 2. R-013 / R-015 — les états de la réception ──
CREATE OR REPLACE FUNCTION public.regle_achats_reception_etat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_effet    text;
  v_event    text;
  v_reliquat numeric := 0;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('partial', 'pending') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NEW.status = 'partial' THEN
    v_effet := 'purchase.receipt.partial'; v_event := 'goods_receipts.partial';
  ELSE
    v_effet := 'purchase.receipt.pending'; v_event := 'goods_receipts.pending';
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'goods_receipts', NEW.status, v_effet,
                     'goods_receipts', NEW.id, NULL,
                     format('Réception %s : l''état « %s » n''a pas été tracé (règle %s, module achats).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  -- Le reliquat n'a de sens que pour une réception partielle rattachée à une commande.
  IF NEW.status = 'partial' AND NEW.purchase_order_id IS NOT NULL THEN
    SELECT COALESCE(sum(pol.quantity), 0) - COALESCE(sum(grl.quantity_received), 0) INTO v_reliquat
    FROM purchase_order_lines pol
    LEFT JOIN goods_receipt_lines grl ON grl.product_id = pol.product_id AND grl.tenant_id = pol.tenant_id
      AND grl.goods_receipt_id IN (SELECT gr.id FROM goods_receipts gr
                                   WHERE gr.tenant_id = NEW.tenant_id AND gr.purchase_order_id = NEW.purchase_order_id)
    WHERE pol.purchase_order_id = NEW.purchase_order_id AND pol.tenant_id = NEW.tenant_id;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'goods_receipts', NEW.id,
                            jsonb_build_object('number', NEW.number, 'status', NEW.status,
                                               'purchase_order_id', NEW.purchase_order_id,
                                               'reliquat', GREATEST(v_reliquat, 0)), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'goods_receipts', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. R-016 — la facture fournisseur annulée ──
CREATE OR REPLACE FUNCTION public.regle_achats_facture_annulee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'purchase_invoices.cancelled'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'purchase_invoices', 'cancelled', 'purchase.invoice.cancelled',
                     'purchase_invoices', NEW.id, NULL,
                     format('Facture fournisseur %s : l''annulation n''a pas été tracée (règle purchase.invoice.cancelled, module achats).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_invoices.cancelled', 'purchase_invoices', NEW.id,
                            jsonb_build_object('number', NEW.number, 'supplier_id', NEW.supplier_id,
                                               'total', NEW.total, 'amount_paid', NEW.amount_paid), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.invoice.cancelled', 'purchase_invoices', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 4. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r013_015_reception_etat ON goods_receipts;
CREATE TRIGGER zz_b2r013_015_reception_etat
AFTER UPDATE ON goods_receipts
FOR EACH ROW
EXECUTE FUNCTION public.regle_achats_reception_etat();

DROP TRIGGER IF EXISTS zz_b2r016_facture_annulee ON purchase_invoices;
CREATE TRIGGER zz_b2r016_facture_annulee
AFTER UPDATE ON purchase_invoices
FOR EACH ROW
EXECUTE FUNCTION public.regle_achats_facture_annulee();

-- Ces maillons ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_achats_reception_etat() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_achats_facture_annulee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_achats_reception_etat() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_achats_facture_annulee() TO service_role;
