-- ═══════════════════════════════════════════════════════════════════════════
-- 760_chain_l16_cloture_resultat_tests.sql — L16 · exercice clos → écriture d'affectation
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : l'exercice clos rattache son écriture d'affectation ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : exercice introuvable, exercice OUVERT, résultat non
--        affecté — trois refus, trois raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit l'écriture depuis l'exercice, et
--        l'exercice depuis l'écriture ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '760', false);
DELETE FROM _audit_results WHERE file = '760';

-- ── T01 — LE NOMINAL : l'exercice clos rattache son écriture ───────────────
DO $$
DECLARE t uuid; fy uuid; e uuid; r jsonb; n int;
BEGIN
  t := _mk_tenant('T760A');
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  e := _entry(t, 'JE-760-A', '2026-12-31', '[{"a":"120000","d":5000},{"a":"110000","c":5000}]'::jsonb);
  UPDATE fiscal_years SET status = 'closed', closed_at = now(),
         result_allocated_at = now(), result_allocation_entry_id = e WHERE id = fy;

  PERFORM _as_user();
  r := chain_l16_fiscal_year_result(fy);

  PERFORM _rec('T01a', 'l''exercice clos rattache son écriture d''affectation (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'entry_id')::uuid = e, r::text);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'fiscal_years' AND amont_id = fy
     AND aval_type = 'journal_entries' AND aval_id = e
     AND effet = 'rev.fiscal_year.result_allocated' AND etat = 'actif';
  PERFORM _rec('T01b', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; fy uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T760B');
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  e := _entry(t, 'JE-760-B', '2026-12-31', '[{"a":"120000","d":800},{"a":"110000","c":800}]'::jsonb);
  UPDATE fiscal_years SET status = 'closed', closed_at = now(),
         result_allocated_at = now(), result_allocation_entry_id = e WHERE id = fy;
  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_result(fy);
  BEGIN
    PERFORM chain_l16_fiscal_year_result(fy);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = fy AND effet = 'rev.fiscal_year.result_allocated' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : trois refus, trois raisons ────────────────────
DO $$
DECLARE t uuid; fy_open uuid; fy_noalloc uuid;
BEGIN
  t := _mk_tenant('T760C');
  -- l'exercice ouvert créé par _mk_tenant (2026) ; un exercice clos SANS affectation
  SELECT id INTO fy_open FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, '2027', '2027-01-01', '2027-12-31', 'closed') RETURNING id INTO fy_noalloc;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_fiscal_year_result('00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'un exercice INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un exercice INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_fiscal_year_result(fy_open);
    PERFORM _rec('T03b', 'un exercice OUVERT est refusé (non clos)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un exercice OUVERT est refusé (non clos)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_fiscal_year_result(fy_noalloc);
    PERFORM _rec('T03c', 'un exercice au RÉSULTAT NON AFFECTÉ est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un exercice au RÉSULTAT NON AFFECTÉ est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; fy uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T760D');
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  e := _entry(t, 'JE-760-D', '2026-12-31', '[{"a":"120000","d":1500},{"a":"110000","c":1500}]'::jsonb);
  UPDATE fiscal_years SET status = 'closed', closed_at = now(),
         result_allocated_at = now(), result_allocation_entry_id = e WHERE id = fy;
  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_result(fy);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'fiscal_years', fy, 'aval', 5, false)
   WHERE type = 'journal_entries' AND id = e;
  PERFORM _rec('T04a', 'depuis l''EXERCICE, la frise voit l''ÉCRITURE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'journal_entries', e, 'amont', 5, false)
   WHERE type = 'fiscal_years' AND id = fy;
  PERFORM _rec('T04b', 'depuis l''ÉCRITURE, la frise voit l''EXERCICE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; fya uuid; ea uuid; n int;
BEGIN
  ta := _mk_tenant('T760E1');
  SELECT id INTO fya FROM fiscal_years WHERE tenant_id = ta LIMIT 1;
  ea := _entry(ta, 'JE-760-E1', '2026-12-31', '[{"a":"120000","d":100},{"a":"110000","c":100}]'::jsonb);
  UPDATE fiscal_years SET status = 'closed', closed_at = now(),
         result_allocated_at = now(), result_allocation_entry_id = ea WHERE id = fya;
  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_result(fya);

  RESET ROLE;
  tb := _mk_tenant('T760E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_fiscal_year_result(fya);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''exercice d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''exercice d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'fiscal_years' AND amont_id = fya AND aval_type = 'journal_entries';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fya AND effet = 'rev.fiscal_year.result_allocated' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('760');
