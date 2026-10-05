# Inventaire des chaînages — Combien fait, combien reste (02/10/2026)

> **Mesuré en base**, pas recopié d'un document. Source : conteneur
> `compta-pg16`, base `test_compta2` (la seule des trois locales qui porte les
> tables `chain_traces`, `document_effects` **et** `chain_invariants`).
> Lecture seule — aucun fichier de `app/sql/` ni de `app/src/` n'a été touché.

## 0. Résumé

| Lot | État | Ce qui est acquis / ce qui manque |
|---|---|---|
| **L0** socle | ✅ **clos** | tables, maillons, gabarit de test |
| **L1** maillons | 🟡 **presque clos** | **23 effets tracés + la caisse (412)** ; il reste les maillons **RPC** |
| **L2** portes G1→G7 | ✅ **clos** | 7 portes |
| **L7** contrats d'effet | ✅ **clos** | **64 contrats**, **28 effets** distincts |
| **L3** maillons RPC + banc D1→D8 | 🔴 **ouvert** | **0 / 62** chaînages éprouvés |
| **L4** indice de cohérence | 🟡 **à moitié** | **13 / 20** invariants mesurables ; **7** non mesurables |
| **L5** pages Robustesse / Cohérence | 🔴 **non commencé** | → partie 4 |
| **L6 → L24** | ⚪ **non commencé** | ≈ 100 j — horizon suivant |

## 1. Ce qui est compté en base

### 1.1 Les effets tracés (L1)

| Mesure | Valeur |
|---|---|
| Lignes dans `chain_traces` | **584** (538 `applique`, 28 `ignore`, 11 `tolere`, 7 `sans_effet`) |
| **Effets distincts tracés** | **26** |
| Effets distincts **déclarés** dans `document_effects` | **28** |
| Contrats dans `document_effects` | **64** |

⚠️ **Une réserve d'honnêteté sur les 6 « 28 − 26 = 2 »** : l'écart apparent est
de **6 effets déclarés sans trace** :

`expense.report.generated_entry`, `expense.report.payroll_element`,
`production.order.generated_entry`, `production.order.stock_in`,
`treasury.bank_account.account`, `treasury.bank_account.journal`

**Ce ne sont PAS des maillons manquants.** Vérifié : chacun est posé par une
migration (`400`, `401`, `404`) **et** exercé par une suite
(`400_…_tests`, `401_…_tests`, `404_…_tests`). Ils n'apparaissent pas dans
`chain_traces` parce que **`test_compta2` est un instantané périmé** : son
`sql_migrations_tracker` compte **270 lignes** et s'arrête à
`99_sprint7_bank_features.sql` — les chaînages `400` → `413` n'y sont **pas**
posés, même si leurs tables existent. **Le chiffre à retenir est donc
26/28 sur un snapshot, et le vrai chiffre se mesurera sur le rejeu base neuve.**

### 1.2 Le catalogue d'invariants (L4) — il est propre

| Mesure | Valeur |
|---|---|
| Lignes dans `chain_invariants` | 32 |
| **Catalogue réel** (`tenant_id IS NULL AND actif`) | **20** |
| — dont **mesurables** | **13** |
| — dont **non mesurables**, chacun avec sa raison écrite | **7** (`INV-05, 06, 07, 08, 10, 12, 19`) |

Les 12 lignes supplémentaires sont des **jeux d'essai** des suites
(`actif = false`, un tenant par ligne) — par exemple `INV-20 / 'Choix de A'`
apparaît 4 fois. **Ce n'est pas une pollution du catalogue** : le code
`INV-01` → `INV-20` y est complet, sans trou, et `INV-20` global porte le bon
libellé. Les 7 non mesurables ont tous une `raison_non_mesurable` renseignée,
ce qui satisfait déjà la moitié de la tâche 3.8 (« ou en retirer avec raison
écrite »).

## 2. Ce qui reste — chiffré par le plan et par la base

### 2.1 Tâche 3.8 — les 7 invariants non mesurables (1 j)
Rendre mesurables `INV-05, 06, 07, 08, 10, 12, 19` → **13/20 → 20/20**, ou les
retirer avec raison. Chaque raison existe déjà en base.

### 2.2 Tâches 3.1 → 3.3 — les maillons RPC (≈ 2 j)
D'après l'[inventaire tranche 4](INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md),
les maillons **RPC / interne / sans déclencheur** encore « à tracer » sont :

| Maillon | Verdict de l'inventaire | Tâche |
|---|---|---|
| `create_pos_ticket` | Maillon / RPC (ticket de caisse) | 3.3 |
| `pos_refund_ticket` | Maillon / RPC (avoir + retour stock) | 3.3 |
| `payroll_post_run` | Maillon / RPC (bulletin → écriture) | 3.3 |
| `payroll_payment_inner` | Maillon interne (versement) | 3.2 |
| `post_bank_statement_line` | Maillon / RPC (relevé → lettrage) | 3.3 |
| `generate_depreciation_entry` | Maillon sans déclencheur (job) | lot L4 |

Soit **6 maillons** au catalogue. La caisse (`post_pos_session_on_close_multi`)
est **déjà faite** en `412` — la tâche 3.1 demande de la rayer de la liste.

### 2.3 Tâches 3.4 → 3.7 — le banc d'épreuves D1→D8 (≈ 5 j)

C'est **le plus gros reste** et il n'a pas commencé : **0 / 62** chaînages
éprouvés. Il faut le moteur paramétré, le rapport par maillon, puis les 8
épreuves (rejeu, concurrence, panne partielle, annulation, réouverture, retour
arrière, volume, isolation).

### 2.4 Tâche 3.9 — relevé nocturne (0,5 j)
`414_chain_l4_alerte_degradation.sql` est **écrit et commité** (`e3110ef`,
989 lignes sur `partie-3-chainages`) mais **en pause**. Sa suite est **rouge
sur T07** (isolation : la propriétaire ne voit pas sa propre alerte). Ce n'est
donc pas encore acquis.

> **↳ Réconcilié le 05/10/2026 (intégration).** Rejouée sur base neuve complète,
> la suite `414` rend **7/7** — `T07` **vert**. Le rouge n'était pas un défaut
> d'isolation : le scénario posait la faute **avant** le relevé sain, d'où un
> motif `deja_rompu` sans alerte ; l'ordre est rétabli et « la propriétaire ne
> voit pas sa propre alerte » **n'est pas reproduite** (lot A1, `plan6/a-chainages`).

### 2.5 Tâche 3.10 — lecture écran de l'indice (0,5 j)
En cours par l'autre session (`chainCoherence.ts`).

## 3. La conclusion, en une phrase

**Le socle est bon et L1 est à un cheveu de sa fin** (les 6 maillons RPC
restants) ; **le gros du travail restant n'est pas du L1, c'est le banc
d'épreuves D1→D8 (0/62, ≈ 5 j) et l'horizon L6→L24 (≈ 100 j).**

Attention à ne pas lire « 26 effets tracés » comme « presque tout est fait » :
le plan exige **62/62 éprouvés** au banc, et l'inventaire L1 pose lui-même la
question du dénominateur (62 par la **mesure**, moins de 62 par la **nature** —
19 des 30 fonctions inspectées ne seront jamais instrumentées, c'est écrit noir
sur blanc dans l'inventaire). **Le chiffre final de L1 doit être tranché avant
d'être publié**, sinon l'indicateur ne peut pas atteindre 62/62 sans mentir.