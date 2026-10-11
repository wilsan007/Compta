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
| F.5 | CRM (séquences, scoring) ; projets (capacité par ressource, champs personnalisés, automatisations) | CRM-01/02, PRJ-02/04/08 | ≈ 5 j | 🟡 **PRJ‑04, PRJ‑02, CRM‑01 et CRM‑02 livrés le 05/10** (`706`, `708`, `709`, `710`, avec leurs écrans) ; **PRJ‑08 (automatisations) reste** |
| F.6 | Notifications et alertes ; rattachement universel de documents ; générateur d'états ; modèles de documents ; connecteurs métier | NOT-01/02, GED-01, BI-01, ADM-04, API-03 | ≈ 8 j | 🟡 **GED‑01 livré le 05/10** (`707` : le rattachement de documents est **validé**) ; **NOT‑01/02, BI‑01, ADM‑04, API‑03 restent** |
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