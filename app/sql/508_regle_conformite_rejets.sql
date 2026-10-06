-- ============================================================
-- 508_regle_conformite_rejets.sql — partie B, lot Conformité, règles R-054, R-055, R-056
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 54-56) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-054/055/056 = ⬜).
--
--   R-054 — `vat_returns.edi_status = rejected` → alerte bloquante, retour en
--           préparation, conservation des motifs de rejet ;
--   R-055 — `dsn_declarations.status = rejected` → alerte bloquante RH, correction,
--           rejeu, historique des rejets ;
--   R-056 — `social_declarations.status = rejected` → idem, impact cotisations / PAS.
--
-- MESURÉ (B.1). Aucun déclencheur ne testait ces rejets (`vat_returns` n'a que
-- `set_tenant_id` + `trg_refuse_client_edi_stamp` ; `dsn_declarations` et
-- `social_declarations` n'ont que `set_tenant_id`). Un rejet d'administration ne
-- produisait RIEN : ni alerte, ni trace.
--
-- CE QUE CE FICHIER FAIT — trois maillons « événement », aucune écriture métier
--   * `vat_returns.edi_status → rejected`   : émet `vat_returns.edi_rejected` ;
--   * `dsn_declarations.status → rejected`  : émet `dsn_declarations.rejected` ;
--   * `social_declarations.status → rejected`: émet `social_declarations.rejected`.
--   Chaque événement est le point d'accroche de l'ALERTE bloquante et de la correction /
--   rejeu (partie F pour l'écran). IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUE CE FICHIER NE FAIT PAS : R-052 (`vat_returns.status = submitted`, « gel des
-- écritures de la période ») touche le VERROU des périodes comptables — à coordonner
-- avec la comptabilité, pas écrit ici.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_conformite_*`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'vat_returns', 'rejected', 'tax.vat_return.edi_rejected',
        false, NULL, false, false, true, false, true,
        'R-054 : déclaration de TVA rejetée par l''administration. Partie B, lot Conformité.'),
       (NULL, 'dsn_declarations', 'rejected', 'payroll.dsn.rejected',
        false, NULL, false, true, true, false, true,
        'R-055 : DSN rejetée. Partie B, lot Conformité.'),
       (NULL, 'social_declarations', 'rejected', 'payroll.social_declaration.rejected',
        false, NULL, false, true, true, false, true,
        'R-056 : déclaration sociale rejetée. Partie B, lot Conformité.')
ON CONFLICT DO NOTHING;

-- ── 2. R-054 — le rejet EDI de la déclaration de TVA ──
CREATE OR REPLACE FUNCTION public.regle_conformite_vat_rejet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.edi_status IS NOT DISTINCT FROM OLD.edi_status OR NEW.edi_status IS DISTINCT FROM 'rejected' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'vat_returns.edi_rejected'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'vat_returns', 'rejected', 'tax.vat_return.edi_rejected',
                     'vat_returns', NEW.id, NULL,
                     format('Déclaration de TVA %s : le rejet EDI n''a pas été tracé (règle tax.vat_return.edi_rejected, module conformité).',
                            NEW.id)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'vat_returns.edi_rejected', 'vat_returns', NEW.id,
                            jsonb_build_object('status', NEW.status, 'edi_status', NEW.edi_status), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'tax.vat_return.edi_rejected', 'vat_returns', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. R-055 — le rejet de la DSN ──
CREATE OR REPLACE FUNCTION public.regle_conformite_dsn_rejet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'rejected' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'dsn_declarations.rejected'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'dsn_declarations', 'rejected', 'payroll.dsn.rejected',
                     'dsn_declarations', NEW.id, NULL,
                     format('DSN %s : le rejet n''a pas été tracé (règle payroll.dsn.rejected, module conformité).',
                            NEW.period)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'dsn_declarations.rejected', 'dsn_declarations', NEW.id,
                            jsonb_build_object('period', NEW.period, 'type', NEW.type, 'status', NEW.status), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'payroll.dsn.rejected', 'dsn_declarations', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 4. R-056 — le rejet de la déclaration sociale ──
CREATE OR REPLACE FUNCTION public.regle_conformite_social_rejet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'rejected' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'social_declarations.rejected'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'social_declarations', 'rejected', 'payroll.social_declaration.rejected',
                     'social_declarations', NEW.id, NULL,
                     format('Déclaration sociale %s : le rejet n''a pas été tracé (règle payroll.social_declaration.rejected, module conformité).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'social_declarations.rejected', 'social_declarations', NEW.id,
                            jsonb_build_object('number', NEW.number, 'period', NEW.period,
                                               'amount', NEW.amount, 'status', NEW.status), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'payroll.social_declaration.rejected', 'social_declarations', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 5. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r054_vat_rejet ON vat_returns;
CREATE TRIGGER zz_b2r054_vat_rejet
AFTER UPDATE ON vat_returns
FOR EACH ROW
EXECUTE FUNCTION public.regle_conformite_vat_rejet();

DROP TRIGGER IF EXISTS zz_b2r055_dsn_rejet ON dsn_declarations;
CREATE TRIGGER zz_b2r055_dsn_rejet
AFTER UPDATE ON dsn_declarations
FOR EACH ROW
EXECUTE FUNCTION public.regle_conformite_dsn_rejet();

DROP TRIGGER IF EXISTS zz_b2r056_social_rejet ON social_declarations;
CREATE TRIGGER zz_b2r056_social_rejet
AFTER UPDATE ON social_declarations
FOR EACH ROW
EXECUTE FUNCTION public.regle_conformite_social_rejet();

-- Ces maillons ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_conformite_vat_rejet() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_conformite_dsn_rejet() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_conformite_social_rejet() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_conformite_vat_rejet() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_conformite_dsn_rejet() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_conformite_social_rejet() TO service_role;
