-- ============================================================
-- 503_regle_ventes_devis_valide.sql — partie B, lot Ventes, règle R-003
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 3) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-003 = ⬜).
--
-- R-003 — « quotes.validation_status = validated → numérotation définitive,
-- immuabilité des lignes, verrou de modification ».
--
-- MESURÉ (B.1). Aucun déclencheur sur `quotes` ne testait la validation. Le numéro
-- n'était posé qu'à l'INSERT (`tg_quote_number`) et rien ne figeait un devis validé.
--
-- CE QUE CE FICHIER FAIT — deux gardes, aucune écriture d'effet aval
--   * à la VALIDATION : si le numéro est encore un brouillon (`BROUILLON-…`), il
--     devient le numéro DÉFINITIF (`next_legal_document_number`, série `DEV`) ;
--   * un devis VALIDÉ est verrouillé : la validation ne se retire pas, et client /
--     date / échéance / numéro ne changent plus ;
--   * les LIGNES d'un devis validé sont GELÉES (insertion, modification,
--     suppression refusées).
--
-- CE QUI RESTE PERMIS sur un devis validé (et pourquoi) — la TRANSFORMATION :
-- R-001 écrit `transformed_to_order_id` / `transformation_status` quand le devis est
-- accepté, et un devis peut être validé AVANT d'être accepté. Le verrou ne porte
-- donc PAS sur ces deux colonnes : les figer casserait le chaînage R-001.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (gardes neuves `regle_r003_…`).
-- ============================================================

-- ── 1. La garde d'en-tête : validation → numéro définitif, puis verrou ──
CREATE OR REPLACE FUNCTION public.regle_r003_devis_valide()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
BEGIN
  -- 1. La validation : le numéro de brouillon devient définitif.
  IF NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated' THEN
    IF NEW.number LIKE 'BROUILLON-%' THEN
      NEW.number := next_legal_document_number(NEW.tenant_id, 'DEV', NEW.date);
    END IF;
    RETURN NEW;
  END IF;

  -- 2. Un devis validé est verrouillé (hors transformation, laissée à R-001).
  IF OLD.validation_status = 'validated' THEN
    IF NEW.validation_status IS DISTINCT FROM 'validated' THEN
      RAISE EXCEPTION 'Devis % validé : sa validation ne se retire pas', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.customer_id, NEW.date, NEW.expiry_date, NEW.number) IS DISTINCT FROM
       (OLD.customer_id, OLD.date, OLD.expiry_date, OLD.number) THEN
      RAISE EXCEPTION 'Devis % validé : client, date, échéance et numéro ne sont plus modifiables', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $garde$;

-- ── 2. La garde des lignes : un devis validé gèle ses lignes ──
CREATE OR REPLACE FUNCTION public.regle_r003_lignes_gelees()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $garde$
DECLARE
  v_num text;
  v_val text;
  v_quote uuid;
  v_tid   uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_quote := OLD.quote_id; v_tid := OLD.tenant_id;
  ELSE
    v_quote := NEW.quote_id; v_tid := NEW.tenant_id;
  END IF;

  IF v_quote IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  SELECT q.number, q.validation_status INTO v_num, v_val
  FROM quotes q WHERE q.id = v_quote AND q.tenant_id = v_tid;

  IF v_val = 'validated' THEN
    RAISE EXCEPTION 'Devis % validé : ses lignes sont gelées', v_num
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $garde$;

-- ── 3. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r003_devis_valide ON quotes;
CREATE TRIGGER zz_b2r003_devis_valide
BEFORE UPDATE ON quotes
FOR EACH ROW
EXECUTE FUNCTION public.regle_r003_devis_valide();

DROP TRIGGER IF EXISTS zz_b2r003_lignes_gelees ON quote_lines;
CREATE TRIGGER zz_b2r003_lignes_gelees
BEFORE INSERT OR UPDATE OR DELETE ON quote_lines
FOR EACH ROW
EXECUTE FUNCTION public.regle_r003_lignes_gelees();

-- Ces gardes ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r003_devis_valide() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r003_lignes_gelees() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r003_devis_valide() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r003_lignes_gelees() TO service_role;
