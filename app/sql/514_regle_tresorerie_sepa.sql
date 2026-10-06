-- ============================================================
-- 514_regle_tresorerie_sepa.sql — partie B, lot Trésorerie, règles R-048 et R-049
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 48-49) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-048/049 = ⬜).
--
--   R-048 — `sepa_payment_orders.status = rejected` → alerte, réouverture des paiements,
--           correction et rejeu, conservation du motif bancaire ;
--   R-049 — `sepa_payment_orders.status = processed` → rapprochement bancaire
--           automatique, changement d'état des factures, échéancier.
--
-- MESURÉ (B.1). `sepa_payment_orders` n'avait que `set_tenant_id` : un rejet ou une
-- acceptation d'un ordre SEPA ne produisait RIEN.
--
-- CE QUE CE FICHIER FAIT — deux maillons « événement » (accroches)
--   * `rejected`  : émet `sepa_payment_orders.rejected` (motif de rejet côté banque,
--     réouverture / rejeu) ;
--   * `processed` : émet `sepa_payment_orders.processed` (accroche du rapprochement
--     bancaire et du changement d'état des règlements).
--   IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUI RESTE À LA COORDINATION : la RÉOUVERTURE effective des paiements (défaire le
-- règlement) et le RAPPROCHEMENT BANCAIRE automatique sont des effets de trésorerie /
-- comptables (`bank_transactions`, lettrage) partagés — leur chaînage se fait avec les
-- décaissements, pas dans cet événement.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_sepa_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'sepa_payment_orders', 'rejected', 'treasury.sepa.rejected',
        false, NULL, false, false, true, false, true,
        'R-048 : ordre SEPA rejeté — alerte, rejeu. Partie B, lot Trésorerie.'),
       (NULL, 'sepa_payment_orders', 'processed', 'treasury.sepa.processed',
        false, NULL, false, false, true, false, true,
        'R-049 : ordre SEPA traité — rapprochement, échéancier. Partie B, lot Trésorerie.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : état d'un ordre SEPA → événement ──
CREATE OR REPLACE FUNCTION public.regle_sepa_etat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_effet text;
  v_event text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('rejected', 'processed') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NEW.status = 'rejected' THEN
    v_effet := 'treasury.sepa.rejected'; v_event := 'sepa_payment_orders.rejected';
  ELSE
    v_effet := 'treasury.sepa.processed'; v_event := 'sepa_payment_orders.processed';
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'sepa_payment_orders', NEW.status, v_effet,
                     'sepa_payment_orders', NEW.id, NULL,
                     format('Ordre SEPA %s : l''état « %s » n''a pas été tracé (règle %s, module trésorerie).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'sepa_payment_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'status', NEW.status,
                                               'total_amount', NEW.total_amount, 'pay_run_id', NEW.pay_run_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'sepa_payment_orders', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r048_r049_sepa_etat ON sepa_payment_orders;
CREATE TRIGGER zz_b2r048_r049_sepa_etat
AFTER UPDATE ON sepa_payment_orders
FOR EACH ROW
EXECUTE FUNCTION public.regle_sepa_etat();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_sepa_etat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_sepa_etat() TO service_role;
