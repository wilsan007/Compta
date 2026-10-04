-- Étape 6 — inscription par pays, dans UNE transaction annulée à la fin.
-- Usage : psql -v pays='France|Djibouti' -f signup_par_pays.sql   (séparateur |)
-- Rien ne reste en base : ROLLBACK final ; en cas d'erreur, psql s'arrête et la
-- connexion fermée annule aussi la transaction. Seules les séquences avancent.
\set ON_ERROR_STOP 1
BEGIN;
SET LOCAL statement_timeout = '10min';
SELECT set_config('rehearsal.pays', :'pays', true) \gset _ignore_

CREATE TEMP TABLE _signup_res (
  pays text, devise text, succes boolean, tenant uuid, comptes int, journaux text,
  exercices_ouverts int, parametres int, devise_societe text, erreur text
) ON COMMIT DROP;

DO $$
DECLARE
  p text; cur text; u uuid; r jsonb; t uuid;
  devises jsonb := '{"Djibouti":"DJF","France":"EUR","Belgique":"EUR","Allemagne":"EUR","Espagne":"EUR",
    "Sénégal":"XOF","Côte d''Ivoire":"XOF","Cameroun":"XAF","Maroc":"MAD","Tunisie":"TND",
    "Canada":"CAD","Suisse":"CHF","Royaume-Uni":"GBP","États-Unis":"USD","Éthiopie":"ETB",
    "Somalie":"SOS","Émirats arabes unis":"AED","Arabie saoudite":"SAR"}';
BEGIN
  FOREACH p IN ARRAY string_to_array(current_setting('rehearsal.pays'), '|') LOOP
    cur := COALESCE(devises->>p, 'USD');
    u := gen_random_uuid();
    BEGIN
      INSERT INTO auth.users (id, email) VALUES (u, 'signup-rehearsal-' || u || '@invalid.test');
      PERFORM set_config('request.jwt.claim.sub', u::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated',
        'email', 'signup-rehearsal@invalid.test', 'user_metadata', json_build_object('name', 'Répétition'))::text, true);
      PERFORM set_config('app.active_tenant_id', '', true);
      PERFORM set_config('role', 'authenticated', true);   -- appel comme l'application
      r := create_tenant_for_current_user(jsonb_build_object('name', 'Répétition ' || p, 'country', p, 'currency', cur));
      PERFORM set_config('role', 'postgres', true);
      t := (r->>'tenant_id')::uuid;
      INSERT INTO _signup_res
      SELECT p, cur, COALESCE((r->>'success')::boolean, false), t,
        (SELECT count(*) FROM chart_accounts WHERE tenant_id = t),
        (SELECT string_agg(code, ',' ORDER BY code) FROM journals WHERE tenant_id = t),
        (SELECT count(*) FROM fiscal_years WHERE tenant_id = t AND status = 'open'),
        (SELECT count(*) FROM company_settings WHERE tenant_id = t),
        (SELECT currency FROM company_settings WHERE tenant_id = t LIMIT 1),
        CASE WHEN COALESCE((r->>'success')::boolean, false) THEN NULL ELSE r::text END;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role', 'postgres', true);
      INSERT INTO _signup_res (pays, devise, succes, erreur) VALUES (p, cur, false, SQLERRM);
    END;
  END LOOP;
END $$;

\echo '=== Détail par pays'
SELECT pays, devise, succes, comptes, journaux, exercices_ouverts AS exo, parametres AS param, devise_societe, left(erreur, 120) AS erreur
FROM _signup_res ORDER BY succes, pays;
\echo '=== Synthèse'
SELECT count(*) AS pays_testes,
       count(*) FILTER (WHERE succes AND comptes > 0 AND journaux ~ 'AC' AND journaux ~ 'VT' AND journaux ~ 'BQ'
                          AND journaux ~ 'OD' AND journaux ~ 'AN' AND exercices_ouverts > 0 AND parametres = 1) AS utilisables,
       count(*) FILTER (WHERE NOT succes) AS echecs,
       count(DISTINCT comptes) AS tailles_de_plan_distinctes
FROM _signup_res;

ROLLBACK;
