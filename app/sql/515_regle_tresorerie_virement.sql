-- ============================================================
-- 515_regle_tresorerie_virement.sql — partie B, lot Trésorerie, règles R-050 et R-051
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 50-51) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-050/051 = ⬜).
--
--   R-050 — `treasury_transfers.status = executed` → écriture du virement d'un compte à
--           l'autre, mise à jour des deux soldes, prévisionnel ;
--   R-051 — `treasury_transfers.status = cancelled` → contre-passation, restitution des soldes.
--
-- MESURÉ (B.1). `treasury_transfers` n'avait que `set_tenant_id` : un virement exécuté
-- ou annulé ne produisait RIEN.
--
-- CE QUE CE FICHIER FAIT — deux maillons « événement » (accroches)
--   * `executed`  : émet `treasury_transfers.executed` ;
--   * `cancelled` : émet `treasury_transfers.cancelled`.
--   IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUI RESTE À LA COORDINATION (et pourquoi) — l'ÉCRITURE COMPTABLE
--   R-050/R-051 demandent une **écriture de virement** (D compte du compte d'arrivée /
--   C compte du compte de départ) et une **contre-passation**. Le schéma la prépare
--   (`treasury_transfers.journal_entry_id`, `bank_accounts.account_code`/`journal_code`),
--   mais l'écrire depuis un déclencheur d'ÉTAT touche le **noyau comptable** (journal,
--   équilibre, période ouverte) et la **détermination des soldes** — un travail à faire
--   d'un seul tenant avec la comptabilité (R7). Chemin pressenti : insérer
--   `journal_entries` + 2 `journal_lines` équilibrées, poster, renseigner
--   `journal_entry_id`, lier (`generated_entry`). Poser l'écriture SEULE, sans la
--   dérivation des soldes ni l'ouverture de période, serait incomplet et dangereux.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_virement_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'treasury_transfers', 'executed', 'treasury.transfer.executed',
        false, NULL, false, false, true, false, true,
        'R-050 : virement exécuté — accroche de l''écriture de virement et des soldes. Partie B, lot Trésorerie.'),
       (NULL, 'treasury_transfers', 'cancelled', 'treasury.transfer.cancelled',
        false, NULL, false, false, true, false, true,
        'R-051 : virement annulé — contre-passation, restitution des soldes. Partie B, lot Trésorerie.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : état d'un virement → événement ──
CREATE OR REPLACE FUNCTION public.regle_virement_etat()
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('executed', 'cancelled') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NEW.status = 'executed' THEN
    v_effet := 'treasury.transfer.executed'; v_event := 'treasury_transfers.executed';
  ELSE
    v_effet := 'treasury.transfer.cancelled'; v_event := 'treasury_transfers.cancelled';
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'treasury_transfers', NEW.status, v_effet,
                     'treasury_transfers', NEW.id, NULL,
                     format('Virement %s : l''état « %s » n''a pas été tracé (règle %s, module trésorerie).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'treasury_transfers', NEW.id,
                            jsonb_build_object('number', NEW.number, 'status', NEW.status,
                                               'amount', NEW.amount, 'from_account_id', NEW.from_account_id,
                                               'to_account_id', NEW.to_account_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'treasury_transfers', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r050_r051_virement_etat ON treasury_transfers;
CREATE TRIGGER zz_b2r050_r051_virement_etat
AFTER UPDATE ON treasury_transfers
FOR EACH ROW
EXECUTE FUNCTION public.regle_virement_etat();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_virement_etat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_virement_etat() TO service_role;
