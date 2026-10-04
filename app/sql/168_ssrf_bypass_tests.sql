-- ============================================================
-- 168_ssrf_bypass_tests.sql
--
-- Vérifie is_allowed_webhook_url (durcie en 167) contre les VRAIS bypass de
-- filtre SSRF. Rejoué par la CI (job db-integration). Exclu du rejeu des
-- migrations par le suffixe `_tests.sql`. Miroir de ssrfGuard.test.ts.
-- ============================================================

DO $$
DECLARE
  -- URLs qui DOIVENT être bloquées (attendu = false)
  v_blocked text[] := ARRAY[
    'http://example.com/webhook',              -- non-HTTPS
    'https://localhost/webhook',
    'https://svc.internal/webhook',
    'https://app.local/webhook',
    'https://127.0.0.1/webhook',
    'https://10.0.0.1/webhook',
    'https://192.168.1.1/webhook',
    'https://169.254.169.254/latest/meta-data',
    'https://172.16.0.1/webhook',
    'https://0.0.0.0/webhook',
    'https://2130706433/webhook',              -- BYPASS décimal 127.0.0.1
    'https://0x7f000001/webhook',              -- BYPASS hex 127.0.0.1
    'https://0177.0.0.1/webhook',              -- BYPASS octal 127.0.0.1
    'https://2852039166/webhook',              -- BYPASS décimal 169.254.169.254
    'https://expected.com@169.254.169.254/x',  -- BYPASS userinfo trompeur
    'https://100.64.0.1/webhook',              -- BYPASS CGNAT
    'https://255.255.255.255/webhook',         -- broadcast
    'https://224.0.0.1/webhook',               -- multicast
    'https://[::1]/webhook',
    'https://[fc00::1]/webhook',
    'https://[fe80::1]/webhook',
    'https://[::ffff:169.254.169.254]/webhook' -- BYPASS IPv6 IPv4-mapped
  ];
  -- URLs qui DOIVENT passer (attendu = true)
  v_allowed text[] := ARRAY[
    'https://example.com/webhook',
    'https://api.slack.com/hooks/abc',
    'https://hooks.example.co.uk:8443/x',
    'https://1.1.1.1/webhook',                 -- IPv4 publique
    'https://100.63.0.1/webhook',              -- hors CGNAT
    'https://[2606:4700:4700::1111]/webhook'   -- IPv6 publique
  ];
  v_url text;
BEGIN
  FOREACH v_url IN ARRAY v_blocked LOOP
    IF is_allowed_webhook_url(v_url) THEN
      RAISE EXCEPTION 'SSRF: URL aurait dû être BLOQUÉE mais est passée : %', v_url;
    END IF;
  END LOOP;

  FOREACH v_url IN ARRAY v_allowed LOOP
    IF NOT is_allowed_webhook_url(v_url) THEN
      RAISE EXCEPTION 'SSRF: URL publique aurait dû être AUTORISÉE mais est bloquée : %', v_url;
    END IF;
  END LOOP;

  RAISE NOTICE 'OK — 168_ssrf_bypass_tests : % bloquées, % autorisées',
    array_length(v_blocked, 1), array_length(v_allowed, 1);
END $$;
