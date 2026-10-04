# Référentiel des chaînages transverses — inventaire, robustesse, comparaison au marché et innovation

> **Document de fond Onusuite — 24 septembre 2026.** Il répond à quatre demandes précises :
>
> 1. **répertorier les chaînages déjà existants** et **éprouver leur qualité et leur robustesse** ;
> 2. **pour chaque action, déterminer si elle exige un chaînage**, et lesquels ;
> 3. **compiler les chaînages des leaders du marché** (SAP, Oracle NetSuite, Microsoft Dynamics 365,
>    ERPNext/Frappe, Sage, Pennylane, PayFit/Silae, Procore…) ;
> 4. **comparer** : ce qu'ils ont et que nous n'avons pas, ce que nous avons et qu'ils n'ont pas, et
>    **ce que personne n'a** — la part d'innovation qui fait la différence commerciale.
>
> Complément du [plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md) : le
> plan corrige les **défauts connus** ; ce référentiel traite la **couverture fonctionnelle des
> chaînages**, y compris ceux qu'aucun audit n'a encore nommés.
>
> **Suite opérationnelle** : [Plan d'implémentation des chaînages](PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md)
> — 25 lots (L0 → L24), ≈ 116 j, avec la doctrine « le meilleur de chacun », le socle technique
> (registres de liens, d'effets et d'événements), la définition de « terminé » en 12 points et les
> 6 portes automatiques.

---

## 0. Méthode — ce qui est mesuré, sur quoi, et avec quelles limites

### 0.1 Les quatre étapes, et comment chacune a été instrumentée

| Étape | Instrument | Résultat mesuré |
|---|---|---|
| **1. Répertorier et éprouver l'existant** | analyse statique des **220 fichiers SQL** et de **325 fonctions PL/pgSQL** : quelles tables chaque fonction touche, en écriture et en lecture ; classement des tables par module ; grille de robustesse à 7 critères | **376 tables**, **424 déclencheurs** sur **233 tables**, **62 chaînages transverses** (une fonction reliant ≥ 2 modules), matrice des liens, **note moyenne 3,65/7** |
| **2. Chaque action exige-t-elle un chaînage ?** | une action d'ERP est d'abord une **transition d'état** : lecture des contraintes `CHECK` de statut (**173 couples table/colonne**, **671 valeurs admises**) puis des valeurs réellement testées par les fonctions de déclencheur | **632 valeurs sur 671 (94 %) ne sont testées par aucun déclencheur** ; sur les seules tables critiques : **141 sur 170 (83 %)** |
| **3. Compilation du marché** | documentation officielle des éditeurs (SAP Help, Oracle NetSuite, Microsoft Learn, ERPNext/Frappe, Pennylane, Procore) — sources citées en partie C | 8 familles de chaînages, ~40 mécanismes distincts |
| **4. Comparaison** | matrice chaîne × éditeur, puis 4 listes : écarts critiques, parités, avances, **innovations que personne n'a** | 3 écarts bloquants, 31 règles à créer, 12 innovations candidat |

### 0.2 Ce que la mesure dit — et ce qu'elle ne dit pas

- **Ce qui est mesuré** : l'existence d'une fonction qui touche des tables de deux modules ; les
  valeurs de statut qu'une fonction de déclencheur compare explicitement ; la présence de sept
  propriétés de robustesse (filtre de société, garde d'idempotence, gestion d'erreur, refus explicite,
  trace de référence, maîtrise du `SECURITY DEFINER`, taille du corps).
- **Ce qui est déduit** : qu'une valeur de statut *devrait* avoir un effet aval. C'est vrai pour un
  statut métier (`accepted`, `received`, `cancelled`, `paid`) et **faux** pour un statut descriptif
  (`chart_accounts.type`, `audit_log.action`). Le document ne présente donc jamais le chiffre brut
  comme un défaut : il le donne comme **écran de sélection**, puis tranche dans une liste curatée.
- **Ce qui n'est pas mesuré ici** : le comportement à l'exécution. Aucune base n'a été montée pour ce
  document ; les 62 chaînages existants ont été notés **statiquement**. La partie E donne la batterie
  dynamique à exécuter pour transformer ces notes en preuves.

### 0.3 Règles de classement (reproductibles)

- Une table appartient à un module selon une liste de motifs de nom explicite (production, projets,
  RH, stock, commercial, trésorerie, comptabilité, système, reporting) — même principe que
  [la couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md) : **relisible mais
  approximatif** (une table au nom de stock alimentée par la production compte en « stock »).
- Un **chaînage** = une fonction qui touche au moins deux modules (colonnes `INSERT INTO`, `UPDATE`,
  `DELETE FROM`, `FROM`, `JOIN`). Les tronçons internes à un module ne sont donc pas comptés : c'est
  pourquoi la partie B les recense séparément (§B.4), la demande portant aussi sur **le même module**.
- **221 tables sur 376 ne sont classées dans aucun module métier** (121 « autre » + 100 réparties) :
  ce sont majoritairement des tables de référence et de configuration, qui ne portent pas de chaînage
  de gestion.

---

## Partie A — Étape 1 : les chaînages existants, répertoriés et éprouvés

### A.1 L'inventaire mesuré

| Mesure | Valeur | Comment elle est obtenue |
|---|---:|---|
| Fichiers SQL analysés | **220** | `app/sql/*.sql` hors `*_tests.sql` |
| Tables reconnues | **376** | contraintes `CREATE TABLE` de l'ensemble des fichiers |
| Fonctions PL/pgSQL analysées | **325** | `CREATE OR REPLACE FUNCTION`, corps rattaché à sa signature |
| Déclencheurs recensés | **424** | `CREATE TRIGGER … ON … EXECUTE FUNCTION` |
| Tables portant au moins un déclencheur | **233** | idem |
| **Chaînages transverses (≥ 2 modules)** | **62** | tables touchées par fonction, puis classement par module |
| Chaînages reliant **3 modules ou plus** | **19** | idem |
| Chaînages reliant **4 modules** | **4** | idem |
| Contraintes de statut lues | **173** couples (table, colonne) | `CHECK ((colonne = ANY (ARRAY[…])))` |
| Valeurs de statut admises | **671** | idem |

**La matrice des chaînages existants** (nombre de fonctions reliant deux modules) :

| | compta | commer | trésor | stock | produc | rh | projet | syst | report |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **comptabilité** | · | 13 | 13 | 11 | 1 | 7 | 1 | 8 | **—** |
| **commercial** | 13 | · | 5 | 11 | 2 | 4 | 1 | 2 | **—** |
| **trésorerie** | 13 | 5 | · | 2 | **—** | 3 | 1 | 1 | **—** |
| **stock** | 11 | 11 | 2 | · | 9 | 2 | **—** | 3 | **—** |
| **production** | 1 | 2 | **—** | 9 | · | **—** | **—** | 2 | **—** |
| **rh** | 7 | 4 | 3 | 2 | **—** | · | 2 | 5 | **—** |
| **projets** | 1 | 1 | 1 | **—** | **—** | 2 | · | 3 | **—** |
| **système** | 8 | 2 | 1 | 3 | 2 | 5 | 3 | · | **—** |
| **reporting** | **—** | **—** | **—** | **—** | **—** | **—** | **—** | **—** | · |

Lecture : la comptabilité est le pivot (elle touche tout le monde, sauf le reporting), le stock est le
second pivot. **Trois trous structurels** apparaissent au premier coup d'œil :
`production ↔ trésorerie`, `production ↔ RH`, `production ↔ projets`, `stock ↔ projets`, et
**neuf liens manquants vers le reporting** (aucune fonction ne relie le reporting à quoi que ce soit :
les 5 vues d'agrégation ne font pas un chaînage).

### A.2 Les chaînages les plus transversaux — le réseau réel

Les 19 fonctions qui relient **trois modules ou plus**. Ce sont les artères de l'application : c'est
par elles que passe toute la cohérence. Les casser casse tout ; les ignorer revient à ignorer la
moitié des régressions possibles.

| Fonction | Modules reliés | Tables | Fichier |
|---|---|---:|---|
| `generate_accounting_annex` | commercial, comptabilité, RH, stock | 7 | `103_medium_priority_business_functions.sql` |
| `calculate_project_profitability` | commercial, projets, RH, trésorerie | 6 | `103_medium_priority_business_functions.sql` |
| `has_module_permission` | comptabilité, projets, RH, système | 6 | `00_schema_dump.sql` |
| `cancel_import_batch` | commercial, comptabilité, RH, stock | 5 | `122_import_generic.sql` |
| `get_vat_summary_by_code` | commercial, comptabilité, système | 10 | `197_vat_reverse_charge_accounts.sql` |
| `post_pos_session_on_close` | comptabilité, stock, trésorerie | 10 | `113_pos_accounting.sql` |
| `run_mrp` | commercial, production, stock | 10 | `144_fix_mrp_and_valuation.sql` |
| `post_pos_session_on_close_multi` | comptabilité, stock, trésorerie | 10 | `119_pos_multi_payment_compliance.sql` |
| `credit_note_guard` | commercial, comptabilité, stock | 9 | `190_sales_to_ledger.sql` |
| `create_journal_on_invoice_validate` | commercial, comptabilité, stock | 8 | `110_product_accounts.sql` |
| `auto_reconcile_by_score` | commercial, comptabilité, trésorerie | 8 | `222_bank_transaction_kind.sql` |
| `create_journal_on_supplier_payment` | commercial, comptabilité, trésorerie | 7 | `108_auxiliary_accounts.sql` |
| `calculate_production_cost` | production, stock, système | 7 | `152_fix_broken_rpc_functions.sql` |
| `calculate_manufacturing_cost` | production, stock, système | 7 | `112_manufacturing_costing.sql` |
| `create_stock_on_manufacturing_complete` | comptabilité, production, stock | 7 | `112_manufacturing_costing.sql` |
| `calculate_provisions` | commercial, comptabilité, stock | 6 | `103_medium_priority_business_functions.sql` |
| `trace_lot_upstream` | commercial, production, stock | 6 | `118_stock_reservation_traceability.sql` |
| `preserve_history_delete_guard` | RH, système, trésorerie | 4 | `244_preserve_history_delete_guards.sql` |
| `cash_flow_forecast` | commercial, RH, trésorerie | 4 | `88_high_priority_business_functions.sql` |

**Ce que ce tableau révèle** : les chaînages les plus transversaux ne sont **pas** les chaînes
métier nobles (commande → livraison → facture), ce sont des **utilitaires** : un annexe comptable, un
calcul de rentabilité, une garde de droits, une annulation d'import. Les grandes chaînes métier sont
**éclatées en petits maillons d'un seul module** — c'est exactement pour cela que les audits du 23 et
du 24/09 ont trouvé la chaîne rompue à chaque jointure (réception → stock → compta en trois fonctions
qui ne se parlent pas).

### A.3 Qualité et robustesse des 62 chaînages existants — la grille de 7 critères

Chaque chaînage est noté sur sept propriétés, lues dans son code. Une propriété absente n'est pas une
opinion : c'est une instruction qui n'existe pas.

| Critère | Ce qu'il garantit | Ce que mesure le contrôle |
|---|---|---|
| **C1 filtre de société** | le chaînage ne franchit pas la frontière entre sociétés | présence de `tenant_id =` ou de `current_tenant_id()` dans le corps |
| **C2 garde d'idempotence** | rejouer l'action ne double pas l'effet | présence d'un `IF (NOT) EXISTS (…)` |
| **C3 erreur gérée** | une panne partielle ne passe pas en silence | présence d'un bloc `EXCEPTION WHEN` |
| **C4 refus explicite** | l'utilisateur reçoit une raison, pas un silence | présence d'un `RAISE` |
| **C5 trace de référence** | on peut relier l'aval à l'amont | écriture de `reference` / `reference_id` |
| **C6 `SECURITY DEFINER` maîtrisé** | pas de contournement de la RLS sans filtre | `DEFINER` **et** C1, ou pas de `DEFINER` |
| **C7 taille raisonnable** | un maillon reste testable et relisible | corps ≤ 400 lignes |

**Résultat : 3,65 / 7 en moyenne.** Répartition : 1 fonction à 1/7, 3 à 2/7, **26 à 3/7**, 21 à 4/7,
9 à 5/7, 2 à 6/7. Aucune n'atteint 7/7.

| Critère | Chaînages qui le respectent | Verdict |
|---|---:|---|
| C1 filtre de société | 58/62 — **94 %** | ✅ le travail d'isolation a porté |
| C6 `SECURITY DEFINER` maîtrisé | 58/62 — **94 %** | ✅ idem |
| C7 taille raisonnable | 59/62 — **95 %** | ✅ |
| C4 refus explicite | 29/62 — **47 %** | ⚠️ un défaut sur deux ne dit rien à l'utilisateur |
| **C2 garde d'idempotence** | **9/62 — 15 %** | 🔴 **le trou principal** |
| **C5 trace de référence** | **7/62 — 11 %** | 🔴 on ne peut pas remonter de l'aval à l'amont |
| **C3 erreur gérée** | **6/62 — 10 %** | 🔴 une panne partielle est invisible |

Les 16 chaînages les plus fragiles (extrait) :

| Note | Chaînage | Ce qui lui manque |
|---:|---|---|
| **1/7** | `bank_account_ensure_journal` | C1, C2, C3, C4, C5, C6 |
| 2/7 | `publish_chart_pack` | C1, C2, C3, C5, C6 |
| 2/7 | `create_invoice_service` | C1, C2, C3, C5, C6 |
| 2/7 | `update_updated_at_column` | C2, C3, C4, C5, C7 *(tolérable : rôle technique)* |
| 3/7 | `create_journal_on_invoice_validate` | C2, C3, C4, C5 |
| 3/7 | `create_journal_on_supplier_payment` | C2, C3, C4, C5 |
| 3/7 | `post_pos_session_on_close` *(et `_multi`)* | C2, C3, C4, C5 |
| 3/7 | `run_mrp` | C2, C3, C4, C5 |
| 3/7 | `credit_note_guard` | C2, C3, C4, C5 |
| 3/7 | `trace_lot_upstream` / `trace_lot_downstream` | C2, C3, C4, C5 |
| 3/7 | `reserve_stock_on_sales_order_confirm` | C2, C3, C4, C5 |
| 3/7 | `st_shipment_stock_out` / `st_receipt_stock_in` | C2, C3, C4, C5 |
| 3/7 | `calculate_stock_valuation_at_date` | C2, C3, C4, C5 |
| 3/7 | `get_bank_reconciliation_state` | C2, C3, C4, C5 |
| 3/7 | `calculate_manufacturing_cost` | C2, C3, C4, C5 |
| 3/7 | `get_stock_at_subcontractors` | C2, C3, C4, C5 |

**Traduction en une phrase** : *nos chaînages savent ne pas franchir la frontière entre sociétés, mais
ils ne savent ni se rejouer sans doubler, ni remonter à leur origine, ni signaler une panne partielle,
ni expliquer un refus.* Ce sont exactement les quatre propriétés qui séparent un ERP « qui marche »
d'un ERP « sur lequel on peut fermer les yeux » — celles que la partie C montre implémentées chez les
leaders (écritures de contre-passation SAP, régénération automatique Pennylane, rapport de comparaison
stock/grand livre ERPNext).

### A.4 Les couples de modules sans aucun chaînage

| Couple vide | Conséquence métier |
|---|---|
| `production ↔ trésorerie` | aucune visibilité de trésorerie sur l'engagement de production (achats déclenchés par le MRP, salaires d'atelier) |
| `production ↔ RH` | **la capacité de production ne connaît pas l'absence** : on planifie avec des salariés absents — le cas d'usage fondateur de tout ce travail |
| `production ↔ projets` | un projet ne peut pas fabriquer (pas de production à la commande, pas d'affaire industrielle) |
| `stock ↔ projets` | un projet ne sort rien du stock : consommations de chantier invisibles, coût de revient projet amputé |
| `reporting ↔ les 8 autres` | **aucun chaînage** : les tableaux de bord sont alimentés par des vues d'agrégation, pas par un chaînage ; rien ne garantit qu'un indicateur corresponde à une écriture |

Ces cinq couples sont, à eux seuls, une feuille de route : ils sont **vides chez nous** et pleins chez
SAP (PS / WM / PP), NetSuite (Projects / Manufacturing) et Procore (chantier).

### A.5 Éprouver la robustesse pour de vrai : les 8 tests dynamiques à exécuter sur chaque chaînage

La note de §A.3 est **statique** : elle dit ce qui manque dans le code, pas ce qui se passe en
production. Voici la batterie à exécuter sur **chacun des 62 chaînages** (et sur tout nouveau) pour
transformer la note en preuve.

| # | Test de robustesse | Ce qu'on manipule | Verdict attendu |
|---|---|---|---|
| **D1** | **Rejeu** | exécuter deux fois la même action sur le même document | l'aval existe **une** fois (C2) |
| **D2** | **Concurrence** | deux transactions simultanées sur la même ligne source | aucune quantité perdue, aucun doublon (`pg_advisory_xact_lock` ou `ON CONFLICT DO UPDATE`) |
| **D3** | **Panne partielle** | injecter une erreur à mi-chaîne | **rien** n'est écrit (atomicité) ou tout est journalisé et reprenable |
| **D4** | **Annulation** | annuler le document source après coup | l'aval est **contre-passé**, jamais supprimé ; la source reste |
| **D5** | **Réouverture** | écrire dans un exercice ou une période fermés | refus explicite, nommant la période |
| **D6** | **Retour arrière (traçabilité)** | partir de l'aval et remonter à la source | le chemin est reconstituable sans requête manuelle (C5) |
| **D7** | **Volume** | 10 000 documents enchaînés | temps linéaire, pas de N+1 (cf. `BUD-04` : deux requêtes par budget) |
| **D8** | **Isolation** | jouer le chaînage pour la société A pendant que B est active | aucune ligne de B écrite ni lue (C1) |

**Verdict mesuré** : ces huit tests n'existent **pour aucun** des 62 chaînages. Les 46 suites
existantes vérifient des **valeurs** (montants, quantités, statuts), jamais la **robustesse du
chaînage**. C'est la lacune la plus coûteuse de la base de tests — et l'occasion d'un différenciateur
commercial (partie D, innovation I-05).

---

## Partie B — Étape 2 : pour chaque action, un chaînage est-il nécessaire ?

### B.1 La méthode : une action d'ERP est un changement d'état

Une action se reconnaît à ce qu'elle **change un état** : `draft → validated`, `confirmed → delivered`,
`received → cancelled`, `approved → paid`. Un état n'est pas décoratif, c'est un **engagement** :
passer à `received` engage du stock et une dette ; passer à `cancelled` oblige à défaire ce qui a été
fait. **Chaque valeur d'état admise par la base devrait donc avoir un effet aval identifié** — ou une
raison explicite de ne pas en avoir.

| Mesure | Valeur |
|---|---:|
| Couples (table, colonne) de statut lus dans les contraintes `CHECK` | **173** |
| Valeurs de statut admises au total | **671** |
| Valeurs **jamais** comparées par une fonction de déclencheur | **632 — 94 %** |
| Couples **totalement muets** (aucune valeur traitée) | **149** |
| Couples **partiellement** couverts | **20** |
| Couples **entièrement** couverts | **4** |
| Sur les seules tables critiques (argent, stock, paie, conformité) | **141 / 170 valeurs sans effet — 83 %** |

> **Le chiffre de 94 % ne signifie pas « 94 % de chaînages manquants ».** Beaucoup de statuts sont
> descriptifs (`chart_accounts.type`, `tax_rates.category`, `audit_log.action`) : ils n'ont rien à
> déclencher. Le chiffre est un **écran de sélection** : il désigne les 173 endroits où la question
> doit être posée. La réponse est donnée table par table ci-dessous, y compris pour ceux qu'on décide
> de laisser muets.

### B.2 Les états qui exigent un chaînage — 62 règles manquantes (R-001 → R-062)

Chaque ligne est une **règle à écrire** : un état, l'effet aval attendu, l'identifiant de la règle.
Ces identifiants servent ensuite aux migrations, aux tests et au suivi.

| # | État aujourd'hui sans effet aval | Ce qui devrait se passer | Règle |
|---|---|---|---|
| 1 | `quotes.status = accepted` | création de la commande, **gel du prix**, réservation prévisionnelle, sortie du pipeline CRM, alerte d'expiration | **R-001** |
| 2 | `quotes.status = expired` | libération de la réservation, relance CRM, statistique de perte | R-002 |
| 3 | `quotes.validation_status = validated` | numérotation définitive, immuabilité des lignes, verrou de modification | R-003 |
| 4 | `sales_orders.status = invoiced` | rapprochement commande ↔ facture, **reliquat non facturé**, clôture de la commande | **R-004** |
| 5 | `sales_orders.validation_status = validated` | numéro définitif, lignes gelées, historique | R-005 |
| 6 | `deliveries.status = delivered` | sortie de stock **par dépôt**, libération de la réservation, **déclenchement du rapprochement facture**, preuve de livraison | **R-006** |
| 7 | `delivery_notes.status = returned` | **retour client** : entrée en stock ou en quarantaine, avoir, contrôle qualité, réintégration du coût | **R-007** |
| 8 | `delivery_notes.status = cancelled` | contre-passation de la sortie de stock, restitution de la réservation | R-008 |
| 9 | `delivery_notes.validation_status = draft / transformed` | interdire toute sortie de stock sur un brouillon ; lier au document transformé | R-009 |
| 10 | `purchase_orders.status = confirmed` | **engagement budgétaire**, réservation fournisseur, entrée dans l'échéancier de trésorerie | **R-010** |
| 11 | `purchase_orders.status = received` | rapprochement commande ↔ réception, consommation de l'engagement, **écart de prix d'achat** | **R-011** |
| 12 | `purchase_orders.status = cancelled` | **libération de l'engagement** — sans quoi il reste déduit à vie (`BUD-03`) | **R-012** |
| 13 | `goods_receipts.status = partial` | stock partiel, engagement partiellement consommé, reliquat de commande, alerte | R-013 |
| 14 | `goods_receipts.status = cancelled` | contre-passation de l'entrée de stock **et** de l'écriture, restitution de l'engagement | **R-014** |
| 15 | `goods_receipts.status = pending` | contrôle qualité obligatoire avant entrée en stock valorisé | R-015 |
| 16 | `purchase_invoices.status = cancelled` | contre-passation de la charge et de la TVA, restitution du règlement, **sortie du lettrage et de l'état de TVA** | **R-016** |
| 17 | `purchase_invoices.status = overdue` | alerte fournisseur, échéancier révisé, pénalités éventuelles | R-017 |
| 18 | `purchase_invoices.approval_status = rejected` | retour au demandeur avec motif, libération de l'engagement | R-018 |
| 19 | `invoices.status = cancelled` | avoir ou contre-passation, sortie du lettrage, **régénération de la TVA**, arrêt des relances | **R-019** |
| 20 | `invoices.validation_status = transformed` | fin du cycle brouillon → définitive, numérotation, immuabilité | R-020 |
| 21 | `credit_notes.status = applied` | lettrage avec la facture d'origine, sortie du chiffre d'affaires, **recalcul de la TVA** | R-021 |
| 22 | `customer_payments.status = reconciled` | lettrage automatique, sortie du compte d'attente, échéancier client mis à jour | R-022 |
| 23 | `customer_payments.status = cancelled` | délettrage, réouverture de la facture, remise en relance | **R-023** |
| 24 | `supplier_payments.status = cancelled` | délettrage, réouverture de la dette, restitution du prévisionnel | R-024 |
| 25 | `pay_runs.status = approved` | gel des bulletins, **écriture de paie**, ordre de virement, alimentation de la DSN | **R-025** |
| 26 | `pay_slips.status = approved` | immuabilité du bulletin, cumuls, archivage légal | R-026 |
| 27 | `pay_slips.status = cancelled` | réouverture du lot, contre-passation de l'écriture, annulation du virement | **R-027** |
| 28 | `pay_slips.status = paid` | écriture de règlement, rapprochement bancaire, clôture du lot | R-028 |
| 29 | `expense_reports.status = submitted` | **contrôle d'absence et de politique de frais**, réservation budgétaire | R-029 |
| 30 | `expense_reports.status = approved` | écriture 625x / 44566 / 421, élément de paie, échéancier de remboursement | R-030 |
| 31 | `expense_reports.status = rejected` | libération de la réservation, retour au salarié avec motif | R-031 |
| 32 | `expense_reports.status = reimbursed` | lettrage avec l'écriture de paie, clôture du dossier | R-032 |
| 33 | `leave_requests.status = pending` | réservation du solde, alerte au manager, **provision de congés** | **R-033** |
| 34 | `leave_requests.status = rejected` | libération du solde, information du salarié | R-034 |
| 35 | `leave_requests.status = cancelled` | restitution du solde, retrait du registre d'absence, contre-passation en paie | **R-035** |
| 36 | `leave_requests.leave_type` (maternité, paternité, maladie, autre) | règles distinctes : IJSS, maintien, carence, subrogation, visite médicale, DSN | **R-036** |
| 37 | `contracts.status = ended` / `terminated` | solde de tout compte, DSN de fin de contrat, restitution du matériel, révocation des accès, provision congés payés | **R-037** |
| 38 | `contracts.status = suspended` | proratisation de la paie, arrêt des accumulations, information RH | R-038 |
| 39 | `contracts.contract_type` (CDD, apprentissage, stage, interim, freelance) | CDD → échéance et prime de précarité ; apprentissage → exonérations ; stage → gratification ; interim → facturation | **R-039** |
| 40 | `projects.status = completed` | **clôture du projet** : encours (WIP), facturation finale, retenue de garantie, libération des engagements, immobilisation éventuelle | **R-040** |
| 41 | `projects.status = cancelled` | contre-passation des coûts en attente, libération des engagements, analyse d'écart | R-041 |
| 42 | `projects.status = on_hold` | alerte de dérive (temps consommé sans facturation), blocage de la facturation à l'avancement | R-042 |
| 43 | `manufacturing_orders.status = cancelled` | contre-passation des consommations, libération des composants réservés, restitution du coût | **R-043** |
| 44 | `manufacturing_orders.status = in_progress` | consommation réelle des composants, déclaration de production, pointage d'atelier, mise en **en-cours de production** | **R-044** |
| 45 | `manufacturing_orders.status = planned` | réservation des composants, engagement de capacité, réservation de trésorerie | R-045 |
| 46 | `manufacturing_orders.origin = mrp` | traçabilité amont : quel besoin, quelle proposition, quelle règle a créé cet ordre | R-046 |
| 47 | `stock_movements.movement_type = transfer` | **transfert entre dépôts** : deux mouvements liés (sortie + entrée), valorisation conservée, suivi des biens en transit | **R-047** |
| 48 | `sepa_payment_orders.status = rejected` | alerte, réouverture des paiements, **correction et rejeu**, conservation du motif bancaire | **R-048** |
| 49 | `sepa_payment_orders.status = processed` | rapprochement bancaire automatique, changement d'état des factures, échéancier | R-049 |
| 50 | `treasury_transfers.status = executed` | écriture de virement d'un compte à l'autre, mise à jour des deux soldes, prévisionnel | **R-050** |
| 51 | `treasury_transfers.status = cancelled` | contre-passation, restitution des soldes | R-051 |
| 52 | `vat_returns.status = submitted` | statut **vis-à-vis de l'administration**, gel des écritures de la période, lien avec la déclaration transmise | **R-052** |
| 53 | `vat_returns.status = paid` | écriture de paiement de la TVA, rapprochement bancaire, lettrage du compte de TVA | R-053 |
| 54 | `vat_returns.edi_status = rejected` | alerte bloquante, retour en préparation, conservation des motifs de rejet | **R-054** |
| 55 | `dsn_declarations.status = rejected` | alerte bloquante RH, correction, rejeu, historique des rejets | **R-055** |
| 56 | `social_declarations.status = rejected` | idem, avec impact sur les cotisations et le prélèvement à la source | R-056 |
| 57 | `budget_commitments.status = consumed` | **libération** de l'engagement quand la facture arrive (`BUD-03`) | **R-057** |
| 58 | `budget_commitments.status = cancelled` | libération motivée, avec trace | R-058 |
| 59 | `collection_reminders.status = sent` | **horodatage de la relance** (sans quoi elle est renvoyée tous les jours : `EF-02`) | **R-059** |
| 60 | `collection_reminders.status = paid` | arrêt des relances, sortie de la file, mise à jour de l'ancienneté | R-060 |
| 61 | `collection_reminders.status = cancelled` | arrêt motivé et tracé (contentieux, geste commercial) | R-061 |
| 62 | `pos_tickets` — **aucune contrainte `CHECK` sur le statut** | contraindre le statut : aujourd'hui un ticket qui n'est pas exactement `completed` **disparaît de l'écriture de clôture sans un mot** | **R-062** |
| — | `asset_free_fields.field_type`, `chart_accounts.type`, `chart_account_templates.type`, `tax_rates.category`, `reporting_plans.report_type`, `document_templates.document_type`, `audit_log.action`, `interviews.type`, `investments.type`, `legal_declarations.declaration_type`, `payroll_tax_grid_lines.category`, `payroll_components.type` | états **descriptifs** : aucun chaînage exigé. Inscrits ici pour dire qu'ils ont été examinés — un audit qui ne nomme pas ce qu'il écarte n'est pas un audit | — |

### B.3 Les chaînages à l'**intérieur** d'un même module

La demande portait aussi sur les chaînages internes. Ils n'apparaissent pas dans la matrice de §A.1
(qui ne compte que les liens entre modules) et sont pourtant aussi critiques : ce sont les tronçons
d'une même chaîne métier.

| Module | Chaînage interne attendu | Mesuré |
|---|---|---|
| **Comptabilité** | lettrage ↔ âge de la dette ↔ relance ↔ provision pour dépréciation ↔ écriture de clôture ; extrait bancaire ↔ pointage ↔ lettrage ↔ état de rapprochement ; à-nouveaux ↔ exercice précédent ↔ reports ; numérotation ↔ pièce ↔ grand livre | partiel : lettrage testé (`175`), provision existante mais non reliée (`calculate_provisions` = 3/7), relance **cassée** (`EF-01`, `EF-02`) |
| **Commercial** | devis ↔ commande ↔ livraison ↔ facture ↔ avoir ↔ règlement ↔ relance ; commande ↔ prix ↔ remise ↔ marge | devis → commande non chaîné (`R-001`), marge prévisionnelle absente |
| **Stock** | besoin (MRP) ↔ proposition ↔ commande ↔ réception ↔ stock ↔ CUMP ↔ écriture ; lot ↔ traçabilité amont/aval ↔ rappel | MRP existe (`run_mrp`, 3/7) ; `transfer` non traité (`R-047`) ; rappel/qualité non chaîné |
| **Production** | OF ↔ nomenclature ↔ consommation ↔ rebuts ↔ PF ↔ coût ↔ marge par OF | partiel : rebuts corrigés (229), multi-niveaux absent, `in_progress` muet (`R-044`) |
| **RH / Paie** | contrat ↔ salarié ↔ absence ↔ temps ↔ variable ↔ bulletin ↔ cumuls ↔ écriture ↔ virement ↔ DSN | **le maillon faible** : les quatre sources d'absence ne convergent pas, `pay_runs.approved` muet (`R-025`) |
| **Projets** | devis ↔ projet ↔ budget ↔ temps ↔ coût ↔ facturation ↔ marge ↔ clôture | `calculate_project_profitability` (4/7) ; clôture de projet muette (`R-040`) |
| **Trésorerie** | prévision ↔ échéancier ↔ ordre de paiement ↔ virement ↔ relevé ↔ rapprochement | `cash_flow_forecast` (4/7) ; virement interne muet (`R-050`) |
| **Caisse** | ticket ↔ session ↔ clôture ↔ écart ↔ TVA ↔ stock ↔ journal NF-525 | le plus complet du produit (5/7 sur la chaîne, `219`) |

### B.4 Le verdict de l'étape 2

| Question | Réponse mesurée |
|---|---|
| Combien d'actions ont été recensées ? | **173 couples (table, colonne)** et **671 valeurs de statut** |
| Combien exigent un chaînage ? | **62 règles** identifiées (R-001 → R-062), dont **34 prioritaires** |
| Combien ont un chaînage aujourd'hui ? | **4 couples entièrement couverts**, 20 partiels |
| Combien de chaînages existent au total ? | **62 fonctions transverses**, notées **3,65/7** en moyenne |
| Combien de couples de modules sont vides ? | **12**, dont 5 structurellement gênants (§A.4) |
| Combien de chaînages internes manquent ? | au moins **9 familles** (§B.3) |
| Combien de tests de robustesse existent ? | **aucun** des 8 tests dynamiques (D1 → D8) |

---

## Partie C — Étape 3 : compilation des chaînages chez les leaders

Ce qui suit vient de la **documentation officielle des éditeurs**, citée source par source. L'objet
n'est pas de résumer des brochures commerciales : c'est de relever **les mécanismes** que les leaders
ont jugés assez importants pour les documenter, puis de les comparer à nos 62 chaînages.

### C.1 Le « document flow » : le chaînage est un objet de premier ordre

**SAP** (Help SAP, *Document Flow* — [source](https://help.sap.com/doc/b183ce53118d4308e10000000a174cb4/700_SFIN3E%20006/en-US/b4dfb65334e6b54ce10000000a174cb4.html))
décrit le document flow comme « les documents consécutifs directement liés à une transaction
commerciale » : « **les documents individuels forment des chaînes de documents** ». Pour chaque
document appelé, SAP affiche **les documents précédents, suivants, et de référence**. La liste des
objets chaînés couvre exactement nos trous : demande d'achat → commande → **réception / sortie de
stock et leur annulation (extourne)** → facture ; demande de prix → offre → commande → **livraison** →
retour → **livraison de retour** → demande d'avoir → avoir **et extourne d'avoir** → facture **et
extourne de facture** ; notification qualité ; ordre de maintenance ; confirmation de temps.

Trois leçons directes :

1. **l'extourne (contre-passation) est dans la chaîne**, pas à côté : SAP modélise l'annulation comme
   un *document* chaîné, jamais comme une suppression. C'est le motif qui manque à 90 % de nos
   chaînages (critères C4/C5 de §A.3) ;
2. **les documents de référence** (devis, contrat, commande ouverte) font partie du chaînage — ce que
   nous ne savons pas faire : aucune colonne `reference_type` / `reference_id` homogène ;
3. la chaîne se parcourt **dans les deux sens**, depuis n'importe quel maillon.

**Oracle NetSuite** (*Using Transaction Links* —
[source](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N551392.html)) modélise
le même besoin par des liens typés : `Created From` (amont), `Orders and Sales` (aval : une estimation
ouvre les commandes, ventes au comptant et factures créées), et les liens d'**affectation** — « les
paiements et avoirs fournissent des liens vers les transactions auxquelles ils s'appliquent ».
Autrement dit : **le lettrage est lui-même un maillon de la chaîne**, ce que nos `payments` ne font pas
(`R-022`, `R-023`).

**Microsoft Dynamics 365 Business Central** (*Track order lines to related documents* —
[source](https://github.com/MicrosoftDocs/dynamics365smb-docs/blob/main/business-central/across-how-to-track-document-lines.md))
offre le *Document Line Tracking* : depuis une **ligne** de commande, on remonte aux documents liés
(devis, expéditions, réceptions, commandes ouvertes), **y compris depuis les lignes archivées**. La
granularité est la ligne, pas l'en-tête — indispensable dès qu'une commande est livrée en plusieurs
fois (chez nous : livraisons partielles, reliquats non tracés — `R-004`, `R-013`).

**ERPNext / Frappe** (*Checking Link Between Documents* —
[source](https://docs.frappe.io/erpnext/check-link-between-documents)) expose un outil « Links » qui
**liste tous les documents liés en aval**, les liens amont étant visibles dans le document lui-même.
Instruction pour nous : à la question « qu'est-ce que ce document a généré ? », notre produit n'a
**aucune réponse générique** — il faut connaître écran par écran la table aval.

### C.2 Chaque document déclare son effet comptable

ERPNext documente explicitement **quels documents touchent le grand livre et lesquels ne le touchent
pas** (*How Transactions Affect the Ledger* —
[source](https://docs.frappe.io/erpnext/how-transactions-affect-the-ledger)) :

| Document | Effet commercial | Effet habituel sur le grand livre |
|---|---|---|
| Devis | offre à un prospect | **aucun** |
| Commande client | engagement client et plan de réalisation | **aucun**, sauf acomptes liés enregistrés séparément |
| Commande fournisseur | engagement fournisseur | **aucun**, sauf acomptes liés |
| Bon de livraison | marchandise livrée | **stock et coût** (+ accrual si inventaire permanent) |
| Bon de réception | marchandise reçue | **stock et accrual** |
| Facture de vente | facturation | **produit, taxe, créance** (+ stock en option) |
| Facture d'achat | facturation fournisseur | **charge ou actif, taxe, dette** |
| Écriture de règlement | mouvement d'argent | **banque ou caisse et compte de tiers** |

Et la phrase la plus utile de cette compilation :

> *« Un document aval créé directement peut être valide, mais il perd sa référence amont et ses
> contrôles opérationnels : une facture de vente directe ne met pas à jour le pourcentage facturé de
> la commande ; un bon de livraison direct ne met pas à jour le pourcentage livré de la commande. »*

C'est **exactement** le défaut de nos chaînes (`R-004`, `R-006`, `R-009`) : chez nous le chemin court
est le seul chemin, et rien n'avertit que le pourcentage facturé ne bouge pas. ERPNext fournit en plus
les outils de diagnostic qui nous manquent : la vue `Accounting Ledger` depuis un document, le
`Stock Ledger` en regard, le rapport **Stock and Account Balance Comparison**, le *reposting* de
valorisation, et les restrictions `Accounts Frozen Upto` / *Accounting Period*. Nos équivalents :
exercice et période sont tenus par le noyau `187` — mais **aucun rapport de comparaison stock / grand
livre** n'existe.

### C.3 L'engagement : trois états simultanés (budgété, engagé, réalisé)

**Procore** (**committed costs** —
[source](https://www.procore.com/library/committed-costs)) formalise la distinction que notre `BUD-03`
rate : *budgété* (prévision), *engagé* (contrat ou commande signé, non encore facturé), *réel*
(facture). L'engagement naît du **contrat ou de la commande**, et **les changements de prix passent
par un ordre de changement** : l'engagement se met à jour par un **document**, jamais par une
modification silencieuse. Chez nous : l'engagement saisi reste `active` et n'est **jamais libéré**
(double déduction) et `purchase_orders.confirmed` ne crée rien (`R-010`, `R-012`, `R-057`).

### C.4 Le lettrage et la TVA : **l'écriture est générée par le rapprochement**

**Pennylane** (aide officielle, *Lettrer des écritures* —
[source](https://help.pennylane.com/fr/articles/18751-lettrer-des-ecritures)) va plus loin que tout ce
que nous avons : chez eux, **lettrer n'est pas constater, c'est produire**.

| Mécanisme Pennylane | Ce qu'il produit |
|---|---|
| Lettrage d'une écriture 401/411 | le compte est lettré **et** l'**écriture de TVA sur encaissements** (44564 / 44574) est **générée et lettrée** |
| Lettrage avec une écriture de vente en OD ou en à-nouveaux | génération automatique de l'écriture de récupération de TVA |
| Modification du compte de charge/produit d'une transaction déjà lettrée | **régénération complète** de l'écriture : l'ancienne est supprimée (lignes de TVA comprises) et recréée ; le lettrage est à refaire |
| Dé-lettrage | **suppression automatique** de l'écriture de récupération de TVA, **à condition que le lien facture ↔ transaction soit intact** |
| Lettrage dans une période figée | écriture RT **datée au premier jour après la fin de la période figée** (J+1), pour préserver l'intégrité des déclarations déjà déposées |
| Lettrage automatique | rapprochement par **solde nul, somme identique, numéro de pièce ou libellé** ; comptes lettrables par défaut : 4, 23, 511, 58 |
| Lettrage d'un paiement SEPA | automatique **si la banque reprend l'identifiant du fichier XML** dans le libellé — sinon manuel |

Deux enseignements majeurs :

1. **le chaînage est réversible par construction** : dé-lettrer **défait** ce que lettrer a produit.
   C'est le test D4 de §A.5, implémenté chez un éditeur français, à l'écran, tous les jours ;
2. **une période figée ne bloque pas l'opération, elle la déplace** (écriture datée J+1). Nous
   refusons (et c'est bien), mais nous n'offrons **aucune** alternative : l'utilisateur est bloqué
   sans chemin de régularisation. Différenciateur immédiat à prendre.

### C.5 Le diagnostic permanent et la réversibilité

| Mécanisme | Où | Ce qu'il apporte | Chez nous |
|---|---|---|---|
| Documents d'extourne (annulation) | SAP | l'annulation est un **document chaîné**, pas une suppression | `cancelled` non traité sur 62 états |
| Régénération d'écriture après changement d'imputation | Pennylane | la chaîne se **recalcule** au lieu de diverger | aucun équivalent |
| Rapport **Stock ↔ Grand livre** | ERPNext | détecte la divergence stock/compta (nos `S-01→S-07`) | **absent** |
| *Reposting* de valorisation | ERPNext | corrige une valorisation après coup | `calculate_stock_valuation_at_date` existe (3/7), **non branché** |
| Gel de période, avec déplacement | ERPNext, Pennylane | empêche d'écrire dans le passé **sans bloquer le travail** | refus sec, aucun chemin |
| Liens aval consultables (« Links ») | ERPNext | répond à « qu'est-ce que ce document a produit ? » | **absent** — aucune vue de chaînage |
| Traçabilité par **ligne** | Business Central | reliquats, livraisons partielles, lignes archivées | en-tête seulement |
| Lettrage typé et affectation | NetSuite | règlement ↔ factures, avoir ↔ facture | lettrage testé (`175`) mais **non chaîné à la TVA** |
| Engagements par document | Procore | budgété / engagé / réel en permanence | engagements jamais libérés (`BUD-03`) |

### C.6 Ce que la compilation enseigne — cinq principes, retenus pour la partie D

1. **Le chaînage est un objet du produit, pas un effet de bord du code.** SAP, NetSuite, BC et ERPNext
   l'exposent, le nomment et le naviguent. Chez nous, c'est une conséquence invisible d'un
   déclencheur.
2. **Chaque document déclare son effet comptable**, y compris quand cet effet est « aucun » (ERPNext).
   C'est un **contrat** : nous n'en avons aucun.
3. **L'annulation est un document**, jamais une suppression (SAP, ERPNext, Pennylane).
4. **Le chaînage est généré et régénéré** par le système, pas saisi par l'utilisateur (Pennylane).
5. **Le chaînage est surveillé** : rapport de cohérence stock/compta, reposting, gel de période
   (ERPNext). Ces trois outils sont des **fonctions commerciales**, pas des détails techniques : ils
   sont vendus comme la promesse « vos chiffres sont justes ».

---

## Partie D — Étape 4 : comparaison, écarts, avances et innovation

### D.1 La matrice chaîne × éditeur

Légende : ✅ présent et documenté · 🟠 partiel · 🔴 absent ou cassé · **n.d.** non documenté dans les
sources consultées (je ne tranche pas ce que je n'ai pas vérifié).

| # | Chaîne | Nous (mesuré) | SAP | NetSuite | Dyn. 365 BC | ERPNext | Pennylane | Procore | PayFit / Silae |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | **Document flow navigable** (amont / aval / référence) | 🔴 | ✅ | ✅ | ✅ | ✅ | 🟠 | ✅ | n.d. |
| 2 | **Traçabilité par ligne** (reliquats, livraisons partielles) | 🟠 | ✅ | ✅ | ✅ | ✅ | n.d. | ✅ | n.d. |
| 3 | **Contrat d'effet comptable par type de document** | 🔴 | ✅ | ✅ | ✅ | ✅ | ✅ | 🟠 | n.d. |
| 4 | **Annulation = document d'extourne** (jamais suppression) | 🟠 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 5 | **Idempotence du chaînage** (rejeu sans doublon) | 🔴 15 % | ✅ | ✅ | ✅ | ✅ | ✅ | n.d. | ✅ |
| 6 | **Régénération après changement d'imputation** | 🔴 | 🟠 | 🟠 | 🟠 | 🟠 | ✅ | n.d. | n.d. |
| 7 | **Rapport de cohérence stock ↔ grand livre** | 🔴 | ✅ | ✅ | ✅ | ✅ | 🟠 | n.d. | n.d. |
| 8 | **Gel de période + chemin de régularisation** | 🔴 | ✅ | ✅ | ✅ | ✅ | ✅ | n.d. | n.d. |
| 9 | **Engagement budgétaire par document, libéré** | 🔴 `BUD-03` | ✅ | ✅ | ✅ | ✅ | n.d. | ✅ | n.d. |
| 10 | **TVA générée par le lettrage** (encaissements) | 🔴 | ✅ | 🟠 | 🟠 | 🟠 | ✅ | n.d. | n.d. |
| 11 | **Paie → écriture comptable** | 🟠 `181` | ✅ | ✅ | ✅ | ✅ | ✅ | n.d. | ✅ |
| 12 | **Absence → temps → paie → projets → frais** | 🔴 | ✅ | 🟠 | 🟠 | 🟠 | n.d. | ✅ *(chantier)* | ✅ |
| 13 | **Lot / série → rappel produit** | 🟠 `S-11` | ✅ | ✅ | ✅ | ✅ | n.d. | n.d. | n.d. |
| 14 | **Coût de revient projet / chantier** (WIP, retenue de garantie) | 🟠 | ✅ | ✅ | ✅ | 🟠 | n.d. | ✅ | n.d. |
| 15 | **Frais de mission ↔ absence ↔ TVA récupérable** | 🔴 | ✅ | 🟠 | 🟠 | 🟠 | 🟠 | ✅ | ✅ |

### D.2 Les écarts critiques — classés par conséquence

**Niveau 1 — ce qui se voit en démonstration commerciale, et qui disqualifie.**
Un prospect qui a connu SAP, NetSuite ou même ERPNext pose trois questions auxquelles nous ne pouvons
pas répondre aujourd'hui :

| Écart | La question du prospect | Ce que les leaders répondent | Notre état |
|---|---|---|---|
| **Chaîne 1** | « Je clique sur cette commande : qu'est-ce qui en est sorti ? » | SAP ouvre la chaîne complète, amont et aval ; ERPNext liste les liens aval | **impossible** : aucune vue, aucune colonne de référence homogène |
| **Chaîne 3** | « Qu'est-ce que la validation de ce bon de réception a produit comptablement ? » | table de correspondance document → effet (ERPNext), document flow + pièces comptables (SAP) | **impossible** : l'effet est caché dans un déclencheur, et aujourd'hui il n'existe pas (`S-01→S-04`) |
| **Chaîne 12** | « Mon salarié est absent : puis-je saisir des heures, une note de frais, du temps projet ce jour-là ? » | PayFit/Silae bloquent côté paie et temps ; Procore bloque côté chantier | **oui, tout est accepté** — c'est le défaut fondateur de tout ce travail |

**Niveau 2 — ce qui se voit à l'usage, en trois mois.** Divergences silencieuses (chaînes 7, 11, 13,
15), engagements jamais libérés (9), annulations qui laissent des traces (4), périodes figées sans
issue (8), idempotence absente (5).

**Niveau 3 — ce qui se voit au premier audit.** Absence de contrat d'effet comptable (3), absence de
régénération (6), TVA non recalculée après lettrage ou annulation (10).

### D.3 Ce que nous avons et que les leaders cités n'ont pas — nos avances réelles

À dire en avant-vente, avec la preuve :

| Avance | Preuve | Pourquoi c'est rare |
|---|---|---|
| **Isolation par société prouvée par exécution sur 340 tables** | `105`, `H02`, `ISO` | la plupart des ERP *affirment* l'isolation ; peu la **testent** dans leur CI |
| **Contre-épreuve systématique** : un test qui n'a jamais été vu rouge ne prouve rien | registre `expected_failures.sql` + protocole §4.7 du plan correctif | quasi inexistant sur le marché : les éditeurs testent le chemin nominal |
| **Contrôles statiques du schéma en CI** (`check_tenant_guard`, `check_status_writes`, `check_trigger_reachability`) | `app/sql/ci/` | outillage interne rare ; nous le rendons **livrable** |
| **Localisation par pays** (plan comptable, packs, neutralité du code) | `201_chart_by_country.sql`, cahier LOC | NetSuite/Odoo le font ; la plupart des ERP français sont mono-pays |
| **Paie + comptabilité + projets + caisse dans la même base, même schéma, même RLS** | 376 tables, 1 schéma | Pennylane et PayFit sont des **silos reliés par connecteurs** ; nous n'avons pas de rupture de synchronisation |
| **Écritures automatiques soumises au même noyau comptable que la saisie** | `187` (équilibre, exercice, période, numéros) | beaucoup d'ERP ont un « module d'interface » qui contourne les contrôles |

**La phrase à retenir en avant-vente** : *nos concurrents vendent le chaînage ; nous pouvons vendre le
chaînage **vérifié**.* C'est exactement l'innovation I-05 ci-dessous, et elle est à notre portée parce
que le harnais existe déjà.

### D.4 Ce que personne n'a — 12 innovations à notre portée

Chaque innovation est décrite par : **ce que le client voit**, **ce qu'il faut techniquement**, et
**pourquoi nos actifs actuels la rendent accessible** (le harnais de test, le registre de défauts, la
RLS prouvée, le noyau comptable `187`, la base unique). Les efforts sont des **estimations**.

#### I-01 — La « Vue Chaîne » : tout document ouvert sur son amont et son aval

- **Le client voit** : depuis n'importe quel document (devis, commande, réception, facture, bulletin,
  ticket de caisse, ordre de fabrication, note de frais), une frise cliquable : ce qui l'a produit,
  ce qu'il a produit, et les pièces comptables associées. C'est le document flow de SAP, mais aussi
  pour la paie, les projets et le temps — ce que SAP lui-même ne fait pas dans un seul écran.
- **Techniquement** : une table `document_links (tenant_id, amont_type, amont_id, aval_type, aval_id,
  link_type, created_at)` alimentée par une fonction unique `link_documents(...)`, appelée par tous
  les chaînages ; une vue récursive d'ascendance/descendance ; un composant d'interface unique
  réutilisé par tous les écrans.
- **Pourquoi maintenant** : nous avons déjà 62 chaînages identifiés et une fonction par maillon ; il
  s'agit de les **instrumenter**, pas de les réécrire. Effort : **4 j**.

#### I-02 — Le contrat d'effet comptable, déclaré en base et testé

- **Le client voit** : sur chaque type de document, un onglet « Effet comptable » qui dit
  précisément ce qui sera produit (et « aucun », s'il ne produit rien), avec un lien vers le
  paramétrage des comptes.
- **Techniquement** : `document_effects (tenant_id, document_type, event, journal_code,
  account_rule, writes_stock, writes_payroll, requires_approval, notes)` + un test qui **compare la
  déclaration au comportement réel** : valider un document de ce type doit produire exactement ce que
  la table annonce.
- **Pourquoi maintenant** : c'est le prolongement direct du tableau de la partie C.2 et le remède au
  défaut « l'effet est caché dans un déclencheur ». Effort : **3 j**.

#### I-03 — L'indice de cohérence, publié chaque nuit

- **Le client voit** : un score par société et par module (« stock ↔ grand livre : 100 % », « absence
  ↔ temps : 97 %, 3 écarts »), avec la liste des écarts et un bouton « corriger ».
- **Techniquement** : `audit_chains(tenant_id)` qui exécute une batterie d'invariants transversaux
  (voir E.3), un job quotidien, un écran et un envoi en cas de dégradation.
- **Pourquoi maintenant** : les données pour détecter les écarts existent déjà (c'est ce que fait
  `EF-02` en négatif : une relance renvoyée tous les jours) ; il manque le rendez-vous quotidien.
  Effort : **3 j**. **C'est la fonctionnalité la plus vendable du lot** : personne ne publie un score
  de cohérence vérifiable.

#### I-04 — Le simulateur d'impact (« avant de valider, voici ce qui va se produire »)

- **Le client voit** : avant de valider une commande, une réception, une paie, une absence, une note
  de frais : la liste exacte des effets (écritures, mouvements de stock, éléments de paie, refus
  éventuels) — un **essai à blanc**.
- **Techniquement** : chaque chaînage exposé en deux modes, `apply` et `preview`, ou exécution dans
  une transaction annulée avec rapport ; une fonction `preview_chain(document_type, id)`.
- **Pourquoi maintenant** : PostgreSQL nous donne la transaction annulée gratuitement ; l'effort est
  dans l'unification des rapports, pas dans les calculs. Effort : **4 j**.

#### I-05 — Le banc d'épreuve des chaînages (les 8 tests D1→D8) publié

- **Le client voit** : une page « Robustesse » qui indique, pour chaque chaîne, le résultat des 8
  épreuves (rejeu, concurrence, panne partielle, annulation, réouverture, retour arrière, volume,
  isolation) — avec la date du dernier passage.
- **Techniquement** : les tests existent déjà dans le harnais du dépôt (fixtures `_mk_tenant`,
  `_rec`, registre) ; il faut les **généraliser par chaîne** et publier le résultat par société.
- **Pourquoi maintenant** : c'est ce qui transforme « nous testons beaucoup » en **preuve opposable**
  — et c'est rejouable par le client sur sa propre base. Effort : **5 j** (le plus élevé, le plus
  différenciant : les éditeurs testent en interne, aucun ne publie le résultat au client).

#### I-06 — Le registre d'événements métier unifié

- **Le client voit** : un journal d'activité unique par société (« 14:32 — commande C-1042 confirmée →
  engagement 12 000 €, réservation 40 articles »), filtrable par module, par utilisateur, par
  document ; et des **automatisations** branchées dessus (« quand un devis est accepté, créer la
  commande et notifier le commercial »).
- **Techniquement** : `domain_events (tenant_id, event_name, aggregate_type, aggregate_id, payload
  jsonb, actor_id, created_at)` alimentée par les chaînages ; consommateurs : notifications,
  webhooks, audit, IA.
- **Pourquoi maintenant** : nous avons déjà `audit_log`, `project_activity_log` et une file de
  webhooks (234) — trois mécanismes partiels à unifier en un seul. Effort : **3 j**.

#### I-07 — Le moteur de règles transverses, paramétrable par le client

- **Le client voit** : une page « Règles » où il écrit lui-même, sans code, ses règles de gestion
  transverse : « si absence bloquante → refuser note de frais, heures supplémentaires, temps projet »,
  « si client en retard de plus de 60 jours → bloquer toute nouvelle commande », « si marge prévisible
  < 5 % → validation du directeur ». Chaque règle est testable depuis l'écran (« essayer cette règle »).
- **Techniquement** : `chain_rules (tenant_id, code, déclencheur, condition jsonb, action, message,
  priorité, active)` + un évaluateur unique appelé par les gardes (`assert_*` de W9).
- **Pourquoi maintenant** : nos gardes sont aujourd'hui **codées en dur** (seuils 7 h / 8 h
  contradictoires, diviseurs 4,33 / 30 / 21 / 151,67, `affects_pay` en dur). Externaliser ces
  paramètres est de toute façon nécessaire — autant en faire un produit. Effort : **5 j**.

#### I-08 — L'explicabilité : « pourquoi ce chiffre ? »

- **Le client voit** : sur n'importe quel montant (chiffre d'affaires d'un mois, marge d'un projet,
  net à payer, écart budgétaire), un bouton qui déroule la **chaîne des documents et écritures** qui
  produit ce montant, avec les liens vers chaque pièce.
- **Techniquement** : le dictionnaire de données unique (`metric_definitions`) + l'exploitation de
  I-01 et I-06 : un indicateur est une requête **nommée et datée**, jamais un calcul recopié dans un
  écran (aujourd'hui `getBudgetTracking`, `calculate_project_profitability` et les tableaux de bord
  recalculent chacun leur version de la marge — `BUD-01`, `PROJ-02`).
- **Pourquoi maintenant** : c'est le remède structurel aux **définitions concurrentes** (deux calculs
  d'avancement, deux moteurs d'amortissement, trois calculs d'heures supplémentaires). Un ERP qui
  explique ses chiffres devient **auditable par le client**. Effort : **4 j**.

#### I-09 — Le gel de période avec régularisation guidée

- **Le client voit** : quand il agit sur une période clôturée, au lieu d'un refus sec : « cette
  période est clôturée ; voici l'écriture de régularisation proposée au 01/04, montant X — appliquer ?
  » ; toutes les régularisations sont listées dans un écran unique.
- **Techniquement** : la table des régularisations (`period_adjustments`), la proposition automatique
  depuis la chaîne (à la manière de Pennylane pour la TVA), et un écran de suivi.
- **Pourquoi maintenant** : nous refusons déjà correctement (noyau `187`) ; il ne manque que le
  **chemin de sortie**, qui est précisément ce qui manque à l'utilisateur bloqué. Effort : **3 j**.

#### I-10 — L'absence comme fait transversal de première classe

- **Le client voit** : un salarié absent le 10 mars ne peut ni pointer, ni saisir des heures
  supplémentaires, ni du temps projet, ni une note de frais ; sa paie est juste ; son solde est juste ;
  ses tâches sont redistribuées avec une alerte ; **et la production/le planning en tient compte**
  (chaîne 12 de la matrice, le couple `production ↔ RH` vide de §A.4).
- **Techniquement** : c'est la vague W9 du plan correctif (`employee_absence_days`, 16 contrôles,
  34 assertions) **plus** l'extension au planning de production (capacité) que le plan prévoit en §3.5.
- **Pourquoi maintenant** : PayFit le fait pour la paie, Procore pour le chantier, **personne ne le
  fait pour l'ensemble paie + projets + frais + tâches + capacité**. C'est notre différenciateur
  « tout-en-un », et il est déjà spécifié. Effort : **4 j** (déjà chiffré au plan).

#### I-11 — La localisation multi-pays par chaînes paramétrées

- **Le client voit** : le même produit en France, à Djibouti, dans la zone CEMAC ou au Maghreb, avec
  le plan comptable, la TVA, les jours fériés, les conventions, la monnaie et les déclarations du
  pays — sans fork du code.
- **Techniquement** : les packs de localisation existent (`201`), il faut y brancher **les chaînes** :
  quel document produit quelle déclaration, quel taux, quelle règle de paie (aujourd'hui : constantes
  françaises en dur — `/30`, `/21`, `/151,67`, `4,33`, `€`, `DSN`).
- **Pourquoi maintenant** : c'est un argument de conquête sur les marchés où les éditeurs français ne
  vont pas, et Odoo/NetSuite y sont chers et lourds. Effort : déjà chiffré au cahier de localisation.

#### I-12 — L'assistant adossé au chaînage (IA avec preuve)

- **Le client voit** : trois usages concrets, tous branchés sur la chaîne :
  1. **prévision de trésorerie par chaîne** (commandes → livraisons → factures → encaissements
     attendus, engagements fournisseurs à venir) plutôt qu'une extrapolation statistique ;
  2. **détection d'anomalies transverses** : frais un jour d'absence, marge prévisionnelle négative,
     engagement qui n'arrive jamais en facture, réception sans écriture, temps facturé sans projet ;
  3. **question en langage naturel** avec réponse **prouvée** : « pourquoi la marge du projet X a
     baissé ? » → réponse + liens vers les documents et écritures concernés.
- **Techniquement** : rien de tout cela n'exige un modèle : il exige **la chaîne et l'événement**
  (I-01, I-06). L'IA vient en dernier, sur des données déjà explicables.
- **Pourquoi maintenant, et honnêtement** : je n'ai **pas vérifié** l'état exact des fonctions d'IA
  chez chaque éditeur cité ; ce que je constate, c'est que l'IA annoncée par le marché (agents de
  clôture, détection d'anomalies) repose sur un chaînage documentaire — donc sur ce qui nous manque
  aujourd'hui. Avoir le chaînage est la condition, pas l'IA. Effort : **5 j** après I-01/I-06.

**Total des 12 innovations : ≈ 46 j**, dont **13 j** pour les trois premières (I-01, I-02, I-03), qui
sont aussi les plus vendables.

---

## Partie E — Le socle : sans lui, 62 règles deviendront 62 bugs

Écrire 62 chaînages un par un, chacun dans son fichier, reproduirait exactement ce que l'étape 1 a
mesuré : 62 maillons isolés, notés 3,65/7. Le socle ci-dessous est **le préalable technique** de toute
la partie B.

### E.1 Le contrat de chaînage — six invariants, pour chaque maillon

| Invariant | Règle | Vérification |
|---|---|---|
| **1. Atomicité** | un maillon s'exécute dans la transaction de l'action déclenchante ; il n'écrit jamais « plus tard » | D3 (panne partielle) |
| **2. Idempotence** | la clé de l'aval est `(source_type, source_id, effet)` : rejouer ne double pas | D1 (rejeu) |
| **3. Réversibilité** | tout effet a un **effet inverse** défini ; l'annulation crée un document d'extourne, jamais une suppression | D4 (annulation) |
| **4. Traçabilité** | chaque effet écrit son lien amont dans `document_links` | D6 (retour arrière) |
| **5. Isolation** | chaque écriture porte le `tenant_id` **de la source**, jamais `current_tenant_id()` quand la source l'indique | D8 (isolation) |
| **6. Explicabilité** | le maillon émet un événement lisible (`domain_events`) : quoi, pour qui, combien, pourquoi | revue + I-08 |

**Signature cible d'un maillon** (gabarit, calqué sur ce que le dépôt fait déjà bien dans les
migrations 229, 240 et 244) :

```sql
CREATE OR REPLACE FUNCTION chain_<domaine>_<effet>(p_source_type text, p_source_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_tenant uuid; v_existant uuid; v_aval uuid;
BEGIN
  SELECT tenant_id INTO v_tenant FROM <table_source> WHERE id = p_source_id;   -- 5. isolation
  IF v_tenant IS NULL THEN RETURN NULL; END IF;
  IF NOT _chain_autorise(v_tenant, p_source_type, p_source_id) THEN RETURN NULL; END IF;

  SELECT aval_id INTO v_existant FROM document_links
   WHERE tenant_id = v_tenant AND amont_type = p_source_type AND amont_id = p_source_id
     AND link_type = '<effet>';                                               -- 2. idempotence
  IF v_existant IS NOT NULL THEN RETURN v_existant; END IF;

  <les écritures de l'effet, avec tenant_id = v_tenant et reference_id = p_source_id>  -- 4. traçabilité

  PERFORM link_documents(v_tenant, p_source_type, p_source_id, '<aval_type>', v_aval, '<effet>');
  PERFORM emit_domain_event(v_tenant, '<event_name>', p_source_type, p_source_id, jsonb_build_object(...));
  RETURN v_aval;
EXCEPTION WHEN others THEN
  RAISE EXCEPTION 'Chaîne % sur % % : %', '<effet>', p_source_type, p_source_id, SQLERRM;  -- 6. explicabilité
END $$;
```

Un maillon écrit dans ce gabarit satisfait **d'office** C1, C2, C3, C4, C5 et C6 de la grille §A.3 :
la note passe de 3,65/7 à **6/7**, et à 7/7 avec les tests D1→D8 au vert.

### E.2 Le trio de registres — le cœur du socle

| Registre | Rôle | Pourquoi un registre unique |
|---|---|---|
| `document_links` | **qui a produit quoi** : `(tenant_id, amont_type, amont_id, aval_type, aval_id, link_type, created_at)` | c'est lui qui rend la « Vue Chaîne » (I-01) et le retour arrière (D6) possibles **sans un écran par cas** |
| `document_effects` | **ce que ce document doit produire** : déclaration par type de document et par événement | c'est le contrat (I-02) et le support du contrôle de §E.5 |
| `domain_events` | **ce qui s'est passé** : événement lisible, horodaté, avec acteur | alimente notifications, webhooks, audit, automatisations, IA (I-06, I-12) |

Ces trois tables sont **petites**, **génériques** (aucune logique métier dedans) et **transverses**
(les 11 modules les utilisent). C'est l'inverse de la situation actuelle, où chaque chaînage invente
sa propre trace : `reference`, `reference_id`, `reference_type`, `source`, `source_id`, `description`…
**aucune de ces conventions n'est partagée** aujourd'hui.

### E.3 Les invariants transversaux à surveiller chaque nuit (le socle de l'indice I-03)

Un invariant est une **égalité entre deux modules** qui doit être vraie en permanence. Chaque ligne est
vérifiable par une requête ; son écart est un défaut exploitable, pas une opinion.

| # | Invariant | Forme du contrôle | Aujourd'hui |
|---|---|---|---|
| INV-01 | stock valorisé (couches) **=** comptes de stock − variation | `Σ stock_valuation_layers.value` vs `Σ journal_lines` 31x / 603x | **rompu** (`S-01→S-07`) |
| INV-02 | quantité par dépôt **=** somme des mouvements du dépôt | `stock_quantities` vs `stock_movements` | rompu |
| INV-03 | rien n'est réservé sans commande confirmée non livrée | `reserved_quantity` vs `sales_orders` | rompu (`S-07`) |
| INV-04 | aucun pointage, temps projet ou frais un jour d'absence bloquante | `employee_absence_days` vs 3 tables | **inexistant** (W9) |
| INV-05 | engagement fournisseur **=** reste à facturer des commandes ouvertes | `budget_commitments` vs `purchase_orders` | rompu (`BUD-03`) |
| INV-06 | réalisé budgétaire **=** mouvements de l'exercice (hors à-nouveaux, clôture, brouillons) | `budgets` vs `journal_lines` | rompu (`BUD-01`, `BUD-02`) |
| INV-07 | lettrage **=** TVA sur encaissements correspondante | lettrage vs comptes 44564 / 44574 | **inexistant** |
| INV-08 | solde relevé **=** solde comptable + en-cours de rapprochement | `bank_transactions` vs 512 | partiellement tenu (`223`) |
| INV-09 | net à payer des bulletins **=** montant du virement | `pay_slips` vs `sepa_payment_orders` | non testé |
| INV-10 | brut de la DSN **=** brut des bulletins du mois | `dsn_declarations` vs `pay_slips` | non testé |
| INV-11 | temps facturé **≤** temps saisi, et facturé **=** lignes de facture | `project_time_entries` vs factures | rompu (`PROJ-01`) |
| INV-12 | marge projet **=** facturé − temps − achats − stock − frais | agrégats croisés | **deux calculs concurrents** (`PROJ-02`) |
| INV-13 | amortissement cumulé **=** compte 28x | `asset_depreciations` vs `journal_lines` | non testé |
| INV-14 | TVA déclarée **=** TVA comptabilisée de la période | `vat_returns` vs `journal_lines` | non testé (M-10) |
| INV-15 | caisse : recette TTC **=** Σ tickets **=** écriture de clôture | `pos_tickets` vs `journal_lines` | **tenu** (219) |
| INV-16 | journal NF-525 intègre (chaîne de hachage sans rupture) | `233` | **tenu** |
| INV-17 | aucune écriture sur exercice ou période fermés | `fiscal_periods` vs `journal_entries` | **tenu** (187) |
| INV-18 | tout document validé a un numéro définitif sans trou | `document_sequences`, `journal_posting_sequences` | **tenu** (217 / 218) |
| INV-19 | aucun document aval orphelin de son amont | `document_links` | **inexistant** |
| INV-20 | toute ligne de paie a une source identifiée (temps, absence, frais, avance) | `payroll_variable_elements.source` | partiel |

**Quatre invariants sont tenus et prouvés** (INV-15 à INV-18) : c'est la base de confiance sur laquelle
construire l'indice. **Le reste est rompu, partiel ou inexistant.** Le score du jour, sur les
invariants vérifiables, serait de l'ordre de **4 à 6 sur 20** — et c'est précisément le chiffre que la
publication de l'indice rend inconfortable **puis** convaincant : un éditeur qui affiche ce score,
puis le fait monter de 6 à 20 devant le client, gagne la confiance qu'aucune plaquette n'achète.

### E.4 Le gabarit de test d'une règle de chaînage

Chaque règle R-xxx (partie B) et chaque contrôle TRV-xx (plan correctif) reçoit **quatre** assertions,
dans le harnais existant :

```
T-1  l'effet attendu est produit          (chiffré : la ligne existe, avec le bon montant)
T-2  le rejeu ne double pas               (D1 : exécuter deux fois, compter une fois)
T-3  l'annulation défait sans supprimer   (D4 : statut source annulé → effet inverse, source intacte)
T-4  l'isolation tient                    (D8 : société A active, la chaîne de B n'est pas touchée)
```

Ce qui donne, pour le plan complet : **62 règles × 4 = 248 assertions**, plus les 34 du scénario
absence, plus les 8 tests D1→D8 sur chaque chaînage existant (62 × 8 = 496 assertions). **Ces tests
sont l'actif le plus précieux du produit** — bien plus que les fonctionnalités qui les déclenchent,
parce qu'eux seuls permettent de dire « c'est juste » sans croire sur parole.

### E.5 La règle d'urbanisme qui empêche le retour du problème

Dans la CI, une étape nouvelle : **tout type de document ou événement déclaré dans l'application doit
avoir une ligne dans `document_effects`**. Un écran, une table ou une transition ajoutés sans
déclaration d'effet font **échouer la construction**.

C'est la clé : sans cette règle, dans six mois nous aurons de nouveau 40 % d'états muets, parce que
rien n'aura forcé le développeur à se poser la question. Avec elle, la question se pose **au moment
où le code s'écrit**, pas six mois plus tard dans un audit.

---

## Partie F — Feuille de route, charge et indicateurs à publier

### F.1 Cinq phases, dans cet ordre — le socle d'abord

| Phase | Contenu | Charge | Dépend de | Livrable mesurable |
|---|---|---:|---|---|
| **P1 — Voir** | `document_links`, `document_effects`, `domain_events` (E.2) ; rétro-instrumentation des **62 chaînages existants** ; « Vue Chaîne » (I-01) ; contrat d'effet (I-02) ; règle d'urbanisme en CI (E.5) | **13 j** | vague W0 du plan | la question « qu'est-ce que ce document a produit ? » a une réponse **générique** |
| **P2 — Prouver** | banc d'épreuve D1→D8 sur les 62 chaînages (I-05) ; `audit_chains()` et les 20 invariants (I-03) ; pages « Robustesse » et « Cohérence » | **13 j** | P1 | note moyenne des chaînages de **3,65/7** à ≥ 6/7 ; l'indice de cohérence est publié et historisé |
| **P3 — Réparer** | les **34 règles prioritaires** de R-001→R-062, chacune dans le gabarit E.1 et testée selon E.4 ; reprise des chaînages internes de §B.3 | **20 j** | P1, P2 + vagues **W1, W3, W4, W9** du plan | les états critiques ne sont plus muets ; l'indice passe de ~5/20 à ≥ 15/20 |
| **P4 — Étendre** | les couples vides de §A.4 : `production ↔ RH` (capacité vs absence), `stock ↔ projets` (consommation chantier), `production ↔ projets` (fabrication à la commande), `production ↔ trésorerie` (engagement), `reporting ↔ tous` (I-08) | **12 j** | P3 | chaque couple vide a ≥ 1 chaînage ; la marge projet devient calculable de bout en bout |
| **P5 — Innover** | I-04 simulateur d'impact, I-06 registre d'événements, I-07 règles clients, I-08 explicabilité, I-09 régularisation guidée, I-11 localisation par chaînes, I-12 assistant | **33 j** | P1, P2 (+ P4 pour l'IA) | les 3 questions de §D.2 reçoivent une réponse **avec preuve à l'écran** |

**Total : ≈ 91 j**, dont **26 j** (P1 + P2) qui rendent tout le reste mesurable. **Les 13 premiers
jours de P1 sont les plus rentables du programme** : ils transforment 62 chaînages invisibles en
actif commercial.

**Trois chemins ne peuvent pas être raccourcis** :

- **le socle avant les règles** : écrire R-001→R-062 sans `document_links` reproduirait 62 maillons
  isolés notés 3,65/7 ;
- **W1 (isolation) et W4 (paie) avant les règles RH** : R-033→R-039 touchent congés, contrats et paie ;
  les chaîner avant que la paie n'ait un seul moteur multiplierait les doublons (`RH-02`→`RH-05`) ;
- **W9 (absence) avant `production ↔ RH`** : la capacité ne peut lire une absence que si l'absence
  existe quelque part (chaîne 12 de la matrice).

### F.2 Les cinq indicateurs à publier (le tableau de bord extérieur)

À mettre dans une plaquette, une démonstration ou une réponse à appel d'offres — parce qu'ils sont
**vérifiables sur la base du client**.

| Indicateur | Aujourd'hui (mesuré) | Après P2 | Après P4 |
|---|---:|---:|---:|
| **Indice de cohérence** (invariants transversaux respectés / 20) | **≈ 5/20** | ≥ 15/20 | 20/20 |
| **Chaînages robustes** (épreuves D1→D8 au vert) | **0 / 62** | ≥ 50 / 62 | 62 / 62 |
| **Contrats d'effet déclarés** (types de documents documentés et testés) | **0 %** | 100 % | 100 % |
| **Écarts critiques de démonstration** (les 3 questions de §D.2) | **3 ouverts** | 1 | 0 |
| **Assertions de chaînage exécutées en CI** | **0** | ≈ 750 | ≈ 1 000 |

> Pour l'honnêteté commerciale : publier un indice qui vaut **5/20** puis **20/20** devant le client est
> un argument plus fort qu'annoncer « 20/20 » d'emblée. Le premier est une **preuve de méthode**, le
> second une affirmation — et le marché est saturé d'affirmations.

### F.3 Ce que cela change, concrètement

| Situation | Aujourd'hui | Après le programme |
|---|---|---|
| « Où est passée cette commande ? » | trois écrans à croiser à la main | **Vue Chaîne** : réponse en un clic, dans les deux sens |
| « Pourquoi ce montant ? » (auditeur) | on relit le code | lineage : chaque chiffre pointe vers ses pièces |
| « Le stock ne colle pas à la comptabilité » | on enquête | l'indice de cohérence **le voyait la veille**, avec l'écart chiffré |
| Un absent saisit une note de frais | acceptée, remboursée | refusée avec motif ; registre d'absence unique (W9) |
| Un devis accepté devient commande | à la main, sans trace | chaîne documentée, prix gelé, engagement créé (R-001, R-010) |
| Une facture annulée après lettrage | contre-passation manuelle, TVA à reprendre | extourne **et régénération de la TVA**, à la manière de Pennylane (R-019) |
| Un lot défectueux doit être rappelé | on remonte les mouvements à la main | traçabilité amont/aval par chaîne (R-007, INV-01) |
| Il faut corriger une période clôturée | refus sec | **écriture de régularisation guidée** (I-09) |
| Un client demande une règle maison | développement spécifique | **règle paramétrée** par lui (I-07) |

---

## Ce que ce document engage, et ce qu'il ne remplace pas

**Il engage six choses**, toutes vérifiables :

1. **Un inventaire chiffré de l'existant** : 62 chaînages transverses, dont 19 reliant trois modules
   ou plus, **3,65/7** de robustesse moyenne, et les quatre propriétés manquantes nommées
   (idempotence 15 %, erreur gérée 10 %, trace 11 %, refus explicite 47 %).
2. **Une méthode d'analyse reproductible** : toute action est un changement d'état ; 173 couples
   (table, colonne) et 671 valeurs ont été lus, **632 ne sont traitées par personne** — et le document
   dit lesquelles n'ont pas à l'être.
3. **62 règles manquantes nommées** (R-001 → R-062), chacune avec son effet attendu, plus **9 familles
   de chaînages internes** et **12 couples de modules vides**.
4. **Une compilation sourcée des leaders** (SAP, NetSuite, Dynamics 365 BC, ERPNext, Pennylane,
   Procore) et une matrice de comparaison honnête, les cases « non documenté » restant telles quelles.
5. **Douze innovations**, dont trois premières (Vue Chaîne, contrat d'effet, indice de cohérence) pour
   **13 jours** : c'est l'écart le plus court entre notre produit et « meilleur que les leaders » sur
   ce sujet précis.
6. **Un socle qui empêche la récidive** : le contrat de chaînage (six invariants), le trio de
   registres, vingt invariants transversaux, et la règle d'urbanisme en CI qui refuse tout nouveau
   document sans effet déclaré.

**Ce qu'il ne remplace pas** : le [plan correctif complet](PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md),
qui traite les défauts connus et dont ce document **dépend** (W0, W1, W4, W9) ; les deux audits, qui
restent les pièces de constat ; le reste-à-faire du 22/09, qui porte la planification des phases.

**Une limite, dite franchement** : les notes de robustesse de la partie A sont **statiques** — elles
lisent le code, elles n'exécutent rien. Les huit tests D1→D8 existent pour combler ce trou, et **aucun
n'est écrit aujourd'hui**. Tant qu'ils ne le sont pas, la partie A est un diagnostic, pas une preuve.

**Les trois gestes à faire avant tout le reste** :

1. **mesurer par exécution** : monter une base neuve et écrire les huit tests D1→D8 sur **trois**
   chaînages seulement — les plus transversaux (§A.2 : `generate_accounting_annex`, `run_mrp`,
   `post_pos_session_on_close`). Trois suffisent à valider la batterie elle-même ;
2. **créer le trio de registres** (E.2) et y rétro-instrumenter ces trois mêmes chaînages : si le
   gabarit E.1 tient sur ces trois-là, il tiendra sur les 62 ;
3. **publier l'indice sur une société pilote**, même à 5/20 : le chiffre de départ devient la
   démonstration de la méthode, et chaque point gagné devient un argument de vente.
















