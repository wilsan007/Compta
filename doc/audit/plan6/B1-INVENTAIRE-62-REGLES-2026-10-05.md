# B.1 — Inventaire des 62 règles d'état contre le schéma du jour (05/10/2026)

> **Objet.** Première tâche de la partie **B** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md) (règle **R4** :
> ce fichier est tenu par la partie B seule).
>
> **Question.** Sur les **62 règles d'état** `R-001` → `R-062` nommées par le
> [référentiel des chaînages](../REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md)
> (§B.2), **combien existent déjà** dans le schéma, combien sont partielles,
> combien sont vierges ? Le plan supposait **0 / 62** et disait que « W1 → W10 » et
> « X1 → X6 » en avaient posé. **Ce n'est pas ce qui est mesuré** : le compte est
> **13 / 62 existantes**, **13 / 62 partielles**, **36 / 62 vierges**, et les règles
> déjà posées ne viennent presque pas des vagues W/X.

---

## 1. La méthode, rejouable

Base **neuve**, procédure de la CI (`.github/workflows/ci.yml`), dans le conteneur
`compta-pg16` (PostgreSQL 16.14) :

```bash
docker exec compta-pg16 psql -U postgres -c "DROP DATABASE IF EXISTS plan6_b_base;"
docker exec compta-pg16 psql -U postgres -c "CREATE DATABASE plan6_b_base;"
docker exec -i compta-pg16 psql -U postgres -d plan6_b_base -v ON_ERROR_STOP=1 -f - < app/sql/ci/00_supabase_stubs.sql
docker exec -i compta-pg16 psql -U postgres -d plan6_b_base -v ON_ERROR_STOP=1 -f - < app/sql/00_schema_dump.sql
cd app && DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5433/plan6_b_base' node run-sql-migrations.mjs
```

Résultat : **333 migrations, 0 erreur**, **299 tables** — le même « schéma du jour »
que la mesure **A.1** (`PARTIE-A.md`). Ce fichier ne recopie aucun document : il lit
`pg_trigger` (déclencheurs **actifs** seulement, `tgisinternal = false`), le corps des
fonctions de déclenchement (`pg_get_functiondef`), le catalogue d'effets
`document_effects` (contrats L7/L1) et les contraintes `CHECK`.

**Ce qu'on appelle « la règle existe ».** Un état *existe* quand un déclencheur
**réagit à cette transition** (le `OLD.status → NEW.status` est testé) **et** produit
l'effet aval annoncé (écriture, mouvement de stock, lien, lettrage). Sinon la règle
est *partielle* (l'effet est là, le déclencheur d'état non — ou l'inverse) ou
*vierge* (aucun déclencheur ne teste cet état sur la table).

---

## 2. Le verdict, en un tableau

| Verdict | Nombre | Part des 62 | Sens |
|---|---:|---:|---|
| ✅ **existe** | **13** | 21 % | le déclencheur réagit à l'état et l'effet aval est produit |
| 🟨 **partielle** | **13** | 21 % | l'effet existe, mais pas sur cette transition (ou incomplet) |
| ⬜ **vierge** | **36** | 58 % | aucun déclencheur ne teste cet état |
| **total** | **62** | 100 % | plafond du plan : 62 / 62 |

**Par module** (l'ordre de B.2) :

| Module | Règles | ✅ | 🟨 | ⬜ |
|---|---|---:|---:|---:|
| Ventes | R-001 → 009, 019 → 021 (12) | 2 | 2 | 8 |
| Achats | R-010 → 018 (9) | 3 | 1 | 5 |
| Trésorerie | R-022 → 024, 048 → 051 (7) | 1 | 2 | 4 |
| Paie / RH | R-025 → 039 (15) | 5 | 6 | 4 |
| Projets | R-040 → 042 (3) | 0 | 0 | 3 |
| Production / stock | R-043 → 047 (5) | 0 | 1 | 4 |
| Conformité | R-052 → 056, 062 (6) | 1 | 0 | 5 |
| Budgets / relances | R-057 → 061 (5) | 1 | 1 | 3 |
| **total** | **62** | **13** | **13** | **36** |

---

## 3. Le détail règle par règle

Légende : **✅** existe · **🟨** partielle · **⬜** vierge. La colonne « preuve » nomme
le déclencheur (et la fonction) lu en base ; « — » veut dire **aucun déclencheur ne
teste cet état**.

### 3.1 Ventes (L8) — R-001 → R-009, R-019 → R-021

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-001 | `quotes.status = accepted` | ⬜ | — (`quotes` n'a que `set_tenant_id` + `tg_quote_number`) |
| R-002 | `quotes.status = expired` | ⬜ | — |
| R-003 | `quotes.validation_status = validated` | ⬜ | — |
| R-004 | `sales_orders.status = invoiced` | ⬜ | `sales_orders` : aucun test de `invoiced` |
| R-005 | `sales_orders.validation_status = validated` | ⬜ | — |
| R-006 | `deliveries.status = delivered` ⚠️ la table est `delivery_notes` | 🟨 | `create_stock_out_on_delivery` (sortie + lien) → sortie de stock ✅ ; **rapprochement facture** et preuve de livraison absents |
| R-007 | `delivery_notes.status = returned` | ⬜ | — (retour client non chaîné) |
| R-008 | `delivery_notes.status = cancelled` | ✅ | `reverse_stock_on_delivery_cancel` + `chain_l3_delivery_cancel_liens` |
| R-009 | `delivery_notes.validation_status = draft/transformed` | ⬜ | — |
| R-019 | `invoices.status = cancelled` | ⬜ | `invoices` : pas de contre-passation (seul le journal NF525) |
| R-020 | `invoices.validation_status = transformed` | 🟨 | `invoice_status_on_validate` (`draft → sent`) ; pas d'immuabilité complète |
| R-021 | `credit_notes.status = applied` | ✅ | `chain_l1_credit_note_entry` + `credit_note_after_validate` + `credit_note_guard` |

⚠️ **`deliveries` n'existe pas** dans le schéma : le référentiel visait `delivery_notes`
(le bon de livraison). À corriger dans le référentiel (§B.2, ligne 6).

### 3.2 Achats (L9) — R-010 → R-018

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-010 | `purchase_orders.status = confirmed` | ✅ | `sync_commitments_on_purchase_order` → `budget_commitments` `active` |
| R-011 | `purchase_orders.status = received` | 🟨 | `update_po_status_on_receipt` met le statut PO ; la consommation d'engagement se fait à **la facture** (`consume_commitment_on_purchase_invoice`) ; l'écart de prix est vu par `perform_three_way_match` |
| R-012 | `purchase_orders.status = cancelled` | ✅ | `sync_commitments_on_purchase_order` (`cancelled` → engagements `cancelled`) |
| R-013 | `goods_receipts.status = partial` | ⬜ | `create_stock_on_goods_receipt` ne réagit **qu'à `received`** ; `partial` est muet |
| R-014 | `goods_receipts.status = cancelled` | ✅ | `reverse_stock_on_goods_receipt_cancel` + `chain_l3_goods_receipt_cancel_liens` |
| R-015 | `goods_receipts.status = pending` | ⬜ | contrôle qualité obligatoire absent |
| R-016 | `purchase_invoices.status = cancelled` | ⬜ | `purchase_invoice_guard` protège `approved`, mais pas de contre-passation TVA/lettrage sur `cancelled` |
| R-017 | `purchase_invoices.status = overdue` | ⬜ | — |
| R-018 | `purchase_invoices.approval_status = rejected` | ⬜ | `purchase_invoice_after_approve` = *settlement* ; le rejet ne libère rien |

### 3.3 Trésorerie (L10) — R-022 → R-024, R-048 → R-051

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-022 | `customer_payments.status = reconciled` | ✅ | `update_invoice_on_customer_payment` (`refresh_invoice_settlement`) + `create_journal_on_customer_payment` |
| R-023 | `customer_payments.status = cancelled` | 🟨 | le solde client est décrémenté (`v_new_counted = 0`), mais pas de « remise en relance » explicite |
| R-024 | `supplier_payments.status = cancelled` | 🟨 | idem, via `update_invoice_on_supplier_payment` |
| R-048 | `sepa_payment_orders.status = rejected` | ⬜ | `sepa_payment_orders` n'a que `set_tenant_id` |
| R-049 | `sepa_payment_orders.status = processed` | ⬜ | — |
| R-050 | `treasury_transfers.status = executed` | ⬜ | `treasury_transfers` n'a que `set_tenant_id` |
| R-051 | `treasury_transfers.status = cancelled` | ⬜ | — |

### 3.4 Paie / RH (L11) — R-025 → R-039

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-025 | `pay_runs.status = approved` | 🟨 | `pay_run_require_slips_before_approval` (garde). **L'écriture de paie se fait sur `paid`**, pas sur `approved` (`create_journal_on_payroll_validate` → `payroll_post_run`) ; la DSN se fait sur `closed` (`generate_dsn_on_payrun_close`). Donc `approved` reste **muet** pour l'effet attendu |
| R-026 | `pay_slips.status = approved` | 🟨 | `nf525_log_payslip_create` + `payroll_cumulative_follow_slip` + `pay_slip_refresh_run_totals` ; immuabilité et archivage légal partiels |
| R-027 | `pay_slips.status = cancelled` | ✅ | `payroll_cumulative_follow_slip` (`cancelled`) + `pay_slip_refresh_run_totals` |
| R-028 | `pay_slips.status = paid` | 🟨 | `payroll.payment.settled` (effet déclaré) ; l'écriture est portée par le **lot** (`pay_runs`), pas par le bulletin |
| R-029 | `expense_reports.status = submitted` | 🟨 | `guard_expense_report_on_decision` (`assert_can_claim_expense`) ; **réservation budgétaire** absente |
| R-030 | `expense_reports.status = approved` | ✅ | `integrate_expense_report_on_approval` (écriture 625x / 44566 / 421 + élément de paie) + `chain_l1_expense_report_integration` |
| R-031 | `expense_reports.status = rejected` | ⬜ | pas de libération / retour motivé |
| R-032 | `expense_reports.status = reimbursed` | 🟨 | lettrage avec l'écriture de paie : partiel |
| R-033 | `leave_requests.status = pending` | ✅ | `apply_leave_balance_movement` (solde `pending`) |
| R-034 | `leave_requests.status = rejected` | ✅ | `apply_leave_balance_movement` (mouvement inverse) |
| R-035 | `leave_requests.status = cancelled` | ✅ | `apply_leave_balance_movement` + `sync_absence_from_leave_request` (`rebuild_absence_days`) |
| R-036 | `leave_requests.leave_type` | 🟨 | `leave_type_affects_balance` + `rebuild_absence_days` ; IJSS / maintien / carence = **B.3 / B.4** (paie FR) |
| R-037 | `contracts.status = ended / terminated` | ⬜ | `contracts` n'a que `set_tenant_id` |
| R-038 | `contracts.status = suspended` | ⬜ | — |
| R-039 | `contracts.contract_type` | ⬜ | — |

### 3.5 Projets (L12) — R-040 → R-042

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-040 | `projects.status = completed` | ⬜ | `projects` n'a que `projects_updated_at` + `set_tenant_id` |
| R-041 | `projects.status = cancelled` | ⬜ | — |
| R-042 | `projects.status = on_hold` | ⬜ | — |

### 3.6 Production / stock (L13) — R-043 → R-047

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-043 | `manufacturing_orders.status = cancelled` | 🟨 | `chain_l1_manufacturing_order` ne réagit qu'à **`completed`** ; `cancelled` muet |
| R-044 | `manufacturing_orders.status = in_progress` | ⬜ | aucun déclencheur |
| R-045 | `manufacturing_orders.status = planned` | ⬜ | — |
| R-046 | `manufacturing_orders.origin = mrp` | ⬜ | traçabilité amont absente |
| R-047 | `stock_movements.movement_type = transfer` | ⬜ | aucun traitement de `transfer` |

### 3.7 Conformité (L14) — R-052 → R-056, R-062

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-052 | `vat_returns.status = submitted` | ⬜ | `vat_returns` : `set_tenant_id` + `trg_refuse_client_edi_stamp` |
| R-053 | `vat_returns.status = paid` | ⬜ | — |
| R-054 | `vat_returns.edi_status = rejected` | ⬜ | — |
| R-055 | `dsn_declarations.status = rejected` | ⬜ | `dsn_declarations` n'a que `set_tenant_id` |
| R-056 | `social_declarations.status = rejected` | ⬜ | — |
| R-062 | `pos_tickets` — contrainte `CHECK` sur le statut | ✅ | **FAITE** : `pos_tickets_status_check` (`completed / cancelled / refunded`) existe. Le référentiel datait d'avant la contrainte |

### 3.8 Budgets / engagements / relances (L15) — R-057 → R-061

| Règle | État | Verdict | Preuve |
|---|---|---|---|
| R-057 | `budget_commitments.status = consumed` | ✅ | `consume_commitment_on_purchase_invoice` (`approved` → `consumed`) |
| R-058 | `budget_commitments.status = cancelled` | 🟨 | libération via `sync_commitments_on_purchase_order` ; l'annulation **motivée et tracée** directement manque |
| R-059 | `collection_reminders.status = sent` | ⬜ | `collection_reminders` n'a que `set_tenant_id` — **`EF-02` reste ouvert** |
| R-060 | `collection_reminders.status = paid` | ⬜ | — |
| R-061 | `collection_reminders.status = cancelled` | ⬜ | — |

---

## 4. Ce que la mesure dit, et que le plan ne disait pas

1. **Ce n'est pas 0 / 62.** Le suivi portait « `0 / 62` → 62 / 62 ». Le schéma du
   jour en porte **13 entiers + 13 partiels = 26 / 62 touchés**. Le plafond de B.2
   (≈ 40 j) reste juste pour le volume, mais **le point de départ est 26, pas 0**.
2. **Les règles déjà posées ne viennent pas des vagues W/X.** Le plan disait
   « W1 → W10, X1 → X6 en ont posé ». Vérifié par `git grep` puis en base : les
   vagues W **citent** `R-025 → R-039` (L11) comme du travail **restant**, elles ne
   le posent pas. Les déclencheurs d'état présents viennent de :
   - **L1 — rétro-instrumentation** : `400` (`chain_l1_invoice_entry`,
     `chain_l1_credit_note_entry`…), `401` (`chain_l1_manufacturing_order`…),
     `404` (`chain_l1_purchase_invoice_entry`, `chain_l1_expense_report_integration`…) ;
   - **partie 3 (L3/L4)** : `433` → `436` (`chain_l3_*_cancel_liens`, banc) ;
   - **sessions fonctionnelles** : `241`, `251`, `253`, `263` (`apply_leave_balance_movement`),
     `314`, `354`, `419` (`create_stock_out_on_delivery`, …).
   **La correction à porter au plan : remplacer « W1 → W10, X1 → X6 » par « L1 (400/401/404),
   partie 3 (433→436), sessions 241→419 ».**
3. **`R-062` est déjà faite.** Le référentiel disait « aucune contrainte `CHECK` sur le
   statut de `pos_tickets` » ; la contrainte `pos_tickets_status_check` existe.
4. **`R-006` vise une table qui n'existe pas.** `deliveries` n'est pas au schéma :
   c'est `delivery_notes`. Le référentiel est à corriger.
5. **Le trou de paie à trancher d'abord.** `R-025` (lot `approved`) : le lot est
   **approuvé sans écriture** ; l'écriture part au `paid`, la DSN au `closed`. C'est
   le premier chantier de B.2 (module paie/RH) et il touche `create_journal_on_payroll_validate`.

## 5. Ce que B.2 en fait

- **Ordre inchangé** (ventes → achats → trésorerie → paie/RH → projets → production →
  conformité → budgets), mais chaque module **commence par ses ⬜**, puis convertit
  ses 🟨 en ✅ — et **ne réécrit pas** ce qui est déjà ✅ (R-008, R-010, R-012, R-014,
  R-021, R-022, R-027, R-030, R-033, R-034, R-035, R-057, R-062).
- **Les 36 vierges** se prennent dans la plage `500` → `559` (registre : `plan6 B`),
  un lot par module, `npm run migration:prendre -- … --session "plan6 B (règles d'état, paie FR)"`.
- **Territoire (R3)** : migrations de règles d'état **par module** + `app/src/lib/payroll*`.
  Les tables `quotes/sales_orders/… /contracts/projects/vat_returns/…` sont **partagées**
  avec C et E : R7 s'applique (une fonction, un propriétaire) et la batterie est rejouée
  à chaque fusion.

## 6. Ce qu'il restait à faire pour B.1

- [x] Base neuve : 333 migrations, 0 erreur, 299 tables
- [x] Les 62 règles confrontées au schéma (déclencheurs actifs + `document_effects` + `CHECK`)
- [x] Le verdict par règle et l'origine des règles déjà posées
- [x] Les corrections à porter au plan et au référentiel (§4, points 2 → 4)
- [ ] **À verser au référentiel** — `doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md`
      **n'est au territoire d'aucune des six parties** (§2 : ni A ni B ni C… ne
      détiennent `doc/audit/`) : c'est un document de référence partagé, tenu par la
      **session d'intégration** (§10), **au même titre que `SUIVI-CHANTIERS.md` et
      `AGENTS.md`** (règle **R4**). Cette note tient donc lieu de **demande à
      l'intégration** (règle **R3**) : corriger le §B.2 (`deliveries` →
      `delivery_notes`) et dater la ligne `R-062` comme faite.
