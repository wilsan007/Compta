-- ============================================================
-- Migration 154 : LOT5-01 à LOT5-05
--   LOT5-01 : verify_nf525_chain — vérification réelle de chaînage + gaps
--   LOT5-02 : log_nf525_event — FOR UPDATE sur le SELECT du hash précédent
--   LOT5-03 : Séparation des tâches désactivable (enforce_segregation)
--   LOT5-04 : File de webhooks persistante — colonnes manquantes + pg_cron
--   LOT5-05 : Filtrage SSRF à l'enregistrement des endpoints
-- Idempotent — CREATE OR REPLACE / IF NOT EXISTS
-- ============================================================

-- ============================================================
-- LOT5-01 + LOT5-02 : NF-525 chaîne + course d'écriture
-- ============================================================

-- LOT5-02 : log_nf525_event avec FOR UPDATE (en plus du verrou advisory)
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

  -- LOT5-02 : Verrou advisory transactionnel pour sérialiser la chaîne par tenant
  PERFORM pg_advisory_xact_lock(hashtext('nf525:' || v_tid::text));

  -- LOT5-02 : FOR UPDATE sur le SELECT pour verrouiller la ligne lue
  SELECT current_hash INTO v_prev_hash
  FROM nf525_event_log
  WHERE tenant_id = v_tid
  ORDER BY id DESC
  LIMIT 1
  FOR UPDATE;

  v_prev_hash := COALESCE(v_prev_hash, 'GENESIS');

  -- Récupérer le nom d'utilisateur depuis la session
  BEGIN
    SELECT current_setting('app.user_name', true) INTO v_user_name;
  EXCEPTION WHEN OTHERS THEN
    v_user_name := NULL;
  END;

  -- Calculer le hash : SHA-256(prev_hash || event_type || entity_type || entity_id || tenant_id || epoch)
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

-- LOT5-01 : verify_nf525_chain avec vérification de chaînage + détection de gaps
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
  v_gap_count integer := 0;
  v_first_id bigint;
  v_last_id bigint := NULL;
  v_last_seen_hash text := NULL;
  v_hash_input text;
  v_expected_hash text;
  v_details jsonb := '[]'::jsonb;
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
    ORDER BY id ASC
  LOOP
    v_total_count := v_total_count + 1;
    IF v_total_count = 1 THEN
      v_first_id := v_rec.id;
    END IF;
    v_last_id := v_rec.id;

    -- LOT5-01 : Vérifier que previous_hash == current_hash de l'enregistrement précédent
    IF v_last_seen_hash IS NOT NULL
       AND v_rec.previous_hash IS DISTINCT FROM v_last_seen_hash THEN
      v_broken_count := v_broken_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'CHAIN_FORK_OR_MISSING_LINK',
        'event_id', v_rec.id,
        'expected_prev', v_last_seen_hash,
        'actual_prev', v_rec.previous_hash
      )::jsonb;
    END IF;
    v_last_seen_hash := v_rec.current_hash;

    -- LOT5-01 : Continuité des identifiants — un BIGSERIAL qui saute signale une suppression
    IF v_last_id IS NOT NULL AND v_rec.id <> v_last_id + 1 THEN
      v_gap_count := v_gap_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'ID_GAP_DETECTED',
        'after_id', v_last_id,
        'before_id', v_rec.id,
        'missing_count', (v_rec.id - v_last_id - 1)
      )::jsonb;
    END IF;
    v_last_id := v_rec.id;

    -- Recalculer le hash attendu pour vérifier l'intégrité du contenu
    v_hash_input := COALESCE(v_rec.previous_hash, 'GENESIS') || '|' ||
      v_rec.event_type || '|' ||
      v_rec.entity_type || '|' ||
      COALESCE(v_rec.entity_id::text, '') || '|' ||
      v_rec.tenant_id::text || '|' ||
      extract(epoch FROM v_rec.event_date)::text;

    v_expected_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

    IF v_expected_hash != v_rec.current_hash THEN
      v_broken_count := v_broken_count + 1;
      v_details := v_details || jsonb_build_object(
        'error', 'HASH_MISMATCH',
        'event_id', v_rec.id,
        'expected_hash', v_expected_hash,
        'actual_hash', v_rec.current_hash
      )::jsonb;
    END IF;
  END LOOP;

  -- LOT5-01 : chain_valid devient une conjonction (chaînage + gaps)
  RETURN jsonb_build_object(
    'total_events', v_total_count,
    'broken_links', v_broken_count,
    'gap_count', v_gap_count,
    'chain_valid', (v_broken_count = 0 AND v_gap_count = 0),
    'first_event_id', v_first_id,
    'last_event_id', v_last_id,
    'details', v_details,
    'verified_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION verify_nf525_chain(timestamptz, timestamptz) TO authenticated;

-- ============================================================
-- LOT5-03 : Séparation des tâches désactivable
-- ============================================================

-- Ajouter la colonne enforce_segregation (défaut: false — désactivé par défaut)
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS enforce_segregation boolean DEFAULT false;

-- Réécrire enforce_journal_entry_permissions pour rendre la séparation conditionnelle
CREATE OR REPLACE FUNCTION enforce_journal_entry_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_enforce boolean := false;
BEGIN
  -- Si on tente de poster une écriture, vérifier la permission
  IF NEW.status = 'posted' AND (OLD.status IS NULL OR OLD.status <> 'posted') THEN
    IF NOT has_permission('journal_entry.post') THEN
      RAISE EXCEPTION 'Permission refusée : journal_entry.post';
    END IF;

    -- LOT5-03 : Séparation des tâches — seulement si activée dans company_settings
    SELECT COALESCE(enforce_segregation, false) INTO v_enforce
    FROM company_settings WHERE tenant_id = NEW.tenant_id;

    IF v_enforce AND NOT check_segregation_of_duties(auth.uid(), 'validate', NEW.id) THEN
      RAISE EXCEPTION 'Séparation des tâches : vous ne pouvez pas valider une écriture que vous avez saisie';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT5-04 : File de webhooks persistante — colonnes manquantes + pg_cron
-- ============================================================

-- Ajouter les colonnes manquantes que l'Edge Function attend
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS url text;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS secret text;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS event text;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS last_error text;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS http_status int;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS response_body text;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE webhook_delivery_queue ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Étendre le CHECK sur status pour inclure 'retry' et 'blocked'
ALTER TABLE webhook_delivery_queue DROP CONSTRAINT IF EXISTS webhook_delivery_queue_status_check;
ALTER TABLE webhook_delivery_queue ADD CONSTRAINT webhook_delivery_queue_status_check
  CHECK (status IN ('pending', 'retry', 'delivered', 'failed', 'disabled', 'blocked'));

-- Index pour le traitement par pg_cron (FOR UPDATE SKIP LOCKED)
CREATE INDEX IF NOT EXISTS idx_webhook_queue_process
  ON webhook_delivery_queue (next_attempt_at)
  WHERE delivered_at IS NULL AND status IN ('pending', 'retry');

-- Fonction SQL pour traiter la queue avec FOR UPDATE SKIP LOCKED
-- Appelée par pg_cron chaque minute
CREATE OR REPLACE FUNCTION process_webhook_queue(p_batch_size int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_processed int := 0;
  v_failed int := 0;
  v_rec RECORD;
BEGIN
  -- LOT5-04 : FOR UPDATE SKIP LOCKED pour un traitement concurrent safe
  FOR v_rec IN
    SELECT id, url, event, payload, secret, tenant_id, attempts, max_attempts
    FROM webhook_delivery_queue
    WHERE status IN ('pending', 'retry')
      AND delivered_at IS NULL
      AND (next_attempt_at IS NULL OR next_attempt_at <= now())
    ORDER BY next_attempt_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    -- LOT5-05 : Revalider SSRF avant l'envoi
    IF NOT is_allowed_webhook_url(v_rec.url) THEN
      UPDATE webhook_delivery_queue
      SET status = 'blocked',
          last_error = 'URL bloquée (protection SSRF)',
          updated_at = now()
      WHERE id = v_rec.id;
      v_failed := v_failed + 1;
      CONTINUE;
    END IF;

    -- Marquer comme en cours de traitement
    UPDATE webhook_delivery_queue
    SET last_attempt_at = now(),
        attempts = attempts + 1,
        updated_at = now()
    WHERE id = v_rec.id;

    -- Note : l'envoi HTTP réel est fait par l'Edge Function outgoing-webhooks?process=1
    -- Cette fonction SQL prépare la queue et filtre SSRF.
    -- L'appel à l'Edge Function se fait via pg_cron → net.http_post (si pg_net installé)
    -- ou via un cron externe qui appelle l'URL de l'Edge Function.

    v_processed := v_processed + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'processed', v_processed,
    'failed', v_failed,
    'processed_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION process_webhook_queue(int) TO authenticated;

-- pg_cron : traiter la queue chaque minute
-- (pg_cron doit être activé dans supabase_extensions)
SELECT cron.schedule(
  'process-webhook-queue',
  '* * * * *',
  $$SELECT process_webhook_queue(50)$$
) WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE name = 'process-webhook-queue'
);

-- ============================================================
-- LOT5-05 : Filtrage SSRF à l'enregistrement des endpoints
-- ============================================================

-- Fonction SQL de validation SSRF (utilisable par trigger et par process_webhook_queue)
CREATE OR REPLACE FUNCTION is_allowed_webhook_url(p_url text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_protocol text;
  v_hostname text;
BEGIN
  IF p_url IS NULL THEN
    RETURN false;
  END IF;

  -- Extraire le protocole
  v_protocol := lower(split_part(p_url, '://', 1));

  -- LOT5-05 : Exiger HTTPS uniquement
  IF v_protocol <> 'https' THEN
    RETURN false;
  END IF;

  -- Extraire le hostname (entre :// et le premier / ou : ou fin)
  v_hostname := lower(split_part(split_part(p_url, '://', 2), '/', 1));
  v_hostname := split_part(v_hostname, ':', 1);  -- retirer le port

  -- Bloquer localhost et domaines locaux
  IF v_hostname = 'localhost' THEN
    RETURN false;
  END IF;
  IF v_hostname LIKE '%.local' OR v_hostname LIKE '%.internal' THEN
    RETURN false;
  END IF;

  -- Bloquer les plages IP privées et réservées
  -- 127.x.x.x (loopback)
  IF v_hostname ~ '^127\.' THEN
    RETURN false;
  END IF;
  -- 10.x.x.x (privé)
  IF v_hostname ~ '^10\.' THEN
    RETURN false;
  END IF;
  -- 192.168.x.x (privé)
  IF v_hostname ~ '^192\.168\.' THEN
    RETURN false;
  END IF;
  -- 169.254.x.x (link-local)
  IF v_hostname ~ '^169\.254\.' THEN
    RETURN false;
  END IF;
  -- 0.x.x.x (réservé)
  IF v_hostname ~ '^0\.' THEN
    RETURN false;
  END IF;
  -- 172.16-31.x.x (privé)
  IF v_hostname ~ '^172\.(1[6-9]|2[0-9]|3[01])\.' THEN
    RETURN false;
  END IF;
  -- IPv6 ::1 (loopback)
  IF v_hostname = '::1' THEN
    RETURN false;
  END IF;
  -- IPv6 fdxx (ULA)
  IF v_hostname LIKE 'fd%' THEN
    RETURN false;
  END IF;
  -- IPv6 fe80 (link-local)
  IF v_hostname LIKE 'fe80%' THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION is_allowed_webhook_url(text) TO authenticated;

-- Trigger de validation SSRF à l'enregistrement des endpoints
CREATE OR REPLACE FUNCTION validate_webhook_endpoint_url()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- LOT5-05 : Valider l'URL à l'insertion et à la modification
  IF NOT is_allowed_webhook_url(NEW.url) THEN
    RAISE EXCEPTION 'URL de webhook non autorisée : protocole HTTPS requis, réseaux privés/bloqués (SSRF)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_webhook_url ON webhook_endpoints;
CREATE TRIGGER validate_webhook_url
  BEFORE INSERT OR UPDATE OF url ON webhook_endpoints
  FOR EACH ROW
  EXECUTE FUNCTION validate_webhook_endpoint_url();

-- ============================================================
-- Fin migration 154
-- ============================================================
