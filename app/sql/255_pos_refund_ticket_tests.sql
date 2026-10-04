-- ============================================================
-- 255_pos_refund_ticket_tests.sql — l'avoir de caisse après clôture
--
-- La 250 refuse l'annulation d'un ticket dont la session est clôturée : la
-- vente est comptabilisée. Son message dit « émettre un avoir » — il n'existait
-- pas. Ce fichier mesure l'avoir : un ticket d'annulation (montants négatifs,
-- mêmes lignes, même caisse) dans une session ouverte du même terminal, le
-- stock rendu, la vente d'origine marquée `refunded` — montants et empreinte
-- intacts — et l'événement NF-525.
--
-- Mesuré AVANT la 255 : T01 vert (le refus de la 250 sur session ouverte),
-- T02, T03, T04, T05 rouges — `pos_refund_ticket()` n'existe pas.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '255', false);
DELETE FROM _audit_results WHERE file = '255';

CREATE OR REPLACE FUNCTION _mk_caisse255(p_nom text,
  OUT t uuid, OUT term uuid, OUT sess uuid, OUT prod uuid, OUT pm uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t, ARRAY['531000','707000','445710','445711','758000','658000']);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom);
  INSERT INTO pos_terminals (tenant_id, name, warehouse_id)
    VALUES (t, 'Caisse ' || p_nom,
            (SELECT id FROM warehouses WHERE tenant_id = t ORDER BY created_at LIMIT 1))
    RETURNING id INTO term;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caissier@audit.test', 100, 'open') RETURNING id INTO sess;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, stock_quantity)
    VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 120, 50, 100) RETURNING id INTO prod;
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code, is_active)
    VALUES (t, 'Espèces', 'cash', '531000', true) RETURNING id INTO pm;
END $$;

CREATE OR REPLACE FUNCTION _tk255(p_t uuid, p_sess uuid, p_prod uuid, p_pm uuid, p_num text,
  p_ht numeric DEFAULT 100)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k uuid; v_vat numeric := round(p_ht * 20 / 100, 2);
BEGIN
  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, customer_id, date, subtotal,
                           vat_total, total, payment_method, amount_paid, status)
  SELECT p_t, p_num, ps.id, ps.terminal_id,
         (SELECT id FROM customers WHERE tenant_id = p_t ORDER BY created_at LIMIT 1),
         CURRENT_DATE, p_ht, v_vat, p_ht + v_vat, 'cash', p_ht + v_vat, 'completed'
  FROM pos_sessions ps WHERE ps.id = p_sess AND ps.tenant_id = p_t
  RETURNING id INTO k;
  INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity,
                                unit_price, vat_rate, line_total)
  VALUES (p_t, k, p_prod, 'Article caisse', 1, p_ht, 20, p_ht);
  INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount)
  VALUES (p_t, k, p_pm, p_ht + v_vat);
  RETURN k;
END $$;

CREATE OR REPLACE FUNCTION _rouvre255(p_t uuid, p_term uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE s uuid;
BEGIN
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (p_t, p_term, 'caissier@audit.test', 0, 'open') RETURNING id INTO s;
  RETURN s;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — session ouverte : on annule le ticket, on n'émet pas d'avoir
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; s1 text; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse255('AV255T01')) x;
  tk := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV1');
  PERFORM _as_user();
  BEGIN
    PERFORM pos_refund_ticket(tk, 'session ouverte');
  EXCEPTION WHEN others THEN s1 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T01', 'session ouverte : l''avoir est refusé, l''annulation directe est le chemin',
    (s1 = '42501' OR s1 = '42883') AND err LIKE '%ouvert%',
    format('SQLSTATE=%s | %s', COALESCE(s1, 'aucune erreur'), left(err, 90)));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T02 — après clôture : l'avoir est une pièce commerciale
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; av uuid; cn record; s record;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse255('AV255T02')) x;
  tk := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV2');
  UPDATE pos_sessions SET status = 'closed', closing_amount = 120, closed_at = now() WHERE id = v.sess;

  PERFORM _as_user();
  av := pos_refund_ticket(tk, 'Client a changé d''avis');
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO cn FROM (SELECT * FROM (
    SELECT number, customer_id, subtotal, vat_total, total, status, invoice_id, reason
    FROM credit_notes WHERE id = av) y) x;
  SELECT * INTO s FROM (SELECT * FROM (
    SELECT customer_id FROM pos_tickets WHERE id = tk) y) x;

  PERFORM _rec('T02', 'l''avoir est un avoir commercial : le client de la vente, ses montants, et il est né',
    cn.customer_id IS NOT NULL AND cn.customer_id = s.customer_id
      AND cn.subtotal = 100 AND cn.vat_total = 20 AND cn.total = 120
      AND cn.status IN ('draft', 'validated') AND cn.reason LIKE 'Avoir de caisse sur le ticket TK-AV2%',
    format('avoir %s du client %s, montants %s/%s/%s, statut %s, motif=%s',
           cn.number, CASE WHEN cn.customer_id = s.customer_id THEN 'de la vente' ELSE 'inconnu' END,
           cn.subtotal, cn.vat_total, cn.total, cn.status, left(cn.reason, 60)));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T03 — l'avoir rentre la marchandise au dépôt
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; av uuid; article numeric; depot numeric; n int; q numeric;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse255('AV255T03')) x;
  tk := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV3');
  UPDATE pos_sessions SET status = 'closed', closing_amount = 120, closed_at = now() WHERE id = v.sess;
  PERFORM _rouvre255(v.t, v.term);

  PERFORM _as_user();
  av := pos_refund_ticket(tk, 'article rendu');
  PERFORM set_config('role', 'postgres', true);

  SELECT stock_quantity INTO article FROM products WHERE id = v.prod;
  SELECT quantity INTO depot FROM stock_quantities
    WHERE tenant_id = v.t AND product_id = v.prod
      AND warehouse_id = (SELECT warehouse_id FROM pos_terminals WHERE id = v.term);
  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q FROM stock_movements
    WHERE tenant_id = v.t AND reference_type = 'pos_refund' AND reference_id = av;

  PERFORM _rec('T03', 'l''avoir rentre la marchandise : le stock revient à 100, une entrée tracée',
    article = 100 AND COALESCE(depot, 0) = 100 AND n = 1 AND q = 1,
    format('article=%s (100 attendu), dépôt=%s (100 attendu), entrées de retour=%s pour %s unité(s) (1/1 attendues)',
           article, COALESCE(depot, 0), n, q));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — la vente d'origine reste lisible, et le journal le dit
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; av uuid; s record; ev int; h text;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse255('AV255T04')) x;
  tk := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV4');
  SELECT ticket_hash INTO h FROM pos_tickets WHERE id = tk;
  UPDATE pos_sessions SET status = 'closed', closing_amount = 120, closed_at = now() WHERE id = v.sess;
  PERFORM _rouvre255(v.t, v.term);

  PERFORM _as_user();
  av := pos_refund_ticket(tk, 'erreur de caisse');
  PERFORM set_config('role', 'postgres', true);

  SELECT * INTO s FROM (SELECT * FROM (
    SELECT status, total, subtotal, ticket_hash, void_reason, is_voided
    FROM pos_tickets WHERE id = tk) y) x;
  SELECT count(*) INTO ev FROM nf525_event_log
    WHERE tenant_id = v.t AND entity_id = tk AND event_type = 'pos_ticket_refunded';

  PERFORM _rec('T04', 'la vente d''origine passe à « refunded », montants et empreinte intacts, événement NF-525',
    s.status = 'refunded' AND s.total = 120 AND s.subtotal = 100 AND s.ticket_hash = h AND s.is_voided
      AND s.void_reason LIKE 'Avoir AV%' AND ev = 1,
    format('statut=%s total=%s sous-total=%s empreinte inchangée=%s motif=%s, événements NF-525=%s (1 attendu)',
           s.status, s.total, s.subtotal, s.ticket_hash = h, left(COALESCE(s.void_reason, '-'), 30), ev));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T05 — un avoir ne s'écrit qu'une fois, et il faut un client
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; tk uuid; tk2 uuid; av uuid; s2 text; s3 text; s4 text; n int; err text := '—';
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_caisse255('AV255T05')) x;
  -- Les deux ventes sont encaissées AVANT la clôture : une ligne de ticket ne
  -- s'ajoute pas dans une session fermée (garde de la 250).
  tk := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV5');
  tk2 := _tk255(v.t, v.sess, v.prod, v.pm, 'TK-AV5B');
  UPDATE pos_sessions SET status = 'closed', closing_amount = 240, closed_at = now() WHERE id = v.sess;

  PERFORM _rouvre255(v.t, v.term);
  PERFORM _as_user();
  av := pos_refund_ticket(tk, 'premier avoir');
  -- (a) second avoir sur la même vente : refusé
  BEGIN
    PERFORM pos_refund_ticket(tk, 'deuxième avoir');
  EXCEPTION WHEN others THEN s2 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  -- (b) une vente de comptoir sans client : un avoir crédite quelqu'un
  BEGIN
    ALTER TABLE pos_tickets DISABLE TRIGGER prevent_pos_ticket_modification_trg;
  EXCEPTION WHEN undefined_object THEN NULL;   -- la garde naît avec la 250
  END;
  UPDATE pos_tickets SET customer_id = NULL WHERE id = tk2;
  BEGIN
    ALTER TABLE pos_tickets ENABLE TRIGGER prevent_pos_ticket_modification_trg;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
  PERFORM _as_user();
  BEGIN
    PERFORM pos_refund_ticket(tk2, 'sans client');
  EXCEPTION WHEN others THEN s4 := SQLSTATE; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO n FROM credit_notes WHERE tenant_id = v.t AND reason LIKE 'Avoir de caisse%';
  PERFORM _rec('T05', 'un second avoir est refusé, et une vente sans client n''a pas d''avoir',
    s2 = '42501' AND s4 = '42501' AND n = 1,
    format('second avoir SQLSTATE=%s (42501 attendu), vente sans client SQLSTATE=%s (42501 attendu), avoirs écrits=%s (1 attendu) | %s',
           COALESCE(s2, 'aucune erreur'), COALESCE(s4, 'aucune erreur'), n, left(err, 60)));
END $$;

DROP FUNCTION _rouvre255(uuid, uuid);
DROP FUNCTION _tk255(uuid, uuid, uuid, uuid, text, numeric);
DROP FUNCTION _mk_caisse255(text);

SELECT _audit_assert('255');
