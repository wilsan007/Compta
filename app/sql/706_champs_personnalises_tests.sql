-- ============================================================
-- 706_champs_personnalises_tests.sql — F.5 / PRJ-04 :
--   UN CHAMP DÉCLARÉ, UN TYPE TENU, ET AUCUNE FUITE ENTRE SOCIÉTÉS
--
--   T01  RLS FORCÉE sur les deux tables
--   T02  la clé (société, module, entité, clé) est UNIQUE (doublon refusé)
--   T03  un `select` sans options est refusé par le CHECK
--   T04  le TYPE de la valeur suit la définition : un champ `number` refuse du texte
--        (CUSTOM_FIELD_TYPE)
--   T05  un `select` refuse une valeur hors de ses options (CUSTOM_FIELD_OPTION)
--   T06  une valeur pour la définition d'une AUTRE société est refusée (clé composite)
--   T07  un champ DÉSACTIVÉ n'accueille plus de valeur (CUSTOM_FIELD_INACTIVE)
--   T08  supprimer une définition emporte ses valeurs (ON DELETE CASCADE)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '706', false);
DELETE FROM _audit_results WHERE file = '706';

DO $$
DECLARE v boolean;
BEGIN
  SELECT bool_and(relforcerowsecurity) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('custom_field_definitions', 'custom_field_values');
  PERFORM _rec('T01', 'RLS FORCÉE sur `custom_field_definitions` et `custom_field_values`',
    v IS TRUE, format('relforcerowsecurity = %s pour les deux', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée sur les deux tables', false, SQLERRM);
END $$;

-- T02 → T08 : un décor partagé (trois définitions, un enregistrement, une 2e société)
DO $$
DECLARE
  ta uuid; tb uuid; d_num uuid; d_sel uuid; d_off uuid; d_b uuid; rec uuid;
  ok boolean; n int;
BEGIN
  ta := _mk_tenant('F706A');
  rec := gen_random_uuid();

  INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type)
    VALUES (ta, 'projects', 'project', 'budget_ref', 'Référence budgétaire', 'number')
    RETURNING id INTO d_num;
  INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type, options)
    VALUES (ta, 'projects', 'project', 'phase', 'Phase', 'select', '["etude","chantier"]'::jsonb)
    RETURNING id INTO d_sel;
  INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type, is_active)
    VALUES (ta, 'projects', 'project', 'obsolete', 'Champ retiré', 'text', false)
    RETURNING id INTO d_off;

  -- T02 — la clé (société, module, entité, clé) est UNIQUE
  ok := false;
  BEGIN
    INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type)
      VALUES (ta, 'projects', 'project', 'budget_ref', 'Doublon', 'text');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23505'; END;
  PERFORM _rec('T02', 'refus : une clé de champ déjà déclarée pour ce couple (module, entité)', ok,
    format('unique_violation 23505 obtenue = %s', ok));

  -- T03 — un `select` sans options est refusé
  ok := false;
  BEGIN
    INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type, options)
      VALUES (ta, 'projects', 'project', 'sans_options', 'Select vide', 'select', '[]'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T03', 'refus : un champ `select` sans options (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T04 — le TYPE suit la définition : un nombre attend un nombre
  ok := false;
  BEGIN
    INSERT INTO custom_field_values (tenant_id, definition_id, record_id, value)
      VALUES (ta, d_num, rec, '"abc"'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CUSTOM_FIELD_TYPE%'; END;
  PERFORM _rec('T04', 'refus : du texte dans un champ `number` (CUSTOM_FIELD_TYPE)', ok,
    format('refus nommé CUSTOM_FIELD_TYPE = %s', ok));

  -- … et une valeur du BON type passe (sinon le refus ne prouverait rien)
  INSERT INTO custom_field_values (tenant_id, definition_id, record_id, value)
    VALUES (ta, d_num, rec, '12500'::jsonb);

  -- T05 — un `select` refuse une valeur hors options
  ok := false;
  BEGIN
    INSERT INTO custom_field_values (tenant_id, definition_id, record_id, value)
      VALUES (ta, d_sel, rec, '"hors_liste"'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CUSTOM_FIELD_OPTION%'; END;
  PERFORM _rec('T05', 'refus : une valeur hors des options d''un `select` (CUSTOM_FIELD_OPTION)', ok,
    format('refus nommé CUSTOM_FIELD_OPTION = %s', ok));

  -- T06 — une valeur ne peut pas viser la définition d'une AUTRE société.
  -- Deux gardes se répondent : le DÉCLENCHEUR (qui cherche la définition dans
  -- la société et lève CUSTOM_FIELD_UNKNOWN) passe avant la CLÉ COMPOSITE
  -- (23503). On exige que l'écriture soit REFUSÉE par l'un des deux, ET que la
  -- clé composite soit bien présente (le garde structurel, indépendant du
  -- déclencheur — c'est lui qui tient même si le déclencheur disparaissait).
  tb := _mk_tenant('F706B');
  INSERT INTO custom_field_definitions (tenant_id, module, entity, field_key, label, field_type)
    VALUES (tb, 'projects', 'project', 'ref_b', 'Champ B', 'text') RETURNING id INTO d_b;
  ok := false;
  BEGIN
    INSERT INTO custom_field_values (tenant_id, definition_id, record_id, value)
      VALUES (ta, d_b, rec, '"x"'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    ok := (SQLSTATE = '23503') OR SQLERRM LIKE '%CUSTOM_FIELD_UNKNOWN%';
  END;
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype = 'f' AND conrelid = 'public.custom_field_values'::regclass
     AND array_length(conkey, 1) = 2;
  PERFORM _rec('T06', 'refus : une valeur vers la définition d''une autre société — et la clé composite existe',
    ok AND n = 1,
    format('refus = %s ; clés composites sur custom_field_values = %s (attendu 1)', ok, n));

  -- T07 — un champ DÉSACTIVÉ n'accueille plus de valeur
  ok := false;
  BEGIN
    INSERT INTO custom_field_values (tenant_id, definition_id, record_id, value)
      VALUES (ta, d_off, rec, '"x"'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CUSTOM_FIELD_INACTIVE%'; END;
  PERFORM _rec('T07', 'refus : un champ désactivé n''accueille plus de valeur (CUSTOM_FIELD_INACTIVE)', ok,
    format('refus nommé CUSTOM_FIELD_INACTIVE = %s', ok));

  -- T08 — supprimer une définition emporte ses valeurs
  DELETE FROM custom_field_definitions WHERE id = d_num;
  SELECT count(*) INTO n FROM custom_field_values WHERE definition_id = d_num;
  PERFORM _rec('T08', 'supprimer une définition emporte ses valeurs (ON DELETE CASCADE)', n = 0,
    format('valeurs restantes = %s (attendu 0)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'unicité de la clé', false, SQLERRM);
  PERFORM _rec('T03', 'select sans options', false, SQLERRM);
  PERFORM _rec('T04', 'type de valeur', false, SQLERRM);
  PERFORM _rec('T05', 'valeur hors options', false, SQLERRM);
  PERFORM _rec('T06', 'valeur inter-société', false, SQLERRM);
  PERFORM _rec('T07', 'champ désactivé', false, SQLERRM);
  PERFORM _rec('T08', 'cascade', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 8 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '706';
  IF n <> 8 THEN
    RAISE EXCEPTION '[706] % verdict(s) enregistré(s) au lieu de 8 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('706');

