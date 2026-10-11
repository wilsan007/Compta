-- ═══════════════════════════════════════════════════════════════════════════
-- 759_chain_l16_bulletin_ecriture_tests.sql — L16 · bulletin de paie → écriture
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : le bulletin rattache son écriture comptable ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : bulletin introuvable, bulletin annulé, bulletin non
--        comptabilisé — trois refus, trois raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit l'écriture depuis le bulletin, et
--        le bulletin depuis l'écriture ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '759', false);
DELETE FROM _audit_results WHERE file = '759';

-- ── T01 — LE NOMINAL : le bulletin rattache son écriture ───────────────────
DO $$
DECLARE t uuid; emp uuid; run uuid; s uuid; e uuid; r jsonb; n int;
BEGIN
  t := _mk_tenant('T759A');
  INSERT INTO employees (tenant_id, name, status, payroll_category)
    VALUES (t, 'Salarie 759', 'active', 'non_cadre') RETURNING id INTO emp;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-759-A', '2026-03-01', '2026-03-31', '2026-03-31', 'closed') RETURNING id INTO run;
  e := _entry(t, 'JE-759-A', '2026-03-31', '[{"a":"641000","d":1000},{"a":"421000","c":1000}]'::jsonb);
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_entry_id, journal_posted)
    VALUES (t, 'BS-759-A', run, emp, '2026-03-01', '2026-03-31', 'paid', e, true) RETURNING id INTO s;

  PERFORM _as_user();
  r := chain_l16_payslip_entry(s);

  PERFORM _rec('T01a', 'le bulletin rattache son écriture (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'entry_id')::uuid = e, r::text);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'pay_slips' AND amont_id = s
     AND aval_type = 'journal_entries' AND aval_id = e
     AND effet = 'payroll.slip.posted' AND etat = 'actif';
  PERFORM _rec('T01b', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; emp uuid; run uuid; s uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T759B');
  INSERT INTO employees (tenant_id, name, status, payroll_category)
    VALUES (t, 'Salarie 759 B', 'active', 'non_cadre') RETURNING id INTO emp;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-759-B', '2026-03-01', '2026-03-31', '2026-03-31', 'closed') RETURNING id INTO run;
  e := _entry(t, 'JE-759-B', '2026-03-31', '[{"a":"641000","d":500},{"a":"421000","c":500}]'::jsonb);
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_entry_id, journal_posted)
    VALUES (t, 'BS-759-B', run, emp, '2026-03-01', '2026-03-31', 'paid', e, true) RETURNING id INTO s;
  PERFORM _as_user();
  PERFORM chain_l16_payslip_entry(s);
  BEGIN
    PERFORM chain_l16_payslip_entry(s);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = s AND effet = 'payroll.slip.posted' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : trois refus, trois raisons ────────────────────
DO $$
DECLARE t uuid; emp uuid; run uuid; s_cancel uuid; s_draft uuid;
BEGIN
  t := _mk_tenant('T759C');
  INSERT INTO employees (tenant_id, name, status, payroll_category)
    VALUES (t, 'Salarie 759 C', 'active', 'non_cadre') RETURNING id INTO emp;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-759-C', '2026-03-01', '2026-03-31', '2026-03-31', 'closed') RETURNING id INTO run;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_posted)
    VALUES (t, 'BS-759-Cc', run, emp, '2026-03-01', '2026-03-31', 'cancelled', false) RETURNING id INTO s_cancel;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_posted)
    VALUES (t, 'BS-759-Cd', run, emp, '2026-03-01', '2026-03-31', 'draft', false) RETURNING id INTO s_draft;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_payslip_entry('00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'un bulletin INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un bulletin INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_payslip_entry(s_cancel);
    PERFORM _rec('T03b', 'un bulletin ANNULÉ est refusé, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un bulletin ANNULÉ est refusé, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_payslip_entry(s_draft);
    PERFORM _rec('T03c', 'un bulletin NON COMPTABILISÉ est refusé (aucune écriture)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un bulletin NON COMPTABILISÉ est refusé (aucune écriture)', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; emp uuid; run uuid; s uuid; e uuid; n int;
BEGIN
  t := _mk_tenant('T759D');
  INSERT INTO employees (tenant_id, name, status, payroll_category)
    VALUES (t, 'Salarie 759 D', 'active', 'non_cadre') RETURNING id INTO emp;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-759-D', '2026-03-01', '2026-03-31', '2026-03-31', 'closed') RETURNING id INTO run;
  e := _entry(t, 'JE-759-D', '2026-03-31', '[{"a":"641000","d":240},{"a":"421000","c":240}]'::jsonb);
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_entry_id, journal_posted)
    VALUES (t, 'BS-759-D', run, emp, '2026-03-01', '2026-03-31', 'paid', e, true) RETURNING id INTO s;
  PERFORM _as_user();
  PERFORM chain_l16_payslip_entry(s);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'pay_slips', s, 'aval', 5, false)
   WHERE type = 'journal_entries' AND id = e;
  PERFORM _rec('T04a', 'depuis le BULLETIN, la frise voit l''ÉCRITURE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'journal_entries', e, 'amont', 5, false)
   WHERE type = 'pay_slips' AND id = s;
  PERFORM _rec('T04b', 'depuis l''ÉCRITURE, la frise voit le BULLETIN', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; empa uuid; runa uuid; sa uuid; ea uuid; n int;
BEGIN
  ta := _mk_tenant('T759E1');
  INSERT INTO employees (tenant_id, name, status, payroll_category)
    VALUES (ta, 'Salarie E1', 'active', 'non_cadre') RETURNING id INTO empa;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (ta, 'PR-759-E1', '2026-03-01', '2026-03-31', '2026-03-31', 'closed') RETURNING id INTO runa;
  ea := _entry(ta, 'JE-759-E1', '2026-03-31', '[{"a":"641000","d":100},{"a":"421000","c":100}]'::jsonb);
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status, journal_entry_id, journal_posted)
    VALUES (ta, 'BS-759-E1', runa, empa, '2026-03-01', '2026-03-31', 'paid', ea, true) RETURNING id INTO sa;
  PERFORM _as_user();
  PERFORM chain_l16_payslip_entry(sa);

  RESET ROLE;
  tb := _mk_tenant('T759E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_payslip_entry(sa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le bulletin d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le bulletin d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'pay_slips' AND amont_id = sa AND aval_type = 'journal_entries';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = sa AND effet = 'payroll.slip.posted' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('759');
