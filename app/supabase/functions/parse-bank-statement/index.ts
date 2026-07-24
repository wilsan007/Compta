// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
// Supabase Edge Function: AI-powered bank statement PDF parser.
// First upload for a new bank → uses OpenAI GPT-4o-mini to:
//   1. Extract transactions (date, description, amount, type, reference)
//   2. Generate a reusable regex template saved to bank_statement_templates
// Subsequent uploads → client uses saved template (no AI needed)
//
// Deploy with:
//   supabase functions deploy parse-bank-statement
//
// Required env vars (set in Supabase dashboard → Edge Functions → Secrets):
//   OPENAI_API_KEY=sk-...
//   SUPABASE_URL=...
//   SUPABASE_ANON_KEY=...

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface PreviousAttempt {
  date_pattern: string;
  amount_pattern: string;
  description_pattern: string | null;
  reference_pattern: string | null;
  debit_indicator: string | null;
  credit_indicator: string | null;
  skip_lines_pattern: string | null;
}

interface ParseRequest {
  rawText: string;
  bankName?: string;
  bankId?: string;
  tenantId?: string;
  previousTemplate?: PreviousAttempt | null;
  correctionNotes?: string | null;
  attemptCount?: number;
}

interface ParsedTransaction {
  date: string;
  description: string;
  reference: string;
  type: "debit" | "credit";
  amount: number;
}

interface TemplatePatterns {
  date_pattern: string;
  amount_pattern: string;
  description_pattern: string | null;
  reference_pattern: string | null;
  debit_indicator: string | null;
  credit_indicator: string | null;
  account_number_pattern: string | null;
  period_pattern: string | null;
  balance_pattern: string | null;
  currency_pattern: string | null;
  skip_lines_pattern: string | null;
}

interface ParseResponse {
  transactions: ParsedTransaction[];
  template: TemplatePatterns;
  bankName: string;
  accountNumber: string | null;
  periodStart: string | null;
  periodEnd: string | null;
  currency: string | null;
  warnings: string[];
}

const ALLOWED_ORIGINS = [
  Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev",
  "http://localhost:5173",
  "http://localhost:4173",
];

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  } as const;
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ============================================
  // AUTHENTICATION
  // ============================================
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace("Bearer ", "");
  if (!token) {
    return new Response(
      JSON.stringify({ error: "Token d'authentification requis" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) {
    return new Response(
      JSON.stringify({ error: "Utilisateur non authentifié" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const { data: tenantUser, error: tuErr } = await userClient
    .from("tenant_users")
    .select("id, role, status, tenant_id")
    .eq("auth_id", user.id)
    .eq("status", "active")
    .maybeSingle();

  if (tuErr || !tenantUser) {
    return new Response(
      JSON.stringify({ error: "Utilisateur non autorisé" }),
      { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const body: ParseRequest = await req.json();
    const { rawText, bankName, bankId, previousTemplate, correctionNotes, attemptCount } = body;

    if (!rawText || rawText.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "rawText is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Limit input size (first 15000 chars ~ 15 pages of text)
    const truncatedText = rawText.slice(0, 15000);

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "OPENAI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ============================================
    // LOAD PREVIOUS FAILED TEMPLATE FOR FEEDBACK
    // ============================================
    let feedbackContext = "";
    let priorTemplate: PreviousAttempt | null = previousTemplate || null;
    let priorNotes: string | null = correctionNotes || null;
    let attemptNum: number = attemptCount || 0;

    // If no explicit previousTemplate but bankId provided, load from DB
    if (!priorTemplate && bankId) {
      const { data: existingTpl } = await userClient
        .from("bank_statement_templates")
        .select("*")
        .eq("bank_id", bankId)
        .eq("is_active", true)
        .order("updated_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (existingTpl) {
        priorTemplate = {
          date_pattern: existingTpl.date_pattern,
          amount_pattern: existingTpl.amount_pattern,
          description_pattern: existingTpl.description_pattern,
          reference_pattern: existingTpl.reference_pattern,
          debit_indicator: existingTpl.debit_indicator,
          credit_indicator: existingTpl.credit_indicator,
          skip_lines_pattern: existingTpl.skip_lines_pattern,
        };
        priorNotes = existingTpl.last_correction_notes;
        attemptNum = existingTpl.validation_count || 0;
      }
    }

    if (priorTemplate) {
      feedbackContext = `\n\n⚠️ CONTEXTE D'AMÉLIORATION (tentative #${attemptNum + 1}):
Tu as déjà généré un template pour cette banque mais l'utilisateur a trouvé des ERREURS.
Voici le template précédent qui était INCORRECT:
- date_pattern: ${priorTemplate.date_pattern}
- amount_pattern: ${priorTemplate.amount_pattern}
- description_pattern: ${priorTemplate.description_pattern || "N/A"}
- reference_pattern: ${priorTemplate.reference_pattern || "N/A"}
- debit_indicator: ${priorTemplate.debit_indicator || "N/A"}
- credit_indicator: ${priorTemplate.credit_indicator || "N/A"}
- skip_lines_pattern: ${priorTemplate.skip_lines_pattern || "N/A"}

${priorNotes ? `Notes de correction de l'utilisateur: ${priorNotes}\n` : ""}
IMPORTANT: Analyse pourquoi le template précédent a échoué et CORRIGE les regex.\nAméliore la précision en tenant compte des erreurs signalées.\nGénère des patterns DIFFÉRENTS et plus précis.`;
    }

    // ============================================
    // BUILD PROMPT FOR GPT-4o-mini
    // ============================================
    const systemPrompt = `Tu es un expert en analyse de relevés bancaires. Tu reçois le texte brut extrait d'un PDF de relevé bancaire.

Ta mission:
1. Extraire TOUTES les transactions (date, description, référence, type débit/crédit, montant)
2. Identifier les patterns regex qui permettent de reconnaître ces lignes automatiquement à l'avenir
3. Détecter le nom de la banque, le numéro de compte, la période et la devise

Réponds UNIQUEMENT avec un JSON valide au format:
{
  "transactions": [
    { "date": "YYYY-MM-DD", "description": "...", "reference": "...", "type": "debit|credit", "amount": 1234.56 }
  ],
  "template": {
    "date_pattern": "regex string",
    "amount_pattern": "regex string",
    "description_pattern": "regex string or null",
    "reference_pattern": "regex string or null",
    "debit_indicator": "regex string or null",
    "credit_indicator": "regex string or null",
    "account_number_pattern": "regex string or null",
    "period_pattern": "regex string or null",
    "balance_pattern": "regex string or null",
    "currency_pattern": "regex string or null",
    "skip_lines_pattern": "regex string or null"
  },
  "bankName": "nom de la banque",
  "accountNumber": "numéro de compte ou null",
  "periodStart": "YYYY-MM-DD ou null",
  "periodEnd": "YYYY-MM-DD ou null",
  "currency": "code devise ou null",
  "warnings": ["avertissements éventuels"]
}

Règles importantes:
- Les dates doivent être au format YYYY-MM-DD
- Les montants sont des nombres décimaux (pas de symbole monétaire)
- type = "credit" pour les dépôts/entrées d'argent, "debit" pour les retraits/sorties
- Les regex doivent utiliser la syntaxe JavaScript (pas les délimiteurs /.../)
- Le date_pattern doit capturer la date dans un groupe
- Le amount_pattern doit capturer le montant dans un groupe
- Le skip_lines_pattern doit ignorer les en-têtes, totaux, soldes, pages
- Sois précis sur les regex pour qu'ils fonctionnent sur d'autres relevés de la même banque
- Si tu ne trouves pas de transactions, retourne un tableau vide avec un warning`;

    const userPrompt = `Analyse ce relevé bancaire et extrais les transactions + génère les patterns regex:

${truncatedText}

${bankName ? `Indice: la banque pourrait être "${bankName}"` : "Identifie la banque à partir du contenu."}${feedbackContext}

Réponds en JSON uniquement.`;

    // ============================================
    // CALL OPENAI
    // ============================================
    const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.1,
        max_tokens: 4000,
        response_format: { type: "json_object" },
      }),
    });

    if (!openaiResponse.ok) {
      const errText = await openaiResponse.text();
      console.error("OpenAI API error:", errText);
      return new Response(
        JSON.stringify({ error: "AI service error" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const openaiData = await openaiResponse.json();
    const content = openaiData.choices?.[0]?.message?.content;

    if (!content) {
      return new Response(
        JSON.stringify({ error: "Empty AI response" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let result: ParseResponse;
    try {
      result = JSON.parse(content);
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON from AI" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ============================================
    // SAVE TEMPLATE TO DATABASE
    // ============================================
    if (result.template && result.transactions.length > 0 && tenantUser.tenant_id) {
      try {
        const { data: savedTpl } = await userClient.from("bank_statement_templates").upsert({
          tenant_id: tenantUser.tenant_id,
          bank_id: bankId || null,
          bank_name: result.bankName || bankName || "Unknown Bank",
          date_pattern: result.template.date_pattern,
          amount_pattern: result.template.amount_pattern,
          description_pattern: result.template.description_pattern,
          reference_pattern: result.template.reference_pattern,
          debit_indicator: result.template.debit_indicator,
          credit_indicator: result.template.credit_indicator,
          account_number_pattern: result.template.account_number_pattern,
          period_pattern: result.template.period_pattern,
          balance_pattern: result.template.balance_pattern,
          currency_pattern: result.template.currency_pattern,
          skip_lines_pattern: result.template.skip_lines_pattern,
          sample_text: truncatedText.slice(0, 2000),
          is_active: true,
          validation_status: "pending",
          consecutive_successes: 0,
          validation_count: 0,
        }, { onConflict: "tenant_id,bank_name" }).select("id").single();

        // Attach template ID to response for client-side validation flow
        if (savedTpl) {
          (result as any).templateId = savedTpl.id;
          (result as any).validationStatus = "pending";
        }
      } catch (saveErr) {
        console.error("Failed to save template:", saveErr);
        // Non-fatal — still return parsed transactions
      }
    }

    return new Response(
      JSON.stringify(result),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(
      JSON.stringify({ error: "Erreur interne du serveur" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
