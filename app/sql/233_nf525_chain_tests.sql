-- ============================================================
-- 233_nf525_chain_tests.sql — H11 : intégrité du journal fiscal NF-525
--
-- Mesuré AVANT la 233, sur trois événements écrits à la suite et rien d'autre :
--   verify_nf525_chain() → sauts=3, chaîne INVALIDE, after_id = before_id,
--   missing_count = -1. Le journal d'une société saine se déclarait altéré à
--   chaque vérification (T01 et T02 rouges).
--
-- T03 et T04 sont l'autre moitié du contrat : une chaîne réellement altérée
-- doit être déclarée invalide. Ils étaient « verts » avant la 233 — mais pour
-- la mauvaise raison, puisque TOUTE chaîne l'était. Ils n'ont de sens qu'une
-- fois T01 vert.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '233', false);
DELETE FROM _audit_results WHERE file = '233';

-- T01 : une chaîne intacte est déclarée valide
DO $$
DECLARE t uuid; r jsonb;
BEGIN
  t := _mk_tenant('T01NF');
  PERFORM _as_user();
  PERFORM log_nf525_event('T01', 'probe', NULL, '{}'::jsonb);
  PERFORM log_nf525_event('T01', 'probe', NULL, '{}'::jsonb);
  PERFORM log_nf525_event('T01', 'probe', NULL, '{}'::jsonb);
  r := verify_nf525_chain(NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T01', 'une chaîne intacte est valide : 3 événements, 0 lien rompu, 0 saut',
    (r ->> 'chain_valid')::boolean AND (r ->> 'total_events')::int = 3
      AND (r ->> 'broken_links')::int = 0 AND (r ->> 'gap_count')::int = 0,
    format('total=%s rompus=%s sauts=%s valide=%s', r ->> 'total_events', r ->> 'broken_links',
           r ->> 'gap_count', r ->> 'chain_valid'));
END $$;

-- T02 : une transaction annulée consomme un numéro de séquence — c'est un
--       signal, pas une altération : le saut est signalé, la chaîne reste valide
DO $$
DECLARE t uuid; r jsonb; v_note text;
BEGIN
  t := _mk_tenant('T02NF');
  PERFORM _as_user();
  PERFORM log_nf525_event('T02', 'probe', NULL, '{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  PERFORM nextval('nf525_event_log_id_seq');   -- ce que laisse une transaction annulée
  PERFORM _as_user();
  PERFORM log_nf525_event('T02', 'probe', NULL, '{}'::jsonb);
  r := verify_nf525_chain(NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(d ->> 'error', ',') INTO v_note FROM jsonb_array_elements(r -> 'details') d;
  PERFORM _rec('T02', 'numéro de séquence consommé par une transaction annulée : saut signalé, chaîne valide',
    (r ->> 'chain_valid')::boolean AND (r ->> 'gap_count')::int = 1 AND (r ->> 'broken_links')::int = 0
      AND COALESCE(v_note, '') = 'ID_GAP_DETECTED',
    format('valide=%s sauts=%s rompus=%s erreurs=%s', r ->> 'chain_valid', r ->> 'gap_count',
           r ->> 'broken_links', COALESCE(v_note, '—')));
END $$;

-- T03 : un maillon supprimé au milieu casse le chaînage
DO $$
DECLARE t uuid; r jsonb; v_id bigint; v_err text;
BEGIN
  t := _mk_tenant('T03NF');
  PERFORM _as_user();
  PERFORM log_nf525_event('T03', 'probe', NULL, '{}'::jsonb);
  v_id := log_nf525_event('T03', 'probe', NULL, '{}'::jsonb);
  PERFORM log_nf525_event('T03', 'probe', NULL, '{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  -- Le journal est inaltérable par trigger (T06) : pour éprouver le contrôle
  -- d'intégrité, on se met dans la peau de qui accède à la base sans passer par
  -- l'application — session_replication_role = replica neutralise les triggers.
  SET LOCAL session_replication_role = 'replica';
  DELETE FROM nf525_event_log WHERE id = v_id;          -- suppression du maillon du milieu
  SET LOCAL session_replication_role = 'origin';
  PERFORM _as_user();
  r := verify_nf525_chain(NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(d ->> 'error', ',' ORDER BY d ->> 'error') INTO v_err FROM jsonb_array_elements(r -> 'details') d;
  PERFORM _rec('T03', 'maillon supprimé au milieu : chaîne invalide, lien rompu ET saut signalés',
    NOT (r ->> 'chain_valid')::boolean AND (r ->> 'broken_links')::int >= 1 AND (r ->> 'gap_count')::int = 1
      AND COALESCE(v_err, '') LIKE '%CHAIN_FORK_OR_MISSING_LINK%',
    format('valide=%s rompus=%s sauts=%s erreurs=%s', r ->> 'chain_valid', r ->> 'broken_links',
           r ->> 'gap_count', COALESCE(v_err, '—')));
END $$;

-- T04 : un contenu retouché ne redonne plus son hachage
DO $$
DECLARE t uuid; r jsonb; v_id bigint; v_err text;
BEGIN
  t := _mk_tenant('T04NF');
  PERFORM _as_user();
  PERFORM log_nf525_event('T04', 'probe', NULL, '{}'::jsonb);
  v_id := log_nf525_event('T04', 'probe', NULL, '{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  SET LOCAL session_replication_role = 'replica';       -- cf. T03 : accès direct à la base
  UPDATE nf525_event_log SET event_type = 'T04-RETOUCHÉ' WHERE id = v_id;
  SET LOCAL session_replication_role = 'origin';
  PERFORM _as_user();
  r := verify_nf525_chain(NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  SELECT string_agg(d ->> 'error', ',') INTO v_err FROM jsonb_array_elements(r -> 'details') d;
  PERFORM _rec('T04', 'contenu retouché : hachage recalculé différent, chaîne invalide',
    NOT (r ->> 'chain_valid')::boolean AND COALESCE(v_err, '') LIKE '%HASH_MISMATCH%',
    format('valide=%s rompus=%s erreurs=%s', r ->> 'chain_valid', r ->> 'broken_links', COALESCE(v_err, '—')));
END $$;

-- T05 : la vérification ne voit que le journal de sa propre société
DO $$
DECLARE ta uuid; tb uuid; r jsonb;
BEGIN
  ta := _mk_tenant('T05NFA');
  PERFORM _as_user();
  PERFORM log_nf525_event('T05A', 'probe', NULL, '{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  tb := _mk_tenant('T05NFB');
  PERFORM _as_user();
  PERFORM log_nf525_event('T05B', 'probe', NULL, '{}'::jsonb);
  PERFORM log_nf525_event('T05B', 'probe', NULL, '{}'::jsonb);
  r := verify_nf525_chain(NULL, NULL);
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T05', 'la vérification ne compte que les événements de sa propre société',
    (r ->> 'total_events')::int = 2 AND (r ->> 'chain_valid')::boolean,
    format('total=%s (2 attendus) valide=%s', r ->> 'total_events', r ->> 'chain_valid'));
END $$;

-- T06 : le journal refuse la suppression et la modification par le chemin normal,
--       même sous un rôle privilégié — c'est la première barrière, le chaînage
--       n'étant que la seconde
DO $$
DECLARE t uuid; v_id bigint; refus_del boolean := false; refus_upd boolean := false; n int;
BEGIN
  t := _mk_tenant('T06NF');
  PERFORM _as_user();
  v_id := log_nf525_event('T06', 'probe', NULL, '{}'::jsonb);
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    DELETE FROM nf525_event_log WHERE id = v_id;
  EXCEPTION WHEN OTHERS THEN refus_del := true;
  END;
  BEGIN
    UPDATE nf525_event_log SET event_type = 'X' WHERE id = v_id;
  EXCEPTION WHEN OTHERS THEN refus_upd := true;
  END;
  SELECT count(*) INTO n FROM nf525_event_log WHERE id = v_id AND event_type = 'T06';
  PERFORM _rec('T06', 'le journal d''événements est inaltérable : suppression et modification refusées',
    refus_del AND refus_upd AND n = 1,
    format('refus suppression=%s refus modification=%s ligne intacte=%s', refus_del, refus_upd, n));
END $$;

SELECT _audit_assert('233');
