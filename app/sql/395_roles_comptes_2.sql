-- 395 — roles_comptes_2
-- Numéro pris le 2026-10-11T09:23:07.433Z par migration-numero.mjs (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).

-- ═══════════════════════════════════════════════════════════════════════════
-- 395 — roles_comptes_2 : les comptes en dur des AVOIRS (LOC1-10, tranche 3)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les deux triggers d'avoir portaient encore leurs comptes en
-- clair — 6 occurrences mesurées par le garde-fou E01. Correspondances EXACTES
-- au pack PCG, donc AUCUNE écriture ne change :
--
--   credit_note_guard           411000 → CLIENTS
--                               706000 → PRESTATIONS_SERVICES (prestation)
--                               707000 → VENTES_MARCHANDISES (marchandise)
--                               709000 → RRR_ACCORDES
--                               445710 → TVA_COLLECTEE
--   purchase_credit_note_guard  401000 → FOURNISSEURS
--                               609000 → RRR_OBTENUS
--                               445660 → TVA_DEDUCTIBLE_BIENS_SERVICES
--
-- Le garde-fou n'en comptait que 6 sur 9 : un compte passé en ARGUMENT à un
-- helper (`post_credit_reversal(…, '709000', …)`) ou affecté à une variable
-- (`v_vat_acc := COALESCE(v_vat_acc, '445710')`) ne porte pas de nom « compte »
-- sur sa ligne. La règle est un INSTRUMENT, pas un oracle : on corrige tout ce
-- qui était écrit en dur, pas seulement ce qui était compté.
--
-- Le JOURNAL, lui, est déjà passé par le rôle en `393` (VT pour l'avoir client,
-- AC pour l'avoir fournisseur) : cette migration ne fait que les COMPTES.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Avoir client : collectif, ventes, RRR et TVA par les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.credit_note_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_src uuid;
  v_noart numeric;
  v_inv invoices%ROWTYPE;
  v_other numeric; v_n int; v_ht numeric; v_tva numeric;
  v_collectif text; v_tiers text; v_entry uuid; v_ordre int := 1; r record; v_vat_acc text;
  v_journal text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := COALESCE(NEW.status, 'draft');
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'Un avoir est créé en brouillon puis validé' USING ERRCODE = 'check_violation';
    END IF;
    NEW.number := draft_document_number('AV', NEW.id);
    NEW.transferred_entry_id := NULL;
    RETURN NEW;
  END IF;

  IF OLD.status IN ('validated', 'applied') THEN
    IF NEW.status = 'draft'
       OR (NEW.number, NEW.date, NEW.customer_id, NEW.invoice_id, NEW.subtotal, NEW.vat_total, NEW.total, NEW.tenant_id)
          IS DISTINCT FROM
          (OLD.number, OLD.date, OLD.customer_id, OLD.invoice_id, OLD.subtotal, OLD.vat_total, OLD.total, OLD.tenant_id) THEN
      RAISE EXCEPTION 'Avoir % validé : il n''est plus modifiable', OLD.number USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  NEW.number := OLD.number;
  SELECT count(*), COALESCE(sum(total), 0), COALESCE(sum(vat_amount), 0) INTO v_n, v_ht, v_tva
  FROM credit_note_lines WHERE credit_note_id = NEW.id;
  IF v_n > 0 THEN
    NEW.subtotal := v_ht; NEW.vat_total := v_tva; NEW.total := v_ht + v_tva;
  END IF;
  IF NEW.status = 'draft' THEN RETURN NEW; END IF;

  -- Validation : rattachement, cohérence, numéro, écriture
  NEW.invoice_id := COALESCE(NEW.invoice_id, NEW.source_invoice_id);
  IF NEW.invoice_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM invoices WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Facture d''origine introuvable' USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.validation_status IS DISTINCT FROM 'validated' THEN
      RAISE EXCEPTION 'La facture d''origine % n''est pas validée', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    NEW.customer_id := COALESCE(NEW.customer_id, v_inv.customer_id);
    IF NEW.customer_id IS DISTINCT FROM v_inv.customer_id THEN
      RAISE EXCEPTION 'L''avoir et la facture % concernent deux clients différents', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(sum(total), 0) INTO v_other FROM credit_notes
    WHERE invoice_id = NEW.invoice_id AND id <> NEW.id AND status IN ('validated', 'applied');
    IF NEW.total > COALESCE(v_inv.total, 0) - v_other THEN
      RAISE EXCEPTION 'Avoir de % supérieur au montant restant à créditer sur la facture % (%)',
        NEW.total, v_inv.number, COALESCE(v_inv.total, 0) - v_other USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.customer_id IS NULL THEN
    RAISE EXCEPTION 'Un avoir doit être rattaché à une facture ou à un client' USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(NEW.total, 0) <= 0 OR NEW.total <> COALESCE(NEW.subtotal, 0) + COALESCE(NEW.vat_total, 0) THEN
    RAISE EXCEPTION 'Avoir incohérent : HT % + TVA % ≠ TTC %', NEW.subtotal, NEW.vat_total, NEW.total
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.number := next_legal_document_number(NEW.tenant_id, 'AV', NEW.date);
  NEW.validated_at := now();

  -- LOC1-10 : le collectif client vient du RÔLE (PCG : CLIENTS = 411000).
  SELECT COALESCE(account_collectif, resolve_account(NEW.tenant_id, 'CLIENTS')), account_tiers
    INTO v_collectif, v_tiers
  FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, resolve_account(NEW.tenant_id, 'CLIENTS'));

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_VENTES');

  -- B4 (ven-012) : l'ecriture de l'avoir porte la reference de la facture
  -- d'origine, pour que le lettrage automatique la rattache.
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, v_journal, 'draft', 'Avoir client ' || NEW.number,
          (SELECT i.number FROM invoices i WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id),
          NEW.number)
  RETURNING id INTO v_entry;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, v_tiers, NEW.customer_id,
          0, NEW.total, 'Client ' || NEW.number, 0);

  -- R-05 : écriture de la facture d'origine, dont les comptes seront contre-passés
  IF NEW.invoice_id IS NOT NULL THEN
    SELECT transferred_entry_id INTO v_src FROM invoices
    WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
  END IF;

  IF v_n > 0 THEN
    -- lignes portant un article : compte de vente de l'article, sinon le rôle de
    -- sa NATURE — prestation ou marchandise (PCG : 706000 / 707000).
    FOR r IN
      SELECT COALESCE(p.sale_account_code, pc.sale_account_code, l.account_code,
                    CASE WHEN p.type = 'service'
                         THEN resolve_account(NEW.tenant_id, 'PRESTATIONS_SERVICES')
                         ELSE resolve_account(NEW.tenant_id, 'VENTES_MARCHANDISES') END) AS compte,
             sum(l.total) AS montant
      FROM credit_note_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.credit_note_id = NEW.id AND l.product_id IS NOT NULL GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, r.montant, 0, 'Avoir ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    -- R-05 : lignes sans article → comptes de l'écriture d'origine, au prorata ;
    -- le repli de tête est le rôle RRR_ACCORDES (PCG : 709000).
    SELECT COALESCE(sum(total), 0) INTO v_noart FROM credit_note_lines
    WHERE credit_note_id = NEW.id AND product_id IS NULL;
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, v_noart, '7',
                                    resolve_account(NEW.tenant_id, 'RRR_ACCORDES'),
                                    'Avoir ' || NEW.number, v_ordre);

    FOR r IN SELECT vat_code, sum(vat_amount) AS tva FROM credit_note_lines WHERE credit_note_id = NEW.id GROUP BY 1 LOOP
      SELECT account_code INTO v_vat_acc FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = r.vat_code AND direction = 'collected'
      ORDER BY tenant_id DESC LIMIT 1;
      -- LOC1-10 : sans correspondance de TVA propre à la société, le rôle
      -- TVA_COLLECTEE (PCG : 445710).
      v_vat_acc := COALESCE(v_vat_acc, resolve_account(NEW.tenant_id, 'TVA_COLLECTEE'));
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, vat_code, vat_amount,
                                 debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, r.vat_code, r.tva, r.tva, 0,
              'TVA collectée ' || r.vat_code || ' — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
  ELSE
    -- R-05 : avoir sans aucune ligne (remise globale) — même règle
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, NEW.subtotal, '7',
                                    resolve_account(NEW.tenant_id, 'RRR_ACCORDES'),
                                    'Remise ' || NEW.number, 1);
    IF COALESCE(NEW.vat_total, 0) <> 0 THEN
      v_vat_acc := resolve_account(NEW.tenant_id, 'TVA_COLLECTEE');
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, NEW.vat_total, 0, 'TVA collectée — ' || NEW.number, v_ordre);
    END IF;
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Avoir fournisseur : collectif, RRR et TVA par les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.purchase_credit_note_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_src uuid;
  v_noart numeric;
  v_inv purchase_invoices%ROWTYPE; v_other numeric;
  v_collectif text; v_tiers text; v_entry uuid;
  v_n int; v_ht numeric; v_tva numeric; v_ordre int := 1; r record; v_vat_acc text;
  v_journal text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := COALESCE(NEW.status, 'draft');
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'Un avoir fournisseur est saisi en brouillon puis validé' USING ERRCODE = 'check_violation';
    END IF;
    NEW.supplier_reference := COALESCE(NEW.supplier_reference, NEW.number);
    NEW.number := draft_document_number('AVF', NEW.id);
    NEW.transferred_entry_id := NULL;
    RETURN NEW;
  END IF;

  IF OLD.status IN ('validated', 'applied') THEN
    IF NEW.status = 'draft'
       OR (NEW.number, NEW.date, NEW.supplier_id, NEW.purchase_invoice_id, NEW.subtotal, NEW.vat_total, NEW.total, NEW.tenant_id)
          IS DISTINCT FROM
          (OLD.number, OLD.date, OLD.supplier_id, OLD.purchase_invoice_id, OLD.subtotal, OLD.vat_total, OLD.total, OLD.tenant_id) THEN
      RAISE EXCEPTION 'Avoir fournisseur % validé : il n''est plus modifiable', OLD.number USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  NEW.number := OLD.number;
  SELECT count(*), COALESCE(sum(total), 0), COALESCE(sum(vat_amount), 0) INTO v_n, v_ht, v_tva
  FROM purchase_credit_lines WHERE purchase_credit_id = NEW.id;
  IF v_n > 0 THEN
    NEW.subtotal := v_ht; NEW.vat_total := v_tva; NEW.total := v_ht + v_tva;
  END IF;
  IF NEW.status = 'draft' THEN RETURN NEW; END IF;

  IF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM purchase_invoices WHERE id = NEW.purchase_invoice_id AND tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Facture fournisseur d''origine introuvable' USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.approval_status IS DISTINCT FROM 'approved' THEN
      RAISE EXCEPTION 'La facture fournisseur d''origine % n''est pas approuvée', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    NEW.supplier_id := COALESCE(NEW.supplier_id, v_inv.supplier_id);
    IF NEW.supplier_id IS DISTINCT FROM v_inv.supplier_id THEN
      RAISE EXCEPTION 'L''avoir et la facture % concernent deux fournisseurs différents', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(sum(total), 0) INTO v_other FROM purchase_credit_notes
    WHERE purchase_invoice_id = NEW.purchase_invoice_id AND id <> NEW.id AND status IN ('validated', 'applied');
    IF NEW.total > COALESCE(v_inv.total, 0) - v_other THEN
      RAISE EXCEPTION 'Avoir de % supérieur au montant restant à créditer sur la facture % (%)',
        NEW.total, v_inv.number, COALESCE(v_inv.total, 0) - v_other USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Un avoir fournisseur doit être rattaché à une facture ou à un fournisseur' USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(NEW.total, 0) <= 0 OR NEW.total <> COALESCE(NEW.subtotal, 0) + COALESCE(NEW.vat_total, 0) THEN
    RAISE EXCEPTION 'Avoir fournisseur incohérent : HT % + TVA % ≠ TTC %', NEW.subtotal, NEW.vat_total, NEW.total
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.number := next_legal_document_number(NEW.tenant_id, 'AVF', NEW.date);
  NEW.validated_at := now();

  -- LOC1-10 : le collectif fournisseur vient du RÔLE (PCG : FOURNISSEURS = 401000).
  SELECT COALESCE(account_collectif, resolve_account(NEW.tenant_id, 'FOURNISSEURS')), account_tiers
    INTO v_collectif, v_tiers
  FROM suppliers WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, resolve_account(NEW.tenant_id, 'FOURNISSEURS'));

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_ACHATS');

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, v_journal, 'draft', 'Avoir fournisseur ' || NEW.number, NEW.number)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, v_tiers, NEW.supplier_id, NEW.total, 0, 'Fournisseur ' || NEW.number, 0);

  -- R-05 : écriture de la facture d'origine, dont les comptes seront contre-passés
  IF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT transferred_entry_id INTO v_src FROM purchase_invoices
    WHERE id = NEW.purchase_invoice_id AND tenant_id = NEW.tenant_id;
  END IF;
  IF v_n > 0 THEN
    FOR r IN
      SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code,
                      resolve_account(NEW.tenant_id, 'RRR_OBTENUS')) AS compte,
             sum(l.total) AS montant
      FROM purchase_credit_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.purchase_credit_id = NEW.id AND l.product_id IS NOT NULL GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, 0, r.montant, 'Avoir obtenu ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    -- R-05 : lignes sans article → comptes de charges de l'écriture d'origine,
    -- le repli de tête étant le rôle RRR_OBTENUS (PCG : 609000).
    SELECT COALESCE(sum(total), 0) INTO v_noart FROM purchase_credit_lines
    WHERE purchase_credit_id = NEW.id AND product_id IS NULL;
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, v_noart,
                                    '6', resolve_account(NEW.tenant_id, 'RRR_OBTENUS'),
                                    'Avoir obtenu ' || NEW.number, v_ordre);

    FOR r IN SELECT vat_code, sum(vat_amount) AS tva FROM purchase_credit_lines
             WHERE purchase_credit_id = NEW.id AND NOT vat_reverse_charge(NEW.tenant_id, vat_code) GROUP BY 1 LOOP
      SELECT account_code INTO v_vat_acc FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = r.vat_code AND direction = 'deductible'
      ORDER BY tenant_id DESC LIMIT 1;
      -- LOC1-10 : sans correspondance de TVA, le rôle
      -- TVA_DEDUCTIBLE_BIENS_SERVICES (PCG : 445660).
      v_vat_acc := COALESCE(v_vat_acc, resolve_account(NEW.tenant_id, 'TVA_DEDUCTIBLE_BIENS_SERVICES'));
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, vat_code, vat_amount,
                                 debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, r.vat_code, r.tva, 0, r.tva,
              'TVA déductible ' || r.vat_code || ' — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    -- 197 : TVA autoliquidée — contre-passation de l'autoliquidation (C déductible / D due)
    FOR r IN SELECT vat_code, sum(vat_self_assessed(NEW.tenant_id, vat_code, total, vat_rate)) AS tva
             FROM purchase_credit_lines
             WHERE purchase_credit_id = NEW.id AND vat_reverse_charge(NEW.tenant_id, vat_code) GROUP BY 1 LOOP
      v_ordre := v_ordre + post_reverse_charge_vat(NEW.tenant_id, v_entry, r.vat_code, r.tva, -1, v_ordre, NEW.number);
    END LOOP;
  ELSE
    -- R-05 : avoir fournisseur sans aucune ligne — même règle
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, NEW.subtotal,
                                    '6', resolve_account(NEW.tenant_id, 'RRR_OBTENUS'),
                                    'Avoir obtenu ' || NEW.number, 1);
    IF COALESCE(NEW.vat_total, 0) <> 0 THEN
      v_vat_acc := resolve_account(NEW.tenant_id, 'TVA_DEDUCTIBLE_BIENS_SERVICES');
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, 0, NEW.vat_total, 'TVA déductible — ' || NEW.number, v_ordre);
    END IF;
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $function$;

