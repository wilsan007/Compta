# Partie 5 — L'intégrité référentielle des chaînages — 2 octobre 2026

> **Objet.** Les colonnes `document_links.amont_type` / `aval_type` sont
> **polymorphes** : `amont_id` peut viser n'importe quelle table, selon la valeur
> texte du type. PostgreSQL ne peut pas poser de clé étrangère sur une colonne qui
> vise « une table parmi 27 ». Mesuré le 02/10/2026 sur une base neuve :
> **13 des 14 colonnes de référence** des tables du socle n'avaient **aucune** clé
> étrangère ; `link_documents` (la seule fonction qui écrit les liens) ne vérifiait
> ni l'existence des documents, ni celle de leur type ; et **15 des 27 tables
> reliées n'avaient aucune garde de suppression**. Un administrateur connecté, par
> le chemin normal de l'écran, a supprimé un compte bancaire (2 liens **actifs**
> vers rien), un règlement client (la facture restait « payée, dû 0 » et l'écriture
> de 120 € restait au grand livre **sans aucun document de règlement**), une
> commande confirmée (**réservation de 3 unités toujours active**), une
> réservation (**quantité réservée jamais rendue**), le journal et le compte
> comptable créés pour une banque.
>
> **Livré.** Six migrations, `450` → `455` : le **registre des 27 types** avec deux
> clés étrangères, le **contrôle d'existence** dans `link_documents`, la **fermeture
> des orphelins déjà présents**, la **garde de suppression** (32 déclencheurs),
> la **libération** d'une réservation, et **INV-19 rendu mesurable**. Une suite de
> **14 scénarios** (`450`) câblée dans la CI, cinq adaptations (252, 402, 413, le
> banc G6 et la garde W10), et l'écran : message de refus traduit fr/en/ar,
> libération par la nouvelle fonction, porte des tables non lues.
>
> **Base de mesure.** Branche `partie-5-integrite-chainages`, posée sur
> `partie-1-stabiliser` (CI verte). Le plan (§ 2.3) prescrivait
> `commercial-hr-paie` ; cette branche ne déclenche **pas** la CI sur `partie-*`
> (la correction est la tâche 1.4 de la partie 1, encore non fusionnée). On a donc
> pris `partie-1-stabiliser`, dont `c51d468` — l'état que le plan mesurait — est
> un ancêtre. Les deux conditions d'entrée du § 2.1 (partie 1 close, base neuve)
> sont ainsi réunies, et le critère de sortie « passage GitHub vert » reste
> atteignable.

---

## 1. Avant — la suite 450, rouge (étape 5.1)

La suite est posée **avant** toute migration 45x, sur une base neuve reconstruite
de zéro (272 migrations, 0 erreur). Sortie complète archivée :
[`partie-5/SORTIE-ROUGE-450-AVANT.txt`](partie-5/SORTIE-ROUGE-450-AVANT.txt).

```
[450] 14 scénario(s) : 2 vert(s), 0 rouge(s) attendu(s) au registre
✅ T05 — confirmer une commande pose toujours son lien commande → réservation
✅ T13 — supprimer une SOCIÉTÉ entière passe : la garde laisse la cascade
❌ T01 — relation "chain_document_types" does not exist
❌ T02 — un lien de type inconnu (« commande ») : SQLSTATE=(aucun refus)
❌ T03 — amont inexistant et amont d'une autre société : (aucun refus)
❌ T04 — ligne amont inventée : (aucun refus)
❌ T06 — suppression=supprimé liens actifs=2 liens rompus=0 (2 attendu)
❌ T07 — suppression=supprimé          ← D2 : facture « payée » sans règlement
❌ T08 — commande=supprimé             ← D3 : réservation de 3 u. toujours active
❌ T09 — release_stock_reservation(uuid) does not exist
❌ T10 — SQLSTATE=42883
❌ T11 — relation "chain_document_types" does not exist
❌ T12 — chain_fermer_orphelins(uuid) does not exist
❌ T14 — journal=supprimé compte=supprimé ← D5
```

**2 verts sur 14** — exactement T05 et T13, les deux non-régressions. Le plan
demande d'arrêter si un **autre** scénario est vert : ce n'est pas le cas.

## 2. Après — la suite 450, verte

Sortie complète archivée :
[`partie-5/SORTIE-VERTE-450-APRES.txt`](partie-5/SORTIE-VERTE-450-APRES.txt).

```
[450] 14 scénario(s) : 14 vert(s), 0 rouge(s) attendu(s) au registre
```

Les cinq défauts D1 → D5 sont mesurés, pas déduits :

| scénario | ce qu'il mesure | avant | après |
## 3. Les contrôles de chaque étape

| étape | contrôle prévu | mesuré |
|---|---|---|
| 5.0 | doublons de numéros de migration | **aucun** (`450`→`459` libre avant de commencer) |
| 5.2 | `count(*) from chain_document_types` | **27** |
| 5.2 | `convalidated` des deux clés étrangères | **`t` / `t`** sur base neuve |
| 5.4 | `chain_fermer_orphelins(NULL)` rejouable | **0** puis **0** |
| 5.5 | `count(*) from pg_trigger … 'zz_garde_p5_suppression%'` | **32** (27 documents + 5 tables de lignes + le compagnon banque) |
| 5.7 | suite 252 / suite 402 | **17/17** et **12/12** |
| 5.8 | banc G6 | **p95 0,482 ms** (budget 50 ms), `link_documents` 0,289 ms |
| 5.9 | la 455 générée contient l'`UPDATE mesurable`, les 3 variables, la branche `INV-19` **juste avant** le `ELSE` final | **oui**, et le diff avec le corps relevé est **uniquement un ajout** (58 lignes ajoutées, **0 supprimée**) |
| 5.12 | `npm run db:types` | **+24 lignes**, `chain_document_types` seule (`Row`/`Insert`/`Update`/`Relationships`) |

> ⚠️ Sur une **base de développement** qui a déjà joué des liens de type inventé,
> les deux clés étrangères restent **`NOT VALID`** et un `NOTICE` nomme les types
> à nettoyer. C'est le comportement voulu (annexe D du plan) : la contrainte
> protège toute **nouvelle** ligne, et seule la validation exige un nettoyage.
> C'est aussi pourquoi le contrôle `t`/`t` ci-dessus est mesuré **sur base neuve**.

## 4. Le rejeu complet

| mesure | résultat |
|---|---|
| base neuve, migrations | **279 succès, 0 erreur** (les 6 de la partie 5, plus la `415` d'une session voisine) |
| job `db-integration`, toutes les étapes `psql -f sql/…` | **115 suites jouées, 115 OK, 0 échec** |
| dont 244 / 252 / 312(402) / 316(406) / 321(411) / 413 / 450 | **9/9 · 17/17 · 12/12 · 12/12 · 6/6 · 8/8 · 14/14** |
| G6 (banc de performance) | **p95 0,482 ms** pour un budget de 50 ms |
| job `screen-path` (PostgREST réel + passerelle JWT) | **15/15 fichiers, 125 verdicts, 0 rouge** |
| porte G5 `check-test-suites.mjs` | **« Toutes les suites du dépôt (101) sont jouées par la CI »** |
| porte X0 `check-screen-writes.mjs` | **0 colonne inexistante** (683 fonctions écrivantes, 245 appels d'écran suivis) |
| `tsc -b --noEmit` | **0 erreur** |
| `oxlint --max-warnings=0` | **0 warning, 0 erreur** (617 fichiers, 103 règles) |
| Vitest | **1 567 verts**, 1 fichier en échec **préexistant et environnemental** (voir § 6) |
## 5. Les cinq adaptations

| adaptation | pourquoi elle casse | ce qu'elle change |
|---|---|---|
| `sql/252_chain_socle_tests.sql` | liens de type `commande` → `livraison` (types inexistants), identifiants tirés au hasard | 35 `commande` + 3 `livraison` → `sales_orders` / `delivery_notes` ; l'aide `_p5_doc` crée la **vraie** commande en brouillon, le **vrai** BL en attente et la ligne qui portent l'identifiant |
| `sql/402_chain_lien_cycle_tests.sql` | idem, plus le scénario C06 qui vérifie que le refus **nomme** le type | 30 + 4 remplacements ; `LIKE '%commande%'` → `LIKE '%sales_orders%'` |
| `sql/413_chain_l4_invariants_tests.sql` | INV-19 passe mesurable : le dénominateur honnête change (13/7 → **14/6**) | **10 remplacements** sur T01, T02, T03, T05, chacun **daté**, l'**ancien verdict conservé en commentaire** |
| `sql/ci/check_chain_performance.sql` | 1 000 liens de types inventés `zz_doc` → `zz_aval` | types remplacés par `sales_orders` ; une **vraie** commande en brouillon est créée à chaque tour, **avant** le chronomètre |
| `src/lib/__tests__/rpc-contract.test.ts` | la garde W10 interdisait **tout** `.rpc(` dans `stock.ts` | assertion **précisée** : elle interdit le recalcul de la **quantité** (`increment_stock`, `decrement_stock`, …), pas `release_stock_reservation`, qui laisse la base rendre la quantité réservée |

## 6. Ce que cette partie ne fait pas, et ce qui reste à mesurer

* **Le test Vitest `db-integration.test.ts` échoue** (1 567 verts, 1 rouge).
  Il demande une connexion **SSL** à la base locale, que le conteneur de test
  n'offre pas. **Vérifié préexistant** : le même fichier échoue à l'identique sur
  l'arbre propre, sans aucun de mes changements (`git stash` puis rejeu). Ce n'est
  pas un rouge de la partie 5.
* **Le registre `ci/expected_failures.sql` n'a pas eu à être touché.** La suite
  450 passe **14/14** après la pose des six migrations : les états rouges
  intermédiaires que le plan prévoyait aux commits 2 et 3 (T06 → T12 et T14
  inscrits au registre) n'ont pas eu lieu, le plan ayant été exécuté en une passe.
  La doctrine « un rouge inscrit au registre » est respectée — elle n'a simplement
  rien à porter.
* **Les lignes « déduites » du § 5 du plan** (suppression d'un **salarié** ayant
  une note de frais intégrée, d'une **tâche** dont un temps est facturé,
  réapplication d'un **pack de plan comptable** sur un compte lié à une banque) sont
  **déduites de la structure**, pas rejouées une à une. Il en va de même des 28
  suppressions d'écran de l'annexe C : 5 lignes sont mesurées, 23 sont déduites.
  Elles sont à dérouler en recette (partie 4, tâche 4.6) avant d'être annoncées.
* **La traduction arabe** des 27 types et du message de refus a été écrite pour ce
  plan ; elle **doit être relue par un arabophone** avant la recette (limite déjà
  connue du lot I).
* **Une session voisine travaille en parallèle dans ce même dossier** :
  `sql/415_chain_l23_evenements.sql` et sa suite sont apparus pendant la partie 5
  (plage `415` → `429`, inscrite par elle dans `AGENTS.md`). Ils ne sont **pas**
  dans les commits de cette partie. Ils expliquent l'écart de **1** entre les 278
  migrations annoncées par le plan et les **279** mesurées ici. Le garde G5 échoue
  **localement** tant que cette suite n'est pas câblée par sa session ; il passe
  (**101/101**) sur le contenu du commit, vérifié en masquant le fichier.
* **La 455 est un point de fragilité assumé** : toute migration qui réécrira
  `chain_invariant_mesurer` après elle devra partir du corps relevé sur une base
  qui contient la 455, sinon elle efface la branche INV-19 sans bruit. La suite 450
  (T12) le détecte, et la CI le dira.
* **Le rejeu de l'écran** a été fait en reproducant le banc de la CI (PostgREST
  16.3 réel + passerelle JWT), mais sur le **port 54401** et non 54399 : sous
  Docker Desktop (macOS), `--network host` n'est pas supporté. Le contenu joué est
  celui de la CI ; seule l'organisation réseau diffère.

## 7. Branche et commits

Branche : **`partie-5-integrite-chainages`**, sur `partie-1-stabiliser`.

| # | contenu |
|---|---|
| 1 | 5.0 — la plage `450 → 459` inscrite (`AGENTS.md` + `NUMEROTATION-MIGRATIONS.md`) |
| 2 | 450 + 451 + 452 + adaptations 252/402/G6 + suite 450 + câblage CI + `db:types` |
| 3 | 453 + 454 + l'écran (5.10, 5.11) |
| 4 | 455 + adaptation 413 (5.9) |
| 5 | 5.13 — cette preuve et les documents |

Le plan autorise (§ 6) **un seul commit** pour 2 → 4 s'il est fait dans la
journée ; c'est ce qui a été fait. Aucun commit intermédiaire rouge n'a existé,
puisqu'aucun n'a été nécessaire.

> **Passage GitHub vert** : [run 37046835384](https://github.com/wilsan007/Compta/actions/runs/37046835384),
> 6 min 23 s, sur le commit `b1e830f`. Les sept jobs joués sont **verts** —
> `DB Integration Tests` (**135 étapes, 0 échec**), `Chemin de l'écran
> (PostgREST réel)`, `Unit Tests`, `i18n`, `Lint & Type Check`,
> `Edge Functions`, `Production Build`, `CI Summary`. (`E2E Tests` et
> `Security Audit` sont `skipped` par la condition existante du workflow.)
>
> Rappel : le run porte aussi le commit `99bc04e` d'une session voisine, qui
> s'est posé sur cette branche pendant le travail (voir § 6).
| i18n fr/en/ar | **parité** sur les 9 espaces, dont `errors` |
| portes `check-i18n`, `check-i18n-usage`, `check-unused-tables`, `check-knip-ceiling`, `check-any-ceiling`, `check-console-error-ceiling`, `check-rpc-contract`, `check-written-columns`, `check-unchecked-writes` | **toutes vertes** |
| `plpgsql_check` | **0 erreur** (porte `sql/ci/check_plpgsql.sql`, dans les 115) |
|---|---|:-:|:-:|
| T01 | registre complet : 27 types, tables présentes, **chaque type écrit en dur dans un maillon inscrit** (analyse de `pg_proc`) | ❌ | ✅ |
| T02 | un type inconnu (`commande`) est refusé, `23503` | ❌ | ✅ |
| T03 | un amont inexistant, et un amont d'une **autre société**, sont refusés | ❌ | ✅ |
| T04 | une ligne amont inexistante est refusée ; une ligne réelle donne un lien | ❌ | ✅ |
| T05 | confirmer une commande pose toujours son lien (non-régression) | ✅ | ✅ |
| T06 | **D1** : compte bancaire **sans opération** → supprimé, ses 2 liens **fermés** (`rompus=2`) | ❌ | ✅ |
| T07 | **D2** : règlement client comptabilisé → `suppression=refusé (chaîne)` | ❌ | ✅ |
| T08 | **D3** : commande confirmée et sa ligne refusées ; **annulée**, supprimée (`liens actifs restants=0`) | ❌ | ✅ |
| T09 | **D4** : réservation → refusée ; `release_stock_reservation` rend 3 → 0, `released`, lien `rompu`, puis suppression passée | ❌ | ✅ |
| T10 | un lecteur (viewer) ne libère pas une réservation (`42501`) | ❌ | ✅ |
| T11 | structure : **32** gardes posées, fonctions internes non exposées | ❌ | ✅ |
| T12 | INV-19 mesurable : orphelin → `rompu`, fermeture (1 puis 0), puis `tenu` | ❌ | ✅ |
| T13 | supprimer une société entière passe (cascade) | ✅ | ✅ |
| T14 | **D5** : journal et compte comptable d'une banque (aval) → `refusé (chaîne)` | ❌ | ✅ |