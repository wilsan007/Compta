// ============================================================
// D-5 / tâche 1.11 — AUCUNE donnée ne part chez le prestataire d'IA sans le
// consentement de la société.
//
// La 318 a posé le consentement (daté et signé par la base) et
// `ocr-invoice-import` le respecte depuis le 30/09. Deux autres fonctions
// parlaient au MÊME prestataire sans garde, nommées au registre de la décision :
//   * `parse-bank-statement` — le TEXTE INTÉGRAL d'un relevé bancaire ;
//   * `ai-import-mapping`    — les en-têtes ET des lignes d'exemple d'un fichier
//                              importé (clients, salariés…).
// Elles devinaient de plus la société (« le premier rattachement actif ») :
// pour un utilisateur de deux sociétés, le consentement de l'une aurait couvert
// l'autre.
//
// CE QUE CE FICHIER PROUVE : sans consentement, la fonction répond 409
// `OCR_CONSENT_REQUIRED` et `fetch` n'est JAMAIS appelé vers le prestataire ;
// sans société désignée, 400 ; et — contre-épreuve, sinon le test passerait à
// vide — AVEC consentement, l'appel part bien.
// ============================================================

import { appeler } from "./stubs/harness.ts"

const SOCIETE = "00000000-0000-0000-0000-0000000000aa" // celle de la ligne neutre du stub
const PRESTATAIRE = "api.openai.com"

const CAS = [
  {
    fonction: "parse-bank-statement",
    corps: { rawText: "01/09/2026 VIREMENT SALAIRE 1 250,00\n02/09/2026 PRLV EDF 82,40", bankName: "Banque d'essai" },
    ligne: { role: "accountant", status: "active" },
  },
  {
    fonction: "ai-import-mapping",
    corps: {
      sourceHeaders: ["Nom", "Email"],
      sampleRows: [["Dupont", "dupont@exemple.fr"]],
      targetFields: [{ key: "name", label: "Nom" }, { key: "email", label: "E-mail" }],
      moduleName: "customers",
    },
    ligne: { role: "admin", status: "active" },
  },
]

/** Joue la fonction en interceptant `fetch` ; rend la réponse et les URL appelées. */
async function jouer(
  cas: (typeof CAS)[number],
  opts: { consentement: boolean; societe?: string | null },
): Promise<{ statut: number; texte: string; appels: string[] }> {
  const appels: string[] = []
  const fetchOriginal = globalThis.fetch
  ;(globalThis as any).__stubUser = { id: `utilisateur-${cas.fonction}-${crypto.randomUUID()}` }
  ;(globalThis as any).__stubLigne = { ...cas.ligne, ocr_consent: opts.consentement }
  globalThis.fetch = async (url: string | URL | Request) => {
    appels.push(String(url instanceof Request ? url.url : url))
    return new Response(JSON.stringify({ choices: [{ message: { content: "{}" } }] }), { status: 200 })
  }
  try {
    const entetes: Record<string, string> = { Authorization: "Bearer jeton-de-test" }
    const societe = opts.societe === undefined ? SOCIETE : opts.societe
    if (societe) entetes["x-tenant-id"] = societe
    const reponse = await appeler({
      fonction: cas.fonction,
      corps: cas.corps,
      entetes,
      env: { OPENAI_API_KEY: "sk-de-test" },
      attendu: 409,
      motif: /OCR_CONSENT_REQUIRED/,
      raison: "D-5 : pas de sortie de données sans consentement",
    })
    return { statut: reponse.status, texte: await reponse.text(), appels }
  } finally {
    globalThis.fetch = fetchOriginal
    delete (globalThis as any).__stubLigne
    delete (globalThis as any).__stubUser
  }
}

for (const cas of CAS) {
  Deno.test(`${cas.fonction} — sans consentement : 409, et RIEN ne part chez le prestataire`, async () => {
    const r = await jouer(cas, { consentement: false })
    const sortis = r.appels.filter((u) => u.includes(PRESTATAIRE))
    if (sortis.length) throw new Error(`${sortis.length} appel(s) au prestataire SANS consentement : ${sortis.join(", ")}`)
    if (r.statut !== 409) throw new Error(`attendu 409, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
    if (!r.texte.includes("OCR_CONSENT_REQUIRED")) throw new Error(`le refus doit se nommer OCR_CONSENT_REQUIRED — ${r.texte.slice(0, 200)}`)
  })

  Deno.test(`${cas.fonction} — sans société désignée : 400, la société n'est pas devinée`, async () => {
    const r = await jouer(cas, { consentement: true, societe: null })
    if (r.appels.some((u) => u.includes(PRESTATAIRE))) throw new Error("appel au prestataire sans société désignée")
    if (r.statut !== 400 || !r.texte.includes("TENANT_REQUIRED")) {
      throw new Error(`attendu 400 TENANT_REQUIRED, reçu ${r.statut} — ${r.texte.slice(0, 200)}`)
    }
  })

  Deno.test(`${cas.fonction} — contre-épreuve : AVEC consentement, l'appel part`, async () => {
    const r = await jouer(cas, { consentement: true })
    if (!r.appels.some((u) => u.includes(PRESTATAIRE))) {
      throw new Error(`avec consentement, l'appel devait partir (statut ${r.statut} — ${r.texte.slice(0, 200)}) : sans cela, le test du refus passerait à vide`)
    }
  })
}
