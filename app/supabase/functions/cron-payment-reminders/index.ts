// @ts-nocheck — Deno Edge Function
// cron-payment-reminders — Cron job pour relances automatiques de paiement
// Inspiré de : Pennylane, Sage, QuickBooks (dunning automation)
// À configurer dans Supabase : pg_cron schedule tous les jours à 9h
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend } from "../_shared/email.ts"

serve(async (req) => {
  // Cette fonction est appelée par pg_cron, pas besoin d'auth
  // mais on vérifie un secret pour sécurité
  const cronSecret = req.headers.get("x-cron-secret")
  const expectedSecret = Deno.env.get("CRON_SECRET")

  if (expectedSecret && cronSecret !== expectedSecret) {
    return new Response(JSON.stringify({ error: "Non autorisé" }), {
      status: 401, headers: { "Content-Type": "application/json" }
    })
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    let remindersSent = 0
    let escalations = 0
    // W6 : trois compteurs honnêtes, pour que « rien envoyé » ne puisse plus
    // ressembler à « tout va bien ».
    let dejaRelancees = 0   // un envoi de ce niveau était déjà prouvé
    let echecs = 0          // la prise ou la clôture a échoué (le motif est journalisé)
    const details: string[] = []

    // === 1. Trouver les factures en retard ===
    // W6 / EF-01 : `.in("status", ["sent", "validated", "posted"])` filtrait sur
    // deux statuts que `invoices_status_check` **interdit** (validated, posted) :
    // la requête ne pouvait donc renvoyer que les factures « sent ». Les statuts
    // réels de la table sont draft/sent/viewed/paid/overdue/cancelled.
    const { data: overdueInvoices, error } = await supabase
      .from("invoices")
      .select(`
        id, number, date, due_date, total, amount_due, payment_state, currency_code,
        customer_id, customers (name, email),
        tenant_id
      `)
      .in("status", ["sent", "viewed", "overdue"])
      .in("payment_state", ["not_paid", "partial"])
      .lt("due_date", new Date().toISOString().split("T")[0])

    if (error) {
      throw new Error(`Erreur récupération factures: ${error.message}`)
    }

    // === 2. Pour chaque facture en retard, déterminer le niveau de relance ===
    for (const invoice of overdueInvoices || []) {
      const daysOverdue = Math.floor(
        (Date.now() - new Date(invoice.due_date).getTime()) / (1000 * 60 * 60 * 24)
      )

      // Déterminer le niveau de relance
      let reminderLevel = 0
      let subject = ""
      let message = ""
      // W6 : la devise est celle de la facture — les messages portaient « € » en dur.
      const devise = invoice.currency_code || "EUR"
      const montant = `${Number(invoice.amount_due ?? 0).toFixed(2)} ${devise}`

      if (daysOverdue >= 1 && daysOverdue < 15) {
        reminderLevel = 1
        subject = `Rappel de paiement - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nNous vous rappelons que la facture ${invoice.number} d'un montant de ${montant} est en retard de ${daysOverdue} jours.\n\nMerci de procéder au règlement dans les meilleurs délais.\n\nCordialement.`
      } else if (daysOverdue >= 15 && daysOverdue < 30) {
        reminderLevel = 2
        subject = `2ème relance - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nMalgré notre précédente relance, la facture ${invoice.number} d'un montant de ${montant} reste impayée (retard: ${daysOverdue} jours).\n\nNous vous prions de régulariser cette situation rapidement.\n\nCordialement.`
      } else if (daysOverdue >= 30 && daysOverdue < 60) {
        reminderLevel = 3
        subject = `MISE EN DEMEURE - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nLa facture ${invoice.number} d'un montant de ${montant} est en retard de ${daysOverdue} jours malgré nos précédentes relances.\n\nNous vous mettons en demeure de procéder au règlement sous 8 jours.\n\nÀ défaut, des poursuites seront engagées.\n\nCordialement.`
      } else if (daysOverdue >= 60) {
        reminderLevel = 4
        subject = `Procédure de recouvrement - Facture ${invoice.number}`
        message = `Facture ${invoice.number} - Retard: ${daysOverdue} jours - Montant: ${montant} - Transfert vers procédure de recouvrement.`
        // L'escalade n'est comptée qu'une fois l'envoi PROUVÉ (plus bas) : la
        // compter ici annonçait une escalade même quand rien ne partait.
      }

      if (reminderLevel > 0 && invoice.customers?.email) {
        // === W6 / EF-01, EF-02 : la relance est PRISE en base, puis envoyée ===
        // Avant : un `.single()` sur une recherche d'antériorité qui ne trouve
        // rien renvoyait `PGRST116` et `throw` interrompait TOUT le cron dès la
        // première facture ; et l'enregistrement de la relance échouait sur des
        // colonnes inexistantes sans lire l'erreur, donc le client était relancé
        // tous les jours. La prise est maintenant atomique et idempotente
        // (258) : elle rend un identifiant, ou NULL si un envoi de ce niveau est
        // déjà prouvé.
        const { data: reminderId, error: claimErr } = await supabase.rpc("claim_collection_reminder", {
          p_tenant_id: invoice.tenant_id,
          p_invoice_id: invoice.id,
          p_customer_id: invoice.customer_id,
          p_reminder_level: reminderLevel,
          p_amount: Number(invoice.amount_due) || 0,
          p_days_overdue: daysOverdue,
          p_number: `REL-${Date.now()}-${reminderLevel}-${invoice.number}`,
        })

        if (claimErr) {
          // Une facture ne fait plus tomber le traitement des autres.
          echecs++
          details.push(`${invoice.number} : relance non prise (${claimErr.message})`)
          console.error(`cron-payment-reminders: relance non prise pour ${invoice.number}:`, claimErr.message)
          continue
        }

        if (!reminderId) {
          dejaRelancees++
          continue
        }

        const emailResult = await sendEmailViaResend({
          to: invoice.customers.email,
          subject,
          html: message.split("\n").map((l) => l.trim() === "" ? "<br>" : `<p>${l}</p>`).join(""),
        })

        // Un seul chemin dit « envoyée » ou « en échec » — avec l'heure réelle
        // et l'erreur du prestataire. Un échec pourra être repris demain ; un
        // envoi prouvé ne repartira pas.
        const { error: finalizeErr } = await supabase.rpc("finalize_collection_reminder", {
          p_tenant_id: invoice.tenant_id,
          p_reminder_id: reminderId,
          p_sent: emailResult.success,
          p_error: emailResult.success ? null : (emailResult.error || "envoi refusé par le prestataire"),
        })

        if (finalizeErr) {
          echecs++
          details.push(`${invoice.number} : clôture de relance impossible (${finalizeErr.message})`)
          console.error(`cron-payment-reminders: clôture impossible pour ${invoice.number}:`, finalizeErr.message)
          continue
        }

        if (emailResult.success) {
          remindersSent++
          if (reminderLevel >= 4) escalations++
        } else {
          echecs++
          details.push(`${invoice.number} : envoi refusé (${emailResult.error || "sans motif"})`)
        }
      }
    }

    // === 3. Mettre à jour le statut des factures très en retard ===
    // NOTE: Intentionnellement cross-tenant — ce cron traite toutes les factures en retard
    // de tous les tenants. Le filtre tenant_id n'est pas applicable ici.
    // audit-silent-failures: cross-tenant — cron service-role, balaie tous les tenants
    const { data: veryOverdue, error: overdueError } = await supabase
      .from("invoices")
      .update({ status: "overdue" })
      .in("payment_state", ["not_paid", "partial"])
      .lt("due_date", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split("T")[0])
      .in("status", ["sent", "viewed"])
      .select("id")
    if (overdueError) throw overdueError

    return new Response(JSON.stringify({
      success: true,
      reminders_sent: remindersSent,
      escalations,
      // W6 : ce qui a été passé et pourquoi — un cron qui n'envoie rien ne peut
      // plus répondre `success: true` sans le dire.
      deja_relancees: dejaRelancees,
      echecs,
      details: details.slice(0, 20),
      overdue_invoices: overdueInvoices?.length || 0,
      updated_to_overdue: veryOverdue?.length || 0,
      executed_at: new Date().toISOString(),
    }), {
      status: 200, headers: { "Content-Type": "application/json" }
    })
  } catch (err) {
    console.error("cron-payment-reminders error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne", details: err.message }), {
      status: 500, headers: { "Content-Type": "application/json" }
    })
  }
})
