# Audit documentaire — l'état réel de la partie 1 au 02/10/2026 (17:40)

> **Ce document ne corrige rien.** C'est un **relevé de mesures**, fait en lecture
> seule pendant que la partie 1 était exécutée par une autre session dans le même
> dossier de travail. Aucun fichier de `app/sql/` ni de `app/src/` n'a été touché.
>
> Objet : permettre à la session qui porte la partie 1 de ne pas refaire une mesure
> déjà faite, et de voir d'un coup d'œil ce qui reste.

## 0. Avertissement de méthode — pourquoi ce document existe

Une **deuxième session** exécutait déjà la partie 1 dans le dossier principal au
moment de l'audit. Preuves relevées :

| Fait | Mesure |
|---|---|
| Session d'agent active | PID **65039**, scratchpad `/private/tmp/claude-501/-Users-awalehosman-Desktop-Projet-Saas-compta/…` |
| Écriture réelle pendant l'audit | `app/src/lib/queries/chainCoherence.ts`, mtime 17:36:13 → **17:37:45** (observé) |
| Branche créée pour la partie 1 | `partie-1-stabiliser`, commit `ab7b697` (17:33:48) |
| Ordre suivi, cité dans le commit | « 1.0 → 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 → (1.8, 1.10, 1.11, 1.13) → 1.9 → 1.12 » |
| Tâche **1.0** déjà faite | commit `e3110ef` : la `414` est committée sur `partie-3-chainages` (tâche 3.9) et **mise en pause** ; `_r414.sql`, `_t01…_t07.txt` déplacés hors de `app/sql/` |
| Tâche **1.1** en cours | `chainCoherence.ts` vise nommément la garde `check-unused-tables.mjs` (77 > 75) |

**Règle 1 du plan** : « Une partie = une branche = une session active. » Ce
document respecte cette règle en **ne touchant pas** `app/sql/` ni `app/src/`.
Il n'est ni un travail de la partie 1, ni un travail de la partie 2 : c'est une
**mesure**, dont la valeur est de prouver que la partie 1 est bien la suite
immédiate, et que la partie 2 reste fermée.

## 1. Pourquoi la partie 2 est fermée (et le restera)

Le § 0 de la partie 2 pose : « **Entrée** : la partie 1 est close (une seule
branche, CI GitHub verte). » Mesures sur le dépôt réel :

| Fait | Mesuré |
|---|---|
| **CI rouge** sur `commercial-hr-paie` | 4 passages rouges le 02/10 ; dernier `37015796916` |
| ↳ job `DB Integration Tests` | `ERROR: Les types générés diffèrent` → **tâche 1.1** |
| ↳ job `Lint & Type Check` | `77 tables non lues > plafond 75` → **tâche 1.1** |
| **Fusion 1.6 non faite** | `merge/recette-2026-10-02` (`4e15326`) n'est **pas** ancêtre de `c51d468` — 49 commits de recette absents |
| **Tâche 2.1 sans support** | `321_payroll_variable_elements_tests.sql` **n'existe pas** sur la branche courante |
| **Registre vide** | `ci/expected_failures.sql` ne contient **aucune** ligne active : les `321 T02/T03/T05` à corriger arrivent **avec** la fusion |

⚠️ **Conséquence directe** : corriger 2.1 avant 1.6 reviendrait à écrire un
correctif pour un fichier de test et un registre qui n'existent pas encore sur la
branche de travail. La tâche serait silencieusement perdue à la fusion.
## 2. Relevé tâche par tâche (partie 1)

État **au 02/10/2026 17:40**, mesuré sur `partie-1-stabiliser` (`ab7b697`).

| # | Tâche | État | Mesure |
|---|---|---|---|
| 1.0 | Inventaire et gel des travaux en vol | ✅ **fait** | `e3110ef` : `414` commitée et en pause, fichiers de travail sortis de `app/sql/` (règle 8) |
| 1.1 | `commercial-hr-paie` au vert | 🔶 **en cours** | les 2 portes rouges ci-dessus ; `chainCoherence.ts` écrit pour le plafond des tables |
| 1.2 | Faux vert de la caisse | ⬜ **ouvert** | `412_chain_l1_caisse_rpc_tests.sql` : **0** occurrence de `_audit_assert` — la suite ne lève jamais |
| 1.3 | Garde anti-faux-vert | ⬜ **ouvert** | `check-test-suites.mjs` ne parle de `_audit_assert` que dans ses commentaires (l. 10, 25), **pas** dans une règle |
| 1.4 | CI sur les branches de travail | ⬜ **ouvert** | `ci.yml` : `branches: [main, master, develop, commercial-hr-paie]` — ni `qa/**` ni `partie-*` |
| 1.5 | Réparer la branche QA avant fusion | ⬜ **ouvert** | non mesuré en détail ici ; porte 1.5, **préalable obligatoire** à 1.6 |
| 1.6 | Fusionner la recette | ⬜ **ouvert** | 49 commits entre `c51d468` et `4e15326` |
| 1.7 | Récupérer le correctif TVA 198 | ⬜ **ouvert** | `claude/tva-saisie-ca3` existe encore (`3d478ba`) ; `get_vat_codes` **absent** du code courant — le défaut est toujours reproductible |
| 1.8 | Vrai dialogue de confirmation | ⬜ **ouvert** | **97** fichiers portent `confirmSync` ; `useConfirm`/`confirmDialog` présents dans **4** fichiers seulement |
| 1.9 | Ménage et documents | ⬜ **ouvert** | **10** worktrees actifs ; plages des parties **non inscrites** (`NUMEROTATION-MIGRATIONS.md` dit encore `325 → 399 LIBRE`) |
| 1.10 | Champs factices du plan comptable | ⬜ **ouvert** | `ChartAccountsPage.tsx` l. 617-621 : `nbLines`, `pageBreak`, `regrouping` — `defaultValue`, **aucun `onChange`**, donc jamais enregistrés |
| 1.11 | Fin de D-5 côté code | ⬜ **ouvert** | `parse-bank-statement` et `ai-import-mapping` : **aucune** garde `409` ; le modèle `ocr-invoice-import` l'a (`OCR_CONSENT_REQUIRED`) |
| 1.13 | D-4, voie A | ✅ **fait** | `generate-pdf/index.ts` l. 106-116 rend `503` sans `GOTENBERG_URL`, et le test existe |
| 1.12 | Rejeu de contrôle final | ⬜ **en attente** | dépend de tout le reste |

### La référence à battre (tâche 1.12)

Passage `36979512386` (02/10, 07:37) — **le seul vert** de la journée :

| Job | Verdict |
|---|---|
| Lint & Type Check · i18n · Edge Functions · Chemin de l'écran · DB Integration · Unit Tests · Production Build | ✅ vert |
| **E2E Tests (Playwright)** | ⬜ **skipped** → c'est la tâche **4.3** |
| **Security Audit** | ⬜ **skipped** |

Le compte du plan est « ≥ 747 scénarios verts, 125 verdicts écran, 1 534 Vitest,
36 Edge » ; les 2 jobs sautés sont à traiter en partie 4 (AUD-J01).

## 3. Ce qui est prêt pour la partie 2 (à revérifier à son jour)

Vérifié disponible, **sans qu'aucune tâche de la partie 1 ait à le produire** :

- **Plage `340` → `369` libre** ✓ — les fichiers `34_` et `35_` sont des
  historiques à **deux chiffres**, pas des prises dans la plage ;
- **`tsc` vert** ✓ et **plafond des `any` vert** ✓ (988 production + 796 tests =
  1 784) — la voie C de `c51d468` tient ;
- **PostgreSQL 16 disponible** pour les rejeux sur base neuve : conteneur
  `compta-pg16` (port 5433), bases `test_compta` et `test_compta2` ;
- les portes `check_plpgsql`, `check_anon_grants` et `check_effects_contract`
  sont déjà câblées dans le job `db-integration`.

## 4. La règle à tenir

Le dépôt a payé le 02/10 deux sessions qui se sont marché dessus
(`NUMEROTATION-MIGRATIONS.md`, « Ce qui s'est passé le 02 octobre »). Pendant que
la partie 1 est portée par une session :

1. **ne rien écrire** dans `app/sql/` ni `app/src/` — y compris « un petit
   correctif sans rapport » ;
2. **ne pas toucher** `app/.unused-tables-ceiling.json` ni le plafond des `any` :
   ce sont des garde-fous, on les relève avec une justification **datée**, on ne les
   déplace pas pour faire verte ;
3. toute mesure se fait **en lecture seule**, et se consigne ici.