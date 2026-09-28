-- ============================================================
-- check_global_rows_writable.sql — aucune politique d'écriture sans société
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME (audit fonctionnel exécuté du 28/09/2026,
-- C1 et C2). Trois politiques d'écriture ne vérifiaient rien :
--   webhook_event_catalog_all  ALL USING (true)                     → un anonyme
--                                                                    modifiait le catalogue ;
--   payroll_legal_params_all   ALL USING (tenant_id IS NULL OR …)   → un anonyme
--                                                                    mettait le SMIC global à 1 € ;
--   tenant_*_banks             current_user_role() = 'admin'        → l'admin d'une
--                                                                    société réécrivait le référentiel.
-- Aucun contrôle ne les voyait : check_policy_duplicates compte les jumelles,
-- check_tenant_guard lit les fonctions, check_anon_grants lisait les droits
-- des FONCTIONS seulement.
--
-- LA RÈGLE. Toute politique d'INSERT, UPDATE, DELETE ou ALL de `public` qui
-- n'est pas réservée à `service_role` doit :
--   (a) mentionner `current_tenant_id()` ou `auth.uid()` — la société ou
--       l'utilisateur du jeton, pas un GUC que personne ne pose
--       (`app.tenant_id`) ni « la première société venue » (`LIMIT 1`) ;
--   (b) ne pas laisser passer `tenant_id IS NULL` — une ligne globale ne
--       s'écrit que par `service_role` ;
--   (c) ne pas être `true`.
-- Les tables filles sans `tenant_id` (lignes d'une grille, affectés d'une
-- tâche) passent par (a) : leur politique remonte au parent par une
-- sous-requête qui mentionne `current_tenant_id()`.
--
-- LE REGISTRE. Une ligne par politique fautive CONNUE, avec le défaut qui la
-- corrige. Une politique fautive hors registre fait échouer la CI ; une ligne
-- du registre qui ne correspond plus à rien aussi (le commit du correctif
-- retire la ligne). Même contrat que ci/expected_failures.sql.
-- ============================================================

CREATE TEMP TABLE global_rows_registre (table_name text, policy_name text, raison text);
-- Registre VIDE depuis la 271 (project_docs et analytic_distribution_lines,
-- défaut M12, en étaient les dernières lignes). Forme d'une ligne :
-- INSERT INTO global_rows_registre VALUES ('table', 'politique', 'défaut qui la corrige');

CREATE TEMP TABLE global_rows_verdicts AS
SELECT p.tablename, p.policyname, p.cmd, p.roles::text AS roles,
       coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') AS expr,
       (p.qual = 'true' OR p.with_check = 'true') AS vrai
FROM pg_policies p
WHERE p.schemaname = 'public'
  AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  AND p.roles <> ARRAY['service_role']::name[];

ALTER TABLE global_rows_verdicts ADD COLUMN motif text;
UPDATE global_rows_verdicts SET motif = CASE
  WHEN vrai THEN 'USING/CHECK (true)'
  WHEN expr ~* 'tenant_id\s+IS\s+NULL' THEN 'laisse passer tenant_id IS NULL'
  WHEN expr !~ 'current_tenant_id\(\)|auth\.uid\(\)' THEN 'ne mentionne ni current_tenant_id() ni auth.uid()'
END;
DELETE FROM global_rows_verdicts WHERE motif IS NULL;

DO $$
DECLARE
  v_corpus int; v_hors text; v_perimees text; v_n int; r record;
BEGIN
  SELECT count(*) INTO v_corpus FROM pg_policies
  WHERE schemaname = 'public' AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');
  IF v_corpus = 0 THEN
    RAISE EXCEPTION 'check_global_rows_writable : aucune politique d''écriture examinée — le contrôle ne vérifie rien';
  END IF;

  FOR r IN SELECT * FROM global_rows_verdicts ORDER BY tablename, policyname LOOP
    RAISE NOTICE '% %.% [%] : %',
      CASE WHEN EXISTS (SELECT 1 FROM global_rows_registre g
                        WHERE g.table_name = r.tablename AND g.policy_name = r.policyname)
           THEN '🟠' ELSE '❌' END,
      r.tablename, r.policyname, r.cmd, r.motif;
  END LOOP;

  SELECT count(*), string_agg(v.tablename || '.' || v.policyname || ' (' || v.motif || ')', E'\n  ')
    INTO v_n, v_hors
  FROM global_rows_verdicts v
  WHERE NOT EXISTS (SELECT 1 FROM global_rows_registre g
                    WHERE g.table_name = v.tablename AND g.policy_name = v.policyname);

  SELECT string_agg(g.table_name || '.' || g.policy_name, ', ') INTO v_perimees
  FROM global_rows_registre g
  WHERE NOT EXISTS (SELECT 1 FROM global_rows_verdicts v
                    WHERE v.tablename = g.table_name AND v.policyname = g.policy_name);

  RAISE NOTICE 'check_global_rows_writable : % politique(s) d''écriture examinée(s), % fautive(s), % inscrite(s) au registre',
    v_corpus, (SELECT count(*) FROM global_rows_verdicts), (SELECT count(*) FROM global_rows_registre);

  IF v_hors IS NOT NULL THEN
    RAISE EXCEPTION E'check_global_rows_writable : % politique(s) d''écriture sans garde de société :\n  %\n'
      '  Une ligne globale ne s''écrit que par service_role ; une ligne de société se garde par current_tenant_id().',
      v_n, v_hors;
  END IF;
  IF v_perimees IS NOT NULL THEN
    RAISE EXCEPTION E'check_global_rows_writable : registre périmé — retirer : %', v_perimees;
  END IF;
  RAISE NOTICE 'Politiques d''écriture : OK — aucune n''atteint une ligne globale ni une autre société';
END $$;

-- ============================================================
-- SECONDE PARTIE — la LECTURE des tables de société (M12)
--
-- `project_docs` lisait sur `tenant_id = (SELECT id FROM tenants LIMIT 1)` :
-- la première société de la table, pas celle de l'utilisateur ;
-- `analytic_distribution_lines` sur un GUC `app.tenant_id` que personne ne
-- pose. Aucun contrôle ne regardait les politiques de lecture — le plan
-- demandait d'étendre check_policy_duplicates ; la règle vit ici, à côté de
-- sa jumelle d'écriture.
--
-- LA RÈGLE. Sur une table qui porte `tenant_id`, toute politique de SELECT
-- (hors `service_role`) mentionne `current_tenant_id()` ou `auth.uid()`.
-- Aucun registre : la règle tient sans exception depuis la 271.
-- ============================================================
DO $$
DECLARE v_n int; v_liste text; v_corpus int;
BEGIN
  SELECT count(*) INTO v_corpus FROM pg_policies WHERE schemaname = 'public' AND cmd = 'SELECT';
  SELECT count(*), string_agg(p.tablename || '.' || p.policyname, E'\n  ' ORDER BY p.tablename)
    INTO v_n, v_liste
  FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.cmd = 'SELECT'
    AND p.roles <> ARRAY['service_role']::name[]
    AND EXISTS (SELECT 1 FROM information_schema.columns c
                WHERE c.table_schema = 'public' AND c.table_name = p.tablename AND c.column_name = 'tenant_id')
    AND coalesce(p.qual, '') !~ 'current_tenant_id\(\)|auth\.uid\(\)';
  RAISE NOTICE 'check_global_rows_writable (lecture) : % politique(s) de lecture examinée(s), % hors du contexte de société', v_corpus, v_n;
  IF v_n > 0 THEN
    RAISE EXCEPTION E'check_global_rows_writable : % politique(s) de lecture d''une table de société ne passent pas par current_tenant_id() :\n  %', v_n, v_liste;
  END IF;
END $$;
