# Vague L0 — le socle des chaînages transverses — 24 septembre 2026

> **Objet.** Poser le lot **L0** du [plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) :
> les tables, les fonctions utilitaires et le gabarit qui portent les **62 chaînages
> transverses** du produit — ceux qui existent, ceux des 62 règles d'état, des 16 contrôles
> d'absence et des 12 innovations.
> **État d'entrée** : le [référentiel](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md)
> mesurait 62 chaînages, note moyenne **3,65/7**, **idempotence 15 %**, **trace 11 %**.
> Aucune table de socle n'existait : `document_links`, `document_effects`, `domain_events`,
> `chain_traces`, `chain_regeneration_log`, `link_documents` — **zéro occurrence** dans
> `app/sql`, `app/src` et `app/scripts` (grep du 24/09/2026).
> **Livré** : migration **252** (`app/sql/252_chain_socle.sql`, 6 tables, 21 index,
> 13 fonctions), suite d'acceptation **252** (16 scénarios, tous verts), câblage CI, et
> l'adaptation du plafond de `scripts/check-unused-tables.mjs` (77 → 77, avec les huit
> tables du socle nommées et justifiées).
> **Plus** (mesuré après la batterie complète, §3.1) : les deux contrôles permanents que le
> socle a fait tomber — **105** (isolation ; partitions écartées, parents partitionnés
> couverts : 340 → **346** tables) et **238** (T07) —, avec **T14** qui mesure le fait sur
> lequel repose leur règle. Batterie entière sur base neuve (227 migrations) : **67 suites et
> contrôles verts, 0 rouge**.

---

## 1. Ce que le socle porte, et ce qu'il ne décide pas

| Objet | Rôle | Décision du plan suivie |
|---|---|---|
| `document_links` (M-10, M-11, M-12) | qui a produit quoi, par quel maillon, avec la **ligne** (M-09) | clé d'idempotence unique : `(tenant_id, amont_type, amont_id, effet, ligne)` |
| `document_effects` (M-05) | le contrat d'effet : ce que chaque document produit, par événement | ligne de société prioritaire sur le contrat standard |
| `domain_events` (M-13, I-06) | journal d'événements lisible, partitionné par mois | partitionné, rétention 24 mois |
| `chain_regeneration_log` (M-04) | ce qui a été recalculé, avant/après, et pourquoi | append-only |
| `chain_traces` (§3.4) | la mesure de **chaque** exécution de maillon | partitionné comme `domain_events` |
| `chain_settings` (§3.6) | le drapeau `observe` → `avertit` → `refuse`, par société | absence de ligne = `observe` |

**Fonctions.** Les six du plan — `link_documents`, `chain_deja_fait`, `chain_integrity_ok`,
`emit_domain_event`, `chain_autorise`, `chain_regenerate` — plus le **gabarit** demandé au
même lot : `chain_avant` (idempotence + contrat + drapeau), `chain_trace` / `chain_apres`
(la mesure), `chain_enforcement_mode` / `chain_set_enforcement` (le drapeau), et
`chain_ensure_partitions` (+ `_table`) pour le calendrier.

**Le socle ne décide rien du métier.** Aucune fonction ne connaît un document : elles
prennent la société **de la source** (point 7 de la définition de « terminé », §4.1) et
laissent le maillon produire son effet. C'est ce qui permet aux 62 maillons de partager la
même clé, le même contrat et la même trace sans se ressembler.

---

## 2. Les mesures, avant et après

| Mesure | Avant la 252 | Après la 252 | Où c'est prouvé |
|---|---:|---:|---|
| Tables de socle | **0** | **6** (+ partitions) | `252_chain_socle_tests.sql` T01 |
| Idempotence structurelle disponible pour les maillons | **0 / 62** | clé unique + `ON CONFLICT` (T02) | T02 |
| Contrat d'effet lisible et fermé par défaut | **inexistant** | `chain_autorise` → faux sans déclaration | T06 |
| Trace d'exécution d'un maillon | **0 table** | `chain_traces`, durée et résultat par exécution | T07 → T12 |
| Cloisonnement des liens : lecture | **—** | RLS forcée, politique unique | T05, T14 |
| Écriture directe par le client | **—** | **refusée** (`REVOKE ALL` puis `GRANT SELECT`) | T05 |
| Partitions lisibles en direct | **—** | **0** (RLS + droits retirés sur chacune) | T14 |
| Couverture du contrôle d'isolation (**105**) | 340 tables | **346** : les 6 tables du socle (4 ordinaires **et** les 2 parents partitionnés, que l'énumération `relkind = 'r'` ne voyait pas) ; les partitions sont écartées | sortie de `105_rls_tests.sql` |
| Plafond « tables jamais lues » | 77 | **77** (huit tables du socle nommées et justifiées) | `scripts/check-unused-tables.mjs` |

---

## 3. Les preuves d'exécution (24/09/2026)

Base locale de rejeu : conteneur `pg_w2w3` (PostgreSQL 16, base `ci`, 223 migrations
appliquées avant la 252).

```
$ DATABASE_URL=postgresql://postgres:postgres@localhost:5440/ci node run-sql-migrations.mjs
📊 Résumé: 223 déjà exécutés, 1 à exécuter, 0 échoués précédemment
▶ Exécution de 252_chain_socle.sql...  ✅ Succès
📊 RÉSULTAT FINAL: 1 succès, 0 erreurs sur 1 migrations

$ psql -f sql/252_chain_socle_tests.sql
NOTICE:  [252] 16 scénario(s) : 16 vert(s), 0 rouge(s) attendu(s) au registre
```

Les sept contrôles permanents de la base, exécutés après la migration **et** après la
suite, restent verts :

```
check_policy_duplicates     OK   (une seule politique permissive par (table, commande))
check_composite_fks         OK   (aucune clé étrangère mono-colonne nouvelle)
check_anon_grants           OK   (13 fonctions du socle révoquées de PUBLIC et anon)
check_tenant_guard          OK   (la seule RPC, chain_set_enforcement, porte sa garde)
check_status_writes         OK
check_trigger_reachability  OK
check_plpgsql               OK   (0 erreur — 33 avertissements tolérés)
check-unused-tables         OK   (77 tables non lues, conforme au plafond)
```

La suite est **rejouable** : exécutée deux fois de suite sur la même base, 16/16 à chaque
passage (T16 calcule le premier mois sans partition au lieu de supposer `+4 mois`).

### 3.1 Le rouge d'abord : ce que la 252 a cassé dans la CI, et pourquoi

Le socle a été appliqué sur une **base neuve** (227 migrations, 0 erreur), puis **la
batterie entière** (67 suites et contrôles, dans l'ordre de `.github/workflows/ci.yml`) a
été rejouée. Quatre suites sont tombées — et elles ne tombaient **pas** sans la 252
(vérifié sur une base construite avec les 226 migrations seules, mêmes quatre suites
vertes) :

| Suite | Ce qu'elle a dit | Cause réelle |
|---|---|---|
| **105** (isolation) | `permission denied for table chain_traces_2026_09` | l'énumération du test prenait `relkind = 'r'` : les 10 partitions du socle y entraient, leurs droits étant retirés pour les rendre inatteignables en direct |
| **234** (file de webhooks) | `Webhook sans événement : renseignez event ou event_name` | **cascade** : la 105 s'arrête **avant son nettoyage** ; ses lignes de fixture (sociétés A et B) restent dans `webhook_delivery_queue` et le lot `claim_webhook_batch` les bloque |
| **243** (paie et nom du salarié) | `T02 — aucune fiche salarié sans prénom ni nom` | même cascade : la fiche salarié de fixture de la 105 reste en base et fait échouer le balayage global |
| **238** (politiques jumelles) | `T07 — aucune table cloisonnée ne reste sans politique` | la partition porte RLS **et** aucune politique (c'est voulu : elle n'est lisible que par son parent) ; le contrôle la comptait comme une cloison |

Les trois premières lignes n'ont qu'**une** cause, et elle est instructive : un contrôle qui
s'arrête au milieu laisse des fixtures derrière lui, et les suites suivantes accusent à sa
place. La quatrième est un défaut de vocabulaire — *partition* n'est pas *cloison*.

Correctifs, dans le même lot :

1. **`105_rls_tests.sql`** énumère `relkind IN ('r', 'p')` **et écarte** `relispartition` :
   la société se lit dans la table ordinaire et dans le **parent** partitionné qui porte la
   politique ; une partition n'est que le stockage du parent, dont l'accès direct est
   refusé. Conséquence **positive** : les 2 parents partitionnés du socle, invisibles à
   l'ancienne énumération, sont désormais couverts. Couverture mesurée : **340 → 346**.
2. **`238_policy_dedup_tests.sql`** (T07) écarte `relispartition` pour la même raison,
   justifiée sur place.
3. **`252_chain_socle_tests.sql` (T14)** mesure le fait sur lequel repose la règle des deux
   contrôles : **10/10** partitions de `domain_events` et `chain_traces` portent
   `relispartition = true`, et le parent **ne le porte pas**. L'exclusion des contrôles
   cesse d'être une convention : elle est vérifiée.

Batterie complète après correctifs, sur **base neuve** (227 migrations) : **67 suites et
contrôles verts, 0 rouge**, hors les deux échecs inscrits au registre
(`231 M-17-01`, `245 T08`).

---

## 4. Les écarts au plan, chacun mesuré

Le plan a été suivi là où il était vrai, et corrigé là où PostgreSQL a dit non. Chaque
écart est mesuré, jamais supposé.

1. **`document_effects` n'a pas de clé primaire sur `COALESCE(tenant_id, …)`.** Le plan
   écrivait `PRIMARY KEY (COALESCE(tenant_id, '000…'))` ; PostgreSQL refuse une clé
   primaire qui contient une expression. Mesure : `ALTER TABLE … ADD PRIMARY KEY
   (COALESCE(…)` → `ERROR: syntax error at or near "("`. L'unicité est portée par un index
   unique sur la même expression, et `ON CONFLICT` le retrouve (T02 le prouve sur
   `document_links`, construit de la même façon).
2. **`domain_events` et `chain_traces` portent `PRIMARY KEY (id, created_at)`.** Une clé
   primaire de table partitionnée doit contenir la clé de partitionnement ; le plan
   écrivait `id` seul.
3. **`document_effects.actif` (colonne ajoutée au plan).** Sans elle, une société pouvait
   *déclarer* un effet mais **jamais le désactiver** : une ligne standard (`tenant_id IS
   NULL`) déclare pour tout le monde. `chain_autorise` lit la ligne la plus spécifique
   (société d'abord) et rend son `actif` — T06 mesure les deux sens : le standard lu par A,
   l'effet éteint pour B.
4. **`chain_traces.resultat` gagne `tolere`.** `ignore` dit « déjà appliqué » ; sans
   `tolere`, un effet appliqué **hors contrat** (mode `observe`) serait indiscernable d'un
   rejeu. T07 et T09 le mesurent.
5. **Les partitions reçoivent RLS *et* la révocation des droits directs.** Mesure du
   24/09/2026 sur une table partitionnée : `has_table_privilege('authenticated', <partition>,
   'select')` → **`t`**. L'image Supabase accorde les privilèges par défaut à `authenticated`,
   et la politique du parent ne s'applique **pas** à qui interroge la partition directement :
   sans ces deux lignes, `domain_events_2026_09` rendait les liens de toutes les sociétés.
   T14 exige **0** partition lisible en direct, et vérifie que l'événement reste visible
   par le parent.
6. **`chain_ensure_partitions_table(text, integer)` (fonction ajoutée).** Premier jet écrit
   avec `FOREACH … ARRAY['domain_events','chain_traces']` : `plpgsql_check` résolvait
   statiquement le SQL dynamique en `relation "public.{domain_events,chain_traces}" does not
   exist` → `ci/check_plpgsql.sql` **échouait**. Le nom de table est désormais un paramètre,
   vérifié contre une liste blanche et contre le catalogue (`relkind = 'p'`).
7. **`scripts/check-unused-tables.mjs` : le plafond n'a pas bougé (77 → 77).** Deux causes
   distinctes, toutes deux traitées :

   * les **huit** tables du socle sont nommées dans `SERVER_ONLY_TABLES` avec leur raison
     (elles sont écrites par les fonctions et lues par des écrans qui viennent aux lots
     L5 → L7 et L23) ;
   * le SQL dynamique du premier jet écrivait `CREATE TABLE` suivi du nom de schéma
     littéral : l'expression régulière du contrôle retombait sur une table nommée
     **`public`** (+1 au compteur). Le schéma est passé en paramètre (`%I.%I`), et la
     formulation littérale est bannie du fichier — le commentaire qui la citait la
     reproduisait, ce que le contrôle voyait aussi.
8. **Deux contrôles permanents apprennent à distinguer une *cloison* d'une *partition*.**
   `105_rls_tests.sql` et `238_policy_dedup_tests.sql` (T07) énumèrent les tables cloisonnées
   et écartent désormais `relispartition`, tout en **incluant** les parents partitionnés
   (`relkind = 'p'`) — que le premier ne voyait pas. Détail, rouge d'abord et mesures : §3.1.
   La règle n'est pas supposée : T14 mesure que les partitions portent `relispartition` et
   que le parent ne le porte pas.


---

## 5. Les limites, dites

* **La trace d'un refus ne survit pas au rollback.** `chain_avant` écrit la trace
  (`refuse`) **puis** lève l'exception : dans la transaction de l'opération refusée, tout
  est annulé — c'est la limite transactionnelle de PostgreSQL, il n'y a pas d'autonomie
  sans `dblink`/`pg_net`. Le tableau de bord des refus (§3.4) lira donc ce qui a survécu
  (les refus rattrapés dans une sous-transaction qui se poursuit) ; le lot **L5** choisira
  le canal autonome si le besoin s'en fait sentir, ou tracera depuis le message remonté au
  client. T08 mesure les deux faits : message nominatif, trace non survivante.
* **Aucun maillon n'est branché.** Les 62 chaînages existants ne sont **pas** instrumentés :
  c'est le lot **L1**. En l'état, le socle est vide et personne ne l'appelle — c'est
  exactement le livrable attendu du L0 (« le socle est en place et vide »).
* **Aucun contrat d'effet n'est semé.** Conséquence assumée : `chain_autorise` rend **faux**
  pour tout, et c'est le mode `observe` (défaut) qui évite de bloquer un client existant.
  Les déclarations sont le lot **L7** ; la mise en service progressive
  `observe` → `avertit` → `refuse` est le drapeau posé par la 252.
* **Rien n'est planifié.** `chain_ensure_partitions()` est écrit pour le job nocturne du
  lot **L4** ; d'ici là, la partition par défaut absorbe les mois manquants — et la fonction
  **refuse** de rattacher un mois qui y porte déjà des lignes, en nommant le mois et le
  nombre de lignes à déplacer.
* **`chain_regenerate` ne recalcule rien.** Le socle ne connaît pas les effets : il
  **refuse** de régénérer ce qui n'a jamais été appliqué (`aucun lien`), journalise
  avant/après et émet `chain.regenerated`. Le recalcul reste au maillon — c'est dit dans
  l'en-tête de la fonction et mesuré par T13.
* **Aucune performance n'est mesurée.** Les budgets du §3.3 (50 ms pour un maillon simple,
  300 ms pour un document commercial complet) demandent des maillons à mesurer : c'est la
  porte **G6** du lot **L2**. La 252 fournit l'instrument (`duree_ms`, `lignes_ecrites`,
  `verrous_attendus_ms`), pas la mesure.
* **Le vocabulaire de `link_type` est fermé** aux huit types du plan (M-11) : en ajouter un
  demande une migration additive. C'est voulu — c'est ce qui met fin aux colonnes
  `reference_*` divergentes d'une table à l'autre.

---

## 6. Ce que la vague suivante (L1) doit produire

Le lot L1 ajoute `link_documents` et `emit_domain_event` dans les **62 maillons existants**,
sans changer leur logique, puis reconstruit l'historique déductible. Le contrat est celui de
la 252 :

1. chaque maillon commence par `chain_avant(...)` et finit par `chain_apres(...)` — le
   squelette est écrit dans l'en-tête de `252_chain_socle.sql` (§15) ;
2. le `tenant_id` vient de la **ligne source** (`NEW.tenant_id`), jamais de la session ;
3. l'effet s'écrit en **un seul `INSERT … SELECT`** (zéro requête N+1) ;
4. le contrat de chaque effet s'inscrit dans `document_effects` (lot L7) — un maillon ne
   décide pas son propre contrat ;
5. la suite du module reste verte, et la suite 252 reste verte : l'idempotence qu'elle exige
   (T02, T10) est celle que les 61 autres maillons doivent désormais tenir.

**Registre.** Aucune exception inscrite : les 16 scénarios de la 252 passent. Les deux
limites les plus fortes du §5 ne sont pas des défauts à blanchir — la première est une
propriété de PostgreSQL, la seconde un lot non commencé.

