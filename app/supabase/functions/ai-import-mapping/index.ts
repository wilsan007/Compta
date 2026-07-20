// Supabase Edge Function: AI-powered import column mapping fallback.
// Called when the heuristic auto-mapping engine returns confidence < 50%.
// Uses OpenAI GPT-4o-mini to analyze column headers + sample data and
// return a structured mapping to target fields.
//
// Deploy with:
//   supabase functions deploy ai-import-mapping --no-verify-jwt
//
// Required env var (set in Supabase dashboard → Edge Functions → Secrets):
//   OPENAI_API_KEY=sk-...

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

interface MappingRequest {
  sourceHeaders: string[];
  sampleRows: Record<string, unknown>[];
  targetFields: { key: string; label: string; required?: boolean }[];
  moduleName: string;
}

interface MappingResponse {
  mapping: Record<string, string>;
  confidence: number;
  reasoning: Record<string, string>;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    const body: MappingRequest = await req.json();
    const { sourceHeaders, sampleRows, targetFields, moduleName } = body;

    if (!sourceHeaders || !targetFields || sourceHeaders.length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing sourceHeaders or targetFields" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "OPENAI_API_KEY not configured" }),
        { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // Build the prompt for GPT
    const sampleData = sampleRows.slice(0, 5);
    const sampleTable = sampleData.map((row) => {
      const obj: Record<string, string> = {};
      for (const h of sourceHeaders) {
        obj[h] = String(row[h] ?? "").slice(0, 50);
      }
      return obj;
    });

    const fieldsDescription = targetFields
      .map((f) => `- "${f.key}" (${f.label})${f.required ? " [OBLIGATOIRE]" : ""}`)
      .join("\n");

    const systemPrompt = `Tu es un expert comptable et financier. Ton rôle est d'analyser des en-têtes de colonnes d'un fichier Excel/CSV d'import et de les associer aux champs cibles d'une base de données de comptabilité.

Module d'import: ${moduleName}

Champs cibles disponibles:
${fieldsDescription}

Réponds UNIQUEMENT avec un JSON valide, sans texte additionnel, au format:
{
  "mapping": { "fieldKey": "sourceHeader", ... },
  "confidence": 0.0-1.0,
  "reasoning": { "fieldKey": "explication courte", ... }
}

Règles:
- Associe chaque champ cible à UNE colonne source au maximum (ou laisse vide si aucune correspondance)
- Une colonne source ne peut être assignée qu'à UN seul champ
- Le score de confiance (0-1) reflète ta certitude globale sur le mapping
- Si une colonne source ne correspond à aucun champ, ne l'inclus pas dans le mapping
- Analyse à la fois les en-têtes ET les données d'exemple pour décider`;

    const userPrompt = `En-têtes du fichier: ${JSON.stringify(sourceHeaders)}

Données d'exemple (5 premières lignes):
${JSON.stringify(sampleTable, null, 2)}

Associe ces colonnes aux champs cibles. Réponds en JSON uniquement.`;

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
        max_tokens: 1500,
        response_format: { type: "json_object" },
      }),
    });

    if (!openaiResponse.ok) {
      const errText = await openaiResponse.text();
      console.error("OpenAI API error:", errText);
      return new Response(
        JSON.stringify({ error: "AI service error", details: errText }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const openaiData = await openaiResponse.json();
    const content = openaiData.choices?.[0]?.message?.content;

    if (!content) {
      return new Response(
        JSON.stringify({ error: "Empty AI response" }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    let result: MappingResponse;
    try {
      result = JSON.parse(content);
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON from AI", raw: content }),
        { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // Validate: only allow mapping to actual source headers
    const validMapping: Record<string, string> = {};
    const validReasoning: Record<string, string> = {};
    for (const [fieldKey, sourceCol] of Object.entries(result.mapping || {})) {
      if (sourceHeaders.includes(sourceCol) && targetFields.some((f) => f.key === fieldKey)) {
        validMapping[fieldKey] = sourceCol;
        if (result.reasoning?.[fieldKey]) {
          validReasoning[fieldKey] = result.reasoning[fieldKey];
        }
      }
    }

    return new Response(
      JSON.stringify({
        mapping: validMapping,
        confidence: result.confidence ?? 0.5,
        reasoning: validReasoning,
      }),
      {
        status: 200,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(
      JSON.stringify({ error: "Internal error", details: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});
