# État des lieux — les 29 accès à une propriété inexistante (2026-10-01)

**Ce que ce document est.** La veille de la dette de types a produit un effet
inattendu, et c'est le sujet ici. En typant des états `useState<any[]>` **à partir
de leur fonction de requête** (le type est déjà écrit dans le code, il suffisait de
le nommer), `tsc` a refusé **29 accès à des propriétés qui n'existent pas** dans le
type de ce que la fonction renvoie. Ce ne sont pas des erreurs de typage à
corriger : ce sont **des écrans qui lisent une donnée qui n'arrive pas**.

⚠️ **Aucune conversion n'est commitée** : le but de cette passe est de **nommer**
le défaut, pas de le maquiller. Chaque ligne ci-dessous est vérifiée dans la
source ou dans la base réelle.

## 1. La mesure

Méthode : appliquer en mémoire le typage `useState<any[]>` →
`useState<Awaited<ReturnType<typeof FN>>>` (43 états convertis), puis
`npx tsc -b --noEmit`, puis `git checkout` (le dépôt est rendu intact).

**Les 29 accès ne sont pas tous de même nature** — et c'est le point. En les
confrontant à `information_schema`, ils se séparent en deux familles :

| Nature | Accès | Ce que ça veut dire |
|---|---|---|
| **La donnée n'existe pas** — l'écran lit une propriété absente du schéma | **9** | **vrai défaut produit** |
| **Le type est incomplet** — la colonne existe en base et arrive, le type TS ne la déclare pas | **19** | dette de types, pas de bug |
| **Faux positif du codemod** | **3** | rien à corriger (voir §3) |

| Fichier | Accès | Donnée absente | Type incomplet |
|---|---|---|---|
| `src/pages/Phase7DInquiryPages.tsx` | 19 | 2 | 17 |
| `src/pages/AnalyticBalancePage.tsx` | 4 | **4** | 0 |
| `src/pages/EmployeeExpensesPage.tsx` | 2 | **2** | 0 |
| `src/pages/EcheancierPage.tsx` | 1 | 1 (bénin) | 0 |
| `src/pages/LotTraceabilityPage.tsx` | 3 | 0 | faux positif |
| **Total** | **29** | **9** | 19 |

Mise en perspective : le dépôt portait **1 811 `any` en production** (mesure du
1er octobre, plafond gelé `b48780c`). Sur ces 29 accès, **9 cachaient une donnée
qui n'arrive pas** — ce qui reste, pour une passe de rangement, un rendement qui
justifie de continuer.

## 2. Les 9 accès à une donnée absente, qualifiés

### 2.1 `AnalyticBalancePage` — 4 accès : le filtre par plan vide l'écran

```
L68  data.filter((d) => d.planId === selectedPlan || d.plan_id === selectedPlan)
L129 plans.find((p) => p.id === (d.planId || d.plan_id))
```

`getAnalyticBalance()` renvoie exactement
`{ sectionId, sectionCode, sectionName, totalDebit, totalCredit, totalAnalytic }`.
**Ni `planId`, ni `plan_id`** — vérifié dans `accounting/etats.ts`. Or l'écran **a**
un sélecteur de plan (`L89-94`, alimenté par `getAnalyticPlans()`).

Conséquence mesurable : dès qu'un plan est choisi, la condition est **toujours
fausse**, `filtered` devient **vide** et l'écran affiche **des totaux à zéro** —
un filtre qui vide au lieu de filtrer. La colonne « plan » (`L129`) reste vide
pour la même raison.

> **Livré par `dbede1a`** (commit postérieur à la publication de ce document, qui
> annonçait déjà le correctif — l'ordre est dit ici pour que la trace soit exacte) :
> l'agrégat de `getAnalyticBalance()` porte désormais `planId`, lu sur
> `analytic_sections.plan_id` (colonne vérifiée dans `information_schema`), l'écran
> ne filtre plus que sur cette propriété, et ses états sont nommés depuis leur
> fonction de requête. Garde : `src/lib/__tests__/analytic-balance-plan-filter.test.ts`
> (3 scénarios, **vus rouges** avec le défaut remis en place — 2 échecs sur 3).

### 2.2 `EmployeeExpensesPage` — 2 accès : un indicateur qui ne passe jamais au vert

```
L89 (r.payroll_integrated || r.payroll_variable_id) ? « Intégré » : « Non intégré »
```

`ExpenseReport` (`src/types/index.ts:2841`) n'a **ni** `payroll_integrated`, **ni**
`payroll_variable_id` ; et `information_schema.columns` confirme qu'**aucune**
colonne `payroll%` n'existe sur `expense_reports` (requête rendue **vide**). La
condition est **toujours fausse** : l'indicateur affiche « Non intégré » **même
quand la note est entrée en paie**.

### 2.3 `Phase7DInquiryPages` — 2 accès : la colonne « tiers » et le filtre de compte

`ThirdPartyInquiryPage` (« Interrogation tiers ») appelle `getJournalEntries()`,
qui sélectionne `'*, journal_lines(*)'` : elle renvoie des **en-têtes d'écriture**
augmentés de leurs lignes.

`journal_entries` **a bien** `number`, `description`, `date`, `total_debit`,
`total_credit` (vérifié en base) : ces 17 accès sont un **type TS incomplet**, pas
un défaut — la donnée arrive. **Un seul** nommé par l'écran n'existe sur aucune
colonne d'en-tête :

| Ligne | Accès | Où vit la donnée |
|---|---|---|
| 92 | `e.third_party_account` | **`journal_lines.account_tiers`** |
| 112 | `e.third_party_account` | idem |

Conséquence mesurable : la colonne **« tiers » est toujours `-`**, et le **filtre
de compte ne filtre rien** (`e.third_party_account` est `undefined`,
`.includes()` n'est jamais atteint). C'est la **même famille** que le défaut
corrigé le 1er octobre dans `GrandLivreTiersPage` (`c43621e`) : le métier d'un
grand livre auxiliaire vit sur les **lignes**, pas sur les en-têtes.

### 2.4 `EcheancierPage` — 1 accès, bénin

`key={r.id || i}` : `id` n'est pas renvoyé par l'échéancier ; le repli `|| i` prend
donc **toujours** l'index. Aucune donnée n'est perdue — c'est un type qui ne dit
pas la vérité, pas un bug d'affichage.

## 3. Les 3 faux positifs — et pourquoi il faut le dire

`LotTraceabilityPage` : `setResults(data?.movements || [])` — `results` reçoit bien
un **tableau**, mais le codemod a déduit son type de `traceLotDownstream(lotId)`,
dont le retour est un **objet** `{ lotId, movements, direction }`. Le type déduit
est donc l'objet, et `.length` / `.map` échouent.

**L'écran est correct ; la déduction était fausse.** Un codemod qui nomme un type
ne remplace pas un raisonnement : ce cas est écrit ici pour que la prochaine passe
ne le compte pas comme un défaut produit.

## 4. Ce que l'on en fait

| # | Cible | Nature | État |
|---|---|---|---|
| 1 | `AnalyticBalancePage` — que le filtre par plan filtre | **donnée absente** | **corrigé le 2026-10-01** (`dbede1a`) |
| 2 | `EmployeeExpensesPage` — un indicateur qui dit la vérité | **donnée absente** | à faire |
| 3 | `Phase7DInquiryPages` — lire le tiers sur la ligne | **donnée absente** | à faire |
| 4 | `Phase7DInquiryPages` — déclarer le type complet de l'en-tête | dette de types | à faire |
| 5 | `EcheancierPage` — nommer l'identifiant de la ligne | cosmétique | à faire |
| 6 | `LotTraceabilityPage` — rien à corriger côté produit | faux positif | clos |

⚠️ **Deux limites, dites.**

1. Cette passe a mesuré **les états alimentés par une fonction de requête connue**
   (43 sur 128 `useState<any[]>` de `src/pages`). Les **85 autres** (alimentés par
   plusieurs appels ou par un chemin indirect) n'ont **pas** été typés : leur lot de
   défauts est **encore caché**. C'est l'argument pour continuer la descente du
   plafond `any` — pas pour s'arrêter aux 9 trouvés.
2. Sur les 29 accès, **19 sont un type incomplet, pas un défaut** : la donnée existe
   en base et arrive. Les corriger est utile (le type protège désormais), mais ce
   n'est **pas** de la même urgence que les 9. Compter « 29 défauts » serait une
   sur-affirmation.