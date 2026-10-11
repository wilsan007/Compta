-- ═══════════════════════════════════════════════════════════════════════════
-- 763_chain_l16_ouverture_exercice_tests.sql — L16 · exercice → écriture d'à-nouveaux
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : l'exercice rattache son écriture d'à-nouveaux ; le LIEN est
--        posé ; et le maillon n'a RIEN écrit — l'écriture validée reste validée,
--        son exercice est celui que le garde de l'écriture (187) a posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : exercice introuvable, écriture introuvable, écriture
--        d'un AUTRE journal, écriture datée d'un AUTRE jour ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit l'écriture depuis l'exercice, et
--        l'exercice depuis l'écriture ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '763', false);
DELETE FROM _audit_results WHERE file = '763';

-- ── T01 — LE NOMINAL : l'exercice rattache son écriture d'à-nouveaux ───────
DO $$
DECLARE t uuid; fy uuid; e uuid; r jsonb; n int; vfy uuid; vst text;
BEGIN
  t := _mk_tenant('T763A');
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (t, 'AN', 'À-nouveaux', 'general', 'active', 1) ON CONFLICT DO NOTHING;
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  -- l'écriture d'à-nouveaux : journal AN, datée du PREMIER JOUR de l'exercice
  e := _entry(t, 'AN-2026-0001', '2026-01-01', '[{"a":"120000","d":5000},{"a":"110000","c":5000}]'::jsonb, true, 'AN');

  PERFORM _as_user();
  r := chain_l16_fiscal_year_opening(fy, e);

  PERFORM _rec('T01a', 'l''exercice rattache son écriture d''à-nouveaux (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'entry_id')::uuid = e, r::text);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'fiscal_years' AND amont_id = fy
     AND aval_type = 'journal_entries' AND aval_id = e
     AND effet = 'rev.fiscal_year.opening_entry' AND etat = 'actif';
  PERFORM _rec('T01b', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);

  -- le maillon N'ÉCRIT RIEN : c'est une décision mesurée (le garde de l'écriture,
  -- 187, a déjà posé fiscal_year_id ; et une écriture validée est immuable — la
  -- tentative d'écriture a été REFUSÉE pendant la construction de cette suite).
  SELECT fiscal_year_id, status INTO vfy, vst FROM journal_entries WHERE id = e;
  PERFORM _rec('T01c', 'l''écriture reste VALIDÉE, son exercice est celui posé par le garde 187 — le maillon n''a rien écrit',
    vst = 'posted' AND vfy = fy, 'status = ' || COALESCE(vst, '?') || ', fiscal_year_id = ' || COALESCE(vfy::text, 'NULL'));
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; fy uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T763B');
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (t, 'AN', 'À-nouveaux', 'general', 'active', 1) ON CONFLICT DO NOTHING;
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  e := _entry(t, 'AN-2026-0002', '2026-01-01', '[{"a":"120000","d":900},{"a":"110000","c":900}]'::jsonb, true, 'AN');

  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_opening(fy, e);
  BEGIN
    PERFORM chain_l16_fiscal_year_opening(fy, e);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = fy AND effet = 'rev.fiscal_year.opening_entry' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; fy uuid; e_od uuid; e_jour uuid;
BEGIN
  t := _mk_tenant('T763C');
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (t, 'AN', 'À-nouveaux', 'general', 'active', 1) ON CONFLICT DO NOTHING;
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;

  -- une écriture du journal OD (pas AN), et une datée d'un AUTRE jour
  e_od    := _entry(t, 'OD-763-C1', '2026-01-01', '[{"a":"120000","d":10},{"a":"110000","c":10}]'::jsonb, true, 'OD');
  e_jour  := _entry(t, 'AN-763-C2', '2026-06-15', '[{"a":"120000","d":20},{"a":"110000","c":20}]'::jsonb, true, 'AN');

  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_fiscal_year_opening('00000000-0000-0000-0000-000000000001'::uuid, e_od);
    PERFORM _rec('T03a', 'un exercice INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un exercice INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_fiscal_year_opening(fy, '00000000-0000-0000-0000-000000000002'::uuid);
    PERFORM _rec('T03b', 'une écriture INTROUVABLE est refusée (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03b', 'une écriture INTROUVABLE est refusée (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_fiscal_year_opening(fy, e_od);
    PERFORM _rec('T03c', 'une écriture d''un AUTRE journal que AN est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une écriture d''un AUTRE journal que AN est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_fiscal_year_opening(fy, e_jour);
    PERFORM _rec('T03d', 'une écriture datée d''un AUTRE jour que l''ouverture est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'une écriture datée d''un AUTRE jour que l''ouverture est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; fy uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T763D');
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (t, 'AN', 'À-nouveaux', 'general', 'active', 1) ON CONFLICT DO NOTHING;
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t LIMIT 1;
  e := _entry(t, 'AN-2026-0004', '2026-01-01', '[{"a":"120000","d":1500},{"a":"110000","c":1500}]'::jsonb, true, 'AN');
  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_opening(fy, e);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'fiscal_years', fy, 'aval', 5, false)
   WHERE type = 'journal_entries' AND id = e;
  PERFORM _rec('T04a', 'depuis l''EXERCICE, la frise voit son ÉCRITURE D''À-NOUVEAUX', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'journal_entries', e, 'amont', 5, false)
   WHERE type = 'fiscal_years' AND id = fy;
  PERFORM _rec('T04b', 'depuis l''ÉCRITURE, la frise voit l''EXERCICE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; fya uuid; ea uuid; n int;
BEGIN
  ta := _mk_tenant('T763E1');
  INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    VALUES (ta, 'AN', 'À-nouveaux', 'general', 'active', 1) ON CONFLICT DO NOTHING;
  SELECT id INTO fya FROM fiscal_years WHERE tenant_id = ta LIMIT 1;
  ea := _entry(ta, 'AN-2026-0005', '2026-01-01', '[{"a":"120000","d":100},{"a":"110000","c":100}]'::jsonb, true, 'AN');
  PERFORM _as_user();
  PERFORM chain_l16_fiscal_year_opening(fya, ea);

  RESET ROLE;
  tb := _mk_tenant('T763E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_fiscal_year_opening(fya, ea);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''exercice d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''exercice d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'fiscal_years' AND amont_id = fya AND aval_type = 'journal_entries';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fya AND effet = 'rev.fiscal_year.opening_entry' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('763');
