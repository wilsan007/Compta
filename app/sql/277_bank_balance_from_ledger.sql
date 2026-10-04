-- ============================================================
-- 277_bank_balance_from_ledger.sql — vague X6 / M3 : le solde bancaire
-- (audit fonctionnel exécuté du 28/09/2026 ; décision D-F du plan)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran :
--   S02b le solde initial saisi à la création (1 000) n'était comptabilisé nulle
--        part : la balance, le bilan et le FEC ignoraient 1 000 € que l'écran affichait ;
--   S06e l'écran affichait `balance`, que RIEN ne met à jour : 1 000 affichés pour
--        2 357,10 encaissés au 512.
--   Et `calculated_balance`, présenté comme « le solde comptable », était en fait
--   la somme des mouvements bancaires de type « book » — pas le grand livre.
--
-- LE CORRECTIF (D-F : les deux soldes côte à côte, le comptable comme référence)
--   1. `calculated_balance` = solde du compte 512x du GRAND LIVRE (écritures
--      validées), recalculé à chaque validation d'écriture qui touche le compte ;
--      `reconciliation_diff` = solde du dernier relevé − solde comptable.
--   2. Le solde initial saisi à la création devient une écriture d'À-NOUVEAU
--      validée : journal AN, date de début de l'exercice en cours, 512x / 890000
--      « Bilan d'ouverture » (compte ajouté au plan de la société s'il manque) —
--      refusée si l'exercice porte déjà un à-nouveau sur ce compte.
--   3. `balance` n'est plus lue ni affichée : elle garde le solde d'ouverture saisi.
--
-- Suite : `277_bank_balance_from_ledger_tests.sql`.
-- ============================================================

CREATE OR REPLACE FUNCTION public.refresh_bank_account_balance(p_account uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  UPDATE bank_accounts ba
     SET calculated_balance = l.solde,
         reconciliation_diff = CASE WHEN ba.statement_balance_date IS NOT NULL
                                    THEN coalesce(ba.statement_balance, 0) - l.solde ELSE 0 END,
         updated_at = now()
    FROM (
      SELECT b.id, b.tenant_id, coalesce((
        SELECT sum(jl.debit - jl.credit)
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = b.tenant_id
        WHERE jl.tenant_id = b.tenant_id AND je.status = 'posted'
          AND coalesce(jl.account_general, jl.account_code) = b.account_code), 0) AS solde
      FROM bank_accounts b WHERE b.id = p_account
    ) l
   WHERE ba.tenant_id = l.tenant_id AND ba.id = l.id AND ba.id = p_account
$$;
REVOKE EXECUTE ON FUNCTION public.refresh_bank_account_balance(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON COLUMN public.bank_accounts.calculated_balance IS
  'X6/M3 (277, D-F) : solde du compte 512x au grand livre (écritures validées) — la référence de tous les états.';
COMMENT ON COLUMN public.bank_accounts.balance IS
  'X6/M3 (277) : solde d''ouverture saisi à la création (comptabilisé en à-nouveau). Ni lu ni affiché : voir calculated_balance.';

-- Une écriture validée qui touche un compte bancaire met son solde à jour
CREATE OR REPLACE FUNCTION public.journal_entry_refresh_bank_balances()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE r record;
BEGIN
  IF NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted' THEN
    FOR r IN
      SELECT DISTINCT b.id FROM bank_accounts b
      JOIN journal_lines jl ON jl.tenant_id = b.tenant_id AND jl.journal_id = NEW.id
       AND coalesce(jl.account_general, jl.account_code) = b.account_code
      WHERE b.tenant_id = NEW.tenant_id
    LOOP
      PERFORM refresh_bank_account_balance(r.id);
    END LOOP;
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.journal_entry_refresh_bank_balances() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_journal_entry_refresh_bank_balances ON public.journal_entries;
CREATE TRIGGER tg_journal_entry_refresh_bank_balances
  AFTER UPDATE OF status ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.journal_entry_refresh_bank_balances();

-- Le solde initial saisi devient une écriture d'à-nouveau
CREATE OR REPLACE FUNCTION public.bank_account_post_opening_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_amount numeric := round(coalesce(NEW.balance, 0), 2);
  v_entry uuid;
  v_number text;
BEGIN
  IF v_amount = 0 THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND current_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_fy FROM fiscal_years
    WHERE tenant_id = NEW.tenant_id AND status NOT IN ('closed', 'locked')
    ORDER BY start_date DESC LIMIT 1;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solde initial de % : aucun exercice ouvert pour le comptabiliser — créez l''exercice, ou créez le compte avec un solde nul',
      NEW.name USING ERRCODE = 'check_violation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
    WHERE je.tenant_id = NEW.tenant_id AND je.journal_code = 'AN' AND je.fiscal_year_id = v_fy.id
      AND coalesce(jl.account_general, jl.account_code) = NEW.account_code) THEN
    RAISE EXCEPTION 'L''exercice % porte déjà un à-nouveau sur le compte % : pas de double ouverture',
      v_fy.code, NEW.account_code USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO journals (tenant_id, code, name, type, status, locked, next_number)
  VALUES (NEW.tenant_id, 'AN', 'À-nouveaux', 'general', 'active', false, 1)
  ON CONFLICT (tenant_id, code) DO NOTHING;
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, '890000', 'Bilan d''ouverture', 'equity')
  ON CONFLICT (tenant_id, code) DO NOTHING;

  v_number := get_next_piece_number('AN');
  INSERT INTO journal_entries (tenant_id, number, piece_number, date, journal_code, status, description, reference)
  VALUES (NEW.tenant_id, v_number, v_number, v_fy.start_date, 'AN', 'draft',
          'Solde d''ouverture — ' || coalesce(NEW.name, NEW.account_code), 'BANK-OPEN-' || NEW.id)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  VALUES
    (NEW.tenant_id, v_entry, NEW.account_code, NEW.account_code, coalesce(NEW.name, 'Banque'),
     greatest(v_amount, 0), greatest(-v_amount, 0), 'Solde d''ouverture', 0),
    (NEW.tenant_id, v_entry, '890000', '890000', 'Bilan d''ouverture',
     greatest(-v_amount, 0), greatest(v_amount, 0), 'Solde d''ouverture', 1);
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;   -- le noyau valide (et rafraîchit le solde)
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.bank_account_post_opening_balance() FROM PUBLIC, anon, authenticated;

-- après `tg_bank_account_journal` (le journal de banque existe) : ordre des noms
DROP TRIGGER IF EXISTS tg_bank_account_opening ON public.bank_accounts;
CREATE TRIGGER tg_bank_account_opening
  AFTER INSERT ON public.bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.bank_account_post_opening_balance();

-- Rattrapage : tous les soldes comptables recalculés depuis le grand livre
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM bank_accounts LOOP
    PERFORM refresh_bank_account_balance(r.id); n := n + 1;
  END LOOP;
  RAISE NOTICE '[X6/M3] % compte(s) bancaire(s) : solde comptable relu au grand livre', n;
END $$;
