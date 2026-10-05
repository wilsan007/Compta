# Reprise 2 — alignement des colonnes sur 10 écrans (déposé pour la partie D)

> **Étape 0.5 du** [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md).
> Ce fichier **nomme** ce qu'il y a à reprendre. Il ne porte pas le code : la
> partie D l'écrit, écran par écran, dans son territoire.

## 1. La source, à l'identique

| | |
|---|---|
| Branche gelée | `claude/import-data-column-alignment-aad9c5` |
| **Commit source** | **`f5cda2f`** — `WIP(1.0) : instantane du travail non commit du worktree, mis en pause` |
| Tag de sûreté | `sauvegarde/2026-10-03/claude/import-data-column-alignment-aad9c5` |
| Base | `b9261f2`, puis `d88729a` |
| Statut | **gelé**, jamais fusionné, jamais poussé sur `main` |

```bash
git show f5cda2f --stat
git show f5cda2f -- app/src/pages/BOMPage.tsx
```

## 2. Les 10 écrans

| Écran | Lignes ± | Nature du balayage |
|---|---|---|
| `app/src/pages/BOMPage.tsx` | 58 | large — alignement des en-têtes |
| `app/src/pages/FixedAssetsPage.tsx` | 46 | large |
| `app/src/pages/PriceListsPage.tsx` | 50 | large |
| `app/src/pages/RoutingsPage.tsx` | 66 | large |
| `app/src/pages/ChartAccountsPage.tsx` | 6 | mécanique |
| `app/src/pages/CreditNotesPage.tsx` | 6 | mécanique |
| `app/src/pages/LettragePage.tsx` | 6 | mécanique |
| `app/src/pages/PurchaseCreditNotesPage.tsx` | 6 | mécanique |
| `app/src/pages/QuotesPage.tsx` | 6 | mécanique |
| `app/src/pages/SearchEntriesPage.tsx` | 6 | mécanique |

**10 fichiers, 132 lignes ajoutées, 124 retirées.**

## 3. Ce que la partie D doit en faire

Tâche **D.3** du plan §7, charge **1 j** :

1. **Vérifier d'abord l'état réel.** `4c8e642` et `80775ed` ont modifié
   `CreditNotesPage.tsx` depuis le gel (`main..HEAD`, +28 lignes sur ce seul
   fichier) : le patch de `f5cda2f` s'y applique-t-il encore ? **Mesurer, ne pas
   supposer.**
2. **Appliquer par module, en lots d'un jour** (règle du §1 : *« D livre ces
   balayages par module et en premier, en lots d'un jour, pour que le conflit
   soit court »*). Ordre proposé : les 6 écrans mécaniques (≈ 36 lignes) en un
   lot, puis un lot par écran large.
3. **Le conflit est le risque, pas le code.** `CreditNotesPage.tsx` est touché
   par la partie E (ventes) et par A (chaînages). D.3 passe **avant** elles.
4. **Rejouer la suite d'écrans** après chaque lot : `npx vitest run
   src/__screen__/` et le job `screen-path`.

## 4. Ce qu'il faut du monde

Rien pour D.3. Le gel est la seule contrainte : le travail existe, il n'est
apporté par personne.

## 5. État au 05/10/2026

- [x] Étape 0.5 — l'instantané est **identifié et nommé** (ce fichier)
- [ ] D.3 — les 6 écrans mécaniques (1 lot)
- [ ] D.3 — les 4 écrans larges (1 lot par jour)
- [ ] `screen-path` vert après chaque lot