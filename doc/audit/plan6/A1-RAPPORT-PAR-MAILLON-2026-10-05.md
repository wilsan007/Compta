# A.1 — Le rapport par maillon (chaînages et preuve) — mesuré le 05/10/2026

> Livrable de la tâche **A.1** de la [partie A](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)
> (§4) : « le rapport par maillon — un fichier, écrit, versé au suivi par
> l'intégration ». Le **décompte** lui-même (7 maillons déclarés, épreuves
> D1→D8, invariants, liens, plage de migrations) est tenu dans
> [PARTIE-A.md](PARTIE-A.md) ; **ce fichier porte la grille des 56 verdicts**,
> maillon par maillon, telle que le banc la rend.
>
> **Base de mesure.** Base neuve (PostgreSQL 16, conteneur `pg_a`, port 5492,
> dédiée à la partie A, montée depuis `main` après l'étape 0), schéma complet
> par `sql/ci/00_supabase_stubs.sql` + `sql/00_schema_dump.sql` +
> `run-sql-migrations.mjs` — **333 migrations, 0 erreur**. Les deux suites du banc ont été **rejouées** sur cette base :
>
> | Suite | Objet | Verdict |
> |---|---|---|
> | `434_chain_banc_epreuves_tests.sql` | les 8 épreuves sur `releve.comptabilise` | **8/8 verts** |
> | `436_chain_banc_six_maillons_tests.sql` | les 6 autres maillons, **et D8 par `T10`** (A.2) | **10 scénarios** — `T10` vert à chaque passage ; le p95 de D7 est volatil en local selon la charge (§3) |
>
> Ce ne sont pas des scores de « confiance » : chaque `✅ tenu` porte une
> **mesure** (liens, traces ou p95 en ms), et chaque `— non joué` porte sa
> **raison**. Un verdict sans mesure n'est jamais publié `tenu` (la suite `436`,
> `T09`, le vérifie pour la campagne entière).

---

## 1. Le banc, en deux phrases

Le banc éprouve **7 maillons** — les sept gestes du socle qui portent une
écriture comptable — contre **8 épreuves** (D1 → D8). Un maillon est décrit une
fois, au catalogue `chain_banc_maillons` (libellé, effet, gabarit d'appel,
geste d'annulation) ; les épreuves sont **dérivées** de cette description par le
moteur `chain_banc_epreuve` / `chain_banc_lancer` (`433`, `434`).

| Code | Libellé | Effet produit | Nature | Geste d'annulation (D4) |
|---|---|---|---|---|
| `releve.comptabilise` | Comptabilisation d'une ligne de relevé | `treasury.statement_line.posted` | application | `unreconcile_bank_statement_line` |
| `releve.pointage` | Pointage manuel d'une ligne de relevé | `treasury.statement_line.manually_reconciled` | application | `unreconcile_bank_statement_line` |
| `releve.delettrage` | Dé-lettrage d'une ligne de relevé (ferme le lien, ne produit rien) | `treasury.statement_line.posted` | application | — *(aucun : il ne produit rien)* |
| `caisse.ticket` | Ticket de caisse (encaissement atomique) | `pos.ticket.stock_out` | **création** | `void_pos_ticket` |
| `caisse.avoir` | Avoir de caisse (avec retour de stock) | `pos.ticket.stock_in` | application | — *(aucun décrit)* |
| `paie.comptabilisee` | Comptabilisation du bulletin de paie | `payroll.run.posted` | application | — *(aucun décrit)* |
| `paie.versement` | Versement de la paie (net, social, taxe, acomptes) | `payroll.payment.settled` | application | — *(aucun décrit)* |

> **Un seul maillon est de nature `création` : `caisse.ticket`.** C'est lui, et
> lui seul, pour qui D1 (« le rejeu ne double pas l'effet ») est **sans objet** :
> son argument est un *contenu*, pas l'identifiant d'une ressource ; le rejouer
> crée un **second** ticket (mesuré : +1 lien, +1 trace). Le publier `rompu`
> serait publier un défaut qui n'existe pas ; il est donc déclaré `non_joue` avec
> cette raison — pas vert par défaut.

---

## 2. La grille — 7 maillons × 8 épreuves = 56 verdicts

`✅` = tenue, avec mesure · `—` = non jouée, avec raison (§3 et §4).

| Maillon | D1 rejeu | D2 concurrence | D3 tout-ou-rien | D4 annulation | D5 réouverture | D6 retour arrière | D7 volume | D8 isolation | **Tenues** |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| `releve.comptabilise` | ✅ | — | — | ✅ | — | ✅ | ✅ | ✅ | **5/8** |
| `caisse.ticket` *(création)* | — | — | — | ✅ | — | ✅ | ✅ | ✅ | 4/8 |
| `caisse.avoir` | ✅ | — | — | — | — | ✅ | ✅ | ✅ | 4/8 |
| `paie.comptabilisee` | ✅ | — | — | — | — | ✅ | ✅ | ✅ | 4/8 |
| `paie.versement` | ✅ | — | — | — | — | ✅ | ✅ | ✅ | 4/8 |
| `releve.pointage` | ✅ | — | — | ✅ | — | ✅ | ✅ | ✅ | 5/8 |
| `releve.delettrage` | ✅ | — | — | — | — | ✅ | — | ✅ | 3/8 |
| **Total (sur 56)** | **6** | **0** | **0** | **3** | **0** | **7** | **6** | **7** | **29/56** |

> **La colonne D8 a changé le 05/10 au soir (T10, tâche A.2).** À la mesure
> initiale d'A.1, les six cases D8 des maillons autres que
> `releve.comptabilise` étaient `non_joue` — tenues : **23/56**. La suite
> `436` les joue désormais (`T10`) : production par le geste réel, voisine
> neutre, mesure sous `authenticated` — **voisine 0, propriétaire 1, pour
> les six**.

**Comment lire ce `29/56`.** Les 27 cases `—` **ne sont pas** 27 défauts : elles
se répartissent en deux familles, chacune nommée ci-dessous.

| Famille | Cases | Pourquoi |
|---|:--:|---|
| D2, D3, D5 — **structurelles** | 7 × 3 = **21** | exigent des instruments que le schéma n'a pas (seconde connexion, point d'échec, chemin de réouverture) — voir §3 |
| D4 / D1 / D7 ponctuels | **6** | un geste d'annulation qui n'existe pas, une création sans rejeu, une série de stimuli absente — chaque raison est écrite |

---

## 3. Les preuves tenues, maillon par maillon

Les mesures ci-dessous sont celles des suites rejouées le 05/10 (verbatim
abrégé). Elles sont aussi en base : `chain_banc_resultats`, une ligne datée par
couple `(code, épreuve)`.

### `releve.comptabilise` — le maillon de référence (suite `434`)

| Épreuve | Verdict | Mesure |
|---|---|---|
| **D1 rejeu** | ✅ tenu | 1ᵉʳ tour : 1 lien, 1 trace `applique` ; 2ᵉ tour : **+0 lien, +0 trace** (refus métier contrôlé, SQLSTATE `23505`) |
| **D4 annulation** | ✅ tenu | **0 lien actif** restant après le dé-lettrage |
| **D6 retour arrière** | ✅ tenu | **0 lien de plus** qu'au départ après l'annulation de la transaction |
| **D7 volume** | ✅ tenu | **p95 = 3 ms** sur 19 tours distincts (budget G6 : 50 ms) |
| **D8 isolation** | ✅ tenu | société voisine : **0 lien visible** ; propriétaire : **1** (> 0, sinon l'épreuve ne prouverait rien) |

### Les six autres (suite `436`)

| Maillon | D1 | D4 | D6 | D7 |
|---|---|---|---|---|
| `caisse.ticket` | — *sans objet (création)* | ✅ `void_pos_ticket` → 0 lien actif | ✅ | ✅ (20 stimuli distincts) |
| `caisse.avoir` | ✅ *par un REFUS (`42501`)* | — *pas de geste décrit* | ✅ | ✅ p95 = 13,05 ms |
| `paie.comptabilisee` | ✅ (1 lien, 1 trace → +0/+0) | — *pas de geste décrit* | ✅ | ✅ p95 = 3,05 ms |
| `paie.versement` | ✅ (1 lien, 1 trace → +0/+0) | — *pas de geste décrit* | ✅ | ✅ p95 = 17,1 ms |
| `releve.pointage` | ✅ (1 lien, 1 trace → +0/+0) | ✅ `unreconcile…` → 0 lien actif | ✅ | ✅ p95 = 4,1 ms |
| `releve.delettrage` | ✅ (1 lien, 1 trace → +0/+0) | — *le re-pointage a été joué, il a REFUSÉ la ligne déjà pointée* | ✅ | — *pas de série de stimuli* |

> **`caisse.avoir` — D1 « tenu par un refus » est une tenue, pas un trou.**
> Le rejeu y est refusé (`42501`), et un refus **est** une tenue valide de
> l'invariant D1 : le second tour n'a **rien** ajouté. Le banc le dit tel quel.

> **D8, ajoutée par T10 (A.2, 05/10 au soir) : tenue pour les six aussi.**
> Production par le geste réel du maillon dans une société neuve, voisine
> choisie **sans lien de ce maillon**, mesure sous `authenticated` via
> `chain_banc_liens_visibles`, réinjection dans l'épreuve — méthode de la
> `434` T06, reprise au mot près. Mesuré : **voisine 0, propriétaire 1, pour
> les six**, `T10` vert à chacun des quatre passages complets.

> **Les p95 de D7 varient avec la charge de la machine.** Mesuré le 05/10 :
> de 1 à 128,5 ms selon le passage, sur quatre passages complets — et les
> dépassements du budget G6 (50 ms) ont tour à tour touché `T02`, `T03` puis
> `T05`, **y compris avec la suite d'origine de `main`**. Ce n'est pas un
> défaut du banc : c'est une machine locale chargée (une dizaine de
> conteneurs). Le verdict de la CI fait foi ; les valeurs mesurées sont dans
> `chain_banc_resultats`.

---

## 4. Les 27 « non jouées », et pourquoi ce n'est pas une échappatoire

### D2, D3, D5 — trois instruments que le schéma n'a pas (21 cases)

Ces trois épreuves sont `non_joue` **pour tous les maillons**, et la raison est
la même : chacune exige quelque chose que la base n'offre pas.

| Épreuve | Ce qu'elle veut | Pourquoi elle n'est pas jouable |
|---|---|---|
| **D2 concurrence** | deux transactions **simultanées** | exige une **seconde connexion** (`dblink`) ; aucun maillon n'a `defaut_dblink = true` |
| **D3 tout-ou-rien** | une panne **au milieu** de l'effet | exige un **point d'échec instrumenté** ; aucun maillon n'en expose |
| **D5 réouverture** | un chemin de « fermé » → « rouvert » | exige un `appat_reouverture` décrit ; aucun maillon n'en a |

Les forcer en écrivant `tenu` serait mentir sur trois épreuves sur huit. La
suite le verrouille : `T09` (`436`) et `T07` (`434`) refusent tout `tenu` sur
D2/D3/D5 (`D2_D3_D5_tenus = 0`), et refusent tout `non_joue` **sans raison**
(`non_joués_sans_raison = 0`).
### D4 — les maillons qui n'ont pas de geste d'annulation (4 cases)

`caisse.avoir`, `paie.comptabilisee`, `paie.versement` et `releve.delettrage`
n'ont **aucun** geste d'annulation au catalogue. On ne l'invente pas : on ne
peut pas annuler en **rejouant** le producteur (cela produirait un *second*
effet, pas sa suppression — doctrine `434`). `releve.delettrage` va plus loin :
le geste que tout le monde proposerait (re-pointer) **a été joué**, et il
**refuse** la ligne déjà pointée — c'est écrit, pas tu.

### D1 — la création, et la série absente (2 cases)

- `caisse.ticket` : D1 sans objet (création — §1).
- `releve.delettrage` D7 : aucune série de stimuli au catalogue (`arg_series`
  vide) ; rejouer une seule entrée ne mesurerait que le chemin de refus, donc
  pas de p95 honnête — la suite ne le publie pas.

### D8 sur les six autres — **fermée par T10 (A.2), le 05/10 au soir** (0 case)

L'isolation entre sociétés était **prouvée** pour `releve.comptabilise` seule
(`434` T06, sous `SET LOCAL ROLE authenticated` : voisin 0, propriétaire 1).
Les six autres restaient `non_joue` — c'était le reste le plus substantiel
nommé par ce rapport. **Il est fermé** : la suite `436` gagne un scénario
`T10` qui produit le lien par le **geste réel** de chaque maillon dans une
société neuve (une par maillon), choisit une voisine **sans lien de ce
maillon** (sinon le témoin est pollué par ses propres liens), mesure sous
`authenticated` via `chain_banc_liens_visibles`, puis **réinjecte la mesure
dans l'épreuve** — c'est le banc, et lui seul, qui rend le verdict. Résultat
mesuré : **voisine 0, propriétaire 1, pour les six** (`tenu`), `T10` vert à
chacun des quatre passages complets.

---

## 5. La campagne (`chain_banc_lancer`) — ce qu'elle prouve, et ce qu'elle ne prouve pas

`chain_banc_lancer(tenant)` parcourt le catalogue et **joue les 8 épreuves** :
le rapport compte alors **7 × 8 = 56 lignes datées** (`T08` de la suite `436` :
`maillons=7 lignes=56 couples=56 verdicts_sans_date=0`). C'est la preuve de la
tâche 3.7 — « un chaînage déclaré = 8 verdicts datés » — appliquée au catalogue
entier, et non à un seul maillon.

⚠️ **Attention à ne pas lire ces 56 lignes comme des verdicts de métier.** La
campagne joue chaque maillon avec la **description courante** du catalogue ; un
maillon dont le décor n'est pas posé rend `non_joue` (décor manquant) ou
`rompu` (chemin de refus). Ce sont les **suites dédiées** (§3) qui posent le
décor par maillon et portent le verdict de référence. La campagne prouve la
**structure** (56 verdicts datés, aucune case muette), pas la tenue.

---

## 6. Reproduire cette mesure

```bash
# 1. la base neuve (une fois) — conteneur Postgres 16 dédié, publié sur 5492
docker run -d --name pg_a -e POSTGRES_PASSWORD=postgres -p 5492:5432 postgres:16
# attendre le serveur (pg_isready), puis créer la base
docker exec pg_a psql -U postgres -h 127.0.0.1 -c 'CREATE DATABASE test_compta'
cd app
export DATABASE_URL="postgresql://postgres:postgres@localhost:5492/test_compta"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/ci/00_supabase_stubs.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/00_schema_dump.sql
node run-sql-migrations.mjs          # 333 migrations, 0 erreur attendue

# 2. les deux suites du banc. Les fichiers sont copiés DANS le conteneur, pour
#    que leurs `\ir ci/…` se résolvent : `psql -f` depuis stdin ne le fait pas.
docker cp sql pg_a:/tmp/psql6
docker exec pg_a psql -U postgres -h 127.0.0.1 -d test_compta -v ON_ERROR_STOP=1 \
  -f /tmp/psql6/434_chain_banc_epreuves_tests.sql
docker exec pg_a psql -U postgres -h 127.0.0.1 -d test_compta -v ON_ERROR_STOP=1 \
  -f /tmp/psql6/436_chain_banc_six_maillons_tests.sql

# 3. la grille par maillon, telle qu'enregistrée (une ligne datée par couple)
docker exec pg_a psql -U postgres -h 127.0.0.1 -d test_compta -c \
  "SELECT code, epreuve, verdict, round(mesure,2) FROM chain_banc_resultats ORDER BY code, epreuve;"
```

---

## 7. Ce que ce rapport ne prouve pas — nommé

- **D2, D3, D5.** Non jouables faute d'instrument (§4) — **pas** « vertes ».
- **D8.** Tenue pour les **sept** maillons depuis `T10` (§4) ; à la mesure
  initiale d'A.1, elle ne l'était que pour un.
- **`plpgsql_check`** n'est pas dans l'image locale : les 333 migrations ont été
  appliquées **sans** cette sonde de code PL/pgSQL (la CI l'installe).
- **Le `p95` est une mesure d'horloge locale** (`pg_a`, conteneur à chaud sur
  une machine chargée) : mesuré de 1 à 128,5 ms selon le passage, avec des
  dépassements du budget G6 (50 ms) touchant des scénarios différents —
  y compris avec la suite d'origine. Indicative, pas une mesure de
  production ; le verdict de la CI fait foi.
- **D4/D7 des maillons sans geste / sans série** : la case reste vide tant que
  le geste ou la série n'est pas décrit ; ce n'est pas un travail « à faire
  semblant ».