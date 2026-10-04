-- ============================================================
-- 255_pos_refund_ticket.sql — l'avoir existe comme pièce (POS-01, suite)
--
-- La 250 refuse d'annuler un ticket dont la session est clôturée — à juste
-- titre : la vente est comptabilisée. Son message dit « émettre un avoir », et
-- cet avoir n'existait pas : un ticket de caisse clôturé ne pouvait plus être
-- corrigé autrement qu'en base.
--
-- CE QUE LA MESURE A APPRIS, ET QUI CHANGE LE CORRECTIF. La première version de
-- ce fichier créait un « ticket d'annulation » à montants négatifs. Le schéma
-- l'a refusé, et il a raison de le faire — la caisse est protégée :
--     pos_tickets_subtotal_nonneg, pos_tickets_vat_total_nonneg,
--     pos_tickets_total_nonneg, pos_tickets_amount_paid_nonneg
-- Un ticket de caisse ne porte pas de montants négatifs. L'avoir n'est donc pas
-- un ticket : c'est un **avoir commercial** (`credit_notes`) — la pièce que
-- l'écran des avoirs porte, avec son numéro légal et son écriture.
--
-- Ce que `pos_refund_ticket()` fait, exactement :
--   1. la vente doit être **clôturée** (sinon `void_pos_ticket()` suffit), et
--      ne doit pas déjà porter d'avoir ;
--   2. elle doit être **nominative** : un avoir crédite quelqu'un, donc la vente
--      doit porter un client ;
--   3. l'avoir est créé **brouillon** avec les lignes de la vente, puis
--      **validé** dans un point de sauvegarde : s'il ne peut pas l'être (compte
--      manquant, plafond de la facture), l'avoir reste brouillon et son motif
--      dit pourquoi — l'utilisateur le complète dans l'écran des avoirs ;
--   4. le stock revient (une entrée miroir par produit vendu, au CUMP du dépôt,
--      `reference_type = 'pos_refund'`) ;
--   5. la vente d'origine passe à `refunded` — montants et empreinte intacts ;
--   6. le journal fiscal écrit `pos_ticket_refunded`, avec le numéro de l'avoir.
--
-- LIMITES DITES
--   * Le **décaissement** de caisse n'est pas écrit ici : l'avoir crédite le
--     client, et le règlement de ce crédit passe par les écrans de règlement.
--   * Un article suivi en lot demandera le lot sur le mouvement de retour (le
--     contrôle S-11 le refuse sans) : la caisse ne saisit pas le lot d'un retour.
-- ============================================================
CREATE OR REPLACE FUNCTION public.pos_refund_ticket(p_ticket_id uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tk record;
  v_wh uuid;
  v_cout numeric;
  v_av uuid;
  v_num text;
  v_nl int := 0;
  v_ligne RECORD;
  v_motif text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : un avoir se fait dans le contexte d''une société.' USING ERRCODE = '42501';
  END IF;

  IF NOT can_perform('pos_tickets', 'update') THEN
    RAISE EXCEPTION 'Le rôle courant n''a pas le droit d''émettre un avoir de caisse.' USING ERRCODE = '42501';
  END IF;

  SELECT tk.*, ps.status AS session_status
  INTO v_tk
  FROM pos_tickets tk
  JOIN pos_sessions ps ON ps.id = tk.session_id AND ps.tenant_id = tk.tenant_id
  WHERE tk.id = p_ticket_id AND tk.tenant_id = v_tid
  FOR UPDATE OF tk;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % : introuvable dans la société courante.', p_ticket_id USING ERRCODE = '42501';
  END IF;

  IF v_tk.session_status <> 'closed' THEN
    RAISE EXCEPTION 'La session du ticket % est encore ouverte : annuler le ticket (void_pos_ticket), sans avoir.', v_tk.number
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.status <> 'completed' OR COALESCE(v_tk.is_voided, false) THEN
    RAISE EXCEPTION 'Ticket % : statut « % » — un avoir ne s''écrit qu''une fois, sur une vente valide.', v_tk.number, v_tk.status
      USING ERRCODE = '42501';
  END IF;

  IF v_tk.customer_id IS NULL THEN
    RAISE EXCEPTION 'Ticket % : vente de comptoir sans client. Un avoir crédite une personne : rattachez d''abord un client à la vente.', v_tk.number
      USING ERRCODE = '42501';
  END IF;

  v_motif := 'Avoir de caisse sur le ticket ' || v_tk.number
    || CASE WHEN NULLIF(btrim(COALESCE(p_reason, '')), '') IS NOT NULL
            THEN ' — ' || btrim(p_reason) ELSE '' END;

  -- 1. L'avoir commercial : la pièce, créée brouillon (la 190 impose ce
  --    passage), rattachée à la facture quand la vente en a une.
  INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status,
                            subtotal, vat_total, total, reason, invoice_id, source_invoice_id)
  VALUES (v_tid, 'AV-CAISSE-' || left(v_tk.id::text, 8), v_tk.customer_id, NULL, CURRENT_DATE, 'draft',
          COALESCE(v_tk.subtotal, 0), COALESCE(v_tk.vat_total, 0), COALESCE(v_tk.total, 0),
          v_motif, v_tk.invoice_id, v_tk.invoice_id)
  RETURNING id INTO v_av;

  INSERT INTO credit_note_lines (tenant_id, credit_note_id, product_id, description, quantity,
                                 unit_price, vat_rate, total, vat_total, line_order)
  SELECT v_tid, v_av, l.product_id, 'AVOIR — ' || l.description, l.quantity,
         l.unit_price, l.vat_rate, COALESCE(l.line_total, 0),
         round(COALESCE(l.line_total, 0) * l.vat_rate / 100, 2), row_number() OVER ()
  FROM pos_ticket_lines l
  WHERE l.ticket_id = p_ticket_id AND l.tenant_id = v_tid;

  -- 2. La validation : la cohérence et l'écriture sont portées par le gardien
  --    des avoirs (190/213). S'il refuse — compte manquant, plafond de la
  --    facture d'origine — l'avoir RESTE, en brouillon, et son motif dit
  --    pourquoi : l'utilisateur le complète dans l'écran des avoirs.
  BEGIN
    UPDATE credit_notes SET status = 'validated' WHERE id = v_av AND tenant_id = v_tid;
  EXCEPTION WHEN others THEN
    UPDATE credit_notes
    SET reason = left(v_motif || ' [à valider : ' || SQLERRM || ']', 900)
    WHERE id = v_av AND tenant_id = v_tid;
  END;

  -- 3. Le stock revient : une entrée miroir par produit vendu, au CUMP du dépôt.
  SELECT t.warehouse_id INTO v_wh
  FROM pos_terminals t WHERE t.id = v_tk.terminal_id AND t.tenant_id = v_tid;

  FOR v_ligne IN
    SELECT l.product_id, SUM(l.quantity) AS qte
    FROM pos_ticket_lines l
    WHERE l.ticket_id = p_ticket_id AND l.tenant_id = v_tid AND l.product_id IS NOT NULL
    GROUP BY l.product_id
    HAVING SUM(l.quantity) > 0
  LOOP
    SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_cout
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_ligne.product_id AND sq.warehouse_id = v_wh;

    IF v_cout IS NULL THEN
      SELECT NULLIF(COALESCE(p.cost_price, 0), 0) INTO v_cout
      FROM products p WHERE p.id = v_ligne.product_id AND p.tenant_id = v_tid;
    END IF;

    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity,
                                 unit_cost, reference, reference_type, reference_id,
                                 date, movement_date, notes)
    VALUES (v_tid, v_ligne.product_id, v_wh, 'in', 'in', v_ligne.qte,
            COALESCE(v_cout, 0), 'POS-AV-' || v_tk.number, 'pos_refund', v_av,
            CURRENT_DATE, CURRENT_DATE, 'Avoir du ticket ' || v_tk.number);
    v_nl := v_nl + 1;
  END LOOP;

  -- 4. La vente d'origine reste lisible, et dit ce qu'elle est devenue.
  SELECT number INTO v_num FROM credit_notes WHERE id = v_av;

  UPDATE pos_tickets
  SET status = 'refunded',
      is_voided = true,
      voided_at = now(),
      void_reason = 'Avoir ' || COALESCE(v_num, v_av::text)
    WHERE id = p_ticket_id AND tenant_id = v_tid;

  -- 5. Le journal fiscal le dit, avec le numéro de l'avoir.
  PERFORM log_nf525_event(
    'pos_ticket_refunded',
    'pos_ticket',
    p_ticket_id,
    jsonb_build_object('number', v_tk.number, 'total', v_tk.total, 'hash', v_tk.ticket_hash,
                       'credit_note', v_av, 'reason', p_reason, 'stock_lines', v_nl),
    NULL,
    to_char(now(), 'YYYY-MM')
  );

  RETURN v_av;
END $$;

COMMENT ON FUNCTION public.pos_refund_ticket(uuid, text) IS
  '255 : l''avoir d''un ticket de caisse clôturé — un avoir commercial (credit_notes) créé puis validé quand c''est possible, les lignes de la vente, le stock rendu au CUMP, l''événement NF-525, et la vente d''origine marquée « refunded » (montants et empreinte intacts). Un ticket de caisse ne porte pas de montants négatifs : l''avoir est une pièce commerciale, pas un ticket.';

REVOKE ALL ON FUNCTION public.pos_refund_ticket(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pos_refund_ticket(uuid, text) TO authenticated;
