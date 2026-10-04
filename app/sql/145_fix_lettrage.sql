-- ============================================================
-- 145_fix_lettrage.sql
-- LOT4-08 : Lettrage bloqué à A999 (tri lexicographique)
-- LOT4-09 : Lettrage sans contrôle d'équilibre
--
-- Le frontend a déjà des correctifs, mais le cahier des charges
-- demande la logique en base pour la sécurité.
-- ============================================================

-- LOT4-08 : Colonne séquence sur company_settings
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS next_lettrage_seq bigint DEFAULT 1;

-- LOT4-08 : Fonction de génération de code de lettrage
-- A001..Z999 puis AA01..ZZ99
CREATE OR REPLACE FUNCTION next_lettrage_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_seq bigint;
  v_tid uuid := current_tenant_id();
  v_letter text;
  v_num int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Incrémenter atomiquement la séquence
  UPDATE company_settings
  SET next_lettrage_seq = next_lettrage_seq + 1
  WHERE tenant_id = v_tid
  RETURNING next_lettrage_seq - 1 INTO v_seq;

  -- Si company_settings n'existe pas pour ce tenant, v_seq est NULL
  IF v_seq IS NULL THEN
    -- Créer la ligne si elle n'existe pas
    INSERT INTO company_settings (tenant_id, next_lettrage_seq)
    VALUES (v_tid, 2)
    ON CONFLICT (tenant_id) DO UPDATE SET next_lettrage_seq = 2
    RETURNING 1 INTO v_seq;
  END IF;

  -- A001..Z999 (26 * 999 = 25 974 codes)
  IF v_seq < 26 * 999 THEN
    v_letter := chr(65 + (v_seq / 999)::int);
    v_num := (v_seq % 999)::int + 1;
    RETURN v_letter || lpad(v_num::text, 3, '0');
  -- AA01..ZZ99 (26 * 26 * 99 = 67 176 codes)
  ELSIF v_seq < 26 * 999 + 26 * 26 * 99 THEN
    v_seq := v_seq - 26 * 999;
    v_letter := chr(65 + (v_seq / (26 * 99))::int) || chr(65 + ((v_seq / 99)::int % 26));
    v_num := (v_seq % 99)::int + 1;
    RETURN v_letter || lpad(v_num::text, 2, '0');
  ELSE
    RAISE EXCEPTION 'Numérotation de lettrage épuisée';
  END IF;
END;
$$;

-- LOT4-09 : Fonction d'application du lettrage avec contrôle d'équilibre
CREATE OR REPLACE FUNCTION apply_lettrage(p_line_ids uuid[], p_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_d numeric;
  v_c numeric;
  v_comptes int;
  v_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- LOT4-08 : Générer le code si non fourni
  IF p_code IS NULL OR p_code = '' THEN
    v_code := next_lettrage_code();
  ELSE
    v_code := p_code;
  END IF;

  -- LOT4-09 : Vérifier l'équilibre débit/crédit
  SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0),
         count(DISTINCT left(COALESCE(account_general, account_code), 3))
  INTO v_d, v_c, v_comptes
  FROM journal_lines
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  -- Vérifier qu'on lettre sur un seul compte de tiers
  IF v_comptes > 1 THEN
    RAISE EXCEPTION 'Lettrage sur % comptes de tiers différents', v_comptes;
  END IF;

  -- Vérifier l'équilibre
  IF ABS(v_d - v_c) > 0.01 THEN
    RAISE EXCEPTION 'Lettrage déséquilibré : débit % ≠ crédit % (écart %)', v_d, v_c, ABS(v_d - v_c);
  END IF;

  -- Appliquer le lettrage
  UPDATE journal_lines
  SET lettrage_code = v_code, lettrage_date = CURRENT_DATE
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  RETURN jsonb_build_object(
    'code', v_code,
    'lines', array_length(p_line_ids, 1),
    'amount', v_d
  );
END;
$$;

-- LOT4-09 : Fonction de suppression de lettrage
CREATE OR REPLACE FUNCTION remove_lettrage(p_line_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  UPDATE journal_lines
  SET lettrage_code = null, lettrage_date = null
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  RETURN jsonb_build_object('lines', array_length(p_line_ids, 1));
END;
$$;
