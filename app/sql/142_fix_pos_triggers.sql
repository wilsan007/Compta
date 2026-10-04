-- ============================================================
-- 142_fix_pos_triggers.sql
-- LOT2-11 → LOT2-14 : Corrections des triggers POS
--
-- LOT2-11 : post_pos_session_on_close (113) utilise tl.subtotal
--           qui n'existe pas sur pos_ticket_lines (→ line_total)
-- LOT2-12 : post_pos_session_on_close_multi (119) utilise CURRENT_DATE
--           au lieu de NEW.closed_at (corrigé)
-- LOT2-13 : NEW.session_number déjà géré via COALESCE (correct)
-- LOT2-14 : nf525_event_log.reference_id → entity_id (déjà correct)
--
-- Le trigger post_pos_session (113) n'est pas supprimé par la 119.
-- Il faut le supprimer car la 119 le remplace par post_pos_session_on_close_multi.
-- ============================================================

-- LOT2-11 : Supprimer l'ancien trigger post_pos_session (113)
-- qui référence tl.subtotal (inexistant sur pos_ticket_lines)
DROP TRIGGER IF EXISTS post_pos_session ON pos_sessions;

-- LOT2-11 : Réécrire post_pos_session_on_close avec tl.line_total
-- (au cas où le trigger serait recréé manuellement)
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

  -- LOT2-11 : pos_tickets.subtotal existe, pas pos_ticket_lines.subtotal
  SELECT COALESCE(sum(subtotal), 0), COALESCE(sum(vat_total), 0), COALESCE(sum(total), 0)
  INTO v_ht, v_vat, v_ttc
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'completed';

  IF v_ttc = 0 THEN
    RETURN NEW;
  END IF;

  -- LOT2-12 : utiliser NEW.closed_at au lieu de entry_date
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

  -- LOT2-11 : tl.subtotal → tl.line_total (pos_ticket_lines a line_total, pas subtotal)
  FOR v_ligne IN
    SELECT
      COALESCE(p.sale_account_code, pc.sale_account_code, '707000') AS compte,
      SUM(tl.line_total) AS montant
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

  -- TVA : pos_ticket_lines n'a pas vat_code/vat_total, on utilise vat_rate
  FOR v_vat_code, v_vat_amount IN
    SELECT 'FR' || REPLACE(tl.vat_rate::text, '.', ''), SUM(tl.line_total * tl.vat_rate / 100)
    FROM pos_ticket_lines tl
    JOIN pos_tickets tk ON tk.id = tl.ticket_id AND tk.tenant_id = NEW.tenant_id
    WHERE tk.session_id = NEW.id AND tk.tenant_id = NEW.tenant_id AND tk.status = 'completed'
      AND tl.vat_rate > 0
    GROUP BY 1
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

  -- Sorties de stock
  INSERT INTO stock_movements (
    tenant_id, product_id, movement_type, type, quantity,
    unit_cost, reference, reference_type, reference_id,
    date, movement_date, warehouse_id
  )
  SELECT
    NEW.tenant_id, l.product_id, 'out', 'out', sum(l.quantity),
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

-- Ne pas recréer le trigger post_pos_session : la 119 a créé post_pos_session_on_close_multi
-- qui est la version correcte. On garde juste la fonction corrigée pour référence.

-- LOT2-12 : Corriger post_pos_session_on_close_multi pour utiliser NEW.closed_at
-- au lieu de CURRENT_DATE
CREATE OR REPLACE FUNCTION post_pos_session_on_close_multi()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := NEW.tenant_id;
  v_je_id uuid;
  v_line_num int := 1;
  v_total_sales numeric := 0;
  v_total_vat numeric := 0;
  v_ticket record;
  v_payment record;
  v_method_amount numeric;
  v_product record;
  v_je_number text;
  v_session_ref text;
  v_close_date date := COALESCE(NEW.closed_at, NOW())::date;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  -- LOT2-13 : utiliser NEW.id::text comme fallback
  v_session_ref := COALESCE(NEW.session_number, NEW.id::text);

  -- Calculer le total des ventes et TVA
  SELECT COALESCE(SUM(subtotal), 0), COALESCE(SUM(vat_total), 0)
  INTO v_total_sales, v_total_vat
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = v_tid AND status = 'completed';

  IF v_total_sales = 0 THEN
    RETURN NEW;
  END IF;

  v_je_number := 'POS-' || NEW.id;

  -- LOT2-12 : utiliser v_close_date au lieu de CURRENT_DATE
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'POS', v_je_number, v_close_date,
    'Clôture caisse session ' || v_session_ref, 'draft', now()
  )
  RETURNING id INTO v_je_id;

  -- Une ligne de débit par moyen de paiement
  FOR v_payment IN
    SELECT ppm.account_code, SUM(pp.amount) AS total
    FROM pos_payments pp
    JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
    JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    GROUP BY ppm.account_code
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, v_payment.account_code,
      v_payment.total, 0, now()
    );
    v_line_num := v_line_num + 1;
  END LOOP;

  -- Crédit des ventes (707000)
  INSERT INTO journal_lines (
    tenant_id, journal_id, line_order, account_code,
    debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_line_num, '707000', 0, v_total_sales, now()
  );
  v_line_num := v_line_num + 1;

  -- Crédit de la TVA (4457100)
  IF v_total_vat > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, '4457100', 0, v_total_vat, now()
    );
    v_line_num := v_line_num + 1;
  END IF;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Créer les mouvements de stock sortants
  FOR v_product IN
    SELECT ptl.product_id, SUM(ptl.quantity) AS total_qty, pt2.warehouse_id
    FROM pos_ticket_lines ptl
    JOIN pos_tickets pt ON pt.id = ptl.ticket_id AND pt.tenant_id = ptl.tenant_id
    JOIN pos_sessions ps ON ps.id = pt.session_id AND ps.tenant_id = pt.tenant_id
    JOIN pos_terminals pt2 ON pt2.id = ps.terminal_id AND pt2.tenant_id = ps.tenant_id
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND ptl.tenant_id = v_tid
    GROUP BY ptl.product_id, pt2.warehouse_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type,
      quantity, unit_cost, reference, reference_type, reference_id,
      date, movement_date, created_at
    )
    SELECT
      v_tid, v_product.product_id, v_product.warehouse_id, 'out', 'out',
      v_product.total_qty,
      COALESCE(sq.unit_cost, 0),
      'POS-' || v_session_ref, 'pos_session', NEW.id,
      v_close_date, v_close_date, now()
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_product.product_id
    LIMIT 1;

    -- Décrémenter le stock
    UPDATE stock_quantities
    SET quantity = quantity - v_product.total_qty, updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product.product_id;
  END LOOP;

  RETURN NEW;
END;
$$;
