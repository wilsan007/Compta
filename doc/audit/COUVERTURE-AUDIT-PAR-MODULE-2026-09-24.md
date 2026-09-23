# Couverture d'audit par module — 24 septembre 2026

> **Question posée** : tous les modules d'Onusuite ont-ils été minutieusement audités ?
> **Réponse courte** : **non**. Un module sur dix l'est à peu près, deux ne le sont pas du tout,
> et les 20 fonctions Edge ne le sont par rien.
>
> Ce document ne donne pas une impression : il donne des mesures, prises le 24/09 sur une base
> neuve rejouée (schéma + **206 migrations, 0 erreur**, conteneur `pg_m3_neuf`), et dit
> exactement comment chaque chiffre est obtenu, pour qu'on puisse le contester.

## 1. Comment les chiffres sont obtenus

| Mesure | Définition exacte |
|---|---|
| **Table métier** | table du schéma `public` portant une colonne `tenant_id` |
| **Porte une logique SQL** | au moins une fonction PL/pgSQL du schéma `public` exécute `INSERT INTO` ou `UPDATE` sur elle |
| **Traversée par un scénario** | son nom apparaît dans au moins un fichier `app/sql/*_tests.sql` |
| **Module** | ventilation par motif sur le nom de la table, à partir des 11 modules déclarés dans `useTenantModules.ts` |

Deux avertissements d'honnêteté :

- La ventilation par module est faite **au nom de la table**. Elle est relisible mais approximative :
  `stock_movements` est compté dans « stock » alors que la production et les ventes l'alimentent aussi.
- « Traversée par un scénario » ne veut pas dire « correcte ». Cela veut dire qu'un scénario a
  regardé cette table. C'est le minimum, pas la preuve.
- Le semeur générique de `105_rls_tests.sql` n'entre pas dans le compte : il alimente les 340 tables
  par `EXECUTE format(...)`, ce qui prouve l'**isolation**, pas le comportement métier.

## 2. Le tableau

| Module | Tables métier | Portent une logique SQL | Logique traversée | Couverture de la logique |
|---|---:|---:|---:|---:|
| Production | 18 | 1 | 1 | **100 %** |
| Commercial | 52 | 10 | 8 | **80 %** |
| Stock | 47 | 8 | 6 | **75 %** |
| Comptabilité | 73 | 19 | 14 | **73 %** |
| Gestion de projet | 19 | 5 | 3 | **60 %** |
| Trésorerie | 30 | 4 | 2 | **50 %** |
| Ressources humaines | 52 | 10 | 5 | **50 %** |
| Système | 43 | 9 | 4 | **44 %** |
| Tableaux de bord | 4 | 1 | 0 | **0 %** |
| Reporting | 3 | 0 | 0 | *aucune logique SQL* |
| **Total** | **341** | **67** | **43** | **64 %** |

**Sur les 341 tables métier, 80 sont traversées par un scénario — 23 %.**

### Ce que le tableau ne dit pas tout seul

- **Le 100 % de la production est un artefact.** Le module ne compte qu'**une** table portant
  une logique SQL (`manufacturing_orders`). Tout le reste de son effet passe par `stock_movements`,
  compté dans « stock ». Un module peut être petit en tables et lourd en conséquences : c'est
  précisément le cas trouvé le 24/09 (rebuts ignorés, reclôture doublant le stock).
- **245 tables sur 341 n'ont ni logique SQL ni scénario.** Elles ne sont écrites que depuis
  l'écran, quand elles le sont. C'est le motif `SQL-01` du registre — la migration 127 a créé
  27 tables sans une fonction ni un trigger — reproduit à l'échelle du schéma.
- **41 tables ne sont référencées ni en SQL ni dans `src/`.** Ce sont des coquilles vides.

## 3. Logique métier écrite mais jamais traversée par un scénario

Ce sont les 24 endroits où du code s'exécute en production sans qu'aucun scénario chiffré
ne soit jamais passé dessus. Par ordre de gravité perçue :

| Table | Module | Pourquoi cela compte |
|---|---|---|
| `vat_returns` | Comptabilité | La déclaration de TVA. Rien ne vérifie la CA3 produite. (M-10) |
| `payroll_accounting_entries` | RH | Le pont paie → comptabilité, par une table à part. |
| `payroll_cumulative` | RH | Les cumuls : une erreur s'y propage sur toute l'année. |
| `lettrage_differences` | Comptabilité | Les écarts de lettrage, alors que le lettrage lui-même est testé (175). |
| `journal_posting_sequences` | Comptabilité | La numérotation des pièces, cœur de la valeur probante. |
| `dsn_declarations` | RH | DSN française. (M-12) |
| `leave_balances` | RH | Soldes de congés. |
| `pay_recalls`, `pay_slip_clarified`, `cpf_accounts` | RH | Rappels, bulletin clarifié, CPF. |
| `stock_valuation_layers`, `stock_quantities` | Stock | Couches de valorisation — traversées en lecture par 173, jamais écrites par un scénario. |
| `landed_costs`, `landed_cost_lines` | Trésorerie / Stock | Coûts annexes d'achat, qui entrent dans le prix de revient. |
| `bank_reconciliation_suggestions` | Trésorerie | Suggestions de rapprochement. |
| `stock_alerts` | Stock | Alertes de seuil. |
| `webhook_delivery_logs`, `webhook_delivery_queue` | Commercial | File de webhooks — déjà signalée en mémoire par `ASY-01`. |
| `project_activity_log`, `project_milestones` | Gestion de projet | Journal d'activité et jalons. |
| `api_keys`, `user_totp` | Système | Clés d'API et second facteur. **Aucun scénario sur l'authentification forte.** |
| `carry_forward_log`, `module_documents`, `tracking_warnings` | Système | Reports, documents, avertissements. |
| `chart_pack_switch_log` | Tableaux de bord | Seule logique du module, jamais traversée. |

## 4. Les 20 fonctions Edge : zéro test

Aucun test — unitaire, SQL ou e2e — ne référence une fonction Edge par son nom, et aucun
test n'importe de code depuis `app/supabase/functions/`.

```
ai-import-mapping      auth-signup            create-user            cron-payment-reminders
generate-pdf           handle-stripe-webhook  ocr-invoice-import     outgoing-webhooks
parse-bank-statement   public-api             refresh-exchange-rates request-signature
send-notification-email submit-e-invoice      submit-vat-return      sync-bank-transactions
transmit-dsn           validate-vat-vies      verify-iban            verify-siret
```

Nuance : le **côté SQL** de certaines est couvert — l'inscription par `182`, la garde SSRF par
`168`. Mais le code Deno lui-même, ses entrées, ses erreurs et ses effets, ne l'est nulle part.
Ce sont pourtant les points d'entrée exposés au réseau.

## 5. Où en sont les 20 modules de la phase 3

Rappel : [le reste-à-faire](RESTE-A-FAIRE-2026-09-22.md) § 6 liste 20 modules « jamais audités
par exécution », chiffrés ≈ 12 j.

| État | Modules |
|---|---|
| ✅ **Audité par exécution** (24/09) | M-06 livraisons, M-08 production, M-17 temps projet |
| 🔄 **En cours, session parallèle** | M-07 réceptions et achats → stock (11 défauts S-01 à S-11) |
| ❌ **Jamais audité** | M-01 multi-devises, M-02 immobilisations, M-03 analytique, M-04 budgets, M-05 notes de frais, M-09 lots et séries, **M-10 TVA**, M-11 FEC, M-12 DSN, M-13 facturation électronique, M-14 relances, M-15 Stripe, M-16 synchronisation bancaire, M-18 utilisateurs et invitations, M-19 import Sage, M-20 miroir |

**16 des 20 modules n'ont jamais vu un scénario chiffré.**

## 6. Ce que l'échantillon de trois modules apprend sur les seize restants

Les trois modules audités le 24/09 ont rendu **six défauts**, dont un bloquant sur toutes les
données et un de sécurité. Rapporté aux seize modules restants, à taux constant, cela ferait
une trentaine de défauts à trouver — dont il faut s'attendre à ce que plusieurs soient
bloquants, puisque **rien ne les aurait empêchés d'exister**.

Trois motifs se répètent et méritent d'être cherchés en premier partout ailleurs :

1. **Les chemins d'annulation.** Les trois défauts d'idempotence viennent du même endroit : un
   statut `cancelled` permis par la contrainte CHECK, qu'aucun déclencheur ne traite. À vérifier
   sur `goods_receipts`, `purchase_orders`, `pay_runs`, `vat_returns`.
2. **Les colonnes présentes que personne ne lit.** `qty_scrapped` existait et ne servait à rien.
   Le même contrôle vaut pour `reserved_quantity`, `invoiced_quantity`, `qty_produced`.
3. **Les fonctions `SECURITY DEFINER` qui lisent sans filtre de société.** Trouvé sur les temps
   projet après la 227 : le contrôle `check_tenant_guard` ne regarde que les fonctions *exposées
   à `authenticated` et prenant un uuid*. Un déclencheur n'entre pas dans ce périmètre.

## 7. Garde-fou ajouté le 24/09

`app/sql/ci/check_status_writes.sql` — refuse une valeur littérale écrite dans une colonne que la
contrainte CHECK n'admet pas. Écrit après le défaut bloquant de la 230, que
`check_trigger_reachability` ne pouvait pas voir : il décide des **comparaisons**, pas des
**affectations**.

Périmètre mesuré : 265 fonctions PL/pgSQL, 215 couples (table, colonne) énumérés, **82 écritures
décidées**, 129 indécidables, 71 INSERT écartés (valeurs imbriquées) — l'angle mort est affiché
plutôt que tu.

> **Le contrôle a d'abord été faussement vert, et son auto-test aussi.** En ARE PostgreSQL, la
> gourmandise d'une expression est fixée par son *premier* quantificateur : un `(.*?);` avalait
> jusqu'au **dernier** point-virgule de la fonction, absorbant tous les `UPDATE` suivants. La
> fixture d'auto-test plaçait l'écriture fautive en **première** position et passait donc au vert
> avec un contrôle cassé. Corrigé par une classe de caractères (`[^;]*`), qui ne dépend d'aucune
> préférence de match, et par une fixture où l'écriture fautive vient **en dernier**.
> Vérifié en réinstallant la version fautive de `release_stock_on_delivery` : le contrôle la
> signale, et redevient vert une fois la 230 réappliquée.
