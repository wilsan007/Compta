-- ============================================================
-- 317_invoice_direct_stock_and_line_accounts.sql — lot B (écrans Ventes)
--
-- Recette /qa du 29/09/2026. Le chemin « facture directe » et l'avoir client.
--
--   B2 (ven-008, haute) Une ligne de facture ne se choisissait pas dans le
--     catalogue : sans article, ni produit ni catégorie, tout le HT partait en
--     707000 — une prestation dont la fiche porte 706000 comprise. Mesuré :
--     707000 C 280,00 pour « 3 × livre + 1 × service » (attendu 707 C 30 /
--     706 C 250). La ligne porte désormais un compte de vente choisi
--     (`invoice_lines.account_code`) et la comptabilisation lit, dans l'ordre :
--     compte de l'article, compte de sa famille, compte de la ligne, puis
--     706000 pour une prestation et 707000 pour un bien.
--
--   D-QA-1 (tranchée le 30/09 : option a, avec garde anti-double) Une facture
--     directe d'un article stocké, **sans bon de livraison**, sort la
--     marchandise à la validation. Une ligne née d'un BL
--     (`invoice_lines.delivery_note_line_id`) ne ressort rien : la sortie du BL
--     (migration 314) existe déjà, et l'index unique `uq_stock_movement_source`
--     porte la garde.
--
--   B4 (ven-012, haute) L'avoir d'un article rendu était ventilé au prorata de
--     la facture d'origine (706 55,56 / 707 44,44) au lieu du compte de
--     l'article rendu, et son écriture ne portait pas `invoice_ref` — le
--     lettrage automatique ne pouvait pas la rattacher à la facture. L'avoir
--     suit la même hiérarchie de comptes que la facture (compte de ligne
--     compris) et son écriture porte la référence de la facture d'origine.
--
--   B6 (ven-006) Une facture née d'un BL n'avait pas de nom de client
--     (`customer_name` vide) : la liste affichait « — » et la recherche par nom
--     ne trouvait pas la pièce. Le nom est recopié à l'écriture, et l'existant
--     est rattrapé.
--
--   B7 (ven-007) / D-QA-2 (tranchée le 30/09 : option a) La validation refuse
--     une facture datée avant la dernière facture validée de la société.
--
-- Preuves : sql/317_*_tests.sql (rouges avant), suites voisines
-- 180/210/213/214/216/221 et banc écran.
-- 706000 / 707000 sont des valeurs françaises provisoires (pack pays, lot K).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Compte de vente d'une ligne libre (B2, B4)
-- ------------------------------------------------------------
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS account_code text;
COMMENT ON COLUMN invoice_lines.account_code IS
  'Compte de vente de la ligne quand elle ne porte pas d''article (B2, ven-008). Lu après le compte de l''article et de sa famille, avant le défaut 706000/707000.';

ALTER TABLE credit_note_lines ADD COLUMN IF NOT EXISTS account_code text;
COMMENT ON COLUMN credit_note_lines.account_code IS
  'Compte de vente de la ligne d''avoir quand elle ne porte pas d''article (B4, ven-012).';

-- ------------------------------------------------------------
-- 2. Facturation : compte de l'article, de la famille, de la ligne, 706/707
--    (reprise à l'identique de la 210 ; seule la résolution du compte change)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_journal_on_invoice_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '411000';
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 2;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_vente text := '707000';
  -- R-03 : acompte reçu et déduction d'acompte en 4191 (compte d'avances clients)
  v_compte_acompte text := '419100';
  v_is_advance boolean := COALESCE(NEW.invoice_type = 'advance' OR NEW.is_advance_invoice, false);
  v_adv uuid;
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'VT' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : récupérer le compte collectif et le compte auxiliaire du client
    SELECT COALESCE(c.account_collectif, '411000'), c.account_tiers, c.id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers c
    WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;

    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'VT', 'draft', 'Facture vente ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- Ligne client (débit ; nulle si l'acompte couvre toute la facture)
    IF COALESCE(NEW.total, 0) <> 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        account_tiers, third_party_id, echeance_date,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
        v_tiers, v_third_party, NEW.due_date,
        GREATEST(NEW.total, 0), GREATEST(-NEW.total, 0), 'Client ' || NEW.number, 0
      );
    END IF;

    -- ACC-03 : boucle sur les lignes de facture regroupées par compte de produit
    -- LOT2-01 : il.subtotal → il.total (subtotal n'existe pas sur invoice_lines)
    FOR v_ligne IN
      SELECT
        CASE WHEN v_is_advance OR il.advance_invoice_id IS NOT NULL THEN v_compte_acompte
             ELSE COALESCE(p.sale_account_code, pc.sale_account_code, il.account_code,
                        CASE WHEN p.type = 'service' THEN '706000' ELSE v_defaut_vente END) END AS compte,
        CASE WHEN v_is_advance THEN NEW.id ELSE il.advance_invoice_id END AS acompte,
        SUM(il.total) AS montant
      FROM invoice_lines il
      LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY 1, 2
    LOOP
      CONTINUE WHEN v_ligne.montant = 0;
      -- une déduction d'acompte (montant négatif) débite 4191 ; reference relie
      -- les lignes 4191 à leur facture d'acompte pour le lettrage
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, reference, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        GREATEST(-v_ligne.montant, 0), GREATEST(v_ligne.montant, 0),
        CASE WHEN v_ligne.acompte IS NULL THEN 'Ventes ' || v_ligne.compte || ' — ' || NEW.number
             WHEN v_is_advance THEN 'Acompte reçu — ' || NEW.number
             ELSE 'Déduction d''acompte — ' || NEW.number END,
        CASE WHEN v_ligne.acompte IS NOT NULL THEN 'ACOMPTE:' || v_ligne.acompte END,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 2 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_vente, v_defaut_vente,
        0, NEW.subtotal, 'Ventes ' || NEW.number, 1
      );
      v_ordre := 3;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA
    FOR v_vat IN
      SELECT il.vat_code,
             SUM(il.total) AS base_ht,
             SUM(il.vat_amount) AS montant_tva
      FROM invoice_lines il
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY il.vat_code
    LOOP
      CONTINUE WHEN v_vat.montant_tva = 0;
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'collected'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '445710');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        GREATEST(-v_vat.montant_tva, 0), GREATEST(v_vat.montant_tva, 0),
        'TVA collectée ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback TVA
    IF v_ordre = 2 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '445710', '445710',
        'FR20', NEW.vat_total,
        0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2
      );
    END IF;

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

    -- R-03 : acompte entièrement déduit → lettrage de ses lignes 4191
    FOR v_adv IN SELECT DISTINCT advance_invoice_id FROM invoice_lines
                 WHERE invoice_id = NEW.id AND tenant_id = NEW.tenant_id AND advance_invoice_id IS NOT NULL LOOP
      PERFORM letter_advance_invoice(NEW.tenant_id, v_adv);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- 3. D-QA-1 : une facture directe d'un article stocké sort le stock
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_stock_out_on_invoice_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ligne RECORD;
  v_wh uuid;
BEGIN
  -- Une facture directe (sans bon de livraison) d'un article stocké sort la
  -- marchandise à la validation. Les lignes nées d'un BL portent
  -- `delivery_note_line_id` : la sortie du bon (314) a déjà eu lieu, rien à
  -- refaire — c'est la garde anti-double de D-QA-1.
  FOR v_ligne IN
    SELECT il.product_id, sum(il.quantity) AS quantite, min(il.description) AS description
    FROM invoice_lines il
    LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = il.tenant_id
    WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      AND il.quantity > 0
      AND il.product_id IS NOT NULL
      AND il.delivery_note_line_id IS NULL
      AND COALESCE(p.type, 'stock') = 'stock'
    GROUP BY il.product_id
  LOOP
    v_wh := resolve_default_warehouse(NEW.tenant_id);

    -- Une sortie impossible (stock insuffisant) refuse la validation avec un
    -- message qui nomme la facture et l'article — pas un code brut.
    BEGIN
      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type, type, quantity,
        reference, reference_type, reference_id, date, movement_date, notes
      ) VALUES (
        NEW.tenant_id, v_ligne.product_id, v_wh, 'out', 'out', v_ligne.quantite,
        'FAC-' || NEW.number, 'invoice', NEW.id, NEW.date, NEW.date, v_ligne.description
      );
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Facture % : sortie de stock impossible pour « % » (quantité %) — %',
        NEW.number,
        COALESCE((SELECT p.name FROM products p WHERE p.id = v_ligne.product_id), v_ligne.product_id::text),
        v_ligne.quantite, SQLERRM
        USING ERRCODE = 'check_violation';
    END;

    -- S-07 : la marchandise est partie, la réservation de la commande l'est aussi
    PERFORM _release_sales_order_reservation(
      NEW.tenant_id,
      (SELECT o.sales_order_id FROM sales_order_lines o
       WHERE o.tenant_id = NEW.tenant_id
         AND o.id IN (SELECT sales_order_line_id FROM invoice_lines
                      WHERE invoice_id = NEW.id AND product_id = v_ligne.product_id
                        AND sales_order_line_id IS NOT NULL)
       LIMIT 1),
      v_ligne.product_id, v_ligne.quantite);
  END LOOP;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_invoice_stock_out ON invoices;
CREATE TRIGGER tg_invoice_stock_out
  AFTER UPDATE OF validation_status ON invoices
  FOR EACH ROW
  WHEN (NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated')
  EXECUTE FUNCTION create_stock_out_on_invoice_validate();

-- ------------------------------------------------------------
-- 4. B6 : le nom du client suit la facture (ven-006)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION invoice_fill_customer_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF COALESCE(NEW.customer_name, '') = '' AND NEW.customer_id IS NOT NULL THEN
    SELECT c.name INTO NEW.customer_name
    FROM customers c
    WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS a_invoice_fill_customer_name ON invoices;
CREATE TRIGGER a_invoice_fill_customer_name
  BEFORE INSERT OR UPDATE OF customer_id, customer_name ON invoices
  FOR EACH ROW EXECUTE FUNCTION invoice_fill_customer_name();

-- Rattrapage : les factures déjà nées d'un BL (B6)
UPDATE invoices i
SET customer_name = c.name
FROM customers c
WHERE c.id = i.customer_id
  AND c.tenant_id = i.tenant_id
  AND COALESCE(i.customer_name, '') = '';


-- ------------------------------------------------------------
-- 5. Avoir client : memes comptes que la facture, ecriture lettrable (B4)
--    (reprise a l identique de la 213 ; seul l ordre des comptes change)
-- ------------------------------------------------------------
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

  -- B4 (ven-012) : l'ecriture de l'avoir porte la reference de la facture
  -- d'origine, pour que le lettrage automatique la rattache.
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, 'VT', 'draft', 'Avoir client ' || NEW.number,
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
    -- lignes portant un article : compte de vente de l'article
    FOR r IN
      SELECT COALESCE(p.sale_account_code, pc.sale_account_code, l.account_code,
                    CASE WHEN p.type = 'service' THEN '706000' ELSE '707000' END) AS compte, sum(l.total) AS montant
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
END $function$;
-- ------------------------------------------------------------
-- 6. Numerotation chronologique (B7 / D-QA-2)
--    (reprise a l identique de la 190 ; seule la garde de date est ajoutee)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoice_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_ht numeric; v_tva numeric; v_n int; v_derniere_num text; v_derniere_date date;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.validation_status := COALESCE(NEW.validation_status, 'draft');
    IF NEW.validation_status = 'validated' THEN
      RAISE EXCEPTION 'Une facture est créée en brouillon puis validée (la validation attribue son numéro et son écriture)'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.number := draft_document_number('FAC', NEW.id);
    NEW.amount_paid := 0;
    NEW.amount_due := COALESCE(NEW.total, 0);
    RETURN NEW;
  END IF;

  -- Le payé ne se saisit pas : il résulte des règlements et avoirs (refresh_invoice_settlement)
  IF current_setting('app.settlement_in_progress', true) IS DISTINCT FROM 'on'
     AND (NEW.amount_paid IS DISTINCT FROM OLD.amount_paid
          OR NEW.payment_state IS DISTINCT FROM OLD.payment_state
          OR (NEW.status = 'paid' AND OLD.status IS DISTINCT FROM 'paid')
          OR (OLD.validation_status = 'validated' AND NEW.amount_due IS DISTINCT FROM OLD.amount_due)) THEN
    RAISE EXCEPTION 'Facture % : le montant payé résulte des règlements — enregistrez un encaissement', OLD.number
      USING ERRCODE = 'check_violation';
  END IF;

  IF OLD.validation_status = 'validated' THEN
    IF NEW.validation_status IS DISTINCT FROM 'validated'
       OR (NEW.number, NEW.date, NEW.customer_id, NEW.subtotal, NEW.vat_total, NEW.total,
           NEW.currency_code, NEW.exchange_rate, NEW.tenant_id)
          IS DISTINCT FROM
          (OLD.number, OLD.date, OLD.customer_id, OLD.subtotal, OLD.vat_total, OLD.total,
           OLD.currency_code, OLD.exchange_rate, OLD.tenant_id) THEN
      RAISE EXCEPTION 'Facture % validée : numéro, date, client et montants ne sont plus modifiables (émettez un avoir)', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  -- Brouillon : le numéro reste provisoire, les totaux suivent les lignes
  NEW.number := OLD.number;
  -- Un brouillon ne part pas chez le client : numéro provisoire, aucune écriture
  IF NEW.validation_status IS DISTINCT FROM 'validated' AND OLD.status = 'draft'
     AND NEW.status IN ('sent', 'viewed', 'overdue') THEN
    RAISE EXCEPTION 'Facture % en brouillon : validez-la avant de l''envoyer', OLD.number
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*), COALESCE(sum(total), 0), COALESCE(sum(vat_amount), 0) INTO v_n, v_ht, v_tva
  FROM invoice_lines WHERE invoice_id = NEW.id;
  IF v_n > 0 THEN
    NEW.subtotal := v_ht; NEW.vat_total := v_tva; NEW.total := v_ht + v_tva;
  END IF;
  NEW.amount_due := GREATEST(COALESCE(NEW.total, 0) - COALESCE(NEW.amount_paid, 0), 0);

  IF NEW.validation_status = 'validated' THEN
    IF v_n = 0 THEN
      RAISE EXCEPTION 'Facture sans ligne : rien à valider' USING ERRCODE = 'check_violation';
    END IF;
    -- B7 (ven-007) / D-QA-2 : la numerotation suit la chronologie. Une facture
    -- datee avant la derniere facture validee de la societe est refusee : la
    -- piste d'audit fiable exige une suite de dates non decroissante.
    SELECT i.number, i.date INTO v_derniere_num, v_derniere_date
    FROM invoices i
    WHERE i.tenant_id = NEW.tenant_id AND i.id <> NEW.id
      AND i.validation_status = 'validated'
    ORDER BY i.date DESC, i.number DESC LIMIT 1;
    IF v_derniere_date IS NOT NULL AND NEW.date < v_derniere_date THEN
      RAISE EXCEPTION 'Facture % : date % anterieure a la derniere facture validee (% du %) — la numerotation suit la chronologie',
        NEW.number, NEW.date, v_derniere_num, v_derniere_date
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.number := next_legal_document_number(NEW.tenant_id, 'FAC', NEW.date);
  END IF;
  RETURN NEW;
END $function$;
-- ------------------------------------------------------------
-- 7. La facture nee d un devis garde la date du devis (B6, ven-006)
--    (reprise a l identique de la 190 ; seule la date change)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.convert_quote_to_invoice(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_q quotes%ROWTYPE; v_inv uuid; v_existing uuid;
BEGIN
  SELECT * INTO v_q FROM quotes WHERE id = p_quote_id AND tenant_id = current_tenant_id() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Devis introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT id INTO v_existing FROM invoices WHERE quote_id = p_quote_id AND tenant_id = v_q.tenant_id LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'Devis % déjà facturé', v_q.number USING ERRCODE = 'unique_violation';
  END IF;
  IF v_q.status IN ('rejected', 'expired') THEN
    RAISE EXCEPTION 'Devis % %: conversion impossible', v_q.number,
      CASE v_q.status WHEN 'rejected' THEN 'refusé' ELSE 'expiré' END USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM quote_lines WHERE quote_id = p_quote_id) THEN
    RAISE EXCEPTION 'Devis % sans ligne', v_q.number USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status, quote_id, notes)
  -- B6 (ven-006) : la facture garde la date de la piece d'origine — la date
  -- du jour imposait une facture au 29/09 pour un devis du 10/09.
  VALUES (v_q.tenant_id, v_q.customer_id, v_q.customer_name, COALESCE(v_q.date, CURRENT_DATE),
          COALESCE(v_q.date, CURRENT_DATE) + 30, 'draft', p_quote_id,
          'Issue du devis ' || v_q.number)
  RETURNING id INTO v_inv;

  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, vat_code, line_order)
  SELECT v_q.tenant_id, v_inv, l.product_id, l.description, l.quantity, l.unit_price, l.vat_rate,
         vat_code_for_rate(l.vat_rate), l.line_order
  FROM quote_lines l WHERE l.quote_id = p_quote_id ORDER BY l.line_order, l.created_at;

  UPDATE quotes SET status = 'accepted', transformation_status = 'transformed', updated_at = now() WHERE id = p_quote_id;

  RETURN jsonb_build_object('success', true, 'invoice_id', v_inv);
END $function$;

-- ------------------------------------------------------------
-- 8. Droits : aucune fonction de ce lot n'est executable par PUBLIC (garde 228 T06)
--    Les fonctions reprises (create_journal_on_invoice_validate, credit_note_guard,
--    invoice_guard, convert_quote_to_invoice) gardent l ACL de leur CREATE OR
--    REPLACE ; les trois fonctions neuves, elles, naissent exposees.
--    `calculate_stock_valuation` (316) etait exposee a PUBLIC — la garde 228 T06
--    le signalait (mesure rouge avant ce fichier) : meme correctif ici.
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION create_stock_out_on_invoice_validate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION invoice_fill_customer_name() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION calculate_stock_valuation(text, uuid, date) FROM PUBLIC;
