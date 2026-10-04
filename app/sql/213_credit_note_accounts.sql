-- ============================================================
-- 213_credit_note_accounts.sql — R-05 : avoirs sans article
--
-- Un avoir sans ligne d'article rattaché à une facture était imputé au compte
-- par défaut — 709000 (remise accordée) côté client, 609000 (rabais obtenu)
-- côté fournisseur. Le chiffre d'affaires constaté en 706000 ou 707000 n'était
-- donc jamais corrigé : la ventilation des produits et des charges restait
-- fausse, et les états financiers avec elle.
--
-- Règle retenue : quand l'avoir est rattaché à une facture, il **contre-passe
-- les comptes de l'écriture d'origine, au prorata de leurs montants**, le
-- centime d'arrondi étant absorbé par la dernière ligne. Sans facture
-- d'origine, l'avoir reste une remise commerciale (709000 / 609000).
--
-- Preuves : sql/213_credit_note_accounts_tests.sql (E23, E23b, E23c, A10, A10b).
-- Les deux fonctions sont reprises de leur DERNIÈRE version (190 pour l'avoir
-- client, 197 pour l'avoir fournisseur, qui y a ajouté l'autoliquidation) :
-- seule la branche « avoir sans ligne » change.
-- 709000 / 609000 et les comptes de TVA sont des valeurs françaises provisoires
-- (lot K : rôles de comptes du pack pays).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Répartition d'un montant au prorata des comptes d'une écriture
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION prorata_source_accounts(p_entry uuid, p_amount numeric, p_class text)
RETURNS TABLE (compte text, montant numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- Côté ventes (classe 7) les produits sont au crédit de l'écriture d'origine ;
  -- côté achats (classe 6), les charges sont au débit.
  WITH src AS (
    SELECT jl.account_code,
           CASE WHEN p_class = '7' THEN sum(jl.credit) - sum(jl.debit)
                                   ELSE sum(jl.debit) - sum(jl.credit) END AS base
    FROM journal_lines jl
    WHERE p_entry IS NOT NULL AND jl.journal_id = p_entry AND jl.account_code LIKE p_class || '%'
    GROUP BY jl.account_code
    HAVING CASE WHEN p_class = '7' THEN sum(jl.credit) - sum(jl.debit)
                                   ELSE sum(jl.debit) - sum(jl.credit) END > 0
  ), o AS (
    SELECT account_code, base,
           row_number() OVER (ORDER BY account_code) AS rn,
           count(*) OVER () AS n,
           sum(base) OVER () AS total
    FROM src
  ), calc AS (
    SELECT account_code, rn, n,
           ROUND(ROUND(COALESCE(p_amount, 0), 2) * base / total, 2) AS part
    FROM o WHERE total > 0 AND COALESCE(p_amount, 0) > 0
  )
  -- la dernière ligne absorbe l'arrondi : la somme rendue vaut exactement p_amount
  SELECT account_code,
         CASE WHEN rn = n
              THEN ROUND(COALESCE(p_amount, 0), 2)
                   - COALESCE(sum(part) OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
              ELSE part END
  FROM calc
  ORDER BY rn
$$;
REVOKE ALL ON FUNCTION prorata_source_accounts(uuid, numeric, text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION prorata_source_accounts(uuid, numeric, text) IS
  'R-05 : répartit un montant sur les comptes de classe p_class d''une écriture, au prorata ; la dernière ligne absorbe l''arrondi.';


-- ------------------------------------------------------------
-- 2. Contrepassation d'un montant : comptes de l'écriture d'origine, sinon défaut
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION post_credit_reversal(p_tenant uuid, p_entry uuid, p_src uuid,
  p_amount numeric, p_class text, p_default text, p_label text, p_order int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE r record; v_o int := p_order; v_any boolean := false;
BEGIN
  IF COALESCE(p_amount, 0) = 0 THEN RETURN v_o; END IF;
  FOR r IN SELECT * FROM prorata_source_accounts(p_src, p_amount, p_class) LOOP
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (p_tenant, p_entry, r.compte, r.compte,
            CASE WHEN p_class = '7' THEN r.montant ELSE 0 END,
            CASE WHEN p_class = '7' THEN 0 ELSE r.montant END,
            p_label || ' — contrepassation', v_o);
    v_o := v_o + 1; v_any := true;
  END LOOP;
  IF NOT v_any THEN
    -- pas de facture d'origine (ou écriture sans compte de cette classe) : remise
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (p_tenant, p_entry, p_default, p_default,
            CASE WHEN p_class = '7' THEN p_amount ELSE 0 END,
            CASE WHEN p_class = '7' THEN 0 ELSE p_amount END,
            p_label, v_o);
    v_o := v_o + 1;
  END IF;
  RETURN v_o;
END $$;
REVOKE ALL ON FUNCTION post_credit_reversal(uuid, uuid, uuid, numeric, text, text, text, int) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION post_credit_reversal(uuid, uuid, uuid, numeric, text, text, text, int) IS
  'R-05 : impute un montant d''avoir aux comptes de l''écriture d''origine au prorata, ou au compte de remise par défaut.';

-- ------------------------------------------------------------
-- 3. Avoir client (reprise de la 190)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION credit_note_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src uuid;
  v_noart numeric;
  v_inv invoices%ROWTYPE;
  v_other numeric; v_n int; v_ht numeric; v_tva numeric;
  v_collectif text; v_tiers text; v_entry uuid; v_ordre int := 1; r record; v_vat_acc text;
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

  SELECT COALESCE(account_collectif, '411000'), account_tiers INTO v_collectif, v_tiers
  FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '411000');

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, 'VT', 'draft', 'Avoir client ' || NEW.number, NEW.number)
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
    -- lignes portant un article : compte de vente de l'article
    FOR r IN
      SELECT COALESCE(p.sale_account_code, pc.sale_account_code, '707000') AS compte, sum(l.total) AS montant
      FROM credit_note_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.credit_note_id = NEW.id AND l.product_id IS NOT NULL GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, r.montant, 0, 'Avoir ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    -- R-05 : lignes sans article → comptes de l'écriture d'origine, au prorata
    SELECT COALESCE(sum(total), 0) INTO v_noart FROM credit_note_lines
    WHERE credit_note_id = NEW.id AND product_id IS NULL;
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, v_noart, '7', '709000',
                                    'Avoir ' || NEW.number, v_ordre);

    FOR r IN SELECT vat_code, sum(vat_amount) AS tva FROM credit_note_lines WHERE credit_note_id = NEW.id GROUP BY 1 LOOP
      SELECT account_code INTO v_vat_acc FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = r.vat_code AND direction = 'collected'
      ORDER BY tenant_id DESC LIMIT 1;
      v_vat_acc := COALESCE(v_vat_acc, '445710');
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, vat_code, vat_amount,
                                 debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, r.vat_code, r.tva, r.tva, 0,
              'TVA collectée ' || r.vat_code || ' — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
  ELSE
    -- R-05 : avoir sans aucune ligne (remise globale) — même règle
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, NEW.subtotal, '7', '709000',
                                    'Remise ' || NEW.number, 1);
    IF COALESCE(NEW.vat_total, 0) <> 0 THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, '445710', '445710', NEW.vat_total, 0, 'TVA collectée — ' || NEW.number, v_ordre);
    END IF;
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 4. Avoir fournisseur (reprise de la 197 : l'autoliquidation y est traitée ;
--    repartir de la 192 l'annulerait — vu rouge sur 197/V06 et 192/A08)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_credit_note_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src uuid;
  v_noart numeric;
  v_inv purchase_invoices%ROWTYPE; v_other numeric;
  v_collectif text; v_tiers text; v_entry uuid;
  v_n int; v_ht numeric; v_tva numeric; v_ordre int := 1; r record; v_vat_acc text;
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

  SELECT COALESCE(account_collectif, '401000'), account_tiers INTO v_collectif, v_tiers
  FROM suppliers WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '401000');

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, 'AC', 'draft', 'Avoir fournisseur ' || NEW.number, NEW.number)
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
      SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code, '609000') AS compte, sum(l.total) AS montant
      FROM purchase_credit_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.purchase_credit_id = NEW.id AND l.product_id IS NOT NULL GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, 0, r.montant, 'Avoir obtenu ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    -- R-05 : lignes sans article → comptes de charges de l'écriture d'origine
    SELECT COALESCE(sum(total), 0) INTO v_noart FROM purchase_credit_lines
    WHERE purchase_credit_id = NEW.id AND product_id IS NULL;
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, v_noart, '6', '609000',
                                    'Avoir obtenu ' || NEW.number, v_ordre);

    FOR r IN SELECT vat_code, sum(vat_amount) AS tva FROM purchase_credit_lines
             WHERE purchase_credit_id = NEW.id AND NOT vat_reverse_charge(NEW.tenant_id, vat_code) GROUP BY 1 LOOP
      SELECT account_code INTO v_vat_acc FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = r.vat_code AND direction = 'deductible'
      ORDER BY tenant_id DESC LIMIT 1;
      v_vat_acc := COALESCE(v_vat_acc, '445660');
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
    v_ordre := post_credit_reversal(NEW.tenant_id, v_entry, v_src, NEW.subtotal, '6', '609000',
                                    'Avoir obtenu ' || NEW.number, 1);
    IF COALESCE(NEW.vat_total, 0) <> 0 THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, '445660', '445660', 0, NEW.vat_total, 'TVA déductible — ' || NEW.number, v_ordre);
    END IF;
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $$;
