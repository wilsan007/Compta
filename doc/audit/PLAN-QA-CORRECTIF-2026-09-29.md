# Plan QA correctif — recette /qa du 29 septembre 2026

> **Objet** : corriger **tous** les défauts relevés par la recette à l'écran du
> 29/09/2026 (six agents en parallèle + coordinateur), puis refaire une recette
> globale complète et le contrôle croisé qui n'a pas pu être fait.
>
> **Branche** : `qa/recette-2026-09-29` (arbre de travail `~/qa-worktrees/compta-qa`).
> **Base de recette** : Supabase local réinitialisé, 258 migrations + `310`, société
> « QA Recette SARL » (`15702510-6094-4822-bd61-1253cd562e40`), exercice FY2026.
> **Sources** : `scratchpad/qa/findings/{COORD,ven,ach,cpt,rh,stk,pil}.md` et
> `scratchpad/qa/ledger/*.jsonl` (registres d'opérations avec les montants attendus).

---

## 0. Synthèse

| Indicateur | Valeur |
|---|---|
| Défauts relevés | **74** (coordinateur 10, ventes 18, stock 15, paie 9, projets 9, comptabilité 8, achats 5) |
| Critiques | **7** — dont **6 corrigés** (COORD-001, pil-001, pil-005, rh-006, ven-013, ven-016) |
| Hauts | **23** — dont **4 déjà corrigés** (COORD-003, pil-002, ven-014, ven-017) |
| Moyens | **24** — dont **1 corrigé** (cpt-005) |
| Bas | **20** |
| Déjà corrigés et commités | **16 commits** (§ 2) |
| **Restant à corriger** | **≈ 56 défauts**, en **8 lots** (§ 4 à § 11), dont **6 lots encore ouverts** |
| Charge estimée | **≈ 19 j** de correctifs + **≈ 3 j** de recette finale (§ 13) |
| Contrôle croisé global | **NON FAIT** — aucune cohérence inter-modules n'est prouvée (§ 12) |

**Les six défauts qui bloquent un parcours métier entier**, à traiter en premier :

1. ~~**rh-006** — aucun écran ne produit de bulletin de paie (toute la paie est intestable).~~
   **CORRIGÉ** (311, `a7b0570`) : un lot se génère par **un appel**, le verdict est
   nommé par salarié, et un lot vide ne s'approuve plus. Reste de cette famille :
   C2 à C6 (simulateur, heures sup, absence).
2. ~~**ven-013 / cpt-005 / ven-014** — clients et fournisseurs créés à l'écran absents du plan tiers~~
   **CORRIGÉ** (312, `6409c0e`) : le compte de tiers naît avec le tiers, le
   rattrapage couvre l'existant, et la balance âgée trouve son type et son nom.
   **ven-017 fermé aussi** (313, `3155a90`) : le solde dû se lit au grand livre.
3. ~~**ven-016** — « Contrôle crédit » en boucle infinie (≈ 1 400 requêtes/s, charge la base).~~
   **CORRIGÉ** (`d9197e1`) : l'appel de chargement ne vit plus dans le corps du
   composant. Mesuré à l'écran : 4 776 GET `/rest/v1/customers` en 5 s et
   3 435 erreurs console avant ; **2** requêtes en 10 s et 0 erreur après. Le même
   défaut existait dans l'assistant de paramétrage (voir B10).
4. **ven-005 / ven-004** — BL « Livré » sans sortie de stock ; BL avec service bloqué.
5. **stk-012** — sortie de caisse d'un produit fini passée en 603/310 au lieu de 7135/355.
6. **ach-001 / stk-015** — fenêtres de création (fournisseur, immobilisation) inatteignables à 1280×720.

---

## 1. Règles de méthode (rappel du dépôt, appliquées à chaque défaut)

1. **Un défaut = un test rouge avant.** SQL (`app/sql/NNN_*_tests.sql`, harnais
   `ci/audit_helpers.sql`, `_rec` / `_audit_assert`) pour ce que la base tient ;
   Vitest (`src/**/__tests__`) pour ce que l'écran calcule ; scénario du banc
   `src/__screen__/` quand le défaut est dans le chemin écran → PostgREST.
2. **Une migration se constate** : prendre le premier numéro libre **au moment du
   commit** (`ls app/sql | sort -n | tail`). À ce jour : `310` est pris par cette
   branche ; la suite prend `311`, `312`… sauf si une autre session a pris le numéro entre-temps.
3. **Câblage CI dans le même commit** (étape `.github/workflows/ci.yml` après la 310).
4. **Un commit par défaut**, message `fix(qa): <ID> — <phrase>` avec la mesure
   avant/après.
5. **Vérification à l'écran** de chaque correctif sur la base de recette, capture
   `qa/screenshots/<ID>-after.png`, et le défaut passe « vérifié corrigé » dans son fichier.
6. **Gardes-fous** : `tsc -b --noEmit` 0, `oxlint --max-warnings=0` 0,
   `node scripts/check-i18n.mjs` (parité fr/en/ar), `check-written-columns`,
   `check-unchecked-writes`, `check-rpc-contract`, `check-screen-writes`,
   `check-embeds` et la batterie SQL sur **base neuve** avant chaque fusion de lot.
7. **Ne rien déployer** en production depuis cette branche sans relecture ; la 276
   (grille paie France 2026) reste soumise à la signature de l'expert (D-G).

---

## 2. Déjà corrigé (branche `qa/recette-2026-09-29`)

| Commit | Défaut | Correctif | Preuve |
|---|---|---|---|
| `d9197e1` | **B10 — ven-016** 🔴 contrôle crédit en boucle infinie ; jumeau `OnboardingDashboardPage` (jamais relevé) | l'appel de chargement quitte le **corps** du composant pour `useEffect(() => { loadData() }, [loadData])` (dépendances déjà stables) ; garde statique `verify-rules/15-no-render-body-call.rule` | Vitest `CreditControlPage.test.tsx` rouge avant (26 lectures) / vert après (1) ; écran société « QA Recette SARL », protocole symétrique : 4 776 GET `/customers` et 10 325 requêtes `/rest/v1` en 5 s + 3 435 erreurs console → **2 en 10 s**, 0 erreur ; `tsc`, `oxlint`, i18n verts |
| `6409c0e` | **A1 — ven-013** 🔴 / **cpt-005** 🟡 tiers sans compte au plan tiers | migration **312** : déclencheur de rattachement sur `customers`, `suppliers`, `employees` (code auxiliaire, collectif, nom, encart, désactivation) + rattrapage sans écraser un compte saisi | `312_*_tests` **7/7** (T01/T02/T03 rouges avant ; sonde : 0 → 3 comptes) ; **banc écran 15/15** |
| `3155a90` | **A2 — ven-014** 🟠 balance âgée « other » / **A3 — ven-017** 🟠 solde dû à 0,00 € | migration **313** : vues `customer_balances` (411) et `supplier_balances` (401) en `security_invoker` ; écrans branchés (listes client et fournisseur, contrôle crédit, fiche 360) | `313_*_tests` **6/6** (T01 rouge avant) ; mesuré : GL 540,00 contre 0,00 à l'écran, corrigé ; **banc écran 15/15** ; Vitest **1 514/1 514** |
| `a7b0570` | **rh-006** 🔴 aucun bulletin ; lot vide approuvable | migration **311** : `generate_pay_run_slips` (le moteur unique appelé par la base, verdict par salarié, refus nommés) + l'approbation exige un bulletin ; écrans branchés (`PayRunsPage`, étape 5 de la préparation, `PaySlipsPage`), boucle cliente retirée | `311_*_tests` **7/7** (T01, T02, T04 rouges avant) ; **banc écran 15/15** (H04 2 bulletins, H05 lot = somme, H06 bulletin d'or) ; Vitest **1 513/1 513** |
| `1699bbd` | **COORD-001** 🔴 inscription bloquée, aucun pays | migration **310** : référentiel `legislation_packs` (société technique `…0001`) lisible, toujours en lecture seule | `310_*_tests` : T01/T02 rouges avant, **4/4** après ; `check_anon_grants`, `check_global_rows_writable`, `check_policy_duplicates` verts |
| `a8f58ed` | **COORD-002/003** 🟠 « e-mail envoyé » alors que rien ne part ; `<strong>` brut | `signUp()` remonte `email_sent` ; message d'échec `role=alert` ; `<Trans>` | vu à l'écran (fr) |
| `bbae422` | **COORD-007** 406 au chargement | `.maybeSingle()` sur `users` | 0 × 406 |
| `9782641` | **COORD-005** vitrine affichée à un connecté | `RootRoute` → `/dashboard` ; fin d'inscription → `/dashboard` | vu à l'écran |
| `55ae7f5` | **COORD-004** doublon d'e-mail non contrôlé (`profiles` absente) | `auth_email_exists()` | tests Edge **32/32** |
| `3808646` | **COORD-008** la 238 échoue sur base Supabase neuve | `DROP INDEX idx_svl_lifo` (doublon DESC) | base rejouée, 0 erreur |
| `02fdda4`, `c8f1148` | **COORD-009** guide d'accueil et légende trésorerie non traduits | `onboardingTour.*`, `dashboard.cashFlowLegend.*` (fr/en/ar) | vu en fr et en |
| `db5a00d` | **pil-005** 🔴 création de tâche impossible (colonne fantôme) | `production_order_id` retiré ; échec affiché (toast) | `POST project_tasks` → 201 |
| `0e8a73d` | **pil-002** 🟠 six vues projet masquées par leur catégorie | catégories en `/project-management/section/*` | six vues vérifiées |
| `7d4ecb4` | **pil-001** 🔴 création de projet impossible | dates vides → `NULL` | `POST projects` → 201 |

**Reste à faire sur ces correctifs** :
- revérification par l'agent `pil` des cinq vues `/graph`, `/my-tasks`, `/large-screen`, `/mind-map` et `/doc` ;
- `COORD-006` non retenu (les modules présélectionnés portent une coche visible).

---

## 3. Préalables d'environnement (avant tout lot)

| # | Action | Pourquoi |
|---|---|---|
| E1 | Relancer le serveur `compta-qa` (port 5180) et les fonctions Edge (`docker start supabase_edge_runtime_app`) | ils se sont arrêtés pendant la pause |
| E2 | Vérifier que le **contrôle automatique des actions** répond (une commande simple) avant de lancer les agents | les 6 agents ont été coupés par l'absence de verdict |
| E3 | Lancer les agents **en deux vagues de 3** plutôt que 6 d'un coup | la limite d'utilisation du compte a coupé les 6 agents à la première vague |
| E4 | Recharger la base de recette **après** chaque migration (`run-sql-migrations.mjs` depuis l'arbre de recette) puis `NOTIFY pgrst, 'reload schema'` | sinon PostgREST sert l'ancien schéma |
| E5 | Écrire dans le brief des agents : `$B viewport 1280x1000` d'office tant que ach-001/stk-015 ne sont pas corrigés | évite les blocages de fenêtre |
| E6 | Données parasites à ignorer : produits `ACH-FOU`, `ACH-GANTS`, `[STK] Matière A` (prix −10), `[STK] Repro prix négatif`, nomenclatures `STK-BOM-C`/`C2` sans article, projet sonde supprimé | créées par des saisies de test |

### État d'exécution (session du 29/09, après C1)

Fait : **E1** (le conteneur `supabase_edge_runtime_app` a été relancé), **E4**
(migration appliquée puis `NOTIFY pgrst, 'reload schema'`) — puis **E1 mené à
terme** au lot B10 : le serveur Vite du worktree tourne de nouveau sur le port
5180 (`npx vite --port 5180 --strictPort`), donc les vérifications navigateur
sont possibles (elles l'étaient restées à zéro jusqu'ici).

Pour la mesure à l'écran, les mots de passe de `.screen-rig/rig.json` n'étaient
plus valides : `setup.mjs` crée ses comptes **sans mot de passe GoTrue** (ils
servent par JWT au banc X0). Un compte de mesure **`b10-recette@screen.test`**
(rôle `admin`, société « QA Recette SARL » `15702510-…`) a donc été créé par
l'API d'administration et rattaché à cette société ; le script de mesure est
`.screen-rig/measure-ven-016.mjs` (hors dépôt, comme le reste du banc). L'ancien
`rig.json` n'a **pas** été régénéré, pour ne pas casser le banc X0.

⚠ **Garde déjà rouge avant ce lot** : la règle `02-hardcoded-euro` compte **7**
occurrences du symbole `€` — toutes dans des **commentaires** ajoutés par le lot
A1-A3 (`CreditControlPage`, `CustomersPage`, `leavesAbsences`, `accounting`) ;
`npm run verify` échoue donc sur 7 erreurs qui ne viennent pas de B10. À nettoyer
dans un commit dédié avant la recette finale.

Mode opératoire **vérifié** pour les lots suivants (commandes réellement jouées) :

```bash
# 1. appliquer une migration sur la base de recette (Suivi par sql_migrations_tracker)
cd ~/qa-worktrees/compta-qa/app
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres node run-sql-migrations.mjs
#    rejouer un fichier déjà tracké après l'avoir modifié :
docker cp sql app/sql supabase_db_app:/tmp/qasql   # puis
docker exec supabase_db_app psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/qasql/<fichier>.sql

# 2. lancer une suite SQL isolée
docker exec supabase_db_app psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/qasql/<nnn>_*_tests.sql

# 3. le banc « chemin de l'écran » (X0), qui n'exige PAS de navigateur
cd ~/qa-worktrees/compta-qa/app
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres node scripts/screen-rig/setup.mjs
#    PostgREST réel sur 3399, avec le secret du banc :
SECRET=$(node -e "console.log(require('./.screen-rig/rig.json').jwtSecret)")
docker run --rm -d --name qa-pgrst-rig -p 3399:3000 \
  -e PGRST_DB_URI="postgres://authenticator:screen-rig@host.docker.internal:54322/postgres" \
  -e PGRST_DB_SCHEMAS=public -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET="$SECRET" \
  -e PGRST_DB_MAX_ROWS=1000 postgrest/postgrest:v16.3
nohup node scripts/screen-rig/gateway.mjs > .screen-rig/gateway.out 2>&1 &
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres npx vitest run -c vitest.screen.config.ts
```

Deux points de méthode mesurés pendant cette exécution :

* **Le banc écran n'est pas idempotent** : les scénarios s'enchaînent (01 → 15) et
  laissent des données dans la société A. Le rejouer **deux fois sans refaire
  `setup.mjs`** fait tomber `04_fec` (F01/F04/F07) sur les salariés laissés par
  `05_payroll` de la passe précédente — rouge de **harnais**, pas de produit.
  Refaire `setup.mjs` (et redémarrer PostgREST **et** la passerelle, le secret JWT
  étant regénéré) avant chaque passe complète.
* **Ce que le banc attrape et que la relecture rate** : la 311 ne refusait aucun
  bulletin à 0,00 € — l'inscription réelle crée un salarié « Admin » **sans
  salaire**, donc la première version produisait un bulletin de 0,00 € pour ce
  compte technique (3 bulletins au lieu de 2, bulletin d'or pris sur la mauvaise
  ligne). Vu par H04/H05/H06, corrigé par T07.

**Reste à faire pour C1** (dit, non fait) : la capture d'écran `qa/screenshots/rh-006-after.png`
exigée par la règle 5 (elle demande un navigateur et le serveur Vite du worktree,
qui n'ont pas été montés ici) ; la preuve retenue est le banc écran + la suite SQL.

### Lot A — A1/A2/A3 livrés (312, 313 ; session du 29/09)

`6409c0e` (312) puis `3155a90` (313) : quatre défauts fermés (ven-013, cpt-005,
ven-014, ven-017) et un cinquième effet mesuré — les salariés reçoivent enfin leur
compte 421, donc le FEC n'a plus de « CompAuxLib manquant » sur les matricules.

Trois leçons de méthode, mesurées pendant ce lot :

* **Un test qui DÉSACTIVE un déclencheur doit pouvoir être interrompu sans
  laisser la base amputée.** Le premier T04 faisait `DISABLE TRIGGER` puis, plus
  loin, `ENABLE` : le fichier ayant échoué entre les deux, le déclencheur est
  resté désactivé (mesuré : T01 et T03 rouges, alors que T02 passait). Le test T04
  ne désactive plus rien : il supprime la ligne de compte du tiers, ce qui mesure
  la même chose (l'état d'avant) sans risque. Envelopper le couple
  `DISABLE`/`ENABLE` dans une transaction serait l'autre voie.
* **Un plafond qui bouge doit être prouvé.** `check-unused-tables` a réécrit son
  plafond de 76 à 75 en passant. Mesure faite : 75 **avec et sans** ce commit
  (mêmes 75 noms de tables, listes identiques) — l'écart vient de la base de
  recette locale, pas du code. Le plafond n'est **pas** commité : la CI mesure une
  base neuve, et l'abaisser sans preuve aurait pu casser la CI.
* **Le générateur de types ne lit que les tables** (`table_type = 'BASE TABLE'`) :
  ajouter une vue ne change pas `src/types/database-generated.ts`. L'avoir lancé
  sur la base de recette y a fait entrer `_audit_results` / `_audit_expected`
  (tables de test) — diff annulé.



---

## 4. Lot A — Tiers et comptes auxiliaires (≈ 2,5 j) — **priorité 1**

Cause commune : la création d'un client ou d'un fournisseur à l'écran n'écrit **aucune**
ligne dans `third_party_accounts`. Or le plan tiers, le lettrage, la balance âgée par type
et les modèles de saisie ne lisent **que** cette table.

### A1 — ven-013 🔴 / cpt-005 🟡 — client ou fournisseur sans compte au plan tiers — **✅ CORRIGÉ** (312, `6409c0e`)
- **Constat** : 4 clients + 4 fournisseurs, `third_party_accounts` = **0**. Lettrage :
  « Aucun tiers trouvé » ; Plan tiers : « 0 compte(s) ».
- **Correctif** (migration `3xx_third_party_accounts_from_partners.sql`) :
  1. Déclencheur `AFTER INSERT OR UPDATE OF name, auxiliary_account, collective_account`
     sur `customers` et `suppliers` (et `employees` pour le 421) qui **crée ou met à jour**
     le compte tiers `(tenant_id, type, code auxiliaire, collectif, nom, partner_id)`.
  2. **Rattrapage** des tiers existants (INSERT … SELECT … ON CONFLICT DO NOTHING).
  3. Unicité `(tenant_id, type, code)` ; clé composite `(tenant_id, partner_id)` (ISO-02).
- **Test rouge avant** `3xx_*_tests.sql` :
  - T01 : un client inséré a son compte tiers 411/CLIxxxxx ;
  - T02 : même chose pour un fournisseur (401/FOUxxxxx) ;
  - T03 : un renommage se propage ;
  - T04 : le rattrapage couvre les tiers existants ;
  - T05 : une autre société ne voit rien (isolation).
- **Vérification écran** : Plan tiers affiche 5 clients (dont `[PIL]`) et 3 fournisseurs `[ACH]` ;
  Lettrage « Clients » liste Dubois avec FAC-2026-000001 540, AV-2026-000001 120,
  RGT-2026-000002 300 → lettrage partiel possible, reste 120.

### A2 — ven-014 🟠 — balance âgée : clients typés « other », filtre « Clients » vide — **✅ CORRIGÉ** (312, `6409c0e`)
- **Cause probable** : type de tiers lu depuis `third_party_accounts` (vide) → repli « other ».
- **Correctif** : après A1, lire le type depuis le compte tiers ; afficher le **nom** et non le code.
- **Test** : Vitest sur la fonction de construction de la balance âgée (type + nom) +
  scénario écran.
- **Attendu** : (Clients) CLI00002 [VEN] Dubois Industrie SAS 162,20 ; CLI00003 [VEN] Müller Handels GmbH 250,00 ;
  CLI00004 [PIL] Client Projet 120,00.

### A3 — ven-017 🟠 — « Solde dû » à 0,00 € partout (liste des clients, contrôle crédit) — **✅ CORRIGÉ** (313, `3155a90`)
- **Constat** : `customers.balance = 0`, `credit_used = 0` alors que 411 porte 532,20.
- **Correctif** : ne plus lire de colonne dénormalisée jamais tenue. Solde dû calculé
  depuis le grand livre (411 × `account_tiers`), par une vue `customer_balances`
  (`security_invoker`) ou une RPC. `credit_used` dérivé de la même source.
- **Test** : SQL (solde = factures − avoirs − règlements) ; attendus Dubois **162,20**,
  Müller **250,00**, Martin **0,00**.

### A4 — ven-001 🟡 / ach-002 🟡 — fiches client et fournisseur sans SIRET, pays, CP/ville, conditions
- **Correctif front** (`CustomersPage`, `SuppliersPage`) :
  - ajouter SIRET (validé par clé de Luhn, et bouton « Vérifier » vers `verify-siret`) ;
  - ajouter pays (liste ISO), code postal et ville ;
  - ajouter les conditions de paiement (`payment_term_id`, liste) ;
  - remplacer « Société parente (ID) » et « Commercial assigné (ID) » par des **listes**
    (sociétés existantes, utilisateurs) au lieu d'un UUID tapé.
- **Base** : ne plus forcer `country='France'` ; défaut = pays de la société **seulement si** non saisi.
- **Test** : Vitest du formulaire (SIRET invalide refusé) ; `check-written-columns`.

### A5 — ach-003 🟡 — IBAN invalide accepté
- **Correctif** : validation IBAN (longueur par pays + clé mod 97) côté écran **et** contrainte
  ou déclencheur côté base sur `partner_bank_accounts.account_number` (quand `type='iban'`).
- **Test rouge** : `FR7612345` refusé ; un IBAN valide accepté.

### A6 — ven-002 🔵 — colonne « Total » de la liste des clients = date de création
- **Correctif** : colonne « Total facturé » (somme HT validée) ou en-tête « Créé le ».

---

## 5. Lot B — Ventes (≈ 4 j)

### B1 — ven-005 🔴 / ven-004 🟠 — sortie de stock du BL
- **Cause établie** : `create_stock_out_on_delivery()` ne réagit qu'au passage à `shipped`,
  et sort **toutes** les lignes, services compris.
- **Correctif** (migration `3xx_delivery_stock_out.sql`) :
  - condition `OLD.status NOT IN ('shipped','delivered') AND NEW.status IN ('shipped','delivered')` ;
  - sortir seulement les lignes dont `products.type = 'stock'` et `product_id IS NOT NULL` ;
  - garder le refus de réexpédition (`23505`) et la libération de réservation (S-07).
- **Test rouge avant** (déjà rédigé : `311_delivery_stock_out_tests.sql`) :
  - T01 : En attente → Livré sort 2 (100 → 98) ;
  - T02 : BL bien + service expédié, une seule sortie ;
  - T03 : expédié puis livré sort une seule fois ;
  - T04 : réexpédition d'un BL annulé refusée.
- **Complément** : la commande passait `fully_delivered=true` dès la **création** du BL.
  Ne la marquer livrée qu'à l'expédition ou la livraison (test T05).
- **Écran** : colonne « Stock » du BL = « Généré ».

### B2 — ven-008 🟠 — facture directe sans choix d'article : service crédité en 707, stock inchangé
- **Correctif front** (`InvoicesPage`, formulaire de ligne) :
  - sélecteur d'article comme sur le devis, qui pré-remplit description, prix, taux, `product_id` ;
  - saisie libre maintenue, avec un compte de vente choisi (706/707) quand il n'y a pas d'article.
- **Base** : la comptabilisation lit `invoice_lines.product_id` → `products.sale_account_code`,
  sinon le compte de la ligne, sinon 706 pour un service et 707 pour un bien.
  Une facture directe d'article stocké **sans BL** sort le stock à la validation (décision à
  prendre : **D-QA-1**, voir § 14).
- **Test rouge** : facture 3 × livre 5,5 % + 1 × service donne 707 C 30, **706 C 250**,
  445713 C 1,65, 445711 C 50 et 411 D 331,65.

### B3 — ven-009 🟠 — client UE : ni autoliquidation, ni mention, Factur-X « Z »
- **Correctif** :
  - position fiscale du client (FR, UE assujetti, hors UE), déduite du pays et du n° TVA, modifiable ;
  - facture à un client UE assujetti : taux 0 proposé d'office et mention
    « Autoliquidation — art. 283-2 CGI » (services) ou « Exonération art. 262 ter I CGI » (biens) ;
  - `vat_code` posé sur la ligne 70x, pour que la CA3 range l'opération (cases E1, E2 et
    ligne 06 « autres opérations non imposables ») ;
  - Factur-X : `CategoryCode=AE` pour une prestation autoliquidée, `K` pour une livraison
    intracommunautaire, avec `ExemptionReason`.
- **Dépend de** : A4 (pays du client).
- **Tests** :
  - SQL : écriture avec `vat_code`, et CA3 qui porte le montant en non imposable ;
  - Vitest : générateur Factur-X, catégorie AE et motif d'exonération.

### B4 — ven-012 🟠 — avoir ventilé au prorata (706 55,56 / 707 44,44) au lieu de l'article rendu
- **Correctif** :
  - l'avoir reprend les **lignes de la facture source** (quantités modifiables) avec leur
    `product_id` et leur compte ;
  - la comptabilisation se fait **par ligne**, pas au prorata ;
  - `journal_entries.invoice_ref` est posé (pour le lettrage) ;
  - le retour en stock est optionnel si l'article est stocké.
- **Écran** : colonne « Facture source » renseignée ; bouton « Créer un avoir » de la liste
  branché (ven-011).
- **Test rouge** : avoir de 1 × Bien A donne 707 D 100, 445711 D 20, 411 C 120 ; aucune ligne 706.

### B5 — ven-011 🟡 — « Créer un avoir » depuis la liste ne fait rien
- **Correctif** : brancher l'action pour ouvrir l'avoir pré-rempli (client, facture source, lignes).
- **Test** : Vitest (clic → ouverture avec `invoice_id`).

### B6 — ven-006 🟡 — facture née d'un BL : client vide, date du jour imposée
- **Correctif** :
  - `customer_name` recopié (ou lu par jointure partout) ;
  - date de la facture choisie à la transformation (par défaut la date du BL) ;
  - la fenêtre « Voir » affiche les lignes, le HT et la TVA par taux.
- **Même défaut sur la chaîne** : devis → commande → BL imposent tous la date du jour
  (le devis du 10/09 donne une commande au 29/09). Proposer la date d'origine.
- **Test** : SQL `create_*_from_*` (client et date recopiés).

### B7 — ven-007 🟡 — numérotation non chronologique malgré l'annonce
- **Correctif** : à la validation, refuser une facture datée **avant** la dernière facture
  numérotée de la série, ou avertir et demander confirmation. Décision **D-QA-2** : refus
  strict ou avertissement ; l'obligation légale française penche pour le refus.
- **Test rouge** : valider FAC du 12/09 après FAC du 29/09 est refusé, avec un message nommé.

### B8 — ven-010 🟠 — « Télécharger » produit un texte de 156 octets au lieu d'un PDF
- **Dépend de la décision D-4** (`generate-pdf` non déployée).
- **Correctif** : générer le PDF côté navigateur (bibliothèque déjà présente dans le bundle `pdf`) avec :
  - vendeur (raison sociale, SIREN, n° TVA, adresse) et client ;
  - lignes, HT par taux, TVA, TTC ;
  - mentions légales : pénalités de retard, indemnité forfaitaire de 40 €, escompte,
    autoliquidation le cas échéant.
- **Correction immédiate** « Client: null » (vient de B6).
- **Test** : Vitest (le document contient le SIREN, les lignes, les mentions ; MIME
  `application/pdf`).

### B9 — ven-015 🟡 — filtre « En retard » vide, statut jamais « En retard », aucune relance
- **Correctif** :
  - statut calculé `overdue` quand `due_date < aujourd'hui` et `amount_due > 0` ;
  - filtre sur ce critère ;
  - message d'état vide correct (« Aucune facture en retard ») ;
  - libellés des deux montants de l'en-tête (« Total TTC », « Reste dû ») ;
  - proposition de relance pour les factures échues.
- **Test** : Vitest du filtre, et SQL de la vue de relances.

### B10 — ven-016 🔴 — « Contrôle crédit » en boucle infinie — **✅ CORRIGÉ** (`d9197e1`)
- **Cause établie** (l'hypothèse d'un `useEffect` à dépendance instable était **fausse** : ce
  fichier n'en contenait aucun) : `loadData()` était appelé **dans le corps** du composant.
  Chaque rendu relançait la lecture, `setCustomers` re-rendait, et la boucle n'avait aucune
  condition d'arrêt. React le nomme lui-même dans la console : « Can't perform a React state
  update … side-effect in your render function ».
- **Correctif** : `useEffect(() => { loadData() }, [loadData])` — les dépendances de `loadData`
  (`toast`, `tCommon`) étaient déjà stables, d'où une seule lecture au montage.
- **Jumeau** : `OnboardingDashboardPage` portait le motif identique, jamais relevé à la recette
  parce que l'écran dépend de l'état d'onboarding — corrigé dans le même commit.
- **Test rouge** : `src/pages/__tests__/CreditControlPage.test.tsx` — 26 lectures `/customers`
  avant, **1** après (plus 2 re-rendus) ; côté onboarding 46 → 1. La source simulée se gèle
  au-delà de 50 appels : le rouge échoue en 0,3 s au lieu de tourner jusqu'au `testTimeout`.
- **Écran** (société « QA Recette SARL », Chrome, protocole **identique avant/après** : la
  fenêtre de mesure couvre toute la vie du document) : avant, **4 776** GET
  `/rest/v1/customers` et **10 325** requêtes `/rest/v1` en 5 s, **3 435 erreurs console** dont
  `net::ERR_INSUFFICIENT_RESOURCES` ; après, **2** requêtes `/customers` en 10 s et **0** erreur
  (2 = une lecture + le double montage `StrictMode` en dev), capture
  `qa/screenshots/ven-016-after.png`. Le relevé « avant » vient du **journal réseau** : le
  tampon de `performance.getEntriesByType` sature (74 entrées) dès que l'écran boucle.
- **Garde** : `scripts/verify-rules/15-no-render-body-call.rule` — le motif tombait 2 fois avant
  ce commit, 0 après (cf. § 15).

### B11 — ven-003 🔵 — `<div>` dans `<tbody>` (devis)
- **Correctif** : `QuotesPage`, remplacer l'enveloppe par un `<Fragment>` ou un `<tr>`.

### B12 — pil-009 🔵 — valider une facture en un clic, sans confirmation ; échéance = date
- **Correctif** : `confirmSync` avant validation (action irréversible) ; échéance par défaut
  = date + conditions de paiement du client.

---

## 6. Lot C — Paie (≈ 4 j) — **priorité 1 (rh-006)**

### C1 — rh-006 🔴 — aucun écran ne produit de bulletin ; lot vide approuvable — **✅ CORRIGÉ** (311, `a7b0570`)
- **Constat** : « Générer les bulletins » fait seulement `POST pay_runs` ; `pay_slips` = 0 ;
  « Valider la préparation » n'émet **aucune** requête (placebo).
- **Correctif** :
  1. « Générer les bulletins » : après la création du lot, appeler `calculate_payslip` (ou une
     RPC de lot `generate_pay_run_slips(p_pay_run_id)`, à créer si elle manque) pour chaque
     salarié actif de la période, puis afficher le verdict par salarié (calculé / en échec
     nommé), sur le modèle de `generate_depreciation_entries` (W5).
  2. « Valider la préparation » : brancher l'action réelle ou **retirer** le bouton.
  3. Base : refuser l'approbation d'un lot à 0 bulletin (`pay_runs.status → approved`
     exige `employee_count > 0`).
  4. Statut `processing` traduit dans les messages.
- **Test rouge** :
  - SQL : lot de février pour 3 salariés, 3 bulletins, totaux du lot = somme ;
  - SQL : approbation d'un lot vide refusée ;
  - banc écran : scénario « générer les bulletins ».
- **Attendus** (grille France 2026, 276, en attente de signature) :
  SMIC 1 823,03 → net **1 477,93** ; 2 500 → **1 919,53** ; 4 500 cadre → **3 121,70**.

### C2 — rh-005 🟠 — simulateur de paie : autre moteur, nets faux
- **Constat** :
  - nets faux : SMIC 1 311,51 (−166,42), 2 500 1 798,53 (−121), cadre 3 237,35 (+115,65) ;
  - chômage salarial compté ; CRDS absente ; net imposable = net ;
  - aucun traitement cadre ;
  - total patronal différent de la somme des rubriques.
- **Doctrine W5** (« un seul moteur par grandeur ») : le simulateur doit **appeler le moteur
  de la base** (même grille, mêmes taux) au lieu de recalculer en TypeScript.
- **Correctif** : RPC en lecture `simulate_payslip(p_employee_id, p_gross, p_options)` qui
  réutilise le cœur de `calculate_payslip` sans écrire. Le simulateur affiche ce qu'elle rend,
  et la réduction générale devient une ligne visible.
- **Test rouge** :
  - SQL : `simulate_payslip` = `calculate_payslip` au centime, pour les 3 bulletins d'or ;
  - Vitest (`single-engine.test.ts` étendu) : plus aucun barème en dur dans `PayrollCalcPage`.

### C3 — rh-008 🟠 — heures sup jamais détectées depuis la feuille de temps
- **Constat** : 12 h approuvées donnent `overtime_minutes = 0` et un élément
  `timesheet_hours` à `amount 0`. Le formulaire n'a ni heure d'arrivée ni heure de départ.
- **Correctif** :
  - formulaire avec arrivée et départ (ou « dont heures sup ») ;
  - base : `overtime_minutes` = heures saisies − horaire prévu du jour (même seuil que W5),
    élément de paie `overtime` au taux majoré via `payroll_overtime_amount` ;
  - `approved_by` = `auth.uid()` à l'approbation (feuilles de temps **et** congés).
- **Test rouge** : 12 h sur un jour prévu à 7 h donnent 300 min et un élément
  ≈ 5 × 2 500/151,67 × 1,25.

### C4 — rh-009 🟡 — pointage d'absence impossible
- **Correctif** : champ « Type d'absence » dans la feuille de temps (`timesheets.absence_type`,
  4ᵉ source du registre W9) ; il alimente `employee_absence_days`.
- **Test** : SQL W9, un pointage d'absence crée **un** jour au registre.

### C5 — Constats hors fiche (paie) à instruire
- Arrêt maladie : `days_count` NULL, payé à 100 % sans élément, 3 jours de carence et
  ancienneté < 1 an → **à faire valider par l'expert-comptable (D-G)**.
- « Calculer les droits acquis » rend 0,00 j pour une embauche au 05/01/2026 (solde −3).
  Correctif : acquisition 2,5 j/mois ouvrable (ou 2,08 ouvrés) depuis l'embauche. Test SQL.
- Type de congé « annual » non traduit.

### C6 — Défauts bas de paie
| ID | Correctif |
|---|---|
| rh-001 | `min=0` sur le salaire, message français mappé depuis `employees_salary_nonneg` ; borne sur la date d'embauche |
| rh-002 | normaliser `contract_type` en minuscules (migration de données + contrainte) ; l'inscription écrit `cdi` |
| rh-003 | une seule colonne de salaire (écrire `base_salary` ou supprimer l'un des deux) ; champ « heures hebdomadaires » éditable |
| rh-004 | en-tête « N° de contrat » ; `<label>` sur la liste employé ; poste et salaire repris dans le contrat |
| rh-007 | dates par défaut de campagne calculées en date locale (pas de `toISOString()`) : 01/09 → 30/09 ; bouton renommé si besoin |

---

## 7. Lot D — Stock, production, caisse (≈ 3,5 j)

### D1 — stk-012 🟠 — sortie de caisse d'un produit fini en 603/310 au lieu de 7135/355
- **Constat** : 355000 reste à 440 alors que le stock de C vaut 308 ; 310000 est diminué à tort de 132.
- **Correctif** : le compte de stock et la contrepartie d'une sortie viennent de l'**article**
  (`products.stock_account_code`) ou de la **couche d'entrée**. Produit fini
  (355/7135), marchandise (37/6037), matière (31/6031). Même règle pour BL, caisse et
  inventaire. Retirer les comptes codés en dur (dette S-10 de W8).
- **Test rouge** : vendre 2 C au CUMP 44 donne 7135 D 88 / 355 C 88, et 310 est inchangé.

### D2 — stk-005 🟠 — « Valoriser le stock » : fonction ambiguë, puis total faux
- **Cause établie** : deux surcharges de `calculate_stock_valuation`
  (`(p_method, p_warehouse_id)` et `(p_tenant_id, p_method, p_date)`), donc PostgREST rend 300.
  La valorisation sur un dépôt calcule quantité × prix de la fiche, pas les couches.
- **Correctif** : **une** fonction `calculate_stock_valuation(p_method, p_warehouse_id, p_date)`
  qui lit les **couches** (CUMP, FIFO) et rend une ligne par article. Supprimer l'autre
  surcharge (règle W10 : `check-rpc-contract`).
- **Test rouge** : CUMP total **5 900,00**, A1 1 800,00 ; FIFO pour A1 1 900,00.

### D3 — stk-010 🟠 — OF terminé affiché à 0,00 € et « Aucune consommation »
- **Correctif écran** : lire `manufacturing_orders.cost_material/cost_total/unit_cost/cost_variance`
  et les mouvements `reference_type='manufacturing_order'`, au lieu de recalculer depuis
  `bom_lines.unit_cost`. Afficher l'écart de coût.
- **Test** : Vitest de la page OF (données simulées), 440 / 44 / écart.

### D4 — stk-013 🟠 — statistiques de caisse vides (période décalée d'un jour, borne de fin = début)
- **Cause établie** : bornes calculées en UTC depuis minuit local, et fin = même jour.
- **Correctif** : utilitaire commun `localDayRange(period)` → `[début local, fin exclusive)` en
  ISO avec fuseau. Le réutiliser partout où `toISOString().slice(0,10)` sert de date
  (**chasse globale** : grep `toISOString().slice(0, 10)` et `toISOString().split('T')`).
- **Test rouge** : Vitest avec le fuseau Europe/Paris simulé : « Aujourd'hui » au 29/09 donne
  `gte 2026-09-29` et `lt 2026-09-30`.

### D5 — stk-014 🟠 — caisse : aucune annulation de ticket ; statut anglais ; « Virement » non paramétré
- **Correctif** :
  - action « Annuler le ticket » (session ouverte), qui appelle `void_pos_ticket` avec motif et confirmation ;
  - après clôture, action « Avoir » (`255`) ;
  - statuts traduits ;
  - l'encaissement ne propose que les moyens de paiement actifs de `pos_payment_methods`.
- **Test** : banc écran (annulation, stock rendu, événement NF-525).

### D6 — stk-001 🟠 / stk-002 🟡 / ach-004 🟡 — prix négatif accepté ; fiche article non modifiable
- **Base** : contraintes `products_sale_price_nonneg` et `products_purchase_price_nonneg`
  (rattrapage des lignes négatives existantes ; décision **D-QA-3** : mettre à 0 ou
  désactiver). Quantité initiale négative refusée avec un message.
- **Écran** : fiche article **modifiable** (nom, prix, seuil, comptes, unité, type), accessible
  depuis le menu Stock **et** Commercial ; routes `/stock/products` valides.
- **Test rouge** : SQL, prix −10 refusé ; Vitest, bouton « Modifier » présent.

### D7 — stk-003 🟡 — sortie affichée à 0,00 € alors que comptabilisée au CUMP
- **Correctif** : poser `stock_movements.unit_cost` = CUMP au moment de la sortie (dans le
  déclencheur qui sort la couche), pour BL, caisse, inventaire et OF.
- **Test** : sortie de 50 A1 donne `unit_cost` 12.

### D8 — stk-004 🟡 — stock initial : dépôt imposé, date du jour, aucune écriture
- **Correctif** : choix du dépôt et de la date dans le formulaire. Décision **D-QA-4**
  sur la contrepartie comptable du stock initial : écriture AN 3x/890000 comme la banque (277),
  ou avertissement.
- **Test** : SQL (dépôt et date respectés ; écriture AN si retenue).

### D9 — stk-006 🟡 / stk-007 🟡 — inventaire : ajustement absent de la liste, libellés trompeurs, écarts en JSON brut
- **Correctif** :
  - le champ devient « Quantité comptée » (≥ 0) ; message « écart = compté − théorique » ;
  - la liste de l'inventaire inclut les ajustements ;
  - référence `INV-<date d'inventaire>` et `stock_movements.date` = date d'inventaire ;
  - services exclus du sélecteur ;
  - « Calculer les écarts » rend un **tableau** (article, théorique, compté, écart, valeur),
    et le calcul trouve l'écart de B (−3, −12,00).
- **Test** : SQL de la fonction d'écarts, et Vitest du rendu.

### D10 — stk-008 🟡 / stk-009 🟡 — nomenclature sans article ; coût à 0
- **Base** : `boms.product_id NOT NULL` (rattrapage : désactiver les nomenclatures sans article).
- **Écran** : colonne « Article » dans la liste ; action « Modifier » ; coût des composants
  = CUMP courant par défaut (lecture des couches), 44,00 € pour C.
- **Test** : SQL NOT NULL ; Vitest du coût.

### D11 — stk-011 🔵 — un OF refusé consomme son numéro
- **Correctif** : attribuer le numéro **après** les contrôles (ou dans la même transaction,
  annulée au refus) ; message sans numéro.

### D12 — ach-005 🔵 — alerte « stock bas » avec seuil 0
- **Correctif** : alerte si `reorder_level > 0 AND stock_quantity < reorder_level`.

### D13 — Non testé à couvrir par la recette finale
- Transfert entre dépôts : **aucun écran n'existe**. Décision **D-QA-5** : le créer
  (mouvement `transfer` out et in atomique) ou le retirer du périmètre.
- Étiquettes et codes-barres, MRP, réservations, alertes, exports, panneau des fantômes.

---

## 8. Lot E — Immobilisations et fenêtres qui débordent (≈ 1 j)

### E1 — stk-015 🟠 / ach-001 🟠 — fenêtre plus haute que l'écran, sans défilement
- **Cause probable** : le composant `Modal` commun n'a ni `max-height` ni `overflow-y: auto`
  sur son corps.
- **Correctif** (une seule fois, dans `components/ui` Modal) :
  - `max-h-[calc(100vh-2rem)]`, en-tête et pied fixes, corps défilant ;
  - vérifier **toutes** les fenêtres à 1280×720 et 375×812.
- **Test** :
  - Playwright : à 1280×720, « Créer » est visible et cliquable dans « Nouveau fournisseur »
    et « Nouvelle immobilisation » ;
  - balayage des fenêtres principales.

### E2 — Immobilisations (non testées, à dérouler après E1)
- Linéaire : ordinateur 1 800 € HT au 01/03/2026 sur 3 ans, dotation 2026 **500,00**.
- Dégressif : machine 12 000 € sur 5 ans, coefficient **légal paramétré** (W5 : 1,5 / 2 / 2,5)
  → 5 ans = coefficient 2 → taux 40 % → 12 000 × 40 % × 10/12 = **4 000,00**.
  L'attendu 3 500 du brief (coefficient 1,75) est **obsolète** : le coefficient 1,75 n'est plus en vigueur. À corriger dans le brief.
- Générer les dotations, plan d'amortissement, écriture 6811/28x, cession.

---

## 9. Lot F — Comptabilité générale (≈ 1,5 j)

### F1 — cpt-001 🟡 — plan comptable : soldes à 0 alors que 512000 porte 10 000
- **Correctif** : ne plus lire les colonnes `chart_accounts.balance/current_debit/current_credit`
  (jamais tenues). Lire les soldes depuis `journal_lines` validées par une vue ou une RPC
  (même doctrine que 277 et 278 : le grand livre est la seule vérité). Compteur d'« actifs »
  par classe.
- **Test rouge** : SQL, 512000 solde 10 000 et 890000 −10 000.

### F2 — cpt-004 🟡 — tout compte sans type précis enregistré « Actifs courants »
- **Correctif** :
  - `account_type` déduit de la **classe** quand il n'est pas choisi
    (1 capitaux/dettes long terme, 2 immobilisations, 3 stocks, 4 tiers selon racine,
    5 trésorerie, 6 charges, 7 produits, 8 spéciaux) ;
  - `racine`/`classe` recopiées du numéro ;
  - **migration de rattrapage** des 714 comptes du plan livré (299 en classe 6 aujourd'hui en asset_current) ;
  - 890000 corrigé.
- **Test rouge** : SQL, aucun compte 6 ni 7 en `asset_current` ; 606810 en `expense`.

### F3 — cpt-002 🔵 — plan comptable ouvert vide (« 0 sur 713 »)
- **Correctif** : état initial = tout afficher ; état vide réservé à 0 compte.

### F4 — cpt-003 🔵 / rh-001 / tous — messages SQL bruts
- **Correctif transversal** : un **traducteur d'erreurs** (`lib/errors.ts`) qui mappe
  `23505`, `23514` et les contraintes nommées vers des messages fr/en/ar
  (« Le compte 606800 existe déjà »). À appliquer sur les toasts d'erreur globaux.
- **Test** : Vitest du traducteur (5 contraintes connues + repli générique).

### F5 — cpt-006 🔵 — libellés sans accents (périodes, plan livré)
- **Correctif** : migration de données sur `fiscal_periods.name` (Février, Août, Décembre)
  et les libellés du plan livré (« stockés », « matières »…), avec la fonction de création
  de périodes corrigée pour les exercices futurs.

### F6 — cpt-007 🔵 — modèle de saisie : le pourcentage 100 recopié comme montant
- **Correctif** : type « À saisir » donne un montant vide ; le pourcentage ne s'applique que si
  un montant de base est saisi. À reproduire avant de corriger (vu une fois).

### F7 — cpt-008 🔵 — date proposée hors de la période choisie
- **Correctif** : date par défaut = aujourd'hui si elle est dans la période, sinon le 1er jour
  de la période.

---

## 10. Lot G — Analytique, projets, budgets (≈ 1,5 j)

### G1 — pil-008 🟠 — impossible d'imputer une section analytique sur une facture
- **Correctif** :
  - champ « Section analytique » par ligne de facture et d'avoir (le porteur
    `invoice_lines.analytic_section_id` existe, 304), liste des sections actives ;
  - application automatique de la **grille de ventilation** du compte de la ligne ;
  - modification d'un **brouillon** possible ;
  - la page « Saisie OD analytique » reçoit un vrai formulaire, ou est retirée du menu.
- **Dépend de** : B2 (compte de la ligne).
- **Test** : banc écran, facture avec section PIL01, puis balance analytique FY2026 PIL01 = 100,00.

### G2 — pil-007 🟡 — grille de ventilation en texte libre
- **Correctif** : compte choisi dans le plan et section dans les sections (listes) ; côté base,
  clé `(tenant_id, section_id)` vers `analytic_sections` au lieu de `section_code` texte
  (migration + rattrapage).
- **Test rouge** : compte 706999 ou section ZZZ99 refusés.

### G3 — pil-006 🟡 — formulaire de tâche sans parent ni avancement
- **Correctif** : champs « Tâche parente » (liste des tâches du projet) et « Avancement (%) ».
  Le refus de cycle (303) doit remonter en message lisible.
- **Test** : banc écran, 10 h à 100 % + 90 h à 0 % → **10 %** (liste, fiche et Gantt
  identiques) ; parent = soi-même refusé avec un message nommé.

### G4 — pil-003 🔵 / pil-004 🔵 — clé i18n brute ; Gantt et calendrier en anglais
- **Correctif** : ajouter `hub.projectManagement.subtitle` ; passer la locale (`fr`, `ar`) aux
  bibliothèques Gantt et calendrier (date-fns ou Intl).

### G5 — Constats non inscrits (projets et budgets)
| Constat | Correctif |
|---|---|
| « 100.0% » au lieu de « 100,0 % » (suivi budgétaire) | `Intl.NumberFormat(locale, { style: 'percent' })` |
| engagement : choix par défaut « Aucun engagement » dans le champ fournisseur | libellé « — Choisir un fournisseur — » |
| engagement −50 refusé avec « Une erreur est survenue » | message clair (F4) + `min=0` |
| formulaire client : UUID de la société parente et du commercial | listes (A4) |

---

## 11. Lot H — Tableaux de bord et trésorerie (≈ 1 j)

### H1 — COORD-010 🟠 / ven-018 🟠 — « Encaissements » = total facturé ; deux soldes bancaires
- **Cause établie** : `getDashboardChartData` additionne `invoices.total` et
  `purchase_invoices.total`.
- **Correctif** :
  - encaissements et décaissements lus sur les mouvements réels du **512x** au grand livre (doctrine 277/278) ;
  - la carte « Comptes bancaires » lit le même solde comptable que la tuile ;
  - l'« Insight IA » lit les factures en retard (B9).
- **Test rouge** : Vitest avec requêtes simulées (encaissements = somme des débits 512) et scénario
  écran (après les 2 règlements VEN, encaissements ≥ 631,65 ; tuile et carte identiques).

### H2 — Non testé, à couvrir par la recette finale (voir § 12)
- Trésorerie : relevé, deux opérations identiques de 42 € (M4), règles, rapprochement, état de
  rapprochement, virement interne, prévisions.
- États : balance, grand livre, journaux, balance auxiliaire, bilan, compte de résultat,
  SIG, CA3, FEC.

---

## 12. Recette finale et contrôle croisé global (≈ 3 j)

Le contrôle croisé demandé (« voir si les résultats se contredisent ») **n'a pas été fait** :
les six agents ont été coupés avant. Il est l'objet de cette dernière phase.

### 12.1 Reprise des parcours non testés
| Agent | Reprendre à | Contenu |
|---|---|---|
| `ach` | étape 3 | demande d'achat → commande (HT 300 / TVA 60 / TTC 360) → réceptions 6 + 4 → facture ; frais généraux 1 440 ; intracom 500 (autoliquidation 100/100) ; avoir 20/4 ; règlements ; SEPA ; lettrage ; 3 voies ; balance âgée ; échéancier |
| `cpt` | trésorerie | `/banking/transactions`, `/banking/reconciliation`, puis tous les états, CA3, FEC, lettrage |
| `rh` | après C1 | février propre vs bulletins d'or ; mars avec absences et heures sup ; écriture 641/645/421/431 ; DSN ; provision ; note de frais 120 TTC (D 100 + 20 / C 421 120) |
| `stk` | après E1 | immobilisations (§ 8.E2), transfert (si D-QA-5), MRP, réservations, exports |
| `pil` | après G3 | scénario projet complet (10 %, cycle, 3 h × 80 = 240 HT) ; tableaux de bord ; **balayage des 281 routes** (`qa/pil-routes.txt`) ; FR/EN/AR (RTL), mode sombre, mobile 375×812 |
| `ven` | après B | remises, conditions de paiement, acomptes, factures récurrentes, exports, entrées invalides |

### 12.2 Contrôles croisés (chacun avec requête SQL **et** chiffre affiché à l'écran)
| # | Contrôle | Égalité attendue |
|---|---|---|
| X1 | Balance générale | Σ débit = Σ crédit (toutes écritures validées) |
| X2 | Résultat | Σ classe 7 − Σ classe 6 = résultat du compte de résultat = résultat au bilan (passif) |
| X3 | Bilan | actif = passif |
| X4 | Banque | solde 512000 au grand livre = Trésorerie = carte et tuile du tableau de bord = état de rapprochement (après rapprochement) |
| X5 | Ventes | Σ HT des factures validées − avoirs = Σ crédits nets 70x (par compte 706/707) ; = CA du tableau de bord ; = CA de la CA3 (300) |
| X6 | TVA | TVA collectée CA3 = solde 4457x ; déductible = solde 4456x ; TVA due = différence |
| X7 | Clients | solde 411 par tiers = reste dû de la liste des factures = fiche client = balance âgée = contrôle crédit |
| X8 | Fournisseurs | solde 401 par tiers = reste à payer = balance âgée fournisseurs |
| X9 | Stock | quantité fiche = Σ mouvements = colonnes Entré/Sorti ; valeur écran = Σ couches = solde 31x+35x+37x |
| X10 | Production | coût OF = consommations valorisées = écriture 601/310 + 355/7135 ; écart affiché = `cost_variance` |
| X11 | Caisse | Z de clôture = Σ tickets − annulés ; 530000 = fond + espèces − remises en banque |
| X12 | Paie | totaux du lot = Σ bulletins ; Σ nets = crédit 421 ; brut = débit 641 ; charges = 645 ; simulateur = bulletin |
| X13 | Immobilisations | dotations = plan d'amortissement = débit 6811 = crédit 28x |
| X14 | Analytique | balance analytique (ventes + achats) = balance générale des comptes ventilés |
| X15 | Projets | avancement liste = fiche = Gantt ; temps facturable = ligne de brouillon de facture |
| X16 | FEC | nombre de lignes = lignes d'écriture validées ; 18 colonnes ; nom `123456782FEC20261231.txt` ; validateur 0 erreur majeure |
| X17 | Budgets | réalisé = Σ 6xx de l'exercice 2026 uniquement ; engagement consommé à la facture |

Chaque écart est inscrit comme défaut `X-nn` avec les deux chiffres et la requête SQL.

### 12.3 Clôture de fin (en dernier, par le coordinateur seul)
Clôture des périodes, puis de l'exercice FY2026 ; à-nouveaux 2027 ; bilan d'ouverture 2027 =
bilan de clôture 2026 ; écritures postérieures refusées dans la période close.

### 12.4 Critères de sortie
- **0 défaut critique ni haut ouvert** ; moyens et bas tous corrigés ou explicitement reportés
  avec leur décision.
- **17/17 contrôles croisés verts.**
- Batterie SQL complète verte sur **base neuve** ; banc écran 15/15 + nouveaux scénarios ;
  `tsc`, `oxlint`, i18n, Vitest, tests Edge, Playwright verts.
- Rapport de recette publié (`doc/audit/RECETTE-QA-<date>.md`) avec les preuves, et mise à
  jour d'`AGENTS.md` et de `RESTE-OUVERT`.

---

## 13. Ordonnancement et charges

| Ordre | Lot | Contenu | Charge | Dépend de |
|---|---|---|---|---|
| 1 | — | Préalables d'environnement (§ 3) | 0,25 j | — |
| 2 | **C1** ✅ | Bulletins de paie (rh-006) | 1,5 j | — |
| 3 | **A1–A3** ✅ | Plan tiers, balance âgée, solde dû | 1,5 j | — |
| 4 | **B10** ✅ | Boucle du contrôle crédit | 0,25 j | — |
| 5 | **B1** | Sortie de stock du BL | 0,5 j | — |
| 6 | **E1** | Fenêtres qui débordent (Modal) | 0,5 j | — |
| 7 | **D1, D2, D4** | Comptes de sortie, valorisation, dates UTC | 1,5 j | — |
| 8 | **H1** | Tableau de bord sur le grand livre | 0,5 j | — |
| 9 | B2–B9, B11, B12 | Reste des ventes | 3 j | A4 pour B3 ; D-4 pour B8 |
| 10 | C2–C6 | Reste de la paie | 2,5 j | C1 |
| 11 | D3, D5–D12 | Reste du stock et de la caisse | 2 j | D1 |
| 12 | F1–F7 | Comptabilité | 1,5 j | — |
| 13 | G1–G5 | Analytique, projets | 1,5 j | B2 |
| 14 | A4–A6 | Fiches tiers | 1 j | — |
| 15 | E2 + § 12 | Recette finale, contrôle croisé, clôture, rapport | 3 j | tout |
| | | **Total** | **≈ 22 j** | |

Parallélisable : les lots **A**, **C** et **D** touchent des fichiers distincts. Deux sessions
peuvent les mener en même temps si elles **constatent** leurs numéros de migration au commit
et commitent par index privé (`GIT_INDEX_FILE`).

---

## 14. Décisions à prendre (bloquent un correctif)

| ID | Question | Options | Recommandation |
|---|---|---|---|
| **D-QA-1** | Une facture directe d'article stocké, sans BL, sort-elle le stock ? | (a) oui à la validation ; (b) non, BL obligatoire pour un bien | (a) avec garde anti-double sortie si un BL existe |
| **D-QA-2** | Facture datée avant la dernière numérotée | (a) refus ; (b) avertissement | (a) : chronologie exigée pour la piste d'audit fiable |
| **D-QA-3** | Articles existants à prix négatif | (a) remis à 0 ; (b) désactivés | (b) : ne pas inventer de prix |
| **D-QA-4** | Contrepartie comptable du stock initial | (a) AN 3x/890000 ; (b) avertissement seulement | (a), cohérent avec la banque (277) |
| **D-QA-5** | Transfert entre dépôts | (a) créer l'écran ; (b) hors périmètre | (a) : fonction de base d'un multi-dépôt |
| **D-4** (existante) | `generate-pdf` | rebrancher ou PDF navigateur | PDF navigateur (B8), sans service externe |
| **D-G** (existante) | Grille paie 276, arrêt maladie, carence | signature de l'expert-comptable | inchangé : ne pas déployer avant |

---

## 15. Gardes-fous à ajouter (pour que ces défauts ne reviennent pas)

| Garde | Ce qu'elle aurait vu |
|---|---|
| `check-written-columns` étendu aux **objets construits puis passés** à `.insert()` (suivi de la variable) | pil-005 (colonne fantôme restée verte) |
| Contrôle « **une fonction, un nom** » : aucune surcharge exposée à PostgREST | stk-005 |
| Contrôle statique « **pas de `toISOString()` pour une date métier** » | stk-013, rh-007 |
| Test Playwright « **toutes les fenêtres tiennent à 1280×720** » | ach-001, stk-015 |
| Test Playwright « **balayage des routes** » (0 erreur console, 0 requête 4xx/5xx, 0 clé i18n brute) | pil-002, pil-003, ven-003 |
| Détecteur de **boucle de requêtes** en test (≤ N appels par montage) — **✅ fait** : budget de requêtes dans `CreditControlPage.test.tsx` (la source se gèle au-delà du plafond) + règle statique `15-no-render-body-call.rule` | ven-016 |
| Contrôle « **aucune colonne dénormalisée lue sans être tenue** » (balance, credit_used, soldes du plan) | ven-017, cpt-001 |
| Scénario banc écran « **client créé → compte tiers** » | ven-013 |

---

## 16. Index de tous les défauts

| ID | Grav. | Titre court | Lot | État |
|---|---|---|---|---|
| COORD-001 | 🔴 | inscription : aucun pays | — | ✅ 1699bbd |
| COORD-002 | 🔵 | `<strong>` brut | — | ✅ a8f58ed |
| COORD-003 | 🟠 | e-mail annoncé non envoyé | — | ✅ a8f58ed |
| COORD-004 | 🔵 | `profiles` absente | — | ✅ 55ae7f5 |
| COORD-005 | 🟡 | vitrine pour un connecté | — | ✅ 9782641 |
| COORD-006 | 🔵 | modules présélectionnés | — | non retenu |
| COORD-007 | 🔵 | 406 au chargement | — | ✅ bbae422 |
| COORD-008 | 🟡 | 238 sur Supabase neuve | — | ✅ 3808646 |
| COORD-009 | 🔵 | libellés non traduits | — | ✅ 02fdda4, c8f1148 |
| COORD-010 | 🟠 | encaissements = facturé | H1 | ouvert |
| ven-001 | 🟡 | fiche client incomplète | A4 | ouvert |
| ven-002 | 🔵 | colonne Total = date | A6 | ouvert |
| ven-003 | 🔵 | div dans tbody | B11 | ouvert |
| ven-004 | 🟠 | BL avec service bloqué | B1 | ouvert (test prêt) |
| ven-005 | 🔴 | BL livré sans sortie | B1 | ouvert (test prêt) |
| ven-006 | 🟡 | facture de BL sans client | B6 | ouvert |
| ven-007 | 🟡 | numérotation non chronologique | B7 | ouvert |
| ven-008 | 🟠 | service en 707 | B2 | ouvert |
| ven-009 | 🟠 | pas d'autoliquidation UE | B3 | ouvert |
| ven-010 | 🟠 | téléchargement texte, pas PDF | B8 | ouvert |
| ven-011 | 🟡 | « Créer un avoir » inerte | B5 | ouvert |
| ven-012 | 🟠 | avoir au prorata | B4 | ouvert |
| ven-013 | 🔴 | client sans compte tiers | A1 | ✅ 6409c0e (312) |
| ven-014 | 🟠 | balance âgée « other » | A2 | ✅ 6409c0e (312) |
| ven-015 | 🟡 | filtre En retard vide | B9 | ouvert |
| ven-016 | 🔴 | contrôle crédit en boucle | B10 | ✅ d9197e1 |
| ven-017 | 🟠 | solde dû à 0 | A3 | ✅ 3155a90 (313) |
| ven-018 | 🟠 | tableau de bord incohérent | H1 | ouvert |
| ach-001 | 🟠 | fenêtre fournisseur déborde | E1 | ouvert |
| ach-002 | 🟡 | fiche fournisseur incomplète | A4 | ouvert |
| ach-003 | 🟡 | IBAN invalide accepté | A5 | ouvert |
| ach-004 | 🟡 | produit non modifiable | D6 | ouvert |
| ach-005 | 🔵 | stock bas à seuil 0 | D12 | ouvert |
| cpt-001 | 🟡 | soldes du plan à 0 | F1 | ouvert |
| cpt-002 | 🔵 | plan ouvert vide | F3 | ouvert |
| cpt-003 | 🔵 | message SQL brut | F4 | ouvert |
| cpt-004 | 🟡 | type de compte faux | F2 | ouvert |
| cpt-005 | 🟡 | plan tiers vide | A1 | ✅ 6409c0e (312) |
| cpt-006 | 🔵 | accents manquants | F5 | ouvert |
| cpt-007 | 🔵 | % recopié en montant | F6 | à reproduire |
| cpt-008 | 🔵 | date hors période | F7 | ouvert |
| rh-001 | 🔵 | salaire négatif, message brut | C6 / F4 | ouvert |
| rh-002 | 🔵 | CDI / cdi | C6 | ouvert |
| rh-003 | 🔵 | base_salary, horaire | C6 | ouvert |
| rh-004 | 🔵 | « N° CAMPAGNE » | C6 | ouvert |
| rh-005 | 🟠 | simulateur faux | C2 | ouvert |
| rh-006 | 🔴 | aucun bulletin | C1 | ✅ a7b0570 (311) |
| rh-007 | 🔵 | dates de campagne décalées | C6 / D4 | ouvert |
| rh-008 | 🟠 | heures sup à 0 | C3 | ouvert |
| rh-009 | 🟡 | pointage d'absence impossible | C4 | ouvert |
| stk-001 | 🟠 | prix négatif, fiche figée | D6 | ouvert |
| stk-002 | 🟡 | pas de fiche article | D6 | ouvert |
| stk-003 | 🟡 | sortie à 0,00 € | D7 | ouvert |
| stk-004 | 🟡 | stock initial imposé | D8 | ouvert |
| stk-005 | 🟠 | valorisation ambiguë et fausse | D2 | ouvert |
| stk-006 | 🟡 | inventaire trompeur | D9 | ouvert |
| stk-007 | 🟡 | écarts en JSON brut | D9 | ouvert |
| stk-008 | 🟡 | nomenclature sans article | D10 | ouvert |
| stk-009 | 🟡 | coût nomenclature à 0 | D10 | ouvert |
| stk-010 | 🟠 | OF affiché à 0 | D3 | ouvert |
| stk-011 | 🔵 | numéro d'OF consommé | D11 | ouvert |
| stk-012 | 🟠 | sortie caisse en 603/310 | D1 | ouvert |
| stk-013 | 🟠 | stats caisse vides | D4 | ouvert |
| stk-014 | 🟠 | pas d'annulation de ticket | D5 | ouvert |
| stk-015 | 🟠 | fenêtre immobilisation déborde | E1 | ouvert |
| pil-001 | 🔴 | pas de création de projet | — | ✅ 7d4ecb4 (vérifié) |
| pil-002 | 🟠 | vues projet masquées | — | ✅ 0e8a73d (1/6 revérifiée) |
| pil-003 | 🔵 | clé i18n brute | G4 | ouvert |
| pil-004 | 🔵 | Gantt en anglais | G4 | ouvert |
| pil-005 | 🔴 | tâche jamais créée | — | ✅ db5a00d |
| pil-006 | 🟡 | tâche sans parent ni % | G3 | ouvert |
| pil-007 | 🟡 | grille en texte libre | G2 | ouvert |
| pil-008 | 🟠 | pas de section sur facture | G1 | ouvert |
| pil-009 | 🔵 | validation sans confirmation | B12 | ouvert |

Légende : 🔴 critique · 🟠 haute · 🟡 moyenne · 🔵 basse.
