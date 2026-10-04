// ============================================================
// W6 — harnais partagé des tests d'entrée des fonctions Edge.
//
// Hors fichier de test À DESSEIN : un test qui importerait un autre fichier de
// test ré-enregistrerait les tests de celui-ci (Deno enregistre `Deno.test` au
// chargement du module) — et les mêmes scénarios seraient comptés deux fois.
//
// Deno met les modules en CACHE : `serve()` n'est appelé qu'au PREMIER import.
// Le gestionnaire est donc capturé une fois par fonction, puis rangé ici.
// ============================================================

import { getEdgeHandler, type EdgeHandler } from "./serve.ts"

// Le harnais vit dans `__tests__/stubs/` : les fonctions sont deux crans plus haut.
const FONCTIONS = "../../"

export interface Contrat {
  fonction: string
  methode?: string
  chemin?: string
  entetes?: Record<string, string>
  corps?: unknown
  /** Code attendu : un REFUS explicite. */
  attendu: number
  /** Vérifié en plus du code : la réponse nomme le refus. */
  motif: RegExp
  env?: Record<string, string>
  /** Pourquoi ce refus est le contrat de cette fonction. */
  raison: string
}

// Les secrets sont posés DANS le test : sans eux, certaines fonctions
// désactivent leur propre garde (un `CRON_SECRET` absent ne se compare à rien).
export const ENV_COMMUN: Record<string, string> = {
  SUPABASE_URL: "https://exemple.supabase.co",
  SUPABASE_ANON_KEY: "anon-de-test",
  SUPABASE_SERVICE_ROLE_KEY: "service-de-test",
  CRON_SECRET: "cron-de-test",
}

const GESTIONNAIRES = new Map<string, EdgeHandler>()

async function gestionnaire(fonction: string): Promise<EdgeHandler> {
  const connu = GESTIONNAIRES.get(fonction)
  if (connu) return connu

  ;(globalThis as unknown as { __edgeHandler?: unknown }).__edgeHandler = undefined
  await import(`${FONCTIONS}${fonction}/index.ts`)
  const h = getEdgeHandler()
  GESTIONNAIRES.set(fonction, h)
  return h
}

/** Exécute une fonction Edge avec la requête du contrat, sans réseau. */
export async function appeler(contrat: Contrat): Promise<Response> {
  for (const [k, v] of Object.entries({ ...ENV_COMMUN, ...(contrat.env || {}) })) {
    Deno.env.set(k, v)
  }
  const handler = await gestionnaire(contrat.fonction)

  const url = `https://exemple.supabase.co/functions/v1/${contrat.fonction}${contrat.chemin || ""}`
  const init: RequestInit = {
    method: contrat.methode || "POST",
    headers: { "Content-Type": "application/json", ...(contrat.entetes || {}) },
  }
  if (init.method !== "GET") init.body = JSON.stringify(contrat.corps ?? {})
  return await handler(new Request(url, init))
}

/** Joue un scénario nominal (jeton posé) et rend le statut et le JSON. */
export async function appelerAvecJeton(
  fonction: string,
  corps: unknown,
): Promise<{ statut: number; json: any }> {
  const reponse = await appeler({
    fonction,
    corps,
    entetes: { Authorization: "Bearer jeton-de-test" },
    attendu: 200,
    motif: /./,
    raison: "chemin nominal",
  })
  return { statut: reponse.status, json: await reponse.json() }
}
