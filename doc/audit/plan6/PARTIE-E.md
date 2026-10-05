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
| E.1 | **Recompter** les chantiers ❓ de son périmètre et **estimer** les ⬜ ; décider pour chacun : faire, reporter, écarter | ACC-01, ACC-03, PRD-03/04/05/08/10, ACH-01/02, VTE-01/03 | à chiffrer | ⬜ **premiere tâche** |
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