-- ============================================================
-- 197_vat_reverse_charge_accounts.sql — TVA autoliquidée séparée de la TVA ordinaire
--
-- Défaut repéré le 21/09/2026 (vague V3, § 6 du plan correctif) :
--   - vat_account_mapping envoyait FR20, AUTOLIQ et UE sur les mêmes comptes
--     (collectée 445711, déductible 445661 pour FR20 et AUTOLIQ) ; UE n'avait
--     pas de compte déductible ;
--   - seed_vat_accounts intitulait ces comptes « TVA collectée AUTOLIQ » /
--     « TVA déductible AUTOLIQ » (premier code par ordre alphabétique) : toute
--     la TVA à 20 % des sociétés s'affichait sous un libellé d'autoliquidation ;
--   - une facture fournisseur autoliquidée portait la TVA au crédit du
--     fournisseur (401 = TTC) et ne constatait pas la TVA due ;
--   - calculate_vat_ca3 (déclaration enregistrée par generate_vat_return)
--     additionnait vat_total des factures aux statuts « paid »/« sent » : une
--     facture validée reste « draft » (validation_status = 'validated'), la
--     déclaration valait 0.
--
-- Correctif :
--   1. comptes propres : AUTOLIQ → 445790 (due) / 445668 (déductible),
--      UE → 445200 (TVA due intracommunautaire) / 445667 ; libellés portés par
--      le paramétrage (account_name) ; drapeau reverse_charge ;
--   2. autoliquidation : la pièce ne facture pas de TVA (lignes à 0) ; à
--      l'achat, l'écriture constate D déductible / C due pour le taux de la
--      ligne (ou celui du paramétrage si la ligne est à 0 %) ; l'avoir
--      fournisseur contre-passe ; à la vente, le vendeur ne facture rien ;
--   3. calculate_vat_ca3 lit le grand livre : mouvements des comptes de TVA
--      des écritures validées de la période, hors à-nouveaux, clôture et
--      liquidation de TVA ; get_vat_summary_by_code classe chaque compte
--      par le paramétrage et ne double plus un code surchargé par la société ;
--   4. reprise : libellés semés renommés, comptes créés dans les plans
--      existants, pièces en brouillon recalculées, écritures validées
--      antérieures listées (vat_reverse_charge_legacy_lines) sans être
--      modifiées — une écriture validée ne se corrige que par une autre.
--
-- Suite : sql/197_vat_reverse_charge_tests.sql (V01 à V07).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Paramétrage
-- ------------------------------------------------------------
ALTER TABLE vat_account_mapping ADD COLUMN IF NOT EXISTS reverse_charge boolean NOT NULL DEFAULT false;
ALTER TABLE vat_account_mapping ADD COLUMN IF NOT EXISTS account_name text;
COMMENT ON COLUMN vat_account_mapping.reverse_charge IS
  '197 — TVA autoliquidée par l''acheteur (art. 283 CGI, acquisitions intracommunautaires) : non facturée, constatée due et déductible à l''achat';
COMMENT ON COLUMN vat_account_mapping.account_name IS '197 — libellé du compte semé au plan';

-- Comptes des codes autoliquidés : ceux d'origine (445711 / 445661) sont remplacés,
-- y compris dans une surcharge société qui les avait recopiés
UPDATE vat_account_mapping m SET account_code = v.new_code
FROM (VALUES ('AUTOLIQ', 'collected', '445711', '445790'),
             ('AUTOLIQ', 'deductible', '445661', '445668'),
             ('UE', 'collected', '445711', '445200')) AS v(vat_code, direction, old_code, new_code)
WHERE m.vat_code = v.vat_code AND m.direction = v.direction AND m.account_code = v.old_code;

INSERT INTO vat_account_mapping (tenant_id, vat_code, rate, direction, account_code, ca3_box)
SELECT '00000000-0000-0000-0000-000000000000', 'UE', 20.0, 'deductible', '445667', '08'
WHERE NOT EXISTS (SELECT 1 FROM vat_account_mapping
                  WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND vat_code = 'UE' AND direction = 'deductible');

UPDATE vat_account_mapping SET reverse_charge = true WHERE vat_code IN ('AUTOLIQ', 'UE');

UPDATE vat_account_mapping m SET account_name = v.name
FROM (VALUES ('445711', 'TVA collectée 20 %'),
             ('445712', 'TVA collectée 10 %'),
             ('445713', 'TVA collectée 5,5 %'),
             ('445714', 'TVA collectée 2,1 %'),
             ('445710', 'TVA collectée'),
             ('445661', 'TVA déductible 20 %'),
             ('445662', 'TVA déductible 10 %'),
             ('445663', 'TVA déductible 5,5 %'),
             ('445664', 'TVA déductible 2,1 %'),
             ('445790', 'TVA due autoliquidée (art. 283 CGI)'),
             ('445668', 'TVA déductible autoliquidée (art. 283 CGI)'),
             ('445200', 'TVA due intracommunautaire'),
             ('445667', 'TVA déductible sur acquisitions intracommunautaires')) AS v(code, name)
WHERE m.tenant_id = '00000000-0000-0000-0000-000000000000' AND m.account_code = v.code;

-- ------------------------------------------------------------
-- 2. Outils
-- ------------------------------------------------------------
-- Code autoliquidé pour la société (sa surcharge d'abord, puis le paramétrage global)
CREATE OR REPLACE FUNCTION vat_reverse_charge(p_tenant uuid, p_code text)
RETURNS boolean
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((SELECT m.reverse_charge FROM vat_account_mapping m
                   WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND m.vat_code = p_code
                   ORDER BY (m.tenant_id = p_tenant) DESC, m.reverse_charge DESC LIMIT 1), false)
$$;

-- TVA autoliquidée d'une ligne : taux de la ligne, ou taux du code si la ligne est à 0 %
CREATE OR REPLACE FUNCTION vat_self_assessed(p_tenant uuid, p_code text, p_base numeric, p_rate numeric)
RETURNS numeric
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT round(COALESCE(p_base, 0) * COALESCE(NULLIF(p_rate, 0),
           (SELECT m.rate FROM vat_account_mapping m
            WHERE m.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND m.vat_code = p_code
            ORDER BY (m.tenant_id = p_tenant) DESC LIMIT 1), 0) / 100, 2)
$$;

-- Deux lignes d'autoliquidation dans une écriture en cours de saisie.
-- p_sign = 1 : facture (D déductible / C due) ; -1 : avoir (C déductible / D due).
-- Renvoie le nombre de lignes insérées.
CREATE OR REPLACE FUNCTION post_reverse_charge_vat(p_tenant uuid, p_entry uuid, p_code text, p_amount numeric,
  p_sign int, p_order int, p_number text)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_due text; v_ded text;
BEGIN
  IF COALESCE(p_amount, 0) = 0 THEN RETURN 0; END IF;
  SELECT account_code INTO v_due FROM vat_account_mapping
  WHERE tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND vat_code = p_code AND direction = 'collected'
  ORDER BY (tenant_id = p_tenant) DESC LIMIT 1;
  SELECT account_code INTO v_ded FROM vat_account_mapping
  WHERE tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND vat_code = p_code AND direction = 'deductible'
  ORDER BY (tenant_id = p_tenant) DESC LIMIT 1;
  IF v_due IS NULL OR v_ded IS NULL THEN
    RAISE EXCEPTION 'Code TVA autoliquidé % : comptes de TVA due et déductible non paramétrés', p_code
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, vat_code, vat_amount,
                             debit, credit, description, line_order)
  VALUES (p_tenant, p_entry, v_ded, v_ded, p_code, p_amount,
          CASE WHEN p_sign > 0 THEN p_amount ELSE 0 END, CASE WHEN p_sign > 0 THEN 0 ELSE p_amount END,
          'TVA déductible autoliquidée ' || p_code || ' — ' || p_number, p_order),
         (p_tenant, p_entry, v_due, v_due, p_code, p_amount,
          CASE WHEN p_sign > 0 THEN 0 ELSE p_amount END, CASE WHEN p_sign > 0 THEN p_amount ELSE 0 END,
          'TVA due autoliquidée ' || p_code || ' — ' || p_number, p_order + 1);
  RETURN 2;
END $$;
REVOKE ALL ON FUNCTION post_reverse_charge_vat(uuid, uuid, text, numeric, int, int, text) FROM PUBLIC, anon, authenticated;

-- Nature d'un compte de TVA pour la déclaration : paramétrage (société d'abord), sinon racine
CREATE OR REPLACE FUNCTION vat_account_class(p_tenant uuid, p_account text,
  OUT direction text, OUT reverse_charge boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(m.direction, CASE WHEN p_account ~ '^445(2|7)' THEN 'collected'
                                    WHEN p_account ~ '^4456' THEN 'deductible' END),
         COALESCE(m.reverse_charge, p_account ~ '^4452')
  FROM (SELECT 1) one
  LEFT JOIN LATERAL (SELECT x.direction, x.reverse_charge FROM vat_account_mapping x
                     WHERE x.tenant_id IN (p_tenant, '00000000-0000-0000-0000-000000000000') AND x.account_code = p_account
                     ORDER BY (x.tenant_id = p_tenant) DESC, x.reverse_charge DESC LIMIT 1) m ON true
$$;

-- ------------------------------------------------------------
-- 3. Plan semé : libellés du paramétrage
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION seed_vat_accounts(p_tenant_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  SELECT DISTINCT ON (m.account_code) p_tenant_id, m.account_code,
         COALESCE(m.account_name,
                  CASE m.direction WHEN 'collected' THEN 'TVA collectée ' ELSE 'TVA déductible ' END || m.vat_code),
         CASE m.direction WHEN 'collected' THEN 'liability' ELSE 'asset' END
  FROM vat_account_mapping m
  WHERE m.tenant_id IN (p_tenant_id, '00000000-0000-0000-0000-000000000000')
  ORDER BY m.account_code, (m.tenant_id = p_tenant_id) DESC, (m.account_name IS NULL), m.reverse_charge, m.vat_code
  ON CONFLICT (tenant_id, code) DO NOTHING;
$$;
REVOKE ALL ON FUNCTION seed_vat_accounts(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 4. Lignes de pièces : un code autoliquidé ne facture pas de TVA
-- ------------------------------------------------------------
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
  -- 197 : autoliquidation — le vendeur ne facture pas la TVA
  IF vat_reverse_charge(NEW.tenant_id, NEW.vat_code) THEN
    NEW.vat_total := 0;
    NEW.vat_amount := 0;
  END IF;
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
  IF vat_reverse_charge(NEW.tenant_id, NEW.vat_code) THEN
    NEW.vat_total := 0;
    NEW.vat_amount := 0;
  END IF;
  RETURN NEW;
END $$;

-- Achats : la TVA autoliquidée n'est pas due au fournisseur ; elle est calculée
-- à la comptabilisation depuis le taux de la ligne (conservé)
CREATE OR REPLACE FUNCTION purchase_invoice_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM purchase_invoices WHERE approval_status = 'approved'
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_invoice_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_invoice_id END)) THEN
    RAISE EXCEPTION 'Facture fournisseur approuvée : ses lignes ne peuvent plus être modifiées (saisissez un avoir)'
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
  IF vat_reverse_charge(NEW.tenant_id, NEW.vat_code) THEN
    NEW.vat_total := 0;
    NEW.vat_amount := 0;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION purchase_credit_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM purchase_credit_notes WHERE status IN ('validated', 'applied')
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_credit_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_credit_id END)) THEN
    RAISE EXCEPTION 'Avoir fournisseur validé : ses lignes ne peuvent plus être modifiées'
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
  IF vat_reverse_charge(NEW.tenant_id, NEW.vat_code) THEN
    NEW.vat_total := 0;
    NEW.vat_amount := 0;
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 5. Comptabilisation des achats (facture, avoir) : TVA facturée, puis autoliquidée
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_journal_on_purchase_invoice_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '401000';
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 0;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_achat text := '607000';
BEGIN
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status = 'approved' THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01
    SELECT COALESCE(s.account_collectif, '401000'), s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- ACC-03 : boucle sur les lignes d'achat regroupées par compte de charge
    -- LOT2-02 : pil.subtotal → pil.total (subtotal n'existe pas sur purchase_invoice_lines)
    FOR v_ligne IN
      SELECT
        COALESCE(p.purchase_account_code, pc.purchase_account_code, v_defaut_achat) AS compte,
        SUM(pil.total) AS montant
      FROM purchase_invoice_lines pil
      LEFT JOIN products p ON p.id = pil.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY 1
    LOOP
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        v_ligne.montant, 0, 'Achats ' || v_ligne.compte || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 0 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_achat, v_defaut_achat,
        NEW.subtotal, 0, 'Achats ' || NEW.number, 0
      );
      v_ordre := 1;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA déductibles
    FOR v_vat IN
      SELECT pil.vat_code,
             SUM(pil.total) AS base_ht,
             SUM(pil.vat_amount) AS montant_tva
      FROM purchase_invoice_lines pil
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
        AND NOT vat_reverse_charge(NEW.tenant_id, pil.vat_code)
      GROUP BY pil.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'deductible'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '445660');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        v_vat.montant_tva, 0, 'TVA déductible ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- 197 : TVA autoliquidée (AUTOLIQ, UE…) — le fournisseur facture HT ;
    -- l'acheteur déclare la TVA due et la déduit (D déductible / C due)
    FOR v_vat IN
      SELECT pil.vat_code, SUM(vat_self_assessed(NEW.tenant_id, pil.vat_code, pil.total, pil.vat_rate)) AS montant_tva
      FROM purchase_invoice_lines pil
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
        AND vat_reverse_charge(NEW.tenant_id, pil.vat_code)
      GROUP BY pil.vat_code
    LOOP
      v_ordre := v_ordre + post_reverse_charge_vat(NEW.tenant_id, v_entry_id, v_vat.vat_code, v_vat.montant_tva, 1, v_ordre, NEW.number);
    END LOOP;

    -- Fallback TVA
    IF v_ordre <= 1 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '445660', '445660',
        'FR20', NEW.vat_total,
        NEW.vat_total, 0, 'TVA déductible ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;
    END IF;

    -- Ligne fournisseur (crédit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      New.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      0, NEW.total, 'Fournisseur ' || NEW.number, 99
    );

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_credit_note_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
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
  IF v_n > 0 THEN
    FOR r IN
      SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code, '609000') AS compte, sum(l.total) AS montant
      FROM purchase_credit_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.purchase_credit_id = NEW.id GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, 0, r.montant, 'Avoir obtenu ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
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
    -- Avoir global sans ligne (remise obtenue)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, '609000', '609000', 0, NEW.subtotal, 'Avoir obtenu ' || NEW.number, 1),
           (NEW.tenant_id, v_entry, '445660', '445660', 0, NEW.vat_total, 'TVA déductible — ' || NEW.number, 2);
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $$;


-- ------------------------------------------------------------
-- 6. Déclaration : mouvements des comptes de TVA de la période
--    (hors à-nouveaux AN, clôture CL et écritures de liquidation, qui
--    soldent les comptes de TVA contre 4455x / 44567)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_vat_ca3(p_period_start date, p_period_end date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lines jsonb;
  v_coll numeric; v_ded numeric; v_rc_due numeric; v_rc_ded numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  WITH mv AS (
    SELECT COALESCE(jl.account_general, jl.account_code) AS acc, jl.debit, jl.credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tid
      AND je.status = 'posted'
      AND je.date BETWEEN p_period_start AND p_period_end
      AND COALESCE(je.journal_code, '') NOT IN ('AN', 'CL')
      AND COALESCE(jl.account_general, jl.account_code) ~ '^445(2|6|7)'
      AND NOT EXISTS (SELECT 1 FROM journal_lines x
                      WHERE x.journal_id = je.id AND COALESCE(x.account_general, x.account_code) ~ '^(4455|44567)')
  ), acc AS (
    SELECT mv.acc, c.direction, c.reverse_charge,
           round(sum(CASE c.direction WHEN 'collected' THEN mv.credit - mv.debit ELSE mv.debit - mv.credit END), 2) AS amount
    FROM mv CROSS JOIN LATERAL vat_account_class(v_tid, mv.acc) c
    WHERE c.direction IS NOT NULL
    GROUP BY 1, 2, 3
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('account_code', acc, 'direction', direction,
                                               'reverse_charge', reverse_charge, 'amount', amount)
                            ORDER BY direction, acc), '[]'::jsonb),
         COALESCE(sum(amount) FILTER (WHERE direction = 'collected'), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'deductible'), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'collected' AND reverse_charge), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'deductible' AND reverse_charge), 0)
    INTO v_lines, v_coll, v_ded, v_rc_due, v_rc_ded
  FROM acc;

  RETURN jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'source', 'ledger',
    'vat_collected', v_coll,
    'vat_deductible', v_ded,
    'reverse_charge_due', v_rc_due,
    'reverse_charge_deductible', v_rc_ded,
    'vat_to_pay', GREATEST(v_coll - v_ded, 0),
    'vat_credit', GREATEST(v_ded - v_coll, 0),
    'lines', v_lines
  );
END $$;

-- Synthèse par code : sens tiré du compte (paramétrage, société d'abord), montant
-- signé par le débit/crédit (un avoir vient en déduction), une seule ligne de
-- paramétrage par code (la surcharge société ne double plus les montants)
CREATE OR REPLACE FUNCTION public.get_vat_summary_by_code(
  p_fiscal_year_id uuid,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL
)
RETURNS TABLE(
  vat_code text,
  direction text,
  account_code text,
  ca3_box text,
  base_ht numeric,
  vat_amount numeric,
  rate numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ), l AS (
    SELECT jl.vat_code, a.acc, COALESCE(c.direction, 'unknown') AS direction,
           CASE c.direction WHEN 'collected' THEN jl.credit - jl.debit
                            WHEN 'deductible' THEN jl.debit - jl.credit
                            ELSE COALESCE(jl.vat_amount, 0) END AS amount,
           jl.tenant_id
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    CROSS JOIN LATERAL (SELECT COALESCE(jl.account_general, jl.account_code) AS acc) a
    CROSS JOIN LATERAL vat_account_class(jl.tenant_id, a.acc) c
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
      AND jl.vat_code IS NOT NULL
      AND jl.vat_code != ''
  )
  SELECT l.vat_code, l.direction, l.acc, m.ca3_box,
         CASE WHEN COALESCE(m.rate, 0) > 0 THEN l.amount / (m.rate / 100) ELSE 0 END,
         l.amount,
         COALESCE(m.rate, 0)
  FROM l
  LEFT JOIN LATERAL (SELECT x.ca3_box, x.rate FROM vat_account_mapping x
                     WHERE x.tenant_id IN (l.tenant_id, '00000000-0000-0000-0000-000000000000')
                       AND x.vat_code = l.vat_code AND x.direction = l.direction
                     ORDER BY (x.tenant_id = l.tenant_id) DESC LIMIT 1) m ON true
  ORDER BY l.vat_code, l.direction;
$$;

-- ------------------------------------------------------------
-- 7. Reprise
-- ------------------------------------------------------------
-- a. Libellés semés (« TVA collectée AUTOLIQ », « TVA déductible FR10 »…) : un libellé
--    retouché par la société est conservé
UPDATE chart_accounts ca SET name = m.account_name
FROM (SELECT DISTINCT account_code, account_name FROM vat_account_mapping
      WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND account_name IS NOT NULL) m
WHERE ca.code = m.account_code
  AND ca.name ~ '^TVA (collectée|déductible) [A-Z0-9]+$'
  AND ca.name IS DISTINCT FROM m.account_name;

-- b. Nouveaux comptes (445790, 445668, 445667) dans les plans existants
SELECT seed_vat_accounts(t.id) FROM tenants t
WHERE EXISTS (SELECT 1 FROM chart_accounts ca WHERE ca.tenant_id = t.id);

-- c. Pièces encore modifiables portant un code autoliquidé : lignes et totaux recalculés
UPDATE invoice_lines l SET vat_code = l.vat_code
WHERE vat_reverse_charge(l.tenant_id, l.vat_code) AND l.vat_amount <> 0
  AND EXISTS (SELECT 1 FROM invoices i WHERE i.id = l.invoice_id AND i.validation_status IS DISTINCT FROM 'validated');
UPDATE credit_note_lines l SET vat_code = l.vat_code
WHERE vat_reverse_charge(l.tenant_id, l.vat_code) AND l.vat_amount <> 0
  AND EXISTS (SELECT 1 FROM credit_notes c WHERE c.id = l.credit_note_id AND c.status NOT IN ('validated', 'applied'));
UPDATE purchase_invoice_lines l SET vat_code = l.vat_code
WHERE vat_reverse_charge(l.tenant_id, l.vat_code) AND l.vat_amount <> 0
  AND EXISTS (SELECT 1 FROM purchase_invoices i WHERE i.id = l.purchase_invoice_id AND i.approval_status IS DISTINCT FROM 'approved');
UPDATE purchase_credit_lines l SET vat_code = l.vat_code
WHERE vat_reverse_charge(l.tenant_id, l.vat_code) AND l.vat_amount <> 0
  AND EXISTS (SELECT 1 FROM purchase_credit_notes c WHERE c.id = l.purchase_credit_id AND c.status NOT IN ('validated', 'applied'));

-- d. Écritures validées avant la 197 : TVA d'un code autoliquidé sur les comptes de la
--    TVA ordinaire. Elles ne sont pas modifiées (une écriture validée se corrige par une
--    écriture de régularisation) : listées ici pour le cabinet.
CREATE OR REPLACE VIEW vat_reverse_charge_legacy_lines
WITH (security_invoker = true) AS
SELECT jl.tenant_id, je.id AS journal_entry_id, je.number AS entry_number, je.date, je.journal_code,
       jl.id AS journal_line_id, COALESCE(jl.account_general, jl.account_code) AS account_code,
       jl.vat_code, jl.debit, jl.credit,
       (SELECT m.account_code FROM vat_account_mapping m
        WHERE m.tenant_id IN (jl.tenant_id, '00000000-0000-0000-0000-000000000000') AND m.vat_code = jl.vat_code
          AND m.direction = CASE WHEN COALESCE(jl.account_general, jl.account_code) ~ '^4456' THEN 'deductible' ELSE 'collected' END
        ORDER BY (m.tenant_id = jl.tenant_id) DESC LIMIT 1) AS expected_account
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
WHERE je.status = 'posted'
  AND vat_reverse_charge(jl.tenant_id, jl.vat_code)
  AND COALESCE(jl.account_general, jl.account_code) ~ '^445'
  AND COALESCE(jl.account_general, jl.account_code) NOT IN (
        SELECT m.account_code FROM vat_account_mapping m
        WHERE m.tenant_id IN (jl.tenant_id, '00000000-0000-0000-0000-000000000000') AND m.vat_code = jl.vat_code);
COMMENT ON VIEW vat_reverse_charge_legacy_lines IS
  '197 — lignes validées avant la séparation de la TVA autoliquidée, imputées sur un compte de TVA ordinaire (à régulariser)';
REVOKE ALL ON vat_reverse_charge_legacy_lines FROM PUBLIC, anon;
GRANT SELECT ON vat_reverse_charge_legacy_lines TO authenticated, service_role;

DO $$
DECLARE n int; nt int;
BEGIN
  SELECT count(*), count(DISTINCT tenant_id) INTO n, nt FROM vat_reverse_charge_legacy_lines;
  RAISE NOTICE '197 : % ligne(s) validée(s) de TVA autoliquidée sur un compte de TVA ordinaire, % société(s) — voir vat_reverse_charge_legacy_lines', n, nt;
END $$;
