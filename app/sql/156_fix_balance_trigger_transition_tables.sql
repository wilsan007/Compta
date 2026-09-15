-- Migration 156 : Corrige le bug du trigger d'équilibre qui référence old_table
-- sur le trigger INSERT (qui ne déclare que new_table).
-- Symptôme : "relation old_table does not exist" lors de toute insertion de ligne d'écriture.
-- Solution : 3 fonctions séparées, une par opération, chacune ne référençant que les
-- tables de transition réellement déclarées par son trigger.

-- 1) Fonction pour INSERT (new_table uniquement)
CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_ins()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_je_id uuid;
  v_total_debit numeric;
  v_total_credit numeric;
  v_affected_je_ids uuid[];
BEGIN
  SELECT ARRAY_agg(DISTINCT journal_id) INTO v_affected_je_ids
  FROM new_table;

  FOREACH v_je_id IN ARRAY v_affected_je_ids
  LOOP
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_total_debit, v_total_credit
    FROM journal_lines
    WHERE journal_id = v_je_id;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %',
        v_je_id, v_total_debit, v_total_credit;
    END IF;

    UPDATE journal_entries
    SET total_debit = v_total_debit, total_credit = v_total_credit, updated_at = now()
    WHERE id = v_je_id;
  END LOOP;

  RETURN NULL;
END;
$function$;

-- 2) Fonction pour UPDATE (old_table + new_table)
CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_upd()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_je_id uuid;
  v_total_debit numeric;
  v_total_credit numeric;
  v_affected_je_ids uuid[];
BEGIN
  SELECT ARRAY_agg(DISTINCT journal_id) INTO v_affected_je_ids
  FROM (
    SELECT journal_id FROM new_table
    UNION
    SELECT journal_id FROM old_table
  ) AS combined;

  FOREACH v_je_id IN ARRAY v_affected_je_ids
  LOOP
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_total_debit, v_total_credit
    FROM journal_lines
    WHERE journal_id = v_je_id;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %',
        v_je_id, v_total_debit, v_total_credit;
    END IF;

    UPDATE journal_entries
    SET total_debit = v_total_debit, total_credit = v_total_credit, updated_at = now()
    WHERE id = v_je_id;
  END LOOP;

  RETURN NULL;
END;
$function$;

-- 3) Fonction pour DELETE (old_table uniquement)
CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_del()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_je_id uuid;
  v_total_debit numeric;
  v_total_credit numeric;
  v_affected_je_ids uuid[];
BEGIN
  SELECT ARRAY_agg(DISTINCT journal_id) INTO v_affected_je_ids
  FROM old_table;

  FOREACH v_je_id IN ARRAY v_affected_je_ids
  LOOP
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_total_debit, v_total_credit
    FROM journal_lines
    WHERE journal_id = v_je_id;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %',
        v_je_id, v_total_debit, v_total_credit;
    END IF;

    UPDATE journal_entries
    SET total_debit = v_total_debit, total_credit = v_total_credit, updated_at = now()
    WHERE id = v_je_id;
  END LOOP;

  RETURN NULL;
END;
$function$;

-- 4) Reconstruire les 3 triggers avec leurs fonctions dédiées
DROP TRIGGER IF EXISTS check_journal_entry_balance_ins ON public.journal_lines;
DROP TRIGGER IF EXISTS check_journal_entry_balance_upd ON public.journal_lines;
DROP TRIGGER IF EXISTS check_journal_entry_balance_del ON public.journal_lines;

CREATE TRIGGER check_journal_entry_balance_ins
  AFTER INSERT ON public.journal_lines
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION check_journal_entry_balance_ins();

CREATE TRIGGER check_journal_entry_balance_upd
  AFTER UPDATE ON public.journal_lines
  REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION check_journal_entry_balance_upd();

CREATE TRIGGER check_journal_entry_balance_del
  AFTER DELETE ON public.journal_lines
  REFERENCING OLD TABLE AS old_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION check_journal_entry_balance_del();

-- 5) Nettoyer l'ancienne fonction partagée (plus référencée)
DROP FUNCTION IF EXISTS public.check_journal_entry_balance_stmt();
