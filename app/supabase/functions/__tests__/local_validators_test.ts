// ============================================================
// W6 — ce qui se vérifie SANS réseau, et qui était faux dans le silence
//
// Trois fonctions de vérification trouvent leur verdict **dans le code** :
// la clé de Luhn d'un SIRET, la clé ISO 13616 d'un IBAN, le format d'un numéro
// de TVA. Un refus doit être un verdict, pas une exception — l'écran affiche
// `valid: false` avec son motif, il ne dit jamais « vérifié » à tort.
//
// `validate-vat-vies` appelle VIES : le `fetch` y est **remplacé** pour que le
// test soit déterministe (jamais de réseau dans un test).
// ============================================================

import { appelerAvecJeton } from "./stubs/harness.ts"

Deno.test("verify-siret — un SIRET dont la clé de Luhn est fausse est REFUSÉ, avec son motif", async () => {
  // 14 chiffres, clé volontairement fausse (le 14e casse la somme de Luhn).
  const { statut, json } = await appelerAvecJeton("verify-siret", { siret: "73282932000075" })
  if (statut !== 200 || json.valid !== false) {
    throw new Error(`attendu valid:false en 200, reçu ${statut} ${JSON.stringify(json)}`)
  }
  if (!/clé de contrôle|contrôle/i.test(String(json.error))) {
    throw new Error(`le motif doit nommer la clé de contrôle — ${JSON.stringify(json)}`)
  }
})

Deno.test("verify-siret — un SIRET de 13 chiffres est refusé en 400", async () => {
  const { statut, json } = await appelerAvecJeton("verify-siret", { siret: "7328293200007" })
  if (statut !== 400 || json.valid !== false) {
    throw new Error(`attendu 400 valid:false, reçu ${statut} ${JSON.stringify(json)}`)
  }
})

Deno.test("verify-siret — un SIRET valide (Luhn) est accepté, et la source du contrôle est NOMMÉE", async () => {
  const { statut, json } = await appelerAvecJeton("verify-siret", { siret: "73282932000074" })
  if (statut !== 200 || json.valid !== true) {
    throw new Error(`attendu valid:true en 200, reçu ${statut} ${JSON.stringify(json)}`)
  }
  if (json.api_source !== "local_validation") {
    throw new Error(`sans SIRENE_API_TOKEN, la source doit être locale — reçu ${json.api_source}`)
  }
})

Deno.test("verify-iban — une clé de contrôle fausse est REFUSÉE, un IBAN FR valide est accepté", async () => {
  const mauvais = await appelerAvecJeton("verify-iban", { iban: "FR7630006000011234567890188" })
  if (mauvais.statut !== 200 || mauvais.json.valid !== false) {
    throw new Error(`IBAN à clé fausse : attendu valid:false, reçu ${JSON.stringify(mauvais.json)}`)
  }

  const bon = await appelerAvecJeton("verify-iban", { iban: "FR7630006000011234567890189" })
  if (bon.statut !== 200 || bon.json.valid !== true) {
    throw new Error(`IBAN valide refusé : ${JSON.stringify(bon.json)}`)
  }
})

Deno.test("validate-vat-vies — un format invalide est refusé sans appeler VIES", async () => {
  let appele = false
  const vraiFetch = globalThis.fetch
  globalThis.fetch = (() => { appele = true; return Promise.reject(new Error("VIES ne doit pas être appelé")) }) as typeof fetch
  try {
    const { statut, json } = await appelerAvecJeton("validate-vat-vies", { vat_number: "FR" })
    if (statut !== 200 || json.valid !== false) {
      throw new Error(`attendu valid:false en 200, reçu ${statut} ${JSON.stringify(json)}`)
    }
    if (appele) throw new Error("VIES a été appelé pour un numéro au format invalide")
  } finally {
    globalThis.fetch = vraiFetch
  }
})

Deno.test("validate-vat-vies — un numéro au bon format est VÉRIFIÉ auprès de VIES (fetch remplacé)", async () => {
  const vraiFetch = globalThis.fetch
  globalThis.fetch = (() => Promise.resolve(new Response(
    "<soap:Envelope><soap:Body><checkVatResponse><valid>true</valid><name>EXEMPLE SA</name><address>1 RUE TEST</address></checkVatResponse></soap:Body></soap:Envelope>",
    { status: 200, headers: { "Content-Type": "text/xml" } },
  ))) as typeof fetch
  try {
    const { statut, json } = await appelerAvecJeton("validate-vat-vies", { vat_number: "FR12345678901" })
    if (statut !== 200 || json.valid !== true) {
      throw new Error(`attendu valid:true, reçu ${statut} ${JSON.stringify(json)}`)
    }
    if (json.api_source !== "VIES") {
      throw new Error(`la source doit être VIES — reçu ${json.api_source}`)
    }
    if (json.company_name !== "EXEMPLE SA") {
      throw new Error(`le nom de la société doit remonter — reçu ${json.company_name}`)
    }
  } finally {
    globalThis.fetch = vraiFetch
  }
})
