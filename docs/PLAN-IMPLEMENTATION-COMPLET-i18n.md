# Plan d'Implémentation Complet — i18n + Modules 100%

> **Objectif :** Amener chaque module à 100% de couverture Sage 100, avec i18n FR/EN/AR.
> **Référence :** `SAGE-100-REFERENCE-COMPLETE.md`

---

## Phase 0 — Infrastructure & Législation multi-pays

### 0.1 Packs de législation — 14 pays

| Pack | Pays | Standard | Devise | TVA |
|---|---|---|---|---|
| UK | UK | UK GAAP | GBP | 20% |
| US | USA | US GAAP | USD | 0% |
| MA | Maroc | CGNC | MAD | 20% |
| DZ | Algérie | SCF | DZD | 19% |
| TN | Tunisie | NCT | TND | 19% |
| SN | Sénégal | SYSCOHADA | XOF | 18% |
| CI | Côte d'Ivoire | SYSCOHADA | XOF | 18% |
| CM | Cameroun | SYSCOHADA | XAF | 19.25% |
| DE | Allemagne | HGB | EUR | 19% |
| ES | Espagne | PGC | EUR | 21% |
| IT | Italie | OIC | EUR | 22% |
| SA | Arabie Saoudite | SOCPA | SAR | 15% |
| AE | EAU | IFRS | AED | 5% |
| EG | Égypte | EAS | EGP | 14% |

- [ ] `sql/04_seed_legislation_packs.sql` — 14 packs + TVA + plans comptables
- [ ] `LegislationPacksPage.tsx` (admin) — i18n `settings:legislation.*`
- [ ] Modifier `OnboardingPage.tsx` : étape pays → charge plan comptable + TVA + devise
- [ ] `useLocale` lit `company_settings.locale` pour formatage dates/devises

---

## Phase 1 — Comptabilité 100% (90% → 100%)

### 1.1 Écritures d'abonnement automatiques
- [ ] Table `recurring_entries` (journal_id, frequency, day_of_month, lines jsonb, status)
- [ ] `RecurringEntriesPage.tsx` — CRUD + `generateRecurringEntries()` auto
- [ ] i18n `accounting:recurring.*`

### 1.2 Écritures de régularisation CCA/PCA
- [ ] Table `regularization_entries` (type CCA/PCA/PRC/CRC, fiscal_year, account 486/487)
- [ ] `RegularizationPage.tsx` — assistant + extourne auto
- [ ] Intégration `FiscalYearClosurePage.tsx` — i18n `accounting:regularization.*`

### 1.3 Calculatrice intégrée dans la saisie
- [ ] Modifier `JournalSaisiePage.tsx` : champ `=expr` → évaluer
- [ ] `evaluateExpression()` dans utils.ts (parser sécurisé)

### 1.4 Bon à payer (validation factures fournisseurs)
- [ ] Colonnes `approval_status/approved_by/approved_at` sur `purchase_invoices`
- [ ] Workflow pending→approved + bouton dans `PurchaseInvoicesPage.tsx`
- [ ] Rôle `approve_invoices` — i18n `purchases:approval.*`

### 1.5 Rapport des délais de paiement
- [ ] `PaymentDelayReportPage.tsx` — délai convenu vs réel par tiers
- [ ] i18n `accounting:reports.payment_delay.*`

### 1.6 Réévaluation créances/dettes en devises
- [ ] `CurrencyRevaluationPage.tsx` — écarts de change (comptes 656/756)
- [ ] Intégration clôture exercice — i18n `accounting:currency_revaluation.*`

### 1.7 Relances avec liens de paiement en ligne
- [ ] Table `payment_links` (invoice_id, provider stripe/paypal, url, status)
- [ ] Intégration Stripe Payment Links + webhook
- [ ] `PaymentLinksPage.tsx` — i18n `accounting:payment_links.*`

### 1.8 Champs statistiques tiers
- [ ] Colonnes `sector_code/geographic_zone` sur customers/suppliers
- [ ] Rapport CA par secteur — i18n `sales:statistics.*`

### 1.9 Multi-plans analytiques (jusqu'à 11)
- [ ] Table `analytic_plans` + `journal_line_analytics` (multi-ventilation)
- [ ] `AnalyticPlansPage.tsx` + modification `JournalSaisiePage.tsx`
- [ ] i18n `accounting:analytic.plans.*`

### 1.10 Pré-ventilation par grilles
- [ ] Table `ventilation_rules` (account_code, plan_id, section_code, percentage)
- [ ] `VentilationRulesPage.tsx` — application auto lors saisie

### 1.11 Rapprochement bancaire automatique (codes AFB)
- [ ] Table `reconciliation_rules` (afb_code, match criteria, date_tolerance)
- [ ] Mode "Auto" dans `BankReconciliationPage.tsx` + génération écritures d'écarts

### 1.12 Import extraits bancaires (CFONB, MT940, Camt.053)
- [ ] `lib/bankStatementParser.ts` — 3 parsers
- [ ] `BankStatementImportPage.tsx` — upload + preview + import

### 1.13 Télé-déclaration TVA (EDI-TVA)
- [ ] `VatDeclarationPage.tsx` — génération XML EDI-TVA + historique

### 1.14 TVA encaissement vs débit
- [ ] Colonne `vat_regime` sur `company_settings` + table `vat_pending`
- [ ] Bascule TVA → exigible au paiement

### 1.15 TVA sur acomptes
- [ ] Type `deposit` dans `invoices` + TVA exigible dès émission

### 1.16 Taxe Véhicules de Société (TVS)
- [ ] Table `vehicle_tax` + `TVSPage.tsx`

### 1.17 RGPD — Gestion données personnelles
- [ ] `GDPRPage.tsx` : cartographie, export, anonymisation + table `gdpr_requests`

### 1.18 Normes IAS-IFRS
- [ ] Table `ifrs_mappings` + `IFRSMappingPage.tsx` + états IFRS

### 1.19 Solde progressif interrogation tiers
- [ ] Colonne `running_balance` dans `GrandLivreTiersPage.tsx`

### 1.20 Protection journaux par droits d'accès
- [ ] Table `journal_permissions` (user_id, journal_id, can_read, can_write)
- [ ] Filtrage selon utilisateur connecté

### 1.21 10 exercices consultables
- [ ] Navigation inter-exercices dans `SearchEntriesPage.tsx`

### 1.22 Sauvegarde fiscale + 150 tableaux de bord
- [ ] `FiscalBackupPage.tsx` — export FEC + pièces + balance
- [ ] Ajouter tableaux manquants : marge par produit, évolution mensuelle, top clients

---

## Phase 2 — Gestion Commerciale 100% (85% → 100%)

### 2.1 Transformation sans ressaisie
- [ ] Boutons "Transformer en..." dans Quotes/Orders/Delivery/Invoices
- [ ] Fonctions `transformQuoteToOrder()`, `transformOrderToDelivery()`, etc.
- [ ] i18n `sales:transform.*`

### 2.2 Articles à gammes (tailles/couleurs)
- [ ] Tables `product_attributes` + `product_variants` (sku, attributes jsonb, price_override)
- [ ] Onglet "Variantes" dans `ProductsPage.tsx` + sélecteur dans devis/factures

### 2.3 Numéros de série et lots
- [ ] Tables `product_serial_numbers` + `product_batches` (expiry_date, quantity)
- [ ] Traçabilité dans stock + factures + BL

### 2.4 Stock dormant + stock prévisionnel
- [ ] `DormantStockPage.tsx` — produits sans mouvement depuis X jours
- [ ] Colonne "Prévisionnel" dans `StockQuantitiesPage.tsx`

### 2.5 Gestion des emplacements
- [ ] Table `warehouse_locations` (zone, aisle, shelf) + `location_id` sur stock_quantities

### 2.6 Contrôle qualité + Picking
- [ ] Table `quality_checks` + `QualityCheckPage.tsx`
- [ ] Table `pick_lists` + `PickListPage.tsx` (scan code-barres)

### 2.7 Représentants et commissionnement
- [ ] Table `sales_representatives` (commission_rate, territory)
- [ ] `RepresentativesPage.tsx` + rapport commissions

### 2.8 Codes-barres + circuit validation
- [ ] Colonne `barcode` sur products + recherche par CB
- [ ] `validation_status` sur documents : draft/validated/transformed

### 2.9 Frais de port + facturation périodique avancée
- [ ] Ligne spéciale "port" (compte 624/708) + calcul auto
- [ ] Table `recurring_invoice_templates` + génération auto

### 2.10 Prospects (séparés des clients)
- [ ] Table `prospects` + `ProspectsPage.tsx` + conversion en client

### 2.11 Import tarifs fournisseurs + cadencier
- [ ] `SupplierPriceImportPage.tsx` + multi-tarifs fournisseurs
- [ ] Table `delivery_schedules` + `DeliverySchedulePage.tsx`

### 2.12 Articles substitution + reliquats
- [ ] Table `product_substitutes` + proposition auto rupture
- [ ] Colonne `delivered_quantity` vs `ordered_quantity` + liste reliquats

### 2.13 Personnalisation documents
- [ ] `DocumentTemplatesPage.tsx` — logo, couleurs, mise en page, aperçu PDF

### 2.14 290 rapports standards + listes avancées
- [ ] Rapports : marge par catégorie, simulation CA, évolution mensuelle
- [ ] Filtres sauvegardables + tris dynamiques

---

## Phase 3 — Trésorerie 100% (50% → 100%)

### 3.1 Mouvements Comptables Futurs (MCF)
- [ ] Table `future_accounting_movements` + `MCFPage.tsx` + incorporation auto

### 3.2 Virements de trésorerie
- [ ] `TreasuryTransfersPage.tsx` — équilibrage entre comptes + écritures auto

### 3.3 Gestion financements + placements/OPCVM
- [ ] Table `credit_lines` + `CreditLinesPage.tsx` (taux, intérêts)
- [ ] Table `investments` + `InvestmentsPage.tsx` (portefeuille)

### 3.4 Pointage prévu/réalisé + ticket d'agios
- [ ] Colonnes prévu/réalisé/écart dans `TreasuryForecastPage.tsx`
- [ ] `AgiosReportPage.tsx` — extraction frais bancaires

### 3.5 Consolidation multi-sociétés
- [ ] `ConsolidatedTreasuryPage.tsx` — agrégation multi-tenants

### 3.6 Conditions de valeur + abonnements trésorerie
- [ ] `ValueDateTrackingPage.tsx` — dates valeur vs opération
- [ ] Table `treasury_recurring` — prévisions récurrentes

### 3.7 Bibliothèque d'états
- [ ] États : activité bancaire, situation nette, synthèse jour + export Excel

---

## Phase 4 — Paie & RH 100% (45% → 100%)

### 4.1 Calcul de paie réel
- [ ] Tables `payroll_components` + `payroll_component_rates` (taux employeur/employé, plafonds)
- [ ] Moteur : brut → cotisations → net imposable → PAS → net à payer
- [ ] Modifier `PaySlipsPage.tsx` : calcul réel

### 4.2 Modèles de bulletins + calcul à l'envers
- [ ] Table `payroll_templates` (cadre/non-cadre/apprenti) + `PayrollTemplatesPage.tsx`
- [ ] `reverseCalculatePay()` — net souhaité → brut

### 4.3 Acomptes + rappel salaires (rétroactivité)
- [ ] Table `salary_advances` + `SalaryAdvancesPage.tsx` (déduction auto)
- [ ] `PayRecallPage.tsx` — rappels rétroactifs

### 4.4 DSN — Production et télétransmission
- [ ] Génération XML DSN + `DSNDeclarationPage.tsx` + télétransmission

### 4.5 DPAE + DADS-U + DUCS + AED + BTP
- [ ] `DPAEPage.tsx` — déclaration préalable embauche
- [ ] Onglets par type dans `LegalDeclarationsPage.tsx`

### 4.6 Pénibilité + carrières + sortie salarié
- [ ] Table `work_hardship` + `career_history` (position, department, salary)
- [ ] `EmployeeExitPage.tsx` — solde de tout compte + certificat

### 4.7 CPF + archivage 10 ans + veille juridique
- [ ] Table `cpf_account` (balance_hours, history)
- [ ] `PayrollArchivePage.tsx` — archivage chiffré
- [ ] `LegalWatchPage.tsx` — actualités légales

### 4.8 Passation comptable CSV + Connect Import
- [ ] Export OD paie CSV ordonnancé
- [ ] `HRDataImportPage.tsx` — import données variables (mapping IA)

---

## Phase 5 — Immobilisations 100% (35% → 100%)

- [ ] **Plans multiples** : Table `asset_depreciation_plans` (économique/fiscal/dérogatoire) + calculs auto
- [ ] **Création depuis écritures** : `AssetFromEntryPage.tsx` — relecture comptes 2
- [ ] **Familles** : Table `asset_families` + `AssetFamiliesPage.tsx`
- [ ] **Immos rattachées** : Colonne `parent_asset_id` + cessions simultanées
- [ ] **Fractionnement** : `splitAsset()` — division en composants
- [ ] **Crédit-bail/leasing** : Colonne `asset_type` + état des engagements
- [ ] **Cessions en rafale** : `BatchDisposalPage.tsx` — plus-values/moins-values auto
- [ ] **Réévaluation** : `AssetRevaluationPage.tsx`
- [ ] **Révision plan** : Modification durée/valeur + recalcul auto
- [ ] **Transfert liasse fiscale** : Génération feuillets 2054/2055/2059
- [ ] **64 champs libres** + 10 champs statistiques + documents attachés
- [ ] **États** : immobilisations, amortissements, acquisitions, sorties, TVS, contrôle dotations
- [ ] i18n `accounting:assets.*` (toutes sous-clés)

---

## Phase 6 — Moyens de Paiement 100% (20% → 100%)

- [ ] **Génération XML SEPA** : `lib/sepaGenerator.ts` — pain.001 (virements) + pain.008 (prélèvements)
- [ ] **Gestion mandats SEPA** : Table `sepa_mandates` (RUM, status, signed_at, revoked_at)
- [ ] **Virements instantanés** : Option `instant` dans pain.001
- [ ] **LCR/BOR** : Génération format CFONB
- [ ] **Adresses structurées ISO 20022** : Validation format adresse dans virements
- [ ] **Lots pré-établis** : Groupement de virements/prélèvements en lot
- [ ] **Relevés Camt.054** : Import et traitement
- [ ] **Email auto tiers** : Notification lors transmission remise
- [ ] **Tiers payeurs** : Table `third_party_payers` (tiers qui paie pour un autre)
- [ ] i18n `treasury:payments.*` (toutes sous-clés)

---

## Phase 7 — Recouvrement 100% (30% → 100%)

- [ ] **Scoring mauvais payeurs** : Algorithme basé sur historique de paiement
- [ ] **Scénarios de relance automatisés** : Table `collection_scenarios` (étapes R1-R5, canaux)
- [ ] **Relance multicanal** : Email + courrier + téléphone (intégration email API)
- [ ] **Promesses de paiement** : Table `payment_promises` (amount, expected_date, status)
- [ ] **DSO** : Calcul automatique Days Sales Outstanding
- [ ] **Cash reporting quotidien** : Email automatique avec situation du jour
- [ ] **Gestion litiges** : Table `collection_disputes` (motif, niveau client/pièce)
- [ ] **Objectif cash** : Pilotage prévisionnel vs objectif
- [ ] **Collaboration multi-acteurs** : Accès DAF/commercial/direction
- [ ] **Relance en masse par scénario** + **seuil minimum par pièce**
- [ ] **Multi-contacts** : Table `customer_contacts` (plusieurs contacts par client)
- [ ] i18n `treasury:collection.*` (toutes sous-clés)

---

## Phase 8 — ECF & Liasse Fiscale 100% (50% → 100%)

- [ ] **Liasse fiscale** : Génération feuillets 2050/2054/2055/2058/2059
- [ ] **Assistant norme ANC 2025** : Ajout nouveaux comptes, mise en sommeil, comparatif
- [ ] **Rubriques états** : Table `financial_statement_lines` (account_code → rubrique)
- [ ] **Édition type Cerfa** : PDF conforme au millésime en cours
- [ ] **Lien direct balance/interrogation** : Navigation état → détail écritures
- [ ] **Configurable par société** : Modèles spécifiques par tenant
- [ ] i18n `reports:fiscal.*` (toutes sous-clés)

---

## Phase 9 — BI Reporting 100% (25% → 100%)

- [ ] **Bibliothèque rapports standards** : 50+ rapports prêts à l'emploi
- [ ] **Tableaux de bord dynamiques** : KPIs temps réel par fonction (ventes, achats, trésorerie, RH)
- [ ] **Export Excel avancé** : Connexion temps réel via API
- [ ] **IA Sage Copilot-like** : Analyse anomalies, suggestions, questions en langage naturel
- [ ] **Planification rapports** : Envoi automatique planifié
- [ ] **Visualisation avancée** : Graphiques, tableaux croisés, indicateurs
- [ ] i18n `reports:bi.*` (toutes sous-clés)

---

## Phase 10 — Automatisation Comptable (ACS) 100% (10% → 100%)

- [ ] **OCR réel** : Intégration API OCR (Tesseract ou cloud) au lieu de simulation
- [ ] **Collecte multi-canal** : Upload + email dédié + SFTP + mobile photo
- [ ] **Extraction automatique** : Montants, TVA, IBAN, SIREN, lignes détaillées
- [ ] **Contrôles** : Vérification IBAN vs fiche fournisseur + détection doublons + cohérence montants
- [ ] **Circuits validation** : Table `invoice_workflows` (jusqu'à 10 étapes, règles par montant/service)
- [ ] **Bon à payer** : Validation avant paiement + traçabilité + relances auto
- [ ] **Validation mobile** : PWA pour valider depuis mobile
- [ ] **Archivage fiscal** : Espace sécurisé + moteur de recherche
- [ ] **Demandes d'achat** : Cycle complet demande → commande → réception → facture
- [ ] **Connecteurs Stripe/PayPal** : Import automatique règlements
- [ ] i18n `purchases:automation.*` (toutes sous-clés)

---

## Phase 11 — Facture Électronique & Sage Network

- [ ] **Génération Factur-X** : PDF avec XML intégré (format mixte)
- [ ] **Génération UBL** : Format XML structuré
- [ ] **Génération CII** : Format XML européen
- [ ] **Annuaire fournisseurs/clients** : Table `edi_directory` (SIREN, platform, status)
- [ ] **Envoi factures électroniques** : API plateforme (PDP ou partenaire)
- [ ] **Réception factures électroniques** : Import auto + intégration comptable
- [ ] **Traçabilité** : Statuts (déposée, rejetée, validée, encaissée)
- [ ] **E-reporting TVA** : Extraction auto données TVA → administration
- [ ] i18n `sales:efacture.*` + `purchases:efacture.*`

---

## Phase 12 — CRM Force de Vente

- [ ] Table `crm_contacts` + `crm_opportunities` + `crm_activities`
- [ ] `CRMContactsPage.tsx` — gestion contacts/prospects
- [ ] `CRMOpportunitiesPage.tsx` — pipeline (étapes, probabilités, prévisionnel)
- [ ] `CRMCampaignsPage.tsx` — campagnes marketing + e-mailing + ROI
- [ ] `CRMAgendaPage.tsx` — agendas partagés + journées de travail
- [ ] Rapports : prévisions ventes, activité par commercial, concurrence
- [ ] i18n `sales:crm.*`

---

## Phase 13 — CRM Service Client

- [ ] Table `support_tickets` + `kb_articles` + `service_contracts`
- [ ] `SupportTicketsPage.tsx` — tickets (priorité, SLA, escalade, assignation)
- [ ] `KnowledgeBasePage.tsx` — articles + recherche full-text
- [ ] `ServiceContractsPage.tsx` — contrats maintenance + alertes renouvellement
- [ ] Portail client (extranet) — création/suivi tickets en self-service
- [ ] i18n `sales:support.*`

---

## Phase 14 — Démat RH & Espace Employés

- [ ] **Coffre-fort bulletins** : Table `employee_documents` (type, file_url, distributed_at)
- [ ] **Distribution auto** : Dépôt bulletins dans coffres-forts salariés
- [ ] **e-signature** : Signature électronique documents RH
- [ ] **Self-service congés** : Améliorer `LeaveRequestsPage.tsx` (planning, soldes, validation manager)
- [ ] **Notes de frais** : Table `expense_reports` + `ExpenseReportPage.tsx` (OCR, TVA, workflow)
- [ ] **Entretiens & objectifs** : Table `interviews` + `InterviewsPage.tsx`
- [ ] **Dossier salarié self-service** : Employé modifie ses infos (avec validation RH)
- [ ] **Synchro calendrier** : O365 / Google Calendar pour congés
- [ ] i18n `hr:demat.*` + `hr:self_service.*`

---

## Phase 15 — i18n : Finalisation trilingue

> Voir `PLAN-I18N-TRILINGUE.md` pour le plan détaillé.

- [ ] Phase 0 i18n : Infrastructure (i18next, 36 fichiers JSON squelettes)
- [ ] Phase 1 i18n : Extraction clés FR (12 agents parallèles, ~3000-5000 clés)
- [ ] Phase 1b i18n : Traduction EN + AR (3 agents)
- [ ] Phase 2 i18n : Refactoring pages (remplacer strings par `t()`)
- [ ] Phase 3 i18n : QA FR/EN/AR + RTL + cohérence
- [ ] Toutes nouvelles pages des Phases 1-14 doivent utiliser `useTranslation()` dès la création

---

## Synthèse & Priorisation

### Ordre d'exécution recommandé

| Priorité | Phase | Effort | Impact |
|---|---|---|---|
| 🔴 P0 | Phase 0 — Législation multi-pays | Moyen | Bloquant pour i18n |
| 🔴 P0 | Phase 1 — Comptabilité 100% | Élevé | Cœur du produit |
| 🔴 P0 | Phase 2 — GesCom 100% | Élevé | Différenciation |
| 🟠 P1 | Phase 3 — Trésorerie 100% | Moyen | Critique PME |
| 🟠 P1 | Phase 4 — Paie & RH 100% | Élevé | Conformité légale |
| 🟠 P1 | Phase 6 — Moyens Paiement 100% | Moyen | SEPA obligatoire |
| 🟡 P2 | Phase 5 — Immobilisations 100% | Moyen | Clôture annuelle |
| 🟡 P2 | Phase 7 — Recouvrement 100% | Moyen | Trésorerie |
| 🟡 P2 | Phase 8 — ECF 100% | Moyen | Conformité fiscale |
| 🟡 P2 | Phase 11 — Facture électronique | Moyen | Obligation 2026 |
| 🟢 P3 | Phase 9 — BI Reporting | Faible | Nice to have |
| 🟢 P3 | Phase 10 — ACS 100% | Élevé | Productivité |
| 🟢 P3 | Phase 12-13 — CRM | Moyen | Extension |
| 🟢 P3 | Phase 14 — Démat RH | Moyen | Extension |
| 🔵 P4 | Phase 15 — i18n finalisation | Élevé | Transversal |

### Estimation volume

| Type | Quantité estimée |
|---|---|
| Nouvelles tables SQL | ~40 |
| Nouvelles pages React | ~60 |
| Modifications pages existantes | ~30 |
| Nouvelles fonctions queries.ts | ~150 |
| Clés i18n (FR+EN+AR) | ~5000 |
| Nouveaux fichiers JSON i18n | 36 |
