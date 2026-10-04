-- ============================================================
-- 190_sales_to_ledger.sql — lot E du plan correctif du 21/09
-- (doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md, vague V3)
--
-- Défauts prouvés par sql/180_sales_to_ledger_tests.sql :
--   AUD-E03  totaux de ligne et d'en-tête saisis par l'écran, facture validée
--            modifiable (E10, E11)
--   AUD-E04  numéro de facture/avoir saisi par l'écran (Math.random) ;
--            décision n° 2 : numéro attribué à la validation, continu par
--            exercice — FAC-<exercice>-000001 (E12, E13)
--   AUD-E05  conversion devis → facture non atomique, TVA de ligne perdue (E04, E14)
--   AUD-E07  avoirs clients sans écriture ni rattachement (E06, E15, E16)
--   AUD-E08  trop-perçu crédité au 411 ; décision n° 1 : excédent en avance
--            client 4191 (E08, E17)
--   AUD-E09  encaissement toujours en 512000 / BQ (E18)
--   AUD-E10  règlement soldant la facture non lettré (E19)
--   AUD-E11  invoice_ref porte le numéro provisoire (E20)
--
-- Les codes TVA déduits d'un taux et les comptes par défaut (707000, 709000,
-- 419100, 530000) sont des valeurs françaises provisoires : le lot K les
-- remplacera par resolve_account / le pack du pays.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Outils
-- ------------------------------------------------------------

-- Code TVA d'un taux, quand la ligne n'en porte pas (devis, avoirs, anciens écrans)
CREATE OR REPLACE FUNCTION vat_code_for_rate(p_rate numeric)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE COALESCE(p_rate, 0)
    WHEN 20  THEN 'FR20'
    WHEN 10  THEN 'FR10'
    WHEN 5.5 THEN 'FR055'
    WHEN 2.1 THEN 'FR021'
    WHEN 0   THEN 'FR0'
    ELSE 'FR20'
  END
$$;

-- Code de lettrage pour une société donnée (next_lettrage_code lit le contexte
-- de la session, qu'un trigger ne peut pas supposer)
CREATE OR REPLACE FUNCTION next_lettrage_code_for(p_tenant uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_seq bigint; v_letter text; v_num int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('lettrage:' || p_tenant::text));
  UPDATE company_settings SET next_lettrage_seq = next_lettrage_seq + 1
  WHERE tenant_id = p_tenant RETURNING next_lettrage_seq - 1 INTO v_seq;
  IF v_seq IS NULL THEN
    INSERT INTO company_settings (tenant_id, name, next_lettrage_seq)
    SELECT p_tenant, COALESCE(t.name, 'Société'), 2 FROM tenants t WHERE t.id = p_tenant;
    v_seq := 1;
  END IF;
  IF v_seq < 26 * 999 THEN
    v_letter := chr(65 + (v_seq / 999)::int);
    v_num := (v_seq % 999)::int + 1;
    RETURN v_letter || lpad(v_num::text, 3, '0');
  ELSIF v_seq < 26 * 999 + 26 * 26 * 99 THEN
    v_seq := v_seq - 26 * 999;
    v_letter := chr(65 + (v_seq / (26 * 99))::int) || chr(65 + ((v_seq / 99)::int % 26));
    v_num := (v_seq % 99)::int + 1;
    RETURN v_letter || lpad(v_num::text, 2, '0');
  END IF;
  RAISE EXCEPTION 'Numérotation de lettrage épuisée';
END $$;
REVOKE ALL ON FUNCTION next_lettrage_code_for(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION next_lettrage_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Aucun tenant actif'; END IF;
  RETURN next_lettrage_code_for(v_tid);
END $$;

-- ------------------------------------------------------------
-- 1. Numérotation légale par exercice (AUD-E04)
-- ------------------------------------------------------------
ALTER TABLE document_number_sequences
  ADD COLUMN IF NOT EXISTS fiscal_year_id uuid REFERENCES fiscal_years(id) ON DELETE CASCADE;
ALTER TABLE document_number_sequences DROP CONSTRAINT IF EXISTS document_number_sequences_tenant_id_prefix_key;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_document_number_sequences_free
  ON document_number_sequences (tenant_id, prefix) WHERE fiscal_year_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_document_number_sequences_fy
  ON document_number_sequences (tenant_id, prefix, fiscal_year_id) WHERE fiscal_year_id IS NOT NULL;

-- Numéro définitif d'une pièce : continu et chronologique par exercice.
-- Le compteur est annulé avec la transaction si la validation échoue plus loin.
CREATE OR REPLACE FUNCTION next_legal_document_number(p_tenant uuid, p_prefix text, p_date date)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_fy fiscal_years%ROWTYPE; v_next int;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = p_tenant AND p_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun exercice ne couvre le % : créez l''exercice avant de valider', to_char(p_date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO document_number_sequences AS s (tenant_id, prefix, fiscal_year_id, next_number)
  VALUES (p_tenant, p_prefix, v_fy.id, 2)
  ON CONFLICT (tenant_id, prefix, fiscal_year_id) WHERE fiscal_year_id IS NOT NULL
  DO UPDATE SET next_number = s.next_number + 1, updated_at = now()
  RETURNING next_number - 1 INTO v_next;
  RETURN p_prefix || '-' || v_fy.code || '-' || lpad(v_next::text, 6, '0');
END $$;
REVOKE ALL ON FUNCTION next_legal_document_number(uuid, text, date) FROM PUBLIC, anon, authenticated;

-- Compteur libre (pièces internes : EXT, AN, CMD, BL…) — inchangé sur le fond,
-- réécrit parce que sa contrainte d'unicité est devenue un index partiel
CREATE OR REPLACE FUNCTION get_next_document_number(p_prefix text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_next int;
BEGIN
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Aucun tenant actif'; END IF;
  INSERT INTO document_number_sequences AS s (tenant_id, prefix, next_number)
  VALUES (v_tid, p_prefix, 2)
  ON CONFLICT (tenant_id, prefix) WHERE fiscal_year_id IS NULL
  DO UPDATE SET next_number = s.next_number + 1, updated_at = now()
  RETURNING next_number - 1 INTO v_next;
  RETURN p_prefix || '-' || extract(year FROM CURRENT_DATE)::int || '-' || lpad(v_next::text, 6, '0');
END $$;

-- Numéro provisoire d'un brouillon : jamais au format légal
CREATE OR REPLACE FUNCTION draft_document_number(p_prefix text, p_id uuid)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$ SELECT 'BROUILLON-' || p_prefix || '-' || upper(left(replace(p_id::text, '-', ''), 10)) $$;

-- ------------------------------------------------------------
-- 2. Lignes de pièces : montants calculés par le serveur (AUD-E03, E05)
-- ------------------------------------------------------------
ALTER TABLE credit_note_lines ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE credit_note_lines ADD COLUMN IF NOT EXISTS vat_code text;
ALTER TABLE credit_note_lines ADD COLUMN IF NOT EXISTS vat_amount numeric NOT NULL DEFAULT 0;

-- Montant de ligne : quantité × prix unitaire HT, TVA au taux de la ligne
CREATE OR REPLACE FUNCTION line_amounts(p_qty numeric, p_price numeric, p_rate numeric,
  OUT total numeric, OUT vat numeric)
LANGUAGE sql IMMUTABLE
AS $$
  SELECT round(COALESCE(p_qty, 0) * COALESCE(p_price, 0), 2),
         round(round(COALESCE(p_qty, 0) * COALESCE(p_price, 0), 2) * COALESCE(p_rate, 0) / 100, 2)
$$;

-- Code TVA absent, ou code par défaut incohérent avec le taux saisi
CREATE OR REPLACE FUNCTION line_vat_code(p_code text, p_rate numeric)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN p_code IS NULL OR btrim(p_code) = '' OR (p_code = 'FR20' AND COALESCE(p_rate, 0) <> 20)
              THEN vat_code_for_rate(p_rate) ELSE p_code END
$$;

CREATE OR REPLACE FUNCTION invoice_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM invoices WHERE validation_status = 'validated'
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.invoice_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.invoice_id END)) THEN
    RAISE EXCEPTION 'Facture validée : ses lignes ne peuvent plus être modifiées (émettez un avoir)'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.total := a.total;
  NEW.vat_total := a.vat;
  NEW.vat_amount := a.vat;
  NEW.vat_code := line_vat_code(NEW.vat_code, NEW.vat_rate);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION credit_note_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM credit_notes WHERE status IN ('validated', 'applied')
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.credit_note_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.credit_note_id END)) THEN
    RAISE EXCEPTION 'Avoir validé : ses lignes ne peuvent plus être modifiées'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.total := a.total;
  NEW.vat_total := a.vat;
  NEW.vat_amount := a.vat;
  NEW.vat_code := line_vat_code(NEW.vat_code, NEW.vat_rate);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION quote_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.total := a.total;
  NEW.vat_total := a.vat;
  RETURN NEW;
END $$;

-- Totaux d'en-tête = somme des lignes, tant que la pièce est modifiable
CREATE OR REPLACE FUNCTION invoice_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT unnest(ARRAY[CASE WHEN TG_OP <> 'INSERT' THEN OLD.invoice_id END,
                                           CASE WHEN TG_OP <> 'DELETE' THEN NEW.invoice_id END]) AS id) x
        LEFT JOIN invoice_lines l ON l.invoice_id = x.id
        WHERE x.id IS NOT NULL GROUP BY x.id) s
  WHERE i.id = s.id AND i.validation_status IS DISTINCT FROM 'validated'
    AND (i.subtotal, i.vat_total, i.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION credit_note_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE credit_notes c SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT unnest(ARRAY[CASE WHEN TG_OP <> 'INSERT' THEN OLD.credit_note_id END,
                                           CASE WHEN TG_OP <> 'DELETE' THEN NEW.credit_note_id END]) AS id) x
        LEFT JOIN credit_note_lines l ON l.credit_note_id = x.id
        WHERE x.id IS NOT NULL GROUP BY x.id) s
  WHERE c.id = s.id AND c.status = 'draft'
    AND (c.subtotal, c.vat_total, c.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION quote_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE quotes q SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_total), 0) tva
        FROM (SELECT DISTINCT unnest(ARRAY[CASE WHEN TG_OP <> 'INSERT' THEN OLD.quote_id END,
                                           CASE WHEN TG_OP <> 'DELETE' THEN NEW.quote_id END]) AS id) x
        LEFT JOIN quote_lines l ON l.quote_id = x.id
        WHERE x.id IS NOT NULL GROUP BY x.id) s
  WHERE q.id = s.id
    AND (q.subtotal, q.vat_total, q.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $$;

-- Reprise : lignes existantes des brouillons recalculées (les pièces validées restent telles quelles)
UPDATE credit_note_lines SET vat_code = vat_code_for_rate(vat_rate), vat_amount = COALESCE(vat_total, 0) WHERE vat_code IS NULL;

DROP TRIGGER IF EXISTS tg_line_compute ON invoice_lines;
CREATE TRIGGER tg_line_compute BEFORE INSERT OR UPDATE OR DELETE ON invoice_lines
  FOR EACH ROW EXECUTE FUNCTION invoice_line_compute();
DROP TRIGGER IF EXISTS tg_line_refresh_totals ON invoice_lines;
CREATE TRIGGER tg_line_refresh_totals AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
  FOR EACH ROW EXECUTE FUNCTION invoice_lines_refresh_totals();

DROP TRIGGER IF EXISTS tg_line_compute ON credit_note_lines;
CREATE TRIGGER tg_line_compute BEFORE INSERT OR UPDATE OR DELETE ON credit_note_lines
  FOR EACH ROW EXECUTE FUNCTION credit_note_line_compute();
DROP TRIGGER IF EXISTS tg_line_refresh_totals ON credit_note_lines;
CREATE TRIGGER tg_line_refresh_totals AFTER INSERT OR UPDATE OR DELETE ON credit_note_lines
  FOR EACH ROW EXECUTE FUNCTION credit_note_lines_refresh_totals();

DROP TRIGGER IF EXISTS tg_line_compute ON quote_lines;
CREATE TRIGGER tg_line_compute BEFORE INSERT OR UPDATE ON quote_lines
  FOR EACH ROW EXECUTE FUNCTION quote_line_compute();
DROP TRIGGER IF EXISTS tg_line_refresh_totals ON quote_lines;
CREATE TRIGGER tg_line_refresh_totals AFTER INSERT OR UPDATE OR DELETE ON quote_lines
  FOR EACH ROW EXECUTE FUNCTION quote_lines_refresh_totals();

-- ------------------------------------------------------------
-- 3. Règlement d'une facture : reste dû, statut, lettrage (AUD-E08, E10)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_invoice_settlement(p_invoice uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inv invoices%ROWTYPE;
  v_paid numeric; v_credits numeric; v_due numeric;
  v_account text; v_lines uuid[]; v_d numeric; v_c numeric; v_open int; v_code text;
BEGIN
  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_paid FROM customer_payments
  WHERE invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('recorded', 'reconciled');
  SELECT COALESCE(sum(total), 0) INTO v_credits FROM credit_notes
  WHERE invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('validated', 'applied');
  v_due := GREATEST(COALESCE(v_inv.total, 0) - v_paid - v_credits, 0);

  PERFORM set_config('app.settlement_in_progress', 'on', true);
  UPDATE invoices SET
    amount_paid = LEAST(v_paid, GREATEST(COALESCE(total, 0) - v_credits, 0)),
    amount_due = v_due,
    payment_state = CASE WHEN v_due = 0 AND COALESCE(total, 0) > 0 THEN 'paid'
                         WHEN v_paid + v_credits > 0 THEN 'partial' ELSE 'not_paid' END,
    status = CASE WHEN v_due = 0 AND COALESCE(total, 0) > 0 AND v_paid > 0 THEN 'paid'
                  WHEN v_due = 0 AND COALESCE(total, 0) > 0 AND v_credits > 0 THEN 'cancelled'
                  WHEN status IN ('paid', 'cancelled') AND v_due > 0 THEN 'sent'
                  ELSE status END,
    updated_at = now()
  WHERE id = p_invoice;
  PERFORM set_config('app.settlement_in_progress', 'off', true);

  -- AUD-E10 : facture soldée → lettrage de ses lignes client avec les règlements et avoirs
  IF v_due > 0 OR v_inv.validation_status IS DISTINCT FROM 'validated' OR v_inv.transferred_entry_id IS NULL THEN
    RETURN;
  END IF;
  SELECT account_code INTO v_account FROM journal_lines
  WHERE journal_id = v_inv.transferred_entry_id AND debit > 0 ORDER BY line_order LIMIT 1;

  SELECT array_agg(jl.id), COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0),
         count(*) FILTER (WHERE jl.lettrage_code IS NULL)
    INTO v_lines, v_d, v_c, v_open
  FROM journal_lines jl
  WHERE jl.tenant_id = v_inv.tenant_id AND jl.account_code = v_account
    AND jl.journal_id IN (
      SELECT v_inv.transferred_entry_id
      UNION ALL SELECT transferred_entry_id FROM customer_payments
        WHERE invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('recorded', 'reconciled')
      UNION ALL SELECT transferred_entry_id FROM credit_notes
        WHERE invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('validated', 'applied'));

  IF v_open = COALESCE(array_length(v_lines, 1), 0) AND v_open > 1 AND v_d = v_c THEN
    v_code := next_lettrage_code_for(v_inv.tenant_id);
    UPDATE journal_lines SET lettrage_code = v_code, lettrage_date = CURRENT_DATE
    WHERE id = ANY(v_lines);
  END IF;
END $$;
REVOKE ALL ON FUNCTION refresh_invoice_settlement(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 4. Facture : numéro, totaux et gel à la validation (AUD-E03, E04, E11)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION invoice_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_ht numeric; v_tva numeric; v_n int;
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
    NEW.number := next_legal_document_number(NEW.tenant_id, 'FAC', NEW.date);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_invoice_guard ON invoices;
CREATE TRIGGER tg_invoice_guard
  BEFORE INSERT OR UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION invoice_guard();

-- Après validation : un règlement saisi sur le brouillon est pris en compte et lettré
CREATE OR REPLACE FUNCTION invoice_after_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM refresh_invoice_settlement(NEW.id);
  RETURN NULL;
END $$;

-- Nommé après create_journal_invoice : l'écriture existe quand il s'exécute
DROP TRIGGER IF EXISTS tg_invoice_after_validate ON invoices;
CREATE TRIGGER tg_invoice_after_validate
  AFTER UPDATE OF validation_status ON invoices
  FOR EACH ROW
  WHEN (NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated')
  EXECUTE FUNCTION invoice_after_validate();

-- ------------------------------------------------------------
-- 5. Avoirs clients (AUD-E07)
-- ------------------------------------------------------------
ALTER TABLE credit_notes DROP CONSTRAINT IF EXISTS credit_notes_status_check;
ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_status_check
  CHECK (status IN ('draft', 'validated', 'applied'));
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS validated_at timestamptz;
COMMENT ON COLUMN credit_notes.status IS
  'draft → validated (écriture VT inverse, numéro AV-<exercice>-n) → applied (imputé). draft → applied valide aussi.';

CREATE OR REPLACE FUNCTION credit_note_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
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

  IF v_n > 0 THEN
    FOR r IN
      SELECT COALESCE(p.sale_account_code, pc.sale_account_code, '707000') AS compte, sum(l.total) AS montant
      FROM credit_note_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.credit_note_id = NEW.id GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, r.montant, 0, 'Avoir ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
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
    -- Avoir global sans ligne (remise commerciale)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, '709000', '709000', NEW.subtotal, 0, 'Remise ' || NEW.number, 1),
           (NEW.tenant_id, v_entry, '445710', '445710', NEW.vat_total, 0, 'TVA collectée — ' || NEW.number, 2);
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_credit_note_guard ON credit_notes;
CREATE TRIGGER tg_credit_note_guard
  BEFORE INSERT OR UPDATE ON credit_notes
  FOR EACH ROW EXECUTE FUNCTION credit_note_guard();

CREATE OR REPLACE FUNCTION credit_note_after_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.invoice_id IS NOT NULL THEN PERFORM refresh_invoice_settlement(NEW.invoice_id); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_credit_note_after_validate ON credit_notes;
CREATE TRIGGER tg_credit_note_after_validate
  AFTER UPDATE OF status ON credit_notes
  FOR EACH ROW
  WHEN (OLD.status = 'draft' AND NEW.status IN ('validated', 'applied'))
  EXECUTE FUNCTION credit_note_after_validate();

-- ------------------------------------------------------------
-- 6. Comptes bancaires : compte de trésorerie et journal propres (AUD-E09)
-- ------------------------------------------------------------
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS account_code text;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS journal_code text;
COMMENT ON COLUMN bank_accounts.account_code IS 'AUD-E09 — compte de trésorerie (512x, 530x) mouvementé par les règlements sur ce compte';
COMMENT ON COLUMN bank_accounts.journal_code IS 'AUD-E09 — journal de trésorerie propre à ce compte';

-- Premier compte bancaire : 512000 / BQ ; suivants : 5121nn / BQn (caisse : 530000 / CA, 5301nn / CAn)
CREATE OR REPLACE FUNCTION bank_account_assign_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_cash boolean := NEW.type = 'cash'; v_base text; v_jbase text; v_n int := 0; v_code text; v_j text;
BEGIN
  v_base := CASE WHEN v_cash THEN '530000' ELSE '512000' END;
  v_jbase := CASE WHEN v_cash THEN 'CA' ELSE 'BQ' END;
  IF NEW.account_code IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM bank_accounts WHERE tenant_id = NEW.tenant_id AND id <> NEW.id AND account_code = v_base) THEN
      NEW.account_code := v_base;
      NEW.journal_code := COALESCE(NEW.journal_code, v_jbase);
    ELSE
      LOOP
        v_n := v_n + 1;
        v_code := left(v_base, 3) || '1' || lpad(v_n::text, 2, '0');
        v_j := v_jbase || (v_n + 1);
        EXIT WHEN NOT EXISTS (SELECT 1 FROM bank_accounts WHERE tenant_id = NEW.tenant_id AND (account_code = v_code OR journal_code = v_j))
              AND NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = v_j);
      END LOOP;
      NEW.account_code := v_code;
      NEW.journal_code := COALESCE(NEW.journal_code, v_j);
    END IF;
  END IF;
  IF NEW.journal_code IS NULL THEN
    v_n := 1;
    LOOP
      v_n := v_n + 1;
      v_j := v_jbase || v_n;
      EXIT WHEN NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = v_j);
    END LOOP;
    NEW.journal_code := v_j;
  END IF;
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, NEW.account_code, CASE WHEN v_cash THEN 'Caisse' ELSE 'Banque' END || ' — ' || COALESCE(NEW.name, NEW.account_code), 'asset')
  ON CONFLICT (tenant_id, code) DO NOTHING;
  RETURN NEW;
END $$;

-- Le journal référence le compte bancaire : créé après l'insertion
CREATE OR REPLACE FUNCTION bank_account_ensure_journal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO journals (tenant_id, code, name, type, account_counterpart, bank_account_id, status, locked, next_number)
  VALUES (NEW.tenant_id, NEW.journal_code, 'Journal ' || COALESCE(NEW.name, NEW.journal_code),
          CASE WHEN NEW.type = 'cash' THEN 'cash' ELSE 'bank' END, NEW.account_code, NEW.id, 'active', false, 1)
  ON CONFLICT (tenant_id, code) DO UPDATE
    SET bank_account_id = COALESCE(journals.bank_account_id, EXCLUDED.bank_account_id),
        account_counterpart = COALESCE(journals.account_counterpart, EXCLUDED.account_counterpart);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_bank_account_ledger ON bank_accounts;
CREATE TRIGGER tg_bank_account_ledger
  BEFORE INSERT OR UPDATE OF account_code, journal_code, type ON bank_accounts
  FOR EACH ROW EXECUTE FUNCTION bank_account_assign_ledger();
DROP TRIGGER IF EXISTS tg_bank_account_journal ON bank_accounts;
CREATE TRIGGER tg_bank_account_journal
  AFTER INSERT OR UPDATE OF account_code, journal_code ON bank_accounts
  FOR EACH ROW EXECUTE FUNCTION bank_account_ensure_journal();

-- Reprise : comptes existants, dans l'ordre de création
DO $$
DECLARE b record;
BEGIN
  FOR b IN SELECT id FROM bank_accounts WHERE account_code IS NULL AND tenant_id IS NOT NULL ORDER BY tenant_id, created_at, id LOOP
    UPDATE bank_accounts SET account_code = NULL WHERE id = b.id;  -- déclenche l'attribution
  END LOOP;
END $$;

-- Compte et journal de trésorerie d'un règlement
CREATE OR REPLACE FUNCTION treasury_for_payment(p_tenant uuid, p_bank_account uuid, p_method text,
  OUT account_code text, OUT journal_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_bank_account IS NOT NULL THEN
    SELECT b.account_code, b.journal_code INTO account_code, journal_code
    FROM bank_accounts b WHERE b.id = p_bank_account AND b.tenant_id = p_tenant;
  END IF;
  IF account_code IS NULL THEN
    IF p_method = 'cash' THEN
      account_code := '530000'; journal_code := 'CA';
    ELSE
      account_code := '512000'; journal_code := 'BQ';
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION treasury_for_payment(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 7. Encaissements : trésorerie, avance client, lettrage (AUD-E08, E09, E10)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_journal_on_customer_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text;
  v_tiers text;
  v_third_party uuid;
  v_tr record;
  v_remaining numeric;
  v_excess numeric := 0;
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id INTO v_collectif, v_tiers, v_third_party
    FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.invoice_id IS NOT NULL THEN
    SELECT c.account_collectif, c.account_tiers, c.id INTO v_collectif, v_tiers, v_third_party
    FROM customers c JOIN invoices i ON i.customer_id = c.id AND i.tenant_id = c.tenant_id
    WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
  END IF;
  v_collectif := COALESCE(v_collectif, '411000');

  -- AUD-E08 : la part qui dépasse le reste dû va en avance client (décision n° 1)
  IF NEW.invoice_id IS NOT NULL THEN
    SELECT COALESCE(i.total, 0)
           - COALESCE((SELECT sum(amount) FROM customer_payments p
                       WHERE p.invoice_id = i.id AND p.id <> NEW.id AND p.status IN ('recorded', 'reconciled')), 0)
           - COALESCE((SELECT sum(total) FROM credit_notes c
                       WHERE c.invoice_id = i.id AND c.status IN ('validated', 'applied')), 0)
      INTO v_remaining
    FROM invoices i WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
    v_excess := GREATEST(NEW.amount - GREATEST(COALESCE(v_remaining, NEW.amount), 0), 0);
  END IF;

  -- AUD-E09 : compte et journal du compte bancaire, ou du mode de règlement
  SELECT * INTO v_tr FROM treasury_for_payment(NEW.tenant_id, NEW.bank_account_id, NEW.method);

  v_number := 'JE-CP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, v_tr.journal_code, 'draft', 'Encaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry_id, v_tr.account_code, v_tr.account_code, NULL, NULL,
          NEW.amount, 0, 'Trésorerie ' || NEW.number, 0);
  IF NEW.amount - v_excess > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_collectif, v_collectif, v_tiers, v_third_party,
            0, NEW.amount - v_excess, 'Client ' || NEW.number, 1);
  END IF;
  IF v_excess > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '419100', '419100', v_tiers, v_third_party,
            0, v_excess, 'Avance client (trop-perçu) ' || NEW.number, 2);
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_invoice_on_customer_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_counted numeric := 0;
  v_new_counted numeric := 0;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IN ('recorded', 'reconciled') THEN
    v_old_counted := COALESCE(OLD.amount, 0);
  END IF;
  IF NEW.status IN ('recorded', 'reconciled') THEN
    v_new_counted := COALESCE(NEW.amount, 0);
  END IF;

  -- Reste dû, statut et lettrage recalculés depuis les règlements et avoirs
  IF NEW.invoice_id IS NOT NULL THEN
    PERFORM refresh_invoice_settlement(NEW.invoice_id);
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.invoice_id IS NOT NULL AND OLD.invoice_id IS DISTINCT FROM NEW.invoice_id THEN
    PERFORM refresh_invoice_settlement(OLD.invoice_id);
  END IF;

  -- Solde client : n'appliquer que la variation réelle du montant compté
  IF TG_OP = 'UPDATE' AND OLD.customer_id IS DISTINCT FROM NEW.customer_id THEN
    IF OLD.customer_id IS NOT NULL AND v_old_counted <> 0 THEN
      UPDATE customers
        SET balance = COALESCE(balance, 0) + v_old_counted,
            credit_used = COALESCE(credit_used, 0) + v_old_counted,
            updated_at = NOW()
      WHERE id = OLD.customer_id AND tenant_id = OLD.tenant_id;
    END IF;
    v_old_counted := 0;
  END IF;

  IF NEW.customer_id IS NOT NULL AND v_new_counted - v_old_counted <> 0 THEN
    UPDATE customers
      SET balance = GREATEST(COALESCE(balance, 0) - (v_new_counted - v_old_counted), 0),
          credit_used = GREATEST(COALESCE(credit_used, 0) - (v_new_counted - v_old_counted), 0),
          updated_at = NOW()
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 8. Devis → facture, côté serveur et atomique (AUD-E05)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION convert_quote_to_invoice(p_quote_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
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
  VALUES (v_q.tenant_id, v_q.customer_id, v_q.customer_name, CURRENT_DATE, CURRENT_DATE + 30, 'draft', p_quote_id,
          'Issue du devis ' || v_q.number)
  RETURNING id INTO v_inv;

  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, vat_code, line_order)
  SELECT v_q.tenant_id, v_inv, l.product_id, l.description, l.quantity, l.unit_price, l.vat_rate,
         vat_code_for_rate(l.vat_rate), l.line_order
  FROM quote_lines l WHERE l.quote_id = p_quote_id ORDER BY l.line_order, l.created_at;

  UPDATE quotes SET status = 'accepted', transformation_status = 'transformed', updated_at = now() WHERE id = p_quote_id;

  RETURN jsonb_build_object('success', true, 'invoice_id', v_inv);
END $$;
REVOKE ALL ON FUNCTION convert_quote_to_invoice(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION convert_quote_to_invoice(uuid) TO authenticated;

-- ------------------------------------------------------------
-- 9. Devis : numéro attribué par le serveur à la création (AUD-E04)
--    Un devis n'est pas une pièce comptable : il est numéroté dès sa création,
--    dans une suite DEV continue par exercice.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION quote_assign_number()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_next int;
BEGIN
  IF EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = NEW.tenant_id
             AND COALESCE(NEW.date, CURRENT_DATE) BETWEEN start_date AND end_date) THEN
    NEW.number := next_legal_document_number(NEW.tenant_id, 'DEV', COALESCE(NEW.date, CURRENT_DATE));
  ELSE
    -- Pas d'exercice ouvert à cette date : un devis reste possible, suite hors exercice
    INSERT INTO document_number_sequences AS s (tenant_id, prefix, next_number)
    VALUES (NEW.tenant_id, 'DEV', 2)
    ON CONFLICT (tenant_id, prefix) WHERE fiscal_year_id IS NULL
    DO UPDATE SET next_number = s.next_number + 1, updated_at = now()
    RETURNING next_number - 1 INTO v_next;
    NEW.number := 'DEV-' || lpad(v_next::text, 6, '0');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_quote_number ON quotes;
CREATE TRIGGER tg_quote_number
  BEFORE INSERT ON quotes
  FOR EACH ROW EXECUTE FUNCTION quote_assign_number();

-- ------------------------------------------------------------
-- 10. Une pièce validée ne se supprime pas (elle s'annule par un avoir)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION sales_document_delete_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (TG_TABLE_NAME = 'invoices' AND to_jsonb(OLD)->>'validation_status' = 'validated')
     OR (TG_TABLE_NAME = 'credit_notes' AND to_jsonb(OLD)->>'status' IN ('validated', 'applied')) THEN
    RAISE EXCEPTION 'Pièce % validée : suppression interdite (émettez un avoir)', OLD.number
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS tg_invoice_delete_guard ON invoices;
CREATE TRIGGER tg_invoice_delete_guard BEFORE DELETE ON invoices
  FOR EACH ROW EXECUTE FUNCTION sales_document_delete_guard();
DROP TRIGGER IF EXISTS tg_credit_note_delete_guard ON credit_notes;
CREATE TRIGGER tg_credit_note_delete_guard BEFORE DELETE ON credit_notes
  FOR EACH ROW EXECUTE FUNCTION sales_document_delete_guard();
