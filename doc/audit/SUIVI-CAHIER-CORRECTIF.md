# Suivi du cahier des charges correctif

> **Référence** [CAHIER-DES-CHARGES-CORRECTIF.md](CAHIER-DES-CHARGES-CORRECTIF.md)
> **Branche** `commercial-hr-paie` — dernier commit au démarrage du suivi : `057c708` · dernier commit au 17/09 : `2d522c7`
> **Session suivie** « Analyse état plateforme par module » (Claude Code, **TERMINÉE 15/09 19h45**)
> **Démarrage du suivi** 15/09/2026, 19h15
> **Règle** une action passe à **OK** seulement avec une preuve (commande exécutée, fichier, commit). Ce que l'autre session affirme sans l'avoir exécuté reste « à valider ».

Légende : **OK** terminé et prouvé · ⏳ en cours · ⬜ à faire · 👤 action de votre part

---

## Tableau de bord

| Bloc | Actions | OK | Reste |
|---|---:|---:|---:|
| A — Chaîne de livraison | 3 | 2 | 1 |
| B — Validation sur une vraie base PostgreSQL | 12 | 6 | 6 |
| C — Front et bugs trouvés à l'exécution | 14 | 12 | 2 |
| D — Garde-fous LOT 6 au vert | 5 | 0 | 5 |
| E — Dette LOT 7 | 8 | 6 | 2 |
| F — Actions de votre part | 2 | 0 | 2 |
| G — Requêtes refusées par PostgREST | 21 | 16 | 5 |
| H — Contraste des couleurs | 10 | 8 | 2 |
| I — Sécurité des Edge Functions | 4 | 0 | 4 |
| **Total** | **79** | **50** | **29** |

> Correction du 18/09 : le bloc C était affiché « 0 OK / 8 » alors que C1 à C7 sont corrigés depuis le 15/09 (migrations 158-159) — seul C8, la rotation de clé, vous revient. Le compteur, pas le travail, était faux.

---

## A — Chaîne de livraison (LOT 0)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| A1 | LOT0-02 | Lint à 0 avertissement (87 restants, option B : corriger les ~8 cas réels et marquer les chargements au montage) | **OK** | 15/09 19h30 | `npx oxlint --max-warnings=0` → code 0 (commande de la CI, `ci.yml:48`) |
| A2 | — | Commiter + pousser (≈ 184 fichiers modifiés, 3 migrations 158-160 non commitées) | ⬜ | | |
| A3 | LOT0-02 | Les 5 jobs de la CI passent au vert (nécessite un push) | ⬜ | | **Cause trouvée le 18/09** : `ci.yml` était **invalide en YAML** depuis `057c708` — 4 noms d'étapes contenaient un `:` non protégé (`- name: UX-03 : No window.confirm`). GitHub rejetait le workflow entier : aucun job n'a jamais pu tourner, ce qui explique A3 et D1 à D5. Corrigé, `yaml.safe_load` passe. **18/09 15h** : les 8 jobs rejoués localement un par un. `i18n-check` échouait (`production.json`, 7 clés `manufacturing.detail.info.*` en fr/en sans arabe) — **corrigé**, parité 24 espaces de noms sur 24. `db-integration` rejoué de bout en bout sur un PostgreSQL 16 neuf : 163 migrations, plpgsql_check 0 erreur, B3, 102, 105, 166, 168, 170 au vert, PostgREST 1 473 requêtes acceptées. **Seul le contrôle « types à jour » échoue**, parce que `database-generated.ts` commité précède la suppression des 22 tables par la 164 : il faut committer les types régénérés. |

## B — Validation sur une vraie base

Le conteneur Docker `onusuite-audit-pg` (base `test_compta`) tourne depuis 19h07 : 302 fonctions et 392 triggers chargés.

| # | Réf | Action / critère de recette | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| B1 | LOT0-01 | Schéma + migrations 74 à 160 rejouées en ordre numérique, sans erreur | **OK** | 15/09 19h45 | « 158 migrations passent sur un PostgreSQL 16 neuf, avec 0 erreur plpgsql_check » (migrations 158-160 écrites et testées, non commitées). Les migrations 99-160 étaient cassées, 158-160 les corrigent. |
| B2 | LOT2-\*, LOT3-\* | `sql/ci/check_plpgsql.sql` = 0 erreur | **OK** | 15/09 19h30 | confirmé post-158 |
| B3 | LOT6-03 / LOT1-01 | Triggers n'ont jamais été validés (faux vert) | **OK** | 18/09 16h | `check_trigger_reachability.sql` réécrit. L'ancien ne lisait qu'un motif (`NEW.status = '…'`) et annonçait « OK — 0 triggers validés » : **zéro assertion sur 394 triggers**. Le nouveau couvre toutes les colonnes, les corps de fonctions *et* les clauses WHEN, dans les formes `=`, `<>`, `IN`, `NOT IN`, `= ANY (ARRAY[…])`. Il s'auto-teste (fixture morte jouée puis annulée) et **échoue si aucune comparaison n'a pu être décidée** : un vert signifie désormais « vérifié ». Mesure sur `test_compta` : 394 triggers, 212 couples (table, colonne) énumérés par des CHECK, **55 comparaisons décidées**, 0 impossible après correctif. A trouvé 3 défauts réels du premier coup — voir C9, C10, C11. |
| B4 | LOT0-03 | `102_trigger_tests.sql` : 17 tests de déclencheurs sur 17 | **OK** | 15/09 19h45 | exécuté sur `test_compta`, tous passent |
| B5 | LOT0-04 | `105_rls_tests.sql` : aucune fuite entre sociétés, 358 tables | **OK** | 15/09 19h45 | exécuté sur `test_compta`, toutes les tables testées sans fuite |
| B6 | LOT2-05 | Contrôle d'équilibre : le brouillard peut être déséquilibré, la validation non | **OK** | 15/09 19h45 | testé à l'exécution |
| B7 | LOT1-01 | `validation_status='validated'` produit une écriture `VT` | **OK** | 15/09 19h45 | confirmé fonctionnel |
| B8 à B12 | LOT4-03, 04, 05, 06, 07, 09, 11, 12 | Valeurs métier : stock, MRP, lettrage, rapprochement | ⏳ | | **Rapprochement : fait le 18/09** — `170_payment_reconciliation_tests.sql`, 3 scénarios complets rejoués sur la vraie base (encaissement, rapprochement, annulation, côté client et fournisseur), branchés dans `db-integration`. Vérifiés non vacants : rejoués contre l'ancien code, ils échouent. **Stock : fait le 18/09** — `173_stock_valuation_tests.sql`, 4 scénarios (CUMP, cohérence du compte 310000 avec la valorisation, consommation FIFO des couches, parcours bon de livraison), branchés dans `db-integration`. A révélé C12 et C13. **MRP et lettrage restent testés unitairement avec Supabase mocké.** |

## C — Bugs découverts à l'exécution réelle (migrations 158-160, commitées en `2d522c7`)

> Correction du 17/09 : les numéros ci-dessous étaient inexacts. La 158 (`158_fix_plpgsql_check_errors.sql`, 1 382 l.) porte tous les correctifs de fonctions ; la 159 ne contient QUE les fuites RLS ; la 160 ne contient QUE la suppression de `_skip_cascade`. Ligne indiquée pour chaque correctif.

| # | Sévérité | Bug | État | Mitigation |
|---|---|---|:---:|---|
| C1 | 🔴 | Coordonnées bancaires de tous les partenaires lisibles/modifiables par toutes les sociétés (politique `allow_all` recréée en 99) | **Corrigé en 159** | `159_fix_rls_cross_tenant_leaks.sql:8` |
| C2 | 🔴 | Création de société échoue (`create_tenant_for_current_user`) | **Corrigé en 158** | `158:346` |
| C3 | 🔴 | Récursion infinie à chaque création/modification d'utilisateur | **Corrigé en 158** | `158:842` |
| C4 | 🔴 | Tout mouvement de stock valorisé refusé (régression migration 101) | **Corrigé en 158** | `158:1200` |
| C5 | 🟠 | Paiement client déduit deux fois du solde | **Corrigé en 158** | `158:865` |
| C6 | 🟠 | Fin d'ordre de fabrication déséquilibrée (641 vs 613) | **Corrigé en 158** | `158:1053` |
| C7 | 🟠 | DSN/TVA/e-invoice marquées transmises sans l'être (maintenant erreur explicite) | **Corrigé (edge functions, pas SQL)** | HTTP 503 dans `transmit-dsn`, `submit-vat-return`, `submit-e-invoice`, `request-signature` — commit `2d522c7` |
| C8 | 👤 | Faire tourner la clé `sb_secret_…` restée en clair | ⬜ | remplacée par espace réservé en 157 ; **la rotation reste à faire côté Supabase** |
| C9 | 🔴 | **Rapprocher un encaissement « dé-payait » la facture.** `customer_payments.status` n'accepte que `recorded` / `reconciled` / `cancelled`, mais le trigger comptait `IN ('recorded', 'validated')` : `validated` n'existe pas et `reconciled` manquait. Dès que `auto_match_bank_transactions` passait un règlement à `reconciled`, il sortait du total payé. Reproduit sur base réelle : `amount_paid` 1000 → 0, `payment_state` `paid` → `not_paid`, solde client 0 → 1000. | **Corrigé en 169** | `169_fix_payment_reconciled_status.sql` ; régression couverte par `170_payment_reconciliation_tests.sql` |
| C10 | 🔴 | Même défaut côté fournisseur (`update_invoice_on_supplier_payment`), avec en plus une sortie anticipée au lieu d'un raisonnement en variation : corriger la seule liste de statuts aurait fait **décrémenter deux fois** le solde fournisseur au rapprochement. Les deux branches de la fonction appliquaient de surcroît des signes opposés au solde. | **Corrigé en 169** | fonction alignée sur son homologue client (variation seule) ; `170_…` test 3 |
| C11 | 🟠 | Statut fantôme `submitted` sur `purchase_invoices.approval_status` (contrainte : `pending` / `approved` / `rejected`) — présent dans `perform_three_way_match`, dans la clause WHEN de son trigger et dans `run_three_way_match`. | **Corrigé en 169** | branche morte retirée, trigger recréé sur `= 'pending'` |
| C12 | 🔴 | **Aucune sortie de stock n'était comptabilisée.** `create_journal_on_stock_movement` sortait immédiatement si `NEW.unit_cost` était nul — or une sortie n'a pas de coût propre, c'est le stock détenu qui la valorise, et `create_stock_out_on_delivery` insère ses mouvements sans `unit_cost`. La branche `movement_type = 'out'` était donc **inatteignable en pratique** : le compte 310000 n'était jamais crédité. Mesuré : entrées 100 @ 10 puis 100 @ 14, sortie de 50 → stock réel 150 u. à 12 (1 800), **compte 310000 à 2 400**. L'écart grandit à chaque livraison : actif surévalué, charges sous-évaluées. | **Corrigé en 172** | `172_fix_stock_exit_accounting.sql` ; `173_…` tests 2 et 4 |
| C13 | 🟠 | **Ordre de consommation des couches de valorisation indéfini.** `consume_valuation_layers_on_exit` triait sur `CASE WHEN v_method = 'lifo' … CASE WHEN v_method = 'fifo' …` alors que `v_method` vaut `'cump'` : les deux CASE valaient NULL. `created_at` ne départage pas non plus, puisqu'il vaut `NOW()`, figé sur toute la transaction. Observé : une sortie consommait la couche la plus **récente**. | **Corrigé en 172** | colonne `seq` monotone + repli FIFO explicite ; `173_…` test 3 |
| C14 | 🟠 | Les ajustements de stock produisent une écriture de **sens entrée** valorisée sur `quantity`, qui est une quantité **absolue** et non une variation : l'écriture est fausse dès que l'ajustement diminue le stock. Non traité — la 172 laisse les ajustements strictement inchangés pour ne pas aggraver. **Décision attendue.** | ⬜ | `create_journal_on_stock_movement`, branche `adjustment` |

## D — Garde-fous LOT 6 (présents dans la CI, jamais passés au vert)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| D1 | LOT6-01 | `plpgsql_check` vert en CI | ⬜ | | |
| D2 | LOT6-02 | Types Supabase générés, contrôle vert en CI | ⬜ | | |
| D3 | LOT6-03 | Trigger atteignable vert en CI | ⬜ | | |
| D4 | LOT6-04 | Plafond knip / tables inutilisées vert en CI | ⬜ | | |
| D5 | LOT6-05 | Scénarios métier bout en bout verts en CI | ⬜ | | ⚠️ **Le garde-fou ne garde rien.** `src/__tests__/e2e-business-scenarios.test.ts` annonce « 10 parcours » : les variantes « mock » vérifient qu'un tableau écrit en dur a 6 éléments, les variantes « DB » que des tables et des fonctions existent. **Aucune valeur métier n'est calculée ni comparée.** Les vrais parcours sont désormais dans `170_…` (rapprochement) et `173_…` (stock) ; MRP et lettrage restent à écrire. |

## E — Dette LOT 7

| # | Réf | Action | Mesure au 15/09 | État | Date OK | Preuve |
|---|---|---|---|:---:|---|---|
| E1 | LOT7-01 | Supprimer les ~250 exports inutilisés | plafond knip seulement | ⏳ | 18/09 | Plafond **71 → 68**. Voir ci-dessous : l'objectif « supprimer » est le mauvais objectif pour l'essentiel de ces objets. |
| E2 | LOT7-02 | Décider du sort des 27 tables de la migration 127 | — | **OK** | 18/09 15h | Arbitrage rendu : **22 tables vides supprimées** par `164_drop_unused_vague3_tables.sql`, 5 conservées (4 en doublon de `00_schema_dump.sql` et utilisées ; `time_entries` attend la décision sur le sprint gestion de projet). Rejoué deux fois sur `test_compta` : 22/22 puis 0/22. Types régénérés 369 → 347 tables. |
| E3 | LOT7-03 | Borner les requêtes | 293 `select('*')`, 31 `.limit/.range` | **OK** | 17/09 08h40 | Helper `fetchAllRows` (`src/lib/queries/core.ts`), 46 requêtes d'export/agrégat paginées dans 9 fichiers. 12 tests dédiés (`src/lib/__tests__/fetch-all-rows.test.ts`). Voir le détail ci-dessous. |
| E4 | LOT7-04 | Réduire les `any` | 2 717 mesurés le 17/09 | ⏳ | | **2 717 → 2 359** : générateur de types sans `any` (312 → 0, type `Json` + tableaux typés), 46 retours de `queries/*` typés via `Joined<>`. Reste le gros du travail dans les pages. Brancher `createClient<Database>` donnerait **1 468 erreurs**, dont ~917 nullabilités réelles (`string \| null`) : chantier à part, à décider. |
| E5 | LOT7-05 | Un seul jeu de triggers d'équilibre | clos selon l'autre session | **OK** | 15/09 | `158:948` — contrôle d'équilibre unique, vérifié à l'exécution (voir B6) |
| E6 | LOT7-06 | `_skip_cascade` posé mais jamais lu | toujours dans `85_…sql` | **OK** | 15/09 | `160_remove_skip_cascade.sql` réécrit `recalc_parent_progress_on_subtask_change` sans la colonne. La 85 la pose encore mais plus personne ne l'écrit. |
| E7 | LOT7-07 | Accessibilité | 51 attributs `aria-` | **OK** | 18/09 12h40 | **51 → 724**. Voir le détail ci-dessous. |
| E8 | LOT7-08 | Sortir du « mode simulation » | 4 fonctions : transmit-dsn, submit-vat-return, submit-e-invoice, request-signature | **OK** | 15/09 | les 4 renvoient un HTTP 503 explicite au lieu de simuler une transmission réussie. Le raccordement aux API réelles (Net-Entreprises, Chorus Pro) reste un chantier produit. |

### E3 — LOT7-03 en détail (17/09)

**Le défaut.** `app/supabase/config.toml:18` fixe `max_rows = 1000`. PostgREST rabote toute
réponse à 1 000 lignes **sans erreur, sans avertissement, sans en-tête distinctif côté appelant**.
Les `.limit(100000)` posés dans `accounting.ts` (« SOC-04 : limite explicite ») ne changeaient
rien : PostgREST applique toujours le minimum des deux. Conséquence : au-delà de 1 000 lignes,
les écrans affichaient des chiffres faux en se présentant comme complets.

**Le correctif.** Un helper `fetchAllRows` dans `src/lib/queries/core.ts` boucle sur
`.range(from, from+999)` jusqu'à une page incomplète. Il accepte un builder PostgREST
(vérifié dans `node_modules/@supabase/postgrest-js/src/` : `range()` fait `searchParams.set`
et retourne `this`, `then()` déclenche un fetch neuf à chaque `await` — le builder est donc
ré-attendable) ou une fabrique `() => builder`. Plafond de sécurité à 200 000 lignes : au-delà,
il lève, pour forcer le passage à une agrégation SQL plutôt que de saturer le navigateur.

**Tri stable.** La pagination par OFFSET n'est correcte que sur un tri **total** : sans ordre
déterministe, PostgreSQL peut renvoyer les lignes dans un ordre différent d'une page à l'autre
et la pagination saute ou double des lignes. `.order('id')` a donc été ajouté en dernier critère
partout. Vérifié sur la base réelle (`onusuite-audit-pg`) : les **38 tables** concernées ont
une colonne `id uuid` couverte par un index unique mono-colonne — le tri est bien total.

**Ce qui est paginé** (46 requêtes, 9 fichiers) :

| Fichier | Fonctions |
|---|---|
| `accounting.ts` | `getFECData` (export légal), `getDashboardStats`, `getCashFlow`, `getJournalPeriodBalance`, `getAgedBalance`, `getEcheancier`, `getSIGData`, `getAnalyticBalance`, `getGrandLivreTiers`, `getGeneralLedgerFiltered`, `getTrialBalanceFiltered`, `getTreasuryDashboard`, `getTreasuryForecast`, `getBudgetTracking`, `checkBudgetAvailability`, `getFinancialDashboard`, `getFiscalBackups`, `getFECAttestations`, `runAccountingControl` |
| `banking.ts` | `getBankAccounts` |
| `catalogAdvanced.ts` | `getProductGridCombinations` (dont dépend `generateAllCombinations`), `getStockForecastDetailed` |
| `crmAdvanced.ts` | `getSalesPipeline` |
| `leavesAbsences.ts` | `exportLeaveDataToPayroll`, `importExpenseElements` |
| `misc.ts` | `calculateAllDepreciation`, `checkStockAvailability`, `getStockForecast` |
| `pilotage.ts` | `getRevenueSimulation`, `getMarginAnalysis` |
| `production.ts` | `getManufacturingOrders` |
| `socialDeclarations.ts` | `checkDsnAnomalies`, `calculateCice`, `calculateBdesIndicators` |
| `sprintH.ts` | `getRhDashboardData` (8 tables), `getEffectifEvolution`, `getSalaryAnalysis`, `getAbsenceStats`, `getTurnoverRate`, `getCostByCenter` |
| `stock.ts` | `getProducts`, `getBOMs`, `runMRPCalculation` (6 requêtes), `importForecastsFromInvoices`, `autoScheduleMOs`, `getProductDocuments` |

**Conséquences métier les plus graves levées** : l'export FEC (art. A47 A-1 du LPF) pouvait
partir amputé ; la balance générale tronquée ne s'équilibrait plus sans que rien ne l'indique ;
`runAccountingControl` annonçait « aucune anomalie » sur des écritures qu'il n'avait jamais lues ;
la dotation aux amortissements sautait des immobilisations ; le contrôle budgétaire laissait
passer des dépassements ; le MRP recommandait des achats déjà couverts.

**Changement de comportement assumé** : `getEcheancier` avalait ses erreurs
(`if (!error && invoices)`) et rendait une liste vide en cas de panne. Il lève désormais —
conforme au registre des échecs silencieux.

**Preuves** : `npx tsc -b --noEmit` (0 erreur), `npx oxlint --max-warnings=0` (code 0),
`npx vitest run` → **1 302 tests passés**, 38 ignorés, 0 échec (1 290 auparavant + 12 nouveaux),
`npm run build` OK. Les mocks de 5 fichiers de test ont dû être corrigés : leur `range()`
renvoyait une valeur figée à la création du mock, invisible tant que rien n'appelait `.range()`.

**Reste ouvert sur LOT7-03** : les 293 `select('*')` ne sont pas réduits (transfert réseau,
pas exactitude). Les fonctions paginées qui agrègent sur de gros volumes (`getTrialBalanceFiltered`,
`runAccountingControl`, `getSIGData`) gagneraient à passer par un RPC SQL d'agrégation plutôt
que par un rapatriement complet — la pagination corrige l'exactitude, pas le coût.

---

## G — Requêtes refusées par PostgREST (trouvées le 17/09 par `npm run db:embeds`)

> **Comment c'est sorti.** Un PostgREST 16.3 réel a été monté devant la base d'audit, et
> `app/scripts/check-embeds.mjs` y a rejoué **les 1 479 colonnes et ressources jointes
> nommées dans le code** (selects et filtres `.eq()`, `.order()`…). Ces défauts ne se
> voient NI à la compilation — ce sont des chaînes de caractères — NI dans les 1 309 tests
> unitaires, où Supabase est mocké. Chaque requête refusée signifie un écran vide ou une
> erreur pour l'utilisateur.
>
> **19 défauts confirmés. 13 corrigés, 6 en attente d'arbitrage.**

### Corrigés (commit `HEAD`)

| # | Fichier | Défaut | Code | Effet pour l'utilisateur |
|---|---|---|---|---|
| G1 | `leavesAbsences.ts` `getPendingLeaveRequests` | embed `employees` ambigu **+** colonne `manager_id` inexistante | PGRST201 + 42703 | page d'approbation des congés vide |
| G2 | `accounting.ts` `getEcheancier` | `invoices.issue_date` → `date` ; `purchase_invoices.invoice_number`/`invoice_date` → `number`/`date` | 42703 | échéancier client **et** fournisseur vides |
| G3 | `stock.ts` `importForecastsFromInvoices` | filtre sur `invoices.issue_date` | 42703 | aucune prévision jamais importée |
| G4 | `stock.ts` `getProductDocuments` | `invoices.issue_date` ; `manufacturing_orders.planned_date` → `start_date` | 42703 | historique documentaire de l'article vide |
| G5 | `stock.ts` `traceLotDownstream` / `traceLotUpstream` | `stock_movements.lot_number` → `lot_id` | 42703 | traçabilité de lot cassée **dans les deux sens** |
| G6 | `stock.ts` `getOFDocumentAccess` | `users.full_name` → `name` | 42703 | droits documentaires d'OF illisibles |
| G7 | `stock.ts` `getProductEquivalences` | deux embeds `products` sans alias | 42712 | écran des équivalences en erreur |
| G8 | `stock.ts` `getProductSubstitutes` | idem ; `name as sub_name` aliasait la colonne, pas la ressource | 42712 | écran des substituts en erreur |
| G9 | `leavesAbsences.ts` `generateSepaFile` | `employees.iban` → `bank_iban` | 42703 | **fichier SEPA de virement des salaires jamais généré** |
| G10 | `dematRh.ts` `controlBatchBeforeDiffusion` | `pay_slips.period` → `period_start`/`period_end` | 42703 | contrôle avant diffusion des bulletins en échec |
| G11 | `payroll.ts`, `sprintDE.ts`, `sprintH.ts`, `leavesAbsences.ts` | 5 embeds `employees` ambigus (deux clés étrangères : `employee_id` + `approved_by`/`manager_id`) | PGRST201 | congés, notes de frais et statistiques d'absentéisme en erreur |
| G12 | `misc.ts` | `bank_transactions.transaction_date` → `date` | 42703 | rapprochement sur période en erreur |
| G13 | `projectManagement.ts` `getTaskAssignees` | filtre `tenant_id` sur une table qui n'en a pas | 42703 | affectations de tâches vides. **L'isolation est bien assurée** — par la RLS, via `project_tasks.tenant_id` |
| G14 | `crmAdvanced.ts` `checkSlaCompliance` | embed `service_contracts` sans relation | PGRST200 | contrôle de SLA en échec ; le contrat est désormais cherché par `customer_id` |
| G15 | `stock.ts` `getProductSupplierPrices` | embed `suppliers` sans relation | PGRST200 | onglet « Tarifs fournisseurs » vide |

### E7 — LOT7-07 en détail (18/09)

**Le vrai défaut n'était pas le nombre d'attributs, mais leur absence là où ils comptent.**
Dans `src/components/ui.tsx`, les `<label>` de `Input`, `Select` et `Textarea` n'étaient liés
à aucun champ — ni `htmlFor`, ni `id`. Un lecteur d'écran annonçait donc « champ de saisie »
sans dire lequel, **sur tous les formulaires de l'application**. Corrigé avec `useId()`, qui
donne un identifiant stable et distinct même à deux champs de même libellé.

Autres correctifs dans les composants de base, d'où tout l'écran bénéficie :

| Composant | Défaut | Correctif |
|---|---|---|
| `Input`, `Select`, `Textarea` | label non lié au champ | `htmlFor`/`id` via `useId()`, plus `aria-required` |
| `Combobox` | bouton sans nom, état d'ouverture muet | `role="combobox"`, `aria-expanded`, `aria-labelledby` |
| `Modal` | simple `<div>` : le lecteur continue de lire la page derrière | `role="dialog"`, `aria-modal`, `aria-labelledby` |
| `Modal` (fermeture) | bouton croix sans libellé | `aria-label` traduit (`actions.close`) |
| `Button` | aucun moyen de nommer un bouton icône | nouvelle prop `ariaLabel`, qui pose aussi `title` |

L'astérisque des champs requis est passé en `aria-hidden` : `aria-required` porte déjà
l'information, sans faire lire « étoile » à chaque champ.

**127 boutons n'affichant qu'une icône étaient muets**, dans 107 fichiers — 122 d'entre eux
étant le même bouton « fermer ». Tous libellés à partir des clés déjà présentes dans
`common.json` (`actions.close`, `actions.send`, `actions.download`, `actions.more`,
`actions.generate`). Les icônes passent en `aria-hidden` : le nom est porté par le bouton,
il ne doit pas être lu deux fois.

**Un garde-fou faux a d'abord donné un faux résultat.** La première version de
`check-a11y-icon-buttons.mjs` cherchait les boutons avec une expression régulière limitée à
une ligne : elle en voyait 127 sur 378, et annonçait « tous corrigés » alors que les deux
tiers restaient muets. Élargir le motif a produit l'erreur inverse — 251 signalements, dont
des boutons portant une icône **et** du texte, parce qu'un attribut JSX contient souvent un
`>` (`onClick={() => …}`) qui trompe la lecture de la balise. Le contrôle repose désormais sur
un petit analyseur qui suit les accolades et les guillemets : **227 vrais boutons muets**,
tous libellés, zéro faux positif vérifié à la main.

**Navigation au clavier.** `useFocusTrap` existait dans `lib/hooks/accessibility.tsx` mais
n'était branché nulle part — et présentait quatre défauts qui l'auraient rendu inopérant : le
focus n'était jamais rendu à l'élément d'origine ; la liste des éléments focalisables était
figée au montage ; les éléments `disabled` y étaient inclus ; et Échap émettait un
`CustomEvent` que personne n'écoutait. Réparé et branché sur les deux `Modal`.

Un cinquième défaut n'est apparu qu'au test : le filtre de visibilité utilisait
`offsetParent !== null`, qui vaut `null` pour **tout élément en `position: fixed`** — ce que
sont les boîtes de dialogue. Le piège se serait retrouvé sans aucun élément, donc inerte en
production. Seul un test exerçant réellement le clavier pouvait le montrer.

**Les messages n'étaient annoncés à personne.** La zone de toasts n'avait ni `aria-live` ni
`role` : un « Erreur lors de la suppression » passait totalement inaperçu d'un lecteur
d'écran. Elle porte désormais `role="alert"` + `aria-live="assertive"` pour les erreurs,
`role="status"` + `aria-live="polite"` sinon.

**Résultat : 51 → 724 attributs ARIA.** Mais le chiffre compte moins que la vérification :
**16 tests** (`src/components/__tests__/ui-a11y.test.tsx`) exercent les composants comme le
ferait un lecteur d'écran ou un utilisateur au clavier — `getByLabelText`,
`getByRole('dialog')`, `toHaveAccessibleName`, Tab, Shift+Tab, Échap, restitution du focus —
et non la simple présence d'un attribut.

**Garde-fou** : `npm run a11y:icon-buttons`, branché dans le job `lint-typecheck`.

**Tri des tableaux** : l'en-tête était un `<th>` cliquable — le tri était donc **inaccessible
au clavier** (pas de focus, pas d'activation par Entrée ou Espace) et son sens n'était annoncé
à aucun lecteur d'écran. C'est désormais un vrai `<button>`, le `<th>` porte `aria-sort` et
`scope="col"`. 7 tests.

**Contraste** : traité au bloc H — mesuré, pas estimé à l'œil.

---

### E1 — LOT7-01 : pourquoi « supprimer » est le mauvais objectif (18/09)

Le cahier demandait de supprimer les exports inutilisés. En les regardant un par un, la
plupart ne sont pas du déchet : ce sont des **fonctionnalités écrites et jamais branchées**
— le motif déjà relevé par l'audit du 12/09. Les supprimer détruirait du travail ; la vraie
question est « brancher ou supprimer ? », et c'est une décision produit.

**Fait, sans risque :**

| Action | Détail |
|---|---|
| `src/types/database.ts` supprimé | 5 490 lignes. Doublon **périmé** de `database-generated.ts` (294 tables contre 369), produit par un `scripts/gen-types.mjs` qui n'existe plus, et importé nulle part. |
| 4 dépendances retirées | `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities`, `@vitest/mocker` — aucun usage dans `src/`. |
| `tailwindcss` conservé | **Faux positif de knip** : il est chargé par `@import "tailwindcss"` dans `src/index.css`, que knip n'analyse pas. Le retirer aurait cassé tous les styles. Ajouté à `ignoreDependencies`. |
| `playwright` non déclaré | `scripts/take-screenshots.ts` l'importait par dépendance transitive. L'import passe par `@playwright/test`, qui ré-exporte `chromium`. |
| Nullabilité des types corrigée | Le générateur écrivait `col?: T` pour une colonne nullable. PostgREST renvoie **toujours** la propriété, avec `null` — jamais absente. C'est désormais `col: T \| null` dans `Row` (`Insert`/`Update` gardent `?`, où une colonne peut réellement être omise). |

**Branché plutôt que supprimé :** `silentFailureGuard.ts` avait été écrit pour ce projet,
avec son mode d'emploi dans son en-tête, et n'avait jamais été appelé — les rejets de promesse
et les erreurs globales passaient donc inaperçus. `installGlobalRejectionHandler()` est
maintenant appelé dans `main.tsx`. Il reste inerte tant que `VITE_SILENT_FAILURE_GUARD=true`
n'est pas posé, donc sans effet sur la production aujourd'hui.

**Plafond knip : 71 → 68** (31 fichiers, 0 dépendance, 24 exports, 13 types).

### 👤 Décisions attendues — brancher ou supprimer ?

Les 31 fichiers et 24 exports restants sont des fonctionnalités complètes sans écran. Les plus
notables :

| Objet | Ce que c'est | Enjeu |
|---|---|---|
| ~~`queries/admin.ts` : `hasPermission`…~~ | contrôle des droits par rôle | **Traité le 18/09, et le constat de départ était faux.** Voir la section dédiée ci-dessous : la RLS ne regarde PAS le rôle (7 politiques sur 2 296), et la matrice de droits existait en trois exemplaires déjà divergents. |
| `lib/bankParsers.ts` : `parseCfonb120`, `parseBankStatement` | import bancaire CFONB/CAMT | Déjà signalé au volet 2 : les formats ne sont que des libellés d'un `<Select>`. Le code existe. |
| `queries/projectManagementSprint1.ts` | 16 fonctions : suivi du temps, observateurs, modèles de tâches | Un sprint entier livré sans écran. |
| `lib/currencyRates.ts` : `convertAmount`, `fetchRatesFromECB` | conversion multi-devises | Écrit, non branché. |
| `components/employee/Mobile*.tsx` | 3 écrans mobiles salarié | Non routés. |
| `components/documents/*`, `queries/documents.ts` | gestion documentaire | Non routée. |
| `lib/hooks/accessibility.tsx` | aides à l'accessibilité | Non utilisé — alors que le LOT7-07 vient d'en réimplémenter une partie dans `ui.tsx`. |

Rien de tout cela n'a été supprimé. Dites-moi lesquels brancher et lesquels abandonner.

### E1 — contrôle des droits : ce qui a été branché, et ce qui n'est pas protégé (18/09)

**La matrice de droits existait en trois exemplaires.** `queries/misc.ts:1343`
(`hasPermission`), `lib/auth.tsx:332` (`canPerform`, exposé par le contexte mais **appelé par
aucun écran**), et la RPC SQL `has_permission`. Les deux copies TypeScript avaient déjà
divergé : la liste des tables commerciales du rôle `manager` comptait **14 entrées dans
`auth.tsx` contre 34 dans `misc.ts`** — le même utilisateur obtenait deux réponses différentes
selon l'appelant. `canPerform` délègue désormais à l'unique implémentation.

**Ce qui est livré** : un hook `usePermission(table)` et le conditionnement des actions de
création et de suppression sur huit écrans de base (factures, devis, clients, produits,
écritures, salariés, fournisseurs, factures d'achat). 4 tests vérifient ce que voit
l'utilisateur, pas la présence d'un appel.

**🔴 Ce que cela ne fait pas : protéger.** Le cahier partait du principe que « la sécurité
repose entièrement sur la RLS ». Mesuré : **7 politiques sur 2 296 regardent le rôle** — et
elles ne couvrent que `project_members` et `notification_email_queue`. Les 2 289 autres ne
testent que `tenant_id`. Autrement dit, sur 528 des 530 tables, **le rôle d'un utilisateur ne
change rien à ce qu'il peut faire** : un `viewer` peut supprimer une facture par un appel
direct à PostgREST avec son propre jeton. Le filtrage d'interface enlève le bouton ; il
n'enlève pas la capacité. Toute règle qui doit être opposable appartient à une politique ou à
un trigger. **Décision attendue** : généraliser le rôle dans la RLS (chantier à cadrer), ou
assumer que le modèle de rôles est un confort d'affichage et le documenter comme tel.

**🔴 `has_permission` était fausse dans les deux sens** — et c'est elle qui garde la validation
des écritures comptables (`enforce_journal_entry_permissions`, `154:211`) :

| Défaut | Effet démontré sur PostgreSQL |
|---|---|
| jointure `(rp.role_id = tu.custom_role_id OR tu.custom_role_id IS NULL)` — aucun écran ne renseigne `custom_role_id`, la condition est donc toujours vraie | une permission accordée à **un** rôle était accordée à **tous** : `viewer` obtenait `secret.action` |
| symétriquement, tant que `role_permissions` est vide — c'est le cas, aucun écran n'y écrit — seul `admin` passait | **un comptable ne pouvait pas valider une écriture**, ce qui est son métier |
| `tu.status` jamais testé | un utilisateur **révoqué** gardait ses droits |

Corrigé par `165_fix_has_permission.sql`. Les deux premiers comportements ont été rejoués
avant/après sur la base réelle ; **6 scénarios** (`sql/166_permission_tests.sql`) sont branchés
dans le job `db-integration` — admin, comptable, lecteur, révoqué, non-fuite entre rôles,
et attribution effective au porteur du rôle.

---

## H — Contraste des couleurs (WCAG AA) — mesuré le 18/09

Le cahier annonçait « contraste : à vérifier visuellement ». Ce n'est pas vérifiable à
l'œil de façon reproductible : `app/scripts/check-contrast.mjs` (`npm run a11y:contrast`)
calcule les rapports WCAG 2.1 des couleurs de texte **réellement employées dans le code**,
sur le fond réellement appliqué, dans les deux thèmes.

**Écrire ce contrôle juste a demandé trois corrections** — chacune produisait des chiffres
faux, dans un sens ou dans l'autre :

| Biais | Effet |
|---|---|
| ne mesurer que contre les fonds de page | un `text-neutral-50` sur `bg-neutral-900` (bloc de code) ressortait à 1:1 alors qu'il est parfaitement lisible |
| prendre `hover:bg-…` pour le fond permanent | mesure contre un fond qui n'existe qu'au survol |
| prendre `bg-[var(--color-success)]/10` pour la couleur pleine | une couleur mesurée contre elle-même : 1:1, absurde |
| apparier les classes de tout un `className` | dans `ok ? 'bg-A text-blanc' : 'text-B'`, A était apparié à B — deux branches qui ne coexistent jamais |
| découper les littéraux sur les apostrophes | les apostrophes du français (« l'utilisateur ») fusionnaient des littéraux voisins |

**Le défaut principal : le thème sombre ne redéfinissait AUCUNE couleur sémantique.** Il
héritait de valeurs pensées pour un fond blanc, d'où des contrastes de 2,68:1 (primary,
416 usages), 3,27:1 (success) et 3,28:1 (danger) sur fond sombre — très en dessous du seuil.

### Corrigé

Même tonalité, même saturation, seule la luminosité change : l'écart visuel est
imperceptible, sauf mention contraire.

| Thème | Variable | Avant | Après | Contraste | Usages |
|---|---|---|---|---|---|
| sombre | `--color-primary` | `#0066cc` | `#1f8fff` | 2,68 → 4,56:1 | 416 |
| sombre | `--color-danger` | `#de350b` | `#f55c36` | 3,28 → 4,59:1 | 554 |
| sombre | `--color-success` | `#00875a` | `#00a66e` | 3,27 → 4,74:1 | 288 |
| sombre | `--color-neutral-400` | `#6b6d85` | `#8b8da2` | 2,95 → 4,56:1 | 12 |
| clair | `--color-danger` | `#de350b` | `#d4330b` | 4,17 → 4,50:1 | 277 |
| clair | `--color-success` | `#00875a` | `#007d53` | 4,17 → 4,74:1 | 144 |
| clair | `--color-neutral-400` | `#97a0af` | `#667184` | 2,42 → 4,52:1 | 12 |

### 👤 Décision attendue

| # | Cas | Enjeu |
|---|---|---|
| H1 | ~~`--color-warning` `#ff9500` en thème clair : **2,02:1**~~ | **Tranché le 18/09** : second jeton `--color-warning-text` (`#a35f00`, 5,01:1 en clair ; l'orange est conservé en sombre, où il atteint 7,9:1). Les 67 usages ont été classés un par un : **30 colorent du texte** et basculent, **37 colorent une icône** — 22 balises lucide, 8 boutons n'affichant qu'une icône, 6 tables de variantes appliquées à un `<Icon>` — et gardent l'orange de marque, comme les fonds et les bordures. Le changement visible se limite au texte d'alerte. |
| H2 | Texte coloré sur fond de la même teinte à 5–10 % (pastilles d'état) : 3,99 à 4,29:1, 18 usages | Juste sous le seuil. Se corrige en éclaircissant le **fond**, pas le texte — sinon on dégrade le texte sur fond de page, qui est désormais juste. |
| H3 | `--color-text-secondary` sur `--color-neutral-100/200` : 4,06 à 4,50:1, 20 usages | Gris sur gris clair. Même remarque : agir sur le fond. |

Ces 11 écarts sont inscrits dans `app/.contrast-allowlist.json` avec leur référence ; tout
AUTRE écart sous 4,5:1 fait échouer la CI. `npm run a11y:contrast -- --suggest` calcule la
correction la plus proche pour chaque couleur fautive.

---

### 👤 En attente de votre arbitrage — la donnée n'existe pas dans le modèle

**G16 est clos** (18/09) : `employees.gender` ajoutée par `161_employee_gender_bdes.sql`, avec
contrainte `IN ('F','M')`, valeur nulle par défaut, commentaire rappelant la base légale, et un
champ dans le formulaire salarié traduit en trois langues. `calculateBdesIndicators` n'est plus
refusée pour cette colonne — mais elle reste refusée pour `gross_salary` (G17), donc l'écran BDES
ne fonctionnera qu'une fois G17 tranché.

Ces cinq requêtes nomment des colonnes ou des relations **absentes de la base**. Les
corriger suppose une décision produit, puis une migration. Je ne les ai pas devinées.

| # | Fichier | Demandé | Ce qui existe en base | Question |
|---|---|---|---|---|
| G17 | `socialDeclarations.ts:323 et 498` `calculateCice` | `employees.gross_salary` | `salary`, `base_salary` | Le CICE doit-il porter sur `salary` ou `base_salary` ? |
| G18 | `catalogAdvanced.ts:265` | `products.min_stock_level`, `max_stock_level` | `safety_stock`, `min_order_qty` — pas de maximum | `safety_stock` tient-il lieu de minimum ? Faut-il ajouter un stock maximum ? |
| G19 | `stock.ts:707` (MRP) | `purchase_order_lines.quantity_received` | `quantity` seule | **Le MRP ne peut pas déduire le reçu du commandé** : il surestime les en-cours d'achat. Ajouter la colonne et l'alimenter à la réception ? |
| G20 | `accounting.ts:1993` `getBudgetTracking` | relation `budgets` → `chart_accounts` | `budgets.account_code` est du **texte libre**, sans clé étrangère | Poser une clé étrangère sur le code de compte, ou charger les libellés séparément ? |
| G21 | `accounting.ts:2926` `getJournalAccessRights` | relation `journal_access_rights` → `tenant_users` | `user_id` sans clé étrangère vers `tenant_users` | Poser la clé étrangère, ou charger les courriels séparément ? |

### Limites connues de l'outil

`check-embeds.mjs` rattache chaque filtre à sa requête en suivant la variable
(`q = supabase.from('x')` → `q.eq(…)`). Quand la requête est construite dans un callback,
l'attribution peut être fausse : ces cas sont signalés à part, en avertissement, et non
comptés comme des défauts. Deux subsistent aujourd'hui (`misc.ts:2015`, `sprintH.ts:167`),
tous deux vérifiés à la main comme corrects.

**Branché en CI le 18/09** : le job `db-integration` lance désormais un conteneur
`postgrest/postgrest:v16.3` après les migrations et exécute `check-embeds.mjs`.

Les 6 défauts en attente d'arbitrage sont inscrits dans `app/.embeds-allowlist.json`,
chacun avec sa référence (G16 à G21) et la question posée — comme le fait déjà
`.knip-ceiling.json`. Toute AUTRE requête refusée fait échouer la CI : aucune nouvelle
colonne fantôme ne peut plus atteindre la production. La liste nomme chaque défaut
plutôt que d'en compter le nombre, pour qu'un nouveau défaut ne puisse pas passer en
prenant la place d'un corrigé ; et une entrée qui n'est plus refusée est signalée pour
être retirée. Vérifié dans les deux sens : code 0 sur l'état actuel, code 1 dès qu'une
colonne inexistante est introduite.

---

## I — Sécurité des Edge Functions (points signalés au départ, jamais traités)

| # | Sévérité | Constat | État | Preuve |
|---|---|---|:---:|---|
| I1 | 🔴 | **`generate-pdf` : SSRF en lecture via Gotenberg.** La fonction accepte un paramètre `html` **entièrement fourni par le client** et le fait rendre par le Chromium de Gotenberg, puis renvoie le PDF par URL signée. Le contrôle d'accès ne porte que sur le document (`isTenantMember`) : le HTML, lui, n'est pas contraint. **Mesuré le 18/09** sur `gotenberg/gotenberg:8` avec configuration par défaut : un `<iframe src="http://…:8899/secret.txt">` pointant sur un service interne **restitue le contenu de ce service dans le PDF rendu** ; `<img>`, `<link rel=stylesheet>` et `fetch()` atteignent aussi la cible (journal du service : `GET /via-img.png`, `GET /via-link.css`, `GET /secret.txt 200`). `file:///etc/passwd` est bloqué par la liste de refus par défaut. Une cible qui ne répond pas (`169.254.169.254`) bloque la requête jusqu'au délai d'expiration : déni de service à moindres frais. | ⬜ | test reproductible ; contournement vérifié : avec `--chromium-deny-private-ips`, le service interne **ne reçoit plus aucune requête** et le PDF ne contient plus rien |
| I2 | 🟠 | `generate-pdf` n'a **aucun appelant dans l'application** (`grep` sur `src/`) et `GOTENBERG_URL` n'est configuré nulle part — mais la fonction est bien dans la liste de `deploy-all-functions.sh`, déployée avec `--no-verify-jwt`. Elle est donc joignable par tout utilisateur authentifié qui connaît l'URL. Le risque est nul tant qu'aucun Gotenberg n'est branché, et complet le jour où quelqu'un renseigne `GOTENBERG_URL`. | ⬜ | — |
| I3 | 🟠 | `generateDocumentHtml` interpole `doc.number`, `doc.date`, les montants… **sans échappement HTML**. Un numéro de facture contenant `<img src=…>` déclenche le même SSRF sans même passer par le paramètre `html`. | ⬜ | `generate-pdf/index.ts:159-168` |
| I4 | 🟠 | **`ocr-invoice-import` envoie les factures fournisseurs à OpenAI** (`api.openai.com/v1/chat/completions`), appelée depuis `src/lib/ocrInvoice.ts`. Enjeu RGPD : pièces comptables de vos clients traitées par un sous-traitant hors périmètre, sans mention dans la documentation. **Décision produit et juridique attendue**, pas un correctif technique. | 👤 | `ocr-invoice-import/index.ts:43` |

> Trois remèdes possibles pour I1, du plus sûr au plus souple : **(a)** supprimer le paramètre `html` et ne rendre que le HTML généré côté serveur — rien ne casse, la fonction n'a aucun appelant ; **(b)** lancer Gotenberg avec `--chromium-deny-private-ips --chromium-disable-javascript` (vérifié efficace ci-dessus) ; **(c)** filtrer le HTML reçu pour n'autoriser que des ressources `data:`. (a) et (b) se cumulent. À arbitrer.

> À ne pas confondre avec le SSRF des **webhooks sortants**, traité en parallèle par l'autre session (`167_harden_ssrf_webhook_url.sql`, `168_ssrf_bypass_tests.sql`, `src/lib/security/ssrfGuard.ts`) : surface différente, `generate-pdf` n'est pas couverte par ce garde-fou.

---

## F — Actions de votre part

| # | Action | État |
|---|---|:---:|
| F1 | 👤 Faire tourner la clé secrète Supabase (`sb_secret_…`) trouvée en clair dans `setup-pg-cron.sql` | ⬜ |
| F2 | 👤 Pousser la branche pour que la CI tourne (A3, D1 à D5) | ⬜ |

---

## Déjà clos avant le démarrage du suivi

Vérifiés dans le code par l'autre session, et commités dans `057c708` :
LOT0-01 (tri numérique des migrations), LOT1-01 à 05, LOT1-07, LOT2-01 à 06, LOT2-07 (migration 157), LOT2-08 à 14, LOT2-16 à 21, LOT4-01 (report à nouveau), LOT4-06, LOT4-08, LOT4-09, LOT4-10 (à-nouveaux et extournes), LOT4-11, LOT5-04, LOT5-05, LOT5-06, build et tests unitaires.

Au sens du cahier, ces points ne sont définitivement clos qu'après le bloc B (exécution réelle) et le bloc D (CI verte).

---

## Journal

| Heure | Événement |
|---|---|
| 15/09 19h15 | Démarrage du suivi. Session suivie en train de traiter l'option B du lint. Conteneur PostgreSQL d'audit lancé à 19h07. |
| 15/09 19h30 | **A1 OK** (lint à 0). **B2 OK** (plpgsql_check à 0 erreur). Migrations 158+ écrites mais non commitées. |
| 15/09 19h45 | **Session terminée (idle)**. Trois migrations supplémentaires (158-160) testées sur PostgreSQL 16 : schéma + 160 migrations rejouées sans erreur. **B1, B4, B5, B6, B7 OK** (17 tests triggers/17, 358 tables RLS sans fuite). 8 bugs graves trouvés et corrigés en 158-160 (politiques RLS, stock, paie, DSN). **184 fichiers modifiés, rien de commité.** Recommandation : commiter avant que d'autres stash écrasent le travail. |
| 17/09 08h40 | **E3 (LOT7-03) OK** — helper `fetchAllRows`, 46 requêtes d'export et d'agrégat paginées dans 9 fichiers, tri total vérifié sur les 38 tables de la base réelle. 12 tests dédiés ; 1 302 tests au vert ; tsc, oxlint et build verts. Section C corrigée (les correctifs sont en 158, pas 159/160). **E5, E6, E8 passés à OK** après vérification dans le code : ils étaient déjà faits mais restés ⬜. |
| 17/09 13h50 | **Bloc G ouvert.** Un PostgREST réel monté devant la base d'audit révèle **19 requêtes cassées** en production (colonnes fantômes, embeds ambigus, relations absentes) — invisibles à la compilation comme aux tests. **13 corrigées**, 6 en attente d'arbitrage produit. Outil `npm run db:embeds` livré. **LOT7-04 avancé** : 2 717 → 2 359 `any`. |
| 18/09 10h50 | **`ci.yml` était invalide en YAML depuis `057c708`** (4 noms d'étapes avec un `:` non protégé) : GitHub rejetait le workflow, **aucun job de CI n'a jamais tourné** — cela explique A3 et D1 à D5. Corrigé. **Contrôle PostgREST branché** dans `db-integration` avec liste de tolérance nommée (`.embeds-allowlist.json`, G16-G21). |
| 18/09 11h00 | **E7 (LOT7-07) OK** — les `<label>` de `ui.tsx` n'étaient liés à aucun champ : tous les formulaires étaient muets pour un lecteur d'écran. Corrigé via `useId()`, plus `role="dialog"` sur la Modal et 127 boutons icône libellés. 51 → 317 attributs ARIA, 7 tests qui interrogent les composants comme un lecteur d'écran, garde-fou `a11y:icon-buttons` en CI. |
| 18/09 11h10 | **E1 (LOT7-01) avancé** — `src/types/database.ts` (doublon périmé de 5 490 l.) et 4 dépendances supprimés ; `tailwindcss` identifié comme faux positif de knip (le retirer aurait cassé tous les styles) ; nullabilité du générateur corrigée (`T \| null` au lieu de `?`) ; `silentFailureGuard` enfin branché. Plafond knip **71 → 68**. Les 31 fichiers restants sont des fonctionnalités non branchées : **décision produit attendue**, rien n'a été supprimé. |
| 18/09 12h40 | **LOT7-07 complété.** Le garde-fou de la veille était faux : il ne voyait que les boutons mono-ligne (127 sur 378). Réécrit avec un analyseur qui suit les accolades JSX → **227 boutons muets**, tous libellés. `useFocusTrap` réparé (5 défauts, dont un `offsetParent` qui l'aurait rendu inerte sur toute boîte `position: fixed`) et branché. Toasts enfin annoncés (`role="alert"`/`"status"`). **51 → 724 attributs ARIA**, 16 tests clavier et lecteur d'écran. Plafond knip 68 → 67. |
| 18/09 15h30 | **Quatre arbitrages rendus et appliqués.** **H1** : jeton `--color-warning-text` (#a35f00, 5,01:1) pour le texte, l'orange de marque conservé sur fonds, bordures et icônes — 30 usages basculés, 37 laissés en orange après vérification une par une ; `check-contrast.mjs` sait désormais qu'une couleur posée sur une icône lucide n'est pas du texte (36 → 14 faux positifs) et une dispense porte un plafond d'usages. **G16** : colonne `employees.gender` ajoutée (161), avec contrainte, commentaire RGPD et champ dans le formulaire salarié en 3 langues ; l'écran BDES n'est plus refusé par PostgREST. **E2 / LOT7-02** : 22 tables mortes supprimées (162). **E1** : contrôle des droits branché — et **deux défauts trouvés au passage**, voir ci-dessous. |
| 18/09 15h30 | 🔴 **Le rôle ne protège rien : 7 politiques RLS sur 2 296 le regardent.** Le suivi affirmait que « la sécurité repose entièrement sur la RLS » ; c'est faux. Les 2 289 autres politiques ne testent que `tenant_id`. Un `viewer` peut aujourd'hui supprimer une facture par un appel direct à PostgREST : ce n'est pas l'interface qui propose trop, c'est la base qui n'interdit rien. Le filtrage d'interface livré ci-dessus est un confort, pas une protection. **Décision attendue.** |
| 18/09 15h30 | 🔴 **`has_permission` était fausse dans les deux sens** (`120:97`), alors qu'elle garde la validation des écritures (`154:211`). Sa jointure `OR tu.custom_role_id IS NULL` — toujours vraie, aucun écran ne renseignant `custom_role_id` — donnait à **tout le monde** chaque permission accordée à n'importe quel rôle ; et tant que `role_permissions` reste vide, ce qui est le cas, **un comptable ne pouvait pas valider une écriture**. Le statut `revoked` n'était pas regardé non plus. Corrigé par la **165**, avec les deux comportements démontrés avant/après sur PostgreSQL et **6 scénarios** (`166_permission_tests.sql`) branchés dans le job `db-integration`. |
| 18/09 16h30 | **B3 : le garde-fou de triggers ne prouvait rien — réécrit, et il trouve tout de suite trois défauts.** L'ancien script ne lisait qu'un motif et annonçait « OK — 0 triggers validés » sur 394 triggers. Le nouveau couvre toutes les colonnes, les corps de fonctions et les clauses WHEN, dans les cinq formes de comparaison ; il s'auto-teste et **échoue s'il n'a décidé d'aucune comparaison**. Première exécution : **55 comparaisons décidées, 3 défauts**, dont un 🔴 — **rapprocher un encaissement « dé-payait » la facture** (`amount_paid` 1000 → 0, solde client 0 → 1000, reproduit sur la vraie base). Corrigé par la **169**, couvert par **170** (3 scénarios complets, vérifiés non vacants contre l'ancien code), branché dans `db-integration`. Avance **B8-B12** sur le volet rapprochement. |
| 18/09 17h00 | **`i18n-check` réparé** (7 clés `production.json` sans arabe) et **chaîne `db-integration` rejouée intégralement** sur un PostgreSQL 16 neuf : 163 migrations, plpgsql_check 0 erreur, B3, 102, 105, 166, 168, 170 verts, PostgREST 1 473 requêtes acceptées. Un seul contrôle rouge : « types à jour », parce que `database-generated.ts` commité précède la suppression des 22 tables par la 164. **Tests e2e : exécutés le 18/09 à 21h** (via le Chrome du système, `PW_CHANNEL=chrome`). Résultat brut : 52 réussis, 2 échoués, 16 non exécutés, 11,6 min, deux workers tués de force après 300 s. **Les 52 « réussites » ne prouvaient rien** : sans identifiants, l'application reste sur `/login` et les tests de route vérifiaient l'écran de connexion — `phase1.spec.ts` l'assumait en commentaire (« if back on /login, that's OK »). Corrigé : abstention explicite sans identifiants, `assertAuthenticated()` après chaque connexion, `networkidle` remplacé (c'est lui qui bloquait les workers), `.env` chargé par la configuration Playwright. La suite dit maintenant la vérité : **68 abstentions, 2 réussites, 15 s**. Reste à fournir `E2E_TEST_EMAIL` et `E2E_TEST_PASSWORD` — la clé publiable, elle, était déjà là. |
| 18/09 23h00 | **Les tests e2e s'exécutent avec un vrai compte — et trois défauts de plus tombent.** (1) 🔴 `setAuthCookies` posait des cookies `sb-access-token` / `sb-refresh-token` que **supabase-js v2 ne lit pas** : il range la session dans `localStorage` sous `sb-<ref>-auth-token`. `business-flows.spec.ts` ne pouvait donc *structurellement* pas s'authentifier, même avec des identifiants valides. Remplacé par une connexion réelle par le formulaire (`loginViaUI`), et les trois implémentations de connexion dupliquées — toutes bâties sur un `waitForTimeout(5000)` fixe — sont unifiées. (2) 🟠 **Sept des routes visitées par `business-flows.spec.ts` n'existent pas dans `App.tsx`** (`/purchases/receipts`, `/accounting/entries`, `/accounting/lettrage`, `/hr/payroll`, `/production/orders`, `/projects`, `/accounting/journal-entry`) : l'application renvoyait sur `/`. Le fichier ne pouvait pas s'en apercevoir puisqu'il échouait avant. Corrigées contre le routeur réel. (3) 🟠 **L'application affichait la clé i18n brute `common.loading`** à l'utilisateur : `main.tsx` rendait avant que les traductions, chargées de façon asynchrone, ne soient disponibles. `i18nReady` existait et n'était pas attendu. Corrigé — l'écran affiche « Loading… ». Nouveau garde-fou `assertWorkspaceReady()` : un compte sans société est redirigé vers `/onboarding`, et un test qui lit du texte y passerait au vert contre l'assistant de création. |
| 18/09 21h00 | 🔴 **Les tests e2e tournaient enfin — et le troisième garde-fou faussement vert est tombé.** Premier passage réel : 52 réussis, 2 échoués, 16 non exécutés en 11,6 min. Mais les deux échecs et les 52 réussites avaient la même cause : sans `E2E_TEST_PASSWORD`, l'application reste sur `/login`, et les tests de route s'exécutaient contre l'écran de connexion. `phase1.spec.ts` l'assumait noir sur blanc (« If back on /login, that's OK for testing purposes »). `business-flows.spec.ts` échouait au lieu de s'abstenir, seule différence de traitement. Correctifs : abstention explicite et uniforme, `assertAuthenticated()` après chaque connexion pour qu'une authentification cassée se voie, `waitForLoadState('networkidle')` remplacé par `domcontentloaded` — il ne retombait jamais avec les abonnements temps réel et c'est lui qui faisait tuer les workers après 300 s —, chargement du `.env` par la configuration Playwright, et job `e2e-tests` de la CI câblé sur des secrets. La suite passe de **11,6 min de faux vert** à **15 s de vérité** : 68 abstentions, 2 réussites (les tests de la page de connexion, seuls à ne pas exiger d'identifiants). |
| 18/09 18h30 | 🔴 **B8 — aucune sortie de stock n'était comptabilisée.** En écrivant les vrais scénarios de valorisation, le compte 310000 s'est révélé à 2 400 pour un stock qui vaut 1 800 : la branche « sortie » de `create_journal_on_stock_movement` était inatteignable, parce qu'elle exigeait un `unit_cost` que les sorties n'ont pas. L'écart grandissait à chaque livraison. Corrigé par la **172** (valorisation au CUMP détenu, y compris pour les sorties sans entrepôt), avec un second défaut trouvé au passage : l'ordre de consommation des couches était **indéfini** et consommait en fait la plus récente. **4 scénarios** (`173_…`) branchés dans `db-integration`, vérifiés non vacants. Au passage, constat sur **D5** : les « 10 parcours bout en bout » de `e2e-business-scenarios.test.ts` ne vérifient que l'existence de tables et de fonctions — deuxième garde-fou faussement vert après B3. |
| 18/09 17h30 | 🔴 **Bloc I ouvert — SSRF en lecture confirmée sur `generate-pdf`.** Mesuré, pas supposé : un `<iframe>` vers un service interne restitue sa réponse dans le PDF renvoyé à l'appelant. La fonction n'a aucun appelant dans l'application mais reste déployée. Trois remèdes chiffrés, dont un vérifié efficace (`--chromium-deny-private-ips`). **Décision attendue.** Ajouté aussi le volet OCR/OpenAI (I4), qui relève d'un arbitrage juridique. |
| 18/09 13h30 | **Bloc H — contraste mesuré.** Le thème sombre ne redéfinissait aucune couleur sémantique : `primary` était à **2,68:1** sur 416 usages. 7 variables corrigées (écart visuel imperceptible), 3 cas laissés à votre décision dont l'orange d'alerte, seul changement visible. Outil `npm run a11y:contrast` branché en CI. Tri des tableaux rendu accessible au clavier (`aria-sort`, `scope`, vrai `<button>`). 1 332 tests. |
