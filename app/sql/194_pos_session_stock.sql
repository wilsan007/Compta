-- ============================================================
-- 194_pos_session_stock.sql — lot G du plan correctif (vague V3)
--
-- AUD-G09 — prouvé par G09 de sql/192_purchases_treasury_tests.sql.
-- À la clôture d'une session de caisse, post_pos_session_on_close_multi insérait
-- un mouvement de sortie (qui décrémente déjà le stock) PUIS décrémentait
-- stock_quantities une seconde fois, sur toutes les lignes de l'article, tous
-- dépôts confondus : 2 ventes → magasin 10 → 6, réserve 10 → 8. Sans ligne de
-- stock préexistante, aucun mouvement n'était créé (INSERT … SELECT … LIMIT 1).
-- Écriture de clôture et chaîne NF525 inchangées (vérifiées par G09).
-- ============================================================

CREATE OR REPLACE FUNCTION public.post_pos_session_on_close_multi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
      v_tid, v_je_id, v_line_num, '445710', 0, v_total_vat, now()
    );
    v_line_num := v_line_num + 1;
  END IF;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Sorties de stock : un mouvement par article et par dépôt de la caisse.
  -- update_stock_on_movement décrémente le stock de CE dépôt et valorise la sortie
  -- (couches FIFO, écriture ST) : aucune autre décrémentation ici.
  FOR v_product IN
    SELECT ptl.product_id, SUM(ptl.quantity) AS total_qty, pt2.warehouse_id
    FROM pos_ticket_lines ptl
    JOIN pos_tickets pt ON pt.id = ptl.ticket_id AND pt.tenant_id = ptl.tenant_id
    JOIN pos_sessions ps ON ps.id = pt.session_id AND ps.tenant_id = pt.tenant_id
    JOIN pos_terminals pt2 ON pt2.id = ps.terminal_id AND pt2.tenant_id = ps.tenant_id
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND ptl.tenant_id = v_tid
      AND ptl.product_id IS NOT NULL
    GROUP BY ptl.product_id, pt2.warehouse_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type,
      quantity, reference, reference_type, reference_id,
      date, movement_date, created_at
    ) VALUES (
      v_tid, v_product.product_id, v_product.warehouse_id, 'out', 'out',
      v_product.total_qty,
      'POS-' || v_session_ref, 'pos_session', NEW.id,
      v_close_date, v_close_date, now()
    );
  END LOOP;

  RETURN NEW;
END;
$function$;
