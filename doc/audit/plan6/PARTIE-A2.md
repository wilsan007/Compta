# Partie A2 — Vue Chaîne et écrans

> **Découpage du 05/10 au soir** : la partie A du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md) est scindée en
> trois lignes parallèles : [A1 — preuve et indice](PARTIE-A1.md) ·
> **A2 — Vue Chaîne et écrans** (ce fichier) ·
> [A3 — moteur L16 → L24](PARTIE-A3.md).
> Historique et cadre dans [PARTIE-A.md](PARTIE-A.md), fichier de famille.

| | |
|---|---|
| **Branche** | `plan6/a2-vue-chaine` |
| **Worktree** | `.claude/worktrees/plan6-a2-vue-chaine` |
| **Plage de migrations** | `487` → `492` (peu de SQL : lectures) |
| **Territoire de fichiers** | écrans et requêtes « chaîne », « cohérence », « robustesse », « pilotage » : `ChainTimeline.tsx`, `chainView.ts`, `chainCoherence.ts`, pages hôtes. Le SQL est **en lecture** (`document_links`, `chain_traces`, `chain_invariants`) ; **toute écriture SQL est une demande vers A1**, consignée ici (R3) |
| **Charge** | ≈ 6-7 j |
| **Départ possible** | tout de suite |
| **Décisions bloquantes** | aucune |

## Couplage à surveiller

**D balaie aussi `app/src/pages`** (dialogue de confirmation, typage des états).
Livrer les pages **une par une**, en déclarant dans le journal les fichiers
touchés, pour que le conflit avec D reste court (même règle que le plan impose à
D vis-à-vis de nous).

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| A2.1 | Recompter la Vue Chaîne : ce que `460` → `467` couvrent, ce qu'il manque pour I-01 | A.5 | 1 j | ✅ fait le 05/10 (voir §Recomptage) |
| A2.2 | Héberger la frise sur les types de documents restants : devis, commandes (ventes/achats), réceptions, bulletins, tickets de caisse, ordres de fabrication, notes de frais | A.5 (I-01) | ≈ 4 j | 🟡 **5 pages ajoutées le 05/10** (6 au total avec `InvoicesPage`) — voir §Livré |
| A2.3 | Pages « Robustesse » et « Cohérence » (L5) | A.4 | 3 j | ⬜ |
| A2.4 | Lecture écran de l'indice de cohérence (`chainCoherence.ts` → page) | 3.10 | 0,5 j | ⬜ |

## Recomptage (05/10/2026) — mesuré, pas supposé

**Le backend est fait et testé ; le composant existe ; il n'est hébergé que sur
une seule page.**

| Brique | Fichier | État |
|---|---|---|
| Ascendance/descendance récursive (amont/aval, garde de cycle, profondeur bornée, liens fermés consultables) | `app/sql/460_chain_arborescence.sql` (+ suite) | ✅ |
| Expliquer un montant — I-08 (document → écriture → ligne ; un chiffre inexpliqué est dit tel, jamais fabriqué) | `app/sql/462_chain_expliquer_montant.sql` (+ suite) | ✅ |
| Indicateurs de pilotage (marge, période, statut) | `461`, `463` → `467` | ✅ |
| Requêtes écran | `app/src/lib/queries/chainView.ts` : `getChain(...)`, `expliquerMontant(...)` | ✅ |
| Composant frise | `app/src/components/ChainTimeline.tsx` (+ test) | ✅ |
| **Pages hôtes** | `app/src/pages/InvoicesPage.tsx` — **la seule** | 🟠 1 / ~10 |

**Ce qu'il manque pour tenir I-01** (« depuis n'importe quel document… une frise
cliquable », la promesse du référentiel) : héberger la frise sur les autres
types de documents. Le composant est générique (`type, id`) : c'est un travail
d'**intégration par page**, pas de réécriture — d'où la charge mesurée ≈ 4 j.

## Livré (05/10/2026) — la frise hébergée, page par page

**3 pages sur ~10** hébergent la frise (`ChainTimeline`) et le « pourquoi ce
montant ? » (`ExplainAmount`). Aucune ligne de SQL, aucun maillon ajouté : le
composant est générique (`type`, `id`), l'intégration suit **mot pour mot** le
bloc déjà écrit dans `InvoicesPage` (label `crossModule.chain.title` → frise →
explication).

| Page | Type au registre `chain_document_types` | État |
|---|---|---|
| `InvoicesPage` | `invoices` | ✅ (existante, modèle suivi) |
| `PurchaseInvoicesPage` | `purchase_invoices` | ✅ ajoutée le 05/10 |
| `EmployeeExpensesPage` | `expense_reports` | ✅ ajoutée le 05/10 |
| `ManufacturingOrderDetailPage` | `manufacturing_orders` | ✅ ajoutée le 05/10 (page détail existante) |
| `SalesOrdersPage` | `sales_orders` | ✅ ajoutée le 05/10 (**vue détail créée** : lignes, reliquats, frise) |
| `DeliveryNotesPage` | `delivery_notes` | ✅ ajoutée le 05/10 (**vue détail créée** : lignes, reliquats facturés, frise) |

**La règle appliquée (décision du 05/10, du demandeur)** : *une vue détail est
ouverte seulement là où il y a de la matière à voir en détail*. Conséquence
directe et assumée :

- **6 pages** hébergent la frise — les 3 qui avaient déjà un détail
  (`invoices`, `purchase_invoices`, `expense_reports`) + les 3 créées ici ;
- **pas d'I-08** sur le bon de livraison : un BL ne porte aucun montant,
  « pourquoi ce chiffre ? » n'aurait rien à expliquer — on n'ouvre pas une
  explication vide ;
- **les pages sans matière à détail n'en reçoivent pas** : `QuotesPage`
  (devis), `PurchaseOrdersPage`, `PosSessionsPage`, `PayrollAccountingPage`
  n'ont ni lignes consultables ni vue détail. Y héberger la frise demanderait
  d'abord de **créer l'écran de détail** — décision de conception, pas
  intégration (demande R3 ci-dessous).

**Vérifications** : `tsc -b` **0 erreur** · `oxlint` **0/0** · `i18n:check` **vert
pour mes fichiers** · `a11y:icon-buttons` **vert** · Vitest **1 661 verts** ·
plafonds `any` **936/936** et `console.error` **488/488** conformes pour mes
fichiers.

## ⚠️ Collision de session dans ce worktree (05/10, 23h04)

Pendant ce lot, **une autre session a écrit dans ce worktree** (territoire A2,
normalement) : `app/src/pages/CoherencePage.tsx` (non suivi, 23h04) et les
`app/src/i18n/locales/{fr,en,ar}/{crossModule,nav}.json`. Ce fichier est du
**territoire A2.4** (lecture écran de l'indice de cohérence).

Conséquence, **mesurée et non cachée** :

- `i18n:check` **échoue sur 20 clés** — toutes dans `CoherencePage.tsx`
  (`crossModule:coherence.*` absentes en fr) ; **aucune de mes clés** ;
- `audit:console-error-ceiling` **489 > 488** — causé par le `console.error` de
  ce même fichier ; mes 3 pages n'en ajoutent aucun (`git diff` : 0).

**Je n'ai rien touché** dans ce fichier ni dans ces locales (R3 : hors de mon
lot ; et une session y travaille en direct). Le commit ci-dessous **n'ajoute que
mes 3 pages et ce fichier de suivi**.

**Demandes à l'intégration (R3)** :
1. `CoherencePage.tsx` et les clés `crossModule:coherence.*` : à porter au
   compte d'**A2.4** (la session en cours), pas de ce lot ;
2. une session ne doit pas écrire dans le worktree d'une autre partie (R1) —
   `CoherencePage.tsx` a été créé dans `plan6-a2-vue-chaine`.

> **Résolu (05/10, 23 h 16).** La session parallèle a livré **A2.4** et l'a
> corrigé : le `console.error` compté était un **mot dans un commentaire** de
> `CoherencePage.tsx` (le plafond compte **toute** occurrence, commentaires
> compris) — reformulé, la porte est **488/488 verte** ; les clés
> `crossModule:coherence.*` sont **présentes en fr/en/ar** (`i18n:check` passe).
> Le lot A2.4 est committé à la suite de ce fichier de suivi. **La demande R3
> n°1 est satisfaite** ; la n°2 (R1) reste valable comme **leçon** : deux
> sessions ne doivent pas écrire dans le même worktree.

**Ce qu'il reste pour tenir I-01, et pourquoi ce n'est pas mécanique.** Les
pages candidates suivantes (commandes de vente `sales_orders`, devis, réceptions
`goods_receipts`, bulletins `pay_runs`, tickets de caisse `pos_tickets`, ordres
de fabrication `manufacturing_orders`) **n'ont pas de vue détail** : ce sont des
tables plates (`SalesOrdersPage` : aucune `<Modal>` de consultation, seulement
transformer/supprimer). Y héberger la frise suppose donc de **créer une vue
détail** — c'est une décision de conception, pas une intégration. Elle est
consignée ici comme **demande** (R3) pour l'intégration : ouvre-t-on une vue
détail sur ces pages, ou attend-on le chantier D (`app/src/pages`) qui les
balaie déjà ?

## A2.4 — la page « Cohérence » (livrée le 05/10)

`app/src/pages/CoherencePage.tsx` — la moitié **écran** de L4/L5 : elle lit
`getChainCoherenceIndex()` et `getChainInvariants()` (`chainCoherence.ts`) et
montre **le score** (tenu / rompu / non mesuré / total), **la date du dernier
relevé**, et **le détail par invariant**. Elle **ne mesure rien** — c'est le job
`audit_chains_nocturne`, en base.

- **Route** `/system/coherence` (`App.tsx`, sous `AdminRoute`) et **entrée de
  navigation** (`navModules.ts`, `items.coherence`) ;
- **i18n fr/en/ar** : bloc `crossModule:coherence.*` + `nav:items.coherence` ;
- **Deux règles tenues ici.** `rompu` et `non_mesure` **ne se confondent pas**
  (un invariant qu'on ne sait pas mesurer n'est **pas** une alerte, il est
  compté à part) ; et **pas de journal console d'erreur** — l'erreur de lecture
  se dit à l'écran (`role="alert"`), comme dans `ChainTimeline`.

**Critère du plan vérifié** — `check-unused-tables` sur base neuve : **75 tables
non lues, conforme au plafond** ; lire l'indice par l'écran **ne relève pas** le
plafond (les deux tables d'invariants sont **lues**).

**Vérifications** : `tsc -b` **0** · `oxlint` **0/0** · `i18n:check` **vert**
(parité + clés littérales) · Vitest **1 661 verts** · `any` **1 735/1 735** ·
`console.error` **488/488** (plafonds gelés conformes).

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A2.1 | Recomptage Vue Chaîne : backend `460`/`462` + composant OK, frise hébergée sur `InvoicesPage` seulement | — (lecture seule) | `3a2642c` |
| 2026-10-05 | A2.2 (lot 1) | Frise + explication hébergées sur `PurchaseInvoicesPage` et `EmployeeExpensesPage` ; constat : les pages restantes n'ont pas de vue détail (demande R3) | `tsc` 0 · `oxlint` 0/0 · i18n vert · Vitest **1 661** · plafonds conformes | `5cd2dcc` |
| 2026-10-05 | A2.2 (lot 2) | Frise sur l'OF (page détail existante) ; **vues détail créées** sur les commandes de vente et les bons de livraison (lignes, reliquats, frise) ; pas d'I-08 sur le BL | `tsc` 0 · `oxlint` 0/0 · a11y vert · Vitest **1 661** · plafonds conformes (hors `CoherencePage.tsx`, session parallèle) | `a3e59cc` |
| 2026-10-05 | A2.4 | Page « Cohérence » (`CoherencePage.tsx`) : indice (tenu/rompu/non mesuré) + détail par invariant, route `/system/coherence`, entrée de nav, i18n fr/en/ar ; `check-unused-tables` conforme | `tsc` 0 · `oxlint` 0/0 · i18n vert · Vitest **1 661** · plafonds `any` **1 735** et `console.error` **488/488** conformes | _(ce lot)_ |
