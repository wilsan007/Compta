-- ============================================================
-- 315_stock_exit_accounts.sql — D1 (stk-012)
--
-- Recette /qa du 29/09/2026 : un produit fini vendu en caisse sortait au compte
-- de MATIÈRES — D 603000 / C 310000 — alors que son entrée (l'OF) l'avait porté
-- en 355000 contre 713500. Mesuré : 355000 restait à 440 pour un stock de 308,
-- et 310000 perdait 132 € de matières qui n'avaient pas bougé.
--
-- `resolve_stock_account` / `resolve_variation_account` (241) lisent l'ARTICLE
-- et sa famille : c'est juste pour une réception, faux pour un produit fabriqué,
-- dont le compte de stock est décidé par la production. La règle retenue est
-- donc celle que la recette attend :
--
--   le compte d'une sortie est celui de l'ENTRÉE qui a nourri la couche
--   consommée — 355000/713500 pour un produit fini fabriqué, 370000/603000
--   pour une marchandise reçue, 310000/603000 pour une matière.
--
-- C'est vrai des quatre chemins de sortie (bon de livraison, caisse, inventaire,
-- production) : tous écrivent un mouvement `out` et passent par ce déclencheur.
--
-- Le lien vers l'écriture d'entrée est exact, jamais deviné :
--   - `piece_number = 'STK-' || mouvement` pour tout mouvement comptabilisé ici ;
--   - `reference = 'JE-OF-' || OF` pour la production, qui écrit sa propre
--     écriture (302) et laisse `piece_number` vide.
--
-- Mesuré sur base neuve à la 314, avant ce fichier : `315_*_tests` T01 rouge
-- (D 603000 88 / C 310000 88 au lieu de D 713500 / C 355000), T02 vert
-- (non-régression marchandise).
--
-- Cas limite inscrit au registre : si un même article a des couches entrées à
-- des comptes DIFFÉRENTS, la sortie suit la couche la plus ancienne — c'est
-- déjà l'ordre de consommation des couches (CUMP les ramène au même coût, pas
-- au même compte).
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_amount numeric;
  v_unit_cost numeric;
  v_product RECORD;
  v_stock_account text;
  v_variation_account text;
  v_existing uuid;
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
  IF NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = 'ST') THEN
    PERFORM ensure_standard_journals(NEW.tenant_id);
  END IF;

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

  -- S-10 : article, puis famille d'articles, puis le plan standard — c'est le
  -- repli, et le seul chemin pour une entrée ou une couche d'avant la 241.
  v_stock_account := COALESCE(v_stock_account, resolve_stock_account(NEW.product_id), '310000');
  v_variation_account := COALESCE(v_variation_account, resolve_variation_account(NEW.product_id), '603000');

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'draft',
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
END $$;

GRANT EXECUTE ON FUNCTION create_journal_on_stock_movement() TO service_role;
