// ============================================================
// W6 — `generate-pdf` : le HTML fourni par le client est REFUSÉ
//
// AUD-H03 : la fonction acceptait un `html` arbitraire ; Chromium allait
// chercher tout ce qu'il contenait — une `<iframe src="http://169.254.169.254">`
// faisait du serveur un proxy vers le réseau interne (SSRF en lecture prouvée),
// et les valeurs interpolées dans le gabarit n'étaient pas échappées.
//
// La fonction n'est **pas déployée** (décision D-4 : « à défaut, retirer de
// deploy-all-functions.sh ») ; ce test tient la porte de sécurité pour le jour
// où la décision sera prise de la rebrancher.
// ============================================================

import { appeler } from "./stubs/harness.ts"

Deno.test("generate-pdf — sans jeton, refus (401)", async () => {
  const reponse = await appeler({ fonction: "generate-pdf", corps: {}, attendu: 401, motif: /Token/i, raison: "porte d'entrée" })
  if (reponse.status !== 401) throw new Error(`attendu 401, reçu ${reponse.status}`)
})

Deno.test("generate-pdf — le HTML fourni par le client est refusé, nommément", async () => {
  // Un utilisateur authentifié (le stub rend `__stubUser`) qui tenterait
  // d'injecter une iframe interne : refus AVANT toute lecture en base.
  ;(globalThis as any).__stubUser = { id: "utilisateur-de-test" }
  try {
    const reponse = await appeler({
      fonction: "generate-pdf",
      corps: {
        document_type: "invoice",
        document_id: "00000000-0000-0000-0000-000000000001",
        html: '<iframe src="http://169.254.169.254/latest/meta-data/"></iframe>',
      },
      entetes: { Authorization: "Bearer jeton-de-test" },
      attendu: 400,
      motif: /./,
      raison: "porte d'entrée",
    })
    const texte = await reponse.text()
    if (reponse.status !== 400) throw new Error(`attendu 400, reçu ${reponse.status} — ${texte.slice(0, 200)}`)
    if (!/CLIENT_HTML_REFUSED/.test(texte)) throw new Error(`le refus doit être nommé — ${texte.slice(0, 200)}`)
  } finally {
    ;(globalThis as any).__stubUser = undefined
  }
})
