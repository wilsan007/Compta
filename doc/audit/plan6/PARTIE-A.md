# Partie A — chaînages et preuve

> Fichier de suivi **exclusif** de la partie A (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/a-chainages` |
| **Worktree** | `.claude/worktrees/plan6-a-chainages` |
| **Plage de migrations** | `475` → `499` (⚠️ et non `423`→`499` comme l'écrit le §2 du plan — voir « La plage, en fait » ci-dessous) |
| **Territoire de fichiers** | `app/sql/*chain*`, `app/sql/*metric*`, `app/sql/ci/check_chain*`, `app/sql/ci/check_effects*` ; écrans et requêtes « chaîne », « cohérence », « pilotage » |
| **Charge** | ≈ 60 j (A.1 → A.7) + ≈ 25 j (A.8) |
| **Départ possible** | tout de suite |
| **Décisions bloquantes** | aucune avant A.8 |

## Rappel des règles qui s'appliquent (R1 → R8)

- **R1** — je travaille **dans le worktree**, jamais dans le dossier principal (réservé à l'intégration).
- **R2** — un numéro se prend par `npm run migration:prendre`, **jamais à la main**.
- **R3** — hors de mon territoire, je **n'édite pas** : je consigne la demande dans **ce fichier**, l'intégration la transmet.
- **R5** — mes suites CI vont **sous mon marqueur** `# --- plan6:a ---` dans `ci.yml`, et nulle part ailleurs.
- **R6** — je ne fusionne pas les fichiers générés ; je **signale** que l'intégration doit les régénérer.
- **R7** — une fonction SQL, un propriétaire : avant un `CREATE OR REPLACE` d'une fonction **existante**, vérifier les autres branches `plan6/*`.
- **R8** — je pousse des lots courts (1 à 3 jours) et je ne fusionne pas dans `main` moi-même.

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| A.1 | Recompter L3 : maillons RPC tracés, épreuves D1 → D8 réellement jouées par `433`/`434`/`436`, rapport par maillon | 3.1, 3.4 → 3.7 | 1 j | 🟡 **compté le 05/10** — voir le rapport A.1 |
| A.2 | Relevé bancaire manuel et maillons RPC restants | 3.3 | 2 j | ⬜ |
| A.3 | Les 6 invariants « non mesurables » ; relevé nocturne et alerte (`414`) ; invariants lus par l'écran | 3.8 → 3.10 | 4 j | ⬜ **le décompte dit 3, pas 6** |
| A.4 | Pages « Robustesse » et « Cohérence » | L5, 4.1/4.2 | 3 j | ⬜ |
| A.5 | Vue Chaîne : finir ce que `460` → `467` ont amorcé | L6, I-01 | à recompter | ⬜ |
| A.6 | L16 → L22 : chaînages internes, couples inter-modules, régénération, lettrage, moteur de règles — reprendre après `415` → `422` | L16 → L22 | plafond du plan | ⬜ |
| A.7 | L23 (événements et webhooks unifiés, suite de la tranche 1) et L24 (explicabilité, régularisation guidée) | L23, L24 | plafond du plan | ⬜ |
| A.8 | P1 certificat d'intégrité, P3 audit de reprise, P2 banc sur données du prospect, puis P4, P5, P7, P8, P6 | propositions P1 → P8 | ≈ 25 j | ⬜ |

## A.1 — le recomptage, mesuré le 05/10/2026

Base neuve (PostgreSQL 16, `postgres:16`, 333 migrations appliquées), après la
réunion des sept commits du 05/10. **Pas de « presque vide » : la partie 3 a
beaucoup avancé**, et le suivi est en retard, pas la base.

### Les maillons déclarés : 7

`chain_banc_maillons` porte **7 maillons actifs** :

| Maillon | Libellé | Éprouvé par le banc ? |
|---|---|---|
| `releve.comptabilise` | Comptabilisation d'une ligne de relevé | ✅ `436` |
| `releve.delettrage` | Dé-lettrage (ferme le lien, ne produit rien) | ✅ `436` |
| `releve.pointage` | Pointage manuel d'une ligne de relevé | ✅ `436` |
| `caisse.ticket` | Ticket de caisse (encaissement atomique) | ✅ `436` |
| `caisse.avoir` | Avoir de caisse (avec retour de stock) | ✅ `436` |
| `paie.comptabilisee` | Comptabilisation du bulletin de paie | ✅ `430` |
| `paie.versement` | Versement (net, social, taxe, acomptes) | ✅ `430` |

**7 maillons déclarés, 7 maillons couverts** — chacun par une suite
rouge-avant. C'est le point le plus important du recomptage : la ligne
« 0 chaînage éprouvé sur 62 » du suivi **ne vaut plus**. Le 62 comptait les
chaînages **déclarés** dans le socle L1 ; le banc n'en éprouve que 7, mais ce
sont les 7 qui portent l'écriture comptable.

### Les épreuves D1 → D8 : jouées, et **trois ne le sont pas**

La suite `434` les joue et les nomme. Résultat mesuré après le patch T06 :

| Épreuve | Nom | Verdict |
|---|---|---|
| D1 | rejeu | ✅ tenu — le 2ᵉ appel n'ajoute ni lien ni trace |
| D2 | — | ❌ **non jouée**, avec raison (pas de faux vert) |
| D3 | — | ❌ **non jouée**, avec raison |
| D4 | annulation | ✅ tenu — plus aucun lien actif |
| D5 | — | ❌ **non jouée**, avec raison |
| D6 | retour arrière | ✅ tenu — l'annulation de la transaction ne laisse rien |
| D7 | volume | ✅ tenu — p95 = 3 ms sur 19 tours, budget G6 |
| D8 | isolation | ✅ tenu — voisin **0** lien, propriétaire **1** |

**5 tenues, 3 non jouées — et c'est le bon comportement.** Une preuve qui ne peut
pas être tenue est dite telle ; elle n'est jamais déclarée verte par défaut
(`tenues_par_défaut=0`). **Il n'y a donc pas de travail « D2/D3/D5 » à faire :
il y a un travail « D2/D3/D5 ne sont pas jouables, et voici pourquoi »** — à
mettre dans le rapport, pas à maquiller.

### Les invariants : **17 mesurables, 3 non** — pas 6

| | |
|---|---|
| **20** invariants au total | |
| **17** mesurables | ✅ |
| **3** non mesurables | ❌ |

Le plan annonçait **6** invariants « non mesurables » (tâche A.3). La mesure en
trouve **3**. Soit trois ont été rendus mesurables depuis (le `456` — une seule
fonction de mesure — y est pour quelque chose), soit le décompte du plan datait
d'avant. **A.3 est donc dimensionné pour 3, pas pour 6** : la charge annoncée
(4 j) devrait être revue à la baisse — c'est le dernier morceau d'A.1.

### Les liens réellement produits : 3, pas 62

Sur la base neuve, `document_links` ne porte que **3 familles de maillons** :

| Maillon | Liens | Actifs |
|---|---|---|
| `bank_transactions.treasury.statement_line.posted` | 124 | 118 |
| `bank_accounts.treasury.bank_account.account` | 16 | 16 |
| `bank_accounts.treasury.bank_account.journal` | 16 | 16 |

Les 6 liens « perdants » (124 − 118) sont les liens **fermés** par le
dé-lettrage : c'est la trace de D3/D4, pas une fuite.

### Ce qu'il reste à faire pour A.1

- [x] Maillons déclarés : 7, tous couverts
- [x] Épreuves D1 → D8 : 5 tenues, 3 non jouées **avec raison**
- [x] Invariants : 17/20 mesurables
- [ ] **Le rapport par maillon** — un fichier, écrit, versé au suivi par
      l'intégration. C'est le dernier morceau d'A.1 et il est court.

## La plage, en fait — `475` → `499`, pas `423` → `499`

Le §2 du plan attribue à la partie A : `423`→`429`, `437`→`449`, `457`→`459`,
`468`→`499`. **Ces quatre segments sont déjà pris**, et pas par une ligne de
travail vivante : par des migrations qui existent et qui tournent.

| Segment prévu | Pourquoi il est indisponible |
|---|---|
| `423`→`429` | **`415` → `422` occupent déjà la zone** : L23, L17, L18, L19, L20, métriques, retour arrière — la tranche L16 → L24 du plan d'origine |
| `437`→`449` | **`437` = `chain_l4_fuites_fermees`**, et `430` → `436` sont les maillons L3 et le banc d'épreuves |
| `457`→`459` | **`456` = une seule fonction de mesure des invariants** ; la suite tient, la zone n'est pas libre |
| `468`→`499` | **`460` → `467` = la Vue Chaîne (I-01)**, et **`470`** est le dernier écrivain au-dessus des chaînages |

Le registre fait foi, et `migration-numero.mjs` **refuse** une plage qui
chevauche ou qui contient un numéro pris — c'est exactement la porte
`SOC-06`. Inscrire `423`→`499` reviendrait à faire passer la commande en
forçant le registre : c'est exactement l'accident que la règle R2 est écrite
pour empêcher.

**Ce qui reste libre, en dessous de 475 : rien.** En dessus : `475` → `499`,
inscrit sous le nom `plan6 A (chaînages et preuve)`.

> **À confirmer par vous** : soit A démarre à `475` et le §2 du plan est
> corrigé en conséquence, soit A doit recevoir une plage au-dessus de `749`.
> La première option est celle que le registre permet ; c'est aussi la seule
> qui ne demande pas de rouvrir des plages déjà tenues.

## Attend de vous

Avant **A.8** : les cinq questions du §6 des propositions (qui signe le
certificat, à qui on le remet, où tournent les données du prospect…), et
l'expert-comptable référent.

Et, pour A.1 tout de suite : l'arbitrage de plage ci-dessus.

## Journal

*(vide — une ligne par lot poussé, avec la date et le verdict de la batterie)*

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|