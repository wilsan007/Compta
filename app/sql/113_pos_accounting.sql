-- ============================================================
-- 113_pos_accounting.sql
-- POS-01 : Comptabiliser et décrémenter le stock
--
-- Les ventes caisse ne généraient ni écriture ni sortie de stock.
-- ============================================================

CREATE OR REPLACE FUNCTION post_pos_session_on_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_entry_id uuid;
  v_ht numeric;
  v_vat numeric;
  v_ttc numeric;
  v_vat_code text;
  v_vat_amount numeric;
  v_compte_tva text;
  v_ordre int := 2;
  v_ligne RECORD;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(sum(subtotal), 0), COALESCE(sum(vat_total), 0), COALESCE(sum(total), 0)
  INTO v_ht, v_vat, v_ttc
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'completed';

  IF v_ttc = 0 THEN
    RETURN NEW;
  END IF;

  -- 1. Écriture de caisse — en 'draft' puis 'posted' (SOC-01)
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number
  ) VALUES (
    NEW.tenant_id, 'JE-POS-' || NEW.id, COALESCE(NEW.closed_at, NOW())::date, 'CA',
    'draft', 'Clôture caisse ' || NEW.id, 'POS-' || NEW.id
  )
  RETURNING id INTO v_entry_id;

  -- Ligne caisse (débit)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '531000', '531000',
    v_ttc, 0, 'Caisse', 0
  );

  -- Ligne vente (crédit) — ACC-03 : par compte de produit
  FOR v_ligne IN
    SELECT
      COALESCE(p.sale_account_code, pc.sale_account_code, '707000') AS compte,
      SUM(tl.subtotal) AS montant
    FROM pos_ticket_lines tl
    JOIN pos_tickets tk ON tk.id = tl.ticket_id AND tk.tenant_id = NEW.tenant_id
    LEFT JOIN products p ON p.id = tl.product_id AND p.tenant_id = NEW.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
    WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND tk.status = 'completed'
    GROUP BY 1
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
      0, v_ligne.montant, 'Ventes comptoir ' || v_ligne.compte, v_ordre
    );
    v_ordre := v_ordre + 1;
  END LOOP;

  -- Fallback si pas de lignes détaillées
  IF v_ordre = 2 AND v_ht > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '707000', '707000',
      0, v_ht, 'Ventes comptoir', 1
    );
    v_ordre := 3;
  END IF;

  -- ACC-02 : TVA par taux
  FOR v_vat_code, v_vat_amount IN
    SELECT tl.vat_code, SUM(tl.vat_total)
    FROM pos_ticket_lines tl
    JOIN pos_tickets tk ON tk.id = tl.ticket_id AND tk.tenant_id = NEW.tenant_id
    WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND tk.status = 'completed'
      AND tl.vat_code IS NOT NULL AND tl.vat_code != ''
    GROUP BY tl.vat_code
  LOOP
    SELECT account_code INTO v_compte_tva
    FROM vat_account_mapping
    WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
      AND vat_code = v_vat_code AND direction = 'collected'
    ORDER BY tenant_id DESC LIMIT 1;

    v_compte_tva := COALESCE(v_compte_tva, '4457000');

    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      vat_code, vat_amount,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
      v_vat_code, v_vat_amount,
      0, v_vat_amount, 'TVA collectée ' || v_vat_code, v_ordre
    );
    v_ordre := v_ordre + 1;
  END LOOP;

  -- Fallback TVA
  IF v_ordre <= 3 AND v_vat > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '4457000', '4457000',
      0, v_vat, 'TVA collectée', v_ordre
    );
  END IF;

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;

  -- 2. Sorties de stock, valorisées au CUMP courant
  INSERT INTO stock_movements (
    tenant_id, product_id, movement_type, quantity,
    unit_cost, reference, reference_type, reference_id,
    date, movement_date, warehouse_id
  )
  SELECT
    NEW.tenant_id, l.product_id, 'out', sum(l.quantity),
    max(COALESCE(sq.unit_cost, p.cost_price, 0)),
    'POS-' || NEW.id, 'pos_session', NEW.id,
    COALESCE(NEW.closed_at, NOW())::date, COALESCE(NEW.closed_at, NOW())::date, t.warehouse_id
  FROM pos_ticket_lines l
  JOIN pos_tickets tk ON tk.id = l.ticket_id AND tk.tenant_id = NEW.tenant_id
  JOIN pos_terminals t ON t.id = tk.terminal_id AND t.tenant_id = NEW.tenant_id
  JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
  LEFT JOIN stock_quantities sq ON sq.product_id = l.product_id
    AND sq.warehouse_id = t.warehouse_id AND sq.tenant_id = NEW.tenant_id
  WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND l.product_id IS NOT NULL
  GROUP BY l.product_id, t.warehouse_id;

  RETURN NEW;
END;
$$;

-- Trigger de clôture de session POS
DROP TRIGGER IF EXISTS post_pos_session ON pos_sessions;
CREATE TRIGGER post_pos_session AFTER UPDATE ON pos_sessions
  FOR EACH ROW EXECUTE FUNCTION post_pos_session_on_close();
