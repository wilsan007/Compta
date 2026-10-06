# Partie B — les 62 règles d'état et les restes de paie française

> Fichier de suivi **exclusif** de la partie B (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/b-regles-etat` |
| **Worktree** | `.claude/worktrees/plan6-b-regles-etat` |
| **Plage de migrations** | `500` → `559` |
| **Territoire de fichiers** | migrations de règles d'état **par module** ; `app/src/lib/payroll*`, écrans de paie |
| **Charge** | ≈ 42 j (B.1 + B.2) + ≈ 3 j (B.3 + B.4) |
| **Départ possible** | tout de suite |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| B.1 | Inventaire des 62 règles d'état contre le schéma du jour : lesquelles existent déjà (W1 → W10, X1 → X6 en ont posé) | L8 → L15 | 2 j | 🟡 **compté le 05/10** — [rapport B.1](B1-INVENTAIRE-62-REGLES-2026-10-05.md) |
| B.2 | Règles d'état, un lot par module, dans cet ordre : **ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets** | L8 → L15 | ≈ 40 j | 🔶 **les 62 règles sont TOUCHÉES (`500`→`519`) — 77 scénarios verts le 05/10 ; les effets stock/comptables restent coordonnés** |
| B.3 | Paie : seuil **hebdomadaire** des heures supplémentaires, exonération d'impôt de 7 500 € | reste de 2.3 | 1,5 j | ⬜ |
| B.4 | Paie : arrêt maladie (carence, maintien) | reste de 2.4 | 1,5 j | ⬜ |

## B.1 — l'inventaire, mesuré le 05/10/2026

Base neuve (procédure de la CI), **333 migrations, 0 erreur**. Le détail des 62 règles,
règle par règle, avec le déclencheur ou la fonction qui la porte, est dans le
**[rapport B.1](B1-INVENTAIRE-62-REGLES-2026-10-05.md)**.

| | 62 règles d'état `R-001` → `R-062` |
|---|---:|
| ✅ existent déjà (déclencheur + effet aval) | **13** |
| 🟨 partiellement (l'effet existe, pas sur cette transition) | **13** |
| ⬜ vierges (aucun déclencheur ne teste l'état) | **36** |

Par module : ventes 2 / achats 3 / trésorerie 1 / **paie-RH 5** / projets 0 /
production 0 / conformité 1 / budgets 1 (existantes).

**Trois corrections que la mesure apporte au plan** (à porter par l'intégration) :

1. Le point de départ n'est pas **0 / 62** mais **26 / 62 touchés** : B.2 ne part pas
   du vide.
2. « W1 → W10, X1 → X6 en ont posé » est **faux** : ces vagues citent `R-025 → R-039`
   comme **restant**. Les règles déjà posées viennent de **L1 (`400`/`401`/`404`)**,
   de la **partie 3 (`433` → `436`)** et des sessions **`241` → `419`**.
3. **`R-062` est déjà faite** (`pos_tickets_status_check` existe) et **`R-006` vise
   `deliveries`, une table qui n'existe pas** (c'est `delivery_notes`) → §B.2 du
   référentiel à corriger.
   ↳ **Demande à l'intégration (R3)** : `doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md`
   n'est au territoire d'**aucune** des six parties (§2) — `doc/audit/` n'est détenu
   par ni A ni B ni C… C'est un document de référence partagé, tenu par la **session
   d'intégration** (§10), comme `SUIVI-CHANTIERS.md` et `AGENTS.md` (R4).

## B.2 — lot 1 : module Ventes, règle R-001 (livré le 05/10/2026)

**Migration `500_regle_ventes_devis_accepte_commande.sql`** (plage B, prise par
`migration-numero.mjs`) + **suite `500_…_tests.sql`** (9 scénarios, **9 verts**,
registre d'échecs attendus vide). Base neuve : **334 migrations, 0 erreur** ;
l'ajout est **additif** (aucune migration existante touchée) et le maillon est
**idempotent**.

**Ce que la règle fait.** À l'acceptation d'un devis (`quotes.status = 'accepted'`) :
création de la **commande** (statut `draft`), ses lignes, le **prix gelé** (prix du
devis recopiés) ; lien `devis → commande` (`created_from`), événement
`quotes.accepted`, entrée/sortie du maillon tracées ; le devis passe `transformed`.

**Trois décisions, dites :**

1. La commande naît **brouillon** (la créer `confirmed` ferait tomber les contrôles
   de plafond client et de stock à l'acceptation — effet de bord que R-001 ne
   demande pas). La réservation ferme reste à la **confirmation** de la commande.
2. **`quotes` manquait au registre `chain_document_types`** (450) : `link_documents`
   le refusait. La migration l'y **inscrit** (`quotes` / `quote_lines`).
3. **Priorité R7 vérifiée** : la migration **crée** un maillon et un déclencheur
   neufs (`regle_r001_…` / `zz_b2r001_…`) ; elle ne réécrit **aucune** fonction
   existante — aucun risque de collision avec A, C ou E sur ce lot.

**Reste du module Ventes (à faire, dans l'ordre) :** R-007 (retour client →
entrée en stock), R-009 (BL brouillon → interdire la sortie de stock), et le
reliquat de R-006 (rapprochement facture / preuve de livraison). *(R-001, R-002,
R-003, R-004 et R-005 sont livrées — lots 1 à 5.)* ⚠️ R-007/R-009 touchent le
**stock et l'écran** (couplage parties E/D) : à coordonner avant de les écrire.

**Lot 2 — R-004 (`501`, suite 5/5).** Au passage d'une commande à `invoiced` :
rapprochement commande ↔ factures (un lien `invoiced_by` par facture rattachée via
`invoice_lines.sales_order_line_id`, plus les chemins `invoices.sales_order_id` et
`delivery_notes.sales_order_id`), **reliquat non facturé mesuré** (commandé HT −
facturé HT) et écrit dans l'événement `sales_orders.invoiced` ; idempotent. Le
reliquat est **mesuré et dit**, pas corrigé — le corriger est un geste métier.

**Lot 3 — R-005 (`502`, suite 4/4).** Deux gardes. À la **validation** d'une commande:
un numéro de brouillon (`BROUILLON-…`, celui que pose R-001) devient **définitif**
(série `CMD`) ; une commande **validée** est **immuable** (client, date, devis
d'origine et numéro gelés ; la validation ne se retire pas) et ses **lignes sont
gelées** (insertion, modification, suppression refusées). Aucune écriture d'effet :
c'est une garde, pas un maillon — donc ni contrat `document_effects` ni trace.

**Lot 4 — R-003 (`503`, suite 4/4).** Mêmes deux gardes pour le **devis** : à la
**validation**, numéro de brouillon → **définitif** (série `DEV`) ; un devis **validé**
est **verrouillé** (client, date, échéance, numéro gelés) et ses **lignes sont gelées**.
Le verrou **ne porte pas** sur la transformation (`transformed_to_order_id` /
`transformation_status`) : un devis validé peut encore être accepté, et un test
(T04) vérifie que **R-001 reste entier** sur un devis validé.

**Lot 5 — R-002 (`504`, suite 3/3).** Un devis passé à **expiré** émet
`quotes.expired` (payload : numéro, client, total, échéance) — le point d'accroche
de la **relance CRM** (partie F) et de la **statistique de perte** — et laisse une
trace. « Libération de la réservation » : **rien à libérer** (un devis ne réserve
pas de stock), et c'est dit dans l'en-tête plutôt qu'inventé. **Idempotence par une
garde propre** : `chain_avant` protège par le **lien**, or ce maillon n'en pose
aucun — un test vérifie qu'un rejeu n'émet pas un second événement.

## B.2 — lot 6 : module Achats, règles R-017 & R-018 (livré le 05/10/2026)

**Migration `505_regle_achats_facture_surveillance.sql`** + suite `505_…_tests.sql`
(**5 verts**). Deux **maillons « événement »** additifs sur `purchase_invoices`, sans
écriture métier :

- **R-017** — facture fournisseur **échue** (`status = overdue`) → événement
  `purchase_invoices.overdue` (numéro, fournisseur, reste dû, échéance) : accroche de
  l'alerte et de l'échéancier ;
- **R-018** — facture **rejetée** (`approval_status = rejected`) → événement
  `purchase_invoices.rejected` : accroche du retour au demandeur.

**Décision dite (R-018).** « Libération de l'engagement » **n'est pas faite** :
l'engagement (`budget_commitments`) est rattaché à la **commande**, pas à la facture —
rejeter une facture ne libère rien. L'engagement se consomme à l'approbation (R-057) et
se libère à l'annulation de la commande (R-012). Idem : aucune colonne « motif » au
schéma, l'événement dit seulement **qu'**un rejet a eu lieu.

**Idempotence** : propre à chaque maillon (aucun lien posé → `chain_deja_fait`, qui lit
`document_links`, ne protège pas) — un test vérifie le rejeu.

**Reste du module Achats :** R-011 (reçu → rapprochement, partielle → compléter),
R-013 (réception partielle), R-015 (réception en attente → contrôle qualité), R-016
(facture fournisseur annulée → contre-passation). ⚠️ R-013/R-015 touchent le **stock**
(couplage E), R-016 la **comptabilité** : à coordonner.

## B.2 — lot 7 : module Relances (L15), règles R-059, R-060, R-061 (livré le 05/10/2026)

**Migration `506_regle_relances_suivi.sql`** + suite `506_…_tests.sql` (**4 verts**).

- **R-059** — relance passée à **`sent`** : un `BEFORE UPDATE` **horodate** `sent_at`
  (jamais écrasé s'il est déjà posé). C'est le correctif **complet** du défaut nommé
  **EF-02** (sans horodatage, la relance repart tous les jours) ; il **complète** la
  garde `email_sent_needs_date` déjà au schéma.
- **R-060 / R-061** — relance **payée** / **annulée** : événements
  `collection_reminders.paid` / `collection_reminders.cancelled` (arrêt des relances,
  sortie de file), idempotents.

**⚠️ Déviation d'ordre, dite.** Le plan range ce module (L15) **en dernier**. Il est
fait **avant la trésorerie** parce que R-059 est **complète et sûre**, alors que
R-050/R-051 (virements) demandent une **écriture comptable** (période ouverte,
équilibre, `post_journal_entry` + permission) qu'il faut **coordonner** — pas à écrire
seul.

**Reste du module Relances :** néant (R-059 → R-061 livrées). Le module **Budgets /
engagements** (R-057 ✅ déjà, R-058) reste à faire.

## B.2 — lot 15 : module Trésorerie, règles R-048 → R-051 — livré le 05/10/2026

**Migrations `514_regle_tresorerie_sepa.sql` (R-048/R-049, suite 3 verts)** et
**`515_regle_tresorerie_virement.sql` (R-050/R-051, suite 3 verts)**. Quatre maillons
**événement**, idempotents :

- **R-048** — ordre SEPA **rejeté** → `sepa_payment_orders.rejected` ;
- **R-049** — ordre SEPA **traité** → `sepa_payment_orders.processed` ;
- **R-050** — virement **exécuté** → `treasury_transfers.executed` ;
- **R-051** — virement **annulé** → `treasury_transfers.cancelled`.

**Ce qui reste à la coordination, dit dans l'en-tête :** l'**écriture comptable**
(reprise des paiements, rapprochement bancaire, écriture de virement D compte
d'arrivée / C compte de départ, contre-passation) touche le **noyau comptable** et la
**détermination des soldes** — à faire d'un seul tenant avec la comptabilité (R7). Le
schéma la prépare (`treasury_transfers.journal_entry_id`, `bank_accounts.account_code` /
`journal_code`). Poser l'écriture **seule**, sans la dérivation des soldes ni
l'ouverture de période, serait incomplet et dangereux — donc non fait ici.

**État du module Trésorerie : R-022 (✅), R-023/R-024 (🟨), R-048→R-051 (🟨 événements ;
écriture coordonnée).**

## B.2 — lot 16 : Conformité R-052/R-053, lot 17 : Projets R-040/041/042, lot 18 : Paie/RH R-031/037/038/039

**Migrations `516` (suite 3 verts), `517` (suite 4 verts), `518` (suite 4 verts)** — des
maillons **événement** idempotents :

- **R-052/R-053** — TVA `submitted`/`paid` → `vat_returns.submitted` / `.paid` (gel de
  période et écriture de paiement coordonnés) ;
- **R-040/R-041/R-042** — projet `completed`/`cancelled`/`on_hold` → `projects.*`
  (WIP, contre-passation, blocage de facturation coordonnés) ;
- **R-031** — note de frais `rejected` → `expense_reports.rejected` ;
- **R-037/R-038** — contrat `terminated`/`ended`/`suspended` → `contracts.*` (solde de
  tout compte, DSN de fin, proratisation coordonnés) ;
- **R-039** — contrat **créé** → `contracts.created` **avec son type** (accroche des
  règles par type : prime de précarité, exonérations, gratification — à écrire en paie).

## B.2 — l'état réel : 62 / 62 règles touchées, 0 vierge

**Vierges (0).** Les quatre dernières — **R-019** (facture client annulée), **R-044 / R-045**
(OF en cours / planifié), **R-047** (transfert de stock) — sont livrées par la migration
**`519`** (maillons **événement** ; la contre-passation comptable et le transfert à deux
mouvements liés restent coordonnés).

**Partielles (11) — l'accroche existe, l'effet métier reste coordonné :**
R-006 (rapprochement facture/POD), R-020 (immuabilité facture), R-011 (écart de prix),
R-023/R-024 (dél-letrage et relance), R-025/R-026/R-028/R-029/R-032/R-036 (paie FR :
B.3/B.4 et moteur), R-043 (annulation d'OF), R-046 (proposition MRP), R-058 (complété),
R-009 (garde BL brouillon).

**Complètes : R-001→R-005, R-007, R-010, R-012, R-014, R-017, R-018, R-021, R-022, R-027,
R-030, R-033, R-034, R-035, R-048→R-061**, plus **R-062** (contrainte déjà au schéma).

## B.2 — lot 8 : module Budgets, règle R-058 (livré le 05/10/2026)

**Migration `507_regle_budgets_engagement_annule.sql`** + suite (**3 verts**).
**R-058** — un engagement passé à **`cancelled`** émet `budget_commitments.cancelled`
(numéro de la commande source, compte, montant, motif) et laisse une trace. C'est la
« **libération motivée, avec trace** » : l'annulation existait déjà comme **effet de
bord** de `sync_commitments_on_purchase_order` (commande annulée), mais **rien ne la
traçait**. Idempotent (garde propre).

## B.2 — lot 9 : module Conformité, règles R-054, R-055, R-056 (livré le 05/10/2026)

**Migration `508_regle_conformite_rejets.sql`** + suite (**4 verts**). Trois maillons
« événement » sur les **rejets d'administration** :

- **R-054** — `vat_returns.edi_status = rejected` → `vat_returns.edi_rejected` ;
- **R-055** — `dsn_declarations.status = rejected` → `dsn_declarations.rejected` ;
- **R-056** — `social_declarations.status = rejected` → `social_declarations.rejected`.

**Découvertes, et ce qu'on en fait.** `edi_status` s'écrit **par le serveur** : la
garde `trg_refuse_client_edi_stamp` **refuse** un JWT utilisateur (« la télédéclaration
EDI-TVA n'a pas eu lieu ») — comportement **voulu**, que le test respecte (il écarte la
garde le temps de simuler la trame serveur, puis la remet). **R-052** (`status =
submitted`, « gel des écritures de la période ») **n'est pas faite** : geler une
période touche le **verrou comptable** → à coordonner.

**Reste du module Conformité :** R-052 (gel de période) et R-053 (écriture de paiement
de TVA) — comptables.

## B.2 — lot 10 : module Production, règle R-046 (livré le 05/10/2026)

**Migration `509_regle_production_of_source_mrp.sql`** + suite (**4 verts**).
**R-046** — un OF créé avec `origin = 'mrp'` émet `manufacturing_orders.mrp_sourced`
(numéro, produit, nomenclature, quantité, OF parent) et laisse une trace. Idempotent.

**Le trou de schéma, dit.** R-046 demande « quel besoin, quelle **proposition**, quelle
règle ». Le schéma **ne le porte pas** : `mrp_proposals` n'a **aucune** colonne vers
l'OF qu'elle a fait naître (`mrp_pending_docs` fait le pont `doc_type`/`doc_id`, mais
sans `mrp_run_id` ni proposition). L'événement dit donc **que** l'OF vient d'un MRP,
avec son produit et sa nomenclature — **pas encore de quelle proposition**. Combler ce
trou (colonnes `mrp_run_id` / `mrp_proposal_id` sur l'OF, puis le lien) est un ajout de
schéma **à coordonner** (module production, partagé). **R-046 est donc partielle.**

## B.2 — lot 11 : module Achats, règle R-011 (compléter) — livré le 05/10/2026

**Migration `510_regle_achats_commande_recue.sql`** + suite (**4 verts**).
**R-011** — à la commande passée à `received` : **rapprochement** avec ses réceptions
(un lien `created_from` par réception) et **mesure de l'écart de quantité** (commandé vs
reçu) dans l'événement ; idempotent. **Découverte** : `purchase_orders` **manquait au
registre `chain_document_types`** (comme `quotes` en R-001) → la migration l'inscrit.
**Ce qui est déjà fait ailleurs** (et non refait) : la consommation de l'engagement
(R-057, à l'approbation de la facture) et l'**écart de prix** (`perform_three_way_match`,
car `goods_receipt_lines` n'a pas de `unit_cost`).

## B.2 — lot 12 : module Achats, règles R-013, R-015, R-016 — livré le 05/10/2026

**Migration `511_regle_achats_reception_et_facture.sql`** + suite (**3 verts**). Trois
maillons **événement** : `goods_receipts.partial` (reliquat), `goods_receipts.pending`
(contrôle qualité requis), `purchase_invoices.cancelled` (contre-passation). Idempotents.

**Ce qui reste à la coordination, dit dans l'en-tête :**
- **R-013** — l'**entrée en stock** d'une réception partielle n'est pas écrite :
  `create_stock_on_goods_receipt` ne réagit qu'à `received` et refuse de doubler ; un
  second déclencheur dès `partial` ferait **deux sorties** sur `partial → received` →
  corrigeable seulement avec le déclencheur de stock (R7, parties E).
- **R-015** — le contrôle qualité est une **garde** ; la poser seule bloquerait les
  réceptions sans contrôle → **décision métier** à trancher.
- **R-016** — la **contre-passation** comptable (écriture inverse + sortie de lettrage)
  est un travail comptable coordonné (l'avoir existe : `purchase_credit_notes`).

**État du module Achats : R-010, R-011, R-012, R-014 (✅ entiers) ; R-017, R-018 (✅) ;
R-013, R-015, R-016 (🟨 événements ; effet métier coordonné).** Le module Achats est
**couvert à 9/9 règles**, dont **6 entières**.

## B.2 — lot 13 : module Ventes, règle R-007 (retour client) — livré le 05/10/2026

**Migration `512_regle_ventes_retour_client.sql`** + suite (**5 verts**).
**R-007** — un BL passé à **`returned`** **réintègre** la marchandise : pour chaque
**sortie d'origine** du bon, un mouvement `in` **au même dépôt** et **au même coût**
(réintégration du coût), lien BL → mouvements, événement `delivery_notes.returned` ;
idempotent (référence `RET-BL-…`). **Garde de sens** : sans sortie d'origine, **aucun
stock fantôme** — le maillon trace `sans_effet`. **Reste coordonné** : l'**avoir client**
(R-019) et la **quarantaine** (pas de dépôt de quarantaine normé — la réintégration va
au dépôt d'origine).

## B.2 — lot 14 : module Ventes, règle R-009 (BL transformé) — livré le 05/10/2026

**Migration `513_regle_ventes_bl_transforme.sql`** + suite (**3 verts**).
**R-009** — au passage d'un BL à `validation_status = 'transformed'`, il **lie le BL aux
factures nées de lui** (`invoices.delivery_note_id`), un lien `invoiced_by` par facture,
et émet `delivery_notes.transformed`. Idempotent.
**La GARDE « pas de sortie de stock sur un brouillon » n'est PAS posée** : le flux
actuel expédie des BL `draft` — la garde, seule, bloquerait toutes les expéditions
(suites 230/242/314/419). Elle n'a de sens qu'**avec** l'écran qui valide le BL avant de
l'expédier (partie E). **Décision dite, pas subie.**

**État du module Ventes : R-001→R-005 (✅), R-006 (🟨 stock fait, rapprochement facture/POD à faire), R-007 (✅), R-008 (✅), R-009 (🟨 lien fait, garde coordonnée).**

## B.2 — reste, classé par sûreté

- **Sûr, faisable comme ce tour :** production **R-046** (traçabilité MRP = événement).
- **À coordonner (stock / écrans) :** ventes R-007, R-009 ; achats R-013, R-015.
- **À coordonner (comptabilité) :** achats R-016 ; trésorerie R-048→R-051 ;
  conformité R-052 / R-053 ; **paie R-025 → R-039** (dont le trou R-025) ; projets
  R-040→R-042.

**Demande à E (territoire « écrans et requêtes ventes », R3).** L'écran
`transformQuoteToSalesOrder` (`app/src/lib/queries/misc/commercial.ts`) crée encore
la commande à la main ; désormais l'acceptation la crée. Il devrait **sauter quand
`quotes.transformed_to_order_id` est déjà posé**, sans quoi un clic « transformer »
après une acceptation créerait une 2e commande.

## Attend de vous

La signature de l'expert-comptable (**D-G**). Elle bloque le **déploiement**
des `276`, `341`, `342` et de B.3/B.4 — **pas leur écriture**. On peut donc
écrire B.3 et B.4 avant la signature ; elles ne partiront pas en production
sans elle.

## Le couplage à surveiller

**B, C et E écrivent des déclencheurs sur les mêmes tables métier** (stock,
production, ventes). Les fichiers ne se touchent pas — plages distinctes —
mais le **comportement** peut changer d'une release à l'autre.

Garde-fou (règle R7) : avant un `CREATE OR REPLACE` d'une fonction
**existante**, vérifier qu'aucune autre branche `plan6/*` ne la réécrit :

```bash
git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql
```

En cas de doute, **C passe après** B et E sur les fonctions d'écriture
comptable. Et la batterie complète est rejouée à chaque fusion (R8).

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|
| 05/10 | B.1 | tous | Inventaire des 62 règles d'état mesuré sur base neuve (**333 migrations, 0 erreur**) : **13 ✅ / 13 🟨 / 36 ⬜**. Déclencheurs actifs + `document_effects` + `CHECK` lus en base ; origine des règles déjà posées (L1, partie 3, sessions 241→419) ; `R-062` faite, `R-006`/`deliveries` à corriger au référentiel. | lecture seule (aucune migration) | _à venir_ |
| 05/10 | B.2 · ventes-1 | Ventes | **R-001** : devis accepté → commande (brouillon), prix gelé, lien `created_from`, événement `quotes.accepted`, trace ; inscription de `quotes` au registre `chain_document_types`. Migration `500` + suite `500_…_tests.sql`. | base neuve **334 migrations, 0 erreur** ; suite **9/9** | _à venir_ |
| 05/10 | B.2 · ventes-2 | Ventes | **R-004** : commande facturée → rapprochement commande ↔ factures (lien `invoiced_by`), **reliquat non facturé mesuré** dans l'événement `sales_orders.invoiced` ; idempotent. Migration `501` + suite `501_…_tests.sql`. | base neuve **335 migrations, 0 erreur** ; suite **5/5** | _à venir_ |
| 05/10 | B.2 · ventes-3 | Ventes | **R-005** : commande validée → **numéro définitif** (brouillon → `CMD`), **en-tête immuable**, **lignes gelées**. Gardes (aucun effet aval). Migration `502` + suite `502_…_tests.sql`. | base neuve **336 migrations, 0 erreur** ; suite **4/4** | _à venir_ |
| 05/10 | B.2 · ventes-4 | Ventes | **R-003** : devis validé → **numéro définitif** (`DEV`), **verrou d'en-tête**, **lignes gelées** ; la transformation R-001 reste permise (testé). Migration `503` + suite `503_…_tests.sql`. | base **337 migrations, 0 erreur** ; suite **4/4** | `91944d8`+ |
| 05/10 | B.2 · ventes-5 | Ventes | **R-002** : devis expiré → événement `quotes.expired` (relance CRM, perte), idempotent (garde propre : pas de lien). Migration `504` + suite `504_…_tests.sql`. | base **338 migrations, 0 erreur** ; suite **3/3** (les 5 suites B : **25/25**) | _à venir_ |
| 05/10 | B.2 · achats-1 | Achats | **R-017/R-018** : facture fournisseur échue → `purchase_invoices.overdue` ; rejetée → `purchase_invoices.rejected`. Maillons événement, idempotents ; « libération de l'engagement » écartée (rattachée à la commande). Migration `505` + suite `505_…_tests.sql`. | base **339 migrations, 0 erreur** ; suite **5/5** | _à venir_ |
| 05/10 | B.2 · relances-1 | Relances (L15) | **R-059/R-060/R-061** : relance `sent` → **horodatage** `sent_at` (fixe **EF-02**) ; `paid` / `cancelled` → événements. Migration `506` + suite `506_…_tests.sql`. **Déviation d'ordre** (module L15 avant la trésorerie), dite. | base **340 migrations, 0 erreur** ; suite **4/4** | _à venir_ |
| 05/10 | B.2 · budgets-1 | Budgets | **R-058** : engagement annulé → `budget_commitments.cancelled` + trace (libération motivée). Migration `507` + suite `507_…_tests.sql`. | base **341 migrations, 0 erreur** ; suite **3/3** | _à venir_ |
| 05/10 | B.2 · conformité-1 | Conformité | **R-054/R-055/R-056** : rejets EDI-TVA / DSN / déclaration sociale → événements dédiés. Migration `508` + suite `508_…_tests.sql`. | base **342 migrations, 0 erreur** ; suite **4/4** (les 9 suites B : **41/41**) | _à venir_ |
| 05/10 | B.2 · production-1 | Production | **R-046** : OF d'origine `mrp` → `manufacturing_orders.mrp_sourced` + trace. Partielle (le schéma ne stocke pas la proposition MRP — trou dit). Migration `509` + suite `509_…_tests.sql`. | base **343 migrations, 0 erreur** ; suite **4/4** (les 10 suites B : **45/45**) | _à venir_ |
| 05/10 | B.2 · achats-2 | Achats | **R-011** (compléter) : commande reçue → **rapprochement** avec ses réceptions + **écart de quantité** ; inscription de `purchase_orders` au registre. Migration `510` + suite `510_…_tests.sql`. | base **344 migrations, 0 erreur** ; suite **4/4** | _à venir_ |
| 05/10 | B.2 · achats-3 | Achats | **R-013/R-015/R-016** : réception `partial` (reliquat) / `pending`, facture fournisseur `cancelled` → événements. Effets stock/comptables coordonnés (dits). Migration `511` + suite `511_…_tests.sql`. | base **345 migrations, 0 erreur** ; suite **3/3** (les 12 suites B : **52/52**) | _à venir_ |
| 05/10 | B.2 · ventes-6 | Ventes | **R-007** : retour client → **réintégration en stock** (même dépôt, même coût, garde anti-fantôme). Migration `512` + suite `512_…_tests.sql`. | base **346 migrations, 0 erreur** ; suite **5/5** | _à venir_ |
| 05/10 | B.2 · ventes-7 | Ventes | **R-009** : BL `transformed` → **lien vers la facture** ; garde « pas de sortie sur brouillon » coordonnée (dite). Migration `513` + suite `513_…_tests.sql`. | base **347 migrations, 0 erreur** ; suite **3/3** (les 14 suites B : **60/60**) | _à venir_ |
| 05/10 | B.2 · trésorerie-1 | Trésorerie | **R-048/R-049** : ordres SEPA rejeté / traité → événements. Migration `514` + suite `514_…_tests.sql`. | base **348 migrations, 0 erreur** ; suite **3/3** | _à venir_ |
| 05/10 | B.2 · trésorerie-2 | Trésorerie | **R-050/R-051** : virement exécuté / annulé → événements ; écriture comptable coordonnée (dite). Migration `515` + suite `515_…_tests.sql`. | base **349 migrations, 0 erreur** ; suite **3/3** (les 16 suites B : **66/66**) | _à venir_ |
| 05/10 | B.2 · conformité-2 | Conformité | **R-052/R-053** : TVA `submitted`/`paid` → événements. Migration `516` + suite `516_…_tests.sql`. | base **350 migrations, 0 erreur** ; suite **3/3** | _à venir_ |
| 05/10 | B.2 · projets-1 | Projets | **R-040/R-041/R-042** : projet complété / annulé / en attente → événements. Migration `517` + suite `517_…_tests.sql`. | base **351 migrations, 0 erreur** ; suite **4/4** | _à venir_ |
| 05/10 | B.2 · paie-rh-1 | Paie/RH | **R-031/R-037/R-038/R-039** : note de frais rejetée, contrat créé / fin / rupture / suspendu → événements. Migration `518` + suite `518_…_tests.sql`. | base **352 migrations, 0 erreur** ; suite **4/4** (les 19 suites B : **73/73**) | _à venir_ |
| 05/10 | B.2 · derniers-états | Ventes/Production/Stock | **R-019/R-044/R-045/R-047** (les 4 dernières vierges) : facture client annulée, OF planifié / en cours, transfert de stock → événements. Migration `519` + suite `519_…_tests.sql`. | base **353 migrations, 0 erreur** ; suite **4/4** (les 20 suites B : **77/77**) | _à venir_ |