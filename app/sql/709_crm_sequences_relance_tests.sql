-- ============================================================
-- 709_crm_sequences_relance_tests.sql — F.5 / CRM-01 :
--   UNE CADENCE DÉCRITE, DES RANGS QUI NE SE DISPUTENT PAS
--
--   T01  RLS FORCÉE sur les deux tables
--   T02  une séquence et son étape s'enregistrent (active par défaut)
--   T03  refus : deux séquences du MÊME nom dans la société (unicité)
--   T04  refus : deux étapes au MÊME rang dans la séquence (unicité)
--   T05  refus : un CANAL hors vocabulaire (CHECK)
--   T06  refus : un rang nul ou un délai négatif (CHECK)
--   T07  refus : une étape vers la séquence d'une AUTRE société (clé composite)
--   T08  supprimer une séquence emporte ses étapes (ON DELETE CASCADE)
--   T09  le visiteur (`anon`) n'a aucun droit
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '709', false);
DELETE FROM _audit_results WHERE file = '709';

DO $$
DECLARE v boolean;
BEGIN
  SELECT bool_and(relforcerowsecurity) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('crm_sequences', 'crm_sequence_steps');
  PERFORM _rec('T01', 'RLS FORCÉE sur `crm_sequences` et `crm_sequence_steps`',
    v IS TRUE, format('relforcerowsecurity = %s pour les deux', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée', false, SQLERRM);
END $$;

DO $$
DECLARE privs text;
BEGIN
  SELECT string_agg(DISTINCT privilege_type, ',') INTO privs
    FROM information_schema.role_table_grants
   WHERE grantee = 'anon' AND table_name IN ('crm_sequences', 'crm_sequence_steps');
  PERFORM _rec('T09', 'le visiteur (`anon`) n''a AUCUN droit sur les séquences',
    privs IS NULL, format('droits d''anon = %s', COALESCE(privs, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T09', 'anon sans droits', false, SQLERRM);
END $$;

-- T02 → T08 : un décor partagé (une séquence, son étape, une seconde société)
DO $$
DECLARE
  ta uuid; tb uuid; seq uuid; seqb uuid; n int; ok boolean; v_active boolean;
BEGIN
  ta := _mk_tenant('F709A');
  INSERT INTO crm_sequences (tenant_id, name, description)
    VALUES (ta, 'Relance devis', 'Trois touches après un devis') RETURNING id, is_active INTO seq, v_active;
  INSERT INTO crm_sequence_steps (tenant_id, sequence_id, step_order, delay_days, channel, subject)
    VALUES (ta, seq, 1, 0, 'email', 'Votre devis');

  -- T02 — la séquence naît ACTIVE, l'étape s'enregistre
  SELECT count(*) INTO n FROM crm_sequence_steps WHERE sequence_id = seq;
  PERFORM _rec('T02', 'une séquence et son étape s''enregistrent (séquence active par défaut)',
    v_active IS TRUE AND n = 1, format('active=%s étapes=%s', v_active, n));

  -- T03 — deux séquences du même nom
  ok := false;
  BEGIN
    INSERT INTO crm_sequences (tenant_id, name) VALUES (ta, 'Relance devis');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23505'; END;
  PERFORM _rec('T03', 'refus : deux séquences du MÊME nom dans la société (unicité)', ok,
    format('unique_violation 23505 obtenue = %s', ok));

  -- T04 — deux étapes au même rang
  ok := false;
  BEGIN
    INSERT INTO crm_sequence_steps (tenant_id, sequence_id, step_order, delay_days, channel)
      VALUES (ta, seq, 1, 3, 'call');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23505'; END;
  PERFORM _rec('T04', 'refus : deux étapes au MÊME rang dans la séquence (unicité)', ok,
    format('unique_violation 23505 obtenue = %s', ok));

  -- T05 — canal hors vocabulaire
  ok := false;
  BEGIN
    INSERT INTO crm_sequence_steps (tenant_id, sequence_id, step_order, delay_days, channel)
      VALUES (ta, seq, 2, 3, 'pigeon_voyageur');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T05', 'refus : un CANAL hors vocabulaire (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T06 — rang nul / délai négatif
  ok := false;
  BEGIN
    INSERT INTO crm_sequence_steps (tenant_id, sequence_id, step_order, delay_days, channel)
      VALUES (ta, seq, 0, -1, 'task');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T06', 'refus : un rang nul ou un délai négatif (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T07 — étape vers la séquence d'une AUTRE société
  tb := _mk_tenant('F709B');
  INSERT INTO crm_sequences (tenant_id, name) VALUES (tb, 'Séquence B') RETURNING id INTO seqb;
  ok := false;
  BEGIN
    INSERT INTO crm_sequence_steps (tenant_id, sequence_id, step_order, delay_days, channel)
      VALUES (ta, seqb, 1, 0, 'email');   -- société A, séquence de B
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23503'; END;
  PERFORM _rec('T07', 'refus : une étape vers la séquence d''une AUTRE société (clé composite, ISO-02)', ok,
    format('foreign_key_violation 23503 obtenue = %s', ok));

  -- T08 — supprimer la séquence emporte ses étapes
  DELETE FROM crm_sequences WHERE id = seq;
  SELECT count(*) INTO n FROM crm_sequence_steps WHERE sequence_id = seq;
  PERFORM _rec('T08', 'supprimer une séquence emporte ses étapes (ON DELETE CASCADE)', n = 0,
    format('étapes restantes = %s (attendu 0)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'séquence et étape enregistrées', false, SQLERRM);
  PERFORM _rec('T03', 'nom de séquence unique', false, SQLERRM);
  PERFORM _rec('T04', 'rang d''étape unique', false, SQLERRM);
  PERFORM _rec('T05', 'canal contraint', false, SQLERRM);
  PERFORM _rec('T06', 'rang et délai contraints', false, SQLERRM);
  PERFORM _rec('T07', 'étape inter-société', false, SQLERRM);
  PERFORM _rec('T08', 'cascade', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 9 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '709';
  IF n <> 9 THEN
    RAISE EXCEPTION '[709] % verdict(s) enregistré(s) au lieu de 9 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('709');

