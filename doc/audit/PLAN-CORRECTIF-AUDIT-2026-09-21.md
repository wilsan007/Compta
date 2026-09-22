# Plan correctif — audit strict du 21 septembre 2026

> **Version** 1.1 — 21 septembre 2026 (vague V1 exécutée, voir [§ 6](#6-journal-dexécution))
> **Branche** `commercial-hr-paie`, commit `b64dda2`
> **Source** audit strict par exécution du 21/09 : base PostgreSQL neuve (`audit_0921`), 167 migrations rejouées, 45 scénarios comptables écrits pour l'audit (16 réussis, 29 échoués), PostgREST réel, build
> **Note de départ** 3,9 / 10 — **note cible** 9,5 / 10 sur chaque module
> **Articulation** ce plan ne remplace ni le [cahier correctif](CAHIER-DES-CHARGES-CORRECTIF.md) ni le [plan de perfection](PLAN-PERFECTION-9.5.md). Il traite les défauts *prouvés à l'exécution* le 21/09, reprend les points encore ouverts du [suivi](SUIVI-CAHIER-CORRECTIF.md) et renvoie au [cahier de localisation](../localisation/CAHIER-DES-CHARGES-LOCALISATION.md) pour Djibouti.

---

## Sommaire

- [0. Règles du plan](#0-règles-du-plan)
- [1. Rectificatif de l'audit du 21/09](#1-rectificatif-de-laudit-du-2109)
- [2. Vue d'ensemble](#2-vue-densemble)
- [LOT A — Filet de tests rouges](#lot-a--filet-de-tests-rouges)
- [LOT B — Inscription et mise en service d'une société](#lot-b--inscription-et-mise-en-service-dune-société)
- [LOT C — Noyau de saisie comptable](#lot-c--noyau-de-saisie-comptable)
- [LOT D — Clôture et états financiers](#lot-d--clôture-et-états-financiers)
- [LOT E — Gestion commerciale → comptabilité](#lot-e--gestion-commerciale--comptabilité)
- [LOT F — Paie → comptabilité](#lot-f--paie--comptabilité)
- [LOT G — Achats, trésorerie, stock, production](#lot-g--achats-trésorerie-stock-production)
- [LOT H — Sécurité](#lot-h--sécurité)
- [LOT I — Ergonomie et i18n](#lot-i--ergonomie-et-i18n)
- [LOT J — Qualité, CI et preuve de bout en bout](#lot-j--qualité-ci-et-preuve-de-bout-en-bout)
- [LOT K — Localisation Djibouti](#lot-k--localisation-djibouti)
- [3. Trajectoire des notes](#3-trajectoire-des-notes)
- [4. Séquencement et effort](#4-séquencement-et-effort)
- [5. Décisions qui vous reviennent](#5-décisions-qui-vous-reviennent)
- [6. Journal d'exécution](#6-journal-dexécution)
- [7. Recette finale](#7-recette-finale)

---

## 0. Règles du plan

### 0.1 Ce que « 9,5 » veut dire ici

Même barème que le [plan de perfection](PLAN-PERFECTION-9.5.md#01-ce-que-signifie--95-). Un module n'atteint 9,5 que si les quatre conditions sont réunies :

| # | Condition |
|---|---|
| 1 | Le mécanisme fonctionne comme chez le leader du marché (Sage 100, Odoo), pas seulement l'écran |
| 2 | Aucun défaut de calcul connu, y compris sur les cas limites |
| 3 | Un test automatisé exécuté en CI couvre le mécanisme, **et on l'a vu échouer sur le code défectueux** |
| 4 | Il tient la charge d'un dossier réel : 3 exercices, 100 000 écritures |

### 0.2 Protocole obligatoire pour chaque correctif

Le projet a déjà connu cinq garde-fous faussement verts. Chaque action `AUD-xx` suit donc cet ordre, sans exception :

1. **Rouge** — le scénario du lot A qui prouve le défaut échoue en CI.
2. **Correctif** — nouvelle migration numérotée (prochain numéro libre après V1 : **187** ; vérifier `ls sql | sort -n | tail` avant de numéroter, d'autres sessions écrivent dans ce dépôt).
3. **Vert** — le même scénario passe, sans avoir été modifié.
4. **Preuve** — ligne ajoutée au [suivi](SUIVI-CAHIER-CORRECTIF.md) avec la commande exécutée et le commit.

Un correctif sans scénario rouge préalable n'est pas accepté.

### 0.3 Trois choses que le code seul ne peut pas apporter

- **Conformité réglementaire djiboutienne** : textes officiels, validation par un expert-comptable référent, pilote client (lot K).
- **Exécution des tests e2e** : impossible sur ce poste (Chromium 1228 non téléchargeable) ; elle se fait en CI (lot J).
- **Arbitrages produit** listés en [section 5](#5-décisions-qui-vous-reviennent).

---

## 1. Rectificatif de l'audit du 21/09

L'audit indiquait qu'une nouvelle société démarre avec un plan comptable vide « parce qu'aucun plan n'est semé ». **La cause était mal identifiée, et la réalité est plus grave.**

- `bootstrap_tenant` (`03_seed_chart_template.sql`) sème bien le plan comptable, les journaux, l'exercice et les paramètres société.
- Mais il insère ensuite les devises EUR, USD et GBP. Or la table `currencies` porte **deux** contraintes d'unicité : `(tenant_id, code)` et **`UNIQUE (code)`** globale. Des lignes EUR/USD/GBP partagées existent déjà (`tenant_id` NULL, migration 39). L'insertion échoue donc **pour toute société**.
- `create_tenant_for_current_user` capture l'erreur (`RAISE NOTICE 'bootstrap_tenant skipped'`) et **répond succès**. Toute l'initialisation est annulée.

**Reproduit le 21/09** par l'appel réel `create_tenant_for_current_user` : `{"success": true}`, puis **0 compte, 0 journal, 0 exercice, 0 paramètre société**.

Conséquence : sur la base rejouée, aucune société créée par l'inscription ne peut rien comptabiliser, puisque `get_next_piece_number` exige un journal. **À confirmer en premier sur le projet cloud** (action `AUD-B00`).

---

## 2. Vue d'ensemble

| Lot | Objet | Actions | Effort | Dépend de |
|---|---|---:|---:|---|
| A | Filet de tests rouges | 4 | 2 j | — |
| B | Inscription et mise en service | 5 | 1,5 j | A |
| C | Noyau de saisie comptable | 11 | 4 j | A, B |
| D | Clôture et états financiers | 9 | 6 j | C |
| E | Gestion commerciale → comptabilité | 11 | 8 j | C |
| F | Paie → comptabilité | 4 | 3 j | C |
| G | Achats, trésorerie, stock, production | 10 | 8 j | C |
| H | Sécurité | 7 | 3 j + vos décisions | — |
| I | Ergonomie et i18n | 5 | 4 j | — |
| J | Qualité, CI, preuve de bout en bout | 7 | 5 j | A à G |
| **Sous-total code** | | **73** | **≈ 44,5 j** | |
| K | Localisation Djibouti (cahier LOC) | 99 exigences | ≈ 74 j + textes + pilote | C, D, E, F |

---

## LOT A — Filet de tests rouges

Objectif : toutes les failles prouvées le 21/09 deviennent des tests CI **avant** toute correction.

### `AUD-A01` — Verser les scénarios d'audit dans le dépôt

Les quatre scripts de l'audit (`audit_compta.sql`, `audit_extra.sql`, `audit_reports.sql`, `audit_pay.sql`) deviennent :

| Fichier | Contenu |
|---|---|
| `sql/178_accounting_kernel_tests.sql` | A01–A07, B01–B04, C01–C03 (saisie, périodes, numérotation) |
| `sql/179_closing_and_statements_tests.sql` | D01–D09, R01–R04 (clôture, balance, résultat, bilan) |
| `sql/180_sales_to_ledger_tests.sql` | E01–E08 (facture, devis, avoir, encaissement) |
| `sql/181_payroll_to_ledger_tests.sql` | P01–P02 (écriture de paie) |
| `sql/182_signup_provisioning_tests.sql` | création de société par l'appel réel (section 1) |

Chaque scénario utilise le motif du lot 175 : un tenant par scénario, `RAISE EXCEPTION` sur échec, et un compteur final qui **échoue si aucune assertion n'a été évaluée**.

### `AUD-A02` — Registre des échecs attendus

Ajouter `sql/ci/expected_failures.sql` (une instruction par défaut, pour qu'on puisse en supprimer une sans casser le fichier), qui liste les identifiants encore rouges (ex. `D01`). Le contrôle de fin de fichier `_audit_assert` :
- **échoue** si un test hors registre échoue (régression) ;
- **échoue** si un test du registre **passe**, ce qui oblige à le retirer du registre dans le commit du correctif.

Ainsi la CI reste verte pendant le chantier sans masquer quoi que ce soit, et le registre mesure l'avancement.

### `AUD-A03` — Brancher les cinq fichiers dans `db-integration`

Une étape par fichier dans `.github/workflows/ci.yml`, sur le modèle des étapes 170 à 177.

### `AUD-A04` — Exécuter les tests en rôle `authenticated`

Aujourd'hui, les scénarios tournent en superutilisateur, qui contourne la RLS. Chaque fichier doit passer en `SET ROLE authenticated` après la mise en place, comme F01, pour que les tests reproduisent les droits réels d'un utilisateur.

**Recette du lot A** : 29 identifiants au registre, la CI verte, et un commit de démonstration où retirer un identifiant du registre fait passer la CI au rouge.

---

## LOT B — Inscription et mise en service d'une société

| Réf | Défaut prouvé | Correctif | Fichier |
|---|---|---|---|
| `AUD-B00` | À vérifier sur le cloud | Lancer `create_tenant_for_current_user` sur une société de test du projet `ndtaedcgwnaopopugiql`, puis compter comptes, journaux et exercices | — |
| `AUD-B01` | `UNIQUE (code)` global sur `currencies` bloque tout bootstrap | Supprimer `currencies_code_unique` ; garder `(tenant_id, code)` ; index unique partiel `(code) WHERE tenant_id IS NULL` pour les devises de référence | migration 183 |
| `AUD-B05` | *Trouvé le 21/09 pendant V1* — l'écran d'inscription (`misc.ts:createTenantForUser`) insère directement dans `tenants`, qui n'a **aucune politique INSERT** : refus RLS systématique | L'écran passe par la RPC `create_tenant_for_current_user` | `misc.ts` |
| `AUD-B02` | L'erreur de bootstrap est avalée et l'inscription répond succès | Retirer le `EXCEPTION WHEN OTHERS … RAISE NOTICE` autour de `bootstrap_tenant` : un bootstrap en échec doit faire échouer l'inscription | `create_tenant_for_current_user` |
| `AUD-B03` | Pays et devise saisis à l'inscription ignorés (EUR, France) | Passer `p_data->>'country'` et `p_data->>'currency'` à `bootstrap_tenant` ; refuser un pays sans pack publié (lien avec K) | `03_seed_chart_template.sql` → migration 183 |
| `AUD-B04` | Aucun contrôle après l'inscription | Fonction `assert_tenant_ready(tenant)` : plan non vide, journaux VT/AC/BQ/OD/AN présents, exercice ouvert, paramètres société présents, comptes utilisés par les écritures automatiques présents dans le plan | migration 183 + `182_…_tests.sql` |

**Recette** : l'inscription réelle crée une société qui passe `assert_tenant_ready`, et une inscription avec bootstrap volontairement cassé renvoie `success: false`.

---

## LOT C — Noyau de saisie comptable

| Réf | Scénario rouge | Défaut prouvé | Correctif |
|---|---|---|---|
| `AUD-C01` | A02, A03 | Tolérance d'équilibre de 0,01 : 50 écritures à 1 centime d'écart faussent la balance de 0,50 | `debit`/`credit` en `numeric(18,2)` (arrondi à la saisie, pas au contrôle) ; égalité **stricte** dans `assert_journal_entries_balanced` et `check_journal_entry_balance_on_post` (158) et dans `close_fiscal_year` |
| `AUD-C02` | A04 | Un en-tête peut être inséré directement en `posted`, sans ligne | Trigger `BEFORE INSERT` sur `journal_entries` : `status` doit valoir `draft` à l'insertion ; `total_debit`/`total_credit` calculés, jamais saisis |
| `AUD-C03` | A05 | Ligne débit **et** crédit, ou ligne 0/0 acceptées | `CHECK ((debit = 0) <> (credit = 0))` sur `journal_lines` ; nettoyer d'abord les lignes 0/0 générées par les triggers (TVA exonérée → ne pas créer la ligne) |
| `AUD-C04` | A06 | Compte absent du plan accepté (`ZZTOP`) | Trigger `BEFORE INSERT/UPDATE` : le compte existe dans `chart_accounts` du tenant, n'est pas `deprecated`, et n'a pas de sous-comptes (feuille). Message qui nomme le compte |
| `AUD-C05` | B02 | Saisie acceptée dans un exercice clos sans découpage en périodes | `check_fiscal_period_open` contrôle aussi `fiscal_years.status IN ('closed','locked')` |
| `AUD-C06` | B03 | Écriture datée de 1990 acceptée | La date doit appartenir à un exercice existant du tenant |
| `AUD-C07` | B04b | Période close contournée sans contexte tenant | Lire `NEW.tenant_id` et non `current_tenant_id()` dans `check_fiscal_period_open` (76). Seule exception légitime : la clôture elle-même (voir `AUD-D03`) |
| `AUD-C08` | — (grille vide) | `post_journal_entry` ignore `fiscal_period_id` ; les 145 écritures de la base l'ont à NULL | Trigger `BEFORE INSERT/UPDATE OF date` qui renseigne `fiscal_period_id` depuis la date ; reprise des écritures existantes dans la migration |
| `AUD-C09` | C02 | Deux écritures au même numéro si `journal_code` est NULL | `journal_code NOT NULL` + clé étrangère vers `journals(tenant_id, code)` ; reprise : affecter `OD` aux écritures sans journal |
| `AUD-C10` | C03 | `post_journal_entry` avec `status: posted` échoue toujours (lignes refusées après en-tête validé) | La RPC insère toujours en `draft`, puis valide après les lignes si `posted` est demandé, dans la même transaction |
| `AUD-C11` | — | Numéro définitif attribué à la saisie (`OD-0001`), jamais remis à zéro | Numéro provisoire en brouillard ; **numéro définitif, continu et chronologique par journal et par exercice attribué à la validation** (motif Sage : brouillard puis validation). Test : 3 validations dont une échoue → numéros 1 et 2, sans trou |

**Recette du lot C** : A02–A06, B02–B04, C02, C03 et un nouveau test de numérotation sans trou sont verts, et les 17 tests de `102_trigger_tests.sql` restent verts.

---

## LOT D — Clôture et états financiers

C'est le lot qui conditionne la note de la page Comptabilité. `close_fiscal_year` (153) est **réécrite**, pas rapiécée.

| Réf | Scénario rouge | Défaut prouvé | Correctif |
|---|---|---|---|
| `AUD-D01` | D07, D08 | Résultat = produits **+** charges (1 600 au lieu de 400) | Résultat = Σ(crédit − débit) sur toutes les lignes des classes 6 et 7, en un seul signe |
| `AUD-D02` | D07, D09 | Écriture de regroupement dans le même sens que les soldes (D 600 ≠ C 2 600) | Chaque compte 6/7 est soldé en **sens inverse** de son solde ; contrepartie 120 (bénéfice) ou 129 (perte) |
| `AUD-D03` | D01 | Exige toutes les périodes closes, puis écrit le 31/12 dans une période close → refus | Ordre : (1) contrôles, (2) écritures de clôture et d'à-nouveaux sous un drapeau de transaction `app.closing_in_progress` que `check_fiscal_period_open` reconnaît pour **cette fonction uniquement**, (3) verrouillage des périodes et de l'exercice. Journal dédié `CL` |
| `AUD-D04` | D04 | Résultat (120/129) exclu des à-nouveaux → à-nouveaux déséquilibrés | À-nouveaux sur **tous** les comptes de bilan, y compris 120/129 ; l'affectation du résultat (report à nouveau, réserves, dividendes) devient une étape séparée `allocate_result(fy, jsonb)` |
| `AUD-D05` | D06 | Cumul depuis l'origine (`je.date <= end_date`) → double comptage après deux clôtures | Base des à-nouveaux = lignes **de l'exercice clôturé seulement** (qui incluent ses propres à-nouveaux d'ouverture) |
| `AUD-D06` | D06 | Clôture impossible si résultat nul (écriture sans ligne) | Aucune écriture de regroupement quand il n'y a rien à solder ; la clôture continue |
| `AUD-D07` | R02 | `get_income_statement` filtre `type = 'revenue'`, valeur interdite par la base (`income`) → produits à 0 | Filtrer sur `'income'` **et** ne plus dépendre du type saisi : rôle de compte issu du pack (`resolve_account`, lot K) ; en attendant, classe 6/7 par préfixe. Supprimer la surcharge `close_fiscal_year(uuid)` (1 argument, 89) |
| `AUD-D08` | R03, R04 | Bilan : comptes hors plan écartés sans message, pas de ligne « résultat de l'exercice », jamais équilibré | (a) plus de filtre sur `chart_accounts` : un compte hors plan apparaît en rubrique « Comptes non classés », avec alerte ; (b) ligne « Résultat de l'exercice » calculée tant que l'exercice n'est pas clos ; (c) `BalanceSheetPage` : sélecteur d'exercice (aujourd'hui toujours le plus récent) et bandeau rouge si actif ≠ passif |
| `AUD-D10` | — | *Trouvé le 21/09 pendant V1* — l'écran des états financiers (`ReportsPage`, menu « Compte de résultat ») affichait des **chiffres écrits en dur** (85 600 de revenus, 78 400 de dépenses) ; ses raccourcis et son bouton « Exporter » ne faisaient rien | Écran branché sur `get_income_statement` et `get_income_statement_monthly` ; raccourcis navigables ; bouton inerte retiré |
| `AUD-D09` | — | SIG filtré par `fiscal_period_id` (toujours NULL) : vide dès qu'il existe des périodes, tout l'historique sinon, brouillards compris. Tableau de bord : « CA » = factures **payées**, **TTC** | `getSIGData` → RPC serveur par dates d'exercice, écritures validées seulement. CA = produits de classe 7 HT de l'exercice |

**Test de propriété (condition 2 et 4 du barème)** : `sql/1xx_accounting_property_tests.sql` (numéro à prendre au moment de l'écrire) génère 3 exercices et 100 000 écritures équilibrées aléatoires, puis vérifie :

1. balance : Σ débits = Σ crédits ;
2. compte de résultat = Σ classe 7 − Σ classe 6 ;
3. bilan : actif = passif + capitaux propres + résultat ;
4. après clôture : classes 6/7 à zéro, à-nouveaux = soldes de clôture compte par compte ;
5. deux clôtures successives : à-nouveaux N+2 = soldes de fin N+1, sans double comptage ;
6. durée de clôture sous 30 s à 100 000 écritures.

**Recette du lot D** : D01–D09 et R02–R04 verts, test de propriété vert, et une clôture réelle rejouée depuis l'écran `FiscalYearClosurePage` en e2e (lot J).

---

## LOT E — Gestion commerciale → comptabilité

| Réf | Scénario rouge | Défaut prouvé | Correctif |
|---|---|---|---|
| `AUD-E01` | E01 | `create_invoice_atomic` insère un `id` NULL (`jsonb_populate_record` + `SELECT *`) → **l'écran « Nouvelle facture » échoue toujours** | Liste de colonnes explicite, `id`/`status`/`created_at` laissés à leurs valeurs par défaut. Même correction, ou suppression, pour les 4 RPC inutilisées au motif identique : `create_quote_atomic`, `create_sales_order_atomic`, `create_delivery_note_atomic`, `create_purchase_invoice_atomic` (147) |
| `AUD-E02` | E05 | L'écran Factures ne crée que des factures vides (0 ligne, total 0), qu'on ne peut pas valider | Formulaire de lignes : article, quantité, prix, remise, code TVA ; totaux affichés et **recalculés côté serveur** |
| `AUD-E03` | — | En-tête et lignes peuvent diverger : le 411 prend `invoices.total`, les produits et la TVA prennent les lignes | Trigger qui recalcule `subtotal`, `vat_total`, `total` depuis les lignes ; la validation refuse une facture sans ligne |
| `AUD-E04` | — | Numéros de facture, avoir, devis, facture et avoir fournisseurs en `Math.random()` (6 écrans + `sales.ts:189`) | Numéro attribué **par le serveur à la validation** via `get_next_document_number` (146), qui existe déjà et que `core.ts` expose ; compteur remis à zéro par exercice ; champ numéro en lecture seule. Test : 1 000 validations concurrentes → 1 000 numéros consécutifs distincts |
| `AUD-E05` | E04 | `convertQuoteToInvoice` écrit `vat_total` au lieu de `vat_amount` → facture non validable (1 200 ≠ 1 000) ; conversion non atomique | RPC serveur `convert_quote_to_invoice(quote_id)` ; la TVA des lignes est calculée par le serveur à partir du code TVA |
| `AUD-E06` | — | Repli TVA mort : si la facture n'a pas de ligne, `v_ordre` vaut déjà 3, la TVA n'est jamais écrite | Disparaît avec `AUD-E03` (facture sans ligne interdite) ; test dédié |
| `AUD-E07` | E06 | **Avoirs clients : aucune écriture comptable** ; statuts `draft`/`applied` seulement | Statut `validated` ; trigger d'écriture inverse de la facture (D 7xx, D 4457x, C 411 avec auxiliaire) ; rattachement obligatoire à une facture ou au client ; lettrage automatique avec la facture d'origine |
| `AUD-E08` | E08 | Un client peut payer 500 de plus qu'une facture soldée ; l'excédent disparaît (`amount_due` = 0) | Refus du trop-perçu, ou, si vous le choisissez (section 5), excédent porté en avance client (4191) avec écriture dédiée |
| `AUD-E09` | E07 | Encaissement toujours en 512000, quel que soit le compte bancaire ou le mode (espèces, chèque) | Compte de trésorerie pris sur `bank_accounts.account_code` ou sur le journal du mode de règlement ; journal de banque propre à chaque compte |
| `AUD-E10` | — | Le règlement ne lettre pas la facture | Lettrage automatique facture ↔ règlement quand le montant solde la facture (réutilise `apply_lettrage`, 174) |
| `AUD-E11` | — | Numéros d'écriture `JE-INV-<n° facture>` hors séquence du journal | Numérotation du journal VT via `AUD-C11` ; le numéro de facture reste en `invoice_ref` |

**Recette du lot E** : E01–E08 verts, et un parcours e2e complet (devis → facture → validation → encaissement → lettrage → avoir) avec vérification des soldes 411, 7xx, 4457x et 512.

---

## LOT F — Paie → comptabilité

| Réf | Scénario rouge | Défaut prouvé | Correctif |
|---|---|---|---|
| `AUD-F01` | P01 | « Générer l'écriture de paie » envoie `status: posted` → toujours refusé | Couvert par `AUD-C10`, et remplacé par `AUD-F02` |
| `AUD-F02` | P02 | Écriture déséquilibrée : les cotisations salariales (brut − net) manquent au crédit (4 260 ≠ 3 600) ; pas de journal (`journal_type` n'est pas une colonne) | RPC serveur `post_payroll_journal(pay_run_id)` construite **depuis les rubriques des bulletins** : D 641 brut, D 645 charges patronales, C 421 net, C 43x cotisations salariales et patronales par organisme, C 447 impôt retenu. Journal PAIE. Idempotente |
| `AUD-F03` | — | Comptes 641/645/421/431 codés en dur côté front | Comptes par rubrique, issus du pack (lot K) ; en attendant, table de correspondance rubrique → compte par société |
| `AUD-F04` | — | Requête DSN cassée (`employees.gross_salary` inexistante, G17, en liste blanche) | Lire le brut depuis les bulletins de la période ; retirer G17 de `.embeds-allowlist.json` |

**Condition de 9,5 pour la paie** : le moteur de paie actuel est français (CSG, PMSS…). Pour votre marché cible, la note 9,5 exige la paie djiboutienne du lot K. Sans elle, la paie plafonne à **6,5**.

---

## LOT G — Achats, trésorerie, stock, production

Ces modules ont été moins audités le 21/09. Le lot commence donc par **mesurer**, puis corrige.

| Réf | Objet | Action |
|---|---|---|
| `AUD-G01` | Audit par exécution des achats | Scénarios rouges sur le modèle du lot E : facture fournisseur → écriture AC (401 auxiliaire, 6xx, 4456x multi-taux), avoir fournisseur, règlement, rapprochement 3 voies, trop-payé |
| `AUD-G02` | Numéros d'achat aléatoires | Traité par `AUD-E04` (`PurchaseInvoicesPage`, `PurchaseCreditNotesPage`) |
| `AUD-G03` | Relevés bancaires | `bankParsers.ts` (CAMT.053, MT940, OFX, CFONB) n'est branché à **aucun écran** ; le seul import passe par un modèle d'IA. Brancher les lecteurs dans `BankStatementImportPage`, avec des fichiers de test réels par format |
| `AUD-G04` | Rapprochement bancaire | Scénario rouge : relevé importé → rapprochement automatique → écart → état de rapprochement ; solde banque = solde 512 à la date |
| `AUD-G05` | Ajustements de stock (C14 du suivi) | Écriture valorisée sur la **variation** et non sur la quantité absolue ; test sur ajustement en baisse |
| `AUD-G06` | MRP cassé (G19, `purchase_order_lines.quantity_received`) | Corriger la requête ; retirer G19 de la liste blanche |
| `AUD-G07` | Articles (G18, `products.min_stock_level`) | Corriger la requête ; retirer G18 |
| `AUD-G08` | Budgets et droits journaux (G20, G21) | Corriger les jointures ; retirer G20 et G21. **Objectif : liste blanche vide** |
| `AUD-G09` | Point de vente | Scénario rouge : vente POS → sortie de stock + écriture + clôture de caisse ; contrôle NF525 de la chaîne |
| `AUD-G10` | Comptes codés en dur (310000, 603, 613, 713550 absent du plan) | Traité par le lot K (`resolve_account`) ; test en attendant : tout compte écrit par un trigger existe dans le plan semé par `bootstrap_tenant` |

**Recette du lot G** : scénarios G01, G04 et G09 verts, `npm run db:embeds` sans aucune tolérance, et les suites 170/173/175/177 toujours vertes.

---

## LOT H — Sécurité

| Réf | Objet | Action |
|---|---|---|
| `AUD-H01` | Période close contournable sans tenant | Traité par `AUD-C07` |
| `AUD-H02` | 7 tables non visibles par leur propre tenant (`105_rls_tests.sql` : 330/337) | Identifier les 7 tables ; décider pour chacune entre « politique manquante » (défaut fonctionnel) et « table de service » (documenter) ; faire échouer le test sur toute table non justifiée |
| `AUD-H03` | SSRF `generate-pdf` (I1 à I3 du suivi) | Appliquer le remède choisi, ou retirer la fonction du déploiement si vous confirmez qu'elle n'a aucun appelant |
| `AUD-H04` | Factures envoyées à OpenAI (I4) | Arbitrage juridique ; au minimum, consentement explicite par société et désactivation par défaut |
| `AUD-H05` | Clé `sb_secret_…` restée en clair (C8) | **Rotation à faire par vous** dans le tableau de bord Supabase |
| `AUD-H06` | Séparation des tâches | Test : avec `enforce_segregation`, l'auteur d'une écriture ne peut pas la valider |
| `AUD-H07` | Tests RLS en rôle réel | Traité par `AUD-A04` |

---

## LOT I — Ergonomie et i18n

| Réf | Objet | Action |
|---|---|---|
| `AUD-I01` | `confirmSync` = `window.confirm`, dans **81 fichiers** ; le vrai `confirmDialog` n'est utilisé nulle part (UX-03) | Migrer les 81 fichiers vers `useConfirm` ; supprimer `confirmSync` ; la règle CI interdit alors `confirmSync` comme elle interdit `window.confirm` |
| `AUD-I02` | Champs factices dans `ChartAccountsPage` (lignes 617–633 : nombre de lignes, saut de page, regroupement, cases cochées), jamais enregistrés | Les brancher sur des colonnes réelles ou les retirer |
| `AUD-I03` | États financiers sans choix d'exercice | Sélecteur d'exercice et de dates sur bilan, compte de résultat, SIG, balance |
| `AUD-I04` | Messages d'erreur techniques remontés tels quels (« violates not-null constraint ») | Traduire les erreurs métier des triggers en clés i18n (fr/en/ar) ; jamais de message SQL brut à l'écran |
| `AUD-I05` | Contraste (H du suivi, 2 points ouverts) | Clore les 2 décisions en attente |

---

## LOT J — Qualité, CI et preuve de bout en bout

| Réf | Objet | Action |
|---|---|---|
| `AUD-J01` | e2e jamais exécutés sur ce poste ; en CI seulement sur étiquette ou planification | Exécuter la suite e2e sur **toute PR vers `main`** ; garder l'étiquette pour les branches de travail |
| `AUD-J02` | Aucun parcours e2e ne vérifie un **chiffre** comptable | 4 parcours qui lisent les montants à l'écran : (1) inscription → plan semé ; (2) vente complète (lot E) ; (3) paie → écriture (lot F) ; (4) exercice complet → clôture → bilan et compte de résultat équilibrés → à-nouveaux |
| `AUD-J03` | Tests unitaires entièrement simulés (Supabase mocké), aucun n'a vu ces défauts | Garder les tests unitaires pour la logique pure ; toute règle comptable se teste en SQL (lot A) ou en e2e |
| `AUD-J04` | Liste blanche PostgREST (6 requêtes cassées tolérées) | Objectif zéro (lots F et G) ; la CI refuse ensuite tout ajout à la liste |
| `AUD-J05` | Types générés à committer (A3 du suivi) | Régénérer et committer `database-generated.ts` à chaque migration ; le contrôle CI existe déjà |
| `AUD-J06` | Charge | Le test de propriété du lot D à 100 000 écritures tourne chaque nuit, avec des seuils de durée |
| `AUD-J07` | `any` (2 359 restants, E4 du suivi) | Plafond CI décroissant par lot ; zéro `any` dans `lib/queries/accounting.ts` et `sales.ts` à la fin des lots D et E |

---

## LOT K — Localisation Djibouti

Ce lot est entièrement décrit dans le [cahier de localisation](../localisation/CAHIER-DES-CHARGES-LOCALISATION.md) ; il n'est pas redécrit ici. Constat du 21/09 : **rien n'est commencé** (`resolve_account` n'existe pas, aucun pack DJ parmi les 16 packs, EUR et TVA FR20 par défaut).

| Phase | Contenu | Effort (cahier) |
|---|---|---|
| Phase 1 | Neutralité du code : comptes par rôle (`resolve_account`), journaux, devise, arrondis, calendrier, pack France extrait, pack fictif `ZZ` comme preuve | ≈ 48 j |
| Phase 2 | Pack Djibouti : plan comptable national, TVA, paie, états, secteur public ; chaque valeur sourcée (`SRC-DJ-nn`), jeux d'essai à 0 écart | ≈ 26 j + délai d'obtention des textes + pilote |

**Aucune valeur fiscale ou sociale djiboutienne ne sera saisie de mémoire.** Les lots B à F sont écrits pour ne pas ajouter de nouveau code en dur : tout compte nouveau passe par une table de correspondance que la phase 1 remplacera par `resolve_account`.

---

## 3. Trajectoire des notes

| Module | 21/09 | Après A–J | Après K | Ce qui reste nécessaire pour 9,5 |
|---|:---:|:---:|:---:|---|
| Comptabilité : saisie et invariants | 4,5 | 9,0 | **9,5** | plan comptable djiboutien et rôles de comptes (K) |
| Comptabilité : clôture et états financiers | 1,5 | 9,0 | **9,5** | présentation des états au format djiboutien (K) et validation par l'expert-comptable référent |
| Gestion commerciale | 3 | 9,0 | **9,5** | mentions légales et TVA de Djibouti sur les factures (K) |
| Achats | 5 | 9,0 | **9,5** | idem ventes |
| Trésorerie et banque | 4,5 | 9,0 | **9,5** | formats bancaires des banques djiboutiennes (K, à collecter) |
| Stock et production | 6 | 9,5 | 9,5 | — |
| Paie et RH | 3 | 6,5 | **9,5** | moteur de paie djiboutien sourcé (K, phase 2) |
| Sécurité et multi-tenant | 7,5 | 9,5 | 9,5 | vos décisions H03–H05 |
| Localisation Djibouti | 1 | 2 | **9,5** | phases 1 et 2 complètes, pilote réussi |
| Qualité et CI | 6 | 9,5 | 9,5 | — |
| Ergonomie et i18n | 6 | 9,5 | 9,5 | revue de l'arabe par un locuteur natif |
| **Global** | **3,9** | **≈ 8,6** | **9,5** | |

Le plafond à ≈ 8,6 après les lots A à J est volontaire : tant que le produit calcule selon les règles françaises, il ne peut pas être noté 9,5 pour un marché djiboutien.

---

## 4. Séquencement et effort

Effort en jours de développement pour une personne, hors délais d'obtention des textes et de pilote.

| Vague | Lots | Effort | Livrable vérifiable |
|---|---|---:|---|
| **V1 — Arrêter l'hémorragie** | A, B, puis `AUD-E01`, `AUD-C10`, `AUD-D07` | ≈ 5 j | Une société créée peut saisir, facturer et lire un compte de résultat juste |
| **V2 — Noyau comptable** | C, puis D | ≈ 10 j | Un exercice complet se clôture, bilan et compte de résultat équilibrés, test de propriété vert |
| **V3 — Flux métier** | E, F, G | ≈ 19 j | Ventes, achats, paie et banque alimentent la comptabilité sans intervention |
| **V4 — Finition et preuve** | H, I, J | ≈ 10,5 j | e2e sur chaque PR, liste blanche vide, zéro confirmation native |
| **V5 — Djibouti** | K | ≈ 74 j + externe | Pack DJ publié, pilote validé |

V1 est à traiter immédiatement : tant qu'elle n'est pas faite, une société qui s'inscrit n'a pas de comptabilité utilisable.

Les vagues V3 et V4 peuvent avancer en parallèle si deux personnes travaillent sur le projet. La phase 1 de K peut démarrer pendant V3, puisque les lots C à F posent déjà les tables de correspondance qu'elle remplacera.

---

## 5. Décisions qui vous reviennent

| # | Question | Lot | Options |
|---|---|---|---|
| 1 | Trop-perçu client | E08 | Refuser le paiement, ou le porter en avance client (4191) |
| 2 | Numérotation des factures | E04 | Compteur par exercice (`FAC-2026-000001`) ou continu sur toute la vie de la société |
| 3 | Affectation du résultat | D04 | Automatique en report à nouveau, ou écran d'affectation obligatoire avant de clore l'exercice suivant |
| 4 | `generate-pdf` | H03 | Corriger ou retirer du déploiement |
| 5 | Import OCR via OpenAI | H04 | Garder avec consentement, remplacer, ou retirer |
| 6 | Rotation de la clé Supabase | H05 | À faire par vous |
| 7 | Localisation (décisions déjà ouvertes) | K | Périmètre secteur public, expert-comptable référent, arabe dès la v1, groupes multi-pays |

---

## 6. Journal d'exécution

### Vague V1 — 21/09/2026 (non commitée à la rédaction de ce journal)

| Action | État | Preuve |
|---|:---:|---|
| `AUD-A01` à `A04` | **OK** | `sql/178` à `182` (46 scénarios au départ, sous le rôle `authenticated`), `sql/ci/audit_helpers.sql`, `sql/ci/expected_failures.sql`, 5 étapes dans `ci.yml`. Contrôle vu en échec dans les deux sens : défaut retiré du registre → exit 3 ; test vert laissé au registre → exit 3. Un faux vert détecté et corrigé à l'écriture : S04 passait parce que `bootstrap_tenant` échouait pour tout le monde — ajout d'un témoin |
| `AUD-B01` à `B05` | **OK** (B00 : à vous) | `sql/183_fix_tenant_provisioning.sql` ; `misc.ts` passe par la RPC ; S02, S04, S05, S07, S08 verts ; 3 tests unitaires vus rouges sur l'ancien code |
| `AUD-E01` | **OK** | `sql/184_fix_composite_documents_null_id.sql` — les 5 RPC composées ; E01 et E09 verts |
| `AUD-C10` | **OK** | `sql/185_fix_post_journal_entry_posted.sql` ; C03 vert, C04 refusé désormais pour la bonne raison (déséquilibre). P01 échoue maintenant sur son vrai défaut (`AUD-F02`) |
| `AUD-D07`, `AUD-D10` | **OK** | `sql/186_fix_income_statement.sql` (`get_income_statement`, `generate_profit_loss`, nouvelle `get_income_statement_monthly`) ; `ReportsPage` réécrite ; R02, R05, R06, R07 verts ; 3 tests d'écran vus rouges sur l'ancienne page |

**Rejeu complet sur base neuve après V1** : 171 migrations sans erreur ; `plpgsql_check` 0 erreur, 39 avertissements (41 avant) ; suites 102, 105 (0 fuite), 166, 168, 170, 173, 175, 177 vertes ; 178–182 conformes au registre (**36 verts, 22 rouges attendus**, contre 18 et 28 au départ) ; PostgREST 1 473 requêtes acceptées ; types générés inchangés ; oxlint 0, tsc 0, 1 374 tests unitaires, parité i18n, build.

**Non vérifié** : l'affichage réel dans le navigateur. L'application pointe sur le projet cloud, où 183–186 ne sont pas déployées, et la connexion demande vos identifiants.

### Vague V2 — 21/09/2026 (lot C commité en `766608f`, lot D dans le commit suivant)

Protocole suivi : chaque nouveau scénario a été vu rouge sur le code d'avant son correctif, puis vert sans modification.

| Action | État | Preuve |
|---|:---:|---|
| `AUD-C01` à `C09`, `C11` | **OK** | `sql/187_accounting_kernel_strict.sql`. Nouveaux scénarios A08 (compte fermé ou de regroupement), A09 (facture exonérée), C05 (période), C06 (numérotation), tous vus rouges. 178 : **23/23 verts**. Les écritures automatiques imputaient des comptes absents du plan semé (4457000, 4456000, 641/645/431/421, 713550, 665…) ; les comptes de TVA du paramétrage (445661…, 445711…) n'étaient pas au plan : toute facture à TVA aurait été refusée par le contrôle de compte. |
| `AUD-D01` à `D06`, `D08` | **OK** | `sql/189_closing_and_statements.sql` : `close_fiscal_year` réécrite ; bilan, balance et compte de résultat sur une règle de périmètre commune (un exercice reporté par ses à-nouveaux n'est plus relu). Nouveaux scénarios D08 (états après clôture), D09 (ordre des clôtures, exercice suivant retrouvé) et R08 (compte hors plan au bilan), vus rouges. 179 : **17/17 verts**. `BalanceSheetPage` : le sélecteur d'exercice pilote enfin les données, les comptes non classés s'affichent et un bandeau signale un écart. |
| `AUD-D07` | **OK** | Surcharge `close_fiscal_year(uuid)` supprimée ; compte de résultat hors journal `CL`. |
| `AUD-D09` | **OK** | `getSIGData` passe par `get_income_statement`. Chiffre d'affaires du tableau de bord : comptes 70 HT de l'exercice en cours, et non plus le TTC des factures payées. |
| Test de propriété | **OK** | `sql/189_accounting_property_tests.sql`, branché en CI. 3 exercices, **100 000 écritures** : 7 invariants verts ; clôtures en 0,9 s (seuil 30 s) ; 53 s au total. Sur le code d'avant la 189, 5 invariants sur 7 échouent. |
| Performance de la validation | **OK** | Trouvé par le test de propriété sur base neuve : **100 000 validations en 18 min**. Cause : `log_nf525_event` cherchait le dernier maillon de la chaîne NF525 sans index sur `(tenant_id, id)`, donc le coût de chaque validation croissait avec l'historique de la société. Le défaut existe aussi en production. Index ajouté dans la 189 : 30 000 validations passent de 50,6 s à 6,8 s, et 100 000 prennent 25 s. |

**Écarts assumés par rapport au plan** :
- une ligne 0/0 n'est pas enregistrée (au lieu d'être refusée) ; une ligne ramenée à 0/0 bloque la validation ;
- le numéro définitif est une colonne à part, `posting_number` (`OD-2025-000001`) ; `number` reste le numéro de saisie ;
- `post_journal_entry` range en `OD` une écriture sans journal ;
- `allocate_result` n'est pas réécrite (décision n° 3 en attente) ;
- `generate_depreciation_entry`, `generate_residual_entry` et `post_deferred_charge` restent cassées comme avant (en-tête créé directement en « posted », comptes fictifs `6_____`). Elles sont désormais refusées dès l'en-tête. Elles relèvent du lot G.

**Tests retouchés, et pourquoi** : P02 était un **faux vert** (sans écriture, l'`UPDATE` ne touchait rien et le test concluait « ok ») ; il exige maintenant une écriture validée. S03 vérifie les comptes de repli réels (445710/445660). Les sociétés de test reçoivent plan, journaux et exercice (`_mk_tenant`, `ci/ledger_fixture.sql`), comme une société réelle depuis la 183. Deux tests unitaires décrivaient l'ancien `getFECData` ; deux tests SIG ne vérifiaient rien et ont été remplacés.

**Rejeu complet sur base neuve (jusqu'à 189)** :
- migrations sans erreur ; `plpgsql_check` 0 erreur ;
- suites 102, 105, 166, 168, 170, 173, 175, 177 vertes ; 178, 179 et 182 entièrement vertes ; 180 et 181 conformes au registre ;
- registre : **22 → 5 défauts** (E04, E06, E08, P01, P02 — lots E et F) ;
- PostgREST : 1 475 requêtes acceptées ;
- oxlint 0, tsc 0, **1 375 tests unitaires**, parité i18n, build.

**Non vérifié** : l'affichage dans le navigateur, pour la même raison qu'en V1.

### Vague V3 — 21/09/2026 (non commitée à la rédaction de ce journal)

Décisions prises : n° 1, trop-perçu client **en avance client 4191**, appliqué symétriquement aux fournisseurs (4091) ; n° 2, numérotation **par exercice** (`FAC-2026-000001`, `AV-…`, `DEV-…`, `ACH-…`, `AVF-…`). Protocole : chaque scénario a été vu rouge sur le code d'avant son correctif, puis vert. Deux scénarios de V1 ont dû être retouchés, voir plus bas.

| Action | État | Preuve |
|---|:---:|---|
| `AUD-E02` | **OK** | `InvoicesPage` : formulaire de lignes, sans numéro saisi ; `SalesDocumentForms.test.tsx`, 4 tests vus rouges sur l'ancien écran. **Trouvé** : Devis et Avoirs envoyaient leurs lignes sous `quote_lines` / `credit_note_lines`, clé ignorée : aucune ligne enregistrée. |
| `AUD-E03`, `E06` | **OK** | `sql/190_sales_to_ledger.sql` : montants de ligne et totaux d'en-tête calculés par le serveur ; facture validée figée (lignes, montants, suppression). E10, E11. **E11 prouvait qu'on pouvait ramener une facture validée à 1 €.** |
| `AUD-E04`, `E11` | **OK** | Numéro provisoire en brouillon, définitif à la validation, par exercice ; une validation refusée ne consomme pas de numéro. E12, E13 (1 000 validations → 000001 à 001000), E20. `Math.random` retiré des 6 écrans et de `sales.ts`. |
| `AUD-E05` | **OK** | RPC `convert_quote_to_invoice` ; E04, E14. |
| `AUD-E07` | **OK** | Avoirs : statut `validated`, écriture VT inverse, rattachement obligatoire, facture imputée et lettrée. E06, E15, E16 (E16 était un faux vert : témoin ajouté). |
| `AUD-E08`, `E09`, `E10` | **OK** | Excédent en 419100 ; compte et journal propres à chaque compte bancaire (512000/BQ, puis 5121nn/BQn, créés à la volée) ; lettrage automatique au solde. E08, E17, E18, E19. |
| `AUD-F02`, `F01` | **OK** | `sql/191_payroll_to_ledger.sql` : `post_payroll_journal` / `payroll_post_run`, écriture construite rubrique par rubrique depuis les bulletins, journal PAIE, idempotente, bulletin incohérent refusé ; le passage à « payé » appelle la même fonction. P01 à P07 (P01/P02 réécrits sur la RPC, comme annoncé dans l'en-tête du fichier). |
| `AUD-F03` | **OK** | Table `payroll_account_mapping` (défauts PCG, surcharge par société). P03. |
| `AUD-F04` | **OK** | G17 : CICE et BDES lisent le brut sur les bulletins de l'année (ce n'était pas la DSN). |
| `AUD-G01`, `G02` | **OK** | `sql/192_purchases_treasury.sql`, nouvelle suite `sql/192_purchases_treasury_tests.sql` (branchée en CI) : A01 à A08. Référence fournisseur (`supplier_reference`) distincte du numéro interne `ACH-…`. **Trouvé** : l'écran « Nouvelle facture fournisseur » envoyait `status: 'received'`, refusé par la base (**création impossible**) ; l'écran des avoirs fournisseur n'avait aucune action de validation ; un décaissement échouait dès que le solde calculé du compte bancaire devenait négatif (contrainte posée à tort par la 82). `PurchaseDocumentForms.test.tsx`, 3 tests vus rouges. Les 31 libellés de l'écran factures d'achat manquaient dans les trois langues (clés brutes affichées). |
| `AUD-G03` | **OK** | `importBankStatement` : l'écran d'import lit le relevé (CAMT.053, MT940, CFONB 120), écarte les doublons et enregistre les opérations. Avant, il n'enregistrait que le nom du fichier, en « pending ». `bank-statement-import.test.ts`. OFX : aucun lecteur n'existe. |
| `AUD-G04` | **OK** | `sql/196_bank_reconciliation.sql` : pointage automatique relevé ↔ écriture 512x, état de rapprochement réécrit (il lisait l'IBAN comme compte comptable et additionnait les débits). G04. |
| `AUD-G05` | **OK** | `sql/193_stock_adjustment_variation.sql` : un inventaire devient une entrée ou une sortie de la différence. Avant : aucune écriture, dépôt inchangé (fiche article 7, dépôt 10). G05. |
| `AUD-G06` à `G08` | **OK** | `sql/195_purchase_order_line_received.sql` (colonne calculée `quantity_received`) ; G18, G20, G21 corrigés dans les requêtes. **Liste blanche PostgREST vide.** **Trouvé** : une réception partielle faisait échouer la commande (statut `partial` refusé) ; le MRP filtrait un statut `sent` inexistant. G06. |
| `AUD-G09` | **OK** | `sql/194_pos_session_stock.sql` : la clôture de caisse décrémentait le stock deux fois, et dans tous les dépôts. G09 (écriture, stock, chaîne NF525). |
| `AUD-G10` | **OK** | G10 : les 46 comptes des écritures automatiques sont au plan semé ; contrôle vu rouge en retirant 419100. |

**Tests de V1/V2 retouchés, et pourquoi** : E04 comparait la chaîne `'D=1200 C=1200'`, devenue `1200.00` avec le passage en `numeric(18,2)` de la 187 : il ne pouvait plus passer. Il compare désormais des nombres. `102_trigger_tests.sql` : les TESTS 2 et 3 inséraient des factures directement « validées », sans ligne ni écriture, ce que la 190 interdit : elles passent maintenant par brouillon, ligne et validation. TEST 13 retrouve l'écriture par le numéro légal.

**Rejeu complet sur base neuve (jusqu'à 196, avec 189 et 200)** : `plpgsql_check` 0 erreur ; suites 102, 105, 166, 168, 170, 173, 175, 177 vertes ; 178 (23), 179 (17), 180 (20), 181 (7), 182 (8), 192 (13) **entièrement vertes** ; **registre vide** ; PostgREST **1 486 requêtes acceptées, aucune tolérance** ; types régénérés ; oxlint 0, `tsc -b` 0, **1 388 tests unitaires**, parité i18n, build.

**Relecture critique de V3 (même jour)**, défauts trouvés dans ce que V3 avait laissé en place, chacun vu rouge puis vert :
- E21 : un brouillon pouvait être « envoyé » (numéro provisoire, sans écriture). Le serveur refuse désormais, et « Envoyer » valide d'abord la facture ; les boutons Avoir et Factur-X n'apparaissent que sur une facture validée.
- E22 / A09 : le payé d'une facture se saisissait à la main. Le bouton « Marquer payée » des achats écrivait `status = 'paid'` sans décaissement ni écriture. Le payé ne résulte plus que des règlements et avoirs (drapeau `app.settlement_in_progress` posé par les fonctions de règlement). Les deux boutons « Marquer payée » enregistrent un vrai règlement, avec son propre numéro (`REG-…`, `DEC-…`), et seulement sur une facture validée ou approuvée.
- G11 : `auto_reconcile_by_score` ajoutait le montant d'une ligne bancaire au payé de la facture, sans règlement ni écriture, y compris pour les lignes reflétant un règlement déjà saisi. Réécrit dans la 196 : sur une ligne de relevé au crédit reconnue avec certitude, il enregistre un vrai règlement client.
- Le badge « Comptabilisé » des deux listes de factures lisait des colonnes inexistantes et affichait toujours « Non comptabilisé ».
- `applyPurchaseCreditToInvoice` recalculait le payé côté front ; il délègue au serveur.

Après relecture : 180 (**22**), 192 (**15**) verts ; PostgREST **1 489** requêtes acceptées ; **1 400 tests unitaires** ; typecheck, lint, i18n, build verts. Le scénario R08 de 179, cassé un temps par la 201 (session prod), a été corrigé par la session V2 : 179 est de nouveau à 17/17 avec 201.

**Non vérifié** : l'affichage dans le navigateur ; les e2e (lot J) ; le rejeu sur une copie de prod, pourtant nécessaire avant déploiement puisque la prod est à 188 (reprises de la 190 : comptes et journaux créés pour les comptes bancaires existants).

**Restes identifiés** : `vat_account_mapping` envoie `FR20` et `AUTOLIQ` vers les mêmes comptes (445711/445661), à séparer pour la déclaration de TVA ; `toast.loadError` et d'autres clés manquent dans plusieurs écrans (lot I) ; le paiement des salaires (D 421 / C 512) n'est pas généré.

---

---

## 7. Recette finale

Le plan est terminé quand toutes les conditions suivantes sont vraies, prouvées par une exécution datée dans le suivi :

1. `sql/ci/expected_failures.sql` ne contient plus aucune ligne `INSERT`.
2. Le job `db-integration` passe sur une base neuve, avec les fichiers de tests 178 à 182 et le test de propriété.
3. `npm run db:embeds` passe **sans liste blanche**.
4. La suite e2e passe sur la PR finale vers `main`, dont les 4 parcours chiffrés de `AUD-J02`.
5. Le test de propriété à 100 000 écritures passe dans les seuils de durée.
6. Une société réelle créée par l'inscription tient un exercice complet de bout en bout : factures, achats, paie, banque, clôture, à-nouveaux. Bilan et compte de résultat sont revus par un expert-comptable.
7. Pour la note 9,5 sur les modules concernés : pack Djibouti publié et pilote validé (lot K).
