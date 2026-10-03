-- ============================================================
-- 274_accounting_master_data_tests.sql — vague X2 / C14 : données de base comptables
--
-- MESURÉ AVANT (W03, chemin de l'écran) : `section_type` absente, création de
-- section refusée (PGRST204).
--
--   T01 une section se crée avec son type (défaut `section`) ; un type inconnu
--       est refusé
--   T02 une ligne d'écriture imputée sur une section « total » est refusée ;
--       sur une section ordinaire, acceptée
--   T03 une ventilation sur une section « total » est refusée
--   T04 une section déjà imputée ne devient pas un total
--   T05 un lecteur n'écrit aucune des neuf tables de données de base
--       comptables ; un comptable, si (M8, masqué jusqu'à ce que l'écran puisse
--       créer un compte de tiers)
--
-- T01–T05 sont ROUGES avant la 274.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '274', false);
DELETE FROM _audit_results WHERE file = '274';

DO $$
DECLARE t uuid; s_ok uuid; s_tot uuid; ty text; bad text; e uuid; err_tot text; err_ok text;
  err_dist text; l uuid; err_conv text; n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'analytic_sections' AND column_name = 'section_type';
  IF n = 0 THEN
    PERFORM _rec('T01', 'une section se crée avec son type ; un type inconnu est refusé', false, 'colonne section_type absente');
    PERFORM _rec('T02', 'imputation d''une ligne sur une section « total » refusée, sur une section acceptée', false, 'colonne section_type absente');
    PERFORM _rec('T03', 'ventilation sur une section « total » refusée', false, 'colonne section_type absente');
    PERFORM _rec('T04', 'une section déjà imputée ne devient pas un total', false, 'colonne section_type absente');
    RETURN;
  END IF;

  t := _mk_tenant('X2C14S');
  PERFORM _as_user();
  INSERT INTO analytic_sections (tenant_id, code, name) VALUES (t, 'ATL', 'Atelier') RETURNING id INTO s_ok;
  EXECUTE $q$INSERT INTO analytic_sections (tenant_id, code, name, section_type) VALUES ($1, 'PROD', 'Production (total)', 'total') RETURNING id$q$
    INTO s_tot USING t;
  EXECUTE 'SELECT section_type FROM analytic_sections WHERE id = $1' INTO ty USING s_ok;
  BEGIN
    EXECUTE $q$INSERT INTO analytic_sections (tenant_id, code, name, section_type) VALUES ($1, 'X', 'X', 'normal')$q$ USING t;
    bad := 'ACCEPTÉ';
  EXCEPTION WHEN check_violation THEN bad := 'refusé';
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'une section se crée avec son type (défaut section) ; un type inconnu est refusé',
    ty = 'section' AND s_tot IS NOT NULL AND bad = 'refusé', format('défaut=%s total=%s inconnu=%s', ty, s_tot IS NOT NULL, bad));

  e := _entry(t, 'ANA-1', '2026-09-15', '[{"a":"606100","d":100},{"a":"512000","c":100}]', false);
  PERFORM _as_user();
  BEGIN
    UPDATE journal_lines SET analytic_section_id = s_tot WHERE journal_id = e AND account_code = '606100';
    err_tot := 'ACCEPTÉ';
  EXCEPTION WHEN check_violation THEN err_tot := SQLERRM;
  END;
  BEGIN
    UPDATE journal_lines SET analytic_section_id = s_ok WHERE journal_id = e AND account_code = '606100' RETURNING id INTO l;
    err_ok := 'OK';
  EXCEPTION WHEN OTHERS THEN err_ok := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T02', 'imputation d''une ligne sur une section « total » refusée, sur une section acceptée',
    err_tot ~ 'PROD' AND err_ok = 'OK', format('total : %s | section : %s', err_tot, err_ok));

  PERFORM _as_user();
  BEGIN
    INSERT INTO analytic_distribution_lines (tenant_id, journal_line_id, section_id, percentage, amount) VALUES (t, l, s_tot, 100, 100);
    err_dist := 'ACCEPTÉ';
  EXCEPTION WHEN check_violation THEN err_dist := SQLERRM;
  END;
  BEGIN
    EXECUTE $q$UPDATE analytic_sections SET section_type = 'total' WHERE id = $1$q$ USING s_ok;
    err_conv := 'ACCEPTÉ';
  EXCEPTION WHEN check_violation THEN err_conv := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'ventilation sur une section « total » refusée', err_dist ~ 'PROD', err_dist);
  PERFORM _rec('T04', 'une section déjà imputée ne devient pas un total', err_conv ~ 'ATL', err_conv);
END $$;

-- T05 — le lecteur et les données de base comptables
DO $$
DECLARE t uuid; lec uuid; cpt uuid; ecrit_lec text := ''; ecrit_cpt text := ''; r record; n int;
BEGIN
  t := _mk_tenant('X2M8');
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), 'x2m8-lec@audit.test') RETURNING id INTO lec;
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), 'x2m8-cpt@audit.test') RETURNING id INTO cpt;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status) VALUES
    (t, lec, 'x2m8-lec@audit.test', 'Lecteur', 'viewer', 'active'),
    (t, cpt, 'x2m8-cpt@audit.test', 'Comptable', 'accountant', 'active');
  FOR r IN SELECT * FROM (VALUES
      ('third_party_accounts',  $q$INSERT INTO third_party_accounts (tenant_id, code, name, type) VALUES (%L, 'T'||%L, 'Tiers', 'customer')$q$),
      -- L'IBAN est VALIDE (clé 89). Il ne l'était pas : le test posait
      -- `FR76300060000112345678901`, dont la clé de contrôle est fausse, et le
      -- garde-fou de la 324 le refusait — T05 échouait donc sur le jeu de
      -- données, pas sur le droit qu'il prétendait vérifier. La suite 105 et
      -- la 324 portent la même valeur, qui est la bonne : FR76 …0189.
      ('partner_bank_accounts', $q$INSERT INTO partner_bank_accounts (tenant_id, partner_type, partner_id, account_number) VALUES (%L, 'supplier', gen_random_uuid(), 'FR7630006000011234567890189')$q$),
      ('payment_terms',         $q$INSERT INTO payment_terms (tenant_id, code, name, type) VALUES (%L, 'PT'||%L, '30 jours', 'fixed')$q$),
      ('analytic_sections',     $q$INSERT INTO analytic_sections (tenant_id, code, name) VALUES (%L, 'S'||%L, 'Section')$q$),
      ('analytic_plans',        $q$INSERT INTO analytic_plans (tenant_id, code, name) VALUES (%L, 'P'||%L, 'Plan')$q$),
      ('entry_templates',       $q$INSERT INTO entry_templates (tenant_id, name) VALUES (%L, 'Modèle '||%L)$q$)
    ) v(tb, q)
  LOOP
    PERFORM set_config('request.jwt.claim.sub', lec::text, false);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', lec, 'role', 'authenticated')::text, false);
    PERFORM _as_user();
    BEGIN
      EXECUTE format(r.q, t, 'L');
      ecrit_lec := ecrit_lec || r.tb || ' ';
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN NULL;
      WHEN OTHERS THEN ecrit_lec := ecrit_lec || r.tb || '(autre: ' || SQLERRM || ') ';
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub', cpt::text, false);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', cpt, 'role', 'authenticated')::text, false);
    PERFORM _as_user();
    BEGIN
      EXECUTE format(r.q, t, 'C');
    EXCEPTION WHEN OTHERS THEN ecrit_cpt := ecrit_cpt || r.tb || '(' || SQLERRM || ') ';
    END;
    EXECUTE 'RESET ROLE';
  END LOOP;
  SELECT count(*) INTO n FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
  WHERE c.relname IN ('third_party_accounts','partner_bank_accounts','tier_ribs','payment_terms','reminder_levels',
                      'analytic_sections','analytic_plans','analytic_distribution_lines','entry_templates')
    AND p.polcmd IN ('a','w','d','*') AND p.polpermissive
    AND coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') NOT LIKE '%can_perform%';
  PERFORM _rec('T05', 'un lecteur n''écrit aucune donnée de base comptable ; un comptable si ; 0 politique d''écriture sans can_perform',
    ecrit_lec = '' AND ecrit_cpt = '' AND n = 0,
    format('écrites par le lecteur : %s | refusées au comptable : %s | politiques non gardées : %s', nullif(ecrit_lec, ''), nullif(ecrit_cpt, ''), n));
END $$;

SELECT _audit_assert('274');
