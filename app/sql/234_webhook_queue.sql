-- ============================================================
-- 234_webhook_queue.sql — H10 : la file de webhooks ne livrait rien
--
-- Le plan annonçait « file en mémoire dans une fonction Edge » (audit du
-- 12/09). Revérifié : **c'est faux depuis la 154**, la file est en base. Le
-- vrai défaut est ailleurs, et il est complet — mesuré le 24/09 sur base neuve :
--
--   1. **Rien n'entre dans la file.** `webhook_delivery_queue.event_name` est
--      NOT NULL (129) ; la fonction Edge insère `event` (colonne ajoutée par la
--      154) et **jamais** `event_name` : chaque insertion viole la contrainte.
--      Le code compte `if (!insertError) queued++` et répond `success: true,
--      queued: 0` — l'échec ne se voit nulle part.
--   2. **Rien ne sort de la file.** `processQueue` lit et écrit
--      `next_retry_at` : cette colonne **n'existe pas** (la table porte
--      `next_attempt_at`). La requête PostgREST échoue, la fonction rend 0.
--   3. **Le cron brûle les tentatives sans rien envoyer.** `process_webhook_queue`,
--      programmée **chaque minute**, incrémente `attempts` et pose
--      `last_attempt_at` — puis un commentaire explique que l'envoi HTTP est
--      fait ailleurs. En trois minutes, toute entrée atteint `MAX_RETRIES` :
--      même réparée, la livraison serait déclarée « échec définitif » avant le
--      premier appel HTTP.
--
-- Origine commune : la 129 a créé la table, la 154 lui a ajouté un second jeu
-- de colonnes pour les mêmes notions (`event` / `event_name`,
-- `http_status` / `last_response_status`, `response_body` /
-- `last_response_body`) sans réconcilier les deux.
--
-- CORRECTIF
--   1. les colonnes jumelles sont **miroir** : un trigger remplit l'une depuis
--      l'autre, dans les deux sens, et `event_name` cesse d'être obligatoire
--      pour qui écrit `event` (la vue `v_webhook_failures` lit les anciennes,
--      la fonction Edge les nouvelles : les deux disent désormais la vérité) ;
--   2. `claim_webhook_batch()` prend un lot **atomiquement** (FOR UPDATE SKIP
--      LOCKED), le passe à `sending` et le rend à l'appelant. Deux traitements
--      concurrents ne peuvent plus livrer deux fois le même événement — la
--      fonction Edge lisait la file sans verrou, et elle est appelée à la fois
--      après chaque insertion et par le cron ;
--   3. **la prise d'un lot ne consomme plus de tentative** : seul le résultat
--      d'un envoi réel incrémente `attempts` ;
--   4. `requeue_stale_webhook_deliveries()` ramène à `retry` ce qui reste
--      bloqué en `sending` (fonction Edge interrompue), sinon un incident
--      perdrait les événements pour toujours ;
--   5. `process_webhook_queue()` — appelée chaque minute par pg_cron — ne
--      touche plus aux tentatives : elle remet en file les envois abandonnés et
--      bloque les URL refusées par la garde SSRF (167).
--
-- CE QUI RESTE À CÂBLER, et qu'aucune migration ne peut faire seule : le
-- déclenchement périodique de la fonction Edge (`?process=1`). Aujourd'hui le
-- seul déclencheur est l'appel « best-effort » qui suit l'insertion ; les
-- réessais attendent donc un appel extérieur. `trigger_webhook_delivery()`
-- l'appelle quand `pg_net` est disponible ET que l'URL des fonctions est
-- connue (`app.functions_base_url`) — à programmer dans pg_cron le jour où ces
-- deux conditions sont réunies en production.
-- ============================================================

-- 1. Colonnes jumelles : miroir, et event_name cesse d'être obligatoire
ALTER TABLE webhook_delivery_queue ALTER COLUMN event_name DROP NOT NULL;
ALTER TABLE webhook_delivery_queue ALTER COLUMN payload SET DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION sync_webhook_queue_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.event_name := COALESCE(NEW.event_name, NEW.event);
  NEW.event := COALESCE(NEW.event, NEW.event_name);
  NEW.http_status := COALESCE(NEW.http_status, NEW.last_response_status);
  NEW.last_response_status := COALESCE(NEW.last_response_status, NEW.http_status);
  NEW.response_body := COALESCE(NEW.response_body, NEW.last_response_body);
  NEW.last_response_body := COALESCE(NEW.last_response_body, NEW.response_body);
  NEW.updated_at := now();
  IF NEW.event_name IS NULL THEN
    RAISE EXCEPTION 'Webhook sans événement : renseignez event ou event_name';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION sync_webhook_queue_columns() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS sync_webhook_queue_columns ON webhook_delivery_queue;
CREATE TRIGGER sync_webhook_queue_columns
  BEFORE INSERT OR UPDATE ON webhook_delivery_queue
  FOR EACH ROW EXECUTE FUNCTION sync_webhook_queue_columns();

-- 2. `sending` : un envoi confié à un traitement, pas encore conclu
ALTER TABLE webhook_delivery_queue DROP CONSTRAINT IF EXISTS webhook_delivery_queue_status_check;
ALTER TABLE webhook_delivery_queue ADD CONSTRAINT webhook_delivery_queue_status_check
  CHECK (status IN ('pending', 'retry', 'sending', 'delivered', 'failed', 'disabled', 'blocked'));

-- 3. Prise de lot atomique — sans consommer de tentative
CREATE OR REPLACE FUNCTION claim_webhook_batch(p_batch_size int DEFAULT 50)
RETURNS TABLE (id uuid, tenant_id uuid, url text, event text, payload jsonb, secret text, attempts int, max_attempts int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT q.id, q.tenant_id, q.url, q.event, q.event_name, q.payload, q.secret, q.attempts, q.max_attempts
    FROM webhook_delivery_queue q
    WHERE q.status IN ('pending', 'retry')
      AND q.delivered_at IS NULL
      AND (q.next_attempt_at IS NULL OR q.next_attempt_at <= now())
    ORDER BY q.next_attempt_at NULLS FIRST, q.created_at
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Garde SSRF (167) : une URL refusée ne ressort pas du lot
    IF v_rec.url IS NULL OR NOT is_allowed_webhook_url(v_rec.url) THEN
      UPDATE webhook_delivery_queue
      SET status = 'blocked', last_error = 'URL bloquée (protection SSRF)'
      WHERE webhook_delivery_queue.id = v_rec.id;
      CONTINUE;
    END IF;

    UPDATE webhook_delivery_queue
    SET status = 'sending', last_attempt_at = now()
    WHERE webhook_delivery_queue.id = v_rec.id;

    id := v_rec.id; tenant_id := v_rec.tenant_id; url := v_rec.url;
    event := COALESCE(v_rec.event, v_rec.event_name); payload := v_rec.payload;
    secret := v_rec.secret; attempts := COALESCE(v_rec.attempts, 0);
    max_attempts := COALESCE(v_rec.max_attempts, 5);
    RETURN NEXT;
  END LOOP;
END;
$$;
REVOKE EXECUTE ON FUNCTION claim_webhook_batch(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION claim_webhook_batch(int) TO service_role;

-- 4. Reprise des envois abandonnés
CREATE OR REPLACE FUNCTION requeue_stale_webhook_deliveries(p_older_than interval DEFAULT interval '10 minutes')
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n int;
BEGIN
  UPDATE webhook_delivery_queue
  SET status = 'retry', next_attempt_at = now(),
      last_error = COALESCE(last_error, 'Envoi abandonné : traitement interrompu, remis en file')
  WHERE status = 'sending'
    AND delivered_at IS NULL
    AND COALESCE(last_attempt_at, created_at) < now() - p_older_than;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION requeue_stale_webhook_deliveries(interval) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION requeue_stale_webhook_deliveries(interval) TO service_role;

-- 5. Le cron ne consomme plus les tentatives : il remet en file et bloque
CREATE OR REPLACE FUNCTION process_webhook_queue(p_batch_size int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_requeued int;
  v_blocked int := 0;
  v_due int;
BEGIN
  v_requeued := requeue_stale_webhook_deliveries();

  -- URL devenues interdites depuis leur mise en file (garde SSRF, 167)
  UPDATE webhook_delivery_queue
  SET status = 'blocked', last_error = 'URL bloquée (protection SSRF)'
  WHERE status IN ('pending', 'retry') AND delivered_at IS NULL
    AND (url IS NULL OR NOT is_allowed_webhook_url(url));
  GET DIAGNOSTICS v_blocked = ROW_COUNT;

  SELECT count(*) INTO v_due FROM webhook_delivery_queue
  WHERE status IN ('pending', 'retry') AND delivered_at IS NULL
    AND (next_attempt_at IS NULL OR next_attempt_at <= now());

  -- L'envoi HTTP appartient à la fonction Edge outgoing-webhooks?process=1,
  -- qui prend son lot par claim_webhook_batch(). Cette fonction-ci ne compte
  -- plus de tentative : une tentative, c'est un envoi réellement fait.
  RETURN jsonb_build_object(
    'requeued', v_requeued,
    'blocked', v_blocked,
    'due', v_due,
    'processed_at', now()
  );
END;
$$;

-- 6. Déclenchement de la livraison, si et seulement si l'environnement le permet
CREATE OR REPLACE FUNCTION trigger_webhook_delivery()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_base text := current_setting('app.functions_base_url', true);
  v_key text := current_setting('app.supabase_service_role_key', true);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'pg_net absent : la livraison doit être déclenchée de l''extérieur');
  END IF;
  IF v_base IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'app.functions_base_url ou app.supabase_service_role_key non configuré');
  END IF;
  EXECUTE format(
    'SELECT net.http_post(url := %L, headers := jsonb_build_object(''Content-Type'', ''application/json'', ''Authorization'', %L), body := ''{}''::jsonb)',
    rtrim(v_base, '/') || '/outgoing-webhooks?process=1', 'Bearer ' || v_key);
  RETURN jsonb_build_object('success', true, 'triggered_at', now());
END;
$$;
REVOKE EXECUTE ON FUNCTION trigger_webhook_delivery() FROM PUBLIC, anon;
