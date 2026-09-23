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

    // === 1. Trouver les factures en retard ===
    const { data: overdueInvoices, error } = await supabase
      .from("invoices")
      .select(`
        id, number, date, due_date, total, amount_due, payment_state,
        customer_id, customers (name, email),
        tenant_id
      `)
      .in("status", ["sent", "validated", "posted"])
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

      if (daysOverdue >= 1 && daysOverdue < 15) {
        reminderLevel = 1
        subject = `Rappel de paiement - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nNous vous rappelons que la facture ${invoice.number} d'un montant de ${invoice.amount_due}€ est en retard de ${daysOverdue} jours.\n\nMerci de procéder au règlement dans les meilleurs délais.\n\nCordialement.`
      } else if (daysOverdue >= 15 && daysOverdue < 30) {
        reminderLevel = 2
        subject = `2ème relance - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nMalgré notre précédente relance, la facture ${invoice.number} d'un montant de ${invoice.amount_due}€ reste impayée (retard: ${daysOverdue} jours).\n\nNous vous prions de régulariser cette situation rapidement.\n\nCordialement.`
      } else if (daysOverdue >= 30 && daysOverdue < 60) {
        reminderLevel = 3
        subject = `MISE EN DEMEURE - Facture ${invoice.number}`
        message = `Bonjour ${invoice.customers?.name || ""},\n\nLa facture ${invoice.number} d'un montant de ${invoice.amount_due}€ est en retard de ${daysOverdue} jours malgré nos précédentes relances.\n\nNous vous mettons en demeure de procéder au règlement sous 8 jours.\n\nÀ défaut, des poursuites seront engagées.\n\nCordialement.`
      } else if (daysOverdue >= 60) {
        reminderLevel = 4
        subject = `Procédure de recouvrement - Facture ${invoice.number}`
        message = `Facture ${invoice.number} - Retard: ${daysOverdue} jours - Montant: ${invoice.amount_due}€ - Transfert vers procédure de recouvrement.`
        escalations++
      }

      if (reminderLevel > 0 && invoice.customers?.email) {
        // Vérifier si une relance a déjà été envoyée pour ce niveau
        const { data: existing, error } = await supabase
          .from("collection_reminders")
          .select("id")
          .eq("invoice_id", invoice.id)
          .eq("reminder_level", reminderLevel)
          .single()
        if (error) throw error

        if (!existing) {
          // Envoyer l'email
          const emailResult = await sendEmailViaResend({
            to: invoice.customers.email,
            subject,
            text: message,
          })

          // Enregistrer la relance
          await supabase
            .from("collection_reminders")
            .insert({
              tenant_id: invoice.tenant_id,
              number: "REL-" + Date.now() + "-" + invoice.number,
              invoice_id: invoice.id,
              customer_id: invoice.customer_id,
              reminder_level: reminderLevel,
              amount: invoice.amount_due,
              days_overdue: daysOverdue,
              sent_at: new Date().toISOString(),
              status: emailResult.success ? "sent" : "failed",
              email_sent: emailResult.success,
            })

          if (emailResult.success) remindersSent++
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
      .in("status", ["sent", "validated", "posted"])
      .select("id")
    if (overdueError) throw overdueError

    return new Response(JSON.stringify({
      success: true,
      reminders_sent: remindersSent,
      escalations,
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
