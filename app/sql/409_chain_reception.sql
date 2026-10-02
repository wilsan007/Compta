-- ============================================================
-- 319_chain_reception.sql — LA RÉCEPTION DE MARCHANDISE, tracée PAR LIGNE
--
-- Ce que l'inventaire de L1 (tranche 4, §5) en disait :
--   « La réception de marchandise reste non tracée (`create_stock_on_goods_receipt`) :
--     N mouvements à partir de N lignes, la correspondance ligne → ligne demande
--     la RÉÉCRITURE DU CORPS (doctrine 311). »
--
-- POURQUOI UNE RÉÉCRITURE, ET PAS UN COMPAGNON. La doctrine de la 310 pose un
-- déclencheur `AFTER` *compagnon* quand l'aval est unique et identifiable depuis
-- l'extérieur (`link_documents(…, v_aval, …)` retrouvé par une clé). Ici l'aval
-- est **N mouvements calculés dans la boucle** : rien, de l'extérieur, ne dit
-- quel mouvement correspond à quelle ligne — les N mouvements portent tous le
-- même `reference_id` (la réception), et l'ordre d'insertion n'est pas une
-- garantie. C'est la seule justification admise par la 311 pour réécrire un corps
-- métier, et elle est écrite ici.
--
-- CE QUE LA RÉÉCRITURE AJOUTE, ET RIEN D'AUTRE. Le corps reprend **exactement**
-- le comportement de la 241 (même boucle, même coût, même dépôt) et ajoute :
--   * `chain_avant` — l'ENTRÉE du maillon, par ligne de réception ;
--   * `RETURNING id` + `link_documents` — la ligne → LE mouvement qu'elle a produit ;
--   * `emit_domain_event` + `chain_apres` — l'événement et la trace de sortie.
--
-- LE REJEU NE DOUBLE PAS LE STOCK. `chain_avant` rend **faux** quand le lien
-- existe déjà (`chain_deja_fait`), et le corps passe alors à la ligne suivante.
-- Le garde existant — `OLD.status = 'received'` — empêche déjà la seconde
-- exécution, et la **251 refuse la réédition d'une réception** : le rejeu est
-- donc structurellement impossible, et la suite le mesure (T05).
--
-- ⚠️ CE QUE CE FICHIER NE FAIT PAS : il n'appelle pas le **cycle du lien**
-- (`chain_lien_fermer`) sur le chemin d'annulation. Aucun maillon ne le fait
-- encore — c'est le reste de L3, écrit ici pour que la prochaine tranche ne le
-- cherche pas ailleurs.
-- ============================================================


CREATE OR REPLACE FUNCTION create_stock_on_goods_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_warehouse uuid;
  v_unit_cost numeric;
  v_mouvement uuid;
  v_debut timestamptz := clock_timestamp();
  v_lignes integer := 0;
BEGIN
  -- Ne réagir qu'au passage à 'received'
  IF NEW.status <> 'received' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'received' THEN
    RETURN NEW;
  END IF;

  -- S-04 : le dépôt de la réception, sinon le dépôt de la société
  v_warehouse := COALESCE(NEW.warehouse_id, resolve_default_warehouse(NEW.tenant_id));

  FOR v_line IN
    SELECT * FROM goods_receipt_lines
    WHERE goods_receipt_id = NEW.id
      AND tenant_id = NEW.tenant_id
      AND quantity_received > 0
  LOOP
    -- L3 (319) : l'ENTRÉE du maillon, PAR LIGNE de réception (M-09).
    -- Rend faux sur un rejeu — et le stock n'est alors PAS doublé.
    IF NOT chain_avant(NEW.tenant_id, 'goods_receipts', 'received', 'purchase.receipt.stock_in',
                       'goods_receipts', NEW.id, v_line.id,
                       format('Réception %s du %s : l''entrée en stock de l''article %s n''a pas été produite (règle purchase.receipt.stock_in, module stock).',
                              NEW.number, to_char(NEW.receipt_date, 'DD/MM/YYYY'), v_line.product_id))
    THEN
      CONTINUE;
    END IF;

    -- S-02 : coût de la ligne de commande, sinon prix d'achat de l'article,
    -- sinon coût de revient. Sans aucun des trois : 0, et pas d'écriture.
    v_unit_cost := NULL;

    IF NEW.purchase_order_id IS NOT NULL THEN
      SELECT NULLIF(pol.unit_price, 0) INTO v_unit_cost
      FROM purchase_order_lines pol
      WHERE pol.purchase_order_id = NEW.purchase_order_id
        AND pol.tenant_id = NEW.tenant_id
        AND pol.product_id = v_line.product_id
      ORDER BY pol.line_order NULLS LAST, pol.id
      LIMIT 1;
    END IF;

    IF v_unit_cost IS NULL THEN
      SELECT NULLIF(COALESCE(p.purchase_price, 0), 0) INTO v_unit_cost
      FROM products p
      WHERE p.id = v_line.product_id AND p.tenant_id = NEW.tenant_id;
    END IF;

    IF v_unit_cost IS NULL THEN
      SELECT NULLIF(COALESCE(p.cost_price, 0), 0) INTO v_unit_cost
      FROM products p
      WHERE p.id = v_line.product_id AND p.tenant_id = NEW.tenant_id;
    END IF;

    v_unit_cost := COALESCE(v_unit_cost, 0);

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id,
      reference, reference_type, reference_id,
      date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_line.product_id, v_warehouse, 'in', 'in', v_line.quantity_received, v_unit_cost,
      v_line.lot_id, v_line.serial_id,
      'BR-' || NEW.number, 'goods_receipt', NEW.id,
      NEW.receipt_date, NEW.receipt_date,
      'Réception automatique - BR ' || NEW.number
    )
    RETURNING id INTO v_mouvement;

    -- LE LIEN : la LIGNE de réception → LE mouvement qu'elle a produit (M-09).
    PERFORM link_documents(NEW.tenant_id, 'goods_receipts', NEW.id, 'stock_movements', v_mouvement,
                           'purchase.receipt.stock_in', 'created_from',
                           jsonb_build_object('quantity', v_line.quantity_received,
                                              'unit_cost', v_unit_cost,
                                              'warehouse_id', v_warehouse,
                                              'reference', 'BR-' || NEW.number),
                           v_line.id, NULL);

    v_lignes := v_lignes + 1;
  END LOOP;

  IF v_lignes > 0 THEN
    PERFORM emit_domain_event(NEW.tenant_id, 'goods_receipts.received', 'goods_receipts', NEW.id,
                              jsonb_build_object('mouvements', v_lignes, 'warehouse_id', v_warehouse,
                                                 'purchase_order_id', NEW.purchase_order_id), NULL);
    PERFORM chain_apres(NEW.tenant_id, 'purchase.receipt.stock_in', 'goods_receipts', NEW.id,
                        v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  END IF;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.create_stock_on_goods_receipt() IS
  'L3 (319) : BR reçu → une entrée de stock PAR LIGNE, tracée par ligne (purchase.receipt.stock_in). '
  'Réécriture du corps (doctrine 311) : N mouvements à partir de N lignes, la correspondance ligne → ligne ne se devine pas de l''extérieur.';

-- ─────────────────────────────────────────────────────────────
-- LE CONTRAT D'EFFET, déclaré dans le même fichier
-- ─────────────────────────────────────────────────────────────
-- La porte **G2** (`ci/check_effects_contract.sql`) exige que tout effet appelé
-- soit déclaré : sans cette ligne, `chain_avant` tracerait `tolere` (« contrat
-- manquant ») à chaque réception. Le mode par défaut applique quand même l'effet
-- — le stock n'est jamais perdu — mais la trace mentirait sur ce qui est garanti.
--
-- `touche_stock = true` : c'est un mouvement de stock, et `create_journal_on_stock_movement`
-- en tire l'écriture (journal **ST**). `reversible = true` : la 251 contrepasse
-- l'annulation d'une réception (sortie miroir au même coût + écriture inverse).
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  (NULL, 'goods_receipts', 'received', 'purchase.receipt.stock_in',
   true, 'ST', true, false, true, true, true,
   'L3 (319) : create_stock_on_goods_receipt écrit un stock_movement PAR LIGNE de réception, tracé par ligne (M-09). '
   'L''écriture de stock (journal ST) en découle, par le maillon déjà en place. Réversible : la 251 contrepasse l''annulation.')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
             document_type, evenement, effet)
DO UPDATE SET
  ecrit_comptable = EXCLUDED.ecrit_comptable,
  journal_code    = EXCLUDED.journal_code,
  touche_stock    = EXCLUDED.touche_stock,
  touche_paie     = EXCLUDED.touche_paie,
  reversible      = EXCLUDED.reversible,
  obligatoire     = EXCLUDED.obligatoire,
  actif           = EXCLUDED.actif,
  note            = EXCLUDED.note;

-- ─────────────────────────────────────────────────────────────
-- Le contrôle de cohérence, joué à l'application de la migration
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_contrat int;
  v_lien    text;
BEGIN
  SELECT count(*) INTO v_contrat FROM document_effects
   WHERE tenant_id IS NULL AND document_type = 'goods_receipts'
     AND evenement = 'received' AND effet = 'purchase.receipt.stock_in' AND actif;

  IF v_contrat <> 1 THEN
    RAISE EXCEPTION '319 : le contrat purchase.receipt.stock_in doit être déclaré et actif (% trouvé(s)) — sans lui, chaque réception tracerait « contrat manquant »', v_contrat;
  END IF;

  -- La réécriture doit avoir laissé la trace du lien PAR LIGNE dans le corps.
  SELECT prosrc INTO v_lien FROM pg_proc WHERE proname = 'create_stock_on_goods_receipt';
  IF v_lien NOT LIKE '%link_documents%' OR v_lien NOT LIKE '%RETURNING id INTO v_mouvement%' THEN
    RAISE EXCEPTION '319 : le corps de create_stock_on_goods_receipt ne lie pas la ligne à son mouvement — la réécriture n''a pas abouti';
  END IF;
END $$;

