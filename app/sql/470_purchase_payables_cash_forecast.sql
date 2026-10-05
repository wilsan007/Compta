-- 470 — purchase_payables_cash_forecast
-- Numéro pris le 2026-10-05T05:45:43.414Z par migration-numero.mjs (ligne « partie 2 (défauts métier) — dernier écrivain au-dessus des chaînages », branche claude/great-ritchie-5f5d6b).
-- ============================================================
-- 470_purchase_payables_cash_forecast.sql — tâche 2.17 :
--   UNE FACTURE D'ACHAT APPROUVÉE ET IMPAYÉE EST UN DÉCAISSEMENT
--   À VENIR
--
-- ⚠️ MESURÉ LE 05/10/2026, SUR BASE NEUVE (328 migrations, 0 erreur)
--
--   `purchase_invoices_status_check` n'admet que draft | sent | viewed |
--   paid | overdue | cancelled. L'approbation pose `approval_status`,
--   le numéro et l'écriture AC — elle ne touche PAS `status` : une
--   facture approuvée et impayée reste `draft / approved / not_paid`
--   (dû 240, mesuré par l'écran). Or `cash_flow_forecast`, le SEUL
--   moteur de prévision du dépôt (420, 422), cherchait la dette
--   fournisseur sous `status IN ('received', 'overdue')` : `received`
--   n'est pas une valeur admise, et aucun chemin ne pose `overdue` sur
--   une facture d'achat. Les sorties prévues valaient donc 0, toujours.
--
--   Rouges avant (suite 470) : T01 `sorties prévues=0 (120 attendu)`,
--   T03 `0 (70 attendu)`, T05 `à 90 j=0 (120 attendu)`, T07 tout à 0.
--   Et par l'écran (09_dash, D08 → D11) : tableau, ligne de temps,
--   graphique — tous muets sur une facture approuvée de 240.
--
-- LE CRITÈRE — un seul, pour le moteur et pour ses lecteurs :
--     approval_status = 'approved'   la dette est née (écriture AC)
--     status <> 'cancelled'          et n'a pas été annulée
--     amount_due > 0                 et il reste quelque chose à payer
--   montant = amount_due (le reste dû, pas le total).
--   Les lecteurs de l'écran sont corrigés dans le même commit :
--   `getTreasuryDashboard` et `getTreasuryForecast` portent ce critère
--   à l'identique ; `getDashboardChartData` (les DÉPENSES de l'année,
--   réglées ou non) en porte les deux premières lignes et lit `total`.
--   Ce qui les tient ensemble : les verdicts d'écran D08 → D11, qui
--   confrontent chaque lecteur à la base et au moteur.
--
-- ⚠️ POURQUOI 470 ET NON 35x. La plage de la partie 2 est `340` → `369`,
--   mais le runner applique dans l'ordre NUMÉRIQUE et la 420 fait
--   `CREATE OR REPLACE` de cette même fonction : écrite en 35x, cette
--   correction serait ÉCRASÉE par la 420 sur toute base neuve (la leçon
--   de la 327 → 419, NUMEROTATION-MIGRATIONS.md : « un numéro décide du
--   dernier écrivain »). Plage `470` → `474` inscrite pour cela.
--
-- CE QUI NE CHANGE PAS : le corps de la 420 est repris À L'IDENTIQUE —
--   les entrées (factures clients), l'engagement de production, le
--   solde de la classe 5, les onze clés rendues, `SECURITY DEFINER` et
--   `current_tenant_id()` (porte G4). Seul le filtre des sorties change.
--   Les droits d'exécution sont ceux de la fonction remplacée.
--
-- Rejouable : `CREATE OR REPLACE`, aucun changement de schéma.
-- ============================================================

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

  -- ═══ LE PRÉVISIONNEL HISTORIQUE — les entrées, inchangées ═══
  SELECT COALESCE(SUM(amount_due), 0) INTO v_inflows
    FROM invoices
   WHERE tenant_id = current_tenant_id()
     AND status IN ('sent', 'overdue')
     AND due_date <= v_horizon;

  -- 470 (tâche 2.17) : la dette fournisseur se lit sur L'APPROBATION et le
  -- RESTE DÛ, plus sur `status` — `received` n'existe pas au CHECK, et une
  -- facture approuvée impayée reste `draft`. Même critère que les lecteurs
  -- de l'écran (`getTreasuryDashboard`, `getTreasuryForecast`).
  SELECT COALESCE(SUM(amount_due), 0) INTO v_outflows
    FROM purchase_invoices
   WHERE tenant_id = current_tenant_id()
     AND approval_status = 'approved'
     AND status <> 'cancelled'
     AND amount_due > 0
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
  personne d autre ne le voie bouger.
  470 : les sorties sont le RESTE DU des factures d achat APPROUVEES et non
  annulees (approval_status = approved, status <> cancelled, amount_due > 0) -
  plus un statut received qui n existe pas.';
