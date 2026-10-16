# Partie A3 · L16 — les chaînages internes, famille par famille

> **Ligne de travail dédiée à L16** (les 9 familles de chaînages *internes* à un
> module, §B.3 du référentiel). Elle existe pour une raison mesurée : la ligne A3
> (`plan6/a3-moteur`) traite en parallèle la chaîne **Commerciale**, et deux
> sessions ne peuvent pas éditer le même worktree (R1) — or L16 est le lot le
> plus large du plan (« 9 familles → 0 »).

| | |
|---|---|
| **Branche** | `plan6/a3-l16-projets` |
| **Worktree** | `.claude/worktrees/plan6-a3-l16-projets` |
| **Plage de migrations** | `493` → `499`, **partagée avec A3** : le numéro est pris par `prendre` (registre atomique), jamais à la main (R2). **`496` pris** pour ce lot |
| **Territoire** | nouveaux maillons `chain_l16_*` ; `app/sql/*chain*` existant se modifie **par demande** vers l'intégration (R7) |
| **Charge** | le reste de L16 : **7 familles ouvertes** (tableau ci-dessous) |

## Les 9 familles de L16 (§B.3) — état mesuré au 05/10/2026

| Module | Chaînage interne attendu | État |
|---|---|---|
| **Commercial** | devis ↔ commande ↔ livraison ↔ facture ↔ avoir ↔ règlement ↔ relance | 🟡 livré par A3 : `493` (devis→commande), `494` (commande→livraison), `495` (livraison→facture) en cours |
| **Projets** | devis ↔ projet ↔ budget ↔ temps ↔ coût ↔ facturation ↔ marge ↔ clôture | 🟡 **clôture livrée (`496`)** — restent : temps→coût, facturation |
| **Comptabilité** | lettrage ↔ relance ↔ provision ↔ clôture ; rapprochement ; à-nouveaux | ⬜ ouvert |
| **Stock** | besoin (MRP) ↔ proposition ↔ commande ↔ réception ↔ CUMP ↔ écriture ; lot ↔ rappel | ⬜ ouvert (`run_mrp` 3/7 ; `transfer` non traité, R-047) |
| **Production** | OF ↔ nomenclature ↔ consommation ↔ rebuts ↔ PF ↔ coût ↔ marge par OF | 🟡 **démarrage livré (`750`)** — reste : consommation → stock/coût, rebuts ↔ coût, multi-niveaux |
| **RH / Paie** | contrat ↔ salarié ↔ absence ↔ temps ↔ variable ↔ bulletin ↔ cumuls ↔ écriture ↔ virement | ⬜ ouvert — le « maillon faible » du référentiel (R-025) |
| **Trésorerie** | prévision ↔ échéancier ↔ ordre de paiement ↔ virement ↔ relevé ↔ rapprochement | ⬜ ouvert (`cash_flow_forecast` 4/7 ; virement interne muet, R-050) |
| **Caisse** | ticket ↔ session ↔ clôture ↔ écart ↔ TVA ↔ stock ↔ journal NF-525 | ✅ le plus complet (5/7, `219`) |

## Lot 1 — la clôture de projet cesse d'être muette (`496`)

**Défaut nommé** : §B.3 « clôture de projet muette (`R-040`) ». Mesuré avant
d'écrire, sur base neuve (333 migrations) : `projects.status` admet `completed`,
mais **une seule** fonction du schéma mentionnait `projects` + `completed`
(`calculate_project_profitability`), **aucun déclencheur** ne s'exécutait sur le
passage à `completed`, `projects` était **absent** du registre
`chain_document_types`, et aucun contrat ne se nommait pour cet effet.

**Livré** : le type `projects` au registre · le contrat `project.closure.finalized`
· le maillon `chain_l16_project_closure` (déclencheur `AFTER UPDATE`, donc il
couvre **tous** les chemins de clôture, écran compris) — trace « applique »,
événement `projects.completed` **portant la marge gelée** dans sa charge utile.

**Deux décisions, chacune payée par une mesure** :

1. **La clôture n'est jamais bloquée.** La marge est *tentée* ; si le calcul
   échoue (projet sans temps ni coût), la raison est **écrite** au lieu de lever
   — un maillon n'empêche pas le geste qu'il instrumente (doctrine 252, T04) ;
2. **L'idempotence est EXPLICITE, et le pourquoi est mesuré.**
   `chain_deja_fait` du socle détecte le rejeu par `document_links` ; la clôture
   ne produit **aucun document d'aval**, donc rien ne l'aurait détecté — la
   suite l'a prouvé (`T02` : le rejeu produisait une 2ᵉ trace et un 2ᵉ
   événement, **vu rouge avant** d'être vert). C'est l'annonce elle-même qui
   atteste l'effet, et le rejeu est **dit** (trace « ignore »).

**Éprouvé** — suite `496`, **14/14 verdicts** : trace + contrat déclaré (4),
idempotence D1 (3), silence hors clôture (2), clôture non bloquée (2),
isolation D8 (3). Portes : **G2** 64 constats / **0 non déclaré** ·
**G5** 153/153 suites branchées · migration rejouable.

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | L16 · Projets | La clôture de projet est tracée et annoncée (`496`) : registre `projects`, contrat `project.closure.finalized`, maillon `chain_l16_project_closure` + suite enrôlée | suite **14/14** · G2 **0 non déclaré** · G5 **153/153** · rejouable | *(fusionné dans `main`, PR #11)* |
| 2026-10-06 | L16 · Production | Le démarrage d'OF est tracé et annoncé (`750`) : contrat `production.order.started`, maillon `chain_l16_production_start` + suite enrôlée ; plage `750`→`759` inscrite (registre + `AGENTS.md`) | suite **12/12** · G2 **0 non déclaré** · G5 **155/155** · rejouable | _(ce lot)_ |

## Lot 2 — le démarrage d'OF cesse d'être muet (`750`, Production)

**Défaut nommé** : §B.3 « **`in_progress` muet (`R-044`)** ». Mesuré avant d'écrire
(base neuve, 333 migrations) : `manufacturing_orders.status` admet `in_progress`,
mais **un seul** maillon existe sur cette table (`zz_l1_manufacturing_order`,
401) et il ne traite **que** l'arrivée à `completed` (deux effets + un
événement) ; le passage à `in_progress` n'apparaît nulle part.

**Ce que la mesure a AUSSI décidé** : **aucune** fonction ne lie une réservation
de stock à un OF (`stock_reservations.reference_type` existe, rien ne l'écrit
pour la production) — il n'y a donc **aucun document d'aval** au démarrage. Le
maillon **trace et annonce, et ne lie rien** — inventer un lien (l'OF vers
lui-même, ou vers une réservation qui n'existe pas) ferait **mentir la frise**.
C'est écrit dans l'en-tête de la migration, pas caché.

**Livré** : le contrat `production.order.started` · le maillon
`chain_l16_production_start` (déclencheur `AFTER UPDATE`, `planned` →
`in_progress`) — trace « applique » + événement `manufacturing_orders.started`
portant numéro, produit, quantité et date de début. Idempotence **explicite**,
pour la même raison mesurée que la `496` (pas de lien ⇒ c'est l'annonce qui
atteste l'effet, et le rejeu est **dit** par une trace `ignore`).

**Éprouvé** — suite `750`, **12/12 verdicts** : trace + contrat déclaré (4),
idempotence D1 (3), silence hors démarrage (2), isolation D8 (3). Le décor
d'atelier a été repris de la `229` : un OF **refuse de naître sans article à
fabriquer** (« aucun article à fabriquer », garde `a_manufacturing_order_product`)
— la suite l'a **vu rouge** avant d'être verte.

**Portes** : **G2** 0 effet non déclaré · **G5** suites branchées · migration
rejouable · `ci.yml` YAML valide.
