# Vague L1 — tranche 3 : le cycle de vie du lien — 30 septembre 2026

> **Objet.** Lever la **trouvaille du lot L1** (§6.2 de la
> [vague précédente](VAGUE-L1-2026-09-29.md)) : la clé d'idempotence du socle
> — `(société, amont_type, amont_id, effet, ligne)` — ne distinguait pas
> « le même effet **rejoué** » de « le même effet **légitimement reproduit après
> annulation** ». C'était **le prérequis pour poser `chain_avant` partout**
> (§6.5 point 1 de la même vague) : sans lui, poser l'entrée de maillon sur une
> chaîne qui se reproduit fait **disparaître l'effet en silence**.
> **État d'entrée.** Mesuré le 29/09 : la première version de la 311 appelait
> `chain_avant` en tête de boucle du maillon des réservations, et la suite **230
> (T04)** — qui existait depuis la vague des livraisons — a immédiatement rougi :
> une commande **annulée puis reconfirmée** ne réservait plus rien
> (`réservé = 0` au lieu de 10). Conclusion écrite alors : `chain_avant` n'est
> posé que sur les maillons **à sens unique**.
> **Livré.** Migration **312** (`app/sql/312_chain_lien_cycle.sql`), suite
> d'acceptation **312** (**12 scénarios**, tous verts), câblage CI, et
> l'inscription du cycle dans la suite **230** rejouée sans modification.
> **Plus** — les portes **G1**, **G2**, **G5** et **G6** du lot **L2** ont été
> livrées dans le même mouvement ([preuve](VAGUE-L2-PORTES-CI-2026-09-30.md)) :
> c'est la porte **G2** (contrat d'effet) qui rend le cycle utilisable sans
> dériver, puisqu'elle refuse qu'un maillon neuf arrive sans contrat.

---

## 1. Le défaut, et pourquoi il ne se voyait pas

La clé d'idempotence de la 252 est **structurelle** : un index unique, et un
`ON CONFLICT` qui fusionne le payload au rejeu. Elle protège exactement ce
qu'elle nomme — **le rejeu** — et rien d'autre. Or deux faits opposés portent la
même clé :

| Fait | Ce qu'il faut faire | Ce que le socle faisait |
|---|---|---|
| **le même effet REJOUÉ** (double appel, retry, mise à jour sans changement d'état) | ne rien produire de plus | ✅ `chain_deja_fait` rend vrai, la trace dit `ignore` |
| **le même effet REPRODUIT** (commande annulée puis reconfirmée, réexpédition après retour) | **produire** l'effet, sinon l'annulation laisse un trou | ❌ le socle croyait au rejeu et **sautait l'effet** |

Le second cas ne se voyait **pas** dans les suites de L1 : la 310 et la 311
portent sur des documents qui ne reviennent pas en arrière. Il a fallu la suite
**230** (livraisons) — écrite une vague plus tôt, pour d'autres raisons — pour le
faire rougir. C'est la seconde fois du programme qu'un test antérieur trouve le
défaut d'un lot neuf (la première : `check_trigger_reachability` qui ne
s'assertait rien lui-même).

---

## 2. Ce que la 312 pose

**Le lien a un cycle de vie**, et l'unicité ne porte que sur ce qui vit :

* un lien naît **`actif`** ;
* il se ferme par un **acte explicite du métier** : **`remplace`** (l'effet va
  être reproduit) ou **`rompu`** (l'effet est retiré) ;
* l'index `uq_document_links_effet` devient **PARTIEL** (`WHERE etat = 'actif'`) :
  un lien fermé ne bloque plus le tour suivant, et **il n'est jamais réécrit** —
  il reste, avec sa date, son motif et son auteur ;
* `tour` compte les rounds du couple (document, effet, ligne) : 1, puis 2, etc.

C'est la phrase de la tranche 2, tenue : « **un lien remplacé, pas réécrit** ».

**Les six fonctions du cycle** (et ce qu'elles refusent) :

| Fonction | Rôle | Refus |
|---|---|---|
| `chain_lien_actif` | le lien vivant d'un couple — NULL s'il n'y en a pas | — |
| `chain_lien_tour` | le plus haut tour atteint (0 si jamais produit) | — |
| `chain_lien_fermer` | **le cœur** : ferme le lien actif, daté, motivé, signé | refuse s'il n'y a **aucun lien actif** (message nominatif) |
| `chain_lien_remplacer` | l'effet va être reproduit | idem |
| `chain_lien_rompre` | l'effet est retiré (M-03) | idem |
| `chain_liens_fermer` | **tous** les effets d'un document en un acte (annulation globale) | **rapporte** 0, ne refuse pas : zéro effet tracé y est légitime |

**Les décisions, et leur raison** — chacune mesurée par un scénario :

1. **la fermeture n'est jamais automatique.** Le socle ne connaît pas les états
   métier : `st_shipments.status` admet `pending → shipped → returned → shipped`
   (mesuré par la 311), `sales_orders.status` admet `cancelled → confirmed`
   (mesuré par la 230). Fermer sur une transition devinée ferait disparaître
   l'effet d'une réexpédition — exactement le trou qu'on ferme. C'est le **maillon**
   qui ferme, en nommant son motif (le geste est écrit dans l'en-tête de la 312,
   §8, pour le lot L3) ;
2. **le fermé ciblé refuse, le global rapporte.** Le ciblé affirme qu'un lien
   existe (même doctrine que `chain_regenerate`, qui refuse « aucun lien ») ; le
   global, lui, est appelé sur un document dont **rien** n'a pu être tracé, et
   refuser y serait hostile ;
3. **`chain_deja_fait` et `chain_integrity_ok` ne regardent que l'ACTIF.** Un lien
   fermé n'est plus « déjà fait » — c'est ce qui rend possible la reproduction —
   et n'est plus « intact » — c'est ce qui fait qu'une annulation **refuse** au
   lieu de laisser une pièce orpheline (M-03) ;
4. **une fermeture n'écrit pas dans `chain_traces`.** Une trace mesure
   l'exécution d'un maillon (durée, lignes écrites, résultat) ; fermer un lien
   n'est pas produire un effet. Le journal du cycle est `domain_events`
   (`chain.link_superseded`, `chain.link_broken`, un événement par lien fermé) et
   le registre `document_links` lui-même. Le vocabulaire de
   `chain_traces.resultat` reste donc **fermé** : rien à y ajouter ;
5. **les gardes structurelles mordent en base, pas en revue** : un lien fermé
   sans motif est refusé **par la contrainte** (`document_links_fermeture_check`),
   et **deux liens actifs sur la même clé sont impossibles** (index partiel).

**Ce que la 312 ne fait pas** : elle ne ferme aucun lien des 310 et 311 (leurs
maillons restent sur la doctrine du sens unique) et elle **ne pose pas
`chain_avant` partout** — elle lève le verrou qui l'empêchait. C'est le lot
**L3** (les 62 maillons), et le geste à y porter est écrit dans la migration.

---

## 3. Les mesures, avant et après

| Mesure | Avant la 312 | Après la 312 | Où c'est prouvé |
|---|---|---|---|
| Notion de **tour** | **inexistante** (c'était la trouvaille) | `document_links.tour`, 1 puis 2 | C04, C09, C12 |
| Idempotence après fermeture | impossible : le lien fermé bloquait à jamais | **index partiel** : un nouveau lien naît au tour suivant | C04, C10 |
| `chain_avant` sur un maillon qui se reproduit | **faux** — l'effet disparaissait (réservé = 0) | **vrai** après fermeture | C05, C12 |
| Lien fermé : date, motif, auteur | inexistants | trois colonnes **exigées par contrainte** | C03, C10 |
| Historique du cycle | aucune trace de la fermeture | `domain_events` : un événement par lien | C03, C07, C11 |
| Scénarios de la suite 312 | — | **12, tous verts** (rejouée deux fois) | `312_…_tests.sql` |
| Base neuve | 258 migrations | **261 migrations, 0 erreur** | ce document |
| Non-régression rejouée | — | **15 suites, 144 scénarios verts** | ci-dessous |

**Non-régression rejouée sur base neuve** (base construite par les seules
migrations, puis les 11 contrôles du dépôt, puis les suites — l'ordre de la CI) :

| Suite | Verdict | Suite | Verdict |
|---|---|---|---|
| `252` socle des chaînages | **16 / 16** | `213` avoirs | **6 / 6** |
| `310` maillons L1 tranche 1 | **15 / 15** | `229` ordres de fabrication | **6 / 6** |
| `311` maillons L1 tranche 2 | **12 / 12** | `281` caisse | **8 / 8** |
| `312` cycle de vie du lien | **12 / 12** | `302` nomenclature et écarts | **8 / 8** |
| `230` livraisons et sorties | **5 / 5** | `222` nature des lignes bancaires | **5 / 5** |
| `180` ventes → comptabilité | **22 / 22** | `277` solde bancaire du GL | **5 / 5** |
| `192` achats et trésorerie | **15 / 15** | `170` rapprochement des règlements | **3 / 3** |
| `210` factures d'acompte | **6 / 6** | | |

**Contrôles permanents du dépôt sur la même base**, tous à 0 erreur :
`check_trigger_reachability` (117 comparaisons), `check_tenant_guard` (garde
étendue : « aucune table cloisonnée écrite sans mention de la société »),
`check_anon_grants`, `check_global_rows_writable` (325 politiques),
`check_status_writes` (104 écritures), `check_policy_duplicates`,
`check_composite_fks`, `check_roles_opposables`, `audit_registry_selftest`
(AUD-X01) — plus les trois portes neuves (G1, G2, G6) et le câblage (G5).
Le registre `ci/expected_failures.sql` reste **vide**.

---

## 4. Ce que la suite 312 prouve — 12 scénarios

| # | Ce qui est mesuré |
|---|---|
| C01 | la structure : les 5 colonnes, les 3 gardes, et l'index d'idempotence **partiel** |
| C02 | le rejeu d'un effet actif ne double rien et **fusionne** le payload (non-régression de la 252 T02) |
| C03 | la fermeture ciblée : datée, motivée, signée, journalisée — et le lien n'est plus « déjà fait » ni « intact » |
| C04 | après fermeture, un **nouveau** lien naît au tour 2 ; **l'ancien n'est pas réécrit** (aval et état conservés) |
| C05 | `chain_avant` rend faux tant que le lien est actif, et **vrai** dès qu'il est fermé |
| C06 | trois refus nominatifs (motif absent, état inconnu, aucun lien actif) et rien d'écrit quand c'est refusé |
| C07 | la fermeture globale : deux effets fermés en un acte, un événement par lien, et le rejeu **rapporte 0** |
| C08 | le cloisonnement : fermer chez A laisse le lien de B actif (la clause de société est dans **l'écriture**) |
| C09 | `chain_lien_actif` / `chain_lien_tour` avant, pendant, après |
| C10 | les gardes mordent : fermeture sans motif refusée **par la base**, deux actifs sur la même clé impossibles |
| C11 | le payload de l'événement porte l'effet, le lien, le tour, l'état et le motif |
| C12 | **le rouge de la 230, rejoué sur le vrai flux** : commande annulée puis reconfirmée — la réservation est **reproduite**, l'historique garde **deux tours** (2 rompus + 2 actifs), et `chain_avant` rend vrai après la fermeture |

Le C12 est le scénario qui compte : il **joue le geste que le maillon
d'annulation posera au lot L3** (`chain_liens_fermer`), puis laisse le métier
annuler et reconfirmer la commande. Ce qui était un rouge il y a deux jours est
devenu une acceptation.


---

## 5. Les limites, dites

* **Le cycle ne pose aucun maillon.** La 312 est un socle : elle donne le geste
  (`chain_lien_fermer`, `chain_lien_rompre`, `chain_lien_remplacer`) et le
  registre, mais **aucun des 62 maillons ne l'appelle encore**. Tant que le lot
  **L3** n'est pas fait, une commande annulée laisse ses liens `actifs` — donc
  `chain_avant` reste faux sur les maillons qui se reproduisent, et la doctrine
  du **sens unique** (tranche 2) reste la règle. C'est écrit ici pour que le
  prochain lecteur ne croie pas la question réglée deux fois : **le cycle est un
  prérequis, pas la solution**.
* **L'idempotence structurelle reste partielle**, et pour une autre raison que
  celle de la tranche 2 : `chain_avant` n'est toujours appelé que par les maillons
  qui le portent (8 compagnons `zz_l1_` et 4 corps réécrits). Un maillon qui
  écrit son effet sans passer par le socle n'est pas protégé — c'est l'objet de
  la porte **G2** (le contrat) et des 12 points du « terminé » (§4.1 du plan).
* **Un effet produit DEUX FOIS à la main ne se voit pas.** Le cycle interdit deux
  liens **actifs** sur la même clé ; il ne voit pas un maillon qui écrirait son
  effet deux fois en n'appelant `link_documents` qu'une fois. C'est l'objet du
  banc d'épreuve **D1 → D8** (lot L3) et des règles `R-001` → `R-062`.
* **La trace d'un refus ne survit toujours pas au rollback** — limite
  transactionnelle de PostgreSQL, dite par la 252 (§5) et **reconstatée** par la
  vague précédente : 0 ligne `refuse` dans `chain_traces` après une suite
  complète. La 312 ne change rien à ce fait : une fermeture journalise dans
  `domain_events`, qui subit la même transaction. Le lot **L5** (les écrans)
  choisira le canal autonome, ou tracera depuis le message remonté au client.
* **Le banc de performance (G6) ne voit pas la perte du seul index
  d'historique** à N = 1 000 : mesuré, le banc passe encore sans
  `ix_document_links_cycle` (p95 0,199 ms). Il voit, en revanche, la perte de
  l'index **d'arbitrage** — immédiatement, et sans seuil. L'échelle qui décide du
  coût réel (1 M de liens par an) est le banc du lot **L4**.

---

## 6. Trouvaille — le socle écrit sous `FORCE ROW LEVEL SECURITY`

**Ce que la 312 a obligé à regarder.** Les fonctions du cycle **écrivent** dans
`document_links` (mise à jour de l'état d'un lien). Or cette table porte
`FORCE ROW LEVEL SECURITY` et **aucune politique d'écriture** : la 252 ne lui
donne qu'une politique de `SELECT` (« écrit par les chaînages, lu par la
société »). La question est donc : *qui* écrit, et sous quel rôle ?

**Mesuré, sur la base de test, avec un rôle propriétaire non superutilisateur :**

1. une table `ENABLE` + `FORCE ROW LEVEL SECURITY` avec une politique de
   `SELECT` seule **refuse l'`INSERT` de son propre propriétaire** :
   `42501 — new row violates row-level security policy for table « … »` ;
2. corollaire : `link_documents` et `chain_lien_fermer` (SECURITY DEFINER,
   propriétaire de la table) ne peuvent écrire **que si leur propriétaire
   contourne le RLS** — c'est-à-dire s'il est superutilisateur ou `BYPASSRLS`.

**Or la CI ne peut pas le voir** : son `postgres` **est** superutilisateur, donc
le RLS y est contourné. Et les deux environnements mesurés disent des choses
différentes :

| Environnement | `rolsuper` | `rolbypassrls` | Conséquence |
|---|---|---|---|
| CI GitHub Actions (postgres:16) | **t** | **t** | le RLS est contourné : le défaut est invisible |
| Image Supabase officielle (conteneur local `supabase_db_app`) | **t** | **t** | le socle écrit sans difficulté |
| Copie de production du dépôt (mesure du 23/09, `SUIVI-CAHIER-CORRECTIF`) | **f** | *non mesuré* | **si** `rolbypassrls` est aussi faux, **toute écriture de chaînage est refusée** |

**Ce que ce document ne fait pas** : il ne conclut pas. Il nomme la question, la
mesure locale, et les deux hypothèses. **La vérification tient en deux requêtes**
à lancer sur la copie de production :

```sql
select rolsuper, rolbypassrls from pg_roles where rolname = current_user;
-- puis, si rolsuper = f et rolbypassrls = f :
select link_documents('<société de test>', 'zz_amont', gen_random_uuid(),
                      'zz_aval', gen_random_uuid(), 'zz.effet', 'created_from');
```

**Trois sorties possibles**, à trancher dans un lot, pas ici :
(a) si `rolbypassrls = t` — le socle écrit, l'alerte est levée, et un contrôle
peut l'asserter ; (b) si `rolsuper = f` **et** `rolbypassrls = f` — le socle est
muet en production, et le correctif est un choix explicite : `NO FORCE ROW LEVEL
SECURITY` sur les six tables du socle (le propriétaire écrit, `authenticated`
reste filtré — c'est l'intention écrite dans l'en-tête de la 252), ou une
politique d'écriture pour le propriétaire, ou `BYPASSRLS` accordé au rôle
applicatif ; (c) si la copie de production n'a pas la 252 — la question ne se
pose qu'après sa mise en service.

**Pourquoi c'est écrit ici plutôt que corrigé.** Une migration qui change
`FORCE ROW LEVEL SECURITY` sur les tables du socle **affaiblit** la protection de
la société si elle est faite sans mesurer : c'est exactement le genre de décision
qui se prend sur une copie de production, pas sur une déduction.

---

## 7. Ce que la suite doit produire

1. **Les 62 maillons (lot L3)** — dont le geste d'annulation, écrit dans la 312
   §8 : c'est ce qui rend le cycle **utile**, pas seulement disponible ;
2. **les 32 chaînages non encore nommés** ([inventaire](INVENTAIRE-CHAINAGES-L1-2026-09-29.md) §3)
   et les effets multi-lignes restants (facturation partielle, transferts entre
   dépôts) ;
3. **les contrats d'effet (lot L7)** — la porte **G2** les attend : le registre
   du contrôle porte aujourd'hui les **14 effets** de L1, et il ne peut que
   rétrécir ;
4. **la réponse à la trouvaille du §6** — **MESURÉE et gardée** : voir le **§8**
   (l'expérience à une seule variable, l'inventaire des 12 tables, et la porte
   **G7**). Reste la **décision**, qui se prend sur la copie de production.


---

## 8. La trouvaille du §6 est MESURÉE, et gardée par une porte (30/09)

### 8.1 L'expérience, à une seule variable

Le §6 posait la question et refusait d'y répondre sans mesure. Elle est faite, sur
base neuve, avec **une seule variable** : **QUI possède la table**. La phrase
d'écriture, la société, les politiques — tout le reste est identique.

| # | Propriétaire de `document_links` | `rolsuper` | `rolbypassrls` | Résultat mesuré |
|---|---|---|---|---|
| **A** | `zz_owner` | f | f | ❌ **`42501`** — `new row violates row-level security policy for table "document_links"` |
| **B** | `zz_bypass` | f | **t** | ✅ acceptée |
| **C** | `postgres` | **t** | t | ✅ acceptée |

**Ce que cela établit.** Le socle n'écrit **que** parce que son propriétaire
contourne la RLS. Un propriétaire « nu » (ni superutilisateur, ni `BYPASSRLS`)
est refusé — et il n'y a pas d'échappatoire par les fonctions : `link_documents`
est `SECURITY DEFINER`, donc elle s'exécute **en tant que son propriétaire**, et
subit le même refus.

### 8.2 L'inventaire, sur base neuve (30/09/2026)

```
311 tables sous FORCE ROW LEVEL SECURITY
 dont  12 sans AUCUNE politique d'écriture   ← c'est l'exposition
```

Les douze, nommées : `banks`, `chain_regeneration_log`, `chain_settings`,
`chart_account_templates`, `currencies`, `document_effects`, `document_links`,
`journal_posting_sequences`, `legislation_packs`, `stock_movement_phantoms`,
`stock_quantities`, `v_tenant_id`.

**Les six tables du socle en font partie** — c'est le lien direct avec L3.

### 8.3 La porte **G7** — et pourquoi elle a une particularité

`sql/ci/check_forced_rls_writers.sql`, câblée dans la CI :

* elle **publie le verdict de l'environnement** — quel rôle possède ces tables,
  et contourne-t-il la RLS ? — puis **échoue si l'environnement est muet**, en
  nommant les tables et les trois issues possibles ;
* elle **plafonne** les deux nombres (311 et 12) : à la hausse c'est une
  exposition neuve, à la baisse c'est une amélioration à inscrire dans le même
  commit (la règle de `G1`) ;
* elle **s'auto-teste** : table fictive sous `FORCE` sans politique → vue ;
  son propriétaire nu → refusé en `42501` ; politique d'écriture ajoutée → sortie
  de l'exposition. Le tout annulé (`ROLLBACK`).

**Sa particularité, et c'est son intérêt** : la CI **ne peut pas** voir le
défaut, puisque son `postgres` est superutilisateur. Un contrôle qui se
contenterait de compter les tables serait donc vert partout. Celui-ci dit ce que
vaut l'environnement **où il tourne** — c'est-à-dire qu'il devient, **sur la
copie de production, le diagnostic lui-même**, en une commande :

```bash
psql "$PROD_URL" -v ON_ERROR_STOP=1 -f app/sql/ci/check_forced_rls_writers.sql
```

### 8.4 Ce qui reste — et pourquoi ce n'est pas tranché ici

Les trois issues sont écrites dans le message d'échec, et **aucune n'est
choisie** :

1. `NO FORCE ROW LEVEL SECURITY` sur ces tables — le propriétaire écrit,
   `authenticated` reste filtré : c'est **l'intention déjà écrite** dans l'en-tête
   de la `252`. ⚠️ Elle fait **baisser** un nombre de `G1` (tables sans RLS
   forcée), donc elle s'accompagne de la mise à jour du plafond daté de `G1`
   **dans le même commit** ;
2. une **politique d'écriture pour le propriétaire** — `FORCE` conservé ;
3. `BYPASSRLS` accordé au rôle.

Le §6 disait : « ce genre de décision se prend sur une copie de production, pas
sur une déduction ». C'est toujours vrai — mais la mesure qui la permet ne tient
plus en deux requêtes à recopier : **elle tient en un contrôle qu'on exécute**.

