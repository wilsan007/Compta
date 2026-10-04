-- ============================================================
-- 210_advance_invoices.sql — R-03 : factures d'acompte (décision D-9 du 22/09)
--
-- Avant : une facture d'acompte (invoice_type = 'advance') était comptabilisée
-- comme une vente (707000), et rien ne permettait de la déduire de la facture
-- finale : le chiffre d'affaires était compté deux fois.
--
-- Règle retenue (PCG, pratique Sage 100 et Odoo) :
--   - facture d'acompte : D 411 TTC / C 4191 HT / C 4457x TVA ;
--   - facture finale : toutes les lignes, plus une ligne négative « déduction
--     de l'acompte » qui porte advance_invoice_id : D 411 net / D 4191 HT
--     déduit / C 7xx / C 4457x net de la TVA déjà facturée ;
--   - les lignes 4191 d'un acompte sont lettrées dès qu'il est entièrement déduit.
-- La validation refuse une déduction qui ne vise pas un acompte validé du même
-- client, au même taux de TVA, ou qui dépasse le solde de l'acompte.
--
-- 419100 est un compte français provisoire (rôle « avances clients » au lot K).
-- ============================================================

-- Pas de clé étrangère : une seconde FK invoice_lines → invoices rendrait ambiguës
-- toutes les jointures PostgREST invoices ↔ invoice_lines (dont la fonction Edge
-- public-api). L'intégrité tient par invoice_advance_guard (acompte validé exigé)
-- et sales_document_delete_guard (une facture validée ne se supprime pas).
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS advance_invoice_id uuid;
CREATE INDEX IF NOT EXISTS idx_invoice_lines_advance_invoice ON invoice_lines(advance_invoice_id)
  WHERE advance_invoice_id IS NOT NULL;
COMMENT ON COLUMN invoice_lines.advance_invoice_id IS
  'Ligne de déduction d''acompte (montant négatif) : facture d''acompte déduite. Comptabilisée en 4191.';

-- Les montants de ligne restent positifs, sauf sur une ligne de déduction d'acompte
ALTER TABLE invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_total_nonneg;
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_total_nonneg
  CHECK (total >= 0 OR advance_invoice_id IS NOT NULL);
ALTER TABLE invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_unit_price_nonneg;
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_unit_price_nonneg
  CHECK (unit_price >= 0 OR advance_invoice_id IS NOT NULL);
ALTER TABLE invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_vat_total_nonneg;
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_vat_total_nonneg
  CHECK (vat_total >= 0 OR advance_invoice_id IS NOT NULL);

-- ------------------------------------------------------------
-- 1. Contrôle des déductions à la validation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION invoice_advance_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE l record; a invoices%ROWTYPE; v_used numeric;
BEGIN
  FOR l IN SELECT advance_invoice_id AS adv, sum(total) AS montant, array_agg(DISTINCT vat_rate) AS taux
           FROM invoice_lines WHERE invoice_id = NEW.id AND advance_invoice_id IS NOT NULL
           GROUP BY advance_invoice_id LOOP
    SELECT * INTO a FROM invoices WHERE id = l.adv AND tenant_id = NEW.tenant_id;
    IF NOT FOUND OR a.id = NEW.id OR NOT COALESCE(a.invoice_type = 'advance' OR a.is_advance_invoice, false) THEN
      RAISE EXCEPTION 'Facture % : la ligne de déduction ne vise pas une facture d''acompte', NEW.number
        USING ERRCODE = 'check_violation';
    END IF;
    IF COALESCE(NEW.invoice_type = 'advance' OR NEW.is_advance_invoice, false) THEN
      RAISE EXCEPTION 'Facture d''acompte % : on ne déduit pas un acompte d''un autre acompte', NEW.number
        USING ERRCODE = 'check_violation';
    END IF;
    IF a.validation_status IS DISTINCT FROM 'validated' THEN
      RAISE EXCEPTION 'Facture % : l''acompte % n''est pas validé', NEW.number, a.number USING ERRCODE = 'check_violation';
    END IF;
    IF a.customer_id IS DISTINCT FROM NEW.customer_id THEN
      RAISE EXCEPTION 'Facture % : l''acompte % appartient à un autre client', NEW.number, a.number USING ERRCODE = 'check_violation';
    END IF;
    IF l.montant >= 0 THEN
      RAISE EXCEPTION 'Facture % : une déduction d''acompte est une ligne négative', NEW.number USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(l.taux) r
               WHERE NOT EXISTS (SELECT 1 FROM invoice_lines al WHERE al.invoice_id = a.id AND al.vat_rate = r)) THEN
      RAISE EXCEPTION 'Facture % : la déduction de l''acompte % doit reprendre son taux de TVA', NEW.number, a.number
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(-sum(il.total), 0) INTO v_used
    FROM invoice_lines il JOIN invoices i ON i.id = il.invoice_id
    WHERE il.advance_invoice_id = a.id AND i.id <> NEW.id AND i.validation_status = 'validated';
    IF v_used - l.montant > COALESCE(a.subtotal, 0) THEN
      RAISE EXCEPTION 'Facture % : déduction de % sur l''acompte % dont il reste % à déduire',
        NEW.number, -l.montant, a.number, COALESCE(a.subtotal, 0) - v_used USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_invoice_advance_guard ON invoices;
CREATE TRIGGER tg_invoice_advance_guard
  BEFORE UPDATE OF validation_status ON invoices
  FOR EACH ROW
  WHEN (NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated')
  EXECUTE FUNCTION invoice_advance_guard();

-- ------------------------------------------------------------
-- 2. Lettrage 4191 d'un acompte entièrement déduit
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION letter_advance_invoice(p_tenant uuid, p_advance uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lines uuid[]; v_d numeric; v_c numeric; v_open int; v_code text;
BEGIN
  SELECT array_agg(id), COALESCE(sum(debit), 0), COALESCE(sum(credit), 0), count(*) FILTER (WHERE lettrage_code IS NULL)
    INTO v_lines, v_d, v_c, v_open
  FROM journal_lines
  WHERE tenant_id = p_tenant AND account_code = '419100' AND reference = 'ACOMPTE:' || p_advance;
  IF v_open = COALESCE(array_length(v_lines, 1), 0) AND v_open > 1 AND v_d = v_c THEN
    v_code := next_lettrage_code_for(p_tenant);
    UPDATE journal_lines SET lettrage_code = v_code, lettrage_date = CURRENT_DATE
    WHERE id = ANY(v_lines);
  END IF;
END $$;
REVOKE ALL ON FUNCTION letter_advance_invoice(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 3. Écriture de vente : acompte et déduction en 4191
--    (fonction de la 187 ; seuls changent le compte des lignes d'acompte, le
--     sens des montants négatifs et le lettrage final)
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
             ELSE COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut_vente) END AS compte,
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
