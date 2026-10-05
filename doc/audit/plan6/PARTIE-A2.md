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
| A2.2 | Héberger la frise sur les types de documents restants : devis, commandes (ventes/achats), réceptions, bulletins, tickets de caisse, ordres de fabrication, notes de frais | A.5 (I-01) | ≈ 4 j | 🟡 **2 pages livrées le 05/10** (achats `purchase_invoices`, notes de frais `expense_reports`) — voir §Livré |
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

**Vérifications** : `tsc -b` **0 erreur** · `oxlint` **0/0** · `i18n:check`
**vert** · Vitest **1 661 verts** (suite complète ; dont `chainTimeline` 4,
`explainAmount` 3, `chain-coherence` 9) · plafonds `any` **936/936** et
`console.error` **488/488** conformes.

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

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A2.1 | Recomptage Vue Chaîne : backend `460`/`462` + composant OK, frise hébergée sur `InvoicesPage` seulement | — (lecture seule) | `3a2642c` |
| 2026-10-05 | A2.2 (lot 1) | Frise + explication hébergées sur `PurchaseInvoicesPage` et `EmployeeExpensesPage` ; constat : les pages restantes n'ont pas de vue détail (demande R3) | `tsc` 0 · `oxlint` 0/0 · i18n vert · Vitest **1 661** · plafonds conformes | _(ce lot)_ |
