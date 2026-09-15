-- ============================================================
-- 150_fix_phantom_columns.sql
-- LOT1-06 : 9 colonnes fantômes référencées côté front
--
-- Cette migration ajoute les colonnes manquantes côté schéma.
-- Les corrections de requêtes front sont faites dans les fichiers TS.
-- ============================================================

-- 3. employees.auth_user_id (dematRh.ts)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS auth_user_id uuid;

-- Index pour la recherche par auth_user_id
CREATE INDEX IF NOT EXISTS idx_employees_auth_user_id ON employees(auth_user_id);

-- 4. journal_lines.line_date — ajouter la colonne pour le filtrage par période
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS line_date date;
COMMENT ON COLUMN journal_lines.line_date IS 'Date de l''écriture (copie de journal_entries.date pour filtrage rapide)';

-- Trigger pour renseigner line_date automatiquement depuis journal_entries.date
CREATE OR REPLACE FUNCTION set_journal_line_date()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_entry_date date;
BEGIN
  SELECT date INTO v_entry_date FROM journal_entries WHERE id = NEW.journal_id;
  IF v_entry_date IS NOT NULL THEN
    NEW.line_date := v_entry_date;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_journal_line_date ON journal_lines;
CREATE TRIGGER set_journal_line_date
  BEFORE INSERT ON journal_lines
  FOR EACH ROW
  EXECUTE FUNCTION set_journal_line_date();
