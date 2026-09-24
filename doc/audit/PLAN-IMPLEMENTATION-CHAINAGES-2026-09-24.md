# Plan d'implémentation des chaînages transverses — 24 septembre 2026

> **Objet.** Mettre en place, de façon rigoureuse et mesurable, **tous** les chaînages transverses du
> produit : les 62 qui existent (à instrumenter et durcir), les 62 règles d'état manquantes
> (`R-001` → `R-062`), les 16 contrôles d'absence (`TRV-01` → `TRV-16`), les 9 familles de chaînages
> internes, les 5 couples de modules vides, et les mécanismes recommandés par les leaders du marché —
> **en prenant le meilleur de chacun d'eux**, là où leur méthode est supérieure à la nôtre, et en
> allant plus loin quand c'est possible.
>
> **Documents liés** : [Référentiel des chaînages transverses](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md)
> (inventaire mesuré, robustesse, comparaison au marché, innovation) et
> [Plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md) (les 69 défauts et
> les vagues W0 → W9, dont ce plan dépend).
>
> **Sources de comparaison citées en partie 1** : SAP (document flow), Oracle NetSuite (transaction
> links), Microsoft Dynamics 365 Business Central (document line tracking), ERPNext/Frappe (effet
> comptable, liens, rapport stock ↔ grand livre), Pennylane (lettrage génératif et réversibilité),
> Procore (coûts engagés et ordres de changement).

---

## 0. La règle de choix : comment on décide quel modèle adopter

Prendre « le meilleur de chacun » n'est pas une intention, c'est un **classement**. Chaque mécanisme
observé chez un éditeur est noté sur cinq critères pondérés, et c'est la note qui décide.

| Critère | Poids | Question posée |
|---|---:|---|
| **Protection de l'intégrité** | **×3** | le mécanisme empêche-t-il une divergence, une perte ou un doublon ? |
| **Reproductibilité chez nous** | **×3** | peut-on le reproduire avec PostgreSQL + RLS + PL/pgSQL + React, sans brique exotique ? |
| **Réutilisation transverse** | ×2 | sert-il à tous les modules, ou seulement à celui qui l'a inventé ? |
| **Coût d'exploitation** | ×2 | ajoute-t-il de la charge, des verrous, des états intermédiaires ? |
| **Preuve d'usage** | ×1 | est-ce documenté, utilisé en production, éprouvé par des millions d'écritures ? |

**Seuil de décision** : un mécanisme est adopté tel quel si **Protection ≥ 3** et **Reproductibilité ≥ 3** ;
il est adopté **modifié** si l'un des deux est inférieur ; il est **écarté** (partie 2) s'il dépend
d'une couche technique que nous refusons.

**Trois règles de conduite qui en découlent** :

1. **on copie le mécanisme, jamais l'implémentation** : SAP fait un document flow par module (SD, MM,
   PS…) parce que son architecture est modulaire et lourde ; nous faisons **un** registre de liens
   générique qui sert les onze modules, y compris paie, projets et caisse, ce que SAP ne fait pas dans
   un seul écran ;
2. **on copie ce qui protège, on améliore ce qui explique** : la contre-passation (SAP) est copiée
   telle quelle, parce qu'elle protège ; la présentation de la chaîne (SAP, BC) est améliorée, parce
   qu'elle explique ;
3. **toute adoption est prouvée par un test avant d'être considérée faite** (partie 4) : sans test,
   un mécanisme adopté n'est qu'une intention — c'est exactement le piège que le référentiel a mesuré
   (note moyenne **3,65/7** des 62 chaînages existants).

### 0.1 Le vocabulaire, une fois pour toutes

| Terme | Sens dans ce plan |
|---|---|
| **Chaînage** | l'effet automatique d'un changement d'état d'un document sur un ou plusieurs autres modules |
| **Maillon** | une fonction `chain_*` qui réalise un effet unique, idempotent, réversible et tracé |
| **Amont / aval** | le document déclencheur / le document ou l'écriture produite |
| **Extourne** | l'écriture ou le document qui défait un effet, **sans** supprimer l'original |
| **Régénération** | recalcul complet d'un effet après changement de paramètre ou d'imputation |
| **Invariant** | une égalité entre deux modules qui doit être vraie en permanence (INV-01 → INV-20) |
| **DoD** | la définition de « terminé » d'un maillon (partie 4, 12 points) |

---

## Partie 1 — La doctrine : 17 mécanismes retenus, le meilleur de chacun

Chaque ligne = un mécanisme observé chez un leader, **adopté** (tel quel ou modifié), avec ce que nous
copions, ce que nous améliorons et la brique technique qui le porte chez nous.

### 1.1 Les mécanismes de **protection** — adoptés tels quels, car ils empêchent la divergence

| # | Mécanisme | Meilleur modèle observé | Ce qu'on copie | Ce qu'on améliore | Brique chez nous |
|---|---|---|---|---|---|
| **M-01** | **Extourne = document** | SAP : les documents d'annulation font partie de la chaîne | l'annulation **crée** un effet inverse horodaté et tracé ; l'original n'est ni supprimé ni modifié | nous l'appliquons **partout** (paie, stock, caisse, projets), pas seulement en comptabilité ; refus explicite si l'extourne est impossible (période fermée, pièce lettrée) | `prevent_posted_line_modification` (déjà là) + `chain_*_reverse` |
| **M-02** | **Idempotence par clé** | tous (documents uniques, contraintes d'unicité) | rejouer un chaînage ne double rien | l'idempotence devient **structurelle** (index unique + `ON CONFLICT`) au lieu d'un `IF NOT EXISTS` recopié — mesuré : 9 chaînages sur 62 seulement | index unique `uq_document_links_effet` + gabarit §3.2 |
| **M-03** | **Réversibilité conditionnée au lien** | Pennylane : le dé-lettrage supprime l'écriture générée **si** le lien est intact, sinon il prévient | si le lien est rompu, on **refuse** au lieu de laisser une pièce orpheline | le contrôle devient générique : `chain_integrity_ok(amont, aval)` pour **tous** les chaînages | fonction `chain_integrity_ok` + message explicite |
| **M-04** | **Régénération plutôt que correction** | Pennylane : changer le compte d'une transaction lettrée **supprime et recrée** l'écriture | tout effet paramétrique (comptes, taux, diviseurs, seuils) se **régénère** ; on ne corrige jamais une ligne à la main | régénération **en cascade** : changer un taux ou un prix de revient régénère l'écriture **et** les couches **et** la facture liée, avec **historique** | `chain_regenerate(type, id)` + `chain_regeneration_log` |
| **M-05** | **Effet comptable déclaré** | ERPNext : table « quels documents touchent le grand livre, et comment » | chaque type de document **déclare** son effet, y compris « aucun » | la déclaration devient un **contrat testé** : la CI compare le réel à la déclaration et casse si divergence | `document_effects` + `check_effects_contract.sql` |
| **M-06** | **Rapport de cohérence entre modules** | ERPNext : *Stock and Account Balance Comparison* | un rapport qui met deux modules face à face et **chiffre l'écart** | de 1 rapport à **20 invariants**, vérifiés chaque nuit, avec **indice publié** par société et par module | `audit_chains()` + `chain_invariants` + `pg_cron` |
| **M-07** | **Coûts engagés par document** | Procore : budgété / engagé / réel, l'engagement naît du contrat ou de la commande | l'engagement se crée **à la confirmation**, se consomme à la réception, se **libère** à l'annulation et à la facturation | l'engagement devient **transverse** : budget, trésorerie prévisionnelle **et** marge projet — trois modules, un objet | `chain_commitment_*` + `budget_commitments` (à brancher) |
| **M-08** | **Gel de période avec chemin de sortie** | Pennylane : régularisation datée J+1 ; ERPNext : restrictions de période | on refuse d'écrire dans le passé **et** on propose l'écriture de régularisation | la proposition est **guidée** : calculée, chiffrée, approuvée ou refusée par l'utilisateur (I-09) | `chain_period_adjust` + `period_adjustments` |
| **M-09** | **Traçabilité par ligne** | Dynamics 365 BC : *Document Line Tracking*, lignes archivées incluses | les liens portent **la ligne**, pas seulement l'en-tête : indispensable en livraison et réception partielles | nous l'étendons aux flux de temps et de paie (ligne de bulletin ↔ pointage ou absence), ce qu'aucun éditeur cité ne fait génériquement | `document_links.amont_ligne_id`, `aval_ligne_id` |

### 1.2 Les mécanismes d'**explication** — adoptés, puis dépassés

| # | Mécanisme | Meilleur modèle observé | Ce qu'on copie | Ce qu'on améliore |
|---|---|---|---|---|
| **M-10** | **Chaîne navigable amont / aval / référence** | SAP (*document flow*) ; BC (Document Line Tracking) | la frise : ce qui a produit le document, ce qu'il a produit, ce qui le référence | **bidirectionnel et générique** : une seule vue sert les 11 modules, paie et projets compris ; SAP a un document flow **par module** |
| **M-11** | **Liens typés** | NetSuite : `Created From`, `Orders and Sales`, liens d'affectation | chaque lien a un **type** : `created_from`, `delivered_by`, `invoiced_by`, `paid_by`, `reversed_by`, `adjusted_by`, `generated_entry` | un type par réalité, **contraint en base** : fin des colonnes `reference_*` divergentes d'une table à l'autre |
| **M-12** | **Consultation des liens aval** | ERPNext : outil « Links » | depuis un document, la liste de tout ce qu'il a produit | ajout de l'**analyse d'impact** : « si j'annule ce document, voici ce qui sera extourné » — aucun éditeur cité ne le propose **avant** l'action |
| **M-13** | **Événements lisibles** | ERPNext (notifications), SAP (workflows) | un journal d'activité par société, lisible, avec l'auteur | un **registre d'événements unique** (`domain_events`) alimentant notifications, webhooks, audit **et** automatisations du client (I-06) |
| **M-14** | **Règles paramétrables** | SAP / NetSuite : workflows, seuils d'approbation, délégations | seuils, validations à plusieurs niveaux, délégation d'absence | un **moteur de règles transverses** écrit par le client (« absence bloquante → refuser frais et heures supplémentaires ») et **testable depuis l'écran** (I-07) |

### 1.3 Ce que nous ajoutons — et que la documentation consultée ne décrit nulle part

| # | Notre ajout | Pourquoi c'est un avantage commercial |
|---|---|---|
| **M-15** | **L'analyse d'impact avant action** : ce que la validation **va** produire, avant de l'exécuter | supprime la peur de valider ; c'est ce que réclame tout utilisateur venu d'un ERP lourd |
| **M-16** | **Le banc d'épreuve publié** : les 8 épreuves D1→D8 rejouées par chaînage, résultat **visible par le client** | transforme « nous testons » en **preuve opposable**, et se rejoue sur la base du client |
| **M-17** | **L'indice de cohérence** : 20 invariants transversaux, score publié et historisé, écarts chiffrés | personne ne publie un score de cohérence vérifiable : c'est la promesse « vos chiffres sont justes », démontrée |

---

## Partie 2 — Ce que nous ne copions **pas** (et pourquoi)

Un plan d'adoption crédible dit aussi ce qu'il refuse. Ces quatre mécanismes sont écartés, avec leur
raison — ils sont documentés chez des leaders, mais incompatibles avec nos contraintes ou inférieurs
à ce que nous pouvons faire.

| Mécanisme écarté | Chez qui | Pourquoi nous le refusons |
|---|---|---|
| **Un document flow par module** (couplage SD ↔ MM ↔ FI propre à chaque domaine) | SAP | c'est la source de la lourdeur de SAP : chaque module connaît les autres. Nous avons une base commune et une RLS commune : **un registre unique** est plus simple, plus rapide et couvre la paie et les projets que SAP laisse hors du document flow |
| **Le raccourci qui perd les contrôles** (facture directe sans commande, livraison directe sans commande) | ERPNext (documenté comme un choix assumé) | ERPNext l'autorise et l'explique ; chez nous le contrôle de pourcentage facturé/livré est **la seule garantie** que la commande est soldée. Nous l'autorisons **avec avertissement et lien obligatoire** (jamais sans référence) |
| **Le lettrage manuel par défaut** | plusieurs éditeurs (dont Pennylane pour les cas SEPA non repris) | un lettrage manuel de masse est une dette de qualité. Nous gardons le manuel comme **exception**, avec suggestion automatique par score (déjà amorcé : `auto_reconcile_by_score`) et traçabilité du refus d'automatisation |
| **Le paramétrage infini par société** (champs de personnalisation libres partout) | SAP, Dynamics | c'est ce qui rend ces ERP impossibles à mettre à jour. Nous limitons la personnalisation au **moteur de règles (M-14)** et aux **contrats d'effet (M-05)**, tous deux testés |

---

## Partie 3 — L'architecture d'implémentation : le socle

Le socle est **le préalable de tous les lots**. Il est écrit une fois, il porte les 62 chaînages
existants, les 62 règles, les 16 contrôles d'absence et les 12 innovations.

### 3.1 Les quatre tables du socle (DDL de référence)

```sql
-- 1) QUI A PRODUIT QUOI — le registre de chaîne (M-10, M-11, M-12, D6)
CREATE TABLE document_links (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  amont_type      text NOT NULL,          -- 'sales_order', 'delivery', 'pay_run', 'leave_request', 'pos_ticket'…
  amont_id        uuid NOT NULL,
  amont_ligne_id  uuid,                   -- M-09 : granularité ligne
  aval_type       text NOT NULL,          -- 'invoice', 'journal_entry', 'stock_movement', 'pay_slip'…
  aval_id         uuid NOT NULL,
  aval_ligne_id   uuid,
  link_type       text NOT NULL,          -- 'created_from' | 'delivered_by' | 'invoiced_by' | 'paid_by' | 'reversed_by' | 'adjusted_by' | 'generated_entry' | 'consumed_by_absence'
  effet           text NOT NULL,          -- l'identifiant du maillon qui a créé le lien : 'sale.delivery.stock_out'
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,   -- quantités, montants, pour l'analyse d'impact
  created_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_document_links_effet
  ON document_links (tenant_id, amont_type, amont_id, effet, COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX ix_document_links_amont ON document_links (tenant_id, amont_type, amont_id);
CREATE INDEX ix_document_links_aval  ON document_links (tenant_id, aval_type, aval_id);
CREATE INDEX ix_document_links_type  ON document_links (tenant_id, link_type, created_at DESC);

-- 2) CE QUE CE DOCUMENT DOIT PRODUIRE — le contrat d'effet (M-05, I-02)
CREATE TABLE document_effects (
  tenant_id       uuid,                   -- NULL = contrat standard livré avec le produit
  document_type   text NOT NULL,
  evenement       text NOT NULL,          -- 'validated' | 'confirmed' | 'received' | 'cancelled' | 'approved' | 'paid'
  effet           text NOT NULL,          -- même vocabulaire que document_links.effet
  ecrit_comptable boolean NOT NULL DEFAULT false,
  journal_code    text,
  touche_stock    boolean NOT NULL DEFAULT false,
  touche_paie     boolean NOT NULL DEFAULT false,
  reversible      boolean NOT NULL DEFAULT true,
  obligatoire     boolean NOT NULL DEFAULT false,   -- le chaînage est-il obligatoire (pas de raccourci) ?
  note            text,
  PRIMARY KEY (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), document_type, evenement, effet)
);

-- 3) CE QUI S'EST PASSÉ — le registre d'événements (M-13, I-06)
CREATE TABLE domain_events (
  id           bigserial PRIMARY KEY,
  tenant_id    uuid NOT NULL,
  event_name   text NOT NULL,             -- 'invoice.cancelled', 'absence.blocking_created', 'chain.regenerated'
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_id     uuid,
  created_at   timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);       -- partition mensuelle, rétention 24 mois

-- 4) L'HISTORIQUE DES RÉGÉNÉRATIONS (M-04)
CREATE TABLE chain_regeneration_log (
  id           bigserial PRIMARY KEY,
  tenant_id    uuid NOT NULL,
  effet        text NOT NULL,
  amont_type   text NOT NULL,
  amont_id     uuid NOT NULL,
  cause        text NOT NULL,             -- 'taux changé', 'prix de revient corrigé', 'compte remappé'
  avant        jsonb, apres jsonb,
  created_by   uuid,
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

**Pourquoi ces quatre tables et pas trois ou cinq** : la première dit *qui a produit quoi* (navigation,
analyse d'impact, retour arrière), la deuxième dit *ce qui doit se produire* (contrat et contrôle CI),
la troisième dit *ce qui s'est passé* (événements et automatisations), la quatrième dit *ce qui a été
recalculé* (régénération et audit). Aucune ne contient de logique métier : c'est ce qui les rend
transverses.



### 3.2 Les six fonctions utilitaires du socle (écrites une fois, utilisées 62 fois)

```sql
-- a) Déclarer un lien (idempotent) : LA fonction que tous les maillons appellent
link_documents(p_tenant, p_amont_type, p_amont_id, p_aval_type, p_aval_id, p_effet, p_link_type,
               p_payload jsonb DEFAULT '{}', p_amont_ligne uuid DEFAULT NULL, p_aval_ligne uuid DEFAULT NULL)

-- b) Le lien existe-t-il déjà ? (idempotence M-02, appelée en début de maillon)
chain_deja_fait(p_tenant, p_amont_type, p_amont_id, p_effet, p_amont_ligne uuid DEFAULT NULL) → boolean

-- c) Le lien amont ↔ aval est-il intact ? (M-03 : condition de réversibilité)
chain_integrity_ok(p_tenant, p_amont_type, p_amont_id, p_aval_type, p_aval_id) → boolean

-- d) Émettre un événement lisible (M-13)
emit_domain_event(p_tenant, p_event_name, p_aggregate_type, p_aggregate_id, p_payload jsonb, p_actor uuid)

-- e) Le contrat autorise-t-il cet effet ? (M-05 : lu avant chaque maillon)
chain_autorise(p_tenant, p_document_type, p_evenement, p_effet) → boolean

-- f) Régénérer un effet de façon traçable (M-04)
chain_regenerate(p_tenant, p_effet, p_amont_type, p_amont_id, p_cause text) → uuid
```

**Règle absolue** : aucun maillon n'écrit dans une table métier sans passer par `a)`, et aucun maillon
ne commence sans appeler `b)`. C'est cette discipline — et non la bonne volonté — qui fait passer
l'idempotence mesurée de **9/62 à 62/62**.

### 3.3 Performance : les budgets à ne pas dépasser (l'« ultra-performance » exigée)

Un chaînage lent sera désactivé par ses utilisateurs. Les budgets sont donc **chiffrés, mesurés et
publiés**.

| Situation | Budget (p95) | Mesure |
|---|---:|---|
| Un maillon simple (une écriture, un lien) | **≤ 50 ms** | trace d'exécution (§3.4) |
| Un document commercial complet (commande → réception → facture → écriture) | **≤ 300 ms** | idem |
| Une paie de 100 bulletins (chaîne complète) | **≤ 5 s** | idem |
| Une clôture de caisse avec sortie de stock | **≤ 1 s** | idem |
| `audit_chains()` sur 100 000 écritures (20 invariants) | **≤ 60 s**, en tâche de fond | `pg_cron` nocturne |
| Ouverture de la « Vue Chaîne » (10 niveaux) | **≤ 200 ms** | interface |

**Moyens techniques imposés** — sans eux les budgets ne tiennent pas :

1. **Zéro requête N+1** : tout maillon qui traite des lignes le fait en **un seul `INSERT … SELECT`**.
   C'est le défaut mesuré `BUD-04` (deux requêtes par budget) et `PROJ-02` (deux calculs d'avancement) ;
2. **Index obligatoires** sur les quatre tables du socle (§3.1) et sur toute colonne de jointure d'un
   maillon : un maillon qui filtre sur une colonne non indexée est **refusé en revue** ;
3. **`domain_events` partitionné par mois** : un million de lignes par an et par société ne doit pas
   ralentir l'écriture ; rétention 24 mois puis archivage ;
4. **Verrous ciblés uniquement** : `pg_advisory_xact_lock(hashtext(tenant_id || terminal_id))` pour
   toute numérotation (déjà nécessaire en caisse, `POS-03`) — jamais de verrou de table ;
5. **Agrégats sans verrou** : `ON CONFLICT DO UPDATE` (déjà corrigé en 240 pour `stock_quantities`) ;
6. **Vue récursive bornée** : la « Vue Chaîne » limite la profondeur (10 niveaux) et le nombre de
   nœuds (500), puis pagine ;
7. **Indice de cohérence incrémental** : les 20 invariants sont recalculés par société et conservés
   datés dans `chain_invariants`, jamais recalculés à l'affichage ;
8. **Contrat mis en cache de transaction** : `document_effects` est chargée une fois par transaction
   (`SET LOCAL`), pas une fois par ligne.

### 3.4 Observabilité : chaque maillon laisse une trace mesurable

Un chaînage qui ne se mesure pas ne s'améliore pas. Chaque exécution de maillon écrit une ligne de
trace (table `chain_traces`, partitionnée comme `domain_events`) :

| Colonne | Usage |
|---|---|
| `effet`, `amont_type`, `amont_id` | quel maillon, sur quel document |
| `duree_ms` | comparaison au budget §3.3 ; alerte si p95 > budget |
| `lignes_ecrites` | détection des maillons « bavards » (une écriture par ligne au lieu d'un `INSERT … SELECT`) |
| `verrous_attendus_ms` | détection des contentions (deux encaissements simultanés, `POS-03`) |
| `resultat` | `applique` / `ignore` (contrat non autorisé) / `refuse` (message) / `regeneré` |
| `message` | le texte exact vu par l'utilisateur quand la chaîne refuse |

**Trois tableaux de bord internes** en découlent : **performance** (p50/p95/p99 par maillon),
**refus** (les messages les plus fréquents : c'est là que se cachent les règles mal comprises),
**regénérations** (fréquence et cause : c'est là que se cachent les paramétrages instables).

### 3.5 Sécurité des nouvelles tables (le réflexe du dépôt, appliqué d'emblée)

| Règle | Application |
|---|---|
| RLS activée et **forcée** | les 5 nouvelles tables (`document_links`, `document_effects`, `domain_events`, `chain_regeneration_log`, `chain_traces`) |
| Une politique par commande, **jamais deux** | le doublon de politiques a annulé 38 gardes de droits (`ISO-03`) : la leçon est appliquée dès la création |
| Lecture seule pour le client | `document_links` et `domain_events` sont **écrits par les chaînages** (fonctions `SECURITY DEFINER` filtrées par société) et **lus** par l'utilisateur de la société : aucun `INSERT` direct |
| Aucune clé étrangère inter-société | `(tenant_id, amont_id)` et `(tenant_id, aval_id)` vérifiés, conformément à `ISO-02` |
| Rétention et données personnelles | `domain_events.payload` ne contient **aucune donnée personnelle** non nécessaire (montants, identifiants) : la purge RGPD ne casse pas l'audit |

### 3.6 Migration, rétro-instrumentation et mise en service sans rupture

| Étape | Méthode | Garde-fou |
|---|---|---|
| **Création du socle** | migration numérotée (première du programme), réversible | test de structure (grille `BT` du plan correctif) |
| **Rétro-instrumentation des 62 chaînages** | on **n'ajoute** que `link_documents(...)` et `emit_domain_event(...)` dans les maillons existants, **sans changer leur logique** | chaque chaînage instrumenté repasse ses suites existantes (aucune régression) |
| **Rattrapage de l'historique** | script idempotent qui reconstruit les liens **déductibles** (commande → livraison → facture → écriture) pour les documents existants | le script est **rejouable** et s'arrête sur incohérence au lieu de deviner ; il rapporte ce qu'il n'a pas pu reconstituer |
| **Mise en service progressive** | un drapeau par société (`chain_enforcement`) : `observe` → `avertit` → `refuse` | en `observe`, les règles signalent sans bloquer ; on mesure le taux de refus avant de bloquer |
| **Compatibilité** | aucune colonne supprimée, aucune contrainte ajoutée sans validation sur copie de production | le dépôt a l'habitude : `pg_dump` de prod rejoué avant tout changement de schéma |
| **Retour arrière** | chaque lot fournit sa migration inverse ; la désactivation du drapeau suffit à revenir au comportement d'avant | testé sur copie avant mise en production |

---

## Partie 4 — Le standard : ce que « terminé » veut dire, et les portes qui le garantissent

C'est ici que se décide la qualité. Le plan correctif a mesuré ce qui arrive sans standard : **62
chaînages, note moyenne 3,65/7, idempotence 15 %, trace 11 %**. Le standard ci-dessous existe pour que
cette moyenne ne puisse pas se reproduire.

### 4.1 La définition de « terminé » d'un chaînage — 12 points, sans exception

| # | Point | Preuve exigée |
|---|---|---|
| 1 | **Contrat déclaré** dans `document_effects` (même si l'effet est « aucun ») | ligne en base, revue |
| 2 | **Un maillon = une fonction** `chain_<domaine>_<effet>`, écrite dans le gabarit §3.2 | revue de code + `check_plpgsql` |
| 3 | **Idempotence structurelle** : la clé unique est respectée, `chain_deja_fait` est appelée en entrée | test T-2 (rejeu : une seule ligne) |
| 4 | **Réversibilité** : `chain_*_reverse` existe, **ou** la non-réversibilité est déclarée avec son motif et son message | test T-3 |
| 5 | **Traçabilité** : `link_documents(...)` écrit le lien (avec la ligne si applicable) **et** `emit_domain_event(...)` émet l'événement | test D-6 (retour arrière depuis l'aval) |
| 6 | **Refus explicite** : tout refus lève un message nommant le document, la date, la règle et le module | test de refus (assertion sur le texte) |
| 7 | **Isolation** : le `tenant_id` vient de la source, jamais d'un `current_tenant_id()` implicite | test D-8 |
| 8 | **Performance mesurée** : p95 consigné dans `chain_traces`, dans le budget §3.3 ; index en place | relevé daté |
| 9 | **Tests T-1 → T-4** (effet produit, rejeu, annulation, isolation) | fichier `NNN_*_tests.sql` branché en CI |
| 10 | **Épreuves D-1 → D-8** (les huit de robustesse) vertes | rapport du banc d'épreuve |
| 11 | **Traçabilité documentaire** : la règle `R-xxx` passe à « fait », la ligne de suivi est mise à jour, la page « Robustesse » s'actualise | tableau de suivi daté |
| 12 | **Aucune régression** : les 12 points de la liste blanche (N1→N12) et les suites du module restent verts | CI |

> **Un maillon qui échoue à un seul de ces douze points n'est pas terminé** — il est en cours, et il
> est interdit de le mettre en service, même derrière un drapeau.

### 4.2 Les six portes automatiques (CI), et ce qu'elles empêchent de réintroduire

| Porte | Contrôle | Défaut que la porte rend impossible |
|---|---|---|
| **G1 — structure** | la grille `BT` du plan correctif : RLS active et forcée, **une politique par commande**, index de société, clés composites | `ISO-02`, `ISO-03`, `ISO-04` (réintroduction) |
| **G2 — contrat** | `check_effects_contract.sql` : pour chaque type de document et chaque événement déclaré, un test exécute le document et **compare le réel à la déclaration** | `M-05` (un effet caché ou absent), défauts `S-01→S-04` |
| **G3 — colonnes et erreurs** | les deux scanners du plan correctif (colonnes écrites, écritures non vérifiées), étendus à `supabase/functions/` | les 21 colonnes fantômes et 29 écritures muettes (`EF-04`, `EF-05`, `EF-07`, `EF-08`) |
| **G4 — garde de société étendue** | toute fonction `SECURITY DEFINER` qui écrit dans une table portant `tenant_id` doit mentionner `tenant_id` dans son corps (au-delà des RPC exposées) | `ISO-01` (les 13 déclencheurs qui écrivent chez le voisin) |
| **G5 — tests et registre** | les suites `*_tests.sql` branchées une par une ; registre `expected_failures` par **couple (fichier, test)** ; un test vu rouge puis vert doit sortir du registre | `AUD-X01` (blanchiment par identifiant réutilisé) et le pourrissement des specs |
| **G6 — performance** | un banc qui exécute 1 000 chaînages sur une base neuve et **échoue si un p95 dépasse le budget §3.3** | les chaînages « qui marchent en démo » et bloquent en production |

**Pourquoi six portes et pas une** : chacune couvre un mode d'échec **différent** — structure, contrat,
code fantôme, isolation, preuve, performance. Le dépôt a déjà payé pour l'apprendre : le contrôle
`check_status_writes` a d'abord été **faussement vert** (quantificateur gourmand, fixture mal placée).
La leçon est intégrée : **tout contrôle de texte doit avoir une fixture où l'erreur est en dernière
position**.

### 4.3 La revue de code d'un chaînage — six questions, dans cet ordre

1. **Le contrat existe-t-il, et est-il vrai ?** (déclaration + test de contrat)
2. **Que se passe-t-il si on rejoue ?** (idempotence structurelle, pas un `IF NOT EXISTS` recopié)
3. **Que se passe-t-il si on annule ?** (extourne tracée, ou déclaration motivée)
4. **Que se passe-t-il si la société voisine est active ?** (tenant de la source, pas de session)
5. **Combien de requêtes pour N lignes ?** (un seul `INSERT … SELECT`, aucun N+1)
6. **Que lit l'utilisateur quand ça refuse ?** (message nommant document, date, règle, module)

---

## Partie 5 — Le plan : 25 lots, 6 phases

Chaque lot est autonome : il laisse le dépôt dans un état meilleur, vérifié, et **sans rupture de
service**. Les charges sont des estimations en jours de développement (hors recette et déploiement).

### Phase A — Socle : les fondations (12 j)

| Lot | Contenu précis | Charge | Dépend de | Livrable | Preuve |
|---|---|---:|---|---|---|
| **L0** | migration de socle : les 5 tables (§3.1) + index + RLS forcée + une politique par commande ; les 6 fonctions utilitaires (§3.2) ; le gabarit de maillon ; le drapeau `chain_enforcement` par société (`observe`/`avertit`/`refuse`) ; `chain_traces` | **4 j** | vague **W0** du plan correctif | le socle est en place et vide | grille `BT` + `check_policy_duplicates` verts |
| **L1** | **rétro-instrumentation des 62 chaînages** : ajout de `link_documents` et `emit_domain_event` dans chaque maillon **sans changer sa logique** ; plus le script de rattrapage de l'historique `document_links` (rejouable, s'arrête sur incohérence) | **5 j** | L0 | la chaîne est **visible** pour les documents existants | 62 maillons tracés + suites existantes vertes |
| **L2** | les **6 portes CI** (§4.2), dont `check_effects_contract.sql` et le banc de performance G6 | **3 j** | L0 | la qualité devient automatique | une régression volontaire casse la CI |

### Phase B — Prouver : robustesse et cohérence (13 j)

| Lot | Contenu précis | Charge | Dépend de | Livrable | Preuve |
|---|---|---:|---|---|---|
| **L3** | **banc d'épreuve D1→D8** : un moteur de test paramétré par chaînage (rejeu, concurrence, panne partielle, annulation, réouverture, retour arrière, volume, isolation) et son rapport par maillon | **5 j** | L1, L2 | chaque chaînage a une **note de robustesse prouvée** (et non plus statique) | les 8 épreuves sur 62 maillons |
| **L4** | les **20 invariants transversaux** (INV-01→INV-20) + `audit_chains(tenant)` + `chain_invariants` + job `pg_cron` nocturne + alerte en cas de dégradation | **5 j** | L0 | **l'indice de cohérence** existe | relevé daté par société et par module |
| **L5** | les pages **« Robustesse »** (résultat des 8 épreuves) et **« Cohérence »** (score, écarts, historique) | **3 j** | L3, L4 | le client **voit** la qualité | capture + test e2e |

**Pourquoi ces deux phases avant tout le reste** : elles transforment un diagnostic en **preuve
opposable**, et elles sont la condition pour que les 40 jours de règles de la phase D ne reproduisent
pas les 3,65/7 mesurés aujourd'hui.

### Phase C — Voir : les deux innovations qui se vendent en démonstration (9 j)

| Lot | Contenu précis | Charge | Dépend de | Livrable | Preuve |
|---|---|---:|---|---|---|
| **L6** | **Vue Chaîne (I-01, M-10, M-11, M-12)** : vue récursive bornée amont/aval, composant d'interface unique, intégration aux écrans principaux (commande, livraison, facture, réception, paie, bulletin, ticket, OF, note de frais, projet) ; **analyse d'impact** (« si j'annule, voici ce qui sera extourné ») sur les documents réversibles | **5 j** | L1, L5 | la question « qu'est-ce que ce document a produit ? » a une réponse en un clic | test e2e + les 10 écrans |
| **L7** | **Contrat d'effet (I-02, M-05)** : remplissage de `document_effects` pour **tous** les types de documents ; onglet « Effet comptable » ; `check_effects_contract.sql` en porte G2 | **4 j** | L0, L2 | aucun effet n'est plus caché dans un déclencheur | G2 vert + revue métier |

### Phase D — Réparer : les 62 règles, domaine par domaine (40 j)

Pour chaque lot : les règles sont écrites dans le gabarit §3.2, testées selon §4.1 (T-1→T-4 et
D-1→D-8), et leur ligne de suivi passe à « fait ».

| Lot | Domaine | Règles couvertes | Charge | Dépend de | Effet commercial |
|---|---|---|---:|---|---|
| **L8** | **Ventes** | `R-001` → `R-009`, `R-019` → `R-021` | **6 j** | L6, L7, vague **W3** | devis → commande → livraison → facture → avoir, enfin soldé (pourcentages livré/facturé) |
| **L9** | **Achats** | `R-010` → `R-018` | **5 j** | L6, L7, **W3** | la réception entre en stock, à son coût, et l'engagement se libère |
| **L10** | **Trésorerie** | `R-022` → `R-024`, `R-048` → `R-051` | **4 j** | L6, L7, **W6** | lettrage, délettrage, virements internes, rejets bancaires traités |
| **L11** | **Paie et RH** | `R-025` → `R-039` + fusion des `TRV-01` → `TRV-16` | **8 j** | L6, **W1**, **W4**, **W9** | l'absence, le contrat, la paie et la DSN deviennent une seule chaîne |
| **L12** | **Projets** | `R-040` → `R-042` | **3 j** | L6, **W8** | clôture de projet : encours, facturation finale, retenue de garantie |
| **L13** | **Production et stock** | `R-043` → `R-047` | **5 j** | L6, **W3**, **W8** | OF annulé/repris/rebuts, transferts entre dépôts, en-cours de production |
| **L14** | **Conformité et déclaratif** | `R-052` → `R-056`, `R-062` | **4 j** | L6, L7, **W6** | TVA, DSN, déclarations sociales : états vis-à-vis de l'administration |
| **L15** | **Budgets, engagements, relances** | `R-057` → `R-061` + `INV-05` | **3 j** | L6, **W7** | engagements libérés, relance envoyée **une fois** |
| **L16** | **Chaînages internes** (§B.3) | les 9 familles : comptabilité (lettrage↔dépréciation↔clôture), stock (besoin↔proposition↔commande), projet (budget↔temps↔coût↔marge), RH (contrat↔absence↔cumuls), caisse (déjà bon), etc. | **2 j** | L8 → L15 | plus de tronçon manquant **à l'intérieur** d'un module |

**Un principe de conduite pour cette phase** : dès qu'une règle révèle un défaut **structurel** (colonne
absente, clé étrangère en cascade, contrainte de statut manquante), **on s'arrête et on corrige la
structure d'abord** — c'est la leçon des `S-01→S-04` (une colonne dépôt absente a rendu inutile tout
un chaînage).

### Phase E — Étendre : les cinq couples de modules vides (12 j)

Ces chaînages n'existent **chez personne** sous cette forme : ils relient des domaines que les
éditeurs séparent (paie/comptabilité d'un côté, production/projets de l'autre).

| Lot | Chaînage à créer | Ce qu'il produit | Charge | Dépend de |
|---|---|---|---:|---|
| **L17** | **Production ↔ RH** (capacité ↔ absence) | le planning de production connaît les absences : capacité ajustée, alerte sur les créneaux orphelins, proposition de réaffectation ; à l'inverse, une charge de production planifiée apparaît dans le prévisionnel RH | **4 j** | L11 (`employee_absence_days`) |
| **L18** | **Stock ↔ Projets** et **Production ↔ Projets** | sortie de stock sur projet (consommation de chantier, avec imputation analytique), **fabrication à la commande** (un projet commande un OF), réintégration du coût matière dans la marge projet | **5 j** | L12, L13 |
| **L19** | **Production ↔ Trésorerie** et **Reporting ↔ Tous** | l'engagement de production alimente le prévisionnel de trésorerie ; le reporting lit des **définitions uniques** de marge, de CA et de DSO au lieu de recalculer chacun la sienne (`BUD-01`, `PROJ-02` → I-08) | **3 j** | L15 |

### Phase F — Innover : ce que personne n'a (30 j)

| Lot | Innovation | Ce qu'elle apporte | Charge | Dépend de |
|---|---|---|---:|---|
| **L20** | **Régénération généralisée (M-04)** + historique | changer un taux, un compte, un prix de revient ou un diviseur **régénère** l'écriture, les couches et les pièces liées, avec historique et possibilité de revenir à la version précédente | **5 j** | L7, L8, L13 |
| **L21** | **Dérivés du lettrage (M-03)** : TVA sur encaissements, réversibilité conditionnée au lien | lettrer un 411 génère l'écriture de TVA sur encaissements ; dé-lettrer la supprime ; si le lien est rompu, **refus explicite** (à la manière de Pennylane, mais généralisé au stock et à la paie) | **5 j** | L10, L14, L20 |
| **L22** | **Moteur de règles client (I-07)** + **simulateur d'impact (I-04)** | le client écrit ses règles transverses et les teste ; avant chaque validation, il **voit** ce qui va se produire (écritures, stock, paie, refus éventuels) | **8 j** | L1, L5, L11 |
| **L23** | **Événements, automatisations, webhooks unifiés (I-06)** | journal unique + automatisations (« devis accepté → créer la commande et notifier ») + webhooks branchés sur les mêmes événements | **4 j** | L0, L2 |
| **L24** | **Explicabilité (I-08)**, **régularisation guidée (I-09)**, **localisation par chaînes (I-11)**, **assistant (I-12)** | « pourquoi ce chiffre ? » sur tout montant ; proposition d'écriture J+1 sur période close ; chaînes paramétrées par pays (TVA, fériés, conventions, monnaie) ; assistant qui répond **avec preuve** (chaîne + écritures) | **8 j** | L4, L6, L21, L23 |

---

## Partie 6 — Le suivi : un tableau, un chiffre par lot

### 6.1 Le tableau de bord d'exécution

Chaque lot a **un indicateur qui bouge** : c'est ce qui prouve qu'il est fait, et pas seulement codé.

| Lot | Indicateur qui bouge | État |
|---|---|---|
| L0 | tables de socle en place, grille `BT` verte | ⬜ |
| L1 | chaînages existants tracés (**0 / 62** → 62 / 62) | ⬜ |
| L2 | portes CI G1 → G6 actives | ⬜ |
| L3 | chaînages robustes prouvés (**0 / 62** → 62 / 62) | ⬜ |
| L4 | indice de cohérence publié (**≈ 5 / 20** → 20 / 20) | ⬜ |
| L5 | pages « Robustesse » et « Cohérence » en service | ⬜ |
| L6 | Vue Chaîne sur 10 écrans | ⬜ |
| L7 | contrats d'effet déclarés (**0 %** → 100 %) | ⬜ |
| L8 → L15 | règles d'état couvertes (**0 / 62** → 62 / 62) | ⬜ |
| L16 | chaînages internes manquants (**9 familles** → 0) | ⬜ |
| L17 → L19 | couples de modules vides (**12 → 0**) | ⬜ |
| L20 → L24 | innovations livrées (I-01 → I-12) | ⬜ |

### 6.2 Ce qu'on mesure **chaque semaine** (le rendez-vous de pilotage)

| Mesure | Source | Seuil d'alerte |
|---|---|---|
| Règles passées à « fait » cette semaine | tableau de suivi | < 2 par semaine pendant la phase D |
| p95 des chaînages, par maillon | `chain_traces` | > budget §3.3 |
| Taux de refus par règle | `chain_traces` (résultat = `refuse`) | > 5 % des tentatives : règle mal comprise ou trop stricte |
| Régénérations par cause | `chain_regeneration_log` | une même cause > 20 fois : paramétrage instable |
| Invariants en écart | `chain_invariants` | un invariant qui **se dégrade** d'une nuit à l'autre |
| Épreuves D1 → D8 en échec | banc d'épreuve | tout échec bloque la mise en service du lot |

---

## Partie 7 — Charge, ordre, risques et lancement

### 7.1 La charge globale, et sa place à côté du plan correctif

| Programme | Charge | Rôle |
|---|---:|---|
| **Plan correctif** (vagues W0 → W9) | **≈ 38 j** | **réparer** ce qui est cassé (69 défauts, dont 32 bloquants) |
| **Plan d'implémentation des chaînages** (lots L0 → L24) | **≈ 116 j** | **construire** ce qui manque : 62 règles d'état, 16 contrôles d'absence, 9 familles internes, 5 couples de modules, 17 mécanismes adoptés, 12 innovations |
| **Total** | **≈ 150 j** | un ERP complet **et** vérifiable |

**Les deux programmes se recouvrent volontairement sur quatre vagues** — `W0` (registre et CI), `W1`
(isolation), `W4` (paie, un seul moteur), `W9` (absence) — parce que ces quatre-là sont le **prérequis
technique** des règles `R-033` → `R-039` et de la chaîne 12. Il ne faut donc pas les compter deux fois :
le total réel « correctifs + chaînages » est de **≈ 150 j**, dont **26 j** (l'ensemble L0 → L5) qui
conditionnent tout le reste.

### 7.2 L'ordre imposé : le chemin critique

```
W0 (1 j) ─▶ L0 (4 j) ─▶ L1 (5 j) ─▶ L3 (5 j) ─▶ L5 (3 j) ─▶ L6 (5 j) ─▶ Phase D (40 j)
            socle       trace       preuve      écrans      chaîne      les 62 règles
               │
               ├─▶ L2 (3 j) portes CI
               └─▶ L4 (5 j) indice de cohérence

W1 (3 j) isolation ─┐
W4 (4 j) paie ──────┼─▶ L11 (8 j) paie et RH   (obligatoire avant la phase E)
W9 (4 j) absence ───┘
```

**Ce qui peut être mené en parallèle** : `L2` avec `L1` ; `L4` avec `L3` ; `L8` (ventes) avec `L9`
(achats) si deux développeurs travaillent sur des tables disjointes ; `L23` (événements) avec la phase D
(il ne touche que le socle) ; `L14` (conformité) avec `L12` (projets).

**Ce qui ne peut pas être parallélisé** : `L0` → `L1` (une seule vérité à poser d'abord) ; `L3` après
`L1` (on ne note que ce qui est tracé) ; `L11` après `W4` et `W9` (sinon on chaîne une paie qui a
encore trois moteurs, et une absence qui n'existe nulle part).

### 7.3 Les six risques, et la riposte prévue pour chacun

| Risque | Pourquoi il surviendrait | Riposte |
|---|---|---|
| **Le socle est contourné** : un maillon écrit sans `link_documents` | la discipline humaine cède toujours | porte **G1** + contrôle de texte : tout `INSERT`/`UPDATE` dans une table métier depuis une fonction `chain_*` sans appel à `link_documents` échoue en CI |
| **La performance casse sur gros volumes** | 1 M de liens par an, 100 000 écritures par clôture | budgets chiffrés (§3.3), banc **G6**, index obligatoires, partitionnement de `domain_events` et `chain_traces` |
| **La mise en service bloque un client existant** | une règle en mode `refuse` sur un historique incohérent | drapeau `observe` → `avertit` → `refuse` par société ; mesure du taux de refus avant blocage ; rattrapage de l'historique |
| **Les règles sont mal comprises** | un message trop technique ne dit rien à l'utilisateur | message obligatoire nommant document, date, règle et module (§4.1 point 6) + tableau de bord des refus |
| **Le périmètre dérive** | 62 règles, 17 mécanismes, 12 innovations : de quoi se disperser | un lot = un indicateur qui bouge ; aucun lot suivant avant que le précédent soit **prouvé** |
| **La dépendance aux correctifs bloque la chaîne** | `W1`, `W4`, `W9` sont hors de ce plan | ces quatre vagues sont **placées en tête** du séquencement, jamais en parallèle lointain |

### 7.4 Le lancement : trois lots, douze jours

| Ordre | Lot | Durée | Ce que le client voit à la fin |
|---:|---|---:|---|
| 1 | **L0 — socle** | 4 j | rien à l'écran, mais **tout le reste devient possible** |
| 2 | **L1 — traçage des 62 chaînages** | 5 j | rien à l'écran, mais chaque document a désormais une **ascendance et une descendance** en base |
| 3 | **L2 — portes CI** | 3 j | la garantie que la qualité ne se dégradera plus : **une régression future casse la construction** |

Puis **`L3` + `L4` + `L5` (13 j)** donnent les deux premiers écrans vendables : **Robustesse** et
**Cohérence**. À ce moment, nous pouvons dire à un client, chiffres en main : « voici les points faibles
de votre base, voici l'écart, voici le plan » — ce que personne ne peut montrer aujourd'hui.

### 7.5 Ce que ce plan change par rapport au plan correctif

Le plan correctif **répare** : 69 défauts, 32 bloquants, une cible « zéro défaut bloquant ». Il rend le
produit **sain**. Il ne le rend pas **différent**.

Ce plan d'implémentation **construit** : il donne au produit une propriété que les leaders ont (le
chaînage) **et** deux propriétés qu'ils n'ont pas — le chaînage **vérifié** et **publié** — plus cinq
chaînages inter-domaines qu'aucun éditeur cité ne propose (production↔RH, stock↔projets,
production↔projets, production↔trésorerie, absence↔frais↔temps↔tâches).

> *Le plan correctif nous rend crédibles ; ce plan nous rend préférables.*








