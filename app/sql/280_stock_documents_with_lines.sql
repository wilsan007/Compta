-- ============================================================
-- 280_stock_documents_with_lines.sql — vague X4 (partie 3 du plan correctif
-- de l'audit fonctionnel exécuté du 28/09/2026), décision D-B
--
-- MESURÉ AVANT, par le chemin de l'écran (base neuve, 254 migrations,
-- `src/__screen__/02_purch_stock.screen.ts`) :
--   C8  la fiche article envoie `type` sans `movement_type` : le mouvement est
--       ENREGISTRÉ (la contrainte `type = movement_type` vaut NULL, donc passe)
--       mais aucun déclencheur ne le lit — entrée de 10 : stock 50 → 50 ;
--       sortie de 5 000 sur 57 : ACCEPTÉE sans effet (ST03, ST05, ST06) ;
--   M6  l'article créé avec « quantité initiale 50 » porte 50 en stock sans
--       aucun mouvement ni couche valorisée : un stock sans origine (ST02) ;
--   C9  la commande fournisseur n'a qu'un montant saisi, 0 ligne ; la
--       réception n'a aucune ligne, « Reçue » ne fait rien entrer (P06, ST08) ;
--   C10 la commande client : 0 ligne, TVA 0 sur 1 000 saisis (ST09).
--
-- CE QUI EST POSÉ.
--   1. `stock_movements` : `movement_type` et `type` ne font plus qu'un
--      (déclencheur AVANT tous les autres), un mouvement sans type est refusé,
--      et un mouvement enregistré ne se réécrit plus par un écran (il se
--      contrepasse) — sinon un nouveau fantôme naît d'une modification.
--   2. D-B : les mouvements fantômes déjà en base ne sont PAS rejoués. Ils sont
--      inscrits à `stock_movement_phantoms` (« à valider ») ; l'utilisateur
--      décide, mouvement par mouvement, de les rejouer (un mouvement neuf, daté
--      du jour de la décision) ou de les ignorer (`resolve_stock_movement_phantom`).
--   3. M6 : `products.stock_quantity` n'est écrit que par le moteur de stock ;
--      un écran (rôles `authenticated`/`anon`) ne le pose ni à la création ni
--      à la modification. Le stock initial est un mouvement `initial`.
--   4. C9/C10 : les lignes de commande (achat et vente) sont calculées par la
--      base (`line_amounts`, comme les factures) et les totaux d'en-tête sont
--      l'agrégat des lignes ; une commande reçue/livrée/annulée ne change plus
--      ses lignes. Création atomique en-tête + lignes :
--      `create_purchase_order`, `create_sales_order` (au moins une ligne).
--   5. C9 : la réception naît DE la commande (`create_goods_receipt_from_order`) :
--      une ligne par ligne de commande, au reste à recevoir, rattachée à sa
--      ligne (`goods_receipt_lines.purchase_order_line_id`). « Reçue » passe
--      ensuite par la chaîne déjà prouvée (241/251).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Un mouvement, un type
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stock_movement_type_sync()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.movement_type IS NOT NULL AND NEW.type IS NOT NULL
     AND NEW.movement_type IS DISTINCT FROM NEW.type THEN
    RAISE EXCEPTION 'Mouvement de stock contradictoire : type « % », movement_type « % »', NEW.type, NEW.movement_type
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.movement_type := COALESCE(NEW.movement_type, NEW.type);
  IF NEW.movement_type IS NULL THEN
    RAISE EXCEPTION 'Mouvement de stock sans type (entrée, sortie, ajustement, initial, transfert)'
      USING ERRCODE = 'not_null_violation';
  END IF;
  NEW.type := NEW.movement_type;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.stock_movement_type_sync() FROM PUBLIC, anon, authenticated;

-- « a_ » : les déclencheurs BEFORE s'exécutent par ordre alphabétique ; celui-ci
-- doit précéder `check_tracking_on_sm` et `tg_stock_adjustment_to_delta`.
DROP TRIGGER IF EXISTS a_stock_movement_type_sync ON public.stock_movements;
CREATE TRIGGER a_stock_movement_type_sync
  BEFORE INSERT ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.stock_movement_type_sync();

-- Un mouvement enregistré a produit (ou non) son effet : le réécrire par un écran
-- ne rejoue rien. Il se contrepasse par un mouvement inverse.
CREATE OR REPLACE FUNCTION public.stock_movement_effect_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF (NEW.product_id, NEW.warehouse_id, NEW.movement_type, NEW.type, NEW.quantity, NEW.unit_cost)
     IS DISTINCT FROM
     (OLD.product_id, OLD.warehouse_id, OLD.movement_type, OLD.type, OLD.quantity, OLD.unit_cost) THEN
    RAISE EXCEPTION 'Un mouvement de stock enregistré ne se modifie pas : saisissez le mouvement inverse'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.stock_movement_effect_guard() FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 2. D-B : les fantômes existants sont listés, pas rejoués
-- ------------------------------------------------------------
-- La clé (tenant_id, id) des mouvements porte la clé composite du registre.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'stock_movements_tenant_id_id_key') THEN
    ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_tenant_id_id_key UNIQUE (tenant_id, id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.stock_movement_phantoms (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id     uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  movement_id   uuid NOT NULL,
  product_id    uuid,
  warehouse_id  uuid,
  type          text NOT NULL,
  quantity      numeric NOT NULL,
  unit_cost     numeric,
  movement_date date,
  reference     text,
  detected_at   timestamptz NOT NULL DEFAULT now(),
  decision      text NOT NULL DEFAULT 'pending' CHECK (decision IN ('pending', 'replayed', 'ignored')),
  decided_by    uuid,
  decided_at    timestamptz,
  replay_movement_id uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, movement_id)
);
ALTER TABLE public.stock_movement_phantoms
  DROP CONSTRAINT IF EXISTS stock_movement_phantoms_movement_fkey,
  ADD CONSTRAINT stock_movement_phantoms_movement_fkey
    FOREIGN KEY (tenant_id, movement_id) REFERENCES public.stock_movements(tenant_id, id) ON DELETE CASCADE;
-- L'écran lit l'article du fantôme (embed PostgREST) : clés composites vers
-- l'article et le dépôt, comme toutes les clés de société (237).
ALTER TABLE public.stock_movement_phantoms
  DROP CONSTRAINT IF EXISTS stock_movement_phantoms_product_fkey,
  ADD CONSTRAINT stock_movement_phantoms_product_fkey
    FOREIGN KEY (tenant_id, product_id) REFERENCES public.products(tenant_id, id) ON DELETE SET NULL (product_id),
  DROP CONSTRAINT IF EXISTS stock_movement_phantoms_warehouse_fkey,
  ADD CONSTRAINT stock_movement_phantoms_warehouse_fkey
    FOREIGN KEY (tenant_id, warehouse_id) REFERENCES public.warehouses(tenant_id, id) ON DELETE SET NULL (warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_movement_phantoms_pending
  ON public.stock_movement_phantoms (tenant_id) WHERE decision = 'pending';

ALTER TABLE public.stock_movement_phantoms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movement_phantoms FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_stock_movement_phantoms ON public.stock_movement_phantoms;
CREATE POLICY tenant_select_stock_movement_phantoms ON public.stock_movement_phantoms
  FOR SELECT TO authenticated USING (tenant_id = current_tenant_id());
-- Aucune écriture directe : la décision passe par resolve_stock_movement_phantom.
REVOKE ALL ON public.stock_movement_phantoms FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.stock_movement_phantoms FROM authenticated;
GRANT SELECT ON public.stock_movement_phantoms TO authenticated;
GRANT ALL ON public.stock_movement_phantoms TO service_role;


-- Inventaire des fantômes : `type` posé, `movement_type` absent — aucun
-- déclencheur ne les a lus, le stock ne les connaît pas.
INSERT INTO public.stock_movement_phantoms
  (tenant_id, movement_id, product_id, warehouse_id, type, quantity, unit_cost, movement_date, reference)
SELECT sm.tenant_id, sm.id, sm.product_id, sm.warehouse_id, sm.type, sm.quantity, sm.unit_cost,
       COALESCE(sm.movement_date, sm.date), sm.reference
FROM public.stock_movements sm
WHERE sm.movement_type IS NULL AND sm.type IS NOT NULL
ON CONFLICT (tenant_id, movement_id) DO NOTHING;

-- Le type est aligné SANS rien rejouer (un UPDATE ne déclenche aucun moteur),
-- et le mouvement dit ce qu'il est.
UPDATE public.stock_movements sm
SET movement_type = sm.type,
    notes = concat_ws(' — ', NULLIF(sm.notes, ''),
                      'Mouvement sans effet sur le stock (280, D-B) : à rejouer ou ignorer')
WHERE sm.movement_type IS NULL AND sm.type IS NOT NULL;

-- L'inverse (movement_type seul) a produit son effet : on complète `type`.
UPDATE public.stock_movements SET type = movement_type
WHERE type IS NULL AND movement_type IS NOT NULL;

-- Ni l'un ni l'autre : un mouvement dont on ignore le sens. Il est inscrit comme
-- les autres fantômes (sens « adjustment » : aucun sens n'est présumé) et marqué.
INSERT INTO public.stock_movement_phantoms
  (tenant_id, movement_id, product_id, warehouse_id, type, quantity, unit_cost, movement_date, reference)
SELECT sm.tenant_id, sm.id, sm.product_id, sm.warehouse_id, 'adjustment', sm.quantity, sm.unit_cost,
       COALESCE(sm.movement_date, sm.date), sm.reference
FROM public.stock_movements sm
WHERE sm.movement_type IS NULL AND sm.type IS NULL
ON CONFLICT (tenant_id, movement_id) DO NOTHING;
UPDATE public.stock_movements sm
SET movement_type = 'adjustment', type = 'adjustment',
    notes = concat_ws(' — ', NULLIF(sm.notes, ''),
                      'Mouvement sans type ni effet sur le stock (280, D-B) : à rejouer ou ignorer')
WHERE sm.movement_type IS NULL AND sm.type IS NULL;

ALTER TABLE public.stock_movements ALTER COLUMN movement_type SET NOT NULL;
ALTER TABLE public.stock_movements ALTER COLUMN type SET NOT NULL;

-- Posé APRÈS l'alignement ci-dessus (qui s'exécute en propriétaire, donc
-- n'aurait de toute façon pas été arrêté).
DROP TRIGGER IF EXISTS stock_movement_effect_guard ON public.stock_movements;
CREATE TRIGGER stock_movement_effect_guard
  BEFORE UPDATE ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.stock_movement_effect_guard();

-- La décision de l'utilisateur, mouvement par mouvement.
CREATE OR REPLACE FUNCTION public.resolve_stock_movement_phantom(p_phantom_id uuid, p_decision text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_ph public.stock_movement_phantoms%ROWTYPE;
  v_new uuid;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Société non identifiée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT can_perform('stock_movements', 'insert') THEN
    RAISE EXCEPTION 'Droit insuffisant : seul un utilisateur qui saisit les mouvements de stock décide d''un mouvement fantôme'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('replayed', 'ignored') THEN
    RAISE EXCEPTION 'Décision inconnue « % » (replayed ou ignored)', p_decision USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_ph FROM public.stock_movement_phantoms
  WHERE id = p_phantom_id AND tenant_id = v_tid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mouvement fantôme introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_ph.decision <> 'pending' THEN
    RAISE EXCEPTION 'Ce mouvement fantôme a déjà été traité (%)', v_ph.decision USING ERRCODE = 'check_violation';
  END IF;

  IF p_decision = 'replayed' AND v_ph.type NOT IN ('in', 'out', 'initial') THEN
    -- Un inventaire rejoué aujourd'hui poserait une quantité comptée à une autre
    -- date : seul un nouvel inventaire dit le stock réel.
    RAISE EXCEPTION 'Un mouvement « % » ne se rejoue pas : ignorez-le et saisissez un inventaire', v_ph.type
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_decision = 'replayed' THEN
    -- Un mouvement NEUF, daté du jour de la décision : le fantôme reste tel quel.
    INSERT INTO public.stock_movements
      (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
       reference, reference_type, reference_id, date, movement_date, notes)
    VALUES
      (v_tid, v_ph.product_id, v_ph.warehouse_id, v_ph.type, v_ph.type, v_ph.quantity,
       NULLIF(v_ph.unit_cost, 0), v_ph.reference, 'phantom_replay', v_ph.movement_id,
       CURRENT_DATE, CURRENT_DATE,
       'Rejeu du mouvement fantôme du ' || COALESCE(v_ph.movement_date::text, '?'))
    RETURNING id INTO v_new;
  END IF;

  UPDATE public.stock_movement_phantoms
  SET decision = p_decision, decided_by = auth.uid(), decided_at = now(), replay_movement_id = v_new
  WHERE id = v_ph.id;

  RETURN jsonb_build_object('id', v_ph.id, 'decision', p_decision, 'movement_id', v_new);
END $$;
REVOKE EXECUTE ON FUNCTION public.resolve_stock_movement_phantom(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_stock_movement_phantom(uuid, text) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 3. M6 : le stock d'un article naît de ses mouvements
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.products_stock_quantity_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Le moteur (`_stock_increment`, `_stock_decrement`, `update_stock_on_movement`)
  -- est SECURITY DEFINER : il écrit sous le rôle propriétaire.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND COALESCE(NEW.stock_quantity, 0) <> 0 THEN
    RAISE EXCEPTION 'Le stock d''un article naît de ses mouvements : créez l''article, puis saisissez son stock initial (dépôt et coût)'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity THEN
    RAISE EXCEPTION 'La quantité en stock ne se saisit pas : elle suit les mouvements (entrée, sortie, inventaire)'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.products_stock_quantity_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS products_stock_quantity_guard ON public.products;
CREATE TRIGGER products_stock_quantity_guard
  BEFORE INSERT OR UPDATE OF stock_quantity ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_stock_quantity_guard();

-- ------------------------------------------------------------
-- 4. Lignes de commande calculées par la base, totaux = agrégat des lignes
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_order_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE a record; v_st text; v_num text;
BEGIN
  IF TG_OP = 'DELETE'
     OR (TG_OP = 'INSERT')
     OR (NEW.product_id, NEW.quantity, NEW.unit_price, NEW.vat_rate)
        IS DISTINCT FROM (OLD.product_id, OLD.quantity, OLD.unit_price, OLD.vat_rate) THEN
    SELECT status, number INTO v_st, v_num FROM purchase_orders
    WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.purchase_order_id ELSE NEW.purchase_order_id END
      AND tenant_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
    IF v_st IN ('partial', 'received', 'cancelled') THEN
      RAISE EXCEPTION 'Commande % (%) : ses lignes ne se modifient plus', v_num, v_st
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.line_total := a.total;
  IF NULLIF(btrim(NEW.description), '') IS NULL AND NEW.product_id IS NOT NULL THEN
    SELECT name INTO NEW.description FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.purchase_order_line_compute() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sales_order_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE a record; v_st text; v_num text;
BEGIN
  IF TG_OP = 'DELETE'
     OR (TG_OP = 'INSERT')
     OR (NEW.product_id, NEW.quantity, NEW.unit_price, NEW.vat_rate)
        IS DISTINCT FROM (OLD.product_id, OLD.quantity, OLD.unit_price, OLD.vat_rate) THEN
    SELECT status, number INTO v_st, v_num FROM sales_orders
    WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.sales_order_id ELSE NEW.sales_order_id END
      AND tenant_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
    IF v_st IN ('delivered', 'invoiced', 'cancelled') THEN
      RAISE EXCEPTION 'Commande % (%) : ses lignes ne se modifient plus', v_num, v_st
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.line_total := a.total;
  IF NULLIF(btrim(NEW.description), '') IS NULL AND NEW.product_id IS NOT NULL THEN
    SELECT name INTO NEW.description FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.sales_order_line_compute() FROM PUBLIC, anon, authenticated;

-- Totaux d'une commande : somme des lignes (HT), TVA ligne à ligne.
CREATE OR REPLACE FUNCTION public.order_totals_from_lines(p_table text, p_order_id uuid, p_tenant_id uuid,
  OUT n int, OUT ht numeric, OUT tva numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF p_table = 'purchase_orders' THEN
    SELECT count(*)::int, COALESCE(sum(l.line_total), 0),
           COALESCE(sum((line_amounts(l.quantity, l.unit_price, l.vat_rate)).vat), 0)
      INTO n, ht, tva
    FROM purchase_order_lines l
    WHERE l.purchase_order_id = p_order_id AND l.tenant_id = p_tenant_id;
  ELSE
    SELECT count(*)::int, COALESCE(sum(l.line_total), 0),
           COALESCE(sum((line_amounts(l.quantity, l.unit_price, l.vat_rate)).vat), 0)
      INTO n, ht, tva
    FROM sales_order_lines l
    WHERE l.sales_order_id = p_order_id AND l.tenant_id = p_tenant_id;
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.order_totals_from_lines(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- En-tête : les totaux ne se saisissent pas. Une commande sans ligne (création,
-- ou commande antérieure à la 280) garde ses totaux précédents — 0 à la création.
CREATE OR REPLACE FUNCTION public.order_header_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE s record;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.subtotal := 0; NEW.vat := 0; NEW.total := 0;
    RETURN NEW;
  END IF;
  s := order_totals_from_lines(TG_TABLE_NAME, NEW.id, NEW.tenant_id);
  IF s.n > 0 THEN
    NEW.subtotal := s.ht; NEW.vat := s.tva; NEW.total := s.ht + s.tva;
  ELSE
    NEW.subtotal := OLD.subtotal; NEW.vat := OLD.vat; NEW.total := OLD.total;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.order_header_totals() FROM PUBLIC, anon, authenticated;

-- Lignes → en-tête
CREATE OR REPLACE FUNCTION public.order_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_id uuid; v_tid uuid;
BEGIN
  IF TG_TABLE_NAME = 'purchase_order_lines' THEN
    FOR v_id, v_tid IN
      SELECT DISTINCT x.id, x.t FROM (VALUES
        (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_order_id END, CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
        (CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_order_id END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
      ) x(id, t) WHERE x.id IS NOT NULL
    LOOP
      -- le déclencheur d'en-tête recalcule depuis les lignes
      UPDATE purchase_orders SET updated_at = now() WHERE id = v_id AND tenant_id = v_tid;
    END LOOP;
  ELSE
    FOR v_id, v_tid IN
      SELECT DISTINCT x.id, x.t FROM (VALUES
        (CASE WHEN TG_OP <> 'INSERT' THEN OLD.sales_order_id END, CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
        (CASE WHEN TG_OP <> 'DELETE' THEN NEW.sales_order_id END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
      ) x(id, t) WHERE x.id IS NOT NULL
    LOOP
      UPDATE sales_orders SET updated_at = now() WHERE id = v_id AND tenant_id = v_tid;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.order_lines_refresh_totals() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_po_line_compute ON public.purchase_order_lines;
CREATE TRIGGER tg_po_line_compute
  BEFORE INSERT OR UPDATE OR DELETE ON public.purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.purchase_order_line_compute();
DROP TRIGGER IF EXISTS tg_po_lines_refresh_totals ON public.purchase_order_lines;
CREATE TRIGGER tg_po_lines_refresh_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.order_lines_refresh_totals();
DROP TRIGGER IF EXISTS tg_po_header_totals ON public.purchase_orders;
CREATE TRIGGER tg_po_header_totals
  BEFORE INSERT OR UPDATE ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.order_header_totals();

DROP TRIGGER IF EXISTS tg_so_line_compute ON public.sales_order_lines;
CREATE TRIGGER tg_so_line_compute
  BEFORE INSERT OR UPDATE OR DELETE ON public.sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.sales_order_line_compute();
DROP TRIGGER IF EXISTS tg_so_lines_refresh_totals ON public.sales_order_lines;
CREATE TRIGGER tg_so_lines_refresh_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.order_lines_refresh_totals();
DROP TRIGGER IF EXISTS tg_so_header_totals ON public.sales_orders;
CREATE TRIGGER tg_so_header_totals
  BEFORE INSERT OR UPDATE ON public.sales_orders
  FOR EACH ROW EXECUTE FUNCTION public.order_header_totals();

-- Création atomique en-tête + lignes (SECURITY INVOKER : RLS et can_perform
-- s'appliquent comme à l'écran).
CREATE OR REPLACE FUNCTION public.create_purchase_order(p_order jsonb, p_lines jsonb)
RETURNS public.purchase_orders
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_po public.purchase_orders; v_l jsonb; i int := 0;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Une commande fournisseur porte au moins une ligne (article, quantité, prix)'
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO purchase_orders (number, supplier_id, order_date, expected_date, status, notes)
  VALUES (p_order->>'number', NULLIF(p_order->>'supplier_id', '')::uuid,
          COALESCE(NULLIF(p_order->>'order_date', '')::date, CURRENT_DATE),
          NULLIF(p_order->>'expected_date', '')::date, 'draft', NULLIF(p_order->>'notes', ''))
  RETURNING * INTO v_po;
  FOR v_l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    i := i + 1;
    IF COALESCE((v_l->>'quantity')::numeric, 0) <= 0 THEN
      RAISE EXCEPTION 'Ligne % : la quantité doit être positive', i USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO purchase_order_lines (purchase_order_id, product_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (v_po.id, NULLIF(v_l->>'product_id', '')::uuid, COALESCE(v_l->>'description', ''),
            (v_l->>'quantity')::numeric, COALESCE((v_l->>'unit_price')::numeric, 0),
            COALESCE((v_l->>'vat_rate')::numeric, 0), i);
  END LOOP;
  SELECT * INTO v_po FROM purchase_orders WHERE id = v_po.id;
  RETURN v_po;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_purchase_order(jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_purchase_order(jsonb, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_sales_order(p_order jsonb, p_lines jsonb)
RETURNS public.sales_orders
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_so public.sales_orders; v_l jsonb; i int := 0;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Une commande client porte au moins une ligne (article, quantité, prix)'
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO sales_orders (number, customer_id, order_date, delivery_date, status, notes)
  VALUES (p_order->>'number', NULLIF(p_order->>'customer_id', '')::uuid,
          COALESCE(NULLIF(p_order->>'order_date', '')::date, CURRENT_DATE),
          NULLIF(p_order->>'delivery_date', '')::date, 'draft', NULLIF(p_order->>'notes', ''))
  RETURNING * INTO v_so;
  FOR v_l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    i := i + 1;
    IF COALESCE((v_l->>'quantity')::numeric, 0) <= 0 THEN
      RAISE EXCEPTION 'Ligne % : la quantité doit être positive', i USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO sales_order_lines (sales_order_id, product_id, description, quantity, unit_price, vat_rate, delivered_quantity)
    VALUES (v_so.id, NULLIF(v_l->>'product_id', '')::uuid, COALESCE(v_l->>'description', ''),
            (v_l->>'quantity')::numeric, COALESCE((v_l->>'unit_price')::numeric, 0),
            COALESCE((v_l->>'vat_rate')::numeric, 0), 0);
  END LOOP;
  SELECT * INTO v_so FROM sales_orders WHERE id = v_so.id;
  RETURN v_so;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_sales_order(jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_sales_order(jsonb, jsonb) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 5. La réception naît de la commande
-- ------------------------------------------------------------
ALTER TABLE public.goods_receipt_lines ADD COLUMN IF NOT EXISTS purchase_order_line_id uuid;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'goods_receipt_lines_tenant_id_id_key') THEN
    ALTER TABLE public.goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_tenant_id_id_key UNIQUE (tenant_id, id);
  END IF;
END $$;
ALTER TABLE public.goods_receipt_lines
  DROP CONSTRAINT IF EXISTS grl_purchase_order_line_id_fkey,
  ADD CONSTRAINT grl_purchase_order_line_id_fkey
    FOREIGN KEY (tenant_id, purchase_order_line_id)
    REFERENCES public.purchase_order_lines(tenant_id, id) ON DELETE SET NULL (purchase_order_line_id);
CREATE INDEX IF NOT EXISTS idx_grl_purchase_order_line
  ON public.goods_receipt_lines (tenant_id, purchase_order_line_id) WHERE purchase_order_line_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_goods_receipt_from_order(
  p_order_id uuid, p_number text, p_receipt_date date DEFAULT CURRENT_DATE, p_warehouse_id uuid DEFAULT NULL)
RETURNS public.goods_receipts
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_po public.purchase_orders;
  v_gr public.goods_receipts;
  v_l record;
  v_n int := 0;
BEGIN
  SELECT * INTO v_po FROM purchase_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commande fournisseur introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_po.status NOT IN ('confirmed', 'partial') THEN
    RAISE EXCEPTION 'Commande % au statut « % » : seule une commande confirmée se réceptionne', v_po.number, v_po.status
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO goods_receipts (number, supplier_id, purchase_order_id, receipt_date, status, warehouse_id)
  VALUES (p_number, v_po.supplier_id, v_po.id, COALESCE(p_receipt_date, CURRENT_DATE), 'pending', p_warehouse_id)
  RETURNING * INTO v_gr;

  -- Reste à recevoir par ligne : commandé − déjà rattaché à une réception non annulée
  FOR v_l IN
    SELECT pol.id, pol.product_id, pol.description, pol.quantity,
           pol.quantity - COALESCE((
             SELECT sum(grl.quantity_received)
             FROM goods_receipt_lines grl
             JOIN goods_receipts gr ON gr.id = grl.goods_receipt_id AND gr.tenant_id = grl.tenant_id
             WHERE grl.purchase_order_line_id = pol.id AND grl.tenant_id = pol.tenant_id
               AND gr.status <> 'cancelled' AND gr.id <> v_gr.id), 0) AS reste
    FROM purchase_order_lines pol
    WHERE pol.purchase_order_id = v_po.id AND pol.tenant_id = v_po.tenant_id
      AND pol.product_id IS NOT NULL
    ORDER BY pol.line_order NULLS LAST, pol.id
  LOOP
    CONTINUE WHEN v_l.reste <= 0;
    INSERT INTO goods_receipt_lines (goods_receipt_id, product_id, description, quantity_ordered,
                                     quantity_received, purchase_order_line_id)
    VALUES (v_gr.id, v_l.product_id, v_l.description, v_l.quantity, v_l.reste, v_l.id);
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Commande % : plus rien à recevoir (ou aucune ligne d''article)', v_po.number
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_gr;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_goods_receipt_from_order(uuid, text, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_goods_receipt_from_order(uuid, text, date, uuid) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 6. Ce qu'un lecteur ne doit pas écrire (M8, révélé par ces écrans)
-- Le balayage du lecteur (15_security) ne teste qu'une table qui A une ligne :
-- commande client confirmée → `stock_reservations`, commande fournisseur
-- confirmée → `budget_commitments`. Même mécanisme que 271 §2, 274 §3, 275 §4.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.guard_writes_with_can_perform(p_tables text[])
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE r record; v_action text; v_garde text; v_qual text; v_wc text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name, p.polname, p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS wc
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relname = ANY (p_tables) AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd', '*')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN CONTINUE; END IF;
    IF r.polcmd = '*' THEN
      -- politique ALL scindée : les noms dérivent de l'ancienne (une table peut
      -- déjà porter un « <table>_select »)
      EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.table_name);
      -- une lecture existe déjà (politique SELECT propre) : ne pas la doubler (238)
      IF NOT EXISTS (SELECT 1 FROM pg_policy p2 WHERE p2.polrelid = ('public.' || quote_ident(r.table_name))::regclass
                     AND p2.polpermissive AND p2.polcmd = 'r') THEN
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT USING (%s)', r.polname || '_r', r.table_name, r.qual);
      END IF;
      EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT WITH CHECK ((%s) AND can_perform(%L, ''insert''))',
                     r.polname || '_a', r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE USING ((%s) AND can_perform(%L, ''update'')) WITH CHECK ((%s) AND can_perform(%L, ''update''))',
                     r.polname || '_w', r.table_name, r.qual, r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE USING ((%s) AND can_perform(%L, ''delete''))',
                     r.polname || '_d', r.table_name, r.qual, r.table_name);
      v_n := v_n + 4;
      CONTINUE;
    END IF;
    v_action := CASE r.polcmd WHEN 'a' THEN 'insert' WHEN 'w' THEN 'update' ELSE 'delete' END;
    v_garde := format('can_perform(%L, %L)', r.table_name, v_action);
    IF r.polcmd = 'a' THEN
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', r.polname, r.table_name, v_wc);
    ELSIF r.polcmd = 'd' THEN
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', r.polname, r.table_name, v_qual);
    ELSE
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', r.polname, r.table_name, v_qual, v_wc);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

DO $$
DECLARE v_n int;
BEGIN
  v_n := pg_temp.guard_writes_with_can_perform(ARRAY['stock_reservations', 'budget_commitments']);
  RAISE NOTICE '[X4/M8] % politique(s) d''écriture gardée(s) par can_perform', v_n;
END $$;
