-- ============================================================
-- 302_manufacturing_multilevel_and_variances.sql — W8 (M-08) :
-- nomenclature multi-niveaux, écarts chiffrés, date de l'OF
--
-- Trois défauts prouvés par `302_manufacturing_multilevel_and_variances_tests.sql`,
-- tous vus **rouges avant** ce fichier :
--
--   PROD-01 🟠 La nomenclature était lue **à un seul niveau**
--             (`WHERE bl.bom_id = NEW.bom_id`). Mesuré : un OF de 10 pièces dont
--             le composant est lui-même fabriqué échoue sur « Stock insuffisant:
--             disponible=0, demandé=10 » — l'atelier consommait le sous-ensemble,
--             jamais fabriqué ni stocké.
--   PROD-02 🟠 `qty_produced` était **écrasée** (100 lancées − 8 rebutées = 92)
--             alors que l'atelier en déclarait 88 : l'écart de production était
--             effacé. Un rebut supérieur au lancé était ramené à zéro en silence
--             (`GREATEST`), et aucun écart de coût n'était écrit
--             (`cost_variance` n'existait pas).
--   PROD-03 🟡 Mouvements et écriture datés de `CURRENT_DATE` : un OF daté du
--             15/03 clôturé le 28/09 sortait au 28/09.
--
-- UN SEUL MOTEUR. L'explosion de la nomenclature vit dans **une** fonction
-- (`manufacturing_requirements`), et c'est elle qui sert désormais à trois
-- choses : le coût matière de `calculate_manufacturing_cost`, les sorties de
-- stock de la clôture, et l'écart de coût. Auparavant le coût et les sorties
-- lisaient `bom_lines` chacun de leur côté — à un niveau, et par deux requêtes
-- différentes. La règle « combien de pièces bonnes » vit de même dans
-- `manufacturing_good_quantity`, appelée par les deux.
--
-- LES LIMITES, DITES.
--   • Un composant qui porte une nomenclature **active** est explosé (ses propres
--     composants sont consommés à sa place) : nomenclature « fantôme », la
--     convention la plus lisible. Aucun sous-OF n'est créé
--     (`manufacturing_orders.parent_mo_id` reste inutilisé).
--   • L'explosion s'arrête au composant déjà rencontré (un cycle de nomenclature
--     ne récurse pas sans fin) et à 8 niveaux.
--   • Le prix standard d'un composant est celui de la ligne de nomenclature
--     (`bom_lines.unit_cost`), pondéré par les quantités ; s'il est absent, le
--     prix réel est repris — l'écart de coût ne fabrique pas de fausse variance
--     sur une nomenclature non valorisée.
--   • Les comptes `601000` / `310000` / `355000` / `713500` restent codés en dur
--     (défaut S-10 de la vague W3, hors de ce lot).
-- ============================================================

ALTER TABLE public.manufacturing_orders
  ADD COLUMN IF NOT EXISTS cost_variance numeric DEFAULT 0;

COMMENT ON COLUMN public.manufacturing_orders.cost_variance IS
  'Écart de coût matière : coût standard (bom_lines.unit_cost) − coût réel (couches de stock). Négatif = le standard est dépassé. 302 (W8).';

-- ------------------------------------------------------------
-- 1. Une seule règle : combien de pièces bonnes
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.manufacturing_good_quantity(
  p_quantity numeric, p_declared numeric, p_scrapped numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  -- La quantité produite **déclarée** prime (c'est l'atelier qui sait) ; sinon
  -- elle se déduit du lancé moins les rebuts. Jamais négative.
  SELECT CASE WHEN COALESCE(p_declared, 0) > 0 THEN COALESCE(p_declared, 0)
              ELSE GREATEST(COALESCE(p_quantity, 0) - COALESCE(p_scrapped, 0), 0) END
$$;

REVOKE EXECUTE ON FUNCTION public.manufacturing_good_quantity(numeric, numeric, numeric) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 2. Une seule explosion : les besoins réels d'un OF
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.manufacturing_requirements(p_mo_id uuid, p_tenant_id uuid)
RETURNS TABLE (
  product_id uuid,
  quantity numeric,
  actual_unit_cost numeric,
  standard_unit_cost numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH RECURSIVE mo AS (
    SELECT m.id, m.tenant_id, m.bom_id, m.warehouse_id, m.quantity AS launched,
           m.product_id AS produit
    FROM public.manufacturing_orders m
    WHERE m.id = p_mo_id AND m.tenant_id = p_tenant_id
  ),
  explos AS (
    -- niveau 1 : les composants directs
    SELECT bl.product_id, bl.quantity AS qte, 1 AS niveau,
           ARRAY[bl.product_id] AS chemin,
           COALESCE(NULLIF(bl.unit_cost, 0), 0) AS std,
           (SELECT produit FROM mo) AS parent_produit
    FROM mo
    JOIN public.bom_lines bl ON bl.bom_id = mo.bom_id AND bl.tenant_id = mo.tenant_id
    UNION ALL
    -- niveaux suivants : un composant qui porte une nomenclature active est
    -- remplacé par ses propres composants, quantités mises à l'échelle par la
    -- quantité produite de SA nomenclature (boms.quantity).
    SELECT enfant.product_id,
           e.qte * enfant.quantity / COALESCE(NULLIF(b.quantity, 0), 1),
           e.niveau + 1,
           e.chemin || enfant.product_id,
           COALESCE(NULLIF(enfant.unit_cost, 0), e.std),
           e.product_id
    FROM explos e
    JOIN public.boms b ON b.product_id = e.product_id AND b.tenant_id = p_tenant_id
                      AND COALESCE(b.active, true)
    JOIN public.bom_lines enfant ON enfant.bom_id = b.id AND enfant.tenant_id = p_tenant_id
    WHERE e.niveau < 8
      AND enfant.product_id <> ALL(e.chemin)                 -- un cycle s'arrête ici
      AND NOT EXISTS (SELECT 1 FROM mo WHERE enfant.product_id = mo.produit)
  ),
  -- Une feuille est un composant qui n'a **pas** été explosé dans cet arbre : un
  -- produit dont la nomenclature boucle (jamais descendue) reste donc consommé.
  feuilles AS (
    SELECT e.* FROM explos e
    WHERE NOT EXISTS (SELECT 1 FROM explos x WHERE x.parent_produit = e.product_id)
  ),
  agg AS (
    SELECT f.product_id,
           round(sum(f.qte) * mo.launched, 4) AS quantite,
           COALESCE(max(COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0),
                                NULLIF(f.std, 0), 0)), 0) AS reel,
           CASE WHEN COALESCE(sum(f.qte), 0) > 0
                THEN round(sum(f.qte * COALESCE(NULLIF(f.std, 0), 0)) / sum(f.qte), 4)
                ELSE 0 END AS std_moyen
    FROM feuilles f
    CROSS JOIN mo
    LEFT JOIN public.products p ON p.id = f.product_id AND p.tenant_id = mo.tenant_id
    LEFT JOIN public.stock_quantities sq ON sq.product_id = f.product_id
         AND sq.warehouse_id = mo.warehouse_id AND sq.tenant_id = mo.tenant_id
    GROUP BY f.product_id, mo.launched
  )
  SELECT agg.product_id, agg.quantite, agg.reel,
         CASE WHEN agg.std_moyen > 0 THEN agg.std_moyen ELSE agg.reel END
  FROM agg
  ORDER BY agg.product_id
$$;

REVOKE EXECUTE ON FUNCTION public.manufacturing_requirements(uuid, uuid) FROM PUBLIC, anon, authenticated;


-- ------------------------------------------------------------
-- 3. Le coût de revient lit la même explosion, et chiffre l'écart
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_manufacturing_cost(p_mo_id uuid, p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cost_material numeric := 0;
  v_cost_standard numeric := 0;
  v_cost_variance numeric := 0;
  v_cost_labor numeric := 0;
  v_cost_overhead numeric := 0;
  v_unit_cost numeric;
  v_quantity numeric;
  v_declared numeric;
  v_scrapped numeric;
  v_good numeric;
  v_routing_id uuid;
  v_overhead_rate numeric := 0;
BEGIN
  SELECT mo.quantity, mo.qty_produced, COALESCE(mo.qty_scrapped, 0), mo.routing_id
  INTO v_quantity, v_declared, v_scrapped, v_routing_id
  FROM public.manufacturing_orders mo
  WHERE mo.id = p_mo_id AND mo.tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OF introuvable');
  END IF;

  -- Matières : la nomenclature est explosée sur tous ses niveaux, et consommée
  -- pour la quantité LANCÉE (un rebut a coûté sa matière). Le standard vient de
  -- la même fonction que le réel : l'écart est leur différence, rien d'autre.
  SELECT COALESCE(sum(quantity * actual_unit_cost), 0),
         COALESCE(sum(quantity * standard_unit_cost), 0)
  INTO v_cost_material, v_cost_standard
  FROM public.manufacturing_requirements(p_mo_id, p_tenant_id);

  v_cost_variance := round(v_cost_standard - v_cost_material, 2);

  -- Temps en minutes → heures
  SELECT COALESCE(sum((COALESCE(ro.setup_time_min, 0) + COALESCE(ro.run_time_min, 0) * v_quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_cost_labor
  FROM public.routing_operations ro
  JOIN public.work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = p_tenant_id
  WHERE ro.routing_id = v_routing_id AND ro.tenant_id = p_tenant_id;

  SELECT COALESCE(overhead_rate, 0) INTO v_overhead_rate
  FROM public.company_settings WHERE tenant_id = p_tenant_id LIMIT 1;

  v_cost_overhead := v_cost_labor * v_overhead_rate;

  -- M-08 : le coût total est absorbé par les seules pièces bonnes — celles que
  -- l'atelier déclare, sinon le lancé moins les rebuts. C'est la règle de la
  -- clôture, appelée ici : une seule définition.
  v_good := public.manufacturing_good_quantity(v_quantity, v_declared, v_scrapped);
  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead) / NULLIF(v_good, 0);

  UPDATE public.manufacturing_orders
  SET cost_material = v_cost_material,
      cost_labor = v_cost_labor,
      cost_overhead = v_cost_overhead,
      cost_total = v_cost_material + v_cost_labor + v_cost_overhead,
      unit_cost = COALESCE(v_unit_cost, 0),
      cost_variance = v_cost_variance
  WHERE id = p_mo_id AND tenant_id = p_tenant_id;

  RETURN jsonb_build_object(
    'success', true,
    'cost_material', v_cost_material,
    'cost_standard', v_cost_standard,
    'cost_variance', v_cost_variance,
    'cost_labor', v_cost_labor,
    'cost_overhead', v_cost_overhead,
    'cost_total', v_cost_material + v_cost_labor + v_cost_overhead,
    'qty_good', v_good,
    'qty_variance', GREATEST(v_quantity - v_good - v_scrapped, 0),
    'unit_cost', COALESCE(v_unit_cost, 0)
  );
END;
$$;


-- ------------------------------------------------------------
-- 4. La clôture : la nomenclature explosée, la date de l'OF, les écarts refusés
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_stock_on_manufacturing_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

  -- Écriture comptable de production
  v_number := 'JE-OF-' || NEW.number;
  SELECT id INTO v_existing FROM public.journal_entries
    WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

  IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
    INSERT INTO public.journal_entries (
      tenant_id, number, date, journal_code, status, description, reference
    ) VALUES (
      NEW.tenant_id, v_number, v_date, 'OF', 'draft',
      'Production OF ' || NEW.number, v_number
    )
    RETURNING id INTO v_entry_id;

    IF v_cost_material > 0 THEN
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, '601000', '601000', v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;

      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, '310000', '310000', 0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END IF;

    -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie, factures) ;
    -- ils sont absorbés dans la valeur du produit fini via 355 / 713, sans nouvelle
    -- charge. Le coût des rebuts reste absorbé par les pièces bonnes : l'écriture ne
    -- change pas, seul le coût unitaire monte.
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '355000', '355000', v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre);
    v_ordre := v_ordre + 1;

    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '713500', '713500', 0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre);

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE public.journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  END IF;

  UPDATE public.manufacturing_orders
  SET qty_produced = v_good
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;

