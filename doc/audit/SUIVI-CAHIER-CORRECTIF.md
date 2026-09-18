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
| B — Validation sur une vraie base PostgreSQL | 12 | 5 | 7 |
| C — Front et bugs trouvés à l'exécution | 8 | 0 | 8 |
| D — Garde-fous LOT 6 au vert | 5 | 0 | 5 |
| E — Dette LOT 7 | 8 | 5 | 3 |
| F — Actions de votre part | 2 | 0 | 2 |
| G — Requêtes refusées par PostgREST | 21 | 15 | 6 |
| **Total** | **59** | **27** | **32** |

---

## A — Chaîne de livraison (LOT 0)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| A1 | LOT0-02 | Lint à 0 avertissement (87 restants, option B : corriger les ~8 cas réels et marquer les chargements au montage) | **OK** | 15/09 19h30 | `npx oxlint --max-warnings=0` → code 0 (commande de la CI, `ci.yml:48`) |
| A2 | — | Commiter + pousser (≈ 184 fichiers modifiés, 3 migrations 158-160 non commitées) | ⬜ | | |
| A3 | LOT0-02 | Les 5 jobs de la CI passent au vert (nécessite un push) | ⬜ | | **Cause trouvée le 18/09** : `ci.yml` était **invalide en YAML** depuis `057c708` — 4 noms d'étapes contenaient un `:` non protégé (`- name: UX-03 : No window.confirm`). GitHub rejetait le workflow entier : aucun job n'a jamais pu tourner, ce qui explique A3 et D1 à D5. Corrigé, `yaml.safe_load` passe. |

## B — Validation sur une vraie base

Le conteneur Docker `onusuite-audit-pg` (base `test_compta`) tourne depuis 19h07 : 302 fonctions et 392 triggers chargés.

| # | Réf | Action / critère de recette | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| B1 | LOT0-01 | Schéma + migrations 74 à 160 rejouées en ordre numérique, sans erreur | **OK** | 15/09 19h45 | « 158 migrations passent sur un PostgreSQL 16 neuf, avec 0 erreur plpgsql_check » (migrations 158-160 écrites et testées, non commitées). Les migrations 99-160 étaient cassées, 158-160 les corrigent. |
| B2 | LOT2-\*, LOT3-\* | `sql/ci/check_plpgsql.sql` = 0 erreur | **OK** | 15/09 19h30 | confirmé post-158 |
| B3 | LOT6-03 / LOT1-01 | Triggers n'ont jamais été validés (faux vert) | ⏳ | | Le script doit être reécrit pour tester réellement. |
| B4 | LOT0-03 | `102_trigger_tests.sql` : 17 tests de déclencheurs sur 17 | **OK** | 15/09 19h45 | exécuté sur `test_compta`, tous passent |
| B5 | LOT0-04 | `105_rls_tests.sql` : aucune fuite entre sociétés, 358 tables | **OK** | 15/09 19h45 | exécuté sur `test_compta`, toutes les tables testées sans fuite |
| B6 | LOT2-05 | Contrôle d'équilibre : le brouillard peut être déséquilibré, la validation non | **OK** | 15/09 19h45 | testé à l'exécution |
| B7 | LOT1-01 | `validation_status='validated'` produit une écriture `VT` | **OK** | 15/09 19h45 | confirmé fonctionnel |
| B8 à B12 | LOT4-03, 04, 05, 06, 07, 09, 11, 12 | Valeurs métier : stock, MRP, lettrage, rapprochement | ⏳ | | testés unitairement, à confirmer en scénarios complets |

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

## D — Garde-fous LOT 6 (présents dans la CI, jamais passés au vert)

| # | Réf | Action | État | Date OK | Preuve |
|---|---|---|:---:|---|---|
| D1 | LOT6-01 | `plpgsql_check` vert en CI | ⬜ | | |
| D2 | LOT6-02 | Types Supabase générés, contrôle vert en CI | ⬜ | | |
| D3 | LOT6-03 | Trigger atteignable vert en CI | ⬜ | | |
| D4 | LOT6-04 | Plafond knip / tables inutilisées vert en CI | ⬜ | | |
| D5 | LOT6-05 | Scénarios métier bout en bout verts en CI | ⬜ | | |

## E — Dette LOT 7

| # | Réf | Action | Mesure au 15/09 | État | Date OK | Preuve |
|---|---|---|---|:---:|---|---|
| E1 | LOT7-01 | Supprimer les ~250 exports inutilisés | plafond knip seulement | ⬜ | | |
| E2 | LOT7-02 | Décider du sort des 27 tables de la migration 127 | — | ⬜ | | |
| E3 | LOT7-03 | Borner les requêtes | 293 `select('*')`, 31 `.limit/.range` | **OK** | 17/09 08h40 | Helper `fetchAllRows` (`src/lib/queries/core.ts`), 46 requêtes d'export/agrégat paginées dans 9 fichiers. 12 tests dédiés (`src/lib/__tests__/fetch-all-rows.test.ts`). Voir le détail ci-dessous. |
| E4 | LOT7-04 | Réduire les `any` | 2 717 mesurés le 17/09 | ⏳ | | **2 717 → 2 359** : générateur de types sans `any` (312 → 0, type `Json` + tableaux typés), 46 retours de `queries/*` typés via `Joined<>`. Reste le gros du travail dans les pages. Brancher `createClient<Database>` donnerait **1 468 erreurs**, dont ~917 nullabilités réelles (`string \| null`) : chantier à part, à décider. |
| E5 | LOT7-05 | Un seul jeu de triggers d'équilibre | clos selon l'autre session | **OK** | 15/09 | `158:948` — contrôle d'équilibre unique, vérifié à l'exécution (voir B6) |
| E6 | LOT7-06 | `_skip_cascade` posé mais jamais lu | toujours dans `85_…sql` | **OK** | 15/09 | `160_remove_skip_cascade.sql` réécrit `recalc_parent_progress_on_subtask_change` sans la colonne. La 85 la pose encore mais plus personne ne l'écrit. |
| E7 | LOT7-07 | Accessibilité | 51 attributs `aria-` | **OK** | 18/09 11h00 | **51 → 317**. Voir le détail ci-dessous. |
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

**Résultat : 51 → 317 attributs ARIA.** Mais le chiffre compte moins que la vérification :
**7 tests** (`src/components/__tests__/ui-a11y.test.tsx`) interrogent les composants comme le
ferait un lecteur d'écran — `getByLabelText`, `getByRole('dialog')`, `toHaveAccessibleName` —
et non la simple présence d'un attribut.

**Garde-fou** : `npm run a11y:icon-buttons` échoue si un bouton icône sans libellé réapparaît.
Branché dans le job `lint-typecheck` de la CI.

**Reste à faire sur l'accessibilité** : navigation au clavier dans la `Modal` (piège de focus,
fermeture par Échap, restitution du focus à la fermeture), contraste des couleurs, et
`SortableTable` (`aria-sort` sur les en-têtes triables). Ces points demandent des essais
manuels au clavier, pas seulement une analyse statique.

---

### 👤 En attente de votre arbitrage — la donnée n'existe pas dans le modèle

Ces six requêtes nomment des colonnes ou des relations **absentes de la base**. Les
corriger suppose une décision produit, puis une migration. Je ne les ai pas devinées.

| # | Fichier | Demandé | Ce qui existe en base | Question |
|---|---|---|---|---|
| G16 | `socialDeclarations.ts:498` `calculateBdesIndicators` | `employees.gender` | aucune colonne de sexe | L'**indicateur d'égalité F/H et l'écart de rémunération sont impossibles à calculer**. Ajouter la colonne (avec les précautions RGPD qui s'imposent) ou retirer ces deux indicateurs de la BDES ? |
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
