-- ============================================================
-- 504_regle_ventes_devis_expire.sql — partie B, lot Ventes, règle R-002
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 2) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-002 = ⬜).
--
-- R-002 — « quotes.status = expired → libération de la réservation, relance CRM,
-- statistique de perte ».
--
-- MESURÉ (B.1). Aucun déclencheur sur `quotes` ne testait `expired`. L'expiration
-- d'un devis ne produisait RIEN : ni relance, ni perte comptée.
--
-- CE QUE CE FICHIER FAIT — un maillon (événement + trace)
--   * au passage d'un devis à `expired` : il ÉMET `quotes.expired` (payload : numéro,
--     client, total, échéance) — c'est le point d'accroche de la RELANCE CRM (partie F)
--     et de la STATISTIQUE DE PERTE ;
--   * il trace l'entrée / la sortie du maillon (contrat `sale.quote.expired`) ;
--   * il est IDEMPOTENT — par une garde PROPRE : l'idempotence de `chain_avant`
--     (`chain_deja_fait`) lit `document_links`, et ce maillon ne pose AUCUN lien
--     (il n'émet qu'un événement). On refuse donc un second `quotes.expired`.
--
-- « LIBÉRATION DE LA RÉSERVATION » : il n'y a rien à libérer. Un devis ne réserve
-- pas de stock — la réservation naît à la CONFIRMATION de la commande
-- (`reserve_stock_on_sales_order_confirm`), et si le devis n'a jamais été accepté,
-- aucune commande ni réservation n'existe. Le dire ici vaut mieux que d'inventer
-- une libération sans objet.
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'quotes', 'expired', 'sale.quote.expired',
        false, NULL, false, false,
        true, false, true,
        'R-002 : un devis expiré émet l évènement (relance CRM, statistique de perte). Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : devis expiré → événement ──
CREATE OR REPLACE FUNCTION public.regle_r002_devis_expire()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  -- Fait générateur : le devis vient d'être marqué « expiré ».
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'expired' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Idempotence PROPRE à ce maillon : `chain_avant` protège par le LIEN
  -- (`chain_deja_fait` lit `document_links`), et ce maillon n'en pose aucun —
  -- il n'émet qu'un événement. On refuse donc un second `quotes.expired`.
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'quotes.expired'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  -- Entrée du maillon — rejeu, contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'quotes', 'expired', 'sale.quote.expired',
                     'quotes', NEW.id, NULL,
                     format('Devis %s : la règle d''expiration n''a pas été appliquée (sale.quote.expired, module ventes).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- L'ÉVÉNEMENT : le point d'accroche de la relance CRM et de la perte.
  PERFORM emit_domain_event(NEW.tenant_id, 'quotes.expired', 'quotes', NEW.id,
                            jsonb_build_object('number', NEW.number, 'customer_id', NEW.customer_id,
                                               'total', NEW.total, 'expiry_date', NEW.expiry_date), NULL);

  -- La mesure.
  PERFORM chain_apres(NEW.tenant_id, 'sale.quote.expired', 'quotes', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (nommé `zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r002_devis_expire ON quotes;
CREATE TRIGGER zz_b2r002_devis_expire
AFTER UPDATE ON quotes
FOR EACH ROW
EXECUTE FUNCTION public.regle_r002_devis_expire();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r002_devis_expire() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r002_devis_expire() TO service_role;
