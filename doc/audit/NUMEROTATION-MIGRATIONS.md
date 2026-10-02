# 📌 NUMÉROTATION DES MIGRATIONS — à lire AVANT d'écrire une migration

> Ce fichier est destiné à **toutes les sessions et tous les agents qui travaillent
> en parallèle sur ce dépôt**, présentes ou futures.

## La règle, depuis le 02/10/2026 au soir : un numéro se PREND par l'outil

**On ne crée plus jamais un fichier `app/sql/NNN_….sql` à la main.** On le prend :

```bash
cd app
npm run migration:prendre -- <nom_en_minuscules> --session "<votre ligne de travail>"
```

L'outil (`app/scripts/migration-numero.mjs`) fait, sous un verrou partagé par
**tous** les worktrees du dépôt :

1. **contrôle AVANT** : le prochain numéro de la plage de votre ligne est-il libre
   **partout** — dans les dossiers `app/sql/` de tous les worktrees (fichiers
   **non suivis** compris), sur toutes les branches vivantes locales **et**
   distantes, et au registre ?
2. **création** exclusive du fichier `app/sql/NNN_<nom>.sql` ;
3. **contrôle APRÈS, immédiatement** : si un autre a pris le même numéro entre
   les deux instants, le fichier est retiré et l'outil passe au suivant ;
4. le numéro est **inscrit PRIS** au registre partagé
   (`.git/onusuite-migrations-prises.json`, dans le dossier git commun : un seul
   registre pour tous les worktrees de la machine).

**Trois portes** tiennent la règle, pour qu'elle ne dépende de la mémoire de
personne :

| Porte | Où | Ce qu'elle refuse |
|---|---|---|
| **crochet `pre-commit`** | dossier git commun — tous les worktrees (`npm run hooks:install`) | un fichier de migration **ajouté** au commit qui collisionne, ou qui n'a **jamais été pris** au registre |
| **CI** `SOC-06 : numéros de migration uniques sur toutes les branches` | job Lint & Type Check | un numéro de la branche qui porte un autre nom sur une autre branche distante |
| **runner** `run-sql-migrations.mjs` | à l'application | un doublon dans la même copie (le dernier filet, après la fusion) |

Un fichier créé à la main avant ce jour se rattache par
`node app/scripts/migration-numero.mjs inscrire app/sql/NNN_<nom>.sql --session "<ligne>"` —
**refusé** si le numéro est dans la plage d'une autre ligne. Une nouvelle ligne
de travail inscrit d'abord sa plage :
`node app/scripts/migration-numero.mjs plage NNN-MMM --session "<ligne>"` — **refusée**
si elle chevauche une plage existante ou contient un numéro déjà pris.

Puis, **dans le même commit** que la première migration : la ligne de la plage dans
la table ci-dessous **et** dans `AGENTS.md`. Le registre est la vérité de la
machine ; ces deux tables sont la vérité du dépôt.

## Les plages (registre : `node app/scripts/migration-numero.mjs plages`)

| Plage | Ligne de travail (`--session`) | Inscrite le |
|---|---|---|
| `100` → `129` | fondations produit | — |
| `130` → `197` | sessions fonctionnelles | 2026-09 |
| `200` → `209` | socles | — |
| `210` → `299` | audits fonctionnels, W7/W8, L7 | 2026-09-28 |
| `300` → `309` | W7 | 2026-09-28 |
| `310` → `324` | session recette (qa/recette-2026-09-29) | 2026-10-02 |
| `325` | partie 1 (correctif TVA 198, tâche 1.7) | 2026-10-02 |
| `340` → `369` | partie 2 (défauts métier) | 2026-10-02 (plan) |
| `400` → `413` | chaînages L1-L4 (socle) | 2026-10-02 |
| `414`, `430` → `449` | partie 3 (L3, L4) | 2026-10-02 |
| `415` → `429` | L16-L24 | 2026-10-02 |
| `450` → `459` | partie 5 (intégrité référentielle) | 2026-10-02 |
| `326` → `339`, `370` → `399`, `460` → … | **LIBRE** — à inscrire avant usage | — |

*Numéros constatés hors de leur fichier de plan, au 02/10 : `414` alerte de
dégradation, `430` paie versée, `431` invariants mesurables, `432` relevé
bancaire manuel (partie 3) ; `415` journal d'événements unifié (L23), `416`
capacité ↔ absence (L17).*

## Ce qui s'est passé le 02 octobre — deux fois

**Le matin.** La session recette a pris `310` → `324` **sans inscrire sa plage**
dans `AGENTS.md`. Les chaînages y étaient inscrits depuis le 30/09 : **douze
numéros en collision** (`310` → `321`), aux noms **homonymes mais aux contenus
différents** (`310_chain_l1_maillons` ≠ `310_legislation_packs_readable`). Le
chaînage a été déplacé en `400` → `413`.

**Le soir — la règle écrite n'a pas suffi.** Le plan de la partie 3 annonçait
`414` → `449` (17:33) **sans l'inscrire dans `AGENTS.md`** ; la session L23 y a
inscrit `415` → `429` pour L16 → L24 (20:45) **sans avoir vu le plan** ; puis :

- `415` pris deux fois : `415_chain_l3_paie_rpc` (partie 3, poussé) et
  `415_chain_l23_evenements` (L23, commité) ;
- `416` pris **trois fois en deux heures** : `416_chain_l4_invariants_mesurables`
  (`l4-invariants`), `416_chain_l3_releve_bancaire` (`partie-3-chainages`),
  `416_chain_l17_capacite_absence` (copie principale, non suivi) ;
- pendant la correction, `417_chain_banc_moteur` naissait **dans la plage
  d'une autre ligne** ;
- et `431` (ex-`416` de L4) crée la table `chain_document_types` que la
  partie 5 (`450`) crée aussi : collision de **contenu**, à trancher à la fusion.

Aucune de ces sessions n'avait tort à son instant : **chacune ne voyait que sa
copie de travail**. D'où l'outil, qui regarde tous les worktrees, toutes les
branches et un registre commun, et les trois portes. La règle d'arbitrage, elle,
n'a pas changé : **la plage inscrite dans `AGENTS.md` garde le numéro ; l'autre
se déplace** — la partie 3 est passée en `430` → `432` (`0cd347c` sur
`partie-3-chainages`, `9e0f33d` sur `l4-invariants`).
