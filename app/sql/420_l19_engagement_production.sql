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
  v_of        record;
  v_besoin    record;
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
  FOR v_of IN
    SELECT mo.id, mo.cost_labor
      FROM manufacturing_orders mo
     WHERE mo.tenant_id = current_tenant_id()
       AND mo.status IN ('planned', 'in_progress')
       AND mo.bom_id IS NOT NULL
       AND COALESCE(mo.end_date, v_horizon) <= v_horizon
  LOOP
    -- les salaires d'atelier de cette OF
    v_atelier := v_atelier + COALESCE(v_of.cost_labor, 0);

    -- la matière à ACHETER : besoin MOINS ce qui est en stock.
    -- `manufacturing_requirements` rend (produit, quantité, coût
    -- réel, coût standard) — le besoin BRUT.
    --
    -- ⚠️ LE STOCK EST LU SUR LES MOUVEMENTS, ET C'EST MESURÉ.
    -- Les trois sources du dépôt ne concordent pas : mesuré sur la
    -- base neuve, un produit porte `products.stock_quantity = 50`
    -- alors que ses mouvements totalisent 0, et `stock_quantities`
    -- ne suit pas les mouvements (60 lignes pour 625 mouvements).
    -- Lire `stock_quantities` — le réflexe — SURESTIMERAIT donc
    -- l'engagement : on verrait un achat déjà couvert par du stock.
    -- On lit donc les MOUVEMENTS, qui sont la seule vérité
    -- append-only, et c'est aussi ce que la 418 lit pour son coût.
    -- Le désaccord entre les trois tables est un défaut du module
    -- stock, mesuré ici et laissé à son lot : le corriger depuis la
    -- trésorerie serait le corriger ailleurs que là où il vit.
    FOR v_besoin IN
      SELECT r.product_id, r.quantity, r.actual_unit_cost
        FROM manufacturing_requirements(v_of.id, current_tenant_id()) r
    LOOP
      IF COALESCE(v_besoin.actual_unit_cost, 0) > 0 THEN
        v_achat_mat := v_achat_mat
          + GREATEST(0,
              COALESCE(v_besoin.quantity, 0)
              - COALESCE((SELECT SUM(
                            CASE WHEN sm.movement_type = 'in'  THEN  sm.quantity
                                 WHEN sm.movement_type = 'out' THEN -sm.quantity
                                 ELSE 0 END)
                           FROM stock_movements sm
                          WHERE sm.tenant_id = current_tenant_id()
                            AND sm.product_id = v_besoin.product_id
                            AND sm.movement_type IN ('in', 'out')), 0)
            ) * v_besoin.actual_unit_cost;
      END IF;
    END LOOP;
  END LOOP;

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
