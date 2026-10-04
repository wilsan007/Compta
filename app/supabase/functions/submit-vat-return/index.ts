// @ts-nocheck — Deno Edge Function
// submit-vat-return — Télédéclaration TVA CA3 via EFI / EDI
// Inspiré de : Pennylane, Sage, QuickBooks
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
    if (!token) return new Response(JSON.stringify({ error: "Token requis" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) return new Response(JSON.stringify({ error: "Non authentifié" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const body = await req.json()
    const { vat_return_id, _mode = "edi" } = body

    if (!vat_return_id) {
      return new Response(JSON.stringify({ error: "vat_return_id requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // Récupérer la déclaration TVA
    const { data: vatReturn, error: vrErr } = await supabase
      .from("vat_returns")
      .select("*")
      .eq("id", vat_return_id)
      .single()

    if (vrErr || !vatReturn) {
      return new Response(JSON.stringify({ error: "Déclaration TVA non trouvée" }), { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }
    if (!(await isTenantMember(supabase, user.id, vatReturn.tenant_id))) return forbidden(corsHeaders)

    if (vatReturn.status === "submitted") {
      return new Response(JSON.stringify({ error: "Déclaration déjà soumise", edi_tva_id: vatReturn.edi_tva_id }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Récupérer les infos entreprise
    const { data: company, error } = await supabase
      .from("company_settings")
      .select("*")
      .eq("tenant_id", vatReturn.tenant_id)
      .limit(1)
      .maybeSingle()
    if (error) { console.error('submit-vat-return:', error); }

    if (!company?.siret) {
      return new Response(JSON.stringify({ error: "SIRET requis pour la télédéclaration" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Vérifier si l'API EFI est configurée
    const efiToken = Deno.env.get("EFI_API_TOKEN")
    const efiApiUrl = Deno.env.get("EFI_API_URL") || "https://api.impots.gouv.fr"

    if (!efiToken) {
      // LOT7-08 : sans accès configuré, refuser plutôt que simuler.
      // Une simulation enregistrait la déclaration comme transmise alors que rien n'était envoyé.
      return new Response(JSON.stringify({
        success: false,
        code: "NOT_CONFIGURED",
        error: "API EFI (impots.gouv.fr) non configuré : définissez EFI_API_TOKEN pour activer la transmission. Aucune donnée n'a été transmise.",
      }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Transmission réelle via API EFI (impots.gouv.fr)
    // Génération du message EDI-TVA (format CA3)
    const ediMessage = generateCA3EdiMessage(vatReturn, company)

    const efiResponse = await fetch(`${efiApiUrl}/rest/edi-tva/declarations`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${efiToken}`,
        "Content-Type": "application/xml",
      },
      body: ediMessage,
    })

    const efiData = await efiResponse.json()

    if (efiResponse.ok) {
      await supabase
        .from("vat_returns")
        .update({
          status: "submitted",
          submitted_date: new Date().toISOString().split("T")[0],
          edi_tva_id: efiData.numeroDeclaration,
          edi_status: "submitted",
          edi_submitted_at: new Date().toISOString(),
          edi_acknowledgment: efiData.accuse,
        })
        .eq("id", vat_return_id)
        .eq("tenant_id", vatReturn.tenant_id)
    }

    return new Response(JSON.stringify({
      success: efiResponse.ok,
      vat_return_id: vat_return_id,
      edi_tva_id: efiData.numeroDeclaration,
      status: efiResponse.ok ? "submitted" : "error",
      error: efiResponse.ok ? null : efiData.error,
    }), {
      status: efiResponse.ok ? 200 : 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })

  } catch (err) {
    console.error("submit-vat-return error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})

// Génération du message EDI-TVA CA3
function generateCA3EdiMessage(vatReturn: any, company: any): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Message xmlns="urn:fr:insee:edi:ca3">
  <EnTete>
    <SIRET>${company.siret}</SIRET>
    <Periode>${vatReturn.period_start}_${vatReturn.period_end}</Periode>
    <Type>CA3</Type>
  </EnTete>
  <Corps>
    <CadreA>
      <A08_TVACollectee>${vatReturn.box1_output_vat || 0}</A08_TVACollectee>
    </CadreA>
    <CadreB>
      <B20_TVADeductible>${vatReturn.box2_input_vat || 0}</B20_TVADeductible>
    </CadreB>
    <CadreC>
      <C22_TVAADecaisser>${vatReturn.box3_vat_due || 0}</C22_TVAADecaisser>
      <C24_Remplacement>0</C24_Remplacement>
    </CadreC>
  </Corps>
</Message>`
}
