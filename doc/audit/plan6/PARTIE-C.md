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
| C.1 | Phase 1 — **neutralité** : les comptes codés en dur (`310000`, `601000`, `355000`, `713500`, `641`/`645`/`421`/`431`…) passent par `resolve_account` ; pack fictif `ZZ` comme preuve | LOC1-01 → 58, S-10, AUD-F03, AUD-G10 | ≈ 48 j | 🟡 **LOC1-01 → 06 (+ LOC1-48) faits — `380`→`386`** ; **LOC1-07 : POS `387`, stock/production `388`** ; **LOC1-08 : affectation/écarts `389`** ; reste → 58 à venir |
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

**Ensuite (`390`)** : `close_fiscal_year` (journal `CL`, `AN`, comptes
`120000`/`129000`) — même méthode, même résultat.

**Non fait, et pourquoi** : `generate_depreciation_entry` — ses littéraux
`280000`/`681000` ne correspondent **pas** aux rôles (`AMORTISSEMENTS` est par
CATÉGORIE ; le pack porte `681100`). Le remplacer **changerait les écritures** :
à trancher (même principe que `613000` — on ne « corrige » pas pour coller au
cahier).

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
| 06/10 | LOC1-08 (tranche affectation/écarts) | `allocate_result`, `generate_residual_entry` | affectation du résultat et écarts de lettrage sur les rôles ; **rôle `JOURNAL_CLOTURE`→`CL` ajouté** ; écritures identiques | base : `389` 5/5 ; suites `179`/`175` OK ; **10 portes CI vertes** | (ce commit) |