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
| PRD-08 | mineur | **🔶 corrigé le 05/10.** Le RPC `run_mrp` existe et **est branché** (`MRPPages.handleRunMRP`). La `651` l'a complété et a retiré l'ancienne signature (`DROP run_mrp(uuid,integer)`). **Reste** : l'ancien moteur client `runMRPCalculation` (`handleCalculate`) coexiste encore. | 🔶 finir | 0,5 j |
| PRD-03 | 4 j | **✅ corrigé le 05/10 — le ❓ lisait le mauvais moteur.** Le RPC SQL `run_mrp` (`152`) lisait **déjà** les trois sources (OF, commandes clients, prévisions) **et** l'horizon `p_horizon_days` ; le critère ne manquait que sur la **consommation des prévisions** — livrée par la `651`. Le vieux moteur client, lui, ne lit que les OF : c'est lui qui avait fait dire ❓. | ✅ fait (base) | 0 |
| PRD-04 | 1 j | **✅ corrigé le 05/10 — même cause.** `run_mrp` applique **déjà** `safety_stock`, `lead_time_days`, `min_order_qty`, `qty_multiple` ; le `+7 j` en dur et le `Math.ceil` nu n'existent que dans le vieux moteur client. | ✅ fait (base) | 0 |
| PRD-10 | 1 sem. (avec PRD-11) | **Non fait.** `workflows` et `product_equivalences` sont des écrans CRUD ; non exploités dans le MRP ; finalité non documentée. | ⬜ faire (léger) | 2 j |
| ACH-01 | — | **Non fait.** Aucune table de contrat ni d'accord-cadre. | ⬜ faire | 3 j |
| ACH-02 | — | **Non fait.** Aucune table ni fonction de score fournisseur. | ⬜ faire | 2 j |
| VTE-01 | 3 j | **Partiel.** `resolve_price` (`117`) + helper client `resolvePrice` existent, mais **aucun formulaire ne l'appelle** : `price_list` n'est lu que par la page de saisie des grilles. | 🔶 finir | 2 j |
| VTE-03 | — | **Partiel.** `calculate_payment_due_dates` (`88`) produit des échéances multiples ; manquent la cascade de remises, l'escompte conditionnel et les remises de fin d'année. | 🔶 faire | 3 j |

**Compte du recomptage (corrigé le 05/10) : 5 ✅** (`ACC-01`, `ACC-03`, `PRD-05`,
`PRD-03`, `PRD-04`) **· 3 🔶** (`PRD-08`, `VTE-01`, `VTE-03`) **· 3 ⬜**
(`PRD-10`, `ACH-01`, `ACH-02`) **· 0 écarté.**

**Ce que le recomptage change.** Le §9 du plan rangeait ces onze chantiers sous
« à estimer ». **Cinq sont déjà faits** — comme pour la partie 3 (A.1), le suivi
est en retard, pas le dépôt. Et deux corrections d'honnêteté : `PRD-03` et
`PRD-04` n'étaient ❓ que parce que la première mesure regardait le **vieux
moteur client** (`runMRPCalculation`) ; le moteur qui fait foi — le RPC SQL
`run_mrp` — les portait déjà. La charge du périmètre ❓ tombe à **≈ 13,5 j**
(ACC-01/03 garde-fous 1 j, PRD-08 0,5 j, VTE-01 2 j, VTE-03 3 j, PRD-10 2 j,
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

- **`ci.yml` — une branche `plan6/*` ne déclenche aucune CI.** Le filtre
  `on: push: branches` liste `main`, `master`, `develop`, `commercial-hr-paie`,
  `qa/**`, `partie-*`, `fusion-*`, `harmonisation` — **pas `plan6/**`** (mesuré
  le 05/10, `ci.yml:22-30`). Les six marqueurs `# --- plan6:<lettre> ---` sont bien
  posés (R5) mais restent **inertes** : une suite ajoutée sous le marqueur E ne
  sera jamais jouée tant que ces branches ne se déclenchent pas. C'est la même
  porte que le « 0 passage sur la branche QA » du 02/10. **À corriger par
  l'intégration** — ajouter `plan6/**` à `push.branches` et
  `pull_request.branches` — **avant** que la partie E ne pousse sa première suite.

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|
| 05/10/2026 | **E.1** — recomptage des 11 ❓ | 5 ✅ · 3 🔶 · 3 ⬜ · 0 écarté (corrigé) | ≈ 13,5 j (❓) + ≈ 9 sem. (⬜ E.2→E.5) | `35d5d5d` |
| 05/10/2026 | **Les 2 décisions** — `STK-03` (`650`) et `PRD-03` (`651`) | LIFO écarté (IAS 2/PCG) ; consommation des prévisions livrée | 0,5 j, `650` 4/4 · `651` 4/4 · `254` 5/5 | `f280641` |
| 05/10/2026 | **E.2** — « Modifier » une nomenclature | `updateBOM`/`updateBOMLine` + bouton ; MRP testé (`651`) | 0,5 j ; tsc 0 · oxlint 0 · vitest 86/86 | `b22b443` |
| 05/10/2026 | **E.2** — transferts inter-dépôts | `652` (expédier/réceptionner) + requêtes + écran `/stock/transfers` | `652` 5/5 · tsc 0 · oxlint 0 · i18n OK | à committer |