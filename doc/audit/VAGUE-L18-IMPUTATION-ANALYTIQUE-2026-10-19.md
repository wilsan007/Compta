# VAGUE L18 — tranche 2, fin : l'imputation analytique du stock (768) — 2026-10-19

> Branche `plan6/a3-moteur`. Migration `768_chain_l18_imputation_analytique.sql`
> + suite `768_chain_l18_imputation_analytique_tests.sql` (**8 scénarios**).
> Ce document est la preuve du lot ; la migration porte son propre en-tête
> (défaut mesuré, contrat, décisions, limites).

## 1. Le défaut, mesuré (rouge d'abord)

La 304 avait posé le porteur analytique sur les lignes de facture et d'achat,
et **avait dit sa limite** : « la paie, le stock, la caisse et la production ne
portent pas encore de section analytique ». Le stock en était donc un :

- **T01** : `colonnes=0 clés=0` — ni `stock_movements` ni `manufacturing_orders`
  ne pouvaient porter une section ;
- **T02** : `column "analytic_section_id" of relation "stock_movements" does
  not exist` — une sortie de chantier ne pouvait pas être rattachée à son axe.

Conséquence mesurée : les écritures générées par le stock (journal **STK**,
journal **OF**) étaient **muettes côté analytique**. La balance analytique ne
pouvait égaler la balance générale **en dehors des ventes et des achats** —
la limite W7/304 tenait.

## 2. Ce que la 768 pose

1. **Deux porteurs**, clés composites ISO-02 (le miroir exact de la 304) :
   `stock_movements.analytic_section_id` et `manufacturing_orders.analytic_section_id`.
2. **La circulation, dans les DEUX seules fonctions vivantes qui comptabilisent
   le stock** :
   - `create_journal_on_stock_movement` (388 LOC1-07 — comptes **par les rôles**,
     jamais `ST`/`310000` en dur) : la section du mouvement est portée par les
     lignes de **charge** (6xx) de l'écriture qu'il écrit ;
   - `create_stock_on_manufacturing_complete` (187 — l'écriture `JE-OF-…`) : la
     section de l'OF est portée par ses **mouvements de composants** (sorties)
     et par la ligne **601000** (consommation matières) de l'écriture de production.
3. **Le vrai chemin de clôture, corrigé au passage** : la clôture d'OF écrit ses
   mouvements avec `reference = numéro d'OF` et **sans `reference_id`** (187,
   mesuré) — le compagnon 767 ne résolvait que par `reference_id` et ratait donc
   la clôture réelle au profit des mouvements de test. `chain_l18_imputer_cout`
   résout désormais **par le numéro** quand l'identifiant est absent.

**Décisions** : seules les lignes de **charge** (6xx) portent la section (la
règle de la 304 — pas de section sur la TVA — appliquée au stock : `310000`,
`355000`, `713500` sont des comptes de bilan) ; l'entrée de produit fini ne
reçoit **pas** la section (c'est du stock qui naît, pas une dépense de chantier) ;
aucune écriture, aucun lien de chaîne nouveau — G2, G8 et le catalogue des
événements ne bougent pas.

## 3. Les 8 verdicts (verts)

| Test | Ce qu'il mesure | Mesure |
|---|---|---|
| **T01** | le porteur existe : 2 colonnes + 2 clés composites ISO-02 | `colonnes=2 clés=2` |
| **T02** | une section d'une **autre** société est **refusée** (clé composite nommée) | `23503` sur `stock_movements_ana…` |
| **T03** | une section étrangère sur l'**OF** est refusée | `23503` sur `manufacturing_…` |
| **T04a** | supprimer la section **nettoie** le porteur | `ON DELETE SET NULL` → `NULL` |
| **T04b** | l'écriture STK **postée** protège sa section (inaltérabilité W2) | refus nommé, porteur intact |
| **T05** | la section du mouvement de chantier circule jusqu'à la **ligne de charge** de l'écriture STK | section portée + débit `20.00` |
| **T06** | l'OF **de chantier** porte sa section : sorties **et** ligne 601000 — et le coût matière atteint le projet | `actual_cost=50.0000` |
| **T07** | un OF **sans** section produit mouvements et écriture **sans** section (muet) | `(aucune)` |

## 4. Non-régression rejouée (13 suites, 120 scénarios, base `l20_t2`)

`418` 8/8 · `302` 8/8 · `304` 5/5 · `315` 2/2 · `241` 7/7 · `280` 10/10 ·
`767` 10/10 · `766` 8/8 · `765` 6/6 · `400` 15/15 · `401` 12/12 · `450` 14/14 ·
`252` 17/17 — **0 rouge**.

**Portes CI (12/12 vertes)** : `check_tenant_guard`, `check_effects_contract`,
`check_status_writes`, `check_global_rows_writable`, `check_anon_grants`,
`check_composite_fks`, `check_roles_opposables`, `check_policy_duplicates`,
`check_forced_rls_writers`, `check_trigger_reachability`, `check_bt_grid`,
`check_chain_rpc_inventory`.

**Front** : `tsc -b --noEmit` exit 0 · `oxlint --max-warnings=0` 0 avertissement
(582 fichiers) · **Vitest 1662 verts / 38 ignorés** (79 fichiers) ·
`check-test-suites` (G5) **259 suites câblées, 0 référence morte** ·
`db:types` régénéré depuis la base locale : **403 tables**, diff **exact**
(+20 lignes, 2 colonnes).

## 5. Limites dites

- la section est portée **telle quelle** (l'écran la saisira — partie D) :
  aucune dérivation automatique projet → section (les projets ne portent pas
  d'axe analytique) ;
- la **paie**, la **caisse** et la **production** (autre que l'OF de chantier)
  restent sans section : la moitié non-stock de la limite 304 tient ;
- la 768 ne crée **aucun** maillon de chaîne : elle fait circuler une
  colonne, elle ne trace pas d'effet (G2 et G8 ne bougent pas).

## 6. Suite

**L18 est clos** (tranche 1 `418` + tranche 2 `767` + `768`). L'étape
suivante de la file A3 est **③ L19-reporting** (définitions uniques des
indicateurs, I-08).
