-- ============================================================
-- 223_bank_reconciliation_state.sql — R-09 : l'état de rapprochement, et l'écran qui le lit
--
-- Constat (plan, R-09), mesuré :
--   * `get_bank_reconciliation_state` (196, corrigée par la 222) n'était appelée par
--     AUCUN écran : 0 appel dans src/ ;
--   * le pointage de l'écran « Rapprochement bancaire » écrivait `reconciled` et
--     `matched` sur la SEULE ligne de relevé — ni `reconciled_entry_id`, ni
--     `journal_lines.reconciled`. Or l'état de rapprochement lit ces deux colonnes :
--     le pointage fait à la main ne changeait donc RIEN à l'état (et laissait les
--     écarts des deux côtés) ;
--   * `bank_accounts.statement_balance` (solde de CLÔTURE du relevé importé) n'était
--     alimenté par aucun écran — `updateStatementBalance` existait, jamais appelé :
--     aucune comparaison n'était possible ;
--   * `is_balanced` est vrai dès que le pointage est cohérent : c'est un contrôle
--     d'INTÉGRITÉ des paires, pas un état de rapprochement. L'information utile est
--     la LISTE des écarts, des deux côtés (relevé ET compte 512x).
--
-- Ce que la 223 ajoute :
--   1. l'état expose les écarts des DEUX côtés (`ledger_unmatched_transactions` :
--      chèques émis non débités, remises non créditées), les paires pointées
--      (`reconciled_transactions`), les compteurs, et `is_reconciled` — la seule
--      réponse qui vaille à « est-ce rapproché ? », distincte d'`is_balanced` ;
--   2. le solde de clôture du relevé est comparé aux lignes importées jusqu'à sa
--      date (`statement_closing_balance`, `closing_date`, `closing_difference`,
--      `closing_matches`) : une clôture qui ne colle pas à ses propres lignes
--      signale un import incomplet — ce que l'écran doit dire ;
--   3. `reconcile_bank_statement_line` / `unreconcile_bank_statement_line` : le
--      pointage manuel écrit les DEUX côtés, comme le pointage automatique de la
--      196. Un drapeau posé d'un seul côté n'est pas un pointage ; il laisse le
--      solde des écarts faux et l'état incapable de le voir ;
--   4. `post_bank_statement_line` : « Comptabiliser » une ligne de relevé non pointée
--      (frais bancaires, agios…). Écriture en brouillard puis validation (les gardes
--      de la 187 s'appliquent : équilibre, exercice, comptes du plan, permission),
--      contrepartie sur le compte 6/7 choisi — 627000 (frais bancaires) au débit,
--      768000 (produits financiers) au crédit —, puis pointage des deux côtés.
--
-- Les deux mutations sont gardées : le pointage touche l'état de rapprochement des
-- écritures (`journal_entry.update`), la comptabilisation crée une écriture validée
-- (`journal_entry.post`, la permission que la 187 exige déjà au moment de valider).
-- La lecture, elle, reste ouverte — comme la 220 l'a établi pour cette même fonction.
--
-- Preuve : sql/223_bank_reconciliation_state_tests.sql — R09a à R09j vus rouges avant.
-- ============================================================

-- ------------------------------------------------------------
-- 1. L'état de rapprochement : ce que l'écran montre
--
-- `is_balanced` est conservé tel quel et documenté : vrai dès que les paires
-- pointées sont cohérentes (l'algèbre est une identité sur des paires justes),
-- c'est un contrôle d'intégrité — pas la réponse à « tout est-il pointé ? ».
-- Cette réponse est `is_reconciled` : aucun écart, ni au relevé ni au compte.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_bank_reconciliation_state(uuid, date);
CREATE FUNCTION get_bank_reconciliation_state(p_bank_account_id uuid, p_date date)
RETURNS TABLE (
  bank_account_id uuid,
  account_code text,
  statement_balance numeric,
  accounting_balance numeric,
  unmatched_debits numeric,
  unmatched_credits numeric,
  ledger_unmatched_debits numeric,
  ledger_unmatched_credits numeric,
  is_balanced boolean,
  unmatched_transactions json,
  ledger_unmatched_transactions json,
  reconciled_transactions json,
  difference numeric,
  explained_difference numeric,
  is_reconciled boolean,
  unmatched_count integer,
  ledger_unmatched_count integer,
  reconciled_count integer,
  statement_closing_balance numeric,
  closing_date date,
  closing_difference numeric,
  closing_matches boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_acc text;
  v_stmt numeric; v_book numeric;
  v_ud numeric; v_uc numeric; v_ld numeric; v_lc numeric;
  v_n_stmt int; v_n_ledger int; v_n_rec int;
  v_closing numeric; v_closing_date date; v_stmt_closing numeric;
BEGIN
  SELECT ba.account_code INTO v_acc
  FROM bank_accounts ba WHERE ba.id = p_bank_account_id AND ba.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compte bancaire introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  -- Côté RELEVÉ : les lignes importées jusqu'à la date, et celles qui ne sont
  -- pointées contre aucune écriture.
  SELECT COALESCE(sum(CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END), 0),
         COALESCE(sum(bt.amount) FILTER (WHERE bt.type = 'debit'  AND bt.reconciled_entry_id IS NULL), 0),
         COALESCE(sum(bt.amount) FILTER (WHERE bt.type = 'credit' AND bt.reconciled_entry_id IS NULL), 0),
         count(*) FILTER (WHERE bt.reconciled_entry_id IS NULL),
         count(*) FILTER (WHERE bt.reconciled_entry_id IS NOT NULL)
    INTO v_stmt, v_ud, v_uc, v_n_stmt, v_n_rec
  FROM bank_transactions bt
  WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
    AND bt.date <= p_date AND bt.kind = 'statement';

  -- Côté COMPTE 512x : le solde comptable, et les écritures non pointées.
  SELECT COALESCE(sum(jl.debit - jl.credit), 0),
         COALESCE(sum(jl.debit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0),
         count(*) FILTER (WHERE NOT COALESCE(jl.reconciled, false))
    INTO v_book, v_ld, v_lc, v_n_ledger
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = v_tid AND jl.account_code = v_acc
    AND je.status = 'posted' AND je.date <= p_date;

  -- Solde de clôture du relevé importé, s'il a été saisi (bank_accounts).
  -- La comparaison se fait à SA date : une clôture qui ne colle pas aux lignes
  -- importées jusqu'à cette date-là signale un relevé incomplet ou mal lu.
  SELECT ba.statement_balance, ba.statement_balance_date
    INTO v_closing, v_closing_date
  FROM bank_accounts ba
  WHERE ba.id = p_bank_account_id AND ba.tenant_id = v_tid
    AND ba.statement_balance IS NOT NULL AND ba.statement_balance_date IS NOT NULL;

  IF v_closing_date IS NOT NULL THEN
    SELECT COALESCE(sum(CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END), 0)
      INTO v_stmt_closing
    FROM bank_transactions bt
    WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
      AND bt.date <= v_closing_date AND bt.kind = 'statement';
  END IF;

  RETURN QUERY SELECT
    p_bank_account_id, v_acc, v_stmt, v_book, v_ud, v_uc, v_ld, v_lc,
    -- contrôle d'intégrité : les paires pointées des deux côtés se compensent
    (v_stmt - v_book) = (v_uc - v_ud) - (v_ld - v_lc),
-- écarts côté relevé
    (SELECT COALESCE(json_agg(row_to_json(x) ORDER BY x.date DESC, x.label), '[]'::json) FROM (
       SELECT bt.id, bt.date, bt.description AS label, bt.reference, bt.type,
              bt.amount AS raw_amount,
              CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END AS amount
       FROM bank_transactions bt
       WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
         AND bt.date <= p_date AND bt.kind = 'statement' AND bt.reconciled_entry_id IS NULL
    ) x),
    -- écarts côté compte 512x (chèques émis non débités, remises non créditées)
    (SELECT COALESCE(json_agg(row_to_json(y) ORDER BY y.date DESC, y.entry_number), '[]'::json) FROM (
       SELECT jl.id, je.date, je.number AS entry_number, je.description AS entry_label,
              jl.description AS label, jl.debit, jl.credit, (jl.debit - jl.credit) AS amount
       FROM journal_lines jl
       JOIN journal_entries je ON je.id = jl.journal_id
       WHERE jl.tenant_id = v_tid AND jl.account_code = v_acc
         AND je.status = 'posted' AND je.date <= p_date
         AND NOT COALESCE(jl.reconciled, false)
    ) y),
    -- pointages effectués (de quoi les défaire)
    (SELECT COALESCE(json_agg(row_to_json(z) ORDER BY z.date DESC, z.label), '[]'::json) FROM (
       SELECT bt.id, bt.date, bt.description AS label, bt.type, bt.amount AS raw_amount,
              CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END AS amount,
              bt.reconciled_entry_id, je.number AS entry_number, je.date AS entry_date,
              bt.match_type, bt.matched_account_code
       FROM bank_transactions bt
       LEFT JOIN journal_entries je ON je.id = bt.reconciled_entry_id AND je.tenant_id = bt.tenant_id
       WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
         AND bt.date <= p_date AND bt.kind = 'statement' AND bt.reconciled_entry_id IS NOT NULL
    ) z),
    v_stmt - v_book,
    (v_uc - v_ud) - (v_ld - v_lc),
    (v_n_stmt = 0 AND v_n_ledger = 0),
    v_n_stmt, v_n_ledger, v_n_rec,
    v_closing, v_closing_date,
    CASE WHEN v_closing IS NULL THEN NULL ELSE v_closing - v_stmt_closing END,
    CASE WHEN v_closing IS NULL THEN NULL ELSE v_closing = v_stmt_closing END;
END $$;
REVOKE ALL ON FUNCTION get_bank_reconciliation_state(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_bank_reconciliation_state(uuid, date) TO authenticated;

COMMENT ON FUNCTION get_bank_reconciliation_state(uuid, date) IS
  'État de rapprochement d''un compte bancaire à une date : soldes du relevé et du compte '
  '512x, écarts des deux côtés (unmatched_transactions, ledger_unmatched_transactions), '
  'pointages effectués, comparaison au solde de clôture du relevé importé. '
  'is_reconciled = plus aucun écart (l''état) ; is_balanced = intégrité des paires pointées '
  '(un contrôle, pas un état). Lecture STABLE, ouverte aux utilisateurs connectés (R-09, 223).';

-- ------------------------------------------------------------
-- 2. Pointage manuel — les DEUX côtés, comme le pointage automatique de la 196
--
-- L'écran « Rapprochement bancaire » posait `reconciled`/`matched` sur la ligne de
-- relevé seulement : l'état de rapprochement, qui lit `reconciled_entry_id` et
-- `journal_lines.reconciled`, ne voyait rien. Ici, le pointage écrit les deux
-- côtés et REFUSE tout ce qui n'est pas une paire juste : même société, même
-- compte du plan, même montant, même sens, écriture validée, lignes non pointées.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION reconcile_bank_statement_line(p_transaction_id uuid, p_journal_line_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tx record;
  v_jl record;
  v_acc text;
BEGIN
  IF NOT has_permission('journal_entry.update') THEN
    RAISE EXCEPTION 'Permission refusée : journal_entry.update' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT bt.* INTO v_tx FROM bank_transactions bt
  WHERE bt.id = p_transaction_id AND bt.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ligne de relevé introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_tx.kind <> 'statement' THEN
    RAISE EXCEPTION 'Cette ligne n''est pas une ligne de relevé (nature %) : le règlement saisi porte déjà son écriture',
      COALESCE(v_tx.kind, '?')
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_tx.reconciled_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ligne de relevé déjà pointée sur l''écriture %', v_tx.reconciled_entry_id
      USING ERRCODE = 'unique_violation';
  END IF;

  SELECT ba.account_code INTO v_acc FROM bank_accounts ba
  WHERE ba.id = COALESCE(v_tx.bank_account_id, v_tx.account_id) AND ba.tenant_id = v_tid;

  SELECT jl.id, jl.journal_id, jl.account_code, jl.debit, jl.credit,
         COALESCE(jl.reconciled, false) AS already,
         je.status, je.date AS entry_date, je.number AS entry_number
    INTO v_jl
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.id = p_journal_line_id AND jl.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ligne d''écriture introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_jl.status <> 'posted' THEN
    RAISE EXCEPTION 'Écriture % non validée : un pointage porte sur des écritures comptabilisées', v_jl.entry_number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_jl.account_code IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'La ligne d''écriture est au compte % et non au compte % du compte bancaire',
      v_jl.account_code, COALESCE(v_acc, '(non défini)')
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_jl.already THEN
    RAISE EXCEPTION 'Ligne d''écriture % déjà pointée', v_jl.entry_number USING ERRCODE = 'unique_violation';
  END IF;
  IF v_tx.type = 'credit' THEN
    IF v_jl.debit <> v_tx.amount OR v_jl.credit <> 0 THEN
      RAISE EXCEPTION 'Montant ou sens différents : relevé +% / écriture débit % crédit %',
        v_tx.amount, v_jl.debit, v_jl.credit USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    IF v_jl.credit <> v_tx.amount OR v_jl.debit <> 0 THEN
      RAISE EXCEPTION 'Montant ou sens différents : relevé −% / écriture débit % crédit %',
        v_tx.amount, v_jl.debit, v_jl.credit USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE journal_lines SET reconciled = true WHERE id = v_jl.id;
  UPDATE bank_transactions
     SET matched = true, reconciled = true, reconciled_entry_id = v_jl.journal_id,
         reconciled_at = now(), matched_account_code = v_acc, match_type = 'ledger_manual'
   WHERE id = v_tx.id;

  RETURN jsonb_build_object(
    'transaction_id', v_tx.id, 'journal_entry_id', v_jl.journal_id, 'journal_line_id', v_jl.id,
    'account_code', v_acc, 'amount', v_tx.amount,
    'entry_number', v_jl.entry_number, 'entry_date', v_jl.entry_date);
END $$;
REVOKE ALL ON FUNCTION reconcile_bank_statement_line(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reconcile_bank_statement_line(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION reconcile_bank_statement_line(uuid, uuid) IS
  'Pointe une ligne de relevé contre une ligne d''écriture du compte bancaire, des DEUX '
  'côtés (relevé et journal_lines.reconciled) — refuse tout ce qui n''est pas une paire '
  'juste. Exige journal_entry.update (R-09, 223).';

-- ------------------------------------------------------------
-- 3. Dépointage manuel — symétrique, et sur les mêmes deux côtés
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION unreconcile_bank_statement_line(p_transaction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tx record;
  v_acc text;
  v_cleared int := 0;
BEGIN
  IF NOT has_permission('journal_entry.update') THEN
    RAISE EXCEPTION 'Permission refusée : journal_entry.update' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT bt.* INTO v_tx FROM bank_transactions bt
  WHERE bt.id = p_transaction_id AND bt.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ligne de relevé introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_tx.kind <> 'statement' THEN
    RAISE EXCEPTION 'Cette ligne n''est pas une ligne de relevé (nature %)', COALESCE(v_tx.kind, '?')
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_tx.reconciled_entry_id IS NULL THEN
    RAISE EXCEPTION 'Ligne de relevé non pointée : il n''y a rien à défaire' USING ERRCODE = 'check_violation';
  END IF;

  SELECT ba.account_code INTO v_acc FROM bank_accounts ba
  WHERE ba.id = COALESCE(v_tx.bank_account_id, v_tx.account_id) AND ba.tenant_id = v_tid;

  -- L'écriture pointée rend sa ligne au compte : elle réapparaît dans les écarts.
  UPDATE journal_lines SET reconciled = false
   WHERE tenant_id = v_tid AND journal_id = v_tx.reconciled_entry_id
     AND account_code = v_acc AND COALESCE(reconciled, false);
  GET DIAGNOSTICS v_cleared = ROW_COUNT;

  UPDATE bank_transactions
     SET matched = false, reconciled = false, reconciled_entry_id = NULL,
         reconciled_at = NULL, match_type = NULL, matched_account_code = NULL
   WHERE id = v_tx.id;

  RETURN jsonb_build_object(
    'transaction_id', v_tx.id, 'journal_entry_id', v_tx.reconciled_entry_id,
    'account_code', v_acc, 'amount', v_tx.amount, 'ledger_lines_reopened', v_cleared);
END $$;
REVOKE ALL ON FUNCTION unreconcile_bank_statement_line(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION unreconcile_bank_statement_line(uuid) TO authenticated;

COMMENT ON FUNCTION unreconcile_bank_statement_line(uuid) IS
  'Défait un pointage des DEUX côtés : la ligne de relevé et la ligne d''écriture du '
  'compte bancaire reviennent dans les écarts. Exige journal_entry.update (R-09, 223).';

-- ------------------------------------------------------------
-- 4. « Comptabiliser » une ligne de relevé non pointée
--
-- Frais bancaires, agios… : la ligne existe au relevé, l'écriture n'existe pas.
-- L'écriture naît en brouillard puis est validée dans le même mouvement (les
-- gardes de la 187 s'appliquent, dont la permission journal_entry.post), et la
-- ligne de relevé est pointée des deux côtés sur l'écriture ainsi créée — un
-- frais comptabilisé n'est plus un écart.
--
-- Idempotence : refus explicite si la ligne est déjà pointée (sinon un second
-- appel écrirait la charge deux fois).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION post_bank_statement_line(
  p_transaction_id uuid,
  p_account_code text DEFAULT NULL,
  p_label text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tx record;
  v_acc text;
  v_journal text;
  v_counterpart text;
  v_label text;
  v_number text;
  v_je uuid;
  v_in boolean;
BEGIN
  IF NOT has_permission('journal_entry.post') THEN
    RAISE EXCEPTION 'Permission refusée : journal_entry.post' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT bt.* INTO v_tx FROM bank_transactions bt
  WHERE bt.id = p_transaction_id AND bt.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ligne de relevé introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_tx.kind <> 'statement' THEN
    RAISE EXCEPTION 'Cette ligne n''est pas une ligne de relevé (nature %) : elle porte déjà son écriture',
      COALESCE(v_tx.kind, '?')
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_tx.reconciled_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ligne de relevé déjà pointée : la comptabiliser de nouveau ferait un doublon'
      USING ERRCODE = 'unique_violation';
  END IF;
  IF COALESCE(v_tx.amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Montant nul ou négatif : il n''y a rien à comptabiliser' USING ERRCODE = 'check_violation';
  END IF;

  SELECT ba.account_code INTO v_acc FROM bank_accounts ba
  WHERE ba.id = COALESCE(v_tx.bank_account_id, v_tx.account_id) AND ba.tenant_id = v_tid;
  IF v_acc IS NULL THEN
    RAISE EXCEPTION 'Le compte bancaire n''a pas de compte comptable : renseignez-le avant de comptabiliser'
      USING ERRCODE = 'check_violation';
  END IF;

  v_in := v_tx.type = 'credit';
  -- 627000 (services bancaires) quand l'argent sort, 768000 (produits financiers)
  -- quand il entre ; l'écran peut choisir un autre compte, agios 661000 compris.
  v_counterpart := COALESCE(NULLIF(btrim(p_account_code), ''),
                            CASE WHEN v_in THEN '768000' ELSE '627000' END);
  IF v_counterpart = v_acc THEN
    RAISE EXCEPTION 'La contrepartie ne peut pas être le compte bancaire % lui-même', v_acc
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts ca WHERE ca.tenant_id = v_tid AND ca.code = v_counterpart) THEN
    RAISE EXCEPTION 'Compte % absent du plan comptable de la société', v_counterpart
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT j.code INTO v_journal FROM journals j
  WHERE j.tenant_id = v_tid AND j.type = 'bank' ORDER BY j.code LIMIT 1;
  v_journal := COALESCE(v_journal, 'OD');

  v_label := COALESCE(NULLIF(btrim(p_label), ''), NULLIF(btrim(v_tx.description), ''), 'Opération bancaire');
  v_number := 'COMPTA-BQ-' || upper(left(replace(v_tx.id::text, '-', ''), 12));

  -- 1. en-tête en brouillard (AUD-C02)
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_tx.date, v_journal, 'draft', v_label, v_number, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes : la charge (ou le produit) et la banque, du bon côté
  IF v_in THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_acc, v_label, v_tx.amount, 0, v_label),
           (v_tid, v_je, v_counterpart, v_label, 0, v_tx.amount, v_label);
  ELSE
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_counterpart, v_label, v_tx.amount, 0, v_label),
           (v_tid, v_je, v_acc, v_label, 0, v_tx.amount, v_label);
  END IF;

  -- 3. validation : les triggers de la 187 vérifient équilibre, exercice, comptes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  -- 4. la ligne du compte bancaire naît pointée : c'est un rapprochement,
  --    pas une écriture à rapprocher (mêmes deux côtés que la 196)
  UPDATE journal_lines SET reconciled = true
   WHERE journal_id = v_je AND tenant_id = v_tid AND account_code = v_acc;

  UPDATE bank_transactions
     SET matched = true, reconciled = true, reconciled_entry_id = v_je,
         reconciled_at = now(), matched_account_code = v_acc, match_type = 'ledger_posted'
   WHERE id = v_tx.id;

  RETURN jsonb_build_object(
    'transaction_id', v_tx.id, 'journal_entry_id', v_je, 'entry_number', v_number,
    'journal_code', v_journal, 'account_code', v_acc, 'counterpart_account', v_counterpart,
    'amount', v_tx.amount, 'direction', CASE WHEN v_in THEN 'in' ELSE 'out' END);
END $$;
REVOKE ALL ON FUNCTION post_bank_statement_line(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION post_bank_statement_line(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION post_bank_statement_line(uuid, text, text) IS
  'Comptabilise une ligne de relevé non pointée (frais bancaires, agios…) : écriture en '
  'brouillard puis validée, contrepartie 627000 au débit / 768000 au crédit (ou le compte '
  'choisi), ligne de relevé pointée des deux côtés. Refuse une ligne déjà pointée. '
  'Exige journal_entry.post (R-09, 223).';