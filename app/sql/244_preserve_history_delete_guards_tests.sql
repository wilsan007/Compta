-- ============================================================
-- 244_preserve_history_delete_guards_tests.sql — SUP-01, SUP-02, SUP-03
--
-- Audit des modules hors comptabilité (23/09), § Suppressions. Les trois
-- défauts sont structurels — ils tiennent aux clés étrangères, pas au code :
--
--   SUP-01  `pay_slips.employee_id → employees ON DELETE CASCADE` : supprimer
--           un salarié efface ses bulletins de paie. Un document de paie
--           (montants, cotisations, écriture rattachée) disparaît sans trace.
--           Même famille un cran au-dessus : un lot de paie emporte ses bulletins
--           (`pay_slips.pay_run_id` est aussi en CASCADE), d'où T08 et T09.
--   SUP-02  `bank_transactions.account_id → bank_accounts ON DELETE CASCADE` :
--           supprimer un compte bancaire efface TOUTES ses opérations, y
--           compris les lignes rapprochées et leur écriture de règlement.
--   SUP-03  `stock_movements.product_id → products ON DELETE CASCADE` :
--           supprimer un article efface son historique de mouvements, donc la
--           trace des entrées et sorties qui ont valu ses écritures de stock.
--
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), AVANT la 244 : T01, T03, T05 et T08 rouges (la
-- suppression passe et le document a disparu), T02, T04 et T06 verts d'emblée
-- — ils gardent qu'une suppression légitime reste possible.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '244', false);
DELETE FROM _audit_results WHERE file = '244';

-- T01 — SUP-01 : un salarié qui a des bulletins de paie ne se supprime pas
DO $$
DECLARE t uuid; e uuid; r uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T01');
  INSERT INTO employees (tenant_id, name, status) VALUES (t, 'Salarié Payé T01', 'active') RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-T01', '2026-03-01', '2026-03-31', '2026-03-31', 'approved') RETURNING id INTO r;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status)
    VALUES (t, 'BS-T01', r, e, '2026-03-01', '2026-03-31', 'draft');
  PERFORM _as_user();
  BEGIN
    DELETE FROM employees WHERE id = e;
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pay_slips WHERE employee_id = e;
  PERFORM _rec('T01', 'supprimer un salarié qui a un bulletin de paie : refusé, le bulletin reste',
    ok AND n = 1 AND err LIKE '%bulletin%',
    format('refusé=%s bulletins restants=%s (1 attendu) | %s', ok, n, left(err, 80)));
END $$;

-- T02 — SUP-01 : un salarié sans bulletin se supprime toujours
DO $$
DECLARE t uuid; e uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T02');
  INSERT INTO employees (tenant_id, name, status) VALUES (t, 'Salarié Sans Paie T02', 'active') RETURNING id INTO e;
  PERFORM _as_user();
  BEGIN
    DELETE FROM employees WHERE id = e;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM employees WHERE id = e;
  PERFORM _rec('T02', 'supprimer un salarié sans bulletin : toujours possible',
    ok AND n = 0, format('supprimé=%s fiches restantes=%s (0 attendue) | %s', ok, n, left(err, 60)));
END $$;

-- T03 — SUP-02 : un compte bancaire qui a des opérations ne se supprime pas
DO $$
DECLARE t uuid; b uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T03');
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Compte T03', 'chequing') RETURNING id INTO b;
  INSERT INTO bank_transactions (tenant_id, account_id, date, description, type, amount)
    VALUES (t, b, CURRENT_DATE, 'Virement fournisseur T03', 'debit', 100);
  PERFORM _as_user();
  BEGIN
    DELETE FROM bank_accounts WHERE id = b;
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM bank_transactions WHERE account_id = b;
  PERFORM _rec('T03', 'supprimer un compte bancaire qui a des opérations : refusé, les opérations restent',
    ok AND n = 1 AND err LIKE '%opération%',
    format('refusé=%s opérations restantes=%s (1 attendue) | %s', ok, n, left(err, 80)));
END $$;

-- T04 — SUP-02 : un compte sans opération se supprime toujours
DO $$
DECLARE t uuid; b uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T04');
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Compte vide T04', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    DELETE FROM bank_accounts WHERE id = b;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM bank_accounts WHERE id = b;
  PERFORM _rec('T04', 'supprimer un compte bancaire sans opération : toujours possible',
    ok AND n = 0, format('supprimé=%s comptes restants=%s (0 attendu) | %s', ok, n, left(err, 60)));
END $$;

-- T05 — SUP-03 : l'historique de mouvements survit à la suppression de l'article
DO $$
DECLARE t uuid; wh uuid; p uuid; ok boolean := false; err text := '—';
DECLARE n int; q numeric; lien text;
BEGIN
  t := _mk_tenant('T05');
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-T05', 'Dépôt T05') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Article T05', 'A-T05', 'stock', 0)
    RETURNING id INTO p;
  -- Mouvement sans coût : aucune écriture de stock n'est produite, donc rien
  -- d'autre que l'historique du mouvement lui-même n'est en jeu.
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 10, 0, 'APPRO-T05', CURRENT_DATE, CURRENT_DATE);

  PERFORM _as_user();
  BEGIN
    DELETE FROM products WHERE id = p;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(max(quantity), 0), COALESCE(max(product_id::text), '∅')
    INTO n, q, lien
  FROM stock_movements WHERE tenant_id = t AND reference = 'APPRO-T05';
  PERFORM _rec('T05', 'supprimer un article qui a des mouvements : le mouvement survit (quantité 10 conservée)',
    ok AND n = 1 AND q = 10,
    format('article supprimé=%s mouvements survivants=%s (1 attendu) quantité=%s article du mouvement=%s | %s',
           ok, n, q, lien, left(err, 60)));
END $$;


-- T06 — SUP-03 : un article sans mouvement se supprime toujours
DO $$
DECLARE t uuid; p uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T06');
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article neuf T06', 'A-T06', 'stock')
    RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    DELETE FROM products WHERE id = p;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM products WHERE id = p;
  PERFORM _rec('T06', 'supprimer un article sans mouvement : toujours possible',
    ok AND n = 0, format('supprimé=%s articles restants=%s (0 attendu) | %s', ok, n, left(err, 60)));
END $$;

-- T07 — la suppression d'une société entière emporte ses documents (seul cas voulu)
DO $$
DECLARE t uuid; e uuid; r uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T07');
  INSERT INTO employees (tenant_id, name, status) VALUES (t, 'Salarié T07', 'active') RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-T07', '2026-03-01', '2026-03-31', '2026-03-31', 'approved') RETURNING id INTO r;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status)
    VALUES (t, 'BS-T07', r, e, '2026-03-01', '2026-03-31', 'draft');
  BEGIN
    DELETE FROM tenants WHERE id = t;   -- le chemin d'administration (AUD-B00)
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM pay_slips WHERE tenant_id = t;
  PERFORM _rec('T07', 'supprimer la société emporte ses bulletins : la garde ne bloque que la suppression d''une fiche seule',
    ok AND n = 0, format('société supprimée=%s bulletins restants=%s (0 attendu) | %s', ok, n, left(err, 70)));
END $$;

-- T08 — même famille que SUP-01 : un lot de paie calculé ne part pas avec ses bulletins
DO $$
DECLARE t uuid; e uuid; r uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T08');
  INSERT INTO employees (tenant_id, name, status) VALUES (t, 'Salarié Lot T08', 'active') RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-T08', '2026-03-01', '2026-03-31', '2026-03-31', 'paid') RETURNING id INTO r;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end, status)
    VALUES (t, 'BS-T08', r, e, '2026-03-01', '2026-03-31', 'paid');
  PERFORM _as_user();
  BEGIN
    DELETE FROM pay_runs WHERE id = r;
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pay_slips WHERE pay_run_id = r;
  PERFORM _rec('T08', 'supprimer un lot de paie calculé : refusé, ses bulletins restent',
    ok AND n = 1 AND err LIKE '%bulletin%',
    format('refusé=%s bulletins restants=%s (1 attendu) | %s', ok, n, left(err, 80)));
END $$;

-- T09 — un lot de paie vide (brouillon jamais calculé) se supprime toujours
DO $$
DECLARE t uuid; r uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  t := _mk_tenant('T09');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-T09', '2026-04-01', '2026-04-30', '2026-04-30', 'draft') RETURNING id INTO r;
  PERFORM _as_user();
  BEGIN
    DELETE FROM pay_runs WHERE id = r;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM pay_runs WHERE id = r;
  PERFORM _rec('T09', 'supprimer un lot de paie sans bulletin : toujours possible',
    ok AND n = 0, format('supprimé=%s lots restants=%s (0 attendu) | %s', ok, n, left(err, 60)));
END $$;

SELECT _audit_assert('244');
