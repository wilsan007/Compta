// @ts-nocheck — Deno Edge Function
// submit-e-invoice — Soumet une facture électronique (Factur-X / Chorus Pro / PEPPOL)
// Inspiré de : Sage, Cegid, EBP, Pennylane (conformité e-invoicing 2026)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"

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
    const { invoice_id, platform = "chorus_pro", xml_content, format = "factur-x" } = body

    if (!invoice_id) {
      return new Response(JSON.stringify({ error: "invoice_id requis" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // Récupérer la facture
    const { data: invoice, error: invErr } = await supabase
      .from("invoices")
      .select(`
        *,
        invoice_lines (*),
        customers (*)
      `)
      .eq("id", invoice_id)
      .single()

    if (invErr || !invoice) {
      return new Response(JSON.stringify({ error: "Facture non trouvée" }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    // Générer le XML Factur-X si non fourni
    const facturXXml = xml_content || generateFacturXXml(invoice)

    // === Soumission à Chorus Pro ===
    if (platform === "chorus_pro") {
      const chorusToken = Deno.env.get("CHORUS_PRO_TOKEN")
      const chorusSiret = Deno.env.get("CHORUS_PRO_SIRET")

      if (!chorusToken) {
        // Mode simulation si Chorus Pro n'est pas configuré
        await supabase
          .from("invoices")
          .update({
            e_invoice_status: "submitted",
            e_invoice_platform: "chorus_pro",
            e_invoice_submitted_at: new Date().toISOString(),
          })
          .eq("id", invoice_id)
          .eq("tenant_id", invoice.tenant_id)

        return new Response(JSON.stringify({
          success: true,
          platform: "chorus_pro",
          status: "submitted",
          mode: "simulation",
          message: "Facture soumise en mode simulation (Chorus Pro non configuré)",
          xml_size: facturXXml.length,
        }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }

      // Soumission réelle à Chorus Pro API
      const chorusResponse = await fetch(
        "https://api.chorus-pro.gouv.fr/piste/api/v1/transactions/submit",
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${chorusToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            siret: chorusSiret,
            format: format,
            xml: btoa(facturXXml),
            invoice_number: invoice.number,
          }),
        }
      )

      const chorusData = await chorusResponse.json()

      if (chorusResponse.ok) {
        await supabase
          .from("invoices")
          .update({
            e_invoice_status: "submitted",
            e_invoice_platform: "chorus_pro",
            e_invoice_submitted_at: new Date().toISOString(),
            e_invoice_id: chorusData.transaction_id,
          })
          .eq("id", invoice_id)
          .eq("tenant_id", invoice.tenant_id)
      }

      return new Response(JSON.stringify({
        success: chorusResponse.ok,
        platform: "chorus_pro",
        status: chorusResponse.ok ? "submitted" : "error",
        transaction_id: chorusData.transaction_id,
        error: chorusResponse.ok ? null : chorusData.error,
      }), {
        status: chorusResponse.ok ? 200 : 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    // === Soumission au réseau PEPPOL ===
    if (platform === "peppol") {
      const peppolEndpoint = Deno.env.get("PEPPOL_ENDPOINT")
      if (!peppolEndpoint) {
        return new Response(JSON.stringify({
          success: true,
          platform: "peppol",
          status: "simulation",
          message: "PEPPOL non configuré — mode simulation",
        }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }

      const peppolResponse = await fetch(peppolEndpoint, {
        method: "POST",
        headers: { "Content-Type": "application/xml" },
        body: facturXXml,
      })

      return new Response(JSON.stringify({
        success: peppolResponse.ok,
        platform: "peppol",
        status: peppolResponse.ok ? "sent" : "error",
      }), {
        status: peppolResponse.ok ? 200 : 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    return new Response(JSON.stringify({ error: "Platform non reconnue" }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  } catch (err) {
    console.error("submit-e-invoice error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})

// Génération XML Factur-X minimal
function generateFacturXXml(invoice: any): string {
  const _customer = invoice.customers || {}
  const lines = invoice.invoice_lines || []
  const _now = new Date().toISOString()

  const lineItems = lines.map((line: any, i: number) => `
    <cac:InvoiceLine>
      <cbc:ID>${i + 1}</cbc:ID>
      <cbc:InvoicedQuantity unitCode="C62">${line.quantity || 1}</cbc:InvoicedQuantity>
      <cbc:LineExtensionAmount currencyID="EUR">${line.total || line.unit_price || 0}</cbc:LineExtensionAmount>
      <cac:Item>
        <cbc:Description>${escapeXml(line.description || "")}</cbc:Description>
        <cbc:Name>${escapeXml(line.description || "Article")}</cbc:Name>
      </cac:Item>
      <cac:Price>
        <cbc:PriceAmount currencyID="EUR">${line.unit_price || 0}</cbc:PriceAmount>
      </cac:Price>
    </cac:InvoiceLine>`).join("")

  return `<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
  xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationModel:100"
  xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <rsm:ExchangedDocument>
    <cbc:ID>${invoice.number}</cbc:ID>
    <cbc:TypeCode>380</cbc:TypeCode>
    <cbc:IssueDate>${invoice.date}</cbc:IssueDate>
  </rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
    ${lineItems}
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>${invoice.subtotal || 0}</ram:LineTotalAmount>
        <ram:TaxTotalAmount currencyID="EUR">${invoice.vat_total || 0}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${invoice.total || 0}</ram:GrandTotalAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`
}

function escapeXml(str: string): string {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;")
}
