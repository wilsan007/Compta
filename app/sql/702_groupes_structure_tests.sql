-- ============================================================
-- 702_groupes_structure_tests.sql — F.4 / GRP-01 + GRP-02 :
--   UN GROUPE RELIE PLUSIEURS SOCIÉTÉS, ET LE CLOISONNEMENT TIENT
--
--   T01  création : la société créatrice devient membre « parent »
--   T02  refus : un NON-admin ne crée pas (GROUP_FORBIDDEN)
--   T03  ajout d'un membre : la structure porte les 2 sociétés et leurs paramètres
--   T04  ISOLATION : une société HORS du groupe ne le voit pas
--   T05  refus : on n'ajoute pas à un groupe dont on n'est pas membre
--   T06  flux intra-groupe : un flux relie deux sociétés membres (confirmed) ;
--        un flux vers soi-même est refusé
--   T07  refus : un flux vers une société hors du groupe est refusé
--   T08  retrait : retirer le dernier membre supprime le groupe
--
-- NB : la suite s'exécute en superutilisateur (psql de la CI). Les gardes
-- mesurées ici sont celles des FONCTIONS (`my_group_ids()`, `group_structure()`,
-- les RPC) — qui filtrent par `current_tenant_id()` — et non la RLS, que le
-- superutilisateur contourne. C'est le bon niveau : c'est le code de la base qui
-- décide, pas le privilège de qui l'appelle.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '702', false);
DELETE FROM _audit_results WHERE file = '702';

-- Pose le contexte d'une société membre (son admin), comme PostgREST le ferait.
CREATE OR REPLACE FUNCTION _l702_act_as(p_tenant uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u uuid;
BEGIN
  PERFORM set_config('app.active_tenant_id', p_tenant::text, false);
  SELECT auth_id INTO u FROM tenant_users
   WHERE tenant_id = p_tenant AND role = 'admin' ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
END $$;

-- T01 — création : le groupe naît avec sa société comme membre « parent »
DO $$
DECLARE t uuid := _mk_tenant('F702T01'); r jsonb; n int; mt text;
BEGIN
  r := create_group('Groupe T01');
  SELECT count(*) INTO n FROM group_members WHERE group_id = (r ->> 'group_id')::uuid;
  SELECT member_type INTO mt FROM group_members
   WHERE group_id = (r ->> 'group_id')::uuid AND tenant_id = t;
  PERFORM _rec('T01', 'création : la société créatrice devient membre « parent » du groupe',
    (r ->> 'success')::boolean AND n = 1 AND mt = 'parent',
    format('success=%s membres=%s type=%s', r ->> 'success', n, mt));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'création du groupe et premier membre', false, SQLERRM);
END $$;

-- T02 — refus : un non-admin ne crée pas
DO $$
DECLARE t uuid := _mk_tenant('F702T02'); v2 uuid := gen_random_uuid(); r jsonb;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v2, 'viewer-' || v2 || '@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
  VALUES (t, v2, 'viewer@audit.test', 'Viewer', 'viewer', 'active');
  PERFORM set_config('request.jwt.claim.sub', v2::text, false);
  BEGIN
    PERFORM create_group('Interdit');
    PERFORM _rec('T02', 'un non-admin ne peut pas créer de groupe', false, 'créé alors que l''appelant n''est pas admin');
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'un non-admin ne peut pas créer de groupe',
      SQLERRM LIKE '%GROUP_FORBIDDEN%', SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'un non-admin ne peut pas créer de groupe', false, SQLERRM);
END $$;

-- T03 → T08 : un décor partagé (A crée le groupe, B rejoint, C reste dehors)
DO $$
DECLARE
  ta uuid; tb uuid; tc uuid; ga uuid; r jsonb; s jsonb;
  membres int; confirme boolean;
BEGIN
  -- ── décor ────────────────────────────────────────────────
  ta := _mk_tenant('F702T03A');
  r  := create_group('Groupe T03');
  ga := (r ->> 'group_id')::uuid;
  tb := _mk_tenant('F702T03B');
  tc := _mk_tenant('F702T03C');

  -- T03 — A ajoute B comme filiale à 60 %
  PERFORM _l702_act_as(ta);
  PERFORM add_group_member(ga, tb, 'subsidiary', 60, 'full');
  s := group_structure(ga);
  SELECT count(*) INTO membres FROM jsonb_array_elements(s -> 'members');
  PERFORM _rec('T03', 'ajout : la structure porte les DEUX sociétés, avec leur type / % / méthode',
    membres = 2
      AND (s -> 'members') @> jsonb_build_array(jsonb_build_object('tenant_id', tb::text, 'ownership_pct', 60, 'member_type', 'subsidiary')),
    format('membres=%s', membres));

  -- T04 — C, hors du groupe, ne le voit ni par la fonction ni par le helper
  PERFORM _l702_act_as(tc);
  PERFORM _rec('T04', 'isolation : une société HORS du groupe ne le voit pas',
    group_structure(ga) IS NULL AND NOT EXISTS (SELECT 1 FROM my_group_ids() g WHERE g = ga),
    format('group_structure=%s my_group_ids contient=%s',
      COALESCE(group_structure(ga)::text, 'NULL'),
      EXISTS (SELECT 1 FROM my_group_ids() g WHERE g = ga)));

  -- T05 — C ne peut pas s'ajouter au groupe de A
  confirme := false;
  BEGIN
    PERFORM add_group_member(ga, tc, 'subsidiary');
  EXCEPTION WHEN OTHERS THEN
    confirme := SQLERRM LIKE '%GROUP_NOT_MEMBER%';
  END;
  PERFORM _rec('T05', 'refus : on n''ajoute personne à un groupe dont SA société n''est pas membre',
    confirme, format('refus nommé GROUP_NOT_MEMBER = %s', confirme));

  -- T06 — A enregistre un flux vers B ; un flux vers soi-même est refusé
  PERFORM _l702_act_as(ta);
  r := record_intra_group_transaction(ga, tb, 'sale', 1000, CURRENT_DATE, 'FA-2026-1');
  SELECT (status = 'confirmed' AND from_tenant_id = ta AND to_tenant_id = tb)
    INTO confirme FROM intra_group_transactions WHERE id = (r ->> 'transaction_id')::uuid;
  IF NOT confirme THEN
    PERFORM _rec('T06', 'flux intra-groupe : enregistré, confirmé, de MA société vers la contrepartie', false,
      format('flux non trouvé ou non confirmé (r=%s)', r));
  ELSE
    BEGIN
      PERFORM record_intra_group_transaction(ga, ta, 'sale', 100, CURRENT_DATE);
      PERFORM _rec('T06', 'flux intra-groupe', false, 'un flux d''une société vers elle-même a été accepté');
    EXCEPTION WHEN OTHERS THEN
      PERFORM _rec('T06', 'flux intra-groupe : enregistré et confirmé ; un flux vers soi-même est refusé',
        SQLERRM LIKE '%INTRA_GROUP_SELF%', SQLERRM);
    END;
  END IF;

  -- T07 — un flux vers C (hors groupe) est refusé
  confirme := false;
  BEGIN
    PERFORM record_intra_group_transaction(ga, tc, 'sale', 500, CURRENT_DATE);
  EXCEPTION WHEN OTHERS THEN
    confirme := SQLERRM LIKE '%GROUP_NOT_MEMBER%';
  END;
  PERFORM _rec('T07', 'refus : un flux vers une société HORS du groupe est refusé',
    confirme, format('refus nommé GROUP_NOT_MEMBER = %s', confirme));

  -- T08 — retrait : B sort (le groupe reste), puis A sort (le groupe meurt)
  PERFORM _l702_act_as(ta);
  PERFORM remove_group_member(ga, tb);
  SELECT count(*) INTO membres FROM group_members WHERE group_id = ga;
  r := remove_group_member(ga, ta);
  PERFORM _rec('T08', 'retrait : B sort (le groupe reste), puis retirer le DERNIER membre supprime le groupe',
    membres = 1 AND (r ->> 'group_deleted')::boolean
      AND to_regclass('public.groups') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM groups WHERE id = ga),
    format('après retrait de B : %s membre(s) ; group_deleted=%s', membres, r ->> 'group_deleted'));
EXCEPTION WHEN OTHERS THEN
  -- Le décor a cassé : AUCUN scénario ne passe en silence.
  PERFORM _rec('T03', 'ajout d''un membre à la structure', false, SQLERRM);
  PERFORM _rec('T04', 'isolation : une société hors du groupe ne le voit pas', false, SQLERRM);
  PERFORM _rec('T05', 'refus d''ajout par une société non membre', false, SQLERRM);
  PERFORM _rec('T06', 'flux intra-groupe', false, SQLERRM);
  PERFORM _rec('T07', 'refus d''un flux vers une société hors groupe', false, SQLERRM);
  PERFORM _rec('T08', 'retrait d''un membre', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 8 verdicts (un décor cassé
-- enregistrerait moins de lignes et passerait pour verte sans rien prouver).
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '702';
  IF n <> 8 THEN
    RAISE EXCEPTION '[702] % verdict(s) enregistré(s) au lieu de 8 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('702');

