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

    // Liste fermée : la clé service ne doit jamais lire une table choisie par le client
    const TABLES: Record<string, string> = {
      invoice: "invoices",
      quote: "quotes",
      payslip: "pay_slips",
      credit_note: "credit_notes",
      purchase_invoice: "purchase_invoices",
    }
    const tableName = TABLES[document_type]
    if (!tableName) {
      return new Response(JSON.stringify({ error: "document_type non pris en charge" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

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

    // Convertir HTML → PDF via Gotenberg (self-hosted ou API)
    const gotenbergUrl = Deno.env.get("GOTENBERG_URL") || "http://localhost:3000"
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
      // Fallback : retourner le HTML si Gotenberg n'est pas disponible
      return new Response(JSON.stringify({
        success: false,
        error: "Service PDF non disponible",
        html: pdfHtml,
        fallback: true,
      }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const pdfBuffer = await pdfResponse.arrayBuffer()

    // Stocker le PDF dans Supabase Storage, rangé par tenant ; accès par URL signée
    // (un bulletin de paie ou une facture ne doit jamais avoir d'URL publique)
    const fileName = `${document_type}_${document_id}_${Date.now()}.pdf`
    const storagePath = `pdfs/${doc.tenant_id}/${fileName}`
    const { error: uploadErr } = await supabase
      .storage
      .from("documents")
      .upload(storagePath, pdfBuffer, {
        contentType: "application/pdf",
        upsert: true,
      })

    let publicUrl: string | null = null
    if (!uploadErr) {
      const { data: signed } = await supabase.storage.from("documents").createSignedUrl(storagePath, 3600)
      publicUrl = signed?.signedUrl || null
    }

    return new Response(JSON.stringify({
      success: true,
      file_name: fileName,
      url: publicUrl,
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
