# Registre consolidé des défauts — Onusuite

> **Version** 1.0 — 12 septembre 2026
> **Branche** `commercial-hr-paie`
> **Sources fusionnées**
> - Revue Claude, volets 1 à 3 (9 et 12 septembre) — noyau comptable, modules d'exploitation, évolution
> - Audit Gemini (septembre) — requêtes, triggers, workflows
> **Méthode** chaque constat des deux rapports a été reconfronté au code le 12 septembre. Les constats non reproductibles sont marqués comme tels.

---

## Sommaire

- [1. Synthèse](#1-synthèse)
- [2. Pourquoi deux audits, et pourquoi ils ne se recouvrent pas](#2-pourquoi-deux-audits-et-pourquoi-ils-ne-se-recouvrent-pas)
- [3. Registre maître](#3-registre-maître)
- [4. Bloquants — `P0`](#4-bloquants--p0)
- [5. Majeurs — `P1`](#5-majeurs--p1)
- [6. Moyens — `P2`](#6-moyens--p2)
- [7. Constats non retenus](#7-constats-non-retenus)
- [8. Plan d'exécution](#8-plan-dexécution)
- [9. Le test qui manque](#9-le-test-qui-manque)

---

## 1. Synthèse

| Mesure | Valeur |
|---|---|
| Défauts confirmés dans le code au 12/09 | **26** |
| dont bloquants `P0` | **10** |
| dont majeurs `P1` | **10** |
| dont moyens `P2` | **6** |
| Constats écartés après vérification | 3 |
| Défauts corrigés pendant l'intervalle d'audit | 1 |
| Défauts qu'un test d'intégration aurait attrapés | **17 sur 26** |
| Effort cumulé des `P0` | ~3 jours |
| Note globale | **6,9 / 10** — plafonnée à 6,9 tant que la chaîne de livraison est arrêtée |

**Trois faits dominent ce registre.**

1. **Rien ne peut être déployé.** `npm run build` échoue depuis l'activation du mode strict. Tous les correctifs listés ici, y compris ceux déjà écrits et présents dans le dépôt, restent hors production tant que ce point n'est pas réglé.

2. **Une partie du travail des trois derniers jours est annulée à l'exécution.** Le runner de migrations trie les fichiers en ordre alphabétique : les migrations 100 à 130 s'exécutent avant les migrations 12 à 99. Dix fonctions corrigées reviennent à leur version d'avant le correctif.

3. **Dix-sept des vingt-six défauts se seraient manifestés au premier scénario métier exécuté contre une vraie base.** Le job `db-integration` existe depuis le 11 septembre et couvre quatorze scénarios — dont aucun ne touche les bons de livraison, les contrôles qualité, les lots, le lettrage, NF-525 ni les réservations.

---

## 2. Pourquoi deux audits, et pourquoi ils ne se recouvrent pas

Les deux revues ont lu le même dépôt à trois jours d'intervalle et se sont partagé le travail sans le savoir.

| | Revue Claude | Audit Gemini |
|---|---|---|
| **Angle** | Exécution : ordre des migrations, build, tests, chaîne CI, comparaison au marché | Lecture : corps de chaque trigger, algorithme de chaque requête |
| **Trouve** | Ce qui ne se voit qu'en lançant les commandes | Ce qui ne se voit qu'en lisant ligne à ligne |
| **Rate** | La condition d'un trigger, la logique d'une vérification cryptographique | L'ordre d'exécution, l'état du build |
| **Apport unique** | Ordre des migrations, build cassé, colonne de réservation dupliquée, câblage front absent | Vérification NF-525 inopérante, doubles mouvements de stock, réservations multi-dépôts, lettrage bloqué, report à nouveau non conforme |

**Aucune revue statique ne remplace l'autre, et aucune des deux ne remplace un test.** C'est la conclusion opérationnelle de ce registre, et elle est traitée en [section 9](#9-le-test-qui-manque).

---

## 3. Registre maître

| Réf | Défaut | Source | Sév. | Fichier | Test manquant |
|---|---|---|:---:|---|:---:|
| `INF-01` | Migrations triées alphabétiquement — 10 fonctions écrasées | Claude v3 | **P0** | `run-sql-migrations.mjs:88` | oui |
| `INF-02` | Build de production cassé | Claude v3 | **P0** | `vite.config.ts:11` | oui |
| `NF-01` | Vérification de chaîne NF-525 inopérante | Gemini 4.1 | **P0** | `91:325` | oui |
| `NF-02` | Course d'écriture sur la chaîne d'empreintes | Gemini 4.1 | **P0** | `91:113` | oui |
| `STK-01` | Mouvements de stock non idempotents | Gemini 3.1 | **P0** | `90:290` | oui |
| `STK-02` | Double entrée réception + contrôle qualité | Gemini 3.1b | **P0** | `81:255` / `90:303` | oui |
| `STK-03` | Réservations appliquées à tous les dépôts | Gemini 3.3 | **P0** | `118:106` | oui |
| `STK-04` | Colonne de réservation dupliquée | Claude | **P0** | `schema:4013` / `118:9` | oui |
| `ACC-01` | Report à nouveau des classes 6 et 7 | Gemini 2.3 | **P0** | `accounting.ts:3071` | oui |
| `UI-01` | Statut `shipped` refusé par la base mais proposé à l'écran | Claude | **P0** | `DeliveryNotesPage.tsx:13` | oui |
| `ACC-02` | Lettrage bloqué à A999 | Gemini 2.4 | P1 | `accounting.ts:1074` | oui |
| `ACC-03` | Lettrage sans contrôle d'équilibre | Gemini 2.4 | P1 | `accounting.ts:1046` | oui |
| `ACC-04` | Numérotation par horodatage | Gemini 2.3 | P1 | `accounting.ts:3019,3098` | non |
| `ACC-05` | Documents composés non atomiques | Gemini 2.1 | P1 | `sales.ts:106` | oui |
| `STK-05` | Traçabilité lot bloquante (latente) | Gemini 3.2 | P1 | `118:198` | oui |
| `ACH-01` | Rapprochement 3 voies en `LIMIT 1` | Gemini 4.2 | P1 | `86:174,198` | oui |
| `ACH-02` | Variables d'écart non réinitialisées | Gemini 4.2 | P1 | `86:123` | oui |
| `QUA-01` | Tests d'intégration lacunaires | les deux | P1 | `102_trigger_tests.sql` | — |
| `QUA-02` | Tests RLS : 4 tables sur 530 | Claude v3 | P1 | `105_rls_tests.sql` | — |
| `DAT-01` | 303 requêtes non bornées | les deux | P1 | `queries/*.ts` | oui |
| `FRT-01` | Briques neuves non câblées au front | Claude v3 | P1 | `sales.ts:15`, `bankParsers.ts` | non |
| `SQL-01` | Migration 127 : 27 tables, 0 fonction | Claude v3 | P2 | `127` | non |
| `ASY-01` | File de webhooks en mémoire | Gemini 4.4 | P2 | `outgoing-webhooks:18` | non |
| `ASY-02` | Aucun filtrage SSRF sur les webhooks | Gemini 4.4 | P2 | `outgoing-webhooks` | non |
| `PRJ-01` | `_skip_cascade` jamais lu | Gemini 3.4 | P2 | `85:78` | non |
| `PRF-01` | Deux jeux de triggers d'équilibre actifs | Claude v3 | P2 | `76:105` / `128:57` | oui |
| `TS-01` | `any` en progression malgré le mode strict | Claude v3 | P2 | `src/` | non |

---

## 4. Bloquants — `P0`

---

### `INF-01` — Les migrations s'exécutent dans le désordre

**Constat.** `run-sql-migrations.mjs:88` applique un `.sort()` JavaScript sur les noms de fichiers. C'est un tri de chaînes. Tant que la numérotation tenait sur deux chiffres l'ordre était juste ; le passage à trois chiffres l'a inversé.

Ordre réel sur 126 migrations :

```
position   9 → 101_stock_valuation_to_gl.sql
position  15 → 107_fiscal_year_close.sql
position  16 → 108_auxiliary_accounts.sql
position  21 → 112_manufacturing_costing.sql
position  42 → 130_missing_rpc_and_fixes.sql
   …
position 102 → 76_accounting_invariants_and_stock_rpcs.sql   ← écrase la 101
position 107 → 81_complete_workflow_triggers.sql             ← écrase la 112
position 115 → 89_missing_rpc_functions.sql                  ← écrase la 107
position 121 → 95_fix_posted_before_lines.sql                ← écrase 108/109/110
```

Chaque migration tardive utilise `CREATE OR REPLACE FUNCTION`, qui remplace sans avertir. **Dix fonctions et un trigger reviennent à leur version d'avant le correctif :**

| Fonction | Corrigée par | Écrasée par | Chantier annulé |
|---|---|---|---|
| `create_journal_on_invoice_validate` | 108, 109, 110 | 95 | comptes auxiliaires, TVA multi-taux, comptes par article |
| `create_journal_on_purchase_invoice_validate` | 108, 109, 110 | 95 | idem sur le flux achat |
| `create_journal_on_customer_payment` | 108 | 95 | comptes auxiliaires |
| `create_journal_on_supplier_payment` | 108 | 95 | comptes auxiliaires |
| `create_stock_on_manufacturing_complete` | 112 | 81 | coût de revient d'OF |
| `close_fiscal_year` | 107 | 89 | clôture d'exercice |
| `increment_stock`, `decrement_stock`, `update_stock_on_movement` | 101 | 76 | fonctions de stock |
| trigger d'équilibre | 128 | 76 | passage en `FOR EACH STATEMENT` |

**Ce que cela change pour le constat Gemini 3.5.** Les comptes en dur `411000` / `707000` / `4457000` ne sont pas seulement un défaut de conception : **le correctif existe déjà** dans les migrations 108, 109 et 110. Il suffit de le laisser s'exécuter en dernier.

**Correctif.**

```js
// run-sql-migrations.mjs:88 — trier sur le numéro, pas sur la chaîne
- .sort();
+ .sort((a, b) => {
+     const na = parseInt(a.match(/^(\d+)/)[1], 10);
+     const nb = parseInt(b.match(/^(\d+)/)[1], 10);
+     return na - nb || a.localeCompare(b);
+   });
```

Puis rejouer sur une base neuve et vérifier :

```sql
-- doit contenir account_tiers, pas seulement '411000'
SELECT pg_get_functiondef('create_journal_on_invoice_validate'::regproc);
-- doit contenir unit_cost
SELECT pg_get_functiondef('create_stock_on_manufacturing_complete'::regproc);
-- un seul jeu de triggers d'équilibre
SELECT tgname FROM pg_trigger WHERE tgrelid = 'journal_lines'::regclass AND NOT tgisinternal;
```

**Effort.** 15 minutes pour le tri, 2 heures pour le rejeu vérifié.

---

### `INF-02` — Le build de production est cassé

**Constat.** L'activation du mode strict a été faite sur `tsconfig.app.json`, qui passe à zéro erreur. Mais `tsc -b` construit les trois projets référencés, et `tsconfig.node.json` en remonte quatre :

```
$ npm run build
vite.config.ts(11,5): error TS2769: No overload matches this call.
    Type '"" | VisualizerPlugin | undefined' is not assignable to type 'PluginOption'.
      Type '""' is not assignable to type 'PluginOption'.
```

La cause est `process.env.ANALYZE && visualizer({…})` : quand la variable n'est pas définie, l'expression vaut la chaîne vide, que Vite refuse comme greffon.

**Conséquence sur la chaîne.** `lint-typecheck` lance `npx tsc -b --noEmit` et échoue. `build` lance `npm run build` et échoue. Le job de synthèse exige les cinq jobs en succès, et `deploy.yml` se déclenche sur `workflow_run` avec `conclusion == 'success'`. **Rien ne peut être déployé.**

**Correctif.**

```ts
// vite.config.ts:11
- process.env.ANALYZE && visualizer({ filename: 'dist/stats.html', … }),
+ ...(process.env.ANALYZE
+     ? [visualizer({ filename: 'dist/stats.html', template: 'treemap', gzipSize: true, brotliSize: false })]
+     : []),
```

Les trois autres erreurs du même projet se traitent de la même façon. Ajouter ensuite `npm run build` au crochet de pré-envoi, pour que l'écart entre le poste et la CI ne se reproduise pas.

**Effort.** 30 minutes.

---

### `NF-01` — La vérification d'intégrité NF-525 ne vérifie rien

**Constat.** La fonction censée prouver qu'aucun événement n'a été altéré recalcule l'empreinte de chaque ligne à partir du `previous_hash` *stocké sur cette même ligne* :

```sql
-- 91_nf525_anti_fraud.sql:325
v_hash_input := COALESCE(v_rec.previous_hash, 'GENESIS') || '|' || …
v_expected_hash := encode(digest(v_hash_input, 'sha256'), 'hex');
IF v_expected_hash != v_rec.current_hash THEN
  v_broken_count := v_broken_count + 1;
END IF;
```

Chaque ligne est donc cohérente **avec elle-même**. Le lien entre lignes n'est jamais testé. Supprimer un enregistrement au milieu de la chaîne, ou en réécrire un avec son propre `previous_hash` recalculé, laisse la fonction répondre `chain_valid: true`.

C'est exactement ce que la norme demande d'empêcher. L'argument de conformité anti-fraude est actuellement sans fondement.

**Correctif.**

```sql
-- dans verify_nf525_chain, à l'intérieur de la boucle
IF v_last_seen_hash IS NOT NULL
   AND v_rec.previous_hash IS DISTINCT FROM v_last_seen_hash THEN
  v_broken_count := v_broken_count + 1;   -- rupture de chaîne
END IF;
v_last_seen_hash := v_rec.current_hash;

-- et contrôle de continuité des identifiants : un BIGSERIAL qui saute
-- signale une suppression, même si les empreintes se recollent
IF v_last_id IS NOT NULL AND v_rec.id <> v_last_id + 1 THEN
  v_gap_count := v_gap_count + 1;
END IF;
```

Retourner `gap_count` dans le résultat et faire de `chain_valid` une conjonction : `v_broken_count = 0 AND v_gap_count = 0`.

**Effort.** 3 heures.

---

### `NF-02` — Course d'écriture sur la chaîne d'empreintes

**Constat.** `log_nf525_event` lit le dernier `current_hash` du tenant sans aucun verrou :

```sql
-- 91_nf525_anti_fraud.sql:113
SELECT current_hash INTO v_prev_hash
FROM nf525_event_log
WHERE tenant_id = v_tid
ORDER BY id DESC
LIMIT 1;
```

Deux transactions simultanées lisent le même parent et créent deux branches. Une chaîne qui bifurque n'est plus une chaîne — et `NF-01` corrigé la détectera comme une rupture, transformant un défaut silencieux en alerte permanente.

**Correctif.**

```sql
-- première instruction de log_nf525_event, avant toute lecture
PERFORM pg_advisory_xact_lock(hashtext('nf525:' || v_tid::text));
```

Le verrou est pris par tenant et libéré à la fin de la transaction. Il sérialise les écritures d'un même dossier sans bloquer les autres.

**Effort.** 1 heure.

---

### `STK-01` — Les mouvements de stock ne sont pas idempotents

**Constat, avec une nuance importante.** Le trigger déclenche à chaque transition vers l'un des deux états :

```sql
-- 90_missing_workflow_triggers.sql:290
IF NEW.status IS DISTINCT FROM OLD.status
   AND NEW.status IN ('shipped', 'delivered') THEN
```

L'audit Gemini décrit le scénario `draft → shipped → delivered` produisant une double sortie. **Ce scénario précis est impossible** : la contrainte de la table n'admet que `('pending','delivered','returned','cancelled')` — `'shipped'` est rejeté par la base (voir `UI-01`).

**Le défaut demeure néanmoins, par un autre chemin.** `delivered → returned → delivered` refait sortir la marchandise, et rien ne protège contre une remise à jour du statut par script, par import ou par correction manuelle. Il n'existe aucune garde d'idempotence sur `stock_movements`.

**Correctif — les deux niveaux.**

```sql
-- 1. ne déclencher qu'à l'entrée dans l'état
IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' THEN

-- 2. garde structurelle : rend le double mouvement impossible
--    quelle que soit la condition du trigger, aujourd'hui et demain
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movement_source
  ON stock_movements (tenant_id, reference_type, reference_id, product_id, movement_type)
  WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL;
```

Le second point est le plus important : c'est la protection qui survit aux prochaines modifications de trigger.

**Effort.** 2 heures, plus une reprise des doublons déjà créés.

---

### `STK-02` — Double entrée sur réception puis contrôle qualité

**Constat.** `create_stock_on_goods_receipt` (`81:255`) est idempotent en lui-même — il sort si `OLD.status = 'received'`. Mais `create_stock_in_on_quality_pass` (`90:303`) réinsère les mêmes `goods_receipt_lines` au passage du contrôle en `passed` :

```sql
FOR v_gr_line IN SELECT * FROM goods_receipt_lines
  WHERE goods_receipt_id = NEW.reference_id … LOOP
  INSERT INTO stock_movements (…) VALUES (…, 'in', …);
END LOOP;
```

Dès qu'un article passe par les deux portes, le stock est crédité deux fois.

**Correctif — trancher, pas cumuler.** Choisir *une* porte d'entrée :

- **Option A (recommandée).** La réception place la marchandise dans un emplacement de quarantaine ; seul le contrôle qualité la rend disponible. Suppose `STK-11` du plan de perfection (emplacements).
- **Option B (immédiate).** La réception crédite. Le contrôle qualité ne crée aucun mouvement : il valide, ou déclenche un mouvement de sortie vers le rebut en cas d'échec.

L'option B se met en place aujourd'hui :

```sql
-- create_stock_in_on_quality_pass : ne plus créditer, seulement tracer
IF NEW.status = 'failed' AND OLD.status IS DISTINCT FROM 'failed' THEN
  -- sortie vers rebut uniquement
  INSERT INTO stock_movements (…, movement_type, …) VALUES (…, 'out', …);
END IF;
-- le cas 'passed' ne génère plus de mouvement
```

L'index unique de `STK-01` couvre ce cas aussi, dès lors que `reference_type` diffère (`goods_receipt` contre `quality_check`) — il faut donc **également** corriger la logique, l'index seul ne suffit pas ici.

**Effort.** 3 heures.

---

### `STK-03` — Les réservations s'appliquent à tous les dépôts

**Constat.** `118:106` met à jour `stock_quantities` sans filtrer sur l'entrepôt, alors que la clé métier de cette table est `(product_id, warehouse_id)` :

```sql
UPDATE stock_quantities
SET quantity_reserved = quantity_reserved + v_line.quantity, updated_at = now()
WHERE tenant_id = v_tid AND product_id = v_line.product_id;
```

Une entreprise à trois dépôts réserve trois fois la quantité commandée. La réservation elle-même est insérée avec `warehouse_id = NULL` (`118:100`), donc inexploitable pour une préparation de commande. Et aucun trigger ne libère la réservation à l'expédition : le stock reste gelé indéfiniment.

**Difficulté à traiter avant de corriger.** Ni `sales_orders` ni `sales_order_lines` ne portent de `warehouse_id`. Il n'existe donc aujourd'hui aucune donnée disant *où* réserver. Deux options :

- **Court terme.** Réserver sur l'entrepôt par défaut du dossier — à ajouter dans les paramètres.
- **Cible.** Ajouter `warehouse_id` sur la ligne de commande, avec repli sur l'entrepôt par défaut, et proposer à la saisie l'entrepôt disposant du stock.

**Correctif.**

```sql
-- 1. réserver sur un entrepôt déterminé
UPDATE stock_quantities
SET quantity_reserved = quantity_reserved + v_line.quantity
WHERE tenant_id = v_tid
  AND product_id = v_line.product_id
  AND warehouse_id = COALESCE(
        v_line.warehouse_id,
        (SELECT default_warehouse_id FROM company_settings WHERE tenant_id = v_tid)
      );

-- 2. libérer à l'expédition
CREATE OR REPLACE FUNCTION release_stock_on_shipment() … ;
CREATE TRIGGER release_stock_on_delivery
  AFTER UPDATE ON delivery_notes FOR EACH ROW
  EXECUTE FUNCTION release_stock_on_shipment();
```

**Effort.** 1 jour, dont la moitié pour l'ajout de `warehouse_id` sur les lignes de commande.

---

### `STK-04` — Deux colonnes pour la même réservation

**Constat — trouvé pendant la contre-vérification, absent des deux rapports.** `stock_quantities` possédait déjà une colonne `reserved_quantity` (`00_schema_dump.sql:4013`). La migration 118 en ajoute une seconde, `quantity_reserved` (`118:9`).

Les deux coexistent. Répartition des usages :

| Colonne | Références dans `src/` | Références dans `sql/` |
|---|---:|---:|
| `reserved_quantity` (ancienne) | 9 | 5 |
| `quantity_reserved` (nouvelle) | 4 | 9 |

**Le front lit majoritairement l'ancienne, les triggers écrivent dans la nouvelle. L'interface affichera donc toujours zéro réservation**, même une fois `STK-03` corrigé.

**Correctif.** Choisir `reserved_quantity`, déjà majoritaire côté interface, et supprimer la nouvelle après migration des valeurs :

```sql
UPDATE stock_quantities
SET reserved_quantity = COALESCE(quantity_reserved, 0)
WHERE COALESCE(quantity_reserved, 0) <> 0;

ALTER TABLE stock_quantities DROP COLUMN IF EXISTS quantity_reserved;
```

Puis corriger les 9 occurrences SQL. Ajouter une règle : **toute nouvelle colonne doit être vérifiée contre le schéma existant** — c'est le même motif que les numéros de migration en doublon.

**Effort.** 2 heures.

---

### `ACC-01` — Le report à nouveau embarque les classes 6 et 7

**Constat.** `generateCarryForward` (`accounting.ts:3071`) boucle sur toutes les lignes d'écriture sans aucun filtre de classe :

```ts
for (const entry of fecData) {
  for (const line of entry.journal_lines || []) {
    const key = line.account_general || line.account_code
    if (!key) continue
    // cumul de TOUS les comptes, sans distinction
```

En droit comptable français, **seuls les comptes de bilan — classes 1 à 5 — sont reportés à nouveau**. Les classes 6 et 7 doivent être soldées lors de l'affectation du résultat. Les reporter double les charges et les produits de l'exercice suivant et fausse l'intégralité du compte de résultat.

**Correctif.** Ne pas rafistoler le TypeScript : le RPC `close_fiscal_year` (migration 107) fait déjà le travail correctement, y compris les écritures de regroupement et l'affectation du résultat. Rediriger l'appel :

```ts
export async function generateCarryForward(fiscalYearId: string) {
  const { data, error } = await supabase.rpc('close_fiscal_year', {
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data
}
```

**Dépendance.** Le RPC 107 est actuellement écrasé par la migration 89 (`INF-01`). Corriger l'ordre des migrations **avant** de faire cette redirection, sinon on appelle la mauvaise version.

**Effort.** 2 heures, après `INF-01`.

---

### `UI-01` — L'écran propose un statut que la base refuse

**Constat — trouvé pendant la contre-vérification.** `DeliveryNotesPage.tsx:13` offre cinq statuts :

```ts
const statusKeys: string[] = ['pending', 'shipped', 'delivered', 'returned', 'cancelled']
```

La contrainte de la table n'en admet que quatre :

```sql
-- 00_schema_dump.sql:5551
CHECK (status = ANY (ARRAY['pending','delivered','returned','cancelled']))
```

**Sélectionner « expédié » lève une violation de contrainte.** Le message d'erreur brut de Postgres remonte à l'utilisateur.

**Correctif — trancher dans le bon sens.** Le statut `shipped` est métier-justifié : il distingue la marchandise partie de la marchandise reçue, ce qui est précisément ce qui manque pour gérer le stock en transit. Plutôt que de le retirer de l'écran, l'ajouter à la base :

```sql
ALTER TABLE delivery_notes DROP CONSTRAINT IF EXISTS delivery_notes_status_check;
ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_status_check
  CHECK (status = ANY (ARRAY['pending','shipped','delivered','returned','cancelled']));
```

**Attention à l'ordre.** Ajouter `'shipped'` réactive le scénario de double sortie décrit par l'audit Gemini. **Corriger `STK-01` d'abord**, le statut ensuite.

**Effort.** 1 heure, après `STK-01`.

---

## 5. Majeurs — `P1`

---

### `ACC-02` — Le lettrage se bloque à A999

**Constat.** `getNextLettrageCode` (`accounting.ts:1074`) cherche le maximum par tri de chaînes, puis incrémente avec un remplissage sur trois positions :

```ts
.order('lettrage_code', { ascending: false })
.limit(1)
…
return `${letter}${String(num).padStart(3, '0')}`
```

En tri lexicographique, `'A999' > 'A1000'`. Dès qu'un dossier atteint A999, la requête renvoie éternellement `'A999'`, et la fonction propose toujours `'A1000'` — qui ne devient jamais le nouveau maximum. Le compteur est gelé.

**Correctif.** Un compteur en base, comme pour la numérotation des pièces :

```sql
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS next_lettrage_seq bigint DEFAULT 1;

CREATE OR REPLACE FUNCTION next_lettrage_code()
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_seq bigint; v_tid uuid := current_tenant_id();
BEGIN
  UPDATE company_settings SET next_lettrage_seq = next_lettrage_seq + 1
  WHERE tenant_id = v_tid
  RETURNING next_lettrage_seq - 1 INTO v_seq;

  -- A001..A999, B001..B999, … puis AA001
  RETURN chr(65 + ((v_seq - 1) / 999)::int) || lpad((((v_seq - 1) % 999) + 1)::text, 3, '0');
END; $$;
```

Atomique, sans collision concurrente, et sans limite pratique.

**Effort.** 3 heures.

---

### `ACC-03` — Le lettrage n'exige aucun équilibre

**Constat.** `applyLettrage` (`accounting.ts:1046`) pose le code sur une liste d'identifiants sans vérifier que la somme des débits égale celle des crédits :

```ts
const { error } = await tud(supabase
  .from('journal_lines')
  .update({ lettrage_code: code, lettrage_date: today }), 'journal_lines', tid)
  .in('id', lineIds)
```

Un lettrage déséquilibré fait disparaître des lignes de la balance âgée sans que le solde du tiers ne bouge. C'est le contraire de ce que le lettrage sert à démontrer.

**Correctif — en base, pas côté client.**

```sql
CREATE OR REPLACE FUNCTION apply_lettrage(p_line_ids uuid[], p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_tid uuid := current_tenant_id(); v_d numeric; v_c numeric;
BEGIN
  SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0) INTO v_d, v_c
  FROM journal_lines WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  IF ABS(v_d - v_c) > 0.01 THEN
    RAISE EXCEPTION 'Lettrage déséquilibré : débit % ≠ crédit % (écart %)',
      v_d, v_c, ABS(v_d - v_c);
  END IF;

  UPDATE journal_lines
  SET lettrage_code = p_code, lettrage_date = CURRENT_DATE
  WHERE id = ANY(p_line_ids) AND tenant_id = v_tid;

  RETURN jsonb_build_object('lines', array_length(p_line_ids,1), 'amount', v_d);
END; $$;
```

Prévoir le lettrage partiel (`ACC-06` du plan de perfection) : quand l'écart est inférieur au seuil paramétré, générer l'écriture d'écart plutôt que de refuser.

**Effort.** 4 heures.

---

### `ACC-04` — Numérotation par horodatage

**Constat.** `EXT-${Date.now()}` (`accounting.ts:3019`) et `AN-${Date.now()}` (`:3098`). L'article A.47 A-1 du Livre des procédures fiscales exige une numérotation séquentielle continue sans rupture. Un horodatage en millisecondes n'est ni séquentiel au sens comptable, ni sans rupture, ni reproductible.

**Correctif.** Utiliser le compteur atomique déjà en place :

```ts
const number = await getNextEntryNumber('OD')  // s'appuie sur journals.next_number
```

`76:143` implémente déjà la numérotation atomique par journal. Il suffit de l'appeler.

**Effort.** 2 heures.

---

### `ACC-05` — Documents composés non atomiques

**Constat, avec une nuance.** L'audit Gemini cite `createJournalEntry` comme exemple. **C'est faux** : cette fonction passe par le RPC `post_journal_entry` (`accounting.ts:187`) et est atomique.

**Mais le fond est juste** pour les autres :

```ts
// sales.ts:106-112 — en-tête puis lignes, sans transaction
const { data: inv } = await supabase.from('invoices').insert(…).select().single()
// … si l'insertion suivante échoue, la facture reste en base sans lignes
await supabase.from('invoice_lines').insert(lines.map(…))
```

Même motif dans `generateExtourne` (`:3020`) et dans plusieurs fonctions d'achat.

**Correctif.** Reproduire le modèle de `post_journal_entry`, qui est correct et sert déjà de référence :

```sql
CREATE OR REPLACE FUNCTION create_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_tid uuid := current_tenant_id(); v_id uuid; v_line jsonb;
BEGIN
  INSERT INTO invoices SELECT * FROM jsonb_populate_record(NULL::invoices, p_invoice || jsonb_build_object('tenant_id', v_tid))
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

La fonction PL/pgSQL est implicitement transactionnelle : toute exception annule l'ensemble.

**Effort.** 2 jours pour les cinq documents composés (facture de vente, facture d'achat, devis, commande, bon de livraison).

---

### `STK-05` — Le contrôle de traçabilité bloquera les flux

**Constat, avec une nuance de sévérité.** `check_tracking_on_sm` (`118:198`) lève en `BEFORE INSERT` si `lot_id` est nul, et aucun trigger automatisé ne renseigne cette colonne.

L'audit Gemini classe ce point en bloquant immédiat. **Il est en réalité latent** : `products.tracking` vaut `'none'` par défaut (`118:167`). Le blocage se déclenche au premier article configuré en suivi de lot ou de série — c'est-à-dire à la première mise en service d'un client agroalimentaire, pharmaceutique ou mécanique.

**Correctif — dans cet ordre.**

1. Faire renseigner `lot_id` par les triggers automatisés avant d'activer le contrôle : production (lot de l'OF, déjà présent dans `manufacturing_orders.lot_number`), réception (lot saisi à la réception), livraison (lot prélevé selon la règle FEFO).
2. Tant que le point 1 n'est pas fait, dégrader le contrôle en avertissement plutôt qu'en exception :

```sql
IF v_tracking IN ('lot','serial') AND NEW.lot_id IS NULL AND NEW.serial_id IS NULL THEN
  -- tracer sans bloquer, le temps que les triggers soient équipés
  INSERT INTO stock_tracking_warnings (tenant_id, movement_id, product_id, created_at)
  VALUES (NEW.tenant_id, NEW.id, NEW.product_id, now());
END IF;
```

3. Basculer en exception une fois les triggers équipés, et vider la table d'avertissements.

**Effort.** 1 jour pour la dégradation contrôlée, 3 jours pour l'équipement complet.

---

### `ACH-01` — Le rapprochement à trois voies apparie au hasard

**Constat, avec une nuance.** L'audit Gemini affirme que chaque ligne de facture est appariée à la première ligne de commande. **C'est vrai seulement en repli** : `86:168` privilégie le lien explicite `purchase_order_line_id` quand il existe.

**Mais le défaut demeure sur deux chemins :**

```sql
-- 86:174 — repli par produit
SELECT * INTO v_po_line FROM purchase_order_lines
WHERE purchase_order_id = v_po_id AND product_id = v_inv_line.product_id
LIMIT 1;

-- 86:198 — ligne de réception, TOUJOURS en LIMIT 1, sans option de lien explicite
SELECT * INTO v_gr_line FROM goods_receipt_lines
WHERE goods_receipt_id = v_gr_id AND product_id = v_inv_line.product_id
LIMIT 1;
```

Si une commande porte deux lignes du même article — échéances ou tarifs distincts —, la quantité n'est pas déduite. Deux lignes de facture de 10 unités contre une commande d'une seule ligne de 10 unités passent en `matched`, autorisant la double facturation sans alerte.

**Correctif — consommer les reliquats.**

```sql
-- table temporaire des reliquats, remplie avant la boucle
CREATE TEMP TABLE po_remaining ON COMMIT DROP AS
SELECT id, product_id, quantity AS qty_left, unit_price
FROM purchase_order_lines
WHERE purchase_order_id = v_po_id AND tenant_id = NEW.tenant_id;

-- dans la boucle, prendre la plus ancienne ligne non épuisée
SELECT * INTO v_po_line FROM po_remaining
WHERE product_id = v_inv_line.product_id AND qty_left > 0
ORDER BY id LIMIT 1;

-- puis décrémenter le reliquat
UPDATE po_remaining SET qty_left = qty_left - LEAST(qty_left, v_inv_line.quantity)
WHERE id = v_po_line.id;
```

Même traitement pour `goods_receipt_lines`.

**Effort.** 1 jour.

---

### `ACH-02` — Les écarts d'une ligne contaminent la suivante

**Constat.** `v_price_variance` et `v_quantity_variance` sont déclarés hors de la boucle (`86:123-124`) et ne sont jamais réinitialisés à chaque itération. Seul `v_line_status` l'est (`:163`). Les valeurs écrites dans le détail JSON (`:221-222`) peuvent donc appartenir à une ligne précédente.

**Correctif.** Deux lignes, à l'ouverture de la boucle :

```sql
v_line_status := 'matched';
v_price_variance := 0;      -- ajouter
v_quantity_variance := 0;   -- ajouter
```

**Effort.** 15 minutes.

---

### `QUA-01` — Les tests d'intégration ne couvrent pas les zones défaillantes

**Constat.** Le job `db-integration` est la meilleure décision structurelle des derniers jours. Ses 14 scénarios (`102_trigger_tests.sql`) vérifient le tenant automatique, les paiements, l'immuabilité, l'équilibre, la chaîne stock, la production, la réception, la paie, l'isolation, les périodes closes et l'escalade de rôle.

**Aucun ne touche** les bons de livraison, les contrôles qualité, les lots, le lettrage, NF-525 ni les réservations — c'est-à-dire exactement les six zones où se concentrent les défauts de ce registre.

Et les scénarios existants sont trop lâches : le test 13 vérifie qu'une facture validée produit une écriture équilibrée en `posted` avec au moins trois lignes. C'est vrai avec ou sans comptes auxiliaires, avec ou sans TVA ventilée. **La CI reste verte pendant que `INF-01` annule trois chantiers.**

**Correctif.** Voir [section 9](#9-le-test-qui-manque).

**Effort.** 2 jours.

---

### `QUA-02` — Les tests RLS couvrent 4 tables sur 530

**Constat.** `105_rls_tests.sql` vérifie l'isolation sur `tenants`, `customers`, `products` et `journal_entries`. Le principe est en place, mais 2 279 politiques restent non vérifiées.

**Correctif — rendre le test générique plutôt qu'énumératif.**

```sql
DO $$
DECLARE r RECORD; v_count int;
BEGIN
  FOR r IN
    SELECT c.table_name FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_name = c.table_name AND t.table_schema = 'public'
    WHERE c.column_name = 'tenant_id' AND t.table_type = 'BASE TABLE'
  LOOP
    -- se placer dans le tenant A, compter les lignes du tenant B
    PERFORM set_config('request.headers',
      json_build_object('x-tenant-id', v_tenant_a)::text, true);
    EXECUTE format('SELECT count(*) FROM %I WHERE tenant_id = $1', r.table_name)
      INTO v_count USING v_tenant_b;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'FUITE RLS sur % : % lignes du tenant B visibles', r.table_name, v_count;
    END IF;
  END LOOP;
END $$;
```

Cinquante lignes couvrent les 530 tables, et toute table future est couverte à sa création.

**Effort.** 1 jour.

---

### `DAT-01` — 303 requêtes non bornées

**Constat.** Mesure exacte au 12 septembre : **303** `select('*')` pour **29** `.limit()` et **2** `.range()`, sur 1 057 appels `.select()`. L'audit Gemini annonce « plus de 1 040 » — le chiffre est faux, la substance est juste.

Deux risques : la troncature silencieuse à la limite PostgREST, qui produit une balance fausse sans erreur, et l'export FEC incomplet, fiscalement sanctionnable.

**Correctif — par ordre de gravité, pas en bloc.**

1. **Les états réglementaires d'abord.** `getFECData` et `getSIGData` : pagination par lots avec assemblage, ou génération intégrale côté serveur.
2. **Les listes transactionnelles ensuite.** Type de retour uniforme :
   ```ts
   interface Page<T> { rows: T[]; total: number; page: number; pageSize: number }
   ```
3. **Le garde-fou en CI.** Refuser toute fonction de `queries/` qui interroge une table transactionnelle sans `.range()`.

**Effort.** 1 semaine, dont 1 jour pour le point 1 seul.

---

### `FRT-01` — Les briques neuves ne sont appelées par aucun écran

**Constat.** Sur les 96 fonctions SQL créées dans les migrations 100 à 130, **41 sont appelées depuis le front**. Et parmi les enveloppes TypeScript écrites, plusieurs n'ont aucun appelant :

| Brique | État | Écrans qui l'appellent |
|---|---|---:|
| `resolvePrice` (`sales.ts:15`) | RPC + enveloppe écrites | **0** |
| `bankParsers.ts` (426 lignes, 3 formats) | écrit et testé | **0** (seul son test l'importe) |
| `hasPermission` | RPC + enveloppe écrites | **0** |
| `importOpeningBalance`, `importInitialStock`, `importEmployeeWithCumuls` | RPC écrites | **0** |

C'est le motif « table présente, jamais branchée » du plan de perfection, reproduit sur le code neuf.

**Correctif.** Traiter par valeur métier décroissante : `resolvePrice` dans les formulaires de ligne (devis, commande, facture), `bankParsers` dans `BankStatementImportPage`, `hasPermission` dans les gardes de route, les fonctions d'import dans un assistant.

Et poser le garde-fou `SOC-05` du plan de perfection : un script CI qui refuse une table métier ou une RPC sans consommateur.

**Effort.** 2 semaines.

---

## 6. Moyens — `P2`

---

### `SQL-01` — La migration 127 est une déclaration de schéma

**Constat.** 651 lignes, 27 tables créées, **zéro fonction et zéro trigger**, pour un en-tête annonçant 24 familles de chantiers (PRJ, BI, UX, CNF, ADM, GED, NOT, API, PTL, ONB, CRM, GRP, RH, IMP). 22 des 27 tables ne sont référencées nulle part dans `src/`.

**Correctif.** Reprendre chantier par chantier, en commençant par les deux plus visibles : `PRJ-01` (chemin critique, les colonnes `early_start`, `total_slack`, `is_critical_path` existent déjà, il manque le calcul) et `NOT-01` (notifications unifiées). Ne pas créer de table sans la fonction qui l'alimente et l'écran qui la lit.

**Effort.** 4 semaines pour l'ensemble.

---

### `ASY-01` — La file de webhooks vit en mémoire

**Constat.** `outgoing-webhooks/index.ts:18` déclare un tableau au niveau du module, et relance par `setTimeout` (`:79`). Les fonctions Deno sont des conteneurs éphémères : dès la réponse HTTP retournée, le conteneur est gelé ou détruit, et la file est perdue.

Le commentaire du code l'admet lui-même : *« en production, utiliser pg_cron + table »*.

**Correctif.**

```sql
CREATE TABLE IF NOT EXISTS webhook_delivery_queue (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  endpoint_id uuid NOT NULL,
  event text NOT NULL,
  payload jsonb NOT NULL,
  attempts int DEFAULT 0,
  next_attempt_at timestamptz DEFAULT now(),
  delivered_at timestamptz,
  last_error text
);
CREATE INDEX ON webhook_delivery_queue (next_attempt_at) WHERE delivered_at IS NULL;

SELECT cron.schedule('webhook-delivery', '* * * * *', $$
  SELECT net.http_post(url, payload::text) FROM webhook_delivery_queue
  WHERE delivered_at IS NULL AND next_attempt_at <= now() LIMIT 50;
$$);
```

La migration 129 a déjà créé une table `webhook_queue` : vérifier si elle couvre ce besoin avant d'en créer une autre — même vigilance que pour `STK-04`.

**Effort.** 2 jours.

---

### `ASY-02` — Aucun filtrage SSRF sur les webhooks

**Constat.** Les URL cibles ne sont pas filtrées : zéro occurrence de `hostname`, `127.0.0.1` ou `169.254` dans la fonction. Un utilisateur peut enregistrer un point de terminaison pointant vers le réseau interne ou vers le service de métadonnées de l'infrastructure.

**Correctif — à la validation de l'URL, pas à l'envoi.**

```ts
function isAllowedWebhookUrl(raw: string): boolean {
  let u: URL
  try { u = new URL(raw) } catch { return false }
  if (u.protocol !== 'https:') return false
  const h = u.hostname
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
  // IPv4 privées, boucle locale, lien-local, métadonnées cloud
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(h)) return false
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return false
  if (h === '::1' || h.startsWith('fd') || h.startsWith('fe80:')) return false
  return true
}
```

Revalider aussi après résolution DNS, pour couvrir la réattribution de nom.

**Effort.** 4 heures.

---

### `PRJ-01` — `_skip_cascade` n'est jamais lu

**Constat.** Le drapeau est posé 8 fois dans `85_project_management_triggers.sql`, et la forme `IF NEW._skip_cascade` n'apparaît nulle part dans les 138 migrations. Chaque mise à jour de sous-tâche émet donc deux `UPDATE` sur le parent, pour rien.

**Correctif — choisir.**

- **Le supprimer** si la cascade n'est pas récursive : retirer la colonne et les 8 occurrences.
- **L'implémenter** si elle l'est : ajouter en tête de chaque trigger concerné

```sql
IF COALESCE(NEW._skip_cascade, false) THEN RETURN NEW; END IF;
```

La seconde option est probablement la bonne — le drapeau a été introduit pour une raison, et la cascade parent-enfant sur des tâches imbriquées est un cas classique de boucle.

**Effort.** 2 heures.

---

### `PRF-01` — Deux jeux de triggers d'équilibre tournent en parallèle

**Constat.** La migration 128 supprime `check_journal_entry_balance` et crée trois triggers `FOR EACH STATEMENT` (`_ins`, `_upd`, `_del`). La migration 76, qui s'exécute plus tard (`INF-01`), supprime un trigger déjà disparu puis recrée l'ancien `FOR EACH ROW`.

Résultat : **les quatre triggers sont actifs**. Double validation à chaque ligne, et le gain de performance visé par la 128 est annulé.

**Correctif.** Se résout en grande partie avec `INF-01`. Vérifier ensuite explicitement :

```sql
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'journal_lines'::regclass AND NOT tgisinternal;
-- doit retourner exactement : check_journal_entry_balance_ins/_upd/_del
--                             + prevent_posted_line_modification
--                             + set_tenant_id_journal_lines
```

**Effort.** 1 heure, après `INF-01`.

---

### `TS-01` — `any` progresse malgré le mode strict

**Constat.** Les occurrences passent de 1 884 à **1 991**. C'est le résultat attendu d'une activation rapide : les erreurs ont été éteintes par annotation plutôt que par typage. `strictNullChecks` ne protège rien sur une valeur typée `any`.

**Correctif — plafond décroissant plutôt que campagne.**

```js
// scripts/check-any-budget.mjs, appelé en CI
const BUDGET = 1991;  // à baisser à chaque palier, jamais à monter
const count = countAnyOccurrences('src');
if (count > BUDGET) {
  console.error(`❌ ${count} occurrences de 'any' (plafond : ${BUDGET})`);
  process.exit(1);
}
```

Commencer par `src/lib/queries/`, où `supabase gen types typescript` permet de remplacer la plupart des `as any[]` mécaniquement.

**Effort.** 1 semaine pour le premier palier.

---

## 7. Constats non retenus

Trois affirmations de l'audit Gemini ne se reproduisent pas sur le code actuel. Elles sont listées ici pour éviter qu'on les traite deux fois.

### `createJournalEntry` serait non atomique — **inexact**

La fonction passe par le RPC `post_journal_entry` (`accounting.ts:187`), qui insère l'en-tête et les lignes dans un seul bloc PL/pgSQL. Elle est atomique, et sert de modèle à `ACC-05`.

### Fuite multi-tenant dans l'API publique — **corrigé le 12/09 à 02:29**

Les trois sous-constats sont désormais faux : `.eq("tenant_id", tenantId)` sur toutes les lectures, `body.tenant_id = tenantId` forcé (`:225`), clé hachée en SHA-256 (`:155`). Le commentaire du code porte la référence `SEC-01` du rapport Gemini — le correctif a été appliqué en réponse à l'audit.

**Point de vigilance.** Ce correctif est dans le dépôt et **ne peut pas être déployé** tant que `INF-02` n'est pas réglé.

### Double sortie de stock par `draft → shipped → delivered` — **scénario impossible en l'état**

La contrainte de `delivery_notes` n'admet pas `'shipped'` (voir `UI-01`). Le défaut d'idempotence est réel et traité en `STK-01`, mais par un autre chemin (`delivered → returned → delivered`, reprises manuelles, imports).

---

## 8. Plan d'exécution

### Jour 1 — Débloquer

| Réf | Action | Effort |
|---|---|---|
| `INF-01` | Trier les migrations par numéro | 15 min |
| `INF-02` | Réparer le build | 30 min |
| `ACH-02` | Réinitialiser les variables d'écart | 15 min |
| `INF-01b` | Rejouer sur base neuve, vérifier les 10 fonctions par `pg_get_functiondef` | 2 h |
| `PRF-01` | Vérifier qu'un seul jeu de triggers d'équilibre subsiste | 1 h |
| `STK-04` | Fusionner les deux colonnes de réservation | 2 h |

**Sortie de journée.** Le build passe, le déploiement redémarre, les correctifs des trois derniers jours s'appliquent réellement.

---

### Jours 2 et 3 — Fiabiliser les flux

| Réf | Action | Effort |
|---|---|---|
| `STK-01` | Idempotence des mouvements de stock : condition + index unique | 2 h |
| `STK-02` | Trancher réception contre contrôle qualité | 3 h |
| `STK-03` | Réservations par dépôt, libération à l'expédition | 1 j |
| `UI-01` | Ajouter `'shipped'` à la contrainte, **après** `STK-01` | 1 h |
| `NF-02` | Verrou consultatif sur la chaîne NF-525 | 1 h |
| `NF-01` | Vérification du chaînage et continuité des identifiants | 3 h |
| `ACC-01` | Rediriger le report à nouveau vers `close_fiscal_year` | 2 h |

**Sortie de phase.** Les dix bloquants sont soldés.

---

### Semaines 1 et 2 — Verrouiller

| Réf | Action | Effort |
|---|---|---|
| `QUA-01` | Étendre les tests d'intégration aux six zones découvertes | 2 j |
| `QUA-02` | Rendre les tests RLS génériques | 1 j |
| `ACC-02` | Compteur de lettrage en base | 3 h |
| `ACC-03` | Contrôle d'équilibre du lettrage en RPC | 4 h |
| `ACC-04` | Numérotation séquentielle des extournes et à-nouveaux | 2 h |
| `ACH-01` | Consommation des reliquats au rapprochement | 1 j |
| `STK-05` | Dégrader le contrôle de traçabilité, puis équiper les triggers | 4 j |
| `ACC-05` | Atomicité des cinq documents composés | 2 j |
| `DAT-01` | Pagination des états réglementaires d'abord | 1 j |

---

### Au-delà

`FRT-01` (câblage des briques neuves, 2 semaines), `SQL-01` (implémenter la migration 127, 4 semaines), `ASY-01` et `ASY-02` (webhooks, 2 jours), `TS-01` (plafond `any`, 1 semaine), `PRJ-01` (2 heures), et la suite du plan de perfection.

---

## 9. Le test qui manque

**Dix-sept des vingt-six défauts de ce registre se seraient manifestés au premier scénario métier exécuté contre une vraie base.**

| Défaut | Ce qu'un test aurait vu |
|---|---|
| `INF-01` | La fonction en base ne contient pas `account_tiers` |
| `INF-02` | `npm run build` retourne un code non nul |
| `NF-01` | Supprimer un maillon puis vérifier → `chain_valid` reste `true` |
| `NF-02` | Deux écritures concurrentes → deux lignes avec le même `previous_hash` |
| `STK-01` | Deux transitions de statut → deux mouvements pour une livraison |
| `STK-02` | Réception + contrôle → stock crédité deux fois |
| `STK-03` | Une commande sur trois dépôts → 3× la quantité réservée |
| `STK-04` | Le front lit `reserved_quantity`, qui reste à zéro |
| `STK-05` | Article en suivi de lot → l'OF lève une exception |
| `ACC-01` | Après clôture, les classes 6 et 7 apparaissent dans le journal AN |
| `ACC-02` | Au 1000ᵉ lettrage, le code proposé reste `A1000` |
| `ACC-03` | Lettrer 100 au débit contre 90 au crédit est accepté |
| `ACC-05` | Ligne invalide → la facture reste en base sans lignes |
| `ACH-01` | Deux lignes du même article → double facturation en `matched` |
| `ACH-02` | L'écart de la ligne 1 apparaît sur la ligne 2 |
| `UI-01` | Passer un BL en `shipped` → violation de contrainte |
| `PRF-01` | `pg_trigger` retourne quatre triggers au lieu de trois |

**Le meilleur investissement n'est pas de corriger ces dix-sept points — c'est d'écrire les dix-sept tests qui les auraient trouvés.** Ils empêchent les dix-sept suivants.

### Squelette à ajouter à `102_trigger_tests.sql`

```sql
-- TEST 15 : idempotence des mouvements de stock (STK-01)
DO $$
DECLARE v_bl uuid; v_count int;
BEGIN
  INSERT INTO delivery_notes (…, status) VALUES (…, 'pending') RETURNING id INTO v_bl;
  INSERT INTO delivery_note_lines (…) VALUES (…);
  UPDATE delivery_notes SET status = 'delivered' WHERE id = v_bl;
  UPDATE delivery_notes SET status = 'returned'  WHERE id = v_bl;
  UPDATE delivery_notes SET status = 'delivered' WHERE id = v_bl;

  SELECT count(*) INTO v_count FROM stock_movements
  WHERE reference_type = 'delivery_note' AND reference_id = v_bl;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'TEST 15 FAIL : % mouvements pour une livraison, attendu 1', v_count;
  END IF;
END $$;

-- TEST 16 : le chaînage NF-525 détecte une suppression (NF-01)
DO $$
DECLARE v_mid bigint; v_res jsonb;
BEGIN
  PERFORM log_nf525_event('test', 'invoice', gen_random_uuid(), '{}'::jsonb);
  PERFORM log_nf525_event('test', 'invoice', gen_random_uuid(), '{}'::jsonb);
  PERFORM log_nf525_event('test', 'invoice', gen_random_uuid(), '{}'::jsonb);

  SELECT id INTO v_mid FROM nf525_event_log ORDER BY id DESC OFFSET 1 LIMIT 1;
  DELETE FROM nf525_event_log WHERE id = v_mid;

  v_res := verify_nf525_chain(NULL, NULL);
  IF (v_res->>'chain_valid')::boolean THEN
    RAISE EXCEPTION 'TEST 16 FAIL : suppression non détectée, la chaîne se dit valide';
  END IF;
END $$;

-- TEST 17 : les comptes auxiliaires sont renseignés (INF-01)
DO $$
DECLARE v_inv uuid; v_tiers text;
BEGIN
  INSERT INTO invoices (…, status) VALUES (…, 'draft') RETURNING id INTO v_inv;
  UPDATE invoices SET status = 'validated' WHERE id = v_inv;

  SELECT jl.account_tiers INTO v_tiers
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.invoice_ref = (SELECT number FROM invoices WHERE id = v_inv)
    AND jl.account_general LIKE '411%';

  IF v_tiers IS NULL THEN
    RAISE EXCEPTION 'TEST 17 FAIL : compte auxiliaire non renseigné — migration 108 écrasée ?';
  END IF;
END $$;
```

Les quatorze autres suivent le même modèle : **exécuter le scénario métier complet, puis vérifier le résultat, jamais la présence du code.**

---

*Registre établi le 12 septembre 2026 sur la branche `commercial-hr-paie`. Chaque constat a été reconfronté au code au moment de la rédaction, par examen direct des fichiers cités et vérification des conditions, des ordres de tri et des schémas de table. Les correctifs proposés n'ont pas été exécutés contre une base : ils indiquent la direction, pas un correctif prêt à appliquer.*
