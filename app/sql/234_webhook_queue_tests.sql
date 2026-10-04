-- ============================================================
-- 234_webhook_queue_tests.sql — H10 : la file de webhooks
--
-- Mesuré AVANT la 234, sur base neuve :
--   T01 rouge — l'insertion telle que la fait la fonction Edge viole
--       `event_name NOT NULL` : **aucun événement n'entrait jamais dans la file**,
--       et le code répondait `success: true, queued: 0` ;
--   T02 rouge — `process_webhook_queue()`, programmée chaque minute, incrémentait
--       `attempts` sans rien envoyer : en trois minutes toute entrée était brûlée ;
--   T03, T05, T06 rouges — ni prise de lot atomique, ni reprise des envois
--       abandonnés (les fonctions n'existaient pas).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '234', false);
DELETE FROM _audit_results WHERE file = '234';

CREATE OR REPLACE FUNCTION _wh234(p_t uuid, p_url text DEFAULT 'https://exemple.test/hook')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ep uuid; q uuid;
BEGIN
  INSERT INTO webhook_endpoints (tenant_id, name, url, secret, active, active_events)
  VALUES (p_t, 'Point ' || left(md5(random()::text), 6), p_url, 's3cr3t', true, '["invoice.created"]'::jsonb)
  RETURNING id INTO ep;
  -- exactement les colonnes qu'écrit outgoing-webhooks/index.ts
  INSERT INTO webhook_delivery_queue (tenant_id, endpoint_id, url, event, payload, secret, status, attempts)
  VALUES (p_t, ep, p_url, 'invoice.created', '{"id":"x"}'::jsonb, 's3cr3t', 'pending', 0)
  RETURNING id INTO q;
  RETURN q;
END $$;

-- T01 : l'insertion que fait la fonction Edge entre dans la file
DO $$
DECLARE t uuid; q uuid; v_event text; v_name text; err text := '—'; ok boolean := false;
BEGIN
  t := _mk_tenant('T01WH');
  BEGIN
    q := _wh234(t);
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT event, event_name INTO v_event, v_name FROM webhook_delivery_queue WHERE id = q;
  PERFORM _rec('T01', 'l''événement entre dans la file, et les deux colonnes jumelles disent la même chose',
    ok AND v_event = 'invoice.created' AND v_name = 'invoice.created',
    format('event=%s event_name=%s | %s', coalesce(v_event, 'NULL'), coalesce(v_name, 'NULL'), left(err, 90)));
END $$;

-- T02 : le passage du cron ne consomme aucune tentative
DO $$
DECLARE t uuid; q uuid; r jsonb; v_att int; v_st text;
BEGIN
  t := _mk_tenant('T02WH');
  q := _wh234(t);
  FOR i IN 1..3 LOOP r := process_webhook_queue(50); END LOOP;
  SELECT attempts, status INTO v_att, v_st FROM webhook_delivery_queue WHERE id = q;
  PERFORM _rec('T02', 'trois passages du cron ne brûlent aucune tentative',
    v_att = 0 AND v_st = 'pending',
    format('tentatives=%s (0 attendue) statut=%s | %s', v_att, v_st, left(r::text, 80)));
END $$;

-- T03 : la prise de lot est atomique — un envoi confié ne repart pas deux fois
DO $$
DECLARE t uuid; q uuid; n1 int; n2 int; v_st text; v_att int;
BEGIN
  t := _mk_tenant('T03WH');
  q := _wh234(t);
  SELECT count(*) INTO n1 FROM claim_webhook_batch(50) c WHERE c.id = q;
  SELECT count(*) INTO n2 FROM claim_webhook_batch(50) c WHERE c.id = q;
  SELECT status, attempts INTO v_st, v_att FROM webhook_delivery_queue WHERE id = q;
  PERFORM _rec('T03', 'un envoi pris par un traitement n''est pas rendu à un second',
    n1 = 1 AND n2 = 0 AND v_st = 'sending' AND v_att = 0,
    format('1er lot=%s 2e lot=%s statut=%s tentatives=%s', n1, n2, v_st, v_att));
END $$;

-- T04 : une URL devenue interne après la mise en file est bloquée, jamais rendue
--       (l'enregistrement, lui, refuse déjà l'URL interne — T08)
DO $$
DECLARE t uuid; q uuid; n int; v_st text; v_err text;
BEGIN
  t := _mk_tenant('T04WH');
  q := _wh234(t);
  UPDATE webhook_delivery_queue SET url = 'http://127.0.0.1:8080/interne' WHERE id = q;
  SELECT count(*) INTO n FROM claim_webhook_batch(50) c WHERE c.id = q;
  SELECT status, last_error INTO v_st, v_err FROM webhook_delivery_queue WHERE id = q;
  PERFORM _rec('T04', 'URL interne : bloquée par la garde SSRF et jamais confiée à un envoi',
    n = 0 AND v_st = 'blocked' AND v_err ILIKE '%SSRF%',
    format('rendue=%s statut=%s erreur=%s', n, v_st, left(coalesce(v_err, '—'), 60)));
END $$;

-- T05 : un envoi abandonné revient en file
DO $$
DECLARE t uuid; q uuid; n int; v_st text; v_req int;
BEGIN
  t := _mk_tenant('T05WH');
  q := _wh234(t);
  PERFORM count(*) FROM claim_webhook_batch(50);
  UPDATE webhook_delivery_queue SET last_attempt_at = now() - interval '2 hours' WHERE id = q;
  v_req := requeue_stale_webhook_deliveries();
  SELECT status INTO v_st FROM webhook_delivery_queue WHERE id = q;
  SELECT count(*) INTO n FROM claim_webhook_batch(50) c WHERE c.id = q;
  PERFORM _rec('T05', 'un envoi interrompu il y a deux heures revient en file et repart',
    v_req >= 1 AND v_st = 'retry' AND n = 1,
    format('remises en file=%s statut après reprise=%s reprise dans un lot=%s', v_req, v_st, n));
END $$;

-- T06 : un réessai programmé plus tard n'est pas pris avant l'heure
DO $$
DECLARE t uuid; q uuid; n int;
BEGIN
  t := _mk_tenant('T06WH');
  q := _wh234(t);
  UPDATE webhook_delivery_queue SET status = 'retry', next_attempt_at = now() + interval '1 hour' WHERE id = q;
  SELECT count(*) INTO n FROM claim_webhook_batch(50) c WHERE c.id = q;
  PERFORM _rec('T06', 'un réessai programmé dans une heure n''est pas pris maintenant',
    n = 0, format('rendue dans le lot=%s (0 attendue)', n));
END $$;

-- T07 : le résultat d'un envoi se lit dans les deux jeux de colonnes
--       (la vue des échecs lit les anciennes, la fonction Edge écrit les nouvelles)
DO $$
DECLARE t uuid; q uuid; v_old int; v_new int; v_ob text; v_nb text;
BEGIN
  t := _mk_tenant('T07WH');
  q := _wh234(t);
  UPDATE webhook_delivery_queue
  SET status = 'failed', attempts = 3, http_status = 500, response_body = 'Erreur serveur'
  WHERE id = q;
  SELECT last_response_status, http_status, last_response_body, response_body
    INTO v_old, v_new, v_ob, v_nb FROM webhook_delivery_queue WHERE id = q;
  PERFORM _rec('T07', 'le résultat d''un envoi se lit dans les deux jeux de colonnes',
    v_old = 500 AND v_new = 500 AND v_ob = 'Erreur serveur' AND v_nb = 'Erreur serveur',
    format('ancien=%s/%s nouveau=%s/%s', v_old, coalesce(v_ob, 'NULL'), v_new, coalesce(v_nb, 'NULL')));
END $$;

-- T08 : la première barrière — une URL interne est refusée dès l'enregistrement
DO $$
DECLARE t uuid; refuse boolean := false; n int; err text := '—';
BEGIN
  t := _mk_tenant('T08WH');
  BEGIN
    INSERT INTO webhook_endpoints (tenant_id, name, url, secret, active, active_events)
    VALUES (t, 'Interne', 'http://127.0.0.1:8080/interne', 's', true, '["invoice.created"]'::jsonb);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM webhook_endpoints WHERE tenant_id = t;
  PERFORM _rec('T08', 'une URL interne est refusée dès l''enregistrement du point de livraison',
    refuse AND n = 0, format('refus=%s points enregistrés=%s | %s', refuse, n, left(err, 80)));
END $$;

DROP FUNCTION _wh234(uuid, text);
SELECT _audit_assert('234');
