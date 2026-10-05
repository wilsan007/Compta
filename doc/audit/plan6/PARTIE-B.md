# Partie B — les 62 règles d'état et les restes de paie française

> Fichier de suivi **exclusif** de la partie B (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/b-regles-etat` |
| **Worktree** | `.claude/worktrees/plan6-b-regles-etat` |
| **Plage de migrations** | `500` → `559` |
| **Territoire de fichiers** | migrations de règles d'état **par module** ; `app/src/lib/payroll*`, écrans de paie |
| **Charge** | ≈ 42 j (B.1 + B.2) + ≈ 3 j (B.3 + B.4) |
| **Départ possible** | tout de suite |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| B.1 | Inventaire des 62 règles d'état contre le schéma du jour : lesquelles existent déjà (W1 → W10, X1 → X6 en ont posé) | L8 → L15 | 2 j | 🟡 **compté le 05/10** — [rapport B.1](B1-INVENTAIRE-62-REGLES-2026-10-05.md) |
| B.2 | Règles d'état, un lot par module, dans cet ordre : **ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets** | L8 → L15 | ≈ 40 j | ⬜ |
| B.3 | Paie : seuil **hebdomadaire** des heures supplémentaires, exonération d'impôt de 7 500 € | reste de 2.3 | 1,5 j | ⬜ |
| B.4 | Paie : arrêt maladie (carence, maintien) | reste de 2.4 | 1,5 j | ⬜ |

## B.1 — l'inventaire, mesuré le 05/10/2026

Base neuve (procédure de la CI), **333 migrations, 0 erreur**. Le détail des 62 règles,
règle par règle, avec le déclencheur ou la fonction qui la porte, est dans le
**[rapport B.1](B1-INVENTAIRE-62-REGLES-2026-10-05.md)**.

| | 62 règles d'état `R-001` → `R-062` |
|---|---:|
| ✅ existent déjà (déclencheur + effet aval) | **13** |
| 🟨 partiellement (l'effet existe, pas sur cette transition) | **13** |
| ⬜ vierges (aucun déclencheur ne teste l'état) | **36** |

Par module : ventes 2 / achats 3 / trésorerie 1 / **paie-RH 5** / projets 0 /
production 0 / conformité 1 / budgets 1 (existantes).

**Trois corrections que la mesure apporte au plan** (à porter par l'intégration) :

1. Le point de départ n'est pas **0 / 62** mais **26 / 62 touchés** : B.2 ne part pas
   du vide.
2. « W1 → W10, X1 → X6 en ont posé » est **faux** : ces vagues citent `R-025 → R-039`
   comme **restant**. Les règles déjà posées viennent de **L1 (`400`/`401`/`404`)**,
   de la **partie 3 (`433` → `436`)** et des sessions **`241` → `419`**.
3. **`R-062` est déjà faite** (`pos_tickets_status_check` existe) et **`R-006` vise
   `deliveries`, une table qui n'existe pas** (c'est `delivery_notes`) → §B.2 du
   référentiel à corriger.
   ↳ **Demande à l'intégration (R3)** : `doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md`
   n'est au territoire d'**aucune** des six parties (§2) — `doc/audit/` n'est détenu
   par ni A ni B ni C… C'est un document de référence partagé, tenu par la **session
   d'intégration** (§10), comme `SUIVI-CHANTIERS.md` et `AGENTS.md` (R4).

## Attend de vous

La signature de l'expert-comptable (**D-G**). Elle bloque le **déploiement**
des `276`, `341`, `342` et de B.3/B.4 — **pas leur écriture**. On peut donc
écrire B.3 et B.4 avant la signature ; elles ne partiront pas en production
sans elle.

## Le couplage à surveiller

**B, C et E écrivent des déclencheurs sur les mêmes tables métier** (stock,
production, ventes). Les fichiers ne se touchent pas — plages distinctes —
mais le **comportement** peut changer d'une release à l'autre.

Garde-fou (règle R7) : avant un `CREATE OR REPLACE` d'une fonction
**existante**, vérifier qu'aucune autre branche `plan6/*` ne la réécrit :

```bash
git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql
```

En cas de doute, **C passe après** B et E sur les fonctions d'écriture
comptable. Et la batterie complète est rejouée à chaque fusion (R8).

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|
| 05/10 | B.1 | tous | Inventaire des 62 règles d'état mesuré sur base neuve (**333 migrations, 0 erreur**) : **13 ✅ / 13 🟨 / 36 ⬜**. Déclencheurs actifs + `document_effects` + `CHECK` lus en base ; origine des règles déjà posées (L1, partie 3, sessions 241→419) ; `R-062` faite, `R-006`/`deliveries` à corriger au référentiel. | lecture seule (aucune migration) | _à venir_ |