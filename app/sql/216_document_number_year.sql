-- ============================================================
-- 216_document_number_year.sql — le numéro légal porte l'ANNÉE, pas le libellé
--
-- Trouvé le 23/09 par la répétition sur copie de production (P0-06) : une
-- facture validée sur une société créée par l'inscription réelle reçoit le
-- numéro `FAC-FY2026-000001`, et non `FAC-2026-000001`.
--
-- Cause : next_legal_document_number (190) concatène `fiscal_years.code`, qui
-- est un libellé libre. En production il vaut selon les sociétés `2026`,
-- `FY2026` (code posé par bootstrap_tenant à l'inscription) ou `EX2015` à
-- `EX2024` (sociétés reprises). Le numéro d'une pièce légale dépendait donc
-- d'un texte saisissable, et deux sociétés numérotaient différemment.
-- La CI ne pouvait pas le voir : ses scénarios créent leurs exercices avec le
-- code `2026`, c'est-à-dire déjà l'année.
--
-- Correctif : le segment est l'année de l'exercice — les quatre chiffres
-- contenus dans le code s'il y en a (2026, FY2026, EX2024 → 2026, 2026, 2024),
-- sinon l'année de début de l'exercice. Le format devient stable :
-- FAC-2026-000001, quelle que soit la façon dont l'exercice a été nommé.
--
-- Les numéros déjà attribués ne sont pas touchés (une pièce validée est figée),
-- et les compteurs restent par exercice : aucune renumérotation.
--
-- Preuve : sql/216_document_number_year_tests.sql (N01 à N04).
-- ============================================================

CREATE OR REPLACE FUNCTION fiscal_year_number_segment(p_fy fiscal_years)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE((regexp_match(COALESCE(p_fy.code, ''), '(\d{4})'))[1],
                  to_char(p_fy.start_date, 'YYYY'))
$$;

COMMENT ON FUNCTION fiscal_year_number_segment(fiscal_years) IS
  'Année portée par le numéro légal : les 4 chiffres du code de l''exercice (2026, FY2026, EX2024), sinon l''année de début.';

CREATE OR REPLACE FUNCTION next_legal_document_number(p_tenant uuid, p_prefix text, p_date date)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_fy fiscal_years%ROWTYPE; v_next int;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = p_tenant AND p_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun exercice ne couvre le % : créez l''exercice avant de valider', to_char(p_date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO document_number_sequences AS s (tenant_id, prefix, fiscal_year_id, next_number)
  VALUES (p_tenant, p_prefix, v_fy.id, 2)
  ON CONFLICT (tenant_id, prefix, fiscal_year_id) WHERE fiscal_year_id IS NOT NULL
  DO UPDATE SET next_number = s.next_number + 1, updated_at = now()
  RETURNING next_number - 1 INTO v_next;
  -- 216 : l'année de l'exercice, jamais son libellé libre
  RETURN p_prefix || '-' || fiscal_year_number_segment(v_fy) || '-' || lpad(v_next::text, 6, '0');
END $$;
REVOKE ALL ON FUNCTION next_legal_document_number(uuid, text, date) FROM PUBLIC, anon, authenticated;
