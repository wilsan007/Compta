# Cahier des charges correctif — Onusuite

> **Version** 1.0 — 12 septembre 2026
> **Branche** `commercial-hr-paie`
> **Objet** registre unique de tous les défauts constatés, et spécification de correction pour chacun
> **Sources fusionnées** revue Claude volets 1 à 3, audit Gemini « qualité requêtes/triggers/workflows », audit Gemini « failles masquées », audit par exécution réelle sur PostgreSQL 16.14, et passage d'outillage (`plpgsql_check`, `knip`, `deno check`, `madge`, `npm audit`, détecteur front↔schéma)

---

## Sommaire

- [1. Synthèse](#1-synthèse)
- [2. Registre maître](#2-registre-maître)
- [3. LOT 0 — Infrastructure](#3-lot-0--infrastructure)
- [4. LOT 1 — Contradictions de schéma](#4-lot-1--contradictions-de-schéma)
- [5. LOT 2 — Triggers cassés](#5-lot-2--triggers-cassés)
- [6. LOT 3 — Fonctions RPC cassées](#6-lot-3--fonctions-rpc-cassées)
- [7. LOT 4 — Logique métier fausse](#7-lot-4--logique-métier-fausse)
- [8. LOT 5 — Sécurité, conformité, asynchrone](#8-lot-5--sécurité-conformité-asynchrone)
- [9. LOT 6 — Garde-fous](#9-lot-6--garde-fous)
- [10. LOT 7 — Dette et périmètre](#10-lot-7--dette-et-périmètre)
- [11. Plan d'exécution](#11-plan-dexécution)
- [12. Critères de recette](#12-critères-de-recette)

---

## 1. Synthèse

### 1.1 Ce que contient ce document

**87 défauts** constatés et reproduits, chacun avec sa preuve, sa spécification de correction et son critère de recette. Aucun n'est théorique : tous ont été vérifiés contre le code ou contre une base PostgreSQL 16.14 réelle le 12 septembre 2026.

| Lot | Objet | Défauts | Effort |
|---|---|---:|---:|
| **LOT 0** | Infrastructure — rien ne se déploie | 4 | 1 j |
| **LOT 1** | Contradictions de schéma | 7 | 2 j |
| **LOT 2** | Triggers cassés | 20 | 4 j |
| **LOT 3** | Fonctions RPC cassées | 31 | 5 j |
| **LOT 4** | Logique métier fausse | 14 | 3 sem. |
| **LOT 5** | Sécurité, conformité, asynchrone | 6 | 1 sem. |
| **LOT 6** | Garde-fous | 5 | 3 j |
| **LOT 7** | Dette et périmètre | — | voir plan de perfection |

### 1.2 État réel de l'application

| Axe | Note | Constat dominant |
|---|---:|---|
| Chaîne de livraison | **0** | `npm run build` échoue — rien ne peut être déployé |
| Moteur comptable | **2,5** | aucune facture ne se comptabilise, jamais |
| Banque | **2,0** | toute insertion de transaction bancaire échoue |
| Point de vente | **2,0** | la clôture de caisse échoue à deux endroits |
| Production | **3,0** | `run_mrp` et le calcul de coût sont cassés |
| Paie | **4,0** | quatre fonctions RH cassées, DSN inatteignable |
| Qualité & tests | **3,0** | les deux fichiers de test SQL échouent |
| Sécurité multi-tenant | **8,5** | vérifié à l'exécution — tient, aucune fuite |
| Couverture fonctionnelle | **8,5** | 365 tables, 392 triggers, 224 pages |
| **Note globale** | **≈ 4,2** | |

### 1.3 Les quatre causes racines

Tous les défauts de ce registre se rattachent à quatre causes. Les traiter est plus rentable que de traiter les symptômes un par un.

**C1 — Aucune validation à l'écriture.** PostgreSQL ne résout les identifiants d'un corps PL/pgSQL qu'à l'exécution. 51 fonctions référencent des colonnes inexistantes et se sont installées sans une erreur. → **LOT 6, garde-fou G1.**

**C2 — Le schéma et le code ont divergé.** Trois paires de colonnes concurrentes, six triggers guettant un statut interdit, neuf colonnes fantômes côté front. → **LOT 1 et garde-fous G2, G3.**

**C3 — Ce qui est écrit n'est pas branché.** 250 exports jamais importés, 41 enveloppes RPC sans appelant, 22 tables créées sans consommateur. → **garde-fou G4.**

**C4 — Les tests ne s'exécutent pas.** Les deux fichiers de test SQL échouent au chargement ; les 1 240 tests Vitest mockent la base. → **LOT 6, garde-fou G5.**

### 1.4 Méthode de vérification

| Outil | Défauts remontés |
|---|---:|
| Exécution de scénarios métier sur PostgreSQL 16.14 | 6 |
| `plpgsql_check` | 51 |
| Rejeu des 132 migrations | 4 |
| Croisement conditions de trigger ↔ contraintes `CHECK` | 6 |
| Détecteur front↔schéma | 9 |
| `knip` | ~250 (agrégés en 1 défaut) |
| Lecture croisée des 4 rapports antérieurs | 11 |

Tous reproductibles par la procédure de l'[annexe du rapport d'exécution](AUDIT-EXECUTION-REELLE.md#annexe--reproduire-cet-audit).

---

## 2. Registre maître

### Convention

`LOT-nn` — identifiant stable. **Source** : `C1/2/3` = Claude volets 1/2/3, `Cx` = Claude exécution, `G1` = Gemini requêtes/triggers, `G2` = Gemini failles masquées, `O` = outillage.

| Réf | Défaut | Src | Sév. | Localisation |
|---|---|:---:|:---:|---|
| **LOT0-01** | Migrations triées alphabétiquement — 10 fonctions écrasées | C3 | 🔴 | `run-sql-migrations.mjs:88` |
| **LOT0-02** | Build de production cassé | C3 | 🔴 | `vite.config.ts:11` |
| **LOT0-03** | `102_trigger_tests.sql` échoue au chargement | Cx | 🔴 | `102:576` |
| **LOT0-04** | `105_rls_tests.sql` — 9 erreurs | Cx | 🔴 | `105:40,63,136` |
| **LOT1-01** | `invoices.status` vs `validation_status` — 6 triggers morts | Cx | 🔴 | `00_schema_dump:5579` |
| **LOT1-02** | `stock_movements.type` vs `movement_type` — vocabulaires divergents | Cx | 🔴 | `00_schema_dump:5666` |
| **LOT1-03** | `stock_quantities.reserved_quantity` vs `quantity_reserved` | Cx | 🟠 | `schema:4013` / `118:9` |
| **LOT1-04** | `delivery_notes` : `'shipped'` interdit, proposé à l'écran | Cx | 🟠 | `DeliveryNotesPage.tsx:13` |
| **LOT1-05** | `pay_runs` : statuts `'closed'`/`'processing'` absents | Cx | 🟠 | `pg_constraint` |
| **LOT1-06** | 9 colonnes fantômes référencées côté front | O | 🟠 | 9 fichiers `src/` |
| **LOT1-07** | `68_module_documents_storage_rls.sql` — 30 erreurs, RLS jamais posée | Cx | 🟠 | `68:38-141` |
| **LOT2-01** → **LOT2-20** | 20 triggers référençant des colonnes inexistantes | Cx/G2 | 🔴 | voir §5 |
| **LOT3-01** → **LOT3-31** | 31 fonctions RPC cassées, dont 21 appelées par le front | Cx | 🔴 | voir §6 |
| **LOT4-01** | Report à nouveau des classes 6 et 7 | G1 | 🔴 | `accounting.ts:3071` |
| **LOT4-02** | `calculate_payslip` — formule 22 %/42 % en dur | G2 | 🔴 | `89:32,39` |
| **LOT4-03** | CUMP initialisé à 0 à la première entrée | G2 | 🔴 | `101:46` |
| **LOT4-04** | Mouvements de stock non idempotents | G1 | 🔴 | `90:290` |
| **LOT4-05** | Double entrée réception + contrôle qualité | G1 | 🔴 | `81:255` / `90:303` |
| **LOT4-06** | Réservations appliquées à tous les dépôts | G1 | 🔴 | `118:106` |
| **LOT4-07** | Éclatement MRP récursif mort-né | G2 | 🟠 | `115:50` |
| **LOT4-08** | Lettrage bloqué à A999 | G1 | 🟠 | `accounting.ts:1074` |
| **LOT4-09** | Lettrage sans contrôle d'équilibre | G1 | 🟠 | `accounting.ts:1046` |
| **LOT4-10** | Numérotation par horodatage | G1 | 🟠 | `accounting.ts:3019,3098` |
| **LOT4-11** | Documents composés non atomiques | G1 | 🟠 | `sales.ts:106` |
| **LOT4-12** | Rapprochement 3 voies en `LIMIT 1` | G1 | 🟠 | `86:174,198` |
| **LOT4-13** | Variables d'écart non réinitialisées | G1 | 🟠 | `86:123` |
| **LOT4-14** | Traçabilité lot bloquante (latente) | G1 | 🟠 | `118:198` |
| **LOT5-01** | Vérification de chaîne NF-525 inopérante | G1 | 🔴 | `91:325` |
| **LOT5-02** | Course d'écriture sur la chaîne NF-525 | G1 | 🟠 | `91:113` |
| **LOT5-03** | Séparation des tâches non désactivable | G2 | 🟠 | `120:48` |
| **LOT5-04** | File de webhooks en mémoire | G1 | 🟡 | `outgoing-webhooks:18` |
| **LOT5-05** | Aucun filtrage SSRF sur les webhooks | G1 | 🟡 | `outgoing-webhooks` |
| **LOT5-06** | 3 vulnérabilités npm modérées | O | 🟡 | `vitest`, `@vitest/*` |
| **LOT6-01** → **LOT6-05** | Garde-fous CI | — | 🔴 | voir §9 |
| **LOT7-01** | ~250 exports jamais importés | O | 🟡 | `src/` |
| **LOT7-02** | Migration 127 — 27 tables, 0 fonction | C3 | 🟡 | `127` |
| **LOT7-03** | 303 requêtes non bornées | C1/G1 | 🟠 | `queries/*.ts` |
| **LOT7-04** | 1 991 `any` malgré le mode strict | C3 | 🟡 | `src/` |
| **LOT7-05** | Deux jeux de triggers d'équilibre actifs | C3 | 🟠 | `76:105` / `128:57` |
| **LOT7-06** | `_skip_cascade` jamais lu | G1 | 🟡 | `85:78` |
| **LOT7-07** | Accessibilité non traitée | C1 | 🟡 | `src/` |
| **LOT7-08** | 4 edge functions en « mode simulation » | C1/C2 | 🟠 | `supabase/functions/` |

**Défaut clos pendant la période d'audit** — fuite multi-tenant de l'API publique (Gemini G1 §4.3), corrigée le 12/09 à 02:29. Ne pas retraiter. Vérifier seulement qu'elle survit au déploiement une fois `LOT0-02` réglé.

---

## 3. LOT 0 — Infrastructure

> **Aucun correctif de ce cahier des charges ne produit d'effet en production tant que ce lot n'est pas soldé.**

---

### `LOT0-01` — Trier les migrations par numéro

**Constat.** `run-sql-migrations.mjs:88` applique un `.sort()` sur les noms de fichiers. Tri de chaînes : les migrations `100_` à `130_` s'exécutent aux positions 5 à 42, avant `12_` à `99_`. Dix fonctions et un trigger sont silencieusement ramenés à leur version d'avant le correctif.

| Fonction | Corrigée par | Écrasée par | Chantier annulé |
|---|---|---|---|
| `create_journal_on_invoice_validate` | 108, 109, 110 | 95 | comptes auxiliaires, TVA multi-taux, comptes par article |
| `create_journal_on_purchase_invoice_validate` | 108, 109, 110 | 95 | idem, flux achat |
| `create_journal_on_customer_payment` | 108 | 95 | comptes auxiliaires |
| `create_journal_on_supplier_payment` | 108 | 95 | comptes auxiliaires |
| `create_stock_on_manufacturing_complete` | 112 | 81 | coût de revient d'OF |
| `close_fiscal_year` | 107 | 89 | clôture d'exercice |
| `increment_stock`, `decrement_stock`, `update_stock_on_movement` | 101 | 76 | fonctions de stock |
| `calculate_payslip` | *(jamais réécrite)* | 89 | voir `LOT4-02` |
| trigger d'équilibre | 128 | 76 | `FOR EACH STATEMENT` |

**Spécification.**

```js
// run-sql-migrations.mjs:88
- .sort();
+ .sort((a, b) => {
+     const na = parseInt(a.match(/^(\d+)/)[1], 10);
+     const nb = parseInt(b.match(/^(\d+)/)[1], 10);
+     return na - nb || a.localeCompare(b);
+   });
```

**Recette.**
```sql
SELECT pg_get_functiondef('create_journal_on_invoice_validate'::regproc) LIKE '%account_tiers%';  -- true
SELECT pg_get_functiondef('create_stock_on_manufacturing_complete'::regproc) LIKE '%unit_cost%';  -- true
SELECT count(*) FROM pg_trigger WHERE tgrelid='journal_lines'::regclass AND NOT tgisinternal;     -- 5, pas 6
```

**Effort.** 15 min + 2 h de rejeu vérifié.

---

### `LOT0-02` — Réparer le build

**Constat.** `tsc -b` compile les trois projets référencés. `tsconfig.app.json` passe à zéro erreur, mais `tsconfig.node.json` en remonte quatre :

```
vite.config.ts(11,5): error TS2769: No overload matches this call.
    Type '""' is not assignable to type 'PluginOption'.
```

Cause : `process.env.ANALYZE && visualizer({…})` vaut la chaîne vide quand la variable n'est pas définie. Sans mode strict le type était élargi.

**Conséquence.** Les jobs `lint-typecheck` et `build` échouent. Le job de synthèse exige les cinq jobs en succès, et `deploy.yml` se déclenche sur `conclusion == 'success'`. **Rien ne se déploie.**

**Spécification.**

```ts
// vite.config.ts:11
- process.env.ANALYZE && visualizer({ filename: 'dist/stats.html', … }),
+ ...(process.env.ANALYZE
+     ? [visualizer({ filename: 'dist/stats.html', template: 'treemap', gzipSize: true, brotliSize: false })]
+     : []),
```

Traiter les trois autres erreurs du même projet à l'identique. Ajouter `npm run build` au crochet de pré-envoi.

**Recette.** `npm run build` sort en code 0 ; la CI passe au vert sur les cinq jobs.

**Effort.** 30 min.

---

### `LOT0-03` — Réparer les tests de triggers

**Constat.** `102_trigger_tests.sql` s'arrête ligne 576 :

```
ERROR: ❌ ÉCHEC DES TESTS: column "created_at" of relation "users" does not exist
```

Le job CI `db-integration` ne peut pas passer. Soit la CI est rouge depuis sa mise en place, soit elle n'a jamais tourné sur ce chemin.

**Spécification.**
1. Retirer `created_at` de la fixture d'insertion dans `users`.
2. Ajouter les trois assertions qui manquaient et qui auraient détecté `LOT0-01` :

```sql
-- TEST 15 : le compte auxiliaire est renseigné
IF (SELECT jl.account_tiers FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id
    WHERE je.invoice_ref = v_inv_number AND jl.account_general LIKE '411%') IS NULL THEN
  RAISE EXCEPTION 'TEST 15 : compte auxiliaire non renseigné — migration 108 écrasée ?';
END IF;

-- TEST 16 : autant de lignes de TVA que de taux sur la facture
IF (SELECT count(DISTINCT vat_code) FROM invoice_lines WHERE invoice_id = v_inv_id)
   <> (SELECT count(*) FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
       WHERE je.invoice_ref = v_inv_number AND jl.account_general LIKE '4457%') THEN
  RAISE EXCEPTION 'TEST 16 : TVA non ventilée par taux';
END IF;

-- TEST 17 : la production porte un coût unitaire
IF (SELECT unit_cost FROM stock_movements
    WHERE reference_type='manufacturing_order' AND movement_type='in'
    ORDER BY created_at DESC LIMIT 1) IS NULL THEN
  RAISE EXCEPTION 'TEST 17 : produit fini sans coût — migration 112 écrasée ?';
END IF;
```

**Recette.** `psql -v ON_ERROR_STOP=1 -f 102_trigger_tests.sql` sort en code 0, et la suppression volontaire de `LOT0-01` le fait échouer.

**Effort.** 3 h.

---

### `LOT0-04` — Réparer les tests RLS

**Constat.** `105_rls_tests.sql` produit 9 erreurs : colonnes inexistantes dans les fixtures (`customers.number`, `products.code`) et `set_config('request.headers', …)` alimenté avec un JSON invalide.

**Spécification.** Corriger les fixtures, puis **rendre le test générique** — l'énumération de 4 tables sur 530 n'a pas de valeur :

```sql
DO $$
DECLARE r RECORD; v_count int; v_leaks int := 0;
BEGIN
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', v_tenant_a::text)::text, true);

  FOR r IN
    SELECT c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relkind = 'r' AND c.relrowsecurity
      AND EXISTS (SELECT 1 FROM information_schema.columns col
                  WHERE col.table_schema='public' AND col.table_name=c.relname
                    AND col.column_name='tenant_id')
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE tenant_id = $1', r.t)
      INTO v_count USING v_tenant_b;
    IF v_count > 0 THEN
      RAISE WARNING 'FUITE RLS sur % : % lignes du tenant B', r.t, v_count;
      v_leaks := v_leaks + 1;
    END IF;
  END LOOP;

  IF v_leaks > 0 THEN RAISE EXCEPTION '% table(s) en fuite', v_leaks; END IF;
END $$;
```

50 lignes couvrent les 356 tables portant `tenant_id`, et toute table future est couverte à sa création.

**Recette.** Le test passe ; retirer volontairement une politique le fait échouer.

**Effort.** 1 j.

---

## 4. LOT 1 — Contradictions de schéma

---

### `LOT1-01` — `invoices.status` vs `validation_status` : six triggers morts

**Le défaut le plus grave de tout ce registre.**

**Constat.** La contrainte `invoices_status_check` n'admet que `draft, sent, viewed, paid, overdue, cancelled`. Le trigger `create_journal_on_invoice_validate` se déclenche sur `NEW.status IN ('validated','posted')` — **deux valeurs que la base refuse**. Le front ne les pose d'ailleurs jamais : il ne pose que `'draft'` et `'sent'`.

Une colonne `validation_status` existe avec les valeurs `draft / validated / transformed` — **mais aucun trigger ne la surveille**.

Six triggers sont concernés :

| Trigger | Table | Statut attendu | Statuts autorisés |
|---|---|---|---|
| `create_journal_on_invoice_validate` | `invoices` | `validated` | draft, sent, viewed, paid, overdue, cancelled |
| `create_journal_on_purchase_invoice_validate` | `purchase_invoices` | `validated` | idem |
| `create_stock_out_on_delivery` | `delivery_notes` | `shipped` | pending, delivered, returned, cancelled |
| `generate_dsn_on_payrun_close` | `pay_runs` | `closed` | *(absent)* |
| `integrate_pay_recalls_on_payrun` | `pay_runs` | `processing` | *(absent)* |
| `integrate_salary_advances_on_payrun` | `pay_runs` | `processing` | *(absent)* |

**Conséquence.** Aucune facture de vente ni d'achat ne génère d'écriture. Ni DSN, ni intégration des rappels ou des acomptes. Toutes les analyses des rapports antérieurs sur les comptes auxiliaires ou la ventilation de TVA portaient sur du code qui ne s'exécute jamais.

**Spécification — option retenue : surveiller la bonne colonne.**

```sql
-- ventes
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_entry_id uuid; v_number text; v_existing uuid;
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
    ...
```

Même changement pour les achats. Pour `delivery_notes` et `pay_runs`, élargir la contrainte :

```sql
ALTER TABLE delivery_notes DROP CONSTRAINT IF EXISTS delivery_notes_status_check;
ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_status_check
  CHECK (status = ANY (ARRAY['pending','shipped','delivered','returned','cancelled']));

ALTER TABLE pay_runs DROP CONSTRAINT IF EXISTS pay_runs_status_check;
ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_status_check
  CHECK (status = ANY (ARRAY['draft','processing','approved','closed','cancelled']));
```

**Ordre impératif.** Élargir la contrainte de `delivery_notes` **après** `LOT4-04` (idempotence), sinon on réactive la double sortie de stock.

**Côté interface.** Ajouter le bouton « Valider » qui pose `validation_status = 'validated'` — il n'existe pas aujourd'hui.

**Recette.**
```sql
UPDATE invoices SET validation_status='validated' WHERE id = :id;
SELECT count(*) FROM journal_entries WHERE invoice_ref = :num AND journal_code='VT';  -- = 1
```

**Effort.** 4 h côté base, 1 j côté interface.

---

### `LOT1-02` — `stock_movements` : deux colonnes de type, deux vocabulaires

**Constat.**

```sql
type          CHECK IN ('in','out','adjustment')
movement_type CHECK IN ('in','out','transfer','adjustment','initial')
```

Insérer un mouvement `movement_type='initial'` avec `type='initial'` échoue sur la contrainte de `type`. C'est exactement ce que fait le code de reprise de stock.

**Spécification.**

```sql
-- 1. aligner immédiatement
ALTER TABLE stock_movements DROP CONSTRAINT IF EXISTS stock_movements_type_check;
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_type_check
  CHECK (type = ANY (ARRAY['in','out','transfer','adjustment','initial']));

-- 2. synchroniser les valeurs existantes
UPDATE stock_movements SET type = movement_type WHERE type IS DISTINCT FROM movement_type;

-- 3. empêcher la divergence future
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_type_coherence
  CHECK (type = movement_type);

-- 4. planifier la suppression de `type` (doublon historique)
```

**Recette.** L'insertion d'un mouvement `'initial'` réussit et alimente la valorisation.

**Effort.** 2 h.

---

### `LOT1-03` — Deux colonnes de réservation

**Constat.** `stock_quantities` porte `reserved_quantity` (schéma d'origine) et `quantity_reserved` (migration 118). Le front lit la première (9 références), les triggers écrivent la seconde (9 références). **L'interface affichera toujours zéro réservation**, même une fois `LOT4-06` corrigé.

**Spécification.**

```sql
UPDATE stock_quantities
SET reserved_quantity = COALESCE(quantity_reserved, 0)
WHERE COALESCE(quantity_reserved, 0) <> 0;

ALTER TABLE stock_quantities DROP COLUMN IF EXISTS quantity_reserved;
```

Puis corriger les 9 occurrences SQL pour écrire dans `reserved_quantity`.

**Recette.** Confirmer une commande, puis vérifier que l'écran de stock affiche la quantité réservée.

**Effort.** 2 h.

---

### `LOT1-04` — Statut `'shipped'` proposé mais refusé

**Constat.** `DeliveryNotesPage.tsx:13` offre cinq statuts ; la contrainte n'en admet que quatre. Sélectionner « expédié » lève une violation de contrainte, dont le message brut remonte à l'utilisateur.

**Spécification.** Traité avec `LOT1-01` — élargir la contrainte, **après** `LOT4-04`.

**Effort.** inclus.

---

### `LOT1-05` — `pay_runs` : statuts manquants

Traité avec `LOT1-01`.

---

### `LOT1-06` — Neuf colonnes fantômes côté front

**Constat.** Détecteur front↔schéma : neuf requêtes filtrent sur des colonnes qui n'existent pas. Elles échouent silencieusement à l'exécution (PostgREST retourne une erreur que le code avale souvent dans un `catch`).

| Référence | Fichier | Colonne réelle |
|---|---|---|
| `bank_transactions.transaction_date` | `misc.ts` | `date` |
| `delivery_notes.date` | `customerAdvanced.ts` | `delivery_date` |
| `employees.auth_user_id` | `dematRh.ts` | *(à créer ou joindre via `tenant_users`)* |
| `fiscal_periods.line_date` | `misc.ts` | *(à déterminer)* |
| `invoices.issue_date` | `stock.ts` | `date` |
| `nf525_event_log.sequence_number` | `Nf525AuditPage.tsx` | `id` |
| `payroll_tax_grids.active` | `payroll.ts` | *(à vérifier)* |
| `sales_orders.date` | `customerAdvanced.ts` | `order_date` |
| `tenant_users.user_id` | `analyticDistribution.ts` | `auth_id` |

**Spécification.** Corriger les neuf, puis poser le garde-fou `LOT6-02` — les types générés rendent cette classe impossible.

**Effort.** 4 h.

---

### `LOT1-07` — Politiques RLS du stockage documentaire jamais créées

**Constat.** `68_module_documents_storage_rls.sql` produit 30 erreurs au chargement :

```
ERROR: function has_module_access(text) does not exist
ERROR: function current_tenant_user_id() does not exist
```

Ces deux fonctions ne sont définies nulle part. Les huit politiques du fichier ne sont jamais créées.

**Impact.** Ce n'est pas une fuite — sans politique et avec RLS activée, PostgreSQL refuse tout (`fail-closed`). Mais la fonctionnalité est morte : personne ne peut lire ses documents par cette voie.

**Spécification.** Deux options :

```sql
-- Option A : créer les fonctions manquantes
CREATE OR REPLACE FUNCTION current_tenant_user_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM tenant_users
  WHERE auth_id = auth.uid() AND tenant_id = current_tenant_id() AND status = 'active'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION has_module_access(p_module text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_module = ANY (
    SELECT jsonb_array_elements_text(enabled_modules)
    FROM tenants WHERE id = current_tenant_id()
  );
$$;

-- Option B : réécrire les 8 politiques sur current_tenant_id(), qui existe
```

**Recette.** Le rejeu de la migration 68 ne produit aucune erreur, et `pg_policies` compte 8 politiques sur `module_documents`.

**Effort.** 4 h.

---

## 5. LOT 2 — Triggers cassés

Détectés par `plpgsql_check`. Chaque ligne est une référence que PostgreSQL ne peut pas résoudre à l'exécution.

### Table de correspondance des correctifs

| Réf | Trigger | Erreur | Correctif |
|---|---|---|---|
| **LOT2-01** | `create_journal_on_invoice_validate` | `il.subtotal` inexistant | → `il.total` |
| **LOT2-02** | `create_journal_on_purchase_invoice_validate` | `pil.subtotal` inexistant | → `pil.total` |
| **LOT2-03** | `create_journal_on_customer_payment` | `NEW.invoice_number` | → jointure sur `NEW.invoice_id` |
| **LOT2-04** | `create_journal_on_supplier_payment` | `NEW.invoice_number` | → jointure sur `NEW.purchase_invoice_id` |
| **LOT2-05** | `check_journal_entry_balance_stmt` (×3) | `relation "new_table"` | → `REFERENCING NEW TABLE AS new_table` |
| **LOT2-06** | `propagate_analytic_section` | `NEW.reference_type` | → lire depuis `journal_entries` |
| **LOT2-07** | `nf525_log_invoice_modify` | `invoices ->> text` | → `to_jsonb(NEW) ->> '…'` |
| **LOT2-08** | `auto_reconcile_by_score` | `NEW.label` | → `NEW.description` |
| **LOT2-09** | `apply_bank_reconciliation_rules` | `NEW.label` | → `NEW.description` |
| **LOT2-10** | `notify_bank_reconciliation_needed` | `NEW.currency` | → `NEW.original_currency` |
| **LOT2-11** | `post_pos_session_on_close` | `tl.subtotal` | → `tl.line_total` |
| **LOT2-12** | `post_pos_session_on_close_multi` | `entry_date` | → `date` |
| **LOT2-13** | `post_pos_session_on_close_multi` | `NEW.session_number` | → `NEW.id::text` |
| **LOT2-14** | `assign_pos_ticket_number_and_hash` | `nf525_event_log.reference_id` | → `entity_id` |
| **LOT2-15** | `check_customer_credit_limit` | `NEW.credit_warning` | → `UPDATE customers SET credit_warning` |
| **LOT2-16** | `reserve_stock_on_sales_order_confirm` | `v_line.warehouse_id` | → voir `LOT4-06` |
| **LOT2-17** | `update_po_status_on_receipt` | `quantity_received` | → qualifier `grl.quantity_received` |
| **LOT2-18** | `calculate_lateness_on_timesheet` | `v_emp` non typé | → `DECLARE v_emp employees%ROWTYPE` |
| **LOT2-19** | `deduct_lateness_on_timesheet_approval` | idem | idem |
| **LOT2-20** | `deduct_unpaid_absence_on_timesheet_approval` | idem | idem |
| **LOT2-21** | `sync_cpf_on_transaction` | `ON CONFLICT` sans contrainte | → créer l'index unique |

### Les quatre plus graves, en détail

---

#### `LOT2-05` — L'invariant d'équilibre ne fonctionne pas

**Constat.** La migration 128 réécrit le contrôle débit/crédit en `FOR EACH STATEMENT` avec une table de transition `new_table`, **sans la déclarer**. Le contrôle lève une erreur au lieu de vérifier.

L'équilibre n'est aujourd'hui garanti que **par accident** : l'ancien trigger `FOR EACH ROW` de la migration 76 subsiste à cause de `LOT0-01`. Corriger `LOT0-01` sans corriger celui-ci **supprimerait la garantie d'équilibre comptable**.

**Spécification.**

```sql
DROP TRIGGER IF EXISTS check_journal_entry_balance_ins ON journal_lines;
CREATE TRIGGER check_journal_entry_balance_ins
  AFTER INSERT ON journal_lines
  REFERENCING NEW TABLE AS new_table          -- ← manquant
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();

DROP TRIGGER IF EXISTS check_journal_entry_balance_upd ON journal_lines;
CREATE TRIGGER check_journal_entry_balance_upd
  AFTER UPDATE ON journal_lines
  REFERENCING NEW TABLE AS new_table OLD TABLE AS old_table
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();

DROP TRIGGER IF EXISTS check_journal_entry_balance_del ON journal_lines;
CREATE TRIGGER check_journal_entry_balance_del
  AFTER DELETE ON journal_lines
  REFERENCING OLD TABLE AS old_table
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();
```

La fonction doit lire `new_table` **ou** `old_table` selon `TG_OP`.

**Recette.** Insérer une écriture déséquilibrée lève une exception ; une écriture équilibrée passe.

**Effort.** 2 h. **Priorité absolue dans ce lot.**

---

#### `LOT2-08` / `LOT2-09` — Toute insertion bancaire échoue

**Constat vérifié à l'exécution.**

```
ERROR: record "new" has no field "label"
CONTEXT: PL/pgSQL function auto_reconcile_by_score() line 14
```

`bank_transactions` porte `description`, jamais `label`. Import de relevé, synchronisation bancaire, saisie manuelle : tout est bloqué.

**Spécification.** Remplacer les trois occurrences de `NEW.label` par `NEW.description` dans `116_bank_reconciliation_score.sql` (lignes 61, 65, 160).

> **Note.** Ma propre contre-vérification du 12/09 proposait un correctif utilisant `NEW.label`, recopié d'un autre rapport sans vérification. Ce correctif est erroné et est remplacé par celui-ci.

**Recette.** `INSERT INTO bank_transactions (...)` réussit et déclenche le rapprochement.

**Effort.** 30 min.

---

#### `LOT2-01` / `LOT2-02` — `subtotal` n'existe pas sur les lignes de document

**Constat.** `invoice_lines` porte `total`, `vat_total`, `unit_price`, `quantity`, `vat_amount` — jamais `subtotal`. Idem pour `purchase_invoice_lines`.

**Spécification.** Dans les migrations 108/109/110 (les versions à jour), remplacer :

```sql
- SUM(il.subtotal)
+ SUM(il.total)          -- montant HT de la ligne
```

Vérifier au passage la sémantique : si `total` porte le TTC, utiliser `il.quantity * il.unit_price`.

**Recette.** Valider une facture produit une écriture équilibrée dont la ligne 707 vaut le HT.

**Effort.** 1 h.

---

#### `LOT2-18` → `LOT2-20` — Trois triggers de feuille de temps

**Constat.** `record "v_emp" is not assigned to tuple structure` — la variable est déclarée `RECORD` puis utilisée avant toute affectation, ou affectée par un `SELECT` qui ne remonte rien.

**Spécification.**

```sql
DECLARE
-  v_emp RECORD;
+  v_emp employees%ROWTYPE;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;
+ IF NOT FOUND THEN RETURN NEW; END IF;
```

**Effort.** 2 h pour les trois.

---

## 6. LOT 3 — Fonctions RPC cassées

31 fonctions, dont **21 appelées depuis le front**. Correctifs par famille.

### 6.1 États financiers — `LOT3-01` à `LOT3-04`

| Fonction | Erreur |
|---|---|
| `generate_trial_balance` | `aggregate function calls cannot be nested` |
| `generate_balance_sheet` | idem |
| `generate_profit_loss` | idem |
| `get_balance_sheet_structured` | `subquery uses ungrouped column "jl.account_general"` |

**Spécification.** Les trois premières échouent sur un motif du type `SUM(SUM(...))`. Réécrire avec une CTE intermédiaire :

```sql
WITH par_compte AS (
  SELECT COALESCE(jl.account_general, jl.account_code) AS code,
         SUM(jl.debit) AS d, SUM(jl.credit) AS c
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = current_tenant_id() AND je.status = 'posted'
  GROUP BY 1
)
SELECT code, d, c, d - c AS solde FROM par_compte;
```

Pour `get_balance_sheet_structured`, ajouter `jl.account_general` au `GROUP BY` de la requête englobante.

**Note.** `get_trial_balance` et `get_balance_sheet` (migration 106), celles que le front appelle réellement, sont **saines**. Les quatre ci-dessus sont des doublons exposés en parallèle : envisager leur suppression plutôt que leur correction.

**Effort.** 1 j.

---

### 6.2 Paie et RH — `LOT3-05` à `LOT3-09`

| Fonction | Erreur | Correctif |
|---|---|---|
| `calculate_overtime_pay` | `column "base_salary" does not exist` | → `salary` |
| `calculate_sick_leave_pay` | `v_emp has no field "base_salary"` | → `salary` |
| `calculate_notice_compensation` | idem | → `salary` |
| `calculate_compensated_leave_indemnity` | `relation "employee_attendance" does not exist` | → `timesheets` ou créer la table |
| `import_employee_with_cumuls` | `column "first_name" of relation "employees"` | → `name` (colonne unique) |

**Spécification.** `employees` porte `salary`, pas `base_salary`, et `name` en un seul champ, pas `first_name`/`last_name`. Corriger les cinq références. Déclarer `v_emp employees%ROWTYPE` plutôt que `RECORD`.

**Effort.** 4 h.

---

### 6.3 Immobilisations — `LOT3-10` à `LOT3-12`

| Fonction | Erreur | Correctif |
|---|---|---|
| `calculate_depreciation` | `v_asset has no field "acquisition_value"` | → `purchase_value` |
| `generate_depreciation_entry` | `v_fa has no field "acquisition_value"` | → `purchase_value` |
| `generate_adjusting_entries` | `column "acquisition_value" does not exist` | → `purchase_value` |

`fixed_assets` porte `purchase_value`, `current_value`, `residual_value`, `useful_life_years`.

**Effort.** 2 h.

---

### 6.4 Lettrage — `LOT3-13`, `LOT3-14`

| Fonction | Erreur | Correctif |
|---|---|---|
| `auto_letter_accounts` | `jl.lettering_code does not exist` | → `lettrage_code` |
| `auto_lettrage_by_reference` | `column "date" does not exist` | → qualifier `je.date` |

**Effort.** 1 h.

---

### 6.5 Tarification et commercial — `LOT3-15` à `LOT3-18`

| Fonction | Erreur | Correctif |
|---|---|---|
| `resolve_price` | `pl.customer_id does not exist` | voir ci-dessous |
| `calculate_payment_due_dates` | `v_terms has no field "days"` | `payment_terms` porte `type`, `end_of_month` |
| `calculate_project_profitability` | `i.project_id does not exist` | ajouter `invoices.project_id` |
| `check_segregation_of_duties` | `column "created_by" does not exist` | ajouter `journal_entries.created_by` |

**`resolve_price` — spécification complète.** `price_lists` porte `id, name, code, type, currency, valid_from, valid_to, active, is_default, tenant_id`. Il n'y a **aucun rattachement client**. La fonction ne peut pas fonctionner en l'état.

```sql
-- prérequis : rattacher les tarifs aux clients
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS priority int DEFAULT 0;
CREATE TABLE IF NOT EXISTS price_list_customers (
  price_list_id uuid NOT NULL REFERENCES price_lists(id) ON DELETE CASCADE,
  customer_id   uuid NOT NULL REFERENCES customers(id)   ON DELETE CASCADE,
  tenant_id     uuid NOT NULL,
  PRIMARY KEY (price_list_id, customer_id)
);
-- customers.price_list_id existe déjà : l'utiliser comme rattachement direct
```

Puis réécrire la résolution : tarif nominatif du client → tarif de sa catégorie → tarif par défaut, la quantité minimale la plus haute l'emportant, dans la fenêtre de validité.

**Effort.** 2 j.

---

### 6.6 Production et stock — `LOT3-19` à `LOT3-24`

| Fonction | Erreur | Correctif |
|---|---|---|
| `run_mrp` | `relation "_mrp_needs" does not exist` | créer la table temporaire |
| `calculate_production_cost` | `p.standard_cost does not exist` | → `cost_price` |
| `calculate_manufacturing_cost` | `ro.setup_time does not exist` | vérifier `routing_operations` |
| `calculate_stock_valuation` | `product_id is ambiguous` | qualifier `sq.product_id` |
| `import_initial_stock` | idem | qualifier |
| `distribute_by_grill` | `dgl.section_id does not exist` | vérifier `distribution_grill_lines` |

**`run_mrp` — spécification.**

```sql
CREATE OR REPLACE FUNCTION run_mrp(p_tenant_id uuid, p_horizon_days int DEFAULT 90)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  CREATE TEMP TABLE _mrp_needs ON COMMIT DROP AS      -- ← manquant
  SELECT * FROM explode_bom_recursive(p_tenant_id, 15);
  ...
```

**Effort.** 1 j.

---

### 6.7 Banque et divers — `LOT3-25` à `LOT3-31`

| Fonction | Erreur | Correctif |
|---|---|---|
| `smart_bank_reconciliation` | `column "bank_account_id" does not exist` | → `account_id` |
| `get_bank_reconciliation_state` | `jl.journal_entry_id does not exist` | → `jl.journal_id` |
| `generate_vat_return` | `vat_returns.vat_collected does not exist` | → `box1_output_vat` |
| `run_three_way_match` | `match_status is ambiguous` | qualifier |
| `generate_recurring_tasks` | `v_task is not assigned yet` | `%ROWTYPE` + `IF NOT FOUND` |
| `get_nf525_attestation` | `v_company has no field "company_name"` | → `name` |
| `create_tenant_for_current_user` | `function auth.jwt() does not exist` | → `auth.uid()` + lecture `tenant_users` |

**Effort.** 1 j.

---

## 7. LOT 4 — Logique métier fausse

Ces défauts ne provoquent pas d'erreur : ils produisent un **résultat plausible et faux**. C'est le mode de défaillance le plus coûteux.

---

### `LOT4-01` — Report à nouveau des classes 6 et 7

**Constat.** `generateCarryForward` (`accounting.ts:3071`) boucle sur toutes les lignes sans filtre de classe. En droit comptable français, **seules les classes 1 à 5 sont reportées** ; les classes 6 et 7 sont soldées à l'affectation du résultat. Les reporter double charges et produits de l'exercice suivant.

**Spécification.** Ne pas rafistoler le TypeScript. Le RPC `close_fiscal_year` (migration 107) fait le travail correctement. Rediriger :

```ts
export async function generateCarryForward(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('close_fiscal_year', { p_fiscal_year_id: fiscalYearId })
  if (error) throw error
  return data
}
```

Le RPC doit garantir :
1. Classes 1 à 5 reportées dans le journal `AN`.
2. Classes 6 et 7 soldées vers `120000` (bénéfice) ou `129000` (perte).
3. Comptes de tiers (401, 411) reportés **ligne à ligne avec leur code de lettrage non soldé** — c'est ce qui donne un grand livre des tiers continu.
4. Numérotation `AN-YYYY-0001` via le compteur séquentiel.

**Dépendance.** `close_fiscal_year` est écrasé par la migration 89 (`LOT0-01`). Corriger l'ordre **avant**.

**Recette.** Après clôture, `SELECT count(*) FROM journal_lines jl JOIN journal_entries je ON je.id=jl.journal_id WHERE je.journal_code='AN' AND jl.account_general ~ '^[67]'` retourne 0.

**Effort.** 4 h.

---

### `LOT4-02` — `calculate_payslip` : formule 22 %/42 % en dur

**Constat.** La migration 114 modélise un moteur de paie complet — `payroll_legal_parameters`, `payroll_cumulative`, scission CSG, réduction générale, PMSS. **Mais `calculate_payslip` n'a jamais été réécrite pour l'utiliser.** La version qui gagne est celle de la migration 89 :

```sql
v_ss_employee := v_total_gross * 0.22;
v_employer_contributions := v_total_gross * 0.42;
```

Et c'est bien cette fonction que le front appelle (`businessFunctions.ts:14`).

**Aggravant.** `PaySlipsPage.tsx` appelle **les deux** moteurs : `calculatePayslip` (RPC, 22 %/42 %) et `generatePaySlipsForRun` (moteur TypeScript refondu). **Deux moteurs qui donnent des résultats différents dans le même écran.**

**Aggravant 2.** La migration 114 s'exécute en position 24, la 89 en position 119. Même si on réécrivait `calculate_payslip` dans la 114, `LOT0-01` la ferait écraser.

**Spécification.**
1. Corriger `LOT0-01` d'abord.
2. Réécrire `calculate_payslip` dans une migration **postérieure à 89** (donc ≥ 131), en lisant `payroll_legal_parameters` et `payroll_cumulative`.
3. **Trancher entre les deux moteurs.** Recommandation : un seul, en SQL, appelé par les deux chemins de l'interface. Le moteur TypeScript devient une prévisualisation qui appelle le RPC.
4. Aucun bulletin n'est légalement valide tant que PMSS, tranches, scission CSG et régularisation progressive ne sont pas appliqués.

**Recette.** Un salarié à 6 000 € de brut voit ses cotisations plafonnées calculées sur le PMSS ; le résultat correspond à un bulletin de référence au centime près.

**Effort.** 3 semaines (voir `PAY-02` à `PAY-06` du plan de perfection).

---

### `LOT4-03` — CUMP initialisé à zéro

**Constat.** À la première entrée d'un article, `stock_quantities` n'a aucune ligne. `update_cump_on_movement` ne trouve rien et son `UPDATE` ne touche aucune ligne. Puis `increment_stock` crée la ligne **sans fournir `unit_cost`**, qui prend la valeur par défaut 0.

À la deuxième entrée : `CUMP = (Q₁ × 0 + Q₂ × P₂) / (Q₁ + Q₂)`. **La valeur du stock est faussée dès l'origine, irréversiblement.**

**Spécification.**

```sql
-- 1. increment_stock accepte et pose le coût
CREATE OR REPLACE FUNCTION increment_stock(
  p_product_id uuid, p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL, p_unit_cost numeric DEFAULT NULL   -- ← ajouté
) ...
  IF NOT FOUND THEN
    INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
    VALUES (v_tid, p_product_id, p_warehouse_id, p_qty, COALESCE(p_unit_cost, 0))
    ON CONFLICT DO NOTHING;
  END IF;

-- 2. update_cump_on_movement crée la ligne si absente, plutôt que de l'ignorer
INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
VALUES (NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 0, NEW.unit_cost)
ON CONFLICT (tenant_id, product_id, warehouse_id) DO NOTHING;
-- puis le calcul incrémental habituel, avec FOR UPDATE
```

L'ordre de déclenchement des deux triggers doit être déterministe : les nommer pour que `update_cump` s'exécute après `update_stock` (PostgreSQL ordonne par nom).

**Recette.** Entrée 100 @ 60 puis 50 @ 80 → `unit_cost = 66,67`, valeur du stock = 10 000 €.

**Effort.** 4 h.

---

### `LOT4-04` — Mouvements de stock non idempotents

**Constat.** `create_stock_out_on_delivery` déclenche sur `NEW.status IN ('shipped','delivered')` avec `IS DISTINCT FROM OLD.status`. Une fois `'shipped'` autorisé (`LOT1-04`), la transition `pending → shipped → delivered` sort la marchandise **deux fois**. Et `delivered → returned → delivered` la sort à nouveau.

**Spécification — deux niveaux.**

```sql
-- 1. ne déclencher qu'à l'entrée dans le flux
IF NEW.status IN ('shipped','delivered')
   AND COALESCE(OLD.status,'') NOT IN ('shipped','delivered') THEN

-- 2. garde structurelle : survit à toute modification future de la condition
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movement_source
  ON stock_movements (tenant_id, reference_type, reference_id, product_id, movement_type)
  WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL;
```

Le point 2 est le plus important. Une condition de trigger se remodifie ; un index unique, non.

**Recette.** Une livraison parcourant `pending → shipped → delivered → returned → delivered` produit **un seul** mouvement de sortie.

**Effort.** 3 h, plus la reprise des doublons existants.

---

### `LOT4-05` — Double entrée réception + contrôle qualité

**Constat.** `create_stock_on_goods_receipt` (81) est idempotent en lui-même. Mais `create_stock_in_on_quality_pass` (90) réinsère les mêmes `goods_receipt_lines` au passage du contrôle en `passed`. Dès qu'un article passe par les deux portes, le stock est crédité deux fois.

**Spécification — trancher, pas cumuler.**

Option immédiate : la réception crédite, le contrôle qualité ne crée plus de mouvement en cas de succès et sort vers le rebut en cas d'échec.

```sql
CREATE OR REPLACE FUNCTION create_stock_in_on_quality_pass() ... AS $$
BEGIN
  IF NEW.status = 'failed' AND OLD.status IS DISTINCT FROM 'failed' THEN
    INSERT INTO stock_movements (..., movement_type, type, ...) VALUES (..., 'out', 'out', ...);
  END IF;
  RETURN NEW;   -- le cas 'passed' ne génère plus de mouvement
END; $$;
```

Option cible : la réception place en quarantaine, le contrôle libère. Suppose le chantier des emplacements (`STK-11` du plan de perfection).

**Recette.** Réception + contrôle favorable → un seul mouvement d'entrée.

**Effort.** 3 h.

---

### `LOT4-06` — Réservations sur tous les dépôts

**Constat.** `118:106` met à jour `stock_quantities` sans filtrer sur l'entrepôt, alors que la clé métier est `(product_id, warehouse_id)`. Trois dépôts → trois fois la quantité réservée. La réservation elle-même est créée avec `warehouse_id = NULL`. Aucune libération à l'expédition.

**Difficulté préalable.** Ni `sales_orders` ni `sales_order_lines` ne portent de `warehouse_id`. Il n'existe aucune donnée disant **où** réserver.

**Spécification.**

```sql
-- prérequis
ALTER TABLE sales_order_lines ADD COLUMN IF NOT EXISTS warehouse_id uuid REFERENCES warehouses(id);
ALTER TABLE company_settings  ADD COLUMN IF NOT EXISTS default_warehouse_id uuid REFERENCES warehouses(id);

-- réservation ciblée
UPDATE stock_quantities
SET reserved_quantity = reserved_quantity + v_line.quantity      -- cf. LOT1-03
WHERE tenant_id = v_tid
  AND product_id = v_line.product_id
  AND warehouse_id = COALESCE(
        v_line.warehouse_id,
        (SELECT default_warehouse_id FROM company_settings WHERE tenant_id = v_tid));

-- libération à l'expédition
CREATE TRIGGER release_stock_on_delivery
  AFTER UPDATE ON delivery_notes FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION release_stock_on_shipment();
```

**Recette.** Une commande de 10 sur un dossier à trois dépôts réserve 10, pas 30 ; l'expédition libère.

**Effort.** 1 j.

---

### `LOT4-07` — Éclatement MRP mort-né

**Constat.** `115:50` joint un identifiant de nomenclature à un identifiant de produit :

```sql
JOIN bom_lines bl ON bl.product_id = (
  SELECT b.product_id FROM boms b WHERE b.id = e.product_id ...   -- b.id ≠ e.product_id
)
```

La sous-requête retourne toujours `NULL`. **L'éclatement ne descend jamais sous le niveau 1.**

**Spécification.**

```sql
FROM explosion e
JOIN boms b      ON b.product_id = e.product_id AND b.tenant_id = p_tenant_id AND b.active
JOIN bom_lines bl ON bl.bom_id = b.id AND bl.tenant_id = p_tenant_id
WHERE e.level < p_max_level
```

**Recette.** Une nomenclature à trois niveaux produit des propositions pour les composants **et** les matières premières.

**Effort.** 2 h.

---

### `LOT4-08` / `LOT4-09` — Lettrage

**`LOT4-08` — bloqué à A999.** `getNextLettrageCode` cherche le maximum par tri de chaînes puis remplit sur trois positions. `'A999' > 'A1000'` en lexicographique : le compteur est gelé.

```sql
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS next_lettrage_seq bigint DEFAULT 1;

CREATE OR REPLACE FUNCTION next_lettrage_code()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_seq bigint; v_tid uuid := current_tenant_id();
BEGIN
  UPDATE company_settings SET next_lettrage_seq = next_lettrage_seq + 1
  WHERE tenant_id = v_tid RETURNING next_lettrage_seq - 1 INTO v_seq;
  -- A001..Z999 puis AA01..ZZ99
  RETURN CASE WHEN v_seq <= 26*999
    THEN chr(65 + ((v_seq-1)/999)::int) || lpad((((v_seq-1)%999)+1)::text, 3, '0')
    ELSE '…' END;
END; $$;
```

**`LOT4-09` — sans contrôle d'équilibre.** `applyLettrage` pose le code sans vérifier ΣD = ΣC. Déplacer le contrôle en base :

```sql
CREATE OR REPLACE FUNCTION apply_lettrage(p_line_ids uuid[], p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_tid uuid := current_tenant_id(); v_d numeric; v_c numeric; v_comptes int;
BEGIN
  SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0),
         count(DISTINCT left(COALESCE(account_general,account_code),3))
  INTO v_d, v_c, v_comptes
  FROM journal_lines WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  IF v_comptes > 1 THEN
    RAISE EXCEPTION 'Lettrage sur % comptes de tiers différents', v_comptes;
  END IF;

  IF ABS(v_d - v_c) > 0.01 THEN
    -- écart sous tolérance → écriture d'écart en 658/758 ; sinon refus
    RAISE EXCEPTION 'Lettrage déséquilibré : débit % ≠ crédit % (écart %)', v_d, v_c, ABS(v_d-v_c);
  END IF;

  UPDATE journal_lines SET lettrage_code = p_code, lettrage_date = CURRENT_DATE
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  RETURN jsonb_build_object('lines', array_length(p_line_ids,1), 'amount', v_d);
END; $$;
```

**Effort.** 7 h pour les deux.

---

### `LOT4-10` — Numérotation par horodatage

**Constat.** `EXT-${Date.now()}` et `AN-${Date.now()}`. L'article A.47 A-1 du Livre des procédures fiscales exige une numérotation séquentielle continue sans rupture.

**Spécification.** `get_next_piece_number(p_journal_code)` existe déjà (`76:148`, corrigée en `80`). L'appeler.

**Effort.** 2 h.

---

### `LOT4-11` — Documents composés non atomiques

**Constat.** `createInvoice` (`sales.ts:106`) insère l'en-tête puis les lignes, sans transaction. Si la seconde insertion échoue, la facture reste en base sans lignes. Idem `generateExtourne` (`:3020`).

**À ne pas retraiter :** `createJournalEntry` **est** atomique (RPC `post_journal_entry`). Elle sert de modèle.

**Spécification.**

```sql
CREATE OR REPLACE FUNCTION create_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_tid uuid := current_tenant_id(); v_id uuid; v_line jsonb;
BEGIN
  INSERT INTO invoices SELECT * FROM jsonb_populate_record(
    NULL::invoices, p_invoice || jsonb_build_object('tenant_id', v_tid))
  RETURNING id INTO v_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO invoice_lines SELECT * FROM jsonb_populate_record(
      NULL::invoice_lines,
      v_line || jsonb_build_object('invoice_id', v_id, 'tenant_id', v_tid));
  END LOOP;

  RETURN jsonb_build_object('success', true, 'invoice_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END; $$;
```

Une fonction PL/pgSQL est implicitement transactionnelle : toute exception annule l'ensemble.

**Portée.** Cinq documents : facture de vente, facture d'achat, devis, commande, bon de livraison.

**Effort.** 2 j.

---

### `LOT4-12` / `LOT4-13` — Rapprochement à trois voies

**`LOT4-12` — appariement au hasard.** `86:174` (repli par produit) et `86:198` (ligne de réception, systématiquement) utilisent `LIMIT 1` sans consommer les reliquats. Deux lignes de facture de 10 contre une commande d'une ligne de 10 passent en `matched` : double facturation non détectée.

```sql
CREATE TEMP TABLE po_remaining ON COMMIT DROP AS
SELECT id, product_id, quantity AS qty_left, unit_price
FROM purchase_order_lines
WHERE purchase_order_id = v_po_id AND tenant_id = NEW.tenant_id;

-- dans la boucle
SELECT * INTO v_po_line FROM po_remaining
WHERE product_id = v_inv_line.product_id AND qty_left > 0
ORDER BY id LIMIT 1;

UPDATE po_remaining SET qty_left = qty_left - LEAST(qty_left, v_inv_line.quantity)
WHERE id = v_po_line.id;
```

Même traitement pour `goods_receipt_lines`.

**`LOT4-13` — écarts contaminants.** `v_price_variance` et `v_quantity_variance` (`86:123-124`) ne sont pas réinitialisés dans la boucle. Deux lignes à ajouter :

```sql
v_line_status := 'matched';
v_price_variance := 0;
v_quantity_variance := 0;
```

**Effort.** 1 j + 15 min.

---

### `LOT4-14` — Traçabilité bloquante

**Constat.** `check_tracking_on_sm` (`118:198`) lève en `BEFORE INSERT` si `lot_id` est nul. Aucun trigger automatisé ne le renseigne, et `delivery_note_lines`, `goods_receipt_lines`, `bom_lines` ne portent pas la colonne.

**Sévérité.** Latente : `products.tracking` vaut `'none'` par défaut. Le blocage se déclenche au premier article configuré — donc à la première mise en service d'un client agroalimentaire, pharmaceutique ou mécanique.

**Spécification — en trois temps.**
1. Dégrader le contrôle en avertissement tracé, pour ne pas bloquer.
2. Ajouter `lot_id` / `serial_id` aux trois tables de lignes, et faire renseigner les triggers automatisés (production depuis `manufacturing_orders.lot_number`, réception par saisie, livraison selon FEFO).
3. Rebasculer en exception et vider la table d'avertissements.

**Effort.** 1 j + 3 j.

---

## 8. LOT 5 — Sécurité, conformité, asynchrone

---

### `LOT5-01` — La vérification NF-525 ne vérifie rien

**Constat.** `verify_nf525_chain` (`91:325`) recalcule l'empreinte de chaque ligne à partir du `previous_hash` **stocké sur cette même ligne**. Chaque ligne est donc cohérente avec elle-même ; **le lien entre lignes n'est jamais testé**. Supprimer un maillon, ou en réécrire un avec son propre `previous_hash` recalculé, laisse la fonction répondre `chain_valid: true`.

C'est exactement ce que la norme demande d'empêcher. **L'argument de conformité anti-fraude est aujourd'hui sans fondement.**

**Spécification.**

```sql
-- dans la boucle, ordonnée par id ASC
IF v_last_seen_hash IS NOT NULL
   AND v_rec.previous_hash IS DISTINCT FROM v_last_seen_hash THEN
  v_broken_count := v_broken_count + 1;
  v_details := v_details || jsonb_build_object(
    'error','CHAIN_FORK_OR_MISSING_LINK','event_id',v_rec.id,
    'expected_prev',v_last_seen_hash,'actual_prev',v_rec.previous_hash);
END IF;
v_last_seen_hash := v_rec.current_hash;

-- continuité des identifiants : un BIGSERIAL qui saute signale une suppression
IF v_last_id IS NOT NULL AND v_rec.id <> v_last_id + 1 THEN
  v_gap_count := v_gap_count + 1;
END IF;
v_last_id := v_rec.id;

-- chain_valid devient une conjonction
'chain_valid', (v_broken_count = 0 AND v_gap_count = 0)
```

**Recette.** Journaliser trois événements, supprimer celui du milieu, appeler `verify_nf525_chain` → `chain_valid = false`.

**Effort.** 3 h.

---

### `LOT5-02` — Course d'écriture sur la chaîne

**Constat.** `log_nf525_event` (`91:113`) lit le dernier `current_hash` sans verrou. Deux transactions simultanées partent du même parent et créent deux branches.

**Spécification.**

```sql
-- première instruction de log_nf525_event
PERFORM pg_advisory_xact_lock(hashtext('nf525_chain_' || v_tid::text));

SELECT current_hash INTO v_prev_hash
FROM nf525_event_log WHERE tenant_id = v_tid
ORDER BY id DESC LIMIT 1
FOR UPDATE;
```

Verrou par tenant, libéré au `COMMIT`. Sérialise un dossier sans bloquer les autres.

**Note.** Une fois `LOT5-01` corrigé, cette course transforme un défaut silencieux en alerte permanente. **Traiter les deux ensemble.**

**Effort.** 1 h.

---

### `LOT5-03` — Séparation des tâches non désactivable

**Constat.** `enforce_journal_entry_permissions` (`120:48`) interdit à un utilisateur de valider une écriture qu'il a saisie. Aucun paramètre ne permet de désactiver la règle. Dans la majorité des TPE et chez les indépendants, il n'y a qu'un seul comptable : **l'application devient inutilisable**.

**Spécification.**

```sql
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS enforce_segregation boolean DEFAULT false;

-- dans enforce_journal_entry_permissions
IF COALESCE((SELECT enforce_segregation FROM company_settings WHERE tenant_id = NEW.tenant_id), false)
   AND NOT check_segregation_of_duties(auth.uid(), 'validate', NEW.id) THEN
  RAISE EXCEPTION 'Séparation des tâches : vous ne pouvez pas valider une écriture que vous avez saisie';
END IF;
```

Défaut à `false` — la règle s'active à la demande, pas par surprise.

**Dépendance.** `check_segregation_of_duties` est elle-même cassée (`LOT3-18`).

**Effort.** 2 h.

---

### `LOT5-04` — File de webhooks en mémoire

**Constat.** `outgoing-webhooks/index.ts:18` déclare un tableau au niveau du module et relance par `setTimeout`. Les fonctions Deno sont éphémères : dès la réponse retournée, le conteneur est gelé. **Toute la file est perdue.** Le commentaire du code l'admet.

**Spécification.**

```sql
CREATE TABLE IF NOT EXISTS outgoing_webhook_queue (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  endpoint_id uuid NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  attempts int NOT NULL DEFAULT 0,
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz,
  last_error text
);
CREATE INDEX ON outgoing_webhook_queue (next_retry_at) WHERE delivered_at IS NULL;
```

Worker `pg_cron` chaque minute, `FOR UPDATE SKIP LOCKED` sur 50 messages, temporisation exponentielle.

**Vérifier avant** : la migration 129 a déjà créé une table `webhook_queue` — ne pas en créer une seconde (même erreur que `LOT1-03`).

**Effort.** 2 j.

---

### `LOT5-05` — Aucun filtrage SSRF

**Constat.** Les URL de webhook ne sont pas filtrées : zéro occurrence de `hostname`, `127.0.0.1` ou `169.254`. Un utilisateur peut enregistrer un point de terminaison vers le réseau interne ou le service de métadonnées de l'infrastructure.

**Spécification.**

```ts
function isAllowedWebhookUrl(raw: string): boolean {
  let u: URL
  try { u = new URL(raw) } catch { return false }
  if (u.protocol !== 'https:') return false
  const h = u.hostname
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(h)) return false
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return false
  if (h === '::1' || h.startsWith('fd') || h.startsWith('fe80:')) return false
  return true
}
```

Valider **à l'enregistrement** du point de terminaison, et revalider après résolution DNS avant l'envoi.

**Effort.** 4 h.

---

### `LOT5-06` — Vulnérabilités npm

**Constat.** 3 vulnérabilités modérées sur `vitest`, `@vitest/coverage-v8`, `@vitest/mocker` — dépendances de développement uniquement.

**Spécification.** `npm audit fix`, puis ajouter `npm audit --audit-level=high` en CI (déjà présent au job 5).

**Effort.** 30 min.

---

## 9. LOT 6 — Garde-fous

> Sans ce lot, les 87 défauts reviendront. C'est le seul investissement qui se rentabilise indéfiniment.

---

### `LOT6-01` — `plpgsql_check` en intégration continue

**Trouve** : les 51 défauts des LOT 2 et LOT 3, et toute récidive.

```yaml
# ci.yml, job db-integration, après l'application des migrations
- name: Installer plpgsql_check
  run: |
    docker exec pg apt-get update -qq
    docker exec pg apt-get install -y -qq postgresql-16-plpgsql-check
    psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS plpgsql_check;"

- name: Valider toutes les fonctions PL/pgSQL
  run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/ci/check_plpgsql.sql
```

```sql
-- sql/ci/check_plpgsql.sql
DO $$
DECLARE r RECORD; v_errors int := 0;
BEGIN
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

**Effort.** 2 h.

---

### `LOT6-02` — Types Supabase générés

**Trouve** : les 9 colonnes fantômes du LOT 1, et rend la classe entière impossible.

```bash
supabase gen types typescript --local > src/types/supabase.ts
```
```ts
const supabase = createClient<Database>(url, key)
// .from('bank_transactions').eq('transaction_date', x)
//                                ~~~~~~~~~~~~~~~~ erreur de compilation
```

Régénérer en CI après les migrations et échouer si le fichier diffère de celui commité.

**C'est le pendant exact de `LOT6-01` côté TypeScript** — et le levier le plus rentable de tout ce document.

**Effort.** 1 j.

---

### `LOT6-03` — Condition de trigger atteignable

**Trouve** : les 6 triggers morts de `LOT1-01`.

```sql
DO $$
DECLARE r RECORD; v_errors int := 0;
BEGIN
  FOR r IN
    WITH trg AS (
      SELECT c.relname AS tbl, p.proname AS fn, pg_get_functiondef(p.oid) AS src
      FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
      WHERE NOT t.tgisinternal
    ), lits AS (
      SELECT DISTINCT tbl, fn, m[1] AS val
      FROM trg, regexp_matches(src, 'NEW\.status\s*(?:=|IN\s*\()\s*''([a-z_]+)''', 'g') m
    ), chk AS (
      SELECT conrelid::regclass::text AS tbl, pg_get_constraintdef(oid) AS def
      FROM pg_constraint WHERE contype='c' AND pg_get_constraintdef(oid) ILIKE '%(status%'
    )
    SELECT l.tbl, l.fn, l.val FROM lits l JOIN chk ON chk.tbl = l.tbl
    WHERE chk.def NOT ILIKE '%''' || l.val || '''%'
  LOOP
    RAISE WARNING 'TRIGGER MORT : %.% attend ''%'' — interdit par la contrainte', r.tbl, r.fn, r.val;
    v_errors := v_errors + 1;
  END LOOP;
  IF v_errors > 0 THEN RAISE EXCEPTION '% trigger(s) ne peuvent jamais se déclencher', v_errors; END IF;
END $$;
```

**Effort.** 1 h.

---

### `LOT6-04` — Objets sans consommateur

**Trouve** : les ~250 exports morts et les 22 tables de la migration 127.

```bash
npx knip --reporter compact   # échoue si le compte dépasse le plafond
```

Plus un script qui croise `information_schema.tables` avec `grep` sur `src/lib/queries/` pour lister les tables métier jamais lues. Plafond décroissant : geler le compte actuel, refuser toute augmentation.

**Effort.** 4 h.

---

### `LOT6-05` — Scénarios métier bout en bout

**Trouve** : ce qu'aucun contrôle statique ne voit.

Les quatre garde-fous précédents sont statiques. Ils ne remplacent pas l'exécution d'un parcours réel. Dix parcours minimum, exécutés contre une vraie base via **Testcontainers** :

1. devis → commande → livraison → facture → règlement → lettrage
2. achat → réception → contrôle → facture → rapprochement 3 voies → paiement
3. saisie d'écriture → validation → balance → grand livre
4. OF → consommation → production → coût de revient → écriture
5. bulletin de paie → écriture → DSN
6. vente en caisse → clôture → comptabilisation
7. import de relevé → rapprochement → lettrage
8. clôture d'exercice → à-nouveaux → bilan d'ouverture
9. réservation → préparation → expédition → libération
10. isolation multi-tenant sur les 356 tables

**Effort.** 1 semaine.

---

## 10. LOT 7 — Dette et périmètre

Traité en détail dans [PLAN-PERFECTION-9.5.md](PLAN-PERFECTION-9.5.md) — 141 chantiers sur 28 axes. Rappel des éléments qui croisent ce registre :

| Réf | Objet | Renvoi |
|---|---|---|
| `LOT7-01` | ~250 exports jamais importés | garde-fou `LOT6-04` |
| `LOT7-02` | Migration 127 : 27 tables, 0 fonction | plan de perfection, vague 3 |
| `LOT7-03` | 303 requêtes non bornées | `DAT-01` |
| `LOT7-04` | 1 991 `any` | `SOC-03` |
| `LOT7-05` | Deux jeux de triggers d'équilibre | se résout avec `LOT0-01` + `LOT2-05` |
| `LOT7-06` | `_skip_cascade` jamais lu | `PRJ-01` |
| `LOT7-07` | Accessibilité non traitée | `UX-02` |
| `LOT7-08` | 4 edge functions en simulation | `CNF-01` |

---

## 11. Plan d'exécution

### Jour 1 — Débloquer

| Réf | Action | Effort |
|---|---|---|
| `LOT0-01` | Trier les migrations par numéro | 15 min |
| `LOT0-02` | Réparer le build | 30 min |
| `LOT4-13` | Réinitialiser les variables d'écart | 15 min |
| `LOT2-05` | Déclarer la table de transition du contrôle d'équilibre | 2 h |
| `LOT2-08` `LOT2-09` | `NEW.label` → `NEW.description` | 30 min |
| `LOT0-01b` | Rejeu vérifié sur base neuve | 2 h |
| `LOT1-03` | Fusionner les colonnes de réservation | 2 h |

**Sortie.** Le déploiement redémarre, l'équilibre comptable est garanti, les transactions bancaires s'insèrent.

---

### Jours 2 à 4 — Rendre l'application fonctionnelle

| Réf | Action | Effort |
|---|---|---|
| `LOT1-01` | Brancher les triggers sur `validation_status` + élargir les contraintes | 4 h |
| `LOT4-04` | Idempotence des mouvements de stock + index unique | 3 h |
| `LOT1-04` | Ajouter `'shipped'`, **après** `LOT4-04` | 1 h |
| `LOT2-01` `LOT2-02` | `subtotal` → `total` | 1 h |
| `LOT2-11` → `LOT2-14` | Caisse : `line_total`, `date`, `id`, `entity_id` | 2 h |
| `LOT2-03` `LOT2-04` | Paiements : jointure sur `invoice_id` | 2 h |
| `LOT1-02` | Aligner `type` et `movement_type` | 2 h |
| `LOT4-03` | CUMP initialisé correctement | 4 h |
| `LOT4-05` | Trancher réception contre contrôle qualité | 3 h |
| `LOT2-15` → `LOT2-21` | Le reste des triggers | 1 j |

**Sortie.** Une facture validée produit une écriture. Une caisse se clôture. Le stock se valorise.

---

### Semaine 1 — Poser les garde-fous

| Réf | Action | Effort |
|---|---|---|
| `LOT0-03` | Réparer et étendre les tests de triggers | 3 h |
| `LOT0-04` | Rendre les tests RLS génériques | 1 j |
| `LOT6-01` | `plpgsql_check` en CI | 2 h |
| `LOT6-03` | Contrôle de trigger atteignable | 1 h |
| `LOT6-02` | Types Supabase générés | 1 j |
| `LOT1-06` | Corriger les 9 colonnes fantômes | 4 h |

**Sortie.** Aucun des 87 défauts ne peut revenir sans faire échouer la CI.

---

### Semaines 2 et 3 — Fonctions RPC et logique métier

LOT 3 en entier (5 j), puis `LOT4-01`, `LOT4-06` à `LOT4-12`, `LOT5-01` à `LOT5-03`.

---

### Semaines 4 à 7 — Le moteur de paie

`LOT4-02` et les chantiers `PAY-02` à `PAY-06` du plan de perfection. C'est le seul chantier qui appelle une refonte plutôt qu'un correctif.

---

### Au-delà

`LOT6-05` (scénarios bout en bout), `LOT5-04` `LOT5-05` (webhooks), puis le plan de perfection.

---

## 12. Critères de recette

Un lot n'est clos que lorsque **tous** ses critères passent en intégration continue.

| Réf | Critère de recette |
|---|---|
| `LOT0-01` | `pg_get_functiondef('create_journal_on_invoice_validate')` contient `account_tiers` |
| `LOT0-02` | `npm run build` sort en code 0 ; les cinq jobs CI sont verts |
| `LOT0-03` | `102_trigger_tests.sql` passe ; annuler `LOT0-01` le fait échouer |
| `LOT0-04` | Le test RLS générique couvre les 356 tables et passe |
| `LOT1-01` | `UPDATE invoices SET validation_status='validated'` produit une écriture `VT` |
| `LOT1-02` | Un mouvement `'initial'` s'insère et alimente la valorisation |
| `LOT1-03` | L'écran de stock affiche la quantité réservée après confirmation d'une commande |
| `LOT1-06` | Le détecteur front↔schéma retourne 0 |
| `LOT1-07` | `pg_policies` compte 8 politiques sur `module_documents` |
| `LOT2-*` | `plpgsql_check` retourne 0 erreur sur les 392 triggers |
| `LOT2-05` | Une écriture déséquilibrée lève une exception ; une équilibrée passe |
| `LOT3-*` | `plpgsql_check` retourne 0 erreur sur les 180 fonctions |
| `LOT4-01` | Après clôture, aucune ligne de classe 6 ou 7 dans le journal `AN` |
| `LOT4-02` | Un brut de 6 000 € plafonne au PMSS ; écart nul avec un bulletin de référence |
| `LOT4-03` | 100 @ 60 puis 50 @ 80 → CUMP 66,67 et valeur 10 000 € |
| `LOT4-04` | `pending → shipped → delivered → returned → delivered` = 1 seul mouvement |
| `LOT4-05` | Réception + contrôle favorable = 1 seule entrée |
| `LOT4-06` | Commande de 10 sur 3 dépôts = 10 réservés, pas 30 |
| `LOT4-07` | Une nomenclature à 3 niveaux remonte les matières premières |
| `LOT4-08` | Le 1000ᵉ lettrage produit un code valide et distinct |
| `LOT4-09` | Lettrer 100 au débit contre 90 au crédit est refusé |
| `LOT4-11` | Ligne invalide → aucune facture orpheline en base |
| `LOT4-12` | 2 lignes du même article → double facturation détectée en `mismatch` |
| `LOT5-01` | Supprimer un maillon → `chain_valid = false` |
| `LOT5-02` | 100 écritures concurrentes → chaîne linéaire, aucun fork |
| `LOT5-03` | `enforce_segregation = false` permet à l'utilisateur unique de valider |
| `LOT5-05` | Un point de terminaison vers `169.254.169.254` est refusé à l'enregistrement |
| `LOT6-01` → `LOT6-05` | Chaque garde-fou échoue quand on réintroduit volontairement son défaut |

---

## Annexe — Reproduire l'audit

```bash
docker run -d --name onusuite-audit -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=audit postgres:16
docker exec -u root onusuite-audit apt-get update -qq
docker exec -u root onusuite-audit apt-get install -y -qq postgresql-16-plpgsql-check
docker cp app/sql/. onusuite-audit:/sql/

# schémas et rôles Supabase simulés (auth.uid, authenticated, anon, service_role)
docker exec onusuite-audit psql -U postgres -d audit -c "…"   # cf. AUDIT-EXECUTION-REELLE.md
docker exec onusuite-audit psql -U postgres -d audit -f /sql/00_schema_dump.sql

# migrations en ordre NUMÉRIQUE
ls app/sql/*.sql | sed 's|.*/||' | grep -E '^[0-9]{2,3}_' | grep -v 00_schema_dump \
  | sort -t_ -k1 -n \
  | while read f; do docker exec onusuite-audit psql -U postgres -d audit -f "/sql/$f"; done

# garde-fous du LOT 6
docker exec onusuite-audit psql -U postgres -d audit -f /sql/ci/check_plpgsql.sql
docker exec onusuite-audit psql -U postgres -d audit -f /sql/ci/check_trigger_reachable.sql

# outillage TypeScript
cd app && npx knip --reporter compact && npx madge --circular --extensions ts,tsx src && npm audit
docker run --rm -v "$PWD/supabase/functions":/fn denoland/deno sh -c 'cd /fn; for d in */; do deno check "$d/index.ts"; done'
```

---

## Documents liés

| Document | Objet |
|---|---|
| [AUDIT-EXECUTION-REELLE.md](AUDIT-EXECUTION-REELLE.md) | méthode et détail de l'audit par exécution |
| [REGISTRE-DEFAUTS-CONSOLIDE.md](REGISTRE-DEFAUTS-CONSOLIDE.md) | fusion des revues Claude et Gemini par lecture |
| [PLAN-PERFECTION-9.5.md](PLAN-PERFECTION-9.5.md) | 141 chantiers vers 9,5/10 sur 28 axes |

---

*Cahier des charges établi le 12 septembre 2026 sur la branche `commercial-hr-paie`. Chaque défaut a été reproduit contre le code ou contre une base PostgreSQL 16.14 réelle. Les spécifications de correction indiquent la direction et n'ont pas été exécutées : elles doivent être validées par les critères de recette de la section 12.*
