# État des lieux — les 29 accès à une propriété inexistante (2026-10-01)

**Ce que ce document est.** La veille de la dette de types a produit un effet
inattendu, et c'est le sujet ici. En typant des états `useState<any[]>` **à partir
de leur fonction de requête** (le type est déjà écrit dans le code, il suffisait de
le nommer), `tsc` a refusé **29 accès à des propriétés qui n'existent pas** dans le
type de ce que la fonction renvoie. Ce ne sont pas des erreurs de typage à
corriger : ce sont **des écrans qui lisent une donnée qui n'arrive pas**.

> **Mise à jour du 2026-10-02 — l'avertissement ci-dessous est périmé.** Les
> défauts 2 à 5 du §4 sont **corrigés et commités** (`6a6c8dd` ; la présente preuve
> dans le commit suivant). Le paragraphe est conservé tel quel parce qu'il disait
> vrai au moment de la mesure : c'est la trace de la méthode, plus une consigne.
>
> ⚠️ **Au moment de la mesure, aucune conversion n'était commitée** : le but de
cette passe est de **nommer** le défaut, pas de le maquiller. Chaque ligne
ci-dessous est vérifiée dans la source ou dans la base réelle.

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

> **Livré par `6a6c8dd`** (2026-10-02) : `getExpensePayrollIntegration()` lit
> `payroll_variable_elements` filtré sur `source = 'expense_report'`, et l'écran
> rend **trois** états — « non intégré », « en paie », « intégré ». C'est le
> troisième qui manquait : l'ancien indicateur ne pouvait pas distinguer une note
> *entrée en paie* d'une note *dont le bulletin est calculé* (`integrated` est posé
> par le moteur de bulletin, `276`). Un `integrated` à `NULL` est traité comme
> « pas encore » — mesuré en base : 35 éléments de ce `source`, dont 7 rattachés
> à un lot.
>
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

> **Livré par `6a6c8dd`** : `entryThirdPartyAccounts()` résout les comptes de tiers
> sur `journal_lines.account_tiers`, sans doublon. La colonne montre **tous** les
> tiers d'une écriture et le filtre en atteint **un** (`tiers.some(...)`) — une
> écriture peut en porter plusieurs (échéancier, TVA sur encaissement), et
> l'ancien code n'en affichait ni n'en filtrait aucun. Même famille que le défaut
> déjà corrigé dans `GrandLivreTiersPage` (`c43621e`).
>
### 2.4 `EcheancierPage` — 1 accès, bénin

`key={r.id || i}` : `id` n'est pas renvoyé par l'échéancier ; le repli `|| i` prend
donc **toujours** l'index. Aucune donnée n'est perdue — c'est un type qui ne dit
pas la vérité, pas un bug d'affichage.

> **⚠️ Cette qualification était trop douce — mesuré le 2026-10-02.** L'énoncé
> « `id` n'est pas renvoyé » est **faux** : `getEcheancier()` le **sélectionne**
> sur les deux documents sources (`'id, number, date, …'`) puis **le jette** à la
> construction de la ligne. L'identité de l'échéance **était** disponible et
> perdue en route. Et le repli sur l'index a une conséquence que « aucune donnée
> n'est perdue » ne dit pas : deux échéances **de même position dans le tri** se
> recouvrent après réordonnancement, et React réutilise alors la ligne d'une
> échéance pour une autre. Ce n'était pas un défaut d'affichage, mais une
> **identité fausse** — la qualification « bénin » est retirée.
>
> **Livré par `6a6c8dd`** : `id` est porté par la ligne construite, et l'écran est
> typé depuis sa fonction de requête (`Awaited<ReturnType<typeof getEcheancier>>`),
> donc l'accès à une propriété absente est désormais refusé par `tsc`.

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
| 2 | `EmployeeExpensesPage` — un indicateur qui dit la vérité | **donnée absente** | **corrigé le 2026-10-02** (`6a6c8dd`) |
| 3 | `Phase7DInquiryPages` — lire le tiers sur la ligne | **donnée absente** | **corrigé le 2026-10-02** (`6a6c8dd`) |
| 4 | `Phase7DInquiryPages` — déclarer le type complet de l'en-tête | dette de types | **clos le 2026-10-02** (`6a6c8dd`) |
| 5 | `EcheancierPage` — nommer l'identifiant de la ligne | cosmétique → **fausse identité** | **corrigé le 2026-10-02** (`6a6c8dd`) |
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
## 5. La garde de régression, et ce qu'elle a coûté (2026-10-02)

**`app/src/lib/__tests__/inexistent-property-accesses.test.ts` — 12 scénarios.**
Ils relisent la **source** des écrans (pas leur DOM) et échouent si la propriété
interdite y revient. Un test d'écran aurait exigé un rendu ; la faute étant une
**lecture de propriété**, elle se voit dans le texte — et c'est ce qui permet de
couvrir les trois derniers défauts sans monter une interface.

**Rouge mesuré, défaut par défaut** (chaque défaut remis en place un par fois,
puis l'état restauré) :

| Défaut rejoué | Garde | `tsc` |
|---|---|---|
| ACCES-02 `payroll_integrated` sur la note | 1 failed / 11 passed | 3 erreurs (TS2339, TS6133) |
| ACCES-03 `third_party_account` sur l'en-tête | 2 failed / 10 passed | 4 erreurs (TS2339, TS6133) |
| ACCES-05 `id` jeté, `key` sur l'index | 2 failed / 10 passed | 3 erreurs (TS2304, TS2345) |
| ACCES-06 `s.type` au lieu de `section_type` | 1 failed / 11 passed | 1 erreur (TS2339) |
| **restauré (état livré)** | **12 passed** | **0 erreur** |

`tsc` est ici un **second signal indépendant** : il attrape exactement ce que les
gardes statiques affirment. Les défauts sont donc refusés par le **compilateur**,
pas seulement par des tests — c'est la vraie raison pour laquelle on convertit un
`useState` non typé, et la preuve que le §4 ligne 4 est **clos** : ces accès sont
désormais vérifiés contre `JournalEntry`, le type que `getJournalEntries()` renvoie
réellement, au lieu d'être acceptés par un `any`.

⚠️ **La garde a fait rouge la CI, et c'est la partie instructive.** Le portillon
`audit:any-ceiling`, **gelé** (`b48780c`), refuse tout `any` nouveau. Le harnais de
simulation PostgREST — recopié du test voisin — en portait **9**, dont **un écrit
dans un commentaire** (le compteur ne retient que les positions de type `: any`,
`as any`, `<any>`, `any[]`, mais un commentaire en contient). Le compte était donc
trompeur à deux titres, et surtout **le total n'avait pas bougé** : convertir les
écrans avait retiré **9 `any` de la production** (1007 → 998) pendant que la garde
en rendait **9 aux tests** (796 → 805). La dette avait simplement **changé de
gisement** — de `src/pages` vers le fichier de test — et le plafond, gelé sur le
gisement `tests`, a rougi.

Corrigé **par le test, jamais par le plafond** : `ReponseSimulee` (`unknown`),
un `Resolveur` nommé et une interface `ChaineSimulee` typent réellement le harnais.
Mesuré après correction : tests **805 → 796**, production **998**, total **1794** —
le portillon **abaisse tout seul** son plafond, il ne se relâche jamais.
   sur-affirmation.