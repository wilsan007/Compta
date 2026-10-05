-- ============================================================
-- 700_auth_forte_api_keys_totp_tests.sql — ORPH-01 / SEC-02 :
--   UNE CLÉ QU'ON NE PEUT PAS RÉVOQUER N'EST PAS UNE AUTHENTIFICATION FORTE
--
-- La preuve attendue (recomptage ORPH-01) : « émission, usage, révocation,
-- rejeu d'une clé ; activation/vérification TOTP ; chaque scénario vu rouge
-- d'abord ». C'était la PREMIÈRE suite de l'histoire du dépôt à exercer
-- `api_keys` et `user_totp` : avant elle, seul un test Vitest à Supabase
-- simulé les nommait.
--
--   T01  émission : la clé rendue une fois, le SHA-256 stocké, active
--        (non-régression : la 130 savait faire)
--   T02  usage : authenticate_api_key dit OUI, et pose last_used_at
--        (ROUGE avant : la fonction n'existait pas)
--   T03  mauvaise clé : refus nommé not_found
--        (ROUGE avant : idem — le rejeu d'une clé ne se constatait nulle part)
--   T04  révocation : revoke_api_key pose le drapeau ET la date
--   T05  REJEU : la même clé rejouée après révocation → refus revoked ;
--        une seconde révocation le dit (already_revoked)
--        (ROUGE avant : révoquer « à vide » rendait success: true)
--   T06  EXPIRATION : une clé expirée est refusée nommément (expired)
--        (ROUGE avant : personne ne lisait expires_at — ni la base, ni
--        public-api, qui filtrait sur active seul)
--   T07  isolation : chaque clé rend SA société, pas celle de l'appelant
--   T08  révoquer la clé d'une AUTRE société : refus nommé
--        (ROUGE avant : success: true muet sur une clé étrangère)
--   T09  TOTP — le vecteur du RFC 6238 lui-même : counter 1 → 287082
--        (ROUGE avant : les fonctions n'existaient pas)
--   T10  TOTP — un code qui n'est pas 6 chiffres est refusé
--        (non-régression, la 130 savait faire)
--   T11  TOTP — un code JUSTE est accepté, et la réponse ne rend PLUS le
--        secret (ROUGE avant : la réponse rendait le secret)
--   T12  TOTP — un code FAUX est REFUSÉ
--        (ROUGE avant : la 130 rendait valid:true pour TOUT code à 6 chiffres)
--   T13  TOTP — le cycle complet : enable → verify (l'ancienne refusait
--        après activation : elle ne lisait que les enrôlements « pendants »)
--        → disable → status disabled
--
-- NB : la suite s'exécute en superutilisateur (psql de la CI) :
-- `authenticate_api_key` est réservée à `service_role` — c'est VOULU, seul
-- public-api (clé de service) doit y répondre.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '700', false);
DELETE FROM _audit_results WHERE file = '700';

-- T01 — émission : la clé rendue une fois, le hash stocké est le SHA-256
DO $$
DECLARE t uuid := _mk_tenant('F700T01'); r jsonb; k record;
BEGIN
  r := create_api_key('Clé T01', '["read"]'::jsonb, 100, NULL);
  SELECT * INTO k FROM api_keys WHERE id = (r ->> 'id')::uuid;
  PERFORM _rec('T01', 'émission : la clé rendue une seule fois, le hash stocké est son SHA-256, active, jamais utilisée',
    r ? 'full_key' AND left(r ->> 'full_key', 4) = 'onu_'
      AND k.key_hash = encode(digest(r ->> 'full_key', 'sha256'), 'hex')
      AND k.active IS TRUE AND k.revoked_at IS NULL AND k.last_used_at IS NULL,
    format('préfixe=%s active=%s hash=%s…', left(r ->> 'full_key', 8), k.active, left(k.key_hash, 12)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'émission : la clé rendue une seule fois, hash SHA-256 stocké', false, SQLERRM);
END $$;

-- T02 — usage : la clé SERT, et la base le retient (last_used_at)
DO $$
DECLARE t uuid := _mk_tenant('F700T02'); r jsonb; a jsonb; k record;
BEGIN
  r := create_api_key('Clé T02', '["read"]'::jsonb, 100, NULL);
  a := authenticate_api_key(r ->> 'full_key');
  SELECT * INTO k FROM api_keys WHERE id = (r ->> 'id')::uuid;
  PERFORM _rec('T02', 'usage : authenticate_api_key dit OUI pour la bonne société, et pose last_used_at',
    (a ->> 'authenticated')::boolean
      AND (a ->> 'api_key_id')::uuid = (r ->> 'id')::uuid
      AND (a ->> 'tenant_id')::uuid = t
      AND k.last_used_at IS NOT NULL,
    format('authenticated=%s société=%s last_used_at=%s', a ->> 'authenticated', a ->> 'tenant_id', k.last_used_at));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'usage : authenticate_api_key dit OUI et pose last_used_at', false, SQLERRM);
END $$;

-- T03 — mauvaise clé : refus nommé, pas un invalide fourre-tout
DO $$
DECLARE t uuid := _mk_tenant('F700T03'); a jsonb;
BEGIN
  a := authenticate_api_key('onu_cle_que_personne_na_émise');
  PERFORM _rec('T03', 'mauvaise clé : refus nommé not_found',
    NOT (a ->> 'authenticated')::boolean AND a ->> 'reason' = 'not_found',
    format('authenticated=%s reason=%s', a ->> 'authenticated', a ->> 'reason'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'mauvaise clé : refus nommé not_found', false, SQLERRM);
END $$;

-- T04 — révocation : le drapeau ET la date, ensemble
DO $$
DECLARE t uuid := _mk_tenant('F700T04'); r jsonb; rv jsonb; k record;
BEGIN
  r := create_api_key('Clé T04', '["read"]'::jsonb, 100, NULL);
  rv := revoke_api_key((r ->> 'id')::uuid);
  SELECT * INTO k FROM api_keys WHERE id = (r ->> 'id')::uuid;
  PERFORM _rec('T04', 'révocation : le drapeau tombe ET la date est posée',
    (rv ->> 'success')::boolean AND k.active IS FALSE AND k.revoked_at IS NOT NULL,
    format('success=%s active=%s revoked_at=%s', rv ->> 'success', k.active, k.revoked_at));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'révocation : le drapeau tombe ET la date est posée', false, SQLERRM);
END $$;

-- T05 — REJEU : la même clé rejouée après révocation est refusée, et la
-- seconde révocation le dit au lieu de réussir en silence
DO $$
DECLARE t uuid := _mk_tenant('F700T05'); r jsonb; a jsonb; rv2 jsonb;
BEGIN
  r := create_api_key('Clé T05', '["read"]'::jsonb, 100, NULL);
  PERFORM revoke_api_key((r ->> 'id')::uuid);
  a := authenticate_api_key(r ->> 'full_key');
  rv2 := revoke_api_key((r ->> 'id')::uuid);
  PERFORM _rec('T05', 'rejeu : la clé révoquée rejouée est refusée nommément (revoked), la seconde révocation dit already_revoked',
    NOT (a ->> 'authenticated')::boolean AND a ->> 'reason' = 'revoked'
      AND (rv2 ->> 'already_revoked')::boolean,
    format('reason=%s already_revoked=%s', a ->> 'reason', rv2 ->> 'already_revoked'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'rejeu : la clé révoquée rejouée est refusée', false, SQLERRM);
END $$;

-- T06 — EXPIRATION : une clé expirée est refusée nommément. Personne ne
-- lisait expires_at avant la 700 — ni public-api (active seul), ni personne.
DO $$
DECLARE t uuid := _mk_tenant('F700T06'); r jsonb; a jsonb;
BEGIN
  r := create_api_key('Clé T06 expirée', '["read"]'::jsonb, 100, now() - interval '1 minute');
  a := authenticate_api_key(r ->> 'full_key');
  PERFORM _rec('T06', 'expiration : une clé expirée est refusée nommément (expired)',
    NOT (a ->> 'authenticated')::boolean AND a ->> 'reason' = 'expired',
    format('authenticated=%s reason=%s expires_at posé dans le passé', a ->> 'authenticated', a ->> 'reason'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'expiration : une clé expirée est refusée nommément', false, SQLERRM);
END $$;

-- T07 — isolation : chaque clé rend SA société — le credential porte la
-- société, l'appelant n'a rien à dire
DO $$
DECLARE ta uuid; tb uuid; ra jsonb; rb jsonb; aa jsonb; ab jsonb;
BEGIN
  -- La clé de A naît dans le contexte de A, AVANT de passer dans B
  ta := _mk_tenant('F700T07A');
  ra := create_api_key('Clé T07 A', '["read"]'::jsonb, 100, NULL);
  tb := _mk_tenant('F700T07B');
  rb := create_api_key('Clé T07 B', '["read"]'::jsonb, 100, NULL);
  aa := authenticate_api_key(ra ->> 'full_key');
  ab := authenticate_api_key(rb ->> 'full_key');
  PERFORM _rec('T07', 'isolation : chaque clé rend SA société, jamais celle de l''autre',
    (aa ->> 'tenant_id')::uuid = ta AND (ab ->> 'tenant_id')::uuid = tb
      AND (aa ->> 'tenant_id') IS DISTINCT FROM (ab ->> 'tenant_id'),
    format('A→%s B→%s (attendu : chacun la sienne)', aa ->> 'tenant_id', ab ->> 'tenant_id'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'isolation : chaque clé rend SA société', false, SQLERRM);
END $$;

-- T08 — révoquer la clé d'une AUTRE société : refus nommé. Avant la 700,
-- revoke_api_key rendait success: true sans jamais toucher la ligne.
DO $$
DECLARE ta uuid := _mk_tenant('F700T08A'); tb uuid := _mk_tenant('F700T08B');
        ra jsonb;
BEGIN
  -- On repose le contexte de A (le dernier _mk_tenant est celui de B) : la
  -- clé naît dans la société A, avec le numéro de session de A.
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM set_config('request.jwt.claim.sub',
    (SELECT tenant_users.auth_id::text FROM tenant_users WHERE tenant_id = ta LIMIT 1), false);
  ra := create_api_key('Clé T08 A', '["read"]'::jsonb, 100, NULL);
  -- Et l'on redevient la société B : la clé de A est étrangère
  PERFORM set_config('app.active_tenant_id', tb::text, false);
  PERFORM set_config('request.jwt.claim.sub',
    (SELECT tenant_users.auth_id::text FROM tenant_users WHERE tenant_id = tb LIMIT 1), false);
  BEGIN
    PERFORM revoke_api_key((ra ->> 'id')::uuid);
    PERFORM _rec('T08', 'révocation croisée : la clé d''une autre société est un refus nommé', false,
      'révoquée sans refus — la fuite de la 130 est ouverte');
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T08', 'révocation croisée : la clé d''une autre société est un refus nommé',
      SQLERRM LIKE '%API_KEY_INTROUVABLE%', SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'révocation croisée : refus nommé API_KEY_INTROUVABLE', false, SQLERRM);
END $$;


-- T09 — TOTP : les vecteurs du RFC 6238 lui-même (secret de test du RFC,
-- base32 GEZDGNBVGY3TQOJQ…, 6 chiffres). Ce n'est pas la fonction qui se
-- prouve elle-même : c'est le standard.
DO $$
DECLARE v bytea := _totp_b32('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
BEGIN
  PERFORM _rec('T09', 'TOTP — trois vecteurs du RFC 6238 (SHA1, 6 chiffres)',
    _totp_code(v, 1) = '287082'
      AND _totp_code(v, 37037036) = '081804'
      AND _totp_code(v, 666666666) = '353130',
    format('c1=%s c37037036=%s c666666666=%s (attendus 287082, 081804, 353130)',
      _totp_code(v, 1), _totp_code(v, 37037036), _totp_code(v, 666666666)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'TOTP — vecteurs du RFC 6238', false, SQLERRM);
END $$;

-- T10 — TOTP : un code qui n'est pas 6 chiffres est refusé par son format
DO $$
DECLARE t uuid := _mk_tenant('F700T10'); rv jsonb;
BEGIN
  rv := verify_totp('abcdef');
  PERFORM _rec('T10', 'TOTP — un code non numérique est refusé (format)',
    NOT (rv ->> 'valid')::boolean AND rv ->> 'error' = 'Invalid token format',
    format('valid=%s error=%s', rv ->> 'valid', rv ->> 'error'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T10', 'TOTP — un code non numérique est refusé', false, SQLERRM);
END $$;

-- T11 — TOTP : un enrôlement PENDING (enabled=false, tel que l'ancienne
-- fonction le lisait), le code JUSTE est accepté — et la réponse ne rend
-- PLUS le secret (l'ancienne le rendait).
DO $$
DECLARE t uuid := _mk_tenant('F700T11'); v_user uuid; v_b32 text;
        v_secret bytea; v_juste text; rv jsonb;
BEGIN
  v_user := current_setting('request.jwt.claim.sub')::uuid;
  v_b32 := 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  INSERT INTO user_totp (user_id, tenant_id, secret_enc, backup_codes, enabled)
  VALUES (v_user, t, encode(convert_to(v_b32, 'UTF8'), 'base64'), '[]'::jsonb, false);
  v_secret := _totp_b32(v_b32);
  v_juste := _totp_code(v_secret, floor(extract(epoch from now()) / 30)::bigint);
  rv := verify_totp(v_juste);
  PERFORM _rec('T11', 'TOTP — le code JUSTE est accepté, et la réponse ne rend plus le secret',
    (rv ->> 'valid')::boolean AND NOT (rv ? 'secret'),
    format('valid=%s contient_secret=%s window=%s', rv ->> 'valid', rv ? 'secret', rv ->> 'window'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T11', 'TOTP — le code juste est accepté, sans le secret', false, SQLERRM);
END $$;

-- T12 — TOTP : un code FAUX est REFUSÉ. Avant la 700, TOUT code à 6 chiffres
-- passait dès qu'un enrôlement existait — c'était un tampon, pas une preuve.
DO $$
DECLARE t uuid := _mk_tenant('F700T12'); v_user uuid; v_b32 text;
        v_secret bytea; v_c bigint; v_faux text; rv jsonb;
BEGIN
  v_user := current_setting('request.jwt.claim.sub')::uuid;
  v_b32 := 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  INSERT INTO user_totp (user_id, tenant_id, secret_enc, backup_codes, enabled)
  VALUES (v_user, t, encode(convert_to(v_b32, 'UTF8'), 'base64'), '[]'::jsonb, false);
  v_secret := _totp_b32(v_b32);
  v_c := floor(extract(epoch from now()) / 30)::bigint;
  -- un code faux qui ne peut PAS être celui d'une des trois fenêtres
  v_faux := '000000';
  WHILE v_faux IN (_totp_code(v_secret, v_c - 1), _totp_code(v_secret, v_c), _totp_code(v_secret, v_c + 1)) LOOP
    v_faux := lpad(((v_faux::int + 1) % 1000000)::text, 6, '0');
  END LOOP;
  rv := verify_totp(v_faux);
  PERFORM _rec('T12', 'TOTP — un code FAUX est refusé (l''ancienne acceptait tout code à 6 chiffres)',
    NOT (rv ->> 'valid')::boolean AND rv ->> 'error' = 'Token does not match',
    format('valid=%s error=%s', rv ->> 'valid', rv ->> 'error'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T12', 'TOTP — un code faux est refusé', false, SQLERRM);
END $$;

-- T13 — TOTP : le cycle complet de l'écran (TwoFactorPage) : enable →
-- verify → disable → disabled. L'ancienne refusait APRÈS activation : elle
-- ne lisait que les enrôlements pendants (WHERE enabled = false).
DO $$
DECLARE t uuid := _mk_tenant('F700T13'); v_b32 text; v_secret bytea;
        v_juste text; rv jsonb; st jsonb; st2 jsonb;
BEGIN
  v_b32 := 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  v_secret := _totp_b32(v_b32);
  PERFORM enable_2fa(encode(convert_to(v_b32, 'UTF8'), 'base64'), '["QUNDLU0wMDA="]'::jsonb);
  st := get_2fa_status();
  v_juste := _totp_code(v_secret, floor(extract(epoch from now()) / 30)::bigint);
  rv := verify_totp(v_juste);
  PERFORM disable_2fa();
  st2 := get_2fa_status();
  PERFORM _rec('T13', 'TOTP — cycle complet : enable → status activé → verify accepté → disable → status désactivé',
    (st ->> 'enabled')::boolean
      AND (rv ->> 'valid')::boolean
      AND NOT (st2 ->> 'enabled')::boolean,
    format('enable=%s verify=%s après_disable=%s', st ->> 'enabled', rv ->> 'valid', st2 ->> 'enabled'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T13', 'TOTP — cycle complet enable/verify/disable', false, SQLERRM);
END $$;

-- Le verdict : chaque scénario relit, la suite peut échouer (G5, check-test-suites)
SELECT _audit_assert('700');
