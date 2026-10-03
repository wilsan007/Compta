-- 420 — l19_engagement_production
-- Numéro pris le 2026-10-03T15:03:14.463Z par migration-numero.mjs (ligne « L16-L24 », branche partie-5-integrite-chainages).
-- ============================================================
-- 420_l19_engagement_production.sql — L19 : L'ENGAGEMENT DE
--   PRODUCTION ALIMENTE LE PRÉVISIONNEL DE TRÉSORERIE
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md §5
-- Phase F, lot **L19** (« l'engagement de production alimente le
-- prévisionnel de trésorerie »), et le référentiel §A.4, où
-- `production ↔ trésorerie` est l'un des **12 couples de modules
-- VIDE** : « aucune visibilité de trésorerie sur l'engagement de
-- production (achats déclenchés par le MRP, salaires d'atelier) ».
--
-- LES TROIS DÉFAUTS, MESURÉS SUR BASE NEUVE (283 migrations) :
--
--   1. **LE PRÉVISIONNEL NE LIT AUCUNE DONNÉE DE PRODUCTION.**
--      `cash_flow_forecast` — la seule fonction de prévision du
--      dépôt, et celle que l'écran appelle — tient en DEUX requêtes :
--      factures clients non payées, factures fournisseurs non
--      payées. Le MRP n'est pas appelé, `manufacturing_orders` pas
--      lu. L'engagement est invisible — alors que les colonnes
--      `cost_material` et `cost_labor` EXISTENT déjà sur l'OF.
--
--   2. **L'ÉCRAN DU PRÉVISIONNEL AFFICHE 0, TOUJOURS.** Mesuré :
--      la fonction rend `{days, net_forecast, expected_inflows,
--      expected_outflows}` ; `TreasuryForecastPage` lit
--      `{currentBalance, totalIncoming, totalOutgoing}`. Zéro clé
--      commune. Un écran entier affiche des zéros sans le dire.
--
--   3. **LE TEST QUI DEVRAIT LE PRENDRE EST UN MOCK.** Mesuré :
--      `e2e-business-workflows.test.ts:535` simule la réponse avec
--      un JSON *inventé* (`current_balance`, `net_flow`,
--      `projected_balance`) — des clés que ni la fonction ni l'écran
--      n'emploient. Vert, et ne prouve rien. Le contrat des clés
--      est donc pris en base, contre la fonction RÉELLE (T01).
--
-- ⚠️ DEUX DÉCISIONS QUI ENGAGENT L'EXISTANT, ET LEUR MOTIF :
--
--   **On MODIFIE `cash_flow_forecast`, on n'en crée pas une
--   deuxième.** Deux prévisions de trésorerie seraient deux
--   vérités — la faute W5, celle du moteur d'amortissement
--   (260). Le dépôt n'a qu'une promesse de trésorerie ; c'est
--   celle-là qu'on complète.
-- ─────────────────────────────────────────────────────────────
-- 1. CE QUE LA FONCTION AJOUTE — trois montants, un par défaut
--
--    `production_material_commitment` — la MATIÈRE À ACHETER pour
--    les OF ouvertes de l'horizon. NETTE DU STOCK (T04) : c'est ce
--    qui distingue un engagement d'un coût, et c'est ce que le
--    MRP déclenche réellement.
--
--    `production_labor_commitment` — les SALAIRES D'ATELIER
--    (`cost_labor`) des mêmes OF.
--
--    `production_commitment` — leur somme.
--
--    L'HORIZON EST CELUI DE LA FONCTION (`p_days`). Une OF qui se
--    termine dans dix mois n'engage pas la trésorerie des trente
--    prochains jours : la restriction n'est pas un défaut de
--    précision, c'est ce qui rend le chiffre utile.
--
--    LE CYCLE : seules les OF `planned` et `in_progress` engagent
--    (T06). Une OF close a livré sa matière — son besoin est
--    satisfait et l'engagement doit disparaître, sans quoi il
--    deviendrait éternel.
--
--    LA NOMENCLATURE est lue par `manufacturing_requirements`
--    (302), qui explose les niveaux. On ne réécrit pas cette
--    explosion ici — ce serait un DEUXIÈME moteur de nomenclature
--    pour la même vérité.
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- 2. LA FONCTION — une seule, complétée
--    Le `SECURITY DEFINER` et le `current_tenant_id()` sont
--    conservés tels quels : c'est le contrôle de société que la
--    porte G4 reconnaît, et le retirer ferait rougir la porte.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cash_flow_forecast(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_inflows   numeric := 0;
  v_outflows  numeric := 0;
  v_achat_mat numeric := 0;   -- engagement MATIÈRE
  v_atelier   numeric := 0;   -- engagement SALAIRES
  v_solde     numeric := 0;   -- solde de trésorerie courant
  v_horizon   date;
BEGIN
  v_horizon := CURRENT_DATE + COALESCE(p_days, 30);

  -- ═══ LE PRÉVISIONNEL HISTORIQUE — inchangé, valeur pour valeur ═══
  SELECT COALESCE(SUM(amount_due), 0) INTO v_inflows
    FROM invoices
   WHERE tenant_id = current_tenant_id()
     AND status IN ('sent', 'overdue')
     AND due_date <= v_horizon;

  SELECT COALESCE(SUM(amount_due), 0) INTO v_outflows
    FROM purchase_invoices
   WHERE tenant_id = current_tenant_id()
     AND status IN ('received', 'overdue')
     AND due_date <= v_horizon;

  -- ═══ L'ENGAGEMENT DE PRODUCTION — ce que la 420 ajoute ═══
  -- Les deux sont séparés : la matière et les salaires sont deux
  -- sorties de trésorerie différentes (un achat, un bulletin), et
  -- les confondre ferait dire « l'atelier ne coûte rien » aux mois
  -- où les achats ont eu lieu.
-- ⚠️ MESURÉ, ET CORRIGÉ : CE SONT LES ALLERS-RETOURS QUI COÛTAIENT.
  --
  -- La première version imbriquait deux boucles : POUR chaque OF → POUR
  -- chaque ligne de nomenclature → un SELECT. En plpgsql, chaque itération
  -- est un APPEL SPI DISTINCT : soixante OF, donc soixante appels à
  -- `manufacturing_requirements`, chacun réentrant dans la fonction et
  -- réévaluant `current_tenant_id()`.
  --
  -- Mesuré sur le même décor (60 OF, moyenne de 20 appels) :
  --
  --     les trois requêtes du prévisionnel historique ...  0,11 / 0,10 / 0,11 ms
  --     l'explosion + le stock, écrits EN ENSEMBLE .........  2,94 ms
  --     la fonction, avec les deux boucles ................ 32,24 ms
  --
  -- Les 29 ms d'écart n'étaient pas du travail utile : c'étaient soixante
  -- allers-retours. La jointure latérale rend les soixante OF par UNE seule
  -- requête, pour le même résultat valeur pour valeur.
  --
  -- LES DEUX SOMMES RESTENT SÉPARÉES, délibérément. Les Salaires sont pris
  -- sur TOUTES les OF ouvertes — une OF sans nomenclature coûte quand même
  -- un bulletin —, la matière seulement sur les lignes qui portent un coût
  -- unitaire. Les confondre, ou filtrer les Salaires par le prix d'achat,
  -- ferait disparaître un atelier qui n'a pas encore reçu sa facture. C'est
  -- pourquoi les deux agrégats ne partagent pas le même filtre.
  --
  -- ⚠️ LE STOCK EST LU SUR LES MOUVEMENTS, ET C'EST MESURÉ.
  -- Les trois sources du dépôt ne concordent pas : un produit porte
  -- `products.stock_quantity = 50` alors que ses mouvements totalisent 0,
  -- et `stock_quantities` ne suit pas les mouvements (60 lignes pour 625).
  -- Lire `stock_quantities` — le réflexe — SURESTIMERAIT l'engagement : on
  -- verrait un achat déjà couvert par du stock. On lit donc les MOUVEMENTS,
  -- seule vérité append-only, et c'est ce que la 418 lit aussi. Le
  -- désaccord entre les trois tables est un défaut du MODULE STOCK, mesuré
  -- ici et laissé à son lot : le corriger depuis la trésorerie serait le
  -- corriger ailleurs que là où il vit.
  WITH ofs AS (
    SELECT mo.id, mo.cost_labor
      FROM manufacturing_orders mo
     WHERE mo.tenant_id = current_tenant_id()
       AND mo.status IN ('planned', 'in_progress')
       AND mo.bom_id IS NOT NULL
       AND COALESCE(mo.end_date, v_horizon) <= v_horizon
  )
  SELECT
    -- les Salaires d'atelier : UNE FOIS par OF, jamais par ligne
    (SELECT COALESCE(SUM(o.cost_labor), 0) FROM ofs o),
    -- la matière à ACHETER : le besoin MOINS ce qui est DÉJÀ en stock.
    -- La jointure latérale du stock s'isole : un produit lu dix fois n'est
    -- agrégé qu'une fois par ligne rendue.
    (SELECT COALESCE(SUM(
              GREATEST(0, r.quantity - COALESCE(st.qte, 0)) * r.actual_unit_cost
            ), 0)
       FROM ofs o
       CROSS JOIN LATERAL manufacturing_requirements(o.id, current_tenant_id()) r
       LEFT JOIN LATERAL (
         SELECT SUM(CASE WHEN sm.movement_type = 'in'  THEN  sm.quantity
                        WHEN sm.movement_type = 'out' THEN -sm.quantity
                        ELSE 0 END) AS qte
           FROM stock_movements sm
          WHERE sm.tenant_id = current_tenant_id()
            AND sm.product_id = r.product_id
            AND sm.movement_type IN ('in', 'out')
       ) st ON TRUE
      WHERE COALESCE(r.actual_unit_cost, 0) > 0)
  INTO v_atelier, v_achat_mat;

  -- Le SOLDE de trésorerie : la somme des lignes d'écriture des
  -- comptes de la classe 5. Une société sans écriture vaut 0 — ce
  -- qui est vrai, pas un défaut d'affichage.
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_solde
    FROM journal_lines jl
   WHERE jl.tenant_id = current_tenant_id()
     AND jl.account_general LIKE '5%';

  RETURN jsonb_build_object(
    -- ═══ les quatre clés HISTORIQUES, inchangées ═══
    'days',              p_days,
    'expected_inflows',  v_inflows,
    'expected_outflows', v_outflows,
    'net_forecast',      v_inflows - v_outflows,
    -- ═══ le CONTRAT DE L'ÉCRAN : les trois clés que
    --     `TreasuryForecastPage` lit, et qu'aucune fonction ne
    --     rendait — mesuré, T01 ═══
    'currentBalance',    v_solde,
    'totalIncoming',     v_inflows,
    'totalOutgoing',     v_outflows,
    -- ═══ l'ENGAGEMENT DE PRODUCTION ═══
    'production_material_commitment', v_achat_mat,
    'production_labor_commitment',    v_atelier,
    'production_commitment',          v_achat_mat + v_atelier,
    -- ═══ et le net QUAND ON VEUT LE TENIR COMPTE ═══
    'net_with_production', (v_inflows - v_outflows) - (v_achat_mat + v_atelier)
  );
END $fn$;

COMMENT ON FUNCTION public.cash_flow_forecast(integer) IS
  'Prevision de tresorerie a N jours. Les quatre cles HISTORIQUES (days,
  expected_inflows, expected_outflows, net_forecast) sont INCHANGEES : y ajouter
  l engagement ferait bouger ce que tous les ecrans montrent aujourd hui.
  S y ajoutent : (a) le CONTRAT DE L ECRAN - currentBalance, totalIncoming,
  totalOutgoing, les trois cles que TreasuryForecastPage lit et qu aucune fonction
  ne rendait (mesure : l ecran affichait 0 en toutes circonstances) ;
  (b) l ENGAGEMENT DE PRODUCTION - la matiere a acheter NETTE DU STOCK pour
  les OF ouvertes de l horizon, et les salaires d atelier ;
  (c) net_with_production, pour qui veut inclure l engagement sans que
  personne d autre ne le voie bouger.';
