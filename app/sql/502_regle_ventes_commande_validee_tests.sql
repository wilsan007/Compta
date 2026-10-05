-- ============================================================
-- 502_regle_ventes_commande_validee_tests.sql — partie B, lot Ventes, règle R-005
--
-- Ce que la règle R-005 garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  valider une commande au numéro de BROUILLON lui donne un numéro DÉFINITIF ;
--   T02  une commande validée REFUSE de changer de client (immuabilité d'en-tête) ;
--   T03  les LIGNES d'une commande validée sont GELÉES (modification refusée) ;
--   T04  un numéro DÉJÀ définitif n'est pas remplacé par la validation.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '502', false);
DELETE FROM _audit_results WHERE file = '502';

-- Société isolée : une commande brouillon (numéro paramétré) et une ligne (10 × 100).
CREATE OR REPLACE FUNCTION _b502(p_nom text, p_num text, OUT t uuid, OUT o uuid, OUT ol uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid; p uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type)
    VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, validation_status)
    VALUES (t, p_num, c, '2026-03-10', 'draft', 'draft') RETURNING id INTO o;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description,
                                 quantity, unit_price, vat_rate)
    VALUES (t, o, p, 'Ligne ' || p_nom, 10, 100, 20) RETURNING id INTO ol;
END $$;

-- ── T01 : validation → numéro définitif ─────────────────────────
DO $$
DECLARE v record; v_num text;
BEGIN
  v := _b502('T01', 'BROUILLON-CMD-T01');
  PERFORM _as_user();
  UPDATE sales_orders SET validation_status = 'validated' WHERE id = v.o;
  SELECT number INTO v_num FROM sales_orders WHERE id = v.o;
  PERFORM _rec('T01', 'la validation remplace le numéro de brouillon par un numéro définitif',
    v_num NOT LIKE 'BROUILLON-%' AND v_num IS NOT NULL,
    format('numéro=%s', v_num));
END $$;

-- ── T04 : un numéro déjà définitif n'est pas remplacé ───────────
DO $$
DECLARE v record; v_num text;
BEGIN
  v := _b502('T04', 'CMD-2026-000123');
  PERFORM _as_user();
  UPDATE sales_orders SET validation_status = 'validated' WHERE id = v.o;
  SELECT number INTO v_num FROM sales_orders WHERE id = v.o;
  PERFORM _rec('T04', 'un numéro déjà définitif reste inchangé à la validation',
    v_num = 'CMD-2026-000123', format('numéro=%s (CMD-2026-000123 attendu)', v_num));
END $$;

-- ── T02 : immuabilité d'en-tête ─────────────────────────────────
DO $$
DECLARE v record; refuse boolean := false;
BEGIN
  v := _b502('T02', 'CMD-2026-000200');
  PERFORM _as_user();
  UPDATE sales_orders SET validation_status = 'validated' WHERE id = v.o;
  BEGIN
    UPDATE sales_orders SET customer_id = NULL WHERE id = v.o;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T02', 'une commande validée refuse de changer de client',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

-- ── T03 : les lignes d'une commande validée sont gelées ─────────
DO $$
DECLARE v record; refuse boolean := false;
BEGIN
  v := _b502('T03', 'CMD-2026-000300');
  PERFORM _as_user();
  UPDATE sales_orders SET validation_status = 'validated' WHERE id = v.o;
  BEGIN
    UPDATE sales_order_lines SET quantity = 99 WHERE id = v.ol;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T03', 'une ligne de commande validée ne se modifie plus',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

SELECT _audit_assert('502');