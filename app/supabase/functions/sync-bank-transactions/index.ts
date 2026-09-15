// @ts-nocheck — Deno Edge Function
// sync-bank-transactions — Synchronise les transactions bancaires via GoCardless/Plaid
// Inspiré de : Pennylane, Qonto, Xero, QuickBooks (Open Banking PSD2)
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
    const { action, bank_connection_id, provider = "gocardless" } = body

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // === ACTION: init_link — Initier le lien OAuth avec le provider ===
    if (action === "init_link") {
      if (provider === "gocardless") {
        const gcToken = Deno.env.get("GOCARDLESS_API_TOKEN")
        if (!gcToken) {
          return new Response(JSON.stringify({ error: "GoCardless non configuré" }), {
            status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
          })
        }

        const redirectUrl = Deno.env.get("GOCARDLESS_REDIRECT_URL") || `${supabaseUrl}/functions/v1/sync-bank-transactions`

        // Créer une requête de lien GoCardless (Requisition)
        const gcResponse = await fetch("https://bankaccountdata.gocardless.com/api/v2/requisitions/", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${gcToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            redirect: redirectUrl,
            reference: user.id,
            agreement: body.agreement_id || undefined,
            user_language: "fr",
          }),
        })

        const gcData = await gcResponse.json()
        if (!gcResponse.ok) {
          return new Response(JSON.stringify({ error: "Erreur GoCardless", details: gcData }), {
            status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" }
          })
        }

        // Stocker la connexion en base
        const { data: conn, error: _connErr } = await supabase
          .from("bank_connections")
          .insert({
            provider: "gocardless",
            provider_requisition_id: gcData.id,
            link_url: gcData.link,
            status: "pending",
            user_id: user.id,
            tenant_id: body.tenant_id,
          })
          .select()
          .single()

        return new Response(JSON.stringify({
          success: true,
          link_url: gcData.link,
          connection_id: conn?.id,
        }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }

      if (provider === "plaid") {
        const plaidClientId = Deno.env.get("PLAID_CLIENT_ID")
        const plaidSecret = Deno.env.get("PLAID_SECRET")
        if (!plaidClientId || !plaidSecret) {
          return new Response(JSON.stringify({ error: "Plaid non configuré" }), {
            status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
          })
        }

        const plaidResponse = await fetch("https://production.plaid.com/link/token/create", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            client_id: plaidClientId,
            secret: plaidSecret,
            client_name: "Onusuite",
            products: ["transactions"],
            country_codes: ["FR", "GB", "DE", "ES", "IT"],
            language: "fr",
            user: { client_user_id: user.id },
          }),
        })

        const plaidData = await plaidResponse.json()
        if (!plaidResponse.ok) {
          return new Response(JSON.stringify({ error: "Erreur Plaid", details: plaidData }), {
            status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" }
          })
        }

        return new Response(JSON.stringify({
          success: true,
          link_token: plaidData.link_token,
        }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }
    }

    // === ACTION: sync — Récupérer les transactions ===
    if (action === "sync") {
      if (!bank_connection_id) {
        return new Response(JSON.stringify({ error: "bank_connection_id requis" }), {
          status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }

      const { data: connection, error: connErr } = await supabase
        .from("bank_connections")
        .select("*")
        .eq("id", bank_connection_id)
        .single()

      if (connErr || !connection) {
        return new Response(JSON.stringify({ error: "Connexion non trouvée" }), {
          status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }

      if (connection.provider === "gocardless") {
        const gcToken = Deno.env.get("GOCARDLESS_API_TOKEN")
        const accountId = body.account_id || connection.provider_account_id

        // Récupérer les transactions
        const txResponse = await fetch(
          `https://bankaccountdata.gocardless.com/api/v2/accounts/${accountId}/transactions/`,
          {
            headers: { "Authorization": `Bearer ${gcToken}` },
          }
        )

        const txData = await txResponse.json()
        if (!txResponse.ok) {
          return new Response(JSON.stringify({ error: "Erreur récupération transactions", details: txData }), {
            status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" }
          })
        }

        // Insérer les transactions en base
        let imported = 0
        const transactions = txData.transactions?.booked || []
        for (const tx of transactions) {
          const amount = parseFloat(tx.transactionAmount?.amount || "0")
          const txDate = tx.bookingDate || tx.valueDate || new Date().toISOString().split("T")[0]

          const { error: insertErr } = await supabase
            .from("bank_transactions")
            .insert({
              account_id: connection.bank_account_id,
              date: txDate,
              description: tx.remittanceInformationUnstructured || tx.debtorName || tx.creditorName || "Transaction",
              reference: tx.entryReference || tx.transactionId || null,
              type: amount >= 0 ? "credit" : "debit",
              amount: Math.abs(amount),
              reconciled: false,
              matched: false,
              source: "gocardless",
              provider_transaction_id: tx.transactionId || tx.entryReference,
              tenant_id: connection.tenant_id,
            })

          if (!insertErr) imported++
        }

        // Mettre à jour la connexion
        await supabase
          .from("bank_connections")
          .update({ last_sync_at: new Date().toISOString(), status: "active" })
          .eq("id", bank_connection_id)
          .eq("tenant_id", connection.tenant_id)

        return new Response(JSON.stringify({
          success: true,
          imported,
          total: transactions.length,
        }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
        })
      }
    }

    return new Response(JSON.stringify({ error: "Action non reconnue" }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  } catch (err) {
    console.error("sync-bank-transactions error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})
