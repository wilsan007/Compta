# Audit des modules hors comptabilité générale — 23 septembre 2026

Cet audit couvre la **phase 3** du [reste-à-faire](RESTE-A-FAIRE-2026-09-22.md) : les modules qui
existent mais **n'ont jamais été vérifiés en exécutant un scénario chiffré**. Les vagues V1 à V3 et
la phase 1 (R-01 à R-17) ont traité la saisie, la clôture, les états financiers, et une première
passe sur ventes / achats / paie / banque. Tout ce qui suit est **nouveau**.

> **Les 18 premiers défauts (S-01 → S-11, RH-01 → RH-04, SUP-01 → SUP-03) sont corrigés** —
> migrations **240 → 244** du 24 septembre 2026, 31 scénarios chiffrés vus rouges avant et verts
> après, 45 suites de CI vertes. Voir [§ Correctifs appliqués](#correctifs-appliqués--migrations-240--244)
> et, pour ce qui reste ouvert, [§ Ce que ces correctifs ne font pas](#ce-que-ces-correctifs-ne-font-pas-inscrit-au-registre).

## Méthode

- Base neuve montée pour l'audit : schéma + **203 migrations, 0 erreur** (conteneur `pg_audmod`),
  avec un PostgREST réel devant elle.
- Chaque défaut est **prouvé** : soit par l'exécution d'un scénario chiffré (`doc/audit/scenarios/`),
  soit par une requête sur le catalogue PostgreSQL. Les défauts établis par simple lecture du code
  sont signalés « lecture ».
- Un outil neuf a été écrit pour cet audit : un **scanner des colonnes écrites** par le code
  (`.insert()` / `.update()`), confrontées au schéma réel. Le contrôle CI existant
  (`check-embeds.mjs`) ne vérifie que les **lectures** : les 1 495 requêtes de lecture passent,
  mais **21 écritures visent des colonnes qui n'existent pas**. C'est l'angle mort qui explique
  la moitié des défauts bloquants ci-dessous.

## Cotation

| Niveau | Sens |
|---|---|
| 🔴 **Bloquant** | Perte de données, faux montants en comptabilité, ou fonction qui ne marche pas du tout |
| 🟠 **Grave** | Résultat faux ou incohérent, sans perte définitive |
| 🟡 **Défaut** | Imprécision, oubli, doublon, code mort |

---

## 1. Tableau de bord

**69 défauts** : **32 bloquants**, 32 graves, 5 défauts mineurs.

| # | Module | Défaut | Niveau | Preuve |
|---|---|---|:---:|:---:|
| **S-01** | Achats → stock | La réception n'alimente pas le stock par dépôt | 🔴 | exécution |
| **S-02** | Achats → stock | La réception entre à coût nul : aucune couche de valorisation | 🔴 | exécution |
| **S-03** | Achats → compta | La réception ne produit **aucune écriture** | 🔴 | exécution |
| **S-04** | Achats | `goods_receipts` n'a pas de colonne dépôt | 🔴 | structure |
| **S-05** | Ventes → stock | La livraison décrémente le global, pas le dépôt | 🔴 | exécution |
| **S-06** | Ventes → stock | La sortie ne consomme aucune couche de valorisation | 🔴 | exécution |
| **S-07** | Ventes | Les réservations ne sont **jamais** libérées | 🔴 | exécution |
| S-08 | Stock | `increment/decrement_stock` se fient à `current_tenant_id()` | 🟠 | lecture |
| S-09 | Stock | `increment_stock` perd la quantité en cas de course | 🟠 | lecture |
| S-10 | Stock | Comptes 310000/603000 codés en dur | 🟠 | lecture |
| S-11 | Stock | La traçabilité lot/série est désactivée en pratique | 🟠 | lecture |
| S-12 | Stock | Un BL annulé puis réexpédié sort le stock deux fois | 🟡 | lecture |
| S-13 | Achats | Un contrôle qualité en échec rebute la quantité **totale** reçue | 🟠 | structure |
| **M01-01** | Multi-devises | Une facture en devise est comptabilisée **au montant en devise** | 🔴 | exécution |
| **M01-02** | Multi-devises | `journal_lines` n'a aucune colonne de devise | 🔴 | structure |
| M01-03 | Multi-devises | Écart de change et réévaluation : écrans alimentés par personne | 🟠 | structure |
| IMMO-01 | Immobilisations | Deux moteurs d'amortissement qui se contredisent | 🟠 | lecture |
| **IMMO-02** | Immobilisations | « Calculer les amortissements » ne comptabilise rien | 🔴 | lecture |
| IMMO-03 | Immobilisations | Recalcul écrasant la valeur de clôture | 🟠 | lecture |
| IMMO-04 | Immobilisations | Les 3 méthodes d'amortissement proposées n'ont aucun effet | 🟠 | lecture |
| IMMO-05 | Immobilisations | Dotations en échec silencieusement sautées | 🟠 | lecture |
| **ANA-01** | Analytique | Les deux triggers analytiques sont **vides** | 🟠 | structure |
| **ANA-02** | Analytique | Aucune écriture générée ne porte de section analytique | 🔴 | structure |
| **BUD-01** | Budgets | Le réalisé ignore l'exercice : il cumule depuis l'origine | 🔴 | lecture |
| BUD-02 | Budgets | À-nouveaux, clôture et brouillons comptés dans le réalisé | 🟠 | lecture |
| BUD-03 | Budgets | Les engagements ne sont jamais libérés → double déduction | 🟠 | structure |
| BUD-04 | Budgets | N+1 : deux requêtes par budget | 🟡 | lecture |
| **RH-01** | RH (18 emplacements) | Le nom du salarié s'affiche « null null » | 🔴 | structure |
| **RH-02** | Paie | Deux `calculate_payslip` : la version à taux fictifs est atteignable | 🔴 | structure |
| RH-03 | Temps → paie | Heures dupliquées à chaque réapprobation | 🟠 | lecture |
| RH-04 | Temps → paie | Heures supplémentaires calculées **trois fois**, de trois façons | 🟠 | lecture |
| RH-05 | Paie | Quatre conventions mensuelles contradictoires (4,33 / 30 / 21 / 151,67) | 🟠 | lecture |
| **RH-06** | Paie | L'import des éléments variables **échoue 5 mois sur 12** | 🔴 | exécution |
| **RH-07** | Notes de frais | Intégrées en paie pour un montant **nul** | 🔴 | structure |
| RH-08 | Notes de frais | Ni TVA récupérable, ni écriture 625x/421 | 🟠 | structure |
| RH-09 | Congés | Un congé à cheval sur deux mois est omis | 🟠 | lecture |
| RH-10 | Paie | Titres restaurant : relancer l'import double les éléments | 🟠 | lecture |
| **SUP-01** | Suppressions | Supprimer un salarié efface ses bulletins de paie | 🔴 | exécution |
| **SUP-02** | Suppressions | Supprimer un compte bancaire efface toutes ses opérations | 🔴 | exécution |
| SUP-03 | Suppressions | Supprimer un produit efface son historique de mouvements | 🟠 | exécution |
| **EF-01** | Relances (M-14) | Le cron échoue dès la première facture (`.single()` sur 0 ligne) | 🔴 | exécution |
| **EF-02** | Relances | La relance n'est jamais enregistrée → **renvoyée tous les jours** | 🔴 | structure |
| **EF-03** | Synchro bancaire | Le bouton « Synchroniser » ne synchronise rien | 🔴 | lecture |
| **EF-04** | Synchro bancaire | La fonction Edge insère une colonne inexistante et dit « succès » | 🔴 | exécution |
| **EF-05** | Facture électronique | La soumission n'est jamais enregistrée → double envoi | 🔴 | structure |
| EF-06 | Facture électronique | L'écran ne soumet rien : il génère et télécharge | 🟠 | lecture |
| EF-07 | Signature | La demande de signature n'est jamais enregistrée | 🟠 | structure |
| EF-08 | Webhooks | Journal de livraison et replanification : colonnes inexistantes | 🟠 | structure |
| **ISO-01** | Isolation | Un utilisateur écrit dans la société **voisine** via un trigger | 🔴 | exécution |
| **ISO-02** | Isolation | 189 tables acceptent une clé étrangère vers une autre société | 🔴 | exécution |
| **ISO-03** | Droits | 38 gardes de permission **annulées** par une politique jumelle | 🔴 | structure |
| ISO-04 | Base | 326 politiques RLS en double, 11 index en double | 🟡 | structure |
| **PERM-01** | Droits (M-18) | Les rôles « lecteur » et « auditeur » ne sont pas opposables | 🔴 | exécution |
| **POS-01** | Caisse | Un ticket « inaltérable » se réécrit de 120 € à 12 € | 🔴 | exécution |
| POS-02 | Caisse | Les lignes de ticket se suppriment librement | 🔴 | exécution |
| POS-03 | Caisse | Pas d'unicité du numéro de ticket par terminal | 🟠 | structure |
| POS-04 | Caisse | `created_at` fourni par le client entre dans le hachage | 🟠 | lecture |
| **TVA-01** | TVA (M-10) | La « télétransmission » EDI-TVA n'envoie rien | 🔴 | lecture |
| PROD-01 | Production | Nomenclature explosée sur **un seul niveau** | 🟠 | lecture |
| PROD-02 | Production | Ni rebuts ni écarts de coût ; `qty_produced` forcée | 🟠 | lecture |
| PROD-03 | Production | Écriture datée du jour de clôture, pas de la production | 🟡 | lecture |
| **PROJ-01** | Projets (M-17) | La refacturation des temps **n'existe pas** | 🔴 | lecture |
| PROJ-02 | Projets | Avancement : moyenne non pondérée, deux calculs concurrents | 🟠 | lecture |
| PROJ-03 | Projets | Une tâche peut être son propre parent (aucun anti-cycle) | 🟠 | exécution |
| **SAGE-01** | Import (M-19) | Les écritures importées restent en brouillon, sans contrôle d'équilibre | 🔴 | lecture |
| SAGE-02 | Import | Les soldes du plan comptable sont **écrasés**, pas cumulés | 🟠 | lecture |
| SAGE-03 | Import | Import partiel sans transaction : comptabilité déséquilibrée | 🟠 | lecture |
| ANA-03 | Analytique | La balance analytique porte sur tout l'historique | 🟠 | lecture |
| FEC-01 | FEC (M-11) | Une 2ᵉ implémentation du FEC, à 9 colonnes sur 18 | 🟡 | structure |

---

## 2. Stock, achats et ventes — la chaîne est rompue à la réception

### S-01 à S-04 🔴 — Une réception de marchandises n'entre nulle part

**Scénario** (`scenarios/M06_achats_reception_stock.sql`) : commande de 100 unités à 10 €,
bon de réception à 100 unités, passage au statut `received`.

| Ce qui devrait se produire | Ce qui se produit |
|---|---|
| Stock du dépôt : +100 | **0 ligne** dans `stock_quantities` |
| Couche de valorisation : 1 000 € | **0 couche** |
| Écriture : 310000 au débit, 408/401 au crédit | **0 écriture** |
| `products.stock_quantity` : +100 | 100 ✅ (seul point juste) |

Trois causes qui se cumulent :

1. **`goods_receipts` n'a aucune colonne `warehouse_id`** (S-04). Le trigger
   `create_stock_on_goods_receipt` insère donc un mouvement sans dépôt.
2. `increment_stock` ne touche `stock_quantities` **que si** `p_warehouse_id IS NOT NULL` ;
   `update_cump_on_movement` cherche `warehouse_id = NEW.warehouse_id`, ce qui n'est jamais vrai
   quand il est nul. Le stock par dépôt et le CUMP sont donc contournés (S-01).
3. **`goods_receipt_lines` ne porte aucun prix** : le trigger insère `unit_cost` à sa valeur par
   défaut, 0. `create_valuation_layer_on_entry` exige `unit_cost > 0` (S-02) et
   `create_journal_on_stock_movement` sort silencieusement quand le montant est nul (S-03).

**Conséquence** : tous les écrans de stock par dépôt (`StockQuantitiesPage`, interrogation
d'article, réapprovisionnement, MRP) restent vides, et **aucun achat n'entre en comptabilité de
stock**. Le prix d'achat existe pourtant sur `purchase_order_lines` — il n'est jamais repris.

### S-05 à S-07 🔴 — La livraison laisse trois vérités contradictoires

**Scénario** (`scenarios/M06_ventes_livraison_reservation.sql`) : entrée propre de 100 unités à
10 € (avec dépôt et coût), commande de 40 confirmée, bon de livraison de 40 expédié puis livré.

| Mesure | Après expédition | Attendu |
|---|---|---|
| `products.stock_quantity` | **60** | 60 |
| `stock_quantities.quantity` (dépôt) | **100** | 60 |
| Couches de valorisation restantes | **100** | 60 |
| Réservation active après « livré » | **1** | 0 |
| `reserved_quantity` | **40** | 0 |
| Disponible affiché | **60** | 100 |

- **S-05** : `create_stock_out_on_delivery` n'indique pas de dépôt ; `decrement_stock` décrémente
  le stock global mais ne trouve aucune ligne de dépôt. Les deux chiffres divergent définitivement.
- **S-06** : `consume_valuation_layers_on_exit` filtre sur
  `COALESCE(warehouse_id, NEW.warehouse_id) = NEW.warehouse_id`, qui vaut `NULL` — donc faux —
  quand le mouvement n'a pas de dépôt. **Aucune couche n'est jamais consommée** : la valeur du
  stock au bilan ne baisse jamais.
- **S-07** : `release_stock_on_delivery` est un trigger sur **`sales_orders`** qui attend
  `status = 'delivered'`. Or **rien, nulle part, ne passe une commande à `delivered`** : la
  livraison écrit `delivery_status` et `fully_delivered`, jamais `status`. Les réservations
  s'accumulent ; `quantity_available` (colonne générée `quantity - reserved_quantity`) finit par
  bloquer toute vente.

### S-08 à S-13 — Défauts de second rang sur le stock

- **S-08 🟠** `increment_stock` et `decrement_stock` lisent `current_tenant_id()` au lieu du
  `tenant_id` du mouvement. Appelées depuis un trigger sous service-role (cron, fonction Edge),
  elles lèvent « Aucun tenant actif » ; et si le contexte désigne une autre société, les `UPDATE`
  filtrés ne touchent rien : **le mouvement est enregistré, le stock ne bouge pas**, sans erreur.
- **S-09 🟠** `increment_stock` crée la ligne de dépôt avec `ON CONFLICT DO NOTHING`. En cas de
  course, la quantité entrante est **perdue** au lieu d'être ajoutée.
- **S-10 🟠** `create_journal_on_stock_movement` code en dur `310000` et `603000` et **ignore
  `products.stock_account_code`**, qui existe et est saisissable. Bloque aussi la localisation
  (plan comptable par pays).
- **S-11 🟠** `check_tracking_on_stock_movement` s'exécute **avant** `set_tenant_id` (ordre
  alphabétique des triggers). Quand le client n'envoie pas `tenant_id`, la recherche du produit
  `WHERE tenant_id = NEW.tenant_id` ne trouve rien, `v_tracking` est nul et **aucun avertissement
  de traçabilité n'est jamais émis**. Le scénario le confirme : 0 avertissement sur une réception
  sans lot. De plus, ni la réception ni la livraison ne recopient `lot_id`/`serial_id`, qui
  existent pourtant sur leurs lignes.
- **S-12 🟡** `create_stock_out_on_delivery` se déclenche quand l'ancien statut n'est ni `shipped`
  ni `delivered`. Un BL `shipped → cancelled → shipped` **sort le stock deux fois**, et aucune
  annulation ne remet jamais le stock.
- **S-13 🟠** `quality_checks` n'a **pas de colonne quantité**. Un contrôle en échec rebute
  `quantity_received` — la totalité de la ligne reçue — même si un seul article est défectueux.

---

## 3. Multi-devises (M-01) — le taux est saisi, protégé, et jamais appliqué

### M01-01 🔴 — Preuve chiffrée

**Scénario** (`scenarios/M01_facture_en_devise.sql`) : facture de **1 000 USD au taux 0,90**.

```
C1 facture 1 000 USD au taux 0,90 → écriture : débit=1000.00 crédit=1000.00
C2 attendu en devise de tenue (EUR) : 900,00
C3 lignes : 411000 D=1000.00 C=0.00 | 707000 D=0.00 C=1000.00
```

L'écriture porte **1 000 EUR**. Le chiffre d'affaires, le compte client et la TVA sont faux de
l'écart de change entier. Dans toute la base, `invoices.currency_code` et `exchange_rate` ne sont
lus que par `invoice_guard` et `purchase_invoice_guard` — **uniquement pour interdire de les
modifier après validation**. Aucune fonction ne les applique.

### M01-02 🔴 — Le modèle ne peut pas porter une devise

`journal_lines` n'a **aucune** colonne de devise, de montant en devise, ni de taux. Même corrigé,
le trigger ne pourrait pas conserver le montant d'origine : la correction exige une migration de
schéma, pas seulement une fonction.

### M01-03 🟠 — Les écrans de change sont des coquilles

`ExchangeGainLossPage` lit `exchange_gain_loss_entries` ; `CurrencyRevaluationPage` lit
`currency_revaluations`. **Aucune fonction SQL et aucun appel du front n'écrit dans ces deux
tables** — `createExchangeGainLossEntry` n'a aucun appelant. Les deux écrans sont vides à vie.
L'écart de change au règlement (666/766) et la réévaluation de clôture ne sont pas implémentés.

---

## 4. Immobilisations (M-02) — deux moteurs, et celui de l'écran ne comptabilise rien

La migration 211, corrigée par la 226 (R-01), a doté le projet d'un **bon** moteur :
`generate_depreciation_entry` gère l'idempotence, le prorata temporis en jours, la valeur
résiduelle, le plafonnement à la base amortissable et le contrôle des comptes.

Le problème est qu'**il coexiste avec deux autres**, toujours en place :

| Moteur | Où | Résiduelle | Prorata | Méthode | Écriture ? |
|---|---|:---:|:---:|:---:|:---:|
| `generate_depreciation_entry` | SQL (211/226) | ✅ | ✅ jours | linéaire seul | ✅ |
| `calculate_depreciation` | SQL (RPC historique) | ❌ | ❌ | linéaire seul | ❌ |
| `calculateDepreciation` | `misc.ts:57` | ✅ | ❌ **années entières** | linéaire seul | ❌ |

- **IMMO-02 🔴** C'est la version `misc.ts` que la page appelle. Elle recalcule `current_value`
  sur la fiche et **n'écrit ni dotation (`asset_depreciations`) ni écriture comptable**. Le bouton
  « Calculer les amortissements » change l'affichage sans rien comptabiliser.
- **IMMO-01 🟠** `yearsElapsed = floor((aujourd'hui − date d'achat) / 365,25)` : au bout de
  11 mois la dotation affichée est **0**, alors que le moteur SQL calcule un prorata en jours.
  Les deux chiffres se contredisent, exactement le défaut que la 226 venait de corriger un cran
  plus bas.
- **IMMO-03 🟠** Le calcul part de `Date.now()`, jamais de l'exercice. Relancer le calcul après
  une clôture **écrase** `current_value` avec la valeur du jour.
- **IMMO-04 🟠** L'écran propose trois méthodes (`straight_line`, `declining_balance`,
  `units_of_production`, `FixedAssetsPage.tsx:361`). `depreciation_method` est enregistrée et
  **aucun des trois moteurs ne la lit** : tout est linéaire. Le dégressif, pourtant fiscalement
  courant, n'existe pas.
- **IMMO-05 🟠** `calculateAllDepreciation` enveloppe chaque immobilisation dans un
  `try/catch { console.error }` : une dotation en échec est sautée en silence et la fonction
  renvoie une liste partielle comme un succès.

---

## 5. Analytique (M-03) — deux triggers vides

```sql
-- propagate_analytic_section  (BEFORE INSERT sur journal_lines)
BEGIN
  -- La section analytique est posée par la saisie [...] ; aucune ligne de document
  -- ne la porte à ce jour.
  RETURN NEW;
END;

-- check_analytic_balance  (BEFORE INSERT/UPDATE sur journal_lines)
IF NEW.account_code ~ '^[67]' AND NEW.analytic_section_id IS NULL THEN
  -- Permettre l'insertion mais alerter (non bloquant pour compatibilité)
  -- En production stricte, décommenter le RAISE
END IF;
```

- **ANA-01 🟠** Les deux corps sont vides ; le second est un `IF` qui ne contient que des
  commentaires. Deux appels de fonction par ligne d'écriture pour zéro effet.
- **ANA-02 🔴** `analytic_section_id` n'est écrit que par `post_journal_entry`, c'est-à-dire par
  la **saisie manuelle**. Aucune écriture produite par les ventes, les achats, la paie, le stock,
  la caisse ou la production ne porte de section. L'exigence « balance analytique = balance
  générale sur les classes 6 et 7 » ne peut pas être satisfaite : l'écart est égal à la totalité
  des écritures automatiques.
- `analytic_distribution_lines` existe et n'est lue par **aucune fonction SQL**.

---

## 6. Budgets (M-04) — le réalisé n'est pas borné

`getBudgetTracking` (`accounting.ts:2104`) :

```ts
let jlQ = supabase.from('journal_lines').select('debit, credit')
  .eq('account_general', b.account_code).order('id')
if (tid) jlQ = jlQ.eq('tenant_id', tid)
```

- **BUD-01 🔴** **Aucun filtre de date ni d'exercice**, alors que le budget porte
  `fiscal_year_id` (utilisé deux lignes plus bas pour les engagements). Le réalisé d'un budget
  2026 additionne **toutes les écritures depuis la création de la société**. Dès le deuxième
  exercice, le suivi budgétaire est faux, et l'écart affiché n'a aucun sens.
- **BUD-02 🟠** Aucun filtre sur le journal ni sur le statut : les à-nouveaux, les écritures de
  clôture et les **brouillons** sont comptés. Après une clôture, les écritures de solde des
  comptes 6/7 annulent le réalisé.
- **BUD-03 🟠** `budget_commitments` prévoit `status = 'consumed'` et
  `source_type IN ('purchase_order','purchase_invoice')`. **Rien ne crée d'engagement depuis une
  commande, et rien ne le solde à la facturation.** Un engagement saisi reste `active` : il est
  déduit du disponible une première fois comme engagement, puis une seconde comme réalisé.
- **BUD-04 🟡** Deux requêtes réseau paginées **par budget** (N+1).

---

## 7. RH et paie — le nom du salarié, et quatre façons de compter un mois

### RH-01 🔴 — 18 emplacements affichent « null null »

`employees` porte **`name` (NOT NULL)** *et* `first_name` / `last_name` (nullables). Le formulaire
de création (`EmployeesPage.tsx:155`) ne remplit que `name`. Aucun trigger ne découpe le nom.

Or **20 requêtes** dans `payroll.ts` et `sprintDE.ts` lisent `employees(first_name, last_name)`, et
**18 emplacements d'affichage, répartis sur 10 fichiers** (dont `Phase4Pages.tsx`, qui regroupe à lui
seul six écrans), les rendent tels quels :

```tsx
{r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}
```

`r.employees` n'est pas nul — c'est l'objet joint — donc le garde-fou ne sert à rien et l'écran
affiche littéralement **« null null »**. Écrans concernés : avances sur salaire, rappels de paie,
DPAE, pénibilité, historique de carrière, CPF, archives de paie, notes de frais (2 écrans),
entretiens, arrêts de travail, examens médicaux, documents du salarié, sortie de salarié
(3 endroits), et jusqu'au tableau de bord du salarié lui-même
(`EmployeeDashboardPage.tsx:42` : message de bienvenue sans nom).

### RH-02 🔴 — La paie a deux moteurs, dont un à taux inventés

```
calculate_payslip(uuid, text)        -- 1 570 caractères
calculate_payslip(uuid, text, uuid)  -- 20 283 caractères
```

Le vrai moteur (3 arguments) lit `payroll_legal_parameters`, `payroll_tax_grids`, le PMSS, la
CSG/CRDS, les tranches et les cumuls. Le moteur à 2 arguments applique **22 % de cotisations
salariales, 10 % d'impôt et 42 % de charges patronales en dur**, et ne persiste rien.

`businessFunctions.ts:16` choisit la surcharge selon la présence de `payRunId` :

```ts
if (payRunId) params.p_pay_run_id = payRunId
const { data, error } = await supabase.rpc('calculate_payslip', params)
```

Et `PaySlipsPage.tsx:155` appelle `handleCalculatePayslip(..., s.pay_run_id || undefined)`. Un
bulletin **sans campagne de paie** — cas prévu par la page, qui groupe les bulletins sous une clé
`'none'` — déclenche donc le moteur fictif : l'écran affiche « succès », rien n'est enregistré,
et les montants rendus sont faux.

### RH-03 à RH-05 🟠 — Les heures supplémentaires, comptées trois fois

| Mécanisme | Déclencheur | Seuil | Valorisation |
|---|---|---|---|
| `calculate_lateness_on_timesheet` → `overtime_minutes` | à la saisie | horaire prévu | **jamais lue par la paie** |
| `sync_timesheet_to_payroll` → élément `overtime` | à l'approbation | **> 7 h/jour** | **montant 0** |
| `importTimesheetElements` (front) → élément `overtime` | manuel | **> 8 h/jour** | taux × 1,25 |

- Les seuils **7 h** et **8 h** se contredisent.
- Si l'utilisateur lance l'import manuel, les heures supplémentaires sont inscrites **deux fois**
  (une fois à 0 €, une fois au vrai taux), en plus de l'élément `timesheet_hours`.
- **RH-03** : `sync_timesheet_to_payroll` est le seul des quatre triggers d'approbation **sans
  garde `NOT EXISTS … source_id`**. Un pointage approuvé → rejeté → réapprouvé duplique ses heures.
- **RH-05** : quatre conventions mensuelles cohabitent — `weekly_hours × 4,33` (retard),
  `/30` (absence non payée), `/21` (congé sans solde), `/151,67` (heures supplémentaires). Deux
  retenues pour le même jour d'absence donnent deux montants différents. Toutes ces constantes
  sont françaises et codées en dur : elles bloquent la localisation.

### RH-06 🔴 — L'import des éléments variables échoue 5 mois sur 12

Quatre requêtes bornent la période avec un **31 littéral** :

```ts
.gte('date', `${period}-01`).lte('date', `${period}-31`)   // leavesAbsences.ts:586
```

Vérifié contre PostgREST :

```
GET /timesheets?date=lte.2026-02-31
{"code":"22008","message":"date/time field value out of range: \"2026-02-31\""}
```

L'erreur est levée pour **février, avril, juin, septembre et novembre**. Les fonctions touchées —
`exportLeaveDataToPayroll` (:461), `importTimesheetElements` (:586), `importLeaveElements` (:612),
`importExpenseElements` (:635) — **lèvent une exception cinq mois par an**. Le commentaire du code
dit pourtant : « Une absence oubliée = un bulletin faux. »

### RH-07 🔴 — Les notes de frais entrent en paie à zéro

```ts
amount: Number(exp.amount),   // leavesAbsences.ts:645
```

`expense_reports` porte **`total_amount`** et `total_vat` — pas `amount`. `Number(undefined)` vaut
`NaN`, sérialisé en `null` : **chaque note de frais est intégrée pour un montant nul**. L'écriture
est en « tirer et oublier » (aucune vérification d'erreur), donc rien ne le signale.

- **RH-08 🟠** Aucune ventilation de TVA récupérable (`total_vat` est ignorée) et aucune écriture
  625x / 421 : l'exigence M-05 n'est pas couverte.

### RH-09, RH-10 🟠

- **RH-09** `importLeaveElements` filtre `start_date >= début` **et** `end_date <= fin`. Un congé
  commencé le mois précédent ou terminé le mois suivant est **entièrement omis**.
- **RH-10** `generateMealVoucherElements` n'a aucune garde d'idempotence : relancer l'import
  double les titres restaurant de toute la campagne.

---

## 8. Suppressions en cascade — trois effacements silencieux

**Scénario** : `scenarios/SUP_suppressions_en_cascade.sql`.

```
D1  ✅ suppression produit refusée : Ligne d'écriture […] validée (posted) — immuable.
D1b ⚠️ produit SUPPRIMÉ : mouvements restants=0
D3  ⚠️ salarié SUPPRIMÉ sans refus : bulletins restants = 0
D5  ⚠️ compte bancaire SUPPRIMÉ sans refus : opérations restantes = 0
```

| Parent supprimé | Ce qui disparaît | Garde |
|---|---|:---:|
| `employees` | **tous les bulletins de paie** (`pay_slips.employee_id` CASCADE) | aucune |
| `pay_runs` | tous les bulletins de la campagne | aucune |
| `bank_accounts` | **toutes les opérations** (`bank_transactions.account_id` CASCADE) | aucune |
| `products` | tout l'historique de mouvements (`stock_movements.product_id` CASCADE) | indirecte |

- **SUP-01 🔴** Un bulletin de paie est une pièce à conservation légale. Le bouton « supprimer »
  d'`EmployeesPage` (`handleDelete` → `deleteEmployee`) l'efface sans le moindre refus.
- **SUP-02 🔴** Idem pour le relevé bancaire, y compris les opérations déjà rapprochées (le lien
  vers l'écriture passe à `NULL`, l'écriture reste, la contrepartie disparaît).
- **SUP-03 🟠** Le produit n'est protégé **que par ricochet** : la cascade tente de passer
  `journal_lines.product_id` à `NULL`, ce qui réveille `prevent_posted_line_modification`. Mais un
  produit dont les mouvements n'ont produit **aucune écriture** — soit exactement le cas normal
  après une réception, par S-03 — est supprimé et son historique effacé (`D1b`).

---

## 9. Fonctions Edge — écrites contre un schéma qui n'a jamais existé

Le scanner d'écritures a trouvé **21 colonnes écrites qui n'existent pas**. Toutes sont dans des
fonctions Edge ou des traitements de fond, et **aucune de ces écritures ne vérifie son erreur**.

| Fonction | Colonne écrite | Table réelle porte |
|---|---|---|
| `cron-payment-reminders` | `days_overdue`, `sent_at`, `email_sent` | rien de tout cela |
| `submit-e-invoice` | `e_invoice_status`, `e_invoice_platform`, `e_invoice_submitted_at`, `e_invoice_id` | aucune colonne `e_invoice*` |
| `request-signature` | `provider`, `provider_signature_id`, `status`, `signers`, `initiated_at` | `signature_hash`, `signer_name`… |
| `sync-bank-transactions` | `provider_transaction_id` | (existe sur `online_payments`) |
| `sync-bank-transactions` | `provider_requisition_id`, `link_url`, `user_id` | `provider_connection_id` |
| `outgoing-webhooks` | `http_status` | `response_code` |
| `outgoing-webhooks` | `next_retry_at` | `next_attempt_at` |
| `handle-stripe-webhook` | `metadata` | — |
| `banking.ts:101` | `matched_line_id` | `matched_invoice_id` |
| `MobileApproval.tsx:45` | `leave_requests.manager_comment` | (existe sur `expense_reports`) |

### EF-01, EF-02 🔴 — Les relances de paiement (M-14)

Deux défauts qui se cumulent, sur un traitement **qui tourne tous les jours à 9 h en production** :

```ts
const { data: existing, error } = await supabase
  .from("collection_reminders").select("id")
  .eq("invoice_id", invoice.id).eq("reminder_level", reminderLevel)
  .single()
if (error) throw error
```

- **EF-01** `.single()` renvoie l'erreur `PGRST116` quand il n'y a **aucune** ligne — c'est-à-dire
  au premier passage sur chaque facture. `if (error) throw error` **interrompt tout le cron**.
  Aucune relance n'est donc jamais envoyée, et le cron échoue chaque jour. Il fallait
  `.maybeSingle()`.
- **EF-02** Si l'on franchit ce point, l'e-mail **part**, puis l'enregistrement de la relance
  échoue sur trois colonnes inexistantes — sans contrôle d'erreur. Le lendemain, le test
  « a-t-on déjà relancé ? » ne trouve toujours rien : **le client reçoit la même relance tous les
  jours, indéfiniment**, y compris les niveaux « MISE EN DEMEURE » et « des poursuites seront
  engagées ».

Accessoirement : les messages sont en français codé en dur avec le symbole `€` en dur, et le
filtre `.in("status", ["sent","validated","posted"])` porte sur deux statuts que la contrainte
`invoices_status_check` **interdit** (`validated`, `posted`).

### EF-03, EF-04 🔴 — La synchronisation bancaire (M-16)

```ts
export async function syncBankConnection(connectionId: string) {
  // …
  await supabase.from('bank_connections').update({
    last_sync_at: now, status: 'active', error_message: null })
  return { synced: 0, error: null }
}
```

- **EF-03** La fonction **n'appelle jamais** `sync-bank-transactions`. Elle tamponne une date de
  synchronisation, force `status: 'active'` et **efface le message d'erreur**. `BankSyncPage`
  affiche alors `bankSync.syncSuccess`. L'utilisateur voit une connexion « active, synchronisée à
  l'instant » alors que rien n'a été récupéré et que toute panne réelle vient d'être masquée.
- **EF-04** Même si elle l'appelait, la fonction Edge insère `provider_transaction_id`, qui
  n'existe pas sur `bank_transactions` (vérifié : `ERROR: column … does not exist`). Le code ne
  teste pas l'erreur (`if (!insertErr) imported++`) et renvoie `success: true, imported: 0`.
  Elle lit aussi `connection.provider_account_id`, colonne absente de `bank_connections` :
  l'URL appelée contient littéralement `undefined`.

### EF-05, EF-06 — La facturation électronique (M-13)

- **EF-05 🔴** `submit-e-invoice` transmet la facture à Chorus Pro puis écrit quatre colonnes
  `e_invoice_*` **inexistantes**, sans vérifier l'erreur, et renvoie `success: true`. L'application
  ne garde **aucune trace** d'une facture transmise : un second clic **la retransmet**.
- **EF-06 🟠** En pratique le problème ne se pose pas encore : `EInvoicePage` **n'appelle jamais**
  `submit-e-invoice`. Elle génère le XML Factur-X/UBL et le télécharge. Aucune soumission.

### EF-07, EF-08 🟠

- **EF-07** `request-signature` enregistre la demande Yousign dans `electronic_signatures` avec
  cinq colonnes inexistantes, sans contrôle : la signature est demandée au prestataire et
  l'application n'en garde aucune trace.
- **EF-08** `outgoing-webhooks` écrit `http_status` dans `webhook_delivery_logs` (la colonne
  s'appelle `response_code`) et replanifie via `next_retry_at` (la colonne s'appelle
  `next_attempt_at`). Sept écritures sans contrôle d'erreur : **aucun journal de livraison, et les
  reprises ne sont jamais replanifiées**.

### Fonctions Edge sans appelant

**11 des 21 fonctions déployées n'ont aucun appelant dans le front** : `submit-e-invoice`,
`request-signature`, `sync-bank-transactions`, `submit-vat-return`, `validate-vat-vies`,
`verify-iban`, `verify-siret`, `generate-pdf`, plus les trois appelées de l'extérieur
(`handle-stripe-webhook`, `outgoing-webhooks`, `refresh-exchange-rates`). Les écrans existent
pourtant : `EInvoicePage`, `BankSyncPage`, `EdiTvaPage`, `VatReturnsPage`.

---

## 10. Écritures sans contrôle d'erreur

29 écritures `insert` / `update` / `delete` ne vérifient **aucune** erreur — ni déstructuration,
ni `.then/.catch`. Le contrôle `audit:silent` existant ne les voit pas (il cherche une
déstructuration incomplète, pas une absence totale). Les plus sensibles :

| Fichier | Ce qui peut disparaître en silence |
|---|---|
| `leavesAbsences.ts` :534, :598, :621, :641 | **quatre alimentations de la paie** en éléments variables |
| `stock.ts` :800, :878, :1005 | propositions MRP, prévisions de production, créneaux de planning |
| `socialDeclarations.ts` :445, :479, :529 | taux PAS, taux AT, indicateurs BDES |
| `outgoing-webhooks` (7 écritures) | file d'attente et journal des webhooks |
| `documents.ts:46` | journal d'accès aux documents (piste d'audit) |

---

## 11. Ce qui a été vérifié et tenu

Pour être juste, plusieurs points de la phase 3 se sont révélés **corrects** :

- La **double sortie de stock** signalée le 12/09 (M-06) est corrigée : `create_stock_out_on_delivery`
  ne réagit qu'au passage vers `shipped`.
- La **double entrée à la réception** (M-07) est corrigée : `create_stock_in_on_quality_pass` ne
  crée plus de mouvement en cas de succès (LOT4-05).
- Le **doublon `reserved_quantity` / `quantity_reserved`** n'existe plus : une seule colonne subsiste.
- Le **noyau comptable de la 187** est bien étanche : toutes les écritures produites par les
  modules passent par `journal_entry_guard`, `check_journal_entry_balance_on_post` et
  `journal_entry_accounts_open_on_post` — équilibre, exercice ouvert, période ouverte, comptes
  imputables et **numéro définitif sans trou** sont contrôlés même pour les écritures automatiques.
- `generate_depreciation_entry` (211/226) est un moteur d'amortissement correct.
- Les **1 495 requêtes de lecture** du front sont acceptées par un PostgREST réel.

---

## 12. Isolation entre sociétés — le défaut le plus grave

### ISO-01 🔴 — Un utilisateur écrit dans la société voisine

**Scénario** (`scenarios/ISO_ecriture_inter_societes.sql`), joué sous le **vrai rôle applicatif**
`authenticated`, RLS active, en-tête `x-tenant-id` légitime :

```
Y0 contexte : société active = A, le client de B est-il visible ? 0
Y1 ⚠️ facture de A rattachée au client INVISIBLE de B — acceptée
Y2 ⚠️ tâche de A rattachée à une tâche de B — acceptée
Y3 statut de la tâche de B : done      ← elle valait « todo »
```

Un utilisateur de la société A, qui **ne voit pas** les données de B (la RLS en lecture tient
parfaitement, `Y0` le confirme), a **fermé une tâche de la société B** — simplement en créant
chez lui une sous-tâche rattachée à celle de B.

Le mécanisme : `update_parent_status_on_subtasks_done` est `SECURITY DEFINER` et fait
`UPDATE project_tasks SET status='done' WHERE id = v_parent_id` **sans filtre `tenant_id`**.
`SECURITY DEFINER` contourne la RLS : la ligne de l'autre société est modifiée.

**13 fonctions trigger `SECURITY DEFINER` écrivent sans jamais mentionner `tenant_id`** :
`update_parent_status_on_subtasks_done`, `update_parent_status_on_subtask_started`,
`recalc_project_progress_on_task_change`, `recalc_parent_progress_on_subtask_change`,
`recalc_task_progress_on_action_change`, `auto_reach_milestone_on_tasks_done`,
`update_project_hours_on_time_entry`, `update_task_time_on_time_entry`,
`notify_assignee_on_assignment`, `trigger_revoke_expired_auditors`, et les quatre
`*_lines_refresh_totals`.

### ISO-02 🔴 — 189 tables acceptent une clé étrangère vers une autre société

La politique RLS de la plupart des tables ne contrôle que **leur propre** `tenant_id` :

```sql
tenant_insert_project_tasks | INSERT | (tenant_id = current_tenant_id())
```

Le `WITH CHECK` valide la ligne insérée, **jamais ce qu'elle référence**. Et la base ne compte
qu'**une seule clé étrangère composite** : aucune ne porte `(tenant_id, id)`. Résultat : une
facture de A peut désigner un client de B, un règlement de A une facture de B, une opération
bancaire de A un compte de B.

**189 tables** combinent une politique simple et une clé étrangère vers une table cloisonnée.

Le bon motif existe pourtant déjà dans le projet — les tables de lignes le pratiquent :

```sql
tenant_insert_invoice_lines | INSERT |
  EXISTS (SELECT 1 FROM invoices p WHERE p.id = invoice_lines.invoice_id
                                     AND p.tenant_id = current_tenant_id())
```

C'est ce contrôle *par le parent* qu'il faut généraliser (ou, plus sûrement, des clés étrangères
composites `(tenant_id, …)`). Le travail H02 du 23/09 a prouvé que la RLS **en lecture** tient sur
340 tables ; il n'a pas touché ce versant en écriture.

### ISO-03 🔴 — 38 gardes de permission annulées par leur jumelle

```
mirror_verification_details (INSERT)
  « tenant_insert_mirror_verification_details » : tenant_id = current_tenant_id()
                                                  AND can_perform('…','insert')
  « tenant_insert_mirror_verification »         : tenant_id = current_tenant_id()
```

Deux politiques **permissives** sur la même table et la même commande sont combinées par un
**OU**. La seconde, plus faible, rend la première inopérante. Le contrôle `can_perform` est donc
mort sur **38 couples table/commande** : tout le module production et sous-traitance
(`mrp_runs`, `mrp_proposals`, `of_lots`, `of_consumptions`, `routings`, `routing_operations`,
`work_centers`, `machines`, `toolings`, `planning_slots`, `st_orders`, `st_receipts`,
`st_shipments`…) et le miroir.

### ISO-04 🟡 — 326 politiques RLS en double, 11 index en double

Chaque table porte souvent deux politiques identiques par commande (`tenant_select` et
`tenant_select_<table>`). **326 doublons stricts**, évalués à chaque requête. C'est aussi ce qui
rend possible ISO-03. Onze index sont également dupliqués (`idx_bank_recon_rules_tenant` =
`idx_bank_reconciliation_rules_tenant`, `idx_stock_movements_product` =
`idx_stock_movements_product_id`, `pay_slips_tenant_number_key` = `uniq_pay_slip_number_tenant`…).

### PERM-01 🔴 — Les rôles ne sont pas opposables (M-18)

**Scénario** (`scenarios/M18_role_non_opposable.sql`), sous `authenticated`, avec un utilisateur
dont le rôle est **`viewer`** (lecture seule) :

```
P0 contexte : société active = …, rôle applicatif = viewer
P1 ⚠️ un LECTEUR (viewer) a CRÉÉ une facture
P2 ⚠️ un LECTEUR a SUPPRIMÉ un client
P3 ✅ refusé : SECURITY: Cannot change own role
```

Il existe **deux systèmes de droits qui ne partagent aucun vocabulaire** :

| | Où | Vocabulaire | Effet réel |
|---|---|---|---|
| Matrice navigateur | `hasPermission`, `misc.ts:1233` | table × CRUD | masque des boutons |
| Fonction serveur | `has_permission`, SQL | `journal_entry.post`… | utilisée par 26 politiques sur 1 739 |

`usePermission` le dit lui-même : « Confort d'interface, pas protection ». Mais **rien ne prend le
relais** : sur `invoices`, les quatre politiques ne testent que `tenant_id`. Un `viewer`, un
`auditor` — dont c'est la raison d'être d'être en lecture seule, avec une date d'expiration et un
`pg_cron` de révocation — peuvent créer, modifier et supprimer par appel direct à l'API.

Seule l'auto-promotion est bloquée (`Cannot change own role`) : cette garde-là fonctionne.

---

## 13. Caisse (POS) — la comptabilité est juste, l'inaltérabilité ne l'est pas

**Scénario** : `scenarios/POS_inalterabilite_nf525.sql`.

Ce qui fonctionne :

```
A1 écriture de clôture : créée — 531000 D=120,00 | 707000 C=100,00 | 445711 C=20,00
A2 sortie de stock sur la vente caisse : 1 mouvement ; stock produit = 99
```

La ventilation de TVA par taux et l'écart de caisse (migration 219) **tiennent**, et la vente
sort bien du stock. C'est le seul module où la chaîne complète est correcte.

Ce qui ne tient pas :

```
B1 ⚠️ ticket ramené de 120 € à 12 € SANS REFUS ; hachage inchangé = true
B2 ⚠️ 1 ligne(s) de ticket supprimée(s) sans refus
B3 journal NF525 : 3 événements — aucun ne mentionne la modification
```

- **POS-01 🔴** `pos_tickets` a une garde en **suppression** (`prevent_pos_ticket_deletion`) et un
  hachage chaîné à l'**insertion**, mais **aucun trigger en modification**. Le montant d'un ticket
  signé se réécrit, et comme le hachage n'est pas recalculé, la chaîne « valide » le ticket
  falsifié. C'est précisément la dissimulation de recettes que la norme NF525 existe pour empêcher.
- **POS-02 🔴** `pos_ticket_lines` ne porte que `set_tenant_id` : aucune garde en modification ni
  en suppression.
- **POS-03 🟠** Aucun index unique sur `(tenant_id, terminal_id, sequential_number)`, et le numéro
  est calculé par `MAX(…)+1` **sans verrou** : deux encaissements simultanés sur le même terminal
  prennent le même numéro et la chaîne de hachage fourche.
- **POS-04 🟠** `created_at`, fourni par le client, entre dans le hachage : un ticket antidaté
  produit un hachage cohérent.
- Le statut du ticket n'a **aucune contrainte `CHECK`** : un ticket dont le statut n'est pas
  exactement `'completed'` est exclu de l'écriture de clôture, silencieusement.

---

## 14. Production, projets, TVA, import

### Production (M-08)

- **PROD-01 🟠** `create_stock_on_manufacturing_complete` lit `bom_lines` **à un seul niveau**
  (`WHERE bl.bom_id = NEW.bom_id`). Un composant lui-même fabriqué n'est pas explosé : les OF
  multi-niveaux ne sont pas gérés.
- **PROD-02 🟠** `qty_produced = NEW.quantity` : la quantité produite est forcée à la quantité
  *commandée*. Ni rebut, ni écart de quantité, ni écart de coût — `products.scrap_rate` existe et
  n'est pas lu.
- **PROD-03 🟡** L'écriture et les mouvements sont datés de `CURRENT_DATE`, pas de la date de l'OF :
  un ordre clôturé en retard tombe dans le mauvais exercice.
- Comptes `601000` / `310000` / `355000` / `713500` codés en dur (cf. S-10).
- **Point tenu** : l'idempotence est correcte (`reference = 'JE-OF-…'`), l'écriture équilibre, et
  `reference_type = 'production'` évite bien la double comptabilisation par le trigger de stock.

### Projets, temps et CRM (M-17)

- **PROJ-01 🔴** `create_billable_line_on_timesheet_stop` promet une ligne facturable. Son corps
  **crée une notification** et rien d'autre — le commentaire l'admet : « On utilise la table quotes
  si elle existe, sinon on crée une notification ». La refacturation des temps passés n'existe pas :
  aucune ligne de devis ni de facture n'est jamais produite.
- **PROJ-02 🟠** `recalc_project_progress_on_task_change` fait la **moyenne non pondérée** des
  tâches de premier niveau : une tâche d'une heure pèse autant qu'une de cent jours. Et un second
  trigger (`recalc_parent_progress_on_subtask_change`) calcule l'avancement autrement.
- **PROJ-03 🟠** Aucune contrainte n'empêche une tâche d'être son propre parent (vérifié). Avec
  treize triggers sur `project_tasks` dont plusieurs se réécrivent en cascade, un cycle produit une
  récursion sans garde de profondeur.
- Message de notification avec `€` codé en dur.

### TVA (M-10)

- **TVA-01 🔴** `submitEdiTva` (`misc.ts:1295`) fabrique un identifiant `EDI-${Date.now()}`, écrit
  `edi_status: 'submitted'` et une date de dépôt — **et ne transmet rien**. `EdiTvaPage` demande
  confirmation, puis affiche « succès ». La déclaration apparaît comme télétransmise à
  l'administration alors qu'elle n'a jamais quitté l'application.
- La fonction Edge `submit-vat-return`, elle, est **correcte** : elle refuse explicitement de
  simuler quand le jeton EFI n'est pas configuré (« Aucune donnée n'a été transmise »). Elle n'est
  **jamais appelée**. Même constat pour `transmit-dsn` (M-12), correcte et, elle, bien appelée.

### FEC (M-11) et import Sage (M-19)

- **FEC** : l'export utilisé par l'écran (`getFECData` + `fecValidator.ts`) porte bien les
  **18 colonnes** de l'arrêté et trie par `posting_seq`. ✅ En revanche une **seconde
  implémentation** subsiste en base, `fec_export`, qui ne produit que **9 colonnes** et utilise
  `je.number` (numéro provisoire) au lieu de `posting_number`. Elle n'est pas appelée, et la
  surcharge qui accepte un `p_tenant_id` du client **n'est pas accordée à `authenticated`** (le
  travail de la 228 a tenu) — mais elle reste à supprimer. Note : `Montantdevise` / `Idevise` ne
  pourront jamais être remplies tant que M01-02 n'est pas corrigé.
- **SAGE-01 🔴** Les écritures importées sont créées en `status: 'draft'` et **rien ne les valide**.
  Une reprise de balance produit un brouillard, jamais une comptabilité. Aucun contrôle
  `totalDebit === totalCredit` n'est fait avant l'appel.
- **SAGE-02 🟠** `updateChartAccount(acc.id, { balance })` **remplace** le solde du compte par le
  seul cumul des lignes importées. Importer dans une société qui a déjà des écritures **écrase**
  les soldes affichés au plan comptable. (La balance générale, elle, est recalculée par
  `get_trial_balance` : elle reste juste.)
- **SAGE-03 🟠** Chaque écriture est tentée dans son propre `try/catch` : un import partiel laisse
  une comptabilité déséquilibrée, sans transaction englobante ni possibilité de reprise.

---

## 15. Ce qui a été vérifié et tenu

Pour être juste, plusieurs points se sont révélés **corrects** à l'exécution :

- Le **noyau comptable de la 187** est étanche : toutes les écritures produites par les modules
  passent par `journal_entry_guard`, `check_journal_entry_balance_on_post` et
  `journal_entry_accounts_open_on_post` — équilibre, exercice ouvert, période ouverte, comptes
  imputables et **numéro définitif sans trou** sont contrôlés même pour les écritures automatiques.
- **La RLS en lecture tient** : le client d'une société voisine est bien invisible, en-tête
  `x-tenant-id` falsifié compris (H02 l'a prouvé sur 340 tables, mon scénario le reconfirme).
- La **comptabilisation de la caisse** est juste : TVA ventilée par taux, écart de caisse, sortie
  de stock (migration 219).
- `generate_depreciation_entry` (211/226) est un **bon** moteur d'amortissement.
- `transmit-dsn` et `submit-vat-return` **refusent de simuler** une transmission non configurée.
- L'**export FEC de l'écran** est conforme (18 colonnes, tri par numéro définitif).
- L'auto-promotion d'un utilisateur est bloquée (`Cannot change own role`).
- La **double sortie de stock** (M-06) et la **double entrée à la réception** (M-07) signalées le
  12/09 sont bien corrigées ; le doublon `reserved_quantity` / `quantity_reserved` n'existe plus.
- Les **1 495 requêtes de lecture** du front sont acceptées par un PostgREST réel.
- `fec_export(uuid,…)` n'est **pas** accordée à `authenticated` : le travail de la 228 tient.

---

## 16. Recommandations d'ordre

L'ordre proposé va du plus dangereux au plus coûteux, et tient compte des dépendances.

| Rang | Quoi | Pourquoi d'abord | Défauts levés |
|---:|---|---|---|
| 1 | Clés étrangères composites `(tenant_id, …)` + `tenant_id` dans les 13 triggers `SECURITY DEFINER` | Écriture inter-sociétés : c'est une faille, pas un bug | ISO-01, ISO-02 |
| 2 | Supprimer les 326 politiques en double | Rétablit les 38 gardes `can_perform` neutralisées | ISO-03, ISO-04 |
| 3 | Rendre les rôles opposables en base | Un « lecteur » écrit aujourd'hui dans les livres | PERM-01 |
| 4 | Garde en modification sur `pos_tickets` et `pos_ticket_lines` + index unique | Inaltérabilité NF525 | POS-01 à POS-04 |
| 5 | Gardes de suppression sur `employees`, `bank_accounts`, `pay_runs`, `products` | Pièces à conservation légale effacées d'un clic | SUP-01 à SUP-03 |
| 6 | `warehouse_id` et prix sur la réception ; dépôt sur les sorties | Débloque toute la chaîne stock/valorisation/compta | S-01 à S-07 |
| 7 | Brancher le scanner d'écritures en CI | Les 21 colonnes fantômes seraient tombées à la première exécution | EF-01 à EF-08 |
| 8 | Les quatre bornes de période `-31` et `exp.amount` | Un correctif d'une ligne chacun, effet immédiat sur la paie | RH-06, RH-07 |
| 9 | Un seul `calculate_payslip`, un seul moteur d'amortissement, un seul calcul d'heures supp | Supprimer les moteurs concurrents | RH-02, RH-04, IMMO-01 à IMMO-04 |
| 10 | Borner le réalisé budgétaire à l'exercice | Une clause `WHERE` | BUD-01, BUD-02, ANA-03 |
| 11 | Retirer les placebos (`syncBankConnection`, `submitEdiTva`) ou les brancher | Un écran qui ment est pire qu'un écran absent | EF-03, TVA-01 |
| 12 | Multi-devises : colonnes de devise sur `journal_lines`, puis conversion | Chantier de schéma, à planifier avec la localisation | M01-01 à M01-03 |

### Deux contrôles à ajouter à la CI

1. **`scan-colonnes-ecrites.mjs`** (livré ici) : confronte les colonnes écrites par `.insert()` /
   `.update()` au schéma réel. Il trouve aujourd'hui **21 écritures impossibles**. C'est l'angle
   mort exact de `check-embeds.mjs`, qui ne vérifie que les lectures.
2. **`scan-ecritures-non-verifiees.mjs`** (livré ici) : recense les **29 écritures** dont l'erreur
   n'est jamais lue. `audit:silent` ne les voit pas : il cherche une déstructuration incomplète,
   pas une absence totale de déstructuration.

Un troisième contrôle, purement SQL, mériterait d'exister : **refuser toute politique permissive
en double** sur un couple table/commande — c'est ce doublon qui a neutralisé 38 gardes de droits.

---

## Correctifs appliqués — migrations 240 → 244

Appliqué le 24 septembre 2026 : les **18 défauts du registre initial** (S-01 → S-11, RH-01 → RH-04,
SUP-01 → SUP-03) et **trois défauts de la même famille** sont corrigés, chacun par une migration et
une suite de scénarios chiffrés, vus **rouges avant** et **verts après** sur une base neuve.

| Migration | Défauts | Ce qu'elle fait | Scénarios |
|---|---|---|---|
| **240** `240_stock_movement_tenant_and_upsert.sql` | S-08, S-09 | la société devient un **paramètre** des mouvements de stock (`_stock_increment` / `_stock_decrement`), le déclencheur passe `NEW.tenant_id` ; l'entrée additionne par `ON CONFLICT … DO UPDATE` (la quantité d'une transaction concurrente n'est plus perdue en silence) ; une sortie supérieure au stock **du dépôt** est refusée au lieu d'être rognée à 0 ; un stock non localisé est rattaché au dépôt utilisé au lieu d'être refusé | `240_…_tests.sql` T01→T04 (4/4) |
| **241** `241_receipt_stock_and_ledger.sql` | S-01 → S-04, S-10, S-11 | `goods_receipts.warehouse_id`, avec repli sur `resolve_default_warehouse` ; le mouvement d'entrée porte **dépôt, coût, lot et numéro de série** (prix de la ligne de commande, puis prix d'achat, puis coût de revient) → couche de valorisation **et** écriture ST (D 310000 / C 603000) ; les comptes sont **résolus** par article puis famille d'articles (`resolve_stock_account` / `resolve_variation_account`, écrits depuis la 125 et appelés nulle part) ; article suivi sans lot → **refus** | `241_…_tests.sql` T01→T07 (7/7) |
| **242** `242_delivery_warehouse_and_reservation.sql` | S-05, S-06, S-07 | la sortie porte le dépôt de la réservation, sinon celui qui peut servir la ligne, sinon celui de la société → les **couches sont réellement consommées** ; l'expédition libère la réservation **au prorata** (une commande de 10 livrée en 4 puis 6 libère 4 puis 6) ; les réservations sont toujours rattachées à un dépôt ; reprise du stock existant dans son dépôt | `242_…_tests.sql` T01→T06 (6/6) |
| **243** `243_payroll_and_employee_name.sql` | RH-01 → RH-04 | `first_name` / `last_name` remplis depuis `name` (déclencheur + reprise des fiches) → les 17 écrans RH ne montrent plus « null null » ; `calculate_payslip(uuid, text)` **supprimée** (la surcharge à taux fictifs n'est plus atteignable) ; le pointage **met à jour** sa ligne de paie (verrou consultatif par pointage) ; une seule mesure des heures supplémentaires (`overtime_minutes`), et l'agrégat du bulletin ne compte plus `timesheet_hours` comme des heures supplémentaires | `243_…_tests.sql` T01→T05 (5/5) |
| **244** `244_preserve_history_delete_guards.sql` | SUP-01 → SUP-03 | garde de suppression sur `employees` (bulletins de paie), `bank_accounts` (opérations et relevés) et `pay_runs` (bulletins du lot) : refus **expliqué** ; `stock_movements.product_id` passe en `ON DELETE SET NULL` — l'historique survit à la suppression d'un article, comme le font déjà `journal_lines`, `invoice_lines` et `purchase_invoice_lines` ; l'effacement d'une société entière reste possible (AUD-B00, jeux de test) | `244_…_tests.sql` T01→T09 (9/9) |

**Preuve d'exécution** — base neuve, schéma + **214 migrations, 0 erreur** (les migrations des
sessions parallèles — 232 séparation des tâches, 233 chaîne NF-525, 234 file de webhooks — sont
dans la même base) :

- les cinq suites **avant** correctif : **26 scénarios rouges sur 31** — les cinq verts d'emblée
  sont les garde-fous qui gardent qu'une suppression légitime reste possible (salarié sans
  bulletin, compte sans opération, article sans mouvement, lot de paie sans bulletin, société
  entière) ;
- les mêmes suites **après** : **31/31 verts** ;
- les **45 suites de la CI** restent vertes, ainsi que `check_trigger_reachability` (82
  comparaisons vérifiées, aucune impossible), `check_tenant_guard` (80 fonctions, aucune exposée
  sans contrôle) et `check_anon_grants` (2 fonctions exposées, les deux inscrites au registre) ;
- les types TypeScript régénérés ne diffèrent que de la colonne ajoutée
  (`goods_receipts.warehouse_id`).

### Ce que ces correctifs ne font pas (inscrit au registre)

| Réf | Ce qui reste ouvert | Pourquoi, et où c'est chiffré |
|---|---|---|
| S-06 (suite) | le stock **antérieur** à la 241 n'a ni couche de valorisation ni écriture d'entrée : ses sorties consomment les couches des entrées postérieures, pas les siennes | reprendre une valeur de stock existante est une **décision comptable** (date, coût, écriture) qui appartient au propriétaire ; la reprise de la 242 ne range que la **quantité**, jamais la valeur. Le CUMP de `stock_quantities` tient les écritures justes |
| S-07 (suite) | annuler un BL expédié ne **contre-passe pas** la sortie de stock (même manque que pour l'OF, M-06/M-08) | demande une écriture de contrepassation documentée, et une décision sur la date |
| S-11 (suite) | un article suivi en lot ne peut plus **sortir** sans lot, mais `delivery_note_lines.lot_id` n'est rempli par aucun écran (`delivery_notes`/`delivery_note_lines` : colonnes présentes, saisie absente) | travail d'écran (`app/src`), à faire avec le parcours P0-08 : sans cela, un article suivi ne se livre plus, ce qui est le prix de la traçabilité |
| RH-04 (suite) | `app/src/lib/queries/leavesAbsences.ts:593` calcule encore des heures supplémentaires en « heures − 8 » au taux 1,25 et crée un élément `overtime` **avec un montant** | hors périmètre SQL : c'est une **troisième** façon de calculer, à aligner sur `overtime_tiers` / `calculate_overtime_pay` (PAY-07) |
| SUP-01/SUP-02 (suite) | l'écran propose toujours « Supprimer » ; le refus est désormais expliqué par un message, mais aucune action « désactiver » n'est offerte pour un salarié ou un compte bancaire | travail d'écran : un bouton « Désactiver » éviterait d'aller au refus |
| 241 (suite) | l'écriture de réception entre au **journal des stocks** (ST, D 310000 / C 603000) : c'est la convention du produit (variation de stocks). Une comptabilité à la **facture non parvenue** (C 4081) serait plus orthodoxe et reste une décision | cf. `S-03` : le correctif rétablit l'écriture, pas la méthode de rattachement à la facture |

