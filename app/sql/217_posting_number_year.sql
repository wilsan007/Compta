-- ============================================================
-- 217_posting_number_year.sql — le numéro d'ÉCRITURE aussi porte l'année
--
-- Suite de la 216, même défaut, autre objet. La 216 a corrigé le numéro des
-- pièces (next_legal_document_number : FAC, ACH, AV, AVF, DEV) ; elle a
-- laissé le numéro de l'écriture comptable, qui concatène lui aussi
-- `fiscal_years.code` — un libellé libre (journal_entry_guard, 187:321).
--
-- Mesuré sur la copie de production du 23/09, en clair dans les données :
--   AN-EX2024-000001, BQ-EX2024-000001, OD-EX2024-000001, VT-EX2024-000001
--   à côté de VT-2026-000342
-- Les codes d'exercice y valent 2026, 2025, 2027, FY2026, 2024, EX2024,
-- EX2021, EX2019, EX2018, EX2017 : deux sociétés numérotent donc différemment,
-- et une société reprise numérote « EX2024 ».
--
-- L'enjeu n'est pas cosmétique : `posting_number` est la colonne exportée au
-- FEC comme numéro de pièce (FECExportPage.tsx:32, `escapeFECField(je.posting_number
-- || je.number)`). Un numéro de pièce opposable ne peut pas dépendre d'un texte
-- saisissable.
--
-- Correctif : le segment du numéro d'écriture est l'année de l'exercice, par la
-- MÊME fonction que la 216 (fiscal_year_number_segment) — les quatre chiffres du
-- code s'il y en a, sinon l'année de début. Les deux numérotations ne peuvent
-- plus diverger.
--
-- Les numéros déjà attribués ne sont pas touchés, comme en 216 : une écriture
-- validée est figée, et un FEC déjà déposé y renvoie. Une normalisation de
-- l'historique serait une décision à part, avec son impact sur les FEC déposés.
--
-- La séquence (journal_posting_sequences) reste par société, journal et exercice :
-- le segment de l'année ne la modifie pas.
--
-- Preuve : sql/217_posting_number_year_tests.sql (P01 à P05), vu rouge avant.
-- ============================================================

CREATE OR REPLACE FUNCTION journal_entry_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_period fiscal_periods%ROWTYPE;
  v_closing boolean;
  v_seq integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- AUD-C02 : une écriture naît en brouillard ; la validation est une
    -- transition contrôlée (équilibre, période, permission, numéro définitif)
    IF NEW.status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'Une écriture est créée en brouillard puis validée après ses lignes (statut demandé : %)', NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.total_debit := 0;
    NEW.total_credit := 0;
    NEW.posting_seq := NULL;
    NEW.posting_number := NULL;
  ELSIF OLD.status = 'posted' THEN
    -- prevent_posted_entry_modification a déjà refusé toute modification
    RETURN NEW;
  END IF;

  IF NEW.journal_code IS NULL OR NOT EXISTS (
       SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = NEW.journal_code) THEN
    RAISE EXCEPTION 'Journal % inexistant pour cette société', COALESCE(NEW.journal_code, '(vide)')
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- AUD-C06 : la date appartient à un exercice de la société de l'écriture
  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND NEW.date BETWEEN start_date AND end_date
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun exercice ne couvre le % : créez l''exercice avant de saisir', to_char(NEW.date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_period FROM fiscal_periods
  WHERE tenant_id = NEW.tenant_id AND fiscal_year_id = v_fy.id
    AND NEW.date BETWEEN start_date AND end_date
  LIMIT 1;

  -- AUD-D03 : seule la clôture en cours écrit dans l'exercice qu'elle clôture,
  -- et seulement dans le journal CL.
  v_closing := NEW.journal_code = 'CL'
    AND current_setting('app.closing_in_progress', true) = v_fy.id::text;

  -- AUD-C05 / C07 : exercice et période lus pour la société de l'écriture
  IF NOT v_closing THEN
    IF v_fy.status IN ('closed', 'locked') THEN
      RAISE EXCEPTION 'Exercice % clos — écriture interdite (date=%)', v_fy.code, NEW.date
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_period.status IN ('closed', 'locked') THEN
      RAISE EXCEPTION 'Période fiscale close — écriture interdite (date=%)', NEW.date
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- AUD-C08
  NEW.fiscal_year_id := v_fy.id;
  NEW.fiscal_period_id := v_period.id;

  IF TG_OP = 'UPDATE' THEN
    -- AUD-C02 : totaux calculés, jamais saisis
    SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0)
      INTO NEW.total_debit, NEW.total_credit
    FROM journal_lines WHERE journal_id = NEW.id;

    -- AUD-C11 : numéro définitif à la validation, sans trou (le compteur est
    -- annulé avec la transaction si la validation échoue plus loin)
    IF NEW.status = 'posted' THEN
      INSERT INTO journal_posting_sequences AS s (tenant_id, journal_code, fiscal_year_id, last_seq)
      VALUES (NEW.tenant_id, NEW.journal_code, v_fy.id, 1)
      ON CONFLICT (tenant_id, journal_code, fiscal_year_id) DO UPDATE SET last_seq = s.last_seq + 1
      RETURNING last_seq INTO v_seq;
      NEW.posting_seq := v_seq;
      -- 217 : l'année de l'exercice, jamais son libellé libre (cf. 216)
      NEW.posting_number := NEW.journal_code || '-' || fiscal_year_number_segment(v_fy) || '-' || lpad(v_seq::text, 6, '0');
      NEW.validated_at := COALESCE(NEW.validated_at, now());
    END IF;
  END IF;

  RETURN NEW;
END $$;

COMMENT ON COLUMN journal_entries.posting_number IS
  'Numéro définitif de l''écriture : <journal>-<année de l''exercice>-<séquence>. L''année vient de fiscal_year_number_segment (216, 217), jamais du libellé libre de l''exercice. Exporté au FEC comme numéro de pièce.';