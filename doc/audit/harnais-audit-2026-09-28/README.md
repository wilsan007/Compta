# Harnais de l'audit fonctionnel du 28/09/2026

Fait tourner **le vrai front** et **ses vraies fonctions de requête** contre une base locale,
sous RLS réelle. Aucun secret n'est versionné ici : `jwt_secret`, `anon_key` et `rig_users.json`
(comptes de test) sont à régénérer.

1. Base : conteneur `postgres:16` → `sql/ci/00_supabase_stubs.sql` → `sql/00_schema_dump.sql`
   → `node run-sql-migrations.mjs` ; rôle `authenticator` (LOGIN, NOINHERIT, membre de
   `anon`, `authenticated`, `service_role`).
2. Comptes : `auth.users` + `create_tenant_for_current_user(...)` (chemin réel d'inscription),
   un lecteur et un comptable ajoutés dans `tenant_users`. Liste dans `rig_users.json`
   (`[{id,email,password,name}]` : admin A, admin B, lecteur A, comptable A).
3. `postgrest/postgrest:v16.3` avec `PGRST_JWT_SECRET` = `jwt_secret`, exposé sur `:3399`.
4. `node gateway.mjs` (port 54399) : `/rest/v1` → PostgREST, `/auth/v1` → GoTrue minimal.
5. Scénarios : `VITE_SUPABASE_URL=http://localhost:54399 VITE_SUPABASE_PUBLISHABLE_KEY=<anon_key>
   npx vitest run -c audit/vitest.audit.config.ts --dir audit <nom>` (depuis `app/`).
6. Contrôles : `node screen-writes.mjs` (colonnes écrites par les écrans à travers les fonctions),
   `node viewer-sweep.cjs` (ce qu'un lecteur peut modifier), `sweep.js` / `sweep2.js`
   (balayage des 333 routes dans le navigateur).

Ne jamais pointer ce harnais vers la base de production : il **écrit**.
