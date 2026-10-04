-- ============================================================
-- 167_harden_ssrf_webhook_url.sql
--
-- LOT5-05 (durci) : renforce is_allowed_webhook_url contre les VRAIS bypass de
-- filtre SSRF que la version 154 laissait passer, parce qu'elle ne comparait que
-- des préfixes de chaîne sur le hostname :
--
--   - IPv4 encodée : décimale 32 bits (https://2130706433/ = 127.0.0.1),
--     hexadécimale (0x7f000001), octale (0177.0.0.1), abrégée (127.1) ;
--   - userinfo trompeur : https://expected.com@169.254.169.254/ ;
--   - IPv6 IPv4-mapped : [::ffff:169.254.169.254] ;
--   - plages oubliées : CGNAT 100.64.0.0/10, multicast/broadcast, fc00::/7.
--
-- Cette fonction est la garde À L'ENREGISTREMENT (trigger sur webhook_endpoints),
-- donc une défense en profondeur. Le DNS rebinding (domaine public → IP privée)
-- et les redirections HTTP ne sont PAS détectables en SQL : ils sont bloqués à
-- l'exécution par la Edge Function outgoing-webhooks (assertPublicHost + safeFetch).
--
-- Miroir de app/src/lib/security/ssrfGuard.ts.
-- ============================================================

CREATE OR REPLACE FUNCTION is_allowed_webhook_url(p_url text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_protocol text;
  v_hostport text;
  v_hostname text;
  v_inet     inet;
BEGIN
  IF p_url IS NULL THEN
    RETURN false;
  END IF;

  -- Protocole : HTTPS uniquement
  v_protocol := lower(split_part(p_url, '://', 1));
  IF v_protocol <> 'https' THEN
    RETURN false;
  END IF;

  -- Authority = tout ce qui suit :// jusqu'au premier /
  v_hostport := split_part(split_part(p_url, '://', 2), '/', 1);
  -- Retirer un éventuel userinfo (user:pass@) — greedy jusqu'au DERNIER @
  v_hostport := regexp_replace(v_hostport, '^.*@', '');

  -- Hostname : littéral IPv6 entre crochets, sinon on retire le port
  IF left(v_hostport, 1) = '[' THEN
    v_hostname := lower(substring(v_hostport from '\[(.*)\]'));
  ELSE
    v_hostname := lower(split_part(v_hostport, ':', 1));
  END IF;

  IF v_hostname IS NULL OR v_hostname = '' THEN
    RETURN false;
  END IF;

  -- Hôtes locaux
  IF v_hostname = 'localhost'
     OR v_hostname LIKE '%.local'
     OR v_hostname LIKE '%.internal' THEN
    RETURN false;
  END IF;

  -- Encodages IPv4 qui contournent une comparaison de préfixe :
  --   décimal 32 bits (que des chiffres), hexadécimal (0x…), octal (segment 0…)
  IF v_hostname ~ '^[0-9]+$' THEN
    RETURN false;                              -- ex. 2130706433, 2852039166
  END IF;
  IF v_hostname ~* '^0x' THEN
    RETURN false;                              -- ex. 0x7f000001
  END IF;
  -- Octal pointé : segment à zéro-en-tête, MAIS seulement si l'hôte est
  -- entièrement numérique-pointé (sinon on bloquerait un domaine « 01foo.ex.com »).
  IF v_hostname ~ '^[0-9]{1,12}(\.[0-9]{1,12}){1,3}$'
     AND v_hostname ~ '(^|\.)0[0-9]' THEN
    RETURN false;                              -- octal, ex. 0177.0.0.1
  END IF;

  -- IPv6 IPv4-mapped / non-spécifiée : bloquer explicitement (inet ne les classe
  -- pas dans les plages IPv4 privées).
  IF v_hostname ~* '^::ffff:' OR v_hostname = '::' THEN
    RETURN false;
  END IF;

  -- Classement par plages via le type inet (IPv4 pointée + IPv6 standard).
  -- Un nom de domaine échoue au cast → on laisse passer (validé au fetch).
  BEGIN
    v_inet := v_hostname::inet;
  EXCEPTION WHEN others THEN
    v_inet := NULL;
  END;

  IF v_inet IS NOT NULL THEN
    IF family(v_inet) = 4 THEN
      IF v_inet <<= ANY (ARRAY[
        '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
        '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24',
        '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4'
      ]::inet[]) THEN
        RETURN false;
      END IF;
    ELSE
      -- IPv4-mapped (::ffff:0:0/96) sous toutes ses formes (courte ou longue) :
      -- jamais une cible de webhook légitime → bloquer sans condition.
      IF v_inet <<= '::ffff:0:0/96'::inet THEN
        RETURN false;
      END IF;
      IF v_inet <<= ANY (ARRAY[
        '::1/128', '::/128', 'fc00::/7', 'fe80::/10', 'ff00::/8'
      ]::inet[]) THEN
        RETURN false;
      END IF;
    END IF;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION is_allowed_webhook_url(text) TO authenticated;

-- Le trigger validate_webhook_url (migration 154) référence la fonction par nom :
-- le CREATE OR REPLACE ci-dessus suffit, pas besoin de recréer le trigger.

-- ============================================================
-- Fin migration 167
-- ============================================================
