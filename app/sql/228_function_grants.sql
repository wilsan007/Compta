-- ============================================================
-- 228_function_grants.sql — H09 : ce que peut appeler un visiteur non connecté
--
-- CONSTAT, mesuré le 23/09 sur base neuve (202 migrations) :
--   389 fonctions dans `public`, dont 284 SECURITY DEFINER ;
--   **332 exécutables par `anon`** — le rôle du visiteur non connecté, dont la
--   clé voyage dans le bundle du navigateur — et **75 des 96 RPC de l'écran**.
--   L'exposition ne vient pas d'un GRANT écrit à la main : `CREATE FUNCTION`
--   accorde EXECUTE à PUBLIC par défaut (227 fonctions ont en plus le GRANT
--   `anon` que l'image Supabase pose par `ALTER DEFAULT PRIVILEGES`). La
--   migration 78 avait bien révoqué `anon` en son temps ; les 149 migrations
--   suivantes ont recréé la dérive, fonction après fonction.
--
-- PROUVÉ AVANT CORRECTIF, sous le rôle `anon`, sans aucun jeton :
--   SELECT auto_revoke_expired_auditors();  -> 0   (exécutée : révocation des auditeurs)
--   SELECT generate_recurring_tasks();      -> ok  (exécutée : création de tâches)
--   SELECT cleanup_expired_idempotency();   -> 0   (exécutée : purge)
--   Trois fonctions SECURITY DEFINER qui écrivent, lancées par n'importe qui.
--   (`disable_2fa()` refusait déjà : « No authenticated user » — la garde était
--   dans le corps, pas dans le droit.)
--
-- CORRECTIF : un visiteur non connecté n'appelle plus rien, sauf deux fonctions
-- inscrites et justifiées. `authenticated` n'est pas touché (362 fonctions,
-- dont les 96 RPC de l'écran) : restreindre l'utilisateur connecté à ce qu'il
-- doit pouvoir appeler relève du chantier des rôles (H08/D-6), pas d'ici.
--
-- ANTI-DÉRIVE. La révocation seule serait défaite par la prochaine fonction
-- créée — c'est exactement ce qui est arrivé à la migration 78. Deux moyens,
-- dont un seul marche, mesuré ici plutôt que supposé :
--   * `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM anon`
--     fonctionne : le GRANT explicite que l'image Supabase pose disparaît des
--     privilèges par défaut du schéma ;
--   * la même chose `FROM PUBLIC` **ne fait rien**. Mesuré : après la
--     révocation, une fonction créée ensuite a `proacl = NULL`, c'est-à-dire le
--     droit par défaut de PostgreSQL — `EXECUTE` à PUBLIC — et
--     `has_function_privilege('anon', …, 'EXECUTE')` rend toujours vrai. Le
--     droit PUBLIC de `CREATE FUNCTION` n'est pas un GRANT stocké : on ne peut
--     pas le retirer d'avance.
-- Donc le garde-fou permanent n'est pas dans les privilèges par défaut : c'est
-- `ci/check_anon_grants.sql`, qui fait échouer la CI sur toute fonction
-- exposée hors registre. Une migration qui crée une RPC révoque PUBLIC dans sa
-- propre ligne, ou la CI le lui rappelle.
-- ============================================================

-- 1. Plus rien pour PUBLIC ni pour anon
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

-- 2. Les deux exceptions, justifiées
--    current_tenant_id() : les politiques RLS des tables de référence lisibles
--    sans connexion (currencies, legislation_packs, tax_rates) l'appellent.
--    Sans ce droit, `SELECT * FROM currencies` répond « permission denied for
--    function current_tenant_id » à la page d'inscription. Elle rend NULL pour
--    un visiteur : aucune donnée de société ne transite.
GRANT EXECUTE ON FUNCTION public.current_tenant_id() TO anon;

--    available_signup_countries() : la liste des pays ouverts à l'inscription,
--    lue par l'écran d'inscription. Référentiel, aucune donnée de société.
GRANT EXECUTE ON FUNCTION public.available_signup_countries() TO anon;

-- 3. Les fonctions à venir ne seront plus accordées à anon
--    (le droit PUBLIC, lui, ne se retire pas d'avance — voir l'en-tête :
--     c'est ci/check_anon_grants.sql qui l'attrape)
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
