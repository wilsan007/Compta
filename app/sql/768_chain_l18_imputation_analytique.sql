-- 768 — chain_l18_imputation_analytique
-- Numéro pris le 2026-10-19T19:45:22.222Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 768_chain_l18_imputation_analytique.sql — L18, tranche 2 (fin) :
--       L'IMPUTATION ANALYTIQUE du stock — la section circule jusqu'au livre
-- ═══════════════════════════════════════════════════════════════════════════
--
-- LE LOT. L18 (§5 Phase F) : « sortie de stock sur projet (consommation de
-- chantier, AVEC IMPUTATION ANALYTIQUE) ». La tranche 1 (418) a posé le coût
-- du chantier, la 767 le lien projet → OF ; la 304 avait posé le porteur
-- analytique sur les lignes de facture et d'achat ET LAIT COMME LIMITE :
-- « la paie, le stock, la caisse et la production ne portent pas encore de
-- section ». Cette 768 ferme la moitié STOCK de cette limite.
--
-- DÉFAUT MESURÉ (rouge d'abord, suite 768 avant cette migration) :
--   * T01 : `colonnes=0 clés=0` — ni `stock_movements` ni
--     `manufacturing_orders` ne pouvaient porter une section analytique ;
--   * T02 : « column "analytic_section_id" of relation "stock_movements"
--     does not exist ». Une sortie de chantier ne pouvait donc pas être
--     rattachée à son axe analytique, et les écritures générées par le
--     stock (journal STK, journal OF) étaient muettes côté analytique : la
--     balance analytique ne pouvait égaler la balance générale en dehors
--     des ventes et des achats (limite W7/304).
--
-- CE QUE CE FICHIER POSE :
--   1. DEUX PORTEURS, clés composites ISO-02 (le miroir exact de la 304) :
--      `stock_movements.analytic_section_id` (la sortie de chantier) et
--      `manufacturing_orders.analytic_section_id` (l'OF de chantier — la
--      767 y avait ajouté `project_id`, la section complète la paire).
--   2. LA CIRCULATION, dans les DEUX seules fonctions vivantes qui
--      comptabilisent le stock :
--      `create_journal_on_stock_movement` (388 LOC1-07 — journal et comptes
--      par les RÔLES, jamais 'ST'/'310000' en dur) : la section du
--      mouvement est portée par les lignes de CHARGE (comptes 6xx) de
--      l'écriture qu'il écrit ;
--      `create_stock_on_manufacturing_complete` (187 — l'écriture
--      `JE-OF-…`) : la section de l'OF est portée par ses MOUVEMENTS DE
--      COMPOSANTS (sorties) à leur création, et par la ligne 601000
--      (consommation matières) de l'écriture de production.
--   3. LE VRAI CHEMIN de clôture, corrigé au passage : la clôture d'OF
--      écrit ses mouvements avec `reference = numéro d'OF` et SANS
--      `reference_id` (187, mesuré) — le compagnon 767 ne résolvait que par
--      `reference_id` et ratait donc la clôture réelle au profit des
--      mouvements de test. `chain_l18_imputer_cout` résout désormais par le
--      numéro quand l'identifiant est absent : T06 mesure que le coût
--      matière de l'OF (50) atteint le projet par le VRAI chemin.
--
-- DÉCISIONS :
--   * Seules les lignes de CHARGE (comptes 6xx) reçoivent la section — la
--     règle de la 304 (pas de section sur la TVA) appliquée au stock : le
--     310000 (sortie de stock) et le 355000/713500 (production stockée)
--     sont des comptes de bilan, pas des charges imputables ;
--   * l'entrée de produit fini (mouvement `in` de production) ne reçoit PAS
--     la section : c'est du stock qui naît, pas une dépense de chantier ;
--   * aucune écriture, aucun lien de chaîne nouveau : G2, G8 et le
--     catalogue des événements ne bougent pas.
--
-- LIMITES DITES :
--   * la section est portée telle quelle (l'écran la saisira, partie D) —
--     aucune dérivation automatique projet → section (les projets ne
--     portent pas de section ; la paire projet/section relève de la saisie) ;
--   * la caisse et la paie restent hors analytique (limite 304 toujours
--     ouverte pour ces deux-là) ;
--   * `db:types` doit être régénéré : deux colonnes entrent au schéma.
--
-- ROUGE D'ABORD — suite 768 (T01→T07) : le porteur, les deux
-- cloisonnements (clés nommées), le nettoyage à la suppression, la
-- circulation sur la sortie de chantier (STK, 6xx, débit 20), l'OF de
-- chantier (mouvements + 601000 + actual_cost 50 par le vrai chemin), le
-- cas ordinaire muet.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Les porteurs : une section par mouvement, une par OF ─────────────────
ALTER TABLE public.stock_movements
  ADD COLUMN IF NOT EXISTS analytic_section_id uuid;

ALTER TABLE public.manufacturing_orders
  ADD COLUMN IF NOT EXISTS analytic_section_id uuid;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'stock_movements_analytic_section_fk'
                   AND conrelid = 'public.stock_movements'::regclass) THEN
    ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_analytic_section_fk
      FOREIGN KEY (tenant_id, analytic_section_id)
      REFERENCES public.analytic_sections (tenant_id, id) ON DELETE SET NULL (analytic_section_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'manufacturing_orders_analytic_section_fk'
                   AND conrelid = 'public.manufacturing_orders'::regclass) THEN
    ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_analytic_section_fk
      FOREIGN KEY (tenant_id, analytic_section_id)
      REFERENCES public.analytic_sections (tenant_id, id) ON DELETE SET NULL (analytic_section_id);
  END IF;
END $$;

COMMENT ON COLUMN public.stock_movements.analytic_section_id IS
  'Section analytique du mouvement (consommation de chantier, etc.) : transmise aux lignes de CHARGE (6xx) de l''écriture STK par create_journal_on_stock_movement. 768 (L18 tranche 2), porteur annoncé par la limite 418 §5.2 et la 304.';
COMMENT ON COLUMN public.manufacturing_orders.analytic_section_id IS
  'Section analytique de l''OF (fabrication pour un chantier) : portée par ses mouvements de composants et par la ligne 601000 de l''écriture JE-OF à la clôture. 768 (L18 tranche 2), avec project_id (767).';

-- ── 2. La circulation côté STK : create_journal_on_stock_movement ───────────
-- Réécriture à l'identique de la 388 (rôles LOC1-07 — la dernière version
-- vivante : journal et comptes par les RÔLES, pas 'ST'/'310000' en dur),
-- PLUS le bloc qui transmet la section du mouvement aux lignes de CHARGE
-- (6xx/7xx) de l'écriture qu'il écrit. La règle de la 304 appliquée au
-- stock : la section voyage avec le flux, et seule la charge l'emporte
-- (le 31x est un compte de bilan — et la variation générique 603000 ne
-- peut être distinguée d'un 6xx sans le résolveur, d'où le filtre sur les
-- lignes DÉBITRICES de charge ; voir le T05).
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

  -- 768 (L18 tranche 2) — LA SECTION CIRCULE : le mouvement sait à quoi il
  -- se rattache (chantier, axe) ; la ligne DÉBITRICE de charge (6xx) le porte
  -- au livre. Seul le débit : une entrée (débit 3xx) n'est pas une dépense ;
  -- le 31x (bilan) n'en porte jamais — même règle que la 304, qui excluait
  -- la TVA des lignes analytiques. La variation générique 603000 débitrice
  -- la porte : c'est le seul débit de charge de l'écriture de sortie, et le
  -- T05 le mesure (débit 20).
  IF NEW.analytic_section_id IS NOT NULL THEN
    UPDATE journal_lines
       SET analytic_section_id = NEW.analytic_section_id,
           analytic_amount = COALESCE(NULLIF(debit, 0), credit, 0)
     WHERE tenant_id = NEW.tenant_id
       AND journal_id = v_entry_id
       AND debit > 0
       AND COALESCE(account_code, account_general) ~ '^6';
  END IF;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  RETURN NEW;
END $function$;

-- ── 3. La circulation côté OF : create_stock_on_manufacturing_complete ───────
-- Réécriture à l'identique de la 388 (rôles LOC1-07 — la dernière version
-- vivante : PROD-01 explosion multi-niveaux, PROD-02 refus des écarts
-- impossibles, PROD-03 date de l'OF, anti-double-clôture M-08, quantités
-- bonnes v_good, journal et comptes par les RÔLES), PLUS : la section de
-- l'OF est portée par ses MOUVEMENTS DE COMPOSANTS (seuls représentatifs
-- d'une dépense — l'entrée de produit fini reste du stock) et par la ligne
-- de consommation matières de l'écriture de production.
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

  -- PROD-03 : la date de l'OF, pas celle du jour où on le clôture.
  v_date := COALESCE(NEW.end_date, NEW.start_date, CURRENT_DATE);

  -- PROD-02 : ce qui est impossible est refusé, jamais ramené à zéro.
  IF COALESCE(NEW.qty_scrapped, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'OF % : rebuts (%) supérieurs à la quantité lancée (%)',
      NEW.number, NEW.qty_scrapped, NEW.quantity USING ERRCODE = '23514';
  END IF;
  IF COALESCE(NEW.qty_produced, 0) + COALESCE(NEW.qty_scrapped, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'OF % : bonnes (%) + rebuts (%) supérieurs au lancé (%)',
      NEW.number, NEW.qty_produced, NEW.qty_scrapped, NEW.quantity USING ERRCODE = '23514';
  END IF;

  -- M-08 défaut 2 : une seconde clôture doublait le stock.
  SELECT count(*) INTO v_deja
  FROM public.stock_movements
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'production' AND reference_id = NEW.id;

  IF v_deja > 0 THEN
    RAISE EXCEPTION 'OF % déjà clôturé : ses mouvements existent. Contrepasser avant de reclôturer.', NEW.number
      USING ERRCODE = '23505';
  END IF;

  -- PROD-02 : quantité déclarée, sinon lancé moins rebuts.
  v_good := public.manufacturing_good_quantity(NEW.quantity, NEW.qty_produced, NEW.qty_scrapped);

  -- Calculer le coût de production
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

    -- Entrée du produit fini : les pièces bonnes seulement — SANS section :
    -- du stock qui naît, pas une dépense de chantier (768).
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
    -- 768 : elle porte la section de l'OF.
    FOR v_component IN
      SELECT r.product_id, r.quantity, r.actual_unit_cost
      FROM public.manufacturing_requirements(NEW.id, NEW.tenant_id) r
    LOOP
      INSERT INTO public.stock_movements (
        tenant_id, product_id, warehouse_id, movement_type,
        quantity, unit_cost, reference, movement_date, date, reference_type, reference_id,
        analytic_section_id
      ) VALUES (
        NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
        v_component.quantity, v_component.actual_unit_cost, NEW.number,
        v_date, v_date, 'production', NEW.id,
        NEW.analytic_section_id
      );
    END LOOP;

    -- Écriture comptable de production — journal et comptes par les RÔLES.
    v_number := 'JE-OF-' || NEW.number;
    SELECT id INTO v_existing FROM public.journal_entries
      WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

    IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
      PERFORM ensure_standard_journals(NEW.tenant_id);
      INSERT INTO public.journal_entries (
        tenant_id, number, date, journal_code, status,
        description, reference
      ) VALUES (
        NEW.tenant_id, v_number, v_date,
        resolve_journal(NEW.tenant_id, 'JOURNAL_PRODUCTION'),
        'draft',
        'Production OF ' || NEW.number, v_number
      )
      RETURNING id INTO v_entry_id;

      -- Sortie des matières (débit consommation, crédit stock) — la CHARGE
      -- porte la section de l'OF et son montant analytique (768) ; le stock
      -- est un compte de bilan, il n'en porte pas.
      IF v_cost_material > 0 THEN
        INSERT INTO public.journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order,
          analytic_section_id, analytic_amount
        ) VALUES (
          NEW.tenant_id, v_entry_id,
          resolve_account(NEW.tenant_id, 'ACHATS_MATIERES'),
          resolve_account(NEW.tenant_id, 'ACHATS_MATIERES'),
          v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre,
          NEW.analytic_section_id,
          CASE WHEN NEW.analytic_section_id IS NOT NULL THEN v_cost_material END
        );
        v_ordre := v_ordre + 1;

        INSERT INTO public.journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id,
          resolve_account(NEW.tenant_id, 'STOCK_MATIERES'),
          resolve_account(NEW.tenant_id, 'STOCK_MATIERES'),
          0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie,
      -- factures) ; absorbés dans le produit fini via 355 / 713. Le coût des
      -- rebuts reste absorbé par les pièces bonnes : seul le coût unitaire monte.
      INSERT INTO public.journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id,
        resolve_account(NEW.tenant_id, 'STOCK_PRODUITS_FINIS'),
        resolve_account(NEW.tenant_id, 'STOCK_PRODUITS_FINIS'),
        v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;

      INSERT INTO public.journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id,
        resolve_account(NEW.tenant_id, 'PRODUCTION_STOCKEE'),
        resolve_account(NEW.tenant_id, 'PRODUCTION_STOCKEE'),
        0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre
      );

      -- Bascule en 'posted' APRÈS les lignes (SOC-01)
      UPDATE public.journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    END IF;

    -- PROD-02 : la quantité produite déclarée prime.
    UPDATE public.manufacturing_orders
    SET qty_produced = v_good
    WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$function$;

-- ── 4. Le vrai chemin de la clôture, atteint par le compagnon 768 ───────────
-- MESURÉ (187) : la clôture d'OF écrit ses mouvements avec
-- `reference = numéro d'OF` et SANS `reference_id`. Le compagnon de la 767
-- ne résolvait que par l'identifiant — il ratait donc la clôture RÉELLE au
-- profit des mouvements de test. Il résout désormais par le numéro quand
-- l'identifiant est absent : la suite 768 T06 mesure que le coût matière
-- de l'OF (50) atteint le projet par le vrai chemin.
CREATE OR REPLACE FUNCTION public.chain_l18_imputer_cout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_projet uuid;
BEGIN
  -- LE RETRAIT d'abord, sur `OLD`. Sans ce geste, un UPDATE imputerait
  -- le nouveau coût EN PLUS de l'ancien : la correction d'une quantité
  -- gonflerait la marge au lieu de la corriger (T04 de la 767).
  IF TG_OP IN ('UPDATE', 'DELETE')
     AND OLD.reference_type IS NOT NULL
     AND COALESCE(OLD.movement_type, OLD.type) = 'out'
  THEN
    v_projet := CASE
      WHEN OLD.reference_type = 'project'   THEN OLD.reference_id
      WHEN OLD.reference_type = 'production' THEN (
        SELECT mo.project_id FROM manufacturing_orders mo
         WHERE mo.tenant_id = OLD.tenant_id
           AND (mo.id = OLD.reference_id
             OR (OLD.reference_id IS NULL AND mo.number = OLD.reference)))
      ELSE NULL END;
    IF v_projet IS NOT NULL AND (OLD.reference_id IS NOT NULL OR OLD.reference IS NOT NULL) THEN
      PERFORM project_stock_cost(OLD.id, v_projet,
                                -(COALESCE(OLD.quantity, 0) * COALESCE(OLD.unit_cost, 0)));
    END IF;
  END IF;

  -- L'IMPUTATION ensuite, sur `NEW`. Une entrée qui référence un projet
  -- (directement ou par son OF) n'est pas une consommation : rien n'est
  -- imputé (T03 de la 767).
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND NEW.reference_type IS NOT NULL
     AND COALESCE(NEW.movement_type, NEW.type) = 'out'
  THEN
    v_projet := CASE
      WHEN NEW.reference_type = 'project'   THEN NEW.reference_id
      WHEN NEW.reference_type = 'production' THEN (
        SELECT mo.project_id FROM manufacturing_orders mo
         WHERE mo.tenant_id = NEW.tenant_id
           AND (mo.id = NEW.reference_id
             OR (NEW.reference_id IS NULL AND mo.number = NEW.reference)))
      ELSE NULL END;
    IF v_projet IS NOT NULL AND (NEW.reference_id IS NOT NULL OR NEW.reference IS NOT NULL) THEN
      PERFORM project_stock_cost(NEW.id, v_projet,
                                (COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_cost, 0)));
    END IF;
  END IF;

  RETURN NULL;   -- AFTER : la valeur de retour est sans effet
END $fn$;

COMMENT ON FUNCTION public.chain_l18_imputer_cout() IS
  'L18 (418 tranche 1, 767 tranche 2, 768) — le compagnon du couple stock ↔ projets : impute, ou retire, le coût matière d''une sortie de stock au projet désigné SOIT directement (reference_type = ''project''), SOIT PAR L''OF qu''elle consomme (reference_type = ''production'' → manufacturing_orders : par id, ou par NUMÉRO quand la clôture n''écrit pas reference_id — le vrai chemin, mesuré). Couvre les TROIS temps du mouvement. Seules les SORTIES imputent. Le cas ordinaire ne fait rien.';

REVOKE ALL ON FUNCTION public.chain_l18_imputer_cout() FROM PUBLIC, anon, authenticated;

