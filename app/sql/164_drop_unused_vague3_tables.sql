-- ============================================================
-- 164_drop_unused_vague3_tables.sql
--
-- LOT7-02 (doc/audit/SUIVI-CAHIER-CORRECTIF.md, bloc E2) — arbitrage du 18/09 :
-- supprimer les tables de `127_vague3_remaining.sql` qu'aucun code n'utilise.
--
-- La 127 crée 27 tables. Cinq sont utilisées et ne sont PAS touchées ici :
--   audit_log, document_templates, electronic_signatures, leave_requests
--     — déjà définies dans 00_schema_dump.sql ; la 127 en donne une seconde
--       définition, neutralisée par le IF NOT EXISTS depuis que les migrations
--       sont rejouées en ordre numérique. C'est une divergence latente, pas une
--       table morte : la supprimer casserait l'application.
--   time_entries
--     — cible des 16 fonctions de `queries/projectManagementSprint1.ts`, encore
--       sans écran. Son sort dépend de la décision « brancher ou supprimer » en
--       cours sur ce sprint ; elle est volontairement conservée.
--
-- Les 22 autres ne sont nommées NULLE PART : ni dans `src/`, ni dans les
-- fonctions edge. Vérifié le 18/09.
--
-- Garde-fou : une table n'est supprimée que si elle est VIDE au moment du rejeu,
-- et qu'aucune table hors de cette liste ne la référence. Sur une base qui porte
-- des données, la migration les conserve et le dit, plutôt que de détruire.
-- Elle est donc rejouable et sans effet sur une base déjà nettoyée.
-- ============================================================

DO $$
DECLARE
  -- Ordre enfant → parent : les clés étrangères internes à la liste
  -- (crm_sequence_steps → crm_sequences, custom_field_values →
  -- custom_field_definitions, group_members + intra_group_transactions →
  -- group_entities, job_applications → job_postings) imposent cet ordre.
  a_supprimer text[] := ARRAY[
    'crm_sequence_steps', 'crm_sequences', 'crm_scoring_rules',
    'custom_field_values', 'custom_field_definitions',
    'group_members', 'intra_group_transactions', 'group_entities',
    'job_applications', 'job_postings',
    'business_alert_rules', 'business_connectors',
    'document_attachments', 'e_invoicing_logs', 'employee_self_service',
    'migration_templates', 'notification_center', 'report_definitions',
    'resource_capacities', 'signup_flows', 'subscriptions',
    'tenant_fiscal_settings'
  ];
  t text;
  n bigint;
  dependantes text;
  supprimees int := 0;
  conservees text[] := '{}';
BEGIN
  FOREACH t IN ARRAY a_supprimer LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      CONTINUE;  -- déjà supprimée : migration rejouable
    END IF;

    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    IF n > 0 THEN
      conservees := conservees || format('%s (%s ligne(s))', t, n);
      CONTINUE;
    END IF;

    -- Une référence entrante encore debout signifie qu'une table conservée en
    -- dépend : on ne force pas, on signale.
    SELECT string_agg(DISTINCT k.conrelid::regclass::text, ', ')
      INTO dependantes
      FROM pg_constraint k
     WHERE k.contype = 'f'
       AND k.confrelid = ('public.' || t)::regclass
       AND k.conrelid <> ('public.' || t)::regclass;

    IF dependantes IS NOT NULL THEN
      conservees := conservees || format('%s (référencée par %s)', t, dependantes);
      CONTINUE;
    END IF;

    EXECUTE format('DROP TABLE public.%I', t);
    supprimees := supprimees + 1;
  END LOOP;

  RAISE NOTICE 'LOT7-02 : % table(s) vide(s) supprimée(s) sur %', supprimees, array_length(a_supprimer, 1);
  IF array_length(conservees, 1) > 0 THEN
    RAISE NOTICE 'LOT7-02 : conservées car non vides ou référencées : %', array_to_string(conservees, ' ; ');
  END IF;
END $$;
