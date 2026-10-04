-- ════════════════════════════════════════════════════════════════════════════
-- 346 — Partie 2, tâche 2.7 (suite) : les deux décisions de la recette,
--       tranchées le 04/10/2026 « selon les standards recommandés »
-- ════════════════════════════════════════════════════════════════════════════
--
--   D-QA-3  Articles existants à prix négatif → option (b) : DÉSACTIVÉS. On
--           n'invente pas de prix ; l'article sort des listes de saisie, et il
--           ne pourra être réactivé qu'avec un prix corrigé (les contraintes de
--           la 345 s'appliquent à toute modification).
--   D-QA-4  Contrepartie comptable du stock initial → option (a) : une écriture
--           d'À-NOUVEAU, compte de stock de l'article au débit, 890000 « Bilan
--           d'ouverture » au crédit — le modèle de la banque (277).
--
-- LE DÉFAUT, MESURÉ (suite 346). Un stock initial de 100 unités à 12 € entrait
-- au stock (quantité, couche valorisée) sans AUCUNE écriture : le stock valorisé
-- valait 1 200 € et le compte 31x restait à 0. L'invariant INV-01 (« stock
-- valorisé = solde des comptes de stock ») était rompu dès la première saisie.
--
-- CE QUE FAIT L'ÉCRITURE.
--   * journal AN, datée du DÉBUT de l'exercice qui contient la date du
--     mouvement (à défaut, de l'exercice ouvert le plus récent) ;
--   * une écriture par mouvement `initial` (référence STOCK-OPEN-<mouvement>),
--     jamais deux ; validée par le noyau comptable ;
--   * sans exercice pour la porter, AUCUNE écriture n'est passée et le
--     mouvement est accepté : un avertissement est émis. Le stock initial d'une
--     société qui n'a pas encore d'exercice ne doit pas être bloqué.
--
-- CE QU'ELLE NE FAIT PAS.
--   * Les stocks initiaux DÉJÀ saisis n'ont pas d'écriture et n'en reçoivent
--     pas d'office : passer des à-nouveaux sur des exercices en cours se décide
--     dossier par dossier. `stock_initial_missing_entries()` les liste.
--   * Un mouvement `initial` sans coût (valeur nulle) ne produit rien.
-- ════════════════════════════════════════════════════════════════════════════

-- ── D-QA-3 : désactiver les articles à prix négatif ───────────────────────
-- Les contraintes de la 345, même NOT VALID, refusent toute modification d'une
-- ligne qui les viole : on les lève le temps de la désactivation, puis on les
-- repose à l'identique.
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sale_price_nonneg;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_purchase_price_nonneg;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_cost_price_nonneg;

DO $$
DECLARE n int;
BEGIN
  UPDATE public.products SET active = false
   WHERE COALESCE(active, true)
     AND (COALESCE(sale_price, 0) < 0 OR COALESCE(purchase_price, 0) < 0 OR COALESCE(cost_price, 0) < 0);
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    RAISE NOTICE '346 (D-QA-3) : % article(s) à prix négatif désactivé(s) — prix laissés tels quels, à corriger avant réactivation', n;
  END IF;
END $$;

ALTER TABLE public.products ADD CONSTRAINT products_sale_price_nonneg
  CHECK (sale_price IS NULL OR sale_price >= 0) NOT VALID;
ALTER TABLE public.products ADD CONSTRAINT products_purchase_price_nonneg
  CHECK (purchase_price IS NULL OR purchase_price >= 0) NOT VALID;
ALTER TABLE public.products ADD CONSTRAINT products_cost_price_nonneg
  CHECK (cost_price IS NULL OR cost_price >= 0) NOT VALID;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.products
                  WHERE COALESCE(sale_price, 0) < 0 OR COALESCE(purchase_price, 0) < 0 OR COALESCE(cost_price, 0) < 0) THEN
    ALTER TABLE public.products VALIDATE CONSTRAINT products_sale_price_nonneg;
    ALTER TABLE public.products VALIDATE CONSTRAINT products_purchase_price_nonneg;
    ALTER TABLE public.products VALIDATE CONSTRAINT products_cost_price_nonneg;
  END IF;
END $$;

-- ── D-QA-4 : l'à-nouveau du stock initial ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.stock_initial_post_opening_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_amount numeric := round(COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_cost, 0), 2);
  v_date date := COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE);
  v_stock_account text;
  v_nom text;
  v_entry uuid;
  v_number text;
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'initial' OR v_amount <= 0 THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM journal_entries je
              WHERE je.tenant_id = NEW.tenant_id AND je.reference = 'STOCK-OPEN-' || NEW.id) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND v_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_fy FROM fiscal_years
    WHERE tenant_id = NEW.tenant_id AND status NOT IN ('closed', 'locked')
    ORDER BY start_date DESC LIMIT 1;
  END IF;
  IF NOT FOUND THEN
    RAISE WARNING 'Stock initial (mouvement %) : aucun exercice pour porter l''écriture d''à-nouveau — le stock est enregistré, l''écriture reste à passer.', NEW.id;
    RETURN NULL;
  END IF;

  SELECT p.name INTO v_nom FROM products p WHERE p.id = NEW.product_id AND p.tenant_id = NEW.tenant_id;
  v_stock_account := COALESCE(resolve_stock_account(NEW.product_id), '310000');

  INSERT INTO journals (tenant_id, code, name, type, status, locked, next_number)
  VALUES (NEW.tenant_id, 'AN', 'À-nouveaux', 'general', 'active', false, 1)
  ON CONFLICT (tenant_id, code) DO NOTHING;
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, '890000', 'Bilan d''ouverture', 'equity')
  ON CONFLICT (tenant_id, code) DO NOTHING;
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, v_stock_account, 'Stocks', 'asset')
  ON CONFLICT (tenant_id, code) DO NOTHING;

  v_number := get_next_piece_number('AN');
  INSERT INTO journal_entries (tenant_id, number, piece_number, date, journal_code, status, description, reference)
  VALUES (NEW.tenant_id, v_number, v_number, v_fy.start_date, 'AN', 'draft',
          'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 'STOCK-OPEN-' || NEW.id)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order, product_id, quantity)
  VALUES
    (NEW.tenant_id, v_entry, v_stock_account, v_stock_account, 'Stocks',
     v_amount, 0, 'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 0, NEW.product_id, NEW.quantity),
    (NEW.tenant_id, v_entry, '890000', '890000', 'Bilan d''ouverture',
     0, v_amount, 'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 1, NULL, NULL);
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  RETURN NULL;
END $$;

REVOKE EXECUTE ON FUNCTION public.stock_initial_post_opening_entry() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_stock_initial_opening ON public.stock_movements;
CREATE TRIGGER tg_stock_initial_opening
  AFTER INSERT ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.stock_initial_post_opening_entry();

-- ── Les stocks initiaux saisis AVANT cette migration, sans écriture ───────
CREATE OR REPLACE FUNCTION public.stock_initial_missing_entries()
RETURNS TABLE (movement_id uuid, product_id uuid, product_name text, movement_date date, quantity numeric, unit_cost numeric, amount numeric)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $fn$
  SELECT m.id, m.product_id, p.name, COALESCE(m.movement_date, m.date)::date,
         m.quantity, m.unit_cost, round(m.quantity * m.unit_cost, 2)
  FROM stock_movements m
  LEFT JOIN products p ON p.id = m.product_id AND p.tenant_id = m.tenant_id
  WHERE m.movement_type = 'initial'
    AND COALESCE(m.quantity, 0) * COALESCE(m.unit_cost, 0) > 0
    AND NOT EXISTS (SELECT 1 FROM journal_entries je
                     WHERE je.tenant_id = m.tenant_id AND je.reference = 'STOCK-OPEN-' || m.id)
  ORDER BY 4, 3
$fn$;

COMMENT ON FUNCTION public.stock_initial_missing_entries() IS
  '346 — les stocks initiaux de la société de l''appelant (RLS) qui n''ont pas leur écriture d''à-nouveau : ceux saisis avant la 346, ou sans exercice pour la porter. Lecture seule ; rien n''est passé d''office.';

REVOKE ALL ON FUNCTION public.stock_initial_missing_entries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.stock_initial_missing_entries() TO authenticated, service_role;
