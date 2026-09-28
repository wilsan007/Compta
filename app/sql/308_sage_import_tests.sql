-- ============================================================
-- 308_sage_import_tests.sql — W7 (M-19) : l'import est un acte unique
--
--   SAGE-01 🔴 les écritures importées restent en **brouillon** (rien ne les
--             valide) et l'équilibre n'est pas contrôlé ;
--   SAGE-02 🟠 les soldes du plan comptable sont **écrasés** (remplacés par le
--             cumul importé) ;
--   SAGE-03 🟠 chaque écriture est tentée dans son propre `try/catch` : un import
--             partiel laisse une comptabilité à moitié faite.
--
-- Les scénarios mesurent : les pièces importées sont **validées**, un import
-- déséquilibré n'écrit **rien**, un réimport ne duplique rien, les soldes
-- **cumulent**, et une validation refusée par le noyau annule **tout**.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '308', false);
DELETE FROM _audit_results WHERE file = '308';

DROP FUNCTION IF EXISTS _imp308_ecriture(text, text, numeric, numeric, text);
CREATE OR REPLACE FUNCTION _imp308_ecriture(p_num text, p_journal text, p_debit numeric,
  p_credit numeric, p_compte text DEFAULT '607000')
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'number', p_num, 'date', '2026-03-15', 'journal_code', p_journal,
    'description', 'Import ' || p_num, 'piece_number', p_num,
    'lines', jsonb_build_array(
      jsonb_build_object('account_code', p_compte, 'account_name', 'Compte ' || p_compte,
                         'debit', p_debit, 'credit', 0, 'line_order', 0),
      jsonb_build_object('account_code', '401000', 'account_name', 'Fournisseurs',
                         'debit', 0, 'credit', p_credit, 'line_order', 1)
    ))
$$;

-- T01 — SAGE-01 : deux écritures équilibrées entrent **validées** (et non en
-- brouillard), leurs lignes sont écrites.
DO $$
DECLARE t uuid; r jsonb; n_posted int; n_draft int; n_lignes int;
BEGIN
  t := _mk_tenant('IMP01');
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  BEGIN
    r := public.import_fec_entries(jsonb_build_array(
      _imp308_ecriture('I-1', 'OD', 1000, 1000),
      _imp308_ecriture('I-2', 'OD', 250, 250, '606000')
    ));
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) FILTER (WHERE status = 'posted'), count(*) FILTER (WHERE status = 'draft')
      INTO n_posted, n_draft FROM journal_entries WHERE tenant_id = t;
    SELECT count(*) INTO n_lignes FROM journal_lines WHERE tenant_id = t;
    PERFORM _rec('T01', 'les écritures importées sont validées (un brouillard n''est pas une comptabilité)',
      n_posted = 2 AND n_draft = 0 AND n_lignes = 4,
      format('validées=%s brouillons=%s lignes=%s | verdict=%s', n_posted, n_draft, n_lignes, r::text));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T01', 'les écritures importées sont validées (un brouillard n''est pas une comptabilité)', false, SQLERRM);
  END;
END $$;

-- T02 — SAGE-01 : un import déséquilibré est refusé avant toute écriture.
DO $$
DECLARE t uuid; refuse boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('IMP02');
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  BEGIN
    PERFORM public.import_fec_entries(jsonb_build_array(_imp308_ecriture('I-3', 'OD', 1000, 900)));
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t;
  PERFORM _rec('T02', 'un import déséquilibré est refusé et n''écrit rien',
    refuse AND n = 0, format('refus=%s écritures écrites=%s | %s', refuse, n, left(err, 90)));
END $$;

-- T03 — SAGE-03 : réimporter les mêmes pièces ne duplique pas et ne laisse pas
-- un import partiel.
DO $$
DECLARE t uuid; refuse boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('IMP03');
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  -- Le premier import est hors du bloc protégé : il doit survivre à l'échec du second.
  PERFORM public.import_fec_entries(jsonb_build_array(_imp308_ecriture('I-4', 'OD', 100, 100)));
  BEGIN
    PERFORM public.import_fec_entries(jsonb_build_array(_imp308_ecriture('I-4', 'OD', 100, 100)));
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t;
  PERFORM _rec('T03', 'réimporter une pièce existante est refusé (pas de doublon, pas d''import partiel)',
    refuse AND n = 1 AND err NOT LIKE '%does not exist%', format('refus=%s écritures=%s (1 attendue) | %s', refuse, n, left(err, 90)));
END $$;

-- T04 — SAGE-02 : les soldes des comptes **cumulent** l'import, ils ne sont pas
-- écrasés (un compte qui portait 500 et reçoit 1 000 vaut 1 500).
DO $$
DECLARE t uuid; solde numeric; n_crees int;
BEGIN
  t := _mk_tenant('IMP04');
  PERFORM ensure_standard_journals(t);
  UPDATE chart_accounts SET balance = 500 WHERE tenant_id = t AND code = '607000';
  PERFORM _as_user();
  BEGIN
    PERFORM public.import_fec_entries(jsonb_build_array(
      _imp308_ecriture('I-5', 'OD', 1000, 1000),
      _imp308_ecriture('I-6', 'OD', 200, 200, '606000')
    ));
    PERFORM set_config('role', 'postgres', true);
    SELECT balance INTO solde FROM chart_accounts WHERE tenant_id = t AND code = '607000';
    SELECT count(*) INTO n_crees FROM chart_accounts WHERE tenant_id = t AND code = '606000';
    PERFORM _rec('T04', 'les soldes des comptes cumulent l''import (500 + 1 000 = 1 500)',
      solde = 1500, format('solde 607000=%s (1 500 attendu) ; compte créé=%s', solde, n_crees));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T04', 'les soldes des comptes cumulent l''import (500 + 1 000 = 1 500)', false, SQLERRM);
  END;
END $$;

-- T05 — SAGE-03 : si le noyau refuse **une** écriture, l'import entier est
-- annulé (aucune écriture, aucun solde touché).
DO $$
DECLARE t uuid; refuse boolean := false; err text := '—'; n int; solde numeric;
BEGIN
  t := _mk_tenant('IMP05');
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  BEGIN
    PERFORM public.import_fec_entries(jsonb_build_array(
      _imp308_ecriture('I-7', 'OD', 300, 300),
      _imp308_ecriture('I-8', 'ZZ', 300, 300)
    ));
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t;
  SELECT balance INTO solde FROM chart_accounts WHERE tenant_id = t AND code = '607000';
  PERFORM _rec('T05', 'une écriture refusée par le noyau annule tout l''import (atomicité)',
    refuse AND n = 0 AND COALESCE(solde, 0) = 0 AND err NOT LIKE '%does not exist%',
    format('refus=%s écritures=%s solde 607000=%s | %s', refuse, n, solde, left(err, 80)));
END $$;

DROP FUNCTION _imp308_ecriture(text, text, numeric, numeric, text);
SELECT _audit_assert('308');

