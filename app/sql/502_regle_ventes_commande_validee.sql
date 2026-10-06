-- ============================================================
-- 502_regle_ventes_commande_validee.sql — partie B, lot Ventes, règle R-005
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 5) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-005 = ⬜).
--
-- R-005 — « sales_orders.validation_status = validated → numéro définitif, lignes
-- gelées, historique ».
--
-- MESURÉ (B.1). La validation d'une commande ne déclenchait RIEN. Le gel des
-- lignes n'existait que pour les statuts `delivered / invoiced / cancelled`
-- (`sales_order_line_compute`, 133) — PAS pour une commande validée.
--
-- CE QUE CE FICHIER FAIT — deux gardes, aucune écriture d'effet aval
--   * à la VALIDATION : si le numéro est encore un brouillon (`BROUILLON-…` — c'est
--     celui que pose R-001), il devient le numéro DÉFINITIF (`next_legal_document_number`,
--     série `CMD`). Un numéro déjà définitif (posé par l'écran) n'est PAS changé ;
--   * une commande VALIDÉE est IMMUABLE : on ne défait pas la validation, et client /
--     date / devis d'origine / numéro ne changent plus (les TOTAUX, eux, restent
--     recalculés par `order_header_totals` — ils n'entrent pas dans le gel) ;
--   * les LIGNES d'une commande validée sont GELÉES (insertion, modification,
--     suppression refusées avec un message nominatif).
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * aucune écriture comptable ni de stock : R-005 est une garde, pas un maillon ;
--     c'est pourquoi il n'y a ni contrat `document_effects` ni trace `chain_*` ici.
--   * l'« historique » est porté par l'audit NF525 des factures et le journal
--     d'événements, pas par cette garde.
--
-- PRIORITÉ R7 : ce fichier n'écrit AUCUNE fonction existante (les gardes sont
-- neuves : `regle_r005_…`). Il ne touche donc pas `sales_order_line_compute`.
-- ============================================================

-- ── 1. La garde d'en-tête : validation → numéro définitif, puis immuabilité ──
CREATE OR REPLACE FUNCTION public.regle_r005_commande_validee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
BEGIN
  -- 1. La validation : le numéro de brouillon devient définitif.
  IF NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated' THEN
    IF NEW.number LIKE 'BROUILLON-%' THEN
      NEW.number := next_legal_document_number(NEW.tenant_id, 'CMD', NEW.order_date);
    END IF;
    RETURN NEW;
  END IF;

  -- 2. Une commande validée est immuable (hors totaux, recalculés par `order_header_totals`).
  IF OLD.validation_status = 'validated' THEN
    IF NEW.validation_status IS DISTINCT FROM 'validated' THEN
      RAISE EXCEPTION 'Commande % validée : sa validation ne se retire pas', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.customer_id, NEW.order_date, NEW.quote_id, NEW.number) IS DISTINCT FROM
       (OLD.customer_id, OLD.order_date, OLD.quote_id, OLD.number) THEN
      RAISE EXCEPTION 'Commande % validée : client, date, devis d''origine et numéro ne sont plus modifiables', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $garde$;

-- ── 2. La garde des lignes : une commande validée gèle ses lignes ──
CREATE OR REPLACE FUNCTION public.regle_r005_lignes_gelees()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
DECLARE
  v_num text;
  v_val text;
  v_order uuid;
  v_tid   uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_order := OLD.sales_order_id; v_tid := OLD.tenant_id;
  ELSE
    v_order := NEW.sales_order_id; v_tid := NEW.tenant_id;
  END IF;

  IF v_order IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  SELECT o.number, o.validation_status INTO v_num, v_val
  FROM sales_orders o WHERE o.id = v_order AND o.tenant_id = v_tid;

  IF v_val = 'validated' THEN
    RAISE EXCEPTION 'Commande % validée : ses lignes sont gelées', v_num
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $garde$;

-- ── 3. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r005_commande_validee ON sales_orders;
CREATE TRIGGER zz_b2r005_commande_validee
BEFORE UPDATE ON sales_orders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r005_commande_validee();

DROP TRIGGER IF EXISTS zz_b2r005_lignes_gelees ON sales_order_lines;
CREATE TRIGGER zz_b2r005_lignes_gelees
BEFORE INSERT OR UPDATE OR DELETE ON sales_order_lines
FOR EACH ROW
EXECUTE FUNCTION public.regle_r005_lignes_gelees();

-- Ces gardes ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r005_commande_validee() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r005_lignes_gelees() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r005_commande_validee() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r005_lignes_gelees() TO service_role;
