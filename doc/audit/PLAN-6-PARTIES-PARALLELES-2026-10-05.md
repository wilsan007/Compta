# Plan en 6 parties parallèles — tout ce qui reste (05/10/2026)

> **Objet.** Tout le reste à faire du dépôt, réparti en **six parties qui ne se
> touchent pas**, chacune tenue par **une** session dans **un** worktree, plus une
> **étape 0** courte et une **session d'intégration** qui est la seule à écrire
> dans `main`. Ce plan remplace, pour la suite, le plan en 5 parties du 02/10.
>
> **Sources.** [SUIVI-CHANTIERS.md](SUIVI-CHANTIERS.md) (mesures du 03/10, en
> partie périmées), l'état de git mesuré le 05/10, le
> [plan des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md), le
> [plan de perfection 9,5](PLAN-PERFECTION-9.5.md), le
> [cahier de localisation](../localisation/CAHIER-DES-CHARGES-LOCALISATION.md).
>
> **Ce que ce plan ne sait pas.** Les charges des parties E et F ne sont pas
> estimées : 32 chantiers du plan 9,5 n'ont jamais été recomptés. Leur première
> tâche est ce recomptage. La partie 3 du plan du 02/10 est notée « presque
> vide » au suivi alors que les migrations `432` → `436` existent : à recompter
> aussi (tâche A.1).

---

## 1. Pourquoi les sessions se sont marché dessus, et les règles qui l'empêchent

Mesuré ce matin : quatre commits partis de `main` en parallèle, **tous** modifient
`SUIVI-CHANTIERS.md`, trois `.any-ceiling.json`, deux `ci.yml`, deux le même
scénario d'écran. Le découpage par sujet ne suffit pas ; il faut un découpage
par **fichier**.

| # | Règle | Détail |
|---|---|---|
| R1 | **Une partie = une session = un worktree = une branche** | branche `plan6/<lettre>-<nom>`, créée depuis `main` après l'étape 0. Personne ne travaille dans le dossier principal, réservé à l'intégration |
| R2 | **Une plage de numéros par partie** | tableau §2 ; un numéro se prend par `npm run migration:prendre`, jamais à la main |
| R3 | **Un territoire de fichiers par partie** | tableau §2. Hors de son territoire, une session **n'édite pas** : elle écrit une demande dans son fichier de suivi, l'intégration la transmet |
| R4 | **Le suivi est par partie** | chaque partie tient `doc/audit/plan6/PARTIE-<lettre>.md`. `SUIVI-CHANTIERS.md` et `AGENTS.md` ne sont écrits **que** par l'intégration |
| R5 | **`ci.yml` : un bloc par partie** | l'étape 0 pose six marqueurs `# --- plan6:<lettre> ---` ; chacun n'ajoute ses suites que sous le sien |
| R6 | **Fichiers générés : on régénère, on ne fusionne pas** | `database-generated.ts` (`npm run db:types`), les plafonds (`.any-ceiling.json`, `.console-error-ceiling.json`, knip) sont recalculés par l'intégration après chaque fusion |
| R7 | **Une fonction SQL, un propriétaire** | avant un `CREATE OR REPLACE` d'une fonction **existante**, vérifier qu'aucune autre branche `plan6/*` ne la réécrit (`git grep -l "FUNCTION <nom>" $(git branch --list 'plan6/*' --format='%(refname:short)') -- app/sql`). En cas de doute : la partie C (comptes par pays) passe **après** les autres sur les fonctions d'écriture comptable |
| R8 | **Fusion fréquente, par l'intégration seule** | chaque partie pousse des lots courts (1 à 3 jours) ; l'intégration les fusionne dans `main` un par un, rejoue la batterie, régénère (R6), puis chaque partie se resynchronise sur `main` |

**Indépendance : ce qui reste couplé, dit.**
- **B, C et E écrivent des déclencheurs sur les mêmes tables métier** (stock,
  production, ventes). Les fichiers ne se touchent pas (plages distinctes), mais
  le comportement peut : R7 et la batterie complète à chaque fusion sont le
  garde-fou.
- **D balaie des écrans** (dialogue de confirmation sur 100 fichiers, typage de
  80 états) que les autres parties modifient aussi. D livre ces balayages
  **par module et en premier**, en lots d'un jour, pour que le conflit soit court.
- **P1 → P8 dépendent de L3/L4** : ils sont dans la partie A, après.

---

## 2. Les six parties d'un coup d'œil

| Partie | Objet | Charge | Plage de migrations | Territoire de fichiers |
|---|---|---|---|---|
| **A** | Chaînages et preuve : finir L3/L4, L6, L16 → L24, pages Robustesse/Cohérence, puis P1 → P8 | ≈ 60 j + ≈ 25 j | `423`→`429`, `437`→`449`, `457`→`459`, `468`→`499` | `app/sql/*chain*`, `*metric*`, `ci/check_chain*`, `ci/check_effects*` ; écrans et requêtes « chaîne », « cohérence », « pilotage » |
| **B** | Les 62 règles d'état (L8 → L15) et les restes de paie française | ≈ 42 j + ≈ 3 j | `500` → `559` | migrations de règles d'état par module ; `lib/payroll*`, écrans de paie |
| **C** | Lot K — localisation Djibouti | ≈ 74 j (48 neutres + 26 pack) | `370` → `399`, puis `600` → `649` | `legislation_packs`, `chart_*`, `resolve_account`, grilles fiscales ; `lib/countries.ts`, écrans Paramètres → pays/plan comptable ; `doc/localisation/` |
| **D** | Qualité des écrans, recette, livraison | ≈ 25 j + recette | `355` → `369` (peu de SQL) | balayages transverses de `src/pages`, `src/components`, `e2e/`, `scripts/qa`, `src/__screen__`, job Playwright |
| **E** | Fonctions manquantes — opérations : stock, production, achats, ventes | **à estimer** (E.1) | `650` → `699` | écrans et requêtes stock, production, achats, ventes ; leurs tables coquilles |
| **F** | Fonctions manquantes — plateforme : sécurité, groupe, CRM, projets, notifications, documents, états, administration | **à estimer** (F.1) | `700` → `749` | `supabase/functions/`, écrans CRM, projets, paramètres, notifications ; leurs tables coquilles |

---

## 3. Étape 0 — remettre une seule ligne (≈ 1 j, séquentielle, avant tout le reste)

Faite par la session d'intégration. **Aucune partie ne démarre avant sa fin.**

| # | Tâche | Critère de sortie |
|---|---|---|
| 0.1 | Finir ou geler la `2.13` (`353`, 21 fichiers non commités dans `partie-2-213`) | un commit |
| 0.2 | Réunir sur une branche partie de `main` : `d38851b` (352), `9c02a74` (retrait Gescom), `c0fd3a0` (354), `e912a4e` (OCR), le commit de 0.1 | conflits résolus (`SUIVI-CHANTIERS.md`, plafonds, `ci.yml`, scénario `02`), batterie verte |
| 0.3 | **Sécurité** : vérifier sur la production qu'aucune politique `allow_all_%` ne subsiste (`SELECT tablename FROM pg_policies WHERE policyname LIKE 'allow_all_%'`) | 0 ligne, ou une migration corrective prise dans la plage de F |
| 0.4 | Appliquer le patch `T06` ([patches/](patches/LISEZ-MOI-T06.md)) sur la suite `434` | suite `434` verte, patch supprimé |
| 0.5 | Sauver ce qui est gelé et utile : barème ITS + calcul « palier fixe » (`claude/extract-tax-salary-table-2a3267`) → déposé pour C ; alignement des colonnes (`claude/import-data-column-alignment-aad9c5`) → déposé pour D | deux fichiers `doc/audit/plan6/REPRISE-*.md` qui nomment le commit source |
| 0.6 | PR unique vers `main`, fusion (= déploiement) | `main` contient tout |
| 0.7 | Ménage (ex-tâche 1.9) : supprimer les 6 worktrees et les branches mortes locales et distantes | `git worktree list` : une ligne |
| 0.8 | Poser le cadre : inscrire les plages du §2 (`migration-numero.mjs plage`), créer `doc/audit/plan6/PARTIE-A.md` … `-F.md`, poser les six marqueurs dans `ci.yml`, créer les six worktrees | six worktrees propres sur `main` |
| 0.9 | Recalculer `SUIVI-CHANTIERS.md` (`suivi-chantiers.mjs --write`) et corriger les lignes périmées (1.5, 1.7, partie 3) | `--check` vert |

---

## 4. Partie A — chaînages et preuve

**Départ possible : tout de suite. Décisions bloquantes : aucune avant P1.**

| # | Tâche | Repris de | Charge |
|---|---|---|---|
| A.1 | Recompter L3 : maillons RPC tracés, épreuves D1 → D8 réellement jouées par `433`/`434`/`436`, rapport par maillon | 3.1, 3.4 → 3.7 | 1 j |
| A.2 | Relevé bancaire manuel et maillons RPC restants | 3.3 | 2 j |
| A.3 | Les 6 invariants encore « non mesurables » ; relevé nocturne et alerte (`414`) ; invariants lus par l'écran | 3.8 → 3.10 | 4 j |
| A.4 | Pages « Robustesse » et « Cohérence » | L5, 4.1/4.2 | 3 j |
| A.5 | Vue Chaîne : finir ce que `460` → `467` ont amorcé | L6, I-01 | à recompter |
| A.6 | L16 → L22 : chaînages internes, couples inter-modules, régénération, lettrage, moteur de règles — reprendre après `415` → `422` | L16 → L22 | plafond du plan |
| A.7 | L23 (événements et webhooks unifiés, suite de la tranche 1) et L24 (explicabilité, régularisation guidée) | L23, L24 | plafond du plan |
| A.8 | P1 certificat d'intégrité, P3 audit de reprise, P2 banc sur données du prospect, puis P4, P5, P7, P8, P6 | propositions P1 → P8 | ≈ 25 j |

**Attend de vous, avant A.8 :** les cinq questions du §6 des propositions (qui
signe le certificat, à qui on le remet, où tournent les données du prospect…),
et l'expert-comptable référent.

---

## 5. Partie B — règles d'état et paie française

**Départ possible : tout de suite.**

| # | Tâche | Repris de | Charge |
|---|---|---|---|
| B.1 | Inventaire des 62 règles d'état contre le schéma du jour : lesquelles existent déjà (W1 → W10, X1 → X6 en ont posé) | L8 → L15 | 2 j |
| B.2 | Règles d'état, un lot par module, dans cet ordre : ventes, achats, trésorerie, paie/RH, projets, production, conformité, budgets | L8 → L15 | ≈ 40 j |
| B.3 | Paie : seuil **hebdomadaire** des heures supplémentaires, exonération d'impôt de 7 500 € | reste de 2.3 | 1,5 j |
| B.4 | Paie : arrêt maladie (carence, maintien) | reste de 2.4 | 1,5 j |

**Attend de vous :** la signature de l'expert-comptable (D-G) — elle bloque le
**déploiement** des `276`, `341`, `342` et de B.3/B.4, pas leur écriture.

---

## 6. Partie C — lot K, localisation Djibouti

**Départ possible : la phase 1 tout de suite ; la phase 2 attend les textes.**

| # | Tâche | Repris de | Charge |
|---|---|---|---|
| C.1 | Phase 1 — neutralité : les comptes codés en dur (`310000`, `601000`, `355000`, `713500`, `641`/`645`/`421`/`431`…) passent par `resolve_account` ; pack fictif `ZZ` comme preuve | LOC1-01 → 58, S-10, AUD-F03, AUD-G10 | ≈ 48 j |
| C.2 | Reprendre le barème ITS gelé (étape 0.5) sous `370`, **sans** les deux lignes extrapolées, source provisoire dite | — | 1 j |
| C.3 | Phase 2 — pack Djibouti : plan comptable national, TVA, paie, états, mentions de facture, formats bancaires ; chaque valeur sourcée `SRC-DJ-nn` | LOC2-01 → 41 | ≈ 26 j |
| C.4 | Pilote | — | hors charge |

**Attend de vous :** `D-11` (entreprises publiques seules ou avec le module des
administrations ; arabe dès la v1), les **14 documents djiboutiens**,
l'expert-comptable référent. Sans eux, C.3 ne commence pas.

**Couplage (R7) :** C.1 réécrit des fonctions d'écriture comptable de tous les
modules. C les traite **module par module**, en annonçant dans son fichier de
suivi le module de la semaine ; B et E n'y touchent pas cette semaine-là.

---

## 7. Partie D — qualité des écrans, recette, livraison

**Départ possible : tout de suite pour D.1 → D.4 ; D.5 attend les secrets.**

| # | Tâche | Repris de | Charge |
|---|---|---|---|
| D.1 | Vrai dialogue de confirmation à la place de `confirmSync` (100 fichiers), **par module, un lot par jour** | 1.8, AUD-I01 | 4 j |
| D.2 | Typer les 80 états d'écran restants (RH, production, trésorerie, immobilisations, CRM) | DAT-02, suite de 2.16 | 5 j |
| D.3 | Alignement des colonnes sur 10 écrans (repris de l'étape 0.5) | branche gelée | 1 j |
| D.4 | Lectures du chemin de l'écran (159 fonctions non couvertes) ; immobilisations et tableaux de bord à l'écran | 4.5, 4.11, 4.12 | 5 j |
| D.5 | Playwright sur chaque PR vers `main` ; 4 parcours qui lisent un chiffre | 4.3, 4.4, AUD-J01/J02 | 3 j |
| D.6 | Les 14 parcours à l'écran, 2 sociétés, 4 gabarits ; correction des écarts bloquants ; re-notation des modules | 4.6, 4.7, P0-08 | recette |
| D.7 | Rejeu sur copie de production (porte G7 sous le vrai propriétaire), relecture des paramètres globaux et de `banks` | 4.8, 4.9 | 2 j |
| D.8 | Contraste : appliquer la décision D-7 | AUD-I05 | 1 j |

**Attend de vous :** les secrets E2E dans GitHub (D.5), la décision `D-7`
(D.8), votre présence pour la recette (D.6).

---

## 8. Partie E — fonctions manquantes, opérations

**Départ possible : tout de suite, par le recomptage.**

| # | Tâche | Repris de (plan 9,5) |
|---|---|---|
| E.1 | **Recompter** les chantiers ❓ de son périmètre et **estimer** les ⬜ ; décider pour chacun : faire, reporter, écarter | ACC-01, ACC-03, PRD-03/04/05/08/10, ACH-01/02, VTE-01/03 |
| E.2 | Restes à l'écran : transfert entre dépôts, étiquettes, MRP jamais testés ; action « Modifier » d'une nomenclature | D13, reste de 2.5 |
| E.3 | Stock avancé : FIFO/LIFO, unités de mesure, frais accessoires, réapprovisionnement et inventaire tournant, emplacements, transferts et variantes | STK-03/07/08/09/11/14 |
| E.4 | Production : capacité finie, maintenance, sous-OF (`parent_mo_id` inutilisé) | PRD-07, PRD-11 |
| E.5 | Tables coquilles de son périmètre, **brancher ou supprimer** : `uom_categories`, `landed_cost_lines`, `reorder_rules`, `stock_count_cycles`, `stock_transfer_lines`, `mo_consumptions`, `mo_operations`, `maintenance_records`, `work_center_calendars`, `quality_control_*`, `fixed_asset_components`, `resource_capacities` | ORPH-02 |

---

## 9. Partie F — fonctions manquantes, plateforme

**Départ possible : tout de suite, par F.1 et F.2.**

| # | Tâche | Repris de |
|---|---|---|
| F.1 | **Recompter** les ❓ de son périmètre et **estimer** les ⬜ | BNQ-04, TRE-01, CRM-03, PRJ-01/06/07/09, BI-03, SEC-03, PRF-03/04, UX-05, ADM-01/03/05, IMP-03, NOT-03, ONB-02, PAY-01/11/12 |
| F.2 | Authentification forte : suite SQL (émission, usage, révocation, rejeu d'une clé ; TOTP), test Edge « clé révoquée → 401 » | ORPH-01, SEC-02 (1 j) |
| F.3 | `generate-pdf`, voie A : convertisseur isolé, `GOTENBERG_URL`, un appelant | 1.13, D-4 |
| F.4 | Groupe : structure, opérations intra-groupe, consolidation | GRP-01 → 03 |
| F.5 | CRM (séquences, scoring) ; projets (capacité par ressource, champs personnalisés, automatisations) | CRM-01/02, PRJ-02/04/08 |
| F.6 | Notifications et alertes ; rattachement universel de documents ; générateur d'états ; modèles de documents ; connecteurs métier | NOT-01/02, GED-01, BI-01, ADM-04, API-03 |
| F.7 | RH hors paie : conventions collectives, recrutement ; mobile hors ligne | PAY-08, RH-03, PTL-03 |
| F.8 | Tables coquilles de son périmètre (les 25 autres), brancher ou supprimer | ORPH-02 |

**Attend de vous :** la clé `sb_secret_…` à tourner, le DPA du prestataire IA,
les comptes des 9 intégrations (Chorus Pro, Yousign, GoCardless, Resend, EFI,
SIRENE/VIES, Stripe, Gotenberg, Sentry).

---

## 10. La session d'intégration (la « ligne unique »)

Une seule, dans le dossier principal, sur `main`. Elle ne développe rien.

1. Reçoit un lot poussé par une partie, le fusionne **seul**, rejoue la batterie
   sur base neuve.
2. Régénère les types et les plafonds (R6), met à jour `SUIVI-CHANTIERS.md` à
   partir des six `PARTIE-*.md` (R4).
3. Fusionne dans `main` par PR ; **rappel : la fusion dans `main` déploie**.
4. Signale aux autres parties qu'elles doivent se resynchroniser.
5. Transmet les demandes hors territoire (R3) à la partie propriétaire.

---

## 11. Ce qui dépend de vous, en une liste

| Sujet | Bloque |
|---|---|
| Expert-comptable référent et signature des bulletins d'or (D-G) | déploiement paie (B), pack Djibouti (C.3), certificat (A.8) |
| D-11 et les 14 documents djiboutiens | C.3 |
| D-7 (contraste) | D.8 |
| Secrets E2E dans GitHub | D.5 |
| Clé `sb_secret_…` à tourner, DPA, comptes des 9 intégrations | F |
| Pilotes (2 à 3) | C.4, recette |
| Les cinq questions des propositions P1 → P8 | A.8 |

---

## 12. Lancer une session

Après l'étape 0, dans le worktree de la partie, le message d'ouverture est :

```
Tu tiens la partie <LETTRE> de doc/audit/PLAN-6-PARTIES-PARALLELES-2026-10-05.md.
Lis le §1 (règles R1 à R8) et ta section. Tu ne modifies que ton territoire,
tu prends tes numéros dans ta plage, tu tiens doc/audit/plan6/PARTIE-<LETTRE>.md,
tu ne touches ni SUIVI-CHANTIERS.md ni AGENTS.md ni main. Commence par la
première tâche non faite.
```
