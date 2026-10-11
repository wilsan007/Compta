-- ═══════════════════════════════════════════════════════════════════════════
-- 758_chain_l16_lettrage_groupes_tests.sql — L16 · groupe de lettrage → ses lignes
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : le groupe trace CHACUNE de ses lignes de journal (2 liens) ;
--   T02  IDEMPOTENCE STRUCTURELLE : rejouer rend le MÊME nombre et ne double aucun
--        lien ;
--   T03  REFUS EXPLICITES : groupe introuvable, groupe annulé, groupe sans ligne ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit les lignes depuis le groupe, et le
--        groupe depuis une ligne ;
--   T05  ISOLATION (D8) : le voisin ne trace pas le groupe d'autrui, et ne voit rien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '758', false);
DELETE FROM _audit_results WHERE file = '758';

-- ── T01 — LE NOMINAL : le groupe trace ses lignes ──────────────────────────
DO $$
DECLARE t uuid; g uuid; e uuid; r jsonb; n int;
BEGIN
  t := _mk_tenant('T758A');
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (t, 'L758A', '2026-03-01', 'open') RETURNING id INTO g;
  e := _entry(t, 'JE-758-A', '2026-03-01',
              '[{"a":"411000","d":100},{"a":"701000","c":100}]'::jsonb);
  UPDATE journal_lines SET lettrage_group_id = g WHERE journal_id = e;

  PERFORM _as_user();
  r := chain_l16_lettrage_group(g);

  PERFORM _rec('T01a', 'le maillon rend le NOMBRE de lignes tracées (2)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'lines')::int = 2, r::text);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'journal_lines'
     AND aval_type = 'lettrage_groups' AND aval_id = g
     AND effet = 'rev.line.lettered' AND etat = 'actif';
  PERFORM _rec('T01b', 'les DEUX liens (une ligne de journal chacun) sont posés, actifs', n = 2, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE STRUCTURELLE : le rejeu ne double rien ───────────────
DO $$
DECLARE t uuid; g uuid; e uuid; r jsonb; n1 int; n2 int;
BEGIN
  t := _mk_tenant('T758B');
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (t, 'L758B', '2026-03-01', 'open') RETURNING id INTO g;
  e := _entry(t, 'JE-758-B', '2026-03-01',
              '[{"a":"411000","d":50},{"a":"701000","c":50}]'::jsonb);
  UPDATE journal_lines SET lettrage_group_id = g WHERE journal_id = e;
  PERFORM _as_user();
  PERFORM chain_l16_lettrage_group(g);
  SELECT count(*) INTO n1 FROM document_links
   WHERE tenant_id = t AND aval_id = g AND effet = 'rev.line.lettered' AND etat = 'actif';
  r := chain_l16_lettrage_group(g);   -- rejeu
  SELECT count(*) INTO n2 FROM document_links
   WHERE tenant_id = t AND aval_id = g AND effet = 'rev.line.lettered' AND etat = 'actif';
  PERFORM _rec('T02a', 'rejouer ne double AUCUN lien (idempotence structurelle)', n1 = 2 AND n2 = 2,
    'avant = ' || n1 || ', après = ' || n2);
  PERFORM _rec('T02b', 'le rejeu rend le même compte de lignes (2)', (r->>'lines')::int = 2, r::text);
END $$;

-- ── T03 — REFUS EXPLICITES : trois refus, trois raisons ────────────────────
DO $$
DECLARE t uuid; g_cancel uuid; g_empty uuid;
BEGIN
  t := _mk_tenant('T758C');
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (t, 'L758Cc', '2026-03-01', 'cancelled') RETURNING id INTO g_cancel;
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (t, 'L758Ce', '2026-03-01', 'open') RETURNING id INTO g_empty;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_lettrage_group('00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'un groupe INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un groupe INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_lettrage_group(g_cancel);
    PERFORM _rec('T03b', 'un groupe ANNULÉ est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un groupe ANNULÉ est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_lettrage_group(g_empty);
    PERFORM _rec('T03c', 'un groupe SANS LIGNE est refusé (rien à tracer)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un groupe SANS LIGNE est refusé (rien à tracer)', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; g uuid; e uuid; l uuid; n int;
BEGIN
  t := _mk_tenant('T758D');
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (t, 'L758D', '2026-03-01', 'open') RETURNING id INTO g;
  e := _entry(t, 'JE-758-D', '2026-03-01',
              '[{"a":"411000","d":240},{"a":"701000","c":240}]'::jsonb);
  UPDATE journal_lines SET lettrage_group_id = g WHERE journal_id = e;
  PERFORM _as_user();
  PERFORM chain_l16_lettrage_group(g);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'lettrage_groups', g, 'amont', 5, false)
   WHERE type = 'journal_lines';
  PERFORM _rec('T04a', 'depuis le GROUPE, la frise voit ses LIGNES DE JOURNAL', n = 2, 'nœuds amont = ' || n);

  SELECT id INTO l FROM journal_lines WHERE journal_id = e LIMIT 1;
  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'journal_lines', l, 'aval', 5, false)
   WHERE type = 'lettrage_groups' AND id = g;
  PERFORM _rec('T04b', 'depuis une LIGNE, la frise voit le GROUPE', n = 1, 'nœuds aval = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne trace pas, et ne voit rien ──────────
DO $$
DECLARE ta uuid; tb uuid; ga uuid; ea uuid; n int;
BEGIN
  ta := _mk_tenant('T758E1');
  INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, status)
    VALUES (ta, 'L758E1', '2026-03-01', 'open') RETURNING id INTO ga;
  ea := _entry(ta, 'JE-758-E1', '2026-03-01',
               '[{"a":"411000","d":10},{"a":"701000","c":10}]'::jsonb);
  UPDATE journal_lines SET lettrage_group_id = ga WHERE journal_id = ea;
  PERFORM _as_user();
  PERFORM chain_l16_lettrage_group(ga);

  RESET ROLE;
  tb := _mk_tenant('T758E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_lettrage_group(ga);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas tracer le groupe d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas tracer le groupe d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'journal_lines' AND aval_type = 'lettrage_groups' AND aval_id = ga;
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE aval_id = ga AND effet = 'rev.line.lettered' AND tenant_id = ta;
  PERFORM _rec('T05c', 'les liens de A existent toujours et restent à A', n = 2, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('758');
