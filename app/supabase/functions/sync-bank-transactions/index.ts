// @ts-nocheck — Deno Edge Function
// sync-bank-transactions — Synchronise les transactions bancaires via GoCardless/Plaid
// Inspiré de : Pennylane, Qonto, Xero, QuickBooks (Open Banking PSD2)
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

        if (!(await isTenantMember(supabase, user.id, body.tenant_id))) return forbidden(corsHeaders)
        // Stocker la connexion en base.
        // W6 / EF-04 : `bank_connections` porte `provider_connection_id`, pas
        // `provider_requisition_id` / `link_url` / `user_id`. L'insertion
        // échouait à chaque appel — et l'erreur n'était pas lue, la fonction
        // répondait `success: true` avec un `connection_id` nul.
        const { data: conn, error: connErr } = await supabase
          .from("bank_connections")
          .insert({
            provider: "gocardless",
            provider_connection_id: gcData.id,
            status: "pending",
            tenant_id: body.tenant_id,
            metadata: { link_url: gcData.link, initiated_by: user.id },
          })
          .select()
          .single()

        if (connErr) {
          console.error("sync-bank-transactions: connexion non enregistrée:", connErr.message)
          return new Response(JSON.stringify({
            success: false,
            code: "CONNECTION_NOT_SAVED",
            error: "Le lien a été créé chez GoCardless mais la connexion n'a pas pu être enregistrée : " + connErr.message,
            link_url: gcData.link,
          }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }

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
      if (!(await isTenantMember(supabase, user.id, connection.tenant_id))) return forbidden(corsHeaders)

      if (connection.provider === "gocardless") {
        const gcToken = Deno.env.get("GOCARDLESS_API_TOKEN")
        if (!gcToken) {
          return new Response(JSON.stringify({
            success: false,
            code: "NOT_CONFIGURED",
            error: "GoCardless non configuré : définissez GOCARDLESS_API_TOKEN. Aucune opération n'a été récupérée.",
          }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }

        // W6 / EF-04 : `connection.provider_account_id` n'existe pas sur
        // `bank_connections` (l'URL appelée contenait littéralement
        // `undefined`). Le compte de la banque est celui du relevé, que le
        // client fournit ou que la connexion mémorise dans ses métadonnées.
        const accountId = body.account_id || connection.metadata?.provider_account_id

        if (!accountId) {
          return new Response(JSON.stringify({
            success: false,
            code: "ACCOUNT_NOT_LINKED",
            error: "Aucun compte bancaire rattaché à cette connexion : fournissez `account_id`. Aucune opération n'a été récupérée.",
          }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }

        // Récupérer les transactions
        const txResponse = await fetch(
          `https://bankaccountdata.gocardless.com/api/v2/accounts/${accountId}/transactions/`,
          {
            headers: { "Authorization": `Bearer ${gcToken}` },
          }
        )

        const txData = await txResponse.json()
        if (!txResponse.ok) {
          const message = txData?.detail || txData?.summary || "Erreur récupération transactions"
          console.error("sync-bank-transactions: GoCardless transactions:", message)
          // La connexion dit maintenant la vérité : elle est en erreur, avec le motif.
          const { error: errStamp } = await supabase
            .from("bank_connections")
            .update({ status: "error", error_message: String(message).slice(0, 500) })
            .eq("id", bank_connection_id)
            .eq("tenant_id", connection.tenant_id)
          if (errStamp) console.error("sync-bank-transactions: statut d'erreur non enregistré:", errStamp.message)
          return new Response(JSON.stringify({
            success: false,
            code: "PROVIDER_ERROR",
            error: message,
          }), { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }

        // Insérer les transactions en base.
        // W6 / EF-04 : `provider_transaction_id` n'existait pas (257) et
        // l'erreur d'insertion n'était pas lue (`if (!insertErr) imported++`) :
        // la fonction répondait `success: true, imported: 0` en n'ayant rien
        // importé. Le champ rend désormais la synchronisation idempotente —
        // rejouer la journée ne double plus les opérations.
        let imported = 0
        let dejaImportees = 0
        let echecs = 0
        const details: string[] = []
        const transactions = txData.transactions?.booked || []
        for (const tx of transactions) {
          const amount = parseFloat(tx.transactionAmount?.amount || "0")
          const txDate = tx.bookingDate || tx.valueDate || new Date().toISOString().split("T")[0]
          const providerTransactionId = tx.transactionId || tx.entryReference || null

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
              provider_transaction_id: providerTransactionId,
              tenant_id: connection.tenant_id,
            })

          if (!insertErr) {
            imported++
          } else if (insertErr.code === "23505") {
            dejaImportees++  // déjà importée : ce n'est pas un échec
          } else {
            echecs++
            details.push(`${providerTransactionId || txDate} : ${insertErr.message}`)
            console.error("sync-bank-transactions: insertion refusée:", insertErr.message)
          }
        }

        // Mettre à jour la connexion — et ne dire « synchronisée à l'instant »
        // que si la synchronisation a réellement eu lieu.
        const now = new Date().toISOString()
        const { error: updErr } = await supabase
          .from("bank_connections")
          .update(echecs > 0
            ? { status: "error", error_message: `Import partiel : ${echecs} opération(s) refusée(s)`, last_sync_at: now }
            : { last_sync_at: now, status: "active", error_message: null })
          .eq("id", bank_connection_id)
          .eq("tenant_id", connection.tenant_id)

        if (updErr) {
          console.error("sync-bank-transactions: connexion non mise à jour:", updErr.message)
          return new Response(JSON.stringify({
            success: false,
            code: "CONNECTION_NOT_UPDATED",
            error: "Opérations récupérées mais état de la connexion non enregistré : " + updErr.message,
            imported, deja_importees: dejaImportees, echecs,
          }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }

        return new Response(JSON.stringify({
          success: echecs === 0,
          imported,
          deja_importees: dejaImportees,
          echecs,
          details: details.slice(0, 10),
          total: transactions.length,
        }), {
          status: echecs === 0 ? 200 : 207,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
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
