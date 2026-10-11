# Partie F — fonctions manquantes, plateforme

> Fichier de suivi **exclusif** de la partie F (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/f-plateforme` |
| **Worktree** | `.claude/worktrees/plan6-f-plateforme` |
| **Plage de migrations** | `700` → `749` |
| **Territoire de fichiers** | `supabase/functions/`, écrans CRM, projets, paramètres, notifications ; leurs tables coquilles |
| **Charge** | **recomptée le 05/10 (F.1)** : ≈ 17 j pour les chantiers décidés « faire » (hors F.2, livré) ; ≈ 45-55 j au total avec F.3 → F.8 |
| **Départ possible** | **tout de suite, par F.1 et F.2** — toutes deux **faites** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| F.1 | **Recompter** les ❓ de son périmètre et **estimer** les ⬜ | BNQ-04, TRE-01, CRM-03, PRJ-01/06/07/09, BI-03, SEC-03, PRF-03/04, UX-05, ADM-01/03/05, IMP-03, NOT-03, ONB-02, PAY-01/11/12 | à chiffrer | ✅ **recompté le 05/10** — verdicts ci-dessous |
| F.2 | Authentification forte : suite SQL (émission, usage, révocation, rejeu d'une clé ; TOTP), test Edge « clé révoquée → 401 » | ORPH-01, SEC-02 | 1 j | ✅ **livré le 05/10** — migration `700`, suite `700` (T01→T13), test Edge « révoquée → 401 » |
| F.3 | `generate-pdf`, voie A : convertisseur isolé, `GOTENBERG_URL`, un appelant | 1.13, D-4 | 1 j (code) + décision D-4 | 🔴 **attend de vous** — D‑4 §9 : le code est durci (503 honnête, bucket `317`), il reste A1 (convertisseur injoignable), le secret `GOTENBERG_URL`, un appelant, le déploiement |
| F.4 | Groupe : structure, opérations intra-groupe, consolidation | GRP-01 → 03 | ≈ 5 j | ✅ **livré le 05/10** — `702` (structure + intra-groupe) et `703` (consolidation), + écran Paramètres → Groupes |
| F.5 | CRM (séquences, scoring) ; projets (capacité par ressource, champs personnalisés, automatisations) | CRM-01/02, PRJ-02/04/08 | ≈ 5 j | ✅ **livré le 05/10** — PRJ‑04 (`706`), PRJ‑02 (`708`), CRM‑01 (`709`), CRM‑02 (`710`) ; **PRJ‑08 (automatisations)** est un **moteur de règles** : **transféré à la partie A** (L22/L23 — R3/R7, voir ci‑dessous) |
| F.6 | Notifications et alertes ; rattachement universel de documents ; générateur d'états ; modèles de documents ; connecteurs métier | NOT-01/02, GED-01, BI-01, ADM-04, API-03 | ≈ 8 j | 🟡 **GED‑01 (`707`) et API‑03 (`711`) livrés le 05/10, NOT‑01 (`712`) et ADM‑04 (`713`) le 11/10** ; **NOT‑02 et BI‑01 restent** |
| F.7 | RH hors paie : conventions collectives, recrutement ; mobile hors ligne | PAY-08, RH-03, PTL-03 | ≈ 4 j | ✅ **PAY‑08 et RH‑03 livrés le 05/10** (`704` conventions collectives + `705` recrutement, avec leurs écrans) ; **PTL‑03 (mobile hors ligne)** reste — hors lot base de données |
| F.8 | Tables coquilles de son périmètre (les 25 autres), **brancher ou supprimer** | ORPH-02 | ≈ 5 j | 🟡 **premier lot livré le 05/10** — recomptage (5 tables réelles, pas 25) + `time_entries` supprimée (`701`) |

## F.1 — le recomptage (fait le 05/10/2026)

Les 20 chantiers ❓ du périmètre, chacun avec un verdict — **faire**,
**reporter**, **écarter** ou **transférer** (R3 : ce qui n'est pas à nous est
consigné ici, l'intégration le transmet). Constats de départ :
[SUIVI-CHANTIERS.md](../SUIVI-CHANTIERS.md) et le plan 9,5.

| Chantier | Verdict | Charge | Pourquoi |
|---|---|---|---|
| **PAY-01** deux corrections immédiates (bloquant, « 2 h ») | **transférer à B** | (B) | moteur de bulletin — territoire de B (R3 : consigné) |
| **PAY-11** solde de tout compte | **transférer à B** | 1,5 j (B) | idem — « la moitié existe déjà » dit le plan 9,5 |
| **PAY-12** architecture cible du moteur | **transférer à B** | décision | décision d'architecture paie, pas une charge F |
| **BNQ-04** SEPA complet | **reporter** | ≈ 3 j | après B.2 (règles d'état trésorerie) : le moteur décide d'abord |
| **TRE-01** prévisionnel enrichi | **reporter** | ≈ 2 j | `cash_flow_forecast` vient d'être réécrit (470) ; laisser B.2 poser ses règles |
| **CRM-03** suivi d'e-mails / IMAP | **écarter (v1)** | — | périmètre marketing ; Resend 👤 en attente ; à revoir après NOT-01/02 |
| **PRJ-01** dépendances, chemin critique | **faire** | 3 j | la base existe (7 fichiers SQL), aucun chemin critique, un seul lecteur |
| **PRJ-06** modèles de projet et jalons | **faire** | 2 j | `project_milestones` est une coquille ; chaque projet se construit à vide |
| **PRJ-07** référence de planning | **reporter** | 1,5 j | dépend de PRJ-01 (la baseline ne se compare qu'à un planning tenu) |
| **PRJ-09** portefeuille, permissions | **faire** | 2 j | `project_members` existe, jamais opposable |
| **BI-03** performance des tableaux de bord | **faire, mesuré d'abord** | 2 j | 137 `.reduce()` dans les pages : mesure avant correctif |
| **SEC-03** journal d'audit applicatif | **faire, en LISANT L23** | 2 j | `415` a posé le journal d'événements unifié : l'étendre, ne pas le réécrire |
| **PRF-03** rendu React (85 `key={index}`) | **transférer à D** | (D) | écrans — territoire de D (R3 : consigné) |
| **PRF-04** équilibre en `FOR EACH STATEMENT` | **reporter — à arbitrer** | 1 j | déclencheur au cœur du socle comptable : ni B ni F ne doivent le réécrire seuls (R7) ; décision d'intégration |
| **UX-05** saisie comptable au clavier | **transférer à D** | (D) | écrans (R3 : consigné) |
| **ADM-01** assistant de paramétrage | **reporter** | 1,5 j | après ONB-02 (le guide suit l'invitation) |
| **ADM-03** paramétrage comptable et fiscal | **transférer à C** | (C) | c'est le lot K : `resolve_account`, grilles fiscales (R3 : consigné) |
| **ADM-05** journal d'audit exposé | **faire (avec SEC-03)** | +0,5 j | même chantier : `/system/audit-log` lit ce que SEC-03 trace |
| **IMP-03** reprise tiers, articles, stocks, salariés | **faire** | 3 j | l'import générique existe (IMP-02), la reprise structurée non |
| **NOT-03** canaux de diffusion | **reporter** | 1,5 j | Resend 👤 en attente ; « trois canaux bien faits » dit le plan |
| **ONB-02** invitations et gestion d'équipe | **faire** | 2 j | `/select-tenant` existe ; le lien d'invitation à durée limitée non |

**Bilan du recomptage** : 8 chantiers « faire » (PRJ-01, PRJ-06, PRJ-09, BI-03,
SEC-03 + ADM-05, IMP-03, ONB-02) ≈ **16,5 j** ; 5 reportés ; 1 écarté ;
6 transférés (PAY-01/11/12 → B, PRF-03 + UX-05 → D, ADM-03 → C — à transmettre
par l'intégration, R3) ; 1 à arbitrer (PRF-04, décision d'intégration).
Avec F.2 livré (1 j) et F.3 → F.8 estimés à ≈ 28 j, **la partie F ≈ 45-55 j**.
Sans F.1, il n'y avait pas de dates — seulement une liste.

## F.2 — livré le 05/10 (ORPH-01 / SEC-02)

« Une clé qu'on ne peut pas révoquer n'est pas une authentification forte. »
La preuve demandée était un test Edge **« clé révoquée → 401 »** — pas
« la clé existe », pas « la clé expire ». Livré :

- **`sql/700_auth_forte_api_keys_totp.sql`** (numéro pris par l'outil, R2) :
  - `authenticate_api_key(p_raw_key)` — **la** vérité du cycle de vie d'une
    clé : refus **nommés** (`not_found`, `revoked`, `expired`), hash SHA-256
    côté base (SEC-01), `last_used_at` posé à l'usage. Réservée à
    `service_role`. **L'ancien chemin de public-api ne lisait QUE
    `active = true` : une clé expirée ouvrait l'API indéfiniment** ;
  - TOTP **réel** (RFC 6238, HMAC-SHA1) : `_totp_b32`, `_totp_code`,
    `verify_totp` réécrit — l'ancienne acceptait **tout** code à 6 chiffres
    dès qu'un enrôlement existait, et **rendait le secret** à l'appelant ;
  - `revoke_api_key` honnête : un identifiant d'une autre société est un
    refus nommé (`API_KEY_INTROUVABLE`), une clé déjà révoquée le dit —
    plus jamais un `success: true` muet.
- **`sql/700_auth_forte_api_keys_totp_tests.sql`** (T01 → T13) : émission,
  usage, mauvaise clé, révocation, **rejeu**, **expiration**, isolation,
  révocation croisée, **trois vecteurs du RFC 6238** (ce n'est pas la
  fonction qui se prouve : c'est le standard), code juste accepté (sans le
  secret), code faux refusé, cycle enable → verify → disable. Les scénarios
  rouges-avant sont nommés dans l'en-tête de la suite.
- **`public-api`** ne garde plus aucune copie de la logique : il appelle la
  RPC et **obéit** au verdict.
- **Test Edge `api_key_auth_test.ts`** : **révoquée → 401** (le refus nomme
  sa raison), expirée → 401, inconnue → 401, contre-épreuve : une clé valide
  ouvre la garde (200 sur `/health`). Le harnais a gagné un crochet
  `__stubRpc` (rétrocompatible : sans lui, tous les tests W6 sont inchangés).
- **Câblage** : la suite est dans `ci.yml` sous le marqueur `plan6:f` (R5).

Pas de changement de schéma (aucune colonne, aucune table) :
`npm run db:types` n'a rien à régénérer (R6 : rien à signaler à
l'intégration sur ce point).

## F.8 — premier lot livré le 05/10 : le recomptage, et une coquille retirée

**Le chiffre du plan est périmé.** Le suivi annonce « 37 tables coquilles », dont
« les 25 autres » pour F. Mesuré le 05/10 contre le schéma réel : sur les 24
tables listées pour F, **cinq existent encore**. Deux raisons, chacune tenable
en une ligne — et ce sont deux **défauts du calcul**, pas du produit :

1. **`164_drop_unused_vague3_tables.sql` (18/09) a déjà supprimé 22** des tables
   que le suivi compte encore. `suivi-chantiers.mjs::coquilles()` lit les
   `CREATE TABLE` des fichiers de migration et **ne regarde pas les `DROP`
   ultérieurs** : une table retirée reste comptée comme coquille.
2. **`platform_admins` n'est pas une coquille** : elle est **lue par une fonction
   SQL** (`is_platform_admin()`, migration `201`). Le même calcul ne regarde que
   les références du **front** (`src/` + Edge) — une table lue par du SQL pur
   passe donc pour une coquille.

**Les cinq tables réellement existantes, et leur verdict :**

| Table | Verdict | Pourquoi |
|---|---|---|
| `collective_agreements` | **brancher (F.7)** | PAY‑08, conventions collectives — conservée |
| `collective_classifications` | **brancher (F.7)** | idem — conservée |
| `platform_admins` | **brancher (lot K/C)** | lue par `is_platform_admin()` ; hors périmètre F — intacte |
| `time_entries` | **supprimer** ✅ **fait (`701`)** | second modèle de temps, jamais lu, double `timesheets` |

**`time_entries` — la décision que la 164 avait laissée ouverte.** La 164 l'avait
conservée car elle serait « la cible des 16 fonctions de
`queries/projectManagementSprint1.ts` ». Mesuré le 05/10, cet argument **n'est
plus vrai** : ces fonctions visent `project_time_entries`. Et la 127 la crée
(bloc « RH‑01 ») sans que **rien** ne la lise : aucune occurrence dans `src/` hors
le type généré, aucune fonction/vue/politique/déclencheur en SQL, aucune suite.
Surtout, elle **double une table vivante** : `timesheets` (baseline, paie W9,
écrans RH). Deux modèles de temps, un seul branché — c'est le leurre que F.8
retire.

**Livré** : migration `701` (garde « vide **et** non référencée » de la 164 :
sur une base qui porte des données, la table est **conservée** et la migration
le dit) ; suite `701` **4/4** (le leurre part ; `timesheets`,
`project_time_entries`, les deux tables de F.7 et `platform_admins` restent) ;
types régénérés (`db:types`, le type `time_entries` disparaît — le diff ne
touche **que** ce bloc) ; câblage sous le marqueur `plan6:f`.

**Ce qui reste de F.8** : « brancher » les tables de F.4→F.7, c'est‑à‑dire
**écrire ces fonctionnalités** (le groupe, le CRM, les documents, les
conventions collectives). Il n'y a **plus de table morte à retirer** dans le
périmètre F — la 164 et la 701 ont fait le tri.

## F.4 — premier lot livré le 05/10 (GRP‑01 + GRP‑02)

**Les tables de la 127 avaient été supprimées** par la `164` le 18/09 (« nommées
NULLE PART ») : c'était vrai, il n'y avait que du DDL. F.4 les rétablit, mais
**corrigées** sur les deux points que la 127 avait faux :

1. **Un groupe relie plusieurs sociétés.** La 127 rangeait `group_entities` sous
   une seule société (`tenant_id`) — un « groupe » qu'une seule société voit
   n'est pas un groupe. Le maître **`groups`** est donc **global** ; l'appartenance
   vit dans **`group_members`** (qui porte, lui, le `tenant_id` de la société
   membre) ;
2. **Le cloisonnement reste tenu par la base.** Un membre ne voit que son groupe
   et ses pairs. La lecture passe par `my_group_ids()`, un helper SECURITY DEFINER
   sans lequel deux politiques se référenceraient l'une l'autre (« infinite
   recursion detected in policy »). L'écriture, elle, **n'a aucune politique** :
   seules les RPC écrivent, après avoir vérifié que l'appelant est
   **administrateur d'une société membre**.

**Livré** : migration `702` (`groups`, `group_members`,
`intra_group_transactions`, RLS, helper, 5 RPC : `create_group`,
`add_group_member`, `remove_group_member`, `record_intra_group_transaction`,
`group_structure`) ; suite `702` **8/8** ; **l'écran**
`Paramètres → Groupes` (`GroupsPage` + `lib/queries/groups.ts` + nav + route
`/settings/groups` + i18n fr/en/ar).

⚠️ **Pourquoi l'écran dans le même lot** : sans lui, les 3 tables neuves
comptaient comme « coquilles » et faisaient **monter** un plafond gelé
(`check-unused-tables`, `SOC-05`) — c'est-à-dire exactement le « leurre » que
F.8 retire. Les brancher était la condition, pas une option. Effet mesuré sur le
plafond : **75 → 74** (la 701 retire `time_entries`, les 3 tables de la 702 sont
lues par l'écran).

**Un plafond daté réinscrit** : `check_bt_grid` (`rls_sans_force` 54 → **53**,
`sans_index_societe` 78 → **77**) — c'est une **baisse** (amélioration) : la 701
retire `time_entries` (RLS non forcée, sans index de société) et la 702 ajoute
`group_members` (forcée, indexée). Le contrôle exige de réinscrire le plafond
dans le même commit ; c'est fait, daté.

**GRP‑03 — la consolidation (migration `703`, suite `703` 6/6, dans l'écran).**
Fonction `group_consolidated_balance(p_group_id, p_from, p_to)` : elle agrège le
grand livre des sociétés membres, par compte et par période, en appliquant la
**méthode** de chacune — `full` (poids 1), `proportional` (poids = détention),
`equity`/`none` **exclus** — et **publie** les flux intra-groupe de la période
pour élimination. Mesuré par la suite : A (full 100) + B (proportional 60 % × 200)
donne le compte 601 à **220** ; un membre `none` (999) et une écriture **hors
période** (1000) n'entrent pas ; les flux sont comptés (1 flux, 500) sans être
éliminés.

⚠️ **Ce que cette consolidation N'EST PAS, et c'est écrit dans la migration** :
une consolidation de **premier niveau**. La **mise en équivalence** (`equity`)
n'est pas calculée ; l'**élimination automatique** des flux intra-groupe non plus
(la table porte le montant, pas l'écriture) ; il n'y a **pas de conversion de
devises**. Un groupe multi-devises ne lira un total homogène que si ses sociétés
partagent la devise. Ce sont des limites dites, pas des oublis.

**La garde** : la fonction lit le grand livre d'AUTRES sociétés — le seul cas
légitime du produit — et elle est réservée à un **administrateur d'une société
membre** (un membre non administrateur ou une société hors du groupe sont refusés
nommément : `GROUP_FORBIDDEN`, `GROUP_NOT_MEMBER`).

## F.7 — premier lot livré le 05/10 (PAY‑08, conventions collectives)

**Le constat.** `collective_agreements` et `collective_classifications` ont été
créées par la `123` (PAY‑08), avec leurs deux colonnes de rattachement sur
`employees` (`collective_agreement_id`, `classification_id`) rendues **composites**
par la `237` — puis **jamais lues** : deux « coquilles » (ORPH‑02). Deux défauts
mesurés le 05/10 :

1. leur **RLS est activée mais NON forcée** — le défaut ISO‑04 que la grille BT
   comptait (`rls_sans_force`) ;
2. **rien ne valide le rattachement** : `employees.collective_agreement_id`
   s'écrit par un simple UPDATE, sans vérifier que la convention appartient à la
   société ni que la classification appartient **à cette convention** — les clés
   composites garantissent la **société**, pas la cohérence interne.

**Livré** :
- migration `704` : **FORCE RLS** sur les deux tables ; `set_employee_collective_agreement(...)`,
  le seul chemin d'affectation, qui vérifie que l'appelant est **administrateur**,
  que le salarié et la convention relèvent de la société, et que la classification
  appartient à la convention (`AGREEMENT_NOT_FOUND`, `CLASSIFICATION_MISMATCH`,
  `PAY_FORBIDDEN` — refus **nommés**) ;
- suite `704` **6/6** (RLS forcée ; affectation ; refus convention étrangère ;
  refus classification incohérente ; refus non‑admin ; retrait) ;
- **l'écran** `Paramètres → Conventions collectives` (conventions, classifications,
  rattachement d'un salarié) + i18n fr/en/ar.

**Plafond daté réinscrit** : `check_bt_grid` `rls_sans_force` 53 → **51** (les deux
tables passent sous FORCE). `check-unused-tables` **74 → 72** (les deux tables sont
lues par l'écran).

**Ce qui restait de F.7 — RH‑03, le recrutement (livré, migration `705`).** Les
tables d'un premier jet avaient été **supprimées par la 164** (« nommées NULLE
PART »). La `705` les rétablit sur un modèle **standard** — faute d'arbitrage
produit, et le vocabulaire est écrit dans la migration pour être discuté :
- **un poste** (`job_postings`) : intitulé, service, type de contrat (CDI/CDD/
  stage/alternance/intérim/freelance), lieu, nombre de postes, et un **cycle de
  vie** (`draft` → `open` → `closed`/`filled`) ;
- **une candidature** (`job_applications`) : rattachée au poste par une **clé
  composite** `(tenant_id, posting_id)` — la candidature d'une société ne peut
  pas viser le poste d'une autre (ISO‑02), et supprimer un poste emporte ses
  candidatures —, avec un **pipeline** nommé (`received` → `screening` →
  `interview` → `offer` → `hired`/`rejected`).
Les **statuts sont contraints par la base**, pas par l'écran. **RLS forcée**,
index de société, **quatre politiques par table**. Suite `705` **6/6** : RLS
forcée ; statuts par défaut ; refus d'un statut hors vocabulaire (`23514`) ;
refus d'une candidature inter‑société (`23503`) ; cascade de suppression ; et le
**visiteur `anon` sans aucun droit**. Écran **RH → Recrutement** + i18n fr/en/ar.
Plafond daté réinscrit : `check_bt_grid` `tables_tenant` 365 → **367** (deux
tables neuves) ; `unused-tables` 72 → **70**.

Reste de F.7 : **PTL‑03 (mobile et hors ligne)** — hors d'un lot base de données.

## F.5 — premier lot livré le 05/10 (PRJ‑04, champs personnalisés)

**Le constat.** Les tables d'un premier jet (`custom_field_definitions`,
`custom_field_values`) avaient été **supprimées par la 164**. F.5 les rétablit —
une société a toujours un champ que le produit n'a pas prévu (un numéro
d'affaire, une date de visite) et n'a nulle part où le mettre.

**Le modèle, et ce qui le tient** (migration `706`) :
- une **définition** décrit un champ pour un couple *(module, entité)* — son
  `field_type` est **contraint** (text/number/date/boolean/select), sa clé est un
  identifiant technique, et un `select` **doit** porter ses options ;
- une **valeur** porte le champ pour **un enregistrement**, rattachée à sa
  définition par une **clé composite** `(tenant_id, definition_id)` : supprimer une
  définition **emporte** ses valeurs, et une valeur ne peut pas viser la définition
  d'une autre société (**ISO‑02**) ;
- un **déclencheur** tient la cohérence que les clés ne peuvent pas tenir : le
  **type de la valeur suit la définition** (`number` → un nombre, `boolean` →
  vrai/faux, `select` → une de ses options), et un champ **désactivé** n'accueille
  plus de valeur — refus **nommés** (`CUSTOM_FIELD_TYPE`, `CUSTOM_FIELD_OPTION`,
  `CUSTOM_FIELD_INACTIVE`).

**Livré** : migration `706` (RLS forcée, index de société, 4 politiques par table,
`anon` révoqué) ; suite `706` **8/8** (RLS forcée ; clé de champ unique ; `select`
sans options refusé ; texte dans un `number` refusé — **et un nombre du bon type
accepté**, sinon le refus ne prouverait rien ; valeur hors options refusée ; valeur
inter‑société refusée *et* clé composite présente ; champ désactivé refusé ;
cascade) ; **écran** `Paramètres → Champs personnalisés` (définitions + saisie des
valeurs pour un projet) + i18n fr/en/ar.

Plafonds datés réinscrits : `check_bt_grid` `tables_tenant` 367 → **369** ;
`unused-tables` 70 → **68**.

⚠️ **Limites dites** : **un seul module est branché** (les projets) — le modèle
est générique, mais brancher un autre module demande une définition de plus **et**
un point d'entrée dans son écran ; la valeur n'est pas indexée par
*(module, entité)* au niveau de la table (elle l'est par sa définition) ; il n'y a
pas de champ **calculé** ni de validation « requis » à la saisie (l'obligation est
déclarée, pas encore opposable).

## F.6 — premier lot livré le 05/10 (GED‑01, le rattachement de documents, validé)

**Le constat, mesuré le 05/10.** `module_documents` (migration 68) porte **deux
colonnes polymorphes** — `entity_type`, `entity_id` — qui disent à quelle pièce un
document se rattache. Elles sont **lues et écrites** par la couche d'écrans, et
**rien ne les valide** : seul `tenant_id` est posé (`set_tenant_id_module_documents`),
aucune contrainte, aucune clé étrangère (une colonne polymorphe ne peut pas en
porter), **aucun contrôle d'existence**. Mesuré : un document peut se rattacher à
une pièce **qui n'existe pas**, ou à une pièce **d'une autre société** —
`entity_id` est un `uuid` nu. C'est le défaut ISO‑02 que la Partie 5 a fermé pour
`document_links` (`451`) ; `module_documents` **n'avait pas eu sa contrepartie**.

**Livré** : migration `707` — un déclencheur `validate_module_document_link` sur
`module_documents` (`BEFORE INSERT OR UPDATE OF entity_type, entity_id`) :
- **les deux colonnes, ou aucune** (une moitié ne désigne rien) ;
- `entity_type` doit être un **code du registre `chain_document_types`** (les 27
  pièces de la `450` — factures, avoirs, BL, écritures, lots de paie, tickets,
  mouvements de stock…) ;
- la pièce doit **exister dans la société du document** (lecture bornée par la
  RLS du lecteur **et** filtre `tenant_id` explicite — les deux gardes).
Refus **nommés** : `DOCUMENT_LINK_INCOMPLETE`, `DOCUMENT_LINK_TYPE`,
`DOCUMENT_LINK_MISSING`. La fonction de déclencheur est **retirée de `PUBLIC`**.
Suite `707` **7/7** (registre = 27 codes ; document **sans** rattachement accepté ;
rattachement valide accepté ; pièce inexistante refusée ; pièce d'une autre société
refusée ; type inconnu refusé ; moitié de rattachement refusée).

**Pas de nouvelle table** : la coquille `document_entity_types` (vue par F.8)
aurait **recopié** `chain_document_types` — un second registre qui aurait pu
diverger. Le registre des chaînages **est** le registre des pièces.

⚠️ **Limites dites** : le vocabulaire accepté est celui du **registre** (27 codes) —
une pièce qui n'y figure pas (projet, client, salarié) ne peut pas encore accueillir
de document ; l'ouvrir demande d'inscrire son code au registre (un acte de revue).
Et l'écriture est aujourd'hui **orpheline côté écran** (`DocumentList` /
`DocumentUploader` n'ont **aucun appelant**) : cette migration rend le rattachement
**réel**, elle ne le rend pas encore **visible** — brancher l'écran est le lot
suivant.

## F.5 — deuxième lot livré le 05/10 (PRJ‑02, la capacité par ressource)

**Le constat.** La table d'un premier jet (`resource_capacities`) avait été
**supprimée par la 164**. F.5 la rétablit : planifier un projet suppose de savoir
**qui a combien d'heures disponibles sur quelle période**, et le produit ne le
disait nulle part.

**Le modèle, et ce qui le tient** (migration `708`) : une ligne = « ce salarié a N
heures par semaine, de telle date à telle date ».
- rattachement au salarié par une **clé composite** `(tenant_id, employee_id)` —
  supprimer un salarié **emporte** ses capacités, et une capacité ne peut pas viser
  le salarié d'une autre société (**ISO‑02**) ;
- bornes **contraintes** (`period_end >= period_start`, `0 ≤ heures ≤ 168` — une
  semaine n'a pas 200 heures) ;
- un **déclencheur** interdit le **chevauchement** : deux capacités du même salarié
  ne peuvent pas couvrir la même journée — la règle que **ni une clé ni un CHECK**
  ne peuvent tenir (`EXCLUDE USING gist` demanderait `btree_gist`, que le socle
  n'a pas ; le déclencheur fait le travail, et le dit dans la migration).

**Livré** : migration `708` (RLS forcée, index de société, 4 politiques par table,
`anon` révoqué) ; suite `708` **8/8** (RLS forcée ; capacité valide enregistrée ;
plus de 168 h refusé ; période à l'envers refusée ; **chevauchement refusé** ;
salarié d'une autre société refusé ; **périodes adjacentes acceptées** ;
`anon` sans droits) ; **écran** `Paramètres → Capacité par ressource` + i18n
fr/en/ar. Plafonds datés réinscrits : `check_bt_grid` `tables_tenant` 369 → **370** ;
`unused-tables` 68 → **67**.

⚠️ **Un défaut corrigé en écrivant la suite** : le déclencheur appelait
`daterange(début, fin)` sur une **période inversée**, et PostgreSQL **lève**
(« range lower bound must be less than or equal to range upper bound ») avant tout
chevauchement — le refus n'était donc pas celui du CHECK de la table. Mesuré par
T04 (rouge), corrigé par une garde qui laisse la période inversée au CHECK.

⚠️ **Limite dite** : la capacité est **déclarée**, elle n'est pas encore **lue** par
la planification (le rapprochement capacité ↔ charge d'un projet est un lot) —
l'écran la saisit et la montre, c'est tout.

## F.5 — troisième lot livré le 05/10 (CRM‑01, les séquences de relance)

**Le constat.** `crm_sequences` et `crm_sequence_steps` avaient été **supprimées
par la 164**. F.5 les rétablit : relancer un prospect, c'est une **cadence** — un
e‑mail, puis un appel trois jours après, puis une tâche — et le produit ne savait
pas la décrire.

**Le modèle, et ce qui le tient** (migration `709`) :
- une **séquence** : nom **unique par société** (deux « Relance devis » seraient un
  doublon), description, état ;
- une **étape** : rattachée à sa séquence par une **clé composite** `(tenant_id,
  sequence_id)` — supprimer une séquence **emporte** ses étapes, et une étape ne
  peut pas viser la séquence d'une autre société (**ISO‑02**) ;
- le **rang** est **unique dans la séquence** (`(société, séquence, rang)`) et
  strictement positif — deux étapes ne se disputent pas la même place ;
- le **délai** est positif ou nul, le **canal** contraint (`email`, `call`, `task`,
  `sms`) — la base refuse un canal hors vocabulaire, pas l'écran.

**Livré** : migration `709` (RLS forcée, index de société, 4 politiques par table,
`anon` révoqué) ; suite `709` **9/9** (RLS forcée ; séquence + étape enregistrées ;
nom de séquence unique ; rang d'étape unique ; canal contraint ; rang/délai
contraints ; étape inter‑société refusée ; **cascade** ; `anon` sans droits) ;
**écran** `CRM → Séquences de relance` + i18n fr/en/ar (namespace `crm`).
Plafonds datés réinscrits : `check_bt_grid` `tables_tenant` 370 → **372** ;
`unused-tables` 67 → **65**.

⚠️ **Ce que ce lot n'est pas** (écrit dans la migration) : le **catalogue** de la
cadence, pas son **exécution**. « Qui entre dans quelle séquence, et quand part la
prochaine étape » demande une horloge et un rattachement aux prospects — c'est un
lot, pas un oubli.

## F.5 — quatrième lot livré le 05/10 (CRM‑02, le scoring de lead)

**Le constat.** `crm_scoring_rules` avait été **supprimée par la 164**. F.5 la
rétablit : qualifier un prospect, c'est une **addition** — « vient d'une
recommandation : +20 ; CA > 1 M€ : +30 ; secteur hors cible : −15 » — et le produit
ne savait pas la calculer.

**Le modèle, et ce qui le tient** (migration `710`) :
- une **règle** dit : *pour un fait*, *avec un opérateur*, *une valeur*, elle
  ajoute *des points*. Nom **unique par société**, opérateur **contraint**
  (`equals`, `not_equals`, `contains`, `greater_than`, `less_than`, `is_set`,
  `is_not_set`), et une **comparaison EXIGE une valeur** (un `greater_than` sans
  valeur n'est pas une règle) ;
- un **moteur** (`crm_lead_score`) applique les règles **actives** aux **faits**
  fournis et rend **le total ET les règles qui ont compté** — un score qui ne dit
  pas d'où il vient ne se discute pas.

**Ce qui est droit, et pas seulement écrit** (chacun mesuré par la suite) :
un fait **absent** ne matche **jamais** une comparaison ; `greater_than` /
`less_than` comparent en **NOMBRE** (un fait non numérique ne devient pas 0 en
silence) ; le moteur filtre `tenant_id = current_tenant_id()` **explicitement** —
la RLS ne suffit pas au propriétaire.

**Livré** : migration `710` (RLS forcée, 4 politiques, `anon` **et la fonction**
révoqués) ; suite `710` **10/10** (RLS forcée ; addition 20 + 30 = 50 **et** les
règles nommées ; règle **inactive** ignorée ; `equals` ; `greater_than`
numérique ET non numérique ; points **négatifs** ; **isolation** d'une autre
société ; nom unique ; opérateur/valeur contraints ; `anon` sans droits) ;
**écran** `CRM → Scoring de lead` (règles + **simulateur** qui appelle le moteur)
+ i18n fr/en/ar. Plafonds datés réinscrits : `check_bt_grid` `tables_tenant`
372 → **373** ; `unused-tables` 65 → **64**.

⚠️ **Limite dite** : le moteur est un **calcul à la demande** — rien ne **stocke**
encore le score d'un lead ni ne le recalcule à son changement ; le brancher sur la
fiche prospect est un lot.

## F.6 — deuxième lot livré le 05/10 (API‑03, les connecteurs métier)

**Le constat.** `business_connectors` avait été **supprimée par la 164**. F.6 la
rétablit : intégrer une société, c'est d'abord **déclarer où l'on parle**.

**Le modèle, et ce qui le tient** (migration `711`) :
- un **connecteur** : nom **unique par société**, **type contraint** (`webhook`,
  `rest`, `odoo`, `sage`, `stripe`, `generic`), URL de base, **mode
  d'authentification contraint** (`none`, `api_key`, `basic`, `oauth2`) ;
- **il ne porte JAMAIS le secret** : `auth_ref` est le **nom** sous lequel le
  secret vit ailleurs (un secret d'Edge Function) — une table qui contiendrait le
  jeton serait une fuite en attente —, et un mode d'authentification **exige** une
  référence (CHECK) ;
- l'URL passe la **garde SSRF du dépôt** : `is_allowed_webhook_url` (`154`, durcie
  par `167`) — **HTTPS seul**, hôte public seul. On ne réécrit pas le contrôle, on
  l'appelle ; le refus est **nommé** (`CONNECTOR_URL_REFUSED`).

**Livré** : migration `711` (RLS forcée, 4 politiques, `anon` révoqué, fonction de
déclencheur retirée de `PUBLIC`) ; suite `711` **8/8** (RLS forcée ; connecteur
valide ; **HTTP refusé** ; **hôte local refusé** — la garde SSRF de bout en bout ;
type contraint ; authentification sans référence refusée ; nom unique ; `anon` sans
droits) ; **écran** `Paramètres → Connecteurs métier` + i18n fr/en/ar. Plafonds
datés réinscrits : `check_bt_grid` `tables_tenant` 373 → **374** ;
`unused-tables` 64 → **63**.

⚠️ **Limite dite** : **HTTPS est une exigence**, pas un confort — un connecteur
vers un Odoo **on‑premise en HTTP sera refusé**. C'est le prix de la garde SSRF, et
c'est écrit dans la migration pour ne pas être découvert en production.

## F.6 — troisième lot livré le 11/10 (NOT‑01, les notifications personnelles)

**Le constat, mesuré sur base neuve.** `notifications` portait déjà **l'intention**
d'une boîte personnelle : une colonne `user_id`, et l'index
`idx_notifications_tenant_unread (tenant_id, user_id, read_at)`. Mais **les quatre
politiques RLS ne filtraient que la société** — `tenant_id = current_tenant_id()` —
et rien d'autre ne bornait :

- **chacun lisait les vingt dernières notifications de tout le monde**
  (`NotificationCenter.tsx` fait `from('notifications').select('*')…limit(20)`) ;
- `mark_notification_read(p_id)` ne vérifiait **que la société** : un utilisateur
  ouvrait le courrier d'un autre, **sans trace** ;
- `get_unread_notification_count()` et `mark_all_notifications_read()`, appelés
  **sans argument** par l'en-tête, lisaient `p_user_id IS NULL` comme « TOUT LE
  MONDE » : le badge comptait la société entière (mesuré **4** au lieu de 3) et
  « tout marquer lu » vidait la boîte de tout le monde (mesuré : la notification de
  B marquée lue par A) ;
- `create_notification` acceptait **n'importe quel destinataire** : un utilisateur
  connecté pouvait écrire dans la boîte d'un autre, ou diffuser à toute la société ;
- `notify_payslip_ready` (93) passait `NEW.employee_id` — un **salarié** — là où la
  colonne attend un **compte** : le salarié ne voyait jamais son bulletin, et la
  ligne ne désignait personne (`employees.auth_user_id` existait depuis le socle).

**Livré** : migration `712`, correctif **entièrement en base** — le front n'est pas
touché. Les quatre politiques sont bornées au **destinataire**, un appel sans
argument veut dire « **moi** », `user_id IS NULL` = **DIFFUSION** à la société
(l'alerte « facture en retard » concerne l'équipe, pas une personne : elle reste
visible et marquable par chacun), `anon` est révoqué, `authenticated` passe en
**lecture seule** (doctrine 271 — « une table personnelle ne s'écrit que par ses
fonctions »), un déclencheur ramène à la DIFFUSION un destinataire qui n'est pas un
membre de la société (jamais d'invisible : il rattrape les lignes déjà écrites par
l'ancien `NEW.employee_id` **et** empêche que ça recommence, sans jamais annuler
l'acte métier qui l'a provoqué), et le bulletin de paie est adressé au **compte**
du salarié.

Deux règles écrites une fois : `user_id IS NULL` = diffusion ; `auth.uid() IS NULL`
= appel **serveur** (déclencheur, `SECURITY DEFINER`, `service_role`) — c'est ce qui
laisse les onze déclencheurs du dépôt fonctionner sans être réécrits. Et un
**marqueur serveur** (`app.notification_serveur`) que **seuls** les déclencheurs du
dépôt posent : sans lui, la garde anti‑usurpation refusait la notification du
bulletin de paie, qui s'exécute **pendant la requête** du gestionnaire de paie et
écrit pour quelqu'un d'autre — défaut trouvé **en écrivant la suite**, corrigé dans
la même migration.

**Mesuré** : suite `712` **13/13**, et **10 rouges / 3 verts** sur l'état d'avant —
reconstruit **verbatim depuis la 93**, jamais inventé. Les trois verts sont les
non‑régressions **assumées** : RLS forcée, diffusion déjà visible, cloisonnement
d'une société à l'autre. Les dix rouges (T02 `anon` avait `SELECT`, T03
`authenticated` écrivait en direct, T04 les 4 politiques sans borne utilisateur, T05
la fuite — **1** ligne de B visible, T07, T08, T09, T10, T11, T12) sont **refusés
par le registre de la CI** (il est vide) : un défaut qui revient casse la CI.

**Portes** : G5 `check-test-suites` → **163 suites, toutes jouées** (la 712 est
branchée dans `ci.yml`) ; G1 `check_bt_grid` **inchangée** (aucune table en plus) ;
`check_anon_grants` 0 relation modifiable par `anon` ; `check_policy_duplicates`
0 doublon (table, commande) ; `check_tenant_guard` 189 fonctions `SECURITY DEFINER`
écrivantes, **0** sans mention de la société ; `check_roles_opposables` OK. **Aucun
changement de schéma** (politiques, fonctions, déclencheurs, droits seulement) :
`db:types` est inchangé, `npm run db:types` n'a pas lieu d'être ici.

⚠️ **Une mesure qui a coûté, et qu'il faut retenir.** Le premier jet de la suite
faisait mourir son T09 sur « invalid input syntax for type json ». Cause : un **GUC
personnalisé n'est jamais « désactivé »** — après le COMMIT d'un `SET LOCAL`, le
placeholder reste à la chaîne **vide**, et `current_tenant_id()` fait
`current_setting('request.headers', true)::json`. La doctrine du dépôt est écrite
dans la 236 (lignes 36‑44) : **l'en-tête en session (`false`), le rôle en local
(`true`)**. C'est ce que fait la suite 712 — l'en-tête de société est posé **en
session** avant les deux transactions `authenticated`, et c'est T13 qui le
surcharge **localement** (une requête forgée qui ne mène nulle part) : au COMMIT,
l'en-tête de session revient, et T09 peut jouer juste après.

⚠️ **Limites dites** : (1) `create_notification` **reste** appelable par un
utilisateur connecté pour **lui‑même** (poser une notification depuis un écran) —
c'est voulu, mais aucun écran ne le fait aujourd'hui : les producteurs sont des
déclencheurs, et le marqueur serveur n'est posé que par `notify_payslip_ready` (les
autres n'ont pas de destinataire à traverser — vérifié : `tu.auth_id` en 264/414,
`employees.auth_user_id` en 93/188, ou NULL). (2) Les **canaux** restent dehors :
`NOT‑02` (alertes/abonnements) et `NOT‑03` (e‑mail/push, reporté — Resend 👤 en
attente) ne sont pas traités ici. (3) La suite mesure ce que la **base** rend à
l'appel sans argument, pas le **rendu** de l'en-tête : le front n'étant pas touché,
il n'y a rien à rejouer côté écran — mais rien ne **prouve** non plus l'affichage.
(4) `plpgsql_check` est **absente de l'image locale** (contrôle non exécutable ici,
comme pour les lots voisins) et les contrôles JS qui interrogent la base
(`check-rpc-contract`, Vitest) ne tournent pas dans ce worktree (`node_modules`
vide) : le contrat des quatre RPC a donc été vérifié **en SQL** contre `pg_proc` —
signatures **identiques** à celles d'avant la 712, donc les trois appels du front
(`get_unread_notification_count`, `mark_notification_read`,
`mark_all_notifications_read`) sont intacts.


## F.6 — quatrième lot livré le 11/10 (ADM‑04, modèles de documents)

**Le constat.** `document_templates` avait un index **unique sans condition** sur
`(tenant_id, document_type, is_default)` : il interdisait deux modèles pour le
même type, mais ne garantissait **pas** qu'un seul fût marqué « défaut » —
`is_default` était un simple booléen que le front posait par `UPDATE` direct
(cas d'égalité : deux `true` côte à côte, l'ancien système de validation ne
faisait rien). La `FOR ALL` (`document_templates_tenant`) s'ajoutait aux autres
politiques et les annulait (ISO‑03), et les trois commandes d'écriture n'avaient
pas de garde de rôle (PERM‑01). `name`, `primary_color`/`secondary_color` et
`config` n'étaient pas contraints. `logo_url` était une URL quelconque (SSRF).

**Livré** : migration `713` — 7 gestes :

1. **Index unique partiel** : `idx_document_templates_one_default` sur
   `(tenant_id, document_type) WHERE is_default` — le `is_default` est retiré du
   vieil index (qui reste pour la déduplication), un nouvel index partiel
   garantit **un seul défaut par type** ;
2. **Bascule transactionnelle** : `set_default_document_template(uuid)` —
   `SECURITY DEFINER`, `can_perform` opposable, `anon` révoqué, démarquage de
   l'ancien puis marquage du nouveau **dans la même requête** (pas de
   fenêtre sans défaut) ;
3. **`FOR ALL` retirée** (ISO‑03) + 3 commandes × `can_perform` (PERM‑01, D‑6 :
   c'est un réglage de société) ;
4. **CHECK** : `name` ≤ 100, couleurs hexa `^#[0-9a-fA-F]{6}$`, `config` JSONB
   objet ;
5. **SSRF** : déclencheur `zz_713_check_logo_url` qui refuse un `logo_url`
   non approuvé (réutilise `is_allowed_webhook_url`) ;
6. **Reprise** : couleurs invalides → valeurs par défaut (`#2563eb` / `#64748b`),
   `config` non objet → `NULL` ;
7. **Écran** : colonne « Défaut » + bouton « Définir par défaut » branché sur
   la RPC (pas un INSERT direct — l'écran appelait jusqu'ici `supabase.from()`
   pour tout), i18n fr/en/ar à parité.

**Mesuré** : suite `713` **14/14** (T01→T14), et **11 rouges / 3 verts** sur
l'état d'avant. Portes : G7 `check_forced_rls_writers` → tables_forcees
318→332, muettes 18→21 ; G5 **164/164** ; tous les contrôles CI verts
(`check_bt_grid`, `check_composite_fks`, `check_anon_grants`, `check_tenant_guard`,
`check_status_writes`, `check_roles_opposables`, `check_policy_duplicates`,
`check_global_rows_writable`).

⚠️ **Limites dites** : (1) `is_default` n'est pas encore **lu** par un moteur de
rendu — le PDF, les factures et les devis ne consultent pas le flag. Ce lot rend
la donnée **vraie** ; il ne la rend pas encore **utile**. (2) `logo_url` peut
être vide (le déclencheur ne s'active que si la colonne est non NULL). (3) Les
`CHECK` sur les couleurs s'appliquent à l'écriture seule — les lignes déjà en
base n'ont pas été vérifiées (la reprise ne corrige que `config` et les
couleurs non-hexa). (4) `plpgsql_check` est absent de l'image locale (contrôle
non exécutable ici, comme pour les lots voisins).

## PRJ‑08 (automatisations de projet) — **transféré à la partie A** (R3)

Le suivi range `PRJ‑08` sous « ➜ **L22/L23** » : les automatisations de projet sont
un **moteur de règles** (L22) sur des **événements unifiés** (L23), que la partie A
construit. En livrer une version dans F créerait un **second moteur** — exactement ce
que R7 interdit (une fonction, un propriétaire) et ce que le dépôt appelle un
doublon en attente. **Demande consignée** (R3) : l'intégration la transmettra à la
partie A, qui possède `L22`/`L23` et pourra s'appuyer sur les deux tables de F.5
(`crm_scoring_rules` pour la forme « fait → points », qu'elle pourra citer plutôt
que réinventer).

## Attend de vous

- La clé **`sb_secret_…` à tourner**.
- Le **DPA** du prestataire IA.
- Les **comptes des 9 intégrations** : Chorus Pro, Yousign, GoCardless, Resend,
  EFI, SIRENE/VIES, Stripe, Gotenberg, Sentry.

## F.8 — brancher ou supprimer

Comme E.5 : pour chacune des 25 tables coquilles, deux issues seulement. Une
coquille non branchée est un leurre — elle compte dans les mesures sans
apporter d'écran.

## L'arbitrage R7 qui concerne F

En cas de doute sur une fonction d'écriture comptable : **C passe après** les
autres. F n'est pas concernée, mais elle peut l'être indirectement par F.4
(operations intra-groupe) et F.5 (projets).

## Journal

| Date | Chantier | Verdict (faire / reporter / écarter) | Charge estimée | Commit |
|---|---|---|---|---|
| 05/10/2026 | F.1 recomptage des 20 ❓ du périmètre | 8 « faire » ≈ 16,5 j ; 5 reportés ; 1 écarté ; 6 transférés (B/D/C, R3) ; 1 à arbitrer (PRF-04) | — | `plan6/f-plateforme` |
| 05/10/2026 | F.2 authentification forte (ORPH-01/SEC-02) | **fait** : migration `700` + suite T01→T13 + test Edge « clé révoquée → 401 » + câblage CI sous le marqueur `plan6:f` | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.8 tables coquilles (premier lot) | **recompté** : 24 listées → 5 existent (19 déjà supprimées par la `164`). `time_entries` **supprimée** (`701`, garde de la 164) + suite `701` 4/4 ; `collective_*` → brancher F.7 ; `platform_admins` = faux positif (lue par `is_platform_admin()`) | 0,5 j | `plan6/f-plateforme` |
| 05/10/2026 | F.4 groupe (premier lot) | **livré** : `702` (structure `groups`/`group_members` + flux `intra_group_transactions`, RLS, helper anti-récursion, 5 RPC) + suite 8/8 + **écran** Paramètres→Groupes (queries/nav/route/i18n fr/en/ar). Plafonds : `unused-tables` 75→74 ; `check_bt_grid` réinscrit (2 baisses) | 1,5 j | `plan6/f-plateforme` |
| 05/10/2026 | F.4 groupe (GRP‑03, consolidation) | **livré** : `703` (`group_consolidated_balance` — pondération full/proportional, equity/none exclus, bornage de période, flux intra-groupe publiés) + suite 6/6 + section « Consolidation » de l'écran + i18n. **F.4 complet (GRP‑01→03)** | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.7 conventions collectives (PAY‑08) | **livré** : `704` (FORCE RLS sur les 2 tables + `set_employee_collective_agreement` validée : société, convention, cohérence classification) + suite 6/6 + écran Paramètres→Conventions collectives + i18n. Plafonds : `rls_sans_force` 53→51 ; `unused-tables` 74→72 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.7 recrutement (RH‑03) | **livré** : `705` (postes + candidatures, clé composite ISO‑02, statuts contraints, RLS forcée, 4 politiques/table, `anon` révoqué) + suite 6/6 + écran RH→Recrutement + i18n. Plafonds : `tables_tenant` 365→367 ; `unused-tables` 72→70 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.5 champs personnalisés (PRJ‑04) | **livré** : `706` (définitions par module/entité + valeurs par enregistrement, clé composite ISO‑02, déclencheur qui tient le TYPE) + suite 8/8 + écran Paramètres→Champs personnalisés (module branché : projets) + i18n. Plafonds : `tables_tenant` 367→369 ; `unused-tables` 70→68 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.6 rattachement de documents (GED‑01) | **livré** : `707` — le rattachement polymorphe de `module_documents` devient VALIDÉ (les deux colonnes ou aucune ; type = code du registre `chain_document_types` ; existence dans la société), refus nommés + suite 7/7. Pas de nouvelle table, plafonds inchangés | 0,5 j | `plan6/f-plateforme` |
| 05/10/2026 | F.5 capacité par ressource (PRJ‑02) | **livré** : `708` (capacité par salarié et par période, clé composite ISO‑02, bornes contraintes, déclencheur de non‑chevauchement — la règle qu'aucune clé ne tient) + suite 8/8 + écran Paramètres→Capacité par ressource + i18n. Plafonds : `tables_tenant` 369→370 ; `unused-tables` 68→67 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.5 séquences de relance (CRM‑01) | **livré** : `709` (séquence à nom unique + étapes à rang unique, délai ≥ 0, canal contraint, clé composite ISO‑02) + suite 9/9 + écran CRM→Séquences de relance + i18n. Plafonds : `tables_tenant` 370→372 ; `unused-tables` 67→65 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.5 scoring de lead (CRM‑02) | **livré** : `710` (règles pondérées à opérateur contraint + moteur `crm_lead_score` qui rend le total ET ses raisons ; fait absent non matché ; comparaisons numériques ; filtre société explicite) + suite 10/10 + écran CRM→Scoring de lead (simulateur) + i18n. Plafonds : `tables_tenant` 372→373 ; `unused-tables` 65→64 | 1 j | `plan6/f-plateforme` |
| 05/10/2026 | F.5 PRJ‑08 (automatisations de projet) | **transféré à la partie A** (L22/L23, moteur de règles — R3/R7 : un second moteur serait un doublon). Demandé dans ce fichier, à transmettre par l'intégration | — | — |
| 05/10/2026 | F.6 connecteurs métier (API‑03) | **livré** : `711` (connecteur à type/auth contraints, jamais de secret — seulement son nom, URL validée par la garde SSRF du dépôt : HTTPS + hôte public) + suite 8/8 + écran Paramètres→Connecteurs métier + i18n. Plafonds : `tables_tenant` 373→374 ; `unused-tables` 64→63 | 1 j | `plan6/f-plateforme` |
| 11/10/2026 | F.6 notifications personnelles (NOT‑01) | **livré** : `712` — les 4 politiques RLS bornées au **DESTINATAIRE**, appel sans argument = « moi », `user_id IS NULL` = diffusion (visible de tous, marquable par chacun), `anon` révoqué, `authenticated` en **lecture seule**, destinataire non‑membre ramené à la diffusion (déclencheur), bulletin de paie adressé au **compte** du salarié, marqueur serveur pour les déclencheurs du dépôt. Correctif **entièrement en base** (front intact) + suite `712` **13/13** et **10 rouges / 3 verts** sur l'état d'avant (reconstruit verbatim depuis la 93). G5 **163/163** ; plafonds **inchangés** (aucune table, aucun changement de schéma) | 1 j | `plan6/f-plateforme` |
| 11/10/2026 | F.6 modèles de documents (ADM‑04) | **livré** : `713` — unicité partielle `(tenant_id, document_type) WHERE is_default` (un seul défaut par type), bascule transactionnelle `set_default_document_template` (SECURITY DEFINER, `can_perform` opposable, démarquage automatique de l'ancien), `FOR ALL` retirée (ISO‑03), 3 commandes × `can_perform` (PERM‑01/D‑6), CHECK (`name ≤ 100`, couleurs hexa `^#[0-9a-fA-F]{6}$`, `config` JSONB objet), SSRF sur `logo_url` (réutilisation de `is_allowed_webhook_url`), reprise des couleurs invalides et du config non‑objet. Suite **14/14** (T01→T14) et **11 rouges / 3 verts** sur l'état d'avant. Écran : colonne « Défaut » + bouton « Définir par défaut » (RPC, pas INSERT direct) + i18n fr/en/ar à parité. Plafonds G7 : `tables_forcees` 318→332, `muettes` 18→21 | 0,5 j | `plan6/f-plateforme` |