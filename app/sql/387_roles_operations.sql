-- ═══════════════════════════════════════════════════════════════════════════
-- 387 — roles_operations : les OPÉRATIONS sur les rôles (LOC1-07, tranche POS)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Première tranche de LOC1-07 : le **point de vente**. Le trigger
-- de clôture de caisse ne porte plus `'707000'` ni `'445710'` ni le journal
-- `'POS'` : il demande ses **rôles**. Cahier §5, tâche LOC1-07.
--
-- DEUX RÔLES DE JOURNAUX AJOUTÉS AU CATALOGUE. Le pack PCG portait 7 rôles de
-- journaux ; le POS et la production utilisent deux journaux de plus (`POS`,
-- `OF`, créés par `ensure_standard_journals`). Conformément à la règle de
-- LOC1-04 — « toute nouvelle fonction qui a besoin d'un compte AJOUTE un rôle
-- au catalogue » — on les nomme ici plutôt que de laisser un littéral.
--
-- ⚠ CE QUI RESTE EN DUR, ET POURQUOI. Les comptes d'ÉCART DE CAISSE (`658000`
-- manquant, `758000` excédent, l. 162/172) restent des littéraux : ce sont des
-- charges/produits hors exploitation qu'aucun rôle du catalogue (annexe B) ne
-- nomme encore. À trancher avec l'expert-comptable ; on ne les invente pas.
--
-- REJOUABLE : `INSERT … ON CONFLICT DO NOTHING`, `CREATE OR REPLACE`.
--
-- Numéro pris le 2026-10-05T21:05:15.863Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Les deux rôles de journaux manquants (catalogue + pack PCG)
-- ─────────────────────────────────────────────────────────────
INSERT INTO journal_role_catalog (role, journal_type, required_for) VALUES
  ('JOURNAL_POS',        'cash',    ARRAY['pos']),
  ('JOURNAL_PRODUCTION', 'general', ARRAY['manufacturing'])
ON CONFLICT (role) DO NOTHING;

INSERT INTO pack_journal_roles (pack_code, role, journal_code, journal_type) VALUES
  ('PCG', 'JOURNAL_POS',        'POS', 'cash'),
  ('PCG', 'JOURNAL_PRODUCTION', 'OF',  'general')
ON CONFLICT (pack_code, role) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 2. Clôture de caisse (POS) → journal POS, sur les rôles
-- ─────────────────────────────────────────────────────────────
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
  -- LOC1-07 : le journal et les comptes viennent des RÔLES
  v_journal text;
  v_ventes text;
  v_tva_repli text;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  v_journal   := resolve_journal(v_tid, 'JOURNAL_POS');
  v_ventes    := resolve_account(v_tid, 'VENTES_MARCHANDISES');
  v_tva_repli := resolve_account(v_tid, 'TVA_COLLECTEE');

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
    v_tid, v_journal, v_je_number, v_close_date,
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

  -- Crédit des ventes (le compte vient du RÔLE)
  INSERT INTO journal_lines (
    tenant_id, journal_id, line_order, account_code,
    debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_line_num, v_ventes, 0, v_total_sales, now()
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
    -- appartient au plan exigé (chart_required_accounts, 201) — le RÔLE ici.
    IF v_rest > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, line_order, account_code, debit, credit, created_at, description
      ) VALUES (
        v_tid, v_je_id, v_line_num, v_tva_repli, 0, v_rest, now(),
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
  -- 758. ⚠ Ces DEUX comptes restent des littéraux : aucun rôle du catalogue
  -- (annexe B) ne nomme l'écart de caisse — à trancher avec l'expert-comptable.
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
