# Partie D — qualité des écrans, recette, livraison

> Fichier de suivi **exclusif** de la partie D (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/d-ecrans` |
| **Worktree** | `.claude/worktrees/plan6-d-ecrans` |
| **Plage de migrations** | `355` → `369` (peu de SQL) |
| **Territoire de fichiers** | balayages transverses de `app/src/pages`, `app/src/components`, `e2e/`, `scripts/qa`, `app/src/__screen__`, job Playwright |
| **Charge** | ≈ 25 j + recette |
| **Départ possible** | tout de suite pour D.1 → D.4 ; **D.5 attend les secrets** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| D.1 | Vrai dialogue de confirmation à la place de `confirmSync` (100 fichiers), **par module, un lot par jour** | 1.8, AUD-I01 | 4 j | ⬜ |
| D.2 | Typer les 80 états d'écran restants (RH, production, trésorerie, immobilisations, CRM) | DAT-02, suite de 2.16 | 5 j | ⬜ |
| D.3 | Alignement des colonnes sur 10 écrans | étape 0.5 | 1 j | ⬜ |
| D.4 | Lectures du chemin de l'écran (159 fonctions non couvertes) ; immobilisations et tableaux de bord à l'écran | 4.5, 4.11, 4.12 | 5 j | ⬜ |
| D.5 | Playwright sur chaque PR vers `main` ; 4 parcours qui lisent un chiffre | 4.3, 4.4, AUD-J01/J02 | 3 j | ⬜ |
| D.6 | Les 14 parcours à l'écran, 2 sociétés, 4 gabarits ; correction des écarts bloquants ; re-notation des modules | 4.6, 4.7, P0-08 | recette | ⬜ |
| D.7 | Rejeu sur copie de production (porte G7 sous le vrai propriétaire), relecture des paramètres globaux et de `banks` | 4.8, 4.9 | 2 j | ⬜ |
| D.8 | Contraste : appliquer la décision D-7 | AUD-I05 | 1 j | ⬜ |

## Attend de vous

- Les **secrets E2E dans GitHub** (bloque D.5).
- La **décision `D-7`** (bloque D.8 — le contraste a été audité, pas tranché).
- **Votre présence** pour la recette (D.6).

## La règle qui rend D possible : livrer en premier, par module

> D balaie des écrans que les autres parties modifient aussi. Le plan est
> explicite : **D livre ces balayages par module et en premier**, en lots d'un
> jour, pour que le conflit soit **court**.

Un balayage de 100 fichiers livré d'un bloc produirait des conflits de
plusieurs jours sur des fichiers que A, C et E déplacent. **Un lot par jour**,
c'est la condition.

## D.3 — reprise gelée

Voir [REPRISE-2-ALIGNEMENT-COLONNES.md](REPRISE-2-ALIGNEMENT-COLONNES.md) :
10 écrans, l'instantané `f5cda2f`. **Mesurer d'abord** — `CreditNotesPage.tsx`
a bougé depuis le gel, le patch peut ne plus s'appliquer tel quel.

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|