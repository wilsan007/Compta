---
description: Multi-agent parallel implementation protocol for Odoo gaps (42 elements)
---

# Multi Agent Impliment Protocol

## Trigger
When user says "multi agent impliment", execute this workflow automatically.

## Super Agent (Orchestrator) = Cascade

### Step 1: Plan Analysis
- Read `PLAN-IMPLEMENTATION-ODDO-GAPS-42-ELEMENTS.md`
- Determine current sprint (track in todo_list)
- Select elements for this sprint

### Step 2: Launch Implementation Agents (5+ parallel)
Use code_search for research, then edit/write_to_file for implementation:

- **Agent SQL**: Create migration files in `app/sql/`
- **Agent Types**: Update `app/src/types/index.ts`
- **Agent Lib/Logic**: Create libs in `app/src/lib/`
- **Agent UI/Pages**: Create/modify pages in `app/src/pages/`
- **Agent i18n/Routes**: Update i18n locales + `app/src/App.tsx`

### Step 3: Launch Validation Agents (3 parallel)
Use code_search to audit:

- **Agent QA-UI**: Pages structure, useTranslation, empty states, badges
- **Agent Logique Métier**: Queries, calculations, business logic coherence
- **Agent SQL/Intégration**: SQL migrations, types, routes, i18n keys

### Step 4: Fix & Validate
- Super Agent collects findings
- Fixes bugs
- Runs `npx tsc --noEmit` in `/app`
- Runs `npm run dev` + browser_preview
- Advances to next sprint

## Sprints
1. Sprint 1: #1, #88, #57 — Types comptes + taux change + devise journaux
2. Sprint 2: #33, #79, #85 — Devise écritures + comptes + paiements
3. Sprint 3: #21, #11, #18, #20 — Taxes avancées
4. Sprint 4: #32, #56, #66, #22 — Position fiscale + tags
5. Sprint 5: #45, #46, #30, #34, #39, #40, #42, #47 — Analytique + écritures
6. Sprint 6: #62, #63, #64, #65, #90, #91, #92, #93 — Tiers + immobilisation
7. Sprint 7: #69, #70, #72, #80 — Banque
8. Sprint 8: #5, #9, #86, #87, #89, #82, #12-24 — Finalisation

## Rules
- All new pages must use useTranslation (fr/en/ar)
- All new SQL tables must have RLS policies
- Validate with tsc --noEmit after each sprint
