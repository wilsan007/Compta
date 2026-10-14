-- ═══════════════════════════════════════════════════════════════════════════
-- 393 — roles_journaux_restants_3 : journaux en dur, tranche 3 (LOC1-09)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Fin de LOC1-09 : les **4 dernières** fonctions qui portaient un
-- code de journal littéral demandent leur RÔLE. Le pack PCG rend EXACTEMENT les
-- codes d'avant (`JOURNAL_VENTES→VT`, `JOURNAL_ACHATS→AC`, `JOURNAL_OD→OD`) :
-- aucune écriture ne change.
--
-- ⚠ RESTENT EN DUR, ET POURQUOI : les COMPTES (`411000`, `401000`, `706000`,
-- `707000`, `709000`, `609000`, `445710`, `445660`, `280000`, `681000`…) — des
-- comptes, pas des journaux (LOC1-10/11). `generate_depreciation_entry` est
-- particulièrement concerné : ses comptes d'amortissement ne correspondent PAS
-- aux rôles (par catégorie) — c'est un sujet à trancher, pas à corriger ici.
--
-- Après cette tranche, le garde de la suite `391` (T03) doit trouver un reste
-- **VIDE**.
--
-- Numéro pris le 2026-10-11T06:01:00.895Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Avoir client → journal VT
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

  SELECT COALESCE(account_collectif, '411000'), account_tiers INTO v_collectif, v_tiers
  FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '411000');

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

-- ─────────────────────────────────────────────────────────────
-- 2. Avoir fournisseur → journal AC
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

  SELECT COALESCE(account_collectif, '401000'), account_tiers INTO v_collectif, v_tiers
  FROM suppliers WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '401000');

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
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Dotation aux amortissements → journal OD
-- ─────────────────────────────────────────────────────────────
-- ⚠ Les COMPTES restent des COMPTES (681200/281000 par défaut, ou ceux de la
--   fiche) : ce ne sont PAS des journaux, on ne les touche pas ici. Le pack
--   porte 681100 « Dotations aux amortissements » et 280000/281000 côté
--   amortissements, et les rôles de la 383 sont rangés PAR CATÉGORIE. Réécrire
--   ces comptes changerait les écritures comptabilisées → arbitrage, hors LOC1-09.
CREATE OR REPLACE FUNCTION public.generate_depreciation_entry(p_fixed_asset_id uuid, p_fiscal_year_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fa fixed_assets%ROWTYPE;
  v_fy fiscal_years%ROWTYPE;
  v_methode text;
  v_base numeric;
  v_annuel numeric;
  v_amount numeric;
  v_cumul numeric;
  v_total numeric;
  v_annees int;
  v_taux numeric;
  v_debit text;
  v_credit text;
  v_number text;
  v_ref text;
  v_je uuid;
  v_existe uuid;
  v_journal text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fa FROM fixed_assets WHERE id = p_fixed_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Immobilisation introuvable : %', p_fixed_asset_id; END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice introuvable : %', p_fiscal_year_id; END IF;

  -- IMMO-03 : une dotation d'exercice CLOS ne se recalcule pas. Le cumul vient
  -- de l'historique, l'exercice de la demande — jamais de la date du jour.
  IF v_fy.status <> 'open' THEN
    RAISE EXCEPTION 'Exercice % : statut % — une dotation d''exercice clos ne se recalcule pas', v_fy.code, v_fy.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : une dotation déjà comptabilisée est rendue telle quelle
  v_ref := 'AMORT:' || v_fa.id || ':' || v_fy.code;
  SELECT id INTO v_existe FROM journal_entries
  WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN RETURN v_existe; END IF;

  IF v_fa.status <> 'active' THEN
    RAISE EXCEPTION 'Immobilisation % : statut % — aucune dotation à comptabiliser', v_fa.name, v_fa.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- IMMO-04 : la méthode est LUE. Les deux façons d'écrire le linéaire que le
  -- dépôt connaît (l'écran écrit `straight_line`, les reprises `linear`)
  -- désignent le MÊME moteur.
  v_methode := lower(COALESCE(NULLIF(btrim(v_fa.depreciation_method), ''), 'linear'));
  IF v_methode NOT IN ('linear', 'straight_line', 'declining', 'declining_balance') THEN
    IF v_methode = 'units_of_production' THEN
      RAISE EXCEPTION 'Immobilisation % : méthode « units_of_production » RETIRÉE — la fiche ne porte aucun compteur d''unités produites, une dotation par unité serait une donnée inventée ; utilisez linear ou declining_balance', v_fa.name
        USING ERRCODE = 'feature_not_supported';
    END IF;
    RAISE EXCEPTION 'Immobilisation % : méthode d''amortissement « % » inconnue (attendu : linear, straight_line, declining_balance)', v_fa.name, v_methode
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_base := GREATEST(COALESCE(v_fa.purchase_value, 0) - COALESCE(v_fa.residual_value, 0), 0);
  IF v_base = 0 OR COALESCE(v_fa.useful_life_years, 0) <= 0 THEN
    RETURN NULL;  -- rien à amortir
  END IF;

  -- Amortissements déjà dotés : l'historique fait foi, pas la valeur courante.
  -- `v_annees` compte les exercices déjà dotés (la bascule du dégressif en
  -- dépend) ; le cumul est plafonné à la base amortissable.
  SELECT COALESCE(sum(amount), 0), count(*) INTO v_cumul, v_annees
  FROM asset_depreciations
  WHERE tenant_id = v_tid AND asset_id = v_fa.id AND depreciation_type = 'dotation';
  v_cumul := LEAST(v_cumul, v_base);

  IF v_methode IN ('declining', 'declining_balance') THEN
    -- Taux dégressif = coefficient légal / durée, avec BASCULE sur le linéaire
    -- du restant dès que celui-ci devient plus favorable.
    v_taux := depreciation_coefficient(v_tid, v_fa.useful_life_years) / v_fa.useful_life_years;
    v_taux := GREATEST(v_taux, 1.0 / GREATEST(v_fa.useful_life_years - v_annees, 1));
    v_annuel := round(GREATEST(v_base - v_cumul, 0) * v_taux, 2);
  ELSE
    v_annuel := round(v_base / v_fa.useful_life_years, 2);
  END IF;
  v_amount := v_annuel;

  -- Prorata temporis en jours pour l'exercice d'acquisition
  IF v_fa.purchase_date > v_fy.start_date THEN
    v_amount := round(v_annuel * ((v_fy.end_date - v_fa.purchase_date) + 1)::numeric
                             / ((v_fy.end_date - v_fy.start_date) + 1), 2);
  END IF;

  -- Jamais plus que la base amortissable
  v_amount := LEAST(v_amount, round(v_base - v_cumul, 2));
  IF v_amount <= 0 THEN RETURN NULL; END IF;

  -- Comptes : ceux de l'immobilisation, sinon les comptes généraux du PCG
  v_debit := COALESCE(NULLIF(btrim(v_fa.account_expense_depreciation_code), ''), '681200');
  v_credit := COALESCE(NULLIF(btrim(v_fa.account_depreciation_code), ''), '281000');
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_debit) THEN
    RAISE EXCEPTION 'Compte de dotation % absent du plan comptable de la société', v_debit
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_credit) THEN
    RAISE EXCEPTION 'Compte d''amortissement % absent du plan comptable de la société', v_credit
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(v_tid);
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  -- 1. en-tête en brouillard (AUD-C02)
  v_number := 'AMORT-' || COALESCE(NULLIF(btrim(v_fa.code), ''), NULLIF(btrim(v_fa.asset_number), ''),
                                   left(v_fa.id::text, 8)) || '-' || v_fy.code;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_fy.end_date, v_journal, 'draft',
          'Dotation aux amortissements ' || v_fy.code || ' ('
            || CASE WHEN v_methode IN ('declining', 'declining_balance') THEN 'dégressif' ELSE 'linéaire' END
            || ') - ' || v_fa.name,
          v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
  VALUES
    (v_tid, v_je, v_debit,  'Dotations aux amortissements', v_amount, 0, 'Dotation ' || v_fy.code),
    (v_tid, v_je, v_credit, 'Amortissements', 0, v_amount, 'Dotation ' || v_fy.code);

  -- 3. validation : les triggers de la 187 vérifient équilibre, exercice, comptes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  -- Historique de l'immobilisation + valeur nette.
  -- 226 : la VNC est la valeur d'ACQUISITION moins le cumul — la résiduelle est
  -- déjà hors de la base amortissable, la retrancher ici la déduirait deux fois.
  v_total := v_cumul + v_amount;
  INSERT INTO asset_depreciations (tenant_id, asset_id, fiscal_year_code, period, depreciation_type,
    amount, cumulative_amount, net_book_value, entry_number)
  VALUES (v_tid, v_fa.id, v_fy.code, 12, 'dotation', v_amount, v_total,
    round(GREATEST(COALESCE(v_fa.purchase_value, 0) - v_total, 0), 2), v_number);

  UPDATE fixed_assets
  SET current_value = GREATEST(COALESCE(purchase_value, 0) - v_total, 0),
      status = CASE WHEN v_total >= v_base THEN 'fully_depreciated' ELSE status END,
      updated_at = now()
  WHERE id = v_fa.id AND tenant_id = v_tid;

  RETURN v_je;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 4. Réévaluation des soldes en devises → journal OD
-- ─────────────────────────────────────────────────────────────
-- ⚠ Les comptes de contrepartie (766000 gain / 666000 perte) restent des
--   COMPTES : LOC1-10/11. Ici, seul le JOURNAL passe par le rôle.
CREATE OR REPLACE FUNCTION public.revaluate_currency_balances(p_period_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fonc text;
  v_fiche uuid;
  v_nb int := 0;
  v_sans_taux int := 0;
  v_total numeric := 0;
  v_entry uuid;
  v_num text;
  v_ordre int := 0;
  v_journal text;
  r record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF p_period_date IS NULL THEN
    RAISE EXCEPTION 'Date de réévaluation absente' USING ERRCODE = '22007';
  END IF;
  -- Idempotence : une période déjà réévaluée est refusée, pas réécrite en silence.
  IF EXISTS (SELECT 1 FROM public.currency_revaluations
             WHERE tenant_id = v_tid AND period_date = p_period_date AND status <> 'cancelled') THEN
    RAISE EXCEPTION 'La période du % a déjà été réévaluée', p_period_date USING ERRCODE = '23505';
  END IF;

  v_fonc := public.functional_currency(v_tid);
  SELECT id INTO v_fiche FROM public.fiscal_years
  WHERE tenant_id = v_tid AND p_period_date BETWEEN start_date AND end_date LIMIT 1;

  -- Les soldes **en devise** des comptes de tiers, au taux du jour.
  -- `exchange_rates` : `quote_currency` est la devise, `rate` sa valeur dans la
  -- devise de tenue.
  INSERT INTO public.currency_revaluations (
    tenant_id, fiscal_year_id, period_date, account_code, third_party_code, currency,
    original_rate, new_rate, original_amount, original_amount_eur, revalued_amount_eur,
    gain_loss, type, status
  )
  SELECT v_tid, v_fiche, p_period_date, x.compte, x.tiers, x.dev,
         CASE WHEN x.solde_devise <> 0 THEN round(x.histo / x.solde_devise, 6) ELSE 1 END,
         t.rate, x.solde_devise, x.histo, round(x.solde_devise * t.rate, 2),
         round(x.solde_devise * t.rate, 2) - x.histo,
         CASE WHEN left(x.compte, 2) = '41' THEN 'receivable' ELSE 'payable' END,
         'pending'
  FROM (
    SELECT COALESCE(l.account_general, l.account_code) AS compte,
           COALESCE(l.account_tiers, '') AS tiers,
           l.currency_code AS dev,
           round(sum(l.currency_amount), 2) AS solde_devise,
           round(sum(l.debit - l.credit), 2) AS histo
    FROM public.journal_lines l
    JOIN public.journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
    WHERE l.tenant_id = v_tid
      AND e.status = 'posted'
      AND e.date <= p_period_date
      AND l.currency_code IS NOT NULL AND l.currency_code <> v_fonc
      AND COALESCE(l.account_general, l.account_code) ~ '^4[01]'
    GROUP BY 1, 2, 3
    HAVING round(sum(l.currency_amount), 2) <> 0
  ) x
  JOIN LATERAL (
    SELECT er.rate FROM public.exchange_rates er
    WHERE (er.tenant_id = v_tid OR er.tenant_id IS NULL)
      AND er.quote_currency = x.dev
      AND (er.base_currency IS NULL OR er.base_currency = v_fonc)
      AND er.rate_date <= p_period_date
    ORDER BY er.rate_date DESC LIMIT 1
  ) t ON true;
  GET DIAGNOSTICS v_nb = ROW_COUNT;


  -- Les soldes en devise **sans taux** ne sont pas réévalués : ils sont comptés
  -- et rendus, plutôt que réévalués à un taux inventé.
  SELECT count(*) INTO v_sans_taux
  FROM (
    SELECT COALESCE(l.account_general, l.account_code) AS compte,
           COALESCE(l.account_tiers, '') AS tiers, l.currency_code AS dev
    FROM public.journal_lines l
    JOIN public.journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
    WHERE l.tenant_id = v_tid
      AND e.status = 'posted'
      AND e.date <= p_period_date
      AND l.currency_code IS NOT NULL AND l.currency_code <> v_fonc
      AND COALESCE(l.account_general, l.account_code) ~ '^4[01]'
    GROUP BY 1, 2, 3
    HAVING round(sum(l.currency_amount), 2) <> 0
      AND NOT EXISTS (SELECT 1 FROM public.exchange_rates er
                      WHERE (er.tenant_id = v_tid OR er.tenant_id IS NULL)
                        AND er.quote_currency = l.currency_code
                        AND er.rate_date <= p_period_date)
  ) s;

  IF v_nb = 0 THEN
    RETURN jsonb_build_object('period_date', p_period_date, 'lines', 0,
                              'gain_loss', 0, 'without_rate', v_sans_taux, 'entry_id', NULL);
  END IF;

  SELECT COALESCE(sum(gain_loss), 0) INTO v_total
  FROM public.currency_revaluations
  WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending';

  -- L'écriture de réévaluation : le solde de chaque tiers, contre 766 (gain) ou
  -- 666 (perte). Le total des ajustements équilibre la contrepartie.
  v_num := 'REVAL-' || to_char(p_period_date, 'YYYY-MM-DD');

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(v_tid);
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  INSERT INTO public.journal_entries (
    tenant_id, number, date, journal_code, status, description, reference, piece_number
  ) VALUES (
    v_tid, v_num, p_period_date, v_journal, 'draft',
    'Réévaluation des créances et dettes en devises au ' || p_period_date, v_num, v_num
  ) RETURNING id INTO v_entry;

  FOR r IN
    SELECT * FROM public.currency_revaluations
    WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending'
      AND gain_loss <> 0
    ORDER BY account_code, third_party_code
  LOOP
    IF r.gain_loss > 0 THEN
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                        account_tiers, debit, credit, description, line_order)
      VALUES (v_tid, v_entry, r.account_code, r.account_code,
              NULLIF(r.third_party_code, ''), r.gain_loss, 0,
              'Réévaluation ' || r.currency || ' — ' || r.account_code, v_ordre);
    ELSE
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                        account_tiers, debit, credit, description, line_order)
      VALUES (v_tid, v_entry, r.account_code, r.account_code,
              NULLIF(r.third_party_code, ''), 0, abs(r.gain_loss),
              'Réévaluation ' || r.currency || ' — ' || r.account_code, v_ordre);
    END IF;
    v_ordre := v_ordre + 1;
  END LOOP;

  IF v_total > 0 THEN
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (v_tid, v_entry, '766000', '766000', 0, v_total, 'Gain de change (réévaluation)', v_ordre);
  ELSIF v_total < 0 THEN
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (v_tid, v_entry, '666000', '666000', abs(v_total), 0, 'Perte de change (réévaluation)', v_ordre);
  END IF;

  UPDATE public.journal_entries SET status = 'posted' WHERE id = v_entry AND tenant_id = v_tid;
  UPDATE public.currency_revaluations
  SET status = 'posted', entry_id = v_entry, updated_at = now()
  WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending';

  RETURN jsonb_build_object('period_date', p_period_date, 'lines', v_nb,
                            'gain_loss', v_total, 'without_rate', v_sans_taux, 'entry_id', v_entry);
END;
$function$
