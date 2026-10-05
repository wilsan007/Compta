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

Base de mesure : conteneur PostgreSQL 17 éphémère, harnais reproduisant les
contraintes `CHECK` de `36_tax_grids_payroll_corporate.sql`. **Limite dite** : ce
n'est pas une base neuve du dépôt (330+ migrations) — la 370 ne touche que cinq
tables, mais son intégration au schéma complet reste à confirmer par la CI.

## Limites

- Les deux dernières lignes (392, 393) sont une **extrapolation non officielle**,
  signalée dans leurs libellés, à faire valider auprès de la DGI.
- `main` **n'a toujours pas** la purge `allow_all_*` de l'ex-`66_critical_rls_isolation_fix.sql`
  (71 tables). Non Fusionnée ici : elle exige une **mesure sur base neuve** —
  savoir si la 238 a déjà retiré ces politiques — et un numéro pris. **Sujet ouvert.**
- `stock_reservations` n'a toujours **aucune clé étrangère** vers `products`.
  Sujet ouvert, inchangé.
- La 370 ne crée **pas** le fichier `.xlsx` : le bucket est créé, son contenu reste à déposer.