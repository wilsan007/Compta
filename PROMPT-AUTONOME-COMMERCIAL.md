# PROMPT AUTONOME — Module Commercial → Sage 100 100%

## PERMISSIONS UPFRONT (une seule fois)

Accorder pour toute la durée :
1. Créer/éditer : `app/sql/`, `app/src/types/`, `app/src/lib/`, `app/src/pages/`, `app/src/i18n/`, `App.tsx`, `app/src/lib/supabase.ts`
2. Exécuter : `npx tsc --noEmit --pretty` dans `/app`, `npm run dev`, `browser_preview`
3. Rechercher : `code_search`, `grep_search`, `read_file` sur tout le projet
4. Créer : `app/src/__tests__/logic-business-commercial.test.ts`

**SQL** : L'agent crée les fichiers `.sql` dans `app/sql/`. L'utilisateur les exécutera manuellement dans Supabase Dashboard. L'agent n'exécute PAS le SQL.

**Aucune autre permission demandée pendant l'exécution.**

---

## MÉTHODOLOGIE

Répliquer la méthodologie du module comptabilité (voir `PLAN-IMPLEMENTATION-FINAL-SAGE100-COMPTA.md` pour référence).

### Cycle par sprint
1. Lire le plan du sprint dans le fichier `PLAN-COMMERCIAL-PARTIE-X.md` correspondant (voir tableau ci-dessous)
2. Implémenter en parallèle (5 axes) : SQL → Types → Queries → Pages → i18n/Routes
3. Valider en parallèle (3 axes) : QA-UI, Logique métier, SQL/Intégration
4. Corriger les bugs
5. Checkpoints : `tsc --noEmit` + `npm run dev` + `browser_preview`
6. Si échec → auto-correction (max 3 tentatives) → sprint suivant

---

## ORDRE DES SPRINTS

| Sprint | Plan source (à lire on-demand) | Focus |
|---|---|---|
| A | `PLAN-COMMERCIAL-PARTIE-1.md` | Transformations cycle commercial |
| B | `PLAN-COMMERCIAL-PARTIE-2.md` (§ Sprint B) | Clients avancés + Customer 360° |
| C | `PLAN-COMMERCIAL-PARTIE-2.md` (§ Sprint C) | Achats avancés |
| D | `PLAN-COMMERCIAL-PARTIE-3.md` (§ Sprint D) | Catalogue étendu |
| E | `PLAN-COMMERCIAL-PARTIE-3.md` (§ Sprint E) | Stock avancé |
| F | `PLAN-COMMERCIAL-PARTIE-4.md` (§ Sprint F) | CRM Force de Vente |
| G | `PLAN-COMMERCIAL-PARTIE-4.md` (§ Sprint G) | CRM Service Client |
| H | `PLAN-COMMERCIAL-PARTIE-5.md` (§ Sprint H) | POS / Saisie de caisse |
| I | `PLAN-COMMERCIAL-PARTIE-5.md` (§ Sprint I) | Dématérialisation |
| J | `PLAN-COMMERCIAL-PARTIE-5.md` (§ Sprint J) | Pilotage & Reporting |
| K | `PLAN-COMMERCIAL-PARTIE-5.md` (§ Sprint K) | Finalisation i18n |

**Ordre** : A → (B+C) → (D+E) → (F+G) → H → I → J → K
**K en parallèle dès Sprint A** (i18n au fur et à mesure).

---

## RÈGLES OBLIGATOIRES

### i18n
- `useTranslation` obligatoire sur toute nouvelle page/composant
- 3 langues : fr, en, ar (RTL)
- Fichiers : `app/src/i18n/locales/{fr,en,ar}/<namespace>.json`
- Nouveaux namespaces à déclarer dans `app/src/i18n/index.ts` : `purchases`, `crm`, `pos`
- Clés communes (`common.*`) pour actions génériques
- Nouvelles routes dans `nav.json` (fr/en/ar)

### TypeScript
- Interfaces dans `app/src/types/index.ts`
- Types stricts, reflètent exactement les colonnes SQL
- Pas de `any` (sauf jsonb dynamique)

### Queries
- Toutes dans `app/src/lib/queries.ts`
- Filtrage `tenant_id` obligatoire (`getTenantId()`)
- `if (error) throw error`

### Pages
- Composants UI existants (shadcn/ui)
- États : loading (skeleton), empty (empty state), error (toast)
- `formatCurrency` / `formatDate` pour l'affichage
- Badges pour statuts

### SQL
- `tenant_id` + `ON DELETE CASCADE` sur toutes les tables
- `ENABLE ROW LEVEL SECURITY` + policy `allow_all_*`
- `CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` (idempotent)
- Index sur FK et colonnes filtrées

### TENANT_TABLES
- Ajouter toutes les nouvelles tables dans le set `TENANT_TABLES` de `app/src/lib/supabase.ts`

### Routes
- Dans `App.tsx` avec lazy loading pour nouvelles pages

---

## CHECKPOINTS PAR SPRINT

1. `npx tsc --noEmit --pretty` → 0 erreur
2. `npm run dev` → démarre sans erreur
3. `browser_preview` → page se charge
4. Cohérence SQL → Type → Query → UI
5. i18n : toutes les clés `t()` existent dans fr/en/ar
6. Routes : chaque page a une route dans `App.tsx` + entrée dans `nav.json`

---

## SQL CONSOLIDÉ

À la fin de tous les sprints, générer `app/sql/COMMERCIAL_MODULE_ALL_SPRINTS.sql` contenant tous les DDL des sprints A-J. L'utilisateur l'exécutera en une fois dans Supabase Dashboard.

---

## DÉMARRAGE

1. Créer un `todo_list` avec les 11 sprints
2. Lire `PLAN-COMMERCIAL-PARTIE-1.md` pour le Sprint A
3. Implémenter le Sprint A
4. Valider
5. Passer au sprint suivant
6. À la fin : générer le SQL consolidé + tests de logique métier
7. Signaler : "SQL prêt à exécuter dans Supabase Dashboard"
