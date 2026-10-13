-- ============================================================
-- 505_regle_achats_facture_surveillance.sql — partie B, lot Achats, règles R-017 et R-018
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 17-18) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-017, R-018 = ⬜).
--
--   R-017 — `purchase_invoices.status = overdue` → alerte fournisseur, échéancier
--           révisé, pénalités éventuelles ;
--   R-018 — `purchase_invoices.approval_status = rejected` → retour au demandeur
--           avec motif, libération de l'engagement.
--
-- MESURÉ (B.1). Aucun déclencheur sur `purchase_invoices` ne testait `overdue` ni
-- `rejected` : l'échéance dépassée et le rejet d'une facture fournisseur ne
-- produisaient rien (ni alerte, ni trace).
--
-- CE QUE CE FICHIER FAIT — deux maillons (événement + trace), aucune écriture métier
--   * à l'échéance (`overdue`) : émet `purchase_invoices.overdue` (numéro, fournisseur,
--     reste dû, échéance) — point d'accroche de l'ALERTE et de l'échéancier ;
--   * au rejet (`approval_status = rejected`) : émet `purchase_invoices.rejected`
--     (numéro, fournisseur, total, reste dû) — point d'accroche du RETOUR AU DEMANDEUR.
--
-- CE QUE CE FICHIER NE FAIT PAS (dit, et pourquoi)
--   * R-018 « libération de l'engagement » : l'engagement (`budget_commitments`) est
--     rattaché à la COMMANDE, pas à la facture ; le REJET d'une facture ne libère
--     rien (la commande existe toujours). Rien n'est donc écrit dans les engagements —
--     l'engagement se consomme à l'APPROBATION (`consume_commitment_on_purchase_invoice`,
--     règle R-057) et se libère à l'ANNULATION de la commande (R-012).
--   * Il n'y a pas de colonne « motif de rejet » au schéma : le motif vit dans le
--     formulaire qui pose le rejet, l'événement dit seulement QUE le rejet a eu lieu.
--
-- IDEMPOTENCE : propre à chaque maillon (aucun lien posé → `chain_deja_fait`, qui lit
-- `document_links`, ne protège pas) : on refuse un second événement du même type.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_r017_…` /
-- `regle_r018_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'purchase_invoices', 'overdue', 'purchase.invoice.overdue',
        false, NULL, false, false, true, false, true,
        'R-017 : facture fournisseur échue — alerte, échéancier. Partie B, lot Achats.'),
       (NULL, 'purchase_invoices', 'rejected', 'purchase.invoice.rejected',
        false, NULL, false, false, true, false, true,
        'R-018 : facture fournisseur rejetée — retour au demandeur. Partie B, lot Achats.')
ON CONFLICT DO NOTHING;

-- ── 2. R-017 — la facture fournisseur échue ──
CREATE OR REPLACE FUNCTION public.regle_r017_facture_achat_expiree()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'overdue' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence propre (ce maillon ne pose aucun lien).
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'purchase_invoices.overdue'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'purchase_invoices', 'overdue', 'purchase.invoice.overdue',
                     'purchase_invoices', NEW.id, NULL,
                     format('Facture fournisseur %s : l''alerte d''échéance n''a pas été émise (règle purchase.invoice.overdue, module achats).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_invoices.overdue', 'purchase_invoices', NEW.id,
                            jsonb_build_object('number', NEW.number, 'supplier_id', NEW.supplier_id,
                                               'amount_due', NEW.amount_due, 'due_date', NEW.due_date), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.invoice.overdue', 'purchase_invoices', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. R-018 — la facture fournisseur rejetée ──
CREATE OR REPLACE FUNCTION public.regle_r018_facture_achat_rejetee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.approval_status IS NOT DISTINCT FROM OLD.approval_status
     OR NEW.approval_status IS DISTINCT FROM 'rejected' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence propre (ce maillon ne pose aucun lien).
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'purchase_invoices.rejected'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'purchase_invoices', 'rejected', 'purchase.invoice.rejected',
                     'purchase_invoices', NEW.id, NULL,
                     format('Facture fournisseur %s : le retour au demandeur n''a pas été émis (règle purchase.invoice.rejected, module achats).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_invoices.rejected', 'purchase_invoices', NEW.id,
                            jsonb_build_object('number', NEW.number, 'supplier_id', NEW.supplier_id,
                                               'total', NEW.total, 'amount_due', NEW.amount_due), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.invoice.rejected', 'purchase_invoices', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 4. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r017_facture_achat_expiree ON purchase_invoices;
CREATE TRIGGER zz_b2r017_facture_achat_expiree
AFTER UPDATE ON purchase_invoices
FOR EACH ROW
EXECUTE FUNCTION public.regle_r017_facture_achat_expiree();

DROP TRIGGER IF EXISTS zz_b2r018_facture_achat_rejetee ON purchase_invoices;
CREATE TRIGGER zz_b2r018_facture_achat_rejetee
AFTER UPDATE ON purchase_invoices
FOR EACH ROW
EXECUTE FUNCTION public.regle_r018_facture_achat_rejetee();

-- Ces maillons ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r017_facture_achat_expiree() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r018_facture_achat_rejetee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r017_facture_achat_expiree() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r018_facture_achat_rejetee() TO service_role;
