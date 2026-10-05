-- ============================================================
-- 506_regle_relances_suivi.sql — partie B, lot Relances (L15), règles R-059, R-060, R-061
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 59-61) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-059/060/061 = ⬜).
--
--   R-059 — `collection_reminders.status = sent` → HORODATAGE de la relance (sans
--           quoi elle est renvoyée tous les jours : EF-02) ;
--   R-060 — `collection_reminders.status = paid` → arrêt des relances, sortie de la
--           file, mise à jour de l'ancienneté ;
--   R-061 — `collection_reminders.status = cancelled` → arrêt motivé et tracé.
--
-- MESURÉ (B.1). Aucun déclencheur sur `collection_reminders` (seul `set_tenant_id`
-- y existe) : l'horodatage de la relance ne se posait pas et la clôture (payée /
-- annulée) ne produisait rien.
--
-- NOTE D'ORDRE. Le plan range ce module (L15, budgets / engagements / relances) en
-- dernier. Il est fait AVANT la trésorerie parce que **R-059 est une règle COMPLÈTE
-- et sûre** qui ferme le défaut nommé **EF-02**, alors que les règles de trésorerie
-- (R-050, R-051) demandent une **écriture comptable** (période, équilibre) qu'il faut
-- coordonner — voir PARTIE-B.md. Deviation dite, pas subie.
--
-- CE QUE CE FICHIER FAIT
--   * R-059 : un BEFORE UPDATE pose `sent_at` (jamais écrasé s'il est déjà posé) au
--     passage à `sent`. Complète la garde `email_sent_needs_date` déjà au schéma ;
--   * R-060/R-061 : un AFTER UPDATE émet `collection_reminders.paid` /
--     `collection_reminders.cancelled` (accroche de l'arrêt des relances et de la
--     sortie de file), idempotents.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (neuf : `regle_r059_…`, `regle_r060_r061_…`).
-- ============================================================

-- ── 1. R-059 — l'horodatage de la relance (BEFORE UPDATE) ──
CREATE OR REPLACE FUNCTION public.regle_r059_relance_horodatee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
BEGIN
  IF NEW.status = 'sent' AND OLD.status IS DISTINCT FROM 'sent' THEN
    NEW.sent_at := COALESCE(NEW.sent_at, now());
  END IF;
  RETURN NEW;
END $garde$;

-- ── 2. Les contrats d'effet de la clôture (R-060, R-061) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'collection_reminders', 'paid', 'sale.reminder.paid',
        false, NULL, false, false, true, false, true,
        'R-060 : relance clôturée par le paiement. Partie B, lot Relances.'),
       (NULL, 'collection_reminders', 'cancelled', 'sale.reminder.cancelled',
        false, NULL, false, false, true, false, true,
        'R-061 : relance annulée (motivée et tracée). Partie B, lot Relances.')
ON CONFLICT DO NOTHING;

-- ── 3. R-060 / R-061 — la clôture de la relance (AFTER UPDATE) ──
CREATE OR REPLACE FUNCTION public.regle_r060_r061_relance_cloture()
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('paid', 'cancelled') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NEW.status = 'paid' THEN
    v_effet := 'sale.reminder.paid';      v_event := 'collection_reminders.paid';
  ELSE
    v_effet := 'sale.reminder.cancelled'; v_event := 'collection_reminders.cancelled';
  END IF;

  -- Idempotence propre (ce maillon ne pose aucun lien).
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = v_event
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'collection_reminders', NEW.status, v_effet,
                     'collection_reminders', NEW.id, NULL,
                     format('Relance %s : la clôture (« %s ») n''a pas été tracée (règle %s, module relances).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'collection_reminders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'customer_id', NEW.customer_id,
                                               'invoice_id', NEW.invoice_id, 'amount', NEW.amount,
                                               'reminder_level', NEW.reminder_level), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'collection_reminders', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 4. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r059_relance_horodatee ON collection_reminders;
CREATE TRIGGER zz_b2r059_relance_horodatee
BEFORE UPDATE ON collection_reminders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r059_relance_horodatee();

DROP TRIGGER IF EXISTS zz_b2r060_r061_relance_cloture ON collection_reminders;
CREATE TRIGGER zz_b2r060_r061_relance_cloture
AFTER UPDATE ON collection_reminders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r060_r061_relance_cloture();

-- Ces gardes/maillons ne sont pas des points d'entrée (aucun EXECUTE applicatif).
REVOKE ALL ON FUNCTION public.regle_r059_relance_horodatee() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r060_r061_relance_cloture() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r059_relance_horodatee() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r060_r061_relance_cloture() TO service_role;
