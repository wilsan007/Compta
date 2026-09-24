# Plan correctif complet et procédure de vérification ultime — 24 septembre 2026

> **Ce document fusionne deux audits et leur ajoute ce qu'aucun des deux ne contient :**
>
> 1. [Audit des modules hors comptabilité générale — 23 septembre 2026](AUDIT-MODULES-HORS-COMPTA-2026-09-23.md)
>    — **69 défauts** mesurés par exécution de scénarios chiffrés sur base neuve (203 migrations
>    dans le conteneur `pg_audmod`, PostgREST réel devant).
> 2. [Couverture d'audit par module — 24 septembre 2026](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md)
>    — **la mesure de ce qui n'a pas été regardé** : 341 tables métier, 67 portent une logique SQL,
>    43 sont traversées par un scénario (64 %), 80 sur 341 sont atteintes (23 %), 20 fonctions Edge
>    sur 20 sans un seul test, 16 modules sur 20 jamais audités par exécution.
>
> Ce document ajoute : **(I)** le registre des 69 défauts avec l'état d'avancement réel au 24/09,
> **(II)** le plan de correction vague par vague (fichier, migration, test, critère de sortie),
> **(III)** le **chaînage transverse de l'absence** — absent des deux audits et absent du produit —,
> **(IV)** la procédure de vérification ultime : batterie par table, scénarios par module, scénarios
> transverses, contre-épreuve de falsification, **(V)** l'ordre, la charge et le tableau de bord.
>
> **Document complémentaire, à lire avec celui-ci** :
> [Référentiel des chaînages transverses](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md) —
> inventaire et robustesse des **62 chaînages existants** (note moyenne **3,65/7**), **62 états de
> statut sans effet aval** (R-001 → R-062), compilation des chaînages des leaders (SAP, NetSuite,
> Dynamics 365 BC, ERPNext, Pennylane, Procore) et **12 innovations**. L'absence traitée ici en
> partie III y devient un cas particulier d'une catégorie : les chaînages transverses.
>
> **Puis, pour l'exécution** :
> [Plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) — la doctrine
> d'adoption (« le meilleur de chacun » : 17 mécanismes retenus, 4 refusés), le socle technique, la
> définition de « terminé » en 12 points, 6 portes automatiques et **25 lots ≈ 116 j**.
>
> **Et ce qui a été exécuté** : [Preuves d'exécution — vague W0](PREUVES-W0-2026-09-24.md) —
> base neuve (214 migrations, 0 erreur), les suites 240→244 **vertes**, la batterie complète
> (32 vertes / 3 rouges : des specs écrites avant leur correctif), les contre-épreuves des trois
> nouveaux contrôles, et les écarts mesurés par rapport à ce document (20 colonnes fantômes et
> non 21, 29 erreurs non lues, 495 couples de politiques doublées).

---

## 0. Comment ce document est construit — et ce qui est mesuré vs déduit

Le lecteur doit pouvoir trier en trois secondes ce qui est prouvé de ce qui est proposé.

| Marque | Sens exact |
|---|---|
| **MESURÉ** | obtenu par exécution d'un scénario SQL sur base neuve, ou par requête au catalogue PostgreSQL. Reproductible par la commande donnée. |
| **MESURÉ (structure)** | obtenu par lecture du catalogue (`00_schema_dump.sql`) : colonne absente, contrainte `ON DELETE CASCADE`, politique RLS en double. Ce n'est pas une supposition : c'est le schéma. |
| **DÉDUIT** | conséquence logique d'un fait MESURÉ, non encore exécutée. Toute ligne DÉDUITE porte son test de confirmation en partie IV. |
| **PROPOSÉ** | décision d'ingénierie, chiffrée en jours. À valider par le décideur avant exécution. |

**Règle d'honnêteté reprise de la couverture d'audit** : « traversée par un scénario » ne veut pas
dire « correcte ». Cela veut dire qu'un scénario a regardé cette table. C'est le minimum, pas la preuve.

**Base de référence** : schéma + **206 migrations, 0 erreur** (couverture du 24/09, conteneur
`pg_m3_neuf`) ; l'audit du 23/09 a mesuré sur **203 migrations** (`pg_audmod`). État de l'arbre de
travail au 24/09 : **dix fichiers non commités** (`git status` : `?? app/sql/24{0,1,2,3,4}_*.sql` —
cinq correctifs **et** cinq specs) plus le câblage CI (`.github/workflows/ci.yml`, `+41` lignes).

---

## Partie I — Fusion des deux audits

### 1.1 Ce que dit chaque document, en une ligne chacun

| Document | Question | Réponse mesurée |
|---|---|---|
| Audit 23/09 | « Qu'est-ce qui casse sur les modules qui existent mais n'ont jamais été exécutés ? » | **69 défauts : 32 bloquants, 32 graves, 5 mineurs** |
| Couverture 24/09 | « Tous les modules ont-ils été minutieusement audités ? » | **Non** : 1 module sur 10 à peu près, 2 pas du tout, 20/20 fonctions Edge par personne |

Les deux documents se complètent sans se contredire :

- le **23/09 dit où ça casse** (défauts localisés, chacun avec sa preuve) ;
- le **24/09 dit où on n'a pas regardé** (341 tables, 24 logiques SQL jamais traversées, 16 modules
  jamais audités) ;

et ils convergent sur le même diagnostic de fond, que ce document érige en premier principe :

> **Le défaut structurel d'Onusuite n'est pas un bug : c'est l'absence de chaînes transverses
> vérifiées.** Une donnée saisie dans un module n'est pas lue par les autres, et rien ne le dit.

C'est exactement ce que démontrent, chacune de son côté :

| Constat | Où c'est dit |
|---|---|
| `stock_movements` est alimenté par production et ventes, mais compté dans « stock » seulement | Couverture §1, avertissement 1 |
| 245 tables sur 341 n'ont ni logique SQL ni scénario ; 41 ne sont référencées **nulle part** | Couverture §2 |
| 24 endroits où du code s'exécute sans qu'un scénario soit jamais passé dessus | Couverture §3 |
| `qty_scrapped`, `reserved_quantity`, `invoiced_quantity`, `qty_produced` : colonnes présentes que personne ne lit | Couverture §6.2 |
| Les chemins d'annulation (`cancelled` permis par CHECK, traité par aucun trigger) sont le gisement | Couverture §6.1 |
| 13 triggers `SECURITY DEFINER` écrivent sans `tenant_id` | Audit §12 (ISO-01) |
| 21 colonnes écrites qui n'existent pas, la moitié dans les fonctions Edge | Audit §9 |

### 1.2 Registre consolidé des 69 défauts, avec l'état réel au 24/09

Colonnes : **Preuve** = mode d'établissement (exécution / structure / lecture) ;
**Spéc** = un test chiffré existe déjà (fichier `app/sql/NNN_…_tests.sql`) ;
**Vague** = la vague de correction (partie II).

> **État des lieux au 24/09, vérifié dans l'arbre de travail** — les défauts marqués **240**, **241**,
> **242**, **243** ou **244** dans la colonne *Spéc* ont **à la fois** leur spec **et** leur correctif
> écrits, les cinq étapes correspondantes ajoutées à `ci.yml`, mais **rien n'est commité** et
> l'exécution verte **n'est pas consignée** (AUD-X02, §1.6c). Ils sont donc à l'état **écrit**, pas
> **prouvé** : c'est la première chose que le runbook §4.8 doit trancher. Tous les autres restent au
> même état que dans l'audit du 23/09.


#### 1.2.1 Chaîne stock, achats, ventes (13 défauts)

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **S-01** | Achats → stock | La réception n'alimente pas le stock par dépôt | 🔴 | exécution | **241** | W3 |
| **S-02** | Achats → stock | La réception entre à coût nul : aucune couche de valorisation | 🔴 | exécution | **241** | W3 |
| **S-03** | Achats → compta | La réception ne produit **aucune écriture** | 🔴 | exécution | **241** | W3 |
| **S-04** | Achats | `goods_receipts` n'a pas de colonne dépôt | 🔴 | structure | **241** | W3 |
| **S-05** | Ventes → stock | La livraison décrémente le global, pas le dépôt | 🔴 | exécution | **242** | W3 |
| **S-06** | Ventes → stock | La sortie ne consomme aucune couche de valorisation | 🔴 | exécution | **242** | W3 |
| **S-07** | Ventes | Les réservations ne sont **jamais** libérées | 🔴 | exécution | **242** | W3 |
| S-08 | Stock | `increment/decrement_stock` se fient à `current_tenant_id()` | 🟠 | lecture | **240** | W3 |
| S-09 | Stock | `increment_stock` perd la quantité en cas de course (`ON CONFLICT DO NOTHING`) | 🟠 | lecture | **240** | W3 |
| S-10 | Stock | Comptes 310000/603000 codés en dur, `products.stock_account_code` ignoré | 🟠 | lecture | **241** | W3 |
| S-11 | Stock | Traçabilité lot/série désactivée en pratique (avertissement au lieu de refus) | 🟠 | lecture | **241** | W3 |
| S-12 | Stock | Un BL annulé puis réexpédié sort le stock **deux fois** | 🟡 | lecture | à écrire | W3 |
| S-13 | Achats | Un contrôle qualité en échec rebute la quantité **totale** reçue | 🟠 | structure | à écrire | W3 |

#### 1.2.2 Comptabilité avancée : devises, immobilisations, analytique, budgets (15 défauts)

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **M01-01** | Multi-devises | Une facture en devise est comptabilisée **au montant en devise** | 🔴 | exécution | `M01`* | W7 |
| **M01-02** | Multi-devises | `journal_lines` n'a **aucune** colonne de devise | 🔴 | structure | `M01`* | W7 |
| M01-03 | Multi-devises | Écart de change et réévaluation : écrans alimentés par personne | 🟠 | structure | à écrire | W7 |
| IMMO-01 | Immobilisations | Deux moteurs d'amortissement qui se contredisent (`floor(jours/365,25)`) | 🟠 | lecture | à écrire | W5 |
| **IMMO-02** | Immobilisations | « Calculer les amortissements » ne comptabilise rien | 🔴 | lecture | à écrire | W5 |
| IMMO-03 | Immobilisations | Recalcul écrasant la valeur de clôture (part de `Date.now()`) | 🟠 | lecture | à écrire | W5 |
| IMMO-04 | Immobilisations | Les 3 méthodes proposées à l'écran n'ont aucun effet | 🟠 | lecture | à écrire | W5 |
| IMMO-05 | Immobilisations | Dotations en échec silencieusement sautées (`try/catch console.error`) | 🟠 | lecture | à écrire | W5 |
| ANA-01 | Analytique | Les deux triggers analytiques sont **vides** | 🟠 | structure | à écrire | W7 |
| **ANA-02** | Analytique | Aucune écriture générée ne porte de section analytique | 🔴 | structure | à écrire | W7 |
| ANA-03 | Analytique | La balance analytique porte sur tout l'historique | 🟠 | lecture | à écrire | W7 |
| **BUD-01** | Budgets | Le réalisé ignore l'exercice : il cumule depuis l'origine | 🔴 | lecture | à écrire | W7 |
| BUD-02 | Budgets | À-nouveaux, clôture et brouillons comptés dans le réalisé | 🟠 | lecture | à écrire | W7 |
| BUD-03 | Budgets | Les engagements ne sont jamais libérés → double déduction | 🟠 | structure | à écrire | W7 |
| BUD-04 | Budgets | N+1 : deux requêtes par budget | 🟡 | lecture | à écrire | W7 |

\* **`M01`** : les scénarios `doc/audit/scenarios/M01_facture_en_devise.sql` et
`scenarios/ISO_ecriture_inter_societes.sql` existent, mais ce sont des **preuves de constat** (ils
constatent le défaut), pas des tests d'acceptation branchés en CI. Leur passage en test
d'acceptation est un travail de la vague W7.

#### 1.2.3 RH, paie et suppressions en cascade (13 défauts)

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **RH-01** | RH (18 emplacements) | Le nom du salarié s'affiche « null null » (`name` seul alimenté, écrans lisent `first_name`/`last_name`) | 🔴 | structure | **243** | W4 |
| **RH-02** | Paie | Deux `calculate_payslip` : la version à taux fictifs (22/10/42 %) est atteignable sans `pay_run_id` | 🔴 | structure | **243** | W4 |
| RH-03 | Temps → paie | Heures dupliquées à chaque réapprobation (`sync_timesheet_to_payroll` sans garde `NOT EXISTS`) | 🟠 | lecture | **243** | W4 |
| RH-04 | Temps → paie | Heures supplémentaires calculées **trois fois**, seuils 7 h et 8 h contradictoires, montant 0 | 🟠 | lecture | **243** | W4 |
| RH-05 | Paie | Quatre conventions mensuelles contradictoires (4,33 / 30 / 21 / 151,67) | 🟠 | lecture | à écrire | W4 |
| **RH-06** | Paie | L'import des éléments variables **échoue 5 mois sur 12** (`${period}-31` : 22008 sur févr., avr., juin, sept., nov.) | 🔴 | exécution | à écrire | W4 |
| **RH-07** | Notes de frais | Intégrées en paie pour un montant **nul** (`exp.amount` au lieu de `total_amount` → `NaN` → `null`) | 🔴 | structure | à écrire | W4 |
| RH-08 | Notes de frais | Ni TVA récupérable (`total_vat` ignorée), ni écriture 625x / 421 | 🟠 | structure | à écrire | W4 |
| RH-09 | Congés | Un congé à cheval sur deux mois est **entièrement omis** (`start_date >= début AND end_date <= fin`) | 🟠 | lecture | à écrire | W4 |
| RH-10 | Paie | Titres restaurant : relancer l'import double les éléments (aucune garde d'idempotence) | 🟠 | lecture | à écrire | W4 |
| **SUP-01** | Suppressions | Supprimer un salarié efface ses bulletins de paie (`pay_slips.employee_id` CASCADE) | 🔴 | exécution | **244** | W2 |
| **SUP-02** | Suppressions | Supprimer un compte bancaire efface toutes ses opérations (`bank_transactions.account_id` CASCADE) | 🔴 | exécution | **244** | W2 |
| SUP-03 | Suppressions | Supprimer un produit efface son historique de mouvements (`stock_movements.product_id` CASCADE) | 🟠 | exécution | **244** | W2 |

#### 1.2.4 Fonctions Edge et traitements de fond (8 défauts)

Aucune des 20 fonctions Edge n'a de test (couverture §4). Les huit défauts ci-dessous sont tous
**MESURÉS** — la moitié par le scanner de colonnes écrites, l'autre par exécution.

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **EF-01** | Relances (M-14) | Le cron échoue dès la première facture (`.single()` sur 0 ligne → `PGRST116` → `throw`) | 🔴 | exécution | à écrire | W6 |
| **EF-02** | Relances | La relance n'est jamais enregistrée (3 colonnes inexistantes, erreur non lue) → **renvoyée tous les jours** | 🔴 | structure | à écrire | W6 |
| **EF-03** | Synchro bancaire | Le bouton « Synchroniser » n'appelle jamais **la fonction Edge** : il tamponne une date, force `active`, efface l'erreur | 🔴 | lecture | à écrire | W6 |
| **EF-04** | Synchro bancaire | La fonction Edge insère `provider_transaction_id` (colonne inexistante), ne lit pas l'erreur, dit `success: true` | 🔴 | exécution | à écrire | W6 |
| **EF-05** | Facture électronique | La soumission n'est jamais enregistrée (4 colonnes `e_invoice_*` inexistantes) → **double envoi** | 🔴 | structure | à écrire | W6 |
| EF-06 | Facture électronique | L'écran ne soumet rien : il génère le XML et le télécharge | 🟠 | lecture | à écrire | W6 |
| EF-07 | Signature | La demande de signature n'est jamais enregistrée (5 colonnes inexistantes) | 🟠 | structure | à écrire | W6 |
| EF-08 | Webhooks | Journal de livraison et replanification : `http_status` au lieu de `response_code`, `next_retry_at` au lieu de `next_attempt_at` | 🟠 | structure | à écrire | W6 |

**11 des 21 fonctions Edge n'ont aucun appelant dans le front** : `submit-e-invoice`,
`request-signature`, `sync-bank-transactions`, `submit-vat-return`, `validate-vat-vies`,
`verify-iban`, `verify-siret`, `generate-pdf`, `handle-stripe-webhook`, `outgoing-webhooks`,
`refresh-exchange-rates`. Les écrans existent pourtant (`EInvoicePage`, `BankSyncPage`,
`EdiTvaPage`, `VatReturnsPage`).

#### 1.2.5 Sécurité, isolation et droits (5 défauts) — la vague la plus urgente

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **ISO-01** | Isolation | Un utilisateur écrit dans la société **voisine** via un trigger `SECURITY DEFINER` (`update_parent_status_on_subtasks_done` : `UPDATE project_tasks SET status='done' WHERE id = v_parent_id`, sans `tenant_id`) | 🔴 | exécution | `ISO`* | W1 |
| **ISO-02** | Isolation | **189 tables** acceptent une clé étrangère vers une autre société ; une seule FK composite `(tenant_id, …)` dans toute la base | 🔴 | exécution | `ISO`* | W1 |
| **ISO-03** | Droits | **38 gardes `can_perform` annulées** par une politique jumelle plus faible (deux politiques permissives = OU) | 🔴 | structure | `M18`* | W1 |
| ISO-04 | Base | 326 politiques RLS en double, 11 index en double | 🟡 | structure | à écrire | W1 |
| **PERM-01** | Droits (M-18) | Un rôle `viewer` / `auditor` peut créer, modifier et supprimer par appel direct à l'API | 🔴 | exécution | `M18`* | W1 |

\* Scénarios de constat existants : `scenarios/ISO_ecriture_inter_societes.sql`,
`scenarios/M18_role_non_opposable.sql`. À transformer en tests d'acceptation (vague W1).

#### 1.2.6 Caisse, TVA, production, projets, import, FEC (15 défauts)

| ID | Module | Défaut | Niv. | Preuve | Spéc | Vague |
|---|---|---|---|:---:|:---:|:---:|
| **POS-01** | Caisse | Un ticket « inaltérable » se réécrit de 120 € à 12 € (aucun trigger en modification ; hachage non recalculé → chaîne « valide ») | 🔴 | exécution | `POS`* | W2 |
| **POS-02** | Caisse | Les lignes de ticket se suppriment librement | 🔴 | exécution | `POS`* | W2 |
| POS-03 | Caisse | Pas d'unicité `(tenant_id, terminal_id, sequential_number)` et numéroté par `MAX+1` sans verrou | 🟠 | structure | à écrire | W2 |
| POS-04 | Caisse | `created_at` fourni par le client entre dans le hachage (ticket antidaté cohérent) | 🟠 | lecture | à écrire | W2 |
| **TVA-01** | TVA (M-10) | `submitEdiTva` fabrique un identifiant, écrit `edi_status: 'submitted'` et **ne transmet rien** (la fonction Edge `submit-vat-return`, elle, est correcte — et jamais appelée) | 🔴 | lecture | à écrire | W6 |
| PROD-01 | Production | Nomenclature explosée sur **un seul niveau** (`WHERE bl.bom_id = NEW.bom_id`) | 🟠 | lecture | à écrire | W8 |
| PROD-02 | Production | Ni rebuts ni écarts de coût ; `qty_produced` forcée à la quantité commandée | 🟠 | lecture | à écrire | W8 |
| PROD-03 | Production | Écriture datée du jour de clôture, pas de la date de l'OF (mauvais exercice) | 🟡 | lecture | à écrire | W8 |
| **PROJ-01** | Projets (M-17) | La refacturation des temps **n'existe pas** : `create_billable_line_on_timesheet_stop` ne crée qu'une notification | 🔴 | lecture | `M-17-01`† | W8 |
| PROJ-02 | Projets | Avancement : moyenne non pondérée, **deux** calculs concurrents | 🟠 | lecture | à écrire | W8 |
| PROJ-03 | Projets | Une tâche peut être son propre parent (aucun anti-cycle, 13 triggers en cascade) | 🟠 | exécution | à écrire | W8 |
| **SAGE-01** | Import (M-19) | Les écritures importées restent en brouillon, sans contrôle d'équilibre | 🔴 | lecture | à écrire | W7 |
| SAGE-02 | Import | Les soldes du plan comptable sont **écrasés**, pas cumulés | 🟠 | lecture | à écrire | W7 |
| SAGE-03 | Import | Import partiel sans transaction : comptabilité déséquilibrée | 🟠 | lecture | à écrire | W7 |
| FEC-01 | FEC (M-11) | Une 2ᵉ implémentation du FEC, à 9 colonnes sur 18 | 🟡 | structure | à écrire | W7 |

\* `scenarios/POS_inalterabilite_nf525.sql` — constat uniquement.
† `M-17-01` est **déjà au registre** `ci/expected_failures.sql` avec sa raison : le test existe
(`sql/231_project_time_billing_tests.sql`) et est branché en CI. C'est le seul défaut du registre.

**Total vérifié** : 13 + 15 + 13 + 8 + 5 + 15 = **69 défauts**, dont **32 bloquants** (🔴).
Zéro ligne ajoutée, zéro ligne retirée : c'est la somme exacte du tableau du 23/09.

### 1.3 La mesure de couverture, et ce que chaque défaut lui coûte

Le tableau de la couverture du 24/09, augmenté de la colonne « ce que la vague W change » :

| Module | Tables métier | Portent une logique SQL | Logique traversée | Couverture | Vagues qui la font monter |
|---|---:|---:|---:|---:|---|
| Production | 18 | 1 | 1 | **100 %** (artefact) | W8 |
| Commercial | 52 | 10 | 8 | **80 %** | W3, W6 |
| Stock | 47 | 8 | 6 | **75 %** | W3 |
| Comptabilité | 73 | 19 | 14 | **73 %** | W7 |
| Gestion de projet | 19 | 5 | 3 | **60 %** | W8, **W9** |
| Trésorerie | 30 | 4 | 2 | **50 %** | W6, W7 |
| Ressources humaines | 52 | 10 | 5 | **50 %** | W4, **W9** |
| Système | 43 | 9 | 4 | **44 %** | W1, W6 |
| Tableaux de bord | 4 | 1 | 0 | **0 %** | W7 |
| Reporting | 3 | 0 | 0 | *aucune logique SQL* | — |
| **Total** | **341** | **67** | **43** | **64 %** | |

- **64 %** = la part des tables *qui portent une logique* et qu'un scénario traverse. C'est la
  seule mesure honnête, et elle reste **36 points sous la cible**.
- **80 tables sur 341** sont atteintes par un scénario, soit **23 %**.
- **245 tables sur 341** n'ont ni logique SQL ni scénario.
- **41 tables ne sont référencées ni en SQL ni dans `src/`** : des coquilles vides.
- Le **100 % de la production est un artefact** : une seule table porte une logique
  (`manufacturing_orders`) ; tout son effet passe par `stock_movements`, compté dans « stock ».
  C'est la démonstration exacte du principe de §1.1 : **la ventilation par module cache les chaînes**.

### 1.4 Ce qu'aucun scénario n'a jamais traversé

**(a) 24 logiques SQL jamais traversées** — le code s'exécute en production sans qu'un scénario
chiffré soit jamais passé dessus :

| Table | Module | Pourquoi cela compte | Vague |
|---|---|---|---|
| `vat_returns` | Comptabilité | La déclaration de TVA, rien ne vérifie la CA3 produite | W6 |
| `payroll_accounting_entries` | RH | Le pont paie → comptabilité, par une table à part | W4 |
| `payroll_cumulative` | RH | Une erreur s'y propage sur toute l'année | W4 |
| `lettrage_differences` | Comptabilité | Les écarts de lettrage | W7 |
| `journal_posting_sequences` | Comptabilité | La numérotation des pièces, cœur de la valeur probante | W7 |
| `dsn_declarations` | RH | DSN française | W6 |
| `leave_balances` | RH | Soldes de congés | **W9** |
| `pay_recalls`, `pay_slip_clarified`, `cpf_accounts` | RH | Rappels, bulletin clarifié, CPF | W4 |
| `stock_valuation_layers`, `stock_quantities` | Stock | Les couches de valorisation, traversées en lecture, jamais écrites par un scénario | W3 |
| `landed_costs`, `landed_cost_lines` | Stock / Trésorerie | Coûts annexes qui entrent dans le prix de revient | W3 |
| `bank_reconciliation_suggestions` | Trésorerie | Suggestions de rapprochement | W6 |
| `stock_alerts` | Stock | Alertes de seuil | W3 |
| `webhook_delivery_logs`, `webhook_delivery_queue` | Commercial | File de webhooks (déjà `ASY-01`, puis `H10`/234) | W6 |
| `project_activity_log`, `project_milestones` | Gestion de projet | Journal d'activité et jalons | W8 |
| `api_keys`, `user_totp` | Système | **Aucun scénario sur l'authentification forte** | W1 |
| `carry_forward_log`, `module_documents`, `tracking_warnings` | Système | Reports, documents, avertissements | W7 |
| `chart_pack_switch_log` | Tableaux de bord | Seule logique du module | W7 |

**(b) 20 fonctions Edge, zéro test** (aucun test unitaire, SQL ou e2e ne les référence, aucun test
n'importe de `app/supabase/functions/`) :

```
ai-import-mapping      auth-signup            create-user            cron-payment-reminders
generate-pdf           handle-stripe-webhook  ocr-invoice-import     outgoing-webhooks
parse-bank-statement   public-api             refresh-exchange-rates request-signature
send-notification-email submit-e-invoice      submit-vat-return      sync-bank-transactions
transmit-dsn           validate-vat-vies      verify-iban            verify-siret
```

Nuance mesurée : le **côté SQL** de certaines est couvert (l'inscription par `182`, la garde SSRF
par `168`). Le code Deno lui-même, ses entrées, ses erreurs et ses effets ne le sont nulle part —
ce sont pourtant les seuls points d'entrée exposés au réseau.

> **Écart de décompte, tranché par relevé** : la couverture du 24/09 compte **20** fonctions Edge, et
> `ls app/supabase/functions/` en donne exactement **20** (hors `_shared`). L'audit du 23/09 parle de
> « 21 fonctions déployées » — et `app/mirror-daemon/` existe **à côté** des fonctions Edge (`knip.json`
> et `netlify.toml` le référencent). Le 21ᵉ est donc **très probablement le démon du miroir**, que le
> reste-à-faire traite séparément comme module **M-20** et non comme fonction Edge. À confirmer en
> écrivant le harnais (W6) — le point n'est pas cosmétique : `mirror-daemon` a ses propres droits et
> son propre point d'entrée, et il n'apparaît dans aucune des 46 suites.

### 1.5 La liste blanche — ce qui tient, et qu'il est interdit de casser

Un plan correctif qui ne nomme pas ce qui marche le casse. Les points suivants sont **MESURÉS
corrects** par les deux audits et deviennent des **tests de non-régression** (partie IV, scénarios N1
à N12) :

| # | Ce qui tient | Preuve |
|---|---|---|
| N1 | La RLS **en lecture** tient sur 340 tables, en-tête `x-tenant-id` falsifié compris | H02 + ISO `Y0` |
| N2 | Le noyau comptable (187) : équilibre, exercice ouvert, période ouverte, comptes imputables, numéro définitif sans trou, **même pour les écritures automatiques** | Audit §11 |
| N3 | `generate_depreciation_entry` (211/226) : idempotence, prorata en jours, valeur résiduelle, plafonnement | Audit §4 |
| N4 | Les **1 495 requêtes de lecture** du front passent un PostgREST réel | Audit §11 |
| N5 | Comptabilisation de la caisse : TVA ventilée par taux, écart de caisse, sortie de stock (219) | Audit §13 `A1`/`A2` |
| N6 | `transmit-dsn` et `submit-vat-return` **refusent de simuler** une transmission non configurée | Audit §14 |
| N7 | Export FEC de l'écran : 18 colonnes, tri par numéro définitif | Audit §14 |
| N8 | L'auto-promotion de rôle est bloquée (`Cannot change own role`) | PERM `P3` |
| N9 | Double sortie de stock (M-06) et double entrée à la réception (M-07) **corrigées** ; plus de doublon `reserved_quantity` / `quantity_reserved` | Audit §11 |
| N10 | `fec_export(uuid,…)` n'est **pas** accordée à `authenticated` (228) | Audit §15 |
| N11 | Idempotence de la production : `reference = 'JE-OF-…'`, écriture équilibrée, `reference_type='production'` | Audit §14 |
| N12 | Les suites récentes sont vertes et branchées : 227 (garde de société), 228 (droits des fonctions), 229 (production), 230 (livraison), 231 (temps), 232 (séparation des tâches), 233 (NF-525), 234 (file de webhooks) | `ci.yml` |

### 1.6 Les motifs récurrents — et les deux défauts d'outillage que la fusion fait apparaître

**(a) Les trois motifs du 24/09**, à chercher *systématiquement* dans chaque vague :

1. **Les chemins d'annulation.** Un statut `cancelled` permis par la contrainte `CHECK` qu'aucun
   trigger ne traite. Trouvé sur `manufacturing_orders`, `deliveries`, `stock_movements` (3 défauts
   d'idempotence). **À vérifier** : `goods_receipts`, `purchase_orders`, `pay_runs`, `vat_returns`,
   `sick_leaves` (dont la contrainte autorise `cancelled` : *MESURÉ*, `123_payroll_advanced.sql:169`),
   `purchase_invoices`.
2. **Les colonnes présentes que personne ne lit.** `qty_scrapped` existait et ne servait à rien.
   **À vérifier** : `reserved_quantity`, `invoiced_quantity`, `qty_produced`, `total_vat`
   (*MESURÉ* : `expense_reports.total_vat` ignorée), `products.stock_account_code` (S-10),
   `employees.weekly_hours` (RH-05), `timesheets.overtime_minutes` (*MESURÉ* : jamais lue par la
   paie), `timesheets.absence_type` / `absence_reason` (*MESURÉ* : lues par aucun code du front).
3. **Les fonctions `SECURITY DEFINER` qui lisent ou écrivent sans filtre de société.** Le contrôle
   `check_tenant_guard` ne regarde que les fonctions **exposées à `authenticated` et prenant un
   uuid** : un déclencheur n'entre pas dans ce périmètre. 13 triggers sont dans ce cas (ISO-01).

**(b) Un quatrième motif, propre à la fusion des deux documents** : *la donnée saisie qui n'a pas de
destinataire*. C'est le motif de fond de la partie III (l'absence), et il est déjà présent dans les
deux audits sous d'autres noms. Relevé **MESURÉ** sur le schéma du 15/09 (`00_schema_dump.sql`) et
sur `app/src` au 24/09 :

| Donnée saisie | Écrite par | Lue par | Verdict |
|---|---|---|---|
| `leave_requests` approuvée | l'écran RH | `deduct_unpaid_leave_on_approval` → `payroll_variable_elements`, **si** `leave_rules.affects_pay = true` | **`affects_pay` n'est jamais posé par le seed** (`58_sprint_b_leaves_absences.sql:148-165` : les quatre règles « annual », « rtt », « sick », « unpaid » utilisent la valeur par défaut `false`) ⇒ une absence approuvée **ne produit aucun effet de paie par défaut** |
| `timesheets.absence_type` | **personne** (`grep absence_type app/src` : 0 occurrence hors `types/database-generated.ts`) | `deduct_unpaid_absence_on_timesheet_approval` (`104:304`) | la colonne d'absence du pointage n'est **jamais alimentée** : le trigger est du code mort |
| `timesheets.absence_reason` | personne | personne | colonne morte |
| `sick_leaves` | l'écran RH | `calculate_sick_leave_pay` (`123:210`) — jamais branchée sur un bulletin | arrêt de travail sans effet sur la paie réelle |
| `work_stoppages` | l'écran | **rien** : aucune fonction, aucun trigger hors `set_tenant_id` (`00_schema_dump.sql:12780`) | table morte |
| `expense_report_lines.date` | l'écran notes de frais | **rien** ne la confronte à une absence | à construire (W9) |
| `project_time_entries.start_time` | l'écran projet | rien ne le confronte à une absence | à construire (W9) |
| `project_tasks.assignee_id` | l'écran projet | rien ne le confronte à une absence | à construire (W9) |

**(c) Deux défauts d'outillage, trouvés en fusionnant.** Ils ne figurent pas dans les 69 parce qu'ils
ne sont pas métier — mais ils empêchent de **prouver** les 69 autres :

| ID | Défaut d'outillage | Preuve (MESURÉ) | Correctif |
|---|---|---|---|
| **AUD-X01** | Le registre des échecs attendus est indexé sur `test_id` **seul** : `_audit_expected (test_id text PRIMARY KEY)` (`ci/audit_helpers.sql:29`), et `_audit_assert` cherche par `test_id` sans regarder le fichier. Or **13 fichiers** de tests utilisent les identifiants `T01`…`T07` (`grep -ho "_rec('T0"` : 227 à 234 **et** 240 à 244). Inscrire `T01` au registre blanchirait donc `T01` **dans les treize fichiers**, y compris ceux déjà verts — c'est-à-dire taire une régression réelle. | `_rec('T01'` : 13 occurrences ; clé primaire sur `test_id` | Clé primaire `(file, test_id)` ; `expected_failures.sql` porte deux colonnes ; `_audit_assert` compare le couple |
| **AUD-X02** | Les cinq specs 240 à 244 (S-01→S-11, RH-01→RH-04, SUP-01→SUP-03) **et leurs cinq correctifs** existent dans l'arbre de travail, et `ci.yml` les branche — mais **rien n'est commité** (`git status` : `??` pour les dix fichiers, ` M` pour `ci.yml`) et **aucune n'est inscrite au registre** (`ci/expected_failures.sql` ne contient que `M-17-01`). Conséquence exacte : `HEAD` est vert parce que ces fichiers n'y existent pas ; l'arbre de travail, lui, n'est vert **que si** les correctifs font passer les specs, et **cette exécution n'est pas consignée**. Toute la vague W2/W3/W4 est donc à l'état **écrit**, pas **prouvé**. | `git status --short` (10 fichiers `??`, `ci.yml` ` M`), `ls -la app/sql/24*.sql`, `cat ci/expected_failures.sql` | W0 : corriger AUD-X01, **rejouer les cinq suites**, consigner le « avant rouge / après vert », puis commiter correctif + test + étape CI **ensemble** |

> **AUD-X02 est le point de méthode le plus important de ce plan.** Le dépôt pratique déjà le
> « rouge d'abord » (`expected_failures.sql`, avec la raison écrite). Mais **un test écrit et non
> exécuté n'est pas un test : c'est une intention**. L'état exact au 24/09 dans l'arbre de travail :
>
> ```
> ?? app/sql/240_stock_movement_tenant_and_upsert.sql          (correctif, 9,9 ko)
> ?? app/sql/240_stock_movement_tenant_and_upsert_tests.sql    (spec,   7,3 ko)
> ?? app/sql/241_receipt_stock_and_ledger.sql                  (14,5 ko)
> ?? app/sql/242_delivery_warehouse_and_reservation.sql        (12,0 ko)
> ?? app/sql/243_payroll_and_employee_name.sql                 (30,9 ko)
> ?? app/sql/244_preserve_history_delete_guards.sql            ( 5,6 ko)
>  M .github/workflows/ci.yml     (+41 lignes : les cinq étapes de test)
> MM app/sql/ci/expected_failures.sql   (ne contient que M-17-01)
> ```
>
> Autrement dit : **le travail est fait, la preuve ne l'est pas**. Deux gestes, dans cet ordre :
> (1) rejouer les cinq suites sur une base neuve et **consigner** le verdict (avant rouge / après
> vert, protocole §4.7) ; (2) commiter correctif + spec + étape CI **ensemble**, et n'inscrire au
> registre que ce qui échoue encore, avec le couple `(file, test_id)` — donc après AUD-X01.
> Tant que ce n'est pas fait, la seule ligne de défense est que `HEAD` ne contient rien de tout cela.

---

## Partie II — Plan détaillé de correction

### 2.0 Convention de nommage et allocation des numéros (PROPOSÉ)

Le dépôt a déjà une convention, qu'on ne réinvente pas : **`NNN_<nom>.sql` = le correctif**,
**`NNN_<nom>_tests.sql` = le scénario chiffré du même correctif**, même numéro (précédents : `229`,
`230`, `231`). Le test s'exécute sous `psql -v ON_ERROR_STOP=1` et s'appuie sur
`ci/audit_helpers.sql` (`_mk_tenant`, `_as_user`, `_rec`, `_audit_assert`).

| Numéro | Fichier correctif | Fichier test | Vague |
|---:|---|---|:---:|
| 235 | `235_audit_registry_per_file.sql` *(modifie `ci/audit_helpers.sql`)* | — | W0 |
| 236 | `236_security_definer_tenant_writes.sql` (livré sous ce nom) | `236_security_definer_tenant_writes_tests.sql` | W1 ✅ |
| 237 | `237_composite_foreign_keys.sql` (généré) + `249_composite_fks_after.sql` | `237_composite_foreign_keys_tests.sql` | W1 ✅ |
| 238 | `238_policy_dedup.sql` | `238_policy_dedup_tests.sql` | W1 ✅ |
| 239 | `239_roles_opposables.sql` | `239_roles_opposables_tests.sql` | W1 ✅ |
| **240** | `240_stock_movement_tenant_and_upsert.sql` **écrit** | **`240_…_tests.sql` ✅ écrit** | W3 |
| **241** | `241_receipt_stock_and_ledger.sql` **écrit** | **`241_…_tests.sql` ✅ écrit** | W3 |
| **242** | `242_delivery_warehouse_and_reservation.sql` **écrit** | **`242_…_tests.sql` ✅ écrit** | W3 |
| **243** | `243_payroll_and_employee_name.sql` **écrit** | **`243_…_tests.sql` ✅ écrit** | W4 |
| **244** | `244_preserve_history_delete_guards.sql` **écrit** | **`244_…_tests.sql` ✅ écrit** | W2 |
| 245 | `245_pos_immutability.sql` | `245_pos_immutability_tests.sql` | W2 |
| 246 | `246_cancel_paths.sql` | `246_cancel_paths_tests.sql` | W3 |
| 247 | `247_quality_check_quantity.sql` | `247_quality_check_quantity_tests.sql` | W3 |
| 248 | `248_single_payslip_engine.sql` | `248_single_payslip_engine_tests.sql` | W4 |
| 249 | `249_payroll_period_bounds.sql` | `249_payroll_period_bounds_tests.sql` | W4 |
| 250 | `250_payroll_variable_idempotence.sql` | `250_payroll_variable_idempotence_tests.sql` | W4 |
| 251 | `251_expense_to_ledger.sql` | `251_expense_to_ledger_tests.sql` | W4 |
| 252 | `252_single_depreciation_engine.sql` | `252_single_depreciation_engine_tests.sql` | W5 |
| 253 | `253_edge_columns_and_errors.sql` | `253_edge_columns_and_errors_tests.sql` | W6 |
| 254 | `254_payment_reminders_idempotent.sql` | `254_payment_reminders_idempotent_tests.sql` | W6 |
| 255 | `255_placebos_removed_or_wired.sql` | `255_placebos_removed_or_wired_tests.sql` | W6 |
| 256 | `256_multi_currency_ledger.sql` | `256_multi_currency_ledger_tests.sql` | W7 |
| 257 | `257_analytic_propagation.sql` | `257_analytic_propagation_tests.sql` | W7 |
| 258 | `258_budget_fiscal_scope.sql` | `258_budget_fiscal_scope_tests.sql` | W7 |
| 259 | `259_sage_import_atomic.sql` | `259_sage_import_atomic_tests.sql` | W7 |
| 260 | `260_fec_single_implementation.sql` | `260_fec_single_implementation_tests.sql` | W7 |
| 261 | `261_production_cancel_and_bom_levels.sql` | `261_production_cancel_and_bom_levels_tests.sql` | W8 |
| 262 | `262_project_billing_and_cycles.sql` | `262_project_billing_and_cycles_tests.sql` | W8 |
| 263 | `263_absence_registry.sql` | `263_absence_registry_tests.sql` | **W9** |
| 264 | `264_absence_guards.sql` | `264_absence_guards_tests.sql` | **W9** |
| 265 | `265_absence_payroll_single_path.sql` | `265_absence_payroll_single_path_tests.sql` | **W9** |
| 266 | `266_absence_transverse_tests.sql` | *(c'est le test)* | **W9** |

**Règle de commit, pour chaque ligne du tableau** : `git add` du correctif **et** de son test **et**
de l'étape ajoutée à `.github/workflows/ci.yml` — **un seul commit**, message au format du dépôt
(`fix(<module>): <le défaut> (<ID>, <numéro>)`). Les cinq specs 240-244 sont commitées **dans ce
même mouvement**, jamais isolément.

### W0 — Rendre la CI capable de prouver (AUD-X01, AUD-X02) — 1 j PROPOSÉ

**Objectif** : aucun correctif des vagues suivantes ne peut se prouver sans cette vague.
**Pourquoi d'abord** : les 21 colonnes fantômes et les 29 écritures sans contrôle d'erreur sont
tombées par lecture. Aucun contrôle automatique ne les aurait vues. Les brancher **avant** de
corriger garantit qu'aucune vague n'en réintroduit.

| # | Fichier | Contenu |
|---:|---|---|
| 1 | `app/sql/235_audit_registry_per_file.sql` + `app/sql/ci/audit_helpers.sql` + `app/sql/ci/expected_failures.sql` | `_audit_expected` passe à la clé primaire **`(file, test_id)`** ; `_audit_assert` compare le couple ; `expected_failures.sql` insère trois colonnes. **Sans cela, inscrire `T01` blanchirait `T01` dans 13 fichiers** (AUD-X01) |
| 2 | `app/scripts/check-written-columns.mjs` (déplacé depuis `doc/audit/scenarios/scan-colonnes-ecrites.mjs`) + `scripts/verify-rules/written-columns.baseline.json` | Confronte chaque `.insert()` / `.update()` du front **et de `supabase/functions/`** au schéma réel. **Baseline des 21 écritures impossibles**, chacune datée et liée à sa vague (même principe que `check-knip-ceiling.mjs` : un plafond qui ne peut que baisser) |
| 3 | `app/scripts/check-unchecked-writes.mjs` (depuis `scan-ecritures-non-verifiees.mjs`) + baseline des **29** écritures | Recense les `insert/update/delete` dont l'erreur n'est jamais lue |
| 4 | `app/sql/ci/check_policy_duplicates.sql` | Refuse deux politiques **permissives** sur le même `(table, command)` — c'est ce doublon qui a neutralisé 38 gardes de droits (ISO-03 / ISO-04) |
| 5 | `.github/workflows/ci.yml` + `app/package.json` | Les lectures ont déjà `db:embeds` ; on ajoute `db:written-columns`, `audit:unchecked-writes` et le contrôle SQL des doublons de politiques |
| 6 | `git add app/sql/24{0..4}_*_tests.sql` | Les cinq specs sont **commitées**, et inscrites au registre tant que leurs correctifs ne sont pas écrits : `(240,'T01')` … `(244,'T07')`. La CI est ainsi **verte et les défauts restent visibles** |

**Critère de sortie** : `npm run verify` échoue si un nouveau `.insert()` vise une colonne
inexistante, si une écriture n'est pas contrôlée, si une politique est en double, ou si un test du
registre devient vert sans en être retiré. **Zéro finding hors baseline.**
**Risque** : les scanners sont des scripts `.mjs` ; un extracteur naïf produit des faux positifs.
**Contre-mesure** : baseline **gelée par fichier**, tout retrait se justifie par une ligne motivée,
jamais par un `--force`.

### W1 — Isolation et droits : écrire chez le voisin (ISO-01→04, PERM-01) — 3 j PROPOSÉ

**Objectif** : qu'un utilisateur de la société A ne puisse plus, par un chemin détourné, modifier ou
référencer une donnée de la société B. **C'est une faille, pas un bug** : elle passe avant tout le reste.

**236 — `tenant_id` dans les 13 triggers `SECURITY DEFINER`** (ISO-01). Chaque `UPDATE` / `DELETE`
gagne son filtre de société : `… WHERE id = v_parent_id AND tenant_id = NEW.tenant_id`. Les treize
fonctions nommées : `update_parent_status_on_subtasks_done`,
`update_parent_status_on_subtask_started`, `recalc_project_progress_on_task_change`,
`recalc_parent_progress_on_subtask_change`, `recalc_task_progress_on_action_change`,
`auto_reach_milestone_on_tasks_done`, `update_project_hours_on_time_entry`,
`update_task_time_on_time_entry`, `notify_assignee_on_assignment`, `trigger_revoke_expired_auditors`,
et les quatre `*_lines_refresh_totals`.
**Le contrôle CI est étendu dans le même commit** : `check_tenant_guard.sql` ne regarde aujourd'hui
que les fonctions *exposées à `authenticated` **et** prenant un uuid*. Nouvelle règle, lue sur
`pg_proc.prosrc` : **toute fonction `SECURITY DEFINER` qui écrit dans une table portant `tenant_id`
doit mentionner `tenant_id` (ou `current_tenant_id()`) dans son corps.** Vingt lignes de SQL, et
ISO-01 n'aurait jamais existé.

**237 — Clés étrangères composites `(tenant_id, …)`** (ISO-02, 189 tables). En deux temps :
1. `UNIQUE (tenant_id, id)` sur chaque table « parente » (prérequis technique d'une FK composite) ;
2. FK composite sur les enfants : `FOREIGN KEY (tenant_id, customer_id) REFERENCES customers (tenant_id, id)`.
**Migration générée** (même esprit que `generate-db-types.mjs`) : un script lit `pg_constraint` et
produit le SQL dans le bon ordre. **Priorité là où l'argent circule** : `invoice_lines`, `payments`,
`journal_lines`, `stock_movements`, `bank_transactions`, `project_time_entries`, `expense_report_lines`,
`pay_slip_lines`, `purchase_order_lines`, `sales_order_lines`, `delivery_lines`, `goods_receipt_lines`.
Le reste suit par lots de 20 tables, sans changer de forme.
**Complément, pas remplacement** : la politique RLS « par le parent »
(`EXISTS (SELECT 1 FROM parent p WHERE p.id = enfant.parent_id AND p.tenant_id = current_tenant_id())`),
déjà pratiquée sur les tables de lignes. Elle bloque le rôle `authenticated` ; **elle ne bloque ni
`service_role` ni les triggers** — d'où 236.

**238 — Dédoublonnage des politiques** (ISO-03, ISO-04). `DROP POLICY` du jumeau faible, sur les
326 doublons ; les 38 gardes `can_perform` redeviennent opposables. Les 11 index en double tombent
dans la même migration, et `check_policy_duplicates.sql` (W0.4) interdit le retour.

**239 — Rôles opposables** (PERM-01). Deux vocabulaires à réconcilier : la matrice navigateur
(`hasPermission`, `misc.ts:1233`) et `has_permission` (SQL). Décision **PROPOSÉE** : la clé SQL devient
`<module>.<objet>.<action>` (ex. `commercial.invoice.create`), la matrice navigateur est **générée
depuis la base** (une seule source de vérité), et les politiques des tables sensibles (`invoices`,
`customers`, `suppliers`, `journal_entries`, `pay_runs`, `pay_slips`, `products`, `projects`,
`project_tasks`, `bank_transactions`, `expense_reports`, `leave_requests`, `timesheets`…) gagnent
`AND can_perform('<objet>','<action>')`. Un `viewer` et un `auditor` n'ont alors plus aucun droit
d'écriture, y compris par appel direct à PostgREST.
**Test** : `scenarios/M18_role_non_opposable.sql` (`P1`, `P2` refusés ; `P3` — auto-promotion — reste
vert, N8 non régressé).

**Critère de sortie** : les deux scénarios rejoués sous le **vrai rôle `authenticated`** sont verts
(`Y0` toujours 0 ligne visible pour le client de B, `Y1`/`Y2` refusés, `Y3` statut de B inchangé),
`check_tenant_guard` étendu vert, `check_policy_duplicates` vert, et les 340 tables de `105` restent
isolées en lecture (N1).

### W2 — Inaltérabilité et pièces à conserver (POS-01→04, SUP-01→03) — 2,5 j PROPOSÉ

**244 — Gardes de suppression** (SUP-01, SUP-02, SUP-03). La spec est déjà écrite : `T01` (salarié
avec bulletin → refusé, bulletin conservé), `T02` (salarié sans bulletin → toujours supprimable),
`T03`/`T04` (compte bancaire, idem), `T05`/`T06` (article, idem), `T07` (supprimer la **société**
emporte bien ses bulletins : la garde ne vise que la fiche seule).
Le correctif n'est **pas** une fonction métier : c'est un changement de `ON DELETE` sur trois clés
étrangères (CASCADE → `RESTRICT`) plus un refus explicite et son message (« Ce salarié a N bulletin(s)
de paie : la suppression est refusée »). Fichier : `244_preserve_history_delete_guards.sql`.
**Sous-produit obligatoire** : les écrans doivent offrir une **sortie légitime** (archiver/désactiver
`status = 'inactive'`), sinon la garde sera contournée par un `UPDATE` de masse côté produit.

**245 — Inaltérabilité NF-525** (POS-01→04).
- **POS-01/02** : `BEFORE UPDATE OR DELETE` sur `pos_tickets` **et** `pos_ticket_lines`, refusant toute
  modification d'un ticket `completed` hors fonction dédiée d'annulation, avec **recalcul du hachage
  en modification** — le ticket ne peut pas changer sans que la chaîne le dise.
- **POS-03** : `UNIQUE (tenant_id, terminal_id, sequential_number)` + numérotation sous
  `pg_advisory_xact_lock(hashtext(terminal_id::text))` (au lieu de `MAX+1` sans verrou).
- **POS-04** : `created_at` en `DEFAULT now()` et **hors du hachage** ; un ticket antidaté n'est plus
  cohérent par construction.
- **Plus** : un `CHECK` sur le statut du ticket (il n'en a aucun) — un ticket dont le statut n'est pas
  exactement `completed` est exclu de l'écriture de clôture **en silence**.

**Test** : `scenarios/POS_inalterabilite_nf525.sql` devient une acceptation — `B1` (120 € → 12 €) et
`B2` (suppression d'une ligne) **refusés**, `B3` (le journal NF-525 mentionne la modification),
`A1`/`A2` restent verts (N5).

### W3 — La chaîne stock, achats, ventes, comptabilité (S-01→S-13) — 4 j PROPOSÉ

Trois specs existent déjà et sont rouges : c'est le meilleur endroit pour commencer, le « rouge
d'abord » est déjà fait.

| Fichier | Défauts | Changement précis | Test |
|---|---|---|---|
| `240_stock_movement_tenant_and_upsert.sql` | S-08, S-09 | `increment_stock` / `decrement_stock` prennent le `tenant_id` **du mouvement** (paramètre explicite), plus jamais `current_tenant_id()` ; `ON CONFLICT DO UPDATE` au lieu de `DO NOTHING` ; **refus** d'une sortie supérieure au stock du dépôt (aujourd'hui `GREATEST(…, 0)` : le dépôt tombe à 0 pendant que l'article baisse) | `240_…_tests.sql` **écrit** : T01→T04 |
| `241_receipt_stock_and_ledger.sql` | S-01→S-04, S-10, S-11 | `goods_receipts` gagne `warehouse_id` (repli : dépôt de la société) ; la ligne reprend le prix de `purchase_order_lines.unit_cost` ; le mouvement porte dépôt **et** coût → couche de valorisation **et** écriture D 310000 / C 603000 ; les comptes viennent de `resolve_stock_account` / `resolve_variation_account` (existants depuis la 125, appelés nulle part) ; article suivi sans lot → **refus**, plus un avertissement | `241_…_tests.sql` **écrit** : T01→T07 |
| `242_delivery_warehouse_and_reservation.sql` | S-05, S-06, S-07 | la sortie pose le `warehouse_id` de la ligne ou du dépôt par défaut → consommation réelle des couches ; libération des réservations branchée sur `delivery_status = 'delivered'` **et** `status`, plus seulement sur un statut que rien ne pose ; libération **partielle** si livraison partielle | `242_…_tests.sql` **écrit** : T01→T05 |
| `246_cancel_paths.sql` | S-12, S-13 | Traiter **les chemins d'annulation** : BL `shipped → cancelled → shipped` ne sort plus deux fois ; une réception annulée remet le stock ; `quality_checks` gagne une **quantité contrôlée** (aujourd'hui un échec rebute la **totalité** de la ligne reçue) | `246_…_tests.sql` : 4 cas à écrire |

**Critère de sortie** : les cinq suites stock/achats/ventes **vertes**, plus `173` (valorisation),
`177` (coût de fabrication) et `229` (production) non régressées. Pour chaque grandeur — stock par
dépôt, couche, écriture, CUMP, réservation — **une seule vérité**.

### W4 — Paie et RH : quatre façons de compter un mois (RH-01→RH-10) — 4 j PROPOSÉ

**243 — la spec écrite** (`243_…_tests.sql`, T01→T05) : `T01` une fiche créée avec `name` seul doit
remplir `first_name` et `last_name` pour les 18 écrans ; `T02` la reprise des fiches existantes ;
`T03` `calculate_payslip` ne doit exister **qu'en version légale** `(uuid, text, uuid)` ; `T04` un
pointage approuvé **deux fois** ne produit pas quatre lignes d'éléments ; `T05` un pointage de 9 h
dont 60 min supplémentaires donne **1 h** supplémentaire (ni 2, ni 11).
Correctif `243_payroll_and_employee_name.sql` : trigger de découpe du nom à l'insertion (+ reprise
`UPDATE` des fiches existantes), `DROP FUNCTION calculate_payslip(uuid, text)`, garde
`NOT EXISTS (… source_id = NEW.id)` dans `sync_timesheet_to_payroll`, et **une seule** source
d'heures supplémentaires (`overtime_minutes` alimenté par un paramètre de paie, seuil unique).

**249 — les bornes de période et les montants** (RH-06, RH-07, RH-09, RH-10). Quatre défauts, deux
lignes de code chacun :
- RH-06 : les quatre requêtes `.lte('date', \`${period}-31\`)` (`leavesAbsences.ts:461, 586, 612, 635`)
  passent au **dernier jour réel du mois** (calculé, jamais littéral). **MESURÉ** : aujourd'hui 5 mois
  sur 12 lèvent `22008` — février, avril, juin, septembre, novembre ;
- RH-07 : `Number(exp.amount)` → `Number(exp.total_amount)` ;
- RH-09 : un congé à cheval sur deux mois ne doit plus être omis : le filtre passe de
  *contenu dans la période* à **intersection de périodes** ;
- RH-10 : garde d'idempotence sur `generateMealVoucherElements` (même motif `NOT EXISTS` que RH-03),
  avec au passage une **contrainte d'unicité** sur `payroll_variable_elements`
  `(tenant_id, employee_id, period, element_type, source, source_id)` — c'est elle qui rend les
  quatre alimentations (`timesheet`, `leave_request`, `expense_report`, `salary_advance`) sûres.
  **MESURÉ** : cette contrainte n'existe pas aujourd'hui (aucun index unique hors `id`).

**251 — notes de frais → grand livre** (RH-07, RH-08). `integrate_expense_report_on_approval` écrit le
montant correct et **l'écriture** : D 625x (charge) + D 44566 (TVA récupérable depuis `total_vat`),
C 421 (salarié). Aujourd'hui : montant nul **et** aucune ventilation de TVA. La période vient de
`period` / de la date des lignes, **pas** de `submitted_at` (qui peut tomber dans le mois suivant).

**RH-05 — une seule convention mensuelle.** Aujourd'hui quatre cohabitent : `weekly_hours × 4,33`
(retard), `/30` (absence non payée et congé sans solde), `/21` (congé), `/151,67` (heures
supplémentaires). Deux retenues pour le même jour donnent deux montants différents.
**PROPOSÉ** : un **jeu de paramètres par société** (`company_settings.absence_method`, déjà présent,
+ `payroll_legal_parameters`) définissant *le* diviseur mensuel et le taux horaire, lu par **les
quatre** chemins. Prérequis de la localisation : ces constantes sont françaises et codées en dur.

**Critère de sortie** : `243` vert, `249`/`250`/`251` verts, `181` (paie → grand livre), `212`
(paiement) et `224` (périmètre du paiement) non régressés, et **un seul** élément de paie par
document source — vérifié par la contrainte d'unicité, pas par un `NOT EXISTS` recopié quatre fois.

### W5 — Un seul moteur par grandeur : amortissement, heures supplémentaires (IMMO-01→05, RH-02, RH-04) — 2 j PROPOSÉ

**Le défaut n'est pas le calcul : c'est qu'il y en a trois.**

| Grandeur | Moteurs en présence (MESURÉ) | Décision PROPOSÉE |
|---|---|---|
| Amortissement | `generate_depreciation_entry` (211/226, **correct**) ; `calculate_depreciation` (RPC historique) ; `calculateDepreciation` (`misc.ts:57`, appelé par la page) | **Supprimer les deux derniers.** La page appelle le moteur SQL (`generate_depreciation_entry`), qui comptabilise. Les trois méthodes proposées à l'écran (`straight_line`, `declining_balance`, `units_of_production`) deviennent réellement implémentées **ou retirées de l'écran** : aujourd'hui `depreciation_method` est stockée et **aucun** moteur ne la lit |
| Heures supplémentaires | `calculate_lateness_on_timesheet` → `overtime_minutes` (jamais lu par la paie) ; `sync_timesheet_to_payroll` (> 7 h/jour, **montant 0**) ; `importTimesheetElements` (front, > 8 h/jour, taux × 1,25) | **Un seul seuil**, un seul calcul, côté SQL, alimenté par `payroll_legal_parameters`, avec le taux de majoration lu du paramétrage. Le front n'importe plus d'heures supplémentaires : il les **lit** |
| Exercice | `calculateDepreciation` part de `Date.now()` → relancer le calcul après clôture **écrase** `current_value` | Le calcul est borné à l'exercice ; une dotation d'exercice clos ne se recalcule pas |

**Plus** : `calculateAllDepreciation` enveloppe chaque immobilisation dans un `try/catch { console.error }`
— une dotation en échec est sautée en silence et la fonction rend une liste partielle **comme un
succès**. Le correctif renvoie un résultat **par immobilisation** (`ok` / `erreur`), et l'écran
affiche les échecs.
**Critère de sortie** : un seul point d'entrée d'amortissement (grep : zéro appel à
`calculateDepreciation` dans `src/`), `252_…_tests.sql` vert (2 exercices, méthode dégressive ou
retrait explicite, échec visible), et le test `211`/`226`/`231` non régressé (N3).

### W6 — Les fonctions Edge et les écrans qui mentent (EF-01→EF-08, TVA-01) — 3,5 j PROPOSÉ

**253 — les 21 colonnes fantômes, et les erreurs jamais lues.** Table de correspondance
**MESURÉE** (`scenarios/scan-colonnes-ecrites.mjs` sur le schéma réel) :

| Fonction Edge | Colonne écrite | La table porte |
|---|---|---|
| `cron-payment-reminders` | `days_overdue`, `sent_at`, `email_sent` | rien de tout cela |
| `submit-e-invoice` | `e_invoice_status`, `e_invoice_platform`, `e_invoice_submitted_at`, `e_invoice_id` | aucune colonne `e_invoice*` |
| `request-signature` | `provider`, `provider_signature_id`, `status`, `signers`, `initiated_at` | `signature_hash`, `signer_name`… |
| `sync-bank-transactions` | `provider_transaction_id` | (existe sur `online_payments`) |
| `sync-bank-transactions` | `provider_requisition_id`, `link_url`, `user_id` | `provider_connection_id` |
| `outgoing-webhooks` | `http_status` | `response_code` |
| `outgoing-webhooks` | `next_retry_at` | `next_attempt_at` |
| `handle-stripe-webhook` | `metadata` | — |
| `banking.ts:101` | `matched_line_id` | `matched_invoice_id` |
| `MobileApproval.tsx:45` | `leave_requests.manager_comment` | (existe sur `expense_reports`) |

**Chaque écriture lit son erreur** (`const { error } = …; if (error) throw/return`) ; aucun
`if (!insertErr) imported++`. **Décision à prendre pour les 11 fonctions sans appelant** : les
brancher (l'écran existe) ou les retirer. Un écran qui affiche « succès » sans rien faire est pire
qu'un écran absent (règle reprise de l'audit §16).

**254 — relances de paiement** (EF-01, EF-02). `.single()` → `.maybeSingle()` ; les trois colonnes
inventées remplacées ; **index unique** `(tenant_id, invoice_id, reminder_level)` — c'est lui qui
empêche la relance quotidienne, pas un test applicatif ; filtre de statut corrigé (la contrainte
`invoices_status_check` **interdit** `validated` et `posted` : la requête ne pouvait rien renvoyer) ;
messages et devise **paramétrés** (le `€` est en dur).

**255 — placebos** (EF-03, EF-04, EF-05, EF-06, EF-07, TVA-01).
- `syncBankConnection` **appelle** `sync-bank-transactions` (ou le bouton disparaît) ; l'état affiché
  vient du résultat réel, jamais d'un tampon de date.
- `submitEdiTva` appelle la fonction Edge `submit-vat-return`, **qui est correcte** et refuse de
  simuler : c'est exactement le comportement voulu.
- `EInvoicePage` appelle `submit-e-invoice` (aujourd'hui il génère un XML et le télécharge).
- `request-signature` est appelé, ou la page est retirée.

**Le harnais de test des fonctions Edge — la lacune la plus coûteuse du dépôt** (20 fonctions, zéro
test). **PROPOSÉ, en trois étages, du moins cher au plus cher** :
1. **statique** (déjà livré en W0.2) : toute colonne écrite existe — c'est ce qui aurait vu EF-04,
   EF-05, EF-07, EF-08 ;
2. **unitaire sans base** : les parties pures (`facturX.ts` : profil, numéro définitif ;
   `verify-iban`, `verify-siret` ; la vérification de signature Stripe) testées en Deno/Node ;
3. **contrat HTTP** : pour les fonctions appelées de l'extérieur, un test qui envoie une requête
   **sans jeton** et exige un refus (401/403) — la garde SSRF est déjà testée (168), pas l'accès.

**Critère de sortie** : le scanner de colonnes est vert **sur `supabase/functions/`**, le registre des
21 écritures impossibles est vidé, `cron-payment-reminders` rejoué deux fois n'envoie qu'**une**
relance, et l'API publique renvoie 401 sans jeton.

### W7 — Comptabilité avancée : devises, analytique, budgets, import, FEC — 6 j PROPOSÉ

**256 — multi-devises** (M01-01→03). Chantier de **schéma**, pas de fonction :
`journal_lines` gagne `currency_code`, `amount_currency`, `exchange_rate` (**M01-02**) ; le trigger
d'écriture **applique le taux** du document (**M01-01** : aujourd'hui 1 000 USD au taux 0,90 entre
pour 1 000 EUR et fausse le compte client, le chiffre d'affaires **et** la TVA) ; l'écart de change au
règlement écrit 666/766 ; la réévaluation de clôture alimente `currency_revaluations` (**M01-03** :
`createExchangeGainLossEntry` n'a aucun appelant, les deux écrans sont vides à vie).
Dépendance : la localisation (les devises ne sont pas qu'européennes).

**257 — analytique** (ANA-01→03). Les deux triggers vides sont **implémentés** :
`propagate_analytic_section` lit la section de la ligne de document (ou
`analytic_distribution_lines`, qui existe et n'est lue par **aucune** fonction SQL) ;
`check_analytic_balance` devient **bloquant** sur les classes 6/7 (aujourd'hui « non bloquant pour
compatibilité »). L'exigence « balance analytique = balance générale sur 6/7 » devient alors
**vérifiable** ; la balance est bornée à l'exercice (ANA-03).

**258 — budgets** (BUD-01→04). Une clause `WHERE` : le réalisé est borné à `fiscal_year_id` **et** au
journal, en excluant à-nouveaux, clôture et **brouillons** ; les engagements sont créés depuis la
commande d'achat et **soldés à la facturation** (aujourd'hui rien ne les libère : double déduction) ;
N+1 → une requête agrégée pour tous les budgets.

**259 — import Sage** (SAGE-01→03). Les écritures importées sont **validées** après contrôle
d'équilibre (aujourd'hui elles restent en brouillon, sans contrôle), les soldes de comptes sont
**cumulés** et non écrasés, et l'import est **transactionnel** (un import partiel laissait la
comptabilité déséquilibrée).

**260 — FEC** (FEC-01). Une seule implémentation, à **18 colonnes**, celle de l'écran (conforme,
N7) ; l'autre (9 colonnes) est supprimée avec son test éventuel. Le tableau de bord
(`chart_pack_switch_log`, seule logique du module, jamais traversée) reçoit son scénario.

### W8 — Production et projets : ce qui sort de la fabrique et ce qui se facture (PROD-01→03, PROJ-01→03) — 3 j PROPOSÉ

**261 — production** (PROD-01→03).
- Multi-niveaux : `create_stock_on_manufacturing_complete` lit `bom_lines` à **un seul niveau**
  (`WHERE bl.bom_id = NEW.bom_id`). Correctif : **CTE récursive** qui explose jusqu'aux composants
  achetés, avec les coefficients de quantité à chaque niveau, et **garde de profondeur** (un cycle de
  nomenclature doit être refusé par un message, pas par un dépassement de pile).
- Rebuts et écarts : `qty_produced = NEW.quantity` force la quantité produite à la quantité
  *commandée*. Le correctif s'appuie sur les colonnes qui existent déjà — `qty_scrapped` (traitée par
  la 229 sur le chemin nominal), `products.scrap_rate` — et **répartit le coût sur les pièces bonnes**.
  Un écart de quantité ou de coût doit apparaître, pas disparaître.
- Dates : l'écriture et les mouvements sont datés de `CURRENT_DATE`, pas de la date de l'OF. Un ordre
  clôturé en retard tombe dans le **mauvais exercice** → passer à `NEW.completion_date` (ou
  équivalent), et le noyau comptable (N2) refusera une période fermée, ce qui est le comportement voulu.
- Comptes `601000` / `310000` / `355000` / `713500` codés en dur → `resolve_stock_account` /
  `resolve_variation_account` (même correctif que S-10, à faire **une seule fois**).

**262 — projets** (PROJ-01→03).
- **Refacturation des temps** (`M-17-01`, déjà au registre) : `create_billable_line_on_timesheet_stop`
  doit créer une **ligne de devis** (`quotes` + `quote_lines`) ou une **ligne de facture** selon
  `is_billable` / `hourly_rate` / le mode de facturation du projet — pas une notification. Le test
  `231` existe déjà et passera au vert : **retirer `M-17-01` de `ci/expected_failures.sql` dans le
  même commit** (c'est la règle du registre).
- Avancement : **une seule** formule, pondérée par l'effort (`effort_estimate_h`, qui existe), et un
  seul trigger (`recalc_parent_progress_on_subtask_change` **ou**
  `recalc_project_progress_on_task_change` — pas les deux).
- Anti-cycle : une tâche ne peut pas être son propre parent, ni son ancêtre. Contrainte par
  **trigger récursif** (`WITH RECURSIVE` sur `parent_id`, profondeur limitée à 10). Aujourd'hui
  **rien** ne l'empêche, et 13 triggers se réécrivent en cascade : un cycle produit une récursion sans
  garde de profondeur.

**Critère de sortie** : `229` (production) reste vert et gagne les cas multi-niveaux et rebuts/écarts ;
`231` passe intégralement au vert et quitte le registre ; `project_tasks` refuse un cycle (test
d'exécution) ; l'écriture d'un OF dans un exercice clos est **refusée** avec un message.

---

## Partie III — Le chaînage transverse : l'absence (W9) — le cœur de la demande

### 3.1 État mesuré : quatre sources d'absence qui ne se parlent pas, et zéro contrôle en aval

Tout ce qui suit est **MESURÉ** (schéma `00_schema_dump.sql`, migrations 58/104/123, `grep` sur
`app/src`), au 24/09 :

| Source d'absence | Table | Déclarée où | Effet en paie | Effet sur le temps | Effet sur les frais | Effet sur les tâches |
|---|---|---|---|---|---|---|
| Congés / RTT / sans solde | `leave_requests` (+ `leave_rules`) | écran RH | `deduct_unpaid_leave_on_approval` → **mort** : `leave_rules.affects_pay` n'est **jamais** mis à `true` par le seed (`58:148-165`) | **aucun** : rien n'écrit dans `timesheets` | **aucun** | **aucun** |
| Maladie / AT / maternité | `sick_leaves` | écran RH | `calculate_sick_leave_pay` (`123:182-215`) existe, **n'est branchée sur aucun bulletin** | **aucun** | **aucun** | **aucun** |
| Pointage d'absence | `timesheets.absence_type` (+ `absence_reason`) | **personne** : 0 occurrence d'écriture dans `app/src` | `deduct_unpaid_absence_on_timesheet_approval` (`104:290`) — **code mort** faute de donnée | n/a | **aucun** | **aucun** |
| Arrêt de travail (table dédiée) | `work_stoppages` | écran | **aucune fonction** | **aucun** | **aucun** | **aucun** |

**Et surtout, mesuré par lecture du schéma et du code** :

- Rien — **aucune fonction, aucun trigger, aucune contrainte, aucune politique** — ne confronte
  `expense_report_lines.date` à une absence. Un salarié en congé sans solde peut donc **soumettre sa
  note de frais pour la journée même** et être remboursé.
- Rien ne confronte `timesheets.hours` / `overtime_minutes` à une absence : le trigger
  `calculate_lateness_on_timesheet` calcule les heures supplémentaires **sans jamais regarder
  `absence_type`**, et `sync_timesheet_to_payroll` recalcule « au-delà de 7 h » de la même façon.
- Rien ne confronte `project_time_entries.start_time` à une absence : un salarié absent peut saisir du
  temps projet sur une tâche. C'est le chemin le plus coûteux, parce que ce temps peut finir
  **facturé** au client (W8) et alimenter le chiffre d'affaires.
- Rien ne confronte `project_tasks.assignee_id` à une absence, ni la clôture d'une tâche.
- `leave_balances` (soldes) n'est traversée par aucun scénario : on ne peut pas prouver qu'un solde est
  débité à l'approbation et **restitué à l'annulation**.
- Le seul pont qui existe (congé → `payroll_variable_elements`) est **désarmé par défaut**, et le
  chemin jumeau (pointage d'absence → paie) attend une colonne que personne ne remplit. **Deux chemins
  de retenue potentiels pour la même journée** : si on répare l'un sans unifier, on paie deux fois la
  même absence. C'est le piège à ne pas déclencher (voir TRV-11).

### 3.2 La cible : **une seule vérité par jour et par salarié**

**263 — le registre d'absence** (`263_absence_registry.sql`). On ne répare pas quatre sources : on les
**réduit** à une table de vérité, alimentée par les quatre, et lue par tous les modules.

```sql
CREATE TABLE employee_absence_days (
  tenant_id           uuid NOT NULL,
  employee_id         uuid NOT NULL,
  day                 date NOT NULL,
  absence_kind        text NOT NULL,      -- annual|rtt|sick|work_accident|maternity|unpaid|personal|mission|stoppage|unjustified
  origin              text NOT NULL,      -- leave_request|sick_leaf|work_stoppage|timesheet
  origin_id           uuid,
  justification_state text NOT NULL DEFAULT 'pending',  -- pending|provided|missing
  blocks_work         boolean NOT NULL DEFAULT true,    -- interdit pointage, HS, temps projet
  allows_expenses     boolean NOT NULL DEFAULT false,   -- autorise les frais (mission uniquement)
  paid                boolean NOT NULL DEFAULT false,
  pay_rule_code       text,               -- règle de paie applicable (maintien, IJSS, retenue)
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, employee_id, day)   -- ← un jour, une absence, une vérité
);
```

**Alimentation — quatre déclencheurs, une seule brique.** Chacun appelle
`rebuild_absence_days(tenant_id, employee_id, from, to)` ; la brique est **idempotente** : elle
supprime puis re-remplit la plage. C'est elle qui rend l'**annulation** correcte (défaut retrouvé trois
fois sur les modules d'annulation, cf. §1.6a) :

| Déclencheur | Sur | Convertit |
|---|---|---|
| `sync_absence_from_leave_request` | `leave_requests` (`INSERT OR UPDATE OF status, start_date, end_date, leave_type`) | `annual` → `annual`, `rtt` → `rtt`, `unpaid` → `unpaid`, `sick` → `sick` |
| `sync_absence_from_sick_leave` | `sick_leaves` (statut inclus) | `sickness` → `sick`, `work_accident` → `work_accident`, `maternity`/`paternity`/`parental` → `maternity` |
| `sync_absence_from_stoppage` | `work_stoppages` | → `stoppage` |
| `sync_absence_from_timesheet` | `timesheets` (`INSERT OR UPDATE OF absence_type, date`) | `sick / unpaid / personal / mission` → idem (**c'est ce qui donne enfin un sens à `absence_type`, aujourd'hui jamais écrit**) |

**Résolution des conflits** (deux sources le même jour) : priorité
`work_accident` > `sick` > `maternity` > `stoppage` > `unpaid` > `annual`/`rtt` > `mission`, et le
conflit est **journalisé** (`absence_conflict_log`) au lieu d'être arbitré en silence. Un jour
d'absence ne peut pas être à la fois « congé payé » et « maladie » : la paie ne doit jamais avoir à
choisir toute seule.

**L'API de lecture, écrite une fois, utilisée partout** :

| Fonction | Usage |
|---|---|
| `absence_kind_on(employee, day) → text` | la question simple : que se passe-t-il ce jour-là ? |
| `is_employee_absent(employee, day) → boolean` | le test rapide pour les gardes |
| `assert_not_absent(employee, day, context) → void` | lève l'exception **rédigée** : `« Absence 'unpaid' le 10/03/2026 (congé sans solde) : pointage refusé (timesheets). »` |
| `assert_can_claim_expense(employee, day) → void` | autorise si `allows_expenses` (mission), refuse sinon |
| `absence_summary(employee, from, to)` | pour les écrans (calendrier RH, contrôle de paie) |

### 3.3 La table de vérité — ce qu'un jour d'absence autorise et ce qu'il interdit

C'est le contrat que la partie IV teste, ligne par ligne. `✅` autorisé · `⛔` **refusé, avec message
nommant le type d'absence, la date et le module** · `⚠️` autorisé sous justification tracée.

| Jour J du salarié E | Pointage / heures | Heures supp. | Temps projet | Note de frais (ligne du jour) | Nouvelle tâche assignée | Clôture d'une tâche par E | Paie | Solde de congés | Temps facturé au client |
|---|:---:|:---:|:---:|:---:|:---:|:---:|---|---|:---:|
| **Aucune absence déclarée** | ✅ | ✅ (seuil paramétré) | ✅ | ✅ | ✅ | ✅ | salaire plein | inchangé | ✅ |
| **`annual`** congé payé | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ *(sauf tiers)* | plein (0 retenue) | **−1 j** | ⛔ |
| **`rtt`** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ *(sauf tiers)* | plein | **−1 j RTT** | ⛔ |
| **`sick`** maladie | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | maintien + IJSS selon `sick_leaves` (`waiting_days`, `maintenance_rate`, `daily_ijss`) | sans effet | ⛔ |
| **`work_accident`** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | idem `sick`, **sans délai de carence** | sans effet | ⛔ |
| **`maternity`** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | selon paramétrage | sans effet | ⛔ |
| **`unpaid`** congé sans solde | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | **retenue 1 j** (une seule fois, cf. TRV-11) | sans effet | ⛔ |
| **`personal`** absence personnelle | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | **retenue 1 j** | sans effet | ⛔ |
| **`stoppage`** arrêt de travail / chômage technique | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | selon paramétrage société | sans effet | ⛔ |
| **`mission`** déplacement professionnel | ⚠️ *(heures de mission)* | ✅ *(règles HS mission)* | ✅ | ✅ **+ marquée `mission_absence_id`** | ✅ | ✅ | plein + remboursement des frais | inchangé | ✅ |
| **`unjustified`** absence non justifiée | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | retenue **+** alerte RH | ⛔ | ⛔ |

### 3.4 Les seize contrôles transverses à créer (TRV-01 → TRV-16)

Chaque ligne est un défaut à corriger **et** un test à écrire. Le refus est une **exception SQL
rédigée** (elle remonte jusqu'à l'écran), jamais un silence.

| ID | Règle | Où elle s'applique (264) | Ce qui se passe aujourd'hui (MESURÉ) |
|---|---|---|---|
| **TRV-01** | Un jour d'absence, par salarié, pour toute la société : congés, maladie, arrêt de travail et pointage d'absence convergent dans `employee_absence_days` | déclencheurs des 4 sources + `rebuild_absence_days` | 4 sources indépendantes, aucun point de convergence |
| **TRV-02** | Deux sources contradictoires le même jour : la priorité tranche **et** journalise | `absence_conflict_log` + PK `(tenant_id, employee_id, day)` | aucune détection |
| **TRV-03** | **Pointage refusé** un jour d'absence bloquante (`timesheets`) | `BEFORE INSERT OR UPDATE` sur `timesheets` : `assert_not_absent(employee_id, date, 'pointage')` | accepté : rien ne regarde l'absence |
| **TRV-04** | **Heures supplémentaires refusées** un jour d'absence bloquante (même si l'horaire saisi dépasse le seuil) | `calculate_lateness_on_timesheet` **et** `sync_timesheet_to_payroll` consultent `is_employee_absent` | les HS sont calculées sans jamais regarder `absence_type` |
| **TRV-05** | **Temps projet refusé** un jour d'absence bloquante (`project_time_entries`) | `BEFORE INSERT OR UPDATE` : `assert_not_absent(employee_id, start_time::date, 'temps projet')` | accepté — **et ce temps peut être facturé au client** |
| **TRV-06** | **Ligne de note de frais refusée** si sa `date` est un jour d'absence qui n'autorise pas les frais — vérifié à la **soumission** *et* à l'**approbation** | `expense_report_lines` (`BEFORE INSERT/UPDATE`) + `integrate_expense_report_on_approval` | `expense_report_lines.date` existe, **rien** ne la confronte à une absence |
| **TRV-07** | **Assignation d'une nouvelle tâche refusée** à un salarié absent (`project_tasks.assignee_id`) | `BEFORE INSERT OR UPDATE OF assignee_id` sur `project_tasks` | accepté |
| **TRV-08** | Un salarié absent ne peut pas **clore** lui-même une tâche (`status → done`) ; un tiers peut, et le journal d'activité le dit | `BEFORE UPDATE OF status` sur `project_tasks` : refus seulement si l'auteur de l'écriture est l'absent | accepté |
| **TRV-09** | Le **temps facturable** saisi par un absent est refusé (facturation) — corollaire de TRV-05 côté écran de facturation | `create_billable_line_on_timesheet_stop` / génération de facture : filtre `is_billable AND NOT is_employee_absent` | aucun filtre : le temps d'un absent peut être facturé |
| **TRV-10** | **Mission** : l'absence n'interdit ni les frais ni le temps, mais la ligne de frais est **marquée** (`mission_absence_id`) et le justificatif exigé | `assert_can_claim_expense` (autorise si `allows_expenses`) | la valeur `mission` existe dans le `COMMENT` de `absence_type`… **et n'est utilisée nulle part** |
| **TRV-11** | **Une seule retenue par jour d'absence** : la paie se calcule **depuis `employee_absence_days`**, jamais depuis deux sources | `265_absence_payroll_single_path.sql` : `deduct_unpaid_absence_on_timesheet_approval` **et** `deduct_unpaid_leave_on_approval` sont remplacés par un seul chemin | deux chemins de retenue existent (`timesheets` /30 et `leave_requests` /30) : réparer `affects_pay` sans unifier **paierait deux fois** |
| **TRV-12** | Absence **annulée ou rejetée** : l'élément de paie non intégré est supprimé ; s'il est déjà intégré à un bulletin validé, un **élément inverse** est créé | déclencheurs de `rebuild_absence_days` + garde `payroll_variable_elements.integrated` | rien : le pont des congés ne sait pas revenir en arrière |
| **TRV-13** | Absence **rétroactive** sur une période de paie close : refus explicite, ou régularisation sur la période courante (décision à prendre) | contrôle dans `rebuild_absence_days` contre `fiscal_periods` / `pay_runs` validés | rien |
| **TRV-14** | Justificatif opposable : `leave_rules.requires_justification`, `medical_certificate_url`, `absence_reason` déterminent `justification_state` ; une absence non justifiée devient `unjustified` après le délai | `rebuild_absence_days` + vue d'alerte RH | `absence_reason` **jamais écrite**, `requires_justification` jamais contrôlée |
| **TRV-15** | `leave_balances` : débité à l'**approbation**, restitué à l'**annulation**, recalculable par `rebuild` | déclencheurs de `leave_requests` | **aucun scénario** ne traverse `leave_balances` (couverture §3) |
| **TRV-16** | **Contrôle d'intégrité quotidien** : `check_absence_conflicts()` liste les jours portant une absence **et** (pointage, HS, temps projet ou frais) ; l'écran « Anomalies » les montre, un envoi quotidien prévient l'administrateur | job `pg_cron`, sur le modèle de `payment-reminders-daily` | rien : sans ce filet, une donnée saisie **avant** la mise en place, ou par un chemin détourné, passerait inaperçue |

### 3.5 La matrice : qui doit lire l'absence de qui

C'est le tableau qui répond directement à la question « est-ce que l'absence déclarée quelque part est
reprise ailleurs ? ». Aujourd'hui : **quatre lecteurs sur neuf, et aucun ne nomme l'absence.**

| Module lecteur | Ce qu'il doit lire | Effet attendu | Aujourd'hui (MESURÉ) |
|---|---|:---:|---|
| **RH / congés** (`leave_requests`, `leave_balances`, `sick_leaves`, `work_stoppages`) | `employee_absence_days` | source de vérité, soldes débités/restités | chaque table vit seule ; soldes non testés |
| **Pointage / temps** (`timesheets`) | `is_employee_absent(employee, date)` | ⛔ refus (TRV-03), HS ⛔ (TRV-04) | ne lit rien |
| **Projets / tâches** (`project_time_entries`, `project_tasks`) | idem + `assignee absence` | ⛔ temps (TRV-05), ⛔ assignation (TRV-07), ⛔ clôture par l'absent (TRV-08) | ne lit rien |
| **Notes de frais** (`expense_report_lines`, `expense_reports`) | `assert_can_claim_expense` | ⛔ sauf `mission` (TRV-06, TRV-10) | ne lit rien |
| **Paie** (`payroll_variable_elements`, `calculate_payslip`, `pay_slips`) | `employee_absence_days.pay_rule_code` | une retenue par jour, maintien/IJSS, régularisation | deux ponts, dont un désarmé (`affects_pay = false`) |
| **Facturation** (lignes de devis / facture) | absence du jour du temps | ⛔ temps non facturable (TRV-09) | ne lit rien |
| **Comptabilité** (provisions de congés) | `leave_balances` + absence | provision cohérente (compte 4282 / 153) | `leave_provisions` existe, aucune logique |
| **Production / planning** (`planning_slots`, `staff_requirements`) | absence du salarié | capacité et planning ajustés | `staff_requirements` existe, jamais confronté |
| **Reporting / tableaux de bord** | `check_absence_conflicts()` | anomalies visibles | rien |

### 3.6 Les exceptions : mission, astreinte, dérogation — et la régularisation

Une règle qui n'a pas d'échappatoire sera contournée par le premier cas légitime, puis désactivée.
Les échappatoires sont donc **dans le modèle**, pas dans un `WHERE` oublié :

1. **Mission** (`absence_kind = 'mission'`) : n'interdit ni le temps ni les frais ; la ligne de frais
   porte `mission_absence_id`, et le justificatif est exigé (TRV-10). C'est la réponse au cas
   « mon commercial est en déplacement trois jours ».
2. **Astreinte / intervention urgente** : dérogation **accordée à l'avance** par le manager, portée
   par `approval_workflows` (table existante) ; les fonctions `assert_*` acceptent un paramètre
   `p_override_workflow_id` qui **n'est honoré que si le workflow est validé** pour ce jour et ce
   salarié. Le temps concerné est marqué (`override_workflow_id` sur la ligne), donc auditable.
3. **Régularisation rétroactive** : délai paramétré (défaut 30 jours), **motif obligatoire**,
   journalisé ; l'écriture n'est jamais supprimée — elle est *corrigée avec trace* (même philosophie
   que le journal NF-525).
4. **Télétravail** : n'est **pas** une absence (`blocks_work = false`, `allows_expenses = false`,
   `paid = true`) — c'est une modalité de travail, et la confondre avec une absence était le
   contresens qu'il faut éviter dès la conception.

### 3.7 Ce qui doit rester possible — la garde anti-zèle

Un contrôle qui bloque le travail légitime sera désactivé, et avec lui le contrôle. Le plan engage
donc explicitement les points suivants, chacun couvert par un test (partie IV, `A9` à `A12`) :

| Ce qui doit rester possible | Pourquoi |
|---|---|
| La **paie d'un salarié absent** (maintien, IJSS, retenue) | l'absence change la paie, elle ne la supprime pas |
| La **saisie par un tiers** (RH, manager) d'un pointage, d'un frais ou d'un temps d'un absent, avec dérogation | l'absent ne doit pas être le seul à pouvoir corriger |
| La **correction d'une erreur** de saisie, toujours tracée, jamais silencieuse | sinon les utilisateurs désactiveront les déclencheurs |
| Les **salariés sans pointage** (forfait, cadres) | l'absence ne doit pas casser la paie de ceux qui ne pointent pas |
| Les **jours fériés et week-ends** (`public_holidays` existe) | une absence ne se cumule pas avec un férié : deux lignes pour un jour payé une fois |
| Le **multi-société** strict : un salarié absent dans A ne bloque rien dans B | l'isolation est déjà un principe (W1) |
| Les **dates de forte charge** (clôture, inventaire) : l'absence bloque la *saisie*, pas la *paie* | ne jamais bloquer le processus comptable |

---

## Partie IV — Tests logiques, scénarios et procédure de vérification ultime

### 4.1 Le harnais, tel qu'il existe — commandes exactes

Tout ce qui suit s'exécute dans le harnais **déjà en place** (aucune invention) :

```bash
# 1. Une base neuve (le nom du conteneur est celui utilisé par les audits : pg_m3_neuf)
docker run -d --name pg_m3_neuf -e POSTGRES_PASSWORD=postgres -p 5433:5432 postgres:16
export DATABASE_URL="postgresql://postgres:postgres@localhost:5433/postgres"
#    … ou : export PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres

cd app

# 2. Le socle Supabase simulé, puis l'instantané de schéma (exactement comme la CI)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/ci/00_supabase_stubs.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/00_schema_dump.sql

# 3. Les migrations — le lanceur du dépôt, qui tient le journal sql_migrations_tracker
node run-sql-migrations.mjs

# 4. Un scénario d'acceptation, un par un, à la main
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/266_absence_transverse_tests.sql
```

Trois faits du harnais qu'il faut connaître avant d'écrire un test :

1. **`*_tests.sql` n'est jamais une migration.** `run-sql-migrations.mjs` les exclut explicitement
   (`!/_tests\.sql$/`) et refuse les **numéros en doublon** entre migrations (`SOC-06`). Un fichier de
   test ne pollue donc pas l'historique de schéma, et le couple `240_<nom>.sql` +
   `240_<nom>_tests.sql` est bien la convention (précédent `229`).
2. **Un test doit être branché à la main** : `run-sql-migrations.mjs` ne l'exécute pas, et `ci.yml`
   liste les tests **un par un** — **46 suites `*_tests.sql` sur disque, 46 référencées** dans
   `ci.yml` (vérifié : `ls sql/*_tests.sql | wc -l` = 46, et les deux listes sont identiques). Le
   chiffre « 34 suites » cité par les audits du 21 et du 22/09 est **antérieur** aux lots 227→234 et
   240→244 : il ne faut plus s'y fier. C'est le branchement explicite qui a manqué de peu à
   AUD-X02 — et qui a été fait, sans être commité.
3. **Le harnais est une base seule** : les fonctions Edge se testent à côté (W6, trois étages), pas ici.

**Les briques disponibles** (`sql/ci/audit_helpers.sql`, déjà écrites et utilisées par 178→182 et
227→234) :

| Brique | Rôle |
|---|---|
| `_mk_tenant(nom)` | crée une société complète (tenant, utilisateur `auth.users`, `tenant_users`, `company_settings`, journaux, plan comptable, exercice 2026) **et vérifie que `current_tenant_id()` répond** — « le test ne prouverait rien » sinon |
| `_as_user()` | passe sous le rôle `authenticated` (donc **sous RLS**), comme PostgREST |
| `_entry(...)` | écrit une pièce + ses lignes, la valide si demandé |
| `_rec(id, libellé, ok, détail)` | enregistre un verdict **sans interrompre** le scénario |
| `_audit_assert('NNN')` | confronte les verdicts au registre `ci/expected_failures.sql` : un échec hors registre casse la CI ; un succès **dans** le registre casse aussi (il faut retirer la ligne) ; un fichier sans verdict casse (un test qui ne vérifie rien) |

### 4.2 La batterie par table (BT-01 → BT-11) et la grille qui la cible

« Vérifier chaque table » ne veut pas dire écrire 341 fois le même test : cela veut dire **passer la
même batterie sur chaque table**, puis traiter les exceptions. La grille ci-dessous **produit la liste
des tables à traiter** ; elle est mesurable et se rejoue après chaque vague.

```sql
-- Grille : pour chaque table métier (celle qui porte tenant_id), ses gardes réelles.
WITH t AS (
  SELECT c.oid, c.relname AS table_name, c.relrowsecurity, c.relforcerowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
    AND EXISTS (SELECT 1 FROM pg_attribute a
                WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                  AND a.attnum > 0 AND NOT a.attisdropped)
)
SELECT t.table_name,
       t.relrowsecurity                                  AS rls,
       t.relforcerowsecurity                             AS rls_forcee,
       (SELECT count(*) FROM pg_policy p WHERE p.polrelid = t.oid)            AS politiques,
       (SELECT count(DISTINCT p.polcmd) FROM pg_policy p WHERE p.polrelid = t.oid) AS commandes,
       (SELECT count(*) FROM pg_trigger g
         WHERE g.tgrelid = t.oid AND NOT g.tgisinternal)                      AS declencheurs,
       (SELECT count(*) FROM pg_constraint k
         WHERE k.conrelid = t.oid AND k.contype = 'f'
           AND k.confrelid = 'public.tenants'::regclass)                      AS fk_tenants
FROM t ORDER BY rls, commandes, declencheurs, table_name;
```

Lecture de la grille : `commandes = 4` signifie que les quatre verbes (SELECT, INSERT, UPDATE, DELETE)
sont couverts ; une table à 1 ou 2 est une table où une écriture passe sans garde. Repère
**MESURÉ** : sur le schéma du 15/09, **224 tables** portent au moins un déclencheur, et l'audit de
couverture compte **67 tables portant une logique SQL** — la grille est ce qui rend l'écart visible,
table par table, sans lire 9 000 lignes de SQL.

| # | Contrôle BT — appliqué à chaque table métier | Défauts couverts |
|---|---|---|
| **BT-01** | **Isolation en écriture** : une ligne de A ne peut pas référencer une ligne de B (FK composite ou politique par le parent), et un déclencheur `SECURITY DEFINER` ne peut pas écrire hors de la société du mouvement | ISO-01, ISO-02 |
| **BT-02** | **Isolation en lecture** : la table de B est invisible depuis A, en-tête `x-tenant-id` falsifié compris — **déjà couvert** par `105` (340 tables) : on ne réécrit pas, on ne régresse pas | N1 |
| **BT-03** | **Garde de société sur tout point d'entrée** : RPC exposée (227) **et** fonction de déclencheur (extension de W1) | ISO-01, PERM-01 |
| **BT-04** | **Immuabilité des pièces validées** : `UPDATE`/`DELETE` refusés sur ce qui est `posted` / `completed` / `paid` (écriture, bulletin, ticket, facture validée) | POS-01, POS-02, N2 |
| **BT-05** | **Suppression en cascade** : une pièce à valeur légale ne part pas avec son parent (bulletins, opérations bancaires, mouvements de stock) | SUP-01→03 |
| **BT-06** | **Idempotence** : rejouer la même action ne double rien (`source_id`, `reference`, `number`) — le contrôle qui manquait à S-07, RH-03, RH-10, EF-02 | Couverture §6.1 |
| **BT-07** | **Exercice et période** : rien ne s'écrit hors exercice ouvert ni hors période ouverte, y compris pour une pièce automatique | PROD-03, BUD-01, N2 |
| **BT-08** | **Numérotation** : pas de trou, pas de doublon, reprise après l'existant (écritures, pièces, bulletins, tickets) | POS-03 |
| **BT-09** | **Devise** : montant en devise de tenue, taux du document appliqué, écart de change écrit | M01-01→03 |
| **BT-10** | **Statut et annulation** : *chaque* valeur admise par la contrainte `CHECK` est traitée — surtout `cancelled` | Couverture §6.1 |
| **BT-11** | **Absence** : le jour d'absence bloque ce qui doit l'être (TRV-03 → TRV-09) | **W9** |

**Comment la grille devient un test d'acceptation** — procédure reproductible, à rejouer à chaque vague :

1. exécuter la grille. Toute table avec `rls = false`, `commandes < 4`, `declencheurs = 0` ou
   `fk_tenants = 0` est **suspecte** et entre dans la liste de travail ;
2. pour chaque suspecte, exécuter les BT applicables (BT-01 et BT-11 sont applicables à **toutes**) ;
3. un BT qui passe devient une **ligne de vérification** dans le fichier de test du module ; un BT qui
   échoue devient un **défaut au registre**, avec son identifiant ;
4. la grille est **rejouée après chaque vague** : le nombre de suspects doit **décroître**. C'est la
   mesure d'avancement honnête, en complément de la couverture de scénarios — elle, partielle par
   construction.

### 4.3 La carte des scénarios : quelle table est traversée, par quel test, avec quel cas

Chaque ligne = un fichier de test **exécutable**, avec les tables qu'il traverse et le cas qu'il
chiffre. `✅` = le fichier existe et tourne en CI ; `🧪` = spec **et** correctif écrits, mais
**exécution non consignée et rien de commité** (AUD-X02) ; `⬜` = à écrire.

| Module | Tables traversées par le scénario | Fichier | Cas chiffrés | État |
|---|---|---|---|---|
| Saisie comptable | `journal_entries`, `journal_lines`, `accounts`, `fiscal_years`, `fiscal_periods` | `178_accounting_kernel_tests.sql` | équilibre, exercice, période, compte imputable, numéro sans trou | ✅ |
| Clôture, états | `fiscal_years`, `carry_forward_log`, `balance_sheet`, `trial_balance` | `179_closing_and_statements_tests.sql` | clôture, reports, balance | ✅ |
| Ventes | `invoices`, `invoice_lines`, `payments`, `customers`, `journal_lines` | `180_sales_to_ledger_tests.sql` | facture → écriture → règlement | ✅ |
| Paie → grand livre | `pay_runs`, `pay_slips`, `payroll_variable_elements`, `journal_entries` | `181_payroll_to_ledger_tests.sql` | bulletin → écriture → paiement | ✅ |
| Inscription | `tenants`, `tenant_users`, `profiles`, `journals`, `accounts` | `182_signup_provisioning_tests.sql` | provisionnement complet d'une société | ✅ |
| Achats, trésorerie | `purchase_orders`, `purchase_invoices`, `supplier_payments`, `bank_transactions` | `192_purchases_treasury_tests.sql` | 3 voies, règlement fournisseur | ✅ |
| TVA autoliquidation | `journal_lines`, `tax_groups`, `vat_returns` | `197_vat_reverse_charge_tests.sql` | 7/7, comptes AUTOLIQ / UE | ✅ |
| Factures d'acompte | `invoices`, `advance_invoices`, `journal_lines` | `210_advance_invoices_tests.sql` | acompte puis solde | ✅ |
| Immobilisations | `assets`, `asset_depreciations`, `journal_lines` | `211_asset_deferred_tests.sql`, `226_asset_net_book_value_tests.sql` | dotation, VNC, prorata | ✅ |
| Paiement de la paie | `pay_runs`, `sepa_payment_orders`, `bank_transactions` | `212_payroll_payment_tests.sql` | versement, périmètre | ✅ |
| Avoirs | `credit_notes`, `journal_lines` | `213_credit_note_accounts_tests.sql` | comptes d'avoir | ✅ |
| Réception partielle | `purchase_orders`, `goods_receipts`, `goods_receipt_lines` | `214_purchase_receipt_order_tests.sql` | allocation par `line_order` | ✅ |
| Documents, numérotation | `document_sequences`, `journal_posting_sequences` | `216`, `217`, `218` | année, reprise après l'existant | ✅ |
| Caisse | `pos_tickets`, `pos_ticket_lines`, `journal_entries`, `stock_movements` | `219_pos_vat_cash_tests.sql` | TVA par taux, écart de caisse, sortie de stock | ✅ |
| Droits de paie | `pay_runs`, `payroll_*` | `220_payroll_permission_tests.sql` | `payroll.post`, `payroll.pay` | ✅ |
| API facture | `invoices`, `invoice_lines`, `api_keys` | `221_invoice_api_tests.sql` | idempotence `Idempotency-Key` | ✅ |
| Banque | `bank_transactions`, `bank_reconciliation_rules` | `222`, `223` | nature de ligne, état de rapprochement | ✅ |
| Lignes de commande | `purchase_order_lines` | `225_purchase_line_order_unique_tests.sql` | unicité | ✅ |
| Garde de société | **toute fonction exposée prenant un uuid** | `227_tenant_guard_tests.sql` | refus d'agir pour une autre société | ✅ |
| Droits des fonctions | `pg_proc` + `anon` | `228_function_grants_tests.sql` | un anonyme ne peut plus appeler 332 fonctions | ✅ |
| Production | `manufacturing_orders`, `stock_movements`, `journal_entries` | `229_manufacturing_order_tests.sql` | rebuts, coût unitaire, reclôture refusée | ✅ |
| Livraisons | `sales_orders`, `deliveries`, `stock_movements`, `stock_reservations` | `230_delivery_stock_out_tests.sql` | une seule sortie, réexpédition refusée | ✅ |
| Temps passés | `project_time_entries`, `projects`, `project_tasks` | `231_project_time_billing_tests.sql` | isolation, facturation (**M-17-01 rouge au registre**) | ✅ |
| Séparation des tâches | `journal_entries` | `232_segregation_tests.sql` | l'auteur ne valide pas lui-même | ✅ |
| Journal NF-525 | `pos_journal` / chaîne de hachage | `233_nf525_chain_tests.sql` | intégrité de la chaîne | ✅ |
| File de webhooks | `webhook_delivery_queue`, `webhook_delivery_logs` | `234_webhook_queue_tests.sql` | entrée, sortie, tentatives | ✅ |
| **Stock, société, upsert** | `stock_movements`, `stock_quantities`, `products` | **`240_stock_movement_tenant_and_upsert_tests.sql`** | T01→T04 (S-08, S-09) | 🧪 |
| **Réception → stock → compta** | `goods_receipts`, `goods_receipt_lines`, `stock_valuation_layers`, `journal_lines` | **`241_receipt_stock_and_ledger_tests.sql`** | T01→T07 (S-01→S-04, S-10, S-11) | 🧪 |
| **Livraison, dépôt, réservations** | `deliveries`, `stock_movements`, `stock_quantities`, `stock_reservations` | **`242_delivery_warehouse_and_reservation_tests.sql`** | T01→T05 (S-05→S-07) | 🧪 |
| **Nom du salarié, moteurs de paie** | `employees`, `timesheets`, `payroll_variable_elements` | **`243_payroll_and_employee_name_tests.sql`** | T01→T05 (RH-01→RH-04) | 🧪 |
| **Historique conservé** | `employees`, `pay_slips`, `bank_accounts`, `bank_transactions`, `products`, `stock_movements` | **`244_preserve_history_delete_guards_tests.sql`** | T01→T07 (SUP-01→SUP-03) | 🧪 |
| Caisse — immuabilité | `pos_tickets`, `pos_ticket_lines` | `245_pos_immutability_tests.sql` | 120 € → 12 € refusé, hachage recalculé, numéro unique | ⬜ |
| Annulations | `deliveries`, `goods_receipts`, `quality_checks` | `246_cancel_paths_tests.sql` | 4 chemins d'annulation | ⬜ |
| Paie — bornes et montants | `leave_requests`, `expense_reports`, `meal_voucher_*`, `payroll_variable_elements` | `249`, `250`, `251` | `-31`, `total_amount`, congé à cheval, doublons | ⬜ |
| Amortissement unique | `assets`, `asset_depreciations` | `252_single_depreciation_engine_tests.sql` | 2 exercices, méthode, échec visible | ⬜ |
| Fonctions Edge | `collection_reminders`, `bank_transactions`, `electronic_signatures`, `webhook_delivery_logs` | `253`, `254`, `255` | colonnes réelles, erreurs lues, relance unique, 401 sans jeton | ⬜ |
| Devises, analytique, budgets | `journal_lines`, `currency_revaluations`, `analytic_sections`, `budgets`, `budget_commitments` | `256`, `257`, `258` | taux appliqué, section propagée, réalisé borné à l'exercice | ⬜ |
| Import, FEC, tableaux de bord | `import_batches`, `journal_entries`, `chart_pack_switch_log` | `259`, `260` | équilibre, cumul des soldes, 18 colonnes | ⬜ |
| Production multi-niveaux | `bom_lines`, `manufacturing_orders`, `journal_lines` | `261_production_cancel_and_bom_levels_tests.sql` | nomenclature profonde, cycle refusé, date d'OF | ⬜ |
| Projets | `project_tasks`, `quotes`, `quote_lines`, `project_time_entries` | `262_project_billing_and_cycles_tests.sql` | refacturation réelle, anti-cycle, avancement pondéré | ⬜ |
| **Absence (transverse)** | **`employee_absence_days`** + 8 tables en aval | **`263`, `264`, `265`, `266_absence_transverse_tests.sql`** | **A1 → A12 puis A13 → A34** (voir 4.5) | ⬜ |
| Droits | `invoices`, `customers`, `journal_entries`, `pay_runs` + `pg_policies` | `239_roles_opposables_tests.sql` | un `viewer` ne crée plus rien | ⬜ |
| Politiques en double | `pg_policies` | `238_policy_dedup_tests.sql` | 0 doublon, 38 gardes vivantes | ⬜ |
| Clés composites | `pg_constraint` + tables d'argent | `237_composite_foreign_keys_tests.sql` | facture de A → client de B : refusée | ⬜ |

### 4.4 Les tests de non-régression (N1 → N12) : ce qu'il est interdit de casser

Ces douze points ne demandent **aucun nouveau code** : ils rejouent l'existant après chaque vague.
Ils sont la garantie qu'un correctif n'en défait pas un autre — et c'est la première chose que
l'audit du 24/09 a montrée manquante (le « 100 % » de la production, obtenu en regardant une seule
table).

| # | Commande de vérification | Attendu |
|---|---|---|
| N1 | `psql -f sql/105_rls_tests.sql` | 340 tables isolées en lecture |
| N2 | `psql -f sql/178_accounting_kernel_tests.sql` | noyau comptable vert |
| N3 | `psql -f sql/211_asset_deferred_tests.sql` + `226` | amortissement vert |
| N4 | `npm run db:embeds` | les 1 495 lectures passent un PostgREST réel |
| N5 | `psql -f sql/219_pos_vat_cash_tests.sql` | caisse verte |
| N6 | Test de refus de simulation `transmit-dsn` / `submit-vat-return` | « Aucune donnée n'a été transmise » |
| N7 | Export FEC de l'écran | 18 colonnes, tri par numéro définitif |
| N8 | Scénario `M18` `P3` | `Cannot change own role` |
| N9 | `psql -f sql/230_delivery_stock_out_tests.sql` | une seule sortie par BL |
| N10 | `psql -f sql/228_function_grants_tests.sql` | `fec_export` non accordée à `authenticated` |
| N11 | `psql -f sql/229_manufacturing_order_tests.sql` | idempotence de l'OF |
| N12 | `psql -f sql/227…234_*_tests.sql` | les huit suites récentes restent vertes |

### 4.5 Le scénario transverse « une journée d'absence » — 34 assertions (A01 → A34)

C'est le test que réclame la question initiale : *une absence déclarée quelque part est-elle reprise
partout, et rend-elle impossibles les frais, les heures supplémentaires et le temps de cet employé ce
jour-là ?* Le fichier s'appelle `266_absence_transverse_tests.sql` et suit la forme du dépôt.

**Fixture** (une société, deux salariés, un projet, une tâche, un mois de paie) :

```sql
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '266', false);
DELETE FROM _audit_results WHERE file = '266';

CREATE OR REPLACE FUNCTION _mk_absence_fixture(p_nom text,
  OUT t uuid, OUT e1 uuid, OUT e2 uuid, OUT p uuid, OUT task uuid, OUT run uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);                        -- société + exercice 2026 + plan comptable
  INSERT INTO employees (tenant_id, name, status, salary, weekly_hours)
  VALUES (t, 'Amina Waberi ' || p_nom, 'active', 3600, 35) RETURNING id INTO e1;   -- e1 pointe
  INSERT INTO employees (tenant_id, name, status, salary)
  VALUES (t, 'Forfait Jour ' || p_nom, 'active', 4200) RETURNING id INTO e2;       -- e2 ne pointe pas
  INSERT INTO projects (tenant_id, name, status) VALUES (t, 'Projet ' || p_nom, 'active')
  RETURNING id INTO p;
  INSERT INTO project_tasks (tenant_id, project_id, title, status, assignee_id)
  VALUES (t, p, 'Tâche ' || p_nom, 'todo', e1) RETURNING id INTO task;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-' || p_nom, '2026-03-01', '2026-03-31', '2026-03-31', 'draft')
  RETURNING id INTO run;
  -- jours travaillés : 2026-03-10 (mardi) et 2026-03-11 (mercredi) ; congé : 10 → 12
END $$;
```

**A01 → A12 — le registre d'absence (263)** : on prouve d'abord qu'une seule vérité existe.

| # | Entrée | Attendu exact | Ce qui se passe aujourd'hui |
|---|---|---|---|
| **A01** | congé annuel approuvé du 10/03 au 12/03 | **3** lignes `employee_absence_days` (`10`, `11`, `12`), `absence_kind='annual'`, `blocks_work=true`, `allows_expenses=false`, `origin='leave_request'` | 0 ligne : la table n'existe pas |
| **A02** | un arrêt maladie du 11/03 au 11/03 saisi **aussi** | 1 ligne le 11, `absence_kind='sick'` (priorité), et **1** ligne dans `absence_conflict_log` | aucun conflit détecté |
| **A03** | rejouer la même approbation | toujours **3** lignes (idempotence du `rebuild`) | n/a |
| **A04** | congé **annulé** (`status='cancelled'`) | **0** ligne le 10 et le 12 ; le 11 reste `sick` ; solde de congés **restitué** (`leave_balances`) | rien n'est retiré |
| **A05** | congé **sans solde** du 10 au 12 | 3 lignes `absence_kind='unpaid'`, `paid=false` | 0 ligne |
| **A06** | `timesheets.absence_type='mission'` le 09/03 | 1 ligne `mission`, `blocks_work=false`, `allows_expenses=true` | couleur inexistante en base |
| **A07** | `work_stoppages` du 13/03 | 1 ligne `stoppage` | 0 ligne (table morte) |
| **A08** | `sick_leaves` du 16/03 (`sickness`) | 1 ligne `sick`, `justification_state='provided'` si `medical_certificate_url` | 0 ligne |
| **A09** | absence **non justifiée** (règle `requires_justification=true`, aucun justificatif, délai dépassé) | `justification_state='missing'` puis `absence_kind='unjustified'` après le délai | aucune notion |
| **A10** | deux sociétés A et B, même salarié impossible | le registre de A ne contient **que** les jours de A | n/a |
| **A11** | `is_employee_absent(e1, '2026-03-10')` | `true` ; sur le 09/03 : `false` | fonction inexistante |
| **A12** | `assert_not_absent(e1, '2026-03-10', 'test')` | **lève**, message contenant `annual`, la date, et `test` | n/a |

**A13 → A24 — les gardes en aval** : c'est le cœur de la question posée.

| # | Entrée | Attendu exact (message compris) | Aujourd'hui (MESURÉ) |
|---|---|---|---|
| **A13** | **pointage** de 8 h par `e1` le 10/03 (jour de congé) | **refus** : `Absence 'annual' le 2026-03-10 : pointage refusé (timesheets).` ; `count(timesheets) = 0` | **accepté** (rien ne lit l'absence) |
| **A14** | pointage de 8 h par `e1` le 09/03 (jour normal) | accepté (non-régression du légitime) | accepté |
| **A15** | pointage le 10/03 avec `absence_type='mission'` **et** dérogation validée | accepté, et la ligne porte `override_workflow_id` | n/a |
| **A16** | **heures supplémentaires** : pointage de 12 h par `e1` le 10/03 | **refus** (A13 s'applique) ; aucun élément `overtime` créé dans `payroll_variable_elements` | accepté, HS calculées **sans regarder `absence_type`** |
| **A17** | pointage de 9 h par `e1` le 09/03 (jour normal, > seuil paramétré) | **1 h** supplémentaire, montant > 0, **une seule** ligne `overtime` | 3 calculs concurrents, montant 0 |
| **A18** | **temps projet** de 2 h par `e1` sur `task` le 10/03 | **refus** : `Absence 'annual' le 2026-03-10 : temps projet refusé (project_time_entries).` | **accepté** |
| **A19** | temps projet le 09/03 | accepté | accepté |
| **A20** | **ligne de note de frais** datée du 10/03 pour `e1` (repas 25 €) | **refus** à l'insertion : `… : frais refusés (expense_report_lines).` | **accepté** : `expense_report_lines.date` n'est jamais confrontée |
| **A21** | note de frais **déjà soumise** avant la déclaration de congé, puis **approuvée** après | refus à l'**approbation** (double contrôle, TRV-06) + aucun élément `expense_reimbursement` en paie | approuvée, **montant nul** en paie (RH-07) |
| **A22** | frais de **mission** (25 €) le 09/03, absence `mission` | accepté, `mission_absence_id` renseigné | n/a |
| **A23** | **assignation** d'une nouvelle tâche à `e1` pendant son absence | **refus** (TRV-07) ; `e1` peut **clore** une tâche **par l'entremise d'un tiers** (journalisé) | accepté |
| **A24** | temps de `e1` facturable généré le 10/03 | **0** ligne facturable ; **le temps d'un absent ne part jamais en facture client** | aucun filtre |

**A25 → A34 — la paie, les exceptions et les cas limites** (c'est ici qu'on évite le remède pire que
le mal) :

| # | Entrée | Attendu exact | Aujourd'hui (MESURÉ) |
|---|---|---|---|
| **A25** | **paie du mois** de `e1` avec un congé **sans solde** de 3 jours | **1** élément `unpaid_absence_deduction` de **3 jours**, montant = `salaire / diviseur mensuel × 3` — **une seule ligne**, un seul diviseur (celui du paramétrage) | deux chemins de retenue existent ; le pont des congés est mort (`affects_pay=false`), celui des pointages attend une colonne jamais écrite |
| **A26** | `affects_pay` passé à `true` pour « unpaid » (réparation naïve) | **toujours une seule retenue** : la réparation ne doit pas créer la double retenue (TRV-11) | **double retenue** si on répare l'un sans unifier |
| **A27** | congé **annulé après** intégration en paie non validée | l'élément est **supprimé** ; `pay_runs` recalculé = même montant qu'avant le congé | rien ne revient en arrière |
| **A28** | congé **annulé après** bulletin **validé** | un **élément inverse** est créé ; le bulletin validé n'est **jamais** modifié (`BT-04`) | n/a |
| **A29** | absence **rétroactive** sur une période de paie **close** | **refus** explicite (« période close »), ou régularisation sur la période courante — la décision est paramétrée, pas implicite | rien |
| **A30** | **salarié sans pointage** (`e2`, forfait jour), aucune absence | sa paie est **inchangée** ; aucune exception « pointage manquant » | n/a |
| **A31** | absence tombant un **dimanche** et un **jour férié** (`public_holidays`) | la retenue ne compte **pas** le férié ; le solde de congés ne se décompte pas dessus | non traité |
| **A32** | consommation du **solde de congés** : approbation puis annulation | `leave_balances` : **−3** puis **+3** ; `leave_provisions` cohérente | `leave_balances` traversée par **aucun** scénario |
| **A33** | **contrôle d'intégrité** : insertion directe *hors garde* (service_role) d'un pointage un jour d'absence | `check_absence_conflicts()` retourne **1** anomalie, avec salarié, jour, module et type | aucun filet |
| **A34** | **isolation** : `e1` absent dans A ; une société B du même nom reste libre | le registre et les gardes de A ne portent **que** sur A | n/a |

**Forme des assertions** (le motif exact du dépôt — verdict enregistré, jamais d'arrêt au premier
échec) :

```sql
-- A13 — un jour de congé refuse le pointage
DO $$
DECLARE t uuid; e1 uuid; e2 uuid; p uuid; tk uuid; run uuid; ok boolean := false; err text := '—'; n int;
BEGIN
  SELECT * INTO t, e1, e2, p, tk, run FROM _mk_absence_fixture('A13');   -- via un wrapper OUT
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e1, 'annual', '2026-03-10', '2026-03-12', 3, 'pending') ;
  UPDATE leave_requests SET status = 'approved' WHERE employee_id = e1;   -- déclenche le registre

  PERFORM _as_user();
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e1, '2026-03-10', 8, 'pending');
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO n FROM timesheets WHERE employee_id = e1 AND date = '2026-03-10';
  PERFORM _rec('A13', 'pointage d''un jour de congé annuel : refusé avec message',
    ok AND n = 0 AND err LIKE '%annual%' AND err LIKE '%2026-03-10%',
    format('refusé=%s pointages=%s | %s', ok, n, left(err, 120)));
END $$;

-- Fin de fichier, toujours
SELECT _audit_assert('266');
```

**Ce que le scénario interdit de faire pour « réussir »** : désactiver les déclencheurs, contourner
par `service_role`, ou saisir l'absence *après* la frais — les cas A21 (double contrôle soumission +
approbation), A33 (contrôle quotidien) et A34 (isolation) existent précisément pour ça.

### 4.6 Les neuf autres scénarios transverses à écrire (T1 → T9)

L'absence est le chaînage transverse le plus visible, pas le seul. Les suivants traversent 4 à 7
modules chacun et **aucun** n'existe aujourd'hui : c'est là que se cachent les défauts que la
ventilation par module rend invisibles (principe de §1.1).

| # | Chaîne traversée | Modules | L'assertion finale (le chiffre qui doit tomber juste) |
|---|---|---|---|
| **T1** | Achat complet : commande → réception → contrôle qualité → stock dépôt → CUMP → écriture → facture fournisseur → règlement → TVA | Achats, Stock, Compta, Trésorerie | après 100 reçus à 10 + 50 à 12 : `stock_quantities = 150`, CUMP `10,67`, couches = 150, et **l'écriture de stock égale la somme des couches** |
| **T2** | Vente complète : devis → commande → réservation → livraison partielle ×2 → facture → règlement → lettrage | Commercial, Stock, Compta, Trésorerie | après 2 livraisons (60 puis 40) : stock 0, réservations 0, **2 factures dont 1 solde**, lettrage sans écart |
| **T3** | Coût de revient projet : temps saisi → coût horaire → refacturation → facture → marge | Projets, RH, Compta | `facturé − coût interne = marge`, et le temps non facturable n'apparaît **pas** en CA |
| **T4** | Fabrication : OF multi-niveaux → consommation → rebuts → entrée PF → écriture → marge par OF | Production, Stock, Compta | `coût PF = Σ composants × coefficient`, rebuts **hors** valeur du stock, une seule écriture par OF |
| **T5** | Cycle social : embauche → contrats → absence → pointage → éléments variables → bulletin → écriture → virement → DSN | RH, Paie, Compta, Trésorerie | `net à payer = brut − cotisations − PAS`, le virement **égale** le net, la DSN porte le même brut |
| **T6** | Caisse : ouverture → tickets → clôture → écart → TVA par taux → sortie de stock → écriture → journal NF-525 | Caisse, Stock, Compta | recette TTC = Σ tickets, TVA ventilée, écart de caisse écrit, chaîne de hachage intègre |
| **T7** | Banque : import relevé → suggestion → pointage → lettrage → état de rapprochement → écriture | Trésorerie, Compta | `solde relevé = solde comptable + en-cours`, zéro ligne non pointée à la clôture |
| **T8** | Clôture : écritures → à-nouveaux → budget N+1 → états financiers → FEC → contrôle DGFiP | Compta, Budgets, Reporting | bilan équilibré, **FEC accepté** par l'outil de la DGFiP, réalisé budgétaire = mouvements de l'exercice |
| **T9** | Devise de bout en bout : devis USD → facture USD → règlement USD → écart de change → réévaluation | Commercial, Compta, Trésorerie | écriture **en devise de tenue** au taux du jour, écart 666/766 écrit, réévaluation de clôture justifiée |

**Ce que ces neuf scénarios partagent** : ils ne se contentent pas de vérifier qu'une fonction
s'exécute — ils **additionnent des chiffres** à travers les modules et exigent que les totaux se
rejoignent. C'est la seule forme de test qui aurait vu S-01→S-07 (un stock par dépôt jamais alimenté
alors que le total bougeait) sans avoir à lire le code.

### 4.7 La contre-épreuve : un test qui n'a jamais été vu **rouge** ne prouve rien

C'est la leçon explicite de la couverture du 24/09 (§7) : *« Le contrôle a d'abord été faussement
vert, et son auto-test aussi »* — un `(.*?);` gourmand avalait la fonction entière, et la fixture
d'auto-test plaçait l'écriture fautive **en première** position. Corrigé par une classe de caractères
`[^;]*` et une fixture où l'écriture fautive venait **en dernier**.

**Protocole obligatoire pour chaque correctif** (à consigner dans l'en-tête du fichier de test) :

1. **rouge d'abord** : exécuter le test sur la base **à la migration précédente** — il doit être rouge,
   pour la **raison** attendue (pas pour une erreur de syntaxe). Les specs 240-244 portent déjà cette
   phrase : « Mesuré sur base neuve à la 234, AVANT la 240 : T01/T02 ROUGES » ;
2. **vert après** : appliquer la migration, rejouer, vert ;
3. **contre-épreuve par réintroduction** : réinstaller la **version fautive** de la fonction (le corps
   d'avant, dans la même session), rejouer le test, exiger rouge ; rétablir l'original, exiger vert.
   C'est exactement la méthode employée pour `release_stock_on_delivery` (230) ;
4. **contre-épreuve de position** : si le contrôle est un contrôle *de texte* (scanners, `check_*`),
   la fixture doit placer l'écriture fautive **en dernière** position — sinon un quantificateur
   gourmand rend le contrôle faussement vert ;
5. **contre-épreuve d'isolation** : le test est rejoué **sous `authenticated`** (`_as_user()`), jamais
   seulement en superutilisateur. Un test qui passe seulement en `postgres` ne prouve pas le
   comportement de production (c'est la différence entre H02 et ISO-02).

### 4.8 La procédure de vérification ultime — le runbook

À exécuter **en entier** avant toute mise en production d'une vague, et à la fin du plan. Huit
étapes, dans cet ordre, avec le critère d'échec de chacune.

> **Étape 0, à faire avant tout le reste (AUD-X02)** : rejouer les cinq suites **240 à 244** dans
> l'arbre de travail, puisque les correctifs et le câblage CI y sont déjà écrits mais non éprouvés.
> Trois issues possibles, chacune appelant un geste différent :
> - **vert** → commiter correctif + spec + étape CI dans cinq commits, et retirer du registre ce qui
>   y était (rien, aujourd'hui) ;
> - **rouge hors registre** → c'est un défaut nouveau : inscription au registre avec le couple
>   `(file, test_id)`, donc **après** AUD-X01 (235) ;
> - **rouge pour une autre raison** (erreur SQL, fixture) → corriger le test lui-même : un test qui
>   tombe pour une erreur de syntaxe ne prouve rien.

| # | Étape | Commande | Échec si… |
|---|---|---|---|
| 1 | **Base neuve** | `docker run … postgres:16` puis `psql -f sql/ci/00_supabase_stubs.sql`, `psql -f sql/00_schema_dump.sql` | une erreur quelconque |
| 2 | **Toutes les migrations** | `node run-sql-migrations.mjs` | une migration échoue, ou deux numéros sont en doublon |
| 3 | **PL/pgSQL valide** | `psql -f sql/ci/check_plpgsql.sql` | une fonction ne compile pas |
| 4 | **Contrôles statiques** | `check_tenant_guard`, `check_trigger_reachability`, `check_status_writes`, `check_anon_grants`, **`check_policy_duplicates`** (nouveau) | un contrôle rouge |
| 5 | **Contrôles de code** | `npm run db:embeds`, **`db:written-columns`** (nouveau), **`audit:unchecked-writes`** (nouveau) | un finding hors baseline |
| 6 | **Toutes les suites SQL** | les **46** suites `*_tests.sql` (toutes branchées), une par une, `-v ON_ERROR_STOP=1` | un échec hors `ci/expected_failures.sql`, ou un succès **dans** le registre |
| 7 | **La grille BT** (§4.2) | la requête de grille, rejouée | le nombre de tables suspectes **augmente** par rapport à la vague précédente |
| 8 | **Front** | `npm run test:full` (`oxlint` + `tsc` + `vitest --coverage` + `playwright`) | un test rouge, un type, un lint |

**Critères de sortie globaux** — ce que « terminé » veut dire, en chiffres :

| Indicateur | Aujourd'hui (MESURÉ) | Cible | Où on le lit |
|---|---:|---:|---|
| Défauts bloquants ouverts | **32** | **0** | §1.2 |
| Défauts graves ouverts | 32 | ≤ 5 (les 5 mineurs peuvent rester) | §1.2 |
| Modules phase 3 jamais audités | **16 / 20** | **0** | §1.4 |
| Couverture de la logique SQL | **64 %** | **≥ 90 %** | §1.3 |
| Tables atteintes par un scénario | 80 / 341 (**23 %**) | ≥ 200 / 341 | §1.3 |
| Fonctions Edge sans test | **20 / 20** | **0** | §1.4 |
| Contrôles CI qui attrapent les colonnes fantômes | 0 | 1 (baseline vide) | W0 |
| Chaînage absence | **inexistant** | 16 contrôles + 34 assertions vertes | W9 |
| Tables suspectes de la grille BT | à mesurer au 1ᵉʳ passage | décroissant à chaque vague | §4.2 |

---

## Partie V — Ordre, charge, dépendances et tableau de bord

### 5.1 Les vagues, dans l'ordre du danger et des dépendances

| Vague | Contenu | Défauts | Charge PROPOSÉE | Dépend de | Bloque |
|---|---|---:|---:|---|---|
| **W0** | CI capable de prouver (AUD-X01, AUD-X02) | 2 (outillage) | 1 j | — | toutes |
| **W1** | Isolation et droits | **5** (3 🔴) | 3 j | W0 | W9 |
| **W2** | Inaltérabilité et pièces à conserver | **7** (4 🔴) | 2,5 j | W0 | — |
| **W3** | Chaîne stock / achats / ventes / compta | **13** (7 🔴) | 4 j | W0 | T1, T2 |
| **W4** | Paie et RH | **10** (4 🔴) | 4 j | W0, W1 | W9, T5 |
| **W5** | Un seul moteur par grandeur | 8 (1 🔴) | 2 j | W4 | — |
| **W6** | Fonctions Edge et écrans placebos | **9** (5 🔴) | 3,5 j | W0 | T7, T9 |
| **W7** | Comptabilité avancée | 15 (4 🔴) | 6 j | W3 | T8, T9 |
| **W8** | Production et projets | 6 (1 🔴) | 3 j | W3 | T3, T4 |
| **W9** | **Chaînage absence** (16 contrôles, 34 assertions) | **nouveau** | 4 j | W1, W4 | T5 |
| — | **Les 9 scénarios transverses T1→T9** | — | 5 j | W3…W9 | — |
| | **Total** | **69 + 2 + 16** | **≈ 38 j** | | |

**Chemin critique** : W0 → W1 → W4 → W9. C'est aussi le chemin de la paie : toute la valeur du
chaînage social passe par la paie, et l'audit du 23/09 y a trouvé 4 défauts bloquants.
**Parallélisable sans risque** : W2, W3 et W6 touchent des tables disjointes de W1 ; en revanche
W3 et W7 se croisent sur `journal_lines` (comptes de stock, devise) — à sérialiser sur ce point.
**Parallélisable avec précaution** : W5 et W8 touchent les deux mêmes écrans que W6 (placebos) — un
seul rédacteur par fichier.

> **Estimation honnête, reprise de l'enseignement du 24/09** : chiffrer « 0,5 j par module » était
> optimiste — trois modules audités ont pris une session complète, correctifs compris. Les 38 jours
> ci-dessus sont une estimation de *développement*, hors recette, hors déploiement, et hors les
> défauts que l'audit des 16 modules restants révélera (l'audit en estime une trentaine à taux
> constant, dont plusieurs bloquants).

### 5.2 Definition of Done — pour **un** défaut, sans exception

Un défaut est fermé quand **les six** conditions sont réunies :

1. **un test chiffré existe**, qui échoue **avant** le correctif pour la bonne raison (protocole §4.7) ;
2. **le correctif** est une migration numérotée `NNN_<nom>.sql`, rejouable, sans `DROP` de données ;
3. **le test est branché** dans `.github/workflows/ci.yml`, dans le **même commit** ;
4. la ligne correspondante du **registre** `ci/expected_failures.sql` est **retirée** si le défaut y
   figurait (sinon la CI échoue — c'est prévu) ;
5. les **tests de non-régression** de la liste blanche (§4.4) restent verts — au minimum `105`, `178`,
   `181`, `219` et les suites du module touché ;
6. **le chiffre du tableau de bord** (§5.3) est mis à jour, avec la date.

### 5.3 Tableau de bord de suivi

À cocher au fur et à mesure ; chaque case porte la migration et le test qui la justifient.

| Vague | Étape | Migrations | Tests | État |
|---|---|---|---|---|
| **W0** | Registre par fichier (AUD-X01) | — (pas de migration : `ci/audit_helpers.sql`) | `ci/audit_registry_selftest.sql` (Z1→Z4b) | ✅ **fait le 24/09** — commit `7e25a7f`, contre-épreuve Z1/Z4b rouges avec l'ancienne clé |
| **W0** | Scanners en CI (colonnes écrites, erreurs non lues) | — | baselines gelées : 20 et 29 | ✅ **fait le 24/09** — commit `1ade873` |
| **W0** | Contrôle des politiques en double | — | `ci/check_policy_duplicates.sql` + auto-test | ✅ **fait le 24/09** — commit `1ade873` ; registre vidé par la 238 (506 politiques retirées) |
| **W0** | Specs 240-244 commitées et inscrites au registre | 240→244 (commit `062eef7`) | 240→244 | ✅ **fait le 24/09** — les cinq suites **vertes** sur base neuve ; rien à inscrire au registre |
| **W1** | `tenant_id` dans les 13 triggers + contrôle étendu | 236 | 236 | ✅ **fait le 24/09** — 18 fonctions relevées et filtrées, suite 17/17 (commit `c116e53`) |
| **W1** | Clés composites `(tenant_id, …)` | 237 (+249) | 237 (8 scénarios) | ✅ **fait le 24/09** — 408 clés converties, 2 nées après la 237 (249), 0 mono-colonne, `ci/check_composite_fks.sql` |
| **W1** | Dédoublonnage 326 politiques / 11 index | 238 | 238 (8 scénarios) | ✅ **fait le 24/09** — 495 couples dédoublonnés (506 politiques, 12 index), 57 gardes rendues opposables |
| **W1** | Rôles opposables | 239 | 239 (9 scénarios) | ✅ **fait le 24/09** — décision `D-6` tranchée : 41 tables sensibles (123 politiques), `ci/check_roles_opposables.sql`, 257 tables restantes publiées |
| **W2** | Gardes de suppression (SUP-01→03) | 244 | 244 ✅ | 🟡 correctif écrit, **à rejouer + commiter** |
| **W2** | Immuabilité NF-525 (POS-01→04) | 245 | 245 | ⬜ |
| **W3** | Stock société + upsert (S-08, S-09) | 240 | 240 ✅ | 🟡 correctif écrit, **à rejouer + commiter** |
| **W3** | Réception → stock → compta (S-01→04, S-10, S-11) | 241 | 241 ✅ | 🟡 correctif écrit, **à rejouer + commiter** |
| **W3** | Livraison, dépôt, réservations (S-05→07) | 242 | 242 ✅ | 🟡 correctif écrit, **à rejouer + commiter** |
| **W3** | Chemins d'annulation + quantité contrôlée (S-12, S-13) | 246 | 246 | ⬜ |
| **W4** | Nom du salarié, moteurs de paie (RH-01→04) | 243 | 243 ✅ | 🟡 correctif écrit, **à rejouer + commiter** |
| **W4** | Bornes de période, montants, congés à cheval (RH-06→10) | 249, 250 | 249, 250 | ⬜ |
| **W4** | Notes de frais → grand livre (RH-07, RH-08) | 251 | 251 | ⬜ |
| **W4** | Un seul diviseur mensuel (RH-05) | 249 | 249 | ⬜ |
| **W5** | Un seul moteur d'amortissement (IMMO-01→05) | 252 | 252 | ⬜ |
| **W6** | Colonnes fantômes + erreurs lues (EF-04, 05, 07, 08) | 253 | 253 | ⬜ |
| **W6** | Relances de paiement (EF-01, EF-02) | 254 | 254 | ⬜ |
| **W6** | Placebos branchés ou retirés (EF-03, 06, TVA-01) | 255 | 255 | ⬜ |
| **W7** | Multi-devises (M01-01→03) | 256 | 256 | ⬜ |
| **W7** | Analytique (ANA-01→03) | 257 | 257 | ⬜ |
| **W7** | Budgets (BUD-01→04) | 258 | 258 | ⬜ |
| **W7** | Import Sage + FEC unique (SAGE-01→03, FEC-01) | 259, 260 | 259, 260 | ⬜ |
| **W8** | Production multi-niveaux et écarts (PROD-01→03) | 261 | 261 | ⬜ |
| **W8** | Refacturation et cycles projets (PROJ-01→03, M-17-01) | 262 | 262 | ⬜ |
| **W9** | Registre d'absence (TRV-01, TRV-02, TRV-14, TRV-15) | 263 | 263 | ⬜ |
| **W9** | Gardes en aval (TRV-03→TRV-10) | 264 | 264 | ⬜ |
| **W9** | Paie, annulations, régularisation (TRV-11→TRV-13) | 265 | 265 | ⬜ |
| **W9** | 34 assertions transverses + contrôle quotidien (TRV-16) | — | 266 | ⬜ |
| — | Scénarios transverses T1→T9 | — | — | ⬜ |

### 5.4 Les seize premiers commits, dans l'ordre (PROPOSÉ)

Parce qu'un plan de 38 jours ne commence pas par « tout », voici la séquence exacte. Chaque commit est
**autonome** : il laisse le dépôt dans un état meilleur **et vérifié**.

> **Avant le commit 1, il y a un « commit 0 » qui n'est pas du code** : rejouer les suites 240→244
> (déjà écrites, non éprouvées), consigner le verdict, puis commiter les cinq correctifs avec leurs
> tests et leur câblage CI. Les commits **7 à 11** ci-dessous ne sont donc plus des développements :
> ce sont des **vérifications et des mises en historique** de ce qui existe déjà dans l'arbre de
> travail.

| # | Commit | Contenu | Preuve apportée |
|---:|---|---|---|
| 1 | `fix(ci): le registre des échecs attendus porte le fichier (AUD-X01, 235)` | clé `(file, test_id)`, `expected_failures.sql` à trois colonnes | `_audit_assert` correct sur deux fichiers homonymes |
| 2 | `chore(ci): brancher le scanner des colonnes écrites et celui des erreurs non lues` | 2 scripts, 2 baselines, 2 étapes CI | 21 et 29 findings **gelés**, pas cachés |
| 3 | `chore(ci): le contrôle refuse deux politiques permissives jumelles` | `ci/check_policy_duplicates.sql` | ISO-03 ne peut plus revenir |
| 4 | `test(audit): les cinq specs de la phase 3 entrent au registre (240-244)` | `git add` + inscription des `T0x` | CI verte, défauts **visibles** |
| 5 | `fix(sécurité): un déclencheur ne peut plus écrire chez le voisin (ISO-01, 236)` | 13 fonctions + `check_tenant_guard` étendu | scénario `ISO` vert, `Y3` inchangé |
| 6 | `fix(sécurité): les gardes de droits ne sont plus annulées par leur jumelle (ISO-03, 238)` | 326 politiques retirées, 11 index | 38 gardes **vivantes** |
| 7 | `fix(db): l'historique de paie et de banque ne s'efface plus d'un clic (SUP-01/02/03, 244)` | **écrit** : 3 clés étrangères en `RESTRICT` | **spec 244 verte** — rejouer puis commiter |
| 8 | `fix(stock): le mouvement porte sa société et additionne ses quantités (S-08, S-09, 240)` | **écrit** : `increment_stock`, `decrement_stock` | **spec 240 verte** — rejouer puis commiter |
| 9 | `fix(achats): une réception entre en stock, à son coût, et le dit en comptabilité (S-01→04, 241)` | **écrit** : `warehouse_id`, prix de ligne, comptes résolus | **spec 241 verte** — la chaîne achat existe enfin |
| 10 | `fix(ventes): la livraison sort du bon dépôt et libère sa réservation (S-05→07, 242)` | **écrit** : 2 déclencheurs | **spec 242 verte** |
| 11 | `fix(rh): le nom du salarié s'affiche, un seul moteur de paie (RH-01→04, 243)` | **écrit** : découpe du nom, `DROP` du moteur fictif, idempotence | **spec 243 verte** |
| 12 | `fix(paie): l'import des éléments variables cesse d'échouer cinq mois sur douze (RH-06, 249)` | bornes de période calculées | `22008` impossible |
| 13 | `fix(paie): une note de frais entre pour son montant, avec sa TVA (RH-07, RH-08, 251)` | `total_amount`, écriture 625x / 44566 / 421 | note de frais comptabilisée |
| 14 | `fix(caisse): un ticket validé ne se réécrit plus (POS-01→04, 245)` | garde en modification, hachage, unicité de numéro | scénario `POS` transformé en acceptation |
| 15 | `fix(edge): les fonctions n'écrivent plus dans des colonnes qui n'existent pas (EF-04/05/07/08, 253)` | 21 colonnes réelles + erreurs lues | **baseline vidée** |
| 16 | `fix(rh): une absence déclarée se sait partout — le registre unique (TRV-01, 263)` | `employee_absence_days` + 4 déclencheurs + API de lecture | assertions `A01→A12` |

Le commit **17** — `fix(rh): un jour d'absence refuse pointage, heures supplémentaires, temps projet
et frais (TRV-03→TRV-10, 264)` — est celui qui répond mot pour mot à la question qui a ouvert ce
document.

---

## Annexes

### A. Les 20 fonctions Edge : ce qu'il faut leur demander

Chaque fonction est un **point d'entrée exposé au réseau**. Trois questions pour chacune, dans cet
ordre (c'est l'étage 2 et 3 du harnais de W6) :

1. **refuse-t-elle l'appel sans jeton ?** (401/403 — aujourd'hui seul le SSRF est testé, par `168`) ;
2. **écrit-elle dans des colonnes qui existent ?** (scanner W0.2 étendu à `supabase/functions/`) ;
3. **lit-elle l'erreur de ses écritures ?** (scanner W0.3)

| Fonction | Ce qui est testable sans base | Ce qui exige le réseau | Défaut connu |
|---|---|---|---|
| `auth-signup`, `create-user` | garde de rôle, validation d'entrée | envoi d'invitation | côté SQL testé (182) |
| `submit-e-invoice` | conformité Factur-X (profil, numéro définitif) | Chorus Pro | **EF-05, EF-06** |
| `submit-vat-return` | refus de simuler sans jeton | EFI | correcte, **jamais appelée** |
| `transmit-dsn` | refus de simuler | Net-entreprises | correcte, appelée |
| `validate-vat-vies`, `verify-iban`, `verify-siret` | validation de format, calcul de clé | VIES / INSEE | jamais appelées |
| `sync-bank-transactions` | mapping provider → `bank_transactions` | agrégateur | **EF-04** (+ 2 colonnes fantômes) |
| `parse-bank-statement`, `ocr-invoice-import`, `ai-import-mapping` | parsing de fixtures réelles | OpenAI (clé présente) | non testés |
| `handle-stripe-webhook` | **vérification de signature**, idempotence | Stripe | colonne `metadata` fantôme |
| `cron-payment-reminders` | idempotence de la relance | Resend | **EF-01, EF-02** |
| `outgoing-webhooks`, `public-api` | file d'attente, `Idempotency-Key` | HTTP sortant | **EF-08**, `H10` déjà corrigé (234) |
| `request-signature` | payload Yousign | Yousign | **EF-07** |
| `refresh-exchange-rates`, `generate-pdf`, `send-notification-email` | calcul, rendu | fournisseur | non testés |

### B. Où chaque chose se lit

| Question | Document |
|---|---|
| Le défaut, sa preuve, sa gravité | [Audit des modules hors comptabilité — 23/09](AUDIT-MODULES-HORS-COMPTA-2026-09-23.md) |
| Ce qui **n'a pas** été regardé | [Couverture d'audit par module — 24/09](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md) |
| Le registre consolidé, le plan, les tests | **ce document** |
| Les vagues déjà planifiées et leur charge | [Reste-à-faire — 22/09](RESTE-A-FAIRE-2026-09-22.md) |
| Les lots de correction V1 → V3 | [Plan correctif — 21/09](PLAN-CORRECTIF-AUDIT-2026-09-21.md) |
| Les exigences détaillées par module | [Cahier des charges correctif](CAHIER-DES-CHARGES-CORRECTIF.md) |
| Les scénarios de constat déjà écrits | `doc/audit/scenarios/*.sql` |
| Les échecs attendus encore ouverts | `app/sql/ci/expected_failures.sql` |

---

## Ce que ce document engage, et ce qu'il ne remplace pas

**Il engage quatre choses**, chacune vérifiable :

1. **Un chiffre unique et honnête** : 69 défauts métier mesurés (32 bloquants), 2 défauts d'outillage
   découverts en fusionnant, 16 contrôles transverses à créer — et une mesure de couverture qui dit
   aussi ce qu'elle ne prouve pas (64 % de la logique, 23 % des tables).
2. **Un ordre qui commence par la faille** : l'écriture inter-sociétés (ISO-01, ISO-02) et les droits
   neutralisés (ISO-03, PERM-01) passent avant tout le reste ; la chaîne stock/achats/ventes vient
   ensuite, parce qu'aucun achat n'entre en comptabilité de stock aujourd'hui.
3. **La réponse à la question posée** : une absence déclarée **n'est reprise nulle part** aujourd'hui —
   ni en paie, ni sur le pointage, ni sur les heures supplémentaires, ni sur le temps projet, ni sur
   les notes de frais, ni sur les tâches. Le registre unique `employee_absence_days`, les 16 contrôles
   TRV et les 34 assertions du scénario `266` la rendent opposable **partout**, avec les
   échappatoires légitimes (mission, dérogation, régularisation) prévues **dans le modèle**.
4. **Un test par défaut, jamais un « c'est corrigé »** : la Definition of Done (§5.2), la contre-épreuve
   (§4.7) et le registre des échecs attendus font que chaque correctif laisse une preuve exécutable.

**Ce qu'il ne remplace pas** : les deux audits d'origine, qui restent les pièces de constat (ce
document les cite et ne corrige aucun de leurs chiffres) ; le *reste-à-faire* du 22/09, qui garde la
planification des phases 0 à 6 ; le cahier des charges correctif, qui porte les exigences détaillées
module par module. **Ce document est le pont entre les deux audits et l'exécution.**

**Les trois choses à retenir si on ne lit qu'un paragraphe** :

- **Le danger est l'écriture chez le voisin, pas l'ergonomie** : un utilisateur ferme une tâche d'une
  autre société, un `viewer` crée des factures, une facture de A désigne un client de B. W1, d'abord.
- **La chaîne est rompue à la réception** : une commande reçue n'entre ni en stock par dépôt, ni en
  valorisation, ni en comptabilité. La spécification du correctif est déjà écrite et rouge (241) :
  c'est le point de départ le moins coûteux du plan.
- **Une absence n'existe pour personne** : elle est saisie, elle ne sert à rien. Le jour où la donnée
  d'absence circule (W9), cinq modules changent de comportement d'un coup — c'est le meilleur rapport
  valeur/effort du plan, et la réponse directe à la question posée.
