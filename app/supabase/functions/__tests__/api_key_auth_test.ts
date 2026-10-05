// ============================================================
// ORPH-01 / SEC-02 (partie F, 700) — « UNE CLÉ QU'ON NE PEUT PAS RÉVOQUER
// N'EST PAS UNE AUTHENTIFICATION FORTE »
//
// La preuve demandée par le recomptage n'est PAS « la clé existe », ni « la
// clé expire » — c'est **clé révoquée → 401**. Ce fichier l'exécute :
// la vérité du cycle de vie d'une clé vit dans la base (fonction
// `authenticate_api_key`, migration 700 — elle est exercée pour de bon par la
// suite SQL `700_auth_forte_api_keys_totp_tests.sql`, T01 → T13) ; ici, le
// harnais pose le VERDICT de la base (`__stubRpc`) et prouve que public-api
// l'OBÉIT :
//
//   * révoquée  → 401, et le refus NOMME sa raison (revoked) ;
//   * expirée   → 401 (expired) — l'ancien chemin ne regardait QUE
//                 `active = true` : une clé expirée ouvrait l'API ;
//   * inconnue  → 401 (not_found) ;
//   * contre-épreuve : une clé VALIDE ouvre la garde (200 sur /health) —
//     sans elle, les trois refus ne prouveraient rien (le test passerait
//     à vide si la fonction refusait TOUT).
// ============================================================

import { appeler } from "./stubs/harness.ts"

const CLE = "onu_cle_de_test_public_api_700"

/** Appelle public-api avec la clé, en posant le verdict de la base pour `authenticate_api_key`. */
async function avecCle(
  verdict: { data?: any; error?: any },
  chemin = "/health",
): Promise<{ statut: number; texte: string }> {
  ;(globalThis as any).__stubRpc = { authenticate_api_key: verdict }
  try {
    const reponse = await appeler({
      fonction: "public-api",
      methode: "GET",
      chemin,
      entetes: { "X-API-Key": CLE },
      corps: {},
      attendu: 0,
      motif: /./,
      raison: "cycle de vie d'une clé API (ORPH-01/SEC-02)",
    })
    return { statut: reponse.status, texte: await reponse.text() }
  } finally {
    delete (globalThis as any).__stubRpc
  }
}

Deno.test("public-api — une clé RÉVOQUÉE est refusée : 401, et le refus se nomme", async () => {
  const r = await avecCle({ data: { authenticated: false, reason: "revoked" }, error: null })
  if (r.statut !== 401) {
    throw new Error(`clé révoquée : attendu 401, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
  }
  if (!/revok|r[eé]voqu/i.test(r.texte)) {
    throw new Error(`le refus doit nommer la révocation — ${r.texte.slice(0, 200)}`)
  }
})

Deno.test("public-api — une clé EXPIRÉE est refusée : 401 (l'ancien chemin ne lisait jamais expires_at)", async () => {
  const r = await avecCle({ data: { authenticated: false, reason: "expired" }, error: null })
  if (r.statut !== 401) {
    throw new Error(`clé expirée : attendu 401, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
  }
  if (!/expir/i.test(r.texte)) {
    throw new Error(`le refus doit nommer l'expiration — ${r.texte.slice(0, 200)}`)
  }
})

Deno.test("public-api — une clé INCONNUE est refusée : 401", async () => {
  const r = await avecCle({ data: { authenticated: false, reason: "not_found" }, error: null })
  if (r.statut !== 401) {
    throw new Error(`clé inconnue : attendu 401, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
  }
})

Deno.test("public-api — contre-épreuve : une clé VALIDE ouvre la garde (200 sur /health, pas 401)", async () => {
  const r = await avecCle({
    data: {
      authenticated: true,
      api_key_id: "00000000-0000-0000-0000-0000000000b1",
      tenant_id: "00000000-0000-0000-0000-0000000000aa",
      permissions: ["*"],
    },
    error: null,
  })
  if (r.statut === 401) {
    throw new Error(`une clé valide ne doit PAS être refusée — ${r.texte.slice(0, 200)}`)
  }
  if (r.statut !== 200) {
    throw new Error(`attendu 200 sur /health avec une clé valide, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
  }
})
