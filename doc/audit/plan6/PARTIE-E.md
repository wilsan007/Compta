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
| **Charge** | **à estimer** — c'est la tâche E.1 |
| **Départ possible** | tout de suite, **par le recomptage** |

## Les tâches

| # | Tâche | Repris de (plan 9,5) | Charge | État |
|---|---|---|---|---|
| E.1 | **Recompter** les chantiers ❓ de son périmètre et **estimer** les ⬜ ; décider pour chacun : faire, reporter, écarter | ACC-01, ACC-03, PRD-03/04/05/08/10, ACH-01/02, VTE-01/03 | à chiffrer | 🟡 **compté le 05/10** — voir « E.1 — le recomptage » |
| E.2 | Restes à l'écran : transfert entre dépôts, étiquettes, MRP jamais testés ; action « Modifier » d'une nomenclature | D13, reste de 2.5 | — | ⬜ |
| E.3 | Stock avancé : FIFO/LIFO, unités de mesure, frais accessoires, réapprovisionnement et inventaire tournant, emplacements, transferts et variantes | STK-03/07/08/09/11/14 | — | ⬜ |
| E.4 | Production : capacité finie, maintenance, sous-OF (`parent_mo_id` inutilisé) | PRD-07, PRD-11 | — | ⬜ |
| E.5 | Tables coquilles de son périmètre — **brancher ou supprimer** : `uom_categories`, `landed_cost_lines`, `reorder_rules`, `stock_count_cycles`, `stock_transfer_lines`, `mo_consumptions`, `mo_operations`, `maintenance_records`, `work_center_calendars`, `quality_control_*`, `fixed_asset_components`, `resource_capacities` | ORPH-02 | — | ⬜ |

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
| PRD-08 | mineur | **Partiel.** Le RPC `run_mrp(p_horizon_days)` existe (`115`/`144`/`152`) et **est branché** (`MRPPages.handleRunMRP` → `runMRP(90)`). Mais l'ancien moteur client `runMRPCalculation` **subsiste** et reste le bouton par défaut (`handleCalculate`). Deux moteurs coexistent. | 🔶 finir | 0,5 j |
| PRD-03 | 4 j | **Non fait.** `runMRPCalculation` ne prend que les OF ouverts : ni commandes clients, ni `production_forecasts` (lues par l'écran, jamais par le calcul), ni seaux de temps, ni horizon. | ⬜ faire | 4 j |
| PRD-04 | 1 j | **Non fait.** `suggested_date = aujourd'hui + 7 j` en dur, besoin net jamais diminué du stock de sécurité, quantité = `Math.ceil` nu (ni minimum de commande, ni multiple). | ⬜ faire | 1 j |
| PRD-10 | 1 sem. (avec PRD-11) | **Non fait.** `workflows` et `product_equivalences` sont des écrans CRUD ; non exploités dans le MRP ; finalité non documentée. | ⬜ faire (léger) | 2 j |
| ACH-01 | — | **Non fait.** Aucune table de contrat ni d'accord-cadre. | ⬜ faire | 3 j |
| ACH-02 | — | **Non fait.** Aucune table ni fonction de score fournisseur. | ⬜ faire | 2 j |
| VTE-01 | 3 j | **Partiel.** `resolve_price` (`117`) + helper client `resolvePrice` existent, mais **aucun formulaire ne l'appelle** : `price_list` n'est lu que par la page de saisie des grilles. | 🔶 finir | 2 j |
| VTE-03 | — | **Partiel.** `calculate_payment_due_dates` (`88`) produit des échéances multiples ; manquent la cascade de remises, l'escompte conditionnel et les remises de fin d'année. | 🔶 faire | 3 j |

**Compte du recomptage : 3 ✅** (`ACC-01`, `ACC-03`, `PRD-05`) **· 3 🔶**
(`PRD-08`, `VTE-01`, `VTE-03`) **· 5 ⬜** (`PRD-03`, `PRD-04`, `PRD-10`, `ACH-01`,
`ACH-02`) **· 0 écarté.**

**Ce que le recomptage change.** Le §9 du plan rangeait ces onze chantiers sous
« à estimer ». **Trois sont déjà faits** — comme pour la partie 3 (A.1), le suivi
est en retard, pas le dépôt. La charge du périmètre ❓ tombe à **≈ 18,5 j**, dont
**1 j** pour verrouiller les deux faits par une suite de non-régression
(`ACC-01`, `ACC-03`) : un chantier prouvé par la migration mais par aucune suite
reste un chantier « fait, non gardé ».

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

### Ce qu'E.1 demande de vous

Rien ne bloque. Deux choix de politique à confirmer avant E.3 et E.4 :
1. **`STK-03`** : confirmer l'**écart** du FIFO/LIFO (le CUMP de `254` reste la
   seule valorisation), ou dire que les couches sont voulues.
2. **`PRD-03`** : l'horizon de calcul (jours) et la politique de consommation des
   prévisions — c'est un paramètre de dossier, pas une constante.

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

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|
| 05/10/2026 | **E.1** — recomptage des 11 ❓ | 3 ✅ · 3 🔶 · 5 ⬜ · 0 écarté | ≈ 18,5 j (❓) + ≈ 9 sem. (⬜ E.2→E.5) | doc seule, à intégrer |