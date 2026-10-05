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
| C.1 | Phase 1 — **neutralité** : les comptes codés en dur (`310000`, `601000`, `355000`, `713500`, `641`/`645`/`421`/`431`…) passent par `resolve_account` ; pack fictif `ZZ` comme preuve | LOC1-01 → 58, S-10, AUD-F03, AUD-G10 | ≈ 48 j | 🟡 **LOT 1-A : LOC1-01, LOC1-02 (+ LOC1-48) faits — `380`, `381`** ; LOC1-03 → 05 à venir |
| C.2 | Barème ITS gelé, sous `370`, **sans les deux lignes extrapolées**, source provisoire dite | étape 0.5 | 1 j | 🟡 **fait le 05/10, à reprendre** |
| C.3 | Phase 2 — pack Djibouti : plan comptable national, TVA, paie, états, mentions de facture, formats bancaires ; chaque valeur sourcée `SRC-DJ-nn` | LOC2-01 → 41 | ≈ 26 j | ⬜ |
| C.4 | Pilote | — | hors charge | ⬜ |

## C.1 — LOT 1-A : le modèle de données du pack (LOC1-01 fait)

**`380_pack_model.sql` (+ `380_pack_model_tests.sql`), numéro pris sur la plage
« plan6 C (lot K, Djibouti) ».** Premier lot de C.1 : il ne touche aucun compte,
il pose le **moule** que `resolve_account` (LOC1-05) lira.

### Ce que la `380` fait

- **LOC1-01** — `legislation_packs` reçoit les 17 colonnes du modèle (niveau,
  parent, secteur, version, statut, décimales, arrondi, langues, week-end…).
- **LOC1-48** — le pack `SYSCOHADA` était à la fois une norme ET un pays
  (`country_code 'CI'`). Il devient le **référentiel** `SYSCOHADA` (niveau
  `referential`, sans `country_code`) ; `CI` reste le pack pays.
- La **hiérarchie** `secteur → pays → référentiel` est tenue par deux CHECK
  (`legislation_packs_hierarchy_chk`, `legislation_packs_country_chk`).

### La décision à confirmer : d'où viennent les parents

La contrainte de hiérarchie exige qu'un pack pays ait un parent, et les 17 packs
n'en avaient **aucun**. Le référentiel n'est **pas inventé** : il est **lu dans
la donnée** — `accounting_standard` EST déjà la norme comptable (PCG, SYSCOHADA,
IFRS, UK_GAAP…). La `380` crée donc **un référentiel par norme** (13), et chaque
pays se raccroche à la sienne. **À confirmer** : c'est la lecture retenue, elle
est data-driven, mais le cahier ne la nomme pas explicitement.

### Trois points qui ne sont pas dans le numéro

- **`ci.yml`** — la suite est branchée sous `# --- plan6:c ---` (règle R5).
- **`310_legislation_packs_readable_tests.sql`** (fixture d'une AUTRE plage) —
  son `T04` insérait un pack pays **sans parent** ; il violait la nouvelle
  `hierarchy_chk`. Corrigé en référentiel privé (le test n'observe que la RLS,
  et la FK composite interdirait un parent d'une autre société). Seul fichier
  hors plage touché ; motif : la CI l'aurait refusé.
- **FK de hiérarchie COMPOSITE** `(tenant_id, parent_code) → (tenant_id, code)` :
  la porte ISO-02 (`237`, `check_composite_fks.sql`) exige une clé composite dès
  que l'enfant porte `tenant_id`. Conséquence assumée : un pack ne se raccroche
  qu'à un parent de **SA** société (les packs globaux vivent tous sous la société
  technique `…0001`) — même forme que `company_settings_legislation_pack_code_fkey`.

### Ce que la `380` laisse à l'intégration (règle R6)

- **Régénérer `src/types/database-generated.ts`** (`npm run db:types`) : 17
  colonnes nouvelles.
- Inscrire `380` dans `AGENTS.md` / `NUMEROTATION-MIGRATIONS.md` (je n'y touche
  pas — règle R4).

### Validation — base NEUVE (`test_380i`, PostgreSQL 16, `run-sql-migrations.mjs`)

- **334 migrations, 0 erreur**, la `380` comprise.
- Suites : `380` **6/6**, `202` **13/13**, `310` **4/4**, `237` **8/8**,
  `370` **6/6** ; G5 : **151 suites branchées**, 0 collision de numéro.
- Contrôles CI verts, dont `check_composite_fks`, `check_anon_grants`,
  `check_global_rows_writable`, `check_policy_duplicates`, `check_tenant_guard`,
  `check_forced_rls_writers`, `check_status_writes`, `check_roles_opposables`,
  `check_trigger_reachability`. (Hors image locale : `check_plpgsql`, qui exige
  l'extension `plpgsql_check` — la CI l'installe.)
- **Rejouabilité** : un 2ᵉ passage de la `380` ajoute **0** ligne (`T06`).

### `LOC1-02` — les tables de données du pack (`381`)

**`381_pack_data_tables.sql` (+ suite).** Le MOULE (`380`) reçoit sa FARINE : les
**10 tables** qui portent le contenu d'un pack — `pack_sources`,
`pack_account_roles`, `pack_journal_roles`, `pack_capabilities`, `pack_holidays`,
`pack_legal_identifiers`, `pack_document_rules`, `pack_statement_templates`,
`pack_statement_lines`, `pack_other_taxes`. **Toutes globales, sans `tenant_id`**
(un pack est un référentiel de plateforme) : lecture par tout connecté, écriture
par `service_role` seul (aucune politique d'écriture). **Exemptées d'ISO-02**,
qui ne vise que les enfants portant un `tenant_id`.

Compléments sur les tables existantes : `source_id` sur les **7** tables de
valeurs (`tax_rates`, `chart_account_templates`, `payroll_tax_grids`,
`payroll_tax_grid_lines`, `payroll_legal_parameters`, `corporate_tax_grids`,
`corporate_tax_grid_lines`) ; `pack_code` + **clé composite** `(tenant_id,
pack_code)` sur les **3** grilles/paramètres — même forme que
`company_settings_legislation_pack_code_fkey`.

### Ce qui reste dans C.1

`LOC1-03` (`pack_lineage`, résolution héritée), `LOC1-04` (catalogue des rôles,
annexe B), `LOC1-05` (`resolve_account` / `resolve_journal`), puis `LOC1-06` →
`58`. **Aucun `CREATE OR REPLACE` de fonction dans les lots faits (LOC1-01,
LOC1-02) : rien à annoncer au titre de R7.**

---

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
| 05/10 | LOT 1-A (LOC1-01 + LOC1-48) | `legislation_packs` | modèle de pack : 17 colonnes ; 13 référentiels (un par norme) ; SYSCOHADA promu référentiel ; hiérarchie par 2 CHECK + FK composite ; fixture `310` corrigé ; suite branchée sous `plan6:c` | base neuve : **334 migrations / 0 erreur** ; `380` 6/6, `202` 13/13, `310` 4/4, `237` 8/8, `370` 6/6 ; contrôles CI verts ; G5 151/151 | 1a9e0a7 |
| 05/10 | LOT 1-A (LOC1-02) | `pack_*` | 10 tables du pack (globales, RLS lecture seule) ; `source_id` sur 7 tables ; `pack_code` + clé composite sur 3 grilles ; suite branchée sous `plan6:c` | base neuve : **336 migrations / 0 erreur** ; `381` 6/6, `380` 6/6, `202` 13/13, `310` 4/4, `237` 8/8, `370` 6/6 ; **10 contrôles CI verts** ; G5 152/152 | (ce commit) |