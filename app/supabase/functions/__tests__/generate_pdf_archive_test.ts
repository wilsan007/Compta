// ============================================================
// D-4 — `generate-pdf` : l'ARCHIVE, et le refus honnête
//
// Trois défauts mesurés le 30/09 sur cette fonction, tous corrigés ici :
//   1. elle rangeait dans `storage.from("documents")` — un bucket qui n'existe
//      nulle part (les sept du dépôt sont déclarés par la 68) : l'upload
//      échouait, l'erreur n'était PAS lue, et la réponse annonçait
//      `success: true` avec `url: null` — un succès sans pièce ;
//   2. sans convertisseur, elle rendait le HTML du document avec un 200
//      (`fallback: true`) : un appelant qui lit `res.ok` tenait un HTML pour un
//      PDF, et les données de la pièce partaient dans le corps de la réponse ;
//   3. son repli visait `http://localhost:3000` — un convertisseur supposé sur
//      la machine, donc une conversion « réussie » qui n'en était pas une.
//
// CE QUE CE FICHIER PROUVE, ET CE QU'IL NE PROUVE PAS : il exécute le chemin de
// refus (l'archive doit dire « je n'ai rien produit ») et il lit la SOURCE pour
// les décisions de rangement (bucket, module, `upsert: false`) — c'est le
// « miroir statique » employé ailleurs dans le dépôt. Il n'exécute pas un vrai
// Gotenberg : il n'y en a pas, et c'est exactement pourquoi la fonction doit
// refuser plutôt que mentir.
// ============================================================

import { appeler } from "./stubs/harness.ts"

const SOURCE = await Deno.readTextFile(new URL("../generate-pdf/index.ts", import.meta.url))

Deno.test("generate-pdf — l'archive va dans le bucket de la 317, plus jamais `documents`", () => {
  if (!SOURCE.includes('const ARCHIVE_BUCKET = "generated-pdfs"')) {
    throw new Error("le bucket d'archive doit être `generated-pdfs` (migration 317)")
  }
  if (SOURCE.includes('from("documents")')) {
    throw new Error("le bucket `documents` n'existe pas : c'est lui qui produisait le faux succès")
  }
})

Deno.test("generate-pdf — une pièce archivée ne se réécrit pas (`upsert: false`)", () => {
  if (/upsert:\s*true/.test(SOURCE)) {
    throw new Error("`upsert: true` écraserait une pièce déjà archivée")
  }
  if (!/upsert:\s*false/.test(SOURCE)) {
    throw new Error("`upsert: false` doit être explicite")
  }
})

Deno.test("generate-pdf — le chemin porte la société ET le module (ce que lit la politique)", () => {
  if (!SOURCE.includes("${doc.tenant_id}/${cible.module}/${document_type}/${fileName}")) {
    throw new Error("le chemin doit être {société}/{module}/{type}/{fichier} : c'est la clé de la politique de lecture")
  }
  const attendus: [string, string][] = [
    ["invoice", "accounting"],
    ["quote", "commercial"],
    ["payslip", "hr"],
    ["credit_note", "accounting"],
    ["purchase_invoice", "accounting"],
  ]
  for (const [type, module] of attendus) {
    const motif = new RegExp(`${type}:\\s*\\{[^}]*module: "${module}"`)
    if (!motif.test(SOURCE)) {
      throw new Error(`le document « ${type} » doit être rangé sous le module « ${module} »`)
    }
  }
})

Deno.test("generate-pdf — sans convertisseur, elle REFUSE (503) et ne rend PAS le document", async () => {
  ;(globalThis as any).__stubUser = { id: "utilisateur-de-test" }
  try {
    const reponse = await appeler({
      fonction: "generate-pdf",
      corps: { document_type: "invoice", document_id: "00000000-0000-0000-0000-000000000001" },
      entetes: { Authorization: "Bearer jeton-de-test" },
      env: { GOTENBERG_URL: "" },
      attendu: 503,
      motif: /PDF_SERVICE_NOT_CONFIGURED/,
      raison: "sans convertisseur, aucun PDF n'existe — le dire, pas rendre le HTML",
    })
    const texte = await reponse.text()
    if (reponse.status !== 503) {
      throw new Error(`attendu 503, reçu ${reponse.status} — ${texte.slice(0, 200)}`)
    }
    if (!texte.includes("PDF_SERVICE_NOT_CONFIGURED")) {
      throw new Error(`le refus doit être nommé — ${texte.slice(0, 200)}`)
    }
    if (!texte.includes('"success":false')) {
      throw new Error(`la réponse doit annoncer l'échec — ${texte.slice(0, 200)}`)
    }
    if (/<!DOCTYPE|<html/i.test(texte)) {
      throw new Error("le document ne doit JAMAIS être renvoyé dans la réponse")
    }
  } finally {
    ;(globalThis as any).__stubUser = undefined
  }
})
