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
| Critiques | **7** — **tous corrigés** (COORD-001, pil-001, pil-005, rh-006, ven-013, ven-016, ven-005) |
| Hauts | **23** — dont **15 corrigés** (COORD-003, pil-002, ven-014, ven-017, ven-004, ach-001, stk-015, stk-012, stk-005, stk-013, ven-008, ven-012, ven-010) |
| Moyens | **24** — dont **6 corrigés** (cpt-005, ven-006, ven-007, ven-011, ven-015, **ven-001, ach-002**) |
| Bas | **20** — dont **2 corrigés** (ven-003, pil-009) |
| Déjà corrigés et commités | **26 commits** (§ 2) |
| **Restant à corriger** | **≈ 39 défauts**, en **8 lots** (§ 4 à § 11) — le lot « reste des ventes » se réduit à **B3**, désormais **débloqué** (A4 livré le 30/09) |
| Charge estimée | **≈ 15 j** de correctifs + **≈ 3 j** de recette finale (§ 13) |
| Contrôle croisé global | **NON FAIT** — aucune cohérence inter-modules n'est prouvée (§ 12) |

**Les six défauts qui bloquaient un parcours métier entier — tous fermés** (voir le détail plus bas) :

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
4. ~~**ven-005 / ven-004** — BL « Livré » sans sortie de stock ; BL avec service bloqué.~~
   **CORRIGÉ** (`9ef26c8`, migration 314) : la sortie suit « Expédié » **comme**
   « Livré », une seule fois par bon, et ne porte que sur les articles de type
   `stock`. Mesuré à l'écran : stock 50 → 50 puis 0 mouvement avant ; 50 → **48**
   avec **1** mouvement (aucun pour la prestation) après. La commande, elle, ne
   se dit livrée qu'à la sortie réelle.
5. ~~**stk-012** — sortie de caisse d'un produit fini passée en 603/310 au lieu de 7135/355.~~
   **CORRIGÉ** (`d709bf8`, migration 315) : le compte d'une sortie est celui de
   l'entrée qui a nourri la couche consommée. Rejeu sur la donnée de recette :
   l'écriture devient 713500 D 88 / 355000 C 88, 310000 intouché.
6. ~~**ach-001 / stk-015** — fenêtres de création (fournisseur, immobilisation) inatteignables à 1280×720.~~
   **CORRIGÉ** (`e179882`) : le `Modal` commun borne la fenêtre à l'écran (en-tête et
   pied fixes, corps défilant) et les deux fenêtres y passent. Mesuré : « Créer »
   finissait à **840 px** pour 720, il finit à **652–688 px** ; atteignable et
   cliquable à 1280×720 **et** 375×812.

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
| `4c42b07` | **A6 — ven-002** 🔵 colonne « Total » de la liste des clients affichant une date de création | l'en-tête devient **« Créé le »** (`customers.createdAt`), dans la liste comme dans l'export CSV qui portait le même mensonge ; la colonne reste triable sur `created_at`. **Choix de périmètre assumé** : pas de « Total facturé » — ce montant n'existe pas dans le modèle et sa définition (validées seules ? nets d'avoirs ?) n'est écrite nulle part, ce qui est précisément la faute qui fit afficher 0,00 € à côté d'un 411 à 540,00 € (A3/313). Si la recette le veut, la règle s'écrit **avant** l'agrégat | `PartnerIdentityForm.test.tsx` **9/9** (rouges avant : ni `customers.createdAt` dans les en-têtes, `table.total` dans l'export ; `exportToCSV` capturé par un mock partiel de `@/components/ui`) ; Vitest **1543/1543** ; `tsc`/`oxlint`/i18n verts (hors l'erreur paie préexistante d'une autre session) |
| `eaebd85` | **A5 — ach-003** 🟡 un IBAN à clé de contrôle fausse était enregistré (message rouge, mais aucun refus) | **écran** : `src/lib/iban.ts` (validateur pur, dans le sillage de `src/lib/siret.ts` d'A4) — `cleanIban`, `looksLikeIBAN`, `validateIBAN` et `isIbanRejected`, la décision partagée par les **trois** écritures d'un IBAN : compte bancaire du tiers, ordre de paiement (`third_party_iban`, le chemin qui finit en virement), RIB du salarié (`bank_iban`, qui part en paie) ; refus nommé + bouton désactivé. **base** : migration **324**, `is_valid_iban(text)` IMMUTABLE (mod 97-10) + déclencheur `BEFORE INSERT OR UPDATE` — l'API, les imports et les scripts ne peuvent plus écrire un faux IBAN. ⚠️ l'hypothèse du plan (colonne `type = 'iban'`) était **fausse** : la table porte `bank_code`/`sort_code`/`account_key`, d'où la règle « forme ≠ clé » qui n'enferme pas les comptes américains | `324_*_tests` **6/6** (rouge avant mesuré : T01 en erreur — la fonction n'existe pas ; **T02 `refusé=f`**, le faux IBAN accepté ; **T06** la modification laissait `FR…0180` en base) ; `iban.test.ts` **5/5** ; `PartnerBankAccountsModal.test.tsx` **3/3** (rouges avant : bouton actif, `createPartnerBankAccount` appelé) ; voisines 180/197/245/300/312/313/323 vertes ; Vitest **1541/1541** ; `tsc`/i18n verts (hors l'erreur paie préexistante d'une autre session) |
| `cce353d` | **B6 — ven-006 (reste)** 🟡 la fenêtre « Voir » d'une facture n'affichait aucune ligne | `InvoiceDetailModal` passe au `Modal` commun (E1 : corps défilant, piège à focus, Échap) et montre les **lignes** (description, quantité, prix unitaire, taux, total HT) puis la **ventilation HT / TVA par taux** ; le code `vat_code` (UE/EXO, B3) s'affiche à côté du taux. Les lignes étaient déjà chargées (`getInvoices` → `invoice_lines(*)`) : rien n'était à requêter | rouge avant : `Unable to find role="dialog"` (fenêtre = `<div>` nu) ; `SalesDocumentForms` **7/7** ; Vitest **1533/1533** ; `tsc`/`oxlint`/i18n verts |
| `64f4fe5` | **B3 — ven-009** 🟠 client UE : ni autoliquidation, ni mention, Factur-X « Z » | migration **323** : `resolve_fiscal_regime` (pays ISO-2 de la 318 + n° de TVA → `fr`/`eu_vat`/`non_eu`), positions standard semées, `customers`/`suppliers.fiscal_position_id` (FK composite 237, jamais écrasée si posée à la main) ; `vat_code = 'UE'`/`'EXO'` posé sur la ligne **avant** `invoice_line_compute` (197) → écriture 411/70x sans ligne 445x ; écran : position fiscale du client, 0 % proposé d'office, mention obligatoire ; Factur-X `CategoryCode` **AE** (prestation, art. 283-2) ou **K** (biens, art. 262 ter I) avec `ExemptionReason`, distinction lue sur `products.type` | `323_*_tests` **7/7** (rouge avant mesuré en retirant les définitions : 4 échecs d'exécution + client UE taxé à 20 %, 411 à 300, CA3 à 50,00) ; voisines `197`/`245`/`300`/`317`/`318` vertes ; `facturX.test.ts` **8/8** ; Vitest **1532/1532** ; `tsc`/i18n verts (une erreur `PayrollTaxGridLine` préexistante dans le fichier paie d'une autre session, non commis) |
| `318` | **A4 — ven-001 / ach-002** 🟡 fiche client et fournisseur sans SIRET, pays, CP/ville, conditions de paiement | migration **318** : `country` devient un code ISO 3166-1 alpha-2 (existant normalisé, défaut `'France'` retiré, `CHECK … NOT VALID` à deux lettres) ; `payment_term_id` sous clé étrangère **composite** (doctrine 237) ; écran : SIRET + clé de Luhn + « Vérifier », pays ISO, CP, ville, conditions en liste, « Société parente » et « Commercial » en listes | `318_*_tests` **6/6** (rouge avant : 4 rouges / 2 verts) ; `PartnerIdentityForm.test.tsx` **7/7** (rouge avant : 7 rouges, pages revenues à leur état d'avant) ; `siret.test.ts` **8/8** ; **237 8/8** (une régression de clé étrangère mono-colonne attrapée et corrigée dans le commit) ; Vitest **1542/1542** |
| `4721f49` | **B2** écran, **B4/B5** avoir, **B6** dates de la chaîne, **B8** PDF, **B9** « En retard », **B11** `<div>`/`<tbody>`, **B12** confirmation + échéance | sélecteur d'article et compte de vente par ligne ; avoir pré-rempli depuis la facture ; `/sales/credits?invoice=<id>` ; dates d'origine de la chaîne ; `src/lib/invoicePdf.ts` (PDF 1.4 écrit à la main, sans dépendance) ; statut « En retard » calculé ; `<Fragment>` ; `confirmSync` + échéance par conditions de paiement | `invoicePdf.test.ts` **5/5** ; `DraftDocumentPolicy.test.tsx` (MIME `application/pdf`) ; Vitest **1527/1527** ; `tsc`/`oxlint`/i18n verts |
| `c3e95b8` | **B2 — ven-008** 🟠 facture directe créditée en 707 ; **D-QA-1** facture directe d'un article stocké qui ne sort rien ; **B4 — ven-012** 🟠 avoir au prorata sans `invoice_ref` ; **B6 — ven-006** 🟡 facture sans nom de client et datée du jour ; **B7 — ven-007** 🟡 numérotation non chronologique | migration **317** : `invoice_lines.account_code` ; comptes article → famille → ligne → 706000/707000 ; sortie de stock à la validation d'une facture directe (garde anti-double, message nommé) ; nom de client recopié + rattrapage ; date du devis conservée ; refus d'une facture antérieure | `317_*_tests` **12/12** (rouge avant : 8 rouges / 3 verts mesurés en restaurant les définitions de la 316) ; `180` **42/42** (E12/E13 alignés) ; `213` **6/6** ; `228` **7/7** (les nouvelles fonctions ne sont pas exécutables par PUBLIC) ; `tsc`/`oxlint`/i18n verts |
| `d709bf8` | **D1 — stk-012** 🟠 sortie de caisse d'un produit fini en 603/310 | migration **315** : une sortie prend les comptes de l'ENTRÉE qui a nourri la couche consommée (`piece_number = 'STK-…'`, ou `reference = 'JE-OF-…'` pour la production) ; article et famille restent le repli | `315_*_tests` **6/6** (T01 rouge avant) ; familles 173/230/242/251/253/254/281 vertes ; rejeu sur la recette : 713500 D 88 / 355000 C 88, 310000 intouché |
| `d751071` | **D2 — stk-005** 🟠 « Valoriser le stock » ambigu (300) et faux | migration **316** : une seule `calculate_stock_valuation(p_method, p_warehouse_id, p_date)`, adossée à `calculate_stock_valuation_at_date` (couches) ; les deux surcharges supprimées | `316_*_tests` **3/3** (T01/T02/T03 rouges avant) ; recette : 6 lignes, **8 636,00 €** = Σ couches ; 173/254 vertes ; Vitest **1522/1522** |
| `bf49b03` | **D4 — stk-013** 🟠 statistiques de caisse toujours vides | `src/lib/dateRange.ts` (`localDayRange` en `[from, to)` local, `localDateString`) ; `getPosTickets` prend la période ; date de facture d'un ticket au jour local | `dateRange.test.ts` + `d4-pos-tickets-range.test.ts` (6/6) ; écran recette : **216,00 €** de CA TTC et **36,00 €** de TVA ; le harnais manquait `lt` |
| `e179882` | **E1 — ach-001** 🟠 fenêtre fournisseur débordante / **stk-015** 🟠 fenêtre immobilisation débordante | `Modal` commun borné à l'écran (`max-h-[calc(100vh-2rem)]`, en-tête et pied fixes, corps défilant, emplacement `footer` optionnel) ; les deux fenêtres y passent et gagnent le piège à focus, Échap et le verrou de défilement | `e2e/windows-fit.spec.ts` rouge avant (840 px pour 720) puis **4/4** à 1280×720 et 375×812 ; « Créer » à 652–688 px ; captures `ach-001-after.png`, `stk-015-after.png` ; Vitest **1516/1516** |
| `9ef26c8` | **B1 — ven-005** 🔴 BL livré sans sortie de stock / **ven-004** 🟠 BL avec service bloqué ; complément : la commande se disait livrée dès la **création** du bon | migration **314** : la sortie suit « Expédié » **comme** « Livré » (une fois par bon, gardes `23505` et S-07 conservées) et ne porte que sur les articles `type = 'stock'` ; la commande n'est livrée qu'à la sortie — l'écran n'écrit plus `delivery_status` (règle 16) | `314_*_tests` **6/6** (T01, T02, T05b rouges avant) ; suites voisines 173/230/242/251/253 vertes ; écran : stock 50 → **48**, **1** mouvement (0 pour la prestation), commande `delivered` ; Vitest **1516/1516** |
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

Le test de B10 a reçu un complément `21f7e3e` : `tsc -b --noEmit` (le script
`typecheck`) refusait un local non lu (`PLAFOND`) — `tsc --noEmit`, celui de
`verify.sh`, ne voit pas ce cas, d'où deux contrôles qui ne couvrent pas la même
chose.

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
| E5 | Écrire dans le brief des agents : `$B viewport 1280x1000` d'office tant que ach-001/stk-015 ne sont pas corrigés | évite les blocages de fenêtre — **plus nécessaire** : corrigés par `e179882` |
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

### Lot B — reste des ventes livré (30/09) : 317, puis l'écran

Deux commits (`c3e95b8` base, `4721f49` écran) : B2, B4, B5, B6, B7, B8, B9, B11, B12
fermés ; **B3 (ven-009, client UE) reste ouvert** et dépend d'A4 (pays du client).

**Décisions tranchées dans ce lot** : D-QA-1 (option a) et D-QA-2 (option a), D-4
(PDF navigateur, sans service). Les trois sont écrites en § 14.

Quatre leçons de méthode, toutes mesurées :

* **Une décision de règle change des tests qui n'avaient rien à voir.** D-QA-1
  (la facture directe sort le stock) a fait tomber `213` E23/E23d — des scénarios
  de ventilation d'avoir, qui facturaient une marchandise **sans stock**. Ce n'est
  pas une régression : c'est la règle nouvelle. La donnée a été alignée (50 en
  stock), pas le test affaibli. Même chose pour `180` E12/E13, qui encodaient
  l'ancienne numérotation « dans l'ordre de validation » : ils valident désormais
  dans l'ordre des dates (42/42 verts).
* **Mesurer le rouge avant en restaurant les définitions, pas en croyant le
  souvenir.** Les anciennes fonctions de la 316 ont été réappliquées sur la base
  de recette, la suite `317` passée (8 rouges / 3 verts), puis la 317 réappliquée
  (12/12). Le coût : deux minutes ; la valeur : le fichier de test dit ce qui
  était faux, avec le chiffre, au lieu d'affirmer que la règle est nouvelle.
* **Une garde déjà rouge avant le lot se corrige dans le lot.** `228` T06
  (« aucune fonction de public n'est exécutable par PUBLIC ») était rouge depuis
  la **316** : `calculate_stock_valuation` était née exposée, sans que le lot D2
  ne le voie. Les trois REVOKE sont dans la 317 et T06 est vert (7/7).
* **La base de recette n'est pas la CI.** Rejouer les 70 suites SQL dessus pollue
  l'« e-mail de test » des helpers (`users_email_partial_key`) et la rend rouge
  (`250` T06/T11 sont rouges *avec et sans* la 317 — vérifié). La CI, elle, part
  d'une base neuve. Localement, la base neuve n'a pas pu être reconstruite :
  `00_schema_dump.sql` crée `tenants` sans clé primaire, donc la migration
  `multi_tenant_migration` y échoue sur son `ON CONFLICT (id)` — à regarder avec
  le job `db-integration` avant la recette finale.



---

## 4. Lot A — Tiers et comptes auxiliaires (≈ 2,5 j) — **priorité 1**

> **État au 30/09** : A1, A2, A3, A4, A5, A6 **fermés** (`6409c0e`, `3155a90`,
> `318`, `eaebd85`, A6). **Le lot A est clos** : plus aucun défaut ouvert de
> cohérence sur les tiers et leurs comptes auxiliaires. Suite : les relances B9 et
> la ventilation de la CA3 par cases restent ouverts (voir leur section).

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

### A4 — ven-001 🟡 / ach-002 🟡 — fiches client et fournisseur sans SIRET, pays, CP/ville, conditions — **✅ CORRIGÉ** (migration 318)
- **Constat (base de recette, avant)** : 643 clients et 160 fournisseurs, **tous**
  en `country = 'France'`, **0 SIRET** saisi, aucun code postal ni ville par la
  fiche, et « Société parente (ID) » / « Commercial assigné (ID) » demandaient un
  UUID tapé. Un nom de pays n'est pas un code : rien ne distinguait un client
  français d'un client belge, et le générateur Factur-X écrivait « France » là où
  EN 16931 attend deux lettres.
- **Base (migration `318_partner_identity_country.sql`)** :
  - `country` devient un **code ISO 3166-1 alpha-2** ; l'existant est normalisé
    (mesuré : 0 client et 0 fournisseur portent encore un nom de pays) ;
  - le défaut `'France'` est **retiré** — un tiers dont on ne connaît pas le pays
    n'en porte pas. Le repli « pays de la société seulement si non saisi » est
    fait par l'écran, à la saisie ;
  - `payment_term_id` (clé étrangère sur `payment_terms`) : les conditions de
    paiement deviennent une **liste**. Le texte `payment_terms` reste tenu — il
    porte le nom du modèle choisi, et l'échéance d'une facture née d'un bon de
    livraison le lit (`misc.ts`) ;
  - une **garde** : `country` renseigné = deux lettres, `CHECK … NOT VALID`
    (l'existant non normalisable reste rélisible, sera corrigé à la main puis
    `VALIDATE CONSTRAINT`).
- **Écran** (`CustomersPage`, `SuppliersPage`) : SIRET **avec clé de Luhn** et
  bouton « Vérifier » vers `verify-siret` (qui ne dit « vérifié à la source »
  que si l'INSEE a répondu) ; **pays** (liste ISO, repli sur le pays de la
  société) ; code postal ; ville ; **conditions de paiement** (liste) ;
  « Société parente » et « Commercial » deviennent des **listes** — le
  commercial vient de `sales_representatives`, table que vise la clé étrangère
  existante (le plan parlait d'« utilisateurs » : la clé étrangère dit
  autrement, c'est elle qui fait foi).
- **Test rouge avant** : `318_partner_identity_country_tests.sql` — **4 rouges /
  1 vert** mesurés avant la migration (T01 nom de pays accepté, T03 défaut
  `France`, T04 colonne `payment_term_id` absente, T05 803 lignes en nom de
  pays ; T02 est la non-régression voulue). `PartnerIdentityForm.test.tsx` —
  **7 rouges** mesurés en revenant les deux pages à leur état d'avant.
- **Après** : `318_*_tests` **6/6** ; `PartnerIdentityForm.test.tsx` **7/7** ;
  `siret.test.ts` **8/8** ; non-régression **237 (8/8), 312 (7/7), 313 (6/6),
  317 (12/12), 180 (22/22), 213 (6/6), 228 (7/7), 272 (5/5)** ;
  Vitest **1542/1542** ; `tsc`/`oxlint`/i18n/`check-written-columns`/
  `check-unchecked-writes` verts.
- ⚠️ **Une régression de ma 318, trouvée par le harnais et corrigée dans le même
  commit** : la première version posait `payment_term_id` en clé étrangère
  **mono-colonne** sur `payment_terms(id)` — et le test **237 T08** est
  précisément le garde-fou qui l'interdit (« aucune clé étrangère mono-colonne ne
  relie deux tables cloisonnées »). C'était une vraie fuite d'isolation : un
  client de la société A pouvait pointer vers les conditions d'une société B.
  Corrigé en clé étrangère **composite** `(tenant_id, payment_term_id)` →
  `payment_terms (tenant_id, id)`, avec `ON DELETE SET NULL (payment_term_id)`
  (la forme de la 237 : seule la référence se détache, `tenant_id` reste) ; le
  scénario **T06** de la 318 vérifie maintenant qu'une condition d'une autre
  société est refusée. 237 est repassé **8/8**.
  *Leçon* : sur ce dépôt, la clé étrangère d'une nouvelle colonne se pose
  composite d'emblée, ou elle attend 237.
- **Ce qu'A4 ne fait pas** : la **capture d'écran** `qa/screenshots/ven-001-after.png`
  (elle demande un navigateur et le serveur Vite du worktree, non montés ici —
  même limite que C1, § 3) ; la vérification à l'écran dans le navigateur ;
  `A5` (IBAN) et `A6` (colonne « Total ») restent ouverts.
- ⚠️ **Correction après coup, au lot suivant** : `npm run typecheck`
  (`tsc -b --noEmit`) révèle que **`npx tsc --noEmit`, celui de `verify.sh`, ne
  vérifie rien** — le `tsconfig.json` racine est une configuration « solution »
  (`files: []`, `references`). Le contrôle de A4 avait donc été fait avec une
  commande qui ne compile pas le projet, et deux erreurs de type étaient
  passées : `city`/`postal_code` écrits `null` là où le type les déclare
  `string`, et `country` incapable de porter le `null` que la contrainte de la
  318 exige. Corrigé au lot C2 (`city`/`postal_code` en chaîne vide,
  `country: string | null`). **Le contrôle à utiliser est `npm run typecheck`.**
- **Débloque** : **B3** (client UE : autoliquidation, mention, `CategoryCode=AE`),
  qui attendait le pays du client.


### A5 — ach-003 🟡 — IBAN invalide accepté — **✅ CORRIGÉ** (324 + écran)
- **Correctif** : validation IBAN (longueur par pays + clé mod 97) côté écran **et** contrainte
  ou déclencheur côté base sur `partner_bank_accounts.account_number` (quand `type='iban'`).
- **Test rouge** : `FR7612345` refusé ; un IBAN valide accepté.
- **Fait (324 + écran)** — l'**hypothèse du plan était fausse** : `partner_bank_accounts`
  n'a **aucune colonne `type`** ; elle porte `bank_code` / `sort_code` / `account_key`,
  les champs d'un compte **américain**. Un déclencheur `type = 'iban'` aurait donc
  bloqué des comptes parfaitement légitimes. La règle écrite distingue les deux
  questions : la **forme** (`^[A-Z]{2}[0-9]{2}`) décide de ce qui est un IBAN, la
  **clé** (mod 97-10) décide de sa justesse.
  - écran : `src/lib/iban.ts` (validateur pur, comme `src/lib/siret.ts` d'A4) —
    `cleanIban`, `looksLikeIBAN`, `validateIBAN`, et `isIbanRejected`, la décision
    partagée par les **trois** écritures d'un IBAN : compte bancaire du tiers,
    ordre de paiement (`third_party_iban`, le chemin qui finit en virement), RIB du
    salarié (`bank_iban`, qui part en paie). Refus nommé + bouton désactivé, comme
    le SIRET d'A4 ;
  - base : migration **324** — `is_valid_iban(text)` IMMUTABLE (mod 97-10, boucle
    chiffre par chiffre, pas de débordement) et un déclencheur `BEFORE INSERT OR
    UPDATE` qui refuse avec le message nommé. Un appel d'API, un import ou un
    script ne peuvent donc plus écrire un faux IBAN.
  - ⚠️ **Choix explicite** : la 324 ne rattrape **pas** l'existant. Corriger une
    ligne déjà fausse échouerait (l'`UPDATE` passe par le même déclencheur) ; le
    plan ne demandait pas de reprise de données, et un rattrapage automatique en
    silence serait pire qu'un refus visible. Le nettoyage éventuel est une
    opération ponctuelle, à faire sur les lignes concernées.
- **Preuves** : `324_*_tests` **6/6** (rouge avant mesuré : T01 en erreur de
  compilation — la fonction n'existe pas ; **T02 le IBAN faux était accepté**
  (`refusé=f`) ; T06 la modification laissait `FR…0180` en base) ; voisines 180 /
  197 / 245 / 300 / 312 / 313 / 323 vertes ; `iban.test.ts` **5/5**,
  `PartnerBankAccountsModal.test.tsx` **3/3** (rouges avant : le bouton n'était pas
  désactivé et `createPartnerBankAccount` était appelé) ; Vitest **1541/1541**.

### A6 — ven-002 🔵 — colonne « Total » de la liste des clients = date de création — **✅ CORRIGÉ** (écran)
- **Correctif** : colonne « Total facturé » (somme HT validée) ou en-tête « Créé le ».
- **Fait** : l'en-tête devient **« Créé le »**, dans la liste comme dans l'export
  CSV — le CSV portait le même mensonge (les cinq autres en-têtes y sont, eux,
  correctement alignés sur leurs valeurs). La colonne reste triable sur
  `created_at`.
- **Choix de périmètre, assumé** : on n'a **pas** remplacé la colonne par un
  « Total facturé ». Un tel montant n'existe nulle part dans le modèle, et sa
  définition n'est écrite nulle part (factures validées seules ? nets des avoirs
  ? annulées ?) : c'est exactement le nombre sans définition qui avait produit
  le 411 à 540,00 € contre 0,00 € à l'écran (A3/313). Si la recette le veut, c'est
  un **agrégat à définir d'abord** (`sum(invoices.subtotal)` sur les validées,
  moins les avoirs), pas un en-tête à recopier — on le fera quand la règle
  sera écrite.
- **Preuve** : `PartnerIdentityForm.test.tsx` **9/9** (rouges avant : aucun en-tête
  `customers.createdAt`, et les en-têtes de l'export venaient avec
  `table.total`) ; Vitest complet vert ; `tsc`/`oxlint`/i18n verts.

---

## 5. Lot B — Ventes (≈ 4 j)

> **État au 30/09, après A4** : B1, B2, B3, B4, B5, B6, B7, B8, B10, B11, B12
> **fermés** (`c3e95b8` la base, `4721f49` l'écran, `64f4fe5` B3/UE, puis la
> fenêtre « Voir »). B3 est livré : régime déduit du pays (318) et du n° de TVA,
> `vat_code` UE/EXO posé avant le calcul, mention à l'écran et au PDF, Factur-X
> `AE`/`K` ; la fenêtre « Voir » montre lignes et HT/TVA par taux.
> **Reste ouvert** : la **relance** de B9 (chaîne de relances d'écran
> `/accounting/treatment/payment-reminders`) et la ventilation de la CA3 par
> **cases** (E1/E2/ligne 06) — le `vat_code` est posé pour elle.

### B1 — ven-005 🔴 / ven-004 🟠 — sortie de stock du BL — **✅ CORRIGÉ** (`9ef26c8`, migration 314)
- **Cause établie** : `create_stock_out_on_delivery()` ne réagissait qu'au passage à `shipped`
  (`NEW.status = 'shipped'`, 133) — choisir « Livré » depuis la liste partait donc sans
  mouvement, en contournant le contrôle de disponibilité — et il sortait **toutes** les
  lignes, services compris, si bien que le contrôle refusait le bon entier
  (« Stock insuffisant: disponible=0, demandé=1 », le « 1 » étant la prestation).
- **Correctif** (migration `314_delivery_stock_out_on_ship_or_deliver.sql`) :
  - condition `OLD.status NOT IN ('shipped','delivered') AND NEW.status IN ('shipped','delivered')` ;
  - sortir seulement les lignes dont `products.type = 'stock'` et `product_id IS NOT NULL` ;
  - garder le refus de réexpédition (`23505`) et la libération de réservation (S-07, 242) ;
  - **complément** : c'est la sortie qui pose `delivery_status` / `fully_delivered` de la
    commande ; l'écran ne les écrit plus (`misc.ts`) et la garde statique
    `verify-rules/16-no-client-delivery-status.rule` le tient.
- **Test rouge avant** : `314_delivery_stock_out_on_ship_or_deliver_tests.sql` — le fichier
  annoncé (`311_delivery_stock_out_tests.sql`) **n'existait pas** (311 était pris par la paie) ;
  il est écrit ici, sous son propre numéro :
  - T01 ❌ « En attente » → « Livré » sort 2 (1000 → 998) ;
  - T02 ❌ article + prestation : l'article sort, la prestation ne bloque rien et ne sort rien ;
  - T03 ✅ expédié puis livré ne sort qu'une fois (non-régression 230) ;
  - T04 ✅ réexpédition d'un BL annulé refusée avec un message (non-régression 230) ;
  - T05a ✅ créer le bon ne déclare pas la commande livrée ; T05b ❌ la livrer la déclare.
  Après correctif : **6/6 verts**, et les suites voisines 173/230/242/251/253 restent vertes
  (0 rouge, 0 erreur). Étape CI ajoutée après la 313.
- **Écran** (société « QA Recette SARL », parcours réel : bon créé par le formulaire de
  l'écran, puis bascule directe « Livré ») : à la création, commande encore `pending` /
  `fully_delivered=false` et stock inchangé (50, 0 mouvement) ; après bascule, stock **48**,
  **1** mouvement (0 pour la prestation), commande `delivered` / `true`, badge « Stock » à
  « Sorti », aucun message d'erreur. Captures `ven-004-005-1-bon-en-attente.png` et
  `ven-004-005-2-bon-livre.png`.
- **Conséquence d'écran à connaître** : sur une commande confirmée dont le bon n'est pas
  encore expédié, le bouton « Nouveau bon de livraison » reste proposé (c'est
  `delivery_status` qui le masquait, et il ne bascule plus à la création) ; le formulaire
  refuse alors avec « rien à livrer », puisque tout est déjà affecté. Gênant, sans gravité —
  à reprendre avec le reste du lot B (B2/B3).
- **Hors périmètre, inchangé** : une facture directe d'article stocké, sans BL, ne sort
  toujours pas le stock — c'est la décision **D-QA-1** (§ 14), à trancher avec B2/B3.


### B2 — ven-008 🟠 — facture directe sans choix d'article : service crédité en 707, stock inchangé — **✅ CORRIGÉ** (317, `c3e95b8`)
- **Correctif front** (`InvoicesPage`, formulaire de ligne) :
  - sélecteur d'article comme sur le devis, qui pré-remplit description, prix, taux, `product_id` ;
  - saisie libre maintenue, avec un compte de vente choisi (706/707) quand il n'y a pas d'article.
- **Base** : la comptabilisation lit `invoice_lines.product_id` → `products.sale_account_code`,
  sinon le compte de la ligne, sinon 706 pour un service et 707 pour un bien.
  Une facture directe d'article stocké **sans BL** sort le stock à la validation (décision à
  prendre : **D-QA-1**, voir § 14).
- **Test rouge** : facture 3 × livre 5,5 % + 1 × service donne 707 C 30, **706 C 250**,
  445713 C 1,65, 445711 C 50 et 411 D 331,65.
- **Fait (317)** : `invoice_lines.account_code` (nouvelle colonne) ; la comptabilisation
  lit article → famille → ligne → 706000 (prestation) / 707000 (bien) ; l'écran porte
  un **sélecteur d'article** par ligne et, en saisie libre, le **compte de vente**.
  Mesuré : `317` T01–T04 verts (706 250 / 707 30 / l'article prime), rouges avant (707 C 280).
  **D-QA-1 tranchée (option a)** : la facture directe d'un article stocké sort le stock à
  la validation, une seule fois, et une ligne née d'un BL ne ressort rien (T05, T09) ;
  une sortie impossible refuse la validation avec un message nommé.

### B3 — ven-009 🟠 — client UE : ni autoliquidation, ni mention, Factur-X « Z » — **✅ CORRIGÉ** (323 + écran)
- **Correctif** :
  - position fiscale du client (FR, UE assujetti, hors UE), déduite du pays et du n° TVA, modifiable ;
  - facture à un client UE assujetti : taux 0 proposé d'office et mention
    « Autoliquidation — art. 283-2 CGI » (services) ou « Exonération art. 262 ter I CGI » (biens) ;
  - `vat_code` posé sur la ligne 70x, pour que la CA3 range l'opération (cases E1, E2 et
    ligne 06 « autres opérations non imposables ») ;
  - Factur-X : `CategoryCode=AE` pour une prestation autoliquidée, `K` pour une livraison
    intracommunautaire, avec `ExemptionReason`.
- **Dépend de** : ~~A4 (pays du client)~~ — **délivré le 30/09 par la 318** : le
  pays du client est un code ISO 3166-1 alpha-2 (`customers.country`), sans nom
  de pays et sans défaut « France », gardé par une contrainte ; `isEuCountry()`
  et `EU_COUNTRY_CODES` sont là pour déduire la position fiscale. Le reste de B3
  (mention, `vat_code`, `CategoryCode=AE`) est écrit contre ce modèle et n'a plus
  de préalable.
- **Tests** :
  - SQL : écriture avec `vat_code`, et CA3 qui porte le montant en non imposable ;
  - Vitest : générateur Factur-X, catégorie AE et motif d'exonération.
- **Fait (323 + écran)** : le **régime** d'un tiers se déduit du pays (ISO-2, 318)
  et du n° de TVA — `resolve_fiscal_regime` : `fr` / `eu_vat` (UE **avec** n° de
  TVA) / `non_eu` / `NULL` si le pays est inconnu (on ne devine pas). La position
  fiscale du **tiers** existe (`customers.fiscal_position_id`,
  `suppliers.fiscal_position_id`, FK composite 237) et les trois positions
  standard sont semées par société (la table était **vide** — l'écran
  « Positions fiscales » la remplissait à la main). Un choix explicite n'est
  **jamais** écrasé (T04).
  La base pose `vat_code = 'UE'` (0 %) sur une vente à un client UE assujetti et
  `'EXO'` hors UE, **avant** `invoice_line_compute` (197) qui annule la TVA :
  l'écriture est 411 D / 70x C **sans aucune ligne 445x** (T05) et la CA3 déclare
  le CA **sans** TVA collectée (T06 — mesuré 50,00 avant). L'écran propose 0 %
  d'office, affiche la mention obligatoire, et Factur-X porte `AE` (prestation,
  art. 283-2) ou `K` (livraison de biens, art. 262 ter I) avec son
  `ExemptionReason` — la distinction biens/services se lit sur `products.type`.
  ⚠️ **Reste ouvert et nommé** : la ventilation par **cases** de la CA3
  (E1/E2/ligne 06) n'existe pas — `calculate_vat_ca3` déclare le CA global et la
  TVA par compte, pas par case. Le `vat_code` est posé pour qu'une CA3 qui ventile
  le lise ; c'est un correctif séparé (hors de ce lot).
  Preuves : `323_*_tests` **7/7** (rouge avant mesuré : 4 échecs d'exécution + le
  client UE taxé à 20 %, 411 à 300, CA3 à 50,00) ; `197` 7/7, `245` 9/9, `300`,
  `317` 12/12, `318` 6/6 vertes ; `facturX.test.ts` 8/8.

### B4 — ven-012 🟠 — avoir ventilé au prorata (706 55,56 / 707 44,44) au lieu de l'article rendu — **✅ CORRIGÉ** (317, `c3e95b8`)
- **Correctif** :
  - l'avoir reprend les **lignes de la facture source** (quantités modifiables) avec leur
    `product_id` et leur compte ;
  - la comptabilisation se fait **par ligne**, pas au prorata ;
  - `journal_entries.invoice_ref` est posé (pour le lettrage) ;
  - le retour en stock est optionnel si l'article est stocké.
- **Écran** : colonne « Facture source » renseignée ; bouton « Créer un avoir » de la liste
  branché (ven-011).
- **Test rouge** : avoir de 1 × Bien A donne 707 D 100, 445711 D 20, 411 C 120 ; aucune ligne 706.
- **Fait (317 + écran)** : l'écran des avoirs **reprend les lignes de la facture source**
  (client, article, prix, taux, compte, quantités modifiables) — c'est ce qui manquait :
  la ligne d'avoir saisie à la main n'avait pas d'article, d'où la ventilation au prorata
  (213 R-05, conservée pour une ligne sans article). L'écriture d'avoir porte
  `invoice_ref` (T06b, rouge avant : vide), et la liste montre la facture source par son
  **numéro** (elle affichait huit caractères d'identifiant).

### B5 — ven-011 🟡 — « Créer un avoir » depuis la liste ne fait rien — **✅ CORRIGÉ** (écran)
- **Correctif** : brancher l'action pour ouvrir l'avoir pré-rempli (client, facture source, lignes).
- **Fait** : l'action ouvre `/sales/credits?invoice=<id>` ; l'écran des avoirs lit le
  paramètre et ouvre le formulaire pré-rempli (le `window.prompt` sans suite est retiré).

### B6 — ven-006 🟡 — facture née d'un BL : client vide, date du jour imposée — **✅ CORRIGÉ** (317 + écran)
- **Correctif** :
  - `customer_name` recopié (ou lu par jointure partout) ;
  - date de la facture choisie à la transformation (par défaut la date du BL) ;
  - la fenêtre « Voir » affiche les lignes, le HT et la TVA par taux.
- **Même défaut sur la chaîne** : devis → commande → BL imposent tous la date du jour
  (le devis du 10/09 donne une commande au 29/09). Proposer la date d'origine.
- **Test** : SQL `create_*_from_*` (client et date recopiés).
- **Fait (317 + écran)** : déclencheur `invoice_fill_customer_name` (nom recopié à
  l'écriture) + rattrapage de l'existant ; la facture née d'un devis garde la date du
  devis (`convert_quote_to_invoice`, T07b rouge avant : 30/09 pour un devis du 10/09) ;
  la chaîne devis → commande → BL → facture transporte la date d'origine et l'échéance
  suit les conditions de paiement du client. La fenêtre « Voir » d'une facture
  affiche désormais ses **lignes** (description, quantité, prix unitaire, taux,
  total HT) et la ventilation **HT / TVA par taux**, sur le `Modal` commun
  (correction du dernier point ouvert de restitution, cf. journal).

### B7 — ven-007 🟡 — numérotation non chronologique malgré l'annonce — **✅ CORRIGÉ** (317)
- **Correctif** : à la validation, refuser une facture datée **avant** la dernière facture
  numérotée de la série, ou avertir et demander confirmation. Décision **D-QA-2** : refus
  strict ou avertissement ; l'obligation légale française penche pour le refus.
- **Test rouge** : valider FAC du 12/09 après FAC du 29/09 est refusé, avec un message nommé.
- **Fait (317, D-QA-2 = option a)** : `invoice_guard` refuse une facture datée avant la
  dernière validée de la société (T08 : refus + statut `draft` conservé, message nommé).
  Deux suites portaient l'ancien comportement et ont été alignées : `180` E12 (validation
  dans l'ordre des dates) et E13 (1 000 pièces à date constante) — **42/42 vertes**.

### B8 — ven-010 🟠 — « Télécharger » produit un texte de 156 octets au lieu d'un PDF — **✅ CORRIGÉ** (écran)
- **Dépend de la décision D-4** (`generate-pdf` non déployée).
- **Correctif** : générer le PDF côté navigateur (bibliothèque déjà présente dans le bundle `pdf`) avec :
  - vendeur (raison sociale, SIREN, n° TVA, adresse) et client ;
  - lignes, HT par taux, TVA, TTC ;
  - mentions légales : pénalités de retard, indemnité forfaitaire de 40 €, escompte,
    autoliquidation le cas échéant.
- **Correction immédiate** « Client: null » (vient de B6).
- **Test** : Vitest (le document contient le SIREN, les lignes, les mentions ; MIME
  `application/pdf`).
- **Fait** : `src/lib/invoicePdf.ts` — PDF 1.4 minimal écrit à la main (Helvetica, WinAnsi,
  xref refermable), **sans dépendance nouvelle** (`pdfjs-dist` ne sait que lire). Vendeur
  (SIRET/SIREN, TVA, adresse), client, lignes, HT par taux, TVA, TTC, reste dû et mentions ;
  brouillon en `PRO-FORMA-….pdf`. Preuves : `invoicePdf.test.ts` 5/5 (dont `%PDF-1.4`,
  `startxref` qui pointe bien sur `xref`, échappement des parenthèses) et
  `DraftDocumentPolicy.test.tsx` (MIME `application/pdf`). ⚠️ La mention d'autoliquidation
  (`CategoryCode=AE`) reste à porter avec B3 ; le service Edge `generate-pdf` n'est pas concerné.

### B9 — ven-015 🟡 — filtre « En retard » vide, statut jamais « En retard », aucune relance — **✅ CORRIGÉ** (écran ; relance reste ouverte)
- **Correctif** :
  - statut calculé `overdue` quand `due_date < aujourd'hui` et `amount_due > 0` ;
  - filtre sur ce critère ;
  - message d'état vide correct (« Aucune facture en retard ») ;
  - libellés des deux montants de l'en-tête (« Total TTC », « Reste dû ») ;
  - proposition de relance pour les factures échues.
- **Test** : Vitest du filtre, et SQL de la vue de relances.
- **Fait** : le statut « En retard » est **calculé** (pièce validée, échéance dépassée,
  reste dû > 0, ni payée ni annulée) ; le filtre l'utilise et compte les pièces ; l'état
  vide dit « Aucune facture en retard » ; l'en-tête libelle ses deux montants
  (« Total TTC » / « Reste dû »). ⚠️ **La proposition de relance** (écran
  `/accounting/treatment/payment-reminders` vide) **reste ouverte** — elle demande la
  chaîne de relances, hors de ce correctif.

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

### B11 — ven-003 🔵 — `<div>` dans `<tbody>` (devis) — **✅ CORRIGÉ** (écran)
- **Correctif** : `QuotesPage`, remplacer l'enveloppe par un `<Fragment>` ou un `<tr>`.
- **Fait** : `QuotesPage` **et** `CreditNotesPage` (même motif, jamais relevé) passent
  leurs paires de lignes en `<Fragment>` : plus d'erreur React « `<div>` cannot be a child
  of `<tbody>` ». Le motif `PurchaseCreditNotesPage` (relevé par les journaux Vitest) reste
  à traiter avec les achats.

### B12 — pil-009 🔵 — valider une facture en un clic, sans confirmation ; échéance = date — **✅ CORRIGÉ** (écran)
- **Correctif** : `confirmSync` avant validation (action irréversible) ; échéance par défaut
  = date + conditions de paiement du client.
- **Fait** : « Valider » demande confirmation en nommant la pièce et ce qui est irréversible
  (numéro définitif + écriture) ; l'échéance proposée suit les conditions de paiement du
  client (premier nombre de `payment_terms`, 30 j par défaut) et se fige dès que
  l'utilisateur la saisit.

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

### C2 ter — avantages en nature : titres-restaurant et indemnité de transport hors du bulletin — **🔴 PROUVÉ, à corriger** (suite 321)
- **Comment ce défaut est sorti** : en portant la couverture des éléments
  variables du second moteur vers le moteur réel, avant de le supprimer. Quatre
  types (`bonus`, `meal_vouchers`, `transport_allowance`, `other_deductions`)
  n'étaient couverts que par le second moteur — qu'aucun écran n'appelait. Ils
  sont donc rejoués contre `calculate_payslip` (suite **321**).
- **Constat mesuré** : sur un brut de 2 500 €,
  * une **prime** de 500 € → brut 3 000,00 € ✅ (le moteur la traite) ;
  * une **autre déduction** de 120 € → net inférieur de 120,00 € ✅ ;
  * des **titres-restaurant** de 160 € → brut **2 500,00 €** au lieu de 2 660,00 € ❌ ;
  * une **indemnité de transport** de 75 € → brut **2 500,00 €** au lieu de 2 575,00 € ❌.
- **Nature du défaut** : un avantage en nature **est un salaire**. Sa valeur
  faciale entre dans le brut ; seule la part exonérée (la valeur du titre) échappe
  aux cotisations. Ici les deux montants **n'arrivent nulle part** : ni brut, ni
  cotisations, ni net. Un salarié qui a droit à des titres-restaurant ne les
  reçoit pas. Et la grille 2026 **n'a aucune ligne** pour ces deux postes — il
  manque le paramétrage, pas seulement la formule.
- **Pourquoi ce n'est pas corrigé ici** : la valeur faciale du titre-restaurant et
  le plafond d'exonération de l'indemnité de transport changent chaque année et
  doivent être **sourcés**. La 276 le fait explicitement (`[URSSAF-PSS]`,
  `[URSSAF-TAUX]`) ; écrire un taux de mémoire serait précisément le défaut que
  ce dépôt combat. Chantier à part, avec ses sources.
- **Suivi** : `321 T02`, `T03` et `T05` sont inscrits au registre des rouges
  attendus (`ci/expected_failures.sql`) avec leur motif : visibles en CI, sans
  la casser. Ils disparaîtront **avec leur correctif**, pas avant.

### C2 bis — le prorata d'entrée / sortie (manque trouvé en retirant le second moteur) — **✅ CORRIGÉ** (migration 320)
- **Comment ce manque est sorti** : l'inventaire du second moteur de paie
  (`src/lib/payroll.ts`, 509 lignes) face au moteur SQL a montré **une seule**
  capacité que le vrai moteur n'avait pas : le **prorata d'entrée ou de sortie**.
  Et comme aucun écran n'appelait le second moteur, la capacité était
  simplement perdue.
- **Constat mesuré** : brut 3 000 €, embauche le 30/09/2026 → brut **3 000,00 €**
  et net **2 244,40 €**. Un mois entier de salaire pour un jour de présence.
- **La règle retenue** (obligatoire, et celle de tous les produits du marché) :
  * rapport des **jours de présence dans le mois** au **nombre de jours du
    mois** — pas un trentième : février a 28 jours (URSSAF, Sage 100 §12,
    Odoo `hr.payslip`) ;
  * Code du travail, art. L1234-9 à L1234-13 ;
  * rapport arrondi à **6 décimales** (il n'a pas de fin), brut au **centime** ;
  * **ni le rappel, ni les heures supplémentaires, ni les remboursements** ne
    sont proratisés : ce ne sont pas des salaires dus au prorata du mois.
- **Test rouge avant** : `320_payroll_prorata_tests.sql` — **4 rouges / 2 verts**
  (les verts sont les non-régressions), **7/7** après.
- ⚠️ **Une donnée inventée, corrigée en même temps** : `employees.hire_date`
  portait `DEFAULT CURRENT_DATE`. Invisible jusqu'ici (le moteur ne lisait pas
  cette colonne), mais fausse — une date d'embauche est une donnée métier, pas
  un horodatage de saisie. Le prorata l'a rendu visible : les bulletins d'or de
  septembre 2026 sont tombés à 1 jour sur 30 (rouge mesuré sur **276** et
  **319**, avant correction). Défaut retiré (T07).
- **Reste ouvert, hors de ce commit** : les imports `122`, `153` et `158` font
  `COALESCE(… ->> 'hire_date', CURRENT_DATE)` — la même invention sur l'import
  de masse, qui fausse aussi les **droits acquis** (C5). Chantier à part.
- **Après** : `320_*_tests` **7/7** ; non-régression **276 6/6** (les trois
  bulletins d'or au centime), **319 6/6**, **243 5/5**, **228 7/7**, **311 7/7**,
  **181 7/7**, **212 9/9**, **247 7/7**, **256 8/8**, **265 10/10** ; suite 320
  câblée dans `.github/workflows/ci.yml`.

### C2 — rh-005 🟠 — simulateur de paie : autre moteur, nets faux — **✅ CORRIGÉ** (migration 319)
- **Constat (mesuré par la recette)** : 2 500 € brut → **1 798,53 €** de net au
  simulateur, contre **1 919,53 €** au moteur de la base (bulletin d'or de la
  276) — 121,00 € d'écart. Le chômage salarial y était compté, la CRDS absente,
  le net imposable confondu avec le net, aucun traitement cadre, et le total
  patronal ne correspondait pas à la somme des rubriques. La cause : l'écran
  avait son **propre moteur** TypeScript (`src/lib/payroll.ts`).
- **Doctrine W5** (« un seul moteur par grandeur ») : le simulateur **appelle**
  le moteur. La 319 crée `simulate_payslip(p_employee_id, p_gross, p_period)`,
  qui rend exactement le jsonb du calcul — et n'écrit rien.
- **Comment, sans réécrire 553 lignes de moteur** : le moteur de la 276 devient
  `payroll_compute_slip(…, p_gross_override, p_dry_run)` — **repris mot pour
  mot**, à quatre endroits près (nom, deux paramètres par défaut, salaire
  simulé qui prime, écritures derrière `IF NOT p_dry_run`) ; `calculate_payslip`
  garde sa signature **exacte** et devient l'appelant mince.
- **Écran** (`PayrollCalcPage`) : il appelle `simulatePayslip` et affiche ce que
  le moteur rend. Les champs **type de contrat, heures/semaine, heures sup,
  titres-restaurant, indemnité transport, taux de PAS ont disparu** : le moteur
  ne les prenait pas en entrée, ils n'influençaient rien et l'écran laissait
  croire le contraire. La **réduction générale** (jusqu'à 743 € au SMIC) est
  devenue une ligne affichée, avec son coefficient RGDU.
- **Test rouge avant** : `319_payslip_simulation_tests.sql` — **5 rouges**
  mesurés avant la migration (`simulate_payslip` inexistante ; T05 est un
  invariant, vert par nature). `single-engine.test.ts` — le scénario C2 est
  **rouge** avec l'ancien écran (mesuré en le remettant dans son état d'avant).
- **Après** : `319_*_tests` **6/6** ; `single-engine.test.ts` **6/6** ;
  non-régression **276 6/6** (les trois bulletins d'or au centime), **243 5/5**,
  **228 7/7**, **311 7/7**, **181 7/7**, **211 16/16**, **212 9/9**, **247 7/7**,
  **256 8/8**, **265 10/10** ; Vitest **1543/1543** ; `typecheck`/`oxlint`/
  i18n/`check-written-columns`/`check-unchecked-writes` verts ; suite 319 câblée
  dans `.github/workflows/ci.yml`.
- ⚠️ **Deux garde-fous ont vu une première version, et il a fallu les écouter** :
  * **243 T03** verrouille la signature publique de `calculate_payslip` (« une
    seule version, la légale »). Lui ajouter des paramètres déplaçait le
    verrou : d'où le noyau `payroll_compute_slip`, et `calculate_payslip`
    intacte. *Aucun test n'a été touché.*
  * **228 T06** refuse qu'une fonction de `public` soit exécutable par PUBLIC —
    or `CREATE OR REPLACE` **réinitialise l'ACL** : `calculate_payslip` redevenait
    exposée. La migration lui rend explicitement ses droits, et les deux
    nouvelles sont `REVOKE … FROM PUBLIC` + `GRANT`.
- **Ce que C2 ne fait pas** : `src/lib/payroll.ts` (509 lignes) reste en place
  parce que quatre fichiers de test l'utilisent encore ; **aucun écran ne
  l'appelle**. Le supprimer est un chantier à part. La capture
  `qa/screenshots/rh-005-after.png` n'a pas été prise (même limite que A4 et
  C1 : pas de navigateur ici).

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

### D1 — stk-012 🟠 — sortie de caisse d'un produit fini en 603/310 au lieu de 7135/355 — **✅ CORRIGÉ** (`d709bf8`, migration 315)
- **Constat** : 355000 reste à 440 alors que le stock de C vaut 308 ; 310000 est diminué à tort de 132.
- **Cause établie** : `resolve_stock_account` / `resolve_variation_account` lisent l'**article** et sa
  famille — et l'article porte `stock_account_code = '310000'` (valeur par défaut de la fiche).
  Juste pour une réception, faux pour un produit fabriqué, dont le compte de stock est décidé par
  la production (355000/713500) : `products.type` ne distingue ni produit fini ni marchandise.
- **Correctif** : une **sortie** prend les comptes de l'**entrée qui a nourri la couche consommée**.
  Le lien vers l'écriture d'entrée est exact, jamais deviné : `piece_number = 'STK-' || mouvement`
  d'un côté, `reference = 'JE-OF-' || OF` pour la production (302), qui écrit sa propre écriture.
  L'article et sa famille restent le repli (entrées, couches d'avant la 241). Le déclencheur passe
  avant la consommation des couches (ordre alphabétique), donc la couche à consommer est connue.
  Tous les chemins de sortie en bénéficient : BL, caisse, inventaire, production.
- **Test rouge avant** : `315_*_tests` T01 ❌ (D 603000 88 / C 310000 88, 1 ligne en 310000) ;
  T02 ✅ (non-régression marchandise). Après : 6/6 verts dans la famille 173/230/242/251/253/254/281.
  Preuve sur la donnée de recette (transaction annulée) : 713500 D 88 / 355000 C 88, 0 ligne en 310000.
- **Cas limite inscrit au registre** : si un article a des couches entrées à des comptes différents,
  la sortie suit la couche la plus ancienne (le CUMP ramène les coûts, pas les comptes).

### D2 — stk-005 🟠 — « Valoriser le stock » : fonction ambiguë, puis total faux — **✅ CORRIGÉ** (`d751071`, migration 316)
- **Cause établie** : deux surcharges de `calculate_stock_valuation`
  (`(p_method, p_warehouse_id)` et `(p_tenant_id, p_method, p_date)`), donc PostgREST rend 300 —
  et, avec un dépôt, la première calcule quantité × prix de la **fiche**, d'où la ligne unique
  « — | 0 | 0,00 € | 5 600,00 € » (l'écran ne recevait pas un tableau, il en faisait une ligne).
- **Correctif** : **une** fonction `calculate_stock_valuation(p_method, p_warehouse_id, p_date)`,
  adossée à `calculate_stock_valuation_at_date` (111) qui lit les **couches** — la vérité unique
  depuis la 254 — et rejoue les mouvements. Une ligne par article et par dépôt, articles soldés
  exclus ; les deux surcharges sont supprimées (règle W10 : une fonction, un nom).
- **Test rouge avant** : `316_*_tests` T01/T02/T03 ❌ — l'appel à trois arguments partait dans la
  surcharge `(uuid, text, date)` (« invalid input syntax for type uuid: "cump" »), 2 fonctions
  trouvées. Après : 1 fonction, 2 lignes, total = somme des couches.
- **Preuve sur la donnée de recette** : 6 lignes, **8 636,00 €** = Σ couches — l'ancre que la
  recette donne elle-même (« = écran Quantités en stock, = couches de valorisation »).
- **Note d'attendu** : le « A1 150 × 12 = 1 800 (CUMP) / FIFO 1 900 » de ce plan était
  approximatif — le CUMP de 50 @ 10 + 100 @ 14 vaut 12,666… (1 900/150) ; les couches et la
  fonction disent 1 900, et c'est l'égalité avec les couches que le test vérifie.

### D3 — stk-010 🟠 — OF terminé affiché à 0,00 € et « Aucune consommation »
- **Correctif écran** : lire `manufacturing_orders.cost_material/cost_total/unit_cost/cost_variance`
  et les mouvements `reference_type='manufacturing_order'`, au lieu de recalculer depuis
  `bom_lines.unit_cost`. Afficher l'écart de coût.
- **Test** : Vitest de la page OF (données simulées), 440 / 44 / écart.

### D4 — stk-013 🟠 — statistiques de caisse vides (période décalée d'un jour, borne de fin = début) — **✅ CORRIGÉ** (`bf49b03`)
- **Cause établie** : deux fautes dans la même chaîne — la borne basse venait de
  `new Date().toISOString().split('T')[0]`, qui lit le jour **UTC** de minuit local (minuit à
  Djibouti = 21 h la veille en UTC), et `getPosTickets` posait `lt(date, date + 'T23:59:59')`,
  une fin le **même jour** : la période était vide par construction.
- **Correctif** : `src/lib/dateRange.ts` — `localDayRange(period)` rend `[from, to)` en ISO, fin
  **exclue** (lendemain à minuit local), et `localDateString()` rend le jour **local** d'un instant
  (le remplaçant du motif fautif pour une date métier) ; `getPosTickets` prend `{ from, to }` et
  pose `gte(from) + lt(to)` ; la date de la facture d'un ticket passe aussi à `localDateString()`.
- **Test rouge avant** : `dateRange.test.ts` + `d4-pos-tickets-range.test.ts` — le second a
  révélé un **trou du harnais** (`src/test/setup.ts` n'avait pas `lt` : l'ancien code appelait
  cette méthode sans qu'aucun test unitaire n'y passe). Après : 6/6 verts, Vitest 1 522/1 522.
- **Preuve écran (donnée de recette)** : les requêtes portent deux bornes distinctes en heure
  locale — « Aujourd'hui » `gte=2026-09-29T21:00Z&lt=2026-09-30T21:00Z` (24 h locales),
  « Ce mois » `gte=2026-08-31T21:00Z` ; « Cette semaine » et « Ce mois » affichent **216,00 € de
  CA TTC et 36,00 € de TVA** (l'attendu de la recette). « Aujourd'hui » est vide à juste titre :
  la vérification du 30/09 ne peut pas contenir les tickets du 29/09.
- **Reste ouvert, inscrit au registre** : la chasse globale des **126** autres
  `toISOString().split('T')[0]` (chacun demande sa vérification) et la règle statique
  correspondante du § 15.

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

### E1 — stk-015 🟠 / ach-001 🟠 — fenêtre plus haute que l'écran, sans défilement — **✅ CORRIGÉ** (`e179882`)
- **Cause établie** (l'hypothèse « le `Modal` commun n'a ni hauteur maximale ni défilement »
  était **fausse** : le `Modal` commun, lui, était déjà borné) : ces deux fenêtres étaient
  bâties **à la main**, sur le motif `fixed inset-0` + carte sans `max-height` ni
  `overflow-y` — motif présent **152 fois dans 115 fichiers**. Aucun ancêtre ne défilait :
  « Créer » finissait à 840 px pour un écran de 720, et le clic était impossible.
- **Correctif** :
  - `components/ui` `Modal` : `max-h-[calc(100vh-2rem)]`, en-tête et pied fixes, corps
    défilant, et un emplacement `footer` (optionnel — aucun appelant existant n'est touché) ;
  - `SuppliersPage` (« Nouveau fournisseur ») et `FixedAssetsPage` (« Nouvelle
    immobilisation ») passent à ce `Modal`, et gagnent le piège à focus, Échap et le
    verrou de défilement.
- **Test rouge avant** : `e2e/windows-fit.spec.ts` — à 1280×720 comme à 375×812, le bouton de
  validation doit être **dans** l'écran et répondre au clic. Rouge avant (mesuré : 840 px pour
  720), vert après (**4/4** ; 652–688 px). Deux pièges de mesure corrigés au passage : la
  langue et le guide d'accueil à poser au départ, et surtout `reuseExistingServer` qui
  réutilisait le serveur d'un **autre arbre de travail** (mesuré : le port 5174 appartenait au
  checkout principal, qui servait d'autres sources) → `PW_BASE_URL` dans
  `playwright.config.ts` (le défaut de CI reste 5174).
- **Preuves** : captures `ach-001-after.png`, `stk-015-after.png`.
- **Reste ouvert, inscrit au registre** : les **~150 autres fenêtres** bâties sur le même
  motif ad hoc (mesuré : 152 occurrences dans 115 fichiers) ne sont pas balayées ; seule la
  garde Playwright couvre les deux fenêtres de la recette. Un balayage outillé (règle à
  baseline, sur le modèle de `check-written-columns`) est à prévoir avant la recette finale.

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

## 12 bis. Constats hors fiche, apparus en corrigeant les contrôles

* Ces points ne sont pas dans le registre de la recette : ils sont sortis des
  **contrôles eux-mêmes**, le 30/09/2026, et sont à instruire.
* **Le contrôle de type n'en était pas un** (corrigé, `7e2968b`). Le
  `tsconfig.json` racine est une configuration « solution » (`files: []`), donc
  `npx tsc --noEmit` ne compilait rien et sortait 0 — y compris sur le lot A4,
  commité avec deux erreurs de type (corrigées au lot C2). Le « Type check » de
  `.github/workflows/deploy.yml` ne vérifiait rien non plus, et quatre documents
  prescrivaient la commande aux agents. **Le contrôle réel est
  `npm run typecheck` (`tsc -b --noEmit`).**
* **`db-integration.test.ts` n'a jamais tourné nulle part** (le job CI qui lance
  `vitest run` n'a pas de `DATABASE_URL` ; celui qui en a une ne lance que du
  `psql`). Le SSL y était imposé, et la base locale Supabase le refuse. Une
  fois rendu exécutable, il a donné **2 rouges sur 13** — tous deux instruits le
  30/09, et **tous deux des assertions fausses, pas des défauts** :
  * *« aucune policy `USING (true)` »* : il y en a 5, mais toutes sur des
    **référentiels globaux** (`banks`, `chart_account_templates`,
    `sql_migrations_tracker`, `v_tenant_id`, `webhook_event_catalog`) — le modèle
    voulu depuis la 270 (lignes globales lisibles, non écritables ; contrôle CI
    `check_global_rows_writable`). L'assertion les comptait toutes : elle était
    fausse. **Réécrite** sur les tables de société. Aucune fuite.
  * *« trigger `check_journal_entry_balance` »* : **ce nom n'a jamais existé**.
    Le garde-fou réel est une famille de quatre, et il **mord** — mesuré à la
    main sur la base de recette :
    - une pièce en brouillon peut être déséquilibrée : **voulu**, sinon la saisie
      ligne à ligne serait impossible ;
    - **la pose d'une pièce déséquilibrée est refusée**, avec un motif nommé :
      « Écriture … non équilibrée : débit 100.00 ≠ crédit 0.00 »
      (`check_journal_entry_balance_on_post`) ;
    - **une pièce posée est immuable** : ni ligne ajoutée, ni ligne modifiée
      (« validée (posted) — immuable ») ;
    - le comportement est déjà couvert par `273_journal_entry_validation` T02,
      câblé en CI. **Assertion réécrite** sur les 4 vrais déclencheurs.
  * **Conclusion : l'équilibre ET l'opposabilité sont garantis par la base**, pas
    par l'application. **Aucun défaut.** `db-integration.test.ts` est désormais
    **13/13, sans un seul test neutralisé**.
* **Le harnais de `verify.sh` accusait à tort** : il cherchait « failed » dans
  toute la sortie de vitest, alors que des tests qui vérifient la gestion
  d'erreur journalisent volontairement « … failed ». Il juge désormais sur le
  code de sortie (doctrine déjà appliquée en `5940f57`).
* **Sept suites SQL rouges sur la base de recette** (`users_email_partial_key` :
  220, 232, 270, 271, 273, 274, 275) : le harnais recrée le même
  `tenant_users.email` à chaque exécution. Pollution de la recette, pas une
  régression — comme les 250 T06/T11 déjà signalés.

---

## 13. Ordonnancement et charges

| Ordre | Lot | Contenu | Charge | Dépend de |
|---|---|---|---|---|
| 1 | — | Préalables d'environnement (§ 3) | 0,25 j | — |
| 2 | **C1** ✅ | Bulletins de paie (rh-006) | 1,5 j | — |
| 3 | **A1–A3** ✅ | Plan tiers, balance âgée, solde dû | 1,5 j | — |
| 4 | **B10** ✅ | Boucle du contrôle crédit | 0,25 j | — |
| 5 | **B1** ✅ | Sortie de stock du BL | 0,5 j | — |
| 6 | **E1** ✅ | Fenêtres qui débordent (Modal) | 0,5 j | — |
| 7 | **D1, D2, D4** ✅ | Comptes de sortie, valorisation, dates UTC | 1,5 j | — |
| 8 | **H1** | Tableau de bord sur le grand livre | 0,5 j | — |
| 9 | **B2–B9, B11, B12** ✅ (reste **B3**) | Reste des ventes | 3 j (livrés) | — |
| 9b | B3 (ven-009) | Client UE : autoliquidation, mention, Factur-X AE | 0,5 j | **débloqué** (A4 livré) |
| 10 | **C2** ✅, C3–C6 | Reste de la paie | 2,5 j (C2 livré) | C1 |
| 11 | D3, D5–D12 | Reste du stock et de la caisse | 2 j | D1 |
| 12 | F1–F7 | Comptabilité | 1,5 j | — |
| 13 | G1–G5 | Analytique, projets | 1,5 j | B2 |
| 14 | **A4** ✅, A5–A6 | Fiches tiers | 1 j (A4 livré) | — |
| 15 | E2 + § 12 | Recette finale, contrôle croisé, clôture, rapport | 3 j | tout |
| | | **Total** | **≈ 22 j** | |

Parallélisable : les lots **A**, **C** et **D** touchent des fichiers distincts. Deux sessions
peuvent les mener en même temps si elles **constatent** leurs numéros de migration au commit
et commitent par index privé (`GIT_INDEX_FILE`).

---

## 14. Décisions à prendre (bloquent un correctif)

| ID | Question | Options | Recommandation | Décision |
|---|---|---|---|---|
| **D-QA-1** | Une facture directe d'article stocké, sans BL, sort-elle le stock ? | (a) oui à la validation ; (b) non, BL obligatoire pour un bien | (a) avec garde anti-double sortie si un BL existe | **TRANCHÉE (30/09, option a)** — 317 : sortie à la validation, une fois par facture, jamais pour une ligne née d'un BL ; sortie impossible = validation refusée avec un message nommé |
| **D-QA-2** | Facture datée avant la dernière numérotée | (a) refus ; (b) avertissement | (a) : chronologie exigée pour la piste d'audit fiable | **TRANCHÉE (30/09, option a)** — 317 : refus, message nommé ; `180` E12/E13 alignés |
| **D-QA-3** | Articles existants à prix négatif | (a) remis à 0 ; (b) désactivés | (b) : ne pas inventer de prix | à prendre (lot D) |
| **D-QA-4** | Contrepartie comptable du stock initial | (a) AN 3x/890000 ; (b) avertissement seulement | (a), cohérent avec la banque (277) | à prendre (lot D) |
| **D-QA-5** | Transfert entre dépôts | (a) créer l'écran ; (b) hors périmètre | (a) : fonction de base d'un multi-dépôt | à prendre (lot D) |
| **D-4** (existante) | `generate-pdf` | rebrancher ou PDF navigateur | PDF navigateur (B8), sans service externe | **TRANCHÉE de fait (30/09)** — B8 livre le PDF navigateur, sans service |
| **D-G** (existante) | Grille paie 276, arrêt maladie, carence | signature de l'expert-comptable | inchangé : ne pas déployer avant | inchangée |

---

## 15. Gardes-fous à ajouter (pour que ces défauts ne reviennent pas)

| Garde | Ce qu'elle aurait vu |
|---|---|
| `check-written-columns` étendu aux **objets construits puis passés** à `.insert()` (suivi de la variable) | pil-005 (colonne fantôme restée verte) |
| Contrôle « **une fonction, un nom** » : aucune surcharge exposée à PostgREST — **✅ fait** (D2 : les deux surcharges de `calculate_stock_valuation` supprimées, et le test T02 compte les fonctions) | stk-005 |
| Contrôle statique « **pas de `toISOString()` pour une date métier** » — **reste à faire** : l'utilitaire `localDateString` existe (D4) mais le motif tombe encore **126** fois ; règle à baseline comme `check-written-columns` | stk-013, rh-007 |
| Test Playwright « **toutes les fenêtres tiennent à 1280×720** » — **✅ fait pour les deux fenêtres de la recette** (`e2e/windows-fit.spec.ts`, à 1280×720 et 375×812) ; le balayage des ~150 autres fenêtres bâties sur le motif ad hoc reste à outiller (règle à baseline) | ach-001, stk-015 |
| Test Playwright « **balayage des routes** » (0 erreur console, 0 requête 4xx/5xx, 0 clé i18n brute) | pil-002, pil-003, ven-003 |
| Détecteur de **boucle de requêtes** en test (≤ N appels par montage) — **✅ fait** : budget de requêtes dans `CreditControlPage.test.tsx` (la source se gèle au-delà du plafond) + règle statique `15-no-render-body-call.rule` | ven-016 |
| Contrôle « **aucune colonne dénormalisée lue sans être tenue** » (balance, credit_used, soldes du plan) — **✅ fait pour `delivery_status` / `fully_delivered`** : règle statique `16-no-client-delivery-status.rule` (B1) | ven-017, cpt-001 |
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
| ven-004 | 🟠 | BL avec service bloqué | B1 | ✅ 9ef26c8 (314) |
| ven-005 | 🔴 | BL livré sans sortie | B1 | ✅ 9ef26c8 (314) |
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
| ach-001 | 🟠 | fenêtre fournisseur déborde | E1 | ✅ e179882 |
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
| stk-005 | 🟠 | valorisation ambiguë et fausse | D2 | ✅ d751071 (316) |
| stk-006 | 🟡 | inventaire trompeur | D9 | ouvert |
| stk-007 | 🟡 | écarts en JSON brut | D9 | ouvert |
| stk-008 | 🟡 | nomenclature sans article | D10 | ouvert |
| stk-009 | 🟡 | coût nomenclature à 0 | D10 | ouvert |
| stk-010 | 🟠 | OF affiché à 0 | D3 | ouvert |
| stk-011 | 🔵 | numéro d'OF consommé | D11 | ouvert |
| stk-012 | 🟠 | sortie caisse en 603/310 | D1 | ✅ d709bf8 (315) |
| stk-013 | 🟠 | stats caisse vides | D4 | ✅ bf49b03 |
| stk-014 | 🟠 | pas d'annulation de ticket | D5 | ouvert |
| stk-015 | 🟠 | fenêtre immobilisation déborde | E1 | ✅ e179882 |
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
