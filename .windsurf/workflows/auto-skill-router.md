---
description: "Auto-Skill Router - Sélectionne et active automatiquement le(s) meilleur(s) skill(s) pour chaque tâche. OBLIGATOIRE avant toute exécution."
---

# Auto-Skill Router (Obligatoire)

> **RÈGLE ABSOLUE**: Aucune tâche ne doit être exécutée sans qu'au moins un skill soit activé. Ce workflow doit être exécuté EN PREMIER pour chaque request utilisateur.

## Phase 1: Analyse de la request

Analyser la request de l'utilisateur et la classifier dans une ou plusieurs catégories:

1. **Lire la request** et identifier les mots-clés/intentions
2. **Charger le registry**: Lire `.windsurf/skills/skill-registry.json`
3. **Matcher** les mots-clés contre les `task_routing[].match` du registry
4. **Sélectionner** le(s) skill(s) avec le meilleur score de correspondance

## Phase 2: Sélection du/des skill(s)

Pour chaque catégorie matchée:

### Règles de sélection
- Si 1 seul skill matche avec confiance ≥ 0.6 → **activer ce skill**
- Si plusieurs skills matchent → **activer le skill avec la plus haute priorité** (priority: 1 > 2 > 3)
- Si aucun skill ne matche avec confiance ≥ 0.6 → **activer le fallback** de la meilleure catégorie
- Si aucune catégorie ne matche → **demander à l'utilisateur** quel skill il souhaite utiliser parmi la liste

### Skills multiples
- Si la request couvre plusieurs domaines (ex: "corriger bug + vérifier design") → **activer plusieurs skills en séquence**
- Ordre: skill de sécurité > skill de qualité > skill de design > skill de performance

## Phase 3: Activation du skill

1. **Annoncer** à l'utilisateur: "Skill activé: [skill-name] — [description]"
2. **Invoquer** le skill via `skill` tool: `skill(SkillName: "[skill-name]")`
3. **Lire** les instructions du skill retournées
4. **Exécuter** la tâche en suivant les instructions du skill

## Phase 4: Exécution avec le skill

- Suivre STRICTEMENT les instructions/guidelines du skill activé
- Si le skill requiert des sous-étapes, les exécuter dans l'ordre
- Si le skill détecte des problèmes, les corriger selon les guidelines du skill
- Si le skill recommande l'activation d'un autre skill complémentaire, l'activer

## Phase 5: Validation post-skill

Après exécution du skill:
1. Vérifier que les livrables du skill sont complets
2. Si le skill a un volet validation (ex: `tsc --noEmit`, `npm run dev`), l'exécuter
3. Si des problèmes subsistent, activer un skill complémentaire

## Mapping des catégories → skills (Compta)

| Catégorie | Mots-clés typiques | Skill principal | Fallback |
|-----------|-------------------|-----------------|----------|
| QA Testing | test, qa, qualité, vérifier | `qa` | `qa-only` |
| Audit | audit, rapport, inspecter | `qa-only` | `qa` |
| Code Review | review, pr, diff | `review` | — |
| Debugging | bug, erreur, crash, fix | `investigate` | `qa` |
| Security | sécurité, rls, xss, auth | `cso` | `careful` |
| Destructive | drop, delete, truncate | `careful` | `guard` |
| Design UI | design, ui, visuel, spacing | `design-review` | `design-consultation` |
| Design System | design system, refonte, palette | `design-consultation` | `design-review` |
| Performance | perf, lenteur, bundle, lcp | `web-perf` | — |
| Spec Planning | spec, requirements, planifier | `spec` | — |
| Shipping | ship, déployer, merge, release | `ship` | — |
| Code Health | dette tech, quality, health | `health` | — |
| Documentation | doc, readme, documenter | `document-generate` | `document-release` |
| Cloudflare | cloudflare, workers, kv, d1 | `cloudflare` | `wrangler` |
| Implementation | implémenter, créer, ajouter | `spec` | `review` |
| Multi-agent | multi agent, sprint, parallèle | `spec` | `review` |

## Exemples

### Exemple 1: "Corrige le bug dans la page JournalSaisie"
1. Analyse: "bug" + "corriger" → catégorie `debugging`
2. Skill sélectionné: `investigate`
3. Activation: `skill("investigate")`
4. Exécution: Root cause investigation sur JournalSaisiePage.tsx

### Exemple 2: "Vérifie la qualité de toutes les pages"
1. Analyse: "vérifier" + "qualité" → catégorie `qa_testing`
2. Skill sélectionné: `qa`
3. Activation: `skill("qa")`
4. Exécution: QA systématique sur toutes les pages

### Exemple 3: "Implémente le module de rapprochement bancaire"
1. Analyse: "implémente" + "module" → catégorie `implementation` + `spec_planning`
2. Skills sélectionnés: `spec` puis `review`
3. Activation: `skill("spec")` → spec du module → puis `skill("review")` après implémentation
4. Exécution: Spec → implémentation → review

### Exemple 4: "Sécurise les RLS Supabase"
1. Analyse: "sécurise" + "rls" + "supabase" → catégorie `security`
2. Skill sélectionné: `cso`
3. Activation: `skill("cso")`
4. Exécution: Audit sécurité RLS
