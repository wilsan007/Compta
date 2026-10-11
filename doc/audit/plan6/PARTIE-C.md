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
| C.1 | Phase 1 — **neutralité** : les comptes codés en dur (`310000`, `601000`, `355000`, `713500`, `641`/`645`/`421`/`431`…) passent par `resolve_account` ; pack fictif `ZZ` comme preuve | LOC1-01 → 58, S-10, AUD-F03, AUD-G10 | ≈ 48 j | 🟡 **LOC1-01 → 06 (+ LOC1-48) faits — `380`→`386`** ; **LOC1-07 : `387`/`388`** ; **LOC1-08 : `389`/`390`** ; **LOC1-09 : journaux en dur `391`→`393` — TERMINÉ** ; **LOC1-10 : garde-fou E01 livré et câblé (`check-country-neutral.mjs`) — 41 occurrences front + 24 SQL mesurées et gelées** ; reste → 58 à venir |
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

### `LOC1-03` — la résolution héritée (`382`)

**`382_pack_resolution.sql` (+ suite).** La hiérarchie `secteur → pays →
référentiel` devient **utilisable** :
- `pack_lineage(code)` remonte la chaîne (depth 0 = le pack lui-même) ;
- `tenant_pack_code(tenant_id)` rend le pack effectif d'une société ;
- `pack_effective_value(code, colonne)` résout une valeur de format — **le plus
  spécifique gagne** — avec une **liste close** de colonnes autorisées ;
- `v_pack_effective` expose, pack actif par pack actif, les formats **résolus** ;
- `pack_account_role` / `pack_journal_role` : **le plus profond gagne** ;
- `pack_holidays_of` : **l'union** de la lignée (le pays AJOUTE au référentiel).

C'est le modèle des leaders : *country chart sur operating chart* (SAP), et
`parent_id` + `country_id = None` pour la base générique (Odoo). **Décision de
hiérarchie, arrêtée** : le référentiel est **la norme comptable, sans pays**
(Odoo `country_id = None` ≡ notre `level='referential'`), le pays en hérite, le
secteur hérite du pays ; Djibouti sera repointé vers `PCN-DJ` en C.3 (aujourd'hui
provisoire → `PCG`, comme le dit déjà la `201`).

**Point de sécurité** : `tenant_pack_code` est **SECURITY INVOKER** (pas
DEFINER). `tenants` est en RLS stricte ET forcée (`id = current_tenant_id()`),
donc la RLS fait la garde ; en DEFINER la porte `ci/check_tenant_guard.sql` la
refusait (mesuré).

### `LOC1-04` — le catalogue fermé des rôles (`383`)

**`383_role_catalog.sql` (+ suite).** Les deux catalogues qui rendent la
neutralité possible : `account_role_catalog` (**67** rôles de comptes) et
`journal_role_catalog` (**8** rôles de journaux), repris de l'**annexe B** du
cahier. Le code ne demande plus un numéro de compte mais un **rôle**
(`CLIENTS`, `TVA_COLLECTEE`, `VENTES_MARCHANDISES`…) ; chaque pack mappe ses
rôles vers ses comptes. Les tables du pack y sont **raccrochées par clé
étrangère** : un rôle non catalogué est **refusé**. Même mécanisme que les
*SystemAccounts* de Xero, les `property_*_account_id` d'Odoo et l'attribut
« role » du *group chart* de SAP.

### `LOC1-05` — `resolve_account` / `resolve_journal` (`384`)

**`384_resolve_account.sql` (+ suite).** Le **point d'appel unique** du code vers
un compte. `resolve_account(tenant, rôle, contexte)` résout dans l'ordre :
**objet métier** (collectif d'un client, compte de vente d'une catégorie…) →
**société** (`tenant_account_roles`) → **pack effectif** (lignée) → sinon **échec
explicite** `ROLE_NON_MAPPE` ; le compte doit **exister dans le plan**
(`COMPTE_ABSENT`). `resolve_journal` suit le même schéma. Surcharges société sous
RLS (`tenant_id = current_tenant_id()`), et `resolve_account` /
`resolve_account_from_context` sont **SECURITY INVOKER** : la RLS fait la garde
(la porte `check_tenant_guard` refuse un DEFINER à uuid société sans garde).

### `LOC1-06` — les 4 triggers de ventes/achats/règlements (`386`)

**`386_roles_sales_purchases.sql` (+ suite).** Les quatre déclencheurs qui passent
une facture de vente, une facture d'achat, un encaissement et un décaissement ne
portent plus de numéro de compte : ils **demandent un rôle**
(`resolve_account(…,'CLIENTS',{customer_id})`, `resolve_journal(…,'JOURNAL_VENTES')`…).

- **Prérequis, fait en `385`** : le pack PCG porte ses rôles (sinon la résolution
  échoue sur `ROLE_NON_MAPPE`).
- **Pont de phase 1** : une société **sans pack** retombe sur le pack **par
  défaut** (FR) — sinon les fixtures de test, qui n'en posent aucun, casseraient.
- **Recette tenue** : `102_trigger_tests.sql` rejoué, **17/17 verts, inchangé**
  (écritures identiques — dont facture → `VT` et la ventilation TVA). La suite
  `386` prouve en plus la **neutralité** : plus aucun numéro de compte en dur.
- **Ce qui n'a PAS changé, volontairement** : la TVA continue de passer par
  `vat_account_mapping` (par code de taux) — seul le **repli** est un rôle ; la
  trésorerie des règlements reste `treasury_for_payment`. Les changer modifierait
  les écritures, ce que la recette interdit.

### `LOC1-07` — opérations : tranche POS (`387`)

**`387_roles_operations.sql` (+ suite).** La **clôture de caisse** (`post_pos_session_on_close_multi`,
le seul des deux câblé) ne porte plus `'707000'`, `'445710'` ni le journal
`'POS'` : elle demande ses **rôles** (`JOURNAL_POS`, `VENTES_MARCHANDISES`,
`TVA_COLLECTEE`). Deux **rôles de journaux** sont AJOUTÉS au catalogue
(`JOURNAL_POS`, `JOURNAL_PRODUCTION`) — le pack PCG ne les portait pas —,
conformément à la règle de LOC1-04. ⚠ Les comptes d'**écart de caisse**
(`658000`/`758000`) restent des littéraux : aucun rôle du catalogue ne les
nomme — à trancher avec l'expert-comptable.

**`388_roles_stock_production.sql` (+ suite)** — le **mouvement de stock** et la
**clôture d'ordre de fabrication** passent par les rôles (`STOCK_MATIERES`,
`ACHATS_MATIERES`, `STOCK_PRODUITS_FINIS`, `PRODUCTION_STOCKEE`,
`JOURNAL_STOCK`, `JOURNAL_PRODUCTION`) — **écritures identiques** (le pack rend
exactement les comptes d'avant). Validé : `388` 5/5, suites stock `173`/`240`/
`241`/`230` + `102_trigger_tests` OK.

**Décisions du 06/10 — ne pas « corriger » le code pour coller au cahier.**
- **Pas de compte de stock « par type d'article »** : `products.type` ne prend que
  `'service'`/`'stock'` ; la taxonomie marchandise/matière/produit fini **n'existe
  pas**. La nature est portée par le compte **explicite**
  (`products.stock_account_code`, puis sa catégorie) — la « table de
  paramétrage » ; le repli est un rôle.
- **`713550` → `713500`** : déjà le cas (le cahier citait un compte périmé).
- **`613000` (location) n'est PAS remplacé par `611000` (sous-traitance)** : deux
  natures économiques distinctes ; on ne les confond pas.
- **`resolve_variation_account` garde `'603000'`** : aucun rôle du catalogue ne
  nomme la variation GÉNÉRIQUE ; le remplacer changerait les écritures. À trancher.

**Ce qui reste de `LOC1-07`** : la **paie** — `create_journal_on_payroll_validate`
n'est qu'une enveloppe, et les comptes vivent dans `payroll_post_run`, c'est‑à‑dire
le **module paie = territoire de la Partie B** (R3/R7) : **demande à transmettre**,
pas une édition de C.

### `LOC1-08` — clôture, affectation, écarts (`389`, puis `390`)

**`389_roles_closing.sql` (+ suite)** — l'**affectation du résultat**
(`allocate_result`) et les **écarts de lettrage** (`generate_residual_entry`)
demandent leurs rôles (`RESULTAT_BENEFICE`/`RESULTAT_PERTE`, `ESCOMPTES_ACCORDES`,
`PERTES_CHANGE`, `GAINS_CHANGE`, `PERTES_CREANCES_IRRECOUVRABLES`, `JOURNAL_OD`).
Un **rôle de journal ajouté** : `JOURNAL_CLOTURE` → `CL` (le journal de clôture
n'avait pas de rôle). **Écritures identiques** — la recette « balance d'ouverture
N+1 identique à l'actuelle au centime » est tenue par construction. Validé :
`389` 5/5, suites `179`/`175` OK.

**`390_roles_close_fiscal_year.sql` (+ suite)** — `close_fiscal_year` : journaux
`CL` (clôture) et `AN` (à-nouveaux), et comptes de résultat `120000`/`129000`,
**par les rôles**. **Écritures identiques**. Validé : `390` 4/4, suites `179`/`175`
OK — la recette « balance d'ouverture N+1 identique à l'actuelle au centime » est
tenue.

⚠ **Ce que `390` ne touche pas** : la SÉLECTION des comptes à solder reste par
**classe** (`~ '^[67]'`) — c'est `LOC1-11`, pas 08 (le cahier renvoie au gabarit
`income_statement`, `LOC1-38`, non construit).

**Non fait, et pourquoi** : `generate_depreciation_entry` — ses littéraux
`280000`/`681000` ne correspondent **pas** aux rôles (`AMORTISSEMENTS` est par
CATÉGORIE ; le pack porte `681100`). Le remplacer **changerait les écritures** :
à trancher (même principe que `613000` — on ne « corrige » pas pour coller au
cahier).

### `LOC1-09` — les derniers journaux en dur (`391`, `392`, `393`) — **TERMINÉ**

**`391_roles_journaux_restants.sql` (+ suite) — tranche 1.** Les 4 triggers de
ventes/achats/règlements (`386`), le stock/POS (`387`/`388`) et la clôture
(`389`/`390`) étaient déjà faits. Une **détection sur la base** (patron
`<code>, 'draft'`) a trouvé **9 fonctions** qui écrivaient encore un code de
journal littéral. Cette tranche en traite **3** :
`bank_account_post_opening_balance` (journal `AN`),
`stock_initial_post_opening_entry` (journal `AN`),
`post_exchange_gain_loss_on_payment` (journal `OD`). **Écritures identiques**.
`391` 4/4 ; suites `173`/`211`/`102` OK.

**`392_roles_journaux_restants_2.sql` (+ suite) — tranche 2.**
`integrate_expense_report_on_approval` et `post_deferred_charge` passent par le
rôle (journal `OD`). `392` 4/4 ; suites `211`/`102` OK.

**`393_roles_journaux_restants_3.sql` (+ suite) — tranche 3, la dernière.**
`credit_note_guard` (avoir client → `JOURNAL_VENTES`),
`purchase_credit_note_guard` (avoir fournisseur → `JOURNAL_ACHATS`),
`generate_depreciation_entry` et `revaluate_currency_balances` (→ `JOURNAL_OD`)
demandent leur rôle. **Écritures identiques** (le pack rend `VT`, `AC`, `OD`).
`393` 4/4 ; suites `102`/`180`/`192`/`197`/`211`/`213`/`226`/`255`/`260`/`309`/
`317`/`353` + chaînes `400`/`403`/`412` OK.

> ⚠ Dans `generate_depreciation_entry`, **seul le journal** passe par le rôle. Ses
> **comptes** (`681200`/`281000`, ou ceux de la fiche) restent des comptes : le
> référentiel porte `681100` et `280000`, et les rôles de la `383` sont rangés
> **par catégorie**. Les réécrire **changerait les écritures** → arbitrage, pas
> une correction de tranche.

**LOC1-09 est clos : plus aucune fonction n'écrit un code de journal littéral.**
Le garde de la suite `391` (`T03`) a été **resserré** — sa liste blanche est
maintenant **vide** : la moindre réapparition d'un journal en dur est une
**nouvelle** fonction, donc rouge. La suite `392` (`T02`) ne borne plus qu'un
majorant (les 4 fonctions de la tranche 3), et `393` (`T02`) constate le
**reste à zéro**. R7 déjà vérifié : aucune branche `plan6/*` ne les définit.

**Reste en dur, hors LOC1-09 — ce sont des COMPTES (LOC1-10/11)**, pas des
journaux : `890000` (« Bilan d'ouverture »), `411000`, `401000`, `666000`,
`766000`, `486000`, `487000`, et `603000` dans `resolve_variation_account`.
Le prochain lot (`LOC1-10`) attaque précisément cette liste, **côté écritures**.

### `LOC1-10` — les comptes en dur, et le garde-fou **E01**

Le cahier demande de « supprimer les comptes en dur côté front » (annexe A.2) et
donne pour **recette** : *le garde-fou E01 passe sur `app/src`*. Ce garde-fou
**n'existait pas** — `scripts/check-country-neutral.mjs` est neuf, et c'est la
première livraison de la tâche.

**La règle, telle quelle (annexe E).** Un littéral de **3 à 6 chiffres**
(`'[1-9]\d{2,5}'`) **utilisé comme compte** : affecté à un nom `*account*`,
`*compte*`, `*collectif*`, ou passé à `getSolde`. Deux gisements, **deux
compteurs** :

* `front` — `app/src/**/*.{ts,tsx}` ;
* `sql` — les définitions **effectives** (`pg_proc.prosrc`, schéma `public`).
  C'est le gisement de fond : c'est un **trigger** qui choisit `'641000'`, le
  front ne fait que recopier son choix.

Plafond **GELÉ** dans `app/.country-neutral-ceiling.json` — même doctrine que
`check-any-ceiling.mjs` : une hausse casse la CI, une baisse **abaisse** le
plafond automatiquement ; le compteur ne peut que descendre. Branché **deux
fois** : `--front-only` dans `lint-typecheck` (ce job n'a pas de base) et complet
dans `db-integration`, **avant les suites** (ce sont elles qui créent des
fixtures — même ordre que `check_bt_grid`).

**Mesure du 11/10** (base neuve, 347 migrations) : **41** occurrences au front
(20 fichiers) et **24** en SQL (14 fonctions).

| Gisement | Le gros du compte |
|---|---|
| front (41) | `ProductsPage` 6, `FixedAssetsPage` 6, `queries/payroll.ts` 5, `RegularizationPage` 4, `InvoicesPage`/`CreditNotesPage`/`CustomersPage`/`SuppliersPage`/`FiscalYearClosurePage` 3, `ChartAccountsPage` 2 |
| SQL (24) | `credit_note_guard` 3, `purchase_credit_note_guard` 3, `propagate_analytic_section` 3, `post_pos_session_on_close` 2, `post_exchange_gain_loss_on_payment` 2, `generate_depreciation_entry` 2, `treasury_for_payment` 2, `backfill_third_party_accounts` 2, puis `letter_advance_invoice`, `ensure_pos_payment_methods`, `sync_customer/supplier_third_party_account`, `sync_commitments_on_purchase_order` |

**Deux registres d'exceptions motivées** (le dépôt a le même usage avec
`sql/ci/expected_failures.sql` : une exception se déclare, avec sa raison) :
côté front un `placeholder="12345"` — exemple de code banque, pas un compte ;
côté SQL `seed_standard_chart(_unchecked)` — le **gabarit du plan comptable**,
dont les littéraux **sont** le plan semé (colonnes `code`/`name`). On ne
« résout » pas le plan par lui-même : **son propriétaire est `LOC1-13`**.

**Ce qui manque pour vider les compteurs** (mesuré, pas supposé) :

1. **Le résolveur côté front n'existe pas.** `resolveAccount` / `usePack` sont
   absents de `app/src` (vérifié) : aucune des 41 occurrences ne peut être
   remplacée avant qu'il existe. C'est la **tranche suivante** de `LOC1-10`, et
   elle vaut pour toutes les autres tâches qui produisent des comptes (LOC1-13,
   LOC1-26, LOC1-38…).
2. **Les 24 occurrences SQL** sont dans les fonctions d'écriture — le territoire
   de C. Elles se traitent **fonction par fonction**, comme `LOC1-09` : mêmes
   rôles déjà en place, écritures à vérifier identiques, compteur qui **baisse**
   à chaque tranche (le garde-fou le prouve).
3. **Six fichiers du front ne sont pas à C** (R3) : `queries/payroll.ts` (paie →
   **D1**, partie B), `ProductsPage` (**D2**, partie E), `InvoicesPage` /
   `CreditNotesPage` (ventes), `SuppliersPage` / `CustomersPage` (tiers). Les
   demandes sont écrites ci-dessous, elles ne se traitent pas ici.

### Ce qui reste dans C.1

Le reste de `LOC1-07` (paie) puis `LOC1-08` → `58` : clôture, monnaie/arrondis,
fiscalité, états, capacités, packs `ZZ`… **R7** : `386`/`387`/`388` réécrivent des
fonctions existantes ; leur nom n'est écrit par aucune autre branche `plan6/*`
(vérifié).

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

## Demandes hors territoire (règle R3) — **à transmettre par l'intégration**

> Une partie n'édite pas hors de son territoire : elle **écrit la demande ici**,
> l'intégration la transmet au propriétaire (R3).

| # | Vers | Demande | Pourquoi ce n'est pas C |
|---|---|---|---|
| **D1** | **Partie B** (paie) | Réécrire sur les **rôles** les comptes d'écriture de la paie, dans **`payroll_post_run`** — `create_journal_on_payroll_validate` n'est qu'une **enveloppe** qui l'appelle. Rôles prêts : `SALAIRES_BRUTS`(641000), `CHARGES_SOCIALES_PATRONALES`(645000), `PERSONNEL_REMUNERATIONS_DUES`(421000), `ORGANISME_SOCIAL`(431000), `ETAT_IMPOT_SALAIRES`(442000), `JOURNAL_PAIE`. | Le module paie est le **territoire de la Partie B** (`lib/payroll*`, écrans de paie). C a livré le catalogue, `resolve_account`/`resolve_journal` et les rôles du pack : il ne reste qu'à les appeler. ⚠ `JOURNAL_PAIE` n'est **pas encore mappé** dans le pack PCG (le cahier le note « à créer ») — B doit trancher son code de journal. |
| **D2** | **Partie E** (opérations) | Si la **taxonomie d'article** (marchandise/matière/produit fini) est voulue, elle touche `products` — table d'E. C la consommerait par le rôle. | `products` est le territoire de la Partie E (stock, production). Décision du 06/10 : **pas de compte de stock par type** tant que la taxonomie n'existe pas. |
| **D3** | **Partie E** (ventes/articles) et **Partie B** (paie) | Les comptes en dur **côté front** des écrans qui sont les vôtres : `ProductsPage.tsx` (`707000`/`607000`/`310000`), `InvoicesPage.tsx` et `CreditNotesPage.tsx` (`706000`/`707000`), `SuppliersPage.tsx`/`CustomersPage.tsx` (`401000`/`411000`) — 23 occurrences, mesurées par le garde-fou (`node scripts/check-country-neutral.mjs --front-only --list`). Le remplacement suppose le résolveur **`resolveAccount` côté front**, que C livre (LOC1-10, tranche suivante) : E et B n'ont ensuite qu'à appeler. | Ces écrans sont leur territoire (R3). C fournit **l'outil de mesure** (plafond gelé, la dette ne peut plus grossir) et le résolveur ; la substitution, elle, se fait chez le propriétaire de l'écran. |

## Trouvé en chemin (11/10) — ce que la validation élargie a mis au jour

La clôture de `LOC1-09` a été l'occasion de **passer toutes les suites du dépôt**
(et non les seules suites du lot) sur une base neuve, plus les contrôles
`sql/ci/check_*` **au-delà des 10 habituels**. Quatre constats — trois corrigés,
un à vous.

**1. `check_bt_grid` est ROUGE, et il l'était DÉJÀ avant la `393`.** Sur base
neuve, la grille BT donne **367 tables / 56 sans RLS forcée / 84 à moins de
4 commandes** là où les plafonds datés du fichier disent **365 / 54 / 82**. La
même mesure sur `main`, base neuve aussi, donne **365 / 54 / 82** : la grille y
est **verte**. L'écart est donc celui de la branche, et il tient à **deux
tables** — `tenant_account_roles` et `tenant_journal_roles` (posées par la
`383`) : elles portent `tenant_id`, la RLS **activée mais non forcée**, et **une**
politique `ALL`.

`FORCE ROW LEVEL SECURITY` a été **essayé et mesuré** : il ramène bien
`rls_sans_force` à 54, mais il **casse** `ci/check_forced_rls_writers.sql` **et**
les suites `383`/`384`/`385` — l'écriture de ces catalogues passe par des
fonctions qui écrivent pour la société **passée en paramètre**, jamais pour celle
du contexte.

> **À trancher** : **(a)** reprendre la chaîne d'écriture des deux catalogues
> (garde d'écriture + société de contexte) pour pouvoir les **forcer**, puis
> relever les trois plafonds datés — c'est ce que demande la règle ISO-04 du
> dépôt (« une table cloisonnée porte la RLS forcée ») ; ou **(b)** relever les
> trois plafonds avec leur **raison datée** et tracer la dette. C'est un sujet de
> la `383`, pas des journaux : il ne se règle pas par une tranche de LOC1-09.

**2. Trois suites datées ne suivaient plus l'état de la branche** — elles
n'étaient pas jouées par les validations précédentes, qui ne lançaient que les
suites du lot :

| Suite | Ce qu'elle attendait | Ce que la branche porte | Cause |
|---|---|---|---|
| `383` T02 | **8** rôles de journaux | **11** | `387` : `JOURNAL_POS`, `JOURNAL_PRODUCTION` ; `389` : `JOURNAL_CLOTURE` |
| `385` T02 | **7** rôles au référentiel PCG | **10** | les deux rôles de `387` + celui de `389` |
| `384` T04 | `COMPTE_ATTENTE` = rôle **non mappé** | il l'est devenu | la `387` lui a donné une correspondance |

Les deux premières sont **alignées sur l'état réel** (le catalogue et le pack
sont des **super-ensembles datés** : ils ne reculent pas, ils suivent les
tranches). Pour la troisième, le témoin du « non mappé » est désormais
`AMORTISSEMENTS` — avec `IMMOBILISATIONS`, le seul rôle du catalogue que le
référentiel PCG ne mappe pas (65 = 67 − 2, ce que `385` T01 dit déjà).
`383` 6/6, `384` 7/7, `385` 6/6.

**3. Les gardes de `391`/`392`/`393` dépendaient de l'ORDRE des suites.** Elles
cherchent les journaux en dur dans les fonctions de `public` — et elles
trouvaient les **fixtures** d'autres suites : `325` crée `_i8_piece`, `462` crée
`_vc_entry`, et les deux tournent **avant** `plan6:c` en CI (lignes 775 et 1861).
Le patron exclut maintenant les helpers `_…`, convention du dépôt pour les
fixtures : **le garde ne parle que des fonctions de production** (sur base neuve,
sans suite, il en trouve **zéro**).

**4. `105_rls_tests` ne pouvait plus semer `legislation_packs`.** La `380` lui a
donné **deux CHECK croisés** (niveau × pays, niveau × parent) que le semeur
générique ne sait pas produire : il posait `level = 'country'` sans
`country_code`, la ligne était **refusée**, et la table sortait « **non
alimentée** » — donc **son isolation n'était plus prouvée**. Le semeur a
désormais un **cas dédié** (niveau `sector`, pays `FR`, `parent_code` = son propre
code, recollé ensuite par la passe H02) : `105` repasse à **356 tables / 356
alimentées / 0 fuite**, et l'isolation de `legislation_packs` est **réellement
vérifiée** — ce qu'elle n'était plus depuis la `383`.

**Et deux faux positifs, écartés par la mesure.** Le run complet signale aussi
`234_webhook_queue` et `243_payroll_and_employee_name` : ce sont les suites que
la `105` **pollue** (son semeur générique insère une ligne dans **chaque** table
cloisonnée, y compris `employees` — fiche sans prénom ni nom — et la file de
webhooks). Jouées sur base neuve **sans** `105`, elles passent toutes les deux
(vérifié). `436` et `450` sont du même genre — sensibles à l'état laissé par les
suites précédentes : `450` échoue **même sur `main`** quand on la joue seule.

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
| 05/10 | LOT 1-A (LOC1-02) | `pack_*` | 10 tables du pack (globales, RLS lecture seule) ; `source_id` sur 7 tables ; `pack_code` + clé composite sur 3 grilles ; suite branchée sous `plan6:c` | base neuve : **336 migrations / 0 erreur** ; `381` 6/6, `380` 6/6, `202` 13/13, `310` 4/4, `237` 8/8, `370` 6/6 ; **10 contrôles CI verts** ; G5 152/152 | fca2abd |
| 05/10 | LOT 1-A (LOC1-03) | `pack_lineage` | résolution héritée : `pack_lineage`, `tenant_pack_code` (INVOKER), `pack_effective_value`, `v_pack_effective`, `pack_account_role/journal_role`, `pack_holidays_of` ; suite branchée sous `plan6:c` | base neuve : **336 migrations / 0 erreur** ; `382` 6/6, `381` 6/6, `380` 6/6, `202` 13/13, `310` 4/4, `237` 8/8, `370` 6/6 ; 9 contrôles CI verts | 5605d53 |
| 05/10 | LOT 1-B (LOC1-04) | `*_role_catalog` | catalogue fermé : **67** rôles de comptes + **8** rôles de journaux (annexe B) ; les tables du pack y sont raccrochées par clé étrangère (rôle non catalogué refusé) ; suite branchée sous `plan6:c` | base : `383` 6/6 ; **11 contrôles CI verts** | fbfc978 |
| 05/10 | LOT 1-B (LOC1-05) | `resolve_account` | point d'appel unique : objet métier → société → pack (lignée) → échec explicite (`ROLE_NON_MAPPE` / `COMPTE_ABSENT`) ; `resolve_journal` ; surcharges société sous RLS ; INVOKER (la RLS fait la garde) ; suite branchée sous `plan6:c` | base : `384` 7/7 ; **10 contrôles CI verts** ; G5 155/155 | 1be0b0d |
| 05/10 | prérequis LOC1-06 (`LOC1-13`) | `pack_account_roles` | **65 rôles de comptes + 7 rôles de journaux** semés sur le référentiel **PCG** (annexe B) ; `FR` en hérite par la lignée ; recette `LOC1-05` verte (société FR → `CLIENTS` = `411000`) | base : `385` 6/6 ; **10 contrôles CI verts** | 0294fdf |
| 05/10 | LOT 1-B (LOC1-06) | 4 triggers | facture de vente, facture d'achat, encaissement et décaissement passent par les **rôles** (`resolve_account`/`resolve_journal`) ; **pont** « société sans pack → pack par défaut » ; recette `102_trigger_tests` **17/17 inchangé** ; suite `386` prouve l'absence de numéro en dur | base : `386` 5/5 ; **10 contrôles CI verts** ; suites d'écritures (170/175/178/180…) OK | c57a9d3 |
| 05/10 | LOC1-07 (tranche POS) | `post_pos_session_on_close_multi` | la clôture de caisse demande ses rôles (`JOURNAL_POS`, `VENTES_MARCHANDISES`, `TVA_COLLECTEE`) ; **2 rôles de journaux ajoutés** au catalogue (`JOURNAL_POS`, `JOURNAL_PRODUCTION`) et au pack PCG | base : `387` 5/5 ; suites POS `219`/`250`/`281` OK ; **10 portes CI vertes** | 542f624 |
| 06/10 | LOC1-07 (tranche stock/production) | `create_journal_on_stock_movement`, `create_stock_on_manufacturing_complete`, `resolve_stock_account` | stock et OF sur les rôles (journal `ST`/`OF`, comptes `601000`/`310000`/`355000`/`713500`) ; **écritures identiques** ; décisions du 06/10 documentées (pas de taxonomie d'article ; `613000` intact ; variation `603000`) | base : `388` 5/5 ; suites stock `173`/`240`/`241`/`230` + `102` OK ; **10 portes CI vertes** | 2b56d46 |
| 06/10 | LOC1-08 (tranche affectation/écarts) | `allocate_result`, `generate_residual_entry` | affectation du résultat et écarts de lettrage sur les rôles ; **rôle `JOURNAL_CLOTURE`→`CL` ajouté** ; écritures identiques | base : `389` 5/5 ; suites `179`/`175` OK ; **10 portes CI vertes** | 29aac80 |
| 06/10 | LOC1-08 (clôture d'exercice) | `close_fiscal_year` | journaux `CL`/`AN` et comptes de résultat `120000`/`129000` par les rôles ; écritures identiques ; la sélection par CLASSE reste (`LOC1-11`) | base : `390` 4/4 ; suites `179`/`175` OK ; **10 portes CI vertes** | 424eeca |
| 11/10 | LOC1-09 (tranche 1) | `bank_account_post_opening_balance`, `stock_initial_post_opening_entry`, `post_exchange_gain_loss_on_payment` | journaux `AN`/`OD` par les rôles ; écritures identiques ; **le reste (6 fonctions) est FIGÉ et gardé** par la suite `391` (T03) | base : `391` 4/4 ; suites `173`/`211`/`102` OK ; **10 portes CI vertes** | eb47800 |
| 11/10 | LOC1-09 (tranche 3, **la dernière**) | `credit_note_guard`, `purchase_credit_note_guard`, `generate_depreciation_entry`, `revaluate_currency_balances` | journaux `VT`/`AC`/`OD` par les rôles ; écritures identiques ; **LOC1-09 TERMINÉ** — garde de `391` (T03) resserré à **liste blanche vide**, `392` (T02) borné, `393` (T02) constate **zéro restant** ; gardes rendus **insensibles aux fixtures** (`_…`, suites `325`/`462`) ; suites datées `383`/`384`/`385` réalignées sur l'état réel ; `105` doté d'un **semis dédié** à `legislation_packs` (son isolation est de nouveau **prouvée**) | base neuve : **347 migrations / 0 erreur** ; `393` 4/4, `391` 4/4, `392` 4/4, `383` 6/6, `384` 7/7, `385` 6/6, `105` 356/356 0 fuite ; suites d'écritures (`102`/`180`/`192`/`197`/`211`/`213`/`226`/`255`/`260`/`309`/`317`/`353`) et chaînes (`400`/`403`/`412`) OK ; **10 portes CI vertes** ; G5 164/164. ⚠ `check_bt_grid` **ROUGE** : dette de la `383` (`tenant_account_roles`, `tenant_journal_roles` non forcées), **à trancher** — voir « Trouvé en chemin » | 48a6c86 |
| 11/10 | LOC1-10 (tranche 1) | `check-country-neutral.mjs` — garde-fou **E01** | Le cahier donne pour recette « le garde-fou E01 passe sur `app/src` » : il est **livré**. Règle E01 de l'annexe E sur **deux gisements** — `app/src/**/*.{ts,tsx}` et les définitions **effectives** (`pg_proc.prosrc`) ; plafond **gelé** (`app/.country-neutral-ceiling.json` : une hausse casse, une baisse abaisse) ; **deux registres d'exceptions motivées** (un `placeholder="12345"` côté front, le **gabarit de plan comptable** côté SQL → propriétaire `LOC1-13`) ; câblé dans `lint-typecheck` (`--front-only`) et `db-integration` (complet, **avant** les suites) | Mesure : **41 occurrences front / 24 SQL** (gelées) ; le garde-fou passe dans les deux modes et au 2ᵉ passage (idempotent) ; **347 migrations / 0 erreur** | à venir |
| 11/10 | LOC1-09 (tranche 2) | `integrate_expense_report_on_approval`, `post_deferred_charge` | journal `OD` par le rôle ; le garde `391` (T03) **verrouille l'ensemble** et empêche toute nouvelle occurrence ; **reste 4 fonctions** (tranche 3) | base : `392` 4/4, `391` 4/4 ; suites `211`/`102` OK ; **10 portes CI vertes** | (ce commit) |