// LOT7-03 — décision de l'en-tête `Range` par défaut sur les requêtes REST.
//
// Extrait de `supabase.ts` pour être testable : ce module n'a aucun effet de bord
// (pas de `createClient`, pas de lecture d'`import.meta.env`), là où `supabase.ts`
// est mocké globalement par `src/test/setup.ts`.
//
// `.range()` et `.limit()` de postgrest-js n'écrivent PAS d'en-tête Range — ils posent
// `offset=` / `limit=` dans l'URL (voir PostgrestTransformBuilder). Le garde-fou
// d'origine (`headers.has('Range')`) était donc TOUJOURS faux et son commentaire
// inexact : toute requête explicitement paginée recevait quand même `Range: 0-999`.
// Pire, PostgREST combine en-tête et paramètres : `Range: 0-999` avec `offset=1000`
// produit une limite négative et une réponse **HTTP 416 / PGRST103** — vérifié sur un
// PostgREST 16.3 réel, la 2ᵉ page d'une pagination échouait donc systématiquement.
// La pagination explicite se détecte sur l'URL, pas sur les en-têtes.
export function shouldSetDefaultRange(
  url: string,
  method: string | undefined,
  headers: Headers
): boolean {
  const isGetRequest = !method || method === 'GET'
  if (!isGetRequest) return false
  if (!url.includes('/rest/v1/')) return false
  if (headers.has('Range') || headers.has('range')) return false
  if (/[?&](offset|limit)=/.test(url)) return false
  return true
}
