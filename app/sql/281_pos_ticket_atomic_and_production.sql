-- ============================================================
-- 281_pos_ticket_atomic_and_production.sql — vague X5 (partie 3 du plan
-- correctif de l'audit fonctionnel exécuté du 28/09/2026), décision D-E
--
-- MESURÉ AVANT, par le chemin de l'écran (base neuve, 255 migrations,
-- `07_pos.screen.ts`, `08_prod_treso.screen.ts`) :
--   C12 la clôture de caisse était IMPOSSIBLE : l'écran écrivait le ticket puis
--       ses lignes, jamais `pos_payments` ; l'écriture de clôture n'avait donc
--       aucun débit (« débit 0,00 ≠ crédit 72,00 ») et la clôture tombait (K06),
--       rien n'était comptabilisé (K07). Aucun moyen de paiement n'existait
--       (0 ligne dans `pos_payment_methods`), et les deux tables n'avaient plus
--       AUCUNE politique : illisibles par l'écran des moyens de paiement ;
--   C12 un ticket se créait sur une session close (K09) ;
--   M7  la vente ne sortait pas le stock (57 → 57 après 2 vendus, K04) : la
--       sortie n'avait lieu qu'à la clôture, qui échouait ;
--   C11 l'OF était créé avec `product_id` NULL : jamais terminable (M04 :
--       « null value in column product_id of stock_valuation_layers »).
--
-- CE QUI EST POSÉ.
--   1. D-E : moyens de paiement par défaut — espèces 530000 (ouvre le tiroir),
--      carte 511200, chèque 511200 — posés pour chaque société existante et à
--      la création d'une société ; politiques et clés composites rétablies.
--   2. `create_pos_ticket(ticket, lignes, paiements)` : UN appel atomique —
--      ticket (totaux calculés par la base), lignes, paiements (somme = total),
--      sortie de stock par ligne au dépôt de la caisse. Refus sur une session
--      qui n'est pas ouverte (et garde BEFORE INSERT pour l'écriture directe).
--   3. La clôture : paiements reconstitués pour les tickets qui n'en ont pas,
--      attendu en tiroir = espèces seulement (déjà le cas depuis la 219), et
--      plus de double sortie de stock pour un ticket qui l'a déjà faite.
--   4. `void_pos_ticket` fait revenir le stock sorti au ticket.
--   5. C11 : un OF fabrique l'article de sa nomenclature (déduit si absent,
--      refusé si aucun).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Moyens de paiement (D-E) et paiements : garanties rétablies
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payment_methods_tenant_id_id_key') THEN
    ALTER TABLE public.pos_payment_methods ADD CONSTRAINT pos_payment_methods_tenant_id_id_key UNIQUE (tenant_id, id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payment_methods_tenant_id_fkey') THEN
    ALTER TABLE public.pos_payment_methods ADD CONSTRAINT pos_payment_methods_tenant_id_fkey
      FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payments_tenant_id_fkey') THEN
    ALTER TABLE public.pos_payments ADD CONSTRAINT pos_payments_tenant_id_fkey
      FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payments_ticket_id_fkey') THEN
    ALTER TABLE public.pos_payments ADD CONSTRAINT pos_payments_ticket_id_fkey
      FOREIGN KEY (tenant_id, ticket_id) REFERENCES public.pos_tickets(tenant_id, id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payments_payment_method_id_fkey') THEN
    ALTER TABLE public.pos_payments ADD CONSTRAINT pos_payments_payment_method_id_fkey
      FOREIGN KEY (tenant_id, payment_method_id) REFERENCES public.pos_payment_methods(tenant_id, id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_payments_amount_nonneg') THEN
    ALTER TABLE public.pos_payments ADD CONSTRAINT pos_payments_amount_nonneg CHECK (amount >= 0);
  END IF;
END $$;

ALTER TABLE public.pos_payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_payment_methods FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pos_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_payments FORCE ROW LEVEL SECURITY;

-- Les politiques « FOR ALL » de la 119 laissaient tout rôle de la société écrire
-- les moyens de paiement ET les paiements (un lecteur réécrivait le compte 530).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT polname, polrelid::regclass AS tbl FROM pg_policy
           WHERE polrelid IN ('public.pos_payment_methods'::regclass, 'public.pos_payments'::regclass) LOOP
    EXECUTE format('DROP POLICY %I ON %s', r.polname, r.tbl);
  END LOOP;
END $$;
DROP POLICY IF EXISTS tenant_select_pos_payment_methods ON public.pos_payment_methods;
CREATE POLICY tenant_select_pos_payment_methods ON public.pos_payment_methods
  FOR SELECT TO authenticated USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_pos_payment_methods ON public.pos_payment_methods;
CREATE POLICY tenant_insert_pos_payment_methods ON public.pos_payment_methods
  FOR INSERT TO authenticated WITH CHECK (tenant_id = current_tenant_id() AND can_perform('pos_payment_methods', 'insert'));
DROP POLICY IF EXISTS tenant_update_pos_payment_methods ON public.pos_payment_methods;
CREATE POLICY tenant_update_pos_payment_methods ON public.pos_payment_methods
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND can_perform('pos_payment_methods', 'update'))
  WITH CHECK (tenant_id = current_tenant_id() AND can_perform('pos_payment_methods', 'update'));
DROP POLICY IF EXISTS tenant_delete_pos_payment_methods ON public.pos_payment_methods;
CREATE POLICY tenant_delete_pos_payment_methods ON public.pos_payment_methods
  FOR DELETE TO authenticated USING (tenant_id = current_tenant_id() AND can_perform('pos_payment_methods', 'delete'));

-- Un paiement encaissé est une pièce NF-525 : il s'écrit par le ticket (RPC) et
-- ne se réécrit pas.
DROP POLICY IF EXISTS tenant_select_pos_payments ON public.pos_payments;
CREATE POLICY tenant_select_pos_payments ON public.pos_payments
  FOR SELECT TO authenticated USING (tenant_id = current_tenant_id());
-- Politiques d'écriture gardées (périmètre PERM-01, comme `pos_tickets`) : elles
-- valent pour les fonctions de caisse qui écrivent sous RLS forcée ; un
-- utilisateur, lui, n'a plus aucun droit d'écriture sur la table.
DROP POLICY IF EXISTS tenant_insert_pos_payments ON public.pos_payments;
CREATE POLICY tenant_insert_pos_payments ON public.pos_payments
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform('pos_payments', 'insert'));
DROP POLICY IF EXISTS tenant_update_pos_payments ON public.pos_payments;
CREATE POLICY tenant_update_pos_payments ON public.pos_payments
  FOR UPDATE USING (tenant_id = current_tenant_id() AND can_perform('pos_payments', 'update'))
  WITH CHECK (tenant_id = current_tenant_id() AND can_perform('pos_payments', 'update'));
DROP POLICY IF EXISTS tenant_delete_pos_payments ON public.pos_payments;
CREATE POLICY tenant_delete_pos_payments ON public.pos_payments
  FOR DELETE USING (tenant_id = current_tenant_id() AND can_perform('pos_payments', 'delete'));
REVOKE ALL ON public.pos_payments FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.pos_payments FROM authenticated;
GRANT SELECT ON public.pos_payments TO authenticated;
REVOKE ALL ON public.pos_payment_methods FROM PUBLIC, anon;
REVOKE TRUNCATE ON public.pos_payment_methods FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_payment_methods TO authenticated;

DROP TRIGGER IF EXISTS set_tenant_id_pos_payment_methods ON public.pos_payment_methods;
CREATE TRIGGER set_tenant_id_pos_payment_methods
  BEFORE INSERT ON public.pos_payment_methods
  FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id();

-- Interne : non exposée (société en paramètre).
CREATE OR REPLACE FUNCTION public.ensure_pos_payment_methods(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF p_tenant_id IS NULL THEN RETURN; END IF;
  INSERT INTO pos_payment_methods (tenant_id, name, type, account_code, opens_cash_drawer, is_active, display_order)
  SELECT p_tenant_id, d.name, d.type, d.account_code, d.opens, true, d.ord
  FROM (VALUES ('Espèces', 'cash', '530000', true, 1),
               ('Carte bancaire', 'card', '511200', false, 2),
               ('Chèque', 'check', '511200', false, 3)) d(name, type, account_code, opens, ord)
  WHERE NOT EXISTS (SELECT 1 FROM pos_payment_methods m WHERE m.tenant_id = p_tenant_id AND m.type = d.type);
END $$;
REVOKE EXECUTE ON FUNCTION public.ensure_pos_payment_methods(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tenant_default_pos_payment_methods()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  PERFORM ensure_pos_payment_methods(NEW.id);
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.tenant_default_pos_payment_methods() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tenant_default_pos_payment_methods ON public.tenants;
CREATE TRIGGER tenant_default_pos_payment_methods
  AFTER INSERT ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.tenant_default_pos_payment_methods();

DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM public.tenants LOOP
    PERFORM public.ensure_pos_payment_methods(r.id);
    n := n + 1;
  END LOOP;
  RAISE NOTICE '[X5/D-E] moyens de paiement par défaut vérifiés pour % société(s)', n;
END $$;

-- Le moyen de paiement d'une société pour un type (« cash », « card »…).
CREATE OR REPLACE FUNCTION public.pos_payment_method_for(p_tenant_id uuid, p_type text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_id uuid; v_type text;
BEGIN
  v_type := CASE lower(COALESCE(p_type, 'cash'))
              WHEN 'cash' THEN 'cash' WHEN 'especes' THEN 'cash' WHEN 'espèces' THEN 'cash'
              WHEN 'card' THEN 'card' WHEN 'cb' THEN 'card' WHEN 'carte' THEN 'card'
              WHEN 'check' THEN 'check' WHEN 'cheque' THEN 'check' WHEN 'chèque' THEN 'check'
              WHEN 'voucher' THEN 'voucher' WHEN 'transfer' THEN 'transfer'
              ELSE 'other' END;
  PERFORM ensure_pos_payment_methods(p_tenant_id);
  SELECT id INTO v_id FROM pos_payment_methods
  WHERE tenant_id = p_tenant_id AND type = v_type AND COALESCE(is_active, true)
  ORDER BY display_order, created_at LIMIT 1;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Aucun moyen de paiement « % » actif pour cette société (Caisse → Moyens de paiement)', v_type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.pos_payment_method_for(uuid, text) FROM PUBLIC, anon, authenticated;

-- Tickets d'une session sans paiement ventilé : un paiement = total, moyen déduit.
CREATE OR REPLACE FUNCTION public.pos_backfill_session_payments(p_tenant_id uuid, p_session_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT tk.id, tk.total, tk.payment_method
    FROM pos_tickets tk
    WHERE tk.tenant_id = p_tenant_id AND tk.session_id = p_session_id AND tk.status = 'completed'
      AND COALESCE(tk.total, 0) > 0
      AND NOT EXISTS (SELECT 1 FROM pos_payments pp WHERE pp.tenant_id = tk.tenant_id AND pp.ticket_id = tk.id)
  LOOP
    INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount, transaction_reference)
    VALUES (p_tenant_id, r.id, pos_payment_method_for(p_tenant_id, r.payment_method), r.total,
            'Reconstitué à la clôture (281)');
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
REVOKE EXECUTE ON FUNCTION public.pos_backfill_session_payments(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 2. Le ticket : un seul appel, tout ou rien
-- ------------------------------------------------------------
-- Écriture directe : pas de ticket sur une session qui n'est pas ouverte.
CREATE OR REPLACE FUNCTION public.pos_ticket_session_open_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_st text; v_term uuid;
BEGIN
  SELECT status, terminal_id INTO v_st, v_term FROM pos_sessions
  WHERE id = NEW.session_id AND tenant_id = COALESCE(NEW.tenant_id, current_tenant_id());
  IF v_st IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Session de caisse % : un ticket ne s''enregistre que sur une session ouverte', COALESCE(v_st, 'introuvable')
      USING ERRCODE = '42501';
  END IF;
  IF NEW.terminal_id IS DISTINCT FROM v_term THEN
    RAISE EXCEPTION 'Ticket et session de caisse de terminaux différents' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.pos_ticket_session_open_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS a_pos_ticket_session_open ON public.pos_tickets;
CREATE TRIGGER a_pos_ticket_session_open
  BEFORE INSERT ON public.pos_tickets
  FOR EACH ROW EXECUTE FUNCTION public.pos_ticket_session_open_guard();

CREATE OR REPLACE FUNCTION public.create_pos_ticket(p_ticket jsonb, p_lines jsonb, p_payments jsonb DEFAULT NULL)
RETURNS public.pos_tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_sess record;
  v_wh uuid;
  v_tk public.pos_tickets;
  v_l jsonb;
  v_p jsonb;
  a record;
  v_ht numeric := 0;
  v_tva numeric := 0;
  v_total numeric;
  v_method text;
  v_received numeric;
  v_paid numeric := 0;
  v_n int := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF NOT can_perform('pos_tickets', 'insert') THEN
    RAISE EXCEPTION 'Le rôle courant n''a pas le droit d''encaisser' USING ERRCODE = '42501';
  END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Un ticket porte au moins une ligne' USING ERRCODE = 'check_violation';
  END IF;

  SELECT ps.id, ps.status, ps.terminal_id, t.warehouse_id
    INTO v_sess
  FROM pos_sessions ps
  JOIN pos_terminals t ON t.id = ps.terminal_id AND t.tenant_id = ps.tenant_id
  WHERE ps.id = NULLIF(p_ticket->>'session_id', '')::uuid AND ps.tenant_id = v_tid
  FOR SHARE OF ps;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session de caisse introuvable dans la société courante' USING ERRCODE = '42501';
  END IF;
  IF v_sess.status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Session de caisse close : un ticket ne s''enregistre que sur une session ouverte' USING ERRCODE = '42501';
  END IF;
  v_wh := COALESCE(v_sess.warehouse_id, resolve_default_warehouse(v_tid));

  -- Totaux : calculés par la base, ligne à ligne (comme les factures)
  FOR v_l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF COALESCE((v_l->>'quantity')::numeric, 0) <= 0 THEN
      RAISE EXCEPTION 'Ligne de ticket : la quantité doit être positive' USING ERRCODE = 'check_violation';
    END IF;
    a := line_amounts((v_l->>'quantity')::numeric, (v_l->>'unit_price')::numeric, (v_l->>'vat_rate')::numeric);
    v_ht := v_ht + a.total;
    v_tva := v_tva + a.vat;
  END LOOP;
  v_total := v_ht + v_tva;

  v_method := COALESCE(NULLIF(p_ticket->>'payment_method', ''), 'cash');
  v_received := COALESCE(NULLIF(p_ticket->>'amount_paid', '')::numeric, v_total);
  IF v_method = 'cash' AND v_received < v_total THEN
    RAISE EXCEPTION 'Montant reçu (%) inférieur au total du ticket (%)', v_received, v_total USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, customer_id, date,
                           subtotal, vat_total, total, payment_method, amount_paid, change_given,
                           status, notes)
  VALUES (v_tid, COALESCE(NULLIF(p_ticket->>'number', ''), 'T'), v_sess.id, v_sess.terminal_id,
          NULLIF(p_ticket->>'customer_id', '')::uuid,
          COALESCE(NULLIF(p_ticket->>'date', '')::timestamptz, now()),
          v_ht, v_tva, v_total, v_method,
          CASE WHEN v_method = 'cash' THEN v_received ELSE v_total END,
          CASE WHEN v_method = 'cash' THEN GREATEST(v_received - v_total, 0) ELSE 0 END,
          'completed', NULLIF(p_ticket->>'notes', ''))
  RETURNING * INTO v_tk;

  FOR v_l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    a := line_amounts((v_l->>'quantity')::numeric, (v_l->>'unit_price')::numeric, (v_l->>'vat_rate')::numeric);
    INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (v_tid, v_tk.id, NULLIF(v_l->>'product_id', '')::uuid, COALESCE(NULLIF(v_l->>'description', ''), 'Article'),
            (v_l->>'quantity')::numeric, COALESCE((v_l->>'unit_price')::numeric, 0),
            COALESCE((v_l->>'vat_rate')::numeric, 0), a.total);
  END LOOP;

  -- Paiements : fournis (multi-moyens) ou déduits du moyen du ticket
  IF p_payments IS NOT NULL AND jsonb_typeof(p_payments) = 'array' AND jsonb_array_length(p_payments) > 0 THEN
    FOR v_p IN SELECT * FROM jsonb_array_elements(p_payments) LOOP
      INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount, transaction_reference)
      VALUES (v_tid, v_tk.id,
              COALESCE((SELECT m.id FROM pos_payment_methods m
                        WHERE m.id = NULLIF(v_p->>'payment_method_id', '')::uuid AND m.tenant_id = v_tid),
                       pos_payment_method_for(v_tid, v_p->>'type')),
              (v_p->>'amount')::numeric, NULLIF(v_p->>'reference', ''));
      v_paid := v_paid + (v_p->>'amount')::numeric;
    END LOOP;
    IF v_paid <> v_total THEN
      RAISE EXCEPTION 'Paiements (%) différents du total du ticket (%)', v_paid, v_total USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount)
    VALUES (v_tid, v_tk.id, pos_payment_method_for(v_tid, v_method), v_total);
  END IF;

  -- M7 : la vente sort le stock, ligne par ligne, au dépôt de la caisse
  FOR v_l IN
    SELECT jsonb_build_object('product_id', l.product_id, 'quantity', sum(l.quantity), 'name', min(p.name))
    FROM pos_ticket_lines l
    JOIN products p ON p.id = l.product_id AND p.tenant_id = l.tenant_id
    WHERE l.ticket_id = v_tk.id AND l.tenant_id = v_tid AND COALESCE(p.type, 'stock') = 'stock'
    GROUP BY l.product_id
  LOOP
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity,
                                 reference, reference_type, reference_id, date, movement_date, notes)
    VALUES (v_tid, (v_l->>'product_id')::uuid, v_wh, 'out', 'out', (v_l->>'quantity')::numeric,
            'TK-' || v_tk.number, 'pos_ticket', v_tk.id, CURRENT_DATE, CURRENT_DATE,
            'Vente en caisse — ' || (v_l->>'name'));
    v_n := v_n + 1;
  END LOOP;

  RETURN v_tk;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_ticket(jsonb, jsonb, jsonb) TO authenticated, service_role;

-- Retour du stock sorti au ticket (annulation) : entrée miroir au coût moyen.
CREATE OR REPLACE FUNCTION public.pos_ticket_stock_return(p_tenant_id uuid, p_ticket_id uuid, p_reference_type text)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT sm.product_id, sm.warehouse_id, sm.quantity, sm.reference,
           COALESCE(NULLIF((SELECT sq.unit_cost FROM stock_quantities sq
                             WHERE sq.tenant_id = sm.tenant_id AND sq.product_id = sm.product_id
                               AND sq.warehouse_id = sm.warehouse_id), 0),
                    NULLIF(p.cost_price, 0), NULLIF(p.purchase_price, 0), 0) AS cout
    FROM stock_movements sm
    JOIN products p ON p.id = sm.product_id AND p.tenant_id = sm.tenant_id
    WHERE sm.tenant_id = p_tenant_id AND sm.reference_type = 'pos_ticket'
      AND sm.reference_id = p_ticket_id AND sm.movement_type = 'out'
  LOOP
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
                                 reference, reference_type, reference_id, date, movement_date, notes)
    VALUES (p_tenant_id, r.product_id, r.warehouse_id, 'in', 'in', r.quantity, r.cout,
            r.reference, p_reference_type, p_ticket_id, CURRENT_DATE, CURRENT_DATE,
            'Retour en stock — annulation de ' || r.reference);
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
REVOKE EXECUTE ON FUNCTION public.pos_ticket_stock_return(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 3. La clôture (corps de la 219, deux ajouts marqués « 281 »)
-- ------------------------------------------------------------
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
  -- 219 : ventilation de la TVA par taux, et écart de caisse
  v_rate record;
  v_line_vat numeric;
  v_rest numeric;
  v_acc text;
  v_cash_expected numeric := 0;
  v_cash_account text;
  v_diff numeric := 0;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  -- LOT2-13 : utiliser NEW.id::text comme fallback
  v_session_ref := COALESCE(NEW.session_number, NEW.id::text);

  -- 281 (C12) : un ticket enregistré avant la 281, ou sans paiement ventilé,
  -- reçoit son paiement ici (moyen déduit de `payment_method`, montant = total) :
  -- sans lui, l'écriture de clôture n'avait aucun débit et était refusée.
  PERFORM pos_backfill_session_payments(v_tid, NEW.id);

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

  -- R-13 : la TVA se ventile par TAUX (un compte par taux du plan), au lieu
  -- d'une seule ligne 445710 pour toute la session.
  IF v_total_vat > 0 THEN
    v_rest := v_total_vat;
    FOR v_rate IN
      SELECT l.vat_rate AS rate,
             round(sum(l.line_total * l.vat_rate / 100), 2) AS tva
      FROM pos_ticket_lines l
      JOIN pos_tickets pt ON pt.id = l.ticket_id AND pt.tenant_id = l.tenant_id
      WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pt.tenant_id = v_tid
        AND COALESCE(l.vat_rate, 0) > 0
      GROUP BY 1
      ORDER BY 1 DESC   -- le taux le plus élevé absorbe l'écart d'arrondi
    LOOP
      -- Le ticket fait foi : la ventilation ne peut pas dépasser son total
      v_line_vat := LEAST(COALESCE(v_rate.tva, 0), v_rest);
      IF v_line_vat > 0 THEN
        v_acc := pos_vat_account(v_tid, v_rate.rate);
        INSERT INTO journal_lines (
          tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
        ) VALUES (
          v_tid, v_je_id, v_line_num, v_acc, 0, v_line_vat, now(),
          'TVA collectée ' || v_rate.rate || ' % — ' || v_session_ref
        );
        v_line_num := v_line_num + 1;
        v_rest := v_rest - v_line_vat;
      END IF;
    END LOOP;

    -- Lignes sans taux exploitable : le reste va au compte de repli, qui
    -- appartient au plan exigé (chart_required_accounts, 201).
    IF v_rest > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES (
        v_tid, v_je_id, v_line_num, '445710', 0, v_rest, now(),
        'TVA collectée — ' || v_session_ref
      );
      v_line_num := v_line_num + 1;
    END IF;
  END IF;

  -- R-13 : l'écart de caisse. Le comptage porte sur les ESPÈCES — le reste dû
  -- par carte ou chèque ne se compte pas dans le tiroir. L'attendu est recalculé
  -- ici, sur les paiements espèces seuls, puis écrit sur la session : le serveur
  -- fait foi, l'écran ne le calcule plus.
  SELECT COALESCE(sum(pp.amount), 0), min(ppm.account_code)
    INTO v_cash_expected, v_cash_account
  FROM pos_payments pp
  JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
  JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
  WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    AND ppm.type = 'cash';

  v_diff := COALESCE(NEW.closing_amount, 0)
            - (COALESCE(NEW.opening_amount, 0) + v_cash_expected);

  -- Le serveur fait foi : l'attendu et l'écart sont écrits sur la ligne AVANT
  -- qu'elle ne soit enregistrée (trigger BEFORE), pour que l'appelant — l'écran —
  -- lise l'écart calculé par le serveur et non celui qu'il a proposé.
  NEW.expected_amount := COALESCE(NEW.opening_amount, 0) + v_cash_expected;
  NEW.difference := v_diff;

  -- Manquant : la caisse a moins que l'attendu → charge 658. Excédent : produit
  -- 758. Le compte de caisse est celui du moyen de paiement espèces (jamais un
  -- compte en dur) ; si la session en utilise plusieurs, l'écart va au premier
  -- par ordre de compte — un tiroir physique, un compte.
  IF v_diff <> 0 AND v_cash_account IS NOT NULL THEN
    IF v_diff < 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES
        (v_tid, v_je_id, v_line_num, '658000', -v_diff, 0, now(),
         'Écart de caisse — manquant ' || v_session_ref),
        (v_tid, v_je_id, v_line_num + 1, v_cash_account, 0, -v_diff, now(),
         'Écart de caisse — manquant ' || v_session_ref);
    ELSE
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES
        (v_tid, v_je_id, v_line_num, v_cash_account, v_diff, 0, now(),
         'Écart de caisse — excédent ' || v_session_ref),
        (v_tid, v_je_id, v_line_num + 1, '758000', 0, v_diff, now(),
         'Écart de caisse — excédent ' || v_session_ref);
    END IF;
    v_line_num := v_line_num + 2;
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
      -- 281 (M7) : la vente sort le stock AU TICKET ; seuls les tickets
      -- antérieurs (sans sortie propre) sortent encore à la clôture.
      AND NOT EXISTS (SELECT 1 FROM stock_movements sm
                      WHERE sm.tenant_id = pt.tenant_id AND sm.reference_type = 'pos_ticket'
                        AND sm.reference_id = pt.id)
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

-- ------------------------------------------------------------
-- 4. L'annulation (corps de la 250, ajout marqué « 281 »)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.void_pos_ticket(p_ticket_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tk record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : une annulation se fait dans le contexte d''une société.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT can_perform('pos_tickets', 'update') THEN
    RAISE EXCEPTION 'Le rôle courant n''a pas le droit d''annuler un ticket de caisse.'
      USING ERRCODE = '42501';
  END IF;

  SELECT tk.*, ps.status AS session_status
  INTO v_tk
  FROM pos_tickets tk
  JOIN pos_sessions ps ON ps.id = tk.session_id AND ps.tenant_id = tk.tenant_id
  WHERE tk.id = p_ticket_id AND tk.tenant_id = v_tid
  FOR UPDATE OF tk;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % : introuvable dans la société courante.', p_ticket_id
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.status <> 'completed' OR COALESCE(v_tk.is_voided, false) THEN
    RAISE EXCEPTION 'Ticket % : déjà annulé (statut « % »). Une annulation ne s''écrit qu''une fois.', v_tk.number, v_tk.status
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.session_status = 'closed' THEN
    RAISE EXCEPTION 'Session de caisse clôturée : la vente % est comptabilisée. Émettre un ticket d''annulation (avoir) au lieu de réécrire celui-ci.', v_tk.number
      USING ERRCODE = '42501';
  END IF;

  UPDATE pos_tickets
  SET status = 'cancelled',
      is_voided = true,
      voided_at = now(),
      void_reason = NULLIF(btrim(COALESCE(p_reason, '')), '')
  WHERE id = p_ticket_id AND tenant_id = v_tid;

  -- Le journal NF-525 dit désormais qu'un ticket a changé (avant la 250, trois
  -- événements d'insertion et rien sur la réécriture).
  -- 281 (M7) : la vente avait sorti le stock au ticket ; l'annulation le fait
  -- revenir (entrée miroir au coût moyen du dépôt), avec son écriture ST.
  PERFORM pos_ticket_stock_return(v_tid, p_ticket_id, 'pos_ticket_void');

  PERFORM log_nf525_event(
    'pos_ticket_voided',
    'pos_ticket',
    p_ticket_id,
    jsonb_build_object(
      'number', v_tk.number,
      'total', v_tk.total,
      'hash', v_tk.ticket_hash,
      'reason', p_reason,
      'terminal_id', v_tk.terminal_id,
      'sequential_number', v_tk.sequential_number
    ),
    NULL,
    to_char(now(), 'YYYY-MM')
  );
END $function$;

-- ------------------------------------------------------------
-- 5. C11 : un OF fabrique l'article de sa nomenclature
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.manufacturing_order_product_from_bom()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_prod uuid;
BEGIN
  IF NEW.bom_id IS NOT NULL THEN
    SELECT product_id INTO v_prod FROM boms WHERE id = NEW.bom_id AND tenant_id = NEW.tenant_id;
    IF NEW.product_id IS NULL THEN
      NEW.product_id := v_prod;
    ELSIF v_prod IS NOT NULL AND NEW.product_id IS DISTINCT FROM v_prod THEN
      RAISE EXCEPTION 'OF % : l''article fabriqué n''est pas celui de sa nomenclature', NEW.number
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.product_id IS NULL THEN
    RAISE EXCEPTION 'OF % : aucun article à fabriquer (choisir une nomenclature qui porte un article)', NEW.number
      USING ERRCODE = 'not_null_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.manufacturing_order_product_from_bom() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS a_manufacturing_order_product ON public.manufacturing_orders;
CREATE TRIGGER a_manufacturing_order_product
  BEFORE INSERT ON public.manufacturing_orders
  FOR EACH ROW EXECUTE FUNCTION public.manufacturing_order_product_from_bom();

-- OF déjà en base sans article : on le déduit de la nomenclature quand elle en porte un.
UPDATE public.manufacturing_orders mo SET product_id = b.product_id
FROM public.boms b
WHERE mo.product_id IS NULL AND b.id = mo.bom_id AND b.tenant_id = mo.tenant_id AND b.product_id IS NOT NULL;

-- ------------------------------------------------------------
-- 6. Ce qu'un lecteur ne doit pas écrire (M8, révélé par ces écrans) :
-- l'immobilisation se crée enfin (C13) — le balayage du lecteur y trouve une
-- ligne, et un lecteur la modifiait. Même mécanisme que 271, 274, 275, 280.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.guard_writes_with_can_perform(p_tables text[])
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE r record; v_action text; v_garde text; v_qual text; v_wc text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name, p.polname, p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS wc
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relname = ANY (p_tables) AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd', '*')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN CONTINUE; END IF;
    IF r.polcmd = '*' THEN
      -- politique ALL scindée : les noms dérivent de l'ancienne (une table peut
      -- déjà porter un « <table>_select »)
      EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.table_name);
      -- une lecture existe déjà (politique SELECT propre) : ne pas la doubler (238)
      IF NOT EXISTS (SELECT 1 FROM pg_policy p2 WHERE p2.polrelid = ('public.' || quote_ident(r.table_name))::regclass
                     AND p2.polpermissive AND p2.polcmd = 'r') THEN
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT USING (%s)', r.polname || '_r', r.table_name, r.qual);
      END IF;
      EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT WITH CHECK ((%s) AND can_perform(%L, ''insert''))',
                     r.polname || '_a', r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE USING ((%s) AND can_perform(%L, ''update'')) WITH CHECK ((%s) AND can_perform(%L, ''update''))',
                     r.polname || '_w', r.table_name, r.qual, r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE USING ((%s) AND can_perform(%L, ''delete''))',
                     r.polname || '_d', r.table_name, r.qual, r.table_name);
      v_n := v_n + 4;
      CONTINUE;
    END IF;
    v_action := CASE r.polcmd WHEN 'a' THEN 'insert' WHEN 'w' THEN 'update' ELSE 'delete' END;
    v_garde := format('can_perform(%L, %L)', r.table_name, v_action);
    IF r.polcmd = 'a' THEN
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', r.polname, r.table_name, v_wc);
    ELSIF r.polcmd = 'd' THEN
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', r.polname, r.table_name, v_qual);
    ELSE
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', r.polname, r.table_name, v_qual, v_wc);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

DO $$
DECLARE v_n int;
BEGIN
  v_n := pg_temp.guard_writes_with_can_perform(ARRAY['fixed_assets']);
  RAISE NOTICE '[X5/M8] % politique(s) d''écriture gardée(s) par can_perform', v_n;
END $$;
