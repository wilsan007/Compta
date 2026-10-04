// @ts-nocheck — Deno Edge Function
// generate-pdf — Génère un PDF à partir de HTML via Gotenberg
// Inspiré de : Pennylane, Sage, QuickBooks (génération PDF côté serveur)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { forbidden, isTenantMember } from "../_shared/tenantAccess.ts"

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)
  if (req.method === "OPTIONS") return handleOptions(corsHeaders)

  try {
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")
    if (!token) {
      return new Response(JSON.stringify({ error: "Token requis" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Non authentifié" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const body = await req.json()
    const { document_type, document_id, options = {} } = body

    if (!document_type || !document_id) {
      return new Response(JSON.stringify({ error: "document_type et document_id requis" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    // W6 / AUD-H03 : `html` fourni par le client est **refusé**. Chromium va
    // chercher tout ce que contient la page — une `<iframe src="http://169.254…">`
    // faisait du serveur un proxy vers le réseau interne (SSRF prouvée), et les
    // valeurs interpolées dans le gabarit n'étaient pas échappées.
    // Le HTML est désormais **toujours** construit ici, depuis le document.
    if (body.html) {
      return new Response(JSON.stringify({
        success: false,
        code: "CLIENT_HTML_REFUSED",
        error: "Le HTML fourni par le client est refusé : le document est construit par le serveur à partir de la pièce enregistrée.",
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Le bucket d'ARCHIVE des PDF produits par le serveur (migration 317) : privé,
    // PDF seulement, et une seule politique — la LECTURE, bornée à la société ET
    // au module porté par le chemin. Il n'écrit dans aucun autre bucket : c'est
    // `documents` (un bucket qui n'existait pas) qui produisait le faux succès.
    const ARCHIVE_BUCKET = "generated-pdfs"

    // Liste fermée : la clé service ne doit jamais lire une table choisie par le client.
    // Le MODULE est porté ici, jamais par l'appelant : c'est lui qui devient le
    // 2e segment du chemin d'archivage, donc ce que la politique de lecture du
    // bucket confronte à `has_module_access()` (migration 317). Un bulletin de
    // paie rangé sous `hr` n'est pas lisible par un commercial — et c'est la
    // base qui le tient, pas cette fonction.
    const DOCUMENTS: Record<string, { table: string; module: string }> = {
      invoice:          { table: "invoices",          module: "accounting" },
      quote:            { table: "quotes",            module: "commercial" },
      payslip:          { table: "pay_slips",         module: "hr" },
      credit_note:      { table: "credit_notes",      module: "accounting" },
      purchase_invoice: { table: "purchase_invoices", module: "accounting" },
    }
    const cible = DOCUMENTS[document_type]
    if (!cible) {
      return new Response(JSON.stringify({ error: "document_type non pris en charge" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }
    const tableName = cible.table

    const supabase = createClient(supabaseUrl, serviceRoleKey)
    const { data: doc, error: docErr } = await supabase
      .from(tableName)
      .select("*")
      .eq("id", document_id)
      .maybeSingle()

    if (docErr || !doc) {
      return new Response(JSON.stringify({ error: "Document non trouvé" }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }
    if (!(await isTenantMember(supabase, user.id, doc.tenant_id))) return forbidden(corsHeaders)

    // HTML **construit ici**, depuis la pièce : plus de HTML client.
    const pdfHtml = generateDocumentHtml(document_type, doc)

    // Convertir HTML → PDF via Gotenberg (auto-hébergé, injoignable du réseau
    // interne — c'est l'exigence A1 de la décision D-4, et elle n'est pas dans
    // ce dépôt : le convertisseur doit être isolé AVANT tout déploiement).
    //
    // Sans `GOTENBERG_URL`, la fonction n'a AUCUN convertisseur : elle le dit
    // (503) au lieu de rendre le HTML du document avec un 200. L'ancien repli
    // (`fallback: true`) renvoyait les données de la pièce dans le corps de la
    // réponse ET faisait passer un échec pour un succès — un appelant qui lit
    // `res.ok` tenait un HTML pour un PDF.
    const gotenbergUrl = Deno.env.get("GOTENBERG_URL")
    if (!gotenbergUrl) {
      return new Response(JSON.stringify({
        success: false,
        code: "PDF_SERVICE_NOT_CONFIGURED",
        error: "Conversion PDF non configurée (GOTENBERG_URL absente) : aucun PDF n'a été produit, et le document n'est pas retourné.",
      }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const formData = new FormData()
    formData.append("html", new Blob([pdfHtml], { type: "text/html" }), "document.html")
    if (options.marginTop) formData.append("marginTop", options.marginTop)
    if (options.marginBottom) formData.append("marginBottom", options.marginBottom)
    if (options.paperWidth) formData.append("paperWidth", options.paperWidth)
    if (options.paperHeight) formData.append("paperHeight", options.paperHeight)

    const pdfResponse = await fetch(`${gotenbergUrl}/forms/chromium/convert/html`, {
      method: "POST",
      body: formData,
    })

    if (!pdfResponse.ok) {
      // Le détail du refus reste dans le journal : il peut contenir un chemin
      // interne du convertisseur, et la réponse n'a pas à le porter.
      const detail = (await pdfResponse.text().catch(() => "")).slice(0, 300)
      console.error("generate-pdf : Gotenberg a refusé la conversion", pdfResponse.status, detail)
      return new Response(JSON.stringify({
        success: false,
        code: "PDF_SERVICE_UNAVAILABLE",
        error: "Le service de conversion a refusé la pièce ; aucun PDF n'a été produit.",
      }), {
        status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const pdfBuffer = await pdfResponse.arrayBuffer()

    // ARCHIVER la pièce, rangée par société ET par module ; accès par URL signée
    // (un bulletin de paie ou une facture ne doit jamais avoir d'URL publique).
    //
    // Le chemin est la CLÉ de la politique de lecture du bucket (migration 317) :
    //   {société}/{module}/{type}/{fichier}.pdf
    // c'est-à-dire que le retrouver dans le stockage obéit à la même règle que
    // le retrouver dans l'application.
    const fileName = `${document_type}_${document_id}_${Date.now()}.pdf`
    const storagePath = `${doc.tenant_id}/${cible.module}/${document_type}/${fileName}`
    const { error: uploadErr } = await supabase
      .storage
      .from(ARCHIVE_BUCKET)
      .upload(storagePath, pdfBuffer, {
        contentType: "application/pdf",
        // `upsert: false` : une pièce archivée ne se réécrit pas. Deux
        // générations du même document sont DEUX fichiers (le nom porte
        // l'horodatage), jamais un écrasement.
        upsert: false,
      })

    if (uploadErr) {
      // C'est ICI que le mensonge se produisait : l'échec d'archivage n'était pas
      // lu, et la réponse annonçait `success: true` avec `url: null`. Le bucket
      // `documents` n'existait pas — chaque appel rendait donc un faux succès.
      console.error("generate-pdf : archivage impossible —", uploadErr.message)
      return new Response(JSON.stringify({
        success: false,
        code: "UPLOAD_FAILED",
        error: "Le PDF a été produit mais n'a pas pu être archivé : la pièce n'est pas enregistrée.",
      }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    // L'URL signée est un CONFORT (1 h) : la référence durable est `storage_path`,
    // qui ne dépend d'aucune signature. Un échec de signature ne défait pas
    // l'archivage et n'a donc pas à se déguiser en échec de génération.
    const { data: signed, error: signErr } = await supabase
      .storage
      .from(ARCHIVE_BUCKET)
      .createSignedUrl(storagePath, 3600)
    if (signErr) console.error("generate-pdf : URL signée indisponible —", signErr.message)

    return new Response(JSON.stringify({
      success: true,
      file_name: fileName,
      storage_path: storagePath,
      url: signed?.signedUrl ?? null,
      size: pdfBuffer.byteLength,
    }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  } catch (err) {
    console.error("generate-pdf error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})

// Génération HTML basique pour un document.
// W6 / AUD-H03 (I3) : toutes les valeurs interpolées sont ÉCHAPPÉES — un nom de
// client contenant `<script>` n'a pas à devenir du code dans le PDF.
function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function generateDocumentHtml(type: string, doc: any): string {
  const title = type === "invoice" ? "Facture" : type === "quote" ? "Devis" : type === "payslip" ? "Bulletin de paie" : "Document"
  const nombre = escapeHtml(doc.number || "")
  const date = escapeHtml(doc.date || doc.period_start || "")
  const sousTotal = escapeHtml(doc.subtotal ?? doc.gross_salary ?? "0.00")
  const tva = escapeHtml(doc.vat_total ?? "0.00")
  const total = escapeHtml(doc.total ?? doc.net_salary ?? "0.00")
  const net = escapeHtml(doc.net_salary ?? doc.total ?? "0.00")

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
  h1 { color: #1a56db; border-bottom: 2px solid #1a56db; padding-bottom: 10px; }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; }
  th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
  th { background: #f5f5f5; font-weight: bold; }
  .total { font-size: 1.2em; font-weight: bold; text-align: right; margin-top: 20px; }
  .header { display: flex; justify-content: space-between; }
  .meta { color: #666; font-size: 0.9em; }
</style></head><body>
  <div class="header">
    <h1>${title} ${nombre}</h1>
    <div class="meta">Date: ${date}</div>
  </div>
  <table>
    <tr><th>Description</th><th>Montant</th></tr>
    <tr><td>Total HT</td><td>${sousTotal} €</td></tr>
    <tr><td>TVA</td><td>${tva} €</td></tr>
    <tr><td><strong>Total TTC</strong></td><td><strong>${total} €</strong></td></tr>
  </table>
  <p class="total">Net à payer: ${net} €</p>
</body></html>`
}
