-- ============================================================
-- 244_preserve_history_delete_guards.sql — SUP-01, SUP-02, SUP-03
--
-- Audit des modules hors comptabilité (23/09), § Suppressions. Trois défauts de
-- CLÉS ÉTRANGÈRES — mesurés sur base neuve à la 234 (migrations antérieures seules), scénarios T01 → T06 de
-- `244_preserve_history_delete_guards_tests.sql` :
--
--   SUP-01  `pay_slips.employee_id → employees` était en ON DELETE CASCADE :
--           supprimer un salarié effaçait ses bulletins de paie (T01 :
--           « bulletins restants = 0 »). Un document de paie est un document
--           comptable : il porte le brut, les cotisations, le net et, depuis la
--           212, l'écriture de paie rattachée.
--   SUP-02  `bank_transactions.account_id → bank_accounts` était en CASCADE :
--           supprimer un compte bancaire effaçait TOUTES ses opérations (T03),
--           y compris celles déjà rapprochées de leur écriture de règlement.
--   SUP-03  `stock_movements.product_id → products` était en CASCADE :
--           supprimer un article effaçait son historique de mouvements (T05),
--           donc la trace des entrées et sorties qui ont valu ses écritures.
--   (même famille) `pay_slips.pay_run_id → pay_runs` est en CASCADE : supprimer
--           un lot de paie calculé efface ses bulletins (T08). L'écran propose
--           bien « Supprimer le lot » (payroll.ts:60).
--
-- CORRECTIFS — deux réponses différentes, parce que les deux situations ne sont
-- pas de même nature :
--
--   1. Un salarié ou un compte bancaire ne se supprime pas quand il porte de
--      l'histoire : la suppression est REFUSÉE, avec un message qui dit quoi
--      faire (passer la fiche en inactif, garder le compte). On ne peut pas
--      « délier » un bulletin de paie de son salarié (la colonne est NOT NULL)
--      ni détacher une opération de son compte sans casser le rapprochement.
--
--      L'effacement d'une société entière (`DELETE FROM tenants`, celui du plan
--      de retour arrière et des jeux de test) reste possible : la ligne de
--      `tenants` n'existe plus quand le déclencheur s'exécute, et la garde le
--      voit — c'est le seul cas où l'historique part avec la société.
--
--   2. Un article se supprime, mais son HISTORIQUE SURVIT : la clé étrangère
--      passe en ON DELETE SET NULL, comme le font déjà `journal_lines`,
--      `invoice_lines` et `purchase_invoice_lines` pour les mêmes raisons. Le
--      mouvement garde sa quantité, son coût, son dépôt, sa date et sa
--      référence ; seul le lien vers l'article disparaît (T05).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Salariés et comptes bancaires : un garde qui explique (SUP-01, SUP-02)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION preserve_history_delete_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n int;
  v_releves int;
BEGIN
  -- Effacement d'une société : la ligne de `tenants` est déjà supprimée quand
  -- les cascades s'exécutent. C'est le seul effacement d'historique voulu.
  IF NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id = OLD.tenant_id) THEN
    RETURN OLD;
  END IF;

  IF TG_TABLE_NAME = 'employees' THEN
    SELECT count(*) INTO v_n
    FROM pay_slips ps
    WHERE ps.employee_id = OLD.id AND ps.tenant_id = OLD.tenant_id;

    IF v_n > 0 THEN
      -- `to_jsonb(OLD)` plutôt que `OLD.name` : la fonction est branchée sur
      -- trois tables, et plpgsql_check résout les champs colonne par colonne
      -- (c'est déjà le motif des gardes de 190 et 192).
      RAISE EXCEPTION 'Salarié % : % bulletin(s) de paie rattaché(s). La suppression effacerait des documents de paie — passez la fiche en « inactif ».',
        to_jsonb(OLD)->>'name', v_n
        USING ERRCODE = 'check_violation';
    END IF;

  ELSIF TG_TABLE_NAME = 'bank_accounts' THEN
    SELECT count(*) INTO v_n
    FROM bank_transactions bt
    WHERE bt.account_id = OLD.id AND bt.tenant_id = OLD.tenant_id;

    SELECT count(*) INTO v_releves
    FROM bank_statement_imports bsi
    WHERE bsi.bank_account_id = OLD.id AND bsi.tenant_id = OLD.tenant_id;

    IF v_n > 0 OR v_releves > 0 THEN
      RAISE EXCEPTION 'Compte bancaire % : % opération(s) et % relevé(s) importé(s) rattaché(s). La suppression effacerait des opérations bancaires (dont les rapprochements) — conservez le compte.',
        to_jsonb(OLD)->>'name', v_n, v_releves
        USING ERRCODE = 'check_violation';
    END IF;

  ELSIF TG_TABLE_NAME = 'pay_runs' THEN
    -- Même famille que SUP-01, un cran au-dessus : `pay_slips.pay_run_id` est
    -- en CASCADE, donc supprimer un lot de paie calculé efface ses bulletins.
    SELECT count(*) INTO v_n
    FROM pay_slips ps
    WHERE ps.pay_run_id = OLD.id AND ps.tenant_id = OLD.tenant_id;

    IF v_n > 0 THEN
      RAISE EXCEPTION 'Lot de paie % (% bulletin(s) — statut %) : la suppression effacerait les bulletins du lot. Annulez le lot, ou laissez-le en place.',
        to_jsonb(OLD)->>'number', v_n, to_jsonb(OLD)->>'status'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS preserve_history_delete_guard_employees ON employees;
CREATE TRIGGER preserve_history_delete_guard_employees
  BEFORE DELETE ON employees
  FOR EACH ROW EXECUTE FUNCTION preserve_history_delete_guard();

DROP TRIGGER IF EXISTS preserve_history_delete_guard_bank_accounts ON bank_accounts;
CREATE TRIGGER preserve_history_delete_guard_bank_accounts
  BEFORE DELETE ON bank_accounts
  FOR EACH ROW EXECUTE FUNCTION preserve_history_delete_guard();

DROP TRIGGER IF EXISTS preserve_history_delete_guard_pay_runs ON pay_runs;
CREATE TRIGGER preserve_history_delete_guard_pay_runs
  BEFORE DELETE ON pay_runs
  FOR EACH ROW EXECUTE FUNCTION preserve_history_delete_guard();

-- ------------------------------------------------------------
-- 2. L'historique d'un article survit à sa suppression (SUP-03)
-- ------------------------------------------------------------
ALTER TABLE stock_movements DROP CONSTRAINT IF EXISTS stock_movements_product_id_fkey;
ALTER TABLE stock_movements
  ADD CONSTRAINT stock_movements_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

COMMENT ON CONSTRAINT stock_movements_product_id_fkey ON stock_movements IS
  'SUP-03 : l''historique des mouvements survit à la suppression d''un article (ON DELETE SET NULL, comme journal_lines, invoice_lines et purchase_invoice_lines).';

REVOKE ALL ON FUNCTION preserve_history_delete_guard() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION preserve_history_delete_guard() TO service_role;
