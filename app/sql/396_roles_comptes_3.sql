-- 396 — roles_comptes_3
-- Numéro pris le 2026-10-11T09:32:18.858Z par migration-numero.mjs (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).

-- ═══════════════════════════════════════════════════════════════════════════
-- 396 — roles_comptes_3 : les comptes en dur, tranche 4 (LOC1-10)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les trois DERNIÈRES fonctions mesurées par le garde-fou E01
-- (7 occurrences) passent leurs comptes aux rôles — correspondances EXACTES au
-- pack PCG, donc AUCUNE écriture ne change :
--
--   post_pos_session_on_close        531000 → CAISSE_POS
--                                    707000 → VENTES_MARCHANDISES (×2)
--                                    445710 → TVA_COLLECTEE (×2)
--                                    et son journal `CA` → JOURNAL_CAISSE
--   post_exchange_gain_loss_on_payment  411000 → CLIENTS (×2)
--                                    766000 → GAINS_CHANGE (×2)
--                                    666000 → PERTES_CHANGE (×2)
--   propagate_analytic_section       706000 / 707000 → PRESTATIONS_SERVICES /
--                                    VENTES_MARCHANDISES ; 607000 →
--                                    ACHATS_MARCHANDISES
--
-- Comme en 395 : on corrige TOUT ce qui était en dur, pas seulement ce que la
-- règle comptait. La caisse du POS (531000), la TVA collectée (445710) et les
-- écarts de change (766000 / 666000) ne portaient pas de nom « compte » sur leur
-- ligne — le garde-fou ne les voyait pas ; ce n'en sont pas moins des comptes
-- en dur, et un pays qui lit son propre plan ne peut pas les garder.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Clôture de caisse : caisse, ventes comptoir et TVA
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_pos_session_on_close()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_journal text;
  v_caisse text;
  v_ventes text;
  v_tva text;
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

  -- LOC1-10 : la caisse du point de vente (CAISSE_POS = 531000), les ventes
  -- comptoir (VENTES_MARCHANDISES = 707000) et la TVA collectée (445710) viennent
  -- des rôles — résolues UNE fois, avant les trois écritures qui les emploient.
  -- Le journal de caisse aussi (`CA`), et il est garanti (LOC1-09).
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_CAISSE');
  v_caisse := resolve_account(NEW.tenant_id, 'CAISSE_POS');
  v_ventes := resolve_account(NEW.tenant_id, 'VENTES_MARCHANDISES');
  v_tva := resolve_account(NEW.tenant_id, 'TVA_COLLECTEE');

  -- LOT2-12 : utiliser NEW.closed_at au lieu de entry_date
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number
  ) VALUES (
    NEW.tenant_id, 'JE-POS-' || NEW.id, COALESCE(NEW.closed_at, NOW())::date, v_journal,
    'draft', 'Clôture caisse ' || NEW.id, 'POS-' || NEW.id
  )
  RETURNING id INTO v_entry_id;

  -- Ligne caisse (débit)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, v_caisse, v_caisse,
    v_ttc, 0, 'Caisse', 0
  );

  -- LOT2-11 : tl.subtotal → tl.line_total (pos_ticket_lines a line_total, pas subtotal)
  FOR v_ligne IN
    SELECT
      COALESCE(p.sale_account_code, pc.sale_account_code, v_ventes) AS compte,
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
      NEW.tenant_id, v_entry_id, v_ventes, v_ventes,
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

    -- LOC1-10 : sans correspondance de TVA propre à la société, le rôle.
    v_compte_tva := COALESCE(v_compte_tva, v_tva);

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
      NEW.tenant_id, v_entry_id, v_tva, v_tva,
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
$function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Écart de change sur règlement : client, gain, perte
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_exchange_gain_loss_on_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inv invoices%ROWTYPE;
  v_fonc text;
  v_dev text;
  v_taux numeric;
  v_montant_dev numeric;
  v_ecart numeric;
  v_collectif text;
  v_entry uuid;
  v_num text;
  v_taux_paiement numeric;
  v_journal text;
  v_gain text;
  v_perte text;
BEGIN
  -- Seulement à l'entrée dans les statuts qui comptent le règlement
  IF NOT (NEW.status IN ('recorded', 'reconciled')) THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.invoice_id IS NULL THEN RETURN NEW; END IF;
  -- Déjà traité : le montant d'écart est posé
  IF COALESCE(NEW.exchange_gain_loss, 0) <> 0 THEN RETURN NEW; END IF;

  SELECT * INTO v_inv FROM public.invoices
  WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_fonc := public.functional_currency(NEW.tenant_id);
  v_dev := COALESCE(NULLIF(v_inv.currency_code, ''), v_fonc);
  -- Une pièce en devise de tenue n'a pas d'écart de change
  IF v_dev = v_fonc THEN RETURN NEW; END IF;
  -- Règlement dans une autre devise que la pièce : hors périmètre (taux croisé)
  IF COALESCE(NULLIF(NEW.currency_code, ''), v_dev) <> v_dev THEN RETURN NEW; END IF;

  v_taux := COALESCE(NULLIF(v_inv.exchange_rate, 0), 1);
  v_montant_dev := COALESCE(NEW.amount_currency, NEW.amount);
  -- Ce qui a été encaissé, contre ce que la pièce a valu au grand livre :
  -- positif → on a encaissé **plus** que comptabilisé (gain), négatif → perte.
  v_ecart := round(COALESCE(NEW.amount, 0) - v_montant_dev * v_taux, 2);
  IF v_ecart = 0 THEN RETURN NEW; END IF;

  -- LOC1-10 : le collectif client, et les deux comptes d'écart (GAINS_CHANGE =
  -- 766000, PERTES_CHANGE = 666000) viennent des rôles.
  SELECT COALESCE(c.account_collectif, resolve_account(NEW.tenant_id, 'CLIENTS')) INTO v_collectif
  FROM public.customers c
  WHERE c.id = v_inv.customer_id AND c.tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, resolve_account(NEW.tenant_id, 'CLIENTS'));
  v_gain := resolve_account(NEW.tenant_id, 'GAINS_CHANGE');
  v_perte := resolve_account(NEW.tenant_id, 'PERTES_CHANGE');

  -- LOC1-09 : le journal vient du RÔLE
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_OD');

  v_num := 'ECART-' || COALESCE(NULLIF(NEW.number, ''), left(NEW.id::text, 8));
  INSERT INTO public.journal_entries (
    tenant_id, number, date, journal_code, status, description, reference, piece_number
  ) VALUES (
    NEW.tenant_id, v_num, COALESCE(NEW.payment_date, CURRENT_DATE), v_journal, 'draft',
    'Écart de change sur règlement ' || COALESCE(NEW.number, ''), v_num, v_num
  ) RETURNING id INTO v_entry;

  IF v_ecart > 0 THEN
    -- Encaissé plus que comptabilisé : gain
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      account_tiers, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, NULL, v_ecart, 0, 'Écart de change (gain) — ' || v_num, 0);
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_gain, v_gain, 0, v_ecart, 'Gain de change — ' || v_num, 1);
  ELSE
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_perte, v_perte, abs(v_ecart), 0, 'Perte de change — ' || v_num, 0);
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      account_tiers, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, NULL, 0, abs(v_ecart), 'Écart de change (perte) — ' || v_num, 1);
  END IF;

  UPDATE public.journal_entries SET status = 'posted'
  WHERE id = v_entry AND tenant_id = NEW.tenant_id;

  v_taux_paiement := CASE WHEN v_montant_dev <> 0
                          THEN round(COALESCE(NEW.amount, 0) / v_montant_dev, 6) ELSE v_taux END;

  INSERT INTO public.exchange_gain_loss_entries (
    tenant_id, payment_id, invoice_id, type, amount,
    exchange_rate_original, exchange_rate_payment,
    account_gain_code, account_loss_code, journal_entry_id
  ) VALUES (
    NEW.tenant_id, NEW.id, NEW.invoice_id, 'receivable', abs(v_ecart),
    v_taux, v_taux_paiement, v_gain, v_perte, v_entry
  );

  UPDATE public.customer_payments
  SET exchange_gain_loss = v_ecart
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Propagation analytique : les comptes de la ligne d'origine
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_analytic_section()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_plan text;
  v_section text;
  v_pct numeric;
  v_base numeric;
  v_ref text;
  v_inv_ref text;
  v_piece text;
  v_journal text;
  v_sec uuid;
  v_compte text := COALESCE(NEW.account_code, NEW.account_general);
  v_grille jsonb;
  v_avoir uuid := NULLIF(current_setting('app.credit_note_validating', true), '')::uuid;
  v_services text;
  v_ventes text;
  v_achats text;
BEGIN
  -- ── 1. La ventilation multi-axes donne la section et le montant ──────────
  IF NEW.analytic_distribution IS NOT NULL
     AND jsonb_typeof(NEW.analytic_distribution) = 'object'
     AND NEW.analytic_distribution <> '{}'::jsonb THEN

    -- La section **dominante** (plus fort pourcentage) donne la section plate, et
    -- le montant analytique suit le pourcentage appliqué à l'assiette de la ligne.
    SELECT p.key, s.key, (s.value)::numeric
    INTO v_plan, v_section, v_pct
    FROM jsonb_each(NEW.analytic_distribution) p,
         LATERAL jsonb_each(CASE WHEN jsonb_typeof(p.value) = 'object' THEN p.value ELSE '{}'::jsonb END) s
    WHERE (s.value)::text ~ '^-?[0-9]+(\.[0-9]+)?$'
    ORDER BY (s.value)::numeric DESC, s.key
    LIMIT 1;

    IF v_section IS NOT NULL THEN
      IF NEW.analytic_section_id IS NULL THEN
        NEW.analytic_section_id := v_section::uuid;
      END IF;
      IF NEW.analytic_amount IS NULL OR NEW.analytic_amount = 0 THEN
        v_base := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
        NEW.analytic_amount := round(v_base * v_pct / 100.0, 2);
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.analytic_section_id IS NOT NULL OR v_compte IS NULL OR v_compte !~ '^[67]' THEN
    RETURN NEW;
  END IF;

  -- LOC1-10 : les comptes de produit et de charge employés plus bas viennent des
  -- rôles (PRESTATIONS_SERVICES = 706000, VENTES_MARCHANDISES = 707000,
  -- ACHATS_MARCHANDISES = 607000). Résolus ICI, une fois qu'on sait que la ligne
  -- porte un compte de gestion : une ligne de bilan n'a pas à dépendre du pack.
  v_services := resolve_account(NEW.tenant_id, 'PRESTATIONS_SERVICES');
  v_ventes := resolve_account(NEW.tenant_id, 'VENTES_MARCHANDISES');
  v_achats := resolve_account(NEW.tenant_id, 'ACHATS_MARCHANDISES');

  -- ── 2. La section de la ligne de **document** d'origine ─────────────────
  -- ANA-02 : les écritures engendrées (ventes, achats) naissent d'un document
  -- qui sait à quoi la dépense ou le produit se rattache. La ligne d'écriture
  -- porte le compte ; la ligne de document porte la section : on les apparie par
  -- le numéro du document et par le compte.
  SELECT e.invoice_ref, e.reference, e.piece_number, e.journal_code
  INTO v_inv_ref, v_ref, v_piece, v_journal
  FROM journal_entries e
  WHERE e.id = NEW.journal_id AND e.tenant_id = NEW.tenant_id;

  -- Avoirs de vente (353) : l'avoir en cours de validation (contexte), sinon celui
  -- dont l'écriture porte le numéro en numéro de pièce. Même résolution de compte
  -- que `credit_note_guard`.
  IF v_avoir IS NOT NULL OR v_piece IS NOT NULL THEN
    SELECT cl.analytic_section_id INTO v_sec
    FROM credit_notes cn
    JOIN credit_note_lines cl ON cl.credit_note_id = cn.id AND cl.tenant_id = cn.tenant_id
    LEFT JOIN products p ON p.id = cl.product_id AND p.tenant_id = cn.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = cn.tenant_id
    WHERE cn.tenant_id = NEW.tenant_id
      AND (cn.id = v_avoir OR (v_avoir IS NULL AND cn.number = v_piece))
      AND cl.analytic_section_id IS NOT NULL
      AND COALESCE(p.sale_account_code, pc.sale_account_code, cl.account_code,
                   CASE WHEN p.type = 'service' THEN v_services ELSE v_ventes END) = v_compte
    ORDER BY cl.line_order, cl.id
    LIMIT 1;

    -- Lignes d'avoir SANS article : `credit_note_guard` les passe aux comptes de
    -- l'écriture d'origine au prorata, à défaut au 709000 — le compte ne se déduit
    -- pas de la ligne. La première ligne libre qui porte une section la donne.
    IF v_sec IS NULL THEN
      SELECT cl.analytic_section_id INTO v_sec
      FROM credit_notes cn
      JOIN credit_note_lines cl ON cl.credit_note_id = cn.id AND cl.tenant_id = cn.tenant_id
      WHERE cn.tenant_id = NEW.tenant_id
        AND (cn.id = v_avoir OR (v_avoir IS NULL AND cn.number = v_piece))
        AND cl.product_id IS NULL
        AND cl.analytic_section_id IS NOT NULL
        AND v_compte ~ '^7'
      ORDER BY cl.line_order, cl.id
      LIMIT 1;
    END IF;
  END IF;

  IF v_sec IS NULL AND COALESCE(v_inv_ref, v_ref) IS NOT NULL THEN
    -- Ventes : compte de produit de l'article, sinon de sa catégorie, sinon le
    -- rôle VENTES_MARCHANDISES (PCG : 707000)
    SELECT il.analytic_section_id INTO v_sec
    FROM invoices i
    JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = i.tenant_id
    LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = i.tenant_id
    LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = i.tenant_id
    WHERE i.tenant_id = NEW.tenant_id
      AND i.number IN (v_inv_ref, v_ref)
      AND il.analytic_section_id IS NOT NULL
      AND COALESCE(p.sale_account_code, pc.sale_account_code, v_ventes) = v_compte
    LIMIT 1;

    -- Achats : compte de charge de l'article, sinon de sa catégorie, sinon le
    -- rôle ACHATS_MARCHANDISES (PCG : 607000)
    IF v_sec IS NULL THEN
      SELECT pil.analytic_section_id INTO v_sec
      FROM purchase_invoices pi
      JOIN purchase_invoice_lines pil ON pil.purchase_invoice_id = pi.id AND pil.tenant_id = pi.tenant_id
      LEFT JOIN products p ON p.id = pil.product_id AND p.tenant_id = pi.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = pi.tenant_id
      WHERE pi.tenant_id = NEW.tenant_id
        AND pi.number IN (v_inv_ref, v_ref)
        AND pil.analytic_section_id IS NOT NULL
        AND COALESCE(p.purchase_account_code, pc.purchase_account_code, v_achats) = v_compte
      LIMIT 1;
    END IF;
  END IF;

  IF v_sec IS NOT NULL THEN
    NEW.analytic_section_id := v_sec;
    IF NEW.analytic_amount IS NULL OR NEW.analytic_amount = 0 THEN
      NEW.analytic_amount := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
    END IF;
    RETURN NEW;
  END IF;

  -- ── 3. La grille de ventilation du compte (353) ─────────────────────────
  -- Personne n'a rien choisi : la grille du compte s'applique, si elle est
  -- entièrement valide. Les parts sont écrites après l'insertion de la ligne
  -- (`journal_line_materialize_grill`), reconnue par son identifiant.
  IF TG_OP = 'INSERT' THEN
    v_grille := analytic_grill_distribution(NEW.tenant_id, v_compte, v_journal);
    IF v_grille IS NOT NULL THEN
      SELECT s.key, (s.value)::numeric INTO v_section, v_pct
      FROM jsonb_each(v_grille) p, LATERAL jsonb_each(p.value) s
      ORDER BY (s.value)::numeric DESC, s.key
      LIMIT 1;

      v_base := COALESCE(NULLIF(NEW.debit, 0), NEW.credit, 0);
      NEW.analytic_distribution := v_grille;
      NEW.analytic_section_id := v_section::uuid;
      NEW.analytic_amount := round(v_base * v_pct / 100.0, 2);
      PERFORM set_config('app.analytic_grill_line', NEW.id::text, true);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

