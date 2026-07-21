# Sage 100 Comptabilité — Référence complète des fonctionnalités, écrans, menus et options

> Objet : documenter **exhaustivement** le module Sage 100 Comptabilité (i7 / V10 / 100c).
> Sources : documentation officielle Sage.fr, tutoriels informatique-bureautique.com, ios.fr, fiches produits caplaser/grafe/synoptic-erp, KB Sage, manuels wilroad/perennegestion, 4gestionacademy.

---

## 0. Architecture générale

### 0.1 Barre de menus principale

| Menu | Rôle |
|---|---|
| **Fichier** | Dossiers, A propos de votre société, Paramètres société, Imprimer, Quitter |
| **Édition** | Annuler, Répéter, Couper, Copier, Coller, Rechercher, Remplacer |
| **Structure** | Référentiels : Plan comptable, Plan tiers, Plan analytique, Journaux, Banques, TVA, Modèles, Budgets, Cycles, Fusion |
| **Traitement** | Saisies, Interrogation/lettrage, Rapprochement, Règlements, Relances, Abonnements, Régularisations, Clôtures, Fin d'exercice |
| **État** | Brouillard, Journal, Grand-livre, Balance, Balance âgée, Échéancier, TVA, Bilan, Compte de résultat, SIG, Analytique, Budget, FEC |
| **Fenêtre** | Réorganiser, Actualiser, Barre verticale, Personnaliser |
| **Aide (?)** | Aide contextuelle, Documentation |

### 0.2 Interface IntuiSage

- **Volet comptable** : modules de comptabilité (barre verticale avec icônes)
- **Volet de gestion** : dashboard synthétique (indicateurs, graphiques, alertes)
- **Barre de titre** : nom app + fichier comptable + exercice actif
- **Barre d'état** : fichier, mois en cours, date, statut exercice

### 0.3 Personnalisation (Fenêtre / Personnaliser)

- **Interface utilisateur** : Barres d'outils (afficher/masquer/renommer), Menus (ajouter/supprimer/renommer), Raccourcis clavier
- **Général** : options d'affichage, confirmations, préférences
- **Affichage** : colonnes, ordre, largeur, hauteur des volets
- **Barre verticale** : accès rapide (Fenêtre / Barre verticale)
- **Favoris** : raccourcis vers fonctions internes ou liens externes
- **18 écrans personnalisables** (plan tiers, saisie des écritures, saisie par pièce…)
- Possibilité de **renommer ou masquer** les champs de chaque écran

---

## 1. MENU FICHIER

### 1.1 Gestion des dossiers

| Fonction | Description |
|---|---|
| **Ouvrir** | Ouvrir un fichier comptable (.mae) |
| **Créer** | Créer un nouveau dossier (assistant) |
| **Enregistrer le raccourci** | Mémoriser le raccourci du dossier |

### 1.2 A propos de votre société

| Onglet | Description |
|---|---|
| **Identification** | Raison sociale, adresse, SIRET, NAF, forme juridique, capital |
| **Exercices comptables** | Dates début/fin, nombre de périodes (12 mensuelles), exercice actif |
| **Contacts** | Coordonnées des contacts |

### 1.3 Paramètres société

| Onglet | Description |
|---|---|
| **Général** | Gérer charges/produits à régulariser, saisie négative, saisie quantités, mono/double-monnaie |
| **Comptabilisation** | Journal de régularisation, modèles de saisie (CCA/PCA/FFAR/CFAE), proratisation (360j ou jours réels) |
| **Devises** | Devise tenue, devise présentation, séparateur, code ISO, sigle |
| **TVA** | Mode (CA3/CA12), encaissements ou débits, périodicité |
| **Types tiers** | Types (clients/fournisseurs/salariés/autres), numérotation (manuelle/auto/racine) |
| **Champ statistique tiers** | Critères d'analyse statistique |
| **Structure banque** | Nb caractères RIB/IBAN, code banque, guichet, compte, clé |
| **Services/Contacts** | Départements de l'entreprise |

### 1.4 Préférences

| Volet | Options |
|---|---|
| **Général / Profil Société** | Saisie négative, saisie quantités, mono/double-monnaie |
| **Initialisation / Plan comptable** | Confirmer suppression comptes avec solde N-1, libellé PCG en création |
| **Affichage** | Colonnes par défaut, format dates, format montants |

### 1.5 Gestion des droits d'accès

- Modifier mot de passe administrateur
- Créer un utilisateur (identifiant + mot de passe)
- Gérer les autorisations (droits par module, fonction, journal)
- **Protection des journaux** par droits d'accès (un utilisateur ne peut saisir que dans les journaux autorisés)

---

## 2. MENU STRUCTURE (référentiels)

### 2.1 Plan comptable (Structure / Plan comptable)

**Liste** : Compte (9 car. alphanum., 2 chiffres min.), Désignation (30 car.), Classe, Soldes D/C, coches par classe.

**Fiche compte** — jusqu'à 6 onglets selon la racine :

| Onglet | Champs |
|---|---|
| **Compte** | N°, Désignation, Racine, Classe, Nature (charge/produit/bilan) |
| **Complément** | Code taxe par défaut, Nb lignes, Saut lignes/page, Regroupement, Saisie analytique, Saisie échéance, Saisie compte tiers |
| **Exercice N-1** | Débit/Crédit N-1 (reports à nouveaux → génère écritures dans journal d'OD) |
| **Exercice N** | Débit/Crédit/Solde N |
| **Exercice N+1** | Débit/Crédit N+1 |
| **Informations libres** | Jusqu'à 10 champs personnalisés |

**Options sur comptes** : associer des paramètres de comportement à plusieurs comptes (ex: tous les comptes de tiers gèrent échéancier et lettrage).

**Méthodes de création** : plan standard (247 comptes), récupération d'un autre dossier, import ASCII, import ASCII délimité.

### 2.2 Plan tiers (Structure / Plan tiers)

**Liste** : Compte tiers, Désignation, Type (client/fournisseur/salarié/autre), Compte collectif.

**Fiche tiers** :

| Onglet | Champs |
|---|---|
| **Fiche principale** | N°, Désignation, Type, Compte collectif, Adresse, CP, Ville, Pays, SIRET, TVA intra |
| **Banques** | Multi-RIB, IBAN, BIC, code banque, guichet, compte, clé |
| **Modèles** | Modèle d'échéancement, conditions de règlement, mode de règlement |
| **Complément** | Encours autorisé, niveau de relance, modèle de relance, délai paiement, escompte, contact |
| **Statistiques** | Zone géographique, catégorie, etc. |
| **Informations libres** | Champs personnalisés |

**Caractéristiques** : multi-collectif, multi-échéance, multi-RIB, multi-mode de règlements.

### 2.3 Plan analytique (Structure / Plan analytique)

> ❌ Non couvert par l'app

- Jusqu'à **11 plans analytiques**
- Sections avec structure hiérarchique (niveaux d'analyse)
- Fiche section : N°, Désignation, Plan, Section parente, Niveau, Type (section/total)
- Utilisé pour états analytiques, ventilation des charges et produits

### 2.4 Plan reporting (Structure / Plan reporting)

> ❌ Non couvert par l'app

- Présentation des états de synthèse selon un plan de comptes différent
- Balances et grands livres de reporting

### 2.5 Taux de taxes / TVA (Structure / Taux de taxes)

**Liste** : Code taxe, Intitulé, Taux, Compte collectée, Compte déductible, Type.

**Paramétrage TVA** :
- Mode : CA3 (mensuel/trimestriel) ou CA12 (annuel)
- Sur encaissements ou débits
- Onglet **Rubriques** : calcul des rubriques de déclaration (pré-paramétrées, modifiables)
- Onglet **Informations comptables** : comptes et journaux pour génération auto
- Boutons **[Initialiser]**, **[Annuler l'initialisation]**, **[Assistant]**

### 2.6 Codes journaux (Structure / Journaux)

> ❌ Non couvert par l'app — cause racine

**Liste** : Code (2-3 car.), Intitulé, Type, Statut.

**Fiche journal** :

| Onglet | Champs |
|---|---|
| **Complément** | Code, Intitulé, Type (Vente/Achat/Trésorerie/OD/À-nouveau), Racines autorisées, Comptes paramétrés, Compte d'attente, Numérotation (manuel/auto/continu) |
| **Banque** | Compte banque, RIB, Mode de rapprochement (manuel/auto) — uniquement Trésorerie |
| **Modèle** | Modèle de saisie par défaut |
| **Droits** | Utilisateurs autorisés |

### 2.7 Banques (Structure / Banques)

**Fiche banque** : Nom, adresse, SWIFT/BIC, structure RIB, banques locales/étrangères, comptes associés (compte général + journal).

### 2.8 Modèles de saisie (Structure / Modèles de saisie)

> ❌ Non couvert par l'app

- Code, Intitulé, Type de journal associé
- **Colonnes** : N° compte, Libellé, Débit, Crédit, Échéance, TVA, Analytique
- **Lignes pré-enregistrées** : comptes et libellés pré-saisis, curseur aux endroits à compléter
- Personnalisation des colonnes (ajout/suppression/ordre)
- **Modèles de saisie analytique** : spécifiques à la ventilation analytique
- Exemples : facture téléphone, loyer, salaires, cotisations, TVA

### 2.9 Autres référentiels Structure

| Référentiel | Description |
|---|---|
| **Modèles de grille** | Grilles de ventilation analytique pré-paramétrées, reventilation multi-axes |
| **Modèles de règlement** | Conditions (30j, 30j fin de mois…), calcul auto des échéances, fractionnement |
| **Modèles d'abonnement** | Écritures récurrentes (loyers, assurances), périodicité, dates début/fin, génération auto |
| **Libellés** | Bibliothèque de libellés pré-enregistrés, recherche par mot-clé |
| **Postes budgétaires** | Budgets par axe analytique, par période, comparaison budget/réalisé, écarts |
| **Cycles de révision** | Regroupement de comptes à réviser, association à un collaborateur, suivi avancement |
| **Fusion** | Fusion de comptes généraux/tiers, transfert des écritures |
| **Codes journaux analytiques** | Journaux spécifiques à la saisie analytique, associés à un plan |

---

## 3. MENU TRAITEMENT

### 3.1 Saisie des journaux (Traitement / Saisie des journaux)

> 🟡 Couverture partielle (JournalSaisiePage)

**Fenêtre principale** : grille **Journal × Période** avec statuts (Ouvert/Imprimé/Clôturé) et filtres latéraux.

**Fenêtre de saisie** :
- En-tête : Code journal, Intitulé, Période, Date
- **Bandeau solde progressif** (Trésorerie) : Ancien solde / Mouvements / Nouveau solde
- **Grille** : Jour, N° pièce, N° facture/Référence, N° compte général, **N° compte tiers** (séparé), Libellé, Débit, Crédit, Échéance, Code taxe, Ventilation analytique

**Boutons** : **Équilibrer**, Calculer TVA, Contrepartie auto, Modèle, Libellé auto, **Calculatrice intégrée** (`=1250*1.2`), Appel/création de compte en saisie.

### 3.2 Saisie par pièce (Traitement / Saisie par pièce)

> ❌ Non couvert

- Saisie regroupée par pièce (une pièce = un document)
- Sélection/création automatique du lot (même opérateur, date, origine)
- Raccourci **Alt+P** pour création de pièce
- Fonctions : régénérer contrepartie, recalculer TVA, affecter solde, saisie ventilations analytiques, saisie échéances
- **Règlements multi-échéances** : fractionnement du montant, calcul auto des dates
- **Lettrage en saisie** de pièces
- Menu Actions : Informations complémentaires, Interroger compte, Lettrer/Délettrer

### 3.3 Saisie par lot (Traitement / Saisie par lot)

> ❌ Non couvert

- Groupe d'écritures traitées ensemble
- Liste des journaux du lot (plusieurs journaux dans un même lot)
- Affectation d'un lot à un poste de travail
- Mise à jour différée sécurisée + impression brouillards

### 3.4 Saisie bancaire / OD analytiques

> 🟡 Banque partiel / ❌ OD analytiques

- Saisie opérations bancaires + génération depuis extraits + import fichiers
- Saisie OD analytiques : opérations diverses avec ventilation analytique

### 3.5 Interrogation et lettrage (Traitement / Interrogation et lettrage)

> ❌ Non couvert

#### Interrogation compte général
- Sélection : compte, dates, type de lot, établissement, journal
- Solde progressif : ancien + mouvements + nouveau

#### Interrogation compte tiers
- **Sélections** : type collectif, compte général, dates, type de lot, établissement, journal, approche (Nationale/IAS-IFRS), filtres lettrage (non lettrées/partiellement/totalement), date lettrage, code lettrage, marquage, sélection par montant
- **Résultat** : détail des écritures + infos générales
- **Menu Actions** : Extourner, Pièce (consulter/modifier), Échéances, Lettrer, Marquer, Détail lettrage

#### Lettrage manuel
- Sélection compte tiers, liste écritures non lettrées (D et C)
- Sélection des écritures à lettrer (D = C), attribution code lettrage
- Lettrage partiel avec reliquat si D ≠ C

#### Lettrage automatique
- Sélection tiers ou tous, critères (dates, montant)
- Algorithme de rapprochement auto D/C par montant
- Génération code lettrage auto + rapport

### 3.6 Rapprochement bancaire (Traitement / Rapprochement)

> 🟡 Partiel

- **Manuel** : tableau 2 colonnes (comptables vs bancaires), pointage manuel, écart temps réel, édition état
- **Automatique** : import extraits, rapprochement auto par montant/date, gestion écarts

### 3.7 Règlement tiers (Traitement / Règlement tiers)

> ❌ Non couvert

- Sélection des tiers à régler (filtres : type, échéance, montant)
- Proposition de règlement selon trésorerie
- Règlements partiels, en devises (écarts de change)
- Impression proposition + états de paiement + titres de paiement
- Mise à jour journal de banque + lettrage auto
- **Règlements en rafale** (multi-tiers en une opération)

### 3.8 Relances clients / Relevés (Traitement / Relances)

> ❌ Non couvert

- **10 niveaux de rappel** paramétrables
- Modèles de relance par tiers (criticité, modalités)
- Affichage auto du niveau de relance
- Relevés de compte, justificatifs de solde, extraits tiers
- Personnalisation emails, calcul pénalités de retard
- Suivi promesses de paiement, gestion litiges

### 3.9 Réévaluation devises (Traitement / Réévaluation)

> ❌ Non couvert

- Réévaluation comptes en devises à la clôture
- Calcul écarts de change (gains/pertes), génération auto écritures
- Récupération auto cours de devises (service en ligne)
- Actualisation à l'ouverture + récupération dynamique en saisie

### 3.10 Écritures d'abonnement (Traitement / Écritures d'abonnement)

> ❌ Non couvert

- Génération auto écritures récurrentes (loyers, assurances, abonnements)
- Basé sur modèles d'abonnement (Structure)
- Sélection période, génération en lot, état récapitulatif

### 3.11 Écritures de régularisation (Traitement / Écritures de régularisation)

> ❌ Non couvert

**Assistant** — 4 cas :

| Type | Description |
|---|---|
| **CCA** | Charges constatées d'avance : annuler part anticipée, reporter sur N+1 |
| **PCA** | Produits constatés d'avance : idem pour produits |
| **FFAR** | Fournisseurs factures à recevoir : comptabiliser charges non facturées de N |
| **CFAE** | Clients factures à établir : comptabiliser produits non facturés de N |

**Procédure** : activer dans Paramètres société / Comptabilisation / Général → paramétrer journal + modèles + proratisation (360j ou jours réels) → saisir période d'application sur les écritures → lancer assistant → générer + extourne auto au 01/01/N+1 + état récap.

### 3.12 Autres traitements

| Fonction | Description |
|---|---|
| **Extournes automatiques** | Contre-passation auto (sens contraire ou montant négatif), sur comptes autorisant montants négatifs |
| **Révision par cycle** | Révision par regroupement de comptes, suivi par collaborateur, registres de révision |
| **Recherche d'écritures** | Multicritère : compte, tiers, date, montant, libellé, journal, référence, code lettrage, marquage |
| **Réimputation générales** | Transfert écriture d'un compte général vers un autre |
| **Réimputation analytiques** | Transfert ventilation vers une autre section |
| **Compaction** | Compactage base, suppression écritures de simulation, optimisation |
| **Bon à payer** | Marquage des écritures fournisseurs comme bon à payer |

### 3.13 Clôture des journaux (Traitement / Clôture des journaux)

> ❌ Non couvert

| Niveau | Description |
|---|---|
| **Partielle** | Verrouillage de certaines écritures (brouillard imprimé) |
| **Par période** | Verrouillage d'une période mensuelle pour un journal |
| **Totale** | Verrouillage complet du journal pour l'exercice |

**Procédure** : sélection journal + période → vérification équilibrage → impression brouillard (obligatoire) → clôture (Ouvert → Imprimé → Clôturé). Écritures clôturées **inaltérables**.

### 3.14 Fin d'exercice (Traitement / Fin d'exercice)

> ❌ Non couvert

| Fonction | Description |
|---|---|
| **Nouvel exercice** | Création exercice suivant, définition dates |
| **Report à nouveau** | Reports des comptes de bilan (racines 1,2,3,4,5). Mode : Aucun / Solde / Détail (mouvements non lettrés reportés en détail) |
| **Clôture de l'exercice** | Verrouillage définitif, génération écritures de résultat (bilan) |
| **États de clôture** | Bilan, compte de résultat, SIG, balance de clôture |
| **Fichier DGFIP/FEC** | Génération du Fichier des Écritures Comptables (provisoire et définitif) |
| **Archivage** | Archivage de l'exercice clôturé |
| **Sauvegarde fiscale** | Automatisation production éléments pour contrôle fiscal |

---

## 4. MENU ÉTAT (éditions)

| État | Description | Couverture app |
|---|---|---|
| **Brouillard de saisie** | État provisoire modifiable, première vision des comptes | ❌ |
| **Journal / Journal centralisé / Journal général** | Liste des écritures par journal et par période | 🟡 |
| **Grand-livre des comptes** | Détail des mouvements par compte général, avec soldes | ✅ |
| **Grand-livre des tiers** | Détail des mouvements par compte tiers, avec soldes et lettrage | ❌ |
| **Balance générale** | Tous les comptes avec totaux D/C et soldes | ✅ |
| **Balance âgée (tiers)** | Répartition des soldes tiers par tranche d'âge (0-30j, 30-60j, 60-90j, +90j) | ❌ |
| **Balance analytique** | Balance par section analytique | ❌ |
| **Échéancier** | Liste des échéances par tiers (clients/fournisseurs), par période | ❌ |
| **Déclaration de TVA** | CA3/CA12, état préparatoire, télédéclaration/télépaiement EDI | ✅ |
| **Bilan** | Bilan comptable (actif/passif) | ✅ |
| **Compte de résultat** | Charges/produits, résultat net | ✅ |
| **SIG** | Soldes intermédiaires de gestion (marge commerciale, VA, EBE, résultat…) | ❌ |
| **États analytiques** | Balance, grand-livre, états inversés, bilan et CR analytiques | ❌ |
| **États budgétaires** | Budget/réalisé, écarts par poste et par axe | ❌ |
| **Justificatif de solde** | Détail justifiant le solde d'un compte ou d'un tiers | ❌ |
| **État de rapprochement** | État du rapprochement bancaire (écarts pointés/non pointés) | ❌ |
| **Contrôle de caisse** | État de contrôle des journaux de caisse | ❌ |
| **FEC (DGFIP)** | Fichier des Écritures Comptables (provisoire/définitif), attestation FEC | ❌ |
| **Rapport délais de paiement** | Analyse des délais de paiement clients/fournisseurs | ❌ |
| **États de reporting** | Balances/grands livres selon plan reporting | ❌ |
| **Tableau de bord personnalisé** | Tableaux de bord paramétrables avec indicateurs | ❌ |

**Options d'impression** :
- Sélection avant impression (comptes, périodes, établissements, devises)
- Modes de sortie : imprimante, écran, fichier, email
- Impressions différées
- Mise en page personnalisable
- Menu complémentaire **Excel®** : assistants pour concevoir des états personnalisés
- Construction et réalisation de reportings depuis Excel®

---

## 5. FONCTIONNALITÉS TRANSVERSALES

### 5.1 Comptabilité générale

- Multi-société (15 en version hébergée), multi-exercice, multidevise
- Saisie simplifiée : par pièce, par lot, libellé automatique
- Génération auto des écritures de TVA, calcul auto dates d'échéance
- Contreparties automatiques, équilibrage
- Appel et création de compte en saisie
- Dossiers prêts à l'emploi (comptes, sections, journaux, modèles, taux TVA)

### 5.2 Comptabilité auxiliaire (tiers)

- Suivi des tiers : multi-collectif, multi-échéance, multi-RIB, multi-mode de règlements
- Interrogation des comptes tiers
- État sur les comptes tiers
- Justificatif de solde et extraits tiers paramétrables
- Gestion des écarts de change sur règlements en devises

### 5.3 Comptabilité analytique

- 2 plans par défaut (jusqu'à 11 en option)
- Création de plan analytique structuré
- Saisie des OD analytiques
- Interrogation analytique
- Bilan et compte de résultat analytique
- États analytiques : balance, grand-livre, états inversés
- Reventilation des charges et produits via grilles pré-paramétrées

### 5.4 Suivi budgétaire

- Établissement des budgets à différents niveaux
- Autant de totalisations que nécessaire
- Comparaison budget/réalisé avec écarts

### 5.5 Contrôles comptables

- Incohérence de saisie
- Recherche de doublon
- Mouvements tiers non lettrés
- État de pré-contrôle pour détection des erreurs de saisie

### 5.6 Conformité légale

- Conforme aux exigences légales : IAS/IFRS, contrôle des comptabilités informatisées
- Génération du FEC (provisoire et définitif) + attestation FEC
- Loi contre la fraude à la TVA (article 286 CGI)
- Sauvegarde fiscale automatisée
- Télédéclarations et télépaiements (EDI TVA)

### 5.7 Gestion des devises

- Gestion mono ou multidevise
- Récupération auto des cours de devises
- Actualisation à l'ouverture et en saisie
- Réévaluation des dettes/créances en devises
- Écarts de change

### 5.8 Écritures de régularisation

- Génération et extourne de fin d'exercice
- 4 types : CCA, PCA, FFAR, CFAE
- Assistant guidé avec modèles de saisie
- Reprend les informations d'origine (libellé, référence, infos libres)

### 5.9 Gestion des collaborateurs

- Gestion des utilisateurs et droits d'accès
- Protection des journaux par utilisateur
- Affectation des lots de saisie à un poste de travail
- Suivi des cycles de révision par collaborateur

### 5.10 Intégrations

- **Microsoft 365** : add-in Outlook pour accès données comptables et commerciales
- **Excel®** : menu complémentaire pour états et reportings personnalisés
- **Transfert comptable** : GesCom → Compta (journaux de ventes/achats)
- **Module Financier** : récupération échéances et règlements
- **Logiciel Paie** : alimentation journal d'OD
- **Immobilisations** : intégration achats, cessions, dotations

---

## 6. SYNTHÈSE DES LACUNES vs APP ACTUELLE

### 6.1 Menu STRUCTURE — manquants

| Élément | Statut |
|---|---|
| Plan analytique | ❌ |
| Plan reporting | ❌ |
| **Codes journaux** | ❌ (cause racine) |
| Codes journaux analytiques | ❌ |
| **Modèles de saisie** | ❌ |
| Modèles de grille | ❌ |
| Modèles de règlement | ❌ |
| Modèles d'abonnement (compta) | ❌ |
| Libellés (bibliothèque) | ❌ |
| Postes budgétaires / Budgets | ❌ |
| Cycles de révision | ❌ |
| Fusion (comptes/tiers) | ❌ |

### 6.2 Menu TRAITEMENT — manquants

| Élément | Statut |
|---|---|
| Saisie par pièce | ❌ |
| Saisie par lot | ❌ |
| Saisie OD analytiques | ❌ |
| Clôture des journaux | ❌ |
| **Interrogation et lettrage** | ❌ |
| Interrogation tiers | ❌ |
| Interrogation analytique | ❌ |
| Rapprochement automatique | ❌ |
| **Règlement tiers** | ❌ |
| Relances / relevés | ❌ |
| Réévaluation devises | ❌ |
| Écritures d'abonnement | ❌ |
| Écritures de régularisation | ❌ |
| Extournes automatiques | ❌ |
| Révision par cycle | ❌ |
| Recherche d'écritures | ❌ |
| Réimputation | ❌ |
| Compaction | ❌ |
| Fin d'exercice (nouvel exercice, report à nouveau, clôture, états, FEC, archivage) | ❌ |

### 6.3 Menu ÉTAT — manquants

| Élément | Statut |
|---|---|
| Brouillard de saisie | ❌ |
| Grand-livre des tiers | ❌ |
| **Balance âgée** | ❌ |
| Balance analytique | ❌ |
| **Échéancier** | ❌ |
| SIG | ❌ |
| États analytiques / budgétaires / reporting | ❌ |
| Justificatif de solde | ❌ |
| État de rapprochement | ❌ |
| Contrôle de caisse | ❌ |
| **FEC** | ❌ |
| Rapport délais de paiement | ❌ |
| Tableau de bord personnalisé | ❌ |

### 6.4 Concepts clés manquants dans le modèle de données

| Concept | Description |
|---|---|
| **Code journal** | Référentiel obligatoire avant toute saisie (Vente/Achat/Trésorerie/OD/À-nouveau) |
| **Période mensuelle** | Découpage de l'exercice en 12 périodes, saisie par journal × période |
| **N° pièce** | Numérotation auto ou manuelle par journal |
| **Compte général vs compte tiers** | Séparés dans Sage 100 (le tiers est rattaché à un compte collectif) |
| **Solde progressif** | Ancien solde + Mouvements + Nouveau solde (banque & caisse) |
| **Statut écriture** | Ouvert → Imprimé → Clôturé (inaltérable après clôture) |
| **Code lettrage** | Lien entre écritures D et C d'un compte tiers |
| **Modèle de saisie** | Lignes pré-enregistrées pour accélérer la saisie |
| **Ventilation analytique** | Répartition multi-axes d'un montant sur des sections |
| **Échéance calculée** | Date d'échéance auto selon modèle de règlement du tiers |
| **Marquage** | Type de marquage (litige, bon à payer, etc.) paramétrable |
| **Lot de saisie** | Regroupement d'écritures (même opérateur, date, origine) |
| **Extourne** | Contre-passation d'une écriture |

---

## 7. SOURCES

- Documentation officielle Sage.fr — Sage Comptabilité i7 (mise en route, plan comptable, saisies, rapprochement, lettrage, TVA)
- Tutoriels informatique-bureautique.com — Formation gratuite Sage 100 Comptabilité V10
- ios.fr — Table des matières SAGE Comptabilité 100 V10
- caplaser.fr — Fiche produit Sage 100 Comptabilité (2024)
- grafe.fr — Fiche produit Sage 100 Comptabilité (2023)
- synoptic-erp.com — Découpage fonctionnel Sage 100c Comptabilité
- KB Sage (fr-kb.sage.com) — Génération écritures de régularisation
- wilroad.com — Manuel Sage 100 Comptabilité (menu Fenêtre, personnalisation)
- perennegestion.com — Fiche analyse Comptabilité 100
- 4gestionacademy.com — Formation Sage SAARI Comptabilité 100
- frp.sage.fr — Interrogation compte tiers, saisie par pièce, traitements périodiques
- atlog83.fr — Nouveautés Comptabilité version 3.10
- uptimeo.fr — Découpage fonctionnel Sage 100c
