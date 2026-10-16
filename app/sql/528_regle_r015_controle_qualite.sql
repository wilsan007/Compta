-- ============================================================
-- 528_regle_r015_controle_qualite.sql — partie B, lot Achats, règle R-015
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 15) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-015 = ⬜).
--
-- R-015 — `goods_receipts.status = pending` → « contrôle qualité obligatoire avant entrée
-- en stock valorisé ».
--
-- MESURÉ (B.1). Le passage d'une réception à `received` (qui ENTRE le stock :
-- `create_stock_on_goods_receipt`) ne consultait AUCUN contrôle qualité.
--
-- CE QUE CE FICHIER FAIT — une garde ADDITIVE, qui ne mord que si un contrôle EXISTE
--   * au passage d'une réception à `received` : si un CONTRÔLE QUALITÉ existe pour cette
--     réception (`quality_checks`, `reference_type = 'goods_receipt'`) et qu'il est
--     `pending` ou `failed`, l'entrée en stock est REFUSÉE avec un message nominatif ;
--   * contrôle `passed` ou `partial` : l'entrée passe (le bon du contrôle est suffisant —
--     la quantité rejetée est du ressort du contrôle, pas de cette garde) ;
--   * AUCUN contrôle : l'entrée passe, **inchangée** — c'est la garantie de non-régression
--     (les réceptions qui n'ont jamais eu de contrôle ne sont pas bloquées).
--
-- CE QUI RESTE À LA COORDINATION : rendre le contrôle OBLIGATOIRE **même en son absence**
-- (dès qu'un plan de contrôle `quality_control_plans.is_active` existe pour l'article) est
-- une DÉCISION métier — elle bloquerait des réceptions légitimes d'aujourd'hui. Non posée ici.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (garde neuve `regle_r015_…`).
-- ============================================================

CREATE OR REPLACE FUNCTION public.regle_r015_controle_qualite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
DECLARE
  v_bloquant text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'received' THEN
    RETURN NEW;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  -- Un contrôle qualité existe pour cette réception et n'est pas passé ?
  SELECT qc.status INTO v_bloquant
  FROM quality_checks qc
  WHERE qc.tenant_id = NEW.tenant_id AND qc.reference_type = 'goods_receipt'
    AND qc.reference_id = NEW.id AND qc.status IN ('pending', 'failed')
  LIMIT 1;

  IF v_bloquant IS NOT NULL THEN
    RAISE EXCEPTION 'Réception % : contrôle qualité « % » — l''entrée en stock valorisé attend un contrôle passé (règle R-015)',
      NEW.number, v_bloquant
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END $garde$;

DROP TRIGGER IF EXISTS zz_b2r015_controle_qualite ON goods_receipts;
CREATE TRIGGER zz_b2r015_controle_qualite
BEFORE UPDATE ON goods_receipts
FOR EACH ROW EXECUTE FUNCTION public.regle_r015_controle_qualite();

REVOKE ALL ON FUNCTION public.regle_r015_controle_qualite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r015_controle_qualite() TO service_role;
