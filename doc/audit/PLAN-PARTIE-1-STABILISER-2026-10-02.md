# Partie 1 / 4 — Stabiliser : une seule branche, une CI verte, des gardes honnêtes

> **Plan en 4 parties du 02/10/2026** — charges équilibrées (≈ 9 j chacune, ≈ 36 j au total)
>
> | Partie | Objet | Charge | Document |
> |---|---|---:|---|
> | **1** | **Stabiliser : une branche, une CI verte, des gardes honnêtes** | **≈ 9,25 j** | ce document |
> | 2 | Finir les défauts métier de la recette (paie, stock, compta, analytique) | ≈ 9,5 j | [PLAN-PARTIE-2](PLAN-PARTIE-2-DEFAUTS-METIER-2026-10-02.md) |
> | 3 | Chaînages : finir L3 (maillons RPC, banc D1→D8) et L4 (indice de cohérence) | ≈ 9 j | [PLAN-PARTIE-3](PLAN-PARTIE-3-CHAINAGES-L3-L4-2026-10-02.md) |
> | 4 | Montrer, recetter, livrer (L5, e2e, recette écran, production) | ≈ 10 j | [PLAN-PARTIE-4](PLAN-PARTIE-4-RECETTE-LIVRAISON-2026-10-02.md) |
>
> **Hors de ces 4 parties (horizon suivant, à replanifier quand la partie 4 est close)** :
> chaînages L6 → L24 (≈ 100 j), localisation Djibouti lot K (≈ 74 j + textes + pilote),
> **couverture d'audit phase 10** (16 modules sur 20 jamais audités par exécution, ≈ 15 j),
> propositions P1 → P8.
>
> *Révision du 02/10 à 17 h : le plan a été confronté aux travaux en vol (§ 1 bis). Quatre
> trous ont été bouchés : la voie C des types (tâche 2.16), le cas des travaux déjà
> commencés (tâche 1.0 et règles 7 et 8), la décision G7 en production (tâche 4.8) et la
> couverture d'audit (horizon). D-4 passe de la partie 4 à la partie 1 (1.13) ; E2 et H1
> passent de la partie 2 à la partie 4 (4.11, 4.12).*

---

## 0. Pourquoi cette partie passe en premier, seule

Mesuré le 02/10 par rejeu sur base neuve (copies propres des commits, PostgreSQL 16 +
`plpgsql_check`) et confirmé par la CI GitHub :

- **la branche principale est rouge** depuis `6a6c8dd` (4 passages rouges le 02/10) :
  types générés périmés (2 tables L4 absentes) et plafond des tables non lues (77 > 75) ;
  sur GitHub, le job base **s'arrête** à la porte des types — les ~100 suites suivantes
  **ne sont plus jouées** ;
- **la branche `qa/recette-2026-09-29` n'a jamais été jouée par la CI** (0 passage : le
  workflow ne se déclenche pas sur ce nom) ; le rejeu y trouve **5 portes rouges** ;
- **trois sessions** ont travaillé en même temps sur les mêmes numéros de migration et les
  mêmes portes : doublon `322`, collision `310` → `321`, deux corrections concurrentes du
  même doublon ;
- **un correctif a été perdu** (`198`, codes TVA de la saisie manuelle) et **le défaut est
  toujours reproductible** ;
- **deux gardes sont faussement vertes** : la suite de la caisse n'a pas d'`_audit_assert`,
  et la garde « aucun `window.confirm` » passe parce que `confirmSync` l'enveloppe.

Tant que ces points ne sont pas réglés, **aucun « ✅ » de la partie 2 ou 3 n'est
démontrable**. Cette partie se fait **seule**, par **une seule session**.

## 1. Règles qui valent pour les 4 parties (posées ici, appliquées partout)

1. **Une partie = une branche = une session active.** Branche `partie-N-<objet>` créée
   depuis `commercial-hr-paie` à jour. Aucun autre worktree ne modifie `app/sql/` pendant
   ce temps.
2. **Plages de numéros réservées** (inscrites dans `NUMEROTATION-MIGRATIONS.md` dès la
   tâche 1.9) :

   | Partie | Plage |
   |---|---|
   | 1 | `325` → `339` |
   | 2 | `340` → `369` |
   | 3 | `414` → `449` (série des chaînages, 4xx) |
   | 4 | `370` → `399` |

3. **« Fait » = un passage de CI GitHub vert** sur le commit, lien du passage dans la ligne
   du tableau. Un rejeu local ne suffit pas, un document non plus.
4. Un défaut = un test **rouge avant**, la migration, le câblage CI, la preuve et
   `npm run db:types` **dans le même commit**.
5. Avant chaque commit :
   ```bash
   ls app/sql/*.sql | grep -v '_tests\.sql$' | sed 's|.*/||' | cut -c1-3 | sort | uniq -d
   ```
   Toute ligne imprimée est un doublon.
6. On ne passe à la partie suivante que lorsque les **critères de sortie** sont tous cochés.
7. **Un travail commencé hors de sa partie** (avant que la partie précédente soit close) est
   inscrit au tableau du § 1 bis, avec sa branche et sa tâche de rattachement. Il est
   **mis en pause** au premier commit propre, puis repris dans sa partie. On ne l'abandonne
   pas, et on ne le fusionne pas en douce.
8. **Aucun fichier non suivi le soir.** Une migration en cours est commitée sur sa branche
   (même rouge, avec « WIP » dans le message), ou elle n'existe pas. Le dépôt a déjà perdu
   des fichiers non suivis lors d'une synchronisation iCloud (24/09). Les fichiers de travail
   (`_r414.sql`, `_t01.txt`…) restent dans un dossier temporaire, **jamais** dans `app/sql/`.

## 1 bis. Les travaux en vol, relevés le 02/10 à 17 h, et leur rattachement

| Travail en vol | Où il vit | État relevé | Rattaché à | Ce qu'il faut faire |
|---|---|---|---|---|
| **Fusion de la recette dans la branche principale** (`validateIBAN` remplacé par le réexport du validateur pur) | `/private/tmp/merge-final`, fusion **non terminée** : 16 conflits, base `9ea2eae` + `ae5edba` | les deux côtés ont **déjà bougé** : la principale est à `c51d468`, la recette à `379d31a` (B9 livré après) | **1.6** | Mettre en pause. Faire **1.5 d'abord** (les 5 portes rouges de la recette), geler la branche recette, puis refaire la fusion sur les **deux têtes à jour** |
| **Diagnostic D3** (OF terminé à 0,00 €, onglet « Consommations » vide), test d'écran écrit | `~/qa-worktrees/lot-d`, branche `qa/lot-d-stock`, test **non suivi** | diagnostic juste : l'écran ignore les colonnes de coût posées par la `302` et lit `of_consumptions` au lieu des sorties `stock_movements` | **2.5** | Commiter le test sur sa branche (règle 8), puis reprendre la tâche en partie 2 sur la branche unique |
| **`414_chain_l4_alerte_degradation`** (+ suite) | dossier principal, **non suivi**, avec des fichiers de travail dans `app/sql/` | numéro **conforme** à la plage de la partie 3 | **3.9** | Commiter sur une branche `partie-3-chainages`, et dans le **même commit** : types, G1, G7, plafond des tables non lues (les deux rouges de la principale viennent exactement de cet oubli en L4) |
| **Voie C : types de retour de la paie** (`c51d468`, poussé), suite sur `audit/employe-colonnes-identite` (`/private/tmp/wt-employe`, 2 fichiers modifiés) | branche principale | `tsc` 0, plafond des `any` 1 794 → 1 784 ; **CI rouge** (pour les deux causes de 1.1, pas pour ce commit) | **2.16** (nouvelle) | Commiter la suite (règle 8). Ensuite, plus rien sur la principale avant 1.1 |

## 2. Les tâches

| # | Tâche | Constat mesuré le 02/10 | Preuve attendue | Charge | État |
|---|---|---|---|---:|---|
| 1.0 | **Inventaire et gel des travaux en vol** (§ 1 bis) : chaque travail commité sur sa branche, mis en pause, rattaché ; une seule session reprend la main | 5 sessions, 4 worktrees actifs, 1 fusion inachevée, 3 fichiers non suivis dans `app/sql/` | `git worktree list` et `git status` propres partout | 0,25 j | ⬜ |
| 1.1 | **Remettre `commercial-hr-paie` au vert** : `npm run db:types` sur base neuve, puis plafond des tables non lues (lire `chain_invariants` / `chain_invariant_results` côté écran, ou relever le plafond **avec justification datée**) | types : 93 lignes d'écart ; `check-unused-tables` 77 > 75 | passage GitHub vert, tous jobs | 0,5 j | ⬜ |
| 1.2 | **Faux vert de la caisse** : ajouter `SELECT _audit_assert('412');` en fin de `412_chain_l1_caisse_rpc_tests.sql` ; voir la suite **rouge** en cassant un scénario, puis verte | la suite ne lève jamais (8/8 lus en base, aucun verdict imprimé) | sortie `[412] 8 scénario(s) : 8 vert(s)` | 0,25 j | ⬜ |
| 1.3 | **Garde anti-faux-vert** : `check-test-suites.mjs` refuse toute suite `*_tests.sql` qui ne finit pas par `_audit_assert('<id>')` ; aligner les étiquettes des suites renommées (`[310]` dans `400_…` → `[400]`) et les clés du registre | 14 suites 4xx s'annoncent sous leur ancien numéro | porte vue rouge sur une suite sans assert | 0,5 j | ⬜ |
| 1.4 | **CI sur toutes les branches de travail** : ajouter `qa/**` et `partie-*` aux déclencheurs `push` de `ci.yml` | 0 passage sur la branche QA | un passage visible sur la branche QA | 0,25 j | ⬜ |
| 1.5 | **Réparer la branche QA avant fusion** : (a) `REVOKE EXECUTE … FROM PUBLIC, anon` sur les 6 fonctions de `323`/`324` (`is_eu_country`, `is_valid_iban`, `line_apply_customer_fiscal_position`, `partner_apply_fiscal_position`, `partner_bank_account_iban…`) ; (b) les 7 erreurs `plpgsql_check` (déclencheurs partagés de `312`, `323`, `order_lines_refresh_totals`) ; (c) IBAN de test **valide** dans `274` ; (d) reprendre `216d9ff` (partitions mensuelles hors des types). **Remesurer d'abord sur la tête du moment** (`379d31a` au 02/10 à 17 h), car B9 et la suite sont arrivés après ma mesure | rejeu de `ae5edba` : `check_plpgsql`, `check_anon_grants`, `228 T06`, `274 T05`, types — rouges | les 5 portes vertes sur la branche QA | 1,5 j | ⬜ |
| 1.6 | **Fusionner la recette dans la branche principale** (QA garde `310`→`324`, chaînages `400`→`413`) ; rejeu base neuve + mise à niveau d'une base qui porte les anciens noms | les deux lignes divergent (46 et 49 commits) | base neuve 0 erreur ; suites QA **et** chaînages vertes ; GitHub vert | 1 j | ⬜ |
| 1.7 | **Récupérer le correctif TVA 198** (branche `claude/tva-saisie-ca3`, `3d478ba`) sous le numéro `325` : normalisation du code (`20` → `FR20`), `get_vat_codes`, cases A/B de la CA3 ; écran de saisie qui propose les **codes** du paramétrage ; non-régression `197`, `245`, `300` | une vente saisie avec `20` sort de la synthèse : **base 0, taux 0, sans case** ; avec `FR20` : base 100, A1 | suite `325` rouge avant / verte après | 1 j | ⬜ |
| 1.8 | **Vrai dialogue de confirmation (AUD-I01)** : remplacer `confirmSync` (= `window.confirm`) par `useConfirm` / `confirmDialog` dans les **94** fichiers ; la garde CI interdit `confirmSync` | 94 fichiers (81 à l'audit du 21/09) | `grep confirmSync src` = 0 ; tests d'écran verts | 2 j | ⬜ |
| 1.9 | **Ménage et documents** : décider puis fermer les worktrees `extract-tax-salary-table`, `import-data-column-alignment`, `quirky-goldwasser`, `happy-goodall`, `tva-saisie-ca3`, `l3-tranche2` (et `git worktree prune`) ; mettre à jour le tableau de bord du plan W (W4→W10 sont faits) ; inscrire les plages du §1 dans `NUMEROTATION-MIGRATIONS.md` ; alléger `AGENTS.md` (un pointeur vers ces 4 documents en tête) | tableau W figé au 24/09 ; 6 worktrees dont 2 avec du travail non commité de juillet-août | `git worktree list` = principal + partie en cours | 0,5 j | ⬜ |
| 1.10 | **Champs factices du plan comptable (AUD-I02)** : « nombre de lignes », « saut de page », « regroupement » (`ChartAccountsPage.tsx` l. 616-621) — les retirer ou les enregistrer | non contrôlés, jamais enregistrés | test d'écran | 0,25 j | ✅ 02/10 : les SIX contrôles factices de l'onglet « Complément » retirés — les 3 champs n'avaient aucune colonne, les 3 cases (`saisie_*`) une colonne que plus rien ne lit depuis la 152 ; test `chart-accounts-no-placebo` rouge avant (2/2), vert après |
| 1.11 | **Fin de D-5 côté code** : `parse-bank-statement` et `ai-import-mapping` refusent en `409` sans consentement, comme `ocr-invoice-import` | deux fonctions parlent au prestataire sans garde | 2 tests Edge | 0,5 j | ✅ 02/10 : 409 sans consentement, 400 sans société désignée (la société n'est plus devinée), contre-épreuve « avec consentement l'appel part » ; écrans : `x-tenant-id` joint, refus affiché avec sa phrase. Edge 6 tests (rouges avant), Vitest 2 (rouges avant) |
| 1.13 | **D-4, finir la voie A** (déplacée de la partie 4) : convertisseur PDF isolé, secret `GOTENBERG_URL`, un appelant. C'est un sujet de sécurité (SSRF AUD-H03), il a sa place avec les gardes | la fonction rend `503` sans convertisseur ; le bucket `generated-pdfs` existe (`317`, 9/9) | un PDF réel archivé, test Edge | 0,5 j | ⬜ |
| 1.12 | **Rejeu de contrôle final** : base neuve, job `db-integration` complet **sans s'arrêter au premier rouge**, chemin de l'écran, Vitest, Deno ; mes sondes indépendantes (facture, cloisonnement, viewer, anon, stock, caisse, NF-525) | référence 02/10 : 747 scénarios verts, 125 verdicts écran, 1 534 Vitest, 36 Edge | chiffres ≥ référence, 0 rouge | 0,25 j | ⬜ |
| | **Total** | | | **≈ 9,25 j** | |

## 3. Ordre

1.0 → 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 → (1.8, 1.10, 1.11, 1.13 dans l'ordre voulu) → 1.9 → 1.12.

⚠️ **1.5 avant 1.6, sans exception.** La fusion en cours au 02/10 (`/private/tmp/merge-final`)
a été lancée sans 1.5 : elle importerait dans la branche principale les 6 fonctions
appelables sans connexion et les 7 erreurs `plpgsql_check`.

## 4. Critères de sortie (tous requis)

- [ ] **une seule branche de travail** (`commercial-hr-paie`), qui contient la recette et les
      chaînages ; aucun worktree annexe ;
- [ ] **dernier passage GitHub vert sur tous les jobs** ; le job base joue **toutes** les
      suites ;
- [ ] `0` doublon de numéro ; plages des parties 2, 3 et 4 inscrites ;
- [ ] registre `ci/expected_failures.sql` : seuls les défauts **prouvés et planifiés en
      partie 2** (`321 T02/T03/T05`) ;
- [ ] `confirmSync` absent de `src/` ; suites sans `_audit_assert` refusées par la CI ;
- [ ] défaut TVA 198 fermé ;
- [ ] `AGENTS.md` pointe vers ces 4 documents en tête de fichier.

## 5. Ce qui n'est PAS dans cette partie

Aucun nouveau défaut métier (→ partie 2), aucun nouveau maillon de chaînage (→ partie 3),
aucun déploiement (→ partie 4).
