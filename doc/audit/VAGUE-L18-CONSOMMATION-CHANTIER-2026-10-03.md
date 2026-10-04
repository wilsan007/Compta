# L18 — La consommation de chantier, et la marge qui le sait

**Migration** `418_l18_consommation_chantier.sql` · **Suite** `418_l18_consommation_chantier_tests.sql`
· **Date** 03/10/2026 · **Branche** `partie-5-integrite-chainages`

> Lot **L18** du plan §5 Phase F — « Stock ↔ Projets … sortie de stock
> sur projet (consommation de chantier, avec imputation analytique) …
> coût de revient projet amputé ». Le référentiel §A.4 nomme ce couple
> parmi les **12 couples de modules VIDE** : « un projet ne sort rien
> du stock : consommations de chantier invisibles, coût de revient
> projet amputé ».

---

## 1. Le défaut, mesuré avant (base neuve, 282 migrations, 0 erreur)

| # | Mesure | Chiffre |
|---|---|---|
| D1 | Fonctions lisant `stock_movements` **ET** `projects` | **0** |
| D2 | Colonnes projet sur `stock_movements` | **0** |
| D3 | Fonctions qui **écrivent** `projects.actual_cost` | **0** |
| D4 | Fonctions qui **lisent** `projects.actual_cost` | **0** |

**D3/D4 est le défaut le plus grave de la série.** La colonne existe, le
budget existe, le type TypeScript existe — et personne n'écrit ni ne lit
le coût engagé. **La marge d'un projet vaut donc 0, quel que soit ce
que le chantier a dépensé.** Ce n'est pas une colonne vide : c'est un
**indicateur faux affiché comme vrai** — plus grave que la capacité
théorique de la 416, où au moins la charge existait.

## 2. Ce que la 418 pose

1. **`project_stock_cost(mouvement, projet, delta)`** — impute (`delta > 0`)
   ou retire (`delta < 0`). Un **seul** chemin pour les deux sens : deux
   `IF` dans deux endroits dériverait (faute W5). Le résultat ne descend
   **jamais** sous 0.
2. **`chain_l18_imputer_cout` + déclencheur `zz_p5_projet_cout`** — le
   compagnon, sur les **trois temps** du mouvement : INSERT, UPDATE de la
   quantité ou du coût, DELETE.

**Aucun porteur nouveau** : `stock_movements` porte déjà
`reference_type` / `reference_id` (11 valeurs relevées). On s'y range avec
la valeur `project`. Créer une colonne `project_id` aurait été un
**deuxième porteur** pour la même vérité.

## 3. Quatre décisions, et pourquoi

### 3.1 Le troisième temps du déclencheur

Un UPDATE imputerait le nouveau coût **en plus** du vieux sans retrait
préalable ; un DELETE laisserait son coût au projet. Sans ces deux gestes,
la marge ment — dans un sens pour une correction, dans l'autre pour une
annulation. T04 et T07 mesurent les deux.

### 3.2 L'idempotence est portée par le déclencheur, pas par la fonction

Un rejeu de `project_stock_cost` avec le montant imputé **doit**
ré-imputer : c'est le contrat d'une instruction. Le test le dit plutôt que
de croire à un faux garant — il mesure le vrai rejeu du **chemin produit**
(réinsertion du même couple), que l'index unique du socle refuse.

### 3.3 Le nom du déclencheur : un piège mesuré

Le déclencheur s'appelle `zz_p5_projet_cout`, **pas** `zz_l18_projet_cout`.
Ce n'est pas un goût : la suite 401 (T11) vérifie une propriété sur
`LIKE 'zz_l1_%'` — et **en SQL `_` est le caractère REMPLACEMENT** : le
`8` de `zz_l18_` matche le `_`, le trigger entrait donc dans le compte des
compagnons L1, et `zz_restate_layers_to_cump` triant après lui sur le même
événement, la propriété « aucun frère après » devenait **fausse**.

> Mesuré : la suite 401 est **verte sans la 418 et rouge avec elle** —
> vérifié sur deux bases, l'une construite sans le fichier de migration.

### 3.4 Aucun `document_links`

Même décision que la 416 §3.1 : la 451 refuse un type absent du registre
`chain_document_types`, et inscrire `projects` / `stock_movements` aurait
fait tomber le plafond de 27 et les gardes de la 453.

## 4. Résultats

**Suite 418 — 8/8 verts** (base neuve `l18_ci`, 283 migrations, 0 erreur) :

| | Scénario | Chiffre mesuré |
|---|---|---|
| T01 | le porteur générique | mouvement créé, sans colonne |
| T02 | l'imputation | `actual_cost = 120` (10 × 12) |
| T03 | le coût **matière** | `actual_cost = 40` (5 × 8) — prix de vente du même article : **200**, non imputé |
| T04 | la correction remplace | 100 → **40** (et non 140) |
| T05 | une entrée n'impute rien | `actual_cost = 0` |
| T06 | l'isolation | A = **150**, B = **0** |
| T07 | le retrait borné | 90 → **0**, jamais négatif |
| T08 | le surcoût | **p95 = 4,951 ms** pour 50 ms · `actual_cost = 600` |

**Non-régression, base neuve, ordre de la CI** — **283 migrations, 0 erreur**,
**22 suites vertes, 248 verdicts, 0 rouge** : 234 (8) · 236 (17) · W9
263/264/265/266 (13+11+10+34) · 400→413 (15, 12, 12, 11, 10, 12, 7, 8, 6,
8, 8) · 415 (8) · 416 (8) · 417 (8) · **418 (8)** · 450 (14).

**12 portes vertes** · **G5 : 106/106** · **418 rejouable** (rejouée, 0
erreur, 8/8). Aucune modification de schéma → `db:types` sans écart.

## 5. Limites dites

1. **Aucune écriture comptable.** La 418 impute le **coût matière** sur
   le projet ; elle ne le porte pas dans la comptabilité. Un chantier qui
   consomme ne produit pas d'écriture — c'est une autre chaîne (L19,
   production ↔ trésorerie).
2. **L'imputation analytique n'est pas posée.** Le plan la mentionne
   (« avec imputation analytique ») ; elle supposerait
   `stock_movements.analytic_section_id`, que la 304 n'a posé que sur les
   lignes de facture et d'achat. **Limite dite, pas oubliée** : c'est la
   tranche 2.
3. **`actual_cost` est un compteur, pas une marge.** Il double les
   dépenses si un même mouvement est imputé à deux projets
   volontairement — ce que rien n'interdit aujourd'hui.
4. **Le déclencheur ne filtre pas les mouvements déjà imputés** : la
   garde d'imputation unique serait une contrainte sur
   `(reference_type, reference_id)` — l'index unique du socle la pose
   déjà pour le produit et le sens.

## 6. Suite

Le couple `stock ↔ projets` est ouvert : **le projet consomme, et la marge
le sait**. Restent **L19** (production ↔ trésorerie, l'engagement), la
tranche 2 de L18 (imputation analytique), **L20** (régénération) et
**L23-b/c**.