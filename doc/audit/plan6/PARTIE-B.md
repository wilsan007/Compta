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
| B.1 | Inventaire des 62 règles d'état contre le schéma du jour : lesquelles existent déjà (W1 → W10, X1 → X6 en ont posé) | L8 → L15 | 2 j | ⬜ |
| B.2 | Règles d'état, un lot par module, dans cet ordre : **ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets** | L8 → L15 | ≈ 40 j | ⬜ |
| B.3 | Paie : seuil **hebdomadaire** des heures supplémentaires, exonération d'impôt de 7 500 € | reste de 2.3 | 1,5 j | ⬜ |
| B.4 | Paie : arrêt maladie (carence, maintien) | reste de 2.4 | 1,5 j | ⬜ |

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

## Demandes reçues (R3) — transmises par l'intégration du 05/10/2026

| # | Demande | De | Ce qu'elle débloque / corrige |
|---|---|---|---|
| 1 | Ajouter une **colonne numérique** à `dsn_declarations` (ex. `gross_declared`), **écrite par la génération DSN** | A1 — invariant **INV-10** | rend **INV-10** mesurable (« brut de la DSN = brut des bulletins du mois ») : la table n'a aujourd'hui **zéro** colonne numérique, le brut n'existe que dans le fichier produit (mesure `L4-INVARIANTS-MESURABLES`) |
| 2 | **PAY-01** (deux corrections immédiates, bloquant), **PAY-11** (solde de tout compte, ≈ 1,5 j), **PAY-12** (architecture cible du moteur) | F — recomptage F.1 | chantiers **de paie hors périmètre F**, **transférés à B** (R3) |

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|