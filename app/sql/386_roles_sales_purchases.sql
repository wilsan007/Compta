-- ═══════════════════════════════════════════════════════════════════════════
-- 386 — roles_sales_purchases : LES QUATRE TRIGGERS SUR LES RÔLES (LOC1-06)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Les quatre déclencheurs qui passent une facture de vente, une
-- facture d'achat, un encaissement et un décaissement en comptabilité ne
-- portent plus de numéro de compte : ils DEMANDENT un rôle. Cahier §5,
-- tâche LOC1-06. Le littéral `'411000'` devient
-- `resolve_account(…,'CLIENTS',{customer_id})`, `'VT'` devient
-- `resolve_journal(…,'JOURNAL_VENTES')`, etc.
--
-- ÉCRITURES IDENTIQUES — LA RECETTE DU CAHIER. Pour une société FR, les
-- écritures doivent rester **identiques ligne à ligne** (le pack PCG sème
-- `CLIENTS→411000`, `VENTES_MARCHANDISES→707000`, `PRESTATIONS_SERVICES→706000`,
-- `TVA_COLLECTEE→445710`, `FOURNISSEURS→401000`, `ACHATS_MARCHANDISES→607000`,
-- `TVA_DEDUCTIBLE_BIENS_SERVICES→445660`, `JOURNAL_VENTES→VT`, `JOURNAL_ACHATS→AC`).
-- Preuve : `102_trigger_tests.sql` rejoué, vert — il est inchangé.
--
-- LE PONT « SOCIÉTÉ SANS PACK → PACK PAR DÉFAUT ». `resolve_account` échouait
-- (`ROLE_NON_MAPPE`) pour une société SANS pack ; or les fixtures de test
-- (`_mk_tenant`) n'en posent aucun. On ajoute donc la règle de phase 1 : le
-- pack effectif d'une société sans pack est le **pack par défaut** (`FR`).
-- Elle ne masque rien — c'est le pack FR lui-même qui répond — et elle
-- disparaîtra quand toute société aura un pack (`LOC1-12` / `LOC1-15`).
--
-- ⚠ CE QUI N'EST VOLONTAIREMENT PAS CHANGÉ. La TVA continue de passer par
-- `vat_account_mapping` (par code de taux) ; seul le REPLI final devient le
-- rôle. Et la trésorerie des règlements reste `treasury_for_payment` (elle lit
-- déjà le compte de banque / le mode) ; seuls les replis collectifs deviennent
-- des rôles. Changer ces deux-là changerait les écritures, ce que la recette
-- interdit.
--
-- REJOUABLE : `CREATE OR REPLACE` partout.
--
-- Numéro pris le 2026-10-05T20:40:02.680Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Le pont : pack effectif = pack de la société, sinon pack PAR DÉFAUT
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_account(p_tenant_id uuid, p_role text, p_context jsonb DEFAULT '{}'::jsonb)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text; v_pack text;
BEGIN
  -- 1. surcharge objet métier
  v := resolve_account_from_context(p_tenant_id, p_role, p_context);

  -- 2. surcharge société
  IF v IS NULL THEN
    SELECT account_code INTO v FROM tenant_account_roles
     WHERE tenant_id = p_tenant_id AND role = p_role;
  END IF;

  -- 3. rôle du pack effectif (le plus spécifique gagne)
  IF v IS NULL THEN
    v_pack := tenant_pack_code(p_tenant_id);
    IF v_pack IS NULL THEN
      SELECT code INTO v_pack FROM legislation_packs WHERE is_default AND active ORDER BY code LIMIT 1;
    END IF;
    SELECT par.account_code INTO v
      FROM pack_lineage(v_pack) l
      JOIN pack_account_roles par ON par.pack_code = l.code AND par.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;

  -- 4. échec explicite — jamais de repli silencieux
  IF v IS NULL THEN
    RAISE EXCEPTION 'ROLE_NON_MAPPE: le rôle % n''a aucun compte pour la société %', p_role, p_tenant_id
      USING ERRCODE = 'P0001', HINT = 'Paramétrage > Comptes par défaut';
  END IF;

  -- 5. le compte doit exister dans le plan de la société
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id AND code = v) THEN
    RAISE EXCEPTION 'COMPTE_ABSENT: le rôle % pointe vers % absent du plan', p_role, v
      USING ERRCODE = 'P0001';
  END IF;

  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION resolve_journal(p_tenant_id uuid, p_role text)
RETURNS text
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v text; v_pack text;
BEGIN
  SELECT journal_code INTO v FROM tenant_journal_roles
   WHERE tenant_id = p_tenant_id AND role = p_role;

  IF v IS NULL THEN
    v_pack := tenant_pack_code(p_tenant_id);
    IF v_pack IS NULL THEN
      SELECT code INTO v_pack FROM legislation_packs WHERE is_default AND active ORDER BY code LIMIT 1;
    END IF;
    SELECT pjr.journal_code INTO v
      FROM pack_lineage(v_pack) l
      JOIN pack_journal_roles pjr ON pjr.pack_code = l.code AND pjr.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;

  IF v IS NULL THEN
    RAISE EXCEPTION 'ROLE_JOURNAL_NON_MAPPE: %', p_role USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = p_tenant_id AND code = v) THEN
    RAISE EXCEPTION 'JOURNAL_ABSENT: le rôle % pointe vers % absent', p_role, v USING ERRCODE = 'P0001';
  END IF;

  RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2. Facture de VENTE → journal VT
-- ─────────────────────────────────────────────────────────────
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
  v_collectif text;
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 2;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_vente text;
  v_compte_acompte text;
  v_journal text;
  v_is_advance boolean := COALESCE(NEW.invoice_type = 'advance' OR NEW.is_advance_invoice, false);
  v_adv uuid;
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
    v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_VENTES');
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = v_journal LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : le collectif client vient du RÔLE (client → société → pack)
    v_collectif      := resolve_account(NEW.tenant_id, 'CLIENTS', jsonb_build_object('customer_id', NEW.customer_id));
    v_defaut_vente   := resolve_account(NEW.tenant_id, 'VENTES_MARCHANDISES');
    v_compte_acompte := resolve_account(NEW.tenant_id, 'CLIENTS_AVANCES_RECUES');

    SELECT c.account_tiers, c.id
    INTO v_tiers, v_third_party
    FROM customers c
    WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;

    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, v_journal, 'draft', 'Facture vente ' || NEW.number, NEW.number, v_number)
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
    FOR v_ligne IN
      SELECT
        CASE WHEN v_is_advance OR il.advance_invoice_id IS NOT NULL THEN v_compte_acompte
             ELSE COALESCE(p.sale_account_code, pc.sale_account_code, il.account_code,
                        CASE WHEN p.type = 'service'
                             THEN resolve_account(NEW.tenant_id, 'PRESTATIONS_SERVICES',
                                                  jsonb_build_object('product_id', il.product_id))
                             ELSE v_defaut_vente END) END AS compte,
        CASE WHEN v_is_advance THEN NEW.id ELSE il.advance_invoice_id END AS acompte,
        SUM(il.total) AS montant
      FROM invoice_lines il
      LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY 1, 2
    LOOP
      CONTINUE WHEN v_ligne.montant = 0;
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

    -- ACC-02 : boucle sur les taux de TVA (le mapping par code reste ; le REPLI devient le rôle)
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

      v_compte_tva := COALESCE(v_compte_tva, resolve_account(NEW.tenant_id, 'TVA_COLLECTEE'));

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
      v_compte_tva := resolve_account(NEW.tenant_id, 'TVA_COLLECTEE');
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
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

-- ─────────────────────────────────────────────────────────────
-- 3. Facture d'ACHAT → journal AC
-- ─────────────────────────────────────────────────────────────
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
  v_collectif text;
  v_tiers text;
  v_third_party uuid;
  v_compte_tva text;
  v_ordre int := 0;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_achat text;
  v_journal text;
BEGIN
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status = 'approved' THEN
    v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_ACHATS');
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = v_journal LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : le collectif fournisseur vient du RÔLE (fournisseur → société → pack)
    v_collectif    := resolve_account(NEW.tenant_id, 'FOURNISSEURS', jsonb_build_object('supplier_id', NEW.supplier_id));
    v_defaut_achat := resolve_account(NEW.tenant_id, 'ACHATS_MARCHANDISES');

    SELECT s.account_tiers, s.id INTO v_tiers, v_third_party
    FROM suppliers s WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, v_journal, 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- ACC-03 : boucle sur les lignes d'achat regroupées par compte de charge
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

    -- ACC-02 : TVA déductible (mapping par code conservé ; le REPLI devient le rôle)
    FOR v_vat IN
      SELECT pil.vat_code, SUM(pil.total) AS base_ht, SUM(pil.vat_amount) AS montant_tva
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

      v_compte_tva := COALESCE(v_compte_tva, resolve_account(NEW.tenant_id, 'TVA_DEDUCTIBLE_BIENS_SERVICES'));

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
      v_compte_tva := resolve_account(NEW.tenant_id, 'TVA_DEDUCTIBLE_BIENS_SERVICES');
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
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

-- ─────────────────────────────────────────────────────────────
-- 4. Encaissement client → journal de trésorerie
--    (la trésorerie reste `treasury_for_payment` ; seul le collectif devient un rôle)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_journal_on_customer_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text;
  v_avance text;
  v_tiers text;
  v_third_party uuid;
  v_customer uuid;
  v_tr record;
  v_remaining numeric;
  v_excess numeric := 0;
BEGIN
  v_customer := NEW.customer_id;
  IF v_customer IS NULL AND NEW.invoice_id IS NOT NULL THEN
    SELECT i.customer_id INTO v_customer FROM invoices i
     WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
  END IF;

  SELECT c.account_tiers, c.id INTO v_tiers, v_third_party
  FROM customers c WHERE c.id = v_customer AND c.tenant_id = NEW.tenant_id;

  -- le collectif client vient du RÔLE (client → société → pack)
  v_collectif := resolve_account(NEW.tenant_id, 'CLIENTS', jsonb_build_object('customer_id', v_customer));

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
    v_avance := resolve_account(NEW.tenant_id, 'CLIENTS_AVANCES_RECUES');
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_avance, v_avance, v_tiers, v_third_party,
            0, v_excess, 'Avance client (trop-perçu) ' || NEW.number, 2);
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 5. Décaissement fournisseur → journal de trésorerie
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_journal_on_supplier_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid; v_number text;
  v_collectif text; v_avance text; v_tiers text; v_third_party uuid;
  v_supplier uuid; v_tr record; v_remaining numeric; v_excess numeric := 0;
BEGIN
  v_supplier := NEW.supplier_id;
  IF v_supplier IS NULL AND NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT pi.supplier_id INTO v_supplier FROM purchase_invoices pi
     WHERE pi.id = NEW.purchase_invoice_id AND pi.tenant_id = NEW.tenant_id;
  END IF;

  SELECT s.account_tiers, s.id INTO v_tiers, v_third_party
  FROM suppliers s WHERE s.id = v_supplier AND s.tenant_id = NEW.tenant_id;

  -- le collectif fournisseur vient du RÔLE (fournisseur → société → pack)
  v_collectif := resolve_account(NEW.tenant_id, 'FOURNISSEURS', jsonb_build_object('supplier_id', v_supplier));

  -- Trop-payé : avance fournisseur (décision n° 1 appliquée aux achats)
  IF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT COALESCE(i.total, 0)
           - COALESCE((SELECT sum(amount) FROM supplier_payments p
                       WHERE p.purchase_invoice_id = i.id AND p.id <> NEW.id AND p.status IN ('recorded', 'reconciled')), 0)
           - COALESCE((SELECT sum(total) FROM purchase_credit_notes c
                       WHERE c.purchase_invoice_id = i.id AND c.status IN ('validated', 'applied')), 0)
      INTO v_remaining
    FROM purchase_invoices i WHERE i.id = NEW.purchase_invoice_id AND i.tenant_id = NEW.tenant_id;
    v_excess := GREATEST(NEW.amount - GREATEST(COALESCE(v_remaining, NEW.amount), 0), 0);
  END IF;

  SELECT * INTO v_tr FROM treasury_for_payment(NEW.tenant_id, NEW.bank_account_id, NEW.method);

  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, v_tr.journal_code, 'draft', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  IF NEW.amount - v_excess > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_collectif, v_collectif, v_tiers, v_third_party,
            NEW.amount - v_excess, 0, 'Fournisseur ' || NEW.number, 0);
  END IF;
  IF v_excess > 0 THEN
    v_avance := resolve_account(NEW.tenant_id, 'FOURNISSEURS_AVANCES_VERSEES');
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_avance, v_avance, v_tiers, v_third_party,
            v_excess, 0, 'Avance fournisseur (trop-payé) ' || NEW.number, 1);
  END IF;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry_id, v_tr.account_code, v_tr.account_code, NULL, NULL,
          0, NEW.amount, 'Trésorerie ' || NEW.number, 2);

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$function$;
