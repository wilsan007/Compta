# L17 (tranche 1) — Le planning de production connaît l'absence

**Migration** `416_chain_l17_capacite_absence.sql` · **Suite** `416_chain_l17_capacite_absence_tests.sql`
· **Date** 02/10/2026 · **Branche** `partie-5-integrite-chainages`

> Lot **L17** du plan §5 Phase F — « Production ↔ RH (capacité ↔ absence) ».
> Dépendance : **L11** (`employee_absence_days`, 263) ✅. C'est le couple vide
> nommé en §A.4 du référentiel : « la capacité de production ne connaît pas
> l'absence : on planifie avec des salariés absents — **le cas d'usage
> fondateur de tout ce travail** ».

---

## 1. Le défaut, mesuré avant (base neuve, 273 migrations, 0 erreur)

| # | Mesure | Chiffre |
|---|---|---|
| D1 | Colonnes d'opérateur sur `planning_slots` | **0** (`employee_id` / `operator_id` / `assigned_to`) |
| D2 | Fonctions lisant `planning_slots` **ET** `employee_absence_days` | **0** |
| D3 | `v_work_center_load` (126) mentionnant une absence | **faux** |
| D4 | Gardes d'absence en aval (264) | 7 — **aucune** côté production |

Le couple n'était pas *incomplet* : il était **impossible**. Sans porteur,
aucun jour d'absence ne peut se rattacher à un créneau.

**D3 est le plus grave** : la capacité affichée était un calcul **faux
présenté comme vrai** — un poste pouvait afficher « normal » le jour où la
moitié de l'équipe était absente.

## 2. Ce que la 416 pose

1. **`planning_slots.employee_id`** — le PORTEUR, clé **composite**
   `(tenant_id, employee_id)` → `employees` (ISO-02 : une clé mono-colonne
   relierait deux sociétés), index `(tenant_id, employee_id)`.
2. **`planning_slots.bloque_par_absence`** — le CONSTAT, lisible par l'écran
   sans recalcul. Il ne décide pas, il dit.
3. **`guard_planning_slot_on_absence()`** — délégation intégrale à
   `assert_not_absent` (263). Ni le message ni la dérogation ne sont réécrits.
4. **`work_center_load_hours(société, poste, jour)`** — la charge RÉELLE,
   heures des opérateurs absents **retirées**. `0` si le poste est inconnu :
   une capacité inventée est pire que l'absence de capacité.
5. **`chain_l17_constater_absence()` + `zz_l17_absence_creneau`** — le
   compagnon (doctrine 310 : l'aval est identifié par une clé **mesurée**
   dans le corps du maillon). Il s'accroche à l'absence parce que c'est elle
   qui arrive en second (planning en janvier, congé en février), et couvre
   ses **trois temps** : INSERT, UPDATE de `blocks_work`, DELETE.

## 3. Quatre décisions, et pourquoi

### 3.1 Aucun `document_links` — mesuré, pas omis

`link_documents` (451, session Partie 5) **refuse** un type absent du registre
`chain_document_types`, et la suite 450 fige ce registre à **27 types**.
Inscrire `employee_absence_days` et `planning_slots` aurait cassé :

- la suite 450 (T01 exige 27, T11 exige 32 gardes) ;
- **surtout** la garde de suppression (453) sur `employee_absence_days` :
  `rebuild_absence_days` (263, ligne 349) **SUPPRIME** les jours d'absence
  pour les recalculer. Une garde refusant la suppression dès qu'un créneau est
  lié casserait la reconstruction de l'absence — régression dans un module que
  cette migration ne possède pas.

La paire amont→aval est donc portée par **`chain_traces`** :
`amont_type = employee_absence_days`, `amont_id = day_uid`,
`amont_ligne_id = slot_id`. Elle est **stable** : elle survit à la suppression
du jour d'absence, ce qu'un lien ne ferait pas ici. **INV-19 reste vrai par
construction** — aucun lien posé, donc aucun lien actif vers un amont disparu.

> Ce qu'il reste à faire, et qui appartient à la session qui tient le
> registre : inscrire les deux types, relever les deux plafonds de la suite
> 450, et traiter l'exception de la garde pour `employee_absence_days`.

### 3.2 Aucun `chain_avant` — un bug qu'il aurait introduit

`chain_avant` s'appuie sur `chain_deja_fait`, qui lit le **lien**. Or
`day_uid` est **déterministe** (`md5 société:salari:jour`) : un congé annulé
puis re-déclaré retrouverait la même clé, le compagnon rendrait `false`, et le
créneau **ne serait plus jamais marqué** — donc la capacité compterait les
heures d'un absent. C'est exactement le défaut que la migration combat.

L'idempotence est ici **structurelle** : la boucle ne retient que les créneaux
dont l'état est opposé à la demande. Ni `IF` recopié, ni clé à restaurer.

### 3.3 Le vocabulaire d'événement : `module.action`, **un seul point**

Mesuré : avec `production.slot.orphaned` (deux points), l'événement passe le
CHECK du catalogue, **est produit**, et la porte **415 T05** le déclare
« promesse morte » — car elle extrait `'([a-z_]+\.[a-z_]+)'`, un seul point.
Les 28 autres événements du catalogue sont tous à un point ; celui-ci aussi.
L'ancien nom est **effacé**, pas désactivé : `is_active = false` ne change rien
au verdict.

### 3.4 G4 a vu rouge, et elle avait raison

`check_tenant_guard` a refusé `work_center_load_hours` : elle lisait
`p_tenant` sans vérifier que l'appelant en est membre — un utilisateur de A
passe B en argument et lit la charge d'un poste qui n'est pas le sien, le
`SECURITY DEFINER` passant la RLS pour lui. Corrigé par le contrôle
`tenant_users` × `auth.uid()`, la seconde forme que la porte reconnaît.

## 4. Résultats

**Suite 416 — 8/8 verts** (base neuve `l17_ci`, 280 migrations, 0 erreur) :

| | Scénario | Chiffre mesuré |
|---|---|---|
| T01 | le porteur et sa clé composite | colonne ✓, clé composite ✓, index ✓ |
| T02 | l'absence **après** le planning | 2/2 créneaux, 2/2 traces **rattachées à leur créneau**, 2/2 événements |
| T03 | le cycle | marqué ✓ → **non marqué**, levée tracée 1, **historique conservé 1** |
| T04 | le rejeu | 1 trace, puis **1** |
| T05 | le refus rédigé | « Absence « annual » (congé payé) le 10/03/2026 : planification d'un créneau de production refusé » — contre-exemple « mission » **accepté** |
| T06 | la capacité ajustée | **6 h → 2 h** |
| T07 | l'isolation | contexte B, marqués A=1 **B=0** |
| T08 | le surcoût | **p95 = 0,703 ms** pour 50 ms |

**Non-régression, base neuve, ordre de la CI** — **232 verdicts, 0 rouge** :

- 234 (8) · 236 (17) · **W9 : 263 (13), 264 (11), 265 (10), 266 (34)** ·
  415 (8) · 416 (8) · 450 (14)
- chaînages 400→413 : 15, 12, 12, 11, 10, 12, 7, 8, 6, 8, 8

**12 portes vertes** : `check_anon_grants`, `check_tenant_guard`,
`check_effects_contract`, `check_forced_rls_writers`, `check_composite_fks`,
`check_bt_grid`, `check_policy_duplicates`, `check_global_rows_writable`,
`check_status_writes`, `check_trigger_reachability`, `check_roles_opposables`,
`check_chain_performance`.

**Front** : `tsc` **0** · `oxlint` **0** · **Vitest 1552 verts** ·
`check-written-columns` **0 suspecte** · `check-rpc-contract` **0** ·
i18n **fr/en/ar** (2 clés × 3) · **G5 : 103/103 suites branchées** ·
`db:types` régénéré — **6 lignes**, exactement mes 2 colonnes × `Row`/`Insert`/`Update`.

## 5. Un incident, et ce qu'il apprend

Mes deux fichiers `416` ont été **perdus sur le disque** pendant que la session
Partie 5 committait `4a053ba` → `2a5cf36`. Ils n'étaient pas commités, donc git
ne les avait pas. Récupérés intacts depuis les copies que la session avait
isolées. **« Le travail non commité n'existe pas »** (AUD-X02) — c'est la
deuxième fois que la leçon se présente dans cette journée.

## 6. Limites dites

1. **Le jour regardé est `planned_start::date`** (le jour où le travail
   commence). Un créneau qui déborde sur la nuit reste à traiter : cela
   demanderait une convention d'horaires que la base ne possède pas.
2. **La proposition de réaffectation** (3ᵉ exigence du lot) n'est pas livrée :
   le compagnon **signale**, il ne décide pas. C'est volontaire — le plan
   confie la réaffectation au chef d'atelier — mais l'interface qui **propose**
   un remplaçant reste à écrire (tranche 2).
3. **Le prévisionnel RH en sens inverse** (« une charge de production
   planifiée apparaît dans le prévisionnel RH ») n'est pas livré : il suppose
   `work_center_load_hours` stable, donc une tranche de plus.
4. `v_work_center_load` (126) n'est **pas** corrigée : elle est lue par personne
   (mesuré, 0 fonction). La capacité ajustée est une fonction nouvelle ; les
   deux calculs coexistent et le second est écrit.
5. La garde refuse un créneau posé sur un jour d'absence **bloquante** ; une
   dérogation validée (`approval_workflows`) la lève, comme partout ailleurs.

## 7. Suite

**L17 tranche 2** : proposition de réaffectation (l'interface qui propose un

---

# Tranche 2 — La proposition de réaffectation et le prévisionnel RH

**Migration** `417_l17_reaffectation_previsionnel.sql` · **Suite** `417_l17_reaffectation_previsionnel_tests.sql`
· **Date** 03/10/2026 · **Branche** `partie-5-integrite-chainages`

> Lot **L17** du plan §5 Phase F, troisième et quatrième exigence :
> « alerte sur les créneaux orphelins, **proposition de réaffectation** ;
> à l'inverse, **une charge de production planifiée apparaît dans le
> prévisionnel RH** ». La 416 (tranche 1) a livré le porteur, le constat,
> la garde et la capacité ajustée, et a dit dans sa preuve (§6, points 2
> et 3) que ces deux exigences restaient entières.

## 1. Le défaut, mesuré avant (base neuve, 280 migrations, 0 erreur)

| # | Mesure | Chiffre |
|---|---|---|
| D1 | Fonctions de proposition (« réaffect », « candidat », « remplac », « disponib ») | **0** |
| D2 | Fonctions de prévision / charge lisant `planning_slots` | **0** |
| D3 | Contrainte sur `employees.position` | **aucune** (texte libre) |

La seule fonction approchant D1 est `chain_lien_remplacer` — le **cycle du
lien** du socle (402), sans rapport. La 416 avait rendu le PROBLÈME
visible ; elle n'avait pas rendu la SOLUTION possible.

## 2. Ce que la 417 pose — deux lectures, aucun schéma

1. **`planning_slot_candidats(société, créneau)`** — qui peut prendre ce
   créneau, du plus disponible au moins disponible, **avec son motif**.
   Trois filtres : actif ; **absent ce jour-là → jamais proposé** ; même
   `position` que l'opérateur à remplacer.
2. **`employee_planned_load(société, salarié, du, au)`** — la charge de
   production planifiée en heures, **les créneaux bloqués par une absence
   en sont retirés**.

**Aucune écriture, aucune colonne, aucun déclencheur.** La réaffectation
elle-même est déjà possible depuis la 416 : il suffit d'écrire le nouvel
`employee_id`, et la garde rejoue. Cette migration rend la **décision**
faisable ; elle ne la prend pas — le plan confie la réaffectation au chef
d'atelier.

## 3. Trois décisions, et pourquoi

### 3.1 Sans qualification portée → AUCUN candidat (T04)

`position` étant un texte libre, la fonction **ne devine pas** : quand
l'opérateur à remplacer n'en porte pas, elle ne renvoie personne plutôt
que les 40 employés de la société. Une liste sans critère est une liste
sans information. Le test porte le **contre-exemple** : avec une position,
la proposition revient.

### 3.2 L'égalité de `position` est une égalité de texte

« Tourneur » et « tourneur » ne se rejoignent pas. On ne normalise pas :
normaliser ici supposerait une convention d'écriture que la base ne
possède pas. **Limite dite**, pas cachée.

### 3.3 Un créneau inexistant est REFUSÉ, pas rendu vide

Une liste vide se lit « personne n'est disponible » — ce qui est une
*autre* information que « ce créneau n'existe pas ».

## 4. Résultats

**Suite 417 — 8/8 verts** (base neuve `l17_t3`, 282 migrations, 0 erreur) :

| | Scénario | Chiffre mesuré |
|---|---|---|
| T01 | la proposition et son motif | 1 candidat, motif « Même qualification (Tourneur), 0 h déjà planifiées » |
| T02 | un candidat absent n'est **jamais** proposé | 2 tourneurs absents, 1 seul candidat (le présent) |
| T03 | le moins chargé d'abord | 2 candidats, **Nabil (0 h)** avant Amine (6 h) |
| T04 | sans qualification → aucun | sans position → **0** ; avec position → **2** |
| T05 | le prévisionnel retire les heures bloquées | Amine **4 h** ; Kader **2 h → 0 h** après son absence |
| T06 | l'isolation sur les **deux** sens | contexte B, candidats A **et** B répondent, charge de B lue depuis A = **0** |
| T07 | refus nommé | « Proposition de réaffectation refusée : le créneau … n'existe pas dans la société … » |
| T08 | surcoût mesuré | candidats **p95 0,398 ms** · prévisionnel **p95 0,255 ms** (budget 50 ms) |

**Non-régression, base neuve, ordre de la CI** — **282 migrations, 0 erreur**,
**21 suites vertes, 0 rouge** : 234 (8) · 236 (17) · W9 263/264/265/266
(13+11+10+34) · 400→413 (15, 12, 12, 11, 10, 12, 7, 8, 6, 8, 8) · 415 (8) ·
416 (8) · **417 (8)** · 450 (14).

**12 portes vertes**, dont `check_anon_grants` — qui a **vu rouge** (§5).
G5 : **105/105 suites** branchées.

**Aucune modification de schéma** → `db:types` sans écart, par
construction.

## 5. Une porte a vu rouge, et elle avait raison

`check_anon_grants` a refusé les deux lectures : une fonction créée l'est
avec EXECUTE pour `PUBLIC`, donc **un visiteur non connecté** pouvait
appeler les deux — et les deux traversent la RLS (`SECURITY DEFINER`),
l'une rendant la charge de production d'un salarié. Révocées à `PUBLIC`
et `anon`, accordées à `authenticated` + `service_role`.

## 6. Limites dites

1. **La qualification est un texte libre.** La proposition est aussi
   fiable que `employees.position` — le modèle n'a pas de référentiel de
   compétences. C'est la limite structurelle du lot, et elle est au cœur
   de T04 plutôt que dans une note.
2. **L'écran n'est pas encore branché.** Les deux lectures sont en base ;
   le panneau « réaffecter » de `PlanningPage.tsx` reste à écrire.
3. **Le jour regardé est `planned_start::date`** — hérité de la 416.
4. **Le prévisionnel est borné au créneau lu** : un créneau à cheval ne
   compte que sa fraction dans la période. C'est plus exact, et c'est la
   raison pour laquelle le calcul est un `CASE` et non une somme simple.

## 7. Suite

Le couple `production ↔ RH` est désormais fermé dans ses deux sens :
**porteur, constat, garde, capacité ajustée, proposition, prévisionnel**.
Restent **L18** (stock ↔ projets), **L19** (production ↔ trésorerie),
puis **L20** (régénération) et **L23-b/c**.

**Migration** `416_chain_l17_capacite_absence.sql` · **Suite** `416_chain_l17_capacite_absence_tests.sql`
· **Date** 02/10/2026 · **Branche** `partie-5-integrite-chainages`

> Lot **L17** du plan §5 Phase F — « Production ↔ RH (capacité ↔ absence) ».
> Dépendance : **L11** (`employee_absence_days`, 263) ✅. C'est le couple vide
> nommé en §A.4 du référentiel : « la capacité de production ne connaît pas
> l'absence : on planifie avec des salariés absents — **le cas d'usage
> fondateur de tout ce travail** ».

