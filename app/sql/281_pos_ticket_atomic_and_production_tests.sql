-- ============================================================
-- 281_pos_ticket_atomic_and_production_tests.sql — vague X5 (C11, C12, M7, D-E)
-- (audit fonctionnel exécuté du 28/09/2026, partie 3)
--
-- MESURÉ AVANT (base neuve sans la 281) : T01–T07 ROUGES — aucune fonction
-- d'encaissement atomique, aucun moyen de paiement par défaut, un ticket se
-- créait sur une session close, la clôture d'un ticket sans paiement ventilé
-- produisait une écriture sans débit (refusée), un OF naissait sans article.
--
--   T01 `create_pos_ticket` : ticket + ligne + paiement + sortie de stock en un
--       appel ; totaux calculés par la base (montants saisis ignorés)
--   T02 un ticket sur une session close est refusé (appel et écriture directe)
--   T03 clôture : attendu en tiroir = fond + espèces (la carte n'y est pas),
--       écriture POS validée et équilibrée ; pas de seconde sortie de stock
--   T04 un ticket annulé (session ouverte) rend son stock
--   T05 D-E : une société neuve a ses moyens de paiement (espèces 530000,
--       carte et chèque 511200)
--   T06 un ticket écrit en direct, sans paiement : la clôture le reconstitue
--       et l'écriture est équilibrée
--   T07 un OF prend l'article de sa nomenclature ; sans article : refusé
--   T08 un lecteur n'encaisse pas, ne réécrit pas un moyen de paiement ; nul
--       n'écrit `pos_payments` en direct
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '281', false);
DELETE FROM _audit_results WHERE file = '281';

-- Société de caisse : dépôt, article (stock 10 @ 5), caisse sur le dépôt, session ouverte (fond 100)
CREATE OR REPLACE FUNCTION _mk281(p_nom text, OUT t uuid, OUT wh uuid, OUT prod uuid, OUT term uuid, OUT sess uuid)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom, false);
  PERFORM ensure_standard_journals(t);
  PERFORM _ledger_fixture(t, ARRAY['530000','511200','707000','445710','445711','658000','758000']);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Magasin') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, cost_price, vat_rate)
    VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10, 5, 20) RETURNING id INTO prod;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, quantity, unit_cost, reference)
    VALUES (t, prod, wh, 'initial', 10, 5, 'Stock initial');
  INSERT INTO pos_terminals (tenant_id, name, warehouse_id) VALUES (t, 'Caisse ' || p_nom, wh) RETURNING id INTO term;
  INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caisse@audit.test', 100, 'open') RETURNING id INTO sess;
END $$;

CREATE OR REPLACE FUNCTION _tk281(p_sess uuid, p_prod uuid, p_qty numeric, p_method text, p_received numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k pos_tickets;
BEGIN
  k := create_pos_ticket(
    jsonb_build_object('session_id', p_sess, 'number', 'T', 'payment_method', p_method, 'amount_paid', p_received,
                       'subtotal', 1, 'vat_total', 1, 'total', 1),
    jsonb_build_array(jsonb_build_object('product_id', p_prod, 'description', 'Article', 'quantity', p_qty,
                                         'unit_price', 10, 'vat_rate', 20)));
  RETURN k.id;
END $$;

-- T01 / T02 / T03 / T04
DO $$
DECLARE s record; k1 uuid; k2 uuid; k3 uuid; v record; q1 numeric; q_void numeric; q_close numeric;
  n_pay int; e_rpc text; e_dir text; ss record; je record; n_sess_out int; term uuid;
BEGIN
  s := _mk281('X5A');
  PERFORM _as_user();
  k1 := _tk281(s.sess, s.prod, 2, 'cash', 50);          -- 24 en espèces, rendu 26
  SELECT subtotal, vat_total, total, change_given INTO v FROM pos_tickets WHERE id = k1;
  SELECT count(*) INTO n_pay FROM pos_payments WHERE ticket_id = k1 AND amount = 24;
  SELECT stock_quantity INTO q1 FROM products WHERE id = s.prod;
  k2 := _tk281(s.sess, s.prod, 1, 'card', 0);           -- 12 par carte
  k3 := _tk281(s.sess, s.prod, 3, 'cash', 36);          -- annulé ensuite
  PERFORM void_pos_ticket(k3, 'erreur de saisie');
  SELECT stock_quantity INTO q_void FROM products WHERE id = s.prod;
  UPDATE pos_sessions SET status = 'closed', closing_amount = 124, closed_at = now() WHERE id = s.sess;
  SELECT stock_quantity INTO q_close FROM products WHERE id = s.prod;
  BEGIN
    PERFORM _tk281(s.sess, s.prod, 1, 'cash', 12);
  EXCEPTION WHEN OTHERS THEN e_rpc := SQLERRM;
  END;
  BEGIN
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total, status)
      VALUES (s.t, 'T-DIRECT', s.sess, s.term, 10, 2, 12, 'completed');
  EXCEPTION WHEN OTHERS THEN e_dir := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT expected_amount, difference INTO ss FROM pos_sessions WHERE id = s.sess;
  SELECT max(e.status) st, sum(l.debit) d, sum(l.credit) c,
         sum(l.debit) FILTER (WHERE l.account_code = '530000') d530,
         sum(l.debit) FILTER (WHERE l.account_code = '511200') d5112
    INTO je FROM journal_entries e JOIN journal_lines l ON l.journal_id = e.id
   WHERE e.tenant_id = s.t AND e.journal_code = 'POS';
  SELECT count(*) INTO n_sess_out FROM stock_movements WHERE tenant_id = s.t AND reference_type = 'pos_session';

  PERFORM _rec('T01', 'encaissement atomique : 2 × 10 HT + TVA 20 % = 24 (1 saisi ignoré), rendu 26, 1 paiement de 24, stock 10 → 8',
    v.subtotal = 20 AND v.vat_total = 4 AND v.total = 24 AND v.change_given = 26 AND n_pay = 1 AND q1 = 8,
    format('HT=%s TVA=%s TTC=%s rendu=%s paiements=%s stock=%s', v.subtotal, v.vat_total, v.total, v.change_given, n_pay, q1));
  PERFORM _rec('T02', 'session close : ticket refusé, par l''appel comme par l''écriture directe',
    e_rpc ~* 'close|ouverte' AND e_dir ~* 'ouverte',
    format('appel=%s | direct=%s', coalesce(e_rpc, 'ACCEPTÉ'), coalesce(e_dir, 'ACCEPTÉ')));
  PERFORM _rec('T03', 'clôture : attendu 100 + 24 espèces = 124 (carte hors tiroir), écart 0 ; écriture POS validée, équilibrée (D530 24, D5112 12) ; aucune seconde sortie de stock',
    ss.expected_amount = 124 AND ss.difference = 0 AND je.st = 'posted' AND je.d = je.c AND je.d530 = 24 AND je.d5112 = 12
      AND n_sess_out = 0 AND q_close = q_void,
    format('attendu=%s écart=%s ; écriture %s D=%s C=%s D530=%s D5112=%s ; sorties de clôture=%s ; stock %s → %s',
           ss.expected_amount, ss.difference, je.st, je.d, je.c, je.d530, je.d5112, n_sess_out, q_void, q_close));
  PERFORM _rec('T04', 'un ticket annulé rend son stock (7 après la vente de 3, 7 + 3 = 10 → 7 = 10 − 2 − 1)',
    q_void = 7, format('stock après annulation=%s (attendu 7)', q_void));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'encaissement atomique : 2 × 10 HT + TVA 20 % = 24 (1 saisi ignoré), rendu 26, 1 paiement de 24, stock 10 → 8', false, SQLERRM);
  PERFORM _rec('T02', 'session close : ticket refusé, par l''appel comme par l''écriture directe', false, SQLERRM);
  PERFORM _rec('T03', 'clôture : attendu 100 + 24 espèces = 124 (carte hors tiroir), écart 0 ; écriture POS validée, équilibrée (D530 24, D5112 12) ; aucune seconde sortie de stock', false, SQLERRM);
  PERFORM _rec('T04', 'un ticket annulé rend son stock (7 après la vente de 3, 7 + 3 = 10 → 7 = 10 − 2 − 1)', false, SQLERRM);
END $$;

-- T05 / T06
DO $$
DECLARE s record; pm text; k uuid; je record; n_pay int;
BEGIN
  s := _mk281('X5B');
  SELECT string_agg(type || '=' || account_code, ',' ORDER BY display_order) INTO pm
  FROM pos_payment_methods WHERE tenant_id = s.t;
  PERFORM _as_user();
  -- Chemin antérieur à la 281 : ticket et ligne écrits en direct, sans paiement
  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total, payment_method, amount_paid, status)
    VALUES (s.t, 'T-ANCIEN', s.sess, s.term, 10, 2, 12, 'cash', 12, 'completed') RETURNING id INTO k;
  INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (s.t, k, s.prod, 'Article', 1, 10, 20, 10);
  UPDATE pos_sessions SET status = 'closed', closing_amount = 112, closed_at = now() WHERE id = s.sess;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO n_pay FROM pos_payments WHERE ticket_id = k;
  SELECT max(e.status) st, sum(l.debit) d, sum(l.credit) c INTO je
  FROM journal_entries e JOIN journal_lines l ON l.journal_id = e.id
  WHERE e.tenant_id = s.t AND e.journal_code = 'POS';
  PERFORM _rec('T05', 'D-E : une société neuve a ses moyens de paiement (espèces 530000, carte 511200, chèque 511200)',
    pm = 'cash=530000,card=511200,check=511200', coalesce(pm, 'aucun'));
  PERFORM _rec('T06', 'ticket sans paiement ventilé : la clôture le reconstitue (1 paiement) et l''écriture est équilibrée',
    n_pay = 1 AND je.st = 'posted' AND je.d = je.c AND je.d = 12,
    format('paiements=%s écriture %s D=%s C=%s', n_pay, je.st, je.d, je.c));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'D-E : une société neuve a ses moyens de paiement (espèces 530000, carte 511200, chèque 511200)', false, SQLERRM);
  PERFORM _rec('T06', 'ticket sans paiement ventilé : la clôture le reconstitue (1 paiement) et l''écriture est équilibrée', false, SQLERRM);
END $$;

-- T07 — l'OF et sa nomenclature
DO $$
DECLARE s record; fin uuid; b uuid; mo uuid; mo_prod uuid; e_sans text;
BEGIN
  s := _mk281('X5C');
  PERFORM _as_user();
  INSERT INTO products (tenant_id, name, sku, type) VALUES (s.t, 'Produit fini', 'PF-X5C', 'stock') RETURNING id INTO fin;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity) VALUES (s.t, 'BOM-X5C', 'Nomenclature', fin, 1) RETURNING id INTO b;
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, warehouse_id)
    VALUES (s.t, 'OF-X5C', b, NULL, 10, s.wh) RETURNING id INTO mo;
  SELECT product_id INTO mo_prod FROM manufacturing_orders WHERE id = mo;
  BEGIN
    INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity) VALUES (s.t, 'OF-VIDE', NULL, NULL, 1);
  EXCEPTION WHEN OTHERS THEN e_sans := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T07', 'un OF prend l''article de sa nomenclature ; sans article ni nomenclature : refusé',
    mo_prod = fin AND e_sans ~* 'aucun article',
    format('article de l''OF=%s ; sans article=%s', mo_prod = fin, coalesce(e_sans, 'ACCEPTÉ')));
END $$;

-- T08 — le lecteur, et `pos_payments`
DO $$
DECLARE s record; u uuid := uuid_generate_v4(); e_tk text; n_pm int := -1; e_pay text; k uuid; pm uuid;
BEGIN
  s := _mk281('X5D');
  PERFORM _as_user();
  k := _tk281(s.sess, s.prod, 1, 'cash', 12);
  SELECT id INTO pm FROM pos_payment_methods WHERE tenant_id = s.t AND type = 'cash';
  BEGIN
    INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount) VALUES (s.t, k, pm, 1000);
  EXCEPTION WHEN OTHERS THEN e_pay := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  INSERT INTO auth.users (id, email) VALUES (u, 'lecteur-' || u || '@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (s.t, u, 'lecteur-' || u || '@audit.test', 'Lecteur', 'viewer', 'active');
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
  BEGIN
    PERFORM _tk281(s.sess, s.prod, 1, 'cash', 12);
  EXCEPTION WHEN OTHERS THEN e_tk := SQLERRM;
  END;
  UPDATE pos_payment_methods SET account_code = '999999' WHERE tenant_id = s.t;
  GET DIAGNOSTICS n_pm = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T08', 'un lecteur n''encaisse pas et ne réécrit pas un moyen de paiement ; pos_payments ne s''écrit pas en direct (même par l''administrateur)',
    e_tk ~* 'droit' AND n_pm = 0 AND e_pay ~* 'permission',
    format('encaissement=%s ; moyens réécrits=%s ; paiement direct=%s', coalesce(e_tk, 'ACCEPTÉ'), n_pm, coalesce(e_pay, 'ACCEPTÉ')));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T08', 'un lecteur n''encaisse pas et ne réécrit pas un moyen de paiement ; pos_payments ne s''écrit pas en direct (même par l''administrateur)', false, SQLERRM);
END $$;

DROP FUNCTION _tk281(uuid, uuid, numeric, text, numeric);
DROP FUNCTION _mk281(text);
SELECT _audit_assert('281');
