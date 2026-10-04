# Plan de perfection Onusuite — atteindre 9,5/10 sur chaque module

> **Version** 1.0 — 10 septembre 2026
> **Périmètre** branche `commercial-hr-paie`, commit `31b79bd`
> **Base** volet 1 (noyau comptable & paie) et volet 2 (modules d'exploitation) de la revue du 9 septembre 2026
> **Note de départ** 5,8/10 — **note cible** 9,5/10 sur les 20 axes

---

## Table des matières

- [0. Mode d'emploi](#0-mode-demploi)
- [1. Socle transverse — `SOC`](#1-socle-transverse--soc)
- [2. Comptabilité — `ACC`](#2-comptabilité--acc)
- [3. Paie — `PAY`](#3-paie--pay)
- [4. Ressources humaines — `RH`](#4-ressources-humaines--rh)
- [5. Stock — `STK`](#5-stock--stk)
- [6. Production — `PRD`](#6-production--prd)
- [7. Achats — `ACH`](#7-achats--ach)
- [8. Ventes — `VTE`](#8-ventes--vte)
- [9. Banque — `BNQ`](#9-banque--bnq)
- [10. Trésorerie — `TRE`](#10-trésorerie--tre)
- [11. Point de vente — `POS`](#11-point-de-vente--pos)
- [12. CRM — `CRM`](#12-crm--crm)
- [13. Gestion de projet — `PRJ`](#13-gestion-de-projet--prj)
- [14. Reporting & BI — `BI`](#14-reporting--bi--bi)
- [15. Couche de données — `DAT`](#15-couche-de-données--dat)
- [16. Sécurité — `SEC`](#16-sécurité--sec)
- [17. Performance — `PRF`](#17-performance--prf)
- [18. Qualité & tests — `QUA`](#18-qualité--tests--qua)
- [19. Ergonomie, i18n, accessibilité — `UX`](#19-ergonomie-i18n-accessibilité--ux)
- [20. Conformité réglementaire — `CNF`](#20-conformité-réglementaire--cnf)
- [21. Paramétrage & administration — `ADM`](#21-paramétrage--administration--adm)
- [22. Import & reprise de données — `IMP`](#22-import--reprise-de-données--imp)
- [23. API publique, webhooks, intégrations — `API`](#23-api-publique-webhooks-intégrations--api)
- [24. Notifications — `NOT`](#24-notifications--not)
- [25. Documents & dématérialisation — `GED`](#25-documents--dématérialisation--ged)
- [26. Portail salarié & mobile — `PTL`](#26-portail-salarié--mobile--ptl)
- [27. Multi-société & consolidation — `GRP`](#27-multi-société--consolidation--grp)
- [28. Inscription & mise en service — `ONB`](#28-inscription--mise-en-service--onb)
- [29. Séquencement en vagues](#29-séquencement-en-vagues)
- [30. Tableau de bord de suivi](#30-tableau-de-bord-de-suivi)

> **Couverture.** Les 30 sections couvrent les 337 routes de l'application. Le tableau de correspondance route → chantier figure en [annexe B](#annexe-b--couverture-route-par-route).

---

## 0. Mode d'emploi

### 0.1 Ce que signifie « 9,5 »

Le barème de ce document est volontairement dur. Une fonctionnalité présente à l'écran ne vaut aucun point. Un chantier n'atteint 9,5 que si les **quatre** conditions suivantes sont réunies :

| # | Condition | Pourquoi |
|---|---|---|
| 1 | **Parité de mécanisme** avec le leader (Sage 100, Sage Paie, Odoo 17…), pas seulement de vocabulaire | Un écran « Lettrage » qui ne lettre pas ne vaut rien |
| 2 | **Aucun défaut de correction connu** — le calcul donne le bon résultat sur les cas limites | Un CUMP faux est pire qu'un CUMP absent : il inspire confiance |
| 3 | **Couvert par un test automatisé qui s'exécute en CI** — et qui échouerait si on cassait le mécanisme | Sans cela, la parité d'aujourd'hui est perdue dans trois mois |
| 4 | **Tient la charge d'un dossier réel** — 3 exercices, 100 000 écritures, 5 000 articles, 200 salariés | La correction sans l'échelle ne sert à rien en production |

Le 10/10 est réservé aux points où Onusuite **dépasse** le leader. Il en existe déjà : les invariants comptables garantis par la base de données, que la plupart des concurrents SaaS posent en couche applicative où ils se contournent.

### 0.2 Convention de lecture

Chaque chantier est présenté ainsi :

> **`XXX-nn` — Titre**
> **Note actuelle → cible.** Impact et criticité.
> **État actuel** — le constat, avec la preuve (`fichier:ligne`).
> **Actions** — le détail de ce qu'il faut faire.
> **Critère d'acceptation** — le test qui prouve que c'est fait. S'il ne peut pas s'écrire, le chantier est mal défini.

### 0.3 Règle d'or du séquencement

**Ne jamais construire au-dessus d'un socle défaillant.** Cinq bloquants du socle (`SOC-01` à `SOC-05`) invalident le travail fait par-dessus : tant que la validation d'une facture lève une exception en base, ajouter des fonctionnalités comptables produit du code qui n'a jamais tourné. La vague 0 n'est pas négociable.

### 0.4 Chiffres de référence au 10 septembre 2026

| Mesure | Valeur |
|---|---|
| Lignes TypeScript/TSX | 112 970 |
| Lignes SQL | 37 360 (109 migrations) |
| Tables | 512 |
| Triggers | 323 |
| Fonctions PL/pgSQL | 218 |
| Politiques RLS | 2 208 |
| Index | 1 075 |
| Clés étrangères | 601 |
| Routes React | 337 |
| Pages | 219 |
| Fonctions de requête | 1 152 (dont 29 avec `.limit()`) |
| Edge functions | 21 (dont 4 en « mode simulation ») |
| Tests unitaires | 1 226 verts en 4,65 s (Supabase mocké) |
| Tests E2E | 3 specs Playwright |
| Occurrences de `any` | 1 884 |
| `window.confirm()` | 127 |
| Attributs `aria-*` | 47 |

---

## 1. Socle transverse — `SOC`

Ces neuf chantiers conditionnent tous les autres. Ils ne portent aucune valeur métier visible et doivent pourtant passer en premier.

---

### `SOC-01` — Le motif « écriture validée avant ses lignes »

**Bloquant absolu. Cinq triggers concernés.**

**État actuel.** `76_accounting_invariants_and_stock_rpcs.sql:65` installe `prevent_posted_line_modification` en `BEFORE INSERT OR UPDATE OR DELETE` sur `journal_lines`. La fonction lève une exception dès que l'écriture parente est au statut `posted` — y compris à l'insertion.

Cinq fonctions insèrent pourtant l'en-tête directement en `'posted'` puis ajoutent ses lignes :

| Trigger | Fichier | Ligne | Conséquence si non corrigé |
|---|---|---|---|
| `create_journal_invoice` | `90_missing_workflow_triggers.sql` | 176 | Valider une facture de vente échoue |
| `create_journal_purchase_invoice` | `90_missing_workflow_triggers.sql` | 202 | Valider une facture d'achat échoue |
| `create_journal_customer_payment` | `90_missing_workflow_triggers.sql` | 224 | Saisir un encaissement échoue |
| `create_journal_supplier_payment` | `90_missing_workflow_triggers.sql` | 244 | Saisir un décaissement échoue |
| `create_journal_on_stock_movement` | `87_stock_valuation_to_gl.sql` | 194 | **Toute insertion de mouvement de stock échoue** |

Le dernier est le plus large : réceptions, livraisons, inventaires, production, transferts — tout le flux physique.

`seed_demo_data.sql` est frappé de la même façon (lignes 1252, 1262, 1273, 1413, 1423).

Le motif correct existe déjà dans le dépôt : `trg_payroll_create_journal` en `81_complete_workflow_triggers.sql:337` insère en `'draft'` puis bascule.

**Actions.**

1. Créer la migration `95_fix_posted_before_lines.sql`.
2. Dans chacune des cinq fonctions, remplacer le littéral `'posted'` de l'`INSERT INTO journal_entries` par `'draft'`.
3. Après le dernier `INSERT INTO journal_lines`, ajouter :
   ```sql
   UPDATE journal_entries SET status = 'posted'
   WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
   ```
4. Vérifier que `prevent_posted_entry_modification` (le trigger sur `journal_entries`, `BEFORE UPDATE`) n'interdit pas ce passage : il teste `OLD.status = 'posted'`, or `OLD.status` vaut `'draft'` ici. Le passage est autorisé. **Ne pas modifier ce trigger.**
5. Corriger `seed_demo_data.sql` sur le même motif.
6. Établir la règle dans `CLAUDE.md` : *toute écriture comptable se crée en `draft`, se remplit, puis se valide. Jamais l'inverse.*

**Critère d'acceptation.**
```sql
-- doit passer sans exception
INSERT INTO invoices (...) VALUES (...);
UPDATE invoices SET status = 'validated' WHERE id = ...;
SELECT count(*) FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
 WHERE je.invoice_ref = '...';   -- = 3
```
Idem pour `stock_movements`, `customer_payments`, `supplier_payments`, `purchase_invoices`. À écrire dans `88_trigger_tests.sql` et à exécuter en CI (voir `SOC-02`).

---

### `SOC-02` — Tests d'intégration base de données en CI

**Bloquant. C'est l'absence de ce chantier qui a laissé passer `SOC-01`.**

**État actuel.** 1 226 tests s'exécutent en 4,65 secondes. Cette vitesse prouve qu'aucun ne touche Postgres : 19 fichiers de test appellent `vi.mock` sur Supabase. Sur les assertions, 923 vérifient qu'un mock a été appelé contre 865 qui vérifient une valeur.

Conséquence directe : **323 triggers, 218 fonctions PL/pgSQL et 2 208 politiques RLS ne sont couverts par aucun test exécuté.** Le fichier `88_trigger_tests.sql` existe mais n'est branché sur rien.

**Actions.**

1. Ajouter un job `db-integration` au workflow `ci.yml` :
   ```yaml
   db-integration:
     runs-on: ubuntu-latest
     services:
       postgres:
         image: postgres:16
         env:
           POSTGRES_PASSWORD: postgres
         options: >-
           --health-cmd pg_isready --health-interval 10s
           --health-timeout 5s --health-retries 5
         ports: ['5432:5432']
     steps:
       - uses: actions/checkout@v4
       - name: Charger le schéma
         run: |
           psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f app/sql/00_schema_dump.sql
           node app/run-sql-migrations.mjs
         env:
           DATABASE_URL: postgresql://postgres:postgres@localhost:5432/postgres
       - name: Tests de triggers
         run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f app/sql/88_trigger_tests.sql
   ```
2. Étendre `88_trigger_tests.sql` pour couvrir, au minimum, un scénario par trigger métier — soit 22 scénarios pour la migration 90, plus ceux des migrations 81, 85, 87, 89.
3. Ajouter un fichier `96_rls_tests.sql` : créer deux tenants, insérer des données dans chacun, se placer successivement dans le rôle de chaque tenant via `set_config('request.headers', ...)`, et vérifier que chaque `SELECT` ne remonte que ses propres lignes. Une table oubliée doit faire échouer la CI.
4. Faire échouer le job si une seule assertion tombe.

**Critère d'acceptation.** Le job `db-integration` est vert, et l'introduction volontaire d'un défaut (par exemple retirer `tenant_id = current_tenant_id()` d'une politique) le fait passer au rouge.

---

### `SOC-03` — TypeScript en mode strict

**État actuel.** `tsconfig.app.json` ne contient aucune directive `strict`, et aucun fichier n'en hérite (`tsconfig.json` n'a que des `references`). `strictNullChecks` et `noImplicitAny` sont donc inactifs, avec 1 884 `any` explicites. Paradoxalement, les réglages exigeants voisins sont activés (`noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`) : l'omission ressemble à un oubli.

Pour une application qui manipule des montants, c'est le filet de sécurité le moins cher qui n'est pas tendu.

**Actions.** Procéder par cercles concentriques, du cœur vers la périphérie :

1. **Cercle 1 — `src/lib/`** (calculs). Créer `src/lib/tsconfig.json` avec `"strict": true`, corriger, verrouiller. Priorité absolue à `payroll.ts`, `taxCalculator.ts`, `sepa.ts`, `utils.ts`.
2. **Cercle 2 — `src/lib/queries/`**. Le gros du travail : 1 152 fonctions. Remplacer les `as any[]` de retour par des types réels dérivés de `src/types/database.ts`.
3. **Cercle 3 — `src/types/`** et `src/hooks/`.
4. **Cercle 4 — `src/components/`** puis `src/pages/`.
5. Une fois les quatre cercles verts, hisser `"strict": true` dans `tsconfig.app.json` et supprimer les configurations locales.
6. Interdire `any` par une règle oxlint (`no-explicit-any` en `error`), avec dérogation explicite et commentée là où c'est inévitable.

**Piège à connaître.** Activer `strictNullChecks` fera apparaître des centaines d'erreurs sur les retours Supabase, qui sont tous `T | null`. C'est précisément le but : chaque erreur signale un endroit où l'application suppose une donnée présente sans le vérifier.

**Critère d'acceptation.** `npx tsc -b --noEmit` passe avec `"strict": true` dans `tsconfig.app.json`, et `grep -c ': any' src/lib` retourne 0.

---

### `SOC-04` — Agrégations financières côté serveur

**Bloquant. Risque de résultat faux affiché sans erreur.**

**État actuel.** `getTrialBalance()` (`accounting.ts:243`), `getTrialBalanceFiltered()` (`:1625`), `getBalanceSheet()` (`:482`) et `getGeneralLedger()` (`:217`) exécutent un `select` sur `journal_lines` **sans `limit`**, puis somment dans une `Map` JavaScript.

Deux modes de défaillance distincts :

- **Truncation silencieuse.** Si PostgREST applique une borne de lignes, la balance est calculée sur un sous-ensemble et affiche un total faux, sans aucune erreur. C'est le pire mode de défaillance possible pour un logiciel comptable.
- **Effondrement.** Un dossier PME sur trois exercices dépasse aisément 100 000 lignes. L'onglet ne tient pas.

À l'échelle du dépôt : 29 `.limit()` pour 1 152 fonctions de requête, et 291 `select('*')` sans borne.

**Actions.**

1. Créer `97_financial_aggregations.sql` avec quatre RPC, toutes paramétrées par exercice :

   ```sql
   CREATE OR REPLACE FUNCTION get_trial_balance(
     p_fiscal_year_id uuid,
     p_date_from date DEFAULT NULL,
     p_date_to   date DEFAULT NULL,
     p_journal_code text DEFAULT NULL
   )
   RETURNS TABLE(
     account_code text, account_name text,
     opening_debit numeric, opening_credit numeric,
     period_debit numeric,  period_credit numeric,
     closing_debit numeric, closing_credit numeric
   )
   LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
   AS $$
     WITH bornes AS (
       SELECT start_date, end_date FROM fiscal_years
       WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
     ),
     mouvements AS (
       SELECT
         COALESCE(jl.account_general, jl.account_code) AS code,
         jl.account_name,
         -- à-nouveaux : tout ce qui précède l'ouverture de l'exercice
         SUM(CASE WHEN je.date < b.start_date THEN jl.debit  ELSE 0 END) AS o_d,
         SUM(CASE WHEN je.date < b.start_date THEN jl.credit ELSE 0 END) AS o_c,
         -- mouvements de la période demandée, bornée par l'exercice
         SUM(CASE WHEN je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
                   AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
                  THEN jl.debit ELSE 0 END) AS p_d,
         SUM(CASE WHEN je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
                   AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
                  THEN jl.credit ELSE 0 END) AS p_c
       FROM journal_lines jl
       JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
       CROSS JOIN bornes b
       WHERE jl.tenant_id = current_tenant_id()
         AND je.status = 'posted'
         AND je.date <= b.end_date
         AND (p_journal_code IS NULL OR je.journal_code = p_journal_code)
       GROUP BY 1, 2
     )
     SELECT code, account_name,
            o_d, o_c, p_d, p_c,
            GREATEST(o_d + p_d - o_c - p_c, 0),
            GREATEST(o_c + p_c - o_d - p_d, 0)
     FROM mouvements
     ORDER BY code;
   $$;
   ```

2. Même approche pour `get_balance_sheet`, `get_income_statement` et `get_general_ledger` — cette dernière avec `p_limit` / `p_offset` et un `count` total séparé.
3. Index de couverture indispensable :
   ```sql
   CREATE INDEX IF NOT EXISTS idx_jl_tenant_account_journal
     ON journal_lines (tenant_id, account_general, journal_id)
     INCLUDE (debit, credit);
   CREATE INDEX IF NOT EXISTS idx_je_tenant_date_status
     ON journal_entries (tenant_id, date, status)
     INCLUDE (journal_code);
   ```
4. Réécrire les quatre fonctions TypeScript en simples `supabase.rpc(...)`.
5. **Rendre `p_fiscal_year_id` obligatoire** : c'est ce qui règle simultanément le problème de volumétrie et celui, plus grave, du bilan cumulé depuis l'origine (`ACC-05`).

**Critère d'acceptation.** Sur un jeu de 200 000 lignes d'écriture, `get_trial_balance` répond en moins de 400 ms, et la somme des débits est égale à la somme des crédits au centime près.

---

### `SOC-05` — Le motif « table présente, jamais branchée »

**Ce défaut structurel revient dans six modules.** Il produit une application qui semble complète à la démonstration et vide à l'usage.

| Objet en base | Écran de saisie | Jamais utilisé par | Chantier |
|---|---|---|---|
| `journal_lines.account_tiers` | — | les triggers de comptabilisation | `ACC-02` |
| `journal_lines.vat_code` | — | les triggers, la CA3 | `ACC-03` |
| `price_lists` / `price_list_lines` | oui | la saisie de devis, commande, facture | `VTE-01` |
| `customers.credit_limit` / `credit_used` | oui | aucun contrôle à la commande | `VTE-02` |
| `bank_reconciliation_rules` | oui | `auto_reconcile_bank_transaction` | `BNQ-02` |
| `production_forecasts` | oui | `runMRPCalculation` | `PRD-03` |
| `nf525_event_log` | — | les événements de caisse | `POS-03` |
| `product_serial_numbers` / `product_batches` | oui | `stock_movements` | `STK-06` |

**Action de fond.** Ajouter au workflow CI un contrôle de « tables orphelines » : pour chaque table métier, vérifier qu'elle est lue par au moins une fonction de requête **et** écrite par au moins un chemin applicatif. Un script Node de 60 lignes qui croise `information_schema.tables` avec un `grep` sur `src/lib/queries/` suffit à empêcher la récidive.

**Critère d'acceptation.** Le script `scripts/check-orphan-tables.mjs` s'exécute en CI et liste zéro table métier non consommée.

---

### `SOC-06` — Numéros de migration en doublon

**État actuel.** Six collisions : 38, 44, 71, 87, 88, 89. Dont `87_critical_business_functions.sql` face à `87_stock_valuation_to_gl.sql`, et `88_high_priority_business_functions.sql` face à `88_trigger_tests.sql`. Le runner (`run-sql-migrations.mjs:98`) avertit mais applique quand même, dans l'ordre lexicographique du nom complet. L'ordre d'exécution dépend donc de la première lettre après le numéro — fragile pour des migrations qui se recouvrent.

**Actions.**

1. Renuméroter les doublons dans l'ordre chronologique réel (git log de leur création).
2. Ajouter au runner un `process.exit(1)` sur doublon détecté, au lieu du simple `console.warn`.
3. Adopter une convention horodatée pour les nouvelles migrations : `YYYYMMDDHHMM_description.sql`, comme le fait Supabase CLI. Elle rend les collisions impossibles.

**Critère d'acceptation.** `node run-sql-migrations.mjs --dry-run` sort en code 0 et n'émet aucun avertissement de doublon.

---

### `SOC-07` — Découper les fichiers monstres

**État actuel.**

| Fichier | Lignes | Problème |
|---|---|---|
| `src/types/database.ts` | 5 490 | généré — acceptable |
| `src/types/index.ts` | 4 236 | tous les types métier dans un seul fichier |
| `src/lib/queries/accounting.ts` | 3 943 | 20+ domaines mélangés |
| `src/lib/queries/misc.ts` | 2 680 | fourre-tout, nom sans signification |
| `src/components/Sidebar.tsx` | 1 603 | la configuration de navigation entière |

Un fichier de 3 943 lignes rend le `git blame` inutilisable, allonge chaque revue et provoque des conflits de fusion systématiques.

**Actions.**

1. Éclater `accounting.ts` par domaine : `chartOfAccounts.ts`, `journalEntries.ts`, `financialStatements.ts`, `vat.ts`, `fiscalYears.ts`, `fixedAssets.ts`, `analytics.ts`, `lettrage.ts`. Conserver un `accounting.ts` de ré-export pour ne rien casser.
2. Vider `misc.ts` : chaque fonction rejoint son domaine. Le fichier doit disparaître.
3. Extraire la configuration de navigation de `Sidebar.tsx` vers `src/config/navigation.ts` — c'est de la donnée, pas de la présentation.
4. Découper `src/types/index.ts` par domaine, en miroir de `src/lib/queries/`.
5. Ajouter une règle oxlint `max-lines` à 600, avec dérogation pour les fichiers générés.

**Critère d'acceptation.** Aucun fichier non généré de `src/` ne dépasse 600 lignes.

---

### `SOC-08` — Nettoyage du dépôt

**État actuel.** Six fichiers `.bak` et `.bak2` dans `src/lib/__tests__/` dupliquent des suites entières (`phase6-queries`, `production-queries`, `queries`, `sprint-queries`). Ils ne sont pas exécutés par vitest mais faussent tout comptage et polluent les recherches.

**Actions.**

1. `git rm` les six fichiers.
2. Ajouter `*.bak`, `*.bak2`, `*.orig` au `.gitignore`.
3. Supprimer les 5 `TODO`/`FIXME` restants de `src/` — soit en les traitant, soit en les convertissant en tickets.

**Critère d'acceptation.** `find src -name '*.bak*'` ne retourne rien.

---

### `SOC-09` — Gestion d'erreur uniforme

**État actuel.** 68 blocs `catch {}` vides ou réduits à un commentaire, 269 `console.error`, 2 `ErrorBoundary` pour 219 pages, et Sentry référencé dans 3 fichiers seulement.

Un `catch { /* best-effort */ }` dans un chemin comptable — il y en a dans `generatePaySlipsForRun` (`queries/payroll.ts:301`, `:312`) — signifie qu'une écriture de paie peut échouer silencieusement.

**Actions.**

1. Classer chaque `catch` vide en trois catégories :
   - **Tolérable** (lecture d'un cache, `sessionStorage`) → conserver, mais commenter la raison.
   - **À remonter** → `toast('error', …)` plus `captureException`.
   - **À propager** → retirer le `catch`, laisser l'appelant décider.
   Les 12 `catch` des chemins comptables et de paie sont tous dans la troisième catégorie.
2. Envelopper chaque route dans un `ErrorBoundary` de module, plutôt qu'un seul global : une erreur dans le Gantt ne doit pas vider l'écran de saisie comptable.
3. Brancher Sentry sur `main.tsx` avec `beforeSend` filtrant les données personnelles, et corréler par `tenant_id`.
4. Remplacer les `console.error` par un logger unique (`src/lib/logger.ts`) qui route vers la console en développement et vers Sentry en production.

**Critère d'acceptation.** Zéro `catch` vide dans `src/lib/queries/accounting.ts`, `payroll.ts` et `stock.ts` ; taux d'erreurs non capturées mesurable dans Sentry.

---

## 2. Comptabilité — `ACC`

**5,0 → 9,5.** La structure de `journal_lines` est de facture Sage — `account_general`, `account_tiers`, `lettrage_code`, `analytic_section_id`, `vat_code`, `echeance_date`, `piece_number`. Le problème est que la moitié de ces colonnes n'est jamais alimentée.

### Acquis à préserver (déjà au niveau du marché)

- Équilibre débit/crédit par `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED`, tolérance 0,01 (`76:70`)
- Immuabilité des écritures validées, extourne obligatoire (`76:18`)
- Contrôle de période close (`76:111`)
- Numérotation atomique par compteur sur le journal (`76:143`)
- Unicité des numéros de pièce, facture, avoir, bulletin par tenant (`76:181`)
- Export FEC aux 18 colonnes réglementaires (`FECExportPage.tsx:18`)
- Chaîne d'empreintes NF525 SHA-256 (`91_nf525_anti_fraud.sql`)

---

### `ACC-01` — Comptes auxiliaires sur les écritures automatiques

**Bloquant.**

**État actuel.** `create_journal_on_invoice_validate` (`90:178`) écrit `'411000'` dans `account_code` et `account_general`, et laisse `account_tiers` et `third_party_id` à `NULL`.

Or `getGrandLivreTiers()` filtre sur `.eq('account_tiers', …)` et `getAgedBalance()` sur `.not('account_tiers','is',null)`. **Le grand livre tiers et la balance âgée n'affichent donc rien pour les écritures générées automatiquement**, c'est-à-dire pour l'essentiel du flux.

Chez Sage, le compte auxiliaire est la clé de toute la gestion du poste client : relances, lettrage, échéancier, DSO.

**Actions.**

1. Ajouter à `customers` et `suppliers` une colonne `account_tiers text` (code auxiliaire, ex. `CLIDUPONT`), alimentée à la création par une règle paramétrable dans les paramètres du dossier (préfixe + racine du nom, ou compteur).
2. Ajouter au paramétrage du dossier les comptes collectifs par défaut (`411000` clients, `401000` fournisseurs) et permettre une surcharge par client/fournisseur (cas des clients douteux en `416`, des fournisseurs d'immobilisations en `404`).
3. Dans les quatre triggers de comptabilisation :
   ```sql
   SELECT COALESCE(c.account_collectif, '411000'), c.account_tiers, c.id
     INTO v_collectif, v_tiers, v_third_party
   FROM customers c
   WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;

   INSERT INTO journal_lines (
     tenant_id, journal_id, account_code, account_general,
     account_tiers, third_party_id, echeance_date,
     debit, credit, description, line_order
   ) VALUES (
     NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
     v_tiers, v_third_party, NEW.due_date,
     NEW.total, 0, 'Client ' || NEW.number, 0
   );
   ```
4. Renseigner également `echeance_date` : sans elle, la balance âgée classe sur la date d'écriture au lieu de la date d'échéance, ce qui décale tous les seuils.
5. Écrire une migration de rattrapage qui alimente `account_tiers` sur les écritures existantes, par jointure sur `invoice_ref`.

**Critère d'acceptation.** Après validation d'une facture, `getGrandLivreTiers(codeClient)` retourne la ligne 411, et `getAgedBalance()` la classe dans le bon seuil d'ancienneté.

---

### `ACC-02` — TVA multi-taux et code TVA

**Bloquant.**

**État actuel.** Une facture produit **une seule ligne** `4457000` pour `NEW.vat_total`, quel que soit le nombre de taux qu'elle porte. La colonne `vat_code` de `journal_lines` n'est jamais renseignée.

Conséquences directes :
- La CA3 ne peut pas être ventilée par taux (20 / 10 / 5,5 / 2,1)
- L'autoliquidation et l'intracommunautaire ne sont pas distinguables
- Le contrôle de cohérence TVA collectée ÷ base HT — le premier réflexe d'un cabinet — est impossible

**Actions.**

1. Créer une table de correspondance :
   ```sql
   CREATE TABLE IF NOT EXISTS vat_account_mapping (
     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     tenant_id uuid NOT NULL,
     vat_code text NOT NULL,          -- 'FR20', 'FR10', 'FR055', 'FR021', 'AUTOLIQ', 'EXO', 'UE'
     rate numeric NOT NULL,
     direction text NOT NULL CHECK (direction IN ('collected','deductible')),
     account_code text NOT NULL,      -- 445711, 445712, 445661, 445662…
     ca3_box text,                    -- 'A1','B2','08','09','19'…
     base_account text,               -- compte de produit/charge associé
     UNIQUE (tenant_id, vat_code, direction)
   );
   ```
2. Dans le trigger de vente, remplacer la ligne de TVA unique par une boucle sur les taux réellement présents :
   ```sql
   FOR v_vat IN
     SELECT il.vat_code,
            SUM(il.subtotal)  AS base_ht,
            SUM(il.vat_amount) AS montant_tva
     FROM invoice_lines il
     WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
     GROUP BY il.vat_code
   LOOP
     SELECT account_code INTO v_compte_tva
     FROM vat_account_mapping
     WHERE tenant_id = NEW.tenant_id AND vat_code = v_vat.vat_code
       AND direction = 'collected';

     INSERT INTO journal_lines (
       tenant_id, journal_id, account_code, account_general,
       vat_code, vat_amount, debit, credit, description, line_order
     ) VALUES (
       NEW.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
       v_vat.vat_code, v_vat.montant_tva,
       0, v_vat.montant_tva,
       'TVA collectée ' || v_vat.vat_code || ' — ' || NEW.number,
       v_ordre
     );
     v_ordre := v_ordre + 1;
   END LOOP;
   ```
3. Reconstruire `calcVatFromEntries` pour agréger par `vat_code` et remplir les cases de la CA3 via `vat_account_mapping.ca3_box`, au lieu de sommer un compte unique.
4. Gérer les trois régimes particuliers : autoliquidation (TVA collectée **et** déductible simultanément), acquisitions intracommunautaires, exonérations. Chacun est un `vat_code` avec son propre traitement.
5. Gérer la TVA sur encaissements (prestations de services) en plus de la TVA sur débits : elle change la date d'exigibilité, donc la période de déclaration. Les tables `vat_methods` existent déjà (`17_vat_methods_tvs.sql`).

**Critère d'acceptation.** Une facture à trois taux produit trois lignes de TVA distinctes ; la CA3 générée ventile correctement les bases et les taxes ; le contrôle base × taux = montant passe sur chaque ligne.

---

### `ACC-03` — Comptes de produit et de charge par article

**Majeur.**

**État actuel.** Toute vente va en `707000`, tout achat en `607000`. Aucun mapping par produit, famille, catégorie ou nature de charge — alors que la table `products` et le plan comptable existent.

Un cabinet ne peut pas produire un compte de résultat exploitable si toutes les charges atterrissent en « achats de marchandises ».

**Actions.**

1. Ajouter à `products` : `sale_account_code`, `purchase_account_code`, `stock_account_code`.
2. Créer `product_categories` avec les mêmes trois colonnes, servant de valeur par défaut.
3. Établir la cascade de résolution : *produit → catégorie du produit → paramètres du dossier*.
4. Dans les triggers, remplacer la ligne unique de produit par une boucle sur les lignes de facture regroupées par compte :
   ```sql
   FOR v_ligne IN
     SELECT COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut) AS compte,
            SUM(il.subtotal) AS montant
     FROM invoice_lines il
     LEFT JOIN products p            ON p.id  = il.product_id AND p.tenant_id  = NEW.tenant_id
     LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
     WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
     GROUP BY 1
   LOOP
     -- une ligne d'écriture par compte de produit
   END LOOP;
   ```
5. Propager `analytic_section_id` depuis la ligne de facture vers la ligne d'écriture : sans cela, la comptabilité analytique reste vide pour tout le flux automatique.

**Critère d'acceptation.** Une facture portant deux produits de familles différentes produit deux lignes de produit sur deux comptes distincts, avec section analytique reportée.

---

### `ACC-04` — Plan comptable de la législation du tenant

**Majeur. Contradiction frontale avec l'architecture affichée.**

**État actuel.** L'application gère des `legislation_packs`, un `country_code` par tenant et des grilles fiscales paramétrables. Mais les triggers de comptabilisation écrivent des comptes du PCG français en littéral. Un tenant SYSCOHADA ou djiboutien reçoit des écritures en 411/707/4457.

**Actions.**

1. Ajouter à `legislation_packs` une table fille `legislation_default_accounts` :
   ```sql
   CREATE TABLE legislation_default_accounts (
     legislation_pack_id uuid NOT NULL,
     role text NOT NULL,          -- 'customer','supplier','sales','purchases',
                                  -- 'vat_collected','vat_deductible','stock',
                                  -- 'stock_variation','cash','bank','payroll_expense'
     account_code text NOT NULL,
     PRIMARY KEY (legislation_pack_id, role)
   );
   ```
2. Alimenter au minimum PCG (France) et SYSCOHADA révisé — ce dernier a une structure de classes différente qui ne se déduit pas du PCG.
3. Créer un helper unique et l'utiliser dans **tous** les triggers :
   ```sql
   CREATE OR REPLACE FUNCTION default_account(p_tenant_id uuid, p_role text)
   RETURNS text LANGUAGE sql STABLE AS $$
     SELECT COALESCE(
       -- 1. surcharge du dossier
       (SELECT account_code FROM tenant_default_accounts
         WHERE tenant_id = p_tenant_id AND role = p_role),
       -- 2. défaut de la législation
       (SELECT lda.account_code
          FROM legislation_default_accounts lda
          JOIN tenants t ON t.legislation_pack_id = lda.legislation_pack_id
         WHERE t.id = p_tenant_id AND lda.role = p_role)
     );
   $$;
   ```
4. Si la portée multi-législation n'est pas tenable à court terme, **l'assumer explicitement** : restreindre la création de tenant à la France et retirer le sélecteur de pays. Une promesse non tenue coûte plus cher qu'un périmètre annoncé.

**Critère d'acceptation.** Créer un tenant SYSCOHADA, valider une facture, vérifier que l'écriture utilise les comptes de la classe SYSCOHADA et non ceux du PCG.

---

### `ACC-05` — Exercice, à-nouveaux et affectation du résultat

**Majeur.**

**État actuel.** `getTrialBalance()` et `getBalanceSheet()` ne portent **aucun filtre de date ni d'exercice**. Ils agrègent toutes les écritures depuis l'origine du dossier. Il n'y a pas d'application des à-nouveaux aux états, pas d'affectation du résultat, pas de solde d'ouverture. Le « bilan » produit est un cumul historique.

Le classement se fait par `chart_accounts.type` en trois seaux — actif / passif / capitaux propres. Il n'y a ni colonnes brut / amortissements / net, ni rubriques normalisées, ni résultat de l'exercice en capitaux propres.

**Actions.**

1. Régler la volumétrie et l'exercice d'un seul geste via `SOC-04` : `p_fiscal_year_id` obligatoire, colonnes d'à-nouveaux séparées des mouvements de période.
2. Implémenter la **clôture d'exercice** comme une procédure en cinq temps :
   ```
   1. Contrôles de cohérence   → balance équilibrée, aucune période ouverte, aucun brouillard
   2. Écritures de regroupement → soldes des classes 6 et 7 vers le compte 120 (ou 129)
   3. Calcul du résultat        → produits − charges
   4. Écriture d'à-nouveaux     → soldes des classes 1 à 5 reportés sur le nouvel exercice, journal AN
   5. Verrouillage              → exercice en 'closed', empreinte NF525 calculée et archivée
   ```
   La table `carry_forward_log` existe déjà et doit tracer chaque exécution.
3. Ajouter une écriture d'**affectation du résultat** (N-1 : 120 → 106 réserves / 457 dividendes), déclenchée à l'approbation des comptes.
4. Structurer le bilan en rubriques normalisées, avec les trois colonnes réglementaires **brut / amortissements & provisions / net** — la colonne « amortissements » se remplit depuis les comptes 28 et 29.
5. Reconstruire `LiasseFiscalePage` sur ces rubriques plutôt que sur une somme des classes 6 et 7.

**Critère d'acceptation.** Sur un dossier à deux exercices, le bilan N ouvre exactement sur la clôture N-1 ; total actif = total passif ; le résultat du compte de résultat est égal au résultat porté aux capitaux propres.

---

### `ACC-06` — Lettrage complet

**Mineur — la base est bonne.**

**État actuel.** Le lettrage automatique existe et fonctionne sur les lignes non lettrées (`LettragePage.tsx:100`). `lettrage_code` et `lettrage_date` sont en base.

**Manquent :** le lettrage partiel (un règlement pour deux factures, ou l'inverse), le délettrage tracé, le lettrage automatique par référence de paiement, et l'écart de règlement (escompte, différence de change, perte sur créance) qui doit générer son écriture.

**Actions.**

1. Ajouter `lettrage_partial boolean` et `lettrage_group_id uuid` pour représenter les rapprochements n-à-n.
2. Implémenter le lettrage par référence structurée en priorité sur le lettrage par montant.
3. Sur écart résiduel inférieur au seuil paramétré, générer automatiquement l'écriture d'écart :
   - escompte accordé → 665
   - perte de change → 666
   - gain de change → 766
   - créance irrécouvrable → 654
4. Tracer chaque délettrage dans `nf525_event_log` : un lettrage défait après clôture est un signal d'audit.

**Critère d'acceptation.** Un virement de 1 000 € soldant trois factures de 400, 400 et 210 € produit un lettrage groupé et une écriture d'escompte de 10 €.

---

### `ACC-07` — Immobilisations complètes

**Mineur.**

**État actuel.** Linéaire et dégressif via un RPC `calculate_depreciation`, plans d'amortissement, cession. `FixedAssetsPage.tsx:361` expose `declining_balance`.

**Manquent :** l'amortissement dérogatoire (écart fiscal/comptable, comptes 145 et 687/787), le prorata temporis du premier exercice, la comptabilisation automatique de la dotation annuelle, les composants d'immobilisation, et la réévaluation.

**Actions.**

1. Prorata temporis : la première annuité se calcule en jours (linéaire) ou en mois entiers (dégressif) depuis la date de mise en service, pas depuis le début de l'exercice.
2. Amortissement dérogatoire : maintenir deux plans en parallèle (comptable et fiscal), et générer la dotation ou la reprise de l'écart en 145.
3. Écriture automatique de dotation à la clôture :
   `681 dotations` (débit) / `28x amortissements` (crédit), par catégorie d'immobilisation.
4. Écriture de cession complète : sortie de la valeur brute (crédit 2x), reprise des amortissements (débit 28x), valeur nette comptable en 675, prix de cession en 775.
5. Composants : une immobilisation peut porter plusieurs composants amortis sur des durées différentes — obligatoire en normes françaises depuis 2005.

**Critère d'acceptation.** Une immobilisation mise en service le 15 mars amortie en linéaire sur 5 ans produit une première annuité au prorata de 291 jours, et la dotation génère son écriture automatiquement à la clôture.

---

### `ACC-08` — Comptabilité analytique effective

**Majeur — invisible dans la note globale mais structurant.**

**État actuel.** `analytic_plans`, `analytic_sections`, `distribution_grills` et `journal_lines.analytic_section_id` existent, avec des écrans. Mais aucun trigger de comptabilisation ne renseigne la section : l'analytique reste vide pour tout le flux automatique.

**Actions.**

1. Propager `analytic_section_id` depuis les lignes de document (facture, achat, note de frais, OF, feuille de temps) vers les lignes d'écriture — voir `ACC-03`.
2. Implémenter la ventilation par grille : une charge de structure se répartit sur n sections selon des clés (`distribution_grill_lines` existe déjà).
3. Ajouter un contrôle d'équilibre analytique : la somme des montants analytiques d'une ligne doit être égale au montant de la ligne. À poser en trigger, comme l'équilibre débit/crédit.
4. Rendre l'analytique obligatoire par plage de comptes (typiquement les classes 6 et 7), paramétrable.

**Critère d'acceptation.** Le total de la balance analytique est égal au total des classes 6 et 7 de la balance générale.

---

## 3. Paie — `PAY`

**3,8 → 9,5.** C'est le chantier le plus lourd du document et le seul qui appelle une **refonte** plutôt que des correctifs. Le moteur `src/lib/payroll.ts` tient en 264 lignes et ne modélise aucune des notions structurantes d'un bulletin français.

### Ce que fait le moteur aujourd'hui

Deux modes. En *fallback*, des taux 2024-2025 en dur appliqués à plat sur le brut. En mode *grille*, une boucle sur `payroll_tax_grid_lines` avec quatre types de ligne (`percentage`, `bracket`, `fixed_amount`, `flat`) et sept catégories agrégées. Deux raffinements corrects : l'assiette CSG/CRDS à 98,25 % du brut, et un plafonnement par ligne via `cap_amount`.

C'est un calculateur de cotisations proportionnelles. Sage Paie est un moteur de bulletin avec états de cumul.

---

### `PAY-01` — Deux corrections immédiates

**Bloquant. Deux heures de travail, effet sur chaque bulletin généré.**

**1. Taux de prélèvement à la source en dur.**
`queries/payroll.ts:231` passe `taxRate: 10` pour tous les salariés. Le taux transmis par la DGFiP n'est jamais lu, alors qu'`employees` pourrait le porter.

```typescript
// remplacer taxRate: 10 par :
taxRate: emp.withholding_tax_rate != null
  ? Number(emp.withholding_tax_rate)   // taux personnalisé DGFiP
  : neutralRate(taxableGross),          // barème du taux neutre, à défaut
```
Ajouter `withholding_tax_rate numeric` et `withholding_rate_source text` (`'dgfip'` | `'neutral'` | `'manual'`) sur `employees`, et implémenter le barème du taux neutre (grille mensuelle publiée chaque année).

**2. Assiette d'impôt inversée.**
`payroll.ts:117` : `taxableGross = totalGross + transportAllowance`.
L'indemnité de transport, exonérée dans la limite légale, est **ajoutée** à l'assiette imposable au lieu d'en être exclue.

```typescript
// la part exonérée sort de l'assiette ; seul le dépassement y entre
const transportExemptCap = LEGAL.transportExemptMonthlyCap  // paramétrable par législation
const transportExempt    = Math.min(transportAllowance, transportExemptCap)
const transportTaxable   = Math.max(0, transportAllowance - transportExempt)
const taxableGross       = totalGross + transportTaxable
```
Même traitement pour les titres-restaurant : la part patronale est exonérée dans une limite, au-delà elle est réintégrée.

**Critère d'acceptation.** Deux tests unitaires : un salarié à taux DGFiP 3,5 % voit 3,5 % appliqué ; une indemnité de transport de 75 € avec plafond d'exonération à 100 € n'augmente pas le net imposable.

---

### `PAY-02` — Plafond de sécurité sociale et tranches

**Bloquant. C'est la fondation de tout le reste.**

**État actuel.** Ni `PMSS`, ni plafond mensuel, ni proratisation. Toutes les cotisations plafonnées sont calculées sur le brut intégral : **au-delà de 3 925 € mensuels, chaque bulletin est faux.**

**Actions.**

1. Table de paramètres légaux par période :
   ```sql
   CREATE TABLE payroll_legal_parameters (
     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     tenant_id uuid,                 -- NULL = paramètre global fourni par l'éditeur
     country_code text NOT NULL,
     code text NOT NULL,             -- 'PMSS','SMIC_H','PLAFOND_TR2','TAUX_NEUTRE'…
     value numeric NOT NULL,
     valid_from date NOT NULL,
     valid_to date,
     UNIQUE (tenant_id, country_code, code, valid_from)
   );
   ```
2. Étendre `payroll_tax_grid_lines` avec :
   - `ceiling_type text` — `'none'` | `'pmss'` | `'multiple_pmss'` | `'fixed'`
   - `ceiling_multiplier numeric` — 1 pour la tranche A, 8 pour la tranche 2 AGIRC-ARRCO
   - `floor_multiplier numeric` — début de tranche (T2 commence à 1 PMSS)
3. Calculer l'assiette plafonnée :
   ```typescript
   function ceilingBase(gross: number, line: GridLine, pmss: number, proration: number) {
     if (line.ceiling_type === 'none') return gross
     const ceiling = line.ceiling_type === 'fixed'
       ? line.ceiling_value
       : pmss * (line.ceiling_multiplier ?? 1) * proration
     const floor   = pmss * (line.floor_multiplier ?? 0) * proration
     return Math.max(0, Math.min(gross, ceiling) - floor)
   }
   ```
4. **Proratiser le plafond** — c'est le point que tout le monde oublie. Le PMSS se réduit à proportion des jours de présence en cas d'entrée, de sortie ou de temps partiel. La variable `proration` ci-dessus est le lien avec `PAY-03`.
5. Modéliser AGIRC-ARRCO : tranche 1 (0 à 1 PMSS) et tranche 2 (1 à 8 PMSS), avec taux et taux d'appel distincts, plus la CEG et la CET.

**Critère d'acceptation.** Un salarié à 6 000 € de brut voit ses cotisations plafonnées calculées sur 3 925 € et ses cotisations T2 sur 2 075 €. Le total des cotisations correspond à un bulletin Sage de référence au centime près.

---

### `PAY-03` — Prorata d'entrée, de sortie et d'absence

**Bloquant.**

**État actuel.** Zéro occurrence de « prorata » dans tout le dépôt. Un salarié embauché le 12 du mois est payé plein mois. Aucune méthode de retenue pour absence.

**Actions.**

1. Ajouter au bulletin la notion de **période d'emploi** : `period_start`, `period_end`, `days_worked`, `days_in_period`, `hours_worked`, `hours_contract`.
2. Implémenter les trois méthodes de retenue d'absence utilisées en France, au choix dans le paramétrage :
   - **heures réelles** — `brut × heures_absence / heures_mois`
   - **jours ouvrés** — `brut × jours_absence / jours_ouvrés_mois`
   - **trentième** — `brut × jours_calendaires_absence / 30`
   La méthode retenue doit être un paramètre du dossier, car elle change le résultat et relève de la convention collective.
3. Proratiser le salaire de base, **le plafond de sécurité sociale**, les primes mensuelles et les titres-restaurant sur la même base.
4. Alimenter automatiquement les absences depuis `leave_requests` approuvées et depuis les arrêts maladie, sans ressaisie.

**Critère d'acceptation.** Un salarié à 3 000 € embauché le 12 d'un mois de 22 jours ouvrés perçoit un brut proratisé et un plafond SS proratisé dans la même proportion.

---

### `PAY-04` — Cumuls et régularisation progressive

**Bloquant. Obligatoire en paie française.**

**État actuel.** Le bulletin est calculé isolément, sans mémoire des périodes précédentes. Les écarts d'arrondi et de plafond ne sont jamais rattrapés.

**Actions.**

1. Créer la table de cumuls :
   ```sql
   CREATE TABLE payroll_cumulative (
     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     tenant_id uuid NOT NULL,
     employee_id uuid NOT NULL,
     year integer NOT NULL,
     month integer NOT NULL,
     gross numeric DEFAULT 0,
     taxable_gross numeric DEFAULT 0,
     ceiling_base numeric DEFAULT 0,      -- assiette plafonnée cumulée
     ceiling_available numeric DEFAULT 0, -- plafond cumulé disponible
     net_taxable numeric DEFAULT 0,
     net_social numeric DEFAULT 0,        -- montant net social, mention obligatoire
     employee_contributions numeric DEFAULT 0,
     employer_contributions numeric DEFAULT 0,
     withholding_tax numeric DEFAULT 0,
     csg_deductible numeric DEFAULT 0,
     csg_non_deductible numeric DEFAULT 0,
     UNIQUE (tenant_id, employee_id, year, month)
   );
   ```
2. Implémenter la **régularisation progressive** : à chaque bulletin, l'assiette plafonnée se calcule sur le cumul annuel depuis janvier, moins ce qui a déjà été soumis. Un salarié dont le salaire varie d'un mois à l'autre voit ainsi son plafond réajusté automatiquement.
   ```
   assiette_du_mois = MIN(cumul_brut, cumul_plafond) − assiette_déjà_soumise
   ```
3. Recalculer les cumuls en cascade lorsqu'un bulletin antérieur est modifié — c'est le comportement de Sage : rectifier janvier régularise février à décembre.
4. Rendre les cumuls consultables sur le bulletin (colonne « cumul annuel »), ce qui est une mention attendue.

**Critère d'acceptation.** Un salarié à 3 000 € en janvier puis 5 000 € en février voit son plafond de février régularisé du plafond non consommé en janvier ; le cumul annuel de fin d'année est égal à la somme des douze bulletins.

---

### `PAY-05` — Net imposable et scission de la CSG

**Bloquant. Prérequis de la DSN et du prélèvement à la source.**

**État actuel.** La CSG est agrégée en un seul montant. Sans la scission déductible / non déductible, le net imposable est incalculable — et sans net imposable, la DSN et le PAS sont invalides.

**Actions.**

1. Éclater la CSG-CRDS en trois lignes distinctes, toutes sur l'assiette de 98,25 % du brut (100 % au-delà de 4 PMSS) :
   - CSG déductible — 6,80 %, **retirée** du net imposable
   - CSG non déductible — 2,40 %, **réintégrée** au net imposable
   - CRDS — 0,50 %, réintégrée
2. Calculer le **net imposable** :
   ```
   net_imposable = brut
                 − cotisations salariales déductibles
                 + CSG non déductible + CRDS
                 + part patronale de prévoyance et de mutuelle
                 + avantages en nature
                 − part salariale de mutuelle obligatoire (dans la limite)
   ```
3. Calculer le **montant net social** — mention obligatoire sur le bulletin depuis juillet 2023, avec sa définition propre (différente du net imposable et du net à payer).
4. Appliquer le PAS **sur le net imposable**, pas sur le brut imposable comme aujourd'hui.

**Critère d'acceptation.** Le net imposable d'un bulletin de référence correspond à celui produit par Sage au centime près ; le montant net social apparaît sur le bulletin.

---

### `PAY-06` — Réduction générale de cotisations patronales

**Bloquant. Poste patronal le plus important au voisinage du SMIC.**

**État actuel.** Aucune trace de « réduction générale » ni de coefficient Fillon dans le dépôt.

**Actions.**

1. Implémenter le coefficient annuel :
   ```
   C = (T / 0,6) × (1,6 × SMIC_annuel / rémunération_annuelle_brute − 1)
   ```
   où `T` est la somme des taux de cotisations éligibles, plafonnée au coefficient maximal.
2. Calculer la réduction mois par mois **avec régularisation progressive** — elle dépend du cumul annuel, donc du chantier `PAY-04`.
3. Imputer la réduction sur les cotisations concernées dans l'ordre légal (URSSAF puis retraite complémentaire).
4. Traiter les mécanismes voisins : réduction du taux de cotisation maladie (« bandeau maladie ») et du taux famille, chacun avec son propre seuil en multiples de SMIC.
5. Faire apparaître le total des allègements dans la colonne dédiée du bulletin clarifié.

**Critère d'acceptation.** Un salarié au SMIC ouvre droit à une réduction générale non nulle, correctement imputée et affichée ; le montant correspond au simulateur de l'URSSAF.

---

### `PAY-07` — Heures supplémentaires conformes

**Majeur.**

**État actuel.** Taux unique de 1,25 sur `gross / 151,67` (`payroll.ts:103`). Pas de palier à 50 %, pas d'exonération salariale, pas de déduction forfaitaire patronale.

**Actions.**

1. Majorations par palier : 25 % de la 36ᵉ à la 43ᵉ heure, 50 % au-delà, taux conventionnels prioritaires quand ils existent.
2. Exonération de cotisations salariales sur les heures supplémentaires, dans la limite annuelle de 7 500 € — avec suivi du plafond via les cumuls (`PAY-04`).
3. Déduction forfaitaire patronale pour les entreprises de moins de 20 salariés, puis de 20 à 249.
4. Distinguer heures supplémentaires, heures complémentaires (temps partiel, taux différent) et repos compensateur.
5. Alimenter les heures depuis les feuilles de temps validées plutôt que par saisie manuelle — le trigger `sync_timesheet_to_payroll` existe déjà (`90:454`).

**Critère d'acceptation.** 10 heures supplémentaires produisent 8 h à 25 % et 2 h à 50 %, avec exonération salariale et déduction patronale correctement calculées.

---

### `PAY-08` — Conventions collectives

**Majeur.**

**État actuel.** Aucune notion de convention, de classification, de coefficient ni de minimum conventionnel. Sage livre des paramétrages par IDCC.

**Actions.**

1. Ajouter `collective_agreements` (IDCC, libellé, date d'application) et rattacher le tenant et chaque salarié.
2. Ajouter les classifications : catégorie, niveau, échelon, coefficient, salaire minimum conventionnel.
3. Contrôler à la validation du bulletin que le brut atteint le minimum conventionnel, et alerter sinon.
4. Rattacher les primes conventionnelles (ancienneté, treizième mois, panier, salissure) à la convention plutôt qu'à la saisie manuelle.
5. Livrer d'abord les trois ou quatre conventions les plus fréquentes chez vos clients cibles, pas les 400 IDCC.

**Critère d'acceptation.** Un salarié classé au coefficient 200 d'une convention chargée voit son minimum conventionnel contrôlé et sa prime d'ancienneté calculée automatiquement.

---

### `PAY-09` — Absences maladie, IJSS, subrogation

**Majeur.**

**État actuel.** Les arrêts maladie n'ont aucun effet sur le calcul du bulletin.

**Actions.**

1. Modéliser l'arrêt : type (maladie, AT/MP, maternité, paternité), dates, délai de carence.
2. Retenue pour absence maladie selon la méthode retenue en `PAY-03`.
3. Maintien de salaire selon la loi de mensualisation ou la convention (le plus favorable), avec conditions d'ancienneté et durées d'indemnisation à taux plein puis réduit.
4. Indemnités journalières : calcul, subrogation (l'employeur perçoit les IJSS et maintient le salaire) ou non, et réintégration au net.
5. Attestation de salaire dématérialisée via le signalement d'arrêt de travail en DSN.

**Critère d'acceptation.** Un arrêt de 10 jours avec subrogation produit une retenue, un maintien, et une ligne d'IJSS, avec un net conforme au calcul de référence.

---

### `PAY-10` — Bulletin clarifié réglementaire

**Majeur.**

**État actuel.** `pay_slip_clarified` stocke des lignes libres. Le modèle imposé n'est pas respecté.

**Actions.**

1. Regrouper les cotisations par **risque** selon le modèle légal : santé, accidents du travail, retraite, famille, assurance chômage, autres contributions dues par l'employeur.
2. Ajouter la colonne **« dont allègements de cotisations »** — alimentée par `PAY-06`.
3. Faire apparaître le **montant net social**, le net imposable, le net à payer avant impôt, le PAS et le net payé.
4. Afficher les cumuls annuels en pied de bulletin.
5. Générer le PDF via l'edge function `generate-pdf` existante, avec archivage automatique dans le coffre-fort salarié.

**Critère d'acceptation.** Le bulletin PDF produit contient toutes les mentions obligatoires ; une comparaison visuelle avec un bulletin Sage ne fait apparaître aucune rubrique manquante.

---

### `PAY-11` — Solde de tout compte complet

**Mineur — la moitié existe déjà.**

**État actuel.** `calculate_severance_pay()` (`88:701`) calcule l'indemnité légale et conventionnelle, avec ancienneté et salaire de référence. Elle vit hors du moteur de paie et n'alimente aucun bulletin.

**Actions.**

1. Brancher `calculate_severance_pay` sur le bulletin de solde de tout compte.
2. Ajouter l'indemnité compensatrice de congés payés (règle du dixième ou du maintien, la plus favorable).
3. Ajouter l'indemnité compensatrice de préavis quand il n'est pas exécuté.
4. Traiter le régime social et fiscal des indemnités : exonérations plafonnées, seuils d'assujettissement à CSG-CRDS.
5. Générer les documents de fin de contrat : certificat de travail, attestation France Travail, reçu pour solde de tout compte.

**Critère d'acceptation.** Un licenciement produit un bulletin de solde complet et les trois documents de fin de contrat.

---

### `PAY-12` — Architecture cible du moteur

**Le point qui conditionne les onze précédents.**

La table `payroll_tax_grid_lines` est bien conçue et le paramétrage par pays est la bonne intuition. Mais un modèle à quatre types de ligne et une assiette parmi cinq ne peut pas représenter un plafond proratisé, une tranche indexée, un cumul ni une régularisation.

**Architecture recommandée — un moteur à variables et rubriques :**

```typescript
// 1. Contexte : tout ce dont le calcul a besoin
interface PayrollContext {
  employee: Employee
  contract: Contract
  period: { start: Date; end: Date; daysWorked: number; daysInPeriod: number }
  legalParams: Map<string, number>          // PMSS, SMIC_H, plafonds… à la date
  cumulative: PayrollCumulative             // cumuls depuis janvier
  variableElements: VariableElement[]       // primes, absences, heures
  agreement: CollectiveAgreement | null
}

// 2. Rubrique : une ligne de bulletin, avec sa formule
interface PayrollRule {
  code: string                              // '1000', '6081', 'CSGD'…
  label: string
  section: 'gross' | 'contribution' | 'tax' | 'net' | 'employer' | 'info'
  risk?: 'health' | 'atmp' | 'retirement' | 'family' | 'unemployment' | 'other'
  base: (ctx: PayrollContext, computed: Map<string, number>) => number
  employeeRate?: (ctx: PayrollContext) => number
  employerRate?: (ctx: PayrollContext) => number
  ceiling?: { type: 'pmss'; floorMultiplier: number; capMultiplier: number }
  cumulativeKey?: string                    // clé de régularisation progressive
  order: number
  appliesTo: (ctx: PayrollContext) => boolean
}

// 3. Moteur : ordonne, calcule, régularise, cumule
function computePayslip(ctx: PayrollContext, rules: PayrollRule[]): Payslip
```

Trois propriétés que cette forme apporte et que la forme actuelle ne peut pas avoir :

- **Une rubrique peut dépendre du résultat d'une autre** (via `computed`) — indispensable pour la réduction générale, qui dépend du total des cotisations éligibles.
- **La régularisation progressive est une propriété de la rubrique** (`cumulativeKey`), appliquée uniformément par le moteur.
- **Le paramétrage reste en base** : `PayrollRule` se sérialise dans une table étendue, et le moteur reste générique par pays.

**Ordre de bataille recommandé :** `PAY-01` (2 h) → `PAY-12` (structure) → `PAY-02` → `PAY-04` → `PAY-05` → `PAY-03` → `PAY-06` → le reste. Les cinq premiers sont indissociables : chacun suppose les précédents.

**Ne pas promettre de conformité DSN avant que `PAY-02` à `PAY-06` soient livrés et validés contre des bulletins de référence.**

---

## 4. Ressources humaines — `RH`

**6,5 → 9,5.** Le module est solide hors calcul : congés, soldes, provisions, entretiens, carrière, CPF, coffre salarié, notes de frais, documents.

---

### `RH-01` — Gestion des temps et activités

**État actuel.** `timesheets` existe et le trigger `sync_timesheet_to_payroll` (`90:454`) fait le lien avec la paie. `89_attendance_and_lateness.sql` gère la présence et les retards.

**Manquent :** les plannings de travail (cycles, horaires variables, équipes), le compteur de modulation et d'annualisation, le compte épargne-temps, et la badgeuse.

**Actions.**

1. Modéliser les cycles horaires : semaine type, alternance, équipes 2×8 ou 3×8.
2. Compteurs de modulation : heures au-delà ou en deçà de la durée moyenne, régularisées en fin de période.
3. Compte épargne-temps : alimentation, valorisation, utilisation.
4. Interface d'import de pointeuse (CSV, puis API des principaux fabricants).

**Critère d'acceptation.** Un salarié en cycle 3×8 sur une modulation annuelle voit son compteur juste en fin de période.

---

### `RH-02` — Congés : conformité fine

**État actuel.** `calculate_leave_acquisition` (2,5 j/mois), soldes, provisions, report, planning, approbations. Bonne base.

**Manquent :** la distinction jours ouvrables / ouvrés, les congés d'ancienneté et de fractionnement, la période de référence configurable, et les RTT.

**Actions.**

1. Rendre la méthode de décompte paramétrable (ouvrables = 30 j/an, ouvrés = 25 j/an) — elle change tous les soldes.
2. Jours de fractionnement : attribution automatique selon les dates de prise du congé principal.
3. Congés d'ancienneté selon la convention collective.
4. Période de référence configurable (1ᵉʳ juin – 31 mai, ou année civile).
5. Acquisition pendant les absences assimilées à du temps de travail effectif (maternité, AT).

**Critère d'acceptation.** Un salarié prenant 2 semaines en octobre obtient automatiquement ses jours de fractionnement.

---

### `RH-03` — Recrutement et intégration

**État actuel.** Absent. Ce n'est pas une régression — c'est un périmètre non couvert.

**Actions.** À arbitrer : le recrutement est un marché à part (Welcome to the Jungle, Teamtailor). L'intégration en revanche est un prolongement naturel de la DPAE déjà présente : parcours d'onboarding, remise de matériel, checklist administrative, signature du contrat via `request-signature`.

**Critère d'acceptation.** Une embauche déclenche un parcours d'intégration avec ses tâches assignées et son suivi.

---

## 5. Stock — `STK`

**Périmètre 7,0 / Valorisation 2,5 → 9,5 sur les deux.** Le périmètre fonctionnel est bon. Le calcul de la valeur est faux dans les trois méthodes proposées — et c'est cette valeur qui alimente le bilan.

---

### `STK-01` — Vocabulaire des types de mouvement

**Bloquant. Une heure de travail.**

**État actuel.** La contrainte de `stock_movements` n'admet que cinq valeurs : `'in'`, `'out'`, `'transfer'`, `'adjustment'`, `'initial'`. Or `calculate_stock_valuation` (`88:392`) filtre sur :
```sql
AND sm.movement_type IN ('in', 'receipt', 'production', 'adjustment_in')
```
**Trois de ces quatre valeurs ne peuvent pas exister en base.** La valorisation ne voit donc que `'in'` — jamais `'initial'`, c'est-à-dire **le stock d'ouverture n'est jamais valorisé**. Le trigger comptable (`87:172`) exclut lui aussi `'initial'` : la reprise de stock à la création du dossier ne génère aucune écriture.

**Actions.**

```sql
-- migration 88 : aligner sur la contrainte réelle
AND sm.movement_type IN ('in', 'initial')

-- migration 87:172 : inclure la reprise de stock
IF NEW.movement_type NOT IN ('in', 'out', 'adjustment', 'initial') THEN
  RETURN NEW;
END IF;
```

Puis, pour éviter la récidive, remplacer le `text` + `CHECK` par un type énuméré Postgres :
```sql
CREATE TYPE stock_movement_type AS ENUM ('in','out','transfer','adjustment','initial');
ALTER TABLE stock_movements
  ALTER COLUMN movement_type TYPE stock_movement_type
  USING movement_type::stock_movement_type;
```
Une valeur inexistante devient alors une erreur à la compilation de la fonction, pas un filtre silencieusement vide.

**Critère d'acceptation.** La valorisation d'un produit dont tout le stock provient d'une reprise `'initial'` retourne une valeur non nulle.

---

### `STK-02` — CUMP incrémental

**Bloquant.**

**État actuel.** La formule appliquée est `Σ(unit_cost × qty) / Σ(qty)` sur **toutes les entrées depuis la création du produit**, sans jamais retirer ce qui est sorti. Un produit acheté 100 € il y a trois ans puis 10 € aujourd'hui garde un CUMP proche de 100 € même si l'ancien lot est vendu depuis longtemps.

Aggravant : la fonction se termine par `UPDATE stock_quantities SET unit_cost = v_cump`. Elle **écrit** une nouvelle valeur de stock sans générer l'écriture de réévaluation correspondante. Le poste 310 du bilan et la valeur du stock cessent alors de concorder, sans trace.

**Actions.**

```sql
CREATE OR REPLACE FUNCTION update_cump_on_movement()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_qty numeric; v_cost numeric;
BEGIN
  IF NEW.movement_type NOT IN ('in','initial') OR COALESCE(NEW.unit_cost,0) <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(quantity,0), COALESCE(unit_cost,0) INTO v_qty, v_cost
  FROM stock_quantities
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = NEW.tenant_id
  FOR UPDATE;                       -- sérialise les entrées concurrentes

  -- (valeur détenue + valeur entrante) / (quantité détenue + quantité entrante)
  UPDATE stock_quantities
  SET unit_cost = (v_qty * v_cost + NEW.quantity * NEW.unit_cost)
                  / NULLIF(v_qty + NEW.quantity, 0)
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END; $$;

CREATE TRIGGER update_cump AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_cump_on_movement();
```

Les sorties reprennent alors le `unit_cost` courant de `stock_quantities` : la valeur du stock devient cohérente par construction, et `calculate_stock_valuation` n'a plus qu'à lire la colonne.

Deux compléments indispensables :
- Le `FOR UPDATE` n'est pas décoratif : sans lui, deux réceptions simultanées du même article produisent un CUMP faux.
- Toute modification manuelle du coût doit générer une **écriture de réévaluation** (`310` contre `603` ou un compte d'écart), sinon le bilan décroche.

**Critère d'acceptation.** Une entrée de 100 à 10 €, puis 100 à 20 €, puis une sortie de 150 : le CUMP vaut 15 € et la valeur du stock restant vaut 750 €.

---

### `STK-03` — FIFO et LIFO avec prorata de la couche de bordure

**Majeur.**

**État actuel.** Le filtre `WHERE running_qty - quantity < v_rec.quantity` retient toute couche qui *commence* avant d'atteindre la quantité en stock, puis somme `unit_cost × quantity` sur la couche **complète**. Si la dernière couche retenue est un lot de 1 000 pièces dont il n'en reste que 5, ses 1 000 pièces sont valorisées.

Deux défauts secondaires : l'ordre `ORDER BY movement_date` n'a pas de départage sur `created_at` — résultat non déterministe pour des mouvements du même jour ; et les sorties ne consomment jamais les couches.

**Actions.**

```sql
-- FIFO : le stock restant, ce sont les entrées les plus récentes
SELECT COALESCE(sum(
  sm.unit_cost * LEAST(
    sm.quantity,
    GREATEST(0, v_rec.quantity - (sm.running_qty - sm.quantity))
  )
), 0)
INTO v_fifo_value
FROM (
  SELECT unit_cost, quantity,
    sum(quantity) OVER (ORDER BY movement_date DESC, created_at DESC) AS running_qty
  FROM stock_movements
  WHERE tenant_id = v_tid AND product_id = v_rec.product_id
    AND warehouse_id = v_rec.warehouse_id
    AND movement_type IN ('in','initial')
) sm
WHERE sm.running_qty - sm.quantity < v_rec.quantity;
```

Pour une correction complète, passer au **modèle de couches persistantes** — c'est ce que fait Odoo avec `stock_valuation_layer` :

```sql
CREATE TABLE stock_valuation_layers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  movement_id uuid NOT NULL,
  quantity numeric NOT NULL,          -- + entrée, − sortie
  remaining_qty numeric NOT NULL,     -- consommé au fil des sorties
  unit_cost numeric NOT NULL,
  value numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_svl_fifo
  ON stock_valuation_layers (tenant_id, product_id, warehouse_id, created_at)
  WHERE remaining_qty > 0;
```
Chaque sortie consomme les couches dans l'ordre de la méthode et décrémente `remaining_qty`. La valeur du stock est alors `SUM(remaining_qty × unit_cost)` — exacte par construction, et valorisable à n'importe quelle date par rejeu.

**Critère d'acceptation.** Entrées de 100 à 10 € puis 100 à 20 €, sortie de 150 : en FIFO le stock restant vaut 1 000 € (50 × 20), en LIFO 500 € (50 × 10).

---

### `STK-04` — Une seule fonction de valorisation, avec date

**Majeur.**

**État actuel.** Deux fonctions concurrentes. `get_stock_valuation` (`87:266`) retourne *dernier coût connu × quantité actuelle* — un coût de remplacement. `calculate_stock_valuation` (`88:351`) retourne un CUMP, un FIFO et un LIFO. Trois valeurs pour le même stock, sans qu'aucune règle ne désigne celle qui fait foi au bilan.

Pire, `get_stock_valuation` accepte un `p_date` et l'applique au coût, mais lit `products.stock_quantity`, c'est-à-dire la quantité **d'aujourd'hui**. La valorisation à une date passée est mathématiquement incohérente — or c'est exactement ce dont on a besoin pour l'inventaire de clôture.

**Actions.**

1. Supprimer `get_stock_valuation`.
2. Ajouter `p_date` à `calculate_stock_valuation` et reconstituer la quantité par rejeu :
   ```sql
   SUM(CASE WHEN movement_type IN ('in','initial') THEN quantity ELSE -quantity END)
   FROM stock_movements
   WHERE movement_date <= p_date
   ```
3. Ajouter aux paramètres du dossier `stock_valuation_method` (`'cump'` | `'fifo'` | `'lifo'`), et n'exposer que cette méthode au bilan et aux états.
4. Interdire le changement de méthode en cours d'exercice — c'est une règle comptable, pas une préférence.

**Critère d'acceptation.** La valorisation au 31/12/N recalculée en mars N+1 donne le même résultat qu'au 31/12/N.

---

### `STK-05` — Réservations de stock

**Majeur.**

**État actuel.** Aucune notion. Deux commandes peuvent promettre le même stock.

**Actions.**

1. Ajouter à `stock_quantities` : `quantity_reserved numeric DEFAULT 0`, et exposer `quantity_available` comme colonne générée (`quantity - quantity_reserved`).
2. Réserver à la confirmation de commande, libérer à l'expédition ou à l'annulation.
3. Le contrôle de disponibilité (`check_stock_on_sales_order_confirm`, `90:478`) doit tester `quantity_available`, pas `quantity`.
4. Afficher les trois quantités dans toutes les vues stock : physique, réservée, disponible.
5. Gérer les réservations concurrentes par verrou de ligne, comme pour le CUMP.

**Critère d'acceptation.** Deux commandes simultanées de 10 unités sur un stock de 15 : la première réserve, la seconde est bloquée ou passe en rupture.

---

### `STK-06` — Traçabilité série et lot effective

**Majeur.**

**État actuel.** `product_serial_numbers` et `product_batches` existent avec leurs écrans, mais `stock_movements` ne porte ni numéro de lot ni numéro de série. Aucune généalogie n'est donc possible.

**Actions.**

1. Ajouter à `stock_movements` : `lot_id uuid`, `serial_id uuid`.
2. Ajouter à `products` : `tracking text CHECK (tracking IN ('none','lot','serial'))`.
3. Rendre la saisie du lot obligatoire à la réception et à la sortie pour les articles tracés — contrôlé par trigger.
4. Implémenter la traçabilité **descendante** (ce lot est parti chez quels clients ?) et **ascendante** (ce produit fini contient quels lots de matières ?) — cette dernière suppose que le trigger d'OF enregistre les lots consommés.
5. Gérer les dates de péremption et la règle FEFO (premier périmé, premier sorti) — `manufacturing_orders` porte déjà `expiry_date`.
6. Écran de rappel de lot : sélectionner un lot, obtenir la liste des clients livrés.

**Critère d'acceptation.** À partir d'un numéro de lot de matière première, l'application liste les OF qui l'ont consommé, les produits finis obtenus et les clients livrés.

---

### `STK-07` — Unités de mesure et conversions

**Majeur.**

**État actuel.** Une seule unité implicite. Pas d'achat au kilo et de vente à l'unité.

**Actions.**

1. Créer `uom_categories` (poids, volume, longueur, unité, temps) et `uoms` (code, catégorie, facteur par rapport à l'unité de référence, arrondi).
2. Ajouter à `products` : `uom_id` (unité de stock), `purchase_uom_id`, `sale_uom_id`.
3. Convertir à chaque frontière : ligne de commande, réception, mouvement de stock, ligne de facture.
4. Interdire la conversion entre catégories différentes — erreur explicite, jamais de conversion silencieuse.
5. Gérer l'arrondi par unité : on ne vend pas 3,7 pièces.

**Critère d'acceptation.** Acheter 1 tonne, stocker en kilos, vendre par sacs de 25 kg : les trois vues sont cohérentes et le stock est juste.

---

### `STK-08` — Frais accessoires d'achat

**Mineur mais visible sur la marge.**

**État actuel.** Transport et douane ne rejoignent jamais le coût du stock.

**Actions.**

1. Créer `landed_costs` (facture de frais, méthode de répartition : valeur, quantité, poids, volume) et `landed_cost_lines` (rattachement aux réceptions).
2. À la validation, répartir le coût sur les articles reçus et **ajuster leur `unit_cost`**, ce qui met à jour le CUMP via `STK-02`.
3. Générer l'écriture d'ajustement de valeur de stock.

**Critère d'acceptation.** Une facture de transport de 500 € répartie sur une réception de 10 000 € augmente le CUMP des articles concernés de 5 %.

---

### `STK-09` — Réapprovisionnement et inventaire tournant

**Mineur.**

**Actions.**

1. Créer `reorder_rules` (produit, entrepôt, minimum, maximum, multiple, délai, actif) et l'exploiter dans le MRP (`PRD-04`).
2. Planifier des comptages cycliques : classer les articles en A/B/C par valeur, définir une fréquence par classe, générer les listes de comptage.
3. Écran de saisie de comptage avec écart automatique, et génération du mouvement `'adjustment'` valorisé.
4. Rapport de précision d'inventaire par entrepôt et par classe.

**Critère d'acceptation.** Un article de classe A est proposé au comptage tous les mois ; l'écart constaté génère son mouvement d'ajustement et son écriture.

---

### `STK-10` — Comptes de stock par catégorie

**Mineur.**

**État actuel.** `310000` et `603000` en dur pour tous les produits (`87:161-162`). Le commentaire du code l'admet : *« Pour l'instant on utilise les comptes standards »*.

Or le PCG distingue : 31 matières premières, 32 autres approvisionnements, 33 en-cours, 35 produits finis, 37 marchandises — chacun avec son compte de variation (6031, 6032, 6037, 71331, 71355).

**Actions.** Résoudre le compte via `product_categories.stock_account_code` avec repli sur `default_account(tenant_id, 'stock')` (`ACC-04`).

**Critère d'acceptation.** Un mouvement sur une marchandise touche 370/6037, un mouvement sur un produit fini touche 355/71355.

---

### `STK-11` — Emplacements et logique d'entrepôt

**État actuel.** `warehouse_locations` existe avec son écran (`/stock/warehouse-locations`), mais ne porte **aucun trigger métier** hors `set_tenant_id`, et `stock_movements` ne référence pas d'emplacement. Le stock est donc connu à l'entrepôt, jamais à l'emplacement.

**Actions.**

1. Ajouter `location_id` à `stock_movements` et à `stock_quantities`, et faire porter la clé d'unicité sur `(product_id, warehouse_id, location_id)`.
2. Structurer les emplacements en arbre (zone → allée → travée → niveau → alvéole) avec un `parent_id`, et calculer le stock agrégé par nœud.
3. Typer les emplacements : réception, stockage, préparation, expédition, rebut, quarantaine.
4. Règles de rangement (*put-away*) : à la réception, proposer l'emplacement selon le type d'article, le volume disponible et la zone.
5. Règles de prélèvement (*removal*) : FIFO, FEFO, ou emplacement le plus proche.
6. Capacité par emplacement (poids, volume, nombre de palettes) avec alerte de saturation.

**Critère d'acceptation.** Une réception propose un emplacement de rangement ; le stock d'un article se ventile par emplacement et la somme est égale au stock entrepôt.

---

### `STK-12` — Préparation de commande et expédition

**État actuel.** `pick_lists` et `pick_list_lines` existent avec leur écran (`/stock/pick-lists`), sans aucun trigger métier. La liste à servir ne génère donc ni réservation, ni mouvement, ni lien avec la livraison.

**Actions.**

1. Générer la liste à servir depuis les commandes confirmées, avec regroupement paramétrable : par commande, par vague, par tournée, par zone.
2. Réserver le stock à la génération (`STK-05`) et libérer à l'expédition.
3. Ordonner les lignes selon le **chemin de prélèvement** dans l'entrepôt — c'est le gain de productivité principal d'un WMS.
4. Valider le prélèvement ligne à ligne avec contrôle du lot ou du numéro de série (`STK-06`), et gérer les écarts (rupture, casse).
5. Colisage : constituer les colis, calculer le poids et le volume, générer les étiquettes.
6. Expédition : bon de livraison, lettre de voiture, suivi transporteur, et déclenchement du mouvement de stock à l'enlèvement — pas à la préparation.

**Critère d'acceptation.** Trois commandes groupées en une vague produisent une liste ordonnée par chemin de prélèvement, et la validation génère les mouvements de sortie et les bons de livraison.

---

### `STK-13` — Contrôle qualité

**État actuel.** `quality_checks` existe et dispose du seul trigger métier de cette famille : `create_stock_in_on_quality_pass` (`90:320`), qui fait entrer la marchandise en stock après contrôle. Bonne base.

**Manquent :** les plans de contrôle (quoi contrôler, selon quel critère), l'échantillonnage, la mise en quarantaine, le circuit de non-conformité.

**Actions.**

1. Créer `quality_control_plans` : par article ou famille, liste des points de contrôle, type (mesure, visuel, binaire), tolérances.
2. Échantillonnage : contrôle systématique, par taux, ou selon une table de plan d'échantillonnage.
3. Emplacement de quarantaine (`STK-11`) : la marchandise reçue y entre et n'est disponible qu'après contrôle favorable.
4. Non-conformité : fiche, décision (accepter, retoucher, retourner, rebuter), avoir fournisseur, et alimentation de l'évaluation fournisseur (`ACH-02`).
5. Contrôle en cours de production et contrôle final, rattachés aux opérations de gamme.

**Critère d'acceptation.** Une réception d'article sous plan de contrôle entre en quarantaine et n'est disponible à la vente qu'après validation du contrôle.

---

### `STK-14` — Transferts inter-entrepôts et variantes

**État actuel.** Le type de mouvement `'transfer'` existe dans la contrainte et un écran `/stock/transfer` est présent, mais le trigger comptable exclut explicitement les transferts (`87:171`) — ce qui est correct pour un transfert intra-société. En revanche, aucun objet ne modélise le transfert lui-même : il n'y a ni document, ni stock en transit, ni réception à l'arrivée.

`product_variants` existe (écran `/stock/product-grids`) mais sans trigger métier ni intégration aux mouvements.

**Actions.**

1. Créer `stock_transfers` et `stock_transfer_lines` : entrepôt d'origine, entrepôt de destination, dates d'expédition et de réception attendues, statut.
2. Modéliser le **stock en transit** : la sortie de l'entrepôt A et l'entrée dans l'entrepôt B sont deux mouvements distincts, séparés dans le temps ; entre les deux, la marchandise existe et doit être visible.
3. Transfert inter-sociétés : générer facture de cession et facture d'achat entre les deux entités (`GRP-02`).
4. Variantes : une déclinaison (taille, couleur, format) doit porter son propre stock, son propre code-barres et son propre prix, tout en héritant de l'article parent. Aujourd'hui la table existe mais les mouvements ne référencent que `product_id`.
5. Grille de saisie par variante en commande et en réception — c'est l'ergonomie attendue en textile, chaussure et distribution.

**Critère d'acceptation.** Un transfert de 100 unités entre deux entrepôts fait apparaître 100 unités en transit entre l'expédition et la réception ; une commande de 3 tailles d'un même modèle se saisit en une grille.

---

## 6. Production — `PRD`

**4,0 → 9,5.** Les objets sont là — gammes, postes de charge, machines, outillages, sous-traitance, planning. C'est l'algorithme de calcul des besoins et le coût de revient qui manquent.

---

### `PRD-01` — Valoriser les ordres de fabrication

**Bloquant.**

**État actuel.** Le trigger de fin d'OF (`81:220`) insère le mouvement de production **sans `unit_cost`**. Or le trigger comptable sort immédiatement dans ce cas (`87:167`).

Conséquence en chaîne : les composants sortent du stock (charge constatée), le produit fini y entre à zéro. Le résultat comptable est amputé de toute la valeur ajoutée de production, le stock de produits finis vaut zéro au bilan, et le prix de revient n'existe nulle part — donc aucune marge de production n'est calculable.

**Actions.**

1. Ajouter à `manufacturing_orders` : `cost_material`, `cost_labor`, `cost_overhead`, `cost_total`, `unit_cost`, `qty_produced`, `qty_scrapped`.
2. Calculer le coût avant de produire le mouvement :

```sql
-- dans create_stock_on_manufacturing_complete, avant l'insert du produit fini
DECLARE
  v_cost_material numeric := 0;
  v_cost_labor    numeric := 0;
  v_cost_overhead numeric := 0;
  v_unit_cost     numeric;
BEGIN
  -- 1. matières : quantité de nomenclature × CUMP courant du composant
  SELECT COALESCE(sum(bl.quantity * NEW.quantity
                      * COALESCE(sq.unit_cost, p.cost_price, 0)), 0)
  INTO v_cost_material
  FROM bom_lines bl
  JOIN products p ON p.id = bl.product_id AND p.tenant_id = NEW.tenant_id
  LEFT JOIN stock_quantities sq
    ON sq.product_id = bl.product_id AND sq.warehouse_id = NEW.warehouse_id
   AND sq.tenant_id = NEW.tenant_id
  WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id;

  -- 2. main-d'œuvre : temps de gamme × coût horaire du poste de charge
  SELECT COALESCE(sum((ro.setup_time + ro.run_time * NEW.quantity) / 60.0
                      * wc.cost_per_hour), 0)
  INTO v_cost_labor
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = NEW.tenant_id
  WHERE ro.routing_id = NEW.routing_id AND ro.tenant_id = NEW.tenant_id;

  -- 3. frais généraux : taux d'imputation sur la main-d'œuvre ou sur les heures machine
  v_cost_overhead := v_cost_labor * COALESCE(
    (SELECT overhead_rate FROM company_settings WHERE tenant_id = NEW.tenant_id), 0
  );

  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead)
                 / NULLIF(NEW.quantity, 0);

  UPDATE manufacturing_orders
  SET cost_material = v_cost_material, cost_labor = v_cost_labor,
      cost_overhead = v_cost_overhead,
      cost_total = v_cost_material + v_cost_labor + v_cost_overhead,
      unit_cost = v_unit_cost
  WHERE id = NEW.id;
  -- … puis passer unit_cost = v_unit_cost sur le mouvement 'in' du produit fini
  -- et unit_cost = CUMP courant sur chaque mouvement 'out' de composant
END;
```

3. Générer l'écriture de production : sortie des matières (débit 601/602, crédit 31/32), main-d'œuvre imputée, entrée du produit fini (débit 355, crédit 71355 production stockée).

**Critère d'acceptation.** Un OF consommant 100 € de matières et 50 € de main-d'œuvre produit un article fini valorisé à 150 €, avec les écritures correspondantes.

---

### `PRD-02` — Éclatement MRP récursif

**Bloquant.**

**État actuel.** `stock.ts:738-750` calcule les besoins bruts en parcourant **une seule fois** les lignes de nomenclature des OF ouverts. Un composant qui possède lui-même une nomenclature n'est jamais éclaté. Sur une structure produit à trois niveaux — cas courant en mécanique ou en agroalimentaire — **les matières premières n'apparaissent dans aucune proposition**.

Odoo attribue à chaque article un *low-level code* et traite les niveaux du plus haut au plus bas, pour éviter à la fois l'oubli et le double comptage d'un composant utilisé à deux niveaux.

**Actions.**

```sql
WITH RECURSIVE explosion AS (
  -- niveau 0 : les OF ouverts
  SELECT mo.product_id, mo.bom_id, mo.quantity::numeric AS qty, 0 AS level
  FROM manufacturing_orders mo
  WHERE mo.tenant_id = v_tid AND mo.status IN ('planned','in_progress')

  UNION ALL

  -- niveau n+1 : les composants, éclatés à leur tour s'ils ont une nomenclature
  SELECT bl.product_id, b_child.id, e.qty * bl.quantity, e.level + 1
  FROM explosion e
  JOIN bom_lines bl ON bl.bom_id = e.bom_id AND bl.tenant_id = v_tid
  LEFT JOIN boms b_child
    ON b_child.product_id = bl.product_id AND b_child.tenant_id = v_tid
   AND b_child.active
  WHERE e.level < 15          -- garde-fou anti-boucle
)
SELECT product_id, sum(qty) AS gross_need, max(level) AS low_level_code
FROM explosion
GROUP BY product_id
ORDER BY low_level_code;      -- traiter du plus haut niveau au plus bas
```

Compléments :
- Détecter les nomenclatures circulaires et refuser leur enregistrement, plutôt que de compter sur le garde-fou.
- Gérer les coefficients de perte par ligne de nomenclature (`scrap_rate`).
- Gérer les nomenclatures alternatives et les articles de substitution (`product_substitutes` existe déjà).

**Critère d'acceptation.** Une nomenclature à trois niveaux génère des propositions pour les composants **et** pour les matières premières, dans le bon ordre de traitement.

---

### `PRD-03` — Sources du besoin

**Bloquant.**

**État actuel.** Le besoin brut provient uniquement des OF ouverts. `production_forecasts` existe mais n'est jamais lu. Les commandes clients n'entrent pas dans le besoin. Le MRP ne peut donc que réapprovisionner ce qu'on a déjà décidé de fabriquer : c'est une explosion de nomenclature, pas un plan de besoins.

**Actions.**

1. Ajouter aux sources du besoin brut :
   - les **commandes clients** confirmées non livrées, avec leur date de livraison
   - les **prévisions de vente** (`production_forecasts`), nettes des commandes fermes de la période pour éviter le double comptage
   - les **règles de réapprovisionnement** (`STK-09`)
   - les **OF planifiés** — la source actuelle
2. Placer chaque besoin sur son **seau de temps** (semaine ou mois) selon sa date, plutôt que de tout agréger.
3. Ajouter un paramètre d'horizon (`p_horizon_days`) et une politique de consommation des prévisions.

**Critère d'acceptation.** Une commande client à 6 semaines génère une proposition d'achat de matière première datée en tenant compte du délai de fabrication et du délai fournisseur.

---

### `PRD-04` — Délais, stock de sécurité, lot technique

**Majeur. Le meilleur rapport effet/effort du module.**

**État actuel.** Trois raccourcis : `suggested_date` vaut toujours `aujourd'hui + 7 jours` en dur, le besoin net n'est jamais diminué du stock de sécurité, et la quantité suggérée est un simple `Math.ceil`.

**Actions.**

1. Ajouter à `products` : `safety_stock`, `lead_time_days`, `min_order_qty`, `qty_multiple`.
2. Reprendre le calcul :
```typescript
const safety   = Number(product.safety_stock   || 0)
const leadDays = Number(product.lead_time_days || 7)
const minQty   = Number(product.min_order_qty  || 0)
const multiple = Number(product.qty_multiple   || 1)

const netNeed = Math.max(0, grossNeed + safety - stock - openOrders)
if (netNeed <= 0) continue

// arrondi au multiple de conditionnement, plancher au minimum de commande
let suggestedQty = Math.max(netNeed, minQty)
suggestedQty = Math.ceil(suggestedQty / multiple) * multiple

// jalonnement amont : reculer depuis la date de besoin, pas depuis aujourd'hui
const needDate = new Date(mo.start_date ?? Date.now())
const suggestedDate = new Date(needDate.getTime() - leadDays * 86400000)
```
3. Signaler les propositions dont la date calculée est déjà dépassée — c'est l'information la plus utile du plan.

**Critère d'acceptation.** Un article à 8 semaines de délai, conditionné par 500, avec 100 de stock de sécurité, produit une proposition de 500 datée 8 semaines avant le besoin.

---

### `PRD-05` — Déduction des commandes en cours

**Bloquant. Deux heures de travail.**

**État actuel.** Le calcul construit `openPOMap[po.product_id]` à partir de `purchase_orders`. Cette table n'a **aucune colonne `product_id`** — elle porte `supplier_id`, des dates, des montants. L'expression vaut `undefined` à chaque ligne, la carte reste vide, et le besoin net ignore tout ce qui est déjà commandé.

Effet : à chaque exécution, l'application re-propose de commander ce qui est déjà en route. Un lancement hebdomadaire multiplie les commandes en cascade.

**Actions.**
```typescript
// stock.ts:700 — lire les LIGNES de commande, pas l'en-tête
supabase.from('purchase_order_lines')
  .select('product_id, quantity, quantity_received, purchase_orders!inner(status)')
  .eq('tenant_id', tid)
  .in('purchase_orders.status', ['draft','sent','confirmed'])
  .then(r => r.data || []),

// … puis, pour le reste à recevoir uniquement :
for (const line of openPOLines) {
  const remaining = Number(line.quantity) - Number(line.quantity_received || 0)
  if (remaining > 0)
    openPOMap[line.product_id] = (openPOMap[line.product_id] || 0) + remaining
}
```
Faire de même pour les OF en cours : déduire `quantity - qty_produced`, pas `quantity`.

**Critère d'acceptation.** Deux exécutions consécutives du MRP sans changement de données produisent le même nombre de propositions — pas le double.

---

### `PRD-06` — Déclaration de production et rebuts

**Majeur.**

**État actuel.** La consommation est toujours la quantité théorique de la nomenclature. Aucun rebut, aucun temps réel, aucun écart.

**Actions.**

1. Créer `mo_consumptions` (OF, composant, quantité théorique, quantité réelle, lot) et `mo_operations` (OF, opération, temps prévu, temps passé, opérateur, quantité produite, quantité rebutée).
2. Écran de déclaration d'atelier : saisir les quantités produites et rebutées par opération, et les consommations réelles.
3. Calculer les **écarts** : sur quantité de matière, sur prix de matière, sur temps, sur taux horaire. C'est l'apport principal de Sage Production.
4. Générer les mouvements de rebut valorisés (compte 6588 ou un compte de perte dédié).
5. Autoriser la consommation partielle et la clôture d'OF incomplet.

**Critère d'acceptation.** Un OF déclaré avec 5 % de rebut et 20 % de dépassement de temps affiche ses quatre écarts, chiffrés.

---

### `PRD-07` — Capacité finie et ordonnancement

**Majeur.**

**État actuel.** `work_centers.capacity_hours_per_day` est stocké mais jamais confronté à la charge. Le `planning_slots` et le Gantt existent, sans contrainte de capacité.

**Actions.**

1. Calculer la charge par poste et par jour à partir des OF planifiés et de leurs gammes.
2. Afficher le graphique charge/capacité, avec les surcharges en évidence.
3. Implémenter un ordonnancement à capacité finie : jalonnement au plus tôt ou au plus tard, décalage automatique des opérations en surcharge.
4. Gérer les calendriers d'ouverture par poste : jours fériés, congés, arrêts machine planifiés.
5. Permettre le déplacement d'une opération par glisser-déposer dans le Gantt, avec recalcul des successeurs.

**Critère d'acceptation.** Charger trois OF dépassant la capacité d'un poste : la surcharge est visible et l'ordonnancement propose un étalement.

---

### `PRD-08` — Exécuter le MRP en base

**Mineur mais structurant.**

**État actuel.** Six tables entières rapatriées côté client, puis insertions une par une dans une boucle `await`. Pour 5 000 articles, 5 000 allers-retours. Si l'un échoue, le `mrp_run` reste bloqué en `running` avec des propositions partielles.

**Actions.** Déplacer l'ensemble dans un RPC `run_mrp(p_horizon_days integer)` — la requête récursive de `PRD-02` fait déjà l'essentiel — et insérer les propositions en un seul `INSERT … SELECT`. Le tout devient atomique et passe de plusieurs minutes à quelques centaines de millisecondes.

**Critère d'acceptation.** Un MRP sur 5 000 articles s'exécute en moins de 5 secondes, en une transaction.

---

### `PRD-09` — Sous-traitance de production

**Majeur. Quatre routes, cinq tables, aucun trigger métier.**

**État actuel.** Le périmètre est modélisé sérieusement : `st_orders`, `st_shipments`, `st_shipment_lines`, `st_receipts`, `st_receipt_lines`, avec quatre écrans (`/production/subcontracting/orders`, `/shipments`, `/receipts`, `/supervisor`). Mais aucune de ces tables ne porte de trigger autre que `set_tenant_id`.

Conséquence : envoyer de la matière chez un sous-traitant ne sort rien du stock, recevoir la pièce finie n'y fait rien entrer, et la facture du sous-traitant n'est rattachée à rien. La sous-traitance est un ensemble d'écrans de saisie sans effet.

**Actions.**

1. **Expédition chez le sous-traitant** → mouvement `'out'` valorisé vers un emplacement ou un entrepôt logique « stock chez tiers ». La marchandise reste la propriété de l'entreprise et doit rester au bilan — c'est le point comptable essentiel, souvent manqué.
2. **Réception du sous-traitant** → mouvement `'in'` du composant transformé, valorisé au coût des matières envoyées **plus** le coût de l'opération sous-traitée.
3. Rattacher la facture du sous-traitant à l'ordre, avec rapprochement à trois voies (`ACH` : ordre / réception / facture).
4. Suivre le **stock détenu chez les tiers** dans un état dédié, et le rapprocher périodiquement des déclarations du sous-traitant.
5. Traiter les écarts : matière perdue, rebut chez le sous-traitant, quantité rendue inférieure à la quantité envoyée.
6. Intégrer la sous-traitance au MRP : une opération de gamme marquée « sous-traitée » génère une proposition d'ordre de sous-traitance, pas un besoin interne.

**Critère d'acceptation.** Envoyer 100 pièces chez un sous-traitant, en recevoir 98 finies et 2 rebutées : le stock chez tiers est à zéro, les 98 pièces sont valorisées matière + façon, et les 2 rebuts sont constatés en perte.

---

### `PRD-10` — Workflows et équivalences

**État actuel.** Deux écrans existent — `/production/workflows` et `/production/equivalences` — adossés aux tables `workflows` et `product_equivalences`. Le module `of-access` gère par ailleurs un contrôle d'accès aux ordres de fabrication (`OFDocumentAccess`).

Ces objets sont peu documentés et leur articulation avec le reste de la production n'est pas établie.

**Actions.**

1. **Clarifier l'intention de `workflows`** avant tout développement : s'agit-il d'un circuit de validation d'OF, d'un enchaînement d'étapes de production, ou d'un moteur de règles ? Le nom ne le dit pas et le code ne tranche pas. C'est le prérequis.
2. **Équivalences** : les exploiter dans le MRP et dans la préparation d'OF — si le composant A est en rupture et que B lui est équivalent, la proposition doit le refléter, avec l'écart de coût.
3. **Accès aux OF** : formaliser les droits par atelier ou par poste, et les faire porter par la RLS plutôt que par l'interface.
4. Documenter les trois mécanismes dans `doc/` — ce sont les seuls du module dont la finalité n'est pas lisible depuis le code.

**Critère d'acceptation.** La finalité de chaque mécanisme est documentée, et chacun a au moins un test d'intégration.

---

### `PRD-11` — Maintenance des machines et des outillages

**État actuel.** `machines` porte un statut `active | maintenance | inactive` ; `toolings` porte `max_pieces`, `initial_counter` et `current_counter` — la modélisation de l'usure d'outillage est un vrai point fort, rare à ce niveau de détail.

**Manquent :** l'incrémentation automatique des compteurs à la production, l'alerte de fin de vie, et la maintenance préventive.

**Actions.**

1. Incrémenter `current_counter` automatiquement à la déclaration de production (`PRD-06`), au prorata des pièces réalisées sur la machine.
2. Alerter à l'approche de `max_pieces` et bloquer le lancement d'un OF sur un outillage hors service.
3. Créer `maintenance_plans` (périodicité en temps, en heures machine ou en nombre de pièces) et `maintenance_interventions` (planifiée, curative, coût, durée d'immobilisation).
4. Déduire les périodes d'immobilisation de la capacité du poste (`PRD-07`).
5. Calculer le taux de rendement synthétique par machine — disponibilité × performance × qualité.

**Critère d'acceptation.** Un outillage atteignant 95 % de sa durée de vie déclenche une alerte ; une maintenance planifiée réduit automatiquement la capacité du poste sur la période.

---

## 7. Achats — `ACH`

**7,5 → 9,5.** Le module le plus abouti du volet exploitation.

### Acquis à préserver

Le rapprochement à trois voies (`86_three_way_matching.sql`) lie facture, commande et réception, compare quantités et prix ligne à ligne, applique une tolérance, approuve automatiquement en cas de concordance et bascule en `pending_review` sinon, avec historique. C'est le mécanisme de Sage Intacct et d'Odoo, correctement transposé. Autour : demandes d'achat, circuit d'approbation, tarifs fournisseurs, échéanciers de livraison.

---

### `ACH-01` — Accords-cadres et contrats fournisseurs

**Actions.** Modéliser les contrats à quantité ou montant engagé, avec libération par commandes successives, suivi du reste à consommer, et alerte à l'échéance.

**Critère d'acceptation.** Un contrat de 100 tonnes sur l'année affiche son reste à livrer après chaque commande.

---

### `ACH-02` — Évaluation fournisseur

**Actions.** Calculer automatiquement, par fournisseur : taux de service (livraisons dans les délais), taux de conformité (contrôles qualité passés), écart de prix moyen facture/commande, délai moyen de livraison. Alimenter un score et l'afficher à la sélection du fournisseur dans une demande d'achat.

**Critère d'acceptation.** La fiche fournisseur affiche les quatre indicateurs sur 12 mois glissants.

---

### `ACH-03` — Contrôle budgétaire à l'engagement

**État actuel.** `create_budget_commitments.sql` et `BudgetCommitmentsPage` existent.

**Actions.** Contrôler à la validation d'une demande ou d'une commande que le budget de la ligne analytique n'est pas dépassé, et déclencher une validation hiérarchique en cas de dépassement. C'est l'engagement, pas la facture, qui doit consommer le budget.

**Critère d'acceptation.** Une commande dépassant le budget de sa section analytique est bloquée ou escaladée.

---

## 8. Ventes — `VTE`

**5,5 → 9,5.** Deux mécanismes structurants de Sage Gestion Commerciale sont modélisés en base mais déconnectés du flux.

---

### `VTE-01` — Appliquer les grilles tarifaires

**Majeur.**

**État actuel.** `price_lists` et `price_list_lines` portent prix, quantité minimale et remise. Un écran permet de les saisir. Mais aucune référence à `price_list` n'apparaît dans `src/lib/queries/sales.ts` ni dans les pages de devis, commande ou facture : **le prix de vente reste celui du produit, quel que soit le client.**

Chez Sage comme chez Odoo, la résolution du tarif — par client, par catégorie, par quantité, par période — est le cœur de la saisie commerciale.

**Actions.**

```typescript
// src/lib/queries/sales.ts — à appeler depuis chaque formulaire de ligne
export async function resolvePrice(
  productId: string, customerId: string, quantity: number, date = new Date()
) {
  const tid = await getTenantId()
  const { data } = await supabase
    .from('price_list_lines')
    .select(`unit_price, discount_percent, min_quantity,
             price_lists!inner(id, type, valid_from, valid_to, customer_id, priority)`)
    .eq('tenant_id', tid)
    .eq('product_id', productId)
    .eq('price_lists.type', 'sales')
    .lte('min_quantity', quantity)
    // tarif du client, sinon tarif général
    .or(`customer_id.eq.${customerId},customer_id.is.null`, { foreignTable: 'price_lists' })
    // le plus spécifique d'abord : client > général, puis quantité la plus haute
    .order('priority', { foreignTable: 'price_lists', ascending: false })
    .order('min_quantity', { ascending: false })
    .limit(1)

  const line = data?.[0]
  if (!line) return null
  return {
    unitPrice: Number(line.unit_price),
    discount: Number(line.discount_percent || 0),
  }
}
```

Compléments indispensables :
- Ajouter `valid_from` / `valid_to` et `priority` sur `price_lists` : sans elles, deux tarifs concurrents donnent un résultat arbitraire.
- Gérer les tarifs par **catégorie de client** en plus des tarifs nominatifs.
- Gérer les tarifs en pourcentage d'un autre tarif (« liste publique −15 % »), motif très courant.
- Afficher à la saisie **d'où vient le prix** — le vendeur doit pouvoir le justifier.

**Critère d'acceptation.** Un client rattaché à un tarif remisé voit ce prix s'appliquer automatiquement à la saisie, avec l'origine affichée.

---

### `VTE-02` — Contrôle d'encours client

**Majeur.**

**État actuel.** `customers` porte `credit_limit` et `credit_used`. Aucun trigger n'alimente `credit_used`, et aucun ne bloque une commande qui dépasse la limite. `89_medium_priority_business_functions.sql:249` se contente de *recommander* une limite par scoring.

Dans Sage Gestion Commerciale, le dépassement d'encours bloque la saisie ou déclenche une validation hiérarchique — c'est la protection de base du poste client.

**Actions.**

```sql
CREATE OR REPLACE FUNCTION check_customer_credit_limit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_limit numeric; v_outstanding numeric;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status <> 'confirmed' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(credit_limit,0) INTO v_limit
  FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  IF v_limit <= 0 THEN RETURN NEW; END IF;   -- 0 = pas de plafond

  -- encours = factures non soldées + commandes confirmées non facturées
  SELECT COALESCE(sum(amount_due),0) INTO v_outstanding
  FROM invoices
  WHERE customer_id = NEW.customer_id AND tenant_id = NEW.tenant_id
    AND payment_state IN ('not_paid','partial');

  IF v_outstanding + NEW.total > v_limit THEN
    RAISE EXCEPTION
      'Encours dépassé : % + % > limite % — validation requise',
      v_outstanding, NEW.total, v_limit;
  END IF;

  UPDATE customers SET credit_used = v_outstanding + NEW.total
  WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END; $$;

CREATE TRIGGER check_credit_limit BEFORE UPDATE ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION check_customer_credit_limit();
```

Compléments : trois niveaux de politique (bloquant / alerte / information), gestion des clients bloqués manuellement, et prise en compte de l'assurance-crédit si elle existe.

**Critère d'acceptation.** Une commande portant l'encours au-delà de la limite est refusée avec un message exploitable, et `credit_used` reflète l'encours réel.

---

### `VTE-03` — Remises, escomptes, conditions de règlement

**État actuel.** `discount` existe sur les lignes ; `calculate_payment_due_dates` (`88:786`) calcule les échéances.

**Manquent :** les remises en cascade (ligne, pied, client), les remises de fin d'année, l'escompte pour paiement anticipé, et les échéances multiples sur une facture.

**Actions.**

1. Implémenter la cascade de remises avec ordre explicite et affichage du prix net à chaque étape.
2. Escompte conditionnel : « 2 % à 10 jours, net à 30 » — avec génération de l'écriture d'escompte (665) au règlement anticipé.
3. Échéances multiples : une facture peut porter plusieurs lignes d'échéance (30/60/90), chacune lettrable séparément.
4. Remises de fin d'année : accumulation par client et par palier, provision comptable en fin d'exercice.

**Critère d'acceptation.** Une facture à trois échéances génère trois lignes d'échéance distinctes dans la balance âgée.

---

### `VTE-04` — Relances et recouvrement

**État actuel.** `cron-payment-reminders` existe, `CollectionDashboardPage` et `payment_promises` aussi. Bonne base.

**Actions.**

1. Scénarios de relance paramétrables : niveaux, délais, canaux (e-mail, courrier, téléphone), modèles de courrier.
2. Déclenchement automatique sur la base de l'échéancier réel (`echeance_date`, cf. `ACC-01`).
3. Suivi des promesses de paiement et alerte sur promesse non tenue.
4. Escalade : mise en demeure, passage en contentieux, provision pour dépréciation (491) et passage en créance douteuse (416).
5. Indicateur DSO par client et global.

**Critère d'acceptation.** Une facture échue depuis 15 jours déclenche automatiquement la relance de niveau 1 et l'enregistre dans l'historique client.

---

## 9. Banque — `BNQ`

**4,5 → 9,5.**

---

### `BNQ-01` — Parsers de formats bancaires normés

**Bloquant. Enjeu de conformité et de confidentialité.**

**État actuel.** L'écran d'import propose `MT940` et `Camt.053` dans un menu, et le sous-titre annonce « CFONB, MT940, Camt.053 ». Une recherche exhaustive du dépôt ne trouve ces termes que dans `BankStatementImportPage.tsx:98-99` et dans les trois fichiers de traduction. **Aucun analyseur n'existe.**

Le seul chemin d'import réel est l'edge function `parse-bank-statement`, qui envoie le relevé à OpenAI. C'est ingénieux pour un format inconnu, mais inadapté comme mécanisme principal : le résultat n'est pas reproductible, il n'est pas auditable devant un contrôle, et **les données bancaires du client transitent par un tiers**.

**Actions.**

```typescript
// CAMT.053 est du XML strictement typé — l'analyse tient en ~80 lignes
export function parseCamt053(xml: string): BankTransaction[] {
  const doc = new DOMParser().parseFromString(xml, 'application/xml')
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.053.001.02'
  const out: BankTransaction[] = []

  for (const entry of Array.from(doc.getElementsByTagNameNS(ns, 'Ntry'))) {
    const amt    = entry.getElementsByTagNameNS(ns, 'Amt')[0]
    const cdtDbt = text(entry, ns, 'CdtDbtInd')          // CRDT | DBIT
    const bookg  = entry.getElementsByTagNameNS(ns, 'BookgDt')[0]

    out.push({
      date:      text(bookg, ns, 'Dt'),
      valueDate: text(entry.getElementsByTagNameNS(ns,'ValDt')[0], ns, 'Dt'),
      amount:    Number(amt?.textContent ?? 0),
      currency:  amt?.getAttribute('Ccy') ?? 'EUR',
      type:      cdtDbt === 'CRDT' ? 'credit' : 'debit',
      label:     text(entry, ns, 'AddtlNtryInf'),
      // référence structurée : la clé d'un rapprochement fiable
      reference: text(entry, ns, 'Ref') || text(entry, ns, 'EndToEndId'),
    })
  }
  return out
}
```

- **MT940** se lit ligne à ligne sur ses balises `:61:` (mouvement) et `:86:` (libellé). Une journée de travail.
- **CFONB 120** est un format à position fixe, encore très répandu en France. Une journée.
- **OFX** est du SGML/XML. Une demi-journée.

Conserver l'edge function LLM en **repli explicite** pour les PDF et les formats propriétaires — et le signaler à l'utilisateur quand elle sert, avec une étape de validation manuelle obligatoire.

Ajouter dans tous les cas une **détection de doublons** à l'import : même compte, même date, même montant, même référence.

**Critère d'acceptation.** Un fichier CAMT.053 réel de banque française s'importe sans intervention, avec dates de valeur et références structurées ; le même fichier importé deux fois ne crée pas de doublon.

---

### `BNQ-02` — Rapprochement par score

**Majeur.**

**État actuel.** `auto_reconcile_bank_transaction` (`90:376`) cherche une facture dont le total est à moins d'un centime du mouvement, et s'arrête au premier résultat. Il ne gère ni le paiement partiel, ni le règlement groupé, ni la référence structurée, ni le libellé. La table `bank_reconciliation_rules` existe — le trigger ne la consulte jamais. Et le rapprochement pose `matched = true` sans générer d'écriture ni de lettrage.

**Actions.**

```sql
-- remplacer la sélection unique par un classement multi-critères
SELECT i.*,
  (CASE WHEN ABS(i.amount_due - NEW.amount) < 0.01              THEN 50 ELSE 0 END
 + CASE WHEN NEW.label ILIKE '%' || i.number || '%'             THEN 40 ELSE 0 END
 + CASE WHEN NEW.reference = i.payment_reference               THEN 40 ELSE 0 END
 + CASE WHEN NEW.label ILIKE '%' || c.name || '%'               THEN 20 ELSE 0 END
 + CASE WHEN i.due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 10 ELSE 0 END
  ) AS score
INTO v_invoice
FROM invoices i
JOIN customers c ON c.id = i.customer_id AND c.tenant_id = NEW.tenant_id
WHERE i.tenant_id = NEW.tenant_id
  AND i.payment_state IN ('not_paid','partial')
ORDER BY score DESC
LIMIT 1;

-- rapprocher seul au-dessus du seuil, proposer en dessous
IF v_invoice.score >= 70 THEN
  -- … créer le règlement, l'écriture de banque et le lettrage
ELSIF v_invoice.score >= 40 THEN
  INSERT INTO bank_reconciliation_suggestions(...) VALUES (...);
END IF;
```

Compléments :
1. **Exploiter `bank_reconciliation_rules`** : règles par libellé (« VIR SEPA URSSAF » → compte 431), par montant récurrent, par contrepartie.
2. **Rapprochement n-à-n** : un virement soldant trois factures, ou trois virements soldant une facture.
3. **Générer l'écriture** au rapprochement, et lettrer la ligne client ou fournisseur.
4. Écran de rapprochement en deux colonnes avec suggestions classées par score — le paradigme d'Odoo, très efficace.

**Critère d'acceptation.** Sur un relevé de 100 mouvements d'un dossier réel, plus de 80 % sont rapprochés automatiquement sans faux positif.

---

### `BNQ-03` — État de rapprochement bancaire

**État actuel.** `BankReconciliationPage` et `reconciliation-pdf` existent.

**Actions.** Produire l'état de rapprochement formel : solde du relevé, solde comptable, liste des écritures en rapprochement (chèques émis non débités, remises non créditées), et égalité vérifiée. C'est le document que le commissaire aux comptes demande. Le figer et l'archiver à chaque clôture mensuelle.

**Critère d'acceptation.** L'état affiche l'égalité solde bancaire ± écritures en rapprochement = solde comptable.

---

### `BNQ-04` — SEPA complet

**Mineur.**

**État actuel.** `src/lib/sepa.ts` génère un `pain.001.001.03` propre, avec échappement XML correct.

**Manquent :** la devise est figée à `EUR` en dur (`sepa.ts:64`) ; le prélèvement `pain.008` n'existe pas — donc pas de prélèvement client, alors que ce serait le complément naturel du module Recouvrement.

**Actions.**

1. Rendre la devise dynamique.
2. Implémenter `pain.008.001.02` (prélèvement SEPA) avec gestion des mandats : RUM, date de signature, séquence (FRST/RCUR/FNAL/OOFF).
3. Ajouter la version `pain.001.001.09`, attendue par un nombre croissant de banques depuis la migration ISO 20022.
4. Valider l'IBAN par la clé mod-97 **avant** génération, en réutilisant l'edge function `verify-iban` déjà présente.
5. Traiter les fichiers de retour : `pain.002` (statut) et `camt.054` (avis), pour connaître les rejets de prélèvement.

**Critère d'acceptation.** Un fichier `pain.008` généré est accepté par le portail d'une banque française ; les rejets remontent automatiquement.

---

## 10. Trésorerie — `TRE`

**6,5 → 9,5.** Avec les achats, le module le plus solide du volet exploitation : prévisionnel via RPC `cash_flow_forecast`, positions consolidées multi-comptes, lignes de crédit, placements, dates de valeur, virements internes, mouvements récurrents, ordres de paiement.

---

### `TRE-01` — Prévisionnel enrichi

**Actions.**

1. Alimenter le prévisionnel depuis toutes les sources : échéancier client (`ACC-01`), échéancier fournisseur, paie (dates de virement et d'échéance de charges), TVA, échéances de crédit, abonnements.
2. Trois scénarios en parallèle : pessimiste, réaliste, optimiste, avec taux de retard de paiement paramétrable par client.
3. Position quotidienne sur 13 semaines glissantes — l'horizon standard de la gestion de trésorerie.
4. Alerte sur franchissement de seuil de découvert autorisé.

**Critère d'acceptation.** Le prévisionnel à 13 semaines intègre automatiquement les échéances des factures ouvertes, sans ressaisie.

---

### `TRE-02` — Multidevise et couverture

**Actions.**

1. Réévaluation périodique des comptes en devise, avec écriture d'écart (476/477 puis 666/766).
2. `refresh-exchange-rates` existe déjà : l'utiliser pour une réévaluation automatique en fin de mois.
3. Modéliser les contrats de couverture de change et leur dénouement.

**Critère d'acceptation.** Un compte en dollars réévalué au taux de clôture génère son écriture d'écart de conversion.

---

## 11. Point de vente — `POS`

**2,0 → 9,5.** Le module le plus en retrait de toute l'application.

---

### `POS-01` — Comptabiliser et décrémenter le stock

**Bloquant.**

**État actuel.** Les quatre tables `pos_sessions`, `pos_terminals`, `pos_tickets`, `pos_ticket_lines` ne portent **qu'un seul trigger chacune : `set_tenant_id`**. Il n'en existe aucun autre.

Concrètement, une vente en caisse ne décrémente pas le stock, ne génère aucune écriture — ni chiffre d'affaires, ni TVA collectée, ni encaissement — et ne produit aucune facture. Les tickets s'accumulent dans une table que rien ne lit.

**Actions.**

```sql
CREATE OR REPLACE FUNCTION post_pos_session_on_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_entry_id uuid; v_ht numeric; v_vat numeric; v_ttc numeric;
BEGIN
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN RETURN NEW; END IF;

  SELECT COALESCE(sum(subtotal),0), COALESCE(sum(vat_total),0), COALESCE(sum(total),0)
  INTO v_ht, v_vat, v_ttc
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'completed';

  IF v_ttc = 0 THEN RETURN NEW; END IF;

  -- 1. écriture de caisse — en 'draft' puis 'posted' (cf. SOC-01)
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status,
                               description, piece_number)
  VALUES (NEW.tenant_id, 'JE-POS-' || NEW.id, NEW.closed_at::date, 'CA',
          'draft', 'Clôture caisse ' || NEW.id, 'POS-' || NEW.id)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general,
                             debit, credit, description, line_order) VALUES
    (NEW.tenant_id, v_entry_id, '531000','531000', v_ttc, 0, 'Caisse',          0),
    (NEW.tenant_id, v_entry_id, '707000','707000', 0, v_ht,  'Ventes comptoir', 1),
    (NEW.tenant_id, v_entry_id, '4457000','4457000', 0, v_vat,'TVA collectée',  2);

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  -- 2. sorties de stock, valorisées au CUMP courant
  INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity,
                               unit_cost, reference, reference_type, reference_id,
                               date, movement_date, warehouse_id)
  SELECT NEW.tenant_id, l.product_id, 'out','out', sum(l.quantity),
         max(COALESCE(sq.unit_cost, p.cost_price, 0)),
         'POS-' || NEW.id, 'pos_session', NEW.id,
         NEW.closed_at::date, NEW.closed_at::date, t.warehouse_id
  FROM pos_ticket_lines l
  JOIN pos_tickets tk   ON tk.id = l.ticket_id   AND tk.tenant_id = NEW.tenant_id
  JOIN pos_terminals t  ON t.id = tk.terminal_id AND t.tenant_id  = NEW.tenant_id
  JOIN products p       ON p.id = l.product_id   AND p.tenant_id  = NEW.tenant_id
  LEFT JOIN stock_quantities sq ON sq.product_id = l.product_id
        AND sq.warehouse_id = t.warehouse_id AND sq.tenant_id = NEW.tenant_id
  WHERE tk.session_id = NEW.id AND l.product_id IS NOT NULL
  GROUP BY l.product_id, t.warehouse_id;

  RETURN NEW;
END; $$;

CREATE TRIGGER post_pos_session AFTER UPDATE ON pos_sessions
  FOR EACH ROW EXECUTE FUNCTION post_pos_session_on_close();
```

Affiner ensuite : ventiler la TVA par taux (`ACC-02`), le chiffre d'affaires par famille de produit (`ACC-03`), et l'encaissement par moyen de paiement (`POS-02`).

**Critère d'acceptation.** La clôture d'une session de 10 tickets produit une écriture équilibrée et décrémente le stock de tous les articles vendus.

---

### `POS-02` — Paiements multiples

**Majeur.**

**État actuel.** `pos_tickets` porte `payment_method text` et `amount_paid numeric` : un client qui règle 30 € en espèces et 20 € en carte n'est pas représentable.

**Actions.**

1. Créer `pos_payment_methods` (libellé, type, compte comptable, ouvre le tiroir-caisse ou non) et `pos_payments` (ticket, méthode, montant, référence de transaction).
2. Ventiler l'écriture de clôture par moyen de paiement : 531 espèces, 5112 chèques à encaisser, 5115 cartes bancaires.
3. Gérer le rendu de monnaie et les acomptes.
4. Gérer les avoirs et les retours de marchandise en caisse.

**Critère d'acceptation.** Un ticket réglé en trois moyens produit trois lignes de paiement et trois lignes d'écriture distinctes.

---

### `POS-03` — Conformité loi anti-fraude

**Majeur. Enjeu légal.**

**État actuel.** La loi impose pour un logiciel de caisse un ticket séquentiel inaltérable, un cumul perpétuel (grand total) et une clôture journalière Z archivée. Le journal `nf525_event_log` existe au niveau global mais n'est branché sur **aucun** événement de caisse. En l'état, le module POS n'est pas présentable à un contrôle.

**Le point positif :** `pos_sessions` gère déjà fond d'ouverture, montant de clôture, montant attendu et écart — le contrôle de caisse physique est correctement modélisé.

**Actions.**

1. Numérotation séquentielle des tickets **sans trou**, par terminal, avec compteur atomique en base.
2. Chaînage d'empreintes sur chaque ticket : `hash(ticket_n) = SHA256(données + hash(ticket_n-1))` — la mécanique de `91_nf525_anti_fraud.sql` existe déjà, il faut la brancher.
3. Cumuls perpétuels : grand total du jour, du mois, de l'année, de la vie du terminal — jamais remis à zéro.
4. Clôture Z quotidienne archivée et inaltérable, clôture mensuelle et annuelle.
5. Interdire la suppression d'un ticket : seul l'avoir est possible, et il est chaîné.
6. Journal d'événements : ouverture et fermeture de session, ouverture de tiroir, annulation de ligne, remise exceptionnelle.
7. Export des données au format d'audit demandé par l'administration.

**Critère d'acceptation.** La vérification de la chaîne d'empreintes sur une journée complète passe ; une modification manuelle en base est détectée.

---

### `POS-04` — Ergonomie de caisse

**Actions.** Mode hors ligne avec synchronisation différée (une caisse doit fonctionner sans réseau), lecture de code-barres, écran tactile optimisé, impression de ticket, gestion de la file d'attente, mise en attente d'un ticket, programme de fidélité.

**Critère d'acceptation.** Une session complète se déroule sans connexion réseau et se synchronise au retour.

---

## 12. CRM — `CRM`

**6,0 → 9,5.** Huit écrans, une couverture proche de celle d'Odoo CRM sur le papier — opportunités, activités, campagnes, territoires, prévisions, tickets, contrats, base de connaissances. Ce qui manque, c'est tout ce qui agit sans qu'on le demande.

---

### `CRM-01` — Séquences de relance

**Le correctif le plus rentable du module.**

**État actuel.** Les activités sont saisies à la main, jamais déclenchées.

**Actions.**

1. Créer `crm_sequences` (nom, cible, déclencheur) et `crm_sequence_steps` (rang, délai, canal, modèle, condition de sortie).
2. Déclencher depuis la fonction planifiée qui fait déjà tourner `cron-payment-reminders` — l'infrastructure existe et fonctionne, il suffit de lui donner ce travail.
3. Sortir automatiquement du parcours sur réponse, sur rendez-vous pris ou sur désinscription.
4. Mesurer le taux de conversion par séquence.

**Critère d'acceptation.** Un prospect entré dans une séquence reçoit ses relances aux dates prévues et en sort automatiquement s'il répond.

---

### `CRM-02` — Scoring de lead

**Actions.** Score par règles d'abord (secteur, taille, source, engagement), pondération paramétrable, affichage dans la liste et tri par défaut. Le prédictif viendra ensuite, quand il y aura assez d'historique pour l'entraîner.

**Critère d'acceptation.** La liste des opportunités s'ouvre triée par score décroissant, avec la contribution de chaque critère consultable.

---

### `CRM-03` — Suivi d'e-mails et intégration boîte de réception

**Actions.** Journaliser les envois, suivre ouvertures et clics, rattacher automatiquement les réponses à l'opportunité, et proposer une extension de boîte mail ou une synchronisation IMAP.

**Critère d'acceptation.** Un e-mail envoyé depuis l'opportunité apparaît dans son historique, avec son statut de lecture.

---

## 13. Gestion de projet — `PRJ`

**7,5 → 9,5.** Le module le plus abouti de l'application. Dix-huit routes, quarante-six composants : Gantt éclaté en cinq composants, Kanban, mind-map, burndown, tableau croisé dynamique, vue charge, timeline, calendrier, chat, documents, tâches récurrentes, minuteur, chatter par tâche, colonnes dynamiques typées. C'est la parité de surface avec ClickUp, avec une intégration que ClickUp n'a pas : les projets sont branchés sur la comptabilité analytique et les budgets.

---

### `PRJ-01` — Dépendances et chemin critique

**État actuel.** Les dépendances existent en base (7 fichiers SQL) mais ne sont référencées que dans un seul fichier TypeScript du module. Aucun chemin critique.

**Actions.**

1. Exploiter les dépendances dans le Gantt : les quatre types de liaison (fin-début, début-début, fin-fin, début-fin), avec décalage.
2. Recalculer automatiquement les dates des successeurs au déplacement d'une tâche.
3. Calculer le chemin critique (marge nulle) et le mettre en évidence.
4. Autoriser les dépendances inter-projets — c'est ce qui distingue un outil de portefeuille d'un outil de projet isolé.
5. Détecter les dépendances circulaires et les refuser.

**Critère d'acceptation.** Décaler une tâche du chemin critique décale la date de fin du projet ; décaler une tâche à marge ne la décale pas.

---

### `PRJ-02` — Capacité par ressource

**État actuel.** `WorkloadView` existe. Mais la capacité ne tient pas compte des absences, alors que le module RH détient déjà cette donnée.

**Actions.**

1. Calculer la capacité réelle : contrat, temps partiel, congés approuvés, jours fériés.
2. Croiser avec les affectations pour afficher la surcharge.
3. Proposer un lissage automatique.
4. Alerter à l'affectation d'une personne déjà pleine.

**Critère d'acceptation.** Affecter une personne en congé sur une tâche déclenche une alerte, et la vue charge le montre.

---

### `PRJ-03` — Temps réel multi-utilisateur

**État actuel.** Aucun usage de Supabase Realtime dans toute l'application, hors la souscription d'authentification (`auth.tsx:240`). Les vues sont chargées par requête. Deux personnes travaillant sur le même tableau Kanban ne voient pas les mouvements de l'autre — l'écart le plus perceptible face à ClickUp, Monday ou Notion.

**Actions.**

1. Souscrire aux changements des tâches du projet ouvert :
   ```typescript
   const channel = supabase
     .channel(`project:${projectId}`)
     .on('postgres_changes',
         { event: '*', schema: 'public', table: 'tasks',
           filter: `project_id=eq.${projectId}` },
         (payload) => applyRemoteChange(payload))
     .subscribe()
   ```
2. Vérifier que la RLS s'applique bien aux souscriptions Realtime — elle s'applique, mais il faut l'avoir testé (`SOC-02`).
3. Afficher les curseurs de présence dans les vues collaboratives.
4. Résoudre les conflits d'édition simultanée par horodatage, avec indication visible.
5. Étendre ensuite aux notifications et au chat.

**Critère d'acceptation.** Deux navigateurs ouverts sur le même Kanban : déplacer une carte dans l'un la déplace dans l'autre en moins d'une seconde.

---

### `PRJ-04` — Champs personnalisés

**État actuel.** Absent — zéro occurrence de `custom_field`.

**Actions.** Définition de champs par projet ou par type de tâche (texte, nombre, date, liste, relation), affichage dans les colonnes dynamiques déjà présentes, filtrage et regroupement. La table `DynamicTable` existe : l'infrastructure d'affichage est prête.

**Critère d'acceptation.** Ajouter un champ « Client final » à un projet le rend disponible en colonne, en filtre et en regroupement.

---

### `PRJ-05` — Rentabilité de projet

**L'atout différenciant, à pousser jusqu'au bout.**

**Actions.**

1. Valoriser les temps saisis au coût horaire réel du salarié (issu de la paie) plutôt qu'à un taux forfaitaire.
2. Rapprocher budget, engagé, réalisé et reste à faire par projet et par phase.
3. Calculer la marge par projet : produits facturés moins coûts directs moins quote-part de frais généraux.
4. Facturer au temps passé depuis les feuilles de temps validées.
5. Reconnaissance du revenu à l'avancement pour les projets au forfait.

**Critère d'acceptation.** La fiche projet affiche budget, engagé, réalisé, reste à faire et marge, tous chiffres rapprochables de la comptabilité analytique.

---

### `PRJ-06` — Modèles de projet et jalons

**État actuel.** Chaque projet se construit à vide. Aucun modèle, aucun jalon typé — alors qu'une entreprise de services ou de construction refait toujours la même structure de projet.

**Actions.**

1. Créer `project_templates` : arborescence de tâches, durées, dépendances, affectations par rôle plutôt que par personne, jalons, champs personnalisés (`PRJ-04`).
2. Instancier un modèle en fixant une date de début : toutes les dates se calculent en cascade.
3. Typer les jalons — livraison, validation client, facturation — et les distinguer visuellement dans le Gantt et la timeline.
4. Rattacher les jalons de facturation à l'échéancier de facturation (`PRJ-05`) : un jalon atteint déclenche la facture.
5. Enregistrer un projet existant comme modèle.

**Critère d'acceptation.** Créer un projet depuis un modèle produit 40 tâches datées, avec leurs dépendances et leurs jalons, en un geste.

---

### `PRJ-07` — Référence de planning et suivi d'écart

**État actuel.** `baseline` n'apparaît que dans deux fichiers du module, sans mécanisme.

**Actions.**

1. Figer une **référence** à la validation du planning : dates, charges, budget.
2. Afficher l'écart en permanence : dates prévues contre référence, charge consommée contre référence, budget engagé contre référence.
3. Historiser les références successives (avenants), avec la raison du changement.
4. Courbe en S : avancement prévu contre avancement réel — l'indicateur attendu en gestion de projet mature.
5. Calculer les indicateurs de valeur acquise : indice de performance des délais et indice de performance des coûts.

**Critère d'acceptation.** Un projet en retard de 2 semaines et de 10 % de budget affiche ses deux écarts par rapport à la référence figée.

---

### `PRJ-08` — Automatisations et règles

**État actuel.** Absent côté projet. C'est pourtant la fonction que ClickUp et Monday mettent en avant en premier, et l'infrastructure de tâches planifiées existe déjà dans l'application.

**Actions.**

1. Moteur de règles simple, du type *quand ceci, alors cela* : au changement de statut, à l'approche d'une échéance, à l'affectation, à la création d'une sous-tâche.
2. Actions disponibles : changer un statut, affecter, notifier, créer une tâche, déplacer dans une colonne, poser une date.
3. Éditeur de règle sans code, avec test à blanc avant activation.
4. Journal des exécutions, pour comprendre pourquoi une tâche a bougé toute seule — sans quoi l'automatisation devient anxiogène.
5. Garde-fou anti-boucle : une règle ne peut pas se déclencher en cascade plus de n fois.

**Critère d'acceptation.** Une règle « quand une tâche passe en Terminé, notifier le chef de projet et déplacer la suivante en À faire » s'exécute et se trace.

---

### `PRJ-09` — Portefeuille, permissions et collaboration

**État actuel.** `project_members` existe (`70_project_members.sql`) et `project_docs` porte la documentation collaborative (`67_project_docs.sql`). Les vues `BoxView`, `DocView` et `ChatView` sont en place.

**Manquent :** la vue portefeuille au-dessus des projets, les permissions fines, et le partage externe.

**Actions.**

1. **Portefeuille** : regrouper les projets en programmes, consolider avancement, charge, budget et marge à ce niveau. C'est ce qui manque pour piloter une activité de services.
2. **Permissions par projet** : lecture, contribution, administration — portées par la RLS via `project_members`, pas par le masquage d'interface.
3. **Partage externe** : donner à un client un accès limité en lecture à son projet, via la mécanique de jeton déjà présente (`/shared/:token`).
4. **Documents collaboratifs** : édition simultanée réelle une fois `PRJ-03` livré, historique de versions, commentaires ancrés.
5. **Objectifs** : rattacher les projets à des objectifs d'entreprise et suivre leur contribution.

**Critère d'acceptation.** Un contributeur externe voit uniquement son projet ; le portefeuille consolide l'avancement de dix projets sur un écran.

---

## 14. Reporting & BI — `BI`

**Non noté séparément dans les volets précédents. Cible 9,5.**

**État actuel.** Quinze pages de tableau de bord, une `BIReportingPage`, des filtres sauvegardés (`pilotage.ts:7`), une simulation de chiffre d'affaires et une analyse de marge.

---

### `BI-01` — Générateur d'états

**Actions.** Permettre à l'utilisateur de construire un état sans développeur : choix de la source, des colonnes, des filtres, des regroupements, des totaux ; enregistrement, partage, planification d'envoi par e-mail. C'est la fonction que tout cabinet réclame en premier.

**Critère d'acceptation.** Un comptable construit et planifie un état mensuel sans intervention technique.

---

### `BI-02` — Indicateurs financiers normés

**Actions.** Soldes intermédiaires de gestion complets (le RPC `getSIGData` existe), ratios de structure et de rentabilité, capacité d'autofinancement, besoin en fonds de roulement, seuil de rentabilité, tableau de flux de trésorerie normé. Comparatif N/N-1 et budget/réalisé sur chacun.

**Critère d'acceptation.** Les SIG sont produits et rapprochables ligne à ligne du compte de résultat.

---

### `BI-03` — Performance des tableaux de bord

**État actuel.** 137 agrégations `.reduce()` dans les pages : les tableaux de bord calculent dans le navigateur.

**Actions.** Basculer chaque indicateur sur un RPC, et introduire des vues matérialisées rafraîchies périodiquement pour les indicateurs coûteux. Un tableau de bord doit s'afficher en moins d'une seconde.

**Critère d'acceptation.** Le tableau de bord financier s'affiche en moins d'une seconde sur un dossier de 200 000 écritures.

---

## 15. Couche de données — `DAT`

---

### `DAT-01` — Pagination généralisée

**État actuel.** 29 `.limit()` pour 1 152 fonctions ; 291 `select('*')` sans borne.

**Actions.**

1. Introduire un type de retour paginé uniforme :
   ```typescript
   interface Page<T> { rows: T[]; total: number; page: number; pageSize: number }
   ```
2. Ajouter `page` et `pageSize` à toute fonction de liste, avec un défaut de 50.
3. Faire échouer la CI si une fonction de `queries/` fait un `select` sur une table transactionnelle sans `.range()`.
4. Adopter la pagination par curseur (`created_at`, `id`) sur les tables les plus volumineuses : `journal_lines`, `stock_movements`, `bank_transactions`.

**Critère d'acceptation.** Aucune fonction de requête ne peut rapatrier plus de 1 000 lignes en un appel.

---

### `DAT-02` — Types réels au lieu de `as any[]`

**Actions.** Générer les types depuis le schéma (`supabase gen types typescript`), les régénérer en CI, et remplacer les `as any[]` par les types générés. Le `select('*, relation(*)')` de PostgREST est typable via les helpers de `@supabase/supabase-js`.

**Critère d'acceptation.** Zéro `as any` dans `src/lib/queries/`.

---

### `DAT-03` — Index de couverture

**État actuel.** 1 075 index, dont 398 mentionnant `tenant_id`. Bonne base.

**Actions.**

1. Vérifier que **toute** table métier a un index sur `(tenant_id, …)` en tête — la RLS filtre systématiquement là-dessus.
2. Ajouter les index de couverture des états financiers (`SOC-04`).
3. Activer `pg_stat_statements` et traiter les 20 requêtes les plus coûteuses.
4. Supprimer les index jamais utilisés (`pg_stat_user_indexes` avec `idx_scan = 0`) : ils coûtent à l'écriture.

**Critère d'acceptation.** Aucune requête applicative ne dépasse 200 ms au 95ᵉ centile.

---

## 16. Sécurité — `SEC`

**8,0 → 9,5.** L'axe le plus avancé. Les cinq critiques de l'audit du 3 septembre sont tous corrigés : mot de passe Postgres retiré du runner, RLS balayée par les migrations 74 et 84, `current_tenant_id()` rendu déterministe par la 79, garde anti-secrets au build, déploiement conditionné au succès du CI.

---

### `SEC-01` — Tests d'isolation multi-tenant

Couvert par `SOC-02`. C'est le seul vrai manque de cet axe : 2 208 politiques dont aucune n'est testée. **Sans ce chantier, la note reste à 8 quoi qu'il arrive.**

---

### `SEC-02` — Authentification renforcée

**État actuel.** `93_2fa_email_templates_notifications.sql` existe.

**Actions.** Activer la double authentification par TOTP, la rendre obligatoire pour les rôles d'administration, gérer les codes de secours, expirer les sessions inactives, et journaliser les connexions avec détection de connexion inhabituelle.

**Critère d'acceptation.** Un compte administrateur ne peut pas se connecter sans second facteur.

---

### `SEC-03` — Journal d'audit applicatif

**Actions.** Tracer qui a fait quoi et quand sur les objets sensibles : écritures, bulletins, paramètres, droits. `nf525_event_log` couvre le comptable ; étendre le principe aux données personnelles pour la conformité RGPD.

**Critère d'acceptation.** Toute modification d'un bulletin de paie est tracée avec auteur, horodatage et valeurs avant/après.

---

### `SEC-04` — Conformité RGPD

**Actions.** Registre des traitements, durées de conservation appliquées automatiquement (`payroll_archives.retention_until` existe déjà), export des données d'une personne, suppression sur demande avec conservation des obligations légales, chiffrement des données sensibles au repos, mentions et consentements.

**Critère d'acceptation.** Une demande d'accès produit un export complet et lisible en moins de 24 h.

---

### `SEC-05` — Durcissement du stockage de fichiers

**État actuel.** `68_module_documents_storage_rls.sql` pose les politiques de stockage.

**Actions.** Vérifier le type MIME réel et non l'extension, analyser antivirus, limiter la taille, générer des URL signées de courte durée, et interdire l'accès direct au bucket.

**Critère d'acceptation.** Un fichier renommé en `.pdf` mais qui est un exécutable est refusé.

---

## 17. Performance — `PRF`

**3,0 → 9,5.**

---

### `PRF-01` — Agrégations serveur

Couvert par `SOC-04` et `BI-03`. C'est 80 % de la note de cet axe.

---

### `PRF-02` — Poids du bundle

**État actuel.**

| Chunk | Taille | gzip |
|---|---|---|
| `index` | 1 278 ko | 324 ko |
| `xlsx` | 489 ko | 159 ko |
| `pdf` | 466 ko | 137 ko |
| `charts` | 425 ko | 109 ko |
| `react-vendor` | 280 ko | 90 ko |
| `queries` | 279 ko | 57 ko |

Le découpage par route existe pourtant.

**Actions.**

1. Charger `xlsx` et `pdf` en `import()` dynamique au clic sur le bouton d'export — ils ne servent qu'à ce moment-là. Gain immédiat : 296 ko gzip.
2. Découper le chunk `queries` par domaine, en suivant `SOC-07` : une page comptable ne doit pas charger les requêtes de production.
3. Remplacer la bibliothèque de graphiques par une alternative plus légère, ou ne charger que les types de graphique utilisés.
4. Fixer un budget de performance en CI : échec du build si le chunk d'entrée dépasse 250 ko gzip.

**Critère d'acceptation.** Chunk d'entrée sous 250 ko gzip ; premier affichage utile sous 1,5 s en 4G simulée.

---

### `PRF-03` — Rendu React

**État actuel.** 95 `useMemo` pour 219 pages — peu ; 85 `key={index}`, qui provoquent des remontages inutiles et des états mal réattribués dans les listes réordonnables.

**Actions.**

1. Remplacer `key={index}` par la clé métier (`key={row.id}`).
2. Virtualiser les longues listes (grand livre, mouvements de stock, tâches) avec `@tanstack/react-virtual`.
3. Mémoriser les lignes de tableau et les calculs coûteux.
4. Mesurer avec le profileur React et traiter les rendus supérieurs à 16 ms.

**Critère d'acceptation.** Un grand livre de 10 000 lignes défile à 60 images par seconde.

---

### `PRF-04` — Trigger d'équilibre en `FOR EACH STATEMENT`

**État actuel.** `check_journal_entry_balance` relance un `SUM` complet sur les lignes de l'écriture à chaque ligne insérée. Sur une écriture de dix lignes, dix agrégations. Sur un import FEC de 100 000 lignes, le coût devient quadratique par écriture.

**Actions.** Passer en `FOR EACH STATEMENT` avec une table de transition :
```sql
CREATE CONSTRAINT TRIGGER check_journal_entry_balance
  AFTER INSERT OR UPDATE OR DELETE ON journal_lines
  DEFERRABLE INITIALLY DEFERRED
  REFERENCING NEW TABLE AS nouvelles
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance();
```
La fonction agrège alors une fois sur l'ensemble des écritures touchées.

**Critère d'acceptation.** L'import d'un FEC de 100 000 lignes s'exécute en moins de 60 secondes.

---

## 18. Qualité & tests — `QUA`

**5,5 → 9,5.**

---

### `QUA-01` — Tests de base de données

Couvert par `SOC-02`. **Chantier prioritaire absolu de cet axe.**

---

### `QUA-02` — Tests métier de référence

**État actuel.** Les tests métier (`hr-payroll-business`, `logic-business`) sont de bonne qualité et vérifient de vrais calculs. Mais ils valident le moteur tel qu'il est écrit, pas tel qu'il devrait être : aucun n'aurait détecté l'absence de plafond de sécurité sociale.

**Actions.**

1. Constituer un corpus de **cas de référence externes** : bulletins Sage réels anonymisés, liasses fiscales validées, valorisations de stock calculées à la main.
2. Écrire les tests contre ces références, pas contre le comportement actuel du code.
3. Couvrir systématiquement les cas limites : montant nul, montant négatif, année bissextile, changement de taux en cours d'exercice, salarié entré et sorti le même mois, stock négatif.
4. Ajouter des tests de propriété : « la balance est toujours équilibrée », « la valeur du stock est toujours égale à la somme des couches », « le net à payer est toujours inférieur au brut ».

**Critère d'acceptation.** Chaque calcul métier est confronté à au moins un cas de référence externe.

---

### `QUA-03` — Tests de bout en bout

**État actuel.** 3 specs Playwright pour 337 routes.

**Actions.** Couvrir les dix parcours critiques : devis → commande → livraison → facture → règlement ; achat → réception → facture → paiement ; saisie d'écriture → validation → balance ; bulletin de paie → écriture → DSN ; vente en caisse → clôture → comptabilisation. Faire tourner sur trois navigateurs, avec capture d'écran en cas d'échec.

**Critère d'acceptation.** Les dix parcours passent en CI sur chaque pull request.

---

### `QUA-04` — Couverture mesurée et verrouillée

**Actions.** `test:ci` produit déjà la couverture. Définir un seuil plancher (80 % sur `src/lib/`), et faire échouer la CI en cas de régression.

**Critère d'acceptation.** La couverture de `src/lib/` ne peut plus baisser.

---

## 19. Ergonomie, i18n, accessibilité — `UX`

---

### `UX-01` — i18n : un acquis remarquable

**État actuel.** Trois langues (fr, en, ar), 72 fichiers, parité de clés **vérifiée en CI** et actuellement verte sur les 13 espaces de noms. C'est fait sérieusement et mérite d'être signalé.

**Reste :** le support droite-à-gauche pour l'arabe (au-delà de la traduction), les formats de date, nombre et devise par locale, et le pluriel.

**Actions.**

1. Vérifier `dir="rtl"` sur toute l'interface en arabe : miroir des icônes directionnelles, alignement des tableaux, position des marges.
2. Utiliser `Intl.NumberFormat` et `Intl.DateTimeFormat` partout — `useLocale` existe déjà, il faut généraliser son usage.
3. Gérer les règles de pluriel de i18next.
4. Traduire aussi les libellés du **domaine** : plans comptables, types de contrat, motifs de congé.

**Critère d'acceptation.** L'interface en arabe est intégralement en miroir et les montants s'affichent au format local.

---

### `UX-02` — Accessibilité

**État actuel.** 47 attributs `aria-*` et 23 `role=` pour 219 pages : l'accessibilité n'a pas été traitée. 51 `<div>` ou `<span>` porteurs d'un `onClick` — non atteignables au clavier, invisibles aux lecteurs d'écran.

**Actions.**

1. Remplacer les 51 éléments cliquables non sémantiques par des `<button>`.
2. Parcours clavier complet, avec ordre de tabulation logique et anneau de focus visible.
3. Étiqueter tous les champs de formulaire, associer les messages d'erreur par `aria-describedby`.
4. Annoncer les changements dynamiques par des régions `aria-live` — notamment les notifications.
5. Vérifier les contrastes au niveau AA.
6. Ajouter `eslint-plugin-jsx-a11y` (ou l'équivalent oxlint) en CI.
7. Piloter les modales au clavier : piège de focus, fermeture par Échap, retour du focus à l'ouvrant.

**Critère d'acceptation.** Un audit axe-core ne remonte aucune violation critique sur les dix pages les plus utilisées.

---

### `UX-03` — Remplacer les 127 `window.confirm()`

**État actuel.** 127 appels aux boîtes de dialogue natives du navigateur, alors qu'un `ConfirmDialog` existe dans `ui.tsx`.

Trois problèmes : rupture visuelle complète, blocage du fil d'exécution, et impossibilité de traduire ou d'expliquer l'action.

**Actions.** Remplacer par le composant maison, avec un message qui dit ce qui va se passer (« Supprimer la facture FA-2026-014 ? Cette action est irréversible. ») plutôt que « Êtes-vous sûr ? ». Interdire `window.confirm` par une règle de lint.

**Critère d'acceptation.** Zéro `window.confirm` dans `src/`.

---

### `UX-04` — États de chargement, vide et erreur

**État actuel.** `SkeletonTable` et `EmptyState` existent et sont bien conçus.

**Actions.** Les généraliser à toutes les pages, avec un état vide qui propose l'action suivante plutôt que de constater l'absence de données, et un état d'erreur qui offre de réessayer.

**Critère d'acceptation.** Aucune page n'affiche un écran blanc pendant le chargement.

---

### `UX-05` — Saisie comptable au clavier

**Le détail qui décide de l'adoption par un comptable.**

**Actions.** Dans `JournalSaisiePage`, permettre une saisie entièrement au clavier : Entrée pour valider et passer à la ligne suivante, complétion automatique du compte à la frappe, équilibrage automatique de la dernière ligne, mémorisation de la dernière écriture, écritures types, duplication. Un comptable saisit 200 écritures par jour : chaque clic évité compte.

**Critère d'acceptation.** Saisir une écriture à quatre lignes sans jamais toucher la souris.

---

## 20. Conformité réglementaire — `CNF`

**5,0 → 9,5.**

---

### `CNF-01` — Raccorder les quatre intégrations en simulation

**Majeur.**

**État actuel.** Quatre edge functions retournent `mode: "simulation"` avec un message explicite lorsque l'API cible n'est pas configurée. Le comportement est honnête et bien codé — mais signifie que ces canaux **ne sont pas raccordés** :

| Fonction | Canal | Ligne |
|---|---|---|
| `transmit-dsn` | net-entreprises | 61 |
| `submit-vat-return` | télédéclaration CA3 (EFI/EDI) | 64 |
| `submit-e-invoice` | Chorus Pro / PEPPOL | 72, 145 |
| `request-signature` | Yousign / Universign | 39, 113 |

Les dix-sept autres edge functions sont des implémentations réelles.

**Actions.**

1. Ouvrir les comptes et obtenir les certificats de chacun des quatre canaux — c'est souvent le chemin le plus long, à lancer en premier.
2. Implémenter les échanges réels avec gestion des retours, des rejets et des relances.
3. **Afficher clairement à l'utilisateur** quand le mode simulation est actif, plutôt que de retourner un succès — c'est le point le plus urgent, et il coûte une heure.
4. Journaliser chaque transmission avec son accusé de réception.

**Critère d'acceptation.** Une DSN de test est acceptée par net-entreprises et son accusé est archivé.

---

### `CNF-02` — Facturation électronique

**Enjeu de calendrier réglementaire.**

**Actions.** Générer et lire les trois formats du socle (Factur-X, UBL, CII), se raccorder à une plateforme agréée, gérer les statuts du cycle de vie de la facture, et transmettre les données de transaction et de paiement (e-reporting).

**Critère d'acceptation.** Une facture Factur-X générée est validée par un outil de contrôle de conformité.

---

### `CNF-03` — Certification NF525

**État actuel.** La structure est là : journal d'événements inaltérable à chaînage SHA-256, clôture et empreinte annuelle (`91_nf525_anti_fraud.sql`). C'est ce qu'attend un certificateur.

**Manquent :** le branchement effectif sur tous les événements (notamment la caisse, cf. `POS-03`), la procédure de vérification d'intégrité exposée à l'utilisateur, l'archivage à valeur probante, et la documentation exigée par l'organisme certificateur.

**Actions.**

1. Brancher le journal sur tous les événements : facture, écriture, bulletin, ticket de caisse, paramétrage.
2. Exposer un écran de vérification d'intégrité que l'utilisateur peut lancer lui-même.
3. Archivage à valeur probante : horodatage qualifié, conservation dix ans, restitution.
4. Constituer le dossier de certification (documentation, procédures, tests).

**Critère d'acceptation.** Un audit blanc mené selon le référentiel NF525 ne relève aucune non-conformité majeure.

---

## 21. Paramétrage & administration — `ADM`

**Non noté dans les volets précédents. Cible 9,5.**

**23 routes** — le troisième module de l'application par le nombre d'écrans, derrière la comptabilité et les RH : `company-settings`, `multi-company`, `configuration`, `data`, `company`, `chart-accounts`, `users`, `team`, `integrations`, `modules`, `data-export`, `import`, `import/sage`, `currencies`, `exchange-rates`, `tax-grids`, `api-webhooks`, `email-templates`, `2fa`, `api-docs`, `document-templates`, plus `system/fiscal-years` et `system/audit-log`.

C'est le module qu'on n'ouvre jamais en démonstration et qui décide de la mise en service réelle.

---

### `ADM-01` — Assistant de paramétrage initial

**État actuel.** `/onboarding` existe, et `02_bootstrap_tenant.sql` crée un dossier vide. Mais le paramétrage se fait ensuite écran par écran, sans guide ni ordre.

Un dossier comptable non paramétré produit des écritures fausses en silence — c'est le lien direct avec `ACC-04` et `STK-04`.

**Actions.**

1. Assistant en étapes ordonnées, avec état d'avancement persistant : identité et forme juridique → législation et devise → exercice et périodicité → plan comptable → journaux → comptes par défaut → taux de TVA → modes de règlement → méthode de valorisation de stock → utilisateurs.
2. **Bloquer les opérations tant que le paramétrage minimal n'est pas complet** — plutôt que de laisser passer une écriture sur un compte inexistant.
3. Modèles de dossier par secteur : négoce, industrie, services, bâtiment — chacun avec son plan comptable pré-rempli et ses journaux.
4. Écran de santé du dossier : ce qui est paramétré, ce qui manque, ce qui est incohérent.

**Critère d'acceptation.** Un nouveau dossier passe de la création à la première facture validée en moins de 30 minutes, sans intervention technique.

---

### `ADM-02` — Rôles et permissions

**État actuel.** `tenant_users` porte un rôle, `AdminRoute` protège certaines routes côté interface, et `38_security_fix_role_escalation_and_auditor.sql` traite l'escalade de privilèges. Il existe donc une base sérieuse.

**Manquent :** les rôles personnalisables, les permissions fines par objet et par action, et la séparation des tâches — obligatoire en environnement comptable.

**Actions.**

1. Créer `roles` et `role_permissions` : permissions au format `objet.action` (`invoice.create`, `journal_entry.post`, `payslip.view`, `bank_account.export`).
2. Rôles livrés par défaut : administrateur, comptable, aide-comptable, gestionnaire de paie, commercial, magasinier, chef de projet, lecteur, auditeur externe.
3. **Faire porter les permissions par la RLS**, pas seulement par le masquage d'interface — une route cachée reste appelable par l'API.
4. **Séparation des tâches** : la personne qui saisit un règlement fournisseur ne doit pas pouvoir le valider. C'est un contrôle attendu par les commissaires aux comptes.
5. Restriction par périmètre : un commercial ne voit que ses clients, un magasinier que son entrepôt, un chef de projet que ses projets.
6. Accès auditeur externe à durée limitée — le mécanisme existe (`trigger_revoke_expired_auditors`), il faut l'exposer.

**Critère d'acceptation.** Un utilisateur au rôle « aide-comptable » qui appelle directement l'API pour valider une écriture reçoit un refus de la base, pas seulement de l'interface.

---

### `ADM-03` — Paramétrage comptable et fiscal

**État actuel.** `chart-accounts`, `tax-grids`, `currencies`, `exchange-rates`, `system/fiscal-years` existent. Les grilles fiscales paramétrables sont une bonne intuition (`PAY-02`, `ACC-04`).

**Actions.**

1. Centraliser les **comptes par défaut** du dossier dans un écran unique — c'est le support de `ACC-04` : client, fournisseur, ventes, achats, TVA collectée, TVA déductible, stock, variation de stock, caisse, banque, charges de personnel, écarts.
2. Import du plan comptable depuis un modèle de législation, avec possibilité d'ajout et de renommage sans casser les correspondances.
3. Versionner les taux de TVA dans le temps : un changement de taux ne doit pas modifier rétroactivement les factures antérieures.
4. Journaux : type, contrepartie, numérotation, compte de contrepartie automatique.
5. Écran de contrôle de cohérence du paramétrage : compte par défaut pointant vers un compte inexistant, taux de TVA sans compte associé, journal sans contrepartie.

**Critère d'acceptation.** Le changement du taux normal de TVA au 1ᵉʳ janvier laisse inchangées les factures de décembre.

---

### `ADM-04` — Modèles de documents et personnalisation

**État actuel.** `/settings/document-templates` et `/settings/email-templates` existent, avec `93_2fa_email_templates_notifications.sql`.

**Actions.**

1. Éditeur de modèle avec aperçu en direct et variables documentées, par type de document : devis, commande, bon de livraison, facture, avoir, relance, bulletin, ordre de fabrication.
2. Logo, couleurs, polices, mentions légales, conditions générales par dossier.
3. Modèle par langue et par client — indispensable dès qu'il y a de l'export.
4. Numérotation paramétrable par type et par exercice, avec préfixe, longueur et remise à zéro.
5. Prévisualisation avec des données réelles avant activation.

**Critère d'acceptation.** Un dossier personnalise sa facture (logo, couleurs, mentions) et en obtient un aperçu fidèle sans redéploiement.

---

### `ADM-05` — Journal d'audit exposé

**État actuel.** `/system/audit-log` existe, ainsi que `audit_schema.sql` et `nf525_event_log`.

**Actions.**

1. Unifier les sources de traçabilité en un seul journal consultable : qui, quoi, quand, valeurs avant et après.
2. Filtres par utilisateur, objet, période, type d'action.
3. Export du journal pour un contrôle.
4. Rétention paramétrable et archivage au-delà.
5. Alerte sur action sensible : suppression en masse, changement de droits, export de données personnelles.

**Critère d'acceptation.** Retrouver en moins d'une minute qui a modifié un compte bancaire fournisseur et quelle était la valeur précédente.

---

## 22. Import & reprise de données — `IMP`

**Non noté dans les volets précédents. Cible 9,5.**

**On ne met pas un client en production sans reprendre son historique.** C'est le premier obstacle commercial d'un progiciel de gestion, et il est traité ici de façon inégale.

**État actuel.** Trois écrans — `ImportPage` (chunk de 47 ko, le plus lourd hors bibliothèques), `SageImportPage`, `BankStatementImportPage` — plus une edge function `ai-import-mapping` de 268 lignes avec dictionnaire de synonymes enrichi. L'intention est bonne et la correspondance assistée par modèle de langage est une vraie idée.

---

### `IMP-01` — Reprise de balance et d'historique comptable

**Actions.**

1. Import de la **balance d'ouverture** : par compte, par compte auxiliaire, avec contrôle d'équilibre avant validation.
2. Import du **détail des écritures** depuis un FEC — le format est normé, l'application sait déjà l'exporter, elle doit savoir le lire.
3. Import des **factures ouvertes** clients et fournisseurs avec leurs échéances, pour alimenter la balance âgée et le prévisionnel dès le premier jour.
4. Reprise du **lettrage** existant.
5. Rapport de reprise : ce qui est entré, ce qui est rejeté, pourquoi.

**Critère d'acceptation.** Reprendre un FEC de 50 000 lignes produit une balance identique à celle du logiciel d'origine, au centime près.

---

### `IMP-02` — Import générique fiable

**Actions.**

1. Assistant en quatre temps : téléverser → faire correspondre les colonnes → **prévisualiser et valider** → importer.
2. **Toujours faire précéder l'import d'un contrôle à blanc** qui liste les erreurs ligne par ligne, sans rien écrire. C'est la différence entre un import et un accident.
3. Import **transactionnel** : tout ou rien, avec possibilité d'annulation après coup via un identifiant de lot.
4. Conserver la correspondance de colonnes comme modèle réutilisable — l'edge function `ai-import-mapping` la propose, il faut la persister.
5. Traiter les gros volumes par lots avec barre de progression, plutôt qu'en une requête qui expire.
6. Rapport téléchargeable des lignes rejetées, au format d'origine, corrigeable et réimportable.

**Critère d'acceptation.** Un fichier de 10 000 articles dont 50 lignes sont invalides produit un rapport exploitable et n'écrit rien tant que l'utilisateur n'a pas validé.

---

### `IMP-03` — Reprise des tiers, articles, stocks et salariés

**Actions.**

1. Modèles de fichier téléchargeables, par objet, avec les colonnes obligatoires signalées.
2. **Déduplication** à l'import : détecter un client déjà présent par SIRET, par nom approché ou par e-mail, et proposer la fusion.
3. Reprise du **stock initial** : quantités et valeurs unitaires, générant les mouvements `'initial'` valorisés (`STK-01`).
4. Reprise des **salariés** avec leurs cumuls de l'année en cours — sans quoi la régularisation progressive (`PAY-04`) part d'un cumul faux dès le premier bulletin.
5. Reprise des **immobilisations** avec valeur d'origine, amortissements déjà pratiqués et durée restante.

**Critère d'acceptation.** Un salarié repris en cours d'année voit son premier bulletin tenir compte des cumuls antérieurs.

---

### `IMP-04` — Passerelle de migration depuis les concurrents

**État actuel.** `SageImportPage` existe — bonne intuition commerciale.

**Actions.** Documenter et fiabiliser les formats d'export des principaux logiciels du marché, et livrer une correspondance pré-établie pour chacun. Le coût de sortie d'un concurrent est le premier argument de vente d'un progiciel de gestion.

**Critère d'acceptation.** L'export standard d'un logiciel concurrent s'importe sans correspondance manuelle.

---

## 23. API publique, webhooks, intégrations — `API`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** Base réelle et bien pensée : `92_api_and_webhooks_tables.sql` définit `api_keys` et `webhook_endpoints` ; les edge functions `public-api` (243 lignes) et `outgoing-webhooks` (182 lignes) sont implémentées ; `/settings/api-docs` et `/settings/api-webhooks` existent.

---

### `API-01` — API publique de qualité professionnelle

**Actions.**

1. Publier une **spécification OpenAPI** générée depuis le code, pas rédigée à la main — sans quoi elle diverge en trois mois.
2. Versionner l'API (`/v1/`) et documenter la politique d'obsolescence.
3. Pagination, tri et filtrage uniformes sur toutes les collections, cohérents avec `DAT-01`.
4. Limitation de débit par clé, avec en-têtes de quota restant, et remontée explicite du dépassement.
5. **Portée des clés** : une clé doit pouvoir être limitée en lecture seule, ou à un domaine (facturation uniquement). Une clé qui donne accès à tout le dossier est un risque disproportionné.
6. Idempotence sur les créations, par en-tête `Idempotency-Key` — indispensable pour qu'un client puisse réessayer sans créer de doublon.
7. Format d'erreur uniforme, avec code stable et message exploitable.
8. Journal des appels par clé, consultable par le client.

**Critère d'acceptation.** Un développeur tiers intègre la création de facture en moins d'une heure à partir de la seule documentation.

---

### `API-02` — Webhooks fiables

**Actions.**

1. Catalogue d'événements documenté : facture validée, règlement reçu, stock sous seuil, OF terminé, bulletin disponible.
2. **Signature HMAC** de chaque envoi, avec secret par point de terminaison, pour que le destinataire puisse vérifier l'origine.
3. Réessais avec temporisation exponentielle, et file d'attente des échecs consultable.
4. Livraison **au moins une fois** avec identifiant d'événement, pour que le destinataire puisse dédupliquer.
5. Écran de test : envoyer un événement factice et voir la réponse.
6. Désactivation automatique d'un point de terminaison en échec permanent, avec notification.

**Critère d'acceptation.** Un point de terminaison indisponible pendant une heure reçoit tous les événements manqués à son rétablissement.

---

### `API-03` — Connecteurs métier

**État actuel.** Les intégrations existantes sont réelles : `verify-siret`, `verify-iban`, `validate-vat-vies`, `refresh-exchange-rates`, `sync-bank-transactions`, `handle-stripe-webhook`, `ocr-invoice-import`.

**Actions.** Prioriser selon la demande client plutôt que par exhaustivité : agrégation bancaire, encaissement en ligne, signature électronique (`CNF-01`), plateforme de facturation électronique (`CNF-02`), messagerie et agenda, puis marketplace pour les besoins de niche.

**Critère d'acceptation.** Chaque connecteur dispose d'un écran de configuration, d'un test de connexion et d'un journal d'échange.

---

## 24. Notifications — `NOT`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** `71_notification_email_system.sql` définit `notification_email_queue` et `notification_preferences` ; l'edge function `send-notification-email` existe ; le module projet a sa propre `NotificationsView` ; `cron-payment-reminders` tourne.

Les briques sont là mais fonctionnent en silos : chaque module notifie à sa façon.

---

### `NOT-01` — Centre de notifications unifié

**Actions.**

1. Un seul journal de notifications pour toute l'application, avec type, objet concerné, gravité et lien de rebond.
2. Cloche unique dans l'en-tête, avec compteur de non-lues et regroupement par type.
3. Préférences par utilisateur et par type d'événement : dans l'application, par e-mail immédiat, dans un résumé quotidien, ou jamais.
4. **Regroupement** : dix tâches assignées en dix minutes produisent une notification, pas dix.
5. Marquer comme lu, tout marquer, archiver.

**Critère d'acceptation.** Un utilisateur règle ses préférences une fois et ne reçoit plus que ce qu'il a demandé, quel que soit le module émetteur.

---

### `NOT-02` — Alertes métier proactives

**Actions.**

1. Alertes comptables : échéance de TVA, période non clôturée, écriture en brouillard depuis trop longtemps, balance déséquilibrée.
2. Alertes de trésorerie : franchissement de seuil de découvert, échéance importante à venir.
3. Alertes commerciales : dépassement d'encours (`VTE-02`), facture échue, devis expirant.
4. Alertes de stock : rupture, seuil d'alerte, article dormant, péremption proche.
5. Alertes RH : fin de période d'essai, fin de CDD, entretien annuel à programmer, document expirant.
6. Seuils paramétrables par dossier, jamais codés en dur.

**Critère d'acceptation.** Les six familles d'alertes sont paramétrables et se déclenchent aux seuils définis.

---

### `NOT-03` — Canaux de diffusion

**Actions.** E-mail via l'infrastructure existante ; notifications navigateur ; résumé quotidien ou hebdomadaire ; et, pour les alertes critiques uniquement, un canal externe (messagerie d'équipe ou SMS). Ne pas multiplier les canaux : trois bien faits valent mieux que six mal réglés.

**Critère d'acceptation.** Une alerte critique atteint son destinataire par au moins un canal en moins de cinq minutes.

---

## 25. Documents & dématérialisation — `GED`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** Base substantielle : `queries/documents.ts` (434 lignes), `dematerialisation.ts`, `dematRh.ts`, `project_docs` (`67`), politiques de stockage (`68_module_documents_storage_rls.sql`), edge functions `generate-pdf`, `ocr-invoice-import`, `request-signature`, coffre-fort salarié (`EmployeeDocumentsPage`), et un module documents dans la gestion de projet.

---

### `GED-01` — Rattachement universel

**Actions.**

1. Permettre le rattachement d'un document à **n'importe quel objet** — facture, écriture, salarié, projet, article, tiers, OF — par une table de liaison polymorphe unique, plutôt qu'une table par module.
2. Glisser-déposer depuis n'importe quel écran, avec aperçu en place.
3. Métadonnées : type, date, auteur, mots-clés, période, échéance.
4. Recherche plein texte sur le contenu des PDF, via l'indexation à l'import.
5. Versionnement avec historique et restauration.

**Critère d'acceptation.** Un même contrat se retrouve depuis la fiche client, depuis le projet et depuis la recherche globale.

---

### `GED-02` — Numérisation et reconnaissance de factures

**État actuel.** `ocr-invoice-import` existe (114 lignes).

**Actions.**

1. Adresse e-mail de dépôt par dossier : le fournisseur envoie sa facture, elle arrive en attente de traitement.
2. Extraction : fournisseur, numéro, date, montants HT, TVA, TTC, échéance, et lignes quand c'est possible.
3. **Confronter systématiquement l'extraction à la commande** (`ACH`) plutôt que de l'accepter telle quelle — l'extraction automatique se trompe, le rapprochement à trois voies la rattrape.
4. File de validation avec image et champs extraits côte à côte, correction en un clic.
5. Apprentissage par fournisseur : mémoriser la mise en page pour améliorer les extractions suivantes.
6. Afficher le niveau de confiance et forcer la validation manuelle en dessous d'un seuil.

**Critère d'acceptation.** Une facture fournisseur déposée par e-mail arrive pré-saisie, rapprochée de sa commande, et n'attend qu'une validation.

---

### `GED-03` — Archivage à valeur probante

**Actions.** Conservation dix ans, horodatage qualifié, empreinte au dépôt, restitution avec preuve d'intégrité, purge automatique à l'échéance de rétention. Le lien avec `CNF-03` est direct : sans archivage probant, la chaîne NF525 s'arrête au journal.

**Critère d'acceptation.** Une facture archivée il y a cinq ans est restituée avec la preuve qu'elle n'a pas été modifiée.

---

### `GED-04` — Signature électronique effective

**État actuel.** `request-signature` fonctionne en « mode simulation » (`CNF-01`).

**Actions.** Raccorder un prestataire réel, gérer les circuits de signature à plusieurs signataires, les relances, et l'archivage du dossier de preuve. Usages prioritaires : contrat de travail, devis, bon de commande, mandat de prélèvement.

**Critère d'acceptation.** Un contrat de travail part en signature, revient signé et s'archive automatiquement dans le coffre-fort du salarié.

---

## 26. Portail salarié & mobile — `PTL`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** Cinq écrans dédiés (`EmployeeDashboardPage`, `EmployeeDocumentsPage`, `EmployeeLeavesPage`, `EmployeeProfilePage`, `ManagerLeaveApprovalsPage`), un `EmployeeLayout` distinct, un `MobileExpenseCapture`, et un service worker (`public/sw.js`, cache `compta-v2`).

C'est plus abouti que la moyenne des progiciels de gestion, qui traitent le portail salarié en dernier.

---

### `PTL-01` — Libre-service salarié complet

**Actions.**

1. Consultation et téléchargement des bulletins depuis le coffre-fort, avec accusé de réception.
2. Demande de congé avec solde en direct et détection de conflit d'équipe.
3. Saisie et suivi des notes de frais, avec photo du justificatif — `MobileExpenseCapture` existe déjà.
4. Mise à jour des données personnelles avec circuit de validation RH.
5. Consultation des documents de l'entreprise : règlement intérieur, accords, notes de service.
6. Attestations en libre-service : employeur, salaire, présence.

**Critère d'acceptation.** Un salarié effectue les six opérations depuis son téléphone sans jamais écrire au service RH.

---

### `PTL-02` — Espace responsable

**État actuel.** `ManagerLeaveApprovalsPage` existe.

**Actions.** Étendre au-delà des congés : validation des notes de frais et des feuilles de temps, planning d'équipe, soldes de l'équipe, entretiens à mener, délégation pendant les absences.

**Critère d'acceptation.** Un responsable traite l'ensemble de ses validations depuis un seul écran.

---

### `PTL-03` — Mobile et hors ligne

**État actuel.** Le service worker met en cache les ressources statiques uniquement.

**Actions.**

1. Étendre la stratégie de cache aux données consultées, avec péremption.
2. **Saisie hors ligne** avec file de synchronisation pour les trois cas qui le justifient : note de frais, pointage, saisie en caisse (`POS-04`).
3. Installation en application, notifications poussées, accès à l'appareil photo.
4. Concevoir pour l'écran étroit d'abord sur les écrans du portail — ce sont ceux qu'on consulte en mobilité.
5. Résolution de conflit à la synchronisation, avec arbitrage visible.

**Critère d'acceptation.** Une note de frais saisie dans le métro sans réseau remonte automatiquement au retour de la connexion.

---

## 27. Multi-société & consolidation — `GRP`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** L'architecture multi-tenant est solide et durcie (`SEC`). `MultiCompanyPage`, `/settings/multi-company`, `consolidated_treasury` et un `calculateGroupTax` existent.

La différence entre **multi-tenant** (des dossiers indépendants) et **groupe** (des sociétés liées dont on consolide les comptes) n'est pas faite aujourd'hui. Ce sont deux besoins distincts.

---

### `GRP-01` — Structure de groupe

**Actions.**

1. Modéliser le groupe : société mère, filiales, pourcentages de détention, méthode de consolidation (intégration globale, proportionnelle, mise en équivalence).
2. Basculer d'une société à l'autre sans se déconnecter — la mécanique de tenant actif le permet déjà (`79`).
3. Droits transverses : un directeur financier de groupe voit toutes les sociétés, un comptable une seule.
4. Plan comptable de groupe, avec table de correspondance vers les plans locaux.

**Critère d'acceptation.** Un utilisateur de groupe bascule entre trois sociétés et ne voit à chaque fois que les données de la société active.

---

### `GRP-02` — Opérations intra-groupe

**Actions.**

1. Identifier les tiers intra-groupe et marquer automatiquement leurs écritures.
2. **Facturation réciproque automatique** : une facture de vente chez A crée la facture d'achat chez B, avec le même numéro de pièce de rapprochement. C'est ce qui rend l'élimination possible.
3. Transferts de stock inter-sociétés (`STK-14`) avec valorisation et marge interne.
4. État de rapprochement intra-groupe : les comptes réciproques doivent se solder.

**Critère d'acceptation.** Une vente de A vers B génère les deux écritures miroir et l'état de rapprochement les apparie.

---

### `GRP-03` — Consolidation

**Actions.**

1. Agréger les balances des filiales après conversion en devise de consolidation.
2. Éliminer les opérations réciproques et les marges internes sur stock.
3. Traiter les écritures de consolidation : écarts d'acquisition, intérêts minoritaires, impôts différés.
4. Produire les états consolidés — bilan, compte de résultat, tableau de flux.
5. Historiser chaque cycle de consolidation avec sa piste d'audit.

**Critère d'acceptation.** Un groupe de trois sociétés produit un bilan consolidé dont le total est égal à la somme des bilans moins les éliminations.

---

## 28. Inscription & mise en service — `ONB`

**Non noté dans les volets précédents. Cible 9,5.**

**État actuel.** `/signup`, `/accept-invitation`, `/select-tenant`, `/onboarding`, `/login`, `/terms`, `/privacy`, une page d'accueil marketing refondue, l'edge function `auth-signup`, `create-user` (462 lignes — la plus longue), `75_create_tenant_rpc.sql`, et `handle-stripe-webhook` pour l'abonnement.

C'est le parcours qui décide de la conversion. Il mérite le même soin que le noyau comptable.

---

### `ONB-01` — Parcours d'inscription

**Actions.**

1. Essai sans carte bancaire, avec dossier de démonstration pré-rempli — `seed_demo_data.sql` existe déjà et sert exactement à cela.
2. Vérification de l'adresse e-mail, et pré-remplissage depuis le SIRET via `verify-siret`.
3. Réduire le formulaire au strict minimum : le reste se paramètre plus tard (`ADM-01`).
4. Mesurer chaque étape pour voir où les gens abandonnent.

**Critère d'acceptation.** De la page d'accueil au premier écran de l'application en moins de deux minutes.

---

### `ONB-02` — Invitations et gestion d'équipe

**Actions.** Invitation par e-mail avec rôle pré-attribué (`ADM-02`), lien à durée limitée, relance automatique, révocation, et transfert de propriété du dossier. Traiter le cas de la personne appartenant à plusieurs dossiers — `/select-tenant` existe, il faut le rendre fluide.

**Critère d'acceptation.** Une invitation expirée ne donne aucun accès, et une invitation acceptée place l'utilisateur directement dans le bon dossier avec le bon rôle.

---

### `ONB-03` — Abonnement et facturation du service

**État actuel.** `handle-stripe-webhook` est implémentée (159 lignes).

**Actions.** Formules et modules activables (`useTenantModules` gère déjà l'activation), changement de formule au prorata, gestion de l'échec de paiement avec période de grâce, factures d'abonnement téléchargeables, et surtout : **définir ce qui se passe à la fin de l'essai ou en cas de non-paiement**. Le blocage d'un dossier comptable n'est pas anodin — les données doivent rester exportables.

**Critère d'acceptation.** Un dossier impayé passe en lecture seule avec export possible, jamais en suppression.

---

## 29. Séquencement en vagues

### Vague 0 — Débloquer (2 semaines)

**Rien d'autre ne doit démarrer avant.** Ces chantiers ne produisent aucune fonctionnalité visible, et sans eux tout ce qui est construit par-dessus est du code qui n'a jamais tourné.

| Chantier | Effort |
|---|---|
| `SOC-01` Écriture validée avant ses lignes — 5 triggers | 2 h |
| `STK-01` Vocabulaire des types de mouvement | 1 h |
| `PRD-05` Déduction des commandes en cours | 2 h |
| `PAY-01` Taux PAS et assiette de transport | 2 h |
| `CNF-01.3` Afficher le mode simulation | 1 h |
| `SOC-02` Tests d'intégration base en CI | 5 j |
| `SOC-06` Numéros de migration | 4 h |
| `SOC-08` Nettoyage du dépôt | 1 h |

**Sortie de vague :** la validation d'une facture, d'un mouvement de stock et d'un paiement fonctionne, et un test le prouve en CI.

---

### Vague 1 — Fiabiliser le noyau (6 semaines)

| Chantier | Effort |
|---|---|
| `SOC-04` Agrégations financières serveur | 3 j |
| `ACC-05` Exercice, à-nouveaux, affectation du résultat | 5 j |
| `ACC-01` Comptes auxiliaires | 3 j |
| `ACC-02` TVA multi-taux | 4 j |
| `ACC-03` Comptes par article | 4 j |
| `STK-02` CUMP incrémental | 2 j |
| `STK-03` FIFO/LIFO avec couches | 3 j |
| `STK-04` Fonction de valorisation unique | 1 j |
| `PRD-01` Valoriser les OF | 3 j |
| `POS-01` Comptabiliser le point de vente | 2 j |
| `SOC-03` TypeScript strict, cercles 1 et 2 | 10 j |

**Sortie de vague :** les états financiers sont justes, tiennent la charge, et la valeur du stock concorde avec le bilan.

---

### Vague 2 — Atteindre la parité (3 mois)

| Chantier | Effort |
|---|---|
| `PAY-12` puis `PAY-02` à `PAY-06` — refonte du moteur de paie | 4 sem. |
| `PRD-02` Éclatement MRP récursif | 3 j |
| `PRD-03` Sources du besoin | 4 j |
| `PRD-04` Délais, sécurité, lot technique | 1 j |
| `BNQ-01` Parsers CAMT, MT940, CFONB | 3 j |
| `BNQ-02` Rapprochement par score | 3 j |
| `VTE-01` Grilles tarifaires | 3 j |
| `VTE-02` Encours client | 1 j |
| `STK-05` Réservations | 3 j |
| `STK-06` Traçabilité effective | 4 j |
| `POS-02`, `POS-03` Paiements multiples et conformité | 6 j |
| `QUA-02`, `QUA-03` Cas de référence et parcours E2E | 10 j |
| `ADM-01` Assistant de paramétrage initial | 5 j |
| `ADM-02` Rôles et permissions portés par la RLS | 8 j |
| `IMP-01` à `IMP-03` Reprise de données | 10 j |
| `PRD-09` Sous-traitance de production | 5 j |

**Sortie de vague :** parité de mécanisme avec Sage et Odoo sur les fonctions cœur, **et** un client peut être mis en production avec son historique.

> **Note de séquencement.** `ADM-01`, `ADM-02` et `IMP-01` ont rejoint cette vague parce qu'ils conditionnent la mise en service réelle. Un moteur juste sur un dossier non paramétré, ou sans reprise d'historique, ne se vend pas.

---

### Vague 3 — Dépasser (4 mois)

| Chantier | Effort |
|---|---|
| `PAY-07` à `PAY-11` Paie avancée | 3 sem. |
| `ACC-06` à `ACC-08` Lettrage, immobilisations, analytique | 3 sem. |
| `STK-07` à `STK-10` Unités, frais accessoires, réappro | 2 sem. |
| `STK-11` à `STK-14` Emplacements, picking, qualité, transferts | 3 sem. |
| `PRD-06`, `PRD-07` Déclaration et capacité finie | 2 sem. |
| `PRD-10`, `PRD-11` Workflows et maintenance | 1 sem. |
| `PRJ-01` à `PRJ-09` Projet complet | 5 sem. |
| `BI-01` à `BI-03` Générateur d'états et SIG | 2 sem. |
| `UX-02` à `UX-05` Accessibilité et saisie clavier | 2 sem. |
| `CNF-01`, `CNF-02` Raccordements réels et e-facturation | 4 sem. |
| `PRF-02` à `PRF-04` Performance | 1 sem. |
| `ADM-03` à `ADM-05` Paramétrage, modèles, audit | 2 sem. |
| `GED-01` à `GED-04` Documents et dématérialisation | 3 sem. |
| `NOT-01` à `NOT-03` Notifications unifiées | 2 sem. |
| `API-01`, `API-02` API et webhooks professionnels | 2 sem. |
| `PTL-01` à `PTL-03` Portail salarié et mobile | 3 sem. |
| `ONB-01` à `ONB-03` Inscription et abonnement | 2 sem. |
| `CRM-01` à `CRM-03` Séquences, scoring, e-mails | 2 sem. |
| `GRP-01` à `GRP-03` Groupe et consolidation | 4 sem. |
| `RH-01` à `RH-03` GTA, congés fins, intégration | 3 sem. |
| `IMP-04`, `API-03` Passerelles et connecteurs | 2 sem. |

**Sortie de vague :** 9,5 sur les 28 axes.

> `GRP` (consolidation) est le seul chantier qu'il est raisonnable de reporter au-delà : il ne concerne que les clients organisés en groupe. À arbitrer selon votre cible commerciale.

---

## 30. Tableau de bord de suivi

Ces indicateurs se mesurent automatiquement et doivent figurer dans la CI. Un chantier n'est terminé que lorsque son indicateur bouge.

| Indicateur | Aujourd'hui | Cible | Mesure |
|---|---|---|---|
| Triggers couverts par un test | 0 / 323 | 323 / 323 | job `db-integration` |
| Politiques RLS testées | 0 / 2 208 | 2 208 | `96_rls_tests.sql` |
| Occurrences de `any` | 1 884 | 0 | `grep -c ': any' src` |
| `strict` TypeScript | non | oui | `tsconfig.app.json` |
| Fonctions de requête paginées | 29 / 1 152 | 1 152 | script CI |
| Chunk d'entrée gzip | 324 ko | < 250 ko | budget de build |
| Parcours E2E couverts | 3 | 10 | Playwright |
| Couverture `src/lib/` | à mesurer | > 80 % | `test:ci` |
| Violations axe-core critiques | non mesuré | 0 | audit a11y |
| `window.confirm` | 127 | 0 | règle de lint |
| `catch` vides en compta/paie | 12 | 0 | revue |
| Fichiers > 600 lignes | 14 | 0 | règle `max-lines` |
| Edge functions en simulation | 4 / 21 | 0 | revue |
| Tables métier orphelines | 8 connues | 0 | `check-orphan-tables.mjs` |
| Requête au 95ᵉ centile | non mesuré | < 200 ms | `pg_stat_statements` |

---

## Annexe A — Trois principes à retenir

**1. Le motif « table présente, jamais branchée ».** Il revient huit fois dans ce document : `account_tiers`, `vat_code`, `price_lists`, `credit_limit`, `bank_reconciliation_rules`, `production_forecasts`, `nf525_event_log`, les lots et numéros de série. À chaque fois, l'objet existe en base avec son écran de saisie, et rien ne le consomme. C'est ce qui produit une application impeccable en démonstration et vide à l'usage. Le garde-fou de `SOC-05` est peu coûteux et empêche la récidive.

**2. Le motif « écriture validée avant ses lignes ».** Il touche cinq triggers et bloque la moitié des flux de l'application. Sa cause profonde n'est pas le code : c'est qu'aucun test n'exécute jamais un trigger. `SOC-02` est le chantier qui vaut le plus cher de tout ce document, parce qu'il empêche la classe entière de défauts.

**3. Le motif « calcul juste en apparence ».** Le CUMP, le FIFO, le LIFO, la valorisation à une date, le net imposable, le plafond de sécurité sociale : chacun produit un nombre plausible, affiché sans erreur, et faux. C'est le mode de défaillance le plus coûteux d'un progiciel de gestion, parce qu'il n'est découvert qu'au contrôle. La seule parade est `QUA-02` : confronter chaque calcul à une référence externe, jamais au comportement du code.

---

## Annexe B — Couverture route par route

Les 337 routes de `src/App.tsx`, rattachées à leur section. Aucune n'est laissée de côté.

| Préfixe | Routes | Sections | Observation |
|---|---:|---|---|
| `/accounting` | 89 | `ACC`, `SOC-04`, `CNF` | Le plus gros module. Structure Sage, méthode incomplète. |
| `/hr` | 47 | `PAY`, `RH`, `PTL` | Solide hors calcul de paie. |
| `/settings` + `/system` | 25 | `ADM`, `IMP`, `API`, `SEC` | **Absent du volume 1** — 3ᵉ module par la taille. |
| `/stock` | 22 | `STK-01` à `STK-14` | Périmètre bon, valorisation fausse, WMS non branché. |
| `/production` | 21 | `PRD-01` à `PRD-11` | Sous-traitance : 4 routes sans aucun trigger métier. |
| `/project-management` | 18 | `PRJ-01` à `PRJ-09` | Le module le plus abouti de l'application. |
| `/sales` | 15 | `VTE`, `CNF-02` | Tarifs et encours non branchés. |
| `/treasury` | 14 | `TRE`, `BNQ-04` | Avec les achats, le plus solide du volet exploitation. |
| `/purchases` | 13 | `ACH`, `GED-02` | Three-way matching au niveau du marché. |
| `/banking` | 11 | `BNQ` | Formats bancaires inexistants. |
| `/dashboard` | 11 | `BI-03`, `PRF-01` | 10 tableaux de bord agrégés côté navigateur. |
| `/crm` | 8 | `CRM` | Large en surface, passif en profondeur. |
| `/reports` + `/reporting` | 12 | `BI`, `ACC-05` | Dépendent des agrégations serveur. |
| `/commercial` | 5 | `VTE`, `CRM` | Hub et prospects. |
| `/pos` | 4 | `POS-01` à `POS-04` | Aucun trigger métier. |
| `/employee` + `/portal` + `/pay/:token` | 4 | `PTL` | **Absent du volume 1.** |
| `/login`, `/signup`, `/accept-invitation`, `/select-tenant`, `/onboarding` | 5 | `ONB`, `SEC-02` | **Absent du volume 1.** |
| `/shared/:token` | 1 | `PRJ-09`, `SEC-05` | Partage externe par jeton. |
| `/`, `/home`, `/terms`, `/privacy` | 4 | `UX`, hors périmètre | Vitrine et pages légales. |

**Transverse à toutes les routes :** `SOC` (socle), `DAT` (données), `SEC` (sécurité), `PRF` (performance), `QUA` (tests), `UX` (ergonomie, i18n, accessibilité), `NOT` (notifications), `GED` (documents), `GRP` (groupe).

---

*Document établi le 10 septembre 2026 sur la branche `commercial-hr-paie`, commit `31b79bd`. Les correctifs proposés n'ont pas été exécutés contre une base : ils indiquent la direction, pas un correctif prêt à appliquer. Les comparaisons avec Sage 100, Sage Paie & RH, Sage Gestion Commerciale, Odoo 17, Agicap et HubSpot portent sur les méthodes et mécanismes documentés de ces produits, confrontés au code de ce dépôt ; elles n'impliquent aucun accès à leur code source.*
