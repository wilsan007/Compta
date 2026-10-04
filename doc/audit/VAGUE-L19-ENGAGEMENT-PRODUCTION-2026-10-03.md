# L19 — L'engagement de production alimente le prévisionnel

**Migration** `420_l19_engagement_production.sql` · **Suite** `420_l19_engagement_production_tests.sql`
· **Date** 03/10/2026 · **Branche** `partie-5-integrite-chainages`

> Lot **L19** du plan §5 Phase F — « l'engagement de production alimente
> le prévisionnel de trésorerie ». Le référentiel §A.4 nomme
> `production ↔ trésorerie` parmi les **12 couples de modules VIDE** :
> « aucune visibilité de trésorerie sur l'engagement de production
> (achats déclenchés par le MRP, salaires d'atelier) ».

---

## 1. Les trois défauts, mesurés avant (base neuve, 283 migrations)

| # | Mesure | Chiffre |
|---|---|---|
| D1 | Tables de production lues par `cash_flow_forecast` | **0** |
| D2 | Clés communes entre le JSON rendu et ce que `TreasuryForecastPage` lit | **0 sur 3** |
| D3 | Clés du mock de `e2e-business-workflows.test.ts:535` réellement employées | **0** |

**D1** — `cash_flow_forecast`, la **seule** prévision de trésorerie du dépôt,
tient en deux requêtes : factures clients non payées, factures
fournisseurs non payées. Le MRP n'est pas appelé, `manufacturing_orders`
pas lu — alors que `cost_material` et `cost_labor` **existent** sur l'OF.

**D2 est le défaut le plus visible.** La fonction rend
`{days, net_forecast, expected_inflows, expected_outflows}` ;
`TreasuryForecastPage` lit `{currentBalance, totalIncoming,
totalOutgoing}`. **Zéro clé commune** : le solde projeté, les entrées et
les sorties de l'écran valent 0 en toutes circonstances. Un écran entier
qui affiche des zéros sans le dire.

**D3 est ce qui a laissé passer D2.** Le test censé le prendre est un
**mock** : il simule la réponse avec un JSON *inventé* (`current_balance`,
`net_flow`, `projected_balance`) — des clés que ni la fonction ni l'écran
n'emploient. Vert, et ne prouvant rien.

## 2. Ce que la 420 pose

**Une seule fonction, complétée** — `cash_flow_forecast` est modifiée, pas
dupliquée. Deux prévisions de trésorerie seraient deux vérités (faute W5).

- **Le contrat de l'écran** : `currentBalance`, `totalIncoming`,
  `totalOutgoing` sont rendues, et portent des **nombres**.
- **L'engagement de production** : `production_material_commitment` (la
  matière à acheter, **nette du stock**), `production_labor_commitment`
  (les salaires d'atelier), `production_commitment`.
- **`net_with_production`** : le net quand on veut inclure l'engagement.

## 3. Trois décisions qui engagent l'existant

### 3.1 Les quatre clés historiques ne changent pas de valeur

`net_forecast` reste `inflows − outflows`. Y ajouter l'engagement ferait
bouger ce que **tous** les écrans montrent aujourd'hui, sans qu'aucune
décision produit l'ait demandé. L'engagement est rendu **à côté**. C'est
un choix de gouvernance, écrit pour être débattu — T02 le prouve.

### 3.2 Le stock est lu sur les MOUVEMENTS, et c'est mesuré

Les trois sources de stock du dépôt **ne concordent pas** : sur la base
neuve, un produit porte `products.stock_quantity = 50` alors que ses
mouvements totalisent 0, et `stock_quantities` ne suit pas les mouvements
(**60 lignes pour 625 mouvements**). Lire `stock_quantities` — le
réflexe — **surestimerait** l'engagement : on verrait un achat déjà couvert.

On lit donc les mouvements, seule vérité *append-only* — c'est aussi ce que
la 418 lit pour son coût. Le désaccord entre les trois tables est un défaut
du **module stock**, mesuré ici et laissé à son lot : le corriger depuis la
trésorerie serait le corriger ailleurs que là où il vit.

### 3.3 L'horizon borne l'engagement

Une OF qui se termine dans dix mois n'engage pas la trésorerie des trente
prochains jours. La restriction rend le chiffre utile ; ce n'est pas un
défaut de précision.

## 4. Résultats

**Suite 420 — 8/8 verts** (base neuve `l19_ci`, 285 migrations, 0 erreur) :

| | Scénario | Chiffre mesuré |
|---|---|---|
| T01 | le contrat des clés de l'écran | **aucune** clé manquante, **aucune** non numérique |
| T02 | les clés historiques | `net_forecast = 0`, `days = 30` — inchangées |
| T03 | l'engagement matière | **8** (2 composants × 4 €) |
| T04 | net du stock | stock 50 pour un besoin de 2 → **0** |
| T05 | les salaires d'atelier | **750**, engagement total **758** |
| T06 | le cycle | 300 → **0** après clôture de l'OF |
| T07 | l'isolation | rendu **9008** (celui de B) ; celui de A (≈ 408) **absent** |
| T08 | le surcoût | **p95 = 3,712 ms** pour 50 ms, 60 OF ouvertes (rejoué à chaque exécution : le nombre s'affiche dans la sortie CI) |

**Non-régression, base neuve, ordre de la CI** — **285 migrations, 0 erreur**,
**23 suites vertes, 256 verdicts, 0 rouge**. `tsc` **0** · Vitest du parcours
**30/30** (le mock mensonger réécrit sur les vraies clés).

## 5. Deux portes sont rouges, et ce n'est PAS cette migration

Elles viennent du travail **d'une autre session** sur la même branche, et
je les signale plutôt que de les contourner :

- **G1 (`check_bt_grid`)** : `tables_tenant`, `rls_sans_force`,
  `sans_index_societe` et `moins_de_4_commandes` montent **chacun de 1**.
  La table en trop est **`metric_definitions`**, du commit `68417fe`
  (`461_metric_definitions.sql`). Mesuré par comparaison de deux bases :
  ma 420 **n'ajoute aucune table** (un `CREATE OR REPLACE FUNCTION`).
  Et la correction n'est **pas** évidente : forcer la RLS de
  `metric_definitions` ou relever le plafond est une **décision de
  sécurité** sur la table de quelqu'un d'autre. Je ne la prends pas.
- **G5 (`check-test-suites`)** : `462_chain_expliquer_montant_tests.sql`
  n'est jouée par aucune étape. Le fichier est **non commité** et n'est
  pas le mien.

## 6. Limites dites

1. **Le budget de §3.3 tient jusqu'à ~300 OF ouvertes** — mesuré, et
   c'est une **montée en charge linéaire**, pas un plafond de sécurité :

   | OF ouvertes | 60 | 200 | 400 |
   |---|---|---|---|
   | p95 mesuré | **3,26 ms** | 14,86 ms | **64,55 ms** |

   ⚠️ **La première version de cette preuve annonçait une limite de
   60 OF et l'attribuait à l'explosion de nomenclature. C'était FAUX,
   et la mesure l'a démoli** : l'explosion ne coûte que **2,4 ms**,
   le scan de stock **0,08 ms**, et les trois requêtes historiques
   0,10 ms chacune. Les 29 ms manquants étaient les **soixante
   allers-retours SPI** de la double boucle plpgsql. Écrit en
   ensemble (une jointure latérale), le même calcul rend les mêmes
   nombres **9,6× plus vite**. Une limite qu'on annonce sans avoir
   mesuré où elle vient, c'est une excuse ; celle-ci est un relevé.
2. **`net_forecast` n'inclut pas l'engagement.** Choix explicite (§3.1) ;
   `net_with_production` est là pour qui le veut.
3. **Aucun enchaînement automatique.** L'engagement est une LECTURE ; il
   ne déclenche pas d'achat — le MRP existe déjà pour ça.
4. **Le solde de trésorerie** est lu sur les lignes de la classe `5`. Une
   société sans écriture vaut 0 — vrai, pas un défaut d'affichage.
5. **Les trois tables de stock se contredisent** (`products.stock_quantity`,
   `stock_quantities`, `stock_movements`). On lit les mouvements, seule
   vérité append-only. Le désaccord lui-même est un défaut du module stock,
   mesuré ici et **laissé à son lot** : le corriger depuis la trésorerie
   serait le corriger ailleurs que là où il vit.

## 7. Suite

Le couple `production ↔ trésorerie` est ouvert : l'engagement est visible
dans le prévisionnel, et l'écran qui le montrait en zéros reçoit enfin les
nombres qu'il lit. Restent **L20** (régénération), **L23-b/c**, et la
tranche 2 de L18 (imputation analytique).