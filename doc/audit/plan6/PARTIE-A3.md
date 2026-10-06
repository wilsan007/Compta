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
| A3.2 | L16 → L22 : chaînages internes, couples inter-modules vides, régénération d'écriture, lettrage génératif, moteur de règles | A.6 | plafond du plan | 🟡 **7 maillons livrés** : L16 **Commercial** — devis → commande (`493`, **19/19**), commande → livraison (`494`, **14/14**), livraison → facture (`495`, **14/14**), facture → règlement (`497`, **14/14**) ; L16 **Achats** — commande d'achat → réception (`498`, **14/14**) ; L16 **Trésorerie** — ordre de paiement → virement (`499`, **16/16**) ; L16 **Stock** — proposition MRP → commande d'achat (`751`, **15/15**) — voir §A3.2 lots 1 à 7 ; l'**avoir** est différé (cf. lot 4) |
| A3.3 | L23 (événements et webhooks unifiés, suite de la tranche 1) ; L24 (explicabilité, régularisation guidée) | A.7 | plafond du plan | ⬜ |
| A3.4 | P1 certificat d'intégrité, P3 audit de reprise, P2 banc sur données du prospect, puis P4, P5, P7, P8, P6 | A.8 (propositions P1 → P8) | ≈ 25 j | 🟢 **débloqué le 05/10** — les cinq questions du §6 sont **tranchées** et l'expert-comptable référent est **désigné** (dossier `doc/validation-expert-comptable/DOSSIER-EXPERT-COMPTABLE-2026-10-05.md`, lot A1) ; ordre d'exécution : P1 → P3 → P2 → P4 → P5 → P7 → P8 → P6 |

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
rendre`) et le tronçon reste **au reste d'A3.2** (voir plus bas). Le journal le
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

## Demandes reçues (R3) — transmises par l'intégration du 05/10/2026

| # | Demande | De | Ce qu'elle débloque |
|---|---|---|---|
| 1 | Bâtir le **lien `lettrage_groups` ↔ `journal_lines`** (pour **INV-07**) | A1 — invariant **INV-07** | **Mesure du 05/10** : `journal_lines.lettrage_group_id` **existe déjà** (124) mais **sans clé étrangère** — un premier tronçon possible (FK composite, doctrine 237). Mais INV-07 lui-même (« le lettrage = la TVA sur encaissements ») est le **lettrage génératif** d'**L21**, **bloqué par L20-tranche 2** |

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
| 2026-10-06 | A3.2 (lot 7) | **L16 · Stock · proposition (MRP) → commande d'achat** : migration `751` (`mrp_proposals` au registre, contrat `purchase.proposal.to_order`, maillon `chain_l16_proposal_order` — type `purchase` seul, même fournisseur, marque la proposition `converted`, lien `created_from`) + suite `751` enrôlée dans `ci.yml` | suite **15/15** sur base neuve · G2 67 constats **0 au registre** · G8/tenant/anon **OK** · rejouable | _(ce lot)_ |
