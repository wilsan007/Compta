# Plan d'Implémentation Final — Alignement Sage 100 Comptabilité

> Couverture actuelle: 69% (79/115) → Cible: 100%
> 50 incohérences identifiées (7 critiques, 8 moyennes, 15 faibles, 20 cohérence interne)

---

## A. INCOHÉRENCES CRITIQUES (7)

### 1. Calcul TVA auto en saisie
- **Sage 100**: Bouton "Calculer TVA" → calcule HT→TVA→TTC, génère lignes auto (compte 445xxx)
- **App**: Champ `vat_code` dans grille mais aucun calcul. `JournalLine` n'a pas `vat_code`/`vat_amount`
- **Plan**: Fonction `calculateVAT(ht, vatCode)` + bouton par ligne dans `JournalSaisiePage`
- **SQL**: `ALTER TABLE journal_lines ADD COLUMN vat_code text, ADD COLUMN vat_amount numeric`
- **Type**: Ajouter `vat_code?, vat_amount?` sur `JournalLine`

### 2. Libellé auto non connecté
- **Sage 100**: Règles priorisées remplissent le libellé selon compte/journal/tiers avec variables `{{numero}}`, `{{tiers}}`
- **App**: Table `auto_label_rules` + page CRUD existent mais `JournalSaisiePage` ne les appelle jamais
- **Plan**: Fonction `applyAutoLabelRules(journalCode, accountCode, tiers, pieceNumber, date)` → appel sur `onBlur` compte dans `JournalSaisiePage`

### 3. Échéance + calcul auto
- **Sage 100**: Champ échéance dans grille + calcul auto selon modèle de règlement du tiers (30j, 30j fin de mois, fractionné)
- **App**: `JournalLine` n'a pas `echeance_date`. `ThirdPartyAccount` n'a pas `payment_term_id`. Pas de table `payment_terms`
- **Plan**: 
  - Table `payment_terms` (id, code, name, type: fixed|end_of_month|split, days_1, days_2, pct_1, pct_2)
  - `ALTER TABLE third_party_accounts ADD COLUMN payment_term_id uuid`
  - `ALTER TABLE journal_lines ADD COLUMN echeance_date date`
  - Fonction `calculateEcheance(date, paymentTermId)`
  - Page `PaymentTermsPage` (Structure)
  - Champ échéance dans `JournalSaisiePage`

### 4. Référentiel taux de TVA
- **Sage 100**: Structure/Taux de taxes → Code, Intitulé, Taux, Compte collectée, Compte déductible, Type. Onglets: Liste, Rubriques, Infos comptables
- **App**: Type `TaxRate` existe mais pas de page dédiée
- **Plan**: Page `TaxRatesPage` avec 3 onglets + boutons [Initialiser] [Assistant]
- **SQL**: `ALTER TABLE tax_rates ADD COLUMN account_collectee text, ADD COLUMN account_deductible text, ADD COLUMN type text DEFAULT 'CA3', ADD COLUMN mode text DEFAULT 'debits'`
- **Route**: `/accounting/structure/tax-rates`

### 5. Modèles de règlement
- **Sage 100**: Structure/Modèles de règlement → conditions (30j, 30j fin de mois, fractionnement)
- **App**: `payment_terms` sur Customer/Supplier est texte libre, pas un référentiel
- **Plan**: Voir point 3 — table `payment_terms` + page `PaymentTermsPage`
- **Route**: `/accounting/structure/payment-terms`

### 6. Droits d'accès journaux non appliqués
- **Sage 100**: User ne peut saisir que dans journaux autorisés
- **App**: Table + page existent mais `JournalSaisiePage` affiche tous les journaux
- **Plan**: Fonction `getAuthorizedJournals(userId)` → remplacer `getJournals()` dans `JournalSaisiePage`

### 7. Saisie par pièce
- **Sage 100**: Saisie regroupée par pièce (Alt+P), règlements multi-échéances, lettrage en saisie, menu Actions
- **App**: `BatchEntryPage` est CRUD basique, pas saisie par pièce
- **Plan**: Nouvelle page `SaisieParPiecePage` avec en-tête pièce + grille + boutons (Régénérer contrepartie, Recalculer TVA, Affecter solde, Lettrer en saisie)
- **Route**: `/accounting/treatment/saisie-par-piece`

---

## B. INCOHÉRENCES MOYENNES (8)

### 8. Lettrage en saisie
- Bouton "Lettrer" dans grille sur ligne tiers → popup sélection écritures non lettrées

### 9. Création compte à la volée
- Sur `onBlur` compte inexistant → popup "Créer le compte XXX?" avec formulaire rapide

### 10. Bon à payer
- `ALTER TABLE journal_lines ADD COLUMN marked_bap bool, ADD COLUMN marked_bap_date date`
- Bouton dans `SearchEntriesPage` + filtre dans `PaymentGenerationPage`

### 11. Marquage paramétrable
- Table `marking_types` (id, code, label, color, active)
- `ALTER TABLE journal_lines ADD COLUMN marking_code text`
- Page paramétrage Structure + filtres recherche

### 12. Règlements multi-échéances
- Dans `PaymentGenerationPage`: sur facture avec modèle fractionné → générer N lignes échéance

### 13. Justificatif de solde
- Page `JustificatifSoldePage` — sélection compte/tiers + période → solde initial + mouvements + solde final
- Route: `/accounting/states/justificatif-solde`

### 14. État de rapprochement
- Page `EtatRapprochementPage` — écarts pointés/non pointés
- Route: `/accounting/states/etat-rapprochement`

### 15. 10 niveaux de relance
- Table `reminder_levels` (level 1-10, name, template, days_after_due, penalty_rate)
- Étendre `CollectionReminder` + page paramétrage + suivi promesses + gestion litiges

---

## C. INCOHÉRENCES FAIBLES (15)

| # | Feature | Plan |
|---|---|---|
| 16 | Révision par cycle | Tables `revision_cycles` + page Structure |
| 17 | Réimputation générales | Fonction `reimputeGeneral()` + bouton dans SearchEntries |
| 18 | Réimputation analytiques | Fonction `reimputeAnalytic()` + bouton |
| 19 | Compaction | Page `CompactionPage` + fonction `compactDatabase()` |
| 20 | Fusion comptes/tiers | Page `FusionComptesPage` + fonction `fusionAccounts()` |
| 21 | Plan reporting | Tables `reporting_plans` + page Structure |
| 22 | Codes journaux analytiques | `ALTER TABLE journals ADD COLUMN is_analytic bool, analytic_plan_id uuid` |
| 23 | Saisie OD analytiques | Ventilation multi-lignes dans JournalSaisiePage sur journal OD |
| 24 | RGPD | Page `RGPDPage` — cartographie, conservation, anonymisation |
| 25 | Champs statistiques tiers | Tables `stat_fields` + `tier_stat_values` + onglet dans ThirdParty |
| 26 | Export Excel/HTML | Fonction `exportToExcel()` + bouton sur toutes les pages d'états |
| 27 | Tableau de bord paramétrable | Table `dashboard_widgets` + drag-and-drop |
| 28 | Compte bancaire société par tiers (V12) | `ALTER TABLE third_party_accounts ADD COLUMN default_bank_account_id uuid` |
| 29 | Affichage soldes dans listes | Colonne solde dans ChartAccounts + ThirdParty |
| 30 | Encours tiers | `credit_limit` sur ThirdPartyAccount + contrôle en saisie |

---

## D. COHÉRENCE INTERNE (20)

| # | Problème | Fix |
|---|---|---|
| 31 | `auto_label_rules` non connectées | Voir point 2 |
| 32 | `journal_access_rights` non appliqués | Voir point 6 |
| 33 | `batch_entry_sessions` non intégrées | Intégrer dans SaisieParPiece |
| 34 | `vat_on_collections` non connecté | Générer TVA sur encaissement dans PaymentGeneration |
| 35 | `ifrs_adjustments` non intégré | Sélecteur approche Nationale/IAS-IFRS dans GrandLivre |
| 36 | `carry_forward` sans mode | Paramètre mode: none/balance/detail + filtre racines 1-5 |
| 37 | `extourne` non accessible depuis interrogation | Bouton dans GrandLivreTiers |
| 38 | `tax_payments` non lié à `edi_tva` | Flux auto déclaration→paiement |
| 39 | `JournalLine` manque `vat_code` | Ajouter au type + SQL |
| 40 | `JournalLine` manque `echeance_date` | Ajouter au type + SQL |
| 41 | `JournalLine` manque `quantity` | Ajouter au type + SQL |
| 42 | `JournalLine` manque `marking_code` | Ajouter au type + SQL |
| 43 | `ThirdPartyAccount` manque champs | Ajouter payment_term_id, default_bank_account_id, credit_limit, stat_fields |
| 44 | `Journal` manque champs | Ajouter numbering_mode, account_attente, racines_autorisees, is_analytic |
| 45 | `ChartAccount` manque champs | Ajouter racine, classe, nature, code_taxe_default, saisie_analytique, saisie_echeance, saisie_tiers, infos_libres |
| 46 | `EntryTemplate` incomplet | Ajouter type, colonnes paramétrables |
| 47 | `TaxRate` incomplet | Ajouter account_collectee, account_deductible, type, mode |
| 48 | Préférences société manquantes | Onglets dans CompanySettings (saisie négative, quantités, mono/double monnaie) |
| 49 | Paramètres TVA société manquants | Régime CA3/CA12, encaissements/débits, périodicité |
| 50 | FiscalYear profondeur | V12: 10 exercices consultables |

---

## E. PLAN D'IMPLÉMENTATION PAR PHASE

### Phase 7A — Critiques (items 1-7)
1. **SQL migration** `28_sage100_critical_fixes.sql`:
   - `ALTER TABLE journal_lines ADD COLUMN vat_code text, vat_amount numeric, echeance_date date, quantity numeric, marking_code text, marked_bap bool, marked_bap_date date`
   - `ALTER TABLE tax_rates ADD COLUMN account_collectee text, account_deductible text, type text, mode text`
   - `ALTER TABLE third_party_accounts ADD COLUMN payment_term_id uuid, default_bank_account_id uuid, credit_limit numeric`
   - `ALTER TABLE journals ADD COLUMN numbering_mode text, account_attente text, is_analytic bool, analytic_plan_id uuid`
   - `ALTER TABLE chart_accounts ADD COLUMN racine text, classe text, nature text, code_taxe_default text, saisie_analytic bool, saisie_echeance bool, saisie_tiers bool`
   - `CREATE TABLE payment_terms (...)`
   - `CREATE TABLE marking_types (...)`
   - RLS policies

2. **Types** `types/index.ts`: Enrichir JournalLine, TaxRate, ThirdPartyAccount, Journal, ChartAccount + nouveaux PaymentTerm, MarkingType

3. **Queries** `queries.ts`:
   - `calculateVAT(ht, vatCode)`, `generateVATLines(line, vatRate, account)`
   - `applyAutoLabelRules(journalCode, accountCode, tiers, pieceNumber, date)`
   - `calculateEcheance(date, paymentTermId)`
   - `getAuthorizedJournals(userId)`
   - `getPaymentTerms()`, CRUD payment_terms
   - `getTaxRates()`, CRUD tax_rates (enrichi)

4. **Pages**:
   - `TaxRatesPage.tsx` — 3 onglets (Liste, Rubriques, Infos comptables)
   - `PaymentTermsPage.tsx` — liste + fiche
   - `SaisieParPiecePage.tsx` — saisie par pièce complète
   - Modifier `JournalSaisiePage.tsx` — ajouter calcul TVA, libellé auto, échéance, filtrage journaux

5. **Routes** dans `App.tsx`:
   - `/accounting/structure/tax-rates`
   - `/accounting/structure/payment-terms`
   - `/accounting/treatment/saisie-par-piece`

6. **i18n** — clés dans `accounting.json` (fr/en/ar): `taxRates.*`, `paymentTerms.*`, `saisieParPiece.*`

### Phase 7B — Moyennes (items 8-15)
1. **SQL** `29_sage100_medium_fixes.sql`: marking_types, reminder_levels, payment_promises, disputes
2. **Pages**: JustificatifSoldePage, EtatRapprochementPage, ReminderLevelsPage
3. **Modifications**: Lettrage en saisie dans JournalSaisiePage, création compte volée, bon à payer dans SearchEntries, multi-échéances dans PaymentGeneration

### Phase 7C — Faibles (items 16-30)
1. **SQL** `30_sage100_minor_fixes.sql`: revision_cycles, reporting_plans, stat_fields, dashboard_widgets
2. **Pages**: RevisionCyclesPage, FusionComptesPage, PlanReportingPage, CompactionPage, RGPDPage
3. **Modifications**: Export Excel sur états, sélecteur IFRS dans GrandLivre, soldes dans listes

### Phase 7D — Cohérence interne (items 31-50)
1. Enrichir tous les types (JournalLine, ThirdPartyAccount, Journal, ChartAccount, TaxRate, EntryTemplate)
2. Connecter auto_label_rules à la saisie
3. Connecter journal_access_rights à la saisie
4. Connecter vat_on_collections à PaymentGeneration
5. Ajouter mode à carry_forward
6. Ajouter extourne dans GrandLivreTiers
7. Lier tax_payments à edi_tva
8. Préférences société dans CompanySettings
9. Paramètres TVA dans CompanySettings

---

## F. DÉTAILS UI EXACTS SAGE 100 (référence)

### F.1 Saisie des journaux — grille exacte
**Colonnes (ordre exact Sage 100)**:
1. Jour (J, 2 car.)
2. N° pièce (auto ou manuel)
3. N° facture/Référence
4. N° compte général (9 car. alphanum.)
5. N° compte tiers (séparé du compte général)
6. Libellé (30 car.)
7. Débit (numérique 14,2)
8. Crédit (numérique 14,2)
9. Échéance (date)
10. Code taxe (lien vers référentiel)
11. Ventilation analytique (lien vers sections)

**Bandeau solde progressif (Trésorerie uniquement)**:
- Ancien solde | +Mouvements D / -Mouvements C | Nouveau solde

**Boutons**: Équilibrer | Calculer TVA | Contrepartie auto | Modèle | Libellé auto | Calculatrice

### F.2 Fiche compte (Plan comptable) — onglets exacts
1. **Compte**: N°, Désignation, Racine, Classe, Nature
2. **Complément**: Code taxe défaut, Nb lignes, Saut lignes/page, Regroupement, Saisie analytique, Saisie échéance, Saisie compte tiers
3. **Exercice N-1**: Débit/Crédit N-1
4. **Exercice N**: Débit/Crédit/Solde N
5. **Exercice N+1**: Débit/Crédit N+1
6. **Informations libres**: 10 champs personnalisés

### F.3 Fiche tiers (Plan tiers) — onglets exacts
1. **Fiche principale**: N°, Désignation, Type, Compte collectif, Adresse, CP, Ville, Pays, SIRET, TVA intra
2. **Banques**: Multi-RIB (IBAN, BIC, code banque, guichet, compte, clé)
3. **Modèles**: Modèle échéancement, conditions règlement, mode règlement
4. **Complément**: Encours autorisé, niveau relance, modèle relance, délai paiement, escompte, contact
5. **Statistiques**: Zone géographique, catégorie
6. **Informations libres**: Champs personnalisés

### F.4 Fiche journal (Codes journaux) — onglets exacts
1. **Complément**: Code, Intitulé, Type (Vente/Achat/Trésorerie/OD/À-nouveau), Racines autorisées, Comptes paramétrés, Compte d'attente, Numérotation (manuel/auto/continu)
2. **Banque**: Compte banque, RIB, Mode rapprochement (manuel/auto) — uniquement Trésorerie
3. **Modèle**: Modèle de saisie par défaut
4. **Droits**: Utilisateurs autorisés

### F.5 Interrogation tiers — sélections exactes
- Type collectif, Compte général, Dates, Type de lot, Établissement, Journal
- Approche: Nationale / IAS-IFRS
- Filtres lettrage: non lettrées / partiellement / totalement
- Date lettrage, Code lettrage, Marquage, Sélection par montant
- **Menu Actions**: Extourner, Pièce (consulter/modifier), Échéances, Lettrer, Marquer, Détail lettrage

### F.6 Lettrage manuel — fenêtre exacte
- Sélection compte tiers
- Liste écritures non lettrées (D et C séparés)
- Sélection des écritures à lettrer (D = C)
- Attribution code lettrage
- Lettrage partiel avec reliquat si D ≠ C

### F.7 Lettrage automatique — fenêtre exacte
- Sélection tiers ou tous
- Critères: dates, montant
- Algorithme rapprochement auto D/C par montant
- Génération code lettrage auto + rapport

### F.8 Clôture des journaux — niveaux exacts
- **Partielle**: Verrouillage écritures (brouillard imprimé)
- **Par période**: Verrouillage période mensuelle pour un journal
- **Totale**: Verrouillage complet journal pour exercice
- **Procédure**: Sélection journal + période → vérification équilibrage → impression brouillard (obligatoire) → clôture (Ouvert → Imprimé → Clôturé). Écritures clôturées inaltérables.

### F.9 Fin d'exercice — fonctions exactes
- Nouvel exercice (création, dates)
- Report à nouveau (racines 1-5, modes: Aucun/Solde/Détail)
- Clôture exercice (verrouillage, écritures de résultat)
- États de clôture (Bilan, CR, SIG, balance)
- FEC (provisoire et définitif)
- Archivage
- Sauvegarde fiscale

### F.10 Écritures de régularisation — 4 types exacts
| Type | Sage 100 | App |
|---|---|---|
| CCA | Charges constatées d'avance | ✅ |
| PCA | Produits constatés d'avance | ✅ |
| FFAR | Fournisseurs factures à recevoir | ✅ (nommé PRC) |
| CFAE | Clients factures à établir | ✅ (nommé CRC) |
- **Procédure**: Paramètres société → journal + modèles + proratisation (360j ou jours réels) → saisir période → assistant → générer + extourne auto au 01/01/N+1 + état récap

---

## G. ORDRE D'IMPLÉMENTATION

1. **SQL migrations** (28, 29, 30) — toutes les tables/colonnes manquantes
2. **Types** — enrichir tous les interfaces
3. **Queries** — toutes les fonctions manquantes
4. **Pages critiques** — TaxRatesPage, PaymentTermsPage, SaisieParPiecePage
5. **Modifications JournalSaisiePage** — calcul TVA, libellé auto, échéance, droits journaux
6. **Pages moyennes** — JustificatifSolde, EtatRapprochement, ReminderLevels
7. **Pages faibles** — RevisionCycles, Fusion, PlanReporting, Compaction, RGPD
8. **Cohérence interne** — connecter toutes les features existantes non liées
9. **i18n** — toutes les clés dans fr/en/ar
10. **Routes** — toutes les nouvelles routes dans App.tsx
11. **Tests** — unit tests pour nouvelles fonctions + E2E pour nouvelles pages
