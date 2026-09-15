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
// Required eçnv vars (set in Supabase dashboard → Edge Functions → Secrets):
//   OPENAI_API_KEY=sk-...
//   SUPABASE_URL=...
//   SUPABASE_ANON_KEY=...

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts";
import { checkRateLimit, getClientIp, validateBodySize, rateLimitResponse } from "../_shared/rateLimit.ts";

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

const MAX_INPUT_CHARS = 15000;
const MAX_TRANSACTIONS = 500;
const OPENAI_TIMEOUT_MS = 30_000;
const OPENAI_MAX_RETRIES = 3;

function isValidDate(s: string): boolean {
  if (!s || typeof s !== "string") return false;
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(Date.parse(s));
}

function isValidAmount(n: any): boolean {
  return typeof n === "number" && isFinite(n) && n > 0;
}

function isValidTransactionType(t: any): boolean {
  return t === "debit" || t === "credit";
}

function tryRegex(pattern: string | null): boolean {
  if (!pattern) return true;
  try {
    new RegExp(pattern);
    return true;
  } catch {
    return false;
  }
}

function validateAndSanitizeResult(raw: any): ParseResponse {
  const warnings: string[] = Array.isArray(raw?.warnings) ? raw.warnings : [];

  if (!raw || typeof raw !== "object") {
    return { transactions: [], template: emptyTemplate(), bankName: "", accountNumber: null, periodStart: null, periodEnd: null, currency: null, warnings: ["Invalid AI response structure", ...warnings] };
  }

  const rawTxns = Array.isArray(raw.transactions) ? raw.transactions : [];
  const transactions: ParsedTransaction[] = [];
  let skipped = 0;

  for (const t of rawTxns) {
    if (transactions.length >= MAX_TRANSACTIONS) {
      warnings.push(`Truncated to ${MAX_TRANSACTIONS} transactions`);
      break;
    }
    if (!t || typeof t !== "object") { skipped++; continue; }
    const date = typeof t.date === "string" ? t.date.trim() : "";
    const amount = Number(t.amount);
    const type = t.type;
    const description = typeof t.description === "string" ? t.description.trim() : "";
    const reference = typeof t.reference === "string" ? t.reference.trim() : "";

    if (!isValidDate(date)) { skipped++; continue; }
    if (!isValidAmount(amount)) { skipped++; continue; }
    if (!isValidTransactionType(type)) { skipped++; continue; }

    transactions.push({ date, description, reference, type });
  }

  if (skipped > 0) warnings.push(`${skipped} invalid transactions skipped`);

  const tpl = raw.template || {};
  const template: TemplatePatterns = {
    date_pattern: typeof tpl.date_pattern === "string" ? tpl.date_pattern : "",
    amount_pattern: typeof tpl.amount_pattern === "string" ? tpl.amount_pattern : "",
    description_pattern: typeof tpl.description_pattern === "string" ? tpl.description_pattern : null,
    reference_pattern: typeof tpl.reference_pattern === "string" ? tpl.reference_pattern : null,
    debit_indicator: typeof tpl.debit_indicator === "string" ? tpl.debit_indicator : null,
    credit_indicator: typeof tpl.credit_indicator === "string" ? tpl.credit_indicator : null,
    account_number_pattern: typeof tpl.account_number_pattern === "string" ? tpl.account_number_pattern : null,
    period_pattern: typeof tpl.period_pattern === "string" ? tpl.period_pattern : null,
    balance_pattern: typeof tpl.balance_pattern === "string" ? tpl.balance_pattern : null,
    currency_pattern: typeof tpl.currency_pattern === "string" ? tpl.currency_pattern : null,
    skip_lines_pattern: typeof tpl.skip_lines_pattern === "string" ? tpl.skip_lines_pattern : null,
  };

  const invalidRegexFields: string[] = [];
  for (const [key, val] of Object.entries(template)) {
    if (!tryRegex(val as string)) invalidRegexFields.push(key);
  }
  if (invalidRegexFields.length > 0) {
    warnings.push(`Invalid regex patterns: ${invalidRegexFields.join(", ")}`);
    for (const key of invalidRegexFields) {
      (template as any)[key] = null;
    }
  }

  if (!template.date_pattern || !template.amount_pattern) {
    warnings.push("Missing essential patterns (date_pattern or amount_pattern)");
  }

  return {
    transactions,
    template,
    bankName: typeof raw.bankName === "string" ? raw.bankName : "",
    accountNumber: typeof raw.accountNumber === "string" ? raw.accountNumber : null,
    periodStart: isValidDate(raw.periodStart) ? raw.periodStart : null,
    periodEnd: isValidDate(raw.periodEnd) ? raw.periodEnd : null,
    currency: typeof raw.currency === "string" ? raw.currency : null,
    warnings,
  };
}

function emptyTemplate(): TemplatePatterns {
  return { date_pattern: "", amount_pattern: "", description_pattern: null, reference_pattern: null, debit_indicator: null, credit_indicator: null, account_number_pattern: null, period_pattern: null, balance_pattern: null, currency_pattern: null, skip_lines_pattern: null };
}

async function callOpenAIWithRetry(apiKey: string, body: object): Promise<Response> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < OPENAI_MAX_RETRIES; attempt++) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);
      const resp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timeoutId);

      if (resp.ok) return resp;

      if (resp.status === 429 || resp.status === 500 || resp.status === 502 || resp.status === 503) {
        const retryAfter = Number(resp.headers.get("retry-after")) || (attempt + 1) * 1000;
        lastError = new Error(`OpenAI ${resp.status}`);
        if (attempt < OPENAI_MAX_RETRIES - 1) {
          await new Promise(r => setTimeout(r, Math.min(retryAfter, 5000)));
          continue;
        }
      }
      return resp;
    } catch (err) {
      lastError = err as Error;
      if (attempt < OPENAI_MAX_RETRIES - 1) {
        await new Promise(r => setTimeout(r, (attempt + 1) * 1000));
        continue;
      }
    }
  }
  throw lastError || new Error("OpenAI request failed after retries");
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return handleOptions(corsHeaders);
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ============================================
  // RATE LIMITING: IP-based (anti-DDoS) + body size validation
  // ============================================
  const clientIp = getClientIp(req);
  if (!checkRateLimit(`ip:${clientIp}`, 20, 60_000)) {
    return rateLimitResponse(corsHeaders, 60);
  }

  const bodyCheck = await validateBodySize(req, 20 * 1024); // 20 KB max for bank statement text
  if (!bodyCheck.ok) {
    return new Response(
      JSON.stringify({ error: bodyCheck.error }),
      { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
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

  // Per-user rate limit: max 10 bank statement parses per minute
  if (!checkRateLimit(`user:${user.id}`, 10, 60_000)) {
    return rateLimitResponse(corsHeaders, 60);
  }

  const { data: tenantUser, error: tuErr } = await userClient
    .from("tenant_users")
    .select("id, role, status, tenant_id")
    .eq("auth_id", user.id)
    .eq("status", "active")
    .limit(1);

  if (tuErr || !tenantUser || tenantUser.length === 0) {
    return new Response(
      JSON.stringify({ error: "Utilisateur non autorisé" }),
      { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // SECURITY: Use the first active tenant_user record (client-side set_active_tenant ensures correct RLS context)
  const activeTenantUser = tenantUser[0];

  try {
    const body: ParseRequest = await req.json();
    const { rawText, bankName, bankId, previousTemplate, correctionNotes, attemptCount } = body;

    if (!rawText || typeof rawText !== "string" || rawText.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "rawText is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (rawText.length > 100_000) {
      return new Response(
        JSON.stringify({ error: "Input too large (max 100KB)" }),
        { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Limit input size (first 15000 chars ~ 15 pages of text)
    const truncatedText = rawText.slice(0, MAX_INPUT_CHARS);

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
    // CALL OPENAI (with retry + timeout)
    // ============================================
    let openaiResponse: Response;
    try {
      openaiResponse = await callOpenAIWithRetry(apiKey, {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.1,
        max_tokens: 4000,
        response_format: { type: "json_object" },
      });
    } catch (err) {
      console.error("OpenAI request failed after retries:", err);
      return new Response(
        JSON.stringify({ error: "AI service unavailable after retries" }),
        { status: 504, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!openaiResponse.ok) {
      const errText = await openaiResponse.text();
      console.error("OpenAI API error:", errText);
      return new Response(
        JSON.stringify({ error: `AI service error (${openaiResponse.status})` }),
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
      const rawParsed = JSON.parse(content);
      result = validateAndSanitizeResult(rawParsed);
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON from AI" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ============================================
    // SAVE TEMPLATE TO DATABASE
    // ============================================
    if (result.template && result.transactions.length > 0 && activeTenantUser.tenant_id) {
      try {
        const { data: savedTpl } = await userClient.from("bank_statement_templates").upsert({
          tenant_id: activeTenantUser.tenant_id,
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
