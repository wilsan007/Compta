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
| A3.2 | L16 → L22 : chaînages internes, couples inter-modules vides, régénération d'écriture, lettrage génératif, moteur de règles | A.6 | plafond du plan | ⬜ |
| A3.3 | L23 (événements et webhooks unifiés, suite de la tranche 1) ; L24 (explicabilité, régularisation guidée) | A.7 | plafond du plan | ⬜ |
| A3.4 | P1 certificat d'intégrité, P3 audit de reprise, P2 banc sur données du prospect, puis P4, P5, P7, P8, P6 | A.8 (propositions P1 → P8) | ≈ 25 j | 🔴 **attend vos cinq décisions du §6 + l'expert-comptable référent** |

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

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A3.1 | Recomptage L16 → L22 : `415` → `422` inventoriés (L17 livré, L18/L19/L20/L23 en tranche 1, L16/L21/L22 ouverts) ; 421 libre, 419 sans suite | — (lecture seule) | _(ce lot)_ |
