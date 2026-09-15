-- ============================================================
-- 109_vat_multi_rate.sql
-- ACC-02 : TVA multi-taux et code TVA
--
-- Remplace la ligne de TVA unique par une boucle sur les taux
-- réellement présents dans les lignes de facture.
-- ============================================================

-- ============================================================
-- 1. Table de correspondance VAT code → compte
-- ============================================================
CREATE TABLE IF NOT EXISTS vat_account_mapping (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  vat_code text NOT NULL,
  rate numeric NOT NULL,
  direction text NOT NULL CHECK (direction IN ('collected', 'deductible')),
  account_code text NOT NULL,
  ca3_box text,
  base_account text,
  UNIQUE (tenant_id, vat_code, direction)
);

ALTER TABLE vat_account_mapping ENABLE ROW LEVEL SECURITY;
CREATE POLICY vat_account_mapping_tenant_select ON vat_account_mapping
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY vat_account_mapping_tenant_all ON vat_account_mapping
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

-- Seed : mappings par défaut pour la France (tenant_id = tous)
-- Ces mappings sont créés au niveau du tenant à l'initialisation
INSERT INTO vat_account_mapping (tenant_id, vat_code, rate, direction, account_code, ca3_box)
SELECT '00000000-0000-0000-0000-000000000000', v.vat_code, v.rate, v.direction, v.account_code, v.ca3_box
FROM (VALUES
  ('FR20', 20.0, 'collected', '445711', 'A1'),
  ('FR10', 10.0, 'collected', '445712', 'A1'),
  ('FR055', 5.5, 'collected', '445713', 'A1'),
  ('FR021', 2.1, 'collected', '445714', 'A1'),
  ('FR0', 0.0, 'collected', '445710', 'A1'),
  ('EXO', 0.0, 'collected', '445710', 'A2'),
  ('UE', 20.0, 'collected', '445711', 'B2'),
  ('AUTOLIQ', 20.0, 'collected', '445711', 'B2'),
  ('FR20', 20.0, 'deductible', '445661', '08'),
  ('FR10', 10.0, 'deductible', '445662', '08'),
  ('FR055', 5.5, 'deductible', '445663', '08'),
  ('FR021', 2.1, 'deductible', '445664', '08'),
  ('AUTOLIQ', 20.0, 'deductible', '445661', '08')
) AS v(vat_code, rate, direction, account_code, ca3_box)
WHERE NOT EXISTS (
  SELECT 1 FROM vat_account_mapping
  WHERE tenant_id = '00000000-0000-0000-0000-000000000000'
    AND vat_code = v.vat_code AND direction = v.direction
);

-- ============================================================
-- 2. Ajouter vat_code et vat_amount sur invoice_lines si absents
-- ============================================================
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS vat_code text DEFAULT 'FR20';
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS vat_amount numeric DEFAULT 0;

-- ============================================================
-- 3. Réécrire le trigger de facture vente avec TVA multi-taux
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
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
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted') THEN
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

    -- Ligne client (débit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      NEW.total, 0, 'Client ' || NEW.number, 0
    );

    -- Ligne de vente (crédit) — compte 707000 par défaut
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      New.tenant_id, v_entry_id, '707000', '707000',
      0, NEW.subtotal, 'Ventes ' || NEW.number, 1
    );

    -- ACC-02 : boucle sur les taux de TVA réellement présents
    FOR v_vat IN
      SELECT il.vat_code,
             SUM(il.subtotal) AS base_ht,
             SUM(il.vat_amount) AS montant_tva
      FROM invoice_lines il
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY il.vat_code
    LOOP
      -- Récupérer le compte de TVA depuis le mapping
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'collected'
      ORDER BY tenant_id DESC  -- priorité au tenant spécifique
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '4457000');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        0, v_vat.montant_tva,
        'TVA collectée ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Si aucune ligne de TVA n'a été créée (pas de invoice_lines), fallback sur l'ancien comportement
    IF v_ordre = 2 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '4457000', '4457000',
        'FR20', NEW.vat_total,
        0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2
      );
    END IF;

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 4. Réécrire le trigger de facture achat avec TVA multi-taux
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_purchase_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
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
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted', 'approved') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : récupérer le compte collectif et le compte auxiliaire du fournisseur
    SELECT COALESCE(s.account_collectif, '401000'), s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- Ligne d'achat (débit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      New.tenant_id, v_entry_id, '607000', '607000',
      NEW.subtotal, 0, 'Achats ' || NEW.number, 0
    );

    -- ACC-02 : boucle sur les taux de TVA déductibles
    FOR v_vat IN
      SELECT pil.vat_code,
             SUM(pil.subtotal) AS base_ht,
             SUM(pil.vat_amount) AS montant_tva
      FROM purchase_invoice_lines pil
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY pil.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'deductible'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '4456000');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        v_vat.montant_tva, 0, 'TVA déductible ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre + 1
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes d'achat détaillées
    IF v_ordre = 0 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '4456000', '4456000',
        'FR20', NEW.vat_total,
        NEW.vat_total, 0, 'TVA déductible ' || NEW.number, 1
      );
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
$$;

-- ============================================================
-- 5. RPC : calcul de la TVA par code pour la CA3
-- ============================================================
CREATE OR REPLACE FUNCTION get_vat_summary_by_code(
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
  )
  SELECT
    jl.vat_code,
    CASE
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^4457' THEN 'collected'
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^4456' THEN 'deductible'
      ELSE 'unknown'
    END AS direction,
    COALESCE(jl.account_general, jl.account_code) AS account_code,
    m.ca3_box,
    -- Base HT : pour la TVA collectée, c'est le crédit du compte 70x ; pour déductible, le débit du 60x
    -- Approximation : on prend le montant de TVA / taux
    CASE
      WHEN m.rate > 0 THEN jl.vat_amount / (m.rate / 100)
      ELSE 0
    END AS base_ht,
    COALESCE(jl.vat_amount, 0) AS vat_amount,
    COALESCE(m.rate, 0) AS rate
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  CROSS JOIN bornes b
  LEFT JOIN vat_account_mapping m ON m.tenant_id IN (jl.tenant_id, '00000000-0000-0000-0000-000000000000')
    AND m.vat_code = jl.vat_code
    AND m.direction = CASE
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^4457' THEN 'collected'
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^4456' THEN 'deductible'
    END
  WHERE jl.tenant_id = current_tenant_id()
    AND je.status = 'posted'
    AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
    AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
    AND jl.vat_code IS NOT NULL
    AND jl.vat_code != ''
  ORDER BY jl.vat_code, direction;
$$;
