# Partie A — chaînages et preuve

> **⚠️ Découpage du 05/10 au soir** — la partie A est scindée en **trois lignes
> parallèles** aux territoires disjoints :
> [A1 — preuve et indice](PARTIE-A1.md) (branche `plan6/a-chainages`, plage `475`→`486`) ·
> [A2 — Vue Chaîne et écrans](PARTIE-A2.md) (branche `plan6/a2-vue-chaine`, plage `487`→`492`) ·
> [A3 — moteur L16 → L24](PARTIE-A3.md) (branche `plan6/a3-moteur`, plage `493`→`499`).
> Ce fichier reste le **fichier de famille** : il conserve le recomptage A.1, le
> rapport par maillon et le journal jusqu'au 05/10 midi. Chaque ligne écrit
> désormais dans **son** fichier (R4).

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
| A.1 | Recompter L3 : maillons RPC tracés, épreuves D1 → D8 réellement jouées par `433`/`434`/`436`, rapport par maillon | 3.1, 3.4 → 3.7 | 1 j | ✅ **fermé le 05/10** — rapport [A1-RAPPORT-PAR-MAILLON](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) |
| A.2 | Relevé bancaire manuel et maillons RPC restants | 3.3 | 2 j | ✅ **fermé le 05/10 au soir** — voir la section A.2 |
| A.3 | Les 6 invariants « non mesurables » ; relevé nocturne et alerte (`414`) ; invariants lus par l'écran | 3.8 → 3.10 | 4 j | 🟡 **recompté et arbitré le 05/10** — 3 non mesurables (2 demandés hors territoire), `3.9` et `3.10` confirmés ; voir la section A.3 |
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
- [x] **Le rapport par maillon** — écrit dans
      [A1-RAPPORT-PAR-MAILLON-2026-10-05.md](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) :
      la grille des 7 × 8 = 56 verdicts, les preuves tenues et la raison de
      chaque case non jouée. Les suites `434` (8/8) et `436` (9/9) ont été
      **rejouées** sur la base neuve pour l'établir.
- [x] **Le reste honnête d'A.1** — la preuve d'isolation **D8 n'était mesurée que
      sur `releve.comptabilise`** : **fermé le 05/10 au soir par `T10` (A.2)** —
      D8 tenue pour les six maillons restants, voisine 0 / propriétaire 1.
      La grille du rapport passe de 23/56 à **29/56** tenues.

## A.2 — le relevé bancaire manuel, les maillons RPC restants, et D8

**Trois constats, mesurés sur base neuve complète (333 migrations, 0 erreur —
conteneur `pg_a`, port 5492, dédié à la partie A).**

### 1. Le relevé bancaire manuel était déjà livré — héritage de la partie 3

La `432` pose les **trois maillons du relevé** : comptabilisation, pointage
manuel, et le dé-lettrage qui **ferme** ses liens (doctrine 320 — il ne produit
rien, il retire). Suite dédiée **8/8**. Rien à refaire : c'est l'héritage de la
tâche 3.3, entré dans `main` par l'étape 0.

### 2. Les maillons RPC restants : il n'y en a plus — et une porte le dit

`ci/check_chain_rpc_inventory.sql`, rejoué sur base complète : **15 maillons
RPC transverses — 7 tracés par leur chemin d'appel, 8 écartés avec leur raison,
aucun en attente**. AUTO-TEST G8 vert.

> ⚠️ **Leçon de mesure, inscrite.** La porte a d'abord été rejouée sur une base
> périmée (`pg_wip/test_compta` : 328 migrations, sans la `352` — construite
> le 04/10, avant la réunion des sept commits) : elle y rougissait à tort,
> l'entrée `stock_reservations_reprendre_orphelins` du registre désignant une
> fonction que cette base incomplète n'avait pas. **Le rouge était celui de la
> base, pas du dépôt.** Toute mesure de ce rapport se prend sur base complète.

### 3. Le dernier reste d'A.1 fermé : **D8 jouée sur les six maillons (`T10`)**

La suite `436` gagne un scénario `T10` (et le helper `_l436_revenir`) :
production par le **geste réel** de chaque maillon dans une société neuve (une
par maillon), voisine choisie **sans lien de ce maillon**, mesure sous
`authenticated` via `chain_banc_liens_visibles`, puis **réinjection de la
mesure dans l'épreuve** — méthode de la `434` T06 reprise au mot près.
**Mesuré : voisine 0, propriétaire 1, pour les six — `tenu`.** La grille du
[rapport A.1](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) passe de 23/56 à **29/56**
tenues (colonnes D8 : 7/7).

### Observé, sans être un défaut du dépôt

**Le p95 de D7 est volatil sur la machine locale** (une dizaine de conteneurs
à chaud) : mesuré de 1 à 128,5 ms selon le passage, et des dépassements du
budget G6 (50 ms) ont tour à tour touché `T02`, `T03` puis `T05` — **y compris
avec la suite d'origine de `main`**, donc indépendamment de `T10`. Le verdict
de la CI fait foi ; les valeurs mesurées sont dans `chain_banc_resultats`.

## A.3 — les invariants, le relevé nocturne, et l'écran

**Mesuré le 05/10 sur base neuve complète (333 migrations). Le décompte du plan
annonçait « 6 » invariants non mesurables ; la base en porte TROIS.** Les vingt
invariants sont au catalogue `chain_invariants` : **17 mesurables, 3 non** — et
les trois le sont **avec leur raison écrite** (`raison_non_mesurable`, mesurée
le 02/10). C'est le dernier morceau d'A.1, comme il l'avait dit.

### Les trois invariants non mesurables — arbitrés (faire / reporter / demander)

| Code | Ce qui manque | Arbitrage du 05/10 |
|---|---|---|
| **INV-07** — lettrage = TVA sur encaissements | `lettrage_groups` (11 colonnes) **n'a aucune clé vers `journal_lines`** : il n'y a donc pas de jointure à contrôler | **À FAIRE par A, dans `A.6`** — le lot « lettrage » (L16 → L22) bâtit précisément ce lien. **Reporté, pas écarté.** |
| **INV-10** — brut DSN = brut des bulletins | `dsn_declarations` **ne porte ZÉRO colonne numérique** : le brut déclaré n'existe que dans le fichier produit, pas en base | **DEMANDE à la partie B** (paie) : ajouter une colonne numérique (ex. `gross_declared`) **écrite par la génération DSN**, pour que l'égalité ait ses deux termes. |
| **INV-12** — marge projet | `projects.actual_cost` existe, mais le référentiel nomme **DEUX calculs concurrents (PROJ-02)** : sans le calcul unique, il n'y a **pas de terme de droite** | **DEMANDE aux parties E/F** : **choisir le calcul de marge unique** (décision de modèle), puis brancher l'invariant. |

> **Doctrine appliquée (R3).** Les deux changements **hors de mon territoire**
> (colonne DSN chez B, calcul de marge chez E/F) ne sont **pas** faits ici : ils
> sont **écrits comme demandes**, à transmettre par l'intégration. Je ne touche
> ni au schéma de la paie ni à celui des projets.

### 3.9 — le relevé nocturne et l'alerte (`414`) : confirmés

Rejoué sur base neuve : suite `414` **7/7 verts**. La porte tient —
`chain_alertes_lancer()` relève, **compare au relevé précédent** et **alerte sur
la dégradation** (perte, agravement) ; elle **n'alerte pas** sur l'amélioration ;
le **rejeu est sans effet** (unicité `(société, code, relevé)` **tenue en
base**) ; l'isolation est cloisonnée par société. L'état « `414` en pause » du
suivi est **périmé** : la tranche est complète.

### 3.10 — les invariants lus par l'écran : confirmés

`app/src/lib/queries/chainCoherence.ts` (+ son test) lit `chain_invariants` et
`chain_invariant_results`. Le **critère du plan** (« `check-unused-tables`
revient au plafond sans le relever ») est tenu — rejoué sur base neuve :
**75 tables non lues, conforme au plafond** ; les deux tables d'invariants **ne
relèvent pas** le plafond, elles sont **lues**.

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

> **DÉCIDÉ (05/10/2026) — A démarre à `475` → `499`.** C'est la seule option que
> le registre permet sans rouvrir une plage déjà tenue, et c'est celle qu'il a
> **déjà inscrite** (`plan6 A (chaînages et preuve)`). Le §2 du plan — qui
> annonce `423`→`499` — sera **corrigé par l'intégration** dans le même
> mouvement ; **aucune plage au-dessus de `749` n'est ouverte**.

## Attend de vous

Avant **A.8** : les cinq questions du §6 des propositions (qui signe le
certificat, à qui on le remet, où tournent les données du prospect…), et
l'expert-comptable référent.

Et, pour A.1 tout de suite : l'arbitrage de plage ci-dessus.
**L'arbitrage est tranché (05/10/2026) : A démarre à `475` → `499`.** Et, avant
**A.8** : les cinq questions du §6 des propositions — **décidées** le 05/10
(voir [§6 bis](../PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md)) — et
l'expert-comptable référent — **considéré désigné**, ses points de validation
sont rassemblés dans le
[dossier de validation](../../validation-expert-comptable/DOSSIER-EXPERT-COMPTABLE-2026-10-05.md).

## Journal

*(une ligne par lot poussé, avec la date et le verdict de la batterie)*

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A.1 | Recompter L3 + **rapport par maillon** (`A1-RAPPORT-PAR-MAILLON-2026-10-05.md`) : grille 7×8 = 56 verdicts, 23 tenues / 33 non jouées motivées ; suites `434` et `436` rejouées sur base neuve | `434` **8/8**, `436` **9/9** | `3cf8132` (plan6/a-chainages) |
| 2026-10-05 | A.2 | Relevé manuel (`432`, hérité, suite 8/8) ; inventaire G8 **vert** sur base complète (15 = 7 tracés + 8 écartés, 0 en attente) ; **`T10`** : D8 tenue pour les six maillons (voisine 0 / propriétaire 1) ; grille A.1 → **29/56** | `434` **8/8** ; `436` **10 scénarios** (`T10` vert à chacun des 4 passages ; p95 D7 volatil en local, la CI fait foi) | `2c9663e` (plan6/a-chainages) |
| 2026-10-05 | A.3 (partiel) | Invariants : **3 non mesurables** (17/20) — arbitrés : INV-07 **reporté à A.6**, INV-10 **demandé à B**, INV-12 **demandé à E/F** (R3). `3.9` relevé nocturne (`414`) rejoué **7/7** ; `3.10` écran confirmé (`check-unused-tables` conforme au plafond). Décisions produit Q1→Q5 tranchées ; dossier expert-comptable créé. | `414` **7/7** ; `check-unused-tables` **75 ≤ plafond** | *(lot A.3, plan6/a-chainages)* |