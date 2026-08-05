# Checklist de Vérification Définitive

> **Usage**: Cocher chaque case après vérification. Le code n'est prêt pour production que quand **toutes** les cases sont cochées.
> Le script `npm run verify` automatise les vérifications mécaniques (❍). Les vérifications sémantiques (◇) nécessitent une revue manuelle.

## Lancement rapide

```bash
# Vérification complète (tsc + lint + i18n + audit + tests)
npm run verify

# Vérification rapide (sans tests ni lint, pour itérer rapidement)
npm run verify:fast
```

---

## 1. TypeScript & Type Safety

- [ ] ❍ `tsc --noEmit` passe avec 0 erreur
- [ ] ◇ Pas de `as any` dans `src/pages/` (vérifié par test R6)
- [ ] ◇ Pas de `tid!` non-null assertion dans `src/lib/queries/` (vérifié par test R1)
- [ ] ◇ Pas de `!` non-null assertion sur des valeurs qui pourraient être null/undefined
- [ ] ◇ Les types d'interface (`types.ts`) couvrent tous les champs utilisés dans le code
- [ ] ◇ Pas de type mismatch entre les colonnes Supabase et les interfaces TypeScript

## 2. Multi-tenant (tenant_id)

- [ ] ◇ Toutes les queries Supabase filtrent par `tenant_id` (via `tud()` ou `if (tid)`)
- [ ] ◇ Aucune query ne utilise `.eq('tenant_id', tid!)` (assertion non-null)
- [ ] ◇ Les fonctions `delete` et `update` vérifient le tenant_id avant modification
- [ ] ◇ Les RLS policies sont activées sur toutes les tables tenant-scoped
- [ ] ◇ Pas de query qui retourne des données cross-tenant

## 3. Internationalisation (i18n)

- [ ] ❍ `check-i18n.mjs` passe: parité des clés fr/en/ar (vérifié par test R7)
- [ ] ◇ Toutes les pages importent `useTranslation` (vérifié par test R5)
- [ ] ◇ Pas de texte français hardcoded dans les `.tsx` (vérifié par test R4 du script)
- [ ] ◇ Pas de symbole `€` hardcoded (utiliser `formatCurrency`) (vérifié par test R2)
- [ ] ◇ Pas de `'...'` pour le saving state (utiliser `tCommon('actions.saving')`) (vérifié par test R3)
- [ ] ◇ Les `toast()` utilisent `tCommon('toast.success')` et non `tCommon('common.success')`
- [ ] ◇ Les `tCommon('table.actions')` et non `tCommon('common.table.actions')`
- [ ] ◇ Toutes les nouvelles clés i18n sont ajoutées dans les 3 langues (fr, en, ar)
- [ ] ◇ Pas de clé i18n référencée dans le code qui n'existe pas dans les JSON

## 4. UI Consistency

- [ ] ◇ Pas de caractère `✕` (utiliser `<X />` de lucide-react) (vérifié par test R4)
- [ ] ◇ Pas de `<select>` HTML natif (utiliser le composant `Select`)
- [ ] ◇ Pas de `<input>` HTML natif (utiliser le composant `Input`)
- [ ] ◇ Les statuts utilisent le composant `Badge` avec les bonnes variantes
- [ ] ◇ Les états de chargement utilisent `SkeletonTable` (pas de spinner générique)
- [ ] ◇ Les états vides utilisent `EmptyState` (pas de div avec texte simple)
- [ ] ◇ Les boutons de soumission utilisent `loading` state avec i18n
- [ ] ◇ Les tableaux utilisent le composant `Table` / `TableRow` / `TableCell`

## 5. Sécurité

- [ ] ◇ Pas de secret/API key hardcoded dans le code source
- [ ] ◇ Les Supabase queries utilisent les helpers tenant-aware (`tud`, `ti`)
- [ ] ◇ Les Edge Functions valident l'authentification
- [ ] ◇ Pas de `dangerouslySetInnerHTML` sans sanitization
- [ ] ◇ Les uploads de fichiers valident le type et la taille

## 6. Tests

- [ ] ❍ `vitest run` passe avec 0 échec
- [ ] ❍ Les tests d'audit (`audit-code-quality.test.ts`) passent
- [ ] ◇ Les nouvelles fonctionnalités ont des tests
- [ ] ◇ Les corrections de bugs ont des tests de régression

## 7. Lint

- [ ] ❍ `oxlint --max-warnings=0` passe
- [ ] ◇ Pas d'import inutilisé
- [ ] ◇ Pas de variable déclarée mais non utilisée

---

## Historique des passages

| Date | Script | tsc | Lint | i18n | Audit | Tests | Status |
|------|--------|-----|------|------|-------|-------|--------|
| _À remplir_ | `npm run verify` | — | — | — | — | — | — |

> **Note**: Chaque passage doit mettre à jour ce tableau. Le code est prêt quand toutes les colonnes sont ✅.
