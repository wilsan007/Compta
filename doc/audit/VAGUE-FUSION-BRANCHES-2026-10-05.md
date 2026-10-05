# Fusion des branches du 5 octobre 2026 — la grille ITS de Djibouti

> « Mets toutes les branches dans `main`. »
> Sept branches ne fusionnaient pas. Une seule portait du contenu absent de `main`.

## Ce que chaque branche apportait — mesuré, pas supposé

La mesure est l'écart d'**arbres** (`git diff main <branche>`), pas l'écart de
bases de fusion : une fusion brute aurait **réverti 50 000 à 440 000 lignes**
(les branches ont 121 à 173 commits de retard).

| Branche | Contenu réellement absent de `main` | Verdict |
|---|---|---|
| `origin/merge/recette-2026-10-02` | **0 fichier** | déjà absorbé |
| `origin/l3-tranche2-maillons-rpc` | 0 ; son `413_tests` est **périmé** (13/7 mesurables contre 17/3 dans `main`) | superseded |
| `claude/tva-saisie-ca3` | `198_vat_codes_ca3.sql` = le **`325`** de `main`, renuméroté | superseded |
| `claude/happy-goodall-11da15`, `quirky-goldwasser`, `backup/stash-2026-09-11` | seulement `queries/accounting.ts` et `misc.ts` — que `main` a **éclatés en répertoires** | superseded |
| `claude/import-data-column-alignment-aad9c5` | `queries.ts` (éclaté), `PlaceholderPage.tsx` (supprimé) | superseded |
| **`claude/extract-tax-salary-table-2a3267`** | `25/28/30/31` enrichis dans `main`, `38`→`98`, `44`→`99`… et **deux choses réellement absentes** | **porté en 370** |

Les migrations de cette branche avaient été **renumérotées** dans `main` au fil
des semaines. Le `65` y est `65_project_management.sql` : y remettre le barème
faisait **collision** (porte SOC-06).

## Les deux choses que `main` n'avait pas

**1. La grille ITS de Djibouti.** `main` avait le pack DJ (201) mais **aucune
grille de paie DJ**. Le numéro `370` était réservé le 04/10 et le fichier était
resté **vide de deux lignes** — non suivi, donc invisible pour la CI.

**2. Le moteur capable de la lire.** C'est le vrai défaut, et il est mesuré :

> Une grille « en table » n'a de sens que si le montant ne s'applique **que dans
> sa tranche**. `bracket` et `percentage` testaient `[min_amount, max_amount]`.
> `fixed_amount` **non**. Sur trois tranches (3 650 / 4 400 / 5 150) : tout salaire
> imposait **13 200**, y compris sous la première tranche. Sur les lignes
> extrapolées : **1 643 050** au lieu de **1 045 400**.

Le garde `inFixedBracket` est tenu par `src/lib/__tests__/grid-fixed-amount.test.ts`,
**écrit pour être rouge avant** : les 5 tests de paie ont été vus rouges
(`13200 ≠ 4400`) avant d'être verts, et celui du moteur d'IS rouge séparément.

## Ce que PostgreSQL a trouvé que la relecture n'avait pas vu

La migration ne s'exécutait **pas**. Le fichier d'origine nommait la variable
`v_grid_id` et le PL/pgSQL n'y substituait rien dans un `INSERT … VALUES` :

```
ERROR: column "v_grid_id" does not exist
HINT: Perhaps you meant to reference the column "payroll_tax_grid_lines.grid_id".
```

Deux autres défauts, corrigés en route :

- **non rejouable** — `payroll_tax_grids` n'a aucune contrainte d'unicité, donc
  le `ON CONFLICT DO NOTHING` d'origine était un **no-op** : un second passage
  créait une seconde grille et **doublait les 393 lignes**. Motif repris de la 276.
- **`pg_temp`** — une fonction `pg_temp` disparaît à la fin de la session psql ;
  la suite 370, jouée dans **une autre connexion** par la CI, n'aurait pas pu
  rappeler la fonction pour prouver la rejouabilité. Elle est donc **permanente**,
  et réservée à `service_role`.

## Mesures

| | avant | après |
|---|---|---|
| suite SQL `370` | **1/6** (5 rouges) | **6/6** |
| `grid-fixed-amount.test.ts` | **1/6** (5 rouges) | **6/6** |
| rejouabilité de la 370 | 2ᵉ grille + 393 lignes en double | 1 grille, 393 lignes, même `id` |
| `tsc -b` / `oxlint` | — | 0 / 0 |
| Vitest | 1 650 | **1 661** verts |
| G5 (suites branchées) | 149 | **150/150** |
| SOC-06 (collisions) | — | **0** sur 252 numéros |

**Validation en schéma complet, pas sur harnais.** Le doute de la première
rédaction est levé : la base neuve complète a été montée (stubs + `00_schema_dump`
+ `run-sql-migrations.mjs`) — **333 migrations, 0 erreur** — et sur cette base :

- la suite 370 rend **6/6**, avec les **vrais** helpers d'audit ;
- la grille est appliquée : `grille=1`, `lignes=393`, `pack_DJ=1`, `bucket=1` ;
- cinq contrôles CI passent : `check_anon_grants`, `check_tenant_guard`,
  `check_composite_fks`, `check_global_rows_writable`, `check_policy_duplicates`.

Base de mesure pour le moteur : Vitest sur le dépôt (1 661 verts). `plpgsql_check`
n'est pas dans l'image locale (la CI l'installe) — non exécuté ici.

## Limites

- Les deux dernières lignes (392, 393) sont une **extrapolation non officielle**,
  signalée dans leurs libellés, à faire valider auprès de la DGI.
- **La purge `allow_all_*` de l'ex-`66_critical_rls_isolation_fix.sql` : mesurée,
  et inutile.** Les migrations `47, 54, 60, 62, 64, 99` créent bien des
  `allow_all_<table> FOR ALL USING(true) WITH CHECK(true)`, et le droppeur
  générique `37` tourne **avant** elles — le doute était légitime. Mais sur la
  base neuve complète : **0 politique `allow_all_*` restante**. C'est
  `238_policy_dedup.sql` qui les retire (la plus large perd contre la plus
  étroite). La branche Djibouti **ne portait donc plus rien d'unique** : son
  barème est en `370`, sa purge est déjà faite par `238`.
- `stock_reservations` n'a toujours **aucune clé étrangère** vers `products`.
  Sujet ouvert, inchangé.
- La 370 ne crée **pas** le fichier `.xlsx` : le bucket est créé, son contenu
  reste à déposer.

## Pourquoi les branches ne sont pas « fusionnées » au sens de `git merge`

Mesuré sur chacune, contre son **ancêtre commun** (ce qu'une fusion ajouterait
réellement — et non le `diff` global, trompeur) :

| Branche | Ce qu'un `git merge` ferait |
|---|---|
| `claude/extract-tax-salary-table-2a3267` | ré-ajoute un `65_…` **en collision**, et **réécrit `payroll.ts`** — donc **annule** le correctif `inFixedBracket` |
| `backup/stash-2026-09-11` | **supprime** `38`, `44`, `71` et en modifie 240 |
| `claude/happy-goodall-11da15` | 291 fichiers, dont des versions **antérieures** de suites SQL |
| `claude/quirky-goldwasser-ba49dd`, `claude/import-data-column-alignment-aad9c5` | 72 et 10 fichiers, versions antérieures d'écrans |
| `claude/tva-saisie-ca3` | ré-ajoute un `198_…` **doublon** du `325` |
| `origin/l3-tranche2-maillons-rpc` | 32 **renommages** déjà faits (`310`→`400`…) + un `413_tests` **périmé** |
| `origin/merge/recette-2026-10-02` | 139 fichiers déjà absorbés, dont un `238` **antérieur** |

Fusionner **détruirait** `main`. Le contenu utile est **déjà dedans** : c'est
cela, « toutes les branches dans `main` ». Laisser les branches en place ne coûte
rien ; les fusionner coûterait le dépôt.