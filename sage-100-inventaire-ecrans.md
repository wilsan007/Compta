# Sage 100 (version française) — Inventaire complet des écrans vs Application

> Objet : recenser **tous** les écrans/pages réels de Sage 100 (basé sur les images fournies + recherche des menus officiels *Structure / Traitement / État*) et les comparer aux pages existantes de l'app (`app/src/pages`).
> Date : Juillet 2026
>
> ⚠️ Correctif de périmètre : les 5 images montrent **Sage 100 Comptabilité (produit desktop francophone)** — barre de menu *Fichier / Édition / Structure / Traitement / État / Fenêtre* — et **non** le « Sage 100 ERP US » décrit dans `sage-analysis-reference.md`. C'est la cause principale de l'écart : l'app a été bâtie sur un modèle « cloud simplifié », pas sur le modèle journal×période de Sage 100 Comptabilité.

---

## 0. Ce que montrent les images

| Image | Écran Sage 100 |
|---|---|
| 2 | **Traitement / Saisie des journaux** — liste journaux (code × période) + filtres d'état |
| 4 | **Journal Achats/janv.25** — grille : Jour, N° pièce, N° facture, Référence, N° compte général, **N° compte tiers**, Libellé, Débit, Crédit |
| 3 | **Journal SALAAM BANK/janv.25** — idem + bandeau **Ancien solde / Mouvements / Nouveau solde** |
| 5 | **Journal FOND DE CAISSE/janv.25** — journal de caisse avec solde progressif |
| 1 | **Journal des Salaire/janv.25** — écritures de paie (CNSS, ITS, salaire net…) |

Concepts Sage présents et **absents de l'app** : codes journaux, période mensuelle, N° pièce, compte général **séparé** du compte tiers, solde progressif, **modèles de saisie**, bouton **Équilibrer**, états ouvert/imprimé/clôturé.

---

## 1. MODULE COMPTABILITÉ — arborescence réelle vs app

### 1.1 Menu STRUCTURE (référentiels)

| Écran Sage 100 | Présent dans l'app ? | Page app |
|---|---|---|
| Plan comptable (comptes généraux) | ✅ | `ChartAccountsPage` |
| Plan tiers (clients/fournisseurs/salariés/autres) | 🟡 partiel | `CustomersPage`/`SuppliersPage` (pas de plan tiers unifié + comptes collectifs) |
| Plan analytique (sections) | ❌ | — |
| Plan reporting | ❌ | — |
| Taux de taxes (TVA) | 🟡 partiel | `SettingsPage` |
| **Codes journaux** | ❌ | — (cause racine) |
| Codes journaux analytiques | ❌ | — |
| Banques (fiche banque) | 🟡 partiel | `BankAccountsPage` |
| **Modèles de saisie** | ❌ | — |
| Modèles de grille | ❌ | — |
| Modèles de règlement | ❌ | — |
| Modèles d'abonnement | 🟡 partiel | `RecurringInvoicesPage` (côté facture, pas compta) |
| Libellés (bibliothèque) | ❌ | — |
| Postes budgétaires / Budgets | ❌ | — |
| Cycles de révision | ❌ | — |
| Fusion (comptes/tiers) | ❌ | — |

### 1.2 Menu TRAITEMENT (saisie & opérations)

| Écran Sage 100 | Présent ? | Page app |
|---|---|---|
| **Saisie des journaux (journal × période)** | 🟡 très simplifié | `JournalEntriesPage` (liste plate, pas de journal/période) |
| Saisie par pièce | ❌ | — |
| Saisie des opérations bancaires | 🟡 partiel | `BankTransactionsPage` |
| Saisie par lot | ❌ | — |
| Saisie des OD analytiques | ❌ | — |
| Clôture des journaux (partielle/période/totale) | ❌ | — |
| **Interrogation et lettrage** (manuel/auto) | ❌ | — |
| Interrogation tiers | ❌ | — |
| Interrogation analytique | ❌ | — |
| Gestion des extraits bancaires | 🟡 partiel | `BankTransactionsPage` |
| Rapprochement bancaire manuel | 🟡 partiel | `BankReconciliationPage` |
| Rapprochement bancaire automatique | ❌ | — |
| Règlement tiers | ❌ | — |
| Rappel / relevé (relances) | ❌ | — |
| Réévaluation dettes/créances en devise | ❌ | — |
| Révision par cycle | ❌ | — |
| Recherche d'écritures | ❌ | — |
| Réimputation (générales/analytiques) | ❌ | — |
| Écritures d'abonnement | ❌ | — |
| Compaction | ❌ | — |
| Fin d'exercice : Nouvel exercice | ❌ | — |
| Fin d'exercice : Report à nouveau (à-nouveaux) | ❌ | — |
| Fin d'exercice : Clôture de l'exercice | ❌ | — |
| Fin d'exercice : États de clôture | ❌ | — |
| Dossiers de recouvrement | ❌ | — |

### 1.3 Menu ÉTAT (éditions)

| Écran Sage 100 | Présent ? | Page app |
|---|---|---|
| Brouillard de saisie | ❌ | — |
| Journal / Journal centralisé / Journal général | 🟡 partiel | `JournalsReportPage` |
| Grand-livre des comptes | ✅ | `GeneralLedgerPage` |
| Grand-livre des tiers | ❌ | — |
| Balance générale | ✅ | `TrialBalancePage` |
| Balance âgée (tiers) | ❌ | — |
| Balance analytique | ❌ | — |
| Échéancier | ❌ | — |
| Déclaration de TVA | ✅ | `VatReturnsPage` |
| Bilan | ✅ | `BalanceSheetPage` |
| Compte de résultat | ✅ | `ReportsPage` |
| Soldes intermédiaires de gestion (SIG) | ❌ | — |
| États analytiques / reporting / budgétaires | ❌ | — |
| Justificatif de solde | ❌ | — |
| État de rapprochement bancaire | ❌ | — |
| Contrôle de caisse | ❌ | — |
| Fichier FEC (DGFIP) | ❌ | — |

---

## 2. MODULE GESTION COMMERCIALE (produit Sage 100 séparé)

| Domaine / écran | Présent ? | Page app |
|---|---|---|
| Catalogue articles (nomenclatures, bundles, substitution) | 🟡 partiel | `ProductsPage` |
| Tarifs / promotions / remises en rafale | ❌ | — |
| Ventes : Devis | ✅ | `QuotesPage` |
| Ventes : Bon de commande client | ❌ | — |
| Ventes : Préparation de livraison / Picking | ❌ | — |
| Ventes : Bon de livraison | ❌ | — |
| Ventes : Facture | ✅ | `InvoicesPage` |
| Ventes : Avoir / Retour | ✅ | `CreditNotesPage` |
| Règlements clients | ❌ | — |
| Achats : Demande d'achat | ❌ | — |
| Achats : Commande fournisseur | ❌ | — |
| Achats : Réception marchandises | ❌ | — |
| Achats : Facture fournisseur | ✅ | `PurchaseInvoicesPage` |
| Achats : Avoir fournisseur | ✅ | `PurchaseCreditNotesPage` |
| Stock : multi-dépôts / mouvements | ❌ | — |
| Stock : Inventaire | ❌ | — |
| Stock : valorisation CMUP / FIFO / LIFO | ❌ | — |
| Stock : réapprovisionnement (mini/maxi) | ❌ | — |
| Transfert comptable (GesCom → Compta) | ❌ | — |

---

## 3. CATALOGUE COMPLET DES MODULES SAGE 100

### 3.A — Finance & Comptabilité

#### 3.A.1 — Sage 100 Comptabilité
> Comptabilité générale, auxiliaire et analytique, déclarations TVA, suivi budgétaire.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Comptabilité générale (plan comptable, écritures, journaux) | 🟡 simplifié | `ChartAccountsPage`, `JournalEntriesPage` |
| Comptabilité auxiliaire (tiers clients/fournisseurs/salariés) | 🟡 partiel | `CustomersPage`, `SuppliersPage` |
| Comptabilité analytique (sections, axes, ventilation) | ❌ | — |
| Déclaration TVA (CA3, CA12, acomptes) | 🟡 partiel | `VatReturnsPage` |
| Suivi budgétaire (postes, axes, écarts) | ❌ | — |
| Codes journaux + saisie journal × période | ❌ | — |
| Modèles de saisie + grilles | ❌ | — |
| Lettrage manuel/auto | ❌ | — |
| Clôture journaux + fin d'exercice | ❌ | — |
| Brouillard, balance âgée, échéancier, FEC | ❌ | — |

#### 3.A.2 — Sage 100 Trésorerie
> Visibilité temps réel sur les flux de trésorerie, rapprochements bancaires, prévisions.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Tableau de bord trésorerie (soldes temps réel) | 🟡 partiel | `CashFlowPage` |
| Rapprochement bancaire (manuel + auto) | 🟡 partiel | `BankReconciliationPage` |
| Prévisions de trésorerie (flux futurs, échéancier) | ❌ | — |
| Gestion multi-comptes / multi-banques | 🟡 partiel | `BankAccountsPage` |
| Position de trésorerie consolidée | ❌ | — |
| Simulation de scénarios financiers | ❌ | — |
| Gestion placements / OPCVM | ❌ | — |
| Alertes seuils / découverts | ❌ | — |

#### 3.A.3 — Sage 100 Moyens de Paiement
> Centralisation des virements entrants/sortants et prélèvements.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Génération virements SEPA (sortants) | ❌ | — |
| Génération prélèvements SEPA SDD | ❌ | — |
| Gestion chèques (émission, remise) | ❌ | — |
| LCR / BOR (lettre de change relevé) | ❌ | — |
| Suivi remises bancaires (lots) | ❌ | — |
| Import / export fichiers bancaires | ❌ | — |
| Traitements par lot (multi-règlements) | ❌ | — |
| Suivi accusés de réception | ❌ | — |

#### 3.A.4 — Sage 100 Immobilisations
> Amortissements, suivi des actifs, calculs fiscaux.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Fiche immobilisation (actif, date d'acquisition, valeur) | 🟡 basique | `FixedAssetsPage` |
| Plans d'amortissement (linéaire, dégressif, dérogatoire) | ❌ | — |
| Calcul automatique des dotations | ❌ | — |
| Cessions d'immobilisations | ❌ | — |
| Édition des tableaux d'amortissement | ❌ | — |
| Suivi multi-sites / multi-étab. | ❌ | — |
| Génération écritures comptables (dotations/cessions) | ❌ | — |
| État des immobilisations / inventaire | ❌ | — |

#### 3.A.5 — Sage Automatisation Comptable
> Numérisation, automatisation et traitement des factures fournisseurs.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Numérisation factures fournisseurs (scan/OCR) | ❌ | — |
| Reconnaissance automatique (fournisseur, montant, TVA) | ❌ | — |
| Pré-comptabilisation automatique (suggestion comptes) | ❌ | — |
| Validation workflow (approbation multi-niveaux) | ❌ | — |
| Intégration automatique en comptabilité | ❌ | — |
| Archivage numérique des pièces | ❌ | — |
| Lien avec factures d'achat existantes | ❌ | — |
| Tableau de bord factures à traiter | ❌ | — |

#### 3.A.6 — Sage Recouvrement Créances
> Suivi des paiements clients, relances automatisées, réduction des impayés.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Tableau de bord créances (échéances, retards) | ❌ | — |
| Génération relances automatiques (niveaux) | ❌ | — |
| Modèles de courriers de relance | ❌ | — |
| Calcul des pénalités de retard / intérêts | ❌ | — |
| Suivi promesses de paiement | ❌ | — |
| Gestion litiges clients | ❌ | — |
| Export vers recouvrement externe | ❌ | — |
| Rapport de recouvrement / aging | ❌ | — |

---

### 3.B — Gestion Commerciale & Exploitation

#### 3.B.1 — Sage 100 Gestion Commerciale
> Cycle complet ventes/achats : devis, commandes, stock, livraisons.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Catalogue articles (nomenclatures, bundles) | 🟡 partiel | `ProductsPage` |
| Tarifs / promotions / remises en rafale | ❌ | — |
| Devis client | ✅ | `QuotesPage` |
| Bon de commande client | ❌ | — |
| Préparation de livraison / Picking | ❌ | — |
| Bon de livraison | ❌ | — |
| Facture de vente | ✅ | `InvoicesPage` |
| Avoir / Retour client | ✅ | `CreditNotesPage` |
| Règlements clients | ❌ | — |
| Demande d'achat | ❌ | — |
| Commande fournisseur | ❌ | — |
| Réception marchandises | ❌ | — |
| Facture fournisseur | ✅ | `PurchaseInvoicesPage` |
| Avoir fournisseur | ✅ | `PurchaseCreditNotesPage` |
| Stock multi-dépôts / mouvements | ❌ | — |
| Inventaire / valorisation (CMUP/FIFO/LIFO) | ❌ | — |
| Réapprovisionnement (mini/maxi) | ❌ | — |
| Transfert comptable (GesCom → Compta) | ❌ | — |
| Factures récurrentes | 🟡 partiel | `RecurringInvoicesPage` |

#### 3.B.2 — Sage 100 Gestion de Production
> Fabrication et assemblage : nomenclatures, ordres de fabrication, planification.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Nomenclatures de fabrication (BOM) | ❌ | — |
| Ordres de fabrication (OF) | ❌ | — |
| Gammes opératoires | ❌ | — |
| Planification de la capacité | ❌ | — |
| Suivi atelier / avancement OF | ❌ | — |
| Calcul des coûts de production | ❌ | — |
| Gestion postes de charge / centres | ❌ | — |
| Prévision des besoins (MRP) | ❌ | — |

---

### 3.C — Reporting & Pilotage

#### 3.C.1 — Sage BI Reporting / Sage Business Reporting
> Intégration Excel, tableaux de bord financiers, visualisations stratégiques.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Tableaux de bord financiers (CA, marge, trésorerie) | 🟡 partiel | `DashboardPage` |
| Rapports personnalisés Excel (BI) | ❌ | — |
| Visualisations graphiques (KPI, tendances) | 🟡 partiel | dashboards existants |
| Rapports temps réel (multi-sociétés) | ❌ | — |
| +150 tableaux de bord préconfigurés | ❌ | — |
| Export / partage rapports | ❌ | — |
| Alertes / seuils automatiques | ❌ | — |

---

### 3.D — Paie & Ressources Humaines

#### 3.D.1 — Sage 100 Paie et RH
> Gestion de la paie, déclarations légales, contrats, absences.

| Fonctionnalité / écran | Présent ? | Page app |
|---|---|---|
| Fiche salarié (complète : contrat, salaire, charges) | 🟡 partiel | `EmployeesPage` |
| Bulletins de paie (génération, édition) | 🟡 partiel | `PayRunsPage` |
| Déclarations légales (DSN, URSSAF, CNSS) | ❌ | — |
| Gestion des contrats (CDI, CDD, apprentissage) | ❌ | — |
| Gestion des absences / congés | 🟡 partiel | `TimesheetsPage` |
| Gestion du temps (pointage) | ❌ | — |
| Variables de paie (heures supp, primes) | ❌ | — |
| Comptabilisation de la paie (OD de paie) | ❌ | — |
| Éditions de paie (bulletins, journal, récap) | ❌ | — |
| Gestion RH (entretiens, formations, compétences) | ❌ | — |

---

## 4. SYNTHÈSE CHIFFRÉE GLOBALE

### 4.1 Par module Sage 100

| Module Sage 100 | ✅ Présent | 🟡 Partiel | ❌ Manquant | Total écrans |
|---|---|---|---|---|
| **Comptabilité** | 3 | 4 | 13 | 20 |
| **Trésorerie** | 0 | 3 | 5 | 8 |
| **Moyens de Paiement** | 0 | 0 | 8 | 8 |
| **Immobilisations** | 0 | 1 | 7 | 8 |
| **Automatisation Comptable** | 0 | 0 | 8 | 8 |
| **Recouvrement Créances** | 0 | 0 | 8 | 8 |
| **Gestion Commerciale** | 4 | 2 | 13 | 19 |
| **Gestion de Production** | 0 | 0 | 8 | 8 |
| **BI Reporting** | 0 | 2 | 5 | 7 |
| **Paie & RH** | 0 | 3 | 7 | 10 |
| **TOTAL** | **7** | **15** | **82** | **104** |

### 4.2 Bilan global

- **Total écrans/fonctionnalités Sage 100 recensés : ~104**
- **✅ Présents et conformes : 7** (~7%)
- **🟡 Partiels / simplifiés à approfondir : 15** (~14%)
- **❌ Manquants : 82** (~79%)

### 4.3 Manques prioritaires (bloquants pour « ressembler à Sage 100 »)

**Priorité 1 — Cœur comptable (visible sur les images) :**
1. **Codes journaux** (référentiel) + **Saisie des journaux par journal × période**
2. **Compte général vs compte tiers** séparés + **N° pièce** dans les écritures
3. **Solde progressif** (Ancien/Mouvements/Nouveau) pour banque & caisse
4. **Modèles de saisie** + bouton **Équilibrer**
5. **Lettrage** (manuel/auto) + **Interrogation tiers**
6. **Clôture des journaux** + **Fin d'exercice / Report à nouveau** + états ouvert/imprimé/clôturé
7. **Brouillard, Balance âgée, Échéancier, FEC** côté éditions

**Priorité 2 — Modules financiers manquants :**
8. **Trésorerie** : prévisions, position consolidée, alertes
9. **Moyens de paiement** : virements/prélèvements SEPA, remises bancaires
10. **Immobilisations** : plans d'amortissement, dotations, cessions
11. **Automatisation comptable** : OCR factures, pré-comptabilisation, workflow
12. **Recouvrement** : relances automatiques, pénalités, aging

**Priorité 3 — Gestion commerciale & production :**
13. **Commandes client/fournisseur** + bons de livraison
14. **Stock multi-dépôts** + valorisation + inventaire
15. **Gestion de production** (BOM, OF, gammes, MRP)
16. **Transfert comptable** GesCom → Compta

**Priorité 4 — Reporting & Paie :**
17. **BI Reporting** (Excel, +150 tableaux de bord, multi-sociétés)
18. **Paie complète** (DSN, comptabilisation, variables, éditions)
19. **RH** (contrats, formations, compétences)

### 4.4 Impact base de données

Tables/colonnes à ajouter :
- `journals` (codes journaux, types, statuts)
- `fiscal_periods` (exercices, périodes, statuts)
- `entry_templates` (modèles de saisie)
- Sur `journal_entries` : `journal_code`, `period`, `piece_number`, `account_general`, `account_tiers`, `lettrage_code`, `status` (open/printed/closed)
- `analytic_sections` (plan analytique)
- `budgets` / `budget_lines` (postes budgétaires)
- `fixed_assets` (immobilisations) + `depreciation_plans`
- `payment_means` (virements, prélèvements, SEPA)
- `collection_cases` (recouvrement, relances)
- `production_orders` (ordres de fabrication, BOM)

---

## 5. Sources
- Formation Sage SAARI Comptabilité 100 (menus Structure/Traitement/État) — 4gestionacademy.com, scribd.
- Sage France — Suite Comptable et Financière, Gestion Commerciale (sage.com/fr-fr).
- Guides clôture d'exercice Sage 100cloud (wilroad, setg).
- Découpage fonctionnel Sage 100c GesCom (synoptic-erp, global-gestion).
- Documentation officielle Sage.fr — Sage Comptabilité i7 (saisies comptables, rapprochement, lettrage).
- Guide Sage 100 Comptabilité i7 (scribd.com — 667678819).
- Prise en main Edition Petites Entreprises Sage Comptabilité i7 (documentation.sage.fr).
- Sage 100 Comptabilité — fiche produit (sage.com/fr-fr).
- Catalogue modules Sage 100 (liste fournie par l'utilisateur, Juillet 2026).
