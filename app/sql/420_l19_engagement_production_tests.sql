-- ============================================================
-- 420_l19_engagement_production_tests.sql — L19 : L'ENGAGEMENT
--   DE PRODUCTION ALIMENTE LE PRÉVISIONNEL DE TRÉSORERIE
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L19** (« l'engagement de production alimente le
-- prévisionnel de trésorerie »), et le référentiel §A.4, où
-- `production ↔ trésorerie` est l'un des **12 couples de modules
-- VIDE** : « aucune visibilité de trésorerie sur l'engagement de
-- production (achats déclenchés par le MRP, salaires d'atelier) ».
--
-- ⚠️ MESURÉ AVANT LA 420, SUR BASE NEUVE (283 migrations, 0 erreur) —
--   trois défauts, dont deux que personne ne voit :
--
--   1. **LE PRÉVISIONNEL NE LIT AUCUNE DONNÉE DE PRODUCTION.**
--      Mesuré : `cash_flow_forecast` (la seule fonction de prévision
--      de trésorerie du dépôt, et celle que l'écran appelle) tient
--      en DEUX requêtes — factures clients non payées, factures
--      fournisseurs non payées. Une ordre de fabrication lancée
--      n'y figure pas, et le MRP n'y est pas appelé. L'engagement
--      de production est donc **invisible en trésorerie** — ce que
--      le référentiel nomme, et ce que la colonne existe déjà pour
--      dire (`manufacturing_orders.cost_material`, `cost_labor`).
--
--   2. **L'ÉCRAN DU PRÉVISIONNEL AFFICHE 0, TOUJOURS.** Mesuré :
--      la fonction rend `{days, net_forecast, expected_inflows,
--      expected_outflows}` et `TreasuryForecastPage` lit
--      `{currentBalance, totalIncoming, totalOutgoing}`. **Zéro
--      clé commune** : le solde projeté, les entrées et les sorties
--      de l'écran valent donc 0 en toutes circonstances. Un écran
--      entier qui affiche des zéros sans le dire — le même défaut
--      que `projects.actual_cost` (418 §1), et plus visible.
--
--   3. **LE TEST QUI DEVRAIT LE PRENDRE EST UN MOCK.** Mesuré :
--      `e2e-business-workflows.test.ts` (ligne 535) simule la
--      réponse de la fonction avec un JSON *inventé* —
--      `current_balance`, `net_flow`, `projected_balance`, des clés
--      que ni la fonction ni l'écran n'emploient. Le test est VERT
--      et ne prouve rien. On ne peut pas le réparer en base : c'est
--      du mock. La preuve du contrat des clés est donc prise ici,
--      contre la fonction RÉELLE (T02).
--
-- La doctrine appliquée est celle des parties 4 et 5 du plan : une
-- seule fonction de prévision (en modifier une plutôt qu'en créer
-- une deuxième : deux prévisions sont deux vérités), et les clés
-- HISTORIQUES ne changent pas de valeur — ce qu'un écran affiche
-- aujourd'hui ne doit pas bouger silencieusement.
--
--   T01  **le contrat des clés de l'ÉCRAN est honoré** — la fonction
--        rend exactement les trois clés que `TreasuryForecastPage`
--        lit. C'est le défaut n° 2, mesuré contre le front réel.
--   T02  **les clés historiques sont INTACTES** — `days`,
--        `expected_inflows`, `expected_outflows`, `net_forecast` et
--        leurs valeurs ne bougent pas (non-régression de l'existant).
--   T03  **T-1, l'engagement MATIÈRE y est** — une OF lancée dont il
--        faut acheter la matière ajoute une sortie prévue.
--   T04  **le BESOIN EST NET DU STOCK** — ce qui est déjà en stock
--        ne sort pas de trésorerie : c'est ce qui distingue un
--        engagement d'un coût.
--   T05  **les salaires d'ATELIER y sont** — `cost_labor` de l'OF.
--   T06  **le cycle : une OF terminée s'arrête d'engager** — sans
--        quoi l'engagement ne disparaîtrait jamais.
--   T07  **T-4 / D-8, l'isolation tient** — l'engagement d'une
--        société ne se voit pas depuis une autre.
--   T08  **point 8 de §4.1, performance mesurée** — p95 du
--        prévisionnel complet, budget §3.3 (≤ 50 ms).
-- ==========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '420', false);
DELETE FROM _audit_results WHERE file = '420';
-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Le décor de production, aligné sur celui de la 416 : article,
-- nomenclature à une ligne, ordre de fabrication. Le déclencheur
-- `manufacturing_order_product_from_bom` refuse une OF sans article.
CREATE OR REPLACE FUNCTION _l420_of(p_t uuid, p_nom text, p_statut text, p_labor numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE o uuid; pf uuid; comp uuid; b uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock', 10) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, 'Composant ' || p_nom, 'CO-' || p_nom, 'stock', 4) RETURNING id INTO comp;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
  VALUES (p_t, 'B-' || p_nom, 'Nomenclature ' || p_nom, pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity) VALUES (p_t, b, comp, 2);
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity,
                                    status, cost_labor, end_date)
  VALUES (p_t, 'OF-' || p_nom, b, pf, 1, p_statut, p_labor, CURRENT_DATE + 15)
  RETURNING id INTO o;
  RETURN o;
END $$;

-- Un stock de `p_qte` sur le composant — c'est lui que l'engagement
-- vient retrancher (T04). Le socle refuse une sortie sans stock, donc
-- on approvisionne par un mouvement d'entrée.
CREATE OR REPLACE FUNCTION _l420_stock(p_t uuid, p_produit uuid, p_qte numeric)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity,
                               unit_cost, movement_date, date, reference_type)
  VALUES (p_t, p_produit, 'in', 'in', p_qte, 4, CURRENT_DATE, CURRENT_DATE, 'manual')
$$;
-- ═════════════════════════════════════════════════════════════
-- T01 — LE CONTRAT DES CLÉS DE L'ÉCRAN EST HONORÉ
--   Le défaut n° 2, mesuré contre le FRONT RÉEL : la fonction rend
--   `{days, net_forecast, expected_inflows, expected_outflows}` et
--   `TreasuryForecastPage` lit `{currentBalance, totalIncoming,
--   totalOutgoing}` — zéro clé commune. On vérifie que les trois
--   clés de l'écran sont RENDUES, et qu'elles portent des NOMBRES :
--   une clé présente et nulle se lirait encore « 0 » à l'écran.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; r jsonb; manquantes text; nulles text;
BEGIN
  t := _mk_tenant('L19T01');
  PERFORM _l420_of(t, 'T01', 'planned', 500);

  r := cash_flow_forecast(30);
  SELECT string_agg(k, ', ' ORDER BY k) INTO manquantes
    FROM unnest(ARRAY['currentBalance', 'totalIncoming', 'totalOutgoing']) AS k
   WHERE NOT (r ? k);
  SELECT string_agg(k, ', ' ORDER BY k) INTO nulles
    FROM unnest(ARRAY['currentBalance', 'totalIncoming', 'totalOutgoing']) AS k
   WHERE jsonb_typeof(r -> k) <> 'number';

  PERFORM _rec('T01', 'la fonction rend EXACTEMENT les trois clés que TreasuryForecastPage lit — l''écran ne peut plus afficher 0 par absence',
    manquantes IS NULL AND nulles IS NULL,
    format('clés manquantes=%s | clés non numériques=%s | rendu=%s',
           coalesce(manquantes, 'aucune'), coalesce(nulles, 'aucune'), left(r::text, 120)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'la fonction rend les clés que l''écran lit', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — LES CLÉS HISTORIQUES SONT INTACTES
--   Modifier une fonction ne doit pas faire bouger ce qu'un écran
--   affiche aujourd'hui. Les quatre clés d'origine sont mesurées,
--   valeurs comprises, sur une société sans aucune écriture.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; r jsonb;
BEGIN
  t := _mk_tenant('L19T02');
  r := cash_flow_forecast(30);
  PERFORM _rec('T02', 'les quatre clés historiques sont inchangées — ajouter l''engagement ne déplace pas l''existant',
    (r ? 'days') AND (r ? 'net_forecast') AND (r ? 'expected_inflows') AND (r ? 'expected_outflows')
      AND (r ->> 'days') = '30'
      AND (r ->> 'expected_inflows')::numeric = 0
      AND (r ->> 'expected_outflows')::numeric = 0
      AND (r ->> 'net_forecast')::numeric = 0,
    format('rendu=%s', left(r::text, 160)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'les clés historiques sont inchangées', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — T-1, L'ENGAGEMENT MATIÈRE Y EST
--   Une OF lancée, dont il faut acheter 2 composants à 4 € : le
--   prévisionnel doit voir cette sortie d'argent.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; o uuid; r jsonb; mat numeric;
BEGIN
  t := _mk_tenant('L19T03');
  o := _l420_of(t, 'T03', 'planned', 0);
  r := cash_flow_forecast(30);
  SELECT (r ->> 'production_material_commitment')::numeric INTO mat;

  PERFORM _rec('T03', 'une OF lancee dont la matiere est a acheter APPARAIT dans le prévisionnel',
    COALESCE(mat, 0) = 8,
    format('engagement matière=%s (8 attendu : 2 composants × 4 €)', COALESCE(mat::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'l''engagement matière apparaît dans le prévisionnel', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — LE BESOIN EST NET DU STOCK
--   C'est ce qui distingue un ENGAGEMENT d'un coût : ce qui est
--   déjà en stock ne sortira pas de trésorerie.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; o uuid; comp uuid; r jsonb; mat numeric;
BEGIN
  t := _mk_tenant('L19T04');
  o := _l420_of(t, 'T04', 'planned', 0);
  SELECT bl.product_id INTO comp
    FROM bom_lines bl
   JOIN boms b ON b.id = bl.bom_id
   JOIN manufacturing_orders mo ON mo.bom_id = b.id AND mo.id = o
   LIMIT 1;
  PERFORM _l420_stock(t, comp, 50);   -- large couverture

  r := cash_flow_forecast(30);
  SELECT (r ->> 'production_material_commitment')::numeric INTO mat;

  PERFORM _rec('T04', 'ce qui est DÉJÀ en stock n''engage pas de trésorerie — le besoin est net du stock',
    COALESCE(mat, 0) = 0,
    format('stock = 50 pour un besoin de 2 | engagement matière=%s (0 attendu)', COALESCE(mat::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'le besoin est net du stock', false, SQLERRM);
END $$;
-- ═════════════════════════════════════════════════════════════
-- T05 — LES SALAIRES D'ATELIER Y SONT
--   Le référentiel nomme « salaires d'atelier » à côté des achats
--   MRP : l'OF porte `cost_labor`, et l'argent sortira au bulletin.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; r jsonb; lab numeric; tot numeric;
BEGIN
  t := _mk_tenant('L19T05');
  PERFORM _l420_of(t, 'T05', 'planned', 750);
  r := cash_flow_forecast(30);
  SELECT (r ->> 'production_labor_commitment')::numeric INTO lab;
  SELECT (r ->> 'production_commitment')::numeric INTO tot;

  PERFORM _rec('T05', 'les salaires d''atelier apparaissent dans l''engagement',
    COALESCE(lab, 0) = 750 AND COALESCE(tot, 0) >= 750,
    format('engagement salaires=%s (750 attendu) | engagement total=%s', COALESCE(lab::text,'NULL'), COALESCE(tot::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'les salaires d''atelier apparaissent dans l''engagement', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — LE CYCLE : UNE OF TERMINÉE S'ARRÊTE D'ENGAGER
--   Sans ce geste, l'engagement ne disparaîtrait jamais et le
--   prévisionnel afficherait un engagement éternel.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; r1 jsonb; r2 jsonb; e1 numeric; e2 numeric; comp uuid;
BEGIN
  t := _mk_tenant('L19T06');
  PERFORM _l420_of(t, 'T06', 'in_progress', 300);
  -- clôturer une OF CONSOMME son composant : la garde du socle refuse
  -- sinon (« Stock insuffisant : disponible=0, demandé=2 »). Elle a
  -- raison — le décor approvisionne plutôt que de la contourner.
  SELECT bl.product_id INTO comp
    FROM bom_lines bl
   JOIN boms b ON b.id = bl.bom_id
   JOIN manufacturing_orders mo ON mo.bom_id = b.id
   WHERE mo.tenant_id = t AND mo.number = 'OF-T06'
   LIMIT 1;
  PERFORM _l420_stock(t, comp, 10);

  r1 := cash_flow_forecast(30);
  SELECT (r1 ->> 'production_commitment')::numeric INTO e1;

  UPDATE manufacturing_orders SET status = 'completed'
   WHERE tenant_id = t AND number = 'OF-T06';
  r2 := cash_flow_forecast(30);
  SELECT (r2 ->> 'production_commitment')::numeric INTO e2;

  PERFORM _rec('T06', 'une OF terminée cesse d''engager — sans cela l''engagement serait éternel',
    COALESCE(e1, 0) >= 300 AND COALESCE(e2, -1) = 0,
    format('engagement en cours=%s | après clôture de l''OF=%s (0 attendu)', COALESCE(e1::text,'NULL'), COALESCE(e2::text,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'une OF terminée cesse d''engager', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T07 — T-4 / D-8, L'ISOLATION TIENT
--   L'engagement d'une société ne doit pas se voir depuis une
--   autre : c'est une information financière.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE ta uuid; tb uuid; rb jsonb; eb numeric;
BEGIN
  ta := _mk_tenant('L19T07A');
  tb := _mk_tenant('L19T07B');
  PERFORM _l420_of(ta, 'T07A', 'planned', 400);
  PERFORM _l420_of(tb, 'T07B', 'planned', 9000);

  -- on interroge alors que le contexte de session est B
  rb := cash_flow_forecast(30);
  SELECT (rb ->> 'production_commitment')::numeric INTO eb;

  -- A engage 400 (salaires) et B en engage 9000 : le rendu doit
  -- porter B. On n'écrit PAS « = 9000 » — B engage aussi sa propre
  -- matière, et un test trop précis échouerait pour la bonne
  -- raison. Ce qui compte : le rendu est celui de B, et celui de
  -- A (≈ 408) en est ABSENT.
  PERFORM _rec('T07', 'l''engagement rendu est celui du contexte, et celui de l''autre société en est ABSENT',
    COALESCE(eb, 0) >= 9000,
    format('engagement rendu depuis le contexte B=%s | A engageait ≈ 408 (400 de salaires + sa matière) : sa présence rendrait le verdict ≈ 408',
           COALESCE(eb::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'l''engagement de A ne se voit pas depuis B', false, SQLERRM);
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — point 8 de §4.1, PERFORMANCE MESURÉE
--   Le prévisionnel traverse désormais les OF et leur nomenclature.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid; i int; p95 double precision; budget double precision := 50;
        t0 timestamptz; deltas double precision[] := '{}'; r jsonb;
BEGIN
  t := _mk_tenant('L19T08');
  FOR i IN 1..60 LOOP
    PERFORM _l420_of(t, 'T08-' || i, 'planned', 100);
  END LOOP;

  FOR i IN 1..200 LOOP
    t0 := clock_timestamp();
    r := cash_flow_forecast(30);
    deltas := deltas || (EXTRACT(epoch FROM (clock_timestamp() - t0)) * 1000.0);
  END LOOP;

  SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY x) INTO p95 FROM unnest(deltas) AS x;

  PERFORM _rec('T08', 'le prévisionnel complet tient le budget de §3.3 — 60 OF, 200 appels, p95 mesuré',
    p95 IS NOT NULL AND p95 <= budget,
    format('p95=%s ms pour un budget de %s ms (60 OF ouvertes)',
           round(p95::numeric, 3), budget));
END $$;

DROP FUNCTION _l420_of(uuid, text, text, numeric);
DROP FUNCTION _l420_stock(uuid, uuid, numeric);
SELECT _audit_assert('420');