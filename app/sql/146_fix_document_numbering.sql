-- ============================================================
-- 146_fix_document_numbering.sql
-- LOT4-10 : Numérotation par horodatage → séquentielle
--
-- Problème : Le frontend utilise Date.now() pour générer des numéros
-- de documents (EXT, AN, factures, BL, BR, etc.).
-- L'article A.47 A-1 du Livre des procédures fiscales exige une
-- numérotation séquentielle continue sans rupture.
--
-- Fix : Créer une RPC générique get_next_document_number(p_prefix, p_tenant_id)
-- qui utilise une séquence par tenant + préfixe.
-- ============================================================

-- Table de séquences de numérotation par tenant + préfixe
CREATE TABLE IF NOT EXISTS document_number_sequences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  prefix text NOT NULL,
  next_number int NOT NULL DEFAULT 1,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, prefix)
);

ALTER TABLE document_number_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_number_sequences_tenant ON document_number_sequences
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Fonction générique de génération de numéro de document
-- Format : PREFIX-YYYY-NNNNNN (année + numéro séquentiel)
CREATE OR REPLACE FUNCTION get_next_document_number(p_prefix text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_next int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Incrément atomique
  INSERT INTO document_number_sequences (tenant_id, prefix, next_number)
  VALUES (v_tid, p_prefix, 2)
  ON CONFLICT (tenant_id, prefix)
  DO UPDATE SET next_number = document_number_sequences.next_number + 1,
    updated_at = now()
  RETURNING next_number - 1 INTO v_next;

  RETURN p_prefix || '-' || v_year || '-' || lpad(v_next::text, 6, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION get_next_document_number(text) TO authenticated;
