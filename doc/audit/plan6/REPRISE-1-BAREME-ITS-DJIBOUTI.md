# Reprise 1 — barème ITS Djibouti + calcul « palier fixe » (déposé pour la partie C)

> **Étape 0.5 du** [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md).
> Ce fichier **nomme** ce qu'il y a à reprendre. Il ne porte pas le SQL : la
> partie C l'écrit sous son propre numéro, dans sa plage.

## 1. La source, à l'identique

| | |
|---|---|
| Branche gelée | `claude/extract-tax-salary-table-2a3267` |
| **Commit source** | **`900ce64`** — `WIP(1.0) : instantane du travail non commit du worktree, mis en pause` |
| Tag de sûreté | `sauvegarde/2026-10-03/claude/extract-tax-salary-table-2a3267` |
| Base | `9ceedf2` (`main` au 03/10), puis `27fb2cf` |
| Statut | **gelé**, jamais fusionné, jamais poussé sur `main` |

```bash
git show 900ce64 --stat          # 5 fichiers, 672 lignes ajoutées
git show 900ce64:app/sql/65_seed_dj_its_payroll_grid.sql
```

## 2. Ce que contient l'instantané

| Fichier | Lignes | Nature |
|---|---|---|
| `app/sql/65_seed_dj_its_payroll_grid.sql` | 506 | le barème ITS mensuel, en `INSERT` |
| `app/sql/66_critical_rls_isolation_fix.sql` | 153 | correctif RLS — **ne pas reprendre tel quel** |
| `app/src/lib/payroll.ts` | 11 | calcul « palier fixe » |
| `app/src/lib/countries.ts` | 2 | déclaration du pack `DJ` |
| `.gitignore` | 1 | à examiner avant tout |

## 3. Ce que la partie C doit en faire — et comment

### 3.1 Le numéro

Le plan §6, tâche **C.2** : reprendre le barème gelé **sous `370`**, dans la
plage `370` → `399` de la partie C. Le numéro `65` de l'instantané est
**occupé** et déjà dans une autre plage (`100` → `129`, *fondations produit*) :
il ne peut pas être réutilisé.

```bash
cd app
npm run migration:prendre -- dj_its_bareme_mensuel --session "plan6/c-localisation"
```

> Le fichier `app/sql/370_dj_its_bareme_mensuel.sql` existe **déjà**, pris le
> **04/10/2026 à 20:13:26Z** sur la ligne « lot K (localisation Djibouti) »,
> branche `integration/wip-restants`. Il ne contient que l'en-tête (2 lignes).
> **La partie C l'écrit, elle ne le reprend pas par `prendre`.**

### 3.2 Les deux lignes extrapolées — à ne pas reprendre

Le fichier source `salaires janvier 2026-1.xlsx` (onglet « Bareme ITS ») s'arrête
à **2 004 999 DJF**. Les deux dernières lignes de l'instantané (au-delà de
**2 005 000 DJF**) sont une **extrapolation non officielle** : plancher + 45 %
marginal, taux déduit du dernier écart de tranche.

C.2 les **exclut**, et **dit la source provisoire** dans l'en-tête du fichier
`370` : sans cela, la ligne.d attache à un barème officiel une valeur qui ne
l'est pas.

### 3.3 Le calcul « palier fixe » — déjà partly fait sur la ligne principale

Le plan 9,5 avait laissé ce calcul à moitié fait. Sur la ligne principale,
`4c8e642` (`fix(lot K) : un montant fixe de grille ne vaut que dans sa
tranche`) l'a **terminé** : un `fixed_amount` ne s'applique que si le salaire
imposable tombe dans `[min_amount, max_amount]`. Couverture : `app/src/lib/__tests__/grid-fixed-amount.test.ts` (129 lignes).

> **La partie C n'a donc pas à réécrire ce calcul** — elle a à **le vérifier**
> contre le barème djiboutien, qui est un vrai palier fixe et pas une formule à
> taux marginal.

### 3.4 Le fichier RLS — hors périmètre de C

`66_critical_rls_isolation_fix.sql` (153 lignes) est un correctif de sécurité.
Il **ne va pas** dans la partie C (dont le territoire est `legislation_packs`,
`chart_*`, `resolve_account`, les grilles fiscales). Il relève de la **partie F**
(security, `supabase/functions/`, `SEC-02`/`ORPH-01`) ou de l'**étape 0.3**
(politiques `allow_all_%`). **Demander l'arbitrage** avant de le écrire.

## 4. Ce qu'il faut du monde avant

| Sujet | Bloque |
|---|---|
| Confirmation DGI Djibouti du barème au-delà de 2 004 999 DJF | C.2 |
| `D-11` (arabe dès la v1 ou non) | C.3 |
| Les 14 documents djiboutiens | C.3 |

## 5. État au 05/10/2026

- [x] Étape 0.5 — l'instantané est **identifié et nommé** (ce fichier)
- [ ] C.2 — écrit sous `370`, sans les deux lignes extrapolées
- [ ] Source provisoire dite dans l'en-tête
- [ ] `66_critical_rls…` arbitré (F ou étape 0.3)