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
| A3.2 | L16 → L22 : chaînages internes, couples inter-modules vides, régénération d'écriture, lettrage génératif, moteur de règles | A.6 | plafond du plan | 🟡 **1er maillon livré le 05/10** : L16 · devis accepté → commande (493), **19/19 verdicts** — voir §A3.2 lot 1 |
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

## Demandes reçues (R3) — transmises par l'intégration du 05/10/2026

| # | Demande | De | Ce qu'elle débloque |
|---|---|---|---|
| 1 | Bâtir le **lien `lettrage_groups` ↔ `journal_lines`** | A1 — invariant **INV-07** | rend **INV-07** mesurable (lien groupe de lettrage ↔ ligne de TVA). `lettrage_groups` n'a aujourd'hui **aucune clé** vers `journal_lines` ; c'est le **lettrage génératif** d'**L21** (reste d'A3.2), qui attend **L20-tranche 2** pour être jouable |

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A3.1 | Recomptage L16 → L22 : `415` → `422` inventoriés (L17 livré, L18/L19/L20/L23 en tranche 1, L16/L21/L22 ouverts) ; 421 libre, 419 sans suite | — (lecture seule) | `ea722d2` |
| 2026-10-05 | A3.2 (lot 1) | **L16 · devis accepté → commande** : migration `493` (type `quotes` au registre, contrat `sale.quote.to_order`, maillon `convert_quote_to_order` — prix gelé, idempotent, réversible, tracé) + suite `493` enrôlée dans `ci.yml` | suite **19/19** sur base neuve (333 migrations) · G2 **0 effet non déclaré** · `493` rejouable | _(ce lot)_ |
