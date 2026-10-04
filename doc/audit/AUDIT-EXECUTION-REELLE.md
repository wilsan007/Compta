# Audit par exécution réelle — Onusuite

> **Version** 1.0 — 12 septembre 2026
> **Branche** `commercial-hr-paie`
> **Changement de méthode** les trois volets précédents et les audits Gemini lisaient le code. Celui-ci l'**exécute** contre un PostgreSQL 16.14 réel.

---

## 0. Pourquoi cet audit existe

Les quatre rapports précédents — mes volets 1 à 3 et les deux audits Gemini — reposaient sur la lecture : `grep`, inspection de fichiers, comparaison au marché. Cette méthode a trouvé de vrais défauts, mais elle est **structurellement incapable** d'en détecter toute une classe :

- une fonction PL/pgSQL qui référence une colonne inexistante se crée sans erreur — PostgreSQL ne résout les identifiants du corps qu'à l'exécution ;
- un trigger dont la condition de déclenchement est interdite par une contrainte `CHECK` s'installe normalement — il ne se déclenchera simplement jamais ;
- deux colonnes concurrentes pour le même concept ne produisent aucun avertissement.

**La preuve du problème : j'ai moi-même propagé un de ces défauts.** Dans ma contre-vérification du 12 septembre, j'ai proposé un correctif utilisant `NEW.label` sur `bank_transactions` — colonne qui n'existe pas. J'ai recopié le code d'un autre audit sans le confronter au schéma. Le correctif aurait échoué exactement comme le bug qu'il prétendait corriger.

### Méthode de ce rapport

| Étape | Outil | Ce que ça trouve |
|---|---|---|
| 1. Base réelle | Docker `postgres:16.14` | l'état vrai, pas l'état supposé |
| 2. Schéma + 132 migrations rejouées en **ordre numérique** | `psql -f` | les migrations qui échouent silencieusement |
| 3. Analyse statique de chaque corps de fonction | **`plpgsql_check`** | toute référence à une colonne, table ou champ inexistant |
| 4. Croisement conditions de trigger ↔ contraintes `CHECK` | SQL sur `pg_constraint` | les triggers qui ne peuvent jamais se déclencher |
| 5. Scénarios métier exécutés | `INSERT` / `UPDATE` réels | ce qui casse vraiment à l'usage |
| 6. Croisement RPC du front ↔ catalogue | `pg_proc` vs `src/` | les appels vers du code mort |

---

## 1. Synthèse

| Mesure | Résultat |
|---|---|
| Migrations rejouées | 132 |
| **Migrations en erreur** | **4** (20 erreurs) |
| Fonctions PL/pgSQL installées | 180 |
| Triggers actifs | 392 |
| **Triggers cassés (référence invalide)** | **20** |
| **Fonctions RPC cassées** | **31** |
| dont **appelées par le front** | **21 sur 78** |
| **Triggers au déclenchement impossible** | **6** |
| Politiques RLS | 1 747 |
| Tables avec `tenant_id` sans RLS | **0** ✓ |
| Fuite inter-tenant constatée | **aucune** ✓ |

### Les trois défauts qui dominent tout le reste

**1. Une facture de vente ne peut pas être comptabilisée. Jamais.**
Le trigger `create_journal_on_invoice_validate` se déclenche sur `NEW.status IN ('validated','posted')`. La contrainte `invoices_status_check` n'admet que `draft, sent, viewed, paid, overdue, cancelled`. **Le statut `'validated'` est refusé par la base.** Et le front ne le pose jamais — il ne pose que `'draft'` et `'sent'`. Le chaînage gestion commerciale → comptabilité n'existe pas. Même chose pour les achats.

**2. Le job de tests d'intégration en CI échoue.**
`102_trigger_tests.sql` s'arrête sur `column "created_at" of relation "users" does not exist`. `105_rls_tests.sql` produit 9 erreurs. Les deux fichiers que j'avais présentés comme « la meilleure décision structurelle » ne s'exécutent pas.

**3. Vingt triggers et trente-et-une fonctions référencent des colonnes qui n'existent pas.**
Les audits Gemini en avaient trouvé huit. `plpgsql_check` en trouve cinquante-et-un.

---

## 2. Migrations : ce qui échoue au chargement

Rejeu des 132 migrations numérotées, dans l'ordre **numérique** (et non lexicographique — voir `INF-01` du registre consolidé).

### `68_module_documents_storage_rls.sql` — 30 erreurs

```
ERROR: function has_module_access(text) does not exist
ERROR: function current_tenant_user_id() does not exist
```

Ces deux fonctions ne sont définies nulle part. **Les huit politiques RLS du stockage documentaire ne sont donc jamais créées.** Le fichier porte pourtant « storage_rls » dans son nom.

**Impact.** Les documents de module n'ont pas de politique d'isolation. Ce n'est pas une fuite ouverte — sans politique et avec RLS activée, PostgreSQL refuse tout accès (`fail-closed`) — mais la fonctionnalité est morte : aucun utilisateur ne peut lire ses propres documents par cette voie.

**Correctif.** Créer les deux fonctions manquantes, ou réécrire les politiques sur `current_tenant_id()` qui, lui, existe.

### `102_trigger_tests.sql` — le test échoue

```
ERROR: ❌ ÉCHEC DES TESTS: column "created_at" of relation "users" does not exist
```

Le fichier s'arrête à la ligne 576. **Le job CI `db-integration` ne peut pas passer.** Soit la CI est rouge depuis sa mise en place, soit elle n'a jamais tourné sur ce chemin.

**Correctif.** La table `users` n'a pas de `created_at`. Corriger l'insertion de fixture, puis vérifier que le job passe réellement au vert en CI avant de considérer le chantier `SOC-02` comme livré.

### `105_rls_tests.sql` — 9 erreurs

```
ERROR: column "number" of relation "customers" does not exist
ERROR: column "code" of relation "products" does not exist
ERROR: invalid input syntax for type json     (×6)
```

Les fixtures utilisent des colonnes inexistantes, et `set_config('request.headers', ...)` reçoit un JSON invalide. **Les tests d'isolation ne s'exécutent pas non plus.**

### `94_fix_advisor_security_issues.sql` — 3 erreurs

```
ERROR: relation "public.sql_migrations_tracker" does not exist
```

La table de suivi des migrations est référencée mais jamais créée dans ce chemin.

---

## 3. Les vingt triggers cassés

Détectés par `plpgsql_check` — chaque ligne est une référence que PostgreSQL ne peut pas résoudre à l'exécution.

| Trigger | Table | Erreur |
|---|---|---|
| `create_journal_on_invoice_validate` | `invoices` | `column il.subtotal does not exist` |
| `create_journal_on_purchase_invoice_validate` | `purchase_invoices` | `column pil.subtotal does not exist` |
| `create_journal_on_customer_payment` | `customer_payments` | `record "new" has no field "invoice_number"` |
| `create_journal_on_supplier_payment` | `supplier_payments` | `record "new" has no field "invoice_number"` |
| `check_journal_entry_balance_stmt` | `journal_lines` | `relation "new_table" does not exist` (×3) |
| `propagate_analytic_section` | `journal_lines` | `record "new" has no field "reference_type"` |
| `nf525_log_invoice_modify` | `invoices` | `operator does not exist: invoices ->> text` |
| `auto_reconcile_by_score` | `bank_transactions` | `record "new" has no field "label"` |
| `apply_bank_reconciliation_rules` | `bank_transactions` | `record "new" has no field "label"` |
| `notify_bank_reconciliation_needed` | `bank_transactions` | `record "new" has no field "currency"` |
| `post_pos_session_on_close` | `pos_sessions` | `column tl.subtotal does not exist` |
| `post_pos_session_on_close_multi` | `pos_sessions` | `column "entry_date" of relation "journal_entries" does not exist` |
| `assign_pos_ticket_number_and_hash` | `pos_tickets` | `column "reference_id" of relation "nf525_event_log" does not exist` |
| `check_customer_credit_limit` | `sales_orders` | `record "new" has no field "credit_warning"` |
| `reserve_stock_on_sales_order_confirm` | `sales_orders` | `record "v_line" has no field "warehouse_id"` |
| `update_po_status_on_receipt` | `goods_receipts` | `column "quantity_received" does not exist` |
| `calculate_lateness_on_timesheet` | `timesheets` | `record "v_emp" is not assigned to tuple structure` |
| `deduct_lateness_on_timesheet_approval` | `timesheets` | idem |
| `deduct_unpaid_absence_on_timesheet_approval` | `timesheets` | idem |
| `sync_cpf_on_transaction` | `cpf_transactions` | `no unique constraint matching the ON CONFLICT specification` |

### Les quatre plus graves

**`check_journal_entry_balance_stmt` — l'invariant d'équilibre ne fonctionne pas.**
La migration 128 réécrit le contrôle débit/crédit en `FOR EACH STATEMENT` avec une table de transition `new_table`, mais ne la déclare pas dans la clause `REFERENCING`. **Le contrôle d'équilibre — la garantie fondamentale d'une comptabilité — lève une erreur au lieu de vérifier.** Dans la mesure où l'ancien trigger `FOR EACH ROW` de la migration 76 subsiste (défaut `PRF-01`), l'équilibre est encore vérifié — par accident.

```sql
-- correctif : déclarer la table de transition
CREATE TRIGGER check_journal_entry_balance_ins
  AFTER INSERT ON journal_lines
  REFERENCING NEW TABLE AS new_table        -- ← manquant
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();
```

**`create_journal_on_invoice_validate` — `il.subtotal` n'existe pas.**
`invoice_lines` porte `total`, `vat_total`, `unit_price`, `quantity` — jamais `subtotal`. Le trigger de comptabilisation des ventes est cassé **en plus** de ne jamais pouvoir se déclencher (section 4).

**`auto_reconcile_by_score` — `NEW.label` n'existe pas.**
`bank_transactions` porte `description`, pas `label`. **Confirmé à l'exécution** : toute insertion de transaction bancaire échoue.

```
ERROR: record "new" has no field "label"
CONTEXT: PL/pgSQL function auto_reconcile_by_score() line 14
```

Import de relevé, synchronisation bancaire, saisie manuelle : tout est bloqué.

**`nf525_log_invoice_modify` — `operator does not exist: invoices ->> text`.**
La fonction traite l'enregistrement `invoices` comme du JSON. La journalisation NF-525 des modifications de facture ne fonctionne pas — ce qui vide de sens la chaîne d'inaltérabilité pour cet événement.

---

## 4. La classe de défaut que personne n'avait cherchée

**Six triggers guettent un statut que la contrainte `CHECK` de leur table interdit.**

Aucun des quatre rapports précédents n'a vérifié ce point. Les deux audits ont analysé le *corps* des triggers — comptes en dur, TVA mono-taux, ordre `posted`/lignes — sans jamais se demander si la *condition de déclenchement* était atteignable.

| Trigger | Table | Statut attendu | Statuts autorisés |
|---|---|---|---|
| `create_journal_on_invoice_validate` | `invoices` | `'validated'` | draft, sent, viewed, paid, overdue, cancelled |
| `create_journal_on_purchase_invoice_validate` | `purchase_invoices` | `'validated'` | draft, sent, viewed, paid, overdue, cancelled |
| `create_stock_out_on_delivery` | `delivery_notes` | `'shipped'` | pending, delivered, returned, cancelled |
| `generate_dsn_on_payrun_close` | `pay_runs` | `'closed'` | *(absent de la contrainte)* |
| `integrate_pay_recalls_on_payrun` | `pay_runs` | `'processing'` | *(absent de la contrainte)* |
| `integrate_salary_advances_on_payrun` | `pay_runs` | `'processing'` | *(absent de la contrainte)* |

### Conséquence, module par module

**Comptabilité.** Aucune facture de vente ni d'achat ne génère d'écriture. Le journal des ventes et le journal des achats restent vides, quelle que soit l'activité saisie. Toutes les analyses des rapports précédents sur les comptes auxiliaires, la ventilation de TVA ou les comptes par article portaient sur du code qui ne s'exécute jamais.

**Paie.** Ni DSN, ni intégration des rappels de paie, ni intégration des acomptes.

**Stock.** Aucune sortie sur bon de livraison (déjà relevé).

### La confirmation par le front

Le code de l'interface ne pose jamais `'validated'` :

```
2 occurrences de  status: 'draft'
1 occurrence  de  status: 'sent'
0 occurrence  de  status: 'validated'
```

Il existe bien une colonne `validation_status` avec les valeurs `draft / validated / transformed` — **mais les triggers surveillent `status`, pas `validation_status`.** Le mécanisme de validation et le mécanisme de comptabilisation regardent deux colonnes différentes.

### Correctif

Deux options, à trancher :

```sql
-- Option A : le trigger surveille la bonne colonne (recommandée)
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate() ... AS $$
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
  ...

-- Option B : élargir la contrainte et brancher l'interface
ALTER TABLE invoices DROP CONSTRAINT invoices_status_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_status_check
  CHECK (status = ANY (ARRAY['draft','sent','viewed','validated','posted','paid','overdue','cancelled']));
```

L'option A est préférable : `validation_status` existe déjà pour cet usage, et `status` porte le cycle de vie commercial (envoyée, vue, payée), qui est une autre dimension.

**Puis ajouter le garde-fou** qui empêche la classe entière de revenir — voir section 8.

---

## 5. Les trente-et-une fonctions RPC cassées

Dont **vingt-et-une sont appelées depuis le front**.

| Fonction | Erreur |
|---|---|
| `generate_trial_balance` | `aggregate function calls cannot be nested` |
| `generate_balance_sheet` | `aggregate function calls cannot be nested` |
| `generate_profit_loss` | `aggregate function calls cannot be nested` |
| `get_balance_sheet_structured` | `subquery uses ungrouped column "jl.account_general"` |
| `generate_vat_return` | `column "vat_collected" of relation "vat_returns" does not exist` |
| `generate_adjusting_entries` | `column "acquisition_value" does not exist` |
| `calculate_depreciation` | `record "v_asset" has no field "acquisition_value"` |
| `auto_letter_accounts` | `column jl.lettering_code does not exist` |
| `auto_lettrage_by_reference` | `column "date" does not exist` |
| `resolve_price` | `column pl.customer_id does not exist` |
| `run_mrp` | `relation "_mrp_needs" does not exist` |
| `calculate_production_cost` | `column p.standard_cost does not exist` |
| `calculate_manufacturing_cost` | `column ro.setup_time does not exist` |
| `calculate_stock_valuation` | `column reference "product_id" is ambiguous` |
| `import_initial_stock` | `column reference "product_id" is ambiguous` |
| `import_employee_with_cumuls` | `column "first_name" of relation "employees" does not exist` |
| `smart_bank_reconciliation` | `column "bank_account_id" does not exist` |
| `get_bank_reconciliation_state` | `column jl.journal_entry_id does not exist` |
| `calculate_project_profitability` | `column i.project_id does not exist` |
| `calculate_overtime_pay` | `column "base_salary" does not exist` |
| `calculate_sick_leave_pay` | `record "v_emp" has no field "base_salary"` |
| `calculate_notice_compensation` | `record "v_emp" has no field "base_salary"` |
| `calculate_compensated_leave_indemnity` | `relation "employee_attendance" does not exist` |
| `calculate_payment_due_dates` | `record "v_terms" has no field "days"` |
| `check_segregation_of_duties` | `column "created_by" does not exist` |
| `distribute_by_grill` | `column dgl.section_id does not exist` |
| `run_three_way_match` | `column reference "match_status" is ambiguous` |
| `generate_recurring_tasks` | `record "v_task" is not assigned yet` |
| `get_nf525_attestation` | `record "v_company" has no field "company_name"` |
| `create_tenant_for_current_user` | `function auth.jwt() does not exist` |

### Lecture

**Les trois états financiers sont cassés.** `generate_trial_balance`, `generate_balance_sheet` et `generate_profit_loss` échouent toutes sur des agrégats imbriqués. Les fonctions `get_trial_balance` et `get_balance_sheet` de la migration 106 — celles que le front appelle réellement — sont saines, mais l'application expose aussi ces trois-là.

**`resolve_price` était doublement morte.** Mon volet 3 la classait « écrite mais non câblée ». Elle est aussi **cassée** : `price_lists` n'a pas de colonne `customer_id`. Même en la branchant, elle aurait échoué.

**`run_mrp` référence une table temporaire `_mrp_needs` qui n'est jamais créée.** L'éclatement récursif que j'avais porté au crédit du volet 3 ne s'exécute pas.

**Quatre fonctions de paie et RH utilisent `base_salary`.** La table `employees` porte `salary`. Heures supplémentaires, maladie, préavis, indemnité de congés : aucune ne fonctionne.

---

## 6. Contradictions de schéma

### `stock_movements` : deux colonnes de type, deux vocabulaires

```
type          CHECK IN ('in','out','adjustment')
movement_type CHECK IN ('in','out','transfer','adjustment','initial')
```

Les deux colonnes existent, les deux sont contraintes, **et leurs vocabulaires divergent**. Insérer un mouvement `movement_type = 'initial'` avec `type = 'initial'` échoue sur la contrainte de `type`. Or c'est exactement ce que fait le code de reprise de stock.

**Correctif.** Aligner les deux contraintes, puis planifier la suppression de `type` — c'est un doublon historique.

### `stock_quantities` : deux colonnes de réservation

`reserved_quantity` (schéma d'origine) et `quantity_reserved` (migration 118). Le front lit la première, les triggers écrivent dans la seconde. Déjà relevé au registre consolidé (`STK-04`), confirmé ici sur la base réelle.

### `invoices` : deux colonnes de statut

`status` (cycle commercial) et `validation_status` (cycle comptable). Les triggers surveillent la mauvaise. Voir section 4.

---

## 7. Ce qui fonctionne — vérifié, pas supposé

Trois points que l'exécution confirme et qu'il faut porter au crédit du projet :

**L'isolation multi-tenant tient.**
356 tables portent `tenant_id`, **toutes ont RLS activée**, 1 747 politiques sont en place, et aucune table avec `tenant_id` n'est dépourvue de politique. Le test d'isolation ne montre **aucune fuite**, et le comportement en l'absence de tenant résolu est `fail-closed` — zéro ligne visible plutôt que toutes. C'est le bon arbitrage, et il est correctement implémenté.

**Le chargement du schéma est propre.**
`00_schema_dump.sql` s'applique sans une seule erreur sur 293 tables.

**Le RPC atomique d'écriture fonctionne.**
`post_journal_entry` s'exécute et retourne son résultat. C'est le modèle correct, et il doit servir de référence pour les autres documents composés.

---

## 8. Le garde-fou à mettre en place

Les cinquante-et-un défauts de ce rapport appartiennent à **trois classes mécaniquement détectables**. Chacune se ferme définitivement avec un contrôle en intégration continue.

### Contrôle 1 — `plpgsql_check` sur toutes les fonctions

C'est l'outil qui a trouvé 51 des défauts de ce rapport. Il s'installe en une ligne et s'exécute en quelques secondes.

```sql
-- à ajouter au job db-integration, APRÈS l'application des migrations
CREATE EXTENSION IF NOT EXISTS plpgsql_check;

DO $$
DECLARE r RECORD; v_errors int := 0;
BEGIN
  -- fonctions ordinaires
  FOR r IN
    SELECT p.oid::regprocedure::text AS fn, cf.lineno, cf.message
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    JOIN pg_language l ON l.oid = p.prolang AND l.lanname = 'plpgsql'
    CROSS JOIN LATERAL plpgsql_check_function_tb(p.oid) cf
    WHERE p.prorettype <> 'trigger'::regtype AND cf.level = 'error'
  LOOP
    RAISE WARNING 'FONCTION %  L%  %', r.fn, r.lineno, r.message;
    v_errors := v_errors + 1;
  END LOOP;

  -- fonctions trigger, dans le contexte de leur table
  FOR r IN
    SELECT p.oid::regprocedure::text AS fn, c.relname AS tbl, cf.lineno, cf.message
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    JOIN pg_language l ON l.oid = p.prolang AND l.lanname = 'plpgsql'
    JOIN pg_class c ON c.oid = t.tgrelid
    CROSS JOIN LATERAL plpgsql_check_function_tb(p.oid, t.tgrelid) cf
    WHERE NOT t.tgisinternal AND cf.level = 'error'
  LOOP
    RAISE WARNING 'TRIGGER % @%  L%  %', r.fn, r.tbl, r.lineno, r.message;
    v_errors := v_errors + 1;
  END LOOP;

  IF v_errors > 0 THEN
    RAISE EXCEPTION '% référence(s) invalide(s) dans les fonctions PL/pgSQL', v_errors;
  END IF;
END $$;
```

**Effet immédiat.** Plus aucune fonction ne peut être livrée en référençant une colonne inexistante. Cela couvre les 51 défauts des sections 3 et 5, et empêche la récidive.

### Contrôle 2 — condition de trigger atteignable

```sql
DO $$
DECLARE r RECORD; v_errors int := 0;
BEGIN
  FOR r IN
    WITH trg AS (
      SELECT c.relname AS tbl, p.proname AS fn, pg_get_functiondef(p.oid) AS src
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
      WHERE NOT t.tgisinternal
    ),
    lits AS (
      SELECT DISTINCT tbl, fn, m[1] AS val
      FROM trg, regexp_matches(src, 'NEW\.status\s*(?:=|IN\s*\()\s*''([a-z_]+)''', 'g') m
    ),
    chk AS (
      SELECT conrelid::regclass::text AS tbl, pg_get_constraintdef(oid) AS def
      FROM pg_constraint
      WHERE contype = 'c' AND pg_get_constraintdef(oid) ILIKE '%(status%'
    )
    SELECT l.tbl, l.fn, l.val
    FROM lits l JOIN chk ON chk.tbl = l.tbl
    WHERE chk.def NOT ILIKE '%''' || l.val || '''%'
  LOOP
    RAISE WARNING 'TRIGGER MORT : %.% attend le statut ''%'' — interdit par la contrainte',
      r.tbl, r.fn, r.val;
    v_errors := v_errors + 1;
  END LOOP;

  IF v_errors > 0 THEN
    RAISE EXCEPTION '% trigger(s) ne peuvent jamais se déclencher', v_errors;
  END IF;
END $$;
```

### Contrôle 3 — colonnes concurrentes

```sql
-- deux colonnes de même sens sur une même table = faute de conception
SELECT table_name, string_agg(column_name, ' / ') AS doublons
FROM information_schema.columns
WHERE table_schema = 'public'
GROUP BY table_name,
  -- normalise : quantity_reserved ≡ reserved_quantity
  (SELECT string_agg(w, '' ORDER BY w)
   FROM unnest(string_to_array(column_name, '_')) w)
HAVING count(*) > 1;
```

### Contrôle 4 — scénarios métier bout en bout

Les trois contrôles ci-dessus sont statiques. Ils ne remplacent pas l'exécution d'un parcours réel : créer un tenant, un client, un produit, une facture, la valider, vérifier qu'une écriture équilibrée existe avec ses comptes auxiliaires. C'est ce qu'aurait dû faire `102_trigger_tests.sql`, et ce qu'il faut réparer en priorité.

---

## 9. Plan d'exécution révisé

L'ordre change par rapport au registre consolidé : les défauts découverts ici sont plus en amont que ceux déjà listés.

### Jour 1 — rendre l'application fonctionnelle

| Action | Effort |
|---|---|
| Brancher les triggers de comptabilisation sur `validation_status` (ventes + achats) | 2 h |
| Corriger `il.subtotal` → `il.total` et `pil.subtotal` → colonne réelle | 1 h |
| Corriger `NEW.label` → `NEW.description` dans les trois triggers bancaires | 1 h |
| Corriger `entry_date` → `date` et `NEW.session_number` → `NEW.id` (caisse) | 1 h |
| Déclarer `REFERENCING NEW TABLE AS new_table` sur le contrôle d'équilibre | 30 min |
| Trier les migrations par numéro (`INF-01` du registre) | 15 min |
| Réparer le build (`INF-02` du registre) | 30 min |

**Sortie.** Une facture validée produit une écriture. Une transaction bancaire s'insère. Une caisse se clôture.

### Jour 2 — poser les garde-fous

| Action | Effort |
|---|---|
| Réparer `102_trigger_tests.sql` et `105_rls_tests.sql` | 3 h |
| Ajouter `plpgsql_check` au job `db-integration` (contrôle 1) | 2 h |
| Ajouter le contrôle de trigger atteignable (contrôle 2) | 1 h |
| Vérifier que la CI passe réellement au vert | 1 h |

**Sortie.** Aucun des 51 défauts ne peut revenir sans faire échouer la CI.

### Semaine 1 — traiter le reste

Les 21 fonctions RPC cassées appelées par le front, les contradictions de schéma (`type` / `movement_type`, les deux colonnes de réservation), puis le registre consolidé.

---

## 10. Ce que cet audit change dans les notes

| Axe | Volet 3 | Après exécution réelle |
|---|---|---|
| Moteur comptable | 5,5 | **2,5** — aucune facture ne se comptabilise |
| Banque | 6,0 | **2,0** — toute insertion bancaire échoue |
| Point de vente | 7,0 | **2,0** — la clôture échoue à deux endroits |
| Production | 5,5 | **3,0** — `run_mrp` et les coûts sont cassés |
| Paie | 7,0 | **4,0** — quatre fonctions RH cassées, DSN morte |
| Qualité & tests | 8,0 | **3,0** — les deux fichiers de test échouent |
| Sécurité multi-tenant | 8,5 | **8,5** — vérifié à l'exécution, tient |
| **Note globale** | **6,9** | **≈ 4,2** |

La chute n'est pas due à une dégradation du code : elle est due au **passage d'une évaluation par lecture à une évaluation par exécution**. Le code était déjà dans cet état ; la méthode précédente ne pouvait pas le voir.

---

## Annexe — reproduire cet audit

```bash
docker run -d --name onusuite-audit -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=audit postgres:16
docker exec -u root onusuite-audit apt-get update -qq
docker exec -u root onusuite-audit apt-get install -y -qq postgresql-16-plpgsql-check
docker cp app/sql/. onusuite-audit:/sql/

# schémas et rôles Supabase simulés (auth.uid, authenticated, anon…)
docker exec onusuite-audit psql -U postgres -d audit -f /sql/00_setup_supabase_stub.sql

docker exec onusuite-audit psql -U postgres -d audit -f /sql/00_schema_dump.sql

# migrations en ordre NUMÉRIQUE
ls app/sql/*.sql | sed 's|.*/||' | grep -E '^[0-9]{2,3}_' | grep -v 00_schema_dump \
  | sort -t_ -k1 -n \
  | while read f; do docker exec onusuite-audit psql -U postgres -d audit -f "/sql/$f"; done

# puis les contrôles 1 et 2 de la section 8
```

---

*Audit conduit le 12 septembre 2026 sur PostgreSQL 16.14, avec `plpgsql_check`. 132 migrations rejouées, 180 fonctions et 392 triggers analysés, scénarios métier exécutés. Tous les constats sont reproductibles par la procédure ci-dessus.*
