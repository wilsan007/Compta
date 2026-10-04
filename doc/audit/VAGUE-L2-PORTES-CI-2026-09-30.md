# Vague L2 — les six portes CI — 30 septembre 2026

> **Objet.** Livrer le lot **L2** du
> [plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md)
> (§4.2 et §7.4) : les **six portes automatiques** `G1` → `G6`, « la garantie que
> la qualité ne se dégradera plus : une régression future casse la construction ».
> **État d'entrée.** Mesuré le 30/09/2026 sur base neuve (261 migrations) : trois
> des six portes étaient **déjà tenues** par les contrôles du plan correctif
> (G1 pour moitié, G3, G4), une quatrième pour moitié (G5), et **deux n'existaient
> pas du tout** (G2 le contrat d'effet, G6 la performance). Le plan les nommait
> pourtant : `check_effects_contract.sql` est écrit noir sur blanc dans la
> doctrine `M-05`.
> **Livré.** **Trois contrôles neufs** — `ci/check_bt_grid.sql` (G1),
> `ci/check_effects_contract.sql` (G2), `ci/check_chain_performance.sql` (G6) —
> **un contrôle de câblage neuf** — `scripts/check-test-suites.mjs` (G5) — le
> câblage CI des quatre, et les deux moitiés manquantes **mesurées** plutôt que
> supposées (G3 et G4 étaient déjà en place : c'est écrit, avec les chiffres).

---

## 1. Les six portes, ce qui était gardé, ce qui ne l'était pas

| Porte | Ce que le plan demande (§4.2) | État avant ce lot | Ce qui est livré |
|---|---|---|---|
| **G1** structure | grille `BT` : RLS active **et forcée**, une politique par commande, **index de société**, clés composites | **deux moitiés sur quatre** : `check_policy_duplicates` (ISO-03) et `check_composite_fks` (ISO-02) ; **rien** sur RLS forcée ni sur l'index de société | **`ci/check_bt_grid.sql`** — les deux moitiés manquantes, sur les 360 tables cloisonnées, avec un **plafond daté** |
| **G2** contrat | `check_effects_contract.sql` : comparer le réel à la déclaration | **inexistant** : 0 déclaration, donc **0 effet sous contrat** — chaque exécution traçait `tolere` puis `applique` | **`ci/check_effects_contract.sql`** — lit `pg_proc`, confronte les 25 constats (14 effets, 11 couples) au contrat, registre qui ne peut que rétrécir |
| **G3** colonnes et erreurs | les deux scanners, **étendus à `supabase/functions/`** | **déjà là, et déjà étendus** — mesuré : `check-written-columns.mjs` (465 fichiers, 387 tables, 0 suspect, baseline 0) et `check-unchecked-writes.mjs` (465 fichiers, 0 occurrence) lisent tous deux `src` **et** `supabase/functions` | rien à construire : **vérifié**, chiffres ci-dessus |
| **G4** garde de société étendue | toute fonction SECURITY DEFINER qui écrit dans une table à `tenant_id` doit mentionner `tenant_id` | **déjà là** : `check_tenant_guard.sql` porte les **deux** règles (la règle par signature, et celle des écritures) | rien à construire : **mesuré** — 152 fonctions écrivent dans une table cloisonnée, **0** ne mentionne pas la société |
| **G5** tests et registre | les suites branchées une par une ; registre au couple (fichier, test) ; un test rouge devenu vert sort du registre | **deux moitiés sur trois** : `audit_registry_selftest.sql` (AUD-X01) et `expected_failures.sql` ; **rien** ne vérifiait le **câblage** | **`scripts/check-test-suites.mjs`** — 90 suites, 90 branchées, dans les deux sens |
| **G6** performance | un banc de 1 000 chaînages qui échoue si un p95 dépasse le budget §3.3 | **inexistant** : aucun budget n'était mesuré (la 310 et la 311 fournissaient l'instrument, pas la mesure) | **`ci/check_chain_performance.sql`** — 1 000 tours, p95 par appel et total, linéarité, transaction annulée |

**Ce que ce tableau assume** : L2 n'est pas « trois jours de contrôles neufs »,
c'est **quatre contrôles neufs et deux constats**. Les portes G3 et G4 étaient
réellement tenues — les rejouer aurait ajouté du bruit, pas de la protection. Ce
qui manquait, et qui manquait vraiment, est nommé : la structure (G1), le contrat
(G2), le câblage (G5) et la mesure (G6).


---

## 2. G2 — le contrat d'effet, et pourquoi il rend le lot L7 nécessaire

**La mesure d'entrée, sur base neuve** :

```
Contrat d'effet : 12 maillon(s) lus, 25 constat(s) — 0 déclaré(s), 25 au registre.
Contrats en base : 0 — dont 0 déclaré(s) jamais appelé(s) par un maillon.
```

**Ce que le contrôle lit** — `pg_proc`, pas les fichiers : ce qui compte est ce
qui est **compilé** en base. Deux extractions, les seules littérales donc
décidables : les **couples** `(document, événement, effet)` des appels à
`chain_avant`, et les **effets** des appels à `link_documents` (les quatre
maillons réécrits de la 311 pour lier **par ligne** n'appellent pas toujours
`chain_avant`, mais ils nomment leur effet). Sont exclus les fonctions du
**socle** — elles ne sont pas des maillons — et l'outillage de test (`_…`).

**Les deux sens, et leur asymétrie, écrite dans l'en-tête du fichier** :

* **un effet appelé sans contrat → la CI échoue** (sauf s'il est au registre) ;
* **un effet déclaré jamais appelé → une NOTICE**, jamais un échec : une
  déclaration peut précéder son maillon (le point 1 de la définition de
  « terminé » demande de déclarer même un effet « aucun »).

**Le registre** porte les **25 défauts connus** du jour — 14 effets et 11 couples,
mesurés, chacun avec sa raison (« L1/310 : effet tracé, contrat non déclaré — lot
L7 »). Sa deuxième moitié est celle qui empêche la pourriture : dès qu'une ligne
devient inutile (effet déclaré, ou effet plus appelé), **la CI échoue** jusqu'à
ce qu'elle soit retirée, dans le même commit que la déclaration.

**Preuve que la porte mord — deux rouges provoqués, puis nettoyés** :

| Épreuve | Ce qui a été fait | Ce que la CI a dit |
|---|---|---|
| un maillon neuf sans contrat | `zz_maillon_neuf` appelant `chain_avant(…, 'zz.effet.neuf', …)` | `1 effet(s)/couple(s) appelés par un maillon sans contrat déclaré ni raison au registre : COUPLE « zz_doc / zz_evt / zz.effet.neuf »` |
| une déclaration sans nettoyage | `document_effects` recevant `invoices/validated/sale.invoice.generated_entry` | `2 entrée(s) du registre sont périmées … retirez-les dans le même commit` |
| après nettoyage | déclaration retirée, fonction supprimée | `check_effects_contract : OK` |

**Son auto-test** (Z1/Z2/Z3) : un maillon fictif **non déclaré** doit être vu
**et** jugé non déclaré ; le même appel avec un effet **déclaré** dans la
transaction ne doit pas l'être ; et le corpus réel ne doit porter **aucun** nom du
socle ni d'outillage `_…`. Sans Z1 et Z2, le contrôle pourrait passer au vert en
ne sachant rien décider — le défaut trouvé en septembre sur
`check_trigger_reachability`.

**Ce que G2 change, concrètement** : jusqu'à aujourd'hui, un maillon neuf
pouvait arriver avec un effet que **personne** n'avait déclaré, et la seule trace
en était une ligne `tolere` dans une table de mesure. Désormais **la construction
casse**. C'est ce que le plan appelle rendre impossible le défaut `M-05` — et
c'est ce qui donnera un sens mesurable au lot **L7** (100 % des effets déclarés,
registre vidé).

---

## 3. G1 — la grille BT, plafonnée au lieu d'être rêvée

**Mesuré sur base neuve (261 migrations), et inscrit dans le fichier** :

| Nombre | Valeur du 30/09/2026 | Nature |
|---|---:|---|
| tables portant `tenant_id` | **360** | plafond (une table neuve le fait monter) |
| sans RLS | **0** | **règle**, pas plafond : toute table cloisonnée porte RLS |
| RLS **non forcée** | **55** | état daté (partitions du socle, tables d'historique) |
| à moins de 4 commandes couvertes | **77** | suspect du plan §4.2, état daté |
| sans aucune politique | **10** | RLS fermée par défaut (pas un trou, un nombre) |
| **sans index de société** | **79** | le défaut `BUD-04` à l'échelle du schéma |

**La règle** : chaque nombre doit **égaler** son plafond. Un nombre qui monte
casse la CI (régression) ; un nombre qui **baisse** casse aussi, tant que la
nouvelle valeur n'est pas inscrite dans le même commit — c'est la règle du dépôt
(`expected_failures`, `check-unused-tables`). Un plafond qui ne se met pas à jour
**ment**.

**Preuve que la porte mord** : une table nue (`zz_g1_neuve`, `tenant_id` sans
index ni RLS) a fait monter **cinq** nombres d'un coup, et la CI a dit lesquels :

```
check_bt_grid : 5 nombre(s) ont AUGMENTÉ — régression de la grille BT :
  moins_de_4_commandes : 78 pour 77, sans_index_societe : 80 pour 79,
  sans_politique : 11 pour 10, sans_rls : 1 pour 0, tables_tenant : 361 pour 360.
```

La table retirée, le contrôle repasse au vert. Son auto-test vérifie, lui, qu'une
table sans RLS **est vue**, et que la même table une fois gardée (RLS + FORCE +
politique + index) **ne l'est plus**.

---

## 4. G6 — le banc, ce qu'il voit et ce qu'il ne voit pas

**La mesure du 30/09/2026** (1 000 tours, base neuve, chemin complet d'un maillon) :

```
Banc des chaînages (1000 tours) : p95 total 1.002 ms — chain_avant 0.228,
  link_documents 0.459, emit_domain_event 0.197, chain_apres 0.188
Banc des chaînages : p50 total 0.245 ms ; p95 des 100 premiers 0.667 ms,
  p95 des 100 derniers 0.856 ms (budget 50 ms, linéarité x5 au-delà de 5 ms)
```

Le budget du plan (§3.3) est **50 ms** pour un maillon simple : le socle en
consomme **1 ms**. Ce n'est pas une bonne nouvelle gratuite — c'est la part
**commune** aux 62 maillons qui est mesurée ici, pas l'écriture métier de chacun
(elle est tracée par chaque suite, dans `chain_traces.duree_ms`).

**Ce qu'il détecte, mesuré en le privant de ses index** :

| Ce qui a été retiré | Ce que le banc a fait |
|---|---|
| `uq_document_links_effet` (l'index d'**arbitrage** du `ON CONFLICT`) | **échec immédiat**, sans seuil : « no unique or exclusion constraint matching the ON CONFLICT specification » |
| `ix_document_links_cycle` (l'index d'**historique**) | **il passe quand même** (p95 0,199 ms) : à N = 1 000, un parcours séquentiel sur une petite table est plus rapide que le bruit du poste |

**Ce que ça dit, et c'est écrit dans l'en-tête du contrôle** : le banc protège le
socle de la perte de sa clé d'idempotence, et il publie les budgets — mais
**il ne remplace pas** le banc du lot **L4** sur copie de production, seul capable
de dire ce que coûtent 1 M de liens par an. Un vert qui laisserait croire le
contraire serait un mensonge par omission.

**Le plancher de linéarité a été relevé de 2 ms à 5 ms** après l'avoir vu mentir :
à l'échelle de la milliseconde, un **rapport** est du bruit (p95 de 0,28 ms pour
les 100 premiers tours contre 0,49 ms pour les 100 derniers — rapport 1,8, qui
change de sens d'une exécution à l'autre). Un contrôle qui rougit au hasard est
pire que pas de contrôle : il apprend à ignorer la CI.

---

## 5. G5 — le câblage, et la suite que le contrôle a trouvée lui-même

```
Câblage des suites : 90 fichier(s) dans sql/, 90 référence(s) dans ci.yml.
Non branchées     : aucune
Références fantômes : aucune
✅ Toutes les suites du dépôt (90) sont jouées par la CI, et aucune référence ne pointe un fichier absent.
```

Le contrôle a été écrit **avant** que la suite 312 soit branchée, et son premier
passage a dit exactement ce qu'il devait dire :

```
❌ 1 suite(s) ne sont jouées par aucune étape de la CI : 312_chain_lien_cycle_tests.sql
```

C'est la démonstration la plus courte de ce que la porte apporte : la règle du
dépôt (« le câblage CI dans le même commit ») reposait jusqu'ici sur la mémoire
du développeur. Une suite peut exister, passer **et ne rien protéger** — c'est
même le pire des cas, parce qu'elle rassure.

---

## 6. Les limites, dites

* **G1 est un plafond, pas un zéro.** 55 tables ne forcent pas leur RLS et 79
  n'ont pas d'index de société : la porte empêche que ces nombres **montent**,
  elle n'a pas corrigé l'existant. Le corriger est un lot (des index et des
  `FORCE` sur des tables d'historique), pas une porte.
* **G1 ne prouve pas qu'un index est utilisé**, ni qu'une politique garde
  quelque chose : il lit le catalogue. Les droits sont tenus par
  `check_roles_opposables`, la lecture par la suite `105`.
* **G2 ne prouve pas que l'effet déclaré EST celui qui est produit** — c'est le
  rôle des suites d'acceptation (310/311/312) — ni qu'un effet déclaré « actif »
  est bien exercé. Le registre porte encore **25 défauts connus**, et il ne peut
  que rétrécir : c'est le lot **L7** qui le videra.
* **G5 ne prouve pas qu'une suite branchée vérifie quelque chose** : c'est
  `_audit_assert` (« aucun verdict enregistré » casse) et le registre
  `expected_failures` qui le font.
* **G6 ne voit pas la perte de l'index d'historique** à N = 1 000 (mesuré,
  §4 ci-dessus) : l'échelle de production est le lot **L4**.
* **`plpgsql_check` n'a pas été exécuté localement** (extension absente du
  conteneur de travail) : la CI l'installe (`sql/ci/check_plpgsql.sql`) et valide
  toutes les fonctions. Les fonctions neuves du jour (312, les trois contrôles)
  ont donc été validées par PostgreSQL seul, puis par les suites — la CI fait le
  reste.
* **La vérification complète a été faite sur base neuve en local** (conteneur
  `pg_l1`, PostgreSQL 16) et non dans GitHub Actions : les commandes rejouées sont
  celles du workflow, à l'identique, mais l'exécution distante reste à voir au
  premier passage.

---

## 7. Ce que la suite doit produire

1. **L3 — les 62 maillons** : poser `chain_avant` là où le cycle le permet
   désormais, appeler les fermetures sur les annulations (le geste est écrit dans
   la 312 §8) et prouver chaque maillon par le banc `D1 → D8` ;
2. **L7 — les contrats d'effet** : déclarer les 14 effets, puis vider le registre
   de G2 (la porte refusera de laisser une ligne périmée) ;
3. **L4 — l'indice de cohérence et le banc réel** : 20 invariants, `pg_cron`
   nocturne, et la mesure sur copie de production qui remplace le banc G6 ;
4. **la trouvaille du §6 de la [vague du cycle de vie](VAGUE-L1-TRANCHE3-CYCLE-DU-LIEN-2026-09-30.md)** :
   deux requêtes à lancer sur la copie de production pour savoir si le socle peut
   écrire sous `FORCE ROW LEVEL SECURITY` quand son propriétaire n'est pas
   superutilisateur — question ouverte, mesure locale faite, décision non prise.

