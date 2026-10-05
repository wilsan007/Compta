-- 700 — auth_forte_api_keys_totp
-- Numéro pris le 2026-10-05T18:37:52.184Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- ORPH-01 / SEC-02 (partie F.2 du plan du 05/10) :
-- AUTHENTIFICATION FORTE — le cycle de vie d'une clé API, et TOTP réel.
--
-- Le constat mesuré au recomptage (SUIVI-CHANTIERS, ORPH-01) :
--   * `api_keys` et `user_totp` existent depuis la 92/93, leurs RPC depuis
--     la 130 — et AUCUNE suite SQL ne les exerçait. Seul
--     `src/__tests__/phase5-enterprise-features.test.ts` les nommait, avec
--     Supabase simulé : des enregistrements d'exemple, pas des preuves ;
--   * `public-api` (le seul lecteur réel de `api_keys`) FILTRAIT sur
--     `active = true` — jamais sur `expires_at` : une clé EXPIRÉE ouvrait
--     l'API aussi longtemps que personne ne la révoquait. Le front, lui,
--     révoque par écriture directe `active = false` (ApiWebhooksPage), un
--     chemin que la RLS garde mais que rien ne relisait ;
--   * `verify_totp` acceptait N'IMPORTE QUEL code à 6 chiffres dès qu'un
--     enrôlement existait (« la vraie vérification TOTP doit être faite côté
--     application », disait son commentaire) — et RENDAIT LE SECRET à
--     l'appelant.
--
-- Ce que cette migration pose :
--   1. `authenticate_api_key(p_raw_key)` — LA fonction qui répond du cycle de
--      vie d'une clé : inconnue, révoquée (drapeau OU date), expirée, ou
--      valide (et alors `last_used_at` est posé). Réservée à `service_role` :
--      c'est le point d'entrée de l'Edge Function `public-api`, qui n'en
--      garde plus aucune copie de logique.
--   2. TOTP réel, RFC 6238 (HMAC-SHA1, base32 RFC 4648) : `_totp_b32`,
--      `_totp_code` — prouvés par le vecteur du RFC lui-même — et
--      `verify_totp` réécrit : un code faux est REFUSÉ, le secret n'est plus
--      rendu. Le secret se déballe de son base64 (le front stocke
--      `btoa(base32)`, TwoFactorPage).
--   3. `revoke_api_key` dit la vérité : un identifiant hors de SA société est
--      un refus nommé, plus un `success: true` muet. Elle n'a AUCUN appelant
--      front (l'écran écrit directement, RLS garde ce chemin), donc aucun
--      écran ne peut casser.
--
-- La preuve : `sql/700_auth_forte_api_keys_totp_tests.sql` (T01 → T12),
-- et le test Edge « clé révoquée → 401 »
-- (`supabase/functions/__tests__/api_key_auth_test.ts`).
--
-- Pas de changement de schéma (aucune colonne, aucune table) :
-- `npm run db:types` n'a rien à régénérer.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. authenticate_api_key — le cycle de vie d'une clé, en un seul endroit
-- ============================================================
-- Prend la clé EN CLAIR telle que l'appelant la porte (X-API-Key), la hache
-- côté base (SEC-01 : la clé ne traverse jamais la requête SQL en clair —
-- c'est déjà le hash qui est stocké), et répond du cycle de vie.
-- Les raisons de refus sont NOMMÉES : l'appelant rend un 401 motivé, pas un
-- « invalide » fourre-tout.
CREATE OR REPLACE FUNCTION authenticate_api_key(p_raw_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hash    text;
  v_id      uuid;
  v_tenant  uuid;
  v_perm    jsonb;
  v_active  boolean;
  v_revoked timestamptz;
  v_expires timestamptz;
BEGIN
  IF p_raw_key IS NULL OR btrim(p_raw_key) = '' THEN
    RETURN jsonb_build_object('authenticated', false, 'reason', 'missing_key');
  END IF;

  v_hash := encode(digest(p_raw_key, 'sha256'), 'hex');

  SELECT id, tenant_id, permissions, active, revoked_at, expires_at
    INTO v_id, v_tenant, v_perm, v_active, v_revoked, v_expires
    FROM api_keys
   WHERE key_hash = v_hash;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authenticated', false, 'reason', 'not_found');
  END IF;

  -- Révocation : le drapeau OU la date — l'un sans l'autre est une anomalie,
  -- et les DEUX chemins de révocation écrivent les deux colonnes (l'écran
  -- par UPDATE direct, revoke_api_key aussi).
  IF v_revoked IS NOT NULL OR v_active IS NOT TRUE THEN
    RETURN jsonb_build_object('authenticated', false, 'reason', 'revoked');
  END IF;

  IF v_expires IS NOT NULL AND v_expires <= now() THEN
    RETURN jsonb_build_object('authenticated', false, 'reason', 'expired');
  END IF;

  UPDATE api_keys SET last_used_at = now() WHERE id = v_id;

  RETURN jsonb_build_object(
    'authenticated', true,
    'api_key_id',    v_id,
    'tenant_id',     v_tenant,
    'permissions',   v_perm
  );
END $$;

-- Réservée à service_role : c'est le credential-checker de l'API publique.
-- Jamais à anon, jamais à authenticated (un appelant loggé n'a pas à sonder
-- des clés ; il a déjà sa session).
REVOKE ALL ON FUNCTION authenticate_api_key(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION authenticate_api_key(text) TO service_role;

COMMENT ON FUNCTION authenticate_api_key(text) IS
  'ORPH-01/SEC-02 (700) : répond du cycle de vie d''une clé API — not_found, '
  'revoked (drapeau ou date), expired, ou valide (et alors pose last_used_at). '
  'Hash SHA-256 côté base (SEC-01). Réservée à service_role : le point d''entrée '
  'de l''Edge Function public-api.';

-- ============================================================
-- 2. TOTP réel — RFC 6238 sur HMAC-SHA1 (RFC 4226)
-- ============================================================

-- Base32 (RFC 4648, sans remplissage) → octets. Le secret d'une appli
-- d'authentification (Google Authenticator, Authy…) est TOUJOURS en base32.
-- Fonctions pures : elles ne lisent aucune table, et être appelées par
-- n'importe qui ne révèle rien (sans le secret, on ne calcule rien).
-- Validation STRICTE : un secret corrompu est refusé, jamais « nettoyé ».
CREATE OR REPLACE FUNCTION _totp_b32(p_b32 text)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s     text;
  acc   bigint := 0;
  bits  int := 0;
  v     int;
  o     int;
  r     bytea := ''::bytea;
BEGIN
  s := replace(upper(btrim(p_b32)), '=', '');
  IF s !~ '^[A-Z2-7]+$' THEN
    RAISE EXCEPTION 'TOTP_B32_INVALIDE : le secret n''est pas en base32';
  END IF;

  FOR o IN 1..length(s) LOOP
    v := strpos('ABCDEFGHIJKLMNOPQRSTUVWXYZ234567', substr(s, o, 1)) - 1;
    acc  := (acc << 5) | v;
    bits := bits + 5;
    IF bits >= 8 THEN
      bits := bits - 8;
      r := r || '\x00'::bytea;
      r := set_byte(r, octet_length(r) - 1, ((acc >> bits) & 255)::int);
      acc := acc & ((1 << bits) - 1);
    END IF;
  END LOOP;

  RETURN r;
END $$;

-- Un code TOTP (6 chiffres, période 30 s) pour un compteur donné.
-- La troncature dynamique est celle du RFC 4226 §5.3 ; le vecteur du RFC 6238
-- la prouve dans la suite 700 (T09 : counter 1 du secret de test → 287082).
CREATE OR REPLACE FUNCTION _totp_code(p_secret bytea, p_counter bigint)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  h   bytea;
  off int;
  bin bigint;
BEGIN
  h   := hmac(substring(int8send(p_counter) from 1 for 8), p_secret, 'sha1');
  -- RFC 4226 §5.3 : offset = dernier octet & 0x0f (get_byte est 0-indexé :
  -- PAS de +1). 0 ≤ off ≤ 15, donc off+3 ≤ 18 : jamais hors des 20 octets.
  off := get_byte(h, 19) & 15;
  bin := ((get_byte(h, off)     & 127)::bigint << 24)
      | ((get_byte(h, off + 1) & 255)::bigint << 16)
      | ((get_byte(h, off + 2) & 255)::bigint << 8)
      |  (get_byte(h, off + 3) & 255)::bigint;
  RETURN lpad((bin % 1000000)::text, 6, '0');
END $$;

-- ============================================================
-- 3. verify_totp — réécrit : un code FAUX est refusé, le secret n'est plus rendu
-- ============================================================
-- Avant (130) : format vérifié, puis valid = true pour TOUT code à 6 chiffres
-- dès qu'un enrôlement pendait — et la réponse RENDAIT le secret. Ce n'était
-- pas une vérification, c'était un tampon. Maintenant : HMAC réel, tolérance
-- d'une fenêtre de part et d'autre (±30 s, comme les applis d'authentification
-- elles-mêmes), et une réponse qui ne contient plus jamais le secret.
CREATE OR REPLACE FUNCTION verify_totp(
  p_token text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_user     uuid := auth.uid();
  v_tenant   uuid := current_tenant_id();
  v_enc      text;
  v_b32      text;
  v_secret   bytea;
  v_counter  bigint;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'No authenticated user';
  END IF;

  -- Valide le format (6 chiffres)
  IF p_token IS NULL OR p_token !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Invalid token format');
  END IF;

  -- L'ancienne ne lisait que les enrôlements PENDANTS ; un code se vérifie
  -- aussi bien après activation (c'est alors un jeton de connexion).
  SELECT secret_enc INTO v_enc
    FROM user_totp
   WHERE user_id = v_user AND tenant_id = v_tenant;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'No 2FA setup');
  END IF;

  -- Le front stocke base64(base32) — TwoFactorPage : btoa(secret). Un secret
  -- posé autrement reste lisible : on tente le déballage, et s'il ne donne
  -- pas du base32, on prend le texte tel quel.
  BEGIN
    v_b32 := btrim(convert_from(decode(v_enc, 'base64'), 'UTF8'));
  EXCEPTION WHEN OTHERS THEN
    v_b32 := v_enc;
  END;
  IF v_b32 !~ '^[A-Z2-7]+=*$' THEN
    v_b32 := v_enc;
  END IF;

  BEGIN
    v_secret := _totp_b32(v_b32);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Stored secret unreadable');
  END;

  v_counter := floor(extract(epoch from now()) / 30)::bigint;

  -- Tolérance d'une fenêtre de part et d'autre : l'horloge de l'appli du
  -- salarié n'est pas celle du serveur. RFC 6238 §5.2.
  FOR i IN -1..1 LOOP
    IF _totp_code(v_secret, v_counter + i) = p_token THEN
      RETURN jsonb_build_object('valid', true, 'window', i);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('valid', false, 'error', 'Token does not match');
END $$;

COMMENT ON FUNCTION verify_totp(text) IS
  'ORPH-01/SEC-02 (700) : vérification TOTP RÉELLE (RFC 6238, HMAC-SHA1, ±1 '
  'fenêtre). Refuse un code faux — l''ancienne version (130) acceptait tout code '
  'à 6 chiffres — et ne rend plus le secret.';

-- ============================================================
-- 4. revoke_api_key — un refus est un verdict, pas un succès muet
-- ============================================================
-- Avant (130) : UPDATE … WHERE id = p_key_id AND tenant_id = v_tenant, puis
-- success = true QUEL QUE SOIT le résultat : une clé d'une AUTRE société
-- « se révoquait » en silence. Aucun appelant front (l'écran écrit
-- directement, RLS garde ce chemin) : le durcissement ne peut casser rien.
CREATE OR REPLACE FUNCTION revoke_api_key(p_key_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant  uuid := current_tenant_id();
  v_row     api_keys%ROWTYPE;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'No active tenant';
  END IF;

  SELECT * INTO v_row
    FROM api_keys
   WHERE id = p_key_id AND tenant_id = v_tenant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'API_KEY_INTROUVABLE : aucune clé % dans votre société', p_key_id;
  END IF;

  IF v_row.active IS NOT TRUE OR v_row.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_revoked', true);
  END IF;

  UPDATE api_keys
     SET active = false,
         revoked_at = now()
   WHERE id = p_key_id AND tenant_id = v_tenant;

  RETURN jsonb_build_object('success', true);
END $$;

COMMENT ON FUNCTION revoke_api_key(uuid) IS
  'ORPH-01/SEC-02 (700) : révoque une clé de SA société. Un identifiant '
  'étranger est un refus nommé (API_KEY_INTROUVABLE), une clé déjà révoquée '
  'le dit (already_revoked) — plus jamais un success muet.';
