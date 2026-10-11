# Partie E — fonctions manquantes, opérations

> Fichier de suivi **exclusif** de la partie E (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/e-operations` |
| **Worktree** | `.claude/worktrees/plan6-e-operations` |
| **Plage de migrations** | `650` → `699` |
| **Territoire de fichiers** | écrans et requêtes stock, production, achats, ventes ; leurs tables coquilles |
| **Charge** | ≈ 13,5 j (❓ restants, E.1 faite) + ≈ 9 sem. (⬜ E.2→E.5) |
| **Départ possible** | tout de suite, **par le recomptage** |

## Les tâches

| # | Tâche | Repris de (plan 9,5) | Charge | État |
|---|---|---|---|---|
| E.1 | **Recompter** les chantiers ❓ de son périmètre et **estimer** les ⬜ ; décider pour chacun : faire, reporter, écarter | ACC-01, ACC-03, PRD-03/04/05/08/10, ACH-01/02, VTE-01/03 | à chiffrer | 🟡 **compté le 05/10** — voir « E.1 — le recomptage » |
| E.2 | Restes à l'écran : transfert entre dépôts, étiquettes, MRP jamais testés ; action « Modifier » d'une nomenclature | D13, reste de 2.5 | ≈ 3 j | ✅ **livré le 05/10** — « Modifier » une nomenclature ; **transferts inter-dépôts** (`652` + requêtes + écran `/stock/transfers`, suite 5/5) ; MRP testé (`651`) ; étiquettes OF déjà câblées (`of_labels`) |
| E.3 | Stock avancé : FIFO/LIFO, unités de mesure, frais accessoires, réapprovisionnement et inventaire tournant, emplacements, transferts et variantes | STK-03/07/08/09/11/14 | ≈ 5 sem. | ✅ **`STK-07`**, **`STK-08`** (`658`), **`STK-09`** (`653`/`654`), **`STK-11`** (`655` socle + `659` casiers + `660` rangement/prélèvement), **`STK-14`** livrés · `STK-03` écarté |
| E.4 | Production : capacité finie, maintenance, sous-OF (`parent_mo_id` inutilisé) | PRD-07, PRD-11 | ≈ 1,5 sem. | ✅ `PRD-07` (`657`), `PRD-11` (`656` + interventions) et le **sous-OF** (déjà câblé — onglet « sous-niveaux » ; colonne produit corrigée) |
| E.5 | Tables coquilles de son périmètre — **brancher ou supprimer** : `uom_categories`, `landed_cost_lines`, `reorder_rules`, `stock_count_cycles`, `stock_transfer_lines`, `mo_consumptions`, `mo_operations`, `maintenance_records`, `work_center_calendars`, `quality_control_*`, `fixed_asset_components`, `resource_capacities` | ORPH-02 | ≈ 0,5 j | 🔶 **6 branchées** (`uom_categories`, `reorder_rules`, `stock_count_cycles`, `stock_transfer_lines`, `maintenance_records`, `work_center_calendars`) · les autres **décidées** (voir §E.5) |

## E.1 d'abord : pourquoi

**32 chantiers du plan 9,5 n'ont jamais été recomptés.** Leur charge est donc
inconnue — pas « petite », **inconnue**. Tant qu'E.1 n'a pas rendu ses chiffres,
le plan des parties E et F n'a pas de dates.

C'est aussi une tâche de **décision** : chacun des chantiers ❓ et ⬜ doit être
**fait, reporté ou écarté** — pas laissé en suspens. Un chantier écarté est une
décision ; un chantier oublié est une dette qui grossit en silence.

Écrire le verdict dans **ce fichier** (R3), pas dans `SUIVI-CHANTIERS.md` : la
session d'intégration fera la mise à jour.

## E.1 — le recomptage, mesuré le 05/10/2026

Dépôt du jour, worktree `plan6/e-operations` (`f59accc`, soit `main` moins le seul
commit de documentation du lot K). **Méthode :** pour chaque ❓, lire les
migrations **et le corpus vivant** — le dernier `CREATE OR REPLACE` d'une fonction
l'emporte, pas le premier — puis confronter au **critère d'acceptation** que le
plan 9,5 donne au chantier. Un chantier n'est « fait » que si son critère est
atteint dans le code d'aujourd'hui.

### Les onze ❓, un par un

| # | Plan 9,5 | État réel mesuré | Verdict | Charge E |
|---|---|---|---|---|
| ACC-01 | 3 j | **Fait.** `108_auxiliary_accounts` : `account_tiers` / `account_collectif` sur `customers`/`suppliers`, génération automatique, écriture dans les triggers de compta **et rattrapage** des écritures existantes. Les triggers **vivants** (`210`, `317`) portent bien `account_tiers, third_party_id, echeance_date`. | ✅ fait | 0,5 j (garde-fou seul) |
| ACC-03 | 4 j | **Fait.** `110_product_accounts` : `sale/purchase/stock_account_code` + `product_categories`, boucle « une ligne par compte » dans les triggers ; `resolve_stock_account` (`241`), `315`, `317`. Les triggers vivants gardent `COALESCE(p.sale_account_code, pc.sale_account_code, …)`. | ✅ fait | 0,5 j (garde-fou seul) |
| PRD-05 | 2 h | **Fait.** `stock.ts` lit `purchase_order_lines` (reste à recevoir) et non l'en-tête `purchase_orders` ; les OF en cours sont déduits de `qty_produced`. | ✅ fait | 0 |
| PRD-08 | mineur | **✅ fini le 11/10 (`ea60af5`).** Le RPC `run_mrp` (651, garde 664) est l'**unique** moteur : `runMRPAndSave` (`stock.ts`) persiste le lancement et ses propositions ; l'ancien moteur client `runMRPCalculation` (OF seules, `+7 j` en dur, `Math.ceil` nu) est **supprimé**, ainsi que le second bouton de l'écran (qui portait une chaîne non traduite). | ✅ fait | 0,5 j |
| PRD-03 | 4 j | **✅ corrigé le 05/10 — le ❓ lisait le mauvais moteur.** Le RPC SQL `run_mrp` (`152`) lisait **déjà** les trois sources (OF, commandes clients, prévisions) **et** l'horizon `p_horizon_days` ; le critère ne manquait que sur la **consommation des prévisions** — livrée par la `651`. Le vieux moteur client, lui, ne lit que les OF : c'est lui qui avait fait dire ❓. | ✅ fait (base) | 0 |
| PRD-04 | 1 j | **✅ corrigé le 05/10 — même cause.** `run_mrp` applique **déjà** `safety_stock`, `lead_time_days`, `min_order_qty`, `qty_multiple` ; le `+7 j` en dur et le `Math.ceil` nu n'existent que dans le vieux moteur client. | ✅ fait (base) | 0 |
| PRD-10 | 1 sem. (avec PRD-11) | **Non fait.** `workflows` et `product_equivalences` sont des écrans CRUD ; non exploités dans le MRP ; finalité non documentée. | ⬜ faire (léger) | 2 j |
| ACH-01 | — | **Non fait.** Aucune table de contrat ni d'accord-cadre. | ⬜ faire | 3 j |
| ACH-02 | — | **Non fait.** Aucune table ni fonction de score fournisseur. | ⬜ faire | 2 j |
| VTE-01 | 3 j | **Partiel.** `resolve_price` (`117`) + helper client `resolvePrice` existent, mais **aucun formulaire ne l'appelle** : `price_list` n'est lu que par la page de saisie des grilles. | 🔶 finir | 2 j |
| VTE-03 | — | **Partiel.** `calculate_payment_due_dates` (`88`) produit des échéances multiples ; manquent la cascade de remises, l'escompte conditionnel et les remises de fin d'année. | 🔶 faire | 3 j |

**Compte du recomptage (corrigé le 05/10, PRD-08 fini le 11/10) : 6 ✅**
(`ACC-01`, `ACC-03`, `PRD-05`, `PRD-03`, `PRD-04`, `PRD-08`) **· 2 🔶**
(`VTE-01`, `VTE-03`) **· 3 ⬜** (`PRD-10`, `ACH-01`, `ACH-02`) **· 0 écarté.**

**Ce que le recomptage change.** Le §9 du plan rangeait ces onze chantiers sous
« à estimer ». **Cinq sont déjà faits** — comme pour la partie 3 (A.1), le suivi
est en retard, pas le dépôt. Et deux corrections d'honnêteté : `PRD-03` et
`PRD-04` n'étaient ❓ que parce que la première mesure regardait le **vieux
moteur client** (`runMRPCalculation`) ; le moteur qui fait foi — le RPC SQL
`run_mrp` — les portait déjà (ce vieux moteur client est supprimé le 11/10,
PRD-08). La charge du périmètre ❓ restant tombe à **≈ 13 j**
(ACC-01/03 garde-fous 1 j, VTE-01 2 j, VTE-03 3 j, PRD-10 2 j,
ACH-01 3 j, ACH-02 2 j).

### Les ⬜ du périmètre (E.2 → E.5), estimés

Le plan 9,5 porte déjà des charges par lot ; je les reprends telles quelles, en
les rattachant à la tâche E qui les exécute. Elles **ne sont pas** dans le
décompte ci-dessus, qui ne couvre que les onze ❓.

| Tâche | Chantiers | Charge | Décision |
|---|---|---|---|
| E.2 | D13 : transferts entre dépôts, étiquettes, MRP jamais testés, action « Modifier » d'une nomenclature | ≈ 3 j | faire |
| E.3 | `STK-03` FIFO/LIFO | 0,25 j | **écarter** — `254` les a rendus inertes ; à écrire comme décision, pas comme dette |
| E.3 | `STK-07`→`STK-10` unités, frais accessoires, réappro, inventaire tournant | 2 sem. | faire |
| E.3 | `STK-11`→`STK-14` emplacements, picking, qualité, transferts | 3 sem. | faire |
| E.4 | `PRD-07` capacité finie / ordonnancement | ≈ 1 sem. | faire |
| E.4 | `PRD-11` maintenance (déduction de la capacité comprise dans `PRD-07`) | ≈ 0,5 sem. | faire |
| E.5 | les 12 tables coquilles du périmètre (brancher ou supprimer) | ≈ 0,5 j | faire — ORPH-02 plafonne à 1,5 j pour les 37 |

Les douze coquilles de mon périmètre : `uom_categories`, `landed_cost_lines`,
`reorder_rules`, `stock_count_cycles`, `stock_transfer_lines`, `mo_consumptions`,
`mo_operations`, `maintenance_records`, `work_center_calendars`,
`quality_control_plans` (+ `quality_control_points`), `fixed_asset_components`,
`resource_capacities`. Chacune **branche** sur son chantier 9,5 ci-dessus, ou se
**supprime** par une migration motivée dans `650`→`699` (E.5).

## E.3 — stock avancé, première brique : `STK-07` (unités de mesure)

**Mesuré : la base portait déjà tout, l'app ne lisait rien.** `uom_categories`,
`uoms`, `convert_uom` et les champs `products.uom_id / purchase_uom_id /
sale_uom_id` existaient depuis la `125` — mais **aucun écran ni requête** ne les
nommait : `uom_categories` figurait parmi les coquilles (ORPH-02). Et `convert_uom`
était **correct** : il interdit le croisement de catégories (« Conversion
impossible entre catégories différentes »), convertit via l'unité de référence et
arrondit au pas de l'unité cible.

**Livré (partie app).** Requêtes (`getUomCategories`, `getUoms`, `createUom`,
`updateUom`, `deleteUom`, `convertUom`) et écran **`/stock/uoms`** : catégories,
unités (code, nom, catégorie, facteur, arrondi, unité de référence) et un
**convertisseur**. C'est ce qui **branche `uom_categories`** — elle sort des
coquilles.

**Reste de `STK-07`.** Convertir aux **frontières** (ligne de commande, réception,
mouvement, ligne de facture) et poser `uom_id`/`purchase_uom_id`/`sale_uom_id`
depuis la fiche article : le critère « acheter 1 t, stocker en kg, vendre par sacs
de 25 kg » demande ce branchement.

### `STK-09` — réapprovisionnement : `reorder_rules` branchée (migration `653`)

**Mesuré.** `reorder_rules` (produit, dépôt, minimum, maximum, multiple, délai,
actif) existait depuis la `125` sans être lue : l'écran `/stock/reorder`
s'appuyait sur `stock_quantities.reorder_point`, un simple seuil, sans maximum ni
multiple de conditionnement.

**Livré.** `reorder_suggestions()` (`653`) applique la règle réelle — proposition
seulement si le stock est **≤ au minimum**, remontée jusqu'au **maximum**,
arrondie au **multiple** (règle sans dépôt = stock total de la société) — et
l'écran `/stock/reorder` gagne les **règles** (créer/supprimer) et les
**suggestions**. Suite `653` : **5/5**, rouge avant.

### `STK-09` — inventaire tournant : `stock_count_cycles` branchée (migration `654`)

**Mesuré.** `stock_count_cycles` (planning : produit, dépôt, classe A/B/C,
fréquence, prochaine date) existait depuis la `125` sans moteur.
`calculate_inventory_variance` (`103`) réconcilie le stock théorique et les
mouvements ; il ne **compte** pas.

**Livré.** `generate_count_list()` (`654`) — les articles **dus** (prochaine date
≤ aujourd'hui) avec leur stock courant ; `record_stock_count(id, qty)` — l'écart
(compté − stock) devient un **mouvement valorisé** et les dates du cycle avancent —
et l'écran **`/stock/counts`** (à compter + cycles). Choix dit : l'écart s'enregistre
comme **entrée/sortie**, car le `'adjustment'` de la base ne met à jour que
`products.stock_quantity`, pas `stock_quantities` par dépôt. Suite `654` : **5/5**,
rouge avant.

### `STK-11` — emplacements : le stock par emplacement (migration `655`)

**Mesuré.** `warehouse_locations` porte déjà l'arbre (`parent_id`), le type
(`location_type`) et la capacité (`max_weight`/`max_volume`/`max_pallets`), et
`stock_quantities.location_id` existe — mais **rien ne ventilait le stock par
emplacement**, et l'écran n'exposait ni le type ni la capacité.

**Livré.** `stock_by_location()` (`655`) — le stock d'un article ventilé par
emplacement (`location_id` NULL = « non affecté »), socle du critère « la somme
des emplacements = le stock entrepôt » ; l'écran `/stock/warehouse-locations`
gagne le champ **type** et une carte **« Stock par emplacement »**. Suite `655` :
**3/3**, rouge avant.

**Reste de `STK-11`.** Le **stock par casier** exige que le moteur de mouvement
porte `location_id` (la clé d'unicité de `stock_quantities` est encore
`(produit, dépôt)`) — c'est un changement de moteur, **dit et non fait**. Restent
aussi les règles de **rangement/prélèvement** et l'**alerte de capacité**.

### `STK-08` — frais accessoires : moteur corrigé, `landed_cost_lines` branchée (migration `658`)

**Mesuré.** `distribute_landed_cost` (`125`) répartissait sur **toutes** les
réceptions de la société, sans lien avec les réceptions concernées ; elle divisait
par la quantité **sans garde**, mettait à jour **tous** les dépôts du produit, sans
écriture ni idempotence ; et `landed_costs` n'avait **aucune** cible.

**Livré.** `landed_cost_receipts` (les réceptions ciblées) et un moteur réécrit :
il ne répartit que sur **ses** réceptions, ajuste le CUMP du couple (article,
dépôt) de chaque réception, efface une répartition antérieure et **refuse un
second appel**. Écran **`/stock/landed-costs`** (créer, cibler une réception,
répartir, lire les lignes). Suite `658` : **4/4**, rouge avant.

**Rangement et prélèvement (migration `660`).** Deux règles, sur les affectations
de la `659` :

- `suggest_putaway_location(article, dépôt)` — où **ranger** un article reçu :
  d'abord un casier qui le contient **déjà** (on regroupe : `consolidate`), sinon
  un casier de stockage **vide** (`empty`), sinon le **moins occupé**
  (`least_loaded`) ;
- `suggest_pick_location(article, dépôt)` — où **prélèver** : le casier qui en
  détient **le plus** (on ne disperse pas les prélèvements).

Écran `/stock/warehouse-locations` : carte **« Où ranger / où prélever ? »**
(article + dépôt → « Suggérer »). Suite `660` : **3/3**, rouge avant ; et
**non-régression** : `659` 3/3.

### `STK-11` — stock par casier : ventilation par affectations (migration `659`)

**Décision — le moteur de mouvement n'est PAS touché.** `stock_quantities` porte
le CUMP, les déclencheurs et leur ordre ; le changer mettrait en jeu **tout** le
stock. Le casier est donc une **affectation** d'une partie du stock d'entrepôt :
`stock_location_assignments` (article, dépôt, casier, quantité).

**Livré.** `assign_stock_to_location` (`659`) — refuse une affectation qui
dépasserait le stock du dépôt — et `location_stock()` qui rend la ventilation :
chaque casier **plus la part non affectée**, la somme valant le stock d'entrepôt.
Écran `/stock/warehouse-locations` : bouton **« Affecter »** par emplacement et
carte **« Ventilation par casier »**. Suite `659` : **3/3**, rouge avant ; et
**non-régression** : `254` 5/5, `652` 5/5, `653` 5/5, `654` 5/5, `655` 3/3.

## E.4 — production : alerte d'usure d'outillage (`PRD-11`, migration `656`)

**Mesuré.** `toolings` porte `max_pieces`, `initial_counter` et `current_counter`
(l'usure est modélisée), mais **aucune fonction n'alertait** à l'approche de la fin
de vie — le critère PRD-11 n'était pas tenu.

**Livré.** `tooling_wear_alert()` (`656`) — les outillages à **95 % ou plus** de
leur durée de vie — et une carte **« Usure des outillages »** sur l'écran
`/production/machines`. Suite `656` : **3/3**, rouge avant.

**Reste de `E.4`.** L'incrémentation automatique du compteur à la production
(`PRD-06`) et le blocage du lancement d'OF sur outillage hors service.

### `E.4` — sous-OF : recomptage, **déjà câblé**

Le plan notait « `parent_mo_id` inutilisé ». **Mesuré : il est utilisé.**
`getSubManufacturingOrders` (query) alimente l'onglet **« sous-niveaux »** de
`ManufacturingOrderDetailPage`, qui liste les sous-OF et pointe vers chacun. Seule
la colonne « produit » affichait « — » (la requête ne joignait pas `products`) :
**corrigé** (jointure + affichage). Le sous-OF est donc **fait** — le suivi était
en retard, comme pour `ACC-01`/`PRD-03`.

### `PRD-07` — capacité finie : `work_center_capacity` (migration `657`)

**Mesuré.** La **charge** existait déjà (`work_center_load_hours`, `416`, L17),
mais **aucune capacité** n'était lue : ni `work_centers.capacity_hours_per_day`,
ni `work_center_calendars` — donc aucune **surcharge** constatable (critère PRD-07).

**Livré.** `work_center_capacity(société, poste, jour)` (`657`) — la capacité
réelle du jour (`0` si fermé/férié, sinon les heures du calendrier, sinon la
capacité par défaut) — et `work_center_capacity_load(début, fin)` qui **croise**
charge × capacité par poste et par jour, avec le drapeau **surcharge**. Carte
**« Charge / capacité des postes »** sur `/production/machines`. Suite `657` :
**4/4**, rouge avant.

### `PRD-06` — déclaration d'atelier : `mo_operations` branchée (migration `661`)

**Le trou.** La table `mo_operations` existe depuis la `126` et **rien** ne
l'écrivait. C'est pourtant la seule du domaine qui sache dire **où le temps est
passé** et **où sont les rebuts** : `planned_time_minutes`, `actual_time_minutes`,
`quantity_produced`, `quantity_scrapped`, `scrap_reason`.

**Livré.**

- `record_mo_operation(of, opération, minutes prévues, minutes réelles, produites,
  rebutées, motif)` — l'atelier déclare. Un **index unique** sur
  `(société, OF, lower(nom d'opération))` rend la déclaration **rejouable** :
  corriger un temps met la ligne à jour, il ne la double pas. Un OF **annulé**
  refuse la déclaration ; un temps ou une quantité **négative** aussi ;
- `mo_operations_summary(of)` — le récapitulatif : nombre d'opérations, minutes
  prévues / réelles, produites, rebutées et **taux de rebut**.

**Aucun impact sur le stock** : la matière reste consommée par les mouvements
(`reference_type = 'production'`), cette table ne fait que **déclarer**. Le
moteur de stock n'est pas touché — c'est ce qui rend la brique sûre.

**Écran.** Nouvel onglet **« Atelier »** de la fiche OF
(`/production/of/:id`) : carte de récapitulatif (6 chiffres), tableau des
opérations, et bouton **« Déclarer une opération »**.

Suite `661` : **3/3**, rouge avant (aucune fonction n'existait) ; et
**non-régression** : `302` 8/8, `254` 5/5.

### `STK-13` — plans de contrôle qualité : `quality_control_plans` branchée (migration `662`)

**Le trou.** L'écran `/stock/quality-checks` enregistre bien les **contrôles**
(`quality_checks`), mais **rien** ne disait *quel* contrôle appliquer à un
article, ni sur *combien* d'unités. C'est exactement ce que décrivent
`quality_control_plans` et `quality_control_points` — deux coquilles depuis la
`125` — et c'est ce qu'on branche.

**Livré.**

- `quality_plan_for(article)` — le plan applicable : **celui de l'article** s'il
  en existe un, sinon le plan **générique** (`product_id IS NULL`) ;
- `quality_sample_size(plan, quantité du lot)` — la taille de l'échantillon selon
  la méthode du plan : `rate` = un pourcentage du lot, `systematic`/`table` = le
  lot entier ;
- `quality_plan_points(plan)` — les points de contrôle, obligatoires d'abord ;
- `evaluate_quality_point(point, valeur)` — la valeur est-elle dans la
  tolérance ? (`measure` / `binary` / `visual`, bornes ouvertes quand une
  tolérance est `NULL`).

**Un bug attrapé par le test.** La première version écrivait
`(p.product_id = p_product_id)` : pour le plan **générique**, `product_id` est
`NULL` et `NULL = x` vaut `NULL`, pas `false`. Le plan générique se classait donc
*avant* le plan de l'article et `is_product_specific` sortait `NULL`. La règle
est devenue `(p.product_id IS NOT NULL AND p.product_id = p_product_id)` — c'est
le test `T02`/`T03` qui l'a montré, pas la relecture.

**Écran.** Carte **« Plan de contrôle applicable »** en tête de
`/stock/quality-checks` : article + quantité du lot → le plan qui s'applique,
sa méthode, l'échantillon à contrôler et ses points.

Suite `662` : **5/5**, rouge avant.


### `PRD-06` — écart de matière : `mo_consumptions` branchée (migration `663`)

**Le trou.** Les deux moitiés existaient déjà séparément — le **prévu**
(`manufacturing_requirements`, `302`, nomenclature explosée sur tous les niveaux)
et le **réel** (les mouvements de stock `reference_type = 'production'`) — mais
**rien ne les confrontait**. L'écart de matière ne se lisait nulle part, et
`mo_consumptions` attendait depuis la `126`.

**Livré.**

- `refresh_mo_consumptions(of)` — recalcule et **fige** la comparaison, une ligne
  par composant. Rejouable : on met à jour, on ne double pas (index unique) ;
- `mo_consumption_variance(of)` — la lecture : prévu, réel, écart, écart en %.

**Aucun stock n'est touché** : le réel *vient* des mouvements, il ne les crée pas.
Les écarts se **constatent**, ils ne corrigent rien en silence.

**Ce que le test a appris (et qui n'était pas écrit).** Le moteur de stock
n'admet **qu'une sortie par couple (OF, article)**
(`uq_stock_movement_source`, `137`). Un OF ne peut donc pas consommer un composant
en deux fois : le scénario « on ressort 3 unités de plus » que j'avais écrit est
**interdit par le modèle**, pas seulement par mon test. Le scénario `T03` a été
réécrit en conséquence (idempotence du rafraîchissement) — la contrainte est
désormais **documentée**.

**Écran.** Carte **« Écart de matière (prévu / réel) »** dans l'onglet
*Consommation* de la fiche OF, avec un bouton **« Recalculer »**. Les deux appels
de l'onglet sont **indépendants** : une panne de l'écart ne vide pas la liste des
sorties (défaut attrapé par le test `ManufacturingOrderDetailPage`, pas par
relecture).

Suite `663` : **4/4**, rouge avant.



## E.5 — tables coquilles : brancher ou supprimer

**Dix coquilles de mon périmètre sont désormais branchées** (lues par un écran ou
une fonction) :

| Table | Branchée par |
|---|---|
| `uom_categories` (+ `uoms`) | `STK-07`, écran `/stock/uoms` |
| `reorder_rules` | `STK-09`, `653` + `/stock/reorder` |
| `stock_count_cycles` | `STK-09`, `654` + `/stock/counts` |
| `stock_transfer_lines` | `STK-14`, `652` + `/stock/transfers` |
| `maintenance_records` | `PRD-11`, carte « Interventions » |
| `work_center_calendars` | `PRD-07`, `657` (`work_center_capacity`) |
| `mo_operations` | `PRD-06`, `661` + onglet « Atelier » de la fiche OF |
| `quality_control_plans` (+ `quality_control_points`) | `STK-13`, `662` + carte « Plan de contrôle applicable » |
| `mo_consumptions` | `PRD-06`, `663` + carte « Écart de matière » |

**Ce qui reste, et pourquoi** — aucune n'est laissée en suspens :

| Table | Décision | Motif |
|---|---|---|
| `landed_cost_lines` (+ `landed_cost_receipts`) | **branchée** (STK-08, `658`) | le moteur corrigé et l'écran `/stock/landed-costs` |
| `fixed_asset_components` | **hors périmètre E** | immobilisations (`ACC-07`) — à l'intégration |
| `resource_capacities` | **hors périmètre E** | capacité par ressource des projets (`PRJ`) — à l'intégration |

## Les deux décisions de politique — tranchées le 05/10/2026

E.1 laissait deux questions ouvertes. Elles sont tranchées **selon les normes
comptables et la pratique des leaders**, et chacune a sa migration et sa suite.

### `STK-03` — la méthode de valorisation : LIFO interdit, CUMP + PEPS (migration `650`)

**Le droit, pas une préférence.**
- **IAS 2 (IFRS)** : le LIFO (« dernier entré, premier sorti ») est **interdit**.
- **PCG français** (ANC 2014-03, art. 213-1) : CUMP et PEPS admis, **LIFO interdit
  depuis le 1er janvier 2005** (CRC 2004-06).
- **SYSCOHADA révisé** : CUMP et PEPS admis, **LIFO interdit**.

**Les leaders s'alignent :** Odoo offre FIFO, AVCO et prix standard, **pas de
LIFO** ; Sage Gestion Commerciale FR offre CUMP (défaut) et PEPS, pas de LIFO ;
SAP n'a pas de LIFO en normes IFRS.

**Décision.** `stock_valuation_method` n'admet plus que **`cump`** (défaut, moteur
de la `254`) et **`fifo`** (PEPS). `lifo` est **écarté** — non pas « pas encore
fait », mais **interdit**. La `650` resserre le `CHECK` et normalise les lignes
existantes ; la suite `650` (4 scénarios) est **rouge avant** (`lifo` accepté) et
**verte après**.

### `PRD-03` — horizon et consommation des prévisions : la politique standard (migration `651`)

**La pratique des leaders, mot pour mot.** Sage : « consommation des prévisions » ;
Odoo : « consume forecast » ; SAP : *consumption of forecast*. Une **commande
ferme de la période consomme la prévision** au lieu de s'y ajouter — sinon le
besoin est compté deux fois.

**Décision.** `run_mrp` prend deux paramètres : `p_consume_forecast` (défaut
**true**) et `p_consumption_window_days` (défaut 0 = la période exacte ; la
tolérance est offerte comme chez les leaders). Sous ce défaut, une prévision vaut
`max(0, prévision − commandes fermes de sa fenêtre)`, et une commande tombant dans
la fenêtre n'est plus ajoutée séparément ; `p_consume_forecast := false` rend
l'ancien comportement (porte de non-régression). L'horizon était déjà le paramètre
`p_horizon_days` du RPC. La `651` **retire l'ancienne signature** de `run_mrp`
(leçon de la `316`, sinon deux `run_mrp` coexistent) et **repose les droits**
(228, 152). Suite `651` (4 scénarios) : **rouge avant**, **verte après**.

**État de la base, mesuré sur base neuve** (`postgres:16`, 330 migrations + `650`
+ `651`, 0 erreur) : `650` **4/4 vert** · `651` **4/4 vert** · non-régression
`254` **5/5 vert** · `plpgsql_check` **0 erreur** · rôles opposables OK. Les deux
suites sont câblées dans `ci.yml`, **sous le marqueur `# --- plan6:e ---`**.

## Le couplage à surveiller

**B, C et E écrivent des déclencheurs sur les mêmes tables métier** — stock,
production, ventes. Fichiers disjoints (plages distinctes), **comportement
partagé**.

- **C.1 réécrit des fonctions d'écriture comptable de tous les modules**, module
  par module. **Regarder le journal de C** : s'il annonce un module, E n'y
  touche pas cette semaine-là.
- Avant un `CREATE OR REPLACE` d'une fonction **existante** (R7) :

```bash
git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql
```

## E.5 — brancher ou supprimer, pas laisser en coquille

Une table existante mais non branchée est un **leurre** : elle compte dans les
mesures, elle n'apporte rien à l'écran. Pour chacune des 12 tables ci-dessus,
deux issues seulement — **la brancher**, ou **la supprimer**. La troisième,
la laisser, n'en est pas une.

Une suppression est une migration, donc elle prend un numéro dans `650`→`699`
comme le reste.

## Demandes hors territoire (R3)

- **`ci.yml` — une branche `plan6/*` ne déclenchait aucune CI** → ✅ **corrigé
  dans cette partie** (11/10/2026). Le filtre `on: push: branches` listait
  `main`, `master`, `develop`, `commercial-hr-paie`, `qa/**`, `partie-*`,
  `fusion-*`, `harmonisation` — **pas `plan6/**`** (mesuré le 05/10,
  `ci.yml:22-30`). Les six marqueurs `# --- plan6:<lettre> ---` étaient bien
  posés (R5) mais restaient **inerces** : une suite ajoutée sous le marqueur E
  n'était jamais jouée. C'est la même porte que le « 0 passage sur la branche
  QA » du 02/10.

  **Mesuré** : `gh run list --branch plan6/e-operations` → **liste vide**, alors
  que la branche portait quatorze suites, toutes vertes et toutes branchées dans
  `ci.yml` ; `main`, lui, avait bien ses passages.

  **Corrigé autrement que demandé.** La demande était d'ajouter `plan6/**` à la
  liste. On ne l'a pas fait : c'était la **troisième** fois que cette liste
  blanche oubliait une famille de branches vivantes (`qa/**` puis `partie-*`
  l'avaient précédée). `push` joue désormais **toutes** les branches
  (`branches: ['**']`), et `pull_request` ne filtre plus la branche cible — il la
  limitait à `main`/`develop`, ce qui laissait sans CI les PR d'une branche de
  travail vers une autre (`integration/plan6-b` → `plan6/b-regles-etat`).

  **Et pour que ça ne se reperde pas** : `scripts/check-test-suites.mjs` (G5)
  vérifiait déjà que chaque suite est **branchée** ; il vérifie maintenant aussi
  que le workflow **se déclenche**. Mesure rouge avant (ancienne liste blanche →
  `exit 1`), verte après (`exit 0`).

## Ce que la R3 a déterré (11/10/2026)

Trois défauts sont sortis des contrôles **dès** que la CI a cessé d'être muette. Aucun
des trois n'était visible par une suite de scénarios : il faut soit un contrôle de
schéma, soit un **vrai PostgREST** devant un **vrai** schéma. Ils sont donc corrigés
ici, avec leur mesure.

La R3 a révélé un **quatrième** enseignement, qui n'est pas un défaut applicatif mais
une conséquence du job lui-même : **il s'arrête à sa première étape rouge**. Les
contrôles placés après n'avaient donc jamais tourné depuis le début de la partie E —
leurs plafonds datés n'avaient jamais été relus. La répétition générale, en fin de
section, les joue **tous**.

### `ISO-01` — `run_mrp()` et `work_center_capacity()` prenaient la société du client (migration `664`)

Les deux fonctions recevaient `p_tenant_id` (paramètre **client**) et **ne
vérifiaient pas l'appartenance** de l'appelant : une session pouvait calculer les
besoins ou la charge d'une société étrangère. Le reste du schéma est protégé par
`current_tenant_id()` et la RLS ; ces deux fonctions, en `SECURITY DEFINER`,
passaient à côté.

**Mesuré** : `T01`/`T03` de la suite `664` — avant, la fonction **rendait** la
capacité et les besoins de la société étrangère ; après, `SQLSTATE P0001`
(« Société … hors de votre périmètre »). `T02`/`T04`/`T05` prouvent la
non-régression : la société du contexte est toujours servie, et `run_mrp()` **sans
paramètre** prend celle du contexte.

Trouvé par l'étape `check_tenant_guard.sql` (ISO-01) du job DB.

### `ISO-02` / `ISO-04` / `BUD-04` — les deux tables neuves de la partie E (migration `665`)

`landed_cost_receipts` (`658`) et `stock_location_assignments` (`659`) étaient
sorties avec une clé étrangère **mono-colonne** (`landed_cost_id` sans la société),
**sans `FORCE ROW LEVEL SECURITY`** et **sans index** dont la première colonne est
`tenant_id`.

**Mesuré** — `check_composite_fks.sql` **échouait** (le job s'arrêtait là, il n'a
jamais vu les deux lignes suivantes) ; après `665` : les trois contrôles passent.
La suite `665` verrouille les quatre points : clé composite (`T01`), refus de
rattacher la dépense d'une autre société `23503` (`T02`), `FORCE RLS` 2/2 (`T03`),
index société 2/2 (`T04`).

### `LOT7-04` — `/stock/transfers` ne pouvait pas afficher ses articles (migration `666`)

`getStockTransferLines` (`app/src/lib/queries/stock.ts:347`, écrit par la `652`)
demandait `select: '*, products(name, sku)'` — et `stock_transfer_lines.product_id`
**n'avait aucune clé étrangère**. PostgREST répondait donc `PGRST200`
(« Could not find a relationship… ») et l'écran des transferts s'ouvrait **sans ses
articles**. La 237 n'avait pas pu la créer : elle ne compose que les clés
mono-colonnes **déjà présentes**, et celle-ci manquait entièrement depuis la 125.

**Mesuré** : `check-embeds` contre un vrai PostgREST — `❌ 1 requête refusée
(PGRST200)` **avant**, `✅ Les 1582 requêtes vérifiées sont acceptées` **après**.
La suite `666` prouve le comportement (`T02` : un article d'une autre société est
refusé en `23503`) et la non-régression du moteur de transfert (`652` rejouée 5/5).

C'est l'illustration du principe : **ni `tsc`, ni `oxlint`, ni les tests unitaires
ne pouvaient voir celui-là** (Supabase y est simulé). Seul un vrai PostgREST devant
un vrai schéma le dit — et c'est précisément ce que cette étape installe.

### La répétition générale — les 180 fichiers du job DB, joués **en entier** (11/10/2026)

Le correctif de la R3 a une conséquence qu'il fallait mesurer : **le job DB
s'arrête à sa première étape rouge**. Les contrôles qui suivent n'avaient donc
jamais tourné sur cette branche, et leurs plafonds datés étaient des inscriptions
que personne n'avait relues.

Sur une base **neuve** (`test_e664c`) portant toutes les migrations, les 180
fichiers SQL du job ont été rejoués en entier : **178 OK, 2 échecs**.

* `check_forced_rls_writers.sql` — **320** tables sous `FORCE ROW LEVEL SECURITY`
  contre un plafond daté de **318** : ce sont exactement les deux tables de la
  `665`. Le plafond est donc relevé **dans le même commit** que la migration qui
  l'a fait monter (la règle du dépôt). `muettes` reste à **18** — vérifié : les
  deux tables ont une politique d'écriture `ALL`, elles ne rejoignent pas
  l'exposition ; l'auto-test du contrôle le reconfirme (refus `42501` sur sa
  fixture).
* `check_plpgsql.sql` — `function plpgsql_check_function_tb(oid) does not exist` :
  l'extension est absente de la base **neuve** locale. C'est l'environnement, pas
  le code — la CI l'installe explicitement (`.github/workflows/ci.yml`, étape
  « Installer plpgsql_check »). Une fois installée : **0 erreur, 54
  avertissements**.

Rejeu après correction : **180/180**.

## État final de la CI sur `plan6/e-operations` (11/10/2026)

`completed / success` — passage **38155294420** (`823ecd7`), **tous** les jobs verts :

| Job | Verdict |
|---|---|
| `DB Integration Tests` | ✅ **197 étapes** — les 22 contrôles de schéma (dont clés composites et G7) **et** les suites qui n'avaient jamais été jouées (LOT7-04 contre PostgREST, W0/W10, SOC-01/02, B8/B9/B10, registres AUD) |
| `Chemin de l'écran (PostgREST réel)` | ✅ — c'est ce job qui voyait `PGRST200` sur `/stock/transfers` |
| `Lint & Type Check` · `Unit Tests` · `i18n` · `Edge Functions` · `Production Build` | ✅ tous |
| `E2E Tests (Playwright)` · `Security Audit` | `skipped` — c'est leur **condition** (`schedule`, `workflow_dispatch`, label `run-e2e`), pas un échec |

Les deux passages précédents disent l'histoire de la branche : `38126150912`
(`ea72bc6`) s'arrêtait à `check_composite_fks` — c'est lui qui a fait sortir `665`
et `666` ; `38154354528` (`f911306`) s'arrêtait **étape 24**, « Vérifier que les
types sont à jour », sur les 7 lignes de `stock_transfer_lines` — corrigé en
`823ecd7`. À chaque fois, **une seule** étape rouge à la fois : c'est ce qui a
laissé dix-huit contrôles dans l'ombre pendant toute la partie E.

Les deux plafonds `app/.any-ceiling.json` et `app/.console-error-ceiling.json` ne
sont **pas** touchés par cette branche (R6) : ils se régénèrent à l'intégration,
après fusion.

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|
| 05/10/2026 | **E.1** — recomptage des 11 ❓ | 5 ✅ · 3 🔶 · 3 ⬜ · 0 écarté (corrigé) | ≈ 13,5 j (❓) + ≈ 9 sem. (⬜ E.2→E.5) | `35d5d5d` |
| 05/10/2026 | **Les 2 décisions** — `STK-03` (`650`) et `PRD-03` (`651`) | LIFO écarté (IAS 2/PCG) ; consommation des prévisions livrée | 0,5 j, `650` 4/4 · `651` 4/4 · `254` 5/5 | `f280641` |
| 05/10/2026 | **E.2** — « Modifier » une nomenclature | `updateBOM`/`updateBOMLine` + bouton ; MRP testé (`651`) | 0,5 j ; tsc 0 · oxlint 0 · vitest 86/86 | `b22b443` |
| 05/10/2026 | **E.2** — transferts inter-dépôts | `652` (expédier/réceptionner) + requêtes + écran `/stock/transfers` | `652` 5/5 · tsc 0 · oxlint 0 · i18n OK | `a891161` |
| 05/10/2026 | **E.3** — `STK-07` unités de mesure | requêtes + écran `/stock/uoms` + convertisseur ; branche `uom_categories` | tsc 0 · oxlint 0 · i18n OK · vitest 86/86 | `9192141` |
| 05/10/2026 | **E.3** — `STK-09` réapprovisionnement | `653` `reorder_suggestions` + règles/suggestions sur `/stock/reorder` ; branche `reorder_rules` | `653` 5/5 · tsc 0 · oxlint 0 · i18n OK | `a6aa046` |
| 05/10/2026 | **E.3** — `STK-09` inventaire tournant | `654` `generate_count_list`/`record_stock_count` + écran `/stock/counts` ; branche `stock_count_cycles` | `654` 5/5 · tsc 0 · oxlint 0 · i18n OK | `c73100f` |
| 05/10/2026 | **E.3** — `STK-11` stock par emplacement | `655` `stock_by_location` + type/capacité et « stock par emplacement » à l'écran | `655` 3/3 · tsc 0 · oxlint 0 · i18n OK | `5bdf317` |
| 06/10/2026 | **E.4** — `PRD-11` usure outillage | `656` `tooling_wear_alert` + carte « Usure des outillages » sur `/production/machines` | `656` 3/3 · tsc 0 · oxlint 0 · i18n OK | `0cf025c` |
| 06/10/2026 | **E.4** — `PRD-07` capacité finie | `657` `work_center_capacity`/`work_center_capacity_load` + carte « Charge / capacité » | `657` 4/4 · tsc 0 · oxlint 0 · i18n OK | `9b5f493` |
| 06/10/2026 | **E.4** — `PRD-11` interventions de maintenance | requêtes + carte « Interventions » sur `/production/machines` ; branche `maintenance_records` | tsc 0 · oxlint 0 · i18n OK · vitest 86/86 | `b80d729` |
| 06/10/2026 | **E.5** — décision par coquille | 6 branchées, 5 décidées (brancher via leur chantier / hors périmètre E) | doc seule | `2d09df5` |
| 11/10/2026 | **E.3** — `STK-08` frais accessoires | `658` `landed_cost_receipts` + moteur corrigé + écran `/stock/landed-costs` | `658` 4/4 · tsc 0 · oxlint 0 · i18n OK | `e238842` |
| 11/10/2026 | **E.4** — sous-OF (recomptage) | déjà câblé (onglet « sous-niveaux ») ; colonne produit corrigée | tsc 0 · oxlint 0 · i18n OK · vitest 86/86 | `444d70d` |
| 11/10/2026 | **E.3** — `STK-11` stock par casier | `659` affectations + `location_stock` + « Affecter » à l'écran | `659` 3/3 · non-régression 254/652/653/654/655 · tsc 0 · oxlint 0 · i18n OK | `3b17bf9` |
| 11/10/2026 | **E.3** — `STK-11` rangement/prélèvement | `660` `suggest_putaway_location` + `suggest_pick_location` + carte à l'écran | `660` 3/3 (rouge avant) · `659` 3/3 · tsc 0 · oxlint 0 · i18n OK · vitest 1662 ✓ | `1bfdba4` |
| 11/10/2026 | **E.5 / PRD-06** — déclaration d'atelier | `661` `mo_operations` branchée (`record_mo_operation` + `mo_operations_summary`) + onglet « Atelier » | `661` 3/3 (rouge avant) · `302` 8/8 · tsc 0 · oxlint 0 · i18n OK · vitest 1662 ✓ | `5a9fd96` |
| 11/10/2026 | **E.5 / STK-13** — plans de contrôle qualité | `662` `quality_control_plans` + `points` branchées (plan applicable, échantillonnage, verdict) + carte à l'écran | `662` 5/5 (rouge avant, **1 bug NULL corrigé**) · tsc 0 · oxlint 0 · i18n OK · vitest 1662 ✓ | `8eec80b` |
| 11/10/2026 | **E.5 / PRD-06** — écart de matière | `663` `mo_consumptions` branchée (`refresh_mo_consumptions` + `mo_consumption_variance`) + carte « Écart de matière » | `663` 4/4 (rouge avant) · tsc 0 · oxlint 0 · i18n OK · vitest 1662 ✓ | `6a40a99` |
| 11/10/2026 | **R3** — la CI ne jouait pas les branches `plan6/*` | `push` joue **toutes** les branches (`['**']`), `pull_request` sans filtre ; `check-test-suites.mjs` (G5) refuse le retour d'une liste blanche | `gh run list --branch plan6/e-operations` : liste vide **avant**, passage déclenché **après** · G5 rouge avant (exit 1) / vert après (exit 0) · YAML valide | `ea72bc6` |
| 11/10/2026 | **Répétition générale** — base **neuve** + les **180** fichiers SQL du job DB, joués en entier (la CI s'arrête à la 1re étape rouge : les suivantes n'avaient jamais tourné) | `178 OK / 2 échecs` au 1er passage — `check_forced_rls_writers` (plafond 318 → **320** : mes 2 tables de la `665` ; `muettes` reste à 18) et `check_plpgsql` (extension absente de la base neuve — la CI l'installe) | Rejeu après correction : **180/180** · `check_plpgsql` 0 erreur / 54 avertissements · `check_forced_rls_writers` OK (320 tables, 18 muettes, auto-test `42501`) | `8d9274b` |
| 11/10/2026 | **CI enfin déclenchée** — `ISO-01` : `run_mrp()`/`work_center_capacity()` prenaient la société du **client** (migration `664`) | Une session pouvait calculer les besoins ou la charge d'une société étrangère ; trouvé par `check_tenant_guard` | `664` 5/5 (T01/T03 rouges avant) · `check_tenant_guard` vert | `8d9274b` |
| 11/10/2026 | **CI** — `ISO-02`/`ISO-04`/`BUD-04` : les 2 tables neuves de E (migration `665`) | Clé étrangère mono-colonne, pas de `FORCE RLS`, pas d'index société ; `check_composite_fks` échouait (le job s'arrêtait là) | `665` 4/4 (T02 prouve le refus `23503`) · `check_composite_fks`/`check_bt_grid` verts | `8d9274b` |
| 11/10/2026 | **CI** — `LOT7-04` : `/stock/transfers` s'ouvrait **sans ses articles** (migration `666`) | L'embed `products(name, sku)` était impossible : `stock_transfer_lines.product_id` n'avait aucune clé étrangère (depuis la 125) → `PGRST200` | `check-embeds` : 1 requête refusée **avant** / 1582 acceptées **après** · `666` 3/3 · `652` 5/5 · non-régression 664/665 | `8d9274b` |
| 11/10/2026 | **CI** — étape 24 : les types générés ne portaient pas la clé étrangère de la `666` | Ma régénération datait d'une base **sans** la `666` : 666 réparait le schéma **sans** réparer l'écran (`PGRST200` serait resté) | Diff de la CI reproduit à l'identique en local (`@@ -19543,6 +19543,13 @@`) puis régénéré depuis la base neuve : **7 insertions** · `tsc` 0 · étape 24 verte au passage suivant | `823ecd7` |
| 11/10/2026 | **CI verte** sur la branche | Le job DB va de l'étape 1 à **197** sans un rouge ; les 22 contrôles de schéma passent, et les suites jamais jouées aussi | passage `38155294420` : **`completed / success`** — 8 jobs verts, 2 `skipped` par construction (`schedule` / `workflow_dispatch`) | `823ecd7` |
| 11/10/2026 | **PRD-08 (fin)** — un seul moteur CBN | `runMRPCalculation` (moteur client : OF seules, `+7 j` en dur, `Math.ceil` nu, prévisions ignorées) **supprimé** ; `runMRPAndSave` (`stock.ts`) persiste ce que le RPC `run_mrp` (651/664) calcule — l'écran garde son historique et ses propositions ; un seul bouton (l'autre portait une chaîne **non traduite**) ; wrapper `runMRP` enrichi de toutes les colonnes persistées | vitest **1662/1662** (bloc MRP réécrit : persistance d'un lancement + annulation W6) · tsc 0 · oxlint 0 · i18n OK · plafond `any` racheté **936→926** | `ea60af5` |