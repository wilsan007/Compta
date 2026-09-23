-- ============================================================
-- 218_document_number_seed.sql — D-12 : la suite reprend après le plus grand
-- numéro déjà utilisé, jamais à 1 sur une société reprise
--
-- Décision D-12 tranchée par la mesure, sur la copie de production du 23/09 :
--   * 0 doublon de numéro intra-société aujourd'hui — les séquences posées par
--     la 190 font leur travail pour les documents validés depuis ;
--   * mais 1 société (celle de reprise, exercice EX2024) a des factures
--     FAC-2024-001 à 005 et AUCUNE ligne de séquence : le premier document
--     validé reçoit le numéro 1, déjà porté par une facture du même exercice ;
--   * partout ailleurs, séquence > plus grand numéro utilisé (cohérent).
--
-- L'option (b) « repartir à 1 par exercice » produirait donc un numéro déjà
-- attribué dans la même société et le même exercice dès la prochaine validation
-- d'une société reprise : un numéro de pièce doit rester unique et continu, et
-- le FEC comme l'administration s'y réfèrent. L'option (a) retenue ne coûte
-- qu'une lecture au premier document d'un exercice, et ne renumérote rien.
--
-- Trois pièces :
--   1. document_number_used_max(tenant, préfixe, année) — plus grand numéro
--      déjà porté par un document de cette société, tous types confondus
--      (FAC, ACH, AV, AVF, DEV), au format légal de l'année ;
--   2. next_legal_document_number (216) : au PREMIER document d'un exercice, la
--      séquence démarre après ce plus grand numéro ; un compteur existant n'est
--      jamais rabaissé ;
--   3. repair_document_number_sequences() — remonte les compteurs restés en
--      retard, idempotente, appelée par cette migration et rejouable à la main.
--
-- Ce qui n'est PAS touché, comme en 216 : les numéros déjà attribués. Une pièce
-- validée est figée, un FEC déposé y renvoie ; normaliser l'historique serait
-- une décision à part, avec son impact sur les déclarations déjà déposées.
--
-- R-14 (devis) documenté ici aussi : un devis est numéroté À SA CRÉATION
-- (quote_assign_number, 190) et non à sa validation — ce n'est pas une pièce
-- comptable. Un brouillon de devis supprimé laisse donc un trou dans la suite
-- DEV : c'est licite pour un devis, et c'est désormais écrit (COMMENT), au lieu
-- de rester un écart entre deux comportements. Le devis créé hors exercice
-- garde une suite propre au préfixe, sans année : hors exercice, il n'y a pas
-- d'année à porter, et le devis n'est pas opposable.
--
-- Preuve : sql/218_document_number_seed_tests.sql (D01 à D05), vu rouge avant.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Plus grand numéro déjà utilisé, par société, préfixe et année
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION document_number_used_max(p_tenant uuid, p_prefix text, p_year text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Format légal : PREFIX-ANNÉE-suffixe. Écarte les brouillons
  -- (BROUILLON-FAC-…) et les numéros d'un autre exercice.
  v_pat text := '^' || p_prefix || '-' || p_year || '-([0-9]+)$';
  v_max integer := 0;
BEGIN
  EXECUTE format($q$
    SELECT COALESCE(max(substring(number from %L)::int), 0)
    FROM (
      SELECT number FROM invoices              WHERE tenant_id = $1 AND number ~ %L
      UNION ALL
      SELECT number FROM purchase_invoices     WHERE tenant_id = $1 AND number ~ %L
      UNION ALL
      SELECT number FROM credit_notes          WHERE tenant_id = $1 AND number ~ %L
      UNION ALL
      SELECT number FROM purchase_credit_notes WHERE tenant_id = $1 AND number ~ %L
      UNION ALL
      SELECT number FROM quotes                WHERE tenant_id = $1 AND number ~ %L
    ) d
  $q$, v_pat, v_pat, v_pat, v_pat, v_pat, v_pat) INTO v_max USING p_tenant;
  RETURN COALESCE(v_max, 0);
END $$;
REVOKE ALL ON FUNCTION document_number_used_max(uuid, text, text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION document_number_used_max(uuid, text, text) IS
  'Plus grand suffixe déjà attribué pour un préfixe légal et une année (D-12, 218). '
  'Sert de point de reprise à la numérotation d''une société reprise.';
-- ------------------------------------------------------------
-- 2. next_legal_document_number : point de reprise au premier document
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION next_legal_document_number(p_tenant uuid, p_prefix text, p_date date)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_fy fiscal_years%ROWTYPE; v_next int; v_year text; v_seed integer := 0;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = p_tenant AND p_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun exercice ne couvre le % : créez l''exercice avant de valider', to_char(p_date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  -- 216 : l'année de l'exercice, jamais son libellé libre
  v_year := fiscal_year_number_segment(v_fy);

  -- D-12 : la graine n'est lue qu'au premier document de l'exercice — le
  -- chemin courant (compteur existant) ne paie pas la lecture.
  IF NOT EXISTS (SELECT 1 FROM document_number_sequences
                 WHERE tenant_id = p_tenant AND prefix = p_prefix AND fiscal_year_id = v_fy.id) THEN
    v_seed := document_number_used_max(p_tenant, p_prefix, v_year);
  END IF;

  -- La fonction rend next_number - 1 : avec la graine, la ligne est posée à
  -- v_seed + 2 pour que le premier document reçoive v_seed + 1.
  INSERT INTO document_number_sequences AS s (tenant_id, prefix, fiscal_year_id, next_number)
  VALUES (p_tenant, p_prefix, v_fy.id, v_seed + 2)
  ON CONFLICT (tenant_id, prefix, fiscal_year_id) WHERE fiscal_year_id IS NOT NULL
  DO UPDATE SET next_number = s.next_number + 1, updated_at = now()
  RETURNING next_number - 1 INTO v_next;

  RETURN p_prefix || '-' || v_year || '-' || lpad(v_next::text, 6, '0');
END $$;
REVOKE ALL ON FUNCTION next_legal_document_number(uuid, text, date) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION next_legal_document_number(uuid, text, date) IS
  'Numéro légal d''une pièce : PREFIX-ANNÉE-nnnnnn (216). Le segment est l''année de '
  'l''exercice, jamais son libellé. Au premier document d''un exercice, la suite reprend '
  'après le plus grand numéro déjà attribué à la société (D-12, 218).';

-- ------------------------------------------------------------
-- 3. Réparation des compteurs restés en retard (jamais d'abaissement)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION repair_document_number_sequences()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE r record; v_year text; v_max integer; v_n integer := 0;
BEGIN
  FOR r IN
    SELECT s.id, s.tenant_id, s.prefix, s.next_number, fy AS fy_row
    FROM document_number_sequences s
    JOIN fiscal_years fy ON fy.id = s.fiscal_year_id
  LOOP
    v_year := fiscal_year_number_segment(r.fy_row);
    v_max := document_number_used_max(r.tenant_id, r.prefix, v_year);
    -- next_number EST le prochain numéro à attribuer : il doit dépasser ce qui
    -- existe déjà. Un compteur en avance n'est jamais rabaissé — un numéro
    -- attribué à une pièce supprimée reste consommé.
    IF r.next_number <= v_max THEN
      UPDATE document_number_sequences SET next_number = v_max + 1, updated_at = now()
      WHERE id = r.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION repair_document_number_sequences() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION repair_document_number_sequences() IS
  'Remonte les compteurs de numérotation restés sous le plus grand numéro utilisé '
  '(sociétés reprises). Idempotente, ne rabaisse jamais un compteur (D-12, 218).';

DO $$
DECLARE v_n integer;
BEGIN
  v_n := repair_document_number_sequences();
  RAISE NOTICE '218 : % compteur(s) de numérotation remonté(s) au-dessus des numéros déjà attribués', v_n;
END $$;

-- R-14 : la règle de numérotation des devis est écrite au lieu d'être implicite
COMMENT ON COLUMN quotes.number IS
  'Numéro du devis, attribué À LA CRÉATION (quote_assign_number, 190) et non à la '
  'validation : un devis n''est pas une pièce comptable. Un brouillon supprimé laisse '
  'donc un trou dans la suite DEV — licite pour un devis (R-14, 218).';