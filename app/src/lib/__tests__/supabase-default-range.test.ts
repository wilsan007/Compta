import { describe, it, expect } from 'vitest'

// Logique extraite de supabase.ts dans un module sans effet de bord, pour être testable :
// elle décide de l'en-tête Range posé sur chaque requête REST du client.
import { shouldSetDefaultRange } from '@/lib/supabaseRange'

// ============================================================
// LOT7-03 : en-tête Range par défaut injecté par le client Supabase
//
// `src/lib/supabase.ts` pose `Range: 0-999` sur tout GET non paginé. Or `.range()`
// et `.limit()` de postgrest-js écrivent `offset=` / `limit=` dans l'URL, jamais
// d'en-tête Range — le garde-fou d'origine (`headers.has('Range')`) ne les voyait
// donc pas. PostgREST combinant en-tête et paramètres, `Range: 0-999` avec
// `offset=1000` renvoie **HTTP 416 / PGRST103** : la 2ᵉ page échouait toujours.
// Vérifié sur un PostgREST 16.3 réel (max_rows = 1000, table de 2 003 lignes) :
//   - requête non paginée .......... 1 000 lignes sur 2 003, sans erreur
//   - fetchAllRows + ancien en-tête . HTTP 416 dès offset=1000
//   - fetchAllRows + en-tête corrigé  2 003 lignes, 0 doublon, 0 manquante
// ============================================================
describe('shouldSetDefaultRange', () => {
  const REST = 'https://x.supabase.co/rest/v1/journal_lines?select=*'

  it('pose la limite par défaut sur un GET REST non paginé', () => {
    expect(shouldSetDefaultRange(REST, undefined, new Headers())).toBe(true)
    expect(shouldSetDefaultRange(REST, 'GET', new Headers())).toBe(true)
  })

  it('NE la pose PAS quand l\'URL porte offset= (sinon HTTP 416)', () => {
    expect(shouldSetDefaultRange(`${REST}&offset=1000&limit=1000`, 'GET', new Headers())).toBe(false)
    expect(shouldSetDefaultRange(`${REST}&offset=0&limit=1000`, 'GET', new Headers())).toBe(false)
  })

  it('NE la pose PAS quand l\'URL porte limit= seul', () => {
    expect(shouldSetDefaultRange(`${REST}&limit=50`, 'GET', new Headers())).toBe(false)
    expect(shouldSetDefaultRange('https://x.supabase.co/rest/v1/t?limit=5', 'GET', new Headers())).toBe(false)
  })

  it('NE la pose PAS si un en-tête Range est déjà présent', () => {
    expect(shouldSetDefaultRange(REST, 'GET', new Headers({ Range: '0-9' }))).toBe(false)
  })

  it('NE la pose PAS sur autre chose qu\'un GET', () => {
    for (const method of ['POST', 'PATCH', 'DELETE']) {
      expect(shouldSetDefaultRange(REST, method, new Headers())).toBe(false)
    }
  })

  it('NE la pose PAS hors des routes REST (auth, storage, functions)', () => {
    expect(shouldSetDefaultRange('https://x.supabase.co/auth/v1/token', 'GET', new Headers())).toBe(false)
    expect(shouldSetDefaultRange('https://x.supabase.co/storage/v1/object/f', 'GET', new Headers())).toBe(false)
  })

  it('ne confond pas une colonne nommée « limit » ou « offset » avec une pagination', () => {
    // `select=offset_days` ou un filtre `limit_amount=gt.5` ne sont pas des paramètres de page
    expect(shouldSetDefaultRange('https://x.supabase.co/rest/v1/t?select=offset_days', 'GET', new Headers())).toBe(true)
    expect(shouldSetDefaultRange('https://x.supabase.co/rest/v1/t?limit_amount=gt.5', 'GET', new Headers())).toBe(true)
  })
})
