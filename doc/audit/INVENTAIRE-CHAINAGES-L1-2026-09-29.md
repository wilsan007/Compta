# Inventaire des maillons de L1 — 29 septembre 2026

> **Objet.** Rendre **opposable** la tranche 1 du lot **L1** du
> [plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md) :
> les **19 artères** du [référentiel](REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md)
> partie A.2 et les **16 maillons les plus fragiles** de sa partie A.3 —
> dédoublonnés, **30 fonctions** —, avec pour chacune : où vit sa dernière
> définition, ce qu'elle écrit (mesuré), et le **verdict** : maillon à tracer,
> lecture transverse, garde technique, ou recalcul.
> **Ce que ce document n'est pas** : une liste de 30 travaux. C'est un tri, avec
> la raison de chaque ligne — *un audit qui ne nomme pas ce qu'il écarte n'est
> pas un audit* (la formule est du référentiel lui-même, §B.2).
>
> **Méthode.** Pour chaque nom : dernière définition trouvée par
> `grep -nE 'CREATE (OR REPLACE )?FUNCTION (public\.)?<nom>\('`, puis lecture de
> son corps borné au premier `$…$;` terminant la définition, et relevé des
> instructions `INSERT INTO` / `UPDATE` / `DELETE FROM` et du type de retour.
> Les lignes marquées **lu** ont été lues en entier (corps complet).
>
> **État de la tranche** : **6 effets** sont tracés par la migration
> [310](../../app/sql/310_chain_l1_maillons.sql) et prouvés par la suite
> [310](../../app/sql/310_chain_l1_maillons_tests.sql) (15 scénarios) —
> [preuve](VAGUE-L1-2026-09-29.md). **0 / 62 → 6 / 62** pour l'indicateur du
> plan (§6.1), qui vise 62 / 62 à la fin de L1.

---

## 1. Les maillons à tracer — et ce qui a été tracé dans cette tranche

| # | Maillon (dernière définition) | Ce qu'il écrit (mesuré) | Effet du socle | État |
|---:|---|---|---|---|
| 1 | `create_journal_on_invoice_validate` — `210_advance_invoices.sql:124` **lu** | écritures VT (en-tête + lignes), `invoices.transferred_entry_id` | `sale.invoice.generated_entry` | ✅ **tracé (310)** |
| 2 | `credit_note_guard` — `213_credit_note_accounts.sql:110` | écriture d'avoir, `credit_notes.transferred_entry_id` | `sale.credit_note.generated_entry` | ✅ **tracé (310)** |
| 3 | `create_journal_on_supplier_payment` — `192_purchases_treasury.sql:445` **lu** | écriture de décaissement, `supplier_payments.transferred_entry_id` | `purchase.payment.generated_entry` | ✅ **tracé (310)** |
| 4 | `bank_account_ensure_journal` — `190_sales_to_ledger.sql:685` **lu** — *le plus fragile du référentiel : 1/7* | `journals`, `chart_accounts` | `treasury.bank_account.journal` + `treasury.bank_account.account` | ✅ **tracé (310)** — deux effets |
| — | `create_journal_on_customer_payment` — `190_sales_to_ledger.sql:745` **lu** *(hors des 30 : le maillon symétrique du n° 3 — sans lui la trésorerie n'aurait qu'une moitié de chaîne)* | écriture d'encaissement, `customer_payments.transferred_entry_id` | `sale.payment.generated_entry` | ✅ **tracé (310)** |
| 5 | `post_pos_session_on_close` — `187_accounting_kernel_strict.sql:629` | écritures **et** stock : 13 écritures relevées | `pos.session.closure` (+ effets de stock) | ⬜ tranche 2 — multi-effets |
| 6 | `post_pos_session_on_close_multi` — `281_pos_ticket_atomic_and_production.sql:408` | écritures (9 relevées) | idem | ⬜ tranche 2 — multi-effets |
| 7 | `create_stock_on_manufacturing_complete` — `302_manufacturing_multilevel_and_variances.sql:232` | `stock_movements` (2) **puis** `journal_entries` + `journal_lines` | `production.order.stock_in` + écriture d'OF | ⬜ tranche 2 — multi-effets |
| 8 | `auto_reconcile_by_score` — `222_bank_transaction_kind.sql:241` | `bank_reconciliation_suggestions`, `customer_payments`, `bank_transactions` | `treasury.bank_transaction.reconciled` | ⬜ tranche 2 — multi-effets |
| 9 | `reserve_stock_on_sales_order_confirm` — `242_delivery_warehouse_and_reservation.sql:202` **lu** | `stock_reservations`, `stock_quantities` | `sale.order.reserved` | ⬜ tranche 2 — **N lignes pour un document** |
| 10 | `st_shipment_stock_out` — `121_subcontracting_and_import.sql:11` **lu** | `stock_movements` (**une par ligne**), `stock_quantities` | `subcontracting.shipment.stock_out` | ⬜ tranche 2 — N lignes |
| 11 | `st_receipt_stock_in` — `121_subcontracting_and_import.sql:70` **lu** | `stock_movements` (**une par ligne**), `stock_quantities` | `subcontracting.receipt.stock_in` | ⬜ tranche 2 — N lignes |

**Pourquoi ces trois derniers ne sont pas dans la 310, et ce qu'il faudra faire.**
Leur effet produit **N lignes** (une par ligne de document) pour **un** document
amont. Le socle porte la granularité qui résout cela — `amont_ligne_id` (M-09,
inclus dans la clé unique) — mais la correspondance ligne → ligne n'est
**aujourd'hui pas écrite** par ces maillons : `stock_reservations` ne porte pas
l'identifiant de la ligne de commande, et le mouvement de stock d'une livraison
ne porte que `reference_id` (l'en-tête). La tranche 2 doit donc, pour chacun :
soit lire la correspondance dans ce que le maillon sait déjà (`product_id`, et à
défaut l'ordre stable des lignes), soit **ajouter la colonne de rattachement**
que le maillon a le droit d'écrire — la leçon du plan §5 étant qu'on corrige la
**structure** d'abord quand elle manque (`S-01` : colonne `warehouse_id`
absente, tout un chaînage rendu inutile). C'est un travail de maillon, pas de
socle : il est instruit, pas supposé.

## 2. Les fonctions qui ne sont PAS des maillons — et la raison

Un chaînage, au sens du plan (§0.1), est **l'effet automatique d'un changement
d'état d'un document sur un ou plusieurs autres modules**. Une fonction qui ne
change aucun état n'a ni amont ni aval à déclarer : lui poser un
`link_documents` inventerait un lien que personne ne pourrait lire.

| # | Fonction (dernière définition) | Ce que la mesure dit | Verdict, et pourquoi |
|---:|---|---|---|
| 12 | `generate_accounting_annex` — `103_medium_priority_business_functions.sql:622` | `RETURNS jsonb`, **0 écriture** | **Lecture** — une annexe se calcule, elle ne produit pas de document. Elle sera **citée** par la vue chaîne (L6) comme explication, jamais tracée. |
| 13 | `has_module_permission` — `69_module_access_management.sql:91` | `RETURNS boolean`, 0 écriture | **Lecture** — un droit ne chaîne rien. Le référentiel la compte comme « artère » parce qu'elle touche 4 modules ; c'est un **lecteur** transverse, pas un maillon. |
| 14 | `get_vat_summary_by_code` — `246_vat_return_fixes.sql:229` | `RETURNS TABLE`, **0 écriture** | **Lecture** — un état de TVA se calcule (et la CA3 est couverte par W7 → 300). |
| 15 | `cash_flow_forecast` — `89_missing_rpc_functions.sql:483` | `RETURNS jsonb`, 0 écriture de document | **Lecture** — une prévision n'est pas un document. L'engagement de production (`R-047`, L19) sera, lui, un vrai chaînage. |
| 16 | `trace_lot_upstream` — `118_stock_reservation_traceability.sql:245` | `LANGUAGE sql STABLE`, `RETURNS TABLE`, 0 écriture | **Lecture** — et c'est un **précurseur maison de I-01** : à rebrancher sur `document_links` (L6) plutôt qu'à instrumenter. |
| 17 | `trace_lot_downstream` — `118_stock_reservation_traceability.sql:208` | idem | **Lecture** — mêmes raisons. |
| 18 | `calculate_stock_valuation_at_date` — `111_stock_valuation.sql:162` | `RETURNS TABLE`, 0 écriture | **Lecture** — valorisation à date ; la vérité unique de valorisation (CUMP) est tenue par `254`. |
| 19 | `get_bank_reconciliation_state` — `223_bank_reconciliation_state.sql:55` | `RETURNS TABLE`, 0 écriture | **Lecture** — un état de rapprochement se lit. |
| 20 | `get_stock_at_subcontractors` — `121_subcontracting_and_import.sql:141` | `LANGUAGE sql STABLE`, 0 écriture | **Lecture** — un inventaire chez les tiers. |
| 21 | `calculate_project_profitability` — `158_fix_plpgsql_check_errors.sql:246` | `RETURNS jsonb` | **Lecture ou recalcul → L19** — `PROJ-02` (deux calculs d'avancement) et `I-08` (définitions uniques) disent que c'est le **calcul** qu'il faut unifier, pas le lien qu'il faut poser. |
| 22 | `calculate_provisions` — `103_medium_priority_business_functions.sql:389` | `RETURNS jsonb`, 10 écritures relevées (dépréciation) | **Recalcul paramétrique → L20 (M-04)** : changer un taux **régénère**, cela ne « chaîne » pas. |
| 23 | `calculate_manufacturing_cost` — `302_manufacturing_multilevel_and_variances.sql:146` | `RETURNS jsonb`, 10 écritures | **Recalcul → L20** (nomenclature multi-niveaux livrée par W8). |
| 24 | `calculate_production_cost` — `152_fix_broken_rpc_functions.sql:1109` | `RETURNS jsonb`, écritures | **Recalcul → L20**. |
| 25 | `run_mrp` — `152_fix_broken_rpc_functions.sql:959` | écrit dans `_mrp_needs` (**table de travail**) | **Calcul / proposition** — aucun document durable n'est écrit ; la règle besoin ↔ proposition ↔ commande est `R-046` (phase D). |
| 26 | `cancel_import_batch` — `227_tenant_guard.sql:38` | `DELETE` en cascade sur 4 référentiels | **Annulation d'un acte d'import**, pas la transition d'un document. Aucun des huit `link_type` du socle ne dit « détruit par » — et c'est voulu. |
| 27 | `publish_chart_pack` — `201_chart_by_country.sql:322` | `chart_pack_status`, `tenants`, `tenant_users`, `employees` | **Paramétrage de référentiel** (mise en service d'une société), pas un changement d'état de document. |
| 28 | `create_invoice_service` — `221_invoice_service_api.sql` | API de service (rôle `service_role`) | **Point d'entrée externe** — le document créé est l'aval d'un **appel**, pas d'un document amont : il n'y a rien à lier. |
| 29 | `preserve_history_delete_guard` — `244_preserve_history_delete_guards.sql:47` | `RETURNS trigger`, **0 écriture**, refuse la suppression | **Garde technique** — elle empêche, elle ne produit pas. |
| 30 | `update_updated_at_column` — déclencheur technique d'horodatage | `RETURNS trigger`, met une colonne à jour | **Garde technique** — le référentiel la note 2/7 et dit lui-même que c'est **tolérable pour un rôle technique**. |

**Ce que ce tableau assume.** Dix-neuf des trente fonctions de la tranche ne seront
**jamais** instrumentées, et c'est écrit noir sur blanc. Le plan demande « 62
maillons tracés » ; le référentiel en comptait 62 par la **mesure** (fonctions
touchant ≥ 2 modules), pas par la **nature**. L'écart entre les deux comptes est
exactement ce que ce document rend visible — et il devra être tranché pour le
chiffre final de L1 (plan §6.1), sinon l'indicateur ne pourra pas atteindre
62/62 sans mentir.

## 3. Les 32 chaînages restants : la méthode, réutilisable

Les 30 fonctions ci-dessus sont **nommées** par le référentiel. Les 62 mesurés ne
le sont pas tous : il reste **32 chaînages** à nommer, avec la même méthode, qui
est reproductible :

1. **extraire** les couples (fonction, table écrite) de `app/sql` — 325 fonctions
   et 424 déclencheurs au 24/09 ;
2. **classer** chaque fonction selon les quatre verdicts de ce document :
   écriture d'état (maillon), lecture seule (transverse), recalcul, garde ;
3. **nommer l'effet** des maillons (`<module>.<document>.<effet>`) et le porter
   dans `document_effects` — c'est le lot **L7** ;
4. **tracer** par déclencheur compagnon (doctrine de la 310), ou **réécrire le
   maillon** quand son effet produit N lignes (tranche 2) ;
5. **prouver** chaque effet par une suite du gabarit de la 310 (au moins un
   scénario par effet, plus le rejeu et le refus).

**Ce qui est déjà prêt** : le socle (252) et son gabarit ; la doctrine de la
tranche 1 (`zz_l1_`, ordre alphabétique **prouvé** par T10 de la suite 310, et
`EXECUTE` révoqué **mesuré** sans effet sur les déclencheurs, T15) ; la suite 310
comme gabarit de test ; et six effets tracés qui fixent le vocabulaire
(`sale.*`, `purchase.*`, `treasury.*`).


