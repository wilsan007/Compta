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
| B.2 | Règles d'état, un lot par module, dans cet ordre : **ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets** | L8 → L15 | ≈ 40 j | 🔶 **ventes : R-001→R-005 ; achats : R-017/R-018 ; relances : R-059→R-061 (`500`→`506`) — 34 scénarios verts le 05/10** |
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

## B.2 — la trésorerie, à coordonner (R-048 → R-051)

Non commencée, et **pourquoi** : R-048/R-049 (`sepa_payment_orders`) et R-050/R-051
(`treasury_transfers`) demandent des enfants d'effet qui touchent **le rapprochement
bancaire** et une **écriture comptable** ; leur tierce personne est la partie
d'intégration/comptabilité, pas B seule. Le chemin pressenti : R-050 « exécuté » →
`post_journal_entry` (virement D `to_account.account_code` / C
`from_account.account_code`, `treasury_transfers.journal_entry_id` renseigné).

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