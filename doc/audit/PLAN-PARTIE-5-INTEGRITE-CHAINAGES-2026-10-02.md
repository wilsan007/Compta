# Partie 5 / 5 — L'intégrité référentielle des chaînages

> **Plan du 02/10/2026, partie ajoutée après coup.** Elle suit les quatre premières :
>
> | Partie | Objet | Charge | Document |
> |---|---|---:|---|
> | 1 | Stabiliser : une branche, une CI verte, des gardes honnêtes | ≈ 9,25 j | [PLAN-PARTIE-1](PLAN-PARTIE-1-STABILISER-2026-10-02.md) |
> | 2 | Finir les défauts métier de la recette | ≈ 9,5 j | [PLAN-PARTIE-2](PLAN-PARTIE-2-DEFAUTS-METIER-2026-10-02.md) |
> | 3 | Chaînages : finir L3 et L4 | ≈ 9 j | [PLAN-PARTIE-3](PLAN-PARTIE-3-CHAINAGES-L3-L4-2026-10-02.md) |
> | 4 | Montrer, recetter, livrer | ≈ 10 j | [PLAN-PARTIE-4](PLAN-PARTIE-4-RECETTE-LIVRAISON-2026-10-02.md) |
> | **5** | **L'intégrité référentielle des chaînages** | **≈ 6 j** | ce document |
>
> **Ce document est écrit pour un développeur qui découvre le sujet.** Chaque étape
> dit quoi faire, dans quel fichier, avec quelle commande, ce qu'on doit voir, et ce
> qui peut mal tourner. **Tout le code est déjà écrit et vérifié** : il est rangé dans
> [`doc/audit/partie-5/`](partie-5/). Votre travail consiste à le poser au bon endroit,
> à le voir échouer puis réussir, et à le livrer proprement.

---

## Sommaire

- [0. Le problème, en mots simples](#0-le-problème-en-mots-simples)
- [1. Ce que la partie livre](#1-ce-que-la-partie-livre)
- [2. Avant de commencer](#2-avant-de-commencer)
- [3. Les étapes, une par une](#3-les-étapes-une-par-une)
- [4. Les 14 scénarios de la suite 450](#4-les-14-scénarios-de-la-suite-450)
- [5. Ce qui change pour les utilisateurs](#5-ce-qui-change-pour-les-utilisateurs)
- [6. Les commits, dans l'ordre](#6-les-commits-dans-lordre)
- [7. Critères de sortie](#7-critères-de-sortie)
- [8. Ce que cette partie ne fait pas](#8-ce-que-cette-partie-ne-fait-pas)
- [Annexe A — les 27 types du registre](#annexe-a--les-27-types-du-registre)
- [Annexe B — les 23 maillons qui posent des liens](#annexe-b--les-23-maillons-qui-posent-des-liens)
- [Annexe C — les suppressions de l'écran, avant et après](#annexe-c--les-suppressions-de-lécran-avant-et-après)
- [Annexe D — dépannage](#annexe-d--dépannage)
- [Annexe E — ce qui a été mesuré pour écrire ce document](#annexe-e--ce-qui-a-été-mesuré-pour-écrire-ce-document)

---

## 0. Le problème, en mots simples

**Un chaînage**, c'est la trace qu'un document en a produit un autre : une facture
validée a produit une écriture comptable, une commande confirmée a produit une
réservation de stock, etc. Cette trace vit dans la table `document_links` :

| colonne | exemple |
|---|---|
| `amont_type` / `amont_id` | `sales_orders` / l'identifiant de la commande |
| `aval_type` / `aval_id` | `stock_reservations` / l'identifiant de la réservation |
| `effet`, `etat` | `stock.reserve`, `actif` (ou `remplace`, `rompu` quand le lien est fermé) |

**Le défaut** : ces colonnes sont **polymorphes**. `amont_id` peut viser n'importe
quelle table, selon la valeur texte de `amont_type`. PostgreSQL ne sait pas poser une
clé étrangère sur une colonne qui vise « une table parmi 27 ». Résultat, mesuré le
02/10/2026 sur une base neuve :

1. **la seule clé étrangère** des 8 tables du socle est `tenant_id → tenants`. Les 13
   autres colonnes de référence (`amont_id`, `aval_id`, `amont_ligne_id`, …) n'en ont
   **aucune** ;
2. **`link_documents`** (la seule fonction qui écrit les liens) ne vérifie **pas** que
   les documents existent, ni que le type correspond à une table : la base contient des
   liens de type `commande` et `livraison`, qui ne sont pas des tables ;
3. **15 des 27 tables reliées n'ont aucune garde de suppression.** Un administrateur
   connecté, par le chemin normal de l'écran, a supprimé :

   | essai | ce qui reste après la suppression |
   |---|---|
   | D1 un compte bancaire | 2 liens **actifs** vers rien |
   | D2 un règlement client | 1 lien actif vers rien ; la facture reste « payée, dû 0 » et l'écriture de 120 € reste au grand livre, **sans aucun document de règlement** |
   | D3 une commande confirmée | 1 lien actif vers rien, et une **réservation de 3 unités toujours active** : du stock bloqué pour une commande qui n'existe plus |
   | D4 une réservation | 1 lien actif vers rien (et la quantité réservée **n'est pas rendue**) |
   | D5 le journal et le compte comptable créés pour une banque | 2 liens actifs vers rien |

4. **L'invariant L4 qui devait le voir, INV-19** (« aucun document aval n'est orphelin
   de son amont »), est inscrit « **non mesurable** », précisément pour la raison 1.

Cloisonnement : **0 lien ne relie deux sociétés** (mesuré). Ce n'est pas une fuite de
données ; c'est une perte de cohérence.

## 1. Ce que la partie livre

| # | Livrable | Fichier de référence (déjà écrit et vérifié) | Où il va |
|---|---|---|---|
| A | Un **registre** des 27 types de document et une clé étrangère `amont_type` / `aval_type` → registre | `partie-5/450_chain_document_types.sql` | `app/sql/450_chain_document_types.sql` |
| B | `link_documents` **vérifie l'existence** de l'amont, de l'aval et de leurs lignes | `partie-5/451_chain_link_existence.sql` | `app/sql/451_chain_link_existence.sql` |
| C | Les orphelins déjà présents sont **fermés** (`rompu`, motif daté), jamais effacés | `partie-5/452_chain_orphelins_reprise.sql` | `app/sql/452_chain_orphelins_reprise.sql` |
| D | Une **garde de suppression** sur les 27 tables et leurs 5 tables de lignes, plus l'exception métier « compte bancaire sans opération » | `partie-5/453_chain_delete_guard.sql` | `app/sql/453_chain_delete_guard.sql` |
| E | `release_stock_reservation()` : une réservation se **libère**, elle ne se supprime plus | `partie-5/454_stock_reservation_release.sql` | `app/sql/454_stock_reservation_release.sql` |
| F | **INV-19 devient mesurable** | `partie-5/gen455.py` (génère la migration) | `app/sql/455_chain_inv19_mesurable.sql` |
| G | La **suite de tests** : 14 scénarios | `partie-5/450_chain_integrite_referentielle_tests.sql` | `app/sql/450_chain_integrite_referentielle_tests.sql` |
| H | Les **adaptations** des suites 252, 402, 413 et du banc G6 | `partie-5/adapt_252_402.py`, `adapt_413.py`, `adapt_g6.py` | modifient les fichiers en place |
| I | **L'écran** : message de refus traduit (fr/en/ar), libération par la nouvelle fonction, porte des tables non lues, garde W10 précisée | `partie-5/apply_front.py` (+ une modification à la main, étape 5.11) | modifie les fichiers en place |

**Résultat mesuré quand tout est posé** (base neuve, le 02/10/2026, sur l'état
`c51d468` + cette partie) : **278 migrations, 0 erreur** ; **124 étapes du job base
sur 124** ; **96 suites, 761 scénarios verts** ; suite 450 **14/14** (et **12 rouges sur
14 avant**) ; banc G6 **p95 0,85 ms** pour un budget de 50 ms ; chemin de l'écran **15/15
fichiers, 125/125 verdicts** ; Vitest **1 543 verts, 0 échec** ; `tsc` 0, `oxlint` 0, i18n
fr/en/ar à parité ; `plpgsql_check` **0 erreur** sur les nouvelles fonctions.

**Charge : ≈ 6 j** (le code est écrit ; la charge est l'intégration, la vérification
et la livraison).

## 2. Avant de commencer

### 2.1 Les conditions d'entrée (toutes obligatoires)

- [ ] **La partie 1 est close** : la branche principale est verte sur GitHub. Si elle
      est rouge, vous ne saurez pas distinguer vos rouges de ceux des autres.
- [ ] Vous avez lu [`NUMEROTATION-MIGRATIONS.md`](NUMEROTATION-MIGRATIONS.md).
- [ ] **Aucune autre session ne modifie** `link_documents`, `chain_invariant_mesurer`,
      `src/lib/utils.ts` ou `src/lib/queries/stock.ts` pendant votre travail. La
      partie 2 (lot D, stock) touche aussi `stock.ts` : prévenez-la, et faites passer
      cette partie **avant** ou **après** elle, jamais en même temps.
- [ ] Docker fonctionne (`docker ps` répond), Node 22 est installé.

### 2.2 La plage de numéros

Cette partie prend **`450` → `459`** (elle en utilise 6 : `450` → `455`).

> ⚠️ Un numéro se **constate**, il ne se réserve pas. Avant d'écrire le premier
> fichier, **vérifiez** que personne ne l'a pris, puis **inscrivez** la plage dans le
> tableau de `AGENTS.md` (paragraphe « Numérotation des migrations ») **et** dans
> `NUMEROTATION-MIGRATIONS.md`, avec la date. C'est l'étape 5.0.

```bash
ls app/sql | grep -E '^45[0-9]_'
```

Si cette commande imprime quelque chose qui n'est pas à vous : **arrêtez-vous**, prenez
la plage libre suivante et remplacez `450`…`455` partout dans ce document.

### 2.3 La branche

```bash
git switch commercial-hr-paie
git pull
git switch -c partie-5-integrite-chainages
```

La CI se déclenche sur les branches `partie-*` depuis la tâche 1.4 de la partie 1.

### 2.4 Votre base de test locale (à faire une fois)

Une base PostgreSQL 16 **neuve**, comme celle de la CI, avec l'extension
`plpgsql_check`. On monte le dossier `app` dans le conteneur pour que `psql` lise les
fichiers directement.

```bash
cd app
docker run -d --name pg_p5 -v "$PWD:/app" -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=test_compta -p 5440:5432 postgres:16
sleep 6
docker exec pg_p5 bash -c "apt-get update -qq && apt-get install -y -qq postgresql-16-plpgsql-check"
```

Deux raccourcis, à coller dans votre terminal (ils servent dans toute la suite) :

```bash
export DATABASE_URL=postgresql://postgres:postgres@localhost:5440/test_compta
p5sql() { docker exec -i -w /app pg_p5 psql -U postgres -d test_compta -v ON_ERROR_STOP=1 "$@"; }
```

Pour **reconstruire la base de zéro** (vous le ferez plusieurs fois) :

```bash
docker exec pg_p5 psql -U postgres -c "DROP DATABASE IF EXISTS test_compta WITH (FORCE)" -c "CREATE DATABASE test_compta"
p5sql -f sql/ci/00_supabase_stubs.sql > /dev/null
docker exec -i -w /app pg_p5 psql -U postgres -d test_compta -f sql/00_schema_dump.sql > /dev/null 2>&1
node run-sql-migrations.mjs | grep RÉSULTAT
p5sql -c "CREATE EXTENSION IF NOT EXISTS plpgsql_check"
```

**Ce qu'on doit voir** : `📊 RÉSULTAT FINAL: N succès, 0 erreurs sur N migrations`.

> 💡 Le lanceur `run-sql-migrations.mjs` exécute **chaque fichier dans une
> transaction** (`BEGIN` … `COMMIT`). **N'écrivez jamais `BEGIN;` ni `COMMIT;` dans une
> migration.** Il ignore les fichiers `*_tests.sql`.

## 3. Les étapes, une par une

> **Règle d'or du dépôt** : un défaut = un test **rouge avant**, puis le correctif, puis
> le test vert, le câblage CI, `npm run db:types`, et la preuve, **dans le même
> commit**. Le travail non commité n'existe pas : commitez chaque soir, même en WIP.

### 5.0 — Inscrire la plage (≈ 0,25 j)

1. Vérifiez la plage (§ 2.2).
2. Dans `AGENTS.md`, tableau des plages, ajoutez la ligne :
   `| **`450` → `459`** | **Partie 5** — intégrité référentielle des chaînages (registre des types, existence, garde de suppression, INV-19) | **AAAA-MM-JJ** |`
   et passez la ligne « libre » de `325 → 399` à … ce qu'elle est réellement ce jour-là.
3. Même ligne dans le tableau de `doc/audit/NUMEROTATION-MIGRATIONS.md`.
4. Commit : `docs(partie 5) : la plage 450 → 459 est inscrite`.

### 5.1 — Poser la suite de tests et la voir ROUGE (≈ 0,25 j)

1. Copiez la suite :
   ```bash
   cp ../doc/audit/partie-5/450_chain_integrite_referentielle_tests.sql sql/
   ```
2. Reconstruisez la base de zéro (§ 2.4) **sans** aucune migration 45x.
3. Jouez la suite **sans** `ON_ERROR_STOP` (on veut lire tous les verdicts) :
   ```bash
   docker exec -i -w /app pg_p5 psql -U postgres -d test_compta -f sql/450_chain_integrite_referentielle_tests.sql 2>&1 | grep -E '✅|❌|scénario'
   ```
4. **Ce qu'on doit voir** : `[450] 14 scénario(s) : 2 vert(s)` — **T05 et T13 verts**
   (ce sont des non-régressions), **les 12 autres rouges**. Copiez cette sortie : c'est
   la moitié « avant » de votre preuve.

> ❗ Si un autre scénario que T05 et T13 est vert ici, **arrêtez-vous** : quelqu'un a
> déjà corrigé une partie du défaut, et ce plan ne correspond plus au dépôt.

### 5.2 — Le registre des types (migration 450) (≈ 0,5 j)

1. Copiez : `cp ../doc/audit/partie-5/450_chain_document_types.sql sql/`
2. **Lisez-le en entier** (≈ 130 lignes). Il :
   - crée `chain_document_types (code, table_name, ligne_table, libelle_fr)`. Un type =
     une table ; `code = table_name` est imposé par une contrainte ;
   - y inscrit les **27 types** (annexe A) ;
   - **vérifie à l'application** que chaque table existe et porte `id` et `tenant_id`
     (une faute de frappe fait échouer la migration, c'est voulu) ;
   - pose deux clés étrangères `document_links.amont_type` et `aval_type` → registre,
     d'abord `NOT VALID`, puis les **valide** s'il n'existe aucun type inconnu. Sinon il
     affiche un avis (`NOTICE`) qui nomme les types à nettoyer ;
   - ajoute l'index `ix_document_links_amont_ligne` (la garde 453 en a besoin) ;
   - active la RLS, une seule politique **de lecture**, et **aucun** droit d'écriture.
     La table est **globale** (pas de `tenant_id`) : elle n'entre donc ni dans la
     grille G1 ni dans G7.
3. Appliquez : `node run-sql-migrations.mjs | grep -E '450|RÉSULTAT'`.
4. **Contrôles** :
   ```bash
   p5sql -Atc "select count(*) from chain_document_types"
   p5sql -Atc "select conname, convalidated from pg_constraint where conname like 'document_links_%_type_fk'"
   ```
   Attendu : `27`, puis deux lignes avec `t` (validées).

**Si vous ajoutez un jour un maillon** qui relie un nouveau type : inscrivez-le **dans la
même migration que le maillon** (`INSERT INTO chain_document_types …`) **et** posez-y la
garde (voir 5.5). La suite 450 (T01 et T11) échoue sinon, et c'est voulu.

### 5.3 — `link_documents` vérifie l'existence (migration 451) (≈ 0,5 j)

1. Copiez : `cp ../doc/audit/partie-5/451_chain_link_existence.sql sql/`
2. Ce fichier :
   - crée `chain_document_existe(société, type, id, ligne)`. C'est **la seule** fonction
     qui transforme un type en table, par le registre. Elle répond `false` pour un type
     inconnu. Elle est `SECURITY DEFINER` et **non exposée** (droits retirés à `PUBLIC`,
     `anon`, `authenticated`) ;
   - réécrit `link_documents` **à l'identique** du corps de la 402, en ajoutant **4
     contrôles** juste après les contrôles existants : amont, ligne amont, aval, ligne
     aval. Un refus lève `23503` (`foreign_key_violation`), et PostgREST le rend en 409.
3. **Pourquoi c'est sûr pour les 23 maillons** : mesuré le 02/10, **tous** appellent
   `link_documents` **après** l'écriture du document (déclencheurs `AFTER`, ou
   fonctions RPC qui insèrent avant de lier). Le document existe donc toujours au
   moment du contrôle. Liste : annexe B.
4. **Le coût** : le banc G6 mesure `link_documents` à **0,58 ms** au p95 (contre 0,07 ms
   avant). Le budget est de 50 ms ; c'est acceptable, mais ne l'appelez pas dans une
   boucle de 100 000 sans y penser.
5. **Ne touchez pas aux droits** : `link_documents` reste exécutable par `service_role`
   seulement, comme avant. Le fichier réaffirme le `REVOKE` pour `PUBLIC`, `anon` et
   `authenticated`.

### 5.4 — Fermer les orphelins existants (migration 452) (≈ 0,25 j)

1. Copiez : `cp ../doc/audit/partie-5/452_chain_orphelins_reprise.sql sql/`
2. Ce fichier crée `chain_fermer_orphelins(société DEFAULT NULL)`. Elle parcourt les
   liens **actifs** et **ferme** (`etat = 'rompu'`, `ferme_le = now()`, motif daté) tout
   lien dont l'amont, l'aval ou la ligne amont n'existe plus. Elle rend le nombre de
   liens fermés et **ne supprime jamais rien** (un lien est l'histoire de ce qui s'est
   passé). Elle est rejouable : un second appel rend `0`.
3. La migration l'appelle une fois pour toutes les sociétés et affiche
   `452 : N lien(s) orphelin(s) fermé(s)`. Sur une base neuve, N = 0 ; sur votre base
   de développement, vous verrez peut-être des dizaines de liens (ceux des anciennes
   suites de test).
4. Elle est réservée à `service_role`. Sur une **copie de production** (partie 4,
   tâche 4.8), l'exécuter et **noter le nombre** dans le journal de rejeu.

### 5.5 — La garde de suppression (migration 453) (≈ 0,75 j)

1. Copiez : `cp ../doc/audit/partie-5/453_chain_delete_guard.sql sql/`
2. **La règle** : on ne supprime pas un document (ou une ligne amont) qu'un lien
   **actif** relie. Un document **annulé par son chemin d'annulation** (qui ferme ses
   liens : migrations 410, 412) se supprime normalement.
3. **Une seule fonction**, `chain_refuser_suppression_liee()`, posée en
   `BEFORE DELETE … FOR EACH ROW` par une boucle sur le registre :
   - `zz_garde_p5_suppression` sur les **27 tables** de documents (mode `document` :
     le document est amont **ou** aval d'un lien actif) ;
   - `zz_garde_p5_suppression_ligne` sur les **5 tables de lignes** (mode `ligne` : la
     ligne est l'`amont_ligne_id` d'un lien actif).
4. **Le refus** : `RAISE EXCEPTION 'CHAIN_DELETE_REFUSED'` avec `ERRCODE = '23503'`,
   `DETAIL` = JSON `{type, mode, id, liens:[{effet, vers, vers_id, sens}]}` et `HINT` en
   français. Le message est un **code** : c'est l'écran qui le traduit (étape 5.10).
   Pourquoi `23503` : `apply_chart_pack` sait déjà transformer ce code en « compte
   marqué obsolète » au lieu d'échouer. Le code d'erreur s'intègre donc sans casse.
5. **La suppression d'une société entière passe** : la garde regarde si la ligne
   `tenants` existe encore. Pendant la cascade `ON DELETE CASCADE`, elle n'existe plus,
   et la garde laisse passer (scénario T13).
6. **L'exception métier, la seule** : un **compte bancaire sans aucune opération** se
   supprime toujours. C'est la règle de la migration 244, gardée par sa suite (T04).
   Or sa création pose deux liens (vers son journal et son compte comptable). Le
   compagnon `zz_garde_p5_0_banque_vide` **ferme** ces deux liens (`rompu`, motif) juste
   avant la garde. La suppression passe et ne laisse **aucun** orphelin actif (T06).
7. ⚠️ **Le NOM des déclencheurs est imposé.** PostgreSQL exécute les déclencheurs d'un
   même moment **dans l'ordre alphabétique de leur nom**. Les suites 316 (T10) et 321
   (T05) exigent qu'aucun déclencheur ne se trie **après** un compagnon `zz_l1_…`.
   `zz_garde_…` se trie avant `zz_l1_…`. **Mesuré** : avec un nom en `zz_p5_…`, ces deux
   suites rougissent. Et `zz_garde_p5_0_…` doit se trier avant `zz_garde_p5_s…`, pour que
   le compagnon ferme les liens avant que la garde ne les voie.
8. **Contrôle** :
   ```bash
   p5sql -Atc "select count(*) from pg_trigger where tgname like 'zz_garde_p5_suppression%'"
   ```
   Attendu : `32`.

### 5.6 — Libérer une réservation sans la supprimer (migration 454) (≈ 0,5 j)

1. Copiez : `cp ../doc/audit/partie-5/454_stock_reservation_release.sql sql/`
2. **Pourquoi** : l'écran des réservations (`releaseStockReservation`,
   `src/lib/queries/stock.ts`) faisait `DELETE FROM stock_reservations`. La garde 453
   le refuse désormais, puisque la réservation est l'**aval** d'un lien actif. Et il y
   avait un **second défaut** : `stock_reservations` n'a **aucun** déclencheur, donc la
   suppression ne rendait **jamais** `stock_quantities.reserved_quantity`. Le stock
   restait bloqué.
3. `release_stock_reservation(p_reservation_id)` fait exactement ce que fait déjà
   l'annulation d'une commande (`release_stock_on_sales_order_cancel`) :
   - refuse sans société active, et refuse si le rôle n'a pas
     `can_perform('stock_reservations', 'update')` (un lecteur ne libère rien : T10) ;
   - refuse une réservation absente ou déjà inactive ;
   - **décrémente** `reserved_quantity` au dépôt, passe la réservation à `released`,
     puis **ferme** le lien commande → réservation par `chain_lien_fermer(…, 'rompu',
     motif)`.
4. Droits : `EXECUTE` pour `authenticated`, retiré à `PUBLIC` et `anon`. La porte G4
   (`check_tenant_guard`) l'accepte : elle mentionne la société (`current_tenant_id()`).

### 5.7 — Adapter les suites 252 et 402 (≈ 0,5 j)

**Pourquoi elles cassent** : elles posent des liens de type `commande` → `livraison`
(deux types qui n'existent pas) avec des identifiants tirés au hasard. Le registre et
le contrôle d'existence les refusent désormais. **Mesuré** : 252 et 402 rouges sans
adaptation, **17/17 et 12/12** avec.

```bash
python3 ../doc/audit/partie-5/adapt_252_402.py sql
```

Ce que fait le script (vous pouvez le faire à la main à l'identique) :

1. remplace les littéraux `'commande'` → `'sales_orders'` et `'livraison'` →
   `'delivery_notes'` (35 + 3 dans la 252, 30 + 4 dans la 402) ;
2. dans la 402, remplace `LIKE '%commande%'` par `LIKE '%sales_orders%'` : le scénario
   C06 vérifie que le message de refus **nomme** le type, et il le nomme désormais
   `sales_orders` ;
3. ajoute l'aide `_p5_doc(société, type, id, ligne)`. Elle crée la vraie commande en
   brouillon, le vrai bon de livraison en attente, et la ligne de commande qui portent
   l'identifiant tiré au hasard. Elle ne fait rien si la société ou l'identifiant est
   `NULL` : ces scénarios testent justement le refus de `link_documents` ;
4. fait appeler `_p5_doc` par l'aide de lien du fichier (`_lien252`, `_l312_lien`)
   **avant** `link_documents`.

Ensuite :
```bash
p5sql -f sql/252_chain_socle_tests.sql | tail -1
p5sql -f sql/402_chain_lien_cycle_tests.sql | tail -1
```
Attendu : `[252] 17 scénario(s) : 17 vert(s)` et `[312] 12 scénario(s) : 12 vert(s)`
(la suite 402 s'annonce encore `[312]` : c'est son ancien numéro, le registre des échecs
la connaît sous ce nom).

### 5.8 — Adapter le banc de performance G6 (≈ 0,25 j)

**Pourquoi il casse** : `sql/ci/check_chain_performance.sql` pose 1 000 liens de type
`zz_doc` → `zz_aval` sur des identifiants aléatoires.

```bash
python3 ../doc/audit/partie-5/adapt_g6.py sql/ci/check_chain_performance.sql
p5sql -f sql/ci/check_chain_performance.sql 2>&1 | grep 'p95 total'
```

Le script remplace les types inventés par `sales_orders` et crée, **à chaque tour et
avant le chronomètre**, une vraie commande en brouillon. Le banc mesure donc toujours les
quatre mêmes appels, contrôle d'existence compris. Attendu : une ligne
`p95 total ≈ 1 ms`, très loin du budget de 50 ms.

### 5.9 — INV-19 devient mesurable (migration 455) et la suite 413 suit (≈ 0,25 j)

La 455 réécrit `chain_invariant_mesurer` (≈ 300 lignes). **On ne la recopie pas à la
main** : on la **génère** depuis le corps actuel de la fonction, pour ne rien perdre de
ce que d'autres migrations auraient ajouté depuis.

1. Sur votre base **à jour** (toutes les migrations du dépôt + 450 → 454) :
   ```bash
   p5sql -Atc "select pg_get_functiondef('chain_invariant_mesurer'::regproc)" > /tmp/mesurer.sql
   python3 ../doc/audit/partie-5/gen455.py /tmp/mesurer.sql sql/455_chain_inv19_mesurable.sql
   ```
2. **Ouvrez le fichier produit et lisez-le.** Vous devez y trouver :
   - un `UPDATE chain_invariants SET mesurable = true, raison_non_mesurable = NULL WHERE
     code = 'INV-19' AND tenant_id IS NULL;` ;
   - trois variables de plus dans le `DECLARE` (`v_t`, `v_ids`, `v_lot`) ;
   - une branche `ELSIF p_code = 'INV-19' THEN …` **juste avant** la branche finale
     `ELSE RAISE EXCEPTION … n'a aucune branche de mesure` ;
   - **tout le reste identique** au corps relevé.
3. Ce que mesure la branche : pour chaque type du registre, les liens **actifs** dont
   l'amont, l'aval ou la ligne amont n'existe plus dans la société, plus les liens dont
   le type n'est pas au registre. Chaque lien est compté **une seule fois**. Le
   `lignes_en_ecart` vaut ce nombre, et `audit_chains` en déduit le verdict : `rompu`
   s'il est supérieur à 0, sens `existence`.
4. La suite **413** figeait « 13 mesurables / 7 non mesurables ». Le comportement a
   changé : 14 / 6. Mettez-la à jour :
   ```bash
   python3 ../doc/audit/partie-5/adapt_413.py sql/413_chain_l4_invariants_tests.sql
   ```
   Le script applique **10 remplacements** sur T01, T02, T03 et T05. Chacun est **daté**
   et l'**ancien verdict est conservé en commentaire**. C'est la doctrine du dépôt :
   les assertions changent de nombre, pas de nature.

> ⚠️ **Si une autre migration réécrit `chain_invariant_mesurer` après la 455**
> (partie 3, ou une correction d'invariant), elle **doit** partir du corps relevé sur
> une base qui contient la 455, sinon elle efface la branche INV-19 sans bruit. La
> suite 450 (T12) le détecte. Le jour où cela arrive, la CI le dira.

### 5.10 — L'écran : le message de refus, la libération, la porte (≈ 0,5 j)

```bash
python3 ../doc/audit/partie-5/apply_front.py .
```

Le script fait cinq modifications, chacune vérifiable :

| fichier | changement |
|---|---|
| `scripts/check-unused-tables.mjs` | `chain_document_types` est ajoutée à `SERVER_ONLY_TABLES`, avec sa justification (lue par `link_documents`, la garde, INV-19 ; l'écran traduit les types par i18n). Sans elle, la porte compterait une table non lue de plus. |
| `src/lib/utils.ts` | nouvelle fonction `chainDeleteRefusalMessage(err)`. `errorMessage(err)` l'appelle **en premier**. Elle reconnaît `message === 'CHAIN_DELETE_REFUSED'`, lit le `details` JSON et rend la phrase traduite. Les **788** `catch` qui affichent `errorMessage(err)` en bénéficient sans changement. |
| `src/lib/queries/stock.ts` | `releaseStockReservation(id)` appelle `supabase.rpc('release_stock_reservation', { p_reservation_id: id })` au lieu de `DELETE`. Sa signature ne change pas, donc `StockReservationsPage.tsx` n'a rien à modifier. |
| `src/i18n/locales/{fr,en,ar}/errors.json` | clés `chain.deleteRefused` (avec `{{document}}`, `{{count}}`, `{{vers}}`) et `chain.types.<code>` pour les **27** types, dans les trois langues |
| `src/lib/__tests__/chainDeleteRefusal.test.ts` | 4 tests : le message est traduit, nomme le document et les types reliés ; `errorMessage` le traduit même pour une instance d'`Error` (le client Supabase en rend une) ; les autres erreurs sont inchangées ; un détail illisible ne fait pas planter. |

> 🌐 **Traduction arabe** : les libellés arabes ont été écrits pour ce plan. **Faites-les
> relire par un arabophone** avant la recette (c'est déjà une limite connue du lot I).

### 5.11 — La garde W10 précisée (à la main) (≈ 0,5 j, avec la vérification complète)

Après 5.10, **un** test Vitest échoue :
`rpc-contract.test.ts > le front ne remet pas le stock à jour lui-même`. Il interdit
**tout** `.rpc(` dans `stock.ts`. Son objet (vague W10) était d'interdire au front de
recalculer la **quantité** (`increment_stock` / `decrement_stock`). Or
`release_stock_reservation` laisse la base rendre la quantité réservée : c'est le moteur
unique, pas un second.

Dans `src/lib/__tests__/rpc-contract.test.ts`, remplacez la ligne
`expect(code).not.toMatch(/\.rpc\(/)` par :

```ts
    // AAAA-MM-JJ (Partie 5, 454) : assertion PRÉCISÉE. Elle interdisait tout
    // `.rpc(` dans stock.ts ; son objet est que le front ne recalcule pas la
    // QUANTITÉ en stock (W10 : increment_stock / decrement_stock appelés après
    // l'insertion du mouvement). `release_stock_reservation` (454) laisse la
    // base rendre la quantité réservée : c'est le moteur unique, pas un second.
    // Verdict précédent : expect(code).not.toMatch(/\.rpc\(/)
    expect(code).not.toMatch(/\.rpc\(\s*['"](increment_stock|decrement_stock|update_stock[a-z_]*|adjust_stock[a-z_]*)['"]/)
```

Puis vérifiez **tout** le front :

```bash
npx tsc -b --noEmit && npx oxlint --max-warnings=0 && npx vitest run
node scripts/check-i18n.mjs && node scripts/check-i18n-usage.mjs
node scripts/check-unused-tables.mjs && node scripts/check-knip-ceiling.mjs
node scripts/check-any-ceiling.mjs && node scripts/check-console-error-ceiling.mjs
node scripts/check-rpc-contract.mjs && node scripts/check-written-columns.mjs && node scripts/check-unchecked-writes.mjs
```

Tout doit être vert. Vitest : **0 échec** (mesuré : 1 543 verts).

### 5.12 — Câbler la suite, régénérer les types, rejouer TOUT (≈ 0,5 j)

1. **Câbler la suite 450** dans `.github/workflows/ci.yml`, job `db-integration`,
   **juste après** l'étape `'L4 : les 20 invariants transversaux et l''indice (413)'`
   (même indentation, 6 espaces) :
   ```yaml
         # Partie 5 (450 → 455) : l'intégrité référentielle des chaînages. Un lien ne
         # se pose que vers des documents qui existent (registre des types + contrôle
         # d'existence), un document relié par un lien ACTIF ne se supprime pas, une
         # réservation se libère sans être supprimée, et INV-19 se mesure.
         - name: 'Partie 5 : intégrité référentielle des chaînages (450)'
           run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/450_chain_integrite_referentielle_tests.sql
           env:
             DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test_compta
   ```
   La porte G5 (`node scripts/check-test-suites.mjs`) doit dire
   `✅ Toutes les suites du dépôt (N) sont jouées par la CI`.
2. **Régénérer les types**, sur une base **neuve** (§ 2.4) qui contient 450 → 455 :
   ```bash
   npm run db:types
   git diff --stat src/types/database-generated.ts
   ```
   Attendu : **≈ 24 lignes** ajoutées, uniquement la table `chain_document_types`
   (`Row`, `Insert`, `Update`, `Relationships`). Si le diff touche autre chose, une
   autre session a changé le schéma : **ne le commitez pas avec le vôtre**, demandez.
3. **Rejouer le job base complet, sans s'arrêter au premier rouge.** Toutes les étapes
   `psql … -f sql/…` du job `db-integration` de `ci.yml`, dans l'ordre. Attendu : toutes
   vertes, notamment **244**, **252**, **312** (fichier 402), **316** (fichier 406),
   **321** (fichier 411), **413**, **450**, G1, G2, G4, G6 et G7.
4. **Rejouer le chemin de l'écran** (job `screen-path`) : 15/15 fichiers, 125/125
   verdicts (mesuré).

### 5.13 — La preuve et la mise à jour des documents (≈ 0,25 j)

1. Écrire `doc/audit/VAGUE-PARTIE-5-AAAA-MM-JJ.md`, en suivant le modèle des autres
   preuves : la mesure avant (§ 0 de ce document), la sortie rouge de 5.1, la sortie
   verte, les chiffres de 5.12, et les limites (§ 8).
2. Mettre à jour :
   - `AGENTS.md` : un paragraphe daté « Partie 5 livrée » ;
   - l'en-tête des parties 1 à 4 : ajouter la ligne de la partie 5 à leur tableau.
3. Dans la partie 4, tâche **4.8** (rejeu sur copie de production) : ajouter
   « exécuter `select chain_fermer_orphelins(NULL)` et noter le nombre ».

## 4. Les 14 scénarios de la suite 450

| # | ce qu'il prouve | avant (≤ 413) | après |
|---|---|:-:|:-:|
| T01 | registre complet : 27 types, tables présentes, **chaque type écrit en dur dans un maillon est inscrit** (analyse de `pg_proc`) | ❌ | ✅ |
| T02 | un type inconnu (`commande`) est refusé, `23503` | ❌ | ✅ |
| T03 | un amont inexistant, et un amont d'une **autre société**, sont refusés | ❌ | ✅ |
| T04 | une ligne amont inexistante est refusée ; une ligne réelle donne un lien | ❌ | ✅ |
| T05 | confirmer une commande pose toujours son lien (non-régression) | ✅ | ✅ |
| T06 | D1 : un compte bancaire **sans opération** se supprime, et ses 2 liens sont **fermés** | ❌ | ✅ |
| T07 | D2 : un règlement client comptabilisé ne se supprime pas | ❌ | ✅ |
| T08 | D3 : une commande confirmée et sa ligne ne se suppriment pas ; **annulée**, elle se supprime | ❌ | ✅ |
| T09 | D4 : une réservation ne se supprime pas ; `release_stock_reservation` rend 3 → 0, ferme le lien ; ensuite elle se supprime | ❌ | ✅ |
| T10 | un lecteur ne libère pas une réservation (`42501`) | ❌ | ✅ |
| T11 | structure : 32 gardes posées, fonctions internes non exposées | ❌ | ✅ |
| T12 | INV-19 mesurable : orphelin → `rompu`, fermeture (1 puis 0), puis `tenu` | ❌ | ✅ |
| T13 | supprimer une société entière passe (cascade) | ✅ | ✅ |
| T14 | D5 : le journal et le compte comptable d'une banque (aval) ne se suppriment pas | ❌ | ✅ |

Chaque scénario capture sa propre erreur (`EXCEPTION WHEN OTHERS THEN PERFORM _rec(…,
false, SQLERRM)`) : un scénario qui plante est **rouge**, jamais silencieux. La suite se
termine par `SELECT _audit_assert('450');`. Sans cette ligne, un rouge ne ferait jamais
échouer la CI (c'est le défaut corrigé en 1.2 pour la caisse).

## 5. Ce qui change pour les utilisateurs

À écrire dans les notes de version, et à passer dans la recette (partie 4).

> **Ce qui est mesuré et ce qui est déduit.** Les lignes « commande confirmée »,
> « règlement client », « compte bancaire sans opération » et « libérer une
> réservation » sont **mesurées** (suite 450, T06 → T09). Les lignes « salarié »,
> « tâche » et « pack de plan comptable » sont **déduites** de la structure (clés
> `ON DELETE CASCADE` + garde, et `apply_chart_pack` qui intercepte `23503`) : elles
> n'ont pas été rejouées une à une. **Elles sont à dérouler en recette** avant d'être
> annoncées aux utilisateurs.


| Geste | Avant | Après |
|---|---|---|
| Supprimer une commande **confirmée** | accepté ; réservation bloquée à vie | **refusé** : « annulez-la d'abord ». Annulée, elle se supprime |
| Supprimer un règlement client ou fournisseur **comptabilisé** | accepté ; facture « payée » sans règlement | **refusé** (il faut un chemin d'annulation : voir § 8) |
| Supprimer un compte bancaire **sans opération** | accepté | accepté (et ses liens sont fermés proprement) |
| Supprimer un compte bancaire **avec** opérations | refusé (244) | refusé (244) |
| « Libérer » une réservation | ligne supprimée, quantité **non rendue** | réservation `released`, quantité **rendue** |
| Supprimer un salarié qui a une note de frais **intégrée** | accepté (cascade) | **refusé** (la note de frais est reliée à son écriture) |
| Supprimer une tâche dont un temps est **déjà facturé** | accepté (cascade jusqu'à la ligne de facture) | **refusé** |
| Réappliquer un pack de plan comptable sur un compte lié à une banque | compte supprimé | compte **marqué obsolète** (`apply_chart_pack` intercepte `23503`) |

Le message affiché est, en français : « Suppression refusée : ce document (Commande
client) est relié à 1 document(s) par la chaîne (Réservation de stock). Annulez-le
d'abord : l'annulation ferme ces liens. »

## 6. Les commits, dans l'ordre

Chaque commit doit laisser la CI **verte**. D'où cet ordre, et pas un autre :

| # | contenu | pourquoi ensemble |
|---|---|---|
| 1 | 5.0 — la plage inscrite | documentation seule |
| 2 | 450 + 451 + 452 + **les adaptations 252/402 et G6** (5.7, 5.8) + la suite 450 (ses scénarios de registre et d'existence verts, les autres encore rouges) **inscrite au registre** `ci/expected_failures.sql` pour T06→T12, T14 + câblage CI + `db:types` | sans les adaptations, 252, 402 et G6 rougissent dès la 451 |
| 3 | 453 + 454 + l'écran (5.10, 5.11) + retrait du registre des scénarios devenus verts | sans 454 et sans l'écran, la libération de réservation casse dès la 453 |
| 4 | 455 + adaptation 413 (5.9) + retrait de T12 du registre | sans l'adaptation, la 413 rougit dès la 455 |
| 5 | 5.13 — la preuve et les documents | |

> Plus simple, et accepté : **un seul commit** pour 2 → 4, si vous le faites dans la
> journée. Ce qui est interdit, c'est un commit intermédiaire rouge **sans** que ses
> rouges soient inscrits au registre.

Format des messages, comme le dépôt :
`feat(partie 5) : un lien ne se pose que vers des documents qui existent (450, 451, 452)`.
Terminez chaque message par la ligne de co-auteur demandée par le dépôt.

## 7. Critères de sortie

- [ ] la plage `450 → 459` est inscrite (AGENTS.md et NUMEROTATION) ;
- [ ] 6 migrations `450` → `455` ; base neuve **0 erreur** ; chaque migration
      **rejouable** (la rejouer une seconde fois ne lève rien) ;
- [ ] suite 450 : **14/14**, sortie rouge « avant » archivée dans la preuve ;
- [ ] 244, 252, 312 (402), 316 (406), 321 (411), 413 vertes ; banc G6 dans le budget ;
- [ ] `plpgsql_check` : 0 erreur (porte de la CI) ;
- [ ] types régénérés (≈ 24 lignes, `chain_document_types` seulement) ;
- [ ] Vitest 0 échec ; `tsc`, `oxlint`, i18n, plafonds, porte des tables non lues :
      verts ;
- [ ] chemin de l'écran 15/15 ;
- [ ] **passage GitHub vert** sur le dernier commit, lien dans la preuve ;
- [ ] registre `ci/expected_failures.sql` revenu à son état d'entrée.

## 8. Ce que cette partie ne fait pas

1. **Pas de chemin d'annulation pour tous les documents.** Un règlement comptabilisé,
   une note de frais intégrée, une session de caisse clôturée deviennent **non
   supprimables**, ce qui est juste. Mais leur **annulation** (contrepassation +
   fermeture des liens) n'existe pas pour tous. À inscrire à l'horizon suivant, un
   type à la fois, sur le modèle de la 410 (commande, BL, réception) et de la 412
   (caisse).
2. **`chain_traces.amont_type` et `domain_events.aggregate_type` restent du texte
   libre.** On ne leur a pas posé de clé étrangère : `domain_events` porte aussi des
   agrégats qui ne sont pas des documents (`chain_settings`), et les suites du socle y
   écrivent des types d'essai. INV-19 ne regarde que `document_links`. À décider plus
   tard.
3. **INV-03 reste grossier.** Il ne voit une réservation orpheline que si la société
   n'a **aucune** commande confirmée non livrée (mesuré : il a vu D3 parce que la
   société de test n'en avait pas d'autre). La garde 453 empêche désormais le cas D3,
   mais INV-03 mériterait d'être mesuré réservation par réservation. Ce n'est pas dans
   cette partie.
4. **Les suites de test qui suppriment des sociétés en désactivant les déclencheurs**
   (`session_replication_role`) laissent des liens sans société. Ce sont des artefacts
   de test, pas un chemin de production. Ils ne gênent rien : la reprise 452 et INV-19
   ne regardent que les sociétés existantes.
5. **La traduction arabe** des 27 libellés est à faire relire.

---

## Annexe A — les 27 types du registre

| type (= table) | table de lignes | libellé |
|---|---|---|
| `bank_accounts` | | Compte bancaire |
| `bank_transactions` | | Opération bancaire |
| `chart_accounts` | | Compte comptable |
| `credit_notes` | | Avoir client |
| `customer_payments` | | Règlement client |
| `delivery_notes` | `delivery_note_lines` | Bon de livraison |
| `expense_reports` | | Note de frais |
| `goods_receipts` | `goods_receipt_lines` | Réception de marchandise |
| `invoice_lines` | | Ligne de facture |
| `invoices` | | Facture client |
| `journal_entries` | | Écriture comptable |
| `journal_lines` | | Ligne d'écriture |
| `journals` | | Journal comptable |
| `manufacturing_orders` | | Ordre de fabrication |
| `payroll_variable_elements` | | Élément variable de paie |
| `pay_runs` | | Lot de paie |
| `pos_payments` | | Paiement de caisse |
| `pos_sessions` | | Session de caisse |
| `pos_tickets` | | Ticket de caisse |
| `project_time_entries` | | Temps passé sur projet |
| `purchase_invoices` | | Facture fournisseur |
| `sales_orders` | `sales_order_lines` | Commande client |
| `stock_movements` | | Mouvement de stock |
| `stock_reservations` | | Réservation de stock |
| `st_receipts` | `st_receipt_lines` | Réception de sous-traitance |
| `st_shipments` | `st_shipment_lines` | Expédition de sous-traitance |
| `supplier_payments` | | Règlement fournisseur |

Toutes portent `id` (clé primaire) et `tenant_id` : c'est ce qui permet **une seule**
garde et **une seule** fonction d'existence.

## Annexe B — les 23 maillons qui posent des liens

28 appels à `link_documents` dans 23 fonctions, relevés dans `pg_proc` le 02/10. **Tous**
s'exécutent après l'écriture du document : le contrôle d'existence ne les gêne pas.

| fonction | quand | amont → aval |
|---|---|---|
| `chain_l1_bank_account_ledger` | AFTER sur `bank_accounts` | compte bancaire → journal, compte comptable |
| `chain_l1_bank_reconciliation`, `chain_l1_statement_line_matched` | AFTER sur `bank_transactions` | opération → règlement client, ligne d'écriture |
| `chain_l1_credit_note_entry` | AFTER sur `credit_notes` | avoir → écriture |
| `chain_l1_customer_payment_entry`, `chain_l1_payment_exchange_gain_loss` | AFTER sur `customer_payments` | règlement → écriture |
| `create_stock_out_on_delivery` | AFTER sur `delivery_notes` | BL (par ligne) → mouvement |
| `chain_l1_expense_report_integration` | AFTER sur `expense_reports` | note de frais → écriture, élément de paie |
| `create_stock_on_goods_receipt` | AFTER sur `goods_receipts` | réception (par ligne) → mouvement |
| `chain_l1_invoice_entry` | AFTER sur `invoices` | facture → écriture |
| `chain_l1_manufacturing_order` | AFTER sur `manufacturing_orders` | OF → écriture, mouvement |
| `chain_l1_pay_recall_integration`, `chain_l1_salary_advance_integration`, `chain_l1_payroll_run_reversal` | AFTER sur `pay_runs` | lot → éléments de paie, écriture |
| `chain_l1_pos_session_closure` | AFTER sur `pos_sessions` | session → écriture |
| `chain_l1_time_entry_billed` | AFTER sur `project_time_entries` | temps → ligne de facture |
| `chain_l1_purchase_invoice_entry` | AFTER sur `purchase_invoices` | facture fournisseur → écriture |
| `reserve_stock_on_sales_order_confirm` | AFTER sur `sales_orders` | commande (par ligne) → réservation |
| `st_receipt_stock_in`, `st_shipment_stock_out` | AFTER sur `st_receipts` / `st_shipments` | (par ligne) → mouvement |
| `chain_l1_supplier_payment_entry` | AFTER sur `supplier_payments` | règlement fournisseur → écriture |
| `create_pos_ticket`, `pos_refund_ticket` | RPC (insèrent, puis lient) | ticket → mouvement, paiement, avoir |

## Annexe C — les suppressions de l'écran, avant et après

Les 28 fonctions de `src/lib/queries/` qui font `.from(<table reliée>).delete()`
(relevé statique du 02/10). Elles ne changent pas de code, sauf `releaseStockReservation`.
Ce qui change, c'est qu'elles peuvent recevoir le refus traduit.

> ⚠️ La colonne « refusée quand » est **déduite** de la garde et des liens que posent
> les maillons (annexe B). Seuls les cas des scénarios T06 → T09 et T14 sont
> **mesurés**. **Chaque ligne est à dérouler dans la recette** (partie 4, tâche 4.6) :
> une suppression de chaque sorte, avec et sans lien actif.

| fonction | table | refusée quand |
|---|---|---|
| `deleteBankAccount` (banking.ts) | bank_accounts | le compte a des opérations (244) ; sinon acceptée |
| `deleteBankTransaction` (banking.ts) | bank_transactions | l'opération a été rapprochée (lien actif) |
| `deleteChartAccount` (accounting/accounts.ts) | chart_accounts | le compte a été créé pour une banque |
| `deleteCreditNote` (sales.ts) | credit_notes | l'avoir est validé (garde existante, puis lien) |
| `deleteCustomerPayment` (partners.ts) | customer_payments | le règlement est comptabilisé |
| `deleteDeliveryNote` (sales.ts) | delivery_notes | le BL a sorti du stock et n'est pas annulé |
| `deleteEmployee` (payroll.ts) | employees → cascade | une note de frais ou un élément de paie du salarié est relié |
| `deleteMyExpenseReport` (sprintDE.ts) | expense_reports | la note est intégrée |
| `deleteGoodsReceipt` (misc/commercial.ts) | goods_receipts | la réception a fait entrer du stock et n'est pas annulée |
| `deleteInvoice` (sales.ts) | invoices | la facture est validée (garde existante) |
| `deleteJournalEntry` (accounting/journal.ts) | journal_entries | l'écriture est validée (garde existante) ou est l'aval d'un lien |
| `deleteJournal` (misc/reporting.ts) | journals | le journal a été créé pour une banque |
| `deleteManufacturingOrder` (production.ts) | manufacturing_orders | l'OF a été comptabilisé |
| `deletePayRun` (payroll.ts) | pay_runs | garde existante, puis lien |
| `deleteVariableElement` (leavesAbsences.ts) | payroll_variable_elements | l'élément vient d'une note de frais ou d'un rappel |
| `deletePosTerminal` (posAdvanced.ts) | pos_terminals → cascade | une session ou un ticket du terminal est relié |
| `deleteProduct` (stock.ts) | products → cascade lignes de sous-traitance | une ligne de sous-traitance est reliée |
| `deleteTask` (projectManagement.ts) | project_tasks → cascade | un temps de la tâche est facturé |
| `deleteTimeEntry` (projectManagementSprint1.ts) | project_time_entries | le temps est facturé |
| `deletePurchaseInvoice` (sales.ts) | purchase_invoices | la facture est approuvée (garde existante, puis lien) |
| `deleteSalesOrder` (sales.ts) | sales_orders | la commande est confirmée et non annulée |
| `deleteSTOrder`, `deleteSTReceipt`, `deleteSTShipment`, `deleteSTReceiptLine`, `deleteSTShipmentLine` (stock.ts) | sous-traitance | l'expédition ou la réception a mouvementé le stock |
| `deleteSupplierPayment` (partners.ts) | supplier_payments | le règlement est comptabilisé |
| `releaseStockReservation` (stock.ts) | — | **ne supprime plus** : appelle `release_stock_reservation` |

## Annexe D — dépannage

| symptôme | cause | quoi faire |
|---|---|---|
| `450 : le type X désigne la table Y qui n'existe pas` | faute de frappe dans le registre, ou table renommée | corriger la ligne du registre |
| `NOTICE: 450 : types inconnus présents (commande, livraison)` | base de développement qui garde des liens d'anciennes suites | `select chain_fermer_orphelins(NULL);` ne suffit pas (le type reste) : supprimez ces liens **de test** (`DELETE FROM document_links WHERE amont_type IN (...)`), puis `ALTER TABLE document_links VALIDATE CONSTRAINT document_links_amont_type_fk;` (et `_aval_type_fk`). **Jamais en production.** |
| un maillon lève `Chaînage refusé : le document amont … n'existe pas` | le maillon lie **avant** d'avoir écrit le document (déclencheur `BEFORE`) | le passer en `AFTER`, ou lier après l'`INSERT` |
| `Chaînage refusé : … son type n'est pas inscrit au registre` | nouveau maillon, nouveau type | l'inscrire dans la migration du maillon + poser la garde |
| 316 T10 ou 321 T05 rouges après 453 | les déclencheurs ont un nom qui se trie après `zz_l1_` | les nommer `zz_garde_p5_…` (voir 5.5, point 7) |
| 244 T04 rouge | le compagnon `zz_garde_p5_0_banque_vide` manque, ou se trie après la garde | vérifier son nom et sa présence |
| 413 T01/T02/T03/T05 rouges | la 455 est posée, pas l'adaptation | `adapt_413.py` (5.9) |
| `rpc-contract.test.ts … ne remet pas le stock à jour` rouge | 5.10 fait, 5.11 pas | appliquer 5.11 |
| `check-unused-tables` : une table de plus | la ligne `chain_document_types` manque dans `SERVER_ONLY_TABLES` | relancer `apply_front.py` |
| la CI dit `Les types générés diffèrent` | `npm run db:types` oublié, ou lancé sur une base qui n'est pas neuve | régénérer sur base neuve (§ 2.4), commiter |
| un écran affiche `CHAIN_DELETE_REFUSED` brut | l'écran n'utilise pas `errorMessage(err)` | remplacer `err.message` par `errorMessage(err)` dans ce `catch` |

## Annexe E — ce qui a été mesuré pour écrire ce document

Le 02/10/2026, sur des copies propres des commits (jamais le dossier de travail), avec
une base PostgreSQL 16 neuve et `plpgsql_check` :

- **état d'origine** (`c51d468`) : 8 tables du socle, une seule clé étrangère chacune
  (`tenant_id`) ; 2 914 liens, 1 381 traces, 1 382 événements après les suites ;
  0 lien inter-sociétés ; 2 vrais orphelins (un compte bancaire supprimé) ; 13 liens,
  11 traces et 11 événements de sociétés supprimées par les nettoyages de test ;
  essais D1 → D5 décrits au § 0 ; INV-03 « rompu » sur D3, INV-19 « non mesurable » ;
- **inventaires** : 23 fonctions et 28 appels à `link_documents` (annexe B), tous
  après écriture ; 5 types liés par ligne ; 2 fonctions SQL qui suppriment dans une table
  reliée (`apply_chart_pack`, synchronisations d'absence), 20 clés étrangères
  `ON DELETE CASCADE` vers des tables reliées, 28 suppressions d'écran (annexe C) ;
  `stock_reservations` sans aucun déclencheur ;
- **avec la partie 5** : les chiffres du § 1, et les rouges intermédiaires qui ont
  donné les étapes 5.5 (point 7 : noms), 5.5 (point 6 : banque sans opération), 5.7,
  5.8, 5.9 et 5.11 (garde W10).
