# Partie A3 — moteur L16 → L24

> **Découpage du 05/10 au soir** : la partie A du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md) est scindée en
> trois lignes parallèles : [A1 — preuve et indice](PARTIE-A1.md) ·
> [A2 — Vue Chaîne et écrans](PARTIE-A2.md) ·
> **A3 — moteur L16 → L24** (ce fichier).
> Historique et cadre dans [PARTIE-A.md](PARTIE-A.md), fichier de famille.

| | |
|---|---|
| **Branche** | `plan6/a3-moteur` |
| **Worktree** | `.claude/worktrees/plan6-a3-moteur` |
| **Plage de migrations** | `493` → `499` (⚠️ **7 numéros seulement** : demander à l'intégration une extension de plage avant saturation — le registre fait foi) |
| **Territoire de fichiers** | **nouveaux** maillons et fonctions de L16 → L22 (chaînages internes, couples inter-modules vides, régénération, lettrage génératif), L23 (événements et webhooks unifiés — suite de la tranche 1), L24 (explicabilité, régularisation guidée). Modifier le socle existant d'A1 (`app/sql/*chain*`) : **demande consignée ici** (R3 + R7) |
| **Charge** | plafond du plan (A.6/A.7) + ≈ 25 j (A.8) |
| **Départ possible** | A.6/A.7 tout de suite ; **A.8 attend vos cinq décisions et l'expert-comptable** |

## Le couplage à surveiller — le plus fort du plan

A3 écrit des déclencheurs sur les **mêmes tables métier** que B, C et E (stock,
production, ventes). Les fichiers ne se touchent pas (plages distinctes), mais
le **comportement** peut se contrer. Garde-fous :

- **R7** avant tout `CREATE OR REPLACE` d'une fonction existante
  (`git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql`) ;
- **la règle « module de la semaine »** : A3 annonce dans son journal le module
  qu'il touche cette semaine ; B, C et E n'y écrivent pas cette semaine-là — et
  réciproquement (la même règle est déjà écrite pour C) ;
- **lots courts** (R8) : la batterie complète est rejouée par l'intégration à
  chaque fusion.

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| A3.1 | Recompter L16 → L22 : inventaire de ce que `415` → `422` ont réellement posé (L23 tranche 1, L17 capacité ↔ absence, L18 consommation chantier, L19, L20, métriques, retour arrière) et ce qu'il reste par lot du plan d'implémentation | A.6 | 1 j | ✅ fait le 05/10 (voir §Recomptage) |
| A3.2 | L16 → L22 : chaînages internes, couples inter-modules vides, régénération d'écriture, lettrage génératif, moteur de règles | A.6 | plafond du plan | 🟡 **15 maillons livrés** : L16 **Commercial** — devis → commande (`493`, **19/19**), commande → livraison (`494`, **14/14**), livraison → facture (`495`, **14/14**), facture → règlement (`497`, **14/14**), facture → avoir (`754`, **14/14**), facture → relance (`757`, **15/15**) ; L16 **Achats** — commande d'achat → réception (`498`, **14/14**), réception → facture fournisseur (`755`, **14/14**), facture fournisseur → règlement (`753`, **14/14**), facture fournisseur → avoir (`756`, **14/14**) ; L16 **Comptabilité** — groupe de lettrage → ses lignes (`758`, **12/12**), exercice clos → écriture d'affectation (`760`, **12/12**) ; L16 **RH/Paie** — bulletin → écriture (`759`, **12/12**) ; L16 **Trésorerie** — ordre de paiement → virement (`499`, **16/16**) ; L16 **Stock** — proposition MRP → commande d'achat (`751`, **15/15**) — voir §A3.2 lots 1 à 15 |
| A3.3 | L23 (événements et webhooks unifiés, suite de la tranche 1) ; L24 (explicabilité, régularisation guidée) | A.7 | plafond du plan | 🟡 **L23-b livré le 06/10** : le **moteur d'automatisations** (`752`, suite **10/10**) — voir §A3.3 ; restent **L23-c** (lecture écran), **L24** |
| A3.4 | P1 certificat d'intégrité, P3 audit de reprise, P2 banc sur données du prospect, puis P4, P5, P7, P8, P6 | A.8 (propositions P1 → P8) | ≈ 25 j | 🟡 **P1 : le SQL est livré** (`770`, suite **7/7** sur base neuve) — voir §A3.4 ; l'**écran** reste à **A2** ; puis P3 → P6 |

## Recomptage L16 → L22 (05/10/2026) — mesuré dans `app/sql/`, pas recopié

Ce que les migrations `415` → `422` ont réellement posé, et ce que le plan
d'implémentation dit encore ouvert. **Le suivi du plan était en retard, la base
non** — mais le gros de L16 → L22 reste devant.

| Lot | Objet (plan du 24/09) | Migrations posées | État mesuré | Ce qui reste |
|---|---|---|---|---|
| **L16** | Chaînages internes — **9 familles** (compta : lettrage ↔ dépréciation ↔ clôture ; stock : besoin ↔ proposition ↔ commande ; projet : budget ↔ temps ↔ coût ↔ marge ; RH : contrat ↔ absence ↔ cumuls…) | — | ⬜ **9 → 0** | tout le lot |
| **L17** | Production ↔ RH (capacité ↔ absence) | `416`, `417` | ✅ livré (2 tranches) | le couple est fermé dans les deux sens |
| **L18** | Stock ↔ Projets, Production ↔ Projets | `418` | 🟡 tranche 1 | **tranche 2** : fabrication à la commande (un projet commande un OF), réintégration du coût matière dans la marge projet |
| **L19** | Production ↔ Trésorerie, Reporting ↔ tous | `420` (+ métriques `461`, `463` → `467`) | 🟡 engagé | reporting ↔ tous : lectures par **définitions uniques** (I-08) au lieu d'un recalcul par écran |
| **L20** | Régénération généralisée (M-04) + historique | `422` | 🟡 tranche 1 | **la régénération en cascade n'est PAS livrée** — c'est la tranche 2, le gros du lot |
| **L21** | Dérivés du lettrage (M-03) : TVA sur encaissements, réversibilité | — | ⬜ | tout — **bloqué** par L10/L14/L20 |
| **L22** | Moteur de règles client (I-07) + simulateur d'impact (I-04) | — | ⬜ | tout — dépend de L1, L5, L11 |
| **L23** | Événements, automatisations, webhooks unifiés (I-06) | `415` | 🟡 tranche 1 (journal unifié : pont, catalogue vrai, RLS) | **L23-b** (automatisations), **L23-c** (lecture écran) |
| **L24** | Explicabilité (I-08) · régularisation guidée (I-09) · localisation par chaînes (I-11) · assistant (I-12) | `462` (I-08) | 🟡 partiel | I-09, I-11, I-12 ; l'écran d'I-08 est à A2 |

**Deux constats de numérotation** :

- `419_delivery_stock_out_two_doctrines.sql` n'est **pas** un lot : c'est une
  adaptation des sorties de stock sur livraison (deux doctrines) ; **il n'a pas
  de suite `_tests`** — à vérifier avant de le considérer couvert.
- **`421` n'existe pas** : le numéro est resté libre dans la zone. A3 le prendra
  par `prendre` s'il en a besoin, pas à la main (R2).

**Ordre de reprise conseillé** (dépendances du plan respectées) : L23-b (débloqué)
· L20-tranche 2 (le plus gros, débloque L21) · L18-tranche 2 · L19-reporting ·
L16 → L22 le reste. **L21 et L22 restent bloqués** tant que L20 et L5 ne sont pas
livrés.

## A3.2 — lot 1 : le devis accepté devient une commande (migration `493`)

**Le chaînage le plus attendu du module Commercial, et un écart de niveau 1 du
référentiel** (« devis → commande non chaîné », §B.3 ; « à la main, sans trace »,
§D.2). Mesuré avant d'écrire, sur **base neuve (333 migrations, 0 erreur)** :

| Ce que la mesure a trouvé | Conséquence |
|---|---|
| `convert_quote_to_invoice` existe et est testé (`190`, réécrit en `317`) | le devis savait produire une **facture**, pas une **commande** |
| `quotes.transformed_to_order_id` et `sales_orders.quote_id` existent, `validation_status` admet `transformed` | le schéma portait le chaînon — **personne ne l'écrivait** |
| `quotes` **absent** de `chain_document_types` (27 types, sans les devis) | un lien quotes→sales_orders aurait été **refusé** (garde d'existence `451`) |
| aucun maillon ne se nommait pour cet effet | la porte **G2** aurait refusé l'appel (effet non déclaré) |

**Ce qui est livré** — migration `493_chain_l16_devis_commande.sql` :

1. le type `quotes` **entre au registre** des types de documents (upsert) ;
2. le **contrat d'effet** `sale.quote.to_order` est déclaré (L7) ;
3. le maillon `convert_quote_to_order` — **prix gelé** (totaux = somme des lignes
   acceptées, aucun tarif relu), **idempotent** (rejeu refusé), **réversible**
   (le lien se ferme), **tracé** (`link_documents`) ;
4. droits : `REVOKE` de PUBLIC/anon, `GRANT` à authenticated (garde `228 T06`).

**Éprouvé** — la suite `493` rend **19/19 verdicts** sur base neuve :

| Épreuve | Verdicts | Ce qui est prouvé |
|---|---|---|
| **T01** nominal | 6 | commande créée, lignes copiées, **aucun écart de prix** (gelé), total = somme acceptée, le devis dit ce qu'il est devenu, **le lien est posé** |
| **T02** idempotence (D1) | 3 | le rejeu est **REFUSÉ** (`unique_violation`) ; ni commande ni lien ajouté |
| **T03** refus explicites | 4 | non accepté / refusé / sans ligne : **trois raisons écrites**, aucune commande laissée |
| **T04** la frise (I-01) | 2 | `chain_document_arborescence` voit la commande **depuis le devis**, et le devis **depuis la commande** |
| **T05** isolation (D8) | 4 | le voisin **ne convertit pas** (`no_data_found`), ne voit **aucun** lien ni commande ; la commande d'A existe toujours |

**Portes franchies** : G2 (contrat d'effet) — self-test OK, **0 effet non
déclaré** ; **rejouabilité** de la `493` (2ᵉ application sans erreur) ; suite
**enrôlée dans `ci.yml`** sous le marqueur `plan6:a3` (G5).

**Ce que ce lot NE fait pas** : il ne touche ni le stock (la réservation naît de
la **confirmation** de la commande, pas de sa création — aucun comportement
d'aval n'est modifié) ni la facturation (le devis peut produire une commande
**ou** une facture, les deux étant tracés séparément). Les 8 autres familles de
L16 (stock, production, RH, projets, trésorerie…) restent devant.

## A3.2 — lot 2 : la livraison rattachée à la commande (migration `494`)

**Le tronçon suivant du module Commercial** — « commande ↔ livraison » (§B.3).
Mesuré avant d'écrire : `delivery_notes.sales_order_id` et
`delivery_note_lines.sales_order_line_id` **existaient**, et **personne ne les
écrivait** ; aucun contrat d'effet, donc aucun maillon.

**Ce qui est livré** — migration `494_chain_l16_commande_livraison.sql` :

1. le **contrat d'effet** `sale.order.to_delivery` (`document_effects`) ;
2. le maillon `chain_l16_order_deliver(p_order, p_delivery)` : la commande
   **confirmée** rattache son bon de livraison — **cohérence vérifiée** (même
   client, statuts valides), **idempotent** (rejeu refusé), le
   `delivery_notes.sales_order_id` est **écrit** (la colonne que personne
   n'écrivait), et le **lien** `link_documents` est posé (`delivered_by`).

**Éprouvé** — suite `494` **14/14 verdicts** sur base neuve (clone de
`a3_maillon`, 333 migrations) :

| Épreuve | Verdicts | Ce qui est prouvé |
|---|---|---|
| **T01** nominal | 3 | bon rattaché, `sales_order_id` posé, **le lien est posé** |
| **T02** idempotence (D1) | 2 | rejeu **REFUSÉ** (`unique_violation`), un seul lien |
| **T03** refus explicites | 4 | brouillon / autre client / annulé / inexistant — **quatre raisons** |
| **T04** la frise (I-01) | 2 | la frise voit le bon **depuis la commande**, et la commande **depuis le bon** |
| **T05** isolation (D8) | 3 | le voisin ne rattache pas, ne voit **aucun** lien ; le lien de A reste à A |

**Portes franchies** : G2 (contrat d'effet) **63 constats, 0 au registre** ;
G8 (inventaire RPC) OK ; `check_tenant_guard` OK (485 SECURITY DEFINER, 0 sans
mention de la société) ; `check_anon_grants` OK ; `check_forced_rls_writers` OK ;
rejouabilité de la `494` OK ; suite **enrôlée dans `ci.yml`** (G5 **152/152**).

**Ce que ce lot NE fait pas** : il ne modifie pas le **statut de la commande**
(`sales_orders.delivery_status` reste piloté par les écrivains existants), ni la
sortie de stock (déjà portée par le bon, `sale.delivery.stock_out`). Restent de
la famille Commercial : livraison ↔ facture (partiellement chez B), avoir,
règlement, relance, et la **marge prévisionnelle** (absente).

## A3.2 — lot 3 : la facture rattachée au bon de livraison (migration `495`)

**Le tronçon suivant du module Commercial** — « livraison ↔ facture » (§B.3),
après `493` (devis → commande) et `494` (commande → livraison). Mesuré avant
d'écrire : `invoices.delivery_note_id` et `invoice_lines.delivery_note_line_id`
**existaient**, et **personne ne les écrivait** ; aucun contrat d'effet.

**Ce qui est livré** — migration `495_chain_l16_livraison_facture.sql` :
contrat d'effet `sale.delivery.to_invoice` + maillon
`chain_l16_delivery_invoice(p_delivery, p_invoice)` — la facture et le bon
visent le **même client**, ni l'un ni l'autre n'est **annulé**, un bon déjà
facturé par une autre facture est **refusé** ; **idempotent** (rejeu refusé) ;
`invoices.delivery_note_id` **écrit** ; **lien** `link_documents` (`invoiced_by`).

**Éprouvé** — suite `495` **14/14 verdicts** sur base neuve : T01 nominal (3),
T02 idempotence (2), T03 quatre refus explicites (4), T04 frise des deux côtés
(2), T05 isolation (3). Portes : G2 **64 constats, 0 au registre** ; G8,
`check_tenant_guard` (486 SECURITY DEFINER, 0 sans société), `check_anon_grants`
**OK** ; `495` rejouable ; suite enrôlée dans `ci.yml` (G5 **153/153**).

**Reste de la famille Commercial** : avoir (`reversed_by`), règlement
(`paid_by`), relance, et la **marge prévisionnelle** (absente).

## A3.2 — lot 4 : le règlement rattaché à la facture (migration `497`) ; l'avoir différé

**Le tronçon suivant du module Commercial** — « facture ↔ règlement » (§B.3),
après `495`. Mesuré avant d'écrire : `customer_payments.invoice_id` et
`invoice_number` **existaient**, et **personne ne les écrivait**.

**Ce qui est livré** — migration `497_chain_l16_facture_reglement.sql` :
contrat d'effet `sale.invoice.to_payment` + maillon
`chain_l16_invoice_payment(p_invoice, p_payment)` — même client, ni la facture ni
le règlement n'est annulé, un règlement déjà affecté à une autre facture est
refusé ; **idempotent** ; `customer_payments.invoice_id` **écrit** ; **lien**
`link_documents` (`paid_by`). Éprouvé : suite `497` **14/14** ; G2 **67 constats,
0 au registre** ; G8 / `check_tenant_guard` / `check_anon_grants` **OK** ;
rejouable ; enrôlée dans `ci.yml` (G5).

**⏸️ L'avoir (`498_chain_l16_facture_avoir`) est DIFFÉRÉ — numéro rendu.** Le
maillon est simple (effet `sale.invoice.to_credit_note`, lien `reversed_by`), mais
la **suite** se heurte aux gardes de validation : `credit_note_guard` (213) impose
« un avoir est créé en brouillon **puis validé** », et refuse de rattacher une
facture dont `validation_status <> 'validated'` ; or `invoice_guard` (190) refuse
de valider une facture **sans ligne**. Tester l'avoir proprement demande donc de
construire facture + lignes + validation + avoir + validation — un harnais à part.
Plutôt qu'un lot fragile, le numéro **`498` est rendu** (`migration-numero.mjs
rendre`) et le tronçon restait au reste d'A3.2. **↳ Fermé le 06/10/2026 : le harnais monté pour les lots 753 et 754 l'a livré — voir §A3.2 lot 9.** Le journal le
dit : c'est un report décidé, pas un oubli.

## A3.2 — lot 5 : la réception rattachée à la commande d'achat (migration `498`)

**Le miroir achats du lot 2**, dans la famille **Stock/Achats** (« besoin (MRP) ↔
proposition ↔ commande ↔ réception ↔ stock », §B.3). Mesuré avant d'écrire :
`goods_receipts.purchase_order_id` **existait** et **personne ne l'écrivait** ;
`purchase_orders` **n'était pas au registre** `chain_document_types` (un lien vers
une commande d'achat aurait été **REFUSÉ** par la garde d'existence `451`).

**Ce qui est livré** — migration `498_chain_l16_reception_commande.sql` : le type
`purchase_orders` **entre au registre**, le contrat d'effet
`purchase.order.to_receipt` est déclaré, et le maillon `chain_l16_receipt_order`
rattache la réception à la commande (même fournisseur, statuts valides,
**idempotent**, écrit `goods_receipts.purchase_order_id`, lien `delivered_by`).

**Éprouvé** — suite `498` **14/14** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 quatre refus (commande brouillon / commande annulée /
réception annulée / autre fournisseur — 4), T04 frise (2), T05 isolation (3).
Portes : G2 **OK** ; G8 **15 maillons** (7 tracés + 8 écartés) **OK** ;
`check_tenant_guard` (488 SECURITY DEFINER, 0 sans société) **OK** ;
`check_anon_grants` **OK** ; rejouable ; enrôlée dans `ci.yml` (G5).

**Reste de la famille Stock/Achats** : MRP → proposition, proposition → commande,
réception → stock → CUMP → écriture, lot ↔ traçabilité ↔ rappel ; côté achats :
réception → facture fournisseur (partiellement chez B), règlement fournisseur
(`paid_by`).

## A3.2 — lot 6 : l'ordre de paiement rattaché à son virement (migration `499`)

**La famille Trésorerie** — « prévision ↔ échéancier ↔ **ordre de paiement ↔
virement** ↔ relevé ↔ rapprochement » (§B.3). Mesuré avant d'écrire :
`payment_orders` est **réel** (l'écran `PaymentOrdersPage` l'écrit, le tableau de
bord lit `draft/approved` comme engagements à venir) mais **absent du registre**
`chain_document_types` ; aucun contrat d'effet ; le « virement » = le **règlement
enregistré** (`supplier_payments` **ou** `customer_payments`).

**Ce qui est livré** — migration `499_chain_l16_ordre_virement.sql` : le type
`payment_orders` **entre au registre**, le contrat d'effet
`treasury.order.to_payment`, et le maillon `chain_l16_order_payment` — il
**retrouve** le règlement dans `supplier_payments` **ou** `customer_payments` (le
type du tiers décide de la table), vérifie la **cohérence** (même compte bancaire,
montant du virement ≤ montant de l'ordre), **marque l'ordre `executed`** (le
statut que personne ne posait) et **trace** le lien (`paid_by`).

**Éprouvé** — suite `499` **16/16** sur base neuve : T01 nominal achat (3), T02
nominal vente / auto-détection (2), T03 idempotence (2), T04 quatre refus (annulé
/ déjà exécuté / virement introuvable / virement > ordre — 4), T05 frise (2), T06
isolation (3). Portes : G2 **65 constats, 0 au registre** ; G8 **15 maillons**
**OK** ; `check_tenant_guard` / `check_anon_grants` **OK** ; rejouable ; enrôlée
dans `ci.yml` (G5).

**⚠️ Plage A3 SATURÉE** : `499` est le **dernier** numéro de la plage A3
(`493 → 499`). A3 doit **demander une extension de plage à l'intégration** avant
le prochain maillon — le registre fait foi (R2).

**Reste de la famille Trésorerie** : prévision ↔ échéancier, virement → relevé
(`bank_transactions`), relevé → rapprochement ; virement interne muet (`R-050`).

## A3.2 — lot 7 : la proposition (MRP) rattachée à la commande d'achat (migration `751`)

**Le tronçon amont du lot 5**, dans la famille **Stock/Achats** — « besoin (MRP)
↔ **proposition ↔ commande** ↔ réception ↔ stock » (§B.3). Mesuré avant d'écrire :
`mrp_proposals` **existait** (le MRP la remplit : `run_mrp`, `proposal_type`,
`status`, `supplier_id`) mais **absente du registre** `chain_document_types` ;
aucun contrat d'effet.

**Ce qui est livré** — migration `751_chain_l16_proposition_commande.sql` : le type
`mrp_proposals` **entre au registre**, le contrat d'effet
`purchase.proposal.to_order`, et le maillon `chain_l16_proposal_order` — seule une
proposition d'**achat** devient une commande d'**achat** (une proposition de
fabrication va vers un OF — refusée ici), même fournisseur, statuts valides,
**idempotent**, **marque la proposition `converted`**, **trace** le lien
(`created_from`).

**Éprouvé** — suite `751` **15/15** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 **cinq** refus (rejetée / déjà convertie / fabrication /
commande annulée / autre fournisseur — 5), T04 frise (2), T05 isolation (3).
Portes : G2 **67 constats, 0 au registre** ; G8 **OK** ; `check_tenant_guard` /
`check_anon_grants` **OK** ; rejouable ; enrôlée dans `ci.yml` (G5).

**Reste de la famille Stock** : proposition → OF (fabrication), réception → stock
→ CUMP → écriture, lot ↔ traçabilité ↔ rappel.

*Plage utilisée : `750 → 759` « plan6 A3 L16 (familles restantes) », inscrite pour
les familles restantes d'A3 après saturation de `493 → 499` (le registre fait foi).*

## A3.3 — L23-b : le moteur d'automatisations (migration `752`)

**L23** (plan du 24/09, I-06) = « journal unique + **automatisations** + webhooks
branchés sur les MÊMES événements ». La tranche 1 (`415`) a livré le **journal**
et le pont **webhooks**. **L23-b = les automatisations.**

**Ce que la mesure a trouvé.** Aucune table de règles d'automatisation ; aucun
moteur n'écoute `domain_events` pour autre chose que les webhooks.

**Ce qui est livré** — migration `752_chain_l23_automatisations.sql` :

- `automation_actions` — le **catalogue FERMÉ** des actions (clé étrangère :
  jamais un nom de fonction venu d'une donnée) ;
- `automation_rules` — les règles de la société (`event_name` + `action_code` +
  `params` + `active`, RLS **forcée**) ;
- `automation_runs` — **l'idempotence structurelle et la trace** :
  `UNIQUE (tenant, règle, événement)` ;
- `chain_l23_automatiser(event_id)` — le **moteur** : lit l'événement, joue
  chaque règle ACTIVE de sa société, trace (`executed` / `skipped` / `failed`) ;
- `zz_l23_automatiser` — déclencheur `AFTER INSERT` sur `domain_events` : le
  même point que le pont de la `415`, personne ne peut oublier d'appeler.

**Première action** (`chain.link`, **pilotée par la charge utile**) : poser un
lien amont→aval (`link_documents`) depuis l'agrégat de l'événement et les `params`
de la règle. Les actions métier nommées (« créer la commande », « notifier »)
s'inscrivent au même catalogue.

**Éprouvé** — suite `752` **10/10** sur base neuve : T01 nominal (déclenchement +
lien + trace `executed`, 2), T02 idempotence (rejeu : `rules_run = 0`, un seul
lien, une seule trace, 3), T03 `skipped` (paramètres incomplets, 2), T04 `failed`
(uuid invalide → `SQLERRM` tracée, la transaction métier survit, 1), T05 isolation
(l'événement de B ne joue pas la règle de A, 2). Portes : G2 / G8 /
`check_tenant_guard` / `check_anon_grants` / `check_composite_fks` **OK** ;
**`check_forced_rls_writers` : plafond relevé `318 → 320`** dans le même commit
(deux tables NEUVES, RLS forcée dès la création — la doctrine §3.5, pas une
exposition) ; rejouable ; enrôlée dans `ci.yml` (G5).

**Reste d'A3.3** : **L23-c** (lecture écran des automatisations), **L24**
(explicabilité I-09/I-11/I-12).

⚠️ **Limite dite** : le moteur joue des effets **nommés par la donnée** (les
`params` d'une règle). Or la porte **G2** lit les effets **LITTÉRAUX** du code :
un effet non déclaré posé par une règle ne serait refusé par personne. Sujet à
porter (catalogue d'effets par action, ou contrôle à l'exécution) — c'est le prix
d'un moteur de règles, et il est écrit ici plutôt que tu.

## A3.2 — lot 8 : le règlement rattaché à la facture fournisseur (migration `753`)

**Le miroir fournisseur du lot 4** (facture client → règlement), dans la famille
**Achats** — « commande ↔ réception ↔ **facture ↔ règlement** » (§B.3). Mesuré
avant d'écrire : `supplier_payments.purchase_invoice_id` et `invoice_number`
**existaient** et **personne ne les écrivait**.

**Ce qui est livré** — migration `753_chain_l16_reglement_fournisseur.sql` :
contrat d'effet `purchase.invoice.to_payment` + maillon
`chain_l16_supplier_invoice_payment` — même fournisseur, ni la facture ni le
règlement n'est annulé, un règlement déjà affecté est refusé ; **idempotent** ;
`supplier_payments.purchase_invoice_id` **écrit** ; **lien** `link_documents`
(`paid_by`).

**Éprouvé** — suite `753` **14/14** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 quatre refus (4), T04 frise (2), T05 isolation (3).

**Harnais assumé** : la suite monte une **facture fournisseur approuvée** (helper
`_mk_approved_pi` — saisie `pending`, une ligne, puis approbation), parce que les
gardes l'exigent : `192` (une facture fournisseur se saisit puis s'approuve) et
`354` (**un règlement exige une facture approuvée**). C'est le même genre de
harnais que celui que l'**avoir** réclame (cf. lot 4) — ici, il a été monté.

Portes : G2 **67 constats, 0 au registre** ; G8 / `check_tenant_guard` /
`check_anon_grants` **OK** ; rejouable ; enrôlée dans `ci.yml` (G5).

**Reste de la famille Achats** : réception → facture fournisseur, avoir
fournisseur (`purchase_credit_notes`, même garde que l'avoir client).

## A3.2 — lot 9 : l'avoir rattaché à la facture (migration `754`) — le différé fermé

**Le tronçon qui avait été DIFFÉRÉ** (lot 4, numéro `498` rendu), dans la famille
**Commercial** — « facture ↔ **avoir** ↔ règlement ». La cause du report était le
**harnais** : `credit_note_guard` (213) impose « brouillon PUIS validé » et exige
la facture d'origine **validée** ; `invoice_guard` (190) refuse de valider une
facture **sans ligne**. Le harnais a été monté au lot `753` (facture fournisseur
approuvée) ; il sert ici — deux helpers (`_mk_validated_invoice`,
`_mk_validated_credit_note`).

**Ce qui est livré** — migration `754_chain_l16_facture_avoir.sql` : contrat
d'effet `sale.invoice.to_credit_note` + maillon `chain_l16_invoice_credit_note` —
l'avoir n'est pas un **brouillon**, même client, un avoir qui annule **déjà** une
autre facture est refusé ; **idempotent** ; **lien** `link_documents`
(`reversed_by`). Il **ne réécrit pas** `credit_notes.invoice_id` (posée par le
trigger `213`, et la garde refuse de modifier un avoir validé).

**⚠️ Décision mesurée** : le **statut de la facture n'est PAS un refus**. Un avoir
qui la crédite en entier la fait **légitimement** passer à `cancelled`
(`refresh_invoice_settlement`) — la première version refusait ce cas et **cassait
le geste normal** (mesuré : `FAC-2026-000001 déjà annulée`). Corrigé, et testé.

**Éprouvé** — suite `754` **14/14** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 quatre refus (avoir introuvable / brouillon / autre client /
déjà rattaché — 4), T04 frise (2), T05 isolation (3). Portes : G2 **67 constats,
0 au registre** ; G8 / `check_tenant_guard` / `check_anon_grants` **OK** ;
rejouable ; enrôlée dans `ci.yml` (G5).

**Reste de la famille Commercial** : relance, marge prévisionnelle.

## A3.2 — lot 10 : la réception rattachée à la facture fournisseur (migration `755`)

**Le tronçon qui complète la chaîne Achats** — « commande ↔ réception ↔ **facture**
↔ règlement » (§B.3). Mesuré avant d'écrire : `purchase_invoices.goods_receipt_id`
**existe**, et il est **LU par le rapprochement trois points**
(`check_three_way_match`, 135 puis 148) — mais **personne ne l'écrit** (aucun
`INSERT`/`UPDATE` de `app/sql` ne le pose). Le rapprochement tournait donc **à
vide**.

**Ce qui est livré** — migration `755_chain_l16_reception_facturefournisseur.sql` :
contrat d'effet `purchase.receipt.to_invoice` + maillon
`chain_l16_receipt_supplier_invoice` — même fournisseur, ni la réception ni la
facture n'est annulée, une facture déjà rattachée à une autre réception est
refusée ; **idempotent** ; **écrit** `goods_receipt_id` (ce qui **alimente le
rapprochement trois points**) ; **lien** `link_documents` (`invoiced_by`).

**Éprouvé** — suite `755` **14/14** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 quatre refus (4), T04 frise (2), T05 isolation (3). Les
factures sont saisies `pending` — on **rapproche avant d'approuver**, donc ce lot
n'a pas besoin du harnais d'approbation du lot 8. Portes : G2 / G8 /
`check_tenant_guard` / `check_anon_grants` **OK** ; rejouable ; enrôlée dans
`ci.yml` (G5).

**La chaîne Achats** : `commande → réception → facture → règlement`. Le dernier
tronçon (**avoir fournisseur**) est fermé au **lot 11** ; la famille Achats est
alors complète.

## A3.2 — lot 11 : l'avoir fournisseur rattaché à la facture (migration `756`)

**Le dernier tronçon de la famille Achats**, miroir du lot 9 (avoir client).
`purchase_credit_notes.purchase_invoice_id` **existe** et le trigger `192` l'utilise
pour valider (la facture d'origine doit être **approuvée**) — mais **aucun lien de
chaîne** n'est posé, et `purchase_credit_notes` **n'est pas au registre**
`chain_document_types` (un lien vers un avoir fournisseur aurait été **REFUSÉ**, 451).

**Ce qui est livré** — migration `756_chain_l16_avoir_fournisseur.sql` : le type
`purchase_credit_notes` **entre au registre**, le contrat d'effet
`purchase.invoice.to_credit_note`, et le maillon
`chain_l16_supplier_invoice_credit_note` — avoir non **brouillon**, même
fournisseur, un avoir qui annule **déjà** une autre facture est refusé ;
**idempotent** ; **lien** `link_documents` (`reversed_by`). Il **ne réécrit pas**
`purchase_invoice_id` (posée par le trigger `192`, qui refuse de modifier un avoir
validé). Même décision qu'au lot 9 : **le statut de la facture n'est pas un refus**
(un avoir entier la fait légitimement passer à `cancelled`).

**Éprouvé** — suite `756` **14/14** sur base neuve (harnais `_mk_approved_pi` +
`_mk_validated_pcn`). Portes : G2 / G8 / `check_tenant_guard` / `check_anon_grants`
**OK** ; rejouable ; enrôlée dans `ci.yml` (G5).

**Les chaînes Commercial ET Achats sont désormais complètes de bout en bout** :
`devis → commande → livraison → facture → avoir / règlement` et
`commande → réception → facture → avoir / règlement`.

## A3.2 — lot 12 : la relance rattachée à la facture (migration `757`)

**Le dernier tronçon de la famille Commercial** — « facture ↔ avoir ↔ règlement ↔
**relance** » (§B.3). Mesuré avant d'écrire : `collection_reminders` **existe**
(réparée par W6 / `258`) et `collection_reminders.invoice_id` **existe** — mais
**aucun lien de chaîne** n'est posé (`258` n'appelle aucun `link_documents`) : la
relance d'une facture est **invisible pour la frise**. Et `collection_reminders`
**n'est pas au registre** `chain_document_types`.

**Ce qui est livré** — migration `757_chain_l16_relance.sql` :
`collection_reminders` **entre au registre**, contrat d'effet
`sale.invoice.to_reminder`, maillon `chain_l16_invoice_reminder` — relance non
**brouillon**/annulée, même client, une relance déjà portée par une autre facture
est refusée ; **idempotent** ; **écrit** `invoice_id` **si vide** ; **lien**
`link_documents` (`created_from`).

**Éprouvé** — suite `757` **15/15** sur base neuve : T01 nominal (3), T02
idempotence (2), T03 **cinq** refus (introuvable / brouillon / annulée / autre
client / déjà portée — 5), T04 frise (2), T05 isolation (3). Portes : G2 / G8 /
`check_tenant_guard` / `check_anon_grants` **OK** ; rejouable ; enrôlée dans
`ci.yml` (G5).

**Les familles tenues par A3 sont désormais complètes de bout en bout** :
`devis → commande → livraison → facture → avoir / règlement / relance` (Commercial),
`commande → réception → facture → avoir / règlement` (Achats),
`proposition → commande → réception` (Stock) et `ordre de paiement → virement`
(Trésorerie).

## A3.2 — lot 13 : le groupe de lettrage et ses lignes de journal (migration `758`)

**La famille Comptabilité** (« lettrage ↔ âge de la dette ↔ relance ↔ provision ↔
écriture de clôture », §B.3) — et surtout **la demande R3 d'A1 restée ouverte** :
« bâtir le lien `lettrage_groups` ↔ `journal_lines` » (pour INV-07).

**Ce que la mesure a trouvé.** `lettrage_groups` existe (124 / 187) et
`journal_lines.lettrage_group_id` existe — mais **aucun lien de chaîne** n'est posé
et `lettrage_groups` **n'est pas au registre** : un lettrage était **invisible pour
la frise**.

**Ce qui est livré** — migration `758_chain_l16_lettrage_groupes.sql` :
`lettrage_groups` **entre au registre**, contrat d'effet `rev.line.lettered`, maillon
`chain_l16_lettrage_group` — il trace **CHAQUE ligne de journal** du groupe vers ce
groupe (`link_documents`, `created_from`).

**⚠️ Le sens est LIGNE → GROUPE, et c'est MESURÉ.** `link_documents` **fusionne deux
liens de même amont** (« met à jour son aval au lieu d'empiler », la leçon de la
`401`) : avec le groupe pour amont, les N lignes ne tenaient qu'**UN** lien — mesuré
(`liens actifs = 1` pour 2 lignes). Chaque ligne est donc l'amont de son propre lien
(N liens tiennent, idempotence structurelle).

**Éprouvé** — suite `758` **12/12** sur base neuve : T01 nominal (2), T02 idempotence
structurelle (2), T03 trois refus (introuvable / annulé / sans ligne), T04 frise dans
les deux sens (2), T05 isolation (3). Portes : G2 / G8 / `check_tenant_guard` /
`check_anon_grants` **OK** ; rejouable ; enrôlée dans `ci.yml` (G5).

**Reste de la Comptabilité** : la **FK composite** `journal_lines → lettrage_groups`
(doctrine 237, touche `journal_lines` — territoire C) ; provision → écriture de
clôture ; à-nouveaux ; état de rapprochement.

## A3.2 — lot 14 : le bulletin de paie rattaché à son écriture (migration `759`)

**La famille RH/Paie** — le « maillon faible » du référentiel (§B.3) : « contrat ↔
salarié ↔ absence ↔ temps ↔ variable ↔ **bulletin** ↔ cumuls ↔ **écriture** ↔
virement ↔ DSN ».

**Ce que la mesure a trouvé.** `pay_slips.journal_entry_id` et `journal_posted`
**existent** et sont **écrits** par la comptabilisation de la paie
(`191_payroll_to_ledger`, ligne 207) — mais **aucun lien de chaîne** n'est posé :
l'écriture d'un bulletin est **invisible pour la frise**. Et `pay_slips` **n'est pas
au registre** `chain_document_types`.

**Ce qui est livré** — migration `759_chain_l16_bulletin_ecriture.sql` :
`pay_slips` **entre au registre**, contrat d'effet `payroll.slip.posted`, maillon
`chain_l16_payslip_entry` — bulletin non annulé et **comptabilisé** (refusé sinon :
on ne trace pas une écriture qui n'existe pas), lien `link_documents`
(`generated_entry`). Il **ne réécrit pas** `journal_entry_id` (posée par la
comptabilisation `191`).

**Éprouvé** — suite `759` **12/12** sur base neuve : T01 nominal (2), T02 idempotence
(2), T03 trois refus (introuvable / annulé / non comptabilisé), T04 frise (2), T05
isolation (3). Portes : G2 / G8 / `check_tenant_guard` / `check_anon_grants` **OK** ;
rejouable ; enrôlée dans `ci.yml` (G5).

**⚠️ Plage A3 SATURÉE** : `759` est le **dernier** numéro de la plage `750 → 759`.
A3 doit **demander une extension à l'intégration** avant le prochain maillon — le
registre fait foi (R2).

**Reste de la RH/Paie** : contrat ↔ salarié, absence (**les quatre sources** qui ne
convergent pas), temps, variable ↔ bulletin, cumuls, virement (`sepa_payment_orders`,
≡ INV-09), DSN.

## A3.2 — lot 15 : l'exercice clos rattaché à son écriture d'affectation (migration `760`)

**La famille Comptabilité, suite du lot 13** — « provision pour dépréciation ↔
**écriture de clôture** » (§B.3). **Première migration de la nouvelle plage A3
`760 → 769`**, inscrite au registre le 06/10 après saturation de `750 → 759`.

**Ce que la mesure a trouvé.** `fiscal_years.result_allocation_entry_id` **existe**
(posée par `189`) et est **écrit** par la clôture (`189`, ligne 672) — mais **aucun
lien de chaîne** n'est posé : l'écriture d'affectation d'un exercice est **invisible
pour la frise**. Et `fiscal_years` **n'est pas au registre** `chain_document_types`.

**Ce qui est livré** — migration `760_chain_l16_cloture_resultat.sql` :
`fiscal_years` **entre au registre**, contrat d'effet
`rev.fiscal_year.result_allocated`, maillon `chain_l16_fiscal_year_result` —
exercice **clos** et au résultat **affecté** (refusé sinon), lien `link_documents`
(`generated_entry`). Il **ne réécrit pas** `result_allocation_entry_id` (posée par la
clôture `189`).

**Éprouvé** — suite `760` **12/12** sur base neuve : T01 nominal (2), T02 idempotence
(2), T03 trois refus (introuvable / ouvert / non affecté), T04 frise (2), T05
isolation (3). Portes : G2 / G8 / `check_tenant_guard` / `check_anon_grants` **OK** ;
rejouable ; enrôlée dans `ci.yml` (G5).

**Régistration de plage** : `760 → 769` inscrite au registre **et** dans `AGENTS.md`
+ `doc/audit/NUMEROTATION-MIGRATIONS.md`, **dans ce commit** (la règle de l'outil).

**Reste de la Comptabilité** : provision pour dépréciation → écriture ; à-nouveaux ;
état de rapprochement ; la **FK composite** `journal_lines → lettrage_groups`
(doctrine 237, territoire C).

## Demandes reçues (R3) — transmises par l'intégration du 05/10/2026

| # | Demande | De | Ce qu'elle débloque |
|---|---|---|---|
| 1 | Bâtir le **lien `lettrage_groups` ↔ `journal_lines`** (pour **INV-07**) | A1 — invariant **INV-07** | **Mesure du 05/10** : `journal_lines.lettrage_group_id` **existe déjà** (124) mais **sans clé étrangère** — un premier tronçon possible (FK composite, doctrine 237). Mais INV-07 lui-même (« le lettrage = la TVA sur encaissements ») est le **lettrage génératif** d'**L21**, **bloqué par L20-tranche 2**. **↳ Livré le 06/10/2026 (`758`)** : le lien de **chaîne** est posé — `journal_lines → lettrage_groups`, effet `rev.line.lettered` — un groupe de lettrage est désormais lisible par la frise. Reste la **FK composite** (doctrine 237), qui touche `journal_lines` (territoire C) |

## A3.4 — P1 : l'attestation d'intégrité technique (le SQL, migration `770`)

**Le lot est débloqué** (décisions du §6 bis + dossier expert-comptable, lot A1)
et sa **plage `770` → `779`** est inscrite au registre
(`plan6 A3 (certificat d'integrite, A3.4)`).

`public.chain_certificat_integrite(p_tenant)` (`770`) rend un **`jsonb` de
FAITS** — jamais de prose (le vocabulaire vit à l'écran, pour l'i18n) :

| Champ | Source | Règle tenue |
|---|---|---|
| `emis_le` · `version_migrations` · `nb_migrations` | `now()`, `sql_migrations_tracker` | **quelle** base atteste |
| `invariants` | `chain_invariant_results`, dernier relevé par code | un code **sans relevé** est `non_mesure`, **jamais `tenu`** |
| `ecarts` | les `rompu`, **nommés** (code, libellé, écart, lignes en écart) | **on publie ses écarts** — le différenciateur |
| `banc` | `chain_banc_resultats`, dernier verdict par `(maillon, épreuve)` | `non_joue` **compté et visible** ; le dénominateur `maillons × 8` publié à part |
| `nf525` | `verify_nf525_chain()` (déjà `jsonb`) | **`sans_objet`** si la chaîne est **vide** — « une absence de preuve n'est pas une preuve » |

**Ce que la fonction ne fait pas** : elle **n'écrit rien**, **ne recalcule aucun
solde**, **n'invente aucun `tenu`** ; elle **n'atteste que sa propre société**
(`p_tenant` ≠ `current_tenant_id()` → **refus `42501`**).

**Preuve** — suite `770`, **7/7** sur base neuve : la forme · « aucun `tenu` sans
relevé » (0 tenu / 20 non mesurés) · l'écart nommé · le banc (4 tenues / 2
rompues / 2 non jouées, `maillons = 7`) · `sans_objet` · **lecture pure** (deux
appels identiques, `document_links` inchangé) · **garde de société** (`42501`).
Enrôlée dans `ci.yml` sous `plan6:a3`.

**DEMANDE (R3) — la plage, dans les documents.** L'intégration doit inscrire
`770` → `779` dans `AGENTS.md` **et** `NUMEROTATION-MIGRATIONS.md` (R4 : ces
fichiers ne s'écrivent que par elle) — le **registre machine** la connaît déjà.

**Ce qui reste pour P1** : l'**écran** (A2) — page 1 dirigeant / annexe
vérifiable, la mention légale, « qui signe » ; et le **PDF** (D-4, hors P1). Le
contrat de la fonction et le plan d'écran sont dans
`doc/audit/PREPARATION-P1-CERTIFICAT-INTEGRITE-2026-10-05.md` (lot **A1**).

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A3.1 | Recomptage L16 → L22 : `415` → `422` inventoriés (L17 livré, L18/L19/L20/L23 en tranche 1, L16/L21/L22 ouverts) ; 421 libre, 419 sans suite | — (lecture seule) | `ea722d2` |
| 2026-10-05 | A3.2 (lot 1) | **L16 · devis accepté → commande** : migration `493` (type `quotes` au registre, contrat `sale.quote.to_order`, maillon `convert_quote_to_order` — prix gelé, idempotent, réversible, tracé) + suite `493` enrôlée dans `ci.yml` | suite **19/19** sur base neuve (333 migrations) · G2 **0 effet non déclaré** · `493` rejouable | `fa9ccb7` |
| 2026-10-05 | A3.2 (lot 2) | **L16 · commande → livraison** : migration `494` (contrat `sale.order.to_delivery`, maillon `chain_l16_order_deliver` — cohérence client/statut, idempotent, écrit `delivery_notes.sales_order_id`, lien `delivered_by`) + suite `494` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 63 constats **0 au registre** · G8/tenant/anon/forced-RLS **OK** · `494` rejouable · G5 **152/152** | `010db14` |
| 2026-10-05 | A3.2 (lot 3) | **L16 · livraison → facture** : migration `495` (contrat `sale.delivery.to_invoice`, maillon `chain_l16_delivery_invoice` — cohérence client/statut, idempotent, écrit `invoices.delivery_note_id`, lien `invoiced_by`) + suite `495` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 64 constats **0 au registre** · G8/tenant/anon **OK** · `495` rejouable · G5 **153/153** | `e396ff6` |
| 2026-10-05 | A3.2 (lot 4) | **L16 · facture → règlement** : migration `497` (contrat `sale.invoice.to_payment`, maillon `chain_l16_invoice_payment` — cohérence client/statut, idempotent, écrit `customer_payments.invoice_id`, lien `paid_by`) + suite `497` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 67 constats **0 au registre** · G8/tenant/anon **OK** · `497` rejouable | _(ce lot)_ |
| 2026-10-05 | A3.2 (lot 4) | **Avoir (`498`) DIFFÉRÉ, numéro rendu** : la suite se heurte aux gardes de validation (avoir brouillon→validé ; facture validée sans ligne interdite) — harnais dédié requis. Le tronçon reste au reste d'A3.2 | — (report décidé) | — |
| 2026-10-06 | A3.2 (lot 5) | **L16 · Achats · commande d'achat → réception** : migration `498` (`purchase_orders` au registre, contrat `purchase.order.to_receipt`, maillon `chain_l16_receipt_order` — cohérence fournisseur/statut, idempotent, écrit `goods_receipts.purchase_order_id`, lien `delivered_by`) + suite `498` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 **OK** · G8 15 maillons **OK** · tenant/anon **OK** · rejouable | `61f0ee7` |
| 2026-10-06 | A3.2 (lot 6) | **L16 · Trésorerie · ordre de paiement → virement** : migration `499` (`payment_orders` au registre, contrat `treasury.order.to_payment`, maillon `chain_l16_order_payment` — auto-détection achat/vente, cohérence compte/montant, marque l'ordre `executed`, lien `paid_by`) + suite `499` enrôlée dans `ci.yml` | suite **16/16** sur base neuve · G2 65 constats **0 au registre** · G8/tenant/anon **OK** · rejouable | `560477c` |
| 2026-10-06 | A3.2 (lot 7) | **L16 · Stock · proposition (MRP) → commande d'achat** : migration `751` (`mrp_proposals` au registre, contrat `purchase.proposal.to_order`, maillon `chain_l16_proposal_order` — type `purchase` seul, même fournisseur, marque la proposition `converted`, lien `created_from`) + suite `751` enrôlée dans `ci.yml` | suite **15/15** sur base neuve · G2 67 constats **0 au registre** · G8/tenant/anon **OK** · rejouable | `4bc9567` |
| 2026-10-06 | A3.3 (L23-b) | **L23-b · le MOTEUR D'AUTOMATISATIONS** : migration `752` (`automation_actions` catalogue fermé, `automation_rules`, `automation_runs` — idempotence `(tenant, règle, événement)`, moteur `chain_l23_automatiser`, déclencheur `zz_l23_automatiser` sur `domain_events`) + suite `752` enrôlée dans `ci.yml` | suite **10/10** sur base neuve · G2/G8/tenant/anon/composite-FK **OK** · **plafond FORCE RLS 318→320 inscrit** · rejouable | `fd9a11b` |
| 2026-10-11 | A3.2 (lot 8) | **L16 · Achats · facture fournisseur → règlement** : migration `753` (contrat `purchase.invoice.to_payment`, maillon `chain_l16_supplier_invoice_payment` — même fournisseur, statuts valides, idempotent, écrit `supplier_payments.purchase_invoice_id`, lien `paid_by`) + suite `753` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 67 constats **0 au registre** · G8/tenant/anon **OK** · rejouable | `94cbc84` |
| 2026-10-11 | A3.2 (lot 9) | **L16 · Commercial · facture → avoir** — le **DIFFÉRÉ fermé** : migration `754` (contrat `sale.invoice.to_credit_note`, maillon `chain_l16_invoice_credit_note` — avoir non brouillon, même client, ne réécrit pas `invoice_id`, lien `reversed_by`). **Décision mesurée** : le statut de la facture n'est PAS un refus (un avoir entier la passe légitimement à `cancelled`) — la 1ʳᵉ version le refusait et cassait le geste normal. Harnais `_mk_validated_invoice` / `_mk_validated_credit_note`. + suite `754` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2 67 constats **0 au registre** · G8/tenant/anon **OK** · rejouable | `06f8975` |
| 2026-10-11 | A3.2 (lot 10) | **L16 · Achats · réception → facture fournisseur** : migration `755` (contrat `purchase.receipt.to_invoice`, maillon `chain_l16_receipt_supplier_invoice` — même fournisseur, statuts valides, idempotent, **écrit `purchase_invoices.goods_receipt_id`** que le rapprochement trois points 135/148 lisait sans qu'on l'écrive, lien `invoiced_by`). La chaîne Achats `commande → réception → facture → règlement` est **fermée**. + suite `755` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2/G8/tenant/anon **OK** · rejouable | `48078ce` |
| 2026-10-11 | A3.2 (lot 11) | **L16 · Achats · facture fournisseur → avoir** : migration `756` (`purchase_credit_notes` au registre, contrat `purchase.invoice.to_credit_note`, maillon `chain_l16_supplier_invoice_credit_note` — avoir non brouillon, même fournisseur, ne réécrit pas `purchase_invoice_id`, lien `reversed_by`). **Dernier tronçon de la famille Achats** : Commercial **et** Achats sont désormais complets de bout en bout. + suite `756` enrôlée dans `ci.yml` | suite **14/14** sur base neuve · G2/G8/tenant/anon **OK** · rejouable | `60839c2` |
| 2026-10-11 | A3.2 (lot 12) | **L16 · Commercial · facture → relance** : migration `757` (`collection_reminders` au registre, contrat `sale.invoice.to_reminder`, maillon `chain_l16_invoice_reminder` — relance non brouillon/annulée, même client, écrit `invoice_id` si vide, lien `created_from`). **Dernier tronçon du Commercial** ; les familles tenues par A3 sont complètes de bout en bout. + suite `757` enrôlée dans `ci.yml` | suite **15/15** sur base neuve · G2/G8/tenant/anon **OK** · rejouable | `f31bde7` |
| 2026-10-11 | A3.2 (lot 13) | **L16 · Comptabilité · groupe de lettrage → ses lignes de journal** — la **demande R3 d'A1** : migration `758` (`lettrage_groups` au registre, contrat `rev.line.lettered`, maillon `chain_l16_lettrage_group` — trace chaque ligne vers son groupe). **Défaut mesuré et corrigé** : `link_documents` fusionne deux liens de même amont, donc le sens est LIGNE → GROUPE (avec le groupe pour amont, 2 lignes ne tenaient qu'1 lien). + suite `758` enrôlée dans `ci.yml` | suite **12/12** sur base neuve · G2/G8/tenant/anon **OK** · rejouable | `76e9199` |
| 2026-10-11 | A3.2 (lot 14) | **L16 · RH/Paie · bulletin → son écriture comptable** : migration `759` (`pay_slips` au registre, contrat `payroll.slip.posted`, maillon `chain_l16_payslip_entry` — bulletin comptabilisé requis, ne réécrit pas `journal_entry_id`, lien `generated_entry`). **⚠️ dernier numéro de la plage `750→759` : extension à demander.** + suite `759` enrôlée dans `ci.yml` | suite **12/12** sur base neuve · G2/G8/tenant/anon **OK** · rejouable | `467ee12` |
| 2026-10-11 | A3.4 (P1) | **P1 — le SQL** : migration `770` (`chain_certificat_integrite` → `jsonb` de FAITS : invariants / écarts nommés / banc (`non_joue` compris) / empreinte NF-525 ; **garde de société** ; **lecture pure** ; aucun « tenu » inventé). **Plage `770`→`779` inscrite** au registre. + suite `770` enrôlée dans `ci.yml` sous `plan6:a3` | suite **770 7/7** sur base neuve · SOC-06 **0 collision** (269 numéros) · suites **167/167 branchées** | _(ce lot)_ |
