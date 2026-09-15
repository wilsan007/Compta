-- ============================================================
-- Migration 131 : Corrections critiques NF-525
--   NF-01a : Verrou advisory dans log_nf525_event (anti-fork)
--   NF-01b : Vérification de chaîne (previous_hash == current_hash précédent)
-- Idempotent — CREATE OR REPLACE
-- ============================================================

-- ============================================================
-- NF-01a : log_nf525_event avec verrou advisory
--   Problème : Deux transactions simultanées lisent le même previous_hash
--   Fix : pg_advisory_xact_lock sérialise les insertions par tenant
-- ============================================================
CREATE OR REPLACE FUNCTION log_nf525_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid DEFAULT NULL,
  p_event_data jsonb DEFAULT NULL,
  p_fiscal_year_code text DEFAULT NULL,
  p_period text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_prev_hash text;
  v_current_hash text;
  v_seq bigint;
  v_user_name text;
  v_hash_input text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- NF-01a : Verrou advisory transactionnel pour sérialiser la chaîne par tenant
  -- Empêche deux transactions concurrentes de lire le même previous_hash
  PERFORM pg_advisory_xact_lock(hashtext('nf525:' || v_tid::text));

  -- Récupérer le hash précédent (dernier événement du tenant)
  SELECT current_hash INTO v_prev_hash
  FROM nf525_event_log
  WHERE tenant_id = v_tid
  ORDER BY id DESC
  LIMIT 1;

  v_prev_hash := COALESCE(v_prev_hash, 'GENESIS');

  -- Récupérer le nom d'utilisateur depuis la session
  BEGIN
    SELECT current_setting('app.user_name', true) INTO v_user_name;
  EXCEPTION WHEN OTHERS THEN
    v_user_name := NULL;
  END;

  -- Calculer le hash : SHA-256(prev_hash || event_type || entity_type || entity_id || event_date || tenant_id)
  v_hash_input := v_prev_hash || '|' ||
    p_event_type || '|' ||
    p_entity_type || '|' ||
    COALESCE(p_entity_id::text, '') || '|' ||
    v_tid::text || '|' ||
    extract(epoch FROM now())::text;

  v_current_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Insérer l'événement
  INSERT INTO nf525_event_log (
    tenant_id, event_type, entity_type, entity_id,
    event_data, previous_hash, current_hash,
    fiscal_year_code, period, user_name
  ) VALUES (
    v_tid, p_event_type, p_entity_type, p_entity_id,
    p_event_data, v_prev_hash, v_current_hash,
    p_fiscal_year_code, p_period, v_user_name
  )
  RETURNING id INTO v_seq;

  RETURN v_seq;
END;
$$;

GRANT EXECUTE ON FUNCTION log_nf525_event(text, text, uuid, jsonb, text, text) TO authenticated;

-- ============================================================
-- NF-01b : verify_nf525_chain avec vérification de chaînage
--   Problème : Ne vérifie pas que previous_hash == current_hash du précédent
--   Fix : Vérifier explicitement la continuité de la chaîne
-- ============================================================
CREATE OR REPLACE FUNCTION verify_nf525_chain(
  p_from_date timestamptz DEFAULT NULL,
  p_to_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_total_count integer := 0;
  v_broken_count integer := 0;
  v_first_id bigint;
  v_last_id bigint;
  v_hash_input text;
  v_expected_hash text;
  v_prev_current_hash text := 'GENESIS';
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  FOR v_rec IN
    SELECT id, previous_hash, current_hash, event_type, entity_type, entity_id, event_date, tenant_id
    FROM nf525_event_log
    WHERE tenant_id = v_tid
      AND (p_from_date IS NULL OR event_date >= p_from_date)
      AND (p_to_date IS NULL OR event_date <= p_to_date)
    ORDER BY id
  LOOP
    v_total_count := v_total_count + 1;
    IF v_total_count = 1 THEN
      v_first_id := v_rec.id;
    END IF;
    v_last_id := v_rec.id;

    -- NF-01b : Vérifier que previous_hash == current_hash de l'enregistrement précédent
    IF v_rec.previous_hash != v_prev_current_hash THEN
      v_broken_count := v_broken_count + 1;
    END IF;

    -- Recalculer le hash attendu
    v_hash_input := COALESCE(v_rec.previous_hash, 'GENESIS') || '|' ||
      v_rec.event_type || '|' ||
      v_rec.entity_type || '|' ||
      COALESCE(v_rec.entity_id::text, '') || '|' ||
      v_rec.tenant_id::text || '|' ||
      extract(epoch FROM v_rec.event_date)::text;

    v_expected_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    IF v_expected_hash != v_rec.current_hash THEN
      v_broken_count := v_broken_count + 1;
    END IF;

    -- Mettre à jour pour la prochaine itération
    v_prev_current_hash := v_rec.current_hash;
  END LOOP;

  RETURN jsonb_build_object(
    'total_events', v_total_count,
    'broken_links', v_broken_count,
    'chain_valid', v_broken_count = 0,
    'first_event_id', v_first_id,
    'last_event_id', v_last_id,
    'verified_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION verify_nf525_chain(timestamptz, timestamptz) TO authenticated;
