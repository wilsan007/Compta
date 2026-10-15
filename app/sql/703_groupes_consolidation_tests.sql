-- ============================================================
-- 703_groupes_consolidation_tests.sql — F.4 / GRP-03 :
--   LA CONSOLIDATION PONDÈRE, EXCLUT, BORNE, ET NE SE LIT PAS DE DEHORS
--
--   T01  pondération : A (full) 100 au débit de 601 + B (proportional 60 %) 200
--        → le compte 601 ressort à 220 (100 + 200 × 0,6)
--   T02  exclusion : un membre `none` (compte 623, 999) n'entre PAS dans l'agrégat
--   T03  bornage : une écriture HORS période (compte 615, 1000) n'entre pas
--   T04  flux intra-groupe : publiés pour élimination (1 flux, 500), pas éliminés
--   T05  refus : une société HORS du groupe (GROUP_NOT_MEMBER)
--   T06  refus : un membre NON administrateur (GROUP_FORBIDDEN)
--
-- NB : la suite s'exécute en superutilisateur (psql de la CI) ; les gardes
-- mesurées (T05/T06) sont celles de la FONCTION, pas la RLS.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '703', false);
DELETE FROM _audit_results WHERE file = '703';

-- Pose le contexte d'une société membre (son admin), comme PostgREST le ferait.
CREATE OR REPLACE FUNCTION _l703_act_as(p_tenant uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u uuid;
BEGIN
  PERFORM set_config('app.active_tenant_id', p_tenant::text, false);
  SELECT auth_id INTO u FROM tenant_users
   WHERE tenant_id = p_tenant AND role = 'admin' ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
END $$;

-- T01 → T04 : un décor partagé (A full, B proportional 60 %, C none, + hors période)
DO $$
DECLARE
  ta uuid; tb uuid; tc uuid; ga uuid; r jsonb; v jsonb; v_601 numeric;
BEGIN
  -- ── décor ────────────────────────────────────────────────
  ta := _mk_tenant('F703A');
  PERFORM _entry(ta, 'A-1', DATE '2026-06-15', '[{"a":"601000","d":100},{"a":"401000","c":100}]'::jsonb);
  r  := create_group('Groupe F703');
  ga := (r ->> 'group_id')::uuid;

  tb := _mk_tenant('F703B');
  PERFORM _l703_act_as(ta);
  PERFORM add_group_member(ga, tb, 'subsidiary', 60, 'proportional');
  PERFORM _l703_act_as(tb);
  PERFORM _entry(tb, 'B-1',  DATE '2026-06-20', '[{"a":"601000","d":200},{"a":"401000","c":200}]'::jsonb);
  PERFORM _entry(tb, 'B-HS', DATE '2026-09-30', '[{"a":"615000","d":1000},{"a":"401000","c":1000}]'::jsonb);  -- hors période

  tc := _mk_tenant('F703C');
  PERFORM _l703_act_as(ta);
  PERFORM add_group_member(ga, tc, 'subsidiary', 100, 'none');
  PERFORM _l703_act_as(tc);
  PERFORM _entry(tc, 'C-1', DATE '2026-06-21', '[{"a":"623000","d":999},{"a":"401000","c":999}]'::jsonb);

  PERFORM _l703_act_as(ta);
  PERFORM record_intra_group_transaction(ga, tb, 'sale', 500, DATE '2026-06-25', 'FLUX-1');

  -- ── la consolidation, vue par A (admin d'une société membre) ──
  v := group_consolidated_balance(ga, DATE '2026-06-01', DATE '2026-06-30');
  SELECT (e ->> 'debit')::numeric INTO v_601
    FROM jsonb_array_elements(v -> 'accounts') e WHERE e ->> 'account' = '601000';

  -- T01 — la pondération
  PERFORM _rec('T01', 'consolidation : A (full 100) + B (proportional 60 % × 200) → compte 601 à 220',
    v_601 = 220,
    format('compte 601000 débit = %s (attendu 220)', COALESCE(v_601::text, 'absent')));

  -- T02 — un membre `none` est exclu (son compte 623 n'apparaît pas)
  PERFORM _rec('T02', 'exclusion : un membre `none` n''entre pas dans l''agrégat (compte 623 absent)',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'accounts') e WHERE e ->> 'account' = '623000'),
    format('compte 623000 présent = %s',
      EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'accounts') e WHERE e ->> 'account' = '623000')));

  -- T03 — le bornage de période (l'écriture de septembre n'entre pas)
  PERFORM _rec('T03', 'bornage : une écriture HORS période n''entre pas (compte 615 absent)',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'accounts') e WHERE e ->> 'account' = '615000'),
    format('compte 615000 présent = %s',
      EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'accounts') e WHERE e ->> 'account' = '615000')));

  -- T04 — les flux intra-groupe sont publiés, pas éliminés
  PERFORM _rec('T04', 'flux intra-groupe : publiés pour élimination (1 flux, 500), pas éliminés',
    (v -> 'intra_group' ->> 'count')::int = 1 AND (v -> 'intra_group' ->> 'total_amount')::numeric = 500,
    format('count=%s total=%s', v -> 'intra_group' ->> 'count', v -> 'intra_group' ->> 'total_amount'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'consolidation pondérée', false, SQLERRM);
  PERFORM _rec('T02', 'exclusion d''un membre none', false, SQLERRM);
  PERFORM _rec('T03', 'bornage de période', false, SQLERRM);
  PERFORM _rec('T04', 'flux intra-groupe publiés', false, SQLERRM);
END $$;

-- T05 — refus : une société HORS du groupe ne consolide rien
DO $$
DECLARE tg uuid := _mk_tenant('F703T05GRP'); r jsonb; gid uuid; t_out uuid; ok boolean := false;
BEGIN
  r := create_group('Groupe T05'); gid := (r ->> 'group_id')::uuid;
  t_out := _mk_tenant('F703T05HORS');   -- cette société n'est PAS membre
  PERFORM _l703_act_as(t_out);
  BEGIN
    PERFORM group_consolidated_balance(gid, DATE '2026-06-01', DATE '2026-06-30');
    PERFORM _rec('T05', 'refus : une société hors du groupe ne peut pas consolider', false,
      'consolidée sans appartenir au groupe');
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05', 'refus : une société hors du groupe ne peut pas consolider',
      SQLERRM LIKE '%GROUP_NOT_MEMBER%', SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'refus d''une société hors du groupe', false, SQLERRM);
END $$;

-- T06 — refus : un membre NON administrateur
DO $$
DECLARE tg uuid := _mk_tenant('F703T06'); r jsonb; gid uuid; v uuid;
BEGIN
  r := create_group('Groupe T06'); gid := (r ->> 'group_id')::uuid;
  v := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v, 'viewer-' || v || '@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
  VALUES (tg, v, 'viewer@audit.test', 'Viewer', 'viewer', 'active');
  PERFORM set_config('app.active_tenant_id', tg::text, false);
  PERFORM set_config('request.jwt.claim.sub', v::text, false);
  BEGIN
    PERFORM group_consolidated_balance(gid, DATE '2026-06-01', DATE '2026-06-30');
    PERFORM _rec('T06', 'refus : seul un administrateur d''une société membre consolide', false,
      'consolidée par un non-administrateur');
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'refus : seul un administrateur d''une société membre consolide',
      SQLERRM LIKE '%GROUP_FORBIDDEN%', SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'refus d''un non-administrateur', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 6 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '703';
  IF n <> 6 THEN
    RAISE EXCEPTION '[703] % verdict(s) enregistré(s) au lieu de 6 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('703');

