-- ═══════════════════════════════════════════════════════════════════════════
-- 388 — roles_stock_production : STOCK et PRODUCTION sur les rôles (LOC1-07)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Suite de LOC1-07 : le STOCK et la PRODUCTION. Les écritures de
-- stock ne portent plus `'310000'` ni le journal `'ST'`, celles de production
-- plus `'601000'`/`'310000'`/`'355000'`/`'713500'` ni le journal `'OF'` : elles
-- demandent leurs RÔLES (`STOCK_MATIERES`, `ACHATS_MATIERES`,
-- `STOCK_PRODUITS_FINIS`, `PRODUCTION_STOCKEE`, `JOURNAL_STOCK`,
-- `JOURNAL_PRODUCTION`).
--
-- ÉCRITURES IDENTIQUES. Le pack PCG porte déjà ces rôles vers EXACTEMENT les
-- comptes d'aujourd'hui (`ACHATS_MATIERES→601000`, `STOCK_MATIERES→310000`,
-- `STOCK_PRODUITS_FINIS→355000`, `PRODUCTION_STOCKEE→713500`,
-- `JOURNAL_STOCK→ST`, `JOURNAL_PRODUCTION→OF`). La recette est donc la même que
-- pour LOC1-06 : les écritures ne changent pas.
--
-- ⚠ CE QUI N'EST PAS FAIT — ET POURQUOI (décision du 06/10).
-- 1. **`resolve_variation_account` GARDE `'603000'`.** Aucun rôle du catalogue
--    (annexe B) ne nomme la variation GÉNÉRIQUE ; le remplacer changerait les
--    écritures françaises. On ne le fait pas sans arbitrage. (Le repli n'est
--    atteint que si la catégorie n'a AUCUN `variation_account_code`.)
-- 2. **Pas de compte de stock « par type d'article ».** `products.type` ne prend
--    que `'service'` ou `'stock'` : il n'existe PAS de taxonomie
--    marchandise/matière/produit fini. La nature est déjà portée par le compte
--    EXPLICITE (`products.stock_account_code`, puis sa catégorie) — c'est la
--    « table de paramétrage » ; le repli ci-dessous est le dernier recours.
-- 3. **`613000` n'est pas touché.** Le code de production n'utilise plus
--    `613000` ; et une LOCATION n'est pas une SOUS-TRAITANCE — on ne les
--    confond pas pour faire correspondre un document.
--
-- REJOUABLE : `CREATE OR REPLACE`.
--
-- Numéro pris le 2026-10-06T05:56:02.298Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Le compte de stock d'un article : article → catégorie → RÔLE (repli)
--    ⚠ SECURITY DEFINER conservé : la fonction est AU REGISTRE de
--    `ci/check_tenant_guard.sql` ; en changer la sécurité périmerait la ligne.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_stock_account(p_product_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    NULLIF(btrim(p.stock_account_code), ''),
    NULLIF(btrim(pc.stock_account_code), ''),
    resolve_account(p.tenant_id, 'STOCK_MATIERES', jsonb_build_object('product_id', p_product_id))
  )
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = p.tenant_id
  WHERE p.id = p_product_id;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Mouvement de stock → journal ST, sur les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_journal_on_stock_movement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_amount numeric;
  v_unit_cost numeric;
  v_product RECORD;
  v_stock_account text;
  v_variation_account text;
  v_existing uuid;
  v_journal text;
BEGIN
  -- Ne pas générer pour les transferts internes ni les entrées initiales
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment') THEN
    RETURN NEW;
  END IF;

  -- La production écrit sa propre écriture (journal OF) dans
  -- `create_stock_on_manufacturing_complete` : la comptabiliser ici aussi
  -- enregistrerait les mêmes faits deux fois.
  IF NEW.reference_type = 'production' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  v_unit_cost := NULLIF(COALESCE(NEW.unit_cost, 0), 0);

  IF v_unit_cost IS NULL AND NEW.movement_type = 'out' THEN
    IF NEW.warehouse_id IS NOT NULL THEN
      SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_unit_cost
      FROM stock_quantities sq
      WHERE sq.product_id = NEW.product_id
        AND sq.warehouse_id = NEW.warehouse_id
        AND sq.tenant_id = NEW.tenant_id;
    ELSE
      SELECT NULLIF(SUM(sq.quantity * COALESCE(sq.unit_cost, 0)) / NULLIF(SUM(sq.quantity), 0), 0)
      INTO v_unit_cost
      FROM stock_quantities sq
      WHERE sq.product_id = NEW.product_id
        AND sq.tenant_id = NEW.tenant_id;
    END IF;

    IF v_unit_cost IS NULL THEN
      v_unit_cost := NULLIF(COALESCE(v_product.cost_price, 0), 0);
    END IF;
  END IF;

  IF v_unit_cost IS NULL THEN
    RETURN NEW;
  END IF;

  v_amount := NEW.quantity * v_unit_cost;
  IF v_amount = 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_existing
  FROM journal_entries
  WHERE tenant_id = NEW.tenant_id
    AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;

  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  -- Le journal des stocks fait partie des journaux standard : sans lui, la clé
  -- étrangère (tenant_id, journal_code) ferait échouer le mouvement lui-même.
  -- On les garantit AVANT de résoudre le rôle (resolve_journal lève si absent).
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_STOCK');

  -- D1 (stk-012) : une SORTIE prend les comptes de l'entrée qui a nourri la
  -- couche qu'elle consomme. Les couches ne sont pas encore consommées ici :
  -- `create_journal_stock_movement` passe avant `trg_consume_valuation_layers`
  -- (ordre alphabétique des déclencheurs).
  IF NEW.movement_type = 'out' THEN
    SELECT
      (SELECT jl.account_code FROM journal_lines jl
       WHERE jl.journal_id = je.id AND jl.debit > 0 AND jl.account_code LIKE '3%'
       ORDER BY jl.line_order LIMIT 1),
      (SELECT jl.account_code FROM journal_lines jl
       WHERE jl.journal_id = je.id AND jl.credit > 0 AND jl.account_code NOT LIKE '3%'
       ORDER BY jl.line_order LIMIT 1)
    INTO v_stock_account, v_variation_account
    FROM stock_valuation_layers l
    JOIN stock_movements m ON m.id = l.movement_id AND m.tenant_id = l.tenant_id
    LEFT JOIN journal_entries je ON je.tenant_id = m.tenant_id
      AND (je.piece_number = 'STK-' || m.id::text
           OR (m.reference_type = 'production' AND je.reference = 'JE-OF-' || m.reference))
    WHERE l.tenant_id = NEW.tenant_id
      AND l.product_id = NEW.product_id
      AND l.remaining_qty > 0
      AND COALESCE(l.warehouse_id, NEW.warehouse_id) = NEW.warehouse_id
    ORDER BY l.created_at NULLS LAST, l.seq
    LIMIT 1;
  END IF;

  -- S-10 : article, puis famille d'articles, puis le PACK (rôle) — c'est le
  -- repli, et le seul chemin pour une entrée ou une couche d'avant la 241.
  v_stock_account := COALESCE(v_stock_account, resolve_stock_account(NEW.product_id));
  v_variation_account := COALESCE(v_variation_account, resolve_variation_account(NEW.product_id));

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    v_journal, 'draft',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  IF NEW.movement_type IN ('in', 'adjustment') THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Entrée en stock - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'out' THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       v_amount, 0, 'Variation de stock (sortie) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       0, v_amount, 'Sortie de stock - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  RETURN NEW;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Clôture d'un ordre de fabrication → journal OF, sur les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_stock_on_manufacturing_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_cost jsonb;
  v_unit_cost numeric;
  v_cost_material numeric;
  v_cost_labor numeric;
  v_cost_overhead numeric;
  v_cost_total numeric;
  v_ordre int := 0;
  v_component RECORD;
  v_good numeric;
  v_deja int;
  v_date date;
  -- LOC1-07 : journal et comptes viennent des RÔLES
  v_journal text;
  v_achats_matieres text;
  v_stock_matieres text;
  v_produits_finis text;
  v_production_stockee text;
BEGIN
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'completed') THEN
    RETURN NEW;
  END IF;

  -- PROD-03 : la date de l'OF, pas celle du jour où on le clôture. Un ordre
  -- terminé le 15/03 mais clôturé le 28/09 appartient à l'exercice du 15/03.
  v_date := COALESCE(NEW.end_date, NEW.start_date, CURRENT_DATE);

  -- PROD-02 : ce qui est déclaré impossible est refusé, jamais ramené à zéro.
  IF COALESCE(NEW.qty_scrapped, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'OF % : rebuts (%) supérieurs à la quantité lancée (%)',
      NEW.number, NEW.qty_scrapped, NEW.quantity USING ERRCODE = '23514';
  END IF;
  IF COALESCE(NEW.qty_produced, 0) + COALESCE(NEW.qty_scrapped, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'OF % : pièces bonnes (%) + rebuts (%) supérieurs à la quantité lancée (%)',
      NEW.number, NEW.qty_produced, NEW.qty_scrapped, NEW.quantity USING ERRCODE = '23514';
  END IF;

  -- M-08 défaut 2 : une seconde clôture doublait le stock sans doubler l'écriture.
  SELECT count(*) INTO v_deja
  FROM public.stock_movements
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'production' AND reference_id = NEW.id;

  IF v_deja > 0 THEN
    RAISE EXCEPTION 'OF % déjà clôturé : ses mouvements de stock existent. Contrepasser avant de reclôturer.', NEW.number
      USING ERRCODE = '23505';
  END IF;

  -- PROD-02 : la quantité produite déclarée prime (l'écart n'est plus effacé),
  -- sinon le lancé moins les rebuts — la règle du coût, une seule.
  v_good := public.manufacturing_good_quantity(NEW.quantity, NEW.qty_produced, NEW.qty_scrapped);

  v_cost := public.calculate_manufacturing_cost(NEW.id, NEW.tenant_id);
  IF (v_cost->>'success')::boolean THEN
    v_cost_material := (v_cost->>'cost_material')::numeric;
    v_cost_labor := (v_cost->>'cost_labor')::numeric;
    v_cost_overhead := (v_cost->>'cost_overhead')::numeric;
    v_cost_total := (v_cost->>'cost_total')::numeric;
    v_unit_cost := (v_cost->>'unit_cost')::numeric;
  ELSE
    v_unit_cost := 0;
    v_cost_total := 0;
  END IF;


  -- Entrée du produit fini : les pièces bonnes seulement
  IF v_good > 0 THEN
    INSERT INTO public.stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, date, reference_type, reference_id
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 'in',
      v_good, v_unit_cost, NEW.number, v_date, v_date, 'production', NEW.id
    );
  END IF;

  -- Sortie des composants : l'explosion multi-niveaux (PROD-01), pour la
  -- quantité LANCÉE, rebuts compris — une seule source avec le coût.
  FOR v_component IN
    SELECT r.product_id, r.quantity, r.actual_unit_cost
    FROM public.manufacturing_requirements(NEW.id, NEW.tenant_id) r
  LOOP
    INSERT INTO public.stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, date, reference_type, reference_id
    ) VALUES (
      NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
      v_component.quantity, v_component.actual_unit_cost, NEW.number,
      v_date, v_date, 'production', NEW.id
    );
  END LOOP;

  -- Écriture comptable de production — journal et comptes viennent des RÔLES.
  v_number := 'JE-OF-' || NEW.number;
  SELECT id INTO v_existing FROM public.journal_entries
    WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

  IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
    PERFORM ensure_standard_journals(NEW.tenant_id);
    v_journal            := resolve_journal(NEW.tenant_id, 'JOURNAL_PRODUCTION');
    v_achats_matieres    := resolve_account(NEW.tenant_id, 'ACHATS_MATIERES');
    v_stock_matieres     := resolve_account(NEW.tenant_id, 'STOCK_MATIERES');
    v_produits_finis     := resolve_account(NEW.tenant_id, 'STOCK_PRODUITS_FINIS');
    v_production_stockee := resolve_account(NEW.tenant_id, 'PRODUCTION_STOCKEE');

    INSERT INTO public.journal_entries (
      tenant_id, number, date, journal_code, status, description, reference
    ) VALUES (
      NEW.tenant_id, v_number, v_date, v_journal, 'draft',
      'Production OF ' || NEW.number, v_number
    )
    RETURNING id INTO v_entry_id;

    IF v_cost_material > 0 THEN
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, v_achats_matieres, v_achats_matieres, v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;

      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, v_stock_matieres, v_stock_matieres, 0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END IF;

    -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie, factures) ;
    -- ils sont absorbés dans la valeur du produit fini via 355 / 713, sans nouvelle
    -- charge. Le coût des rebuts reste absorbé par les pièces bonnes : l'écriture ne
    -- change pas, seul le coût unitaire monte.
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_produits_finis, v_produits_finis, v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre);
    v_ordre := v_ordre + 1;

    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_production_stockee, v_production_stockee, 0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre);

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE public.journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  END IF;

  UPDATE public.manufacturing_orders
  SET qty_produced = v_good
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$function$;
