// ============================================================
// W6 — stub de `serve` pour les tests d'entrée des fonctions Edge.
//
// Chaque fonction appelle `serve(handler)` au chargement du module. Le stub
// retient le gestionnaire, et le test l'appelle avec la requête qu'il veut.
//
// CE QUE CES TESTS PROUVENT, ET CE QU'ILS NE PROUVENT PAS : ils exécutent le
// **contrat d'entrée** de chaque fonction (« sans jeton, elle refuse »). Ils
// n'exécutent pas les parcours complets (base, prestataires) : pour cela, la
// CI démarre un Postgres réel pour les suites SQL, et les intégrations
// (Chorus Pro, Yousign, GoCardless, Resend, EFI) demandent des comptes
// configurés — c'est dit, pas contourné.
// ============================================================

export type EdgeHandler = (req: Request) => Promise<Response> | Response

export function serve(handler: EdgeHandler, _options?: unknown): void {
  ;(globalThis as unknown as { __edgeHandler?: EdgeHandler }).__edgeHandler = handler
}

export function getEdgeHandler(): EdgeHandler {
  const h = (globalThis as unknown as { __edgeHandler?: EdgeHandler }).__edgeHandler
  if (!h) throw new Error("Aucun gestionnaire enregistré : la fonction n'a pas appelé serve()")
  return h
}
