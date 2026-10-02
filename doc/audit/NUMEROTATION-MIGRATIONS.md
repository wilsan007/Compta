# 📌 NUMÉROTATION DES MIGRATIONS — à lire AVANT d'écrire une migration

> Ce fichier est destiné à **toutes les sessions et tous les agents qui travaillent
> en parallèle sur ce dépôt**, présentes ou futures. Il n'a qu'une règle.

## La règle

**Un numéro de migration se CONSTATE, il ne se RÉSERVE pas.**

Autrement dit : rien n'empêche deux sessions de prendre le même numéro. Ce qui
l'empêche, c'est de **l'inscrire dans [`AGENTS.md`](../AGENTS.md)** — et de le
faire à la date où on le prend.

`run-sql-migrations.mjs` échoue déjà sur un doublon (porte **SOC-06**,
`exit(1)`). C'est un **garde-fou**, pas un plan : il vous prévient quand le
préjudice est fait, dans un pipeline, après que deux sessions ont travaillé.

## Les plages, au 02 octobre 2026

| Plage | Session | Inscrite le |
|---|---|---|
| `100` → `129` | fondations produit | — |
| `130` → `197` | sessions fonctionnelles | 2026-09 |
| `200` → `209` | socles | — |
| `210` → `299` | audits fonctionnels, W7/W8, L7 | 2026-09-28 |
| `300` → `309` | **W7** | 2026-09-28 |
| `310` → `324` | **session recette** (`qa/recette-2026-09-29`) | 2026-10-02 |
| **`400` → `413`** | **chaînages** (L1, L2, L3, L4) | 2026-10-02 |
| `415` → `429` | **L16 → L24** | 2026-10-02 |
| **`450` → `459`** | **Partie 5 — intégrité référentielle des chaînages** | **2026-10-02** |
| `325` → `399`, `430` → `449` | **LIBRE** | — |

## Ce qui s'est passé le 02 octobre — lisez cette histoire

La session recette a pris `310` → `324` **sans inscrire sa plage** dans
`AGENTS.md`. Les chaînages y étaient inscrits depuis le 30/09. Résultat :

- **douze numéros en collision** (`310` → `321`) ;
- après fusion, `run-sql-migrations.mjs` aurait **refusé de démarrer** ;
- pire : les noms étaient **homonymes mais les contenus différents**
  (`310_chain_l1_maillons` ≠ `310_legislation_packs_readable`) — l'ordre de
  fusion aurait appliqué les deux au **même rang**, dans un ordre arbitraire.

Le **chaînage** a été déplacé en `400` → `413`, parce que c'est **lui** qui
était inscrit. Si vous lisez ceci depuis une session démarrée **avant** le
02 octobre : votre migration était en `3xx` et porte maintenant un `4xx`.

> Deux autres défauts trouvés le même jour, pour mémoire :
> un **doublon interne** (`322` portait à la fois la caisse et les invariants
> — même série, deux migrations) était présent sur `commercial-hr-paie` ;
> et une collision supplémentaire naissait du renumérotage `322` → `323`
> tenté par une session, `323` étant déjà pris côté recette.

## Comment prendre un numéro

1. Lisez la table ci-dessus et **choisissez la prochaine libre** dans la
   plage de votre ligne de travail.
2. **Inscrivez-la dans `AGENTS.md`** — un paragraphe, daté, en tête de fichier.
3. Vérifiez avant de pousser :

   ```bash
   ls app/sql/*.sql | grep -v '_tests\.sql$' | sed 's|.*/||' | cut -c1-3 | sort | uniq -d
   ```

   **Toute ligne imprimée est un doublon** — votre `run-sql-migrations` échouera.

4. Si une session fusionne avec vous et que le numéro est disputé : **celui
   qui est inscrit dans `AGENTS.md` garde le numéro**. L'autre se déplace.
   Ce n'est pas une règle de force, c'est une règle de cohérence — elle vaut
   parce que tout le monde la suit.