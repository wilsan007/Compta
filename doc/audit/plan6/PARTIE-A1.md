# Partie A1 — preuve et indice

> **Découpage du 05/10 au soir** : la partie A du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md) est scindée en
> **trois lignes parallèles** aux territoires disjoints :
> **A1 — preuve et indice** (ce fichier) ·
> [A2 — Vue Chaîne et écrans](PARTIE-A2.md) ·
> [A3 — moteur L16 → L24](PARTIE-A3.md).
> L'historique du 05/10 (recomptage A.1, rapport par maillon, journal, « la plage
> en fait ») reste dans [PARTIE-A.md](PARTIE-A.md), fichier de famille. Chaque
> ligne écrit désormais dans **son** fichier (R4).

| | |
|---|---|
| **Branche** | `plan6/a-chainages` (existante — A1 reprend la ligne A **là où elle en est**) |
| **Worktree** | `.claude/worktrees/plan6-a-chainages` |
| **Plage de migrations** | `475` → `486` |
| **Territoire de fichiers** | `app/sql/*chain*`, `app/sql/*metric*`, `app/sql/ci/check_chain*`, `app/sql/ci/check_effects*` ; requêtes « cohérence » / « pilotage ». **Les écrans sont à A2 ; les nouveaux maillons L16 → L24 sont à A3** |
| **Charge** | ≈ 3-4 j (fin A.2 + A.3) |
| **Départ possible** | déjà en cours |
| **Décisions bloquantes** | aucune |

## Rappel des règles (R1 → R8)

R1 un worktree · R2 numéro par `prendre` · R3 hors territoire = demande consignée
dans ce fichier · R5 suites sous le marqueur `# --- plan6:a1 ---` · R6 fichiers
générés régénérés par l'intégration · R7 une fonction SQL, un propriétaire ·
R8 lots courts, fusion par l'intégration seule.

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| A1.a | Fin d'A.2 : maillons RPC restants après `T10` — croiser `create_pos_ticket`, `pos_refund_ticket`, `payroll_post_run`, `payroll_payment_inner`, `post_bank_statement_line` avec la grille du [rapport par maillon](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) ; tracer ou rayer chacun | 3.3 | ≈ 1 j | ✅ **fait le 05/10 au soir** — voir §A1.a |
| A1.b | A.3 : les **3** invariants encore « non mesurables » (le recomptage du 05/10 dit 3, pas 6) ; relevé nocturne et alerte (`414` — reprendre la suite `T07` rouge : la propriétaire ne voit pas sa propre alerte) | 3.8, 3.9 | ≈ 2 j | 🟡 **fait le 05/10 au soir** — `414` mesuré **7/7** (T07 **vert**, la note rouge non reproduite) ; les 3 invariants arbitrés → §A1.b |

⚠️ La part **écran** de la tâche 3.10 (lecture de l'indice, `chainCoherence.ts`)
part chez **A2** (tâche A2.4).

## A1.a — le croisement des cinq maillons RPC (fin d'A.2)

**Objet.** Croiser les cinq maillons nommés par le plan avec la grille du
[rapport par maillon](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) : **tracer ou rayer
chacun**.

**Résultat, mesuré sur base neuve (333 migrations).** Chacun est soit **tracé**,
soit **rayé nommément** :

| Maillon nommé | Tracé ? | Ce que c'est |
|---|---|---|
| `create_pos_ticket` | ✅ **tracé** (enveloppe) | caisse — ticket |
| `pos_refund_ticket` | ✅ **tracé** (enveloppe) | caisse — avoir |
| `payroll_post_run` | ✅ **tracé** (enveloppe) | paie comptabilisée |
| `post_payroll_payment` | ✅ **tracé** (enveloppe) | paie versée |
| `payroll_payment_inner` | ⛔ **rayé** | le **corps renommé** de `post_payroll_payment` (`430`, doctrine `412`) : le maillon est son **enveloppe publique**, pas l'`_inner` — l'`_inner` **n'est pas un maillon** et **ne doit pas** être tracé |

**La porte G8 le confirme** (`ci/check_chain_rpc_inventory.sql`, rejoué sur base
complète) : **15 maillons RPC transverses — 7 tracés par leur chemin d'appel,
8 écartés motivés, aucun en attente.** Les sept tracés sont exactement les sept
gestes du banc (les cinq ci-dessus + `reconcile_bank_statement_line` et
`unreconcile_bank_statement_line`). **Il ne reste aucun maillon RPC à tracer** :
c'est la fin d'A.2.

## A1.b — les invariants et le relevé nocturne

**Les trois invariants non mesurables** (le recomptage du 05/10 dit **3**, pas 6)
sont au catalogue `chain_invariants` : **17/20 mesurables**, les trois portant
leur **raison écrite**. Arbitrage du 05/10 :

| Code | Ce qui manque | Arbitrage |
|---|---|---|
| **INV-07** | pas de clé `lettrage_groups` → `journal_lines` | **à faire par A3** (lettrage, L16 → L22) — **reporté**, pas écarté |
| **INV-10** | `dsn_declarations` sans **aucune** colonne numérique | **demande à B** (§Demandes) |
| **INV-12** | deux calculs de marge concurrents (PROJ-02) | **demande à E/F** (§Demandes) |

**Le relevé nocturne et l'alerte (`414`) : mesuré 7/7 verts.** ⚠️ La note
d'ouverture d'A1.b annonçait « `T07` rouge : la propriétaire ne voit pas sa
propre alerte ». **Sur base neuve complète (333 migrations), `T07` est VERT** —
rejoué **deux fois**, sur **deux bases indépendantes** : *« AL6 voit la sienne=1
(1 attendu) | AL7 vues par AL6=0 | AL7 voit la sienne=1 »*, et la suite rend
**7 verts / 0 rouge**. La note **n'est donc pas reproduite**. **À réconcilier par
l'intégration** (base incomplète ? état antérieur de la suite ?) avant de clore
A1.b ; **en l'état, la porte est verte.**

**La part écran de la tâche 3.10** (`chainCoherence.ts` lit `chain_invariants`
et `chain_invariant_results`) **appartient à A2** (tâche **A2.4**). Mesure
transmise : `check-unused-tables` sur base neuve = **75 tables non lues, conforme
au plafond** ; les deux tables d'invariants **ne relèvent pas** le plafond (elles
sont **lues**). A2 n'a donc, a priori, qu'à **brancher la page**.

## Demandes hors territoire (règle R3)

| # | Demande | Vers | Pourquoi |
|---|---|---|---|
| 1 | Ajouter une colonne numérique à `dsn_declarations` (ex. `gross_declared`), **écrite par la génération DSN** | **B** (paie) | rend **INV-10** mesurable |
| 2 | **Choisir le calcul de marge projet unique** (PROJ-02), puis le figer | **E/F** | rend **INV-12** mesurable |
| 3 | Bâtir le lien `lettrage_groups` ↔ `journal_lines` | **A3** (lettrage, L16 → L22) | rend **INV-07** mesurable |

## Ce que cette ligne débloque (à transmettre par l'intégration)

- **Les cinq questions du §6 (`P1` → `P8`) sont TRANCHÉES** — voir
  [§6 bis](../PROPOSITIONS-DIFFERENCIATION-APRES-L24-2026-09-30.md). Elles
  débloquent **A3.4** (« attend vos cinq décisions »).
- **L'expert-comptable référent est considéré désigné** ; ses points de
  validation sont rassemblés dans le
  [dossier de validation](../../validation-expert-comptable/DOSSIER-EXPERT-COMPTABLE-2026-10-05.md)
  — il débloque **B** (paie FR), **C.3** (Djibouti) et **A3.4** (`P1`).
- **L'arbitrage de plage est tranché** : A démarre à `475` (ici **A1 = `475` → `486`**).

## Journal

| Date | Lot | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|
| 2026-10-05 | A1.a | Croisement des 5 maillons RPC : **4 tracés**, `payroll_payment_inner` **rayé** (corps `_inner`, pas un maillon) ; G8 **15 = 7 tracés + 8 écartés**, aucun en attente | inventaire **G8 vert** | *(lot A1)* |
| 2026-10-05 | A1.b | 3 invariants non mesurables arbitrés (INV-07 → A3, INV-10 → B, INV-12 → E/F) ; `414` relevé nocturne + alerte **7/7** (**T07 vert** — la note rouge non reproduite) | `414` **7/7** | *(lot A1)* |

*(l'historique du 05/10 midi — recomptage A.1, rapport par maillon, A.2 — est dans
[PARTIE-A.md](PARTIE-A.md), fichier de famille ; commit `3cf8132` puis `2c9663e`.)*
