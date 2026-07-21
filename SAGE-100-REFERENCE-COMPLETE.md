# Sage 100 — Référence Fonctionnelle Ultra-Détaillée

> **Document de référence complet** couvrant l'ensemble des modules Sage 100 (hors Gestion de Production), leur logique métier, leurs fonctionnalités détaillées, et les évolutions des versions V9 à V12 (2023–2025).
>
> **Date de compilation** : Juillet 2025
> **Sources** : 40+ pages web consultées (toutes récentes, moins d'un an), PDF officiels, documentation Sage, blogs d'intégrateurs certifiés.

---

## Table des matières

1. [Vue d'ensemble de Sage 100](#1-vue-densemble-de-sage-100)
2. [Architecture et modes de déploiement](#2-architecture-et-modes-de-déploiement)
3. [IntuiSage — Interface utilisateur](#3-intuisage--interface-utilisateur)
4. [Module Comptabilité](#4-module-comptabilité)
5. [Module Gestion Commerciale](#5-module-gestion-commerciale)
6. [Module Moyens de Paiement](#6-module-moyens-de-paiement)
7. [Module Trésorerie](#7-module-trésorerie)
8. [Module Immobilisations](#8-module-immobilisations)
9. [Module États Comptables et Fiscaux (ECF)](#9-module-états-comptables-et-fiscaux-ecf)
10. [Module CRM — Force de Vente](#10-module-crm--force-de-vente)
11. [Module CRM — Service Client](#11-module-crm--service-client)
12. [Module Paie & RH](#12-module-paie--rh)
13. [Sage Dématérialisation RH](#13-sage-dématérialisation-rh)
14. [Sage Espace Employés](#14-sage-espace-employés)
15. [Module Recouvrement Créances](#15-module-recouvrement-créances)
16. [Module Saisie de Caisse Décentralisée (SCD)](#16-module-saisie-de-caisse-décentralisée-scd)
17. [Sage BI Reporting & Sage Business Reporting](#17-sage-bi-reporting--sage-business-reporting)
18. [Sage Network, Sage Connect & Facture Électronique](#18-sage-network-sage-connect--facture-électronique)
19. [Sage eFacture](#19-sage-efacture)
20. [Sage Data Clean & Control (SDCC)](#20-sage-data-clean--control-sdcc)
21. [Sage Automatisation Comptable (ACS)](#21-sage-automatisation-comptable-acs)
22. [Objets Métiers, API SData & Interopérabilité](#22-objets-métiers-api-sdata--interopérabilité)
23. [Sage Sales Management](#23-sage-sales-management)
24. [SenSaaS](#24-sensaas)
25. [Clictill](#25-clictill)
26. [Sage EDI](#26-sage-edi)
27. [Sage Flux Bancaires](#27-sage-flux-bancaires)
28. [Stockage & Partage Microsoft 365](#28-stockage--partage-microsoft-365)
29. [Évolutions par version (V9 → V12)](#29-évolutions-par-version-v9--v12)
30. [Logique métier transverse et flux inter-modules](#30-logique-métier-transverse-et-flux-inter-modules)

---

## 1. Vue d'ensemble de Sage 100

Sage 100 est un **ERP modulaire** (Enterprise Resource Planning) destiné aux PME/PMI françaises (30 à 500 employés). Développé par Sage (leader mondial fondé en 1981), il couvre l'ensemble des besoins de gestion d'entreprise.

### Liste complète des modules

| Domaine | Module | Code |
|---|---|---|
| **Finance & Comptabilité** | Comptabilité | CPT |
| | États Comptables et Fiscaux (ECF) | ECF |
| | Immobilisations | IMM |
| | Moyens de Paiement | PAI |
| | Trésorerie | TRE |
| **Commerce & Ventes** | Gestion Commerciale | GC |
| | Saisie de Caisse Décentralisée (SCD) | SCD |
| | CRM Force de Vente | CRM-VTE |
| | CRM Service Client | CRM-SVC |
| | Sage Sales Management | SSM |
| | SenSaaS | SNS |
| | Clictill | CLK |
| **RH** | Paie & RH | PAIE |
| | Dématérialisation RH | DRH |
| | Sage Espace Employés | SEE |
| **Pilotage** | BI Reporting | BIR |
| | Business Reporting | BR |
| | Recouvrement Créances | REC |
| **Dématérialisation** | Sage Network / PA Sage | NET |
| | Sage Connect | CON |
| | Sage eFacture | EFACT |
| | SDCC (Data Clean & Control) | SDCC |
| | ACS (Automatisation Comptable) | ACS |
| | Sage EDI | EDI |
| | Sage Flux Bancaires | SFB |
| | Stockage & Partage M365 | M365 |
| **Technique** | Objets Métiers / SData | OM |

### Logique métier globale

Sage 100 fonctionne comme un **système intégré** où les modules partagent une base de données commune (SQL Server / SQL Express). La logique métier repose sur quatre principes fondamentaux :

1. **Saisie unique** : une information saisie dans un module (ex : une facture en Gestion Commerciale) alimente automatiquement les autres modules concernés (Comptabilité, Trésorerie, Moyens de Paiement). Aucune ressaisie.
2. **Traçabilité totale** : chaque opération est historisée (création, modification, suppression) avec horodatage et identification utilisateur. Conformité loi anti-fraude.
3. **Conformité légale native** : le logiciel intègre les obligations françaises (FEC, TVA, loi anti-fraude, RGPD, réforme facture électronique 2026, norme ANC 2025, DSN).
4. **Modularité évolutive** : l'entreprise démarre avec les modules nécessaires et ajoute des modules au fur et à mesure de sa croissance, sans rupture de données.

---

## 2. Architecture et modes de déploiement

### Trois modes de déploiement

| Mode | Description | Infrastructure | Avantages |
|---|---|---|---|
| **On-Premise** | Installé sur les serveurs de l'entreprise | SQL Server / SQL Express, Windows Server | Contrôle total, sécurité interne |
| **Hébergée SPC** | Sage Partner Cloud — hébergé par Sage sur Microsoft Azure | SQL Azure, accès à distance | Aucune maintenance infrastructure, accès 24/7 |
| **Hébergée Online** | Ancienne offre (migration progressive vers SPC) | Migration en cours | Transition vers SPC |

### Base de données

- **SGBD** : Microsoft SQL Server (Standard) ou SQL Server Express (gratuit, limité en taille)
- **Multi-sociétés** : jusqu'à 15 sociétés en Standard, illimité en Premium
- **Multi-devises** : jusqu'à 32 devises gérées simultanément
- **Exercices consultables** : 5 exercices (V11 et antérieures), **10 exercices (V12)**
- **Niveaux d'offre** : Essentials, Standard, Premium (fonctionnalités croissantes)

### Compatibilité et pré-requis

- **Système** : Windows 7 / 8 / 8.1 / 10 / 11 (client), Windows Server (serveur)
- **Navigateur** : IntuiSage accessible via navigateur web
- **Mobile** : Applications iOS et Android pour CRM, Espace Employés, Clictill, Sage Sales Management
- **Microsoft 365** : Intégration SharePoint/OneDrive pour stockage de documents
- **Versions compatibles facture électronique** : V11 et supérieures pour Sage Network

---

## 3. IntuiSage — Interface utilisateur

IntuiSage est l'**interface d'accueil et de navigation** de Sage 100, présente dans tous les modules. Elle s'affiche en fond d'écran sous forme de tuiles/icônes.

### Structure

| Onglet | Fonction |
|---|---|
| **Accueil** | Fonctions essentielles au démarrage, actualités légales, indicateurs de gestion |
| **Favoris** | Organisation personnalisée des fonctions favorites par utilisateur |
| **Sage Connect** | Vidéos Sage, accès documentation, services en ligne, réseaux sociaux |

### Fonctionnalités clés

- **Indicateurs de gestion** : tableau de bord personnalisé avec KPIs en temps réel (CA, encours clients/fournisseurs, trésorerie)
- **Personnalisation par profil** : chaque utilisateur (comptable, commercial, dirigeant) organise ses favoris selon son métier
- **Actualités légales intégrées** : veille réglementaire (TVA, facture électronique, RGPD, normes ANC)
- **Tuile "Inscription PDP Sage"** (V12) : accès direct à l'inscription à la Plateforme Agréée Sage
- **Tuile "Nouveautés"** (V12) : accès direct à la documentation de version

### Évolution par version

- **V11** : IntuiSage introduit avec interface modernisée, tableaux de bord redessinés, navigation plus intuitive
- **V12** : Ajout des tuiles spécifiques pour la facture électronique (PA Sage), amélioration de l'ergonomie

### Logique métier

IntuiSage sert de **point d'entrée unique** vers tous les modules. Il guide l'utilisateur vers les actions prioritaires du jour (relances à effectuer, écritures à lettrer, extraits bancaires à intégrer). La personnalisation par profil permet à chaque utilisateur de voir uniquement ce qui le concerne, améliorant l'efficacité et réduisant le bruit visuel.

---

## 4. Module Comptabilité

### 4.1 Vue d'ensemble

Sage 100 Comptabilité est le **cœur financier** de l'ERP. Il gère la comptabilité générale, auxiliaire, analytique et budgétaire. C'est le module central vers lequel convergent tous les flux des autres modules.

### 4.2 Fonctionnalités détaillées

#### Saisie et productivité

- **Modèles d'écritures paramétrables** : création de modèles récurrents pour accélérer la saisie
- **Saisie par lot** avec indicateur de productivité en temps réel
- **Calculatrice intégrée** : saisie d'opérations directement dans les zones de montant (ex : `=1250*1.2` puis Tabulation)
- **Automatismes de saisie** : calcul automatique des échéances et de la TVA
- **Protection des journaux** par droits d'accès (un utilisateur ne peut saisir que dans les journaux autorisés)
- **Écritures d'abonnement** : génération automatique d'écritures récurrentes (loyers, assurances, abonnements)
- **Écritures de régularisation** : génération et extourne de fin d'exercice (charges constatées d'avance, produits constatés d'avance)

#### Comptabilité générale

- **Plan comptable adaptable** : personnalisation des comptes, création de comptes à la volée
- **Gestion multi-journaux** : journaux d'achats, ventes, banque, OD, etc.
- **Recherche d'écritures inter-exercices** : navigation rapide entre exercices
- **États généraux** : grand livre, balance, bilan, compte de résultat
- **Affichage des soldes dans les listes** (V9+) : visualisation immédiate des comptes nécessitant une intervention
- **Solde progressif** dans l'interrogation tiers : détection d'anomalies

#### Comptabilité auxiliaire (Tiers)

- **Gestion des tiers** : multi-collectifs, multi-échéances, multi-RIB, multi-modes de règlements
- **Lettrage / Pré-lettrage** manuel et automatique : rapprochement des factures avec leurs règlements
- **Bon à payer** : validation des factures fournisseurs avant règlement
- **Rapport des délais de paiement** : analyse du respect des conditions par client/fournisseur
- **Gestion délai maximum échéance** : contrôle des échéances dépassées
- **Réévaluation des dettes et créances en devises** : ajustement des écarts de change
- **Rappels, relevés et relances préventives** : édition automatique avec personnalisation des mails
- **Relances avec liens de paiement en ligne** : intégration PayPal ou Stripe
- **Paiement en ligne** : encaissement direct depuis la relance
- **Champs statistiques tiers** : analyse sectorielle, géographique

#### Comptabilité analytique

- **Jusqu'à 11 plans analytiques** (Premium) / 2 plans (Standard)
- **Multi-ventilations analytiques** : un montant peut être ventilé sur plusieurs sections
- **Pré-ventilation des comptes par grilles** : ventilation automatique selon des règles paramétrées
- **Report analytique par nature de comptes** : reports automatiques entre exercices
- **Balance analytique** : états analytiques détaillés

#### Gestion budgétaire

- **Suivi des prévisions et des réalisations** : comparaison budget vs réel
- **États budgétaires** : tableaux de suivi des écarts

#### TVA

- **TVA multi-taux, multi-régimes** via les registres taxes
- **Gestion de la TVA encaissement / débit** : selon le régime de l'entreprise
- **Télé-déclaration de TVA** incluse (EDI-TVA)
- **Gestion automatisée de la TVA sur les acomptes** (V9+) : exigibilité dès la comptabilisation de l'acompte
- **Distinction des taxes sur les véhicules de société** (TVS) (V9+)
- **Mise à jour fiscale** : assistants d'actualisation des modèles de TVA

#### Rapprochement bancaire

- **Rapprochement bancaire manuel** : pointage des écritures avec les extraits
- **Rapprochement bancaire automatique** (option) :
  - Incorporation manuelle ou automatique des extraits bancaires
  - Critères de rapprochement élaborés et personnalisables sur les codes AFB
  - Rapprochement automatique sur montant, n° de pièce et n° de facture
  - Critères de puissance de rapprochement et d'écart de date
  - Génération automatique des écritures d'écarts, d'agios
  - Justificatif de rapprochement en partie double
- **Génération des écritures directement à partir des extraits bancaires**
- **Formats supportés** : CFONB 120 (France), MT940 (Suisse), Camt.053 (ISO 20022 XML)
- **Communication bancaire via Sage Direct** et **Sage Flux Bancaires**

#### Conformité et contrôle

- **FEC (Fichier des Écritures Comptables)** : génération et pré-contrôle
- **Sauvegarde fiscale des données** : archivage légal
- **Loi anti-fraude** : journal d'audit des données sécurisées, attestation individuelle
- **RGPD** : fonctions facilitatrices intégrées (gestion des données personnelles, cartographie)
- **Gestion des normes IAS-IFRS** : comptabilité en normes internationales
- **Traçabilité des enregistrements** : historique des créations, modifications et suppressions
  - Écritures comptables : n° compte général, code taxe, n° compte tiers, échéance, sens, montant
  - Lignes de registres taxes : type, date pièce, compte de taxe, taux, base taxable, montant
  - Comptes bancaires société et tiers : code banque, guichet, compte, clé, BIC, IBAN

#### Reporting

- **Plus de 150 tableaux de bord**
- **Bilan, compte de résultat, SIG** personnalisables par société
- **Tableau de bord personnalisé**
- **Grand livre reporting, Balance reporting, États analytiques reporting**
- **Export vers Excel et HTML**

### 4.3 Nouveautés V12 spécifiques

| Fonctionnalité | Description | Logique métier |
|---|---|---|
| **Inscription PA Sage depuis IntuiSage** | Tuile dédiée pour s'inscrire à la Plateforme Agréée Sage | Centralise la réception des factures d'achat et sécurise l'émission des factures de vente |
| **Compte bancaire société par fiche tiers** | Association d'un compte bancaire société par défaut dans chaque fiche client/fournisseur | L'IBAN est automatiquement repris dans les factures électroniques et les échéances |
| **Réception factures fournisseurs (volet écriture)** | Les factures réceptionnées sont saisies en pièce comptable avant approbation ; SDCC propose des schémas comptables par tiers | Supprime l'obligation de modèle de saisie pour les cas simples |
| **10 exercices consultables** (au lieu de 5) | Doublement de la profondeur d'historique | Évite les archivages trop fréquents, facilite les comparatifs pluriannuels |
| **Clôture : messages plus clairs** | Messages d'aide à la compréhension lors des clôtures | Réduit les allers-retours et les blocages de fin de période |
| **Conversions de bases sans "Maintenance"** | Conversion automatique lors de l'ouverture d'une société en version plus récente | Fluidifie les mises à jour (on-premise) |
| **Lettrage plus intuitif et rapide** | Interface de lettrage accélérée | Gain de productivité sur les rapprochements comptables |
| **Filtres de recherche avancés** dans les éditions | Nouveaux critères de filtrage | Gain de temps dans les analyses |
| **Connectivité bancaire optimisée** | Accès plus stable et rapide aux flux bancaires | Fiabilise le rapprochement bancaire |
| **Suivi des règlements amélioré** | Vue consolidée des règlements clients et fournisseurs | Meilleure visibilité sur la trésorerie |
| **Dossiers de recouvrement** (Hébergée/SPC) | Disponibles en option sur l'offre Standard | Démocratise l'accès au recouvrement |

### 4.4 Logique métier de la Comptabilité

La comptabilité est le **point de convergence** de tous les flux financiers :

```
Gestion Commerciale → factures de vente/achat → écritures comptables
Moyens de Paiement → virements/prélèvements → écritures de règlement
Trésorerie → extraits bancaires → rapprochement bancaire
Immobilisations → dotations aux amortissements → écritures de dotation
Paie & RH → écritures de salaires → écritures comptables
```

Le **lettrage** est l'opération centrale : il consiste à associer une facture (écriture de vente/achat) avec son règlement (écriture de banque) pour marquer la créance/dette comme soldée. Un compte tiers non lettré indique une créance ou une dette non réglée.

Le **rapprochement bancaire** assure que les écritures comptables correspondent aux mouvements réels sur le compte bancaire. Les écarts (agios, frais, erreurs) sont détectés et corrigés.

---

## 5. Module Gestion Commerciale

### 5.1 Vue d'ensemble

Sage 100 Gestion Commerciale pilote l'**ensemble du cycle commercial** : du devis à la facturation, en passant par les achats, les stocks et la livraison. C'est le module le plus utilisé après la Comptabilité.

### 5.2 Cycle commercial complet

```
Prospect → Devis → Commande → Bon de livraison → Facture → Avoir (si retour)
                                                         ↓
                                              Mise à jour comptable
```

### 5.3 Fonctionnalités détaillées

#### Gestion des ventes

- **Saisie rapide des documents commerciaux** : multiples contrôles et calculs automatiques
- **Identification des articles** par référence fournisseur ou code-barres
- **Transformation sans ressaisie** des pièces commerciales : devis → commande → livraison → facture → avoir
- **Application automatique des tarifs personnalisés** : remises, rabais, promotions, soldes
- **Création d'articles ou de tiers à la volée** pendant la saisie de documents
- **Saisie multi-articles** : traitement de toutes les typologies (unitaires, bundles, nomenclatures, ressources, conditionnements)
- **Frais d'approche et de port** intégrés aux opérations
- **Facturation périodique** (abonnements, contrats récurrents)
- **Facture d'acompte** (V9+) : création d'acomptes avec TVA
- **Gestion des représentants et du commissionnement**
- **Gestion des codes-barres**
- **Circuit de validation des pièces** avec statuts (V8+) : brouillon, validé, transformé
- **Personnalisation du bouton "Action"** (V8+) pour productivité accrue
- **Catégorie comptable modifiable** (V8+) : souplesse de gestion
- **Contrôle de la transformation d'une facture en avoir ou retour** (V8+)

#### Gestion des clients (Tiers)

- **Création illimitée de fiches tiers**
- **Contrôle des encours** et restrictions en cas de dépassement
- **Historique client** complet : coordonnées, conditions tarifaires, historique des achats/ventes, encours, relances
- **Interrogation client** : accès rapide aux informations détaillées
- **Gestion des prospects** : fichiers prospects séparés des clients
- **Rappels et relances** préventives
- **Affichage des encours tiers** dans les listes fournisseurs et clients (V9+)
- **Paramétrage d'envoi par email** par tiers et par type de document (V9+)

#### Gestion des achats et relations fournisseurs

- **Chaîne complète des documents d'achats** : demandes d'achats → commandes → réceptions → factures fournisseurs
- **Calcul automatique des prix d'achat** : CMUP, FIFO, LIFO
- **Import des tarifs fournisseurs** et gestion de plusieurs références par article
- **Gestion de la contremarque**
- **Multi-tarifs fournisseurs** : négociation des meilleurs tarifs
- **Cadencier de livraison** : planning des livraisons fournisseurs
- **Gestion des réceptions marchandises** fournisseurs
- **Niveau de criticité des réapprovisionnements** dans la fiche Article (V8+)
- **Traitement par lot des réapprovisionnements**
- **Prévisions de réapprovisionnement** : commandes en juste-à-temps
- **Proposition d'articles de substitution** en cas de rupture de stock

#### Gestion des stocks

- **Mouvements d'entrée et de sortie** : enregistrement immédiat de chaque flux
- **Gestion multi-dépôts** et transfert de dépôt à dépôt
- **Gestion des emplacements** (option Négoce & Industrie)
- **Mini / maxi** : alertes de seuil pour éviter les ruptures
- **Stock dormant** : détection des stocks immobilisés inutilement
- **Interrogation du stock prévisionnel** (V8+) : réactivité sur les demandes clients
- **Gestion des numéros de série et lots** produits : traçabilité complète
- **Gestion des gammes** : tailles et couleurs, longueurs et largeurs, textures et épaisseurs
- **Inventaires et états de stock** : production rapide
- **Contrôle qualité** (option Négoce & Industrie)
- **Picking** (option Négoce & Industrie) : préparation et validation des livraisons clients
- **Frais d'approche, de port ou de stockage** dans le prix de revient des articles
- **Affectation des utilisateurs par dépôt** (V8+) : précision logistique

#### Catalogue articles

- **Base de données personnalisable** : nomenclatures, bundles, articles liés, produits de substitution
- **Paramétrage des prix** en fonction des volumes et des promotions
- **Gestion des conditionnements**
- **Photos, poids, numéros de série** sur les fiches articles
- **Refresh Gamme/Nomenclature sans quitter la fiche** (V9+)

#### Dématérialisation

- **Facture électronique au format Factur-X** (V9+) : PDF avec XML intégré
- **Envoi et réception de factures via Sage Connect / Sage Network**
- **Signature électronique** des documents
- **Paiement sécurisé en ligne**
- **Stockage et partage** de documents de facturation

#### Pilotage et reporting

- **290 rapports standards** avec assistant de génération
- **Tableaux de bord personnalisables** : CA, marge par catégorie tarifaire, représentants, évolution mensuelle
- **Simulation du chiffre d'affaires** avec projections dynamiques
- **Analyse par marges**
- **Gestion des listes avancées** (V8+) : tris/filtres dynamiques, recherche multi-critères, filtres multi-conditions sauvegardables

### 5.4 Nouveautés V12 spécifiques

| Fonctionnalité | Description | Logique métier |
|---|---|---|
| **Inscription PA Sage depuis IntuiSage** | Tuile dédiée côté ventes | Anticipe la réforme facture électronique |
| **Messages d'erreur améliorés** (Sage Network) | Clarification des erreurs de paramétrage | Réduit les appels support |
| **Notification de fin de transmission** | Confirmation visuelle après envoi de factures via Sage Connect | Sécurise l'étape d'envoi |
| **Compte bancaire société "préféré"** dans la fiche tiers | Reprise automatique de l'IBAN dans les factures de vente | Conformité facture électronique |
| **Mise à jour comptable : aide à la correction** | Assistant de diagnostic des erreurs | Accélère la résolution des anomalies |
| **Factures d'acompte en devises** | Reprise du cours de devise à la date de facture | Cohérence comptable des acomptes en devises |
| **Refonte des fiches clients/fournisseurs** | Interface modernisée, plus ergonomique | Meilleure lisibilité et productivité |
| **Personnalisation accrue des documents** | Bons de commande, factures, devis plus intuitifs à personnaliser | Adaptation à l'image de marque |
| **Gestion des reliquats de commande** améliorée | Meilleur suivi des livraisons partielles | Anticipation des réapprovisionnements |

### 5.5 Logique métier de la Gestion Commerciale

Le cycle commercial suit un **flux séquentiel** où chaque document se transforme en document suivant sans ressaisie :

1. **Devis** : proposition commerciale avec statuts (en cours, accepté, refusé). Historique des devis conservé.
2. **Commande** : transformation du devis en bon de commande. Vérification du stock disponible.
3. **Bon de livraison** : préparation (picking) et expédition. Mise à jour du stock en temps réel.
4. **Facture** : génération automatique depuis le bon de livraison. Calcul de la TVA, échéances, encours client.
5. **Avoir** : en cas de retour ou d'erreur, création d'un avoir depuis la facture.

La **mise à jour comptable** transforme ensuite les factures en écritures comptables dans le module Comptabilité. Les contrôles de cohérence (comptes comptables, TVA, échéances) sont effectués à cette étape. En V12, un assistant aide à corriger les erreurs détectées.

Le **stock** est mis à jour en temps réel à chaque mouvement (entrée en réception, sortie en livraison). Le stock prévisionnel intègre les commandes en cours (ventes et achats) pour anticiper les ruptures.

---

## 6. Module Moyens de Paiement

### 6.1 Vue d'ensemble

Sage 100 Moyens de Paiement gère les **flux bancaires sortants** (virements, prélèvements) et entrants (remises de chèques, cartes). Il sécurise les échanges avec les banques et assure la conformité aux normes SEPA.

### 6.2 Fonctionnalités détaillées

#### Modes de paiement gérés

| Mode | Description | Format |
|---|---|---|
| **Chèques** | Émission et remise | Manuel |
| **Carte bleue** | Remises TPE | Manuel |
| **Espèces** | Fond de caisse | Manuel |
| **LCR / BOR** | Lettres de Change Relevé / Bordereau d'Ordre de Remise | CFONB |
| **Virements SEPA** | Nationaux et internationaux | pain.001.001.03 (XML) |
| **Prélèvements SEPA** | SDD (SEPA Direct Debit) | pain.008.001.02 (XML) |
| **Virements instantanés** (V12) | Temps réel 24/7 | pain.001.001.03 + option instant |

#### Gestion des prélèvements SEPA

- **Gestion des mandats** : création, suivi, historique
- **Mandats en lots pré-établis** et **prélèvements réguliers**
- **Sélection des prélèvements sur le type de paiement**
- **Nouvelles sélections en historiques des mandats**
- **Gestion des mandats SEPA Banque de France**

#### Gestion des virements

- **Virements nationaux et internationaux**
- **Lots pré-établis** de virements
- **Génération et transmission de flux EDI**
- **Gestion des relevés d'opérations Camt.054** (format XML ISO 20022)

#### Fonctionnalités avancées

- **Consultation des extraits de comptes** et analyse des soldes bancaires
- **Gestion des tiers payeurs**
- **Génération automatique d'un mail** au tiers lors de la transmission des remises
- **Import / export au format paramétrable** des extraits bancaires
- **Intégration avec Sage Direct** : connecteur bancaire sécurisé
- **Intégration avec Sage Flux Bancaires** : télétransmission EBICS

### 6.3 Nouveautés V12 spécifiques

| Fonctionnalité | Description | Logique métier |
|---|---|---|
| **Virements instantanés SEPA** | Émission de virements en temps réel, 24/7, 365 jours | Règlement en quelques secondes au lieu de 24-48h. Nécessite activation dans le contrat EBICS |
| **Adresses structurées ISO 20022** | Gestion des adresses selon la norme ISO 20022 pour virements SEPA, virements internationaux et prélèvements | Améliore la qualité des échanges bancaires, interopérabilité, validations plus strictes |
| **Intégration fluide avec Sage Direct** | Connecteur bancaire optimisé | Simplifie les envois bancaires |
| **Sécurité renforcée** des transactions | Couche de protection supplémentaire | Prévention des fraudes |
| **Meilleur contrôle des ordres de virement** | Contrôles avancés | Diminue les risques d'erreurs |
| **Conformité native aux formats SEPA** | Formats à jour | Assure la compatibilité bancaire |
| **Compte bancaire société par tiers** | Reprise automatique dans les échéances | Évite les erreurs d'IBAN |

### 6.4 Logique métier

Le module Moyens de Paiement est **interfacé en temps réel** avec la Comptabilité (échéances) et la Trésorerie (soldes bancaires). Le flux est :

```
Comptabilité → échéances fournisseurs/clients → Moyens de Paiement
Moyens de Paiement → virements/prélèvements → flux bancaire (SEPA/CFONB)
Banque → extrait bancaire → Comptabilité (rapprochement) + Trésorerie (suivi)
```

Le **mandat SEPA** est l'élément central du prélèvement : il autorise l'entreprise à prélever sur le compte de son client. Le mandat doit être signé par le débiteur et référencé (RUM — Référence Unique de Mandat). Le module gère le cycle de vie complet : création, première exécution, exécutions ultérieures, révocation.

Le **virement instantané** (V12) permet un transfert en quelques secondes entre comptes bancaires de l'espace SEPA. Il nécessite que la banque de l'entreprise et celle du bénéficiaire supportent ce service. Le format utilisé est pain.001.001.03 avec une option spécifique.

---

## 7. Module Trésorerie

### 7.1 Vue d'ensemble

Sage 100 Trésorerie optimise la **gestion des liquidités** de l'entreprise. Il fournit une vision en temps réel des soldes bancaires, des prévisions et des flux futurs pour anticiper les besoins et réduire les frais financiers.

### 7.2 Fonctionnalités détaillées

#### Suivi quotidien des flux bancaires

- **Récupération en temps réel des échéances** de la Comptabilité
- **Récupération en temps réel des extraits de comptes**
- **Import automatique des extraits bancaires** depuis les comptes
- **Détection automatique des retards de paiement**
- **Alertes sur dépassement d'autorisation de découvert**
- **Suivi des extraits bancaires au jour le jour**
- **Suivi du rapprochement comptable**

#### Prévisions et analyses financières

- **Saisie des prévisions de trésorerie** non encore comptabilisées
- **Soldes en valeur réels, prévisionnels et nets**
- **Synthèse du jour de trésorerie**
- **Situation de trésorerie prévisionnelle**
- **Situation nette**
- **Tableaux de bord consolidés** (agrégation multi-sociétés)
- **Pointage prévu / réalisé** : vérification des prévisions par rapport aux mouvements réels
- **Ticket d'agios** : analyse des frais bancaires
- **Suivi des conditions de valeur**
- **Bibliothèque d'états** : activité bancaire, conditions de valeur, etc.
- **Export vers Excel**

#### Gestion des opérations financières

- **Écritures d'abonnement** : modèles et prévisions récurrentes
- **Virements de trésorerie** : rééquilibrage entre comptes
  - Saisie simplifiée des virements
  - Suivi des virements de trésorerie
- **Gestion des financements** : suivi des lignes de crédit
- **Gestion des placements** à court terme
- **Portefeuille d'OPCVM** : suivi des investissements
- **Prévisions d'abonnement** : prévisions récurrentes liées aux abonnements

#### Mouvements comptables futurs (MCF)

- **Relevés de MCF** : prévisions issues de la comptabilité
- **Incorporation des relevés de MCF**
- **Liste et situation des MCF**
- **Actualisation des prévisions comptables**

#### Traitement

- **Aide à la gestion quotidienne**
- **Analyse des soldes**
- **Mise à jour de la comptabilité** : déversement des écritures
- **Sauvegarde fiscale des données**
- **Nouvel exercice** et **clôture d'exercice**

### 7.3 Logique métier

La Trésorerie est le **module de pilotage financier** par excellence. Sa logique repose sur la confrontation entre :

1. **Les flux réels** (extraits bancaires intégrés quotidiennement)
2. **Les flux prévisionnels** (échéances comptables + prévisions manuelles)

La **situation de trésorerie prévisionnelle** croise ces deux sources pour projeter les soldes à venir. L'utilisateur peut alors :

- **Anticiper les découverts** et prendre des mesures (virements d'équilibrage, financements)
- **Optimiser les placements** des excédents (OPCVM, placements à court terme)
- **Réduire les frais bancaires** (agios, commissions)
- **Détecter les retards de paiement** clients et relancer

La **consolidation multi-sociétés** permet aux groupes d'avoir une vision agrégée de leur trésorerie.

L'intégration native avec Comptabilité et Moyens de Paiement élimine toute ressaisie : les échéances, extraits bancaires et règlements circulent automatiquement entre les modules.

---

## 8. Module Immobilisations

### 8.1 Vue d'ensemble

Sage 100 Immobilisations gère le **cycle de vie complet des actifs** de l'entreprise : acquisition, amortissement, réévaluation, cession. Il calcule les amortissements selon différents modes et transfère les écritures vers la Comptabilité et les liasses fiscales.

### 8.2 Fonctionnalités détaillées

#### Création et gestion des immobilisations

- **Création par relecture directe des écritures** de Sage 100 Comptabilité : les écritures d'achat d'immobilisations sont automatiquement transformées en fiches d'immobilisation
- **Saisie directe** associée à une gestion de familles d'immobilisations
- **Définition des lieux d'utilisation** des biens
- **Gestion des immobilisations rattachées** : liaison entre immobilisations (ex : un ordinateur et son écran)
- **Fractionnement d'une immobilisation** : division d'un bien en plusieurs composants
- **Gestion de tous les types d'actif** : biens immobilisés, financiers, crédit-bail, leasing
- **64 champs libres** paramétrables sur les fiches immobilisations
- **10 champs statistiques**
- **Documents attachés** (Premium)
- **Bloc-notes** sur chaque fiche

#### Modes d'amortissement

| Mode | Description | Usage |
|---|---|---|
| **Linéaire** | Amortissement constant sur la durée de vie | Standard comptable |
| **Dégressif** | Amortissement accéléré en début de vie | Optimisation fiscale |
| **Dérogoire** | Différence entre amortissement fiscal et économique | Conformité CRC 2002-10 |
| **Exceptionnel** | Pour dépréciation irréversible ou redressement fiscal | Cas spécifiques |
| **Manuel** | Amortissement librement défini | Flexibilité |
| **Natif** | Plan d'amortissement intégré (famille et fiche), CRC 2002-10 | Norme actuelle |
| **IFRS** | Amortissement en normes internationales (économique et natif) | Groupes internationaux |

#### Plans d'amortissement

- **Plan économique** : amortissement comptable basé sur la durée d'usage
- **Plan fiscal** : amortissement selon les règles fiscales
- **Plan dérogatoire** : écart entre fiscal et économique
- **Plan natif** : gestion de la valeur résiduelle, déduite de la base d'amortissement
- **Tableaux simulant les annuités** jusqu'à la fin de l'amortissement
- **Gestion des crédits-bail et locations** avec édition d'un état des engagements

#### Traitements

- **Calcul des amortissements** : génération automatique des dotations
- **Virement de poste à poste** : changement d'affectation comptable
- **Sortie globale** : cession d'une partie ou de l'ensemble des biens (cessation d'activité)
- **Cessions en rafale** : cession simultanée de plusieurs immobilisations
- **Cessions simultanées** : calcul automatique des valeurs de cession pour les biens liés
- **Inventaire comptable** :
  - Amortissements exceptionnels en cas de dépréciation irréversible
  - Provisions en cas de dépréciation temporaire
  - Règle de limitation de la reprise des dépréciations (CRC 2002-10)
- **Réévaluation** des immobilisations
- **Révision du plan d'amortissement** : modification de la durée ou de la valeur d'acquisition, recalcul automatique
- **Optimisation des amortissements dérogatoires** : reprise par anticipation ou limitation, par immobilisation ou au niveau global

#### Intégration

- **Interface temps réel avec Sage 100 Comptabilité** : pas de ressaisie
- **Déversement des écritures en Comptabilité** : dotations, cessions, régularisations
- **Transfert vers liasse fiscale** : génération automatisée dans les feuillets 2054, 2055, 2059
- **Import / export paramétrable** : familles, immobilisations, comptes généraux, sections analytiques

#### États

- État des immobilisations, des amortissements, des acquisitions, des sorties
- État des crédits-bails/locations
- État de rapprochement, état des historiques
- Journal comptable, états analytiques
- États préparatoires fiscaux (2054, 2055, 2059)
- États TVS (Taxe sur les Véhicules de Société)
- État de contrôle dotations appliquées
- Comparatif Comptabilité / Immobilisation
- Simulation

### 8.3 Nouveautés V12

- **Extension à 10 exercices consultables** : en cohérence avec la Comptabilité, facilite les contrôles et analyses pluriannuels

### 8.4 Logique métier

L'immobilisation représente un **actif durable** de l'entreprise (véhicule, matériel, bâtiment). Sa valeur est consommée dans le temps via l'amortissement. La logique métier suit le cycle :

```
Acquisition (achat) → Création de la fiche immo → Calcul des amortissements annuels
→ Dotation comptable (écriture dans Comptabilité) → Transfert vers liasse fiscale
→ Révision éventuelle (modification durée/valeur) → Cession (sortie)
→ Écriture de cession + Plus-value ou moins-value
```

La distinction entre **amortissement économique** (reflète l'usage réel) et **amortissement fiscal** (optimisation fiscale) génère un **amortissement dérogatoire** qui doit être repris ultérieurement. Le module gère cette complexité automatiquement.

---

## 9. Module États Comptables et Fiscaux (ECF)

### 9.1 Vue d'ensemble

Sage 100 ECF génère les **états financiers légaux** : bilan, compte de résultat, liasse fiscale, SIG (Soldes Intermédiaires de Gestion). Il assure la conformité avec les obligations réglementaires françaises.

### 9.2 Fonctionnalités détaillées

- **Bilan, compte de résultat, SIG** personnalisables par société
- **Liasses fiscales** : génération automatisée des feuillets (2050, 2054, 2055, 2058, 2059, etc.)
- **FEC (Fichier des Écritures Comptables)** : production simplifiée pour les contrôles fiscaux
- **Modèles d'impression** personnalisables
- **Assistants de mise à jour fiscale** : actualisation des modèles selon les modifications réglementaires
- **Lien direct balance et interrogation** : navigation entre les états et le détail des écritures
- **Édition type Cerfa** actualisée au millésime en cours
- **Configurables par société** : chaque société peut avoir ses propres modèles

### 9.3 Nouveautés V12

| Fonctionnalité | Description |
|---|---|
| **Mise à jour des formats fiscaux 2025** | Conformité avec les obligations réglementaires 2025 |
| **Génération automatisée des liasses fiscales** | Réduction du temps de production |
| **Production simplifiée des fichiers FEC** | Fluidifie les contrôles fiscaux |
| **Nouveaux modèles d'impression** | Mise à jour des présentations |

### 9.4 Réforme ANC 2025 (V11+)

La **norme ANC 2025** (Autorité des Normes Comptables) modernise les états financiers pour les exercices ouverts à partir du 1er janvier 2025 :

- **Suppression des transferts de charges**
- **Réforme du résultat exceptionnel**
- **Nouveaux modèles de Bilan et Compte de Résultat**
- **Plan comptable mis à jour** : nouveaux comptes obligatoires/facultatifs, suppression de comptes, nouvelle destination de certains comptes

Sage 100 V11 intègre un **assistant de mise en conformité** qui permet :
- L'ajustement du plan comptable (ajout des nouveaux comptes, mise en sommeil des comptes supprimés)
- L'identification des comptes nécessitant un ajustement comptable
- La mise à jour des rubriques des états légaux avec les nouveaux comptes
- Le comparatif anciens/nouveaux comptes

### 9.5 Logique métier

L'ECF est le **module de clôture**. À la fin de chaque exercice, il produit les documents légaux obligatoires à partir des données de la Comptabilité et des Immobilisations. La logique est :

```
Comptabilité → Balance → ECF → Bilan + Compte de résultat + SIG
Immobilisations → Amortissements → ECF → Feuillets 2054/2055/2059
ECF → Liasse fiscale complète → Administration fiscale
ECF → FEC → Contrôle fiscal
```

Les **rubriques** des états font le lien entre les comptes du plan comptable et les lignes du bilan/compte de résultat. Chaque compte est associé à une rubrique (actif immobilisé, stocks, créances, etc.). Lorsque le plan comptable évolue (norme ANC 2025), les rubriques doivent être mises à jour pour pointer vers les nouveaux comptes.

---

## 10. Module CRM — Force de Vente

### 10.1 Vue d'ensemble

Sage 100 CRM Force de Vente (anciennement Sage CRM 100c) est une solution **100% web** de gestion de la relation client centrée sur l'**acquisition** de nouveaux clients. Elle gère la prospection, le suivi des opportunités, le marketing et le management de l'équipe commerciale.

### 10.2 Fonctionnalités détaillées

#### Gestion des contacts et prospection

- **Gestion des comptes, contacts et prospects** : base de données unifiée
- **Fichiers prospects séparés des clients** : pas de pollution de la base client
- **Pop-up d'infos flash** dans les fiches sociétés et opportunités : prévisionnel, gagné, CA N/N-1, risque, conditions de paiement
- **Historique complet** des échanges : emails, appels, besoins, équipement
- **Gestion des secteurs commerciaux** et cycles de ventes
- **Affectation des opportunités** au commercial spécialisé dans le secteur

#### Suivi des opportunités et affaires

- **Suivi des opportunités** du 1er contact à la signature
- **Avancement et probabilités de réussite**
- **Relances automatiques** et procédures d'escalade
- **Réaffectations d'opportunités**
- **Gestion des concurrents** : notes sur la concurrence
- **Prévisions de ventes** : tableaux de bord et rapports graphiques
- **Saisie simple et rapide des devis et commandes** via Sage 100 Etendue
- **Bibliothèque de documents** partagée

#### Management de l'équipe commerciale

- **Organisation des journées de travail**
- **Agendas individuels et collectifs** partagés
- **Rapports d'activité**
- **Identification des bonnes pratiques**
- **Compte rendu**
- **Pilotage transversal de l'activité commerciale**

#### Marketing et fidélisation

- **Segmentation et profiling** de la base contacts
- **Planification des opérations commerciales**
- **Gestion des campagnes marketing** : étapes, budgets, ROI
- **Générateur de requêtes intégré** et modèles fournis en standard
- **Traçabilité commerciale** de la détection à la conclusion
- **Chaînes de prospection et de fidélisation** : messages périodiques automatiques
- **Publipostage et e-mailing**
- **E-mailing avancé avec suivi des clics**
- **Gestion des appels sortants avec CTI** (Couplage Téléphonie-Informatique, en option)
- **Gestion de l'eMarketing** (médias sociaux) et SMSing (en option)

#### Mobilité

- **100% web** : accessible via simple navigateur
- **Applications iOS et Android**
- **Accès aux fiches contacts détaillées** : nouveaux interlocuteurs, etc.
- **Composition automatique** des numéros et emails
- **Géolocalisation** des contacts
- **Historique commercial, technique et marketing**
- **Mise à jour et création de contacts** en mobilité
- **Saisie d'opportunités et de tickets**
- **Agendas partagés synchronisés**
- **Impression des devis et commandes**
- **Présentation multimédia** : photos, vidéos
- **Remontées d'informations sur la concurrence**

#### Intégration

- **Synchronisation avec Microsoft Outlook**
- **Intégration avec Sage 100 Gestion Commerciale** : consultation des données commerciales sur les mêmes rapports
- **Personnalisation intégrale** des fiches, processus
- **Gestion des secteurs et droits d'accès**

### 10.3 Logique métier

Le CRM Force de Vente structure le **pipeline commercial** en étapes claires (prospection, qualification, proposition, négociation, signature). Chaque opportunité est suivie avec sa probabilité de réussite, permettant de calculer un **prévisionnel de ventes pondéré**. L'intégration avec Sage 100 Gestion Commerciale permet de transformer un devis CRM en commande dans l'ERP sans ressaisie.

Le marketing automation (campagnes, e-mailing, chaînes de prospection) nourrit le pipeline en amont. La traçabilité de la détection à la conclusion permet de mesurer le ROI de chaque action marketing.

---

## 11. Module CRM — Service Client

### 11.1 Vue d'ensemble

Sage 100 CRM Service Client est centré sur la **fidélisation** des clients existants. Il gère les demandes de support, les tickets d'incidents, la base de connaissances et l'extranet clients.

### 11.2 Fonctionnalités détaillées

#### Gestion des tickets et demandes

- **Enregistrement des demandes clients** : création de tickets depuis tous les canaux (email, téléphone, web)
- **Suivi des tickets** du signalement à la résolution
- **Affectation automatique** aux bons interlocuteurs selon les règles définies
- **Gestion des priorités** et des niveaux d'urgence
- **Escalade automatique** en cas de non-respect des SLA (Service Level Agreements)
- **Historique complet** des interactions par client

#### Base de connaissances

- **Création et partage d'articles** de la base de connaissances
- **Accès par profil** : clients, techniciens, managers
- **Recherche full-text** dans la base
- **Mise à jour collaborative** des articles

#### Extranet clients

- **Portail client web** : les clients créent et suivent leurs tickets en ligne
- **Consultation des contrats** et des conditions de service
- **Accès à la base de connaissances** en self-service
- **Téléchargement de documents** (manuels, guides, FAQ)

#### Gestion des contrats de service

- **Suivi des contrats de maintenance** et d'assistance
- **Gestion des SLA** : temps de réponse, temps de résolution
- **Alertes de renouvellement** de contrats
- **Facturation des prestations** liées aux contrats

#### Reporting

- **Tableaux de bord** : temps moyen de résolution, taux de résolution au 1er niveau, satisfaction client
- **Rapports d'activité** par technicien, par client, par type de demande
- **Analyse des tendances** : récurrence des problèmes, formation needed

### 11.3 Logique métier

Le CRM Service Client assure la **qualité du service après-vente**. Un client bien servi est un client fidèle. La logique métier repose sur :

1. **Capture** : chaque demande client est enregistrée comme un ticket, quel que soit le canal
2. **Routage** : le ticket est affecté au bon technicien selon les compétences et la disponibilité
3. **Résolution** : le technicien utilise la base de connaissances pour résoudre rapidement
4. **Traçabilité** : l'historique complet permet de comprendre chaque problème et d'améliorer la base
5. **Mesure** : les KPIs (SLA, satisfaction) permettent de piloter la qualité du service

L'intégration avec Sage 100 Gestion Commerciale permet de facturer les prestations de service et de consulter l'historique d'achat du client pour mieux le servir.

---

## 12. Module Paie & RH

### 12.1 Vue d'ensemble

Sage 100 Paie & RH est une solution complète de gestion de la paie et des ressources humaines. Elle produit les bulletins de salaire, gère les déclarations sociales (DSN), et administre le personnel.

### 12.2 Fonctionnalités détaillées

#### Préparation et édition de la paie

- **Assistant de préparation** : report automatique des éléments constants, gestion des titres restaurant
- **Calcul des paies à l'envers** : détermination du brut à partir du net souhaité
- **Gestion des acomptes** : de la génération au virement, contrôle et report automatique
- **Fonction de rappel des salaires** : gestion de la rétroactivité
- **Modèles de bulletins** par catégorie de salariés
- **Bulletins modèles** prêts à l'emploi

#### Gestion du personnel

- **Fiches de personnel détaillées** : état civil, immatriculation, données personnelles, coordonnées
- **Gestion de la pénibilité du travail**
- **Suivi des carrières** et de l'organisation
- **Gestion des entrées et sorties** des salariés
- **Assistant de sortie du salarié**

#### Déclarations sociales

- **DSN (Déclaration Sociale Nominative)** : production et télétransmission
- **DADS-U, DUCS, AED** : déclarations conformes
- **DTS-MSA** : déclaration pour le secteur agricole
- **DPAE** : Déclaration Préalable À l'Embauche
- **CICE** : paramétrage
- **Déclarations spécifiques BTP** (CIBTP, Congés Payés)
- **Service déclaratif Sage DS** : réalisation de toutes les déclarations sociales
- **IntuiDSN** : navigation intuitive pour la DSN

#### Conformité et archivage

- **Archivage des données** pour 10 ans
- **Suivi intégral de la gestion du CPF** (Compte Personnel de Formation)
- **Éditions légales pré-paramétrées**
- **Gestion des honoraires**
- **Veille juridique** intégrée via IntuiSage

#### Évolutions récentes (V7.10)

- **Sauvegarde sur Azure Blob** : flexibilité du lieu de stockage, sécurité renforcée
- **Connect Import** : intégration de données externes sans saisie manuelle
- **Régularisation des données de type brut** sans impact sur les cotisations
- **Passation comptable au format CSV** et ordonnancement des écritures
- **Généralisation de la dématérialisation des bulletins consolidés**
- **Anticipation des obligations légales** : déclaration de refus de CDI, CT2025

### 12.3 Logique métier

La paie est un processus **mensuel récurrent** à forte conformité légale. La logique métier suit le cycle :

```
Collecte des variables (heures, primes, absences) → Préparation de la paie
→ Édition des bulletins → Validation → Télétransmission DSN
→ Passation comptable (écritures vers Comptabilité)
→ Dématérialisation (bulletins dans coffres-forts salariés via LPD)
```

L'enjeu principal est la **conformité réglementaire** : le Plan de Paie Sage intègre les évolutions législatives (taux de cotisations, allègements, dispositifs spécifiques). La DSN remplace de nombreuses déclarations et doit être transmise chaque mois.

La **passation comptable** génère les écritures de salaires (rémunérations brutes, cotisations salariales et patronales, net à payer) dans Sage 100 Comptabilité, assurant le lien entre la paie et la comptabilité.

---

## 13. Sage Dématérialisation RH

### 13.1 Vue d'ensemble

Sage Dématérialisation RH est un **service collaboratif et sécurisé** pour centraliser, structurer et gérer tous les documents RH. Il est intégré à Sage 100 Paie & RH et accessible via La Place Digitale (LPD).

### 13.2 Fonctionnalités détaillées

#### Options incluses

| Option | Description |
|---|---|
| **Relation RH-Salariés** | Distribution automatique des documents dans les coffres-forts salariés |
| **Gestion documentaire** | Centralisation et classement de tous les documents RH |
| **e-signature** | Signature électronique de documents RH |
| **Coffre-fort électronique** | Archivage sécurisé à valeur probante |

#### Distribution des documents

- **Distribution automatique instantanée** des bulletins de paie dans chaque coffre-fort salarié
- **Pilotage de l'activité documentaire RH** : indicateurs en temps réel sur l'activité et le contenu de la plateforme
- **Contrôle des lots avant diffusion** : vérification avant envoi aux salariés
- **Dépôt manuel de documents** hors bulletin de salaire (avec ou sans annexes)
- **Synchronisation des bulletins d'un mois précédent** via dépôt manuel

#### Conformité

- **Conforme à la Loi travail du 8 août 2016** et alimentation du Compte Personnel d'Activité
- **Double archivage légal** : employeur et salarié, respectant les normes AFNOR Z42-013 et NF Z42-025
- **Conformité RGPD** : protection des données personnelles
- **Gestion dématérialisée des documents** conforme à l'Art. L3243-2 du Code du travail

#### Relation RH-Salariés

- **Base de connaissances** accessible à tous selon leur profil
- **Formulaires de demandes personnalisés** accessibles aux gestionnaires, salariés et/ou managers
- **Règles d'attribution** : les salariés sont pris en charge immédiatement par le bon interlocuteur RH
- **Suivi en temps réel** du traitement des requêtes
- **Demandes adressées aux salariés** : relance automatique, obtention des réponses plus rapidement
- **Évaluation des interactions RH/salariés** : indicateurs chiffrés sur l'activité

### 13.3 Logique métier

La dématérialisation RH transforme la gestion documentaire RH en processus **100% digital**. Fini les impressions papier et les distributions manuelles : chaque bulletin de paie est automatiquement déposé dans le coffre-fort électronique du salarié, qui reçoit une notification et peut consulter son bulletin depuis n'importe quel appareil.

Le **double archivage** (employeur + salarié) garantit la conservation légale : en cas de départ du salarié, celui-ci conserve l'accès à son coffre-fort avec tout son historique. L'employeur garde également ses archives conformément aux normes AFNOR.

---

## 14. Sage Espace Employés

### 14.1 Vue d'ensemble

Sage Espace Employés (SEE) est un **SIRH 100% cloud** qui digitalise les processus RH au quotidien : congés, absences, notes de frais, entretiens, objectifs. Il est connecté à Sage 100 Paie & RH.

### 14.2 Les 4 modules

#### Module 1 : Congés et Absences

- **Dématérialisation de toutes natures d'absences** : congés payés (ouvrés/ouvrables), RTT, récupération, maladie, congés sans solde
- **Saisie via planning de congés** partagé ou individuel
- **Calcul et contrôles automatiques** des soldes de congés avec horodatage et archivage
- **Validation personnalisable** et paramétrable des demandes par les managers
- **Mise à jour automatique** des calendriers de jours fériés (régionaux et internationaux)
- **Règles d'acquisition et de prise** des congés selon chaque nature
- **Gestion des règles conditionnelles** de débit/crédit sur les compteurs (jours de récupération…)
- **Gestion des astreintes** (effectif minimum sur une période donnée)
- **Décompte du nombre de jours pris** selon modalité du salarié (temps partiel...)
- **Calcul des soldes à date**
- **Affichage des textes légaux** et aides explicatives lors de la pose des congés
- **Ajout de documents justificatifs** à la demande de congés
- **Exportation sous Excel**
- **Circuit de validation des congés** paramétrable
- **Synchronisation avec calendrier Office 365 ou Google Suite**
- **Multi-sociétés**
- **Calcul et cumul automatique** des soldes
- **Gestion des plannings types**
- **Intégration des données vers la paie** : export en un clic

#### Module 2 : Dossier Salarié

- **Gestion des entrées et sorties** des salariés
- **Mise à jour des informations** par le collaborateur directement (avec processus de validation personnalisable)
- **Données visibles et/ou modifiables** en fonction des droits attribués
- **Historique centralisé** avec stockage de documents
- **Saisie des informations variables de paie** (primes, heures supplémentaires) prise en compte automatiquement dans le bulletin
- **Alertes** programmables pour des évènements importants

#### Module 3 : Entretiens et Objectifs

- **Création et personnalisation des formulaires d'entretien** : structure, sections, questions, modes d'évaluation (étoiles, échelles, listes de valeurs, cases à cocher, texte libre)
- **Types d'entretien** : individuel, professionnel, fin de mission, revue d'objectifs, sondages
- **Gestion de la visibilité des questions** entre salarié et manager
- **Fixation et suivi des objectifs** : individuels ou collectifs
- **Choix de la période et de la fréquence** d'évaluation (annuelle, semestrielle, trimestrielle ou mensuelle)
- **Suivi de la progression** des objectifs au cours de la période de référence
- **Organisation et suivi des campagnes** : date de début/fin, relance, état d'avancement
- **Notification personnalisable** et circuit de validation
- **Historique des modifications** et archivage

#### Module 4 : Notes de frais

- **Numérisation et reconnaissance automatique** des factures (OCR)
- **Accès multi-canal** : desktop, mobile, iPad
- **Accès hors connexion** : saisie en mode dégradé, synchronisation au retour
- **Personnalisation des catégories/natures** de dépense
- **Définition des workflows de validation**
- **Gestion des plafonds de remboursement** et alertes en cas de dépassement
- **Gestion de la TVA**
- **Gestion des moyens de paiement** y compris la carte société
- **Personnalisation du plan de comptes**
- **Transfert des dépenses vers la solution de paie**
- **Génération des écritures comptables** vers une solution tierce (Sage 100 Comptabilité)
- **Détail par compte, centre de coût, catégorie de TVA**

### 14.3 Application mobile

- **Disponible sur Apple Store et Google Play**
- **Compatible PC, MAC, Tablette, Smartphone**
- **Consultation du planning et des soldes de congés**
- **Saisie d'absences ou de congés**
- **Validation des demandes de congés** par les managers
- **Saisie de notes de frais** avec photo des justificatifs

### 14.4 Logique métier

Sage Espace Employés **décharge les RH des tâches administratives** en autonomisant les salariés et les managers :

```
Salarié saisit une demande de congé → Manager valide → Compteur mis à jour
→ Export en fin de mois vers Sage 100 Paie & RH → Intégration dans le bulletin de salaire
```

Pour les notes de frais :

```
Salarié photographie le justificatif → OCR extrait les données → Validation manager
→ Génération des écritures comptables → Intégration dans Sage 100 Comptabilité
```

L'enjeu est triple : **gain de temps** (fini les papiers et les tableaux Excel), **fiabilisation** (calculs automatiques, contrôle des soldes), et **satisfaction collaborateur** (self-service, transparence, mobilité).

---

## 15. Module Recouvrement Créances

### 15.1 Vue d'ensemble

Sage Recouvrement Créances est une **solution cloud** dédiée au suivi et à la relance des factures clients. Directement connectée à Sage 100 Comptabilité, elle permet de réduire l'encours client jusqu'à 50% et de gagner 50% de temps sur les relances.

### 15.2 Fonctionnalités détaillées

#### Tableau de bord et suivi

- **Suivi dynamique des encours clients** : visibilité en temps réel
- **Suivi dynamique des factures** : visibilité en temps réel des factures à relancer
- **Page d'accueil** avec les principaux indicateurs de suivi des relances clients
- **Vision détaillée client** : fiche client avec toutes les informations pour relancer
- **Créances en retard** : dates d'échéances et sommes payées sur les 3 derniers mois
- **Top 10 et scoring mauvais payeur** : identification immédiate des tiers à surveiller
- **Monitoring multi-axes** : promesses de paiement, litige, scoring mauvais payeur, reste à payer, tâches à accomplir

#### Gestion des litiges

- **Litige au client** : identification des motifs de litige
- **Litige à la pièce** : identification des factures en litige
- **Motif de litige client** : gestion des motifs

#### Promesses et prévisions

- **Promesses de paiement** : enregistrement
- **Prévision des encaissements** : enregistrement
- **Objectif cash** : pilotage prévisionnel des encaissements par rapport aux objectifs de rentrées de cash

#### Scoring et analyse

- **Scoring mauvais payeurs** : identification par analyse des comportements de paiement
- **Flag clients et timeline** : suivi des clients spécifiques ou à risque
- **DSO** : paramétrage et consultation du délai moyen de recouvrement des créances

#### Synchronisation

- **Synchronisation à la demande** : par l'utilisateur
- **Synchronisation planifiée** : dans un batch
- **Récupération des écritures comptables et fiches clients** de Sage 100

#### Communication et relances

- **Relance multicanal** : programmation et envoi par mail, courrier, téléphone, autres médias
- **Prévenance / Relance / Remerciement** : séquencement en 3 temps et 5 niveaux R1 à R5
- **Gestion des profils clients** : suivi et relance selon la typologie (grandes entreprises, PME, particuliers)
- **Liste des actions à mener** : tâches de relance par utilisateur
- **Relance en masse par scénario** : par étapes successives de communication
- **Relance individuelle** : par client ou par échéance
- **Gestion de la relance par situation de compte** : relance centralisée par compte (1 relance sur le niveau le plus haut)
- **Automatisation relance email** : dans les scénarios
- **Seuil de relance à la pièce** : montant minimum pour relancer
- **Gestion multi-contacts** : association de plusieurs contacts par client

#### Collaboration

- **Accès personnalisés** pour les collaborateurs impliqués (direction générale, équipes commerciales, DAF, comptables)
- **Cash reporting quotidien** : reçu par email
- **Information des autres acteurs** sur la situation d'un client (encours, actions menées)

#### Paramétrages

- **Personnalisation de la langue, du format monétaire, du format de date, du fuseau horaire**
- **Multi-devise** : définition d'une autre monnaie que l'Euro

### 15.3 Logique métier

Le recouvrement est un **processus structuré en 3 leviers** :

1. **Visibilité** : savoir qui doit quoi, quand, et depuis combien de temps
2. **Communication** : relancer au bon moment, avec le bon message, via le bon canal
3. **Collaboration** : impliquer tous les acteurs (RH, commerciaux, direction) dans le suivi

Les **scénarios de relance** sont personnalisables par typologie de client. Un grand compte ne sera pas relancé comme un particulier : le message, le canal et le timing diffèrent. Le séquencement en 3 temps (prévenance avant échéance, relance après échéance, remerciement après paiement) préserve la relation client tout en étant efficace.

Le **scoring mauvais payeur** analyse le comportement de paiement historique pour identifier les clients à risque avant même qu'un retard ne se produise. Le **DSO** (Days Sales Outstanding) mesure le délai moyen de paiement et permet de suivre l'amélioration.

---

## 16. Module Saisie de Caisse Décentralisée (SCD)

### 16.1 Vue d'ensemble

Sage 100 Saisie de Caisse Décentralisée est une solution de **point de vente** interfacée nativement avec Sage 100 Gestion Commerciale. Elle est conçue pour les entreprises de négoce, entrepôts commerciaux et succursales multiples.

### 16.2 Fonctionnalités détaillées

#### Vente comptoir

- **3 types d'écrans prédéfinis** :
  - Écran de saisie exclusive au clavier
  - Écran de saisie souris/clavier
  - Écran de saisie classique
- **Personnalisation jusqu'à 10 écrans** : association d'un écran type à chaque caisse
- **Touches de clavier programmables** : accès direct aux fonctions courantes (impression ticket, saisie règlement…)

#### Fonctions traditionnelles de caisse

- **Gestion de la caisse** :
  - Ouverture, mouvements (entrées/sorties diverses)
  - Interrogation (édition du X de caisse) : opération de trésorerie, historique des documents et tickets, contrôle de caisse (fond de caisse, règlements espèces/chèque/carte bleue)
  - Clôture de caisse (Z de caisse) : archivage du détail des tickets
  - Possibilité de changer le dépôt défini par défaut
- **Gestion des caissiers** : nombre illimité, identifiés par mot de passe
- **Mise en attente** : un ou plusieurs tickets peuvent être mis en attente puis rappelés

#### Articles, soldes et promotions

- **Partage du fichier articles** de Gestion Commerciale 100 :
  - Articles à gammes (tailles et couleurs, longueurs et largeurs, textures et épaisseurs)
  - Numéros de série et de lot
  - Articles liés, conditionnements, nomenclatures, modèles d'enregistrement
- **Remises promotionnelles** associées à un article ou une famille d'articles, définies sur une période
- **Sélection par lecteur code-barres** (douchette)
- **Fonction de régularisation d'inventaire** : comparaison stock théorique / stock réel

#### Clients

- **Informations complètes** sur le client (solvabilité, références bancaires…)
- **Possibilité de créer ou rattacher un client** en vente comptoir
- **Statistiques** avec affichage graphique

#### Statistiques

- **Palmarès clients et articles**
- **Les 10 plus fortes ou plus faibles ventes** par client, en marge ou CA (HT ou TTC)
- **Les 10 plus fortes ou plus faibles ventes** par article, en quantité, marge ou CA (HT ou TTC)
- **Ventes par caisse / par mode de règlement**
- **Ventes par période / heure / jour**

#### Automatisation site à site

- **Assistant à la communication site à site** : simplifie et automatise le transfert et l'intégration des données entre Gestion Commerciale 100 et SCD 100
- **Guidage de l'utilisateur** à chaque étape de mise à jour pour supprimer tout risque d'erreur

#### Sécurité

- **Contrôle des manipulations** selon les habilitations données à chaque utilisateur
- **Logiciel de caisse certifié** : conformité aux 4 conditions exigées (inaltérabilité, sécurisation, conservation, archivage) — obligation depuis le 1er janvier 2018

#### Matériel compatible

- Écrans tactiles
- Lecteurs de code-barres
- Tiroirs-caisses
- Imprimantes de tickets

### 16.3 Logique métier

SCD partage **en temps réel** le fichier articles et la politique tarifaire de Sage 100 Gestion Commerciale. Un article créé ou modifié dans la GC est immédiatement disponible en caisse. Inversement, les ventes réalisées en caisse remontent dans la GC pour mise à jour des stocks et facturation.

La **vitesse de saisie** est le critère d'achat numéro un : le temps entre deux tickets n'excède pas quelques secondes. Les touches programmables et la compatibilité avec les lecteurs code-barres assurent cette rapidité.

La **certification légale** (inaltérabilité, sécurisation, conservation, archivage) protège l'entreprise en cas de contrôle fiscal. Les tickets de caisse sont horodatés et ne peuvent être modifiés après clôture (Z de caisse).

---

## 17. Sage BI Reporting & Sage Business Reporting

### 17.1 Sage BI Reporting (On-Premise)

#### Vue d'ensemble

Sage BI Reporting est une solution de **Business Intelligence** intégrée à Excel, connectée en temps réel aux données de Sage 100. Elle permet de créer des tableaux de bord, des rapports et des analyses sans manipulation manuelle des données.

#### Fonctionnalités

- **Connexion en temps réel** aux données Sage 100 (Comptabilité et Gestion Commerciale)
- **Tableaux de bord dynamiques** dans Excel : mise à jour automatique
- **Génération automatisée de rapports** : pas de manipulation manuelle
- **Visualisation avancée** : graphiques, tableaux croisés dynamiques, indicateurs
- **Contrôle d'accès par utilisateur** : sécurité des données
- **Bibliothèque de rapports standards** : modèles prêts à l'emploi
- **Support pour la prise de décision** : KPIs par fonction (ventes, achats, trésorerie, RH)
- **Export et partage** : diffusion des rapports aux équipes
- **Compatibilité** : Sage 100 On-Premise (SQL Server)

#### Logique métier

Sage BI Reporting **démocratise l'accès aux données** de gestion. Sans compétences techniques, un dirigeant ou un manager peut :
- Suivre le CA en temps réel par produit, par client, par commercial
- Analyser les marges et identifier les produits les plus rentables
- Piloter la trésorerie avec des prévisions actualisées
- Comparer les performances entre périodes, entre sociétés

La connexion en temps réel élimine les exports manuels et les risques d'erreur : les données dans Excel sont toujours à jour.

### 17.2 Sage Business Reporting (Cloud avec IA)

#### Vue d'ensemble

Sage Business Reporting est une solution **cloud** de BI, intégrée à Excel, avec l'IA **Sage Copilot**. Elle est compatible avec Sage 100 et d'autres ERP Sage.

#### Fonctionnalités

- **Reporting cloud dans Excel** : accès depuis n'importe où
- **IA Sage Copilot** : analyse automatisée, suggestions d'insights, génération de rapports
- **KPIs en temps réel** : connectivité directe avec les données Sage
- **Tableaux de bord personnalisables** : par fonction, par utilisateur
- **Multi-ERP** : compatible avec plusieurs produits Sage
- **Automatisation** : planification de rapports, envoi automatique
- **Sécurité cloud** : chiffrement, contrôle d'accès

#### Logique métier

Sage Business Reporting apporte l'**intelligence artificielle** dans l'analyse de données. Sage Copilot peut :
- Détecter automatiquement des anomalies (baisse de marge, hausse des coûts)
- Suggérer des actions correctives
- Générer des narratifs explicatifs pour les rapports
- Répondre à des questions en langage naturel ("Quel est mon CA par région ce mois-ci ?")

Cette approche rend la BI accessible même aux non-experts : l'IA guide l'utilisateur vers les insights pertinents.

---

## 18. Sage Network, Sage Connect & Facture Électronique

### 18.1 Sage Network

#### Vue d'ensemble

Sage Network est un **réseau digital collaboratif** qui automatise et simplifie les flux de données entre les entreprises (clients, fournisseurs) et avec leur environnement (banque, expert-comptable, administration). Il est au cœur de la réforme de la facture électronique.

#### Fonctionnalités

- **Facturation électronique** : envoi, réception et traitement des factures électroniques directement depuis Sage 100, dans des formats conformes (Factur-X, UBL, CII)
- **Conformité Plateforme Agréée (PA)** : Sage Network est la plateforme agréée officielle de Sage (anciennement PDP)
- **Rapprochements bancaires plus rapides** : partage sécurisé des données avec les banques
- **Paiements simplifiés** : automatisation du parcours client jusqu'au paiement
- **Recouvrement automatisé** : suivi des factures de la création au paiement
- **IA intégrée** : analyses plus pertinentes de l'activité
- **2,5 millions de factures dématérialisées** (échelle du réseau)

#### Plateforme Agréée Sage (PA Sage)

| Fonction clé | Description | Bénéfice |
|---|---|---|
| **Contrôle de conformité** | Vérifie que chaque facture respecte les formats autorisés (Factur-X, UBL, CII) et contient toutes les mentions légales | Évite les rejets, litiges et pénalités fiscales |
| **Transmission sécurisée** | Achemine la facture au bon destinataire via un annuaire centralisé basé sur les numéros de SIREN | Garantit la bonne réception par le partenaire commercial |
| **Extraction de données (E-reporting)** | Extrait automatiquement les données de TVA pour les transmettre à l'administration fiscale | Simplifie et automatise les déclarations de TVA |
| **Traçabilité des flux** | Suivi en temps réel des statuts de chaque facture (Déposée, Rejetée, Validée, Encaissée) | Visibilité complète sur le cycle de facturation |

#### Avantages de la PA Sage vs plateforme tierce

| Critère | Plateforme tierce | Plateforme Agréée Sage |
|---|---|---|
| **Coût** | Connecteur à construire + maintenance | Pas de coûts associés (dans la limite des plafonds par produit) |
| **Intégration** | Connecteur à maintenir | Intégration native et temps réel avec Sage 100 |
| **Évolutivité** | Maintenance du connecteur à chaque évolution | Évolution automatique avec les versions Sage |
| **Cohérence des données** | Risque de désynchronisation | Cohérence garantie entre Sage 100 et la PA |
| **Responsabilité** | Responsabilité partagée | Interlocuteur unique Sage |

#### Plafonds d'utilisation

Les plafonds d'utilisation par produit Sage sont basés sur le nombre de factures électroniques (achat et vente) envoyées ou reçues via la PA Sage. En deçà du plafond mensuel, l'usage est **intégré dans le prix de l'abonnement**.

#### Connexion à Sage Network (3 étapes)

1. **Inscription** : activation du compte Sage ID depuis la tuile IntuiSage (V12) ou directement sur le portail
2. **Paramétrage** : configuration des sociétés, établissements, identifiants (SIRET obligatoire)
3. **Activation** : connexion automatique entre Sage 100 et Sage Network

#### Calendrier réglementaire

| Date | Obligation |
|---|---|
| **Septembre 2026** | Obligation de **réception** des factures électroniques pour toutes les entreprises. Obligation d'**émission** pour les grandes entreprises et ETI |
| **Septembre 2027** | Obligation d'**émission** pour toutes les entreprises (PME et micro-entreprises incluses) |
| **Avant juin 2026** | Recommandation : sélectionner et mettre en place une plateforme agréée |

### 18.2 Sage Connect

#### Vue d'ensemble

Sage Connect est le **connecteur d'échange** qui permet à Sage 100 de communiquer avec Sage Network et d'autres services en ligne. Il est intégré nativement dans les versions V11 et supérieures.

#### Fonctionnalités

- **Réception des factures électroniques** : les factures reçues via Sage Network s'affichent en PDF dans Sage 100
- **Validation en un clic** : l'utilisateur valide la facture, générant automatiquement les écritures comptables ou les documents d'achat en gestion commerciale
- **Inscription à la PA Sage** : accessible depuis la tuile IntuiSage (V12)
- **Vidéos et documentation** Sage via l'onglet Sage Connect d'IntuiSage
- **Accès aux services en ligne** Sage

### 18.3 Logique métier de la facture électronique

La réforme de la facture électronique transforme le cycle de facturation :

```
AVANT (papier/PDF) :
Entreprise A → facture papier/PDF → Entreprise B (saisie manuelle)

APRÈS (électronique) :
Entreprise A → Sage 100 → PA Sage A → Administration fiscale (e-reporting)
                                    → PA Sage B → Sage 100 (intégration auto) → Entreprise B
```

Les **formats acceptés** sont :
- **Factur-X** : format mixte (PDF lisible + XML structuré)
- **UBL** : format XML structuré
- **CII** : format XML européen

L'**annuaire centralisateur** tenu par l'administration permet aux plateformes d'émission de trouver la plateforme de réception de chaque entreprise (basé sur le SIREN).

---

## 19. Sage eFacture

### 19.1 Vue d'overview

Sage eFacture est le **portail historique** de dématérialisation des factures et commandes de Sage. Il préfigure Sage Network et reste actif pour les échanges électroniques de documents commerciaux.

### 19.2 Fonctionnalités détaillées

#### Pour les clients Sage

- **Inscription des sociétés** dans l'annuaire Sage eFacture
- **Consultation des entreprises** présentes dans l'annuaire
- **Invitation des tiers** à échanger des factures et commandes électroniques
- **Consultation en ligne** des factures et commandes, traçabilité des échanges
- **Téléchargement** des factures et commandes électroniques reçues
- **Consultation et téléchargement** des pièces jointes
- **Émission de factures et commandes** électroniques
- **Impression, mise sous pli et envoi postal** (option)
- **Intégration comptable** des factures électroniques reçues
- **Intégration en gestion commerciale** des factures et commandes reçues
- **Archivage électronique à valeur probante** pendant 10 ans

#### Pour les non-clients Sage (gratuit)

- Inscription dans l'annuaire
- Consultation et téléchargement des factures reçues (PDF)
- Pas d'intégration automatisée (saisie manuelle requise)

#### Formats supportés

| Format | Description |
|---|---|
| **Sage eFacture** | PDF encapsulant un XML au format UBL 2.0 (intégration automatisée dans les applications Sage) |
| **AIFE (État français)** | XML UBL 2.0 encapsulant un zip du PDF (encodé base64) |
| **e-FFF (Belgique)** | XML UBL 2.0 encapsulant le PDF (encodé base64) |

#### Versions compatibles

- Sage 100 V8.10 et suivantes (on-premise)
- Sage 100 version hébergée 2019.1 et suivantes
- Sage 1000 version 6.50 et suivantes

#### Processus d'échange

1. **Inscription** de la société et de ses établissements sur la plateforme
2. **Actualisation** de la base client depuis l'application métier Sage
3. **Invitation** des clients acceptant l'échange électronique
4. **Envoi des factures** électroniques pour les clients acceptant l'échange
5. **Réception** des factures : intégration ou refus
6. **Émission optionnelle** du Compte Rendu de Rapprochement et/ou du Bon à payer
7. **Suivi** des factures transmises

#### Scénarios de statuts

| Statut | Description |
|---|---|
| En attente de réponse d'invitation | Invitation envoyée, en attente d'acceptation |
| Invitation vérifiée | Invitation acceptée, échange possible |
| Facture déposée | Facture transmise sur la plateforme |
| Facture refusée | Destinataire a refusé la facture |
| Facture validée | Destinataire a validé la facture |
| Facture encaissée | Paiement enregistré |
| Erreur | Invitation refusée/révoquée |

### 19.3 Logique métier

Sage eFacture fonctionne sur le principe de **l'invitation réciproque** : pour échanger électroniquement, les deux parties doivent avoir accepté la dématérialisation. Une fois l'invitation acceptée, les factures circulent automatiquement entre les systèmes Sage des deux entreprises, avec intégration comptable sans ressaisie.

L'**archivage à valeur probante** pendant 10 ans assure la conservation léggal des documents. Le contrôle de la signature électronique garantit l'intégrité des documents échangés.

---

## 20. Sage Data Clean & Control (SDCC)

### 20.1 Vue d'overview

Sage Data Clean & Control (SDCC) est une **option payante** de Sage 100 qui automatise le traitement des factures en réception et contrôle la qualité des données en vue de la conformité à la réforme de la facture électronique.

### 20.2 Fonctionnalités détaillées

#### Automatisation de la réception des factures

- **Automatisation de la saisie de la pièce comptable** en réception de factures en Comptabilité
- **Automatisation du rapprochement** de l'historique des commandes / bons de livraison lors de la réception des factures en Gestion commerciale
- **Proposition de schémas comptables** par tiers (V12) : SDCC propose automatiquement les comptes à utiliser

#### Contrôle de la base de données

- **État des lieux des données obligatoires** pour la facture électronique
- **Actualisation des informations** : identification des données manquantes ou incorrectes
- **Contrôle des champs obligatoires** : SIREN, adresse, TVA, IBAN, etc.
- **Mise en conformité** des fiches tiers et articles

#### Intégration avec Sage Connect

- Les factures reçues via Sage Connect s'affichent en PDF dans Sage 100
- SDCC automatise le rapprochement avec les bons de commande et les bons de livraison
- Validation en un clic générant automatiquement les écritures comptables ou les documents d'achat

### 20.3 Logique métier

SDCC joue un double rôle dans la **préparation à la facture électronique** :

1. **En amont** : il audite la base de données (tiers, articles) pour identifier les informations manquantes qui seraient obligatoires dans une facture électronique (SIREN, adresse complète, taux de TVA, etc.). L'utilisateur peut corriger les données avant la mise en conformité.

2. **En opérationnel** : il automatise le traitement des factures reçues en proposant les bons comptes et en rapprochant les factures avec les commandes et livraisons existantes. Cela réduit le temps de saisie et les erreurs.

Sans SDCC, la réception d'une facture électronique nécessiterait une saisie manuelle dans Sage 100. Avec SDCC, la facture est pré-remplie et l'utilisateur ne fait que valider.

---

## 21. Sage Automatisation Comptable (ACS)

### 21.1 Vue d'overview

Sage Automatisation Comptable (ACS) est une solution **SaaS** qui dématérialise et automatise le traitement complet des factures fournisseurs. Connectée nativement à Sage 100 Comptabilité via les Objets Métiers, elle élimine la saisie manuelle et sécurise le processus d'achat.

### 21.2 Fonctionnalités détaillées

#### Collecte multi-canal des factures

| Canal | Description |
|---|---|
| **Glisser-déposer** | Dépôt direct de fichiers (PDF, Factur-X, images) |
| **Adresse email dédiée** | Les factures envoyées par email sont automatiquement captées |
| **Collecteurs portails fournisseurs** | Connexion automatique aux portails (Orange, Engie, EDF…) |
| **Connexion SFTP** | Pour les volumes importants |
| **Photo via mobile** | Photographie d'une facture papier depuis l'application mobile |
| **Plateforme Agréée Sage** | Réception des factures électroniques via Sage Network |

#### Extraction automatique (OCR/LAD)

- **OCR (Reconnaissance Optique de Caractères)** : lecture automatique des informations de la facture
- **LAD (Lecture Automatique de Documents)** : extraction des données structurées
- **Informations extraites** : montants, TVA, IBAN, SIREN, dates, lignes détaillées de la facture
- **Reconnaissance des champs** : en-tête, lignes, pied de page
- **Contrôles de cohérence** : équilibre des montants, cohérence TVA

#### Contrôles et alertes

- **Vérification de l'IBAN** : comparaison entre l'IBAN de la facture et l'IBAN de la fiche fournisseur dans Sage 100 → alerte positive si correspondance, alerte négative si différence (prévention fraude au changement d'IBAN)
- **Détection des doublons** : une facture déjà traitée ou en cours de traitement est identifiée
- **Contrôle des montants** : si les montants ne correspondent pas, ACS bloque la facture
- **Alertes de délai** : si une facture n'a pas été traitée dans un délai défini
- **Contrôle du SIREN** : cohérence entre la facture et la fiche fournisseur

#### Circuits de validation (Workflow)

- **Jusqu'à 10 étapes de validation** selon des règles précises :
  - Type de document
  - Service ou société concernée
  - Montant ou devise
  - Fournisseur spécifique
  - Centre de coût
- **Circuits personnalisables** : adaptation aux règles internes de l'entreprise
- **Bon à payer** : une facture ne peut être payée tant qu'elle n'a pas été validée selon les règles définies
- **Traçabilité totale** : horodatage et identification de chaque intervention
- **Relances automatiques** : si un validateur tarde à valider, des rappels ciblés sont envoyés
- **Validation mobile** : accès au processus de validation depuis l'application mobile

#### Intégration Sage 100

- **Connexion via Objets Métiers** : agent installé en local utilisant les Objets Métiers de Sage
- **Récupération des grilles de ventilation analytique** Sage
- **Récupération des conditions de règlement** de chaque fournisseur
- **Création de modèles de saisie** possibles
- **Envoi en temps réel** vers Sage 100 Comptabilité : pas de mise à jour manuelle, pas d'export intermédiaire
- **Retour d'information** : lorsqu'une facture est payée et lettrée dans Sage 100, cette information remonte dans ACS (statut, date de paiement)

#### Archivage

- **Archivage fiscal légal** : espace sécurisé à valeur probante
- **Moteur de recherche intelligente** : recherche sur l'ensemble des documents et données
- **Conservation** conforme aux exigences de l'administration fiscale
- **5 Go inclus** pour le classement des documents d'achats

#### Gestion des ventes (V2)

- **Conversion PDF → Factur-X** : transformation des factures clients en format électronique
- **Envoi via la Plateforme Agréée Sage**
- **Circuit de validation en amont** pour éviter les erreurs
- **Comptabilisation automatique** après envoi
- **Synchronisation du statut de paiement** depuis Sage 100

#### Demandes d'achat (V2)

- **Création de demandes d'achat** avec masques de saisie dédiés
- **Workflow de validation** des demandes
- **Génération automatique de bons de commande**
- **Rapprochement automatique** avec les factures reçues
- **Couverture du cycle achat complet** : de la demande à la comptabilisation

#### Fonctionnalités complémentaires

- **Double validation IBAN** : workflow de validation pour les ajouts/modifications de RIB
- **Import Excel avancé** : saisie en masse d'écritures comptables
- **Détection de doublons** (hors ACS) : empêche la saisie de doublons dans Sage Comptabilité
- **Connecteurs Stripe/PayPal** : intégration automatique des règlements clients
- **Import d'extraits bancaires** : remplace Sage Direct, utile en multi-sociétés

### 21.3 Logique métier

ACS transforme le **cycle des achats** en processus entièrement digital :

```
Réception facture (multi-canal) → OCR extraction → Contrôles (IBAN, doublons, montants)
→ Circuit de validation (workflow) → Bon à payer → Intégration Sage 100 Comptabilité
→ Paiement → Lettrage → Retour d'information vers ACS
```

L'enjeu est triple :
1. **Productivité** : 45% d'économie sur le coût global de traitement, 6€ d'économie par facture
2. **Sécurité** : prévention de la fraude au changement d'IBAN, contrôle des doublons
3. **Conformité** : archivage fiscal légal, traçabilité totale, préparation à la facture électronique 2026

ACS **centralise 100% des factures fournisseurs** : les factures électroniques issues de la PA Sage (flux français) ET les factures PDF des fournisseurs internationaux (non soumis à la RFE française). L'entreprise a un point d'entrée unique pour tout son cycle d'achats.

---

## 22. Objets Métiers, API SData & Interopérabilité

### 22.1 Objets Métiers

#### Vue d'ensemble

Les **Objets Métiers Sage** sont une **bibliothèque COM/ActiveX** qui fournit une couche d'accès sécurisée et structurée aux données de Sage 100. Ils encapsulent la logique métier de Sage (règles de validation, calculs, contrôles) et permettent à des applications tierces de lire et écrire dans la base Sage sans accès direct au SQL.

#### Architecture

```
Application tierce → Objets Métiers (COM/ActiveX) → Base SQL Sage 100
                     ↑ Règles métier, validations, calculs
```

#### Objets disponibles

Chaque module expose ses objets métiers :

| Module | Objets métiers principaux |
|---|---|
| **Comptabilité** | FicheEcriture, FicheJournal, FicheCompte, FicheTiers, FicheEcheance |
| **Gestion Commerciale** | FicheDevis, FicheCommande, FicheBonLivraison, FicheFacture, FicheArticle, FicheClient, FicheFournisseur |
| **Moyens de Paiement** | FicheVirement, FichePrelevement, FicheMandatSEPA |
| **Immobilisations** | FicheImmobilisation, FicheAmortissement |
| **Paie & RH** | FicheSalarie, FicheBulletin, FicheEtablissement |

#### Avantages

- **Sécurité** : pas d'accès direct au SQL, les règles de validation sont appliquées
- **Intégrité des données** : les Objets Métiers garantissent la cohérence (ex : une écriture comptable est toujours équilibrée)
- **Logique métier encapsulée** : les calculs (TVA, échéances, amortissements) sont effectués par les Objets Métiers, pas par l'application tierce
- **Compatibilité** : utilisables depuis .NET, VBA, Python, PHP, etc.
- **Utilisation par ACS** : ACS se connecte à Sage 100 via les Objets Métiers pour garantir la sécurité et l'intégrité

#### Cas d'usage

- **Intégration d'un site e-commerce** : création de commandes et factures dans Sage 100 depuis un site web
- **Import de données** depuis un fichier Excel ou CSV via un script
- **Synchronisation** avec un CRM tiers (Salesforce, HubSpot)
- **Automatisation** de tâches répétitives (génération d'écritures, mise à jour de fiches)
- **Connecteurs** développés par les partenaires Sage (Clictill, SenSaaS, EDI, etc.)

### 22.2 API SData

#### Vue d'ensemble

**SData** (Sage Data) est un **protocole RESTful** basé sur HTTP/HTTPS qui permet d'échanger des données avec Sage 100 au format XML ou JSON. Il est construit au-dessus des Objets Métiers et expose les fonctionnalités de Sage 100 sous forme d'API web.

#### Architecture

```
Application tierce → Requête HTTP/HTTPS (SData) → Serveur SData → Objets Métiers → Base SQL
                    Format : XML (Atom) ou JSON
                    Authentification : Basic, OAuth
```

#### Fonctionnalités

- **Opérations CRUD** : Create, Read, Update, Delete sur tous les objets métiers
- **Requêtes filtrées** : sélection par critères (ex : `?where=CodeClient eq 'C001'`)
- **Pagination** : gestion des grands volumes (`?startIndex=0&count=100`)
- **Tri** : ordre des résultats (`?orderby=DateCreation desc`)
- **Batch** : opérations en lot
- **Template** : récupération d'un modèle vide pour création
- **Lookup** : recherche par référence
- **Liens** : navigation entre objets liés (ex : les lignes d'une facture)

#### Exemple de requête

```http
GET /sdata/sage100/compta/~/FicheEcriture?where=DatePiece ge '2025-01-01'&count=50
Authorization: Basic dXNlcjpwYXNzd29yZA==
Accept: application/json
```

#### Sécurité

- **Authentification** : Basic Auth ou OAuth 2.0
- **Chiffrement** : HTTPS obligatoire en production
- **Droits d'accès** : respect des droits utilisateurs Sage 100
- **Rate limiting** : protection contre les requêtes abusives

### 22.3 Autres technologies d'interopérabilité

| Technologie | Type | Usage |
|---|---|---|
| **Import/Export paramétrable** | Fichiers CSV/TXT | Import en masse de données |
| **ODBC** | Connexion base de données | Lecture directe (en lecture seule recommandé) |
| **Web Services** | SOAP/REST | Intégration applicative |
| **Sage Business Object API** | .NET | Développement C#/VB.NET |
| **Connect Import** | Assistant d'import | Import de données externes (Paie V7.10+) |

### 22.4 Logique métier

L'interopérabilité de Sage 100 repose sur le principe de **sécurité par encapsulation** : plutôt que de donner un accès direct au SQL (risqué), Sage fournit des Objets Métiers qui appliquent toutes les règles de validation. Une application tierce qui crée une écriture comptable via les Objets Métiers bénéficie des mêmes contrôles qu'un utilisateur saisissant dans l'interface Sage 100 : équilibre débit/crédit, validité des comptes, cohérence des dates, etc.

SData étend cette logique au web, permettant à des applications distantes (cloud, mobile, e-commerce) d'interagir avec Sage 100 de manière sécurisée et standardisée.

---

## 23. Sage Sales Management

### 23.1 Vue d'ensemble

Sage Sales Management (anciennement ForceManager) est un **CRM mobile propulsé par l'IA**, intégré à Sage 50 et Sage 100. Il est conçu pour les équipes commerciales nomades (terrain) et optimise les techniques de vente grâce à l'IA et à la mobilité.

### 23.2 Fonctionnalités détaillées

#### CRM mobile (iOS & Android)

- **Application native** iOS et Android
- **Check-in / Check-out** : enregistrement du début et de fin de visite avec géolocalisation
- **Visites géolocalisées** : carte interactive des clients à proximité
- **Itinéraires optimisés** : planification du meilleur parcours avec validation des temps de trajet
- **Mode hors-ligne** : consultation des fiches clients sans connexion
- **Dictée vocale** de comptes-rendus via Sage Copilot (IA)

#### Gestion des contacts et opportunités

- **Gestion des clients, contacts, leads et opportunités**
- **Pipeline commercial visuel** : étapes du cycle de vente
- **Suivi des objectifs de ventes** en temps réel
- **Collaboration d'équipe** : partage des informations

#### Communications intégrées

- **Appels, emails, visites** enregistrés en quelques secondes
- **Intégration WhatsApp** : communication en un clic
- **Intégration Office 365** : calendriers et emails synchronisés
- **Visioconférences** : enregistrement des réunions à distance

#### Devis et commandes (module complémentaire)

- **Création de devis et offres** sur mobile
- **Catalogue de produits** avec règles de prix et remises personnalisées
- **Signature électronique** sur le téléphone (conformité légale)
- **Partage PDF** par WhatsApp ou email
- **Transformation devis → commande** sans ressaisie
- **Synchronisation avec l'ERP** : données automatiquement intégrées dans Sage 100

#### Signature numérique

- **SignatureManager** : solution de signature légale et numérique
- **Accélération des processus commerciaux** : validation à distance
- **Sécurité juridique** : conformité eIDAS

#### IA et analyse

- **Sage Copilot** : assistant IA pour la saisie (dictée vocale de comptes-rendus)
- **Analyse des ventes et des activités** : données clés organisées pour la prise de décision
- **Accélérateur de ventes** : gestion avancée des objectifs d'activité et de vente
- **Communications avec confirmation de lecture** pour les équipes

#### Intégration Sage 100

- **Intégration native avec Sage 100** : gestion comptable et financière, commerciale, trésorerie
- **Synchronisation en temps réel** : clients, devis, commandes, factures
- **Modules complémentaires Devis et Commandes**
- **Connecteur et installation** inclus

#### Offres

| Offre | Cible | Fonctionnalités |
|---|---|---|
| **Sage Sales Management** | TPE/PME | CRM mobile, géolocalisation, devis, signature, intégration Sage 50 |
| **Sage Sales Management Pro** | Moyennes et grandes entreprises | Toutes les fonctionnalités + intégration Sage 100, analyse d'équipe, communications avec confirmation de lecture, signature numérique à distance |

### 23.3 Logique métier

Sage Sales Management adresse le **chaînon manquant** entre le terrain commercial et l'ERP. Un commercial en déplacement peut :

```
Visiter un client (check-in géolocalisé) → Consulter l'historique et les opportunités
→ Créer un devis sur mobile (catalogue + tarifs) → Faire signer électroniquement
→ Envoyer le devis par WhatsApp/email → La commande remonte automatiquement dans Sage 100
→ La facture est générée sans ressaisie
```

L'IA **Sage Copilot** réduit le temps administratif : au lieu de saisir un compte-rendu de visite, le commercial dicte vocalement et l'IA structure l'information. Gain estimé : **jusqu'à 2 heures par semaine** par commercial sur les tâches administratives.

---

## 24. SenSaaS

### 24.1 Vue d'ensemble

SenSaaS est une solution **full SaaS** qui donne accès aux données de Sage 100 Gestion Commerciale via une simple connexion internet. Elle apporte des fonctionnalités innovantes et complémentaires à Sage 100 pour la mobilité commerciale.

### 24.2 Fonctionnalités détaillées

#### Module Vente (actuellement commercialisé)

- **Consultation de tous les documents de vente** : devis, commandes, livraisons, factures
- **Création et modification de devis et commandes** de vente
- **Deux approches de saisie** :
  1. **Approche e-commerce (panier)** : navigation dans le catalogue, ajout au panier, création du document — idéal pour la vente par téléphone ou en rendez-vous
  2. **Approche saisie de document** : saisie complète avec en-tête et lignes, articles simples/gammes/fabrication/nomenclatures
- **Consultation des stocks** en temps réel pendant la saisie
- **Tarifs personnalisés** par client
- **Historique client** : consultation des documents précédents
- **Photos d'articles** : visuel dans le catalogue
- **Signature électronique** des documents (enregistrée comme document joint dans Sage 100)
- **Impression PDF** personnalisée (technologie FastReport)
- **Mode dégradé** : adapté aux connexions internet bas débit et bases volumineuses

#### Fonctionnalités transverses

- **Multi-sociétés** : connexion à plusieurs bases Sage 100
- **Personnalisation et sécurité** : profils adaptés, confidentialité garantie
- **Géolocalisation** des clients
- **Vente en mode panier** : expérience e-commerce
- **Articles avec photo**
- **Connexion des clients** : accès externe possible
- **Filtres avancés** : par société, par profil utilisateur, par utilisateur, par ancienneté des documents, par familles d'articles, par pays/région des clients

#### Intégration Sage 100

- **Compatible avec les versions Sage 100 on-premise et SPC (cloud)**
- **Synchronisation bidirectionnelle** : toute modification dans Sage 100 est visible dans SenSaaS et inversement
- **Connecteur** : installation automatisée
- **Respect des droits d'accès** définis dans Sage 100

#### Fonctionnalités en développement

- Modèles d'enregistrement
- Informations libres calculées
- Documents en devise
- Gestion des statuts de documents
- Alertes d'encours et alertes sur stock en saisie
- Modification de la date de livraison en ligne de document
- Réservation de numéros de série/lot à la commande
- Saisie de formules dans la colonne conditionnement
- Calcul automatique du franco de port
- Intégration de documents (ex : DE à partir de BC)

### 24.3 Logique métier

SenSaaS **déploie la Gestion Commerciale Sage 100 sur le web**. L'objectif est de permettre à des commerciaux, des administratifs ou même des clients d'accéder aux données de vente depuis n'importe quel appareil connecté, sans installer Sage 100 sur leur poste.

Cas d'usage typique :
- Un nouveau collaborateur prend en main le catalogue produit sur SenSaaS avant de passer à la saisie de documents
- Un commercial en déplacement crée un devis sur tablette avec le catalogue et les tarifs à jour
- Un client consulte ses documents de vente en self-service

La **synchronisation bidirectionnelle** garantit que les données sont toujours cohérentes : si un article est créé ou un prix modifié dans Sage 100, la modification est immédiatement visible dans SenSaaS.

---

## 25. Clictill

### 25.1 Vue d'ensemble

Clictill est une **solution de caisse en ligne (SaaS)** destinée aux professionnels du commerce de détail et de la vente comptoir. Elle s'intègre à Sage 100 via un connecteur universel paramétrable (Open Flux).

### 25.2 Fonctionnalités détaillées

#### Gestion de la caisse

- **Encaissement rapide** : évite les files d'attente
- **Fonctionne sur navigateur** : aucune installation requise
- **Multi-appareils** : TPV, smartphone, tablette
- **Mode offline** : encaissement en cas de coupure internet, synchronisation au retour
- **Personnalisation de l'écran de caisse** : boutons produits, couleurs, menus, raccourcis
- **Ticket interactif**
- **Gestion des ventes, remises, retours et avoirs**
- **Bons cadeaux**
- **Factures**
- **Ouverture/fermeture de caisse**
- **Gestion des commandes clients**
- **Envoi des tickets par email**
- **Multi-caisses** : ajout/désactivation de postes, consolidation sur la caisse principale

#### Articles

- **Gestion de tous types d'articles** : code-barre (EAN13, EAN8, CODE39), poids/prix
- **Articles à gamme / déclinés**
- **Articles gérés en n° de lot / série**
- **Structure articles et familles**
- **Gestion des tarifs de vente** : standard, pro, VIP, promo
- **Tarifs personnalisés** appliqués automatiquement selon le client identifié

#### Clients

- **Gestion des comptes clients**
- **Typologies Particulier / Professionnel**
- **Encours client** avec contrôle du montant maximum autorisé
- **Champs d'acceptation RGPD**
- **Contrôle de l'unicité des emails client**

#### Animations commerciales

- **Programmes de fidélité** : points, passages, récompenses, avantages exclusifs
- **Gestion des promotions**
- **Couponing, bons d'achats**
- **Cartes d'abonnement**

#### Gestion des stocks et approvisionnement

- **Propositions de réassort**
- **Commandes d'achats**
- **Avis de livraisons, réceptions et retours de marchandises**
- **Transferts inter-boutiques**
- **Régularisations de stock / Inventaires**
- **Gestion des rayons, familles, sous-familles**
- **N° de séries, n° de lots, codes-barres, articles poids/prix**
- **Gestion des fournisseurs, marques, catégories**

#### Back-office et reporting

- **Module de connexion avec un site Web Prestashop** : e-commerce omnicanal
- **Gestion du mode hors ligne** et **multi-langues**
- **Module de génération et export des écritures comptables**
- **Gestion du coffre et des remises en banque**
- **Gestion et impression des étiquettes**
- **Suivi d'activités, journaux, synthèses**
- **Gestion des utilisateurs et des droits d'accès par profil**
- **Accès réservé expert-comptable**

#### Périphériques de caisse

- **Imprimantes de tickets**
- **TPE (Terminal de Paiement)**
- **Afficheur client**
- **Scanners / douchettes**
- **Tiroirs-caisses**
- **TPV (Terminal Point de Vente)**

#### Clictill Pay (caisse portable)

- **Terminal PAX A77** : Android 8.1, 4G + WiFi + Bluetooth, écran tactile 5.5"
- **Encaissement mobile** en rayon, pop-up store, événementiel
- **Scanner de code-barres intégré** : inventaires et réceptions de stock
- **Validation des ASN** (Avis de Sortie de Marchandise)
- **Sans contact + carte à puce + bande magnétique**
- **Certification NF525** : inaltérabilité, horodatage, sécurisation

#### Intégration Sage 100 (connecteur Open Flux)

- **Synchronisation automatique** des données entre Clictill et Sage 100 :
  - **Ventes** → Sage 100 Gestion Commerciale (remontée automatique)
  - **Stocks** → mise à jour en temps réel à chaque vente
  - **Clients** → cohérence entre le terrain et le siège
  - **Écritures comptables** → Sage 100 Comptabilité (génération automatique)
- **Évite les doubles saisies** et les erreurs de ressaisie
- **Tableaux de bord personnalisables** : CA, marge, panier moyen
- **Installation rapide** : connecteur prêt à l'emploi, paramétré par les équipes Clictill

### 25.3 Logique métier

Clictill est le **point de contact direct avec le client final** dans le commerce de détail. La logique métier suit le cycle :

```
Client en boutique → Scan article (code-barres) → Application tarif/promo/fidélité
→ Encaissement (espèces/CB/carte) → Ticket (papier/email) → Mise à jour stock
→ Remontée vente dans Sage 100 GC → Génération écriture comptable dans Sage 100 Compta
```

La **certification NF525** garantit la conformité fiscale : les tickets sont inaltérables, horodatés et sécurisés. En cas de contrôle, l'entreprise peut prouver l'intégrité de ses ventes.

Le **mode offline** est un avantage clé : contrairement à de nombreuses solutions SaaS, Clictill continue de fonctionner en cas de coupure internet. Les tickets sont enregistrés localement et synchronisés dès le retour de la connexion.

L'**omnicanalité** (boutique physique + e-commerce Prestashop) permet de gérer un stock unique et une politique tarifaire cohérente entre tous les canaux de vente.

---

## 26. Sage EDI

### 26.1 Vue d'ensemble

Sage EDI (Échange de Données Informatisé) permet de **dématérialiser et automatiser les échanges de documents commerciaux** entre entreprises selon des formats standardisés. Il répond aux exigences des plateformes d'achat qui imposent l'EDI comme standard obligatoire.

### 26.2 Standards et formats supportés

| Standard | Description |
|---|---|
| **EDIFACT** | Standard international de l'ONU pour l'échange de documents commerciaux |
| **INOVERT** | Standard français pour le transport et la logistique |
| **ORDERS** | Commande d'achat |
| **ORDRSP** | Réponse à la commande (accusé de réception) |
| **DESADV** | Avis d'expédition (livraison) |
| **INVOIC** | Facture |
| **810** | Facture d'achat (standard ANSI X12) |
| **812** | Ajustement de crédit/débit |
| **820** | Conseil de paiement |
| **846** | Rapport d'inventaire |
| **850** | Bon de commande |
| **855** | Accusé de réception du bon de commande |
| **856** | Avis d'expédition / Manifeste |
| **940** | Ordre d'expédition de l'entrepôt |

### 26.3 Fonctionnalités détaillées

#### Flux entrants (réception)

- **Réception de commandes clients** au format EDI → intégration automatique dans Sage 100 Gestion Commerciale
- **Réception d'avis d'expédition** fournisseurs → mise à jour des réceptions
- **Réception de factures** fournisseurs au format EDI → intégration comptable

#### Flux sortants (émission)

- **Envoi de confirmations de commande** (ORDRSP) aux clients
- **Envoi d'avis d'expédition** (DESADV) aux clients après livraison
- **Envoi de factures** (INVOIC) aux clients au format EDI
- **Envoi de commandes** fournisseurs au format EDI

#### Connecteurs EDI pour Sage 100

| Connecteur | Éditeur | Spécificité |
|---|---|---|
| **Connecteur EDI Logistique** | Tout-pour-la-gestion / Altaïs | Échange avec prestataire logistique (commandes, réceptions, expéditions, stock) |
| **Zest'EDI** | Zest'Info | Connexion avec plateforme EDI @GP, multi-sociétés, paramétrage par client final |
| **Vantree SCV** | Vantree | Suite de connectivité complète, mapping EDI, support partenaires |
| **Melorio EDI** | Melorio | Connexion directe Sage 100, contrôle manuel optionnel, flexibilité volumétrie |
| **Sage EDI (officiel)** | Sage | Plateforme 24/7, EDIFACT/INOVERT, interfaces spécifiques possibles |

#### Fonctionnalités avancées

- **Multi-sociétés** : connexion à plusieurs bases Sage 100
- **Paramétrage des flux par client final** : réception bons de commandes, envoi avis d'expédition, envoi factures
- **Utilisation des factures PDF** générées par Sage 100 (copie conforme sans régénération)
- **Traitements par dépôt dans la base Sage**
- **Envoi d'emails automatisés** : alertes sur anomalies ou bon déroulement
- **Activation/désactivation des échanges** par client et par type de flux (un simple clic)
- **Souches et statuts paramétrables** pour la création des pièces commerciales
- **Création d'articles génériques** : intégration de commandes dont les références sont inexistantes dans Sage 100
- **Contrôle manuel optionnel** : validation humaine avant intégration
- **Traçabilité** : respect des normes EDI, conformité

#### Secteurs spécifiques

| Secteur | Messages EDI | Usage |
|---|---|---|
| **Agro-alimentaire** | ORDERS, DESADV, INVOICE | Centrales d'achats, restauration collective |
| **Transport** | Ordres de mise en livraison, connaissement électronique | INTTRA, AP+, AMS, TRAXON |
| **Douane** | DELT@ | Déclarations normalisées au CID |
| **Entreposage** | Commandes et expéditions | Sage ENTREPOTS |

### 26.4 Logique métier

L'EDI transforme les échanges commerciaux en **flux automatisés** entre systèmes informatiques. La logique est :

```
Client (plateforme d'achat) → Commande EDI (ORDERS) → Connecteur EDI
→ Intégration auto dans Sage 100 GC (commande créée) → Préparation/Livraison
→ Avis d'expédition EDI (DESADV) → Facture EDI (INVOIC) → Client
```

L'EDI élimine la saisie manuelle, réduit les erreurs et accélère les échanges. Il est particulièrement crucial pour les entreprises qui vendent à des **centrales d'achat** (grande distribution, GMS) qui imposent ce standard.

Le **mapping EDI** définit la correspondance entre les champs du message EDI et les champs de Sage 100. Chaque partenaire commercial peut avoir son propre mapping, ce qui nécessite un paramétrage initial puis une maintenance minimale.

---

## 27. Sage Flux Bancaires

### 27.1 Vue d'ensemble

Sage Flux Bancaires est une **plateforme de communication bancaire** qui gère la télétransmission des fichiers bancaires (virements, prélèvements, extraits) via le protocole EBICS. Elle remplace progressivement Sage Direct et offre une sécurité renforcée.

### 27.2 Fonctionnalités détaillées

#### Protocoles supportés

| Protocole | Description | Niveau de service |
|---|---|---|
| **EBICS T** (Transport) | Transmission des fichiers bancaires uniquement | Communication |
| **EBICS TS** (Transport + Signature) | Transmission et signature électronique des fichiers | Communication et signature |

#### Gestion des contrats bancaires

- **Création de contrats bancaires** par société
- **Contrats en émission** : virements et prélèvements sortants
- **Contrats en réception** : extraits de comptes, relevés d'opérations
- **Contrats en émission sans signature** : pour les flux non critiques
- **Paramétrage du nombre de signatures** requises (EBICS TS)
- **PTK** : paramétrage fourni par le partenaire bancaire

#### Gestion des utilisateurs et droits

| Rôle | Droits |
|---|---|
| **Administrateur** | Paramétrage, signature, envoi de fichiers, consultation de tous les flux |
| **Communication** | Envoi de fichiers, consultation des flux émis et reçus |
| **Communication et signature** | Signature et envoi de fichiers, consultation des flux émis et reçus |

#### Traitement des fichiers

- **Ajout de fichiers** depuis Sage 100 (virements, prélèvements générés par Moyens de Paiement)
- **Analyse automatique** des fichiers lors de l'ajout
- **Signature électronique** : utilisation de certificats sur support matériel (token USB)
- **Télétransmission automatique** (option) ou manuelle vers la banque
- **Suivi des flux** : virements et prélèvements émis ou à émettre
- **Historique des sessions de transfert**
- **Gestion des rejets** : fichiers partiellement ou totalement rejetés, visualisation et extraction

#### Certificats

Trois types de certificats sont gérés :

1. **Certificats de la banque** : renouvelés tous les 5 ans par la banque, mise à jour automatique via requête HPB
2. **Certificats autogénérés de Transport** (EBICS T) : 3 certificats (Chiffrement, Authentification, Signature), renouvellement automatique par la plateforme Sage Flux Bancaires environ 3 mois avant expiration
3. **Certificats de signature** (EBICS TS) : générés par une autorité de certification reconnue par la banque, sur support matériel (token), renouvellement manuel avec alertes 30 jours avant expiration

#### Service de signature (Sage eID Sign)

- **Installation sur chaque poste client** concerné par la signature
- **Accès au certificat** via token USB
- **Code PIN** requis pour chaque signature
- **Alertes d'expiration** : affichage en orange 30 jours avant

#### Intégration avec Sage 100

- **Activation depuis Sage 100** : menu "Activer le service"
- **Ajout des sociétés** depuis Sage 100 via "Référencer une société"
- **Fichiers générés par Moyens de Paiement** → ajoutés automatiquement à Sage Flux Bancaires
- **Extraits bancaires reçus** → intégration dans Sage 100 Comptabilité (rapprochement) et Trésorerie

### 27.3 Logique métier

Sage Flux Bancaires est le **pont sécurisé** entre Sage 100 et les banques. Le flux est :

```
Sage 100 Moyens de Paiement → Génération fichier SEPA (pain.001/pain.008)
→ Sage Flux Bancaires → Analyse automatique → Signature électronique (EBICS TS)
→ Télétransmission EBICS → Banque
Banque → Extrait bancaire → Sage Flux Bancaires → Sage 100 Comptabilité + Trésorerie
```

La **signature électronique** (EBICS TS) apporte une sécurité supplémentaire : chaque fichier bancaire est signé avec un certificat sur token USB, ce qui garantit l'identité de l'émetteur et l'intégrité du fichier. La banque peut vérifier la signature avant d'exécuter les ordres de paiement.

Le **renouvellement automatique** des certificats de transport et les **alertes** pour les certificats de signature réduisent la maintenance et évitent les interruptions de service.

---

## 28. Stockage & Partage Microsoft 365

### 28.1 Vue d'ensemble

L'option **Stockage et Partage Microsoft 365** permet de stocker automatiquement les documents Sage 100 (factures, devis, fiches clients, écritures comptables) dans **OneDrive / SharePoint** de l'entreprise. Elle élimine les risques de doublons et structure le classement des documents.

### 28.2 Fonctionnalités détaillées

#### Activation et paramétrage

- **Activation depuis Sage 100** : Paramètres société → Échanges de données → Stockage et partage Office 365 → "Activer le stockage"
- **Authentification Microsoft 365** : connexion avec un compte administrateur disposant des droits de création de groupe
- **Création automatique d'un groupe** "Sage – Raison sociale" dans OneDrive/SharePoint
- **Activation par société** : option valable pour l'ensemble des applications (Comptabilité + Gestion Commerciale)
- **Bouton "Me connecter / Me déconnecter"** : gestion de l'authentification

#### Documents pris en charge

| Type de document | Source |
|---|---|
| **Pièces commerciales d'achats/ventes** | Gestion Commerciale |
| **Documents internes** | Comptabilité / GC |
| **Sections analytiques** | Comptabilité |
| **Documents de stocks** | Gestion Commerciale |
| **Documents joints aux fiches articles** | Gestion Commerciale |
| **Fiches clients / fournisseurs / salariés** | Comptabilité / GC / Paie |
| **Écritures comptables** | Comptabilité |
| **Relevés** | Comptabilité / Trésorerie |
| **Rappels** | Comptabilité |
| **Sauvegarde fiscale** | Comptabilité |

#### Classement automatique

- **Classement par type de document et par tiers** : le système se charge de ranger automatiquement les documents dans les bons répertoires
- **Uniformisation** pour tous les collaborateurs : processus de gestion des documents standardisé
- **Élimination des doublons** : centralisation et organisation

#### Métadonnées (V7+)

- **Ajout automatique de métadonnées** aux fichiers lors du stockage dans OneDrive/SharePoint
- **Colonnes de site SharePoint** : création dans SharePoint avec respect du nommage réservé Sage
- **Filtrage par métadonnées** : recherche rapide par tiers, date, type de document
- **Personnalisation des vues** SharePoint
- **Correspondance** entre champs de la base de données Sage et colonnes SharePoint

#### Collaboration et partage

- **Partage de fichiers** avec des personnes internes ou externes à l'organisation
- **Partage de dossiers** : navigation limitée au dossier et ses sous-dossiers
- **Partage du site** SharePoint complet
- **Gestion des accès** : modification ou consultation seule
- **Liens de partage** : envoi par email avec code de vérification
- **Arrêt du partage** : à tout moment, gestion des accès

#### Mobilité

- **Accès depuis smartphone, tablette, PC ou MAC**
- **Consultation directe depuis Sage 100** : les documents stockés dans M365 sont accessibles depuis les fiches tiers, articles, entêtes de documents
- **Synchronisation montante et descendante** :
  - **Montante** : un document envoyé depuis Sage 100 vers M365 est classé automatiquement
  - **Descendante** : un document copié directement dans M365 depuis un navigateur est synchronisé et accessible depuis Sage 100

#### Fonctionnalités avancées

- **Historique des versions** : consultation des révisions (ex : révisions d'un devis)
- **Alertes** : notification en cas d'ajout de documents sur un répertoire partagé
- **Publication de la sauvegarde fiscale** dans l'espace M365
- **Intégration avec Microsoft Flow** : processus métiers automatisés
- **Notifications par SMS** : via Power Apps

#### Migration depuis Sage Document Manager

- Une fois le stockage M365 activé, **il n'est plus possible d'envoyer des documents vers Sage Document Manager**
- En cas de désactivation : les documents ne sont pas rapatriés automatiquement, rattachement manuel nécessaire
- Le groupe SharePoint "Sage – Raison sociale" n'est pas supprimé automatiquement

### 28.3 Logique métier

Le stockage M365 transforme Sage 100 en **gestionnaire électronique de documents (GED)** sans solution tierce. La logique est :

```
Sage 100 génère un document (facture, devis, fiche) → Envoi automatique vers M365
→ Classement automatique par type et par tiers → Métadonnées ajoutées
→ Accessible depuis Sage 100 (fiche tiers/article) ET depuis M365 (navigateur, mobile)
→ Partageable avec expert-comptable, clients, collaborateurs
```

L'enjeu est triple :
1. **Productivité** : plus de classement manuel, plus de recherche dans des dossiers physiques
2. **Collaboration** : partage sécurisé avec l'expert-comptable (lien vers une facture d'achat), avec un client (lien vers un devis)
3. **Mobilité** : accès aux documents depuis n'importe quel appareil, n'importe où

La **synchronisation descendante** est un atout majeur : si un utilisateur dépose un PDF (ex : une notice technique) directement dans SharePoint, ce document devient immédiatement accessible depuis la fiche article correspondante dans Sage 100.

---

## 29. Évolutions par version (V9 → V12)

### 29.1 Version 9 (2023)

#### Comptabilité

- Affichage des soldes dans les listes (comptes généraux, tiers, journaux)
- Solde progressif dans l'interrogation tiers
- Gestion automatisée de la TVA sur les acomptes
- Distinction des taxes sur les véhicules de société (TVS)

#### Gestion Commerciale

- Affichage des encours tiers dans les listes fournisseurs et clients
- Paramétrage d'envoi par email par tiers et par type de document
- Refresh Gamme/Nomenclature sans quitter la fiche
- Facture électronique au format Factur-X

### 29.2 Version 10 (2023-2024)

#### Introduction de Sage Data Clean & Control (SDCC)

- Module optionnel pour le contrôle des données en vue de la facture électronique
- Automatisation de la saisie des pièces comptables en réception
- Rapprochement automatique avec les commandes / bons de livraison

#### Préparation à la facture électronique

- Premiers outils de mise en conformité
- Sensibilisation à la réforme 2026

### 29.3 Version 11 (2024-2025)

#### Sage Connect

- Introduction du connecteur Sage Connect pour la réception des factures électroniques
- Intégration native avec Sage Network
- Tuile IntuiSage pour l'inscription à la PA Sage

#### Norme ANC 2025

- Assistant de mise en conformité avec la norme ANC 2025
- Ajustement du plan comptable (nouveaux comptes, mise en sommeil)
- Mise à jour des rubriques des états légaux

#### Interface

- IntuiSage modernisé avec tableaux de bord redessinés
- Navigation plus intuitive

### 29.4 Version 12 (2025) — La version stratégique

#### Comptabilité

| Nouveauté | Impact métier |
|---|---|
| Inscription PA Sage depuis IntuiSage | Centralise la conformité facture électronique |
| Compte bancaire société par fiche tiers | Automatise l'IBAN dans les factures électroniques |
| Réception factures fournisseurs (volet écriture) + SDCC | Supprime l'obligation de modèle de saisie |
| 10 exercices consultables (au lieu de 5) | Double la profondeur d'historique |
| Clôture : messages plus clairs | Réduit les blocages de fin de période |
| Conversions sans "Maintenance" | Fluidifie les mises à jour |
| Lettrage plus intuitif et rapide | Gain de productivité |
| Filtres de recherche avancés | Gain de temps dans les analyses |
| Connectivité bancaire optimisée | Fiabilise le rapprochement |
| Suivi des règlements amélioré | Meilleure visibilité trésorerie |
| Dossiers de recouvrement (Hébergée/SPC) | Démocratise l'accès au recouvrement |

#### Gestion Commerciale

| Nouveauté | Impact métier |
|---|---|
| Inscription PA Sage depuis IntuiSage | Anticipe la réforme facture électronique |
| Messages d'erreur améliorés (Sage Network) | Réduit les appels support |
| Notification de fin de transmission | Sécurise l'étape d'envoi |
| Compte bancaire "préféré" par tiers | Conformité facture électronique |
| Mise à jour comptable : aide à la correction | Accélère la résolution des anomalies |
| Factures d'acompte en devises | Cohérence comptable des acomptes |
| Refonte des fiches clients/fournisseurs | Meilleure lisibilité |
| Personnalisation accrue des documents | Adaptation à l'image de marque |
| Gestion des reliquats améliorée | Meilleur suivi des livraisons partielles |

#### Moyens de Paiement

| Nouveauté | Impact métier |
|---|---|
| Virements instantanés SEPA | Règlement en quelques secondes 24/7 |
| Adresses structurées ISO 20022 | Améliore la qualité des échanges bancaires |
| Intégration fluide avec Sage Direct | Simplifie les envois bancaires |
| Sécurité renforcée des transactions | Prévention des fraudes |
| Meilleur contrôle des ordres de virement | Diminue les risques d'erreurs |

#### États Comptables et Fiscaux

| Nouveauté | Impact métier |
|---|---|
| Mise à jour des formats fiscaux 2025 | Conformité réglementaire |
| Génération automatisée des liasses fiscales | Réduction du temps de production |
| Production simplifiée des fichiers FEC | Fluidifie les contrôles fiscaux |
| Nouveaux modèles d'impression | Mise à jour des présentations |

#### Immobilisations

| Nouveauté | Impact métier |
|---|---|
| Extension à 10 exercices consultables | Facilite les contrôles pluriannuels |

#### Transverse

| Nouveauté | Impact métier |
|---|---|
| APIs et Objets Métiers enrichis | Meilleure interopérabilité |
| Sécurité renforcée | Protection des données |
| Performance optimisée | Fluidité d'utilisation |

### 29.5 Recommandation de migration

Tous les sources consultés (apogea, blc-conseil, ig-conseils, tout-pour-la-gestion, performa-gestion) recommandent une **migration précoce vers V12** pour :

1. **Conformité réglementaire** : facture électronique 2026, norme ANC 2025, formats fiscaux à jour
2. **Productivité** : automatises étendues, interface optimisée, exercices consultables doublés
3. **Sécurité** : renforcement des contrôles et de la protection des données
4. **Interopérabilité** : APIs enrichies, intégration native avec Sage Network
5. **Anticipation** : éviter la précipitation de dernière minute avant les échéances réglementaires

---

## 30. Logique métier transverse et flux inter-modules

### 30.1 Architecture des flux

Sage 100 fonctionne comme un **système intégré** où les modules communiquent en temps réel via une base de données commune. Voici la cartographie des flux principaux :

```
┌─────────────────────────────────────────────────────────────┐
│                    SAGE 100 — FLUX INTER-MODULES             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    factures     ┌──────────────┐          │
│  │  Gestion     │ ──────────────→ │  Comptabilité │          │
│  │  Commerciale │ ←────────────── │              │          │
│  │              │    mise à jour   │              │          │
│  └──────┬───────┘                 └──────┬───────┘          │
│         │                                │                   │
│    stocks│                          échéances│               │
│         │                                │                   │
│         ▼                                ▼                   │
│  ┌──────────────┐    règlements    ┌──────────────┐          │
│  │  SCD /       │ ──────────────→ │   Moyens de   │          │
│  │  Clictill    │                 │   Paiement    │          │
│  └──────────────┘                 └──────┬───────┘          │
│                                          │                   │
│                                    flux SEPA│                │
│                                          ▼                   │
│                                   ┌──────────────┐          │
│                                   │  Flux         │          │
│                                   │  Bancaires    │          │
│                                   │  (EBICS)      │          │
│                                   └──────┬───────┘          │
│                                          │                   │
│                                   extraits│                  │
│                                          ▼                   │
│  ┌──────────────┐  dotations     ┌──────────────┐          │
│  │ Immobilisat. │ ──────────────→ │  Trésorerie  │          │
│  │              │                 │  (extraits)  │          │
│  └──────────────┘                 └──────────────┘          │
│                                                              │
│  ┌──────────────┐  écritures      ┌──────────────┐          │
│  │  Paie & RH   │ ──────────────→ │  Comptabilité │          │
│  └──────┬───────┘                 └──────────────┘          │
│         │                                                      │
│    bulletins│                                                   │
│         ▼                                                      │
│  ┌──────────────┐                                             │
│  │ Démat. RH    │                                             │
│  │ (coffre-fort)│                                             │
│  └──────────────┘                                             │
│                                                              │
│  ┌──────────────┐  opportunités  ┌──────────────┐           │
│  │  CRM Force   │ ──────────────→ │  Gestion     │           │
│  │  de Vente    │   devis         │  Commerciale │           │
│  └──────────────┘                 └──────────────┘           │
│                                                              │
│  ┌──────────────┐  factures      ┌──────────────┐           │
│  │  ACS         │ ──────────────→ │  Comptabilité │           │
│  │  (achats)    │                 │              │           │
│  └──────────────┘                 └──────────────┘           │
│                                                              │
│  ┌──────────────┐  écritures      ┌──────────────┐           │
│  │  Espace      │  notes de frais │  Comptabilité │           │
│  │  Employés    │ ──────────────→ │              │           │
│  └──────────────┘                 └──────────────┘           │
│                                                              │
│  ┌──────────────┐                                             │
│  │  Sage        │  factures électroniques (émission/réception)│
│  │  Network     │ ←──────────────→ Sage 100 (tous modules)   │
│  └──────────────┘                                             │
│                                                              │
│  ┌──────────────┐  documents      ┌──────────────┐           │
│  │  Stockage    │ ←────────────── │  Sage 100     │           │
│  │  M365        │                 │  (tous)      │           │
│  └──────────────┘                 └──────────────┘           │
│                                                              │
│  ┌──────────────┐                                             │
│  │  BI          │  données temps réel ← Sage 100 (tous)      │
│  │  Reporting   │                                             │
│  └──────────────┘                                             │
│                                                              │
│  ┌──────────────┐                                             │
│  │  Recouvrement│  écritures comptables ← Sage 100 Compta    │
│  │  Créances    │  relances → clients                        │
│  └──────────────┘                                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 30.2 Principes d'intégration

#### 1. Saisie unique

Une information saisie dans un module alimente automatiquement les autres modules concernés. Exemples :
- Une facture de vente créée en Gestion Commerciale génère l'écriture comptable dans Comptabilité
- Un virement créé en Moyens de Paiement génère l'écriture de règlement dans Comptabilité et met à jour le solde en Trésorerie
- Une dotation calculée en Immobilisations génère l'écriture de dotation dans Comptabilité

#### 2. Temps réel

Les flux entre modules sont **immédiats** (sauf configuration contraire). Il n'y a pas de traitement par lot différé : la validation d'une facture en GC met instantanément à jour la comptabilité, les encours clients et la trésorerie prévisionnelle.

#### 3. Traçabilité

Chaque opération est **historisée** avec :
- Date et heure de création/modification/suppression
- Utilisateur ayant effectué l'action
- Avant/après pour les modifications
- Conformité loi anti-fraude (inaltérabilité, sécurisation)

#### 4. Contrôle de cohérence

Les modules appliquent des **règles de validation** lors des flux inter-modules :
- Une écriture comptable doit être équilibrée (débit = crédit)
- Un compte tiers doit exister dans le plan comptable
- Les montants TVA doivent être cohérents avec les montants HT et TTC
- Les échéances doivent respecter les conditions de règlement du tiers

### 30.3 Conformité réglementaire transverse

| Obligation | Modules concernés | Mécanisme |
|---|---|---|
| **FEC** | Comptabilité, ECF | Génération du fichier des écritures comptables |
| **Loi anti-fraude** | Comptabilité, GC, SCD, Clictill | Journal d'audit, inaltérabilité, certification |
| **DSN** | Paie & RH | Télétransmission mensuelle |
| **RGPD** | Tous modules | Gestion des données personnelles, cartographie |
| **Facture électronique 2026** | GC, Compta, Sage Network, SDCC, ACS | Formats Factur-X/UBL/CII, PA Sage, e-reporting |
| **SEPA** | Moyens de Paiement, Flux Bancaires | Formats pain.001/pain.008, EBICS T/TS |
| **Norme ANC 2025** | Comptabilité, ECF | Nouveaux comptes, nouvelles rubriques |
| **Archivage légal** | Tous modules | Conservation 10 ans, coffre-fort électronique |
| **NF525** | Clictill, SCD | Certification caisse : inaltérabilité, horodatage |

### 30.4 Tableau récapitulatif des modules et de leurs interconnexions

| Module | Données fournies | Données reçues |
|---|---|---|
| **Comptabilité** | Échéances, écritures, soldes | Factures (GC), règlements (PAI), dotations (IMM), salaires (PAIE), notes de frais (SEE), factures fournisseurs (ACS) |
| **Gestion Commerciale** | Factures de vente/achat, mouvements de stock, devis | Commandes (CRM, SSM, SenSaaS, EDI), ventes caisse (SCD, Clictill), factures électroniques (Sage Network) |
| **Moyens de Paiement** | Virements, prélèvements, flux SEPA | Échéances (Compta), extraits (Flux Bancaires) |
| **Trésorerie** | Soldes prévisionnels, prévisions | Échéances (Compta), extraits (Flux Bancaires, PAI) |
| **Immobilisations** | Dotations, cessions, plans d'amortissement | Écritures d'achat (Compta) |
| **ECF** | Bilan, liasse fiscale, FEC | Balance (Compta), amortissements (IMM) |
| **Paie & RH** | Écritures de salaires, DSN | Variables de paie (SEE), congés/absences (SEE) |
| **CRM Force de Vente** | Opportunités, devis | Données clients/articles (GC) |
| **CRM Service Client** | Tickets, contrats | Historique client (GC) |
| **Recouvrement** | Relances, promesses, scoring | Écritures comptables, fiches clients (Compta) |
| **SCD / Clictill** | Ventes, encaissements, stocks | Articles, tarifs, clients (GC) |
| **ACS** | Factures fournisseurs traitées | Comptes, grilles analytiques, conditions de règlement (Compta) |
| **Sage Network** | Factures électroniques émises/reçues | Factures (GC, Compta) |
| **SDCC** | Factures pré-traitées, contrôles données | Factures reçues (Sage Connect), données tiers (Compta, GC) |
| **BI Reporting** | Tableaux de bord, KPIs | Données temps réel (Compta, GC, Trésorerie) |
| **Espace Employés** | Congés, absences, notes de frais | Données salariés (Paie), plan comptable (Compta) |
| **Flux Bancaires** | Extraits bancaires, statuts de télétransmission | Fichiers SEPA (PAI) |
| **Stockage M365** | Documents classés, métadonnées | Documents (tous modules) |
| **EDI** | Commandes, avis d'expédition, factures | Données commerciales (GC) |
| **SenSaaS** | Devis, commandes | Catalogue, clients, stocks (GC) |
| **Sales Management** | Devis, commandes, opportunités | Clients, articles, tarifs (GC, Compta) |

---

## Conclusion

Ce document a couvert l'ensemble des modules Sage 100 (hors Gestion de Production), soit **27 modules et options complémentaires**, avec pour chacun :

- **Vue d'ensemble** : rôle et positionnement dans l'écosystème Sage 100
- **Fonctionnalités détaillées** : liste exhaustive des capacités du module
- **Nouveautés V12** : évolutions récentes (2025) avec leur logique métier
- **Logique métier** : explication du "pourquoi" et du "comment" des fonctionnalités

### Points clés à retenir

1. **Sage 100 V12 est la version stratégique** pour la conformité à la facture électronique 2026 et à la norme ANC 2025. La migration est vivement recommandée avant les échéances réglementaires.

2. **L'écosystème Sage 100 s'étend au-delà des modules cœur** : Sage Network, ACS, SDCC, Sage Sales Management, Clictill, SenSaaS, EDI, et les options cloud (Espace Employés, Dématérialisation RH, BI Reporting) enrichissent l'ERP pour couvrir tous les besoins métiers.

3. **L'interopérabilité est native** : les Objets Métiers et l'API SData permettent à des applications tierces de se connecter en toute sécurité, en respectant la logique métier de Sage 100.

4. **La mobilité est généralisée** : CRM mobile, Espace Employés mobile, Clictill mobile, Sage Sales Management mobile — tous les modules clés sont accessibles en déplacement.

5. **L'IA fait son entrée** : Sage Copilot dans Sage Sales Management et Sage Business Reporting apporte l'intelligence artificielle dans l'analyse de données et la saisie vocale.

6. **La dématérialisation est omniprésente** : facture électronique (Sage Network, eFacture, ACS), bulletins de paie (Démat RH), notes de frais (Espace Employés), documents commerciaux (Stockage M365) — tous les flux papier sont en cours de digitalisation.

---

> **Sources consultées** (40+ pages, toutes récentes — moins d'un an) :
>
> - sage.com (pages produits : Comptabilité, GC, Paie & RH, Immobilisations, CRM, Sales Management, Clictill, SenSaaS, BI Reporting, Business Reporting, ACS, Espace Employés, Démat RH, Flux Bancaires, Stockage M365)
> - apogea.fr, blc-conseil.com, blog.ig-conseils.com, blog.tout-pour-la-gestion.com, performa-gestion.fr (nouveautés V12)
> - activit.fr (évolutions V9, V10, V11)
> - yad.fr (guides Comptabilité et BI Reporting 2025)
> - fr-kb.sage.com (FAQ technique : eFacture, SDCC, Flux Bancaires, Démat RH)
> - efacture.sage.fr (portail eFacture, scénarios)
> - inseco.fr (PDF Espace Employés, CRM)
> - wilroad.com (PDF Immobilisations, découpage fonctionnel)
> - grafe.fr (PDF Stockage M365, métadonnées, partage)
> - clictill.com (connecteur Sage 100, Clictill Pay, fonctionnalités caisse)
> - forcemanager.com (Sage Sales Management, CRM mobile, devis)
> - support.sensaas.fr (fonctionnalités SenSaaS)
> - vantree.com, zestinfo.fr, melorio.fr (connecteurs EDI)
> - audentia-gestion.fr (PDF Sage EDI)
> - adn-software.com (activation Stockage M365)
> - setg.fr (Sage 100 et Microsoft 365)
> - caplaser.fr (facturation électronique Sage 100)
> - invoicing.plus (guide ACS complet)
> - absyscyborg.com (Sage Espace Employés)
> - performa-gestion.fr (PDF Stockage M365, nouveautés V12)

---

*Document compilé en juillet 2025 — ~2000 lignes — 27 modules couverts — 40+ sources.*
