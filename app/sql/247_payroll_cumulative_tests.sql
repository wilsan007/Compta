-- ============================================================
-- 247_payroll_cumulative_tests.sql — RH : les cumuls de paie et le pont vers
-- la comptabilité
--
-- Deux tables portent une logique SQL que nul scénario n'avait traversée
-- (doc/audit/COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md § 3) :
--   `payroll_cumulative`        — les cumuls annuels, écrits par calculate_payslip
--                                 et relus par le bulletin suivant : « une erreur
--                                 s'y propage sur toute l'année » ;
--   `payroll_accounting_entries` — le pont paie → comptabilité, tenu à part de
--                                 l'écriture elle-même.
--
-- Bulletin type : salarié à 3 000 de brut mensuel, paramètres légaux FR semés
-- (PMSS 3 925, CSG 6,80 + 2,40, CRDS 0,50 sur 98,25 % du brut).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '247', false);
DELETE FROM _audit_results WHERE file = '247';

-- Salarié payé au mois, sans grille : calculate_payslip suffit à produire un
-- bulletin et à écrire le cumul du mois.
CREATE OR REPLACE FUNCTION _cum_employee(p_t uuid, p_name text, p_salary numeric DEFAULT 3000)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO employees (tenant_id, name, email, status, base_salary, salary, hire_date, employee_number)
  VALUES (p_t, p_name, 'sal' || replace(left(uuid_generate_v4()::text, 8), '-', '') || '@audit.test', 'active',
          p_salary, p_salary, '2025-01-01', 'M-' || left(uuid_generate_v4()::text, 5))
  RETURNING id INTO e;
  RETURN e;
END $$;


-- Lot de paie approuvé d'un bulletin type (brut 3 000, net 2 340, patronales 1 260),
-- repris de la 181 sous un nom propre à ce fichier.
CREATE OR REPLACE FUNCTION _mk_pay_run_247(p_t uuid, p_number text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_number, '2026-03-01', '2026-03-31', '2026-03-31', 'draft', 3000, 660, 2340, 1)
  RETURNING id INTO r;
  e := _cum_employee(p_t, 'Salarie ' || p_number);
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
    gross_salary, total_gross, social_security_employee, income_tax, other_deductions, total_deductions,
    net_salary, employer_contributions, status, calc_inputs)
  VALUES (p_t, p_number || '-BS', r, e, '2026-03-01', '2026-03-31',
    3000, 3000, 400, 60, 200, 660, 2340, 1260, 'draft',
    '{"csgDeductible": 120, "csgNonDeductible": 60, "crds": 20, "advanceDeduction": 0, "otherDeductions": 0}');
  UPDATE pay_runs SET status = 'approved' WHERE id = r;
  RETURN r;
END $$;

-- C01 — repère : le cumul annuel s'additionne mois après mois et le bulletin de
-- mars connaît les deux mois précédents.
DO $$
DECLARE t uuid := _mk_tenant('CUM01'); e uuid; r jsonb; n int; cum numeric;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _cum_employee(t, 'Salarie A');
    PERFORM calculate_payslip(e, '2026-01');
    PERFORM calculate_payslip(e, '2026-02');
    r := calculate_payslip(e, '2026-03');
    SELECT count(*), COALESCE(sum(gross), 0) INTO n, cum FROM payroll_cumulative WHERE tenant_id = t AND employee_id = e;
    PERFORM _rec('C01', 'trois bulletins : trois lignes de cumul, 9 000 au total, cumul connu du bulletin de mars = 6 000',
      n = 3 AND cum = 9000 AND (r->>'cumulative_gross_ytd')::numeric = 9000,
      format('%s ligne(s), cumul %s, YTD rendu par mars %s', n, cum, r->>'cumulative_gross_ytd'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C01', 'trois bulletins : trois lignes de cumul, 9 000 au total, cumul connu du bulletin de mars = 6 000', false, SQLERRM); END;
END $$;

-- C02 — recalculer un mois ne double pas son cumul.
DO $$
DECLARE t uuid := _mk_tenant('CUM02'); e uuid; n int; cum numeric;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _cum_employee(t, 'Salarie B');
    PERFORM calculate_payslip(e, '2026-01');
    PERFORM calculate_payslip(e, '2026-01');
    PERFORM calculate_payslip(e, '2026-01');
    SELECT count(*), COALESCE(sum(gross), 0) INTO n, cum FROM payroll_cumulative WHERE tenant_id = t AND employee_id = e;
    PERFORM _rec('C02', 'janvier recalculé trois fois : une ligne de cumul, 3 000',
      n = 1 AND cum = 3000, format('%s ligne(s), cumul %s', n, cum));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C02', 'janvier recalculé trois fois : une ligne de cumul, 3 000', false, SQLERRM); END;
END $$;

-- C03 — chemin d'annulation : un bulletin supprimé laisse-t-il son cumul ?
-- Le cumul sert d'assiette au mois suivant (plafond, régularisation
-- progressive) : un bulletin retiré qui y reste fausse toute la fin d'année.
DO $$
DECLARE t uuid := _mk_tenant('CUM03'); e uuid; r jsonb; reste numeric; ytd numeric;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _cum_employee(t, 'Salarie C');
    PERFORM calculate_payslip(e, '2026-01');
    PERFORM calculate_payslip(e, '2026-02');
    DELETE FROM pay_slips WHERE tenant_id = t AND employee_id = e
      AND period_start = '2026-02-01';
    SELECT COALESCE(sum(gross), 0) INTO reste FROM payroll_cumulative WHERE tenant_id = t AND employee_id = e;
    r := calculate_payslip(e, '2026-03');
    ytd := (r->>'cumulative_gross_ytd')::numeric;
    PERFORM _rec('C03', 'bulletin de février supprimé : son cumul part avec lui (reste 3 000, mars cumule 6 000)',
      reste = 3000 AND ytd = 6000,
      format('cumul restant après suppression = %s (attendu 3 000) ; YTD de mars = %s (attendu 6 000)', reste, ytd));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C03', 'bulletin de février supprimé : son cumul part avec lui (reste 3 000, mars cumule 6 000)', false, SQLERRM); END;
END $$;

-- C04 — upsert_payroll_cumulative n'est qu'un rouage de calculate_payslip, et
-- pourtant tout utilisateur connecté peut l'exécuter : il réécrit alors le
-- cumul annuel d'un salarié sans bulletin, sans droit de paie et sans trace.
DO $$
DECLARE t uuid := _mk_tenant('CUM04'); e uuid; ecrit numeric; refuse boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    e := _cum_employee(t, 'Salarie D');
    PERFORM calculate_payslip(e, '2026-01');
    BEGIN
      PERFORM upsert_payroll_cumulative(e, 2026, 1, 999999, 999999, 3925, 0, 999999, 999999, 0, 0, 0, 0, 0, 0, 0);
    EXCEPTION WHEN OTHERS THEN refuse := true; END;
    SELECT gross INTO ecrit FROM payroll_cumulative WHERE tenant_id = t AND employee_id = e AND year = 2026 AND month = 1;
    PERFORM _rec('C04', 'écrire un cumul sans passer par un bulletin est refusé (le cumul reste à 3 000)',
      refuse AND ecrit = 3000, format('refus=%s ; cumul après l''appel direct = %s', refuse, ecrit));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C04', 'écrire un cumul sans passer par un bulletin est refusé (le cumul reste à 3 000)', false, SQLERRM); END;
END $$;

-- C05 — le pont paie → comptabilité porte les totaux de l'écriture qu'il annonce.
DO $$
DECLARE t uuid := _mk_tenant('CUM05'); r uuid; res jsonb; p record; v record;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run_247(t, 'PRC5');
    res := post_payroll_journal(r);
    SELECT gross_total, net_total, employer_contributions_total, employee_deductions_total, status, journal_entry_id
      INTO p FROM payroll_accounting_entries WHERE tenant_id = t AND pay_run_id = r;
    SELECT sum(debit) FILTER (WHERE account_code = '641000') d641,
           sum(credit) FILTER (WHERE account_code = '421000') c421
      INTO v FROM journal_lines WHERE journal_id = p.journal_entry_id;
    PERFORM _rec('C05', 'pont paie → compta : brut 3 000 et net 2 340 identiques à l''écriture, statut « transferred »',
      p.gross_total = 3000 AND p.net_total = 2340 AND p.employer_contributions_total = 1260
        AND p.status = 'transferred' AND p.journal_entry_id = (res->>'entry_id')::uuid
        AND v.d641 = p.gross_total AND v.c421 = p.net_total,
      format('pont brut=%s net=%s patronales=%s salariales=%s statut=%s ; écriture D641=%s C421=%s',
             p.gross_total, p.net_total, p.employer_contributions_total, p.employee_deductions_total, p.status, v.d641, v.c421));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C05', 'pont paie → compta : brut 3 000 et net 2 340 identiques à l''écriture, statut « transferred »', false, SQLERRM); END;
END $$;

-- C06 — chemin d'annulation du pont. La contrainte CHECK admet le statut
-- « cancelled » et `payroll_post_run` s'en sert comme clé d'idempotence
-- (`status <> 'cancelled'`), mais aucune ligne de code ne l'écrivait : annuler
-- un lot déjà comptabilisé laissait le pont à « transferred » et l'écriture au
-- grand livre.
--
-- CE QUE LA MESURE A CORRIGÉ DANS CE SCÉNARIO (24/09). La première rédaction
-- exigeait `journal_entries.status <> 'posted'` sur l'écriture d'origine — et
-- elle restait ROUGE alors que la 248 fait exactement ce qu'il faut. Le noyau de
-- saisie interdit de modifier une écriture validée
-- (`prevent_posted_entry_modification` : « immuable. Utiliser l'extourne pour
-- annuler. ») et la contrainte CHECK de `journal_entries.status` n'admet que
-- `draft` et `posted` : l'annulation comptable passe par une **contrepassation**,
-- jamais par une réécriture. L'assertion porte donc sur ce qui doit être vrai :
-- le pont passe à « cancelled », une écriture inverse est portée au journal PAIE,
-- ses lignes sont le miroir exact de l'originale, les bulletins sont déverrouillés
-- (`journal_posted = false`) — et l'écriture d'origine reste intacte, c'est la
-- valeur probante. Exiger l'inverse demandait au schéma ce qu'il interdit.
DO $$
DECLARE
  t uuid := _mk_tenant('CUM06'); r uuid; res jsonb; p record; v_orig record; v_rev record;
  v_ecarts int; v_slips int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run_247(t, 'PRC6');
    res := post_payroll_journal(r);
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT status, journal_entry_id INTO p FROM payroll_accounting_entries
    WHERE tenant_id = t AND pay_run_id = r;

    SELECT * INTO v_orig FROM journal_entries WHERE id = (res->>'entry_id')::uuid;
    SELECT * INTO v_rev FROM journal_entries
    WHERE tenant_id = t AND reference = 'PAYROLL-REV-PRC6';

    -- Le miroir, compte par compte : ce que l'originale débite, la contrepassation
    -- le crédite — et réciproquement. Un compte absent d'un côté est un écart.
    SELECT count(*) INTO v_ecarts
    FROM (
      SELECT l.account_code, sum(l.debit) AS d, sum(l.credit) AS c
      FROM journal_lines l WHERE l.journal_id = v_orig.id GROUP BY l.account_code
    ) o
    FULL JOIN (
      SELECT l.account_code, sum(l.debit) AS d, sum(l.credit) AS c
      FROM journal_lines l WHERE l.journal_id = v_rev.id GROUP BY l.account_code
    ) e ON e.account_code = o.account_code
    WHERE COALESCE(e.d, 0) <> COALESCE(o.c, 0) OR COALESCE(e.c, 0) <> COALESCE(o.d, 0)
       OR o.account_code IS NULL OR e.account_code IS NULL;

    SELECT count(*) INTO v_slips FROM pay_slips WHERE pay_run_id = r AND journal_posted;

    PERFORM _rec('C06', 'lot de paie annulé après comptabilisation : contrepassation au journal PAIE, pont à « cancelled », originale intacte',
      p.status = 'cancelled'
        AND v_orig.status = 'posted'
        AND v_rev.id IS NOT NULL AND v_rev.status = 'posted' AND v_rev.journal_code = 'PAIE'
        AND v_ecarts = 0
        AND v_slips = 0,
      format('pont=%s | originale %s=%s (immuable, valeur probante) | contrepassation %s trouvée=%s statut=%s écarts de miroir=%s | bulletins encore « comptabilisés »=%s',
             p.status, v_orig.number, v_orig.status, COALESCE(v_rev.number, '—'), v_rev.id IS NOT NULL,
             COALESCE(v_rev.status, '—'), v_ecarts, v_slips));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C06', 'lot de paie annulé après comptabilisation : contrepassation au journal PAIE, pont à « cancelled », originale intacte',
      false, SQLERRM);
  END;
END $$;

-- C07 — annuler deux fois ne contrepasse qu'une fois. La garde d'idempotence de
-- `payroll_reverse_posted_run` (référence `PAYROLL-REV-<lot>` déjà présente) doit
-- tenir même si le déclencheur repart : un lot remis en « approved » puis annulé
-- de nouveau ne doit pas produire une seconde écriture inverse — sans quoi le
-- grand livre porterait l'annulation en double.
DO $$
DECLARE t uuid := _mk_tenant('CUM07'); r uuid; res jsonb; v_avant int; v_apres int; v_pont text;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run_247(t, 'PRC7');
    res := post_payroll_journal(r);
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;
    SELECT count(*) INTO v_avant FROM journal_entries
    WHERE tenant_id = t AND reference = 'PAYROLL-REV-PRC7';

    UPDATE pay_runs SET status = 'approved' WHERE id = r;
    UPDATE pay_runs SET status = 'cancelled' WHERE id = r;

    SELECT count(*) INTO v_apres FROM journal_entries
    WHERE tenant_id = t AND reference = 'PAYROLL-REV-PRC7';
    SELECT status INTO v_pont FROM payroll_accounting_entries WHERE tenant_id = t AND pay_run_id = r;

    PERFORM _rec('C07', 'annuler deux fois un lot comptabilisé ne contrepasse qu''une fois',
      v_avant = 1 AND v_apres = 1 AND v_pont = 'cancelled',
      format('contrepassations après la 1re annulation=%s, après la 2e=%s (attendu 1 et 1), pont=%s',
             v_avant, v_apres, v_pont));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C07', 'annuler deux fois un lot comptabilisé ne contrepasse qu''une fois', false, SQLERRM);
  END;
END $$;

SELECT _audit_assert('247');
