-- ============================================================
-- 524_regle_r047_transfert_lie.sql — partie B, lot Stock, règle R-047 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 47) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-047 = 🟨).
--
-- R-047 — `stock_movements.movement_type = transfer` → transfert entre dépôts : DEUX
-- mouvements liés (sortie + entrée), valorisation conservée, suivi des biens en transit.
--
-- MESURÉ : la `519` a rendu chaque mouvement de transfert OBSERVABLE (événement). Ce qui
-- manquait, c'est le LIEN entre les DEUX jambes du transfert. Le schéma ne porte qu'UN
-- dépôt par mouvement (`stock_movements.warehouse_id`) ET pas de dépôt de destination —
-- un transfert est donc DEUX lignes qui partagent leur `reference`.
--
-- CE QUE CE FICHIER FAIT — le LIEN entre les deux jambes
--   * à l'INSERTION d'un mouvement `transfer` : cherche le(s) AUTRE(S) mouvement(s)
--     `transfer` de MÊME (société, reference) et les LIE (document_links, `reversed_by`) —
--     c'est « les deux mouvements liés » ;
--   * idempotent : un lien déjà posé n'est pas reposé (`chain_deja_fait` lit `document_links`) ;
--   * sans contrepartie (ou sans `reference`) : il trace `sans_effet` — le lien se posera à
--     l'arrivée de la seconde jambe. **La valorisation est conservée** parce que le
--     mouvement d'entrée reprend le `unit_cost` de la sortie (déjà au schéma) ; le suivi
--     « en transit » n'a pas de table au schéma.
--
-- CE QUI RESTE À LA COORDINATION : l'ENTRÉE en stock proprement dite (le second mouvement)
-- est créée par l'écran / le noyau (partie E) — ce fichier LIE les deux, il ne les crée pas.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r047_…`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'stock_movements', 'transfer_paired', 'stock.transfer.linked',
        false, NULL, true, false, true, false, true,
        'R-047 : les deux jambes d''un transfert sont liées. Partie B, lot Stock.')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.regle_r047_transfert_lie()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_liens integer := 0;
  v_a     record;
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'transfer' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Entrée du maillon (rejeu par le lien, contrat, drapeau).
  IF NOT chain_avant(NEW.tenant_id, 'stock_movements', 'transfer_paired', 'stock.transfer.linked',
                     'stock_movements', NEW.id, NULL,
                     format('Mouvement de transfert %s : le lien entre les deux jambes n''a pas été posé (règle stock.transfer.linked, module stock).',
                            NEW.id)) THEN
    RETURN NULL;
  END IF;

  -- LA SECONDE JAMBE : un autre mouvement `transfer` de même référence.
  IF NEW.reference IS NOT NULL THEN
    FOR v_a IN
      SELECT sm.id
      FROM stock_movements sm
      WHERE sm.tenant_id = NEW.tenant_id AND sm.movement_type = 'transfer'
        AND sm.id <> NEW.id AND sm.reference = NEW.reference
        AND sm.reference_type IS NOT DISTINCT FROM NEW.reference_type
      ORDER BY sm.created_at, sm.id
    LOOP
      PERFORM link_documents(NEW.tenant_id, 'stock_movements', NEW.id, 'stock_movements', v_a.id,
                             'stock.transfer.linked', 'reversed_by',
                             jsonb_build_object('reference', NEW.reference, 'product_id', NEW.product_id));
      v_liens := v_liens + 1;
    END LOOP;
  END IF;

  IF v_liens = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'stock.transfer.linked', 'stock_movements', NEW.id,
                        v_debut, 0, 'sans_effet', 'Contrepartie de transfert pas encore présente (référence absente ou seconde jambe à venir).', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'stock_movements.transfer_paired', 'stock_movements', NEW.id,
                            jsonb_build_object('reference', NEW.reference, 'product_id', NEW.product_id,
                                               'jambes_liees', v_liens), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'stock.transfer.linked', 'stock_movements', NEW.id,
                      v_debut, v_liens, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r047_transfert_lie ON stock_movements;
CREATE TRIGGER zz_b2r047_transfert_lie
AFTER INSERT ON stock_movements
FOR EACH ROW EXECUTE FUNCTION public.regle_r047_transfert_lie();

REVOKE ALL ON FUNCTION public.regle_r047_transfert_lie() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r047_transfert_lie() TO service_role;
