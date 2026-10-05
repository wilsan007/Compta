# Partie C — lot K, localisation Djibouti

> Fichier de suivi **exclusif** de la partie C (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/c-localisation` |
| **Worktree** | `.claude/worktrees/plan6-c-localisation` |
| **Plage de migrations** | `370` → `399` (inscrite : `370`→`379` le 05/10), puis `600` → `649` |
| **Territoire de fichiers** | `legislation_packs`, `chart_*`, `resolve_account`, grilles fiscales ; `app/src/lib/countries.ts`, écrans Paramètres → pays/plan comptable ; `doc/localisation/` |
| **Charge** | ≈ 74 j (48 neutres + 26 pack) |
| **Départ possible** | phase 1 tout de suite ; **la phase 2 attend les textes** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| C.1 | Phase 1 — **neutralité** : les comptes codés en dur (`310000`, `601000`, `355000`, `713500`, `641`/`645`/`421`/`431`…) passent par `resolve_account` ; pack fictif `ZZ` comme preuve | LOC1-01 → 58, S-10, AUD-F03, AUD-G10 | ≈ 48 j | ⬜ |
| C.2 | Barème ITS gelé, sous `370`, **sans les deux lignes extrapolées**, source provisoire dite | étape 0.5 | 1 j | 🟡 **fait le 05/10, à reprendre** |
| C.3 | Phase 2 — pack Djibouti : plan comptable national, TVA, paie, états, mentions de facture, formats bancaires ; chaque valeur sourcée `SRC-DJ-nn` | LOC2-01 → 41 | ≈ 26 j | ⬜ |
| C.4 | Pilote | — | hors charge | ⬜ |

## C.2 — ce que l'étape 0 a livré, et les deux réserves

Voir [REPRISE-1-BAREME-ITS-DJIBOUTI.md](REPRISE-1-BAREME-ITS-DJIBOUTI.md).

Livré le 05/10 : le barème ITS de 393 tranches sous `370`, porté de
`claude/extract-tax-salary-table-2a3267` (`900ce64`), plus le **moteur** qui
savait le lire — `fixed_amount` ne testait pas la tranche, donc les 392
montants s'additionnaient en entier.

Vérifié sur base neuve (PostgreSQL 16, 333 migrations) : suite `370` **6/6
verte**, idempotente (`grilles 1→1`, `lignes 393→393`, identique).

**Réserve 1 — les deux lignes extrapolées sont là, et C.2 les exclut.**
Le libellé du plan dit : reprendre le barème gelé **sans** les deux lignes
extrapolées, source provisoire dite. Le fichier livré contient les lignes
392 et 393 (au-delà de **2 005 000 DJF**, alors que la source s'arrête à
2 004 999). Elles sont **signalées** comme non officielles dans leur libellé,
ce qui est mieux que le silence, mais ce n'est pas ce que C.2 demande.

> **À trancher** : soit on les retire et le barème s'arrête à 2 004 999 DJF
> (au-delà : ITS = 0, ce qui est faux), soit on les garde en attendant la DGI.
> La première option est un trou, la seconde une invention. **Décision
> attendue du chef de produit**, avec le seuil écrit noir sur blanc.

**Réserve 2 — `66_critical_rls_isolation_fix.sql`.** Cet instantané de la
branche gelée (153 lignes) corrigeait 71 tables en `allow_all_%`. Il est
**hors du territoire de C**. Vérifié le 05/10 sur la production : **0 ligne
aujourd'hui** — le correctif est devenu inutile. Il ne doit pas être
reprise.

## Attend de vous

- **`D-11`** : entreprises publiques seules, ou avec le module des
  administrations ? Arabe dès la v1 ?
- Les **14 documents djiboutiens**.
- L'**expert-comptable référent**.
- La **DGI Djibouti** pour le barème au-delà de 2 004 999 DJF.

Sans eux, **C.3 ne commence pas**.

## Le couplage à surveiller (règle R7)

**C.1 réécrit des fonctions d'écriture comptable de tous les modules.**

> C les traite **module par module**, en annonçant dans ce fichier le module de
> la semaine ; **B et E n'y touchent pas cette semaine-là**.

C'est la seule partie qui touche aux fonctions d'écriture des autres. Le
protocole : annoncer le module ici **avant** de commencer, etcggrep avant un
`CREATE OR REPLACE` :

```bash
git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql
```

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|