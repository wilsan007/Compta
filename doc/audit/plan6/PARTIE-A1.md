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
| A1.a | Fin d'A.2 : maillons RPC restants après `T10` — croiser `create_pos_ticket`, `pos_refund_ticket`, `payroll_post_run`, `payroll_payment_inner`, `post_bank_statement_line` avec la grille du [rapport par maillon](A1-RAPPORT-PAR-MAILLON-2026-10-05.md) ; tracer ou rayer chacun | 3.3 | ≈ 1 j | 🟡 en cours (`T10` livré le 05/10) |
| A1.b | A.3 : les **3** invariants encore « non mesurables » (le recomptage du 05/10 dit 3, pas 6) ; relevé nocturne et alerte (`414` — reprendre la suite `T07` rouge : la propriétaire ne voit pas sa propre alerte) | 3.8, 3.9 | ≈ 2 j | ⬜ |

⚠️ La part **écran** de la tâche 3.10 (lecture de l'indice, `chainCoherence.ts`)
part chez **A2** (tâche A2.4).

## Journal

*(une ligne par lot poussé, avec la date et le verdict de la batterie —
l'historique jusqu'au 05/10 midi est dans
[PARTIE-A.md](PARTIE-A.md))*
