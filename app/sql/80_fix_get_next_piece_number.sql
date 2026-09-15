-- ============================================================
-- 80_fix_get_next_piece_number.sql
--
-- Correctif ACC-01 (contrôle extrême) : la migration 76 créait
-- get_next_piece_number() avec un filtre sur journals.journal_code,
-- mais la table journals utilise la colonne `code`.
-- Le RPC plantait donc à chaque appel ("column journal_code does
-- not exist") et post_journal_entry échouait pour toute écriture
-- sans numéro explicite.
--
-- Cette version filtre sur `code` et conserve :
--   - le verrou de ligne (UPDATE ... RETURNING) anti-concurrence
--   - le périmètre tenant (current_tenant_id())
--   - l'amorçage du compteur sur la valeur sequence existante
-- ============================================================

CREATE OR REPLACE FUNCTION get_next_piece_number(p_journal_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_next integer;
  v_padded text;
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Verrou de ligne : incrément atomique, pas de doublon en concurrence
  UPDATE journals
    SET next_number = next_number + 1
    WHERE code = p_journal_code
      AND tenant_id = v_tid
    RETURNING next_number - 1 INTO v_next;

  IF v_next IS NULL THEN
    -- Journal non trouvé pour ce tenant : amorcer depuis `sequence` si présent
    SELECT COALESCE(j.sequence, 0) + 1 INTO v_next
    FROM journals j
    WHERE j.code = p_journal_code AND j.tenant_id = v_tid;

    IF v_next IS NULL THEN
      RAISE EXCEPTION 'Journal % introuvable pour le tenant actif', p_journal_code;
    END IF;

    UPDATE journals
      SET next_number = v_next + 1
      WHERE code = p_journal_code AND tenant_id = v_tid;
  END IF;

  v_padded := lpad(v_next::text, 4, '0');
  RETURN p_journal_code || '-' || v_padded;
END;
$$;

GRANT EXECUTE ON FUNCTION get_next_piece_number(text) TO authenticated;
