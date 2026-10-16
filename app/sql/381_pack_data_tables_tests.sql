-- ============================================================
-- 381_pack_data_tables_tests.sql — LOT 1-A : les tables de données du pack
--
--   T01  les 10 tables du pack existent ;
--   T02  chacune est sous RLS avec UNE politique de lecture, et un utilisateur
--        connecté ne peut PAS y écrire (aucune politique d'écriture) ;
--   T03  les CHECK des énumérations tiennent (source_id, kind, sign…) ;
--   T04  pack_statement_lines exige son gabarit (clé étrangère) ;
--   T05  source_id ajouté aux 7 tables existantes ; pack_code + clé COMPOSITE
--        (tenant_id, pack_code) sur les 3 grilles/paramètres ;
--   T06  rejouable : chaque table porte UNE politique (pas de doublon).
--
-- Vu ROUGE avant la 381 : T01 (tables absentes), T02, T03, T04, T05 (colonnes
-- absentes). T06 était sans objet.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '381', false);
DELETE FROM _audit_results WHERE file = '381';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 10 tables existent
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_manque text;
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_manque FROM (
    SELECT t FROM unnest(ARRAY[
      'pack_sources','pack_account_roles','pack_journal_roles','pack_capabilities',
      'pack_holidays','pack_legal_identifiers','pack_document_rules',
      'pack_statement_templates','pack_statement_lines','pack_other_taxes']) AS t
    WHERE NOT EXISTS (SELECT 1 FROM information_schema.tables
                       WHERE table_schema = 'public' AND table_name = t)
  ) m;
  PERFORM _rec('T01', 'les 10 tables de données du pack existent',
    v_manque IS NULL, COALESCE('absentes : ' || v_manque, 'les 10 tables sont présentes'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 10 tables de données du pack existent', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — RLS + une politique de lecture ; l'écriture est refusée
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_sans_rls int; v_sans_pol int; v_ecrit text;
BEGIN
  SELECT count(*) INTO v_sans_rls FROM pg_class
   WHERE relname LIKE 'pack\_%' AND relkind = 'r' AND NOT relrowsecurity;
  SELECT count(*) INTO v_sans_pol FROM pg_class c
   WHERE c.relname LIKE 'pack\_%' AND c.relkind = 'r'
     AND NOT EXISTS (SELECT 1 FROM pg_policies p
                      WHERE p.tablename = c.relname AND p.cmd = 'SELECT');

  -- Un utilisateur connecté (authenticated) tente d'écrire : aucune politique
  -- d'écriture n'existe, donc c'est refusé.
  PERFORM _as_user();
  v_ecrit := 'accepté';
  BEGIN
    INSERT INTO pack_capabilities (pack_code, capability) VALUES ('FR', 'zz.test');
  EXCEPTION WHEN OTHERS THEN v_ecrit := 'refusé';
  END;
  EXECUTE 'RESET ROLE';

  PERFORM _rec('T02', 'chaque table du pack est sous RLS, lisible, et NON écrivable par un connecté',
    v_sans_rls = 0 AND v_sans_pol = 0 AND v_ecrit = 'refusé',
    format('sans RLS=%s, sans politique SELECT=%s, écriture connectée=%s', v_sans_rls, v_sans_pol, v_ecrit));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'chaque table du pack est sous RLS, lisible, et NON écrivable par un connecté', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les CHECK des énumérations tiennent
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a boolean := false; b boolean := false; c boolean := false;
BEGIN
  BEGIN
    INSERT INTO pack_sources (pack_code, source_id, title) VALUES ('FR', 'bad id!', 'x');
  EXCEPTION WHEN check_violation THEN a := true; END;
  BEGIN
    INSERT INTO pack_statement_templates (pack_code, template_code, name, kind)
      VALUES ('FR', 'x', 'x', 'n_importe_quoi');
  EXCEPTION WHEN check_violation THEN b := true; END;
  BEGIN
    INSERT INTO pack_other_taxes (pack_code, tax_code, kind) VALUES ('FR', 'x', 'n_importe_quoi');
  EXCEPTION WHEN check_violation THEN c := true; END;

  DELETE FROM pack_sources WHERE pack_code = 'FR' AND source_id = 'bad id!';
  DELETE FROM pack_statement_templates WHERE pack_code = 'FR' AND template_code = 'x';
  DELETE FROM pack_other_taxes WHERE pack_code = 'FR' AND tax_code = 'x';

  PERFORM _rec('T03', 'les CHECK d''énumération tiennent (source_id, kind de gabarit, kind de taxe)',
    a AND b AND c, format('source_id=%s, kind gabarit=%s, kind taxe=%s', a, b, c));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les CHECK d''énumération tiennent (source_id, kind de gabarit, kind de taxe)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — une ligne d'état exige son gabarit
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE refuse boolean := false;
BEGIN
  BEGIN
    INSERT INTO pack_statement_lines (pack_code, template_code, line_code, label)
      VALUES ('FR', 'gabarit_inexistant', 'L1', 'x');
  EXCEPTION WHEN foreign_key_violation THEN refuse := true; END;
  DELETE FROM pack_statement_lines WHERE pack_code = 'FR' AND template_code = 'gabarit_inexistant';

  PERFORM _rec('T04', 'pack_statement_lines exige son gabarit (clé étrangère vers pack_statement_templates)',
    refuse, format('ligne vers un gabarit inexistant refusée=%s', refuse));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'pack_statement_lines exige son gabarit (clé étrangère vers pack_statement_templates)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — colonnes ajoutées aux tables existantes, et clés composites
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_src text; v_pack text; v_fk int;
BEGIN
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_src FROM unnest(ARRAY[
    'tax_rates','chart_account_templates','payroll_tax_grids','payroll_tax_grid_lines',
    'payroll_legal_parameters','corporate_tax_grids','corporate_tax_grid_lines']) AS t
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = t AND column_name = 'source_id');

  SELECT string_agg(t, ', ' ORDER BY t) INTO v_pack FROM unnest(ARRAY[
    'payroll_tax_grids','payroll_legal_parameters','corporate_tax_grids']) AS t
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = t AND column_name = 'pack_code');

  SELECT count(*) INTO v_fk FROM pg_constraint
   WHERE contype = 'f' AND array_length(conkey, 1) = 2
     AND conrelid::regclass::text IN ('payroll_tax_grids','payroll_legal_parameters','corporate_tax_grids')
     AND pg_get_constraintdef(oid) LIKE '%legislation_packs%';

  PERFORM _rec('T05', 'source_id sur les 7 tables ; pack_code + clé composite (tenant_id, pack_code) sur les 3 grilles',
    v_src IS NULL AND v_pack IS NULL AND v_fk = 3,
    format('source_id manquant=%s ; pack_code manquant=%s ; clés composites=%s (3 attendues)',
           COALESCE(v_src, 'aucun'), COALESCE(v_pack, 'aucun'), v_fk));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'source_id sur les 7 tables ; pack_code + clé composite (tenant_id, pack_code) sur les 3 grilles', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — rejouable : une seule politique de lecture par table
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_pol int; v_dup int;
BEGIN
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE tablename LIKE 'pack\_%' AND policyname LIKE 'select\_%';
  SELECT count(*) INTO v_dup FROM (
    SELECT tablename FROM pg_policies WHERE tablename LIKE 'pack\_%'
    GROUP BY tablename HAVING count(*) <> 1) d;

  PERFORM _rec('T06', 'rejouable : une politique de lecture par table, aucun doublon',
    v_pol = 10 AND v_dup = 0,
    format('politiques select_*=%s (10 attendues) ; tables à doublon=%s', v_pol, v_dup));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'rejouable : une politique de lecture par table, aucun doublon', false, SQLERRM);
END $$;

SELECT _audit_assert('381');
