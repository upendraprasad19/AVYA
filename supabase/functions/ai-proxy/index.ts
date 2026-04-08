import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { getEmbedding } from "../_shared/embeddings.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 3 Cerebras keys → rotate on rate limit → triples effective free quota.
const CEREBRAS_KEYS = [
  Deno.env.get("CEREBRAS_API_KEY_1")!,
  Deno.env.get("CEREBRAS_API_KEY_2")!,
  Deno.env.get("CEREBRAS_API_KEY_3")!,
];

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FREE_MODEL = "llama3.1-8b";
const FREE_MODEL_LABEL = "Cerebras Llama 3.1 8B";
const CEREBRAS_URL = "https://api.cerebras.ai/v1/chat/completions";

const FREE_DAILY_LIMIT = 15;
const FREE_TRIAL_DAYS = 30;
const TIMEOUT_MS = 8000;
const DEDUP_WINDOW_SECS = 30; // Ignore duplicate messages within 30 seconds

async function callCerebras(
  apiKey: string,
  systemPrompt: string,
  userMessage: string,
  timeoutMs: number,
): Promise<{ reply: string; tokens_used: number } | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(CEREBRAS_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: FREE_MODEL,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        max_tokens: 1024,
        temperature: 0.7,
      }),
      signal: controller.signal,
    });

    // 429 = rate limited on this key — caller will try next key.
    if (!response.ok) return null;

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) return null;

    return {
      reply: content,
      tokens_used: data.usage?.total_tokens ?? 0,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Extract structured log actions from AI response.
 * Tags like <ICBF_LOG>{...}</ICBF_LOG> are parsed and stripped from the
 * visible reply. Returns clean text + an array of action objects.
 */
function extractLogActions(rawReply: string): {
  reply: string;
  actions: Array<{ action: string; data: Record<string, unknown> }>;
} {
  const actions: Array<{ action: string; data: Record<string, unknown> }> = [];
  const tagPattern = /<ICBF_LOG>([\s\S]*?)<\/ICBF_LOG>/g;
  let cleanReply = rawReply;
  let match;

  while ((match = tagPattern.exec(rawReply)) !== null) {
    try {
      const parsed = JSON.parse(match[1]);
      if (parsed.action && parsed.data) {
        actions.push({ action: parsed.action, data: parsed.data });
      }
    } catch {
      // Malformed JSON in tag — skip silently.
    }
    cleanReply = cleanReply.replace(match[0], "").trim();
  }

  return { reply: cleanReply, actions };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Extract user ID from JWT.
    // verify_jwt is DISABLED on this function because the Supabase gateway
    // was silently rejecting valid JWTs (100% 401 rate). We validate manually
    // with proper Base64URL decode and expiry check.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    let userId: string;
    let jwtExpired = false;
    try {
      const parts = token.split(".");
      if (parts.length !== 3) throw new Error("Invalid JWT format");
      // JWT uses Base64URL encoding — convert to standard Base64 for atob()
      let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      while (base64.length % 4) base64 += "=";
      const payload = JSON.parse(atob(base64));
      userId = payload.sub;
      if (!userId) throw new Error("No sub claim in JWT");
      // Manual expiry check (since verify_jwt is disabled)
      const exp = payload.exp as number | undefined;
      if (exp && Date.now() / 1000 > exp) {
        jwtExpired = true;
      }
    } catch {
      return new Response(JSON.stringify({ error: "Invalid token format" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (jwtExpired) {
      return new Response(JSON.stringify({ error: "Token expired" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Service role client for DB operations only (NOT for auth validation)
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Parse request body early — needed to route food_text_analysis
    // before trial/rate-limit checks (food logging is always free).
    const body = await req.json();
    const { message, snapshot_json, type, text, context } = body;

    // ── Food text analysis (separate path — no trial/rate-limit check) ────
    if (type === "food_text_analysis" && text) {
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (!geminiKey) {
        return new Response(JSON.stringify({ error: "Food AI unavailable" }), {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const prompt = `You are a nutritionist with deep knowledge of Indian foods. The user says: "${text}"

Analyse this as a meal and return ONLY a JSON object (no markdown, no code block) in this exact format:
{
  "meal_name": "short name for the meal",
  "items": [
    {
      "name": "food item name",
      "quantity": "e.g. 1 scoop, 2 rotis, 100g",
      "calories": 120,
      "protein": 25,
      "carbs": 3,
      "fat": 2,
      "fiber": 4
    }
  ]
}

Rules:
- Use ACCURATE nutrition values based on standard USDA/ICMR data for the exact quantity mentioned
- One item per distinct food
- All values (protein, carbs, fat, fiber) are in grams — numbers only, no "g" suffix
- IMPORTANT: fiber must reflect the actual dietary fiber content (e.g. broccoli 100g = 2.6g fiber, dal 100g = 8g fiber, roti 1 piece = 1.5g fiber, oats 40g = 3g fiber). Never return 0 for high-fiber foods.
- If quantity is unclear, assume a typical single serving for an Indian adult
- Return ONLY the JSON object, nothing else`;

      try {
        const geminiRes = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
            }),
          },
        );

        if (geminiRes.ok) {
          const geminiData = await geminiRes.json();
          const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          // Strip any markdown code fences if present
          const jsonStr = rawText.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(jsonStr);
          return new Response(JSON.stringify(parsed), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
      } catch (_) {
        // Fall through to error
      }

      return new Response(JSON.stringify({ error: "Food analysis failed" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Scan meal (image analysis) ────────────────────────────────────
    if (type === "scan_meal" && body.image) {
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (!geminiKey) {
        return new Response(JSON.stringify({ error: "Food AI unavailable" }), {
          status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const scanPrompt = `You are a nutritionist with deep knowledge of Indian foods. Look at this food photo carefully. Identify all food items visible and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"meal_name":"short name describing the meal","items":[{"name":"food item name","quantity":"estimated quantity e.g. 1 bowl, 2 rotis, 100g","calories":120,"protein":25,"carbs":3,"fat":2,"fiber":4}]}
Rules: identify every distinct food item, estimate realistic portion sizes for an Indian adult, use ACCURATE USDA/ICMR nutrition values, all macro values are numbers in grams no g suffix, fiber must reflect actual dietary fiber never return 0 for high-fiber foods, return ONLY the JSON object nothing else`;
      try {
        const geminiRes = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts: [{ inline_data: { mime_type: "image/jpeg", data: body.image } }, { text: scanPrompt }] }],
              generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
            }),
          },
        );
        if (geminiRes.ok) {
          const geminiData = await geminiRes.json();
          const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          const jsonStr = rawText.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(jsonStr);
          return new Response(JSON.stringify(parsed), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        }
      } catch (_) {}
      return new Response(JSON.stringify({ error: "Image analysis failed" }), {
        status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Prediction handler — bypasses daily limits + interaction logging ──
    // Used for onboarding predictions and PRO monthly refreshes.
    // This is a FREE system function, not an AI Coach message.
    if (type === "prediction") {
      if (!message || typeof message !== "string") {
        return new Response(JSON.stringify({ error: "Missing 'message' for prediction" }), {
          status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const systemPrompt = (context?.system_prompt as string) ??
        "You are a sports science expert making evidence-based fitness predictions. Be specific with numbers but realistic.";

      let result: { reply: string; tokens_used: number } | null = null;
      for (const key of CEREBRAS_KEYS) {
        if (!key) continue;
        result = await callCerebras(key, systemPrompt, message, TIMEOUT_MS);
        if (result) break;
      }

      if (!result) {
        return new Response(
          JSON.stringify({ error: "AI temporarily unavailable" }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // No daily limit check. No ai_coach_interactions logging.
      return new Response(
        JSON.stringify({
          reply: result.reply,
          model_used: FREE_MODEL_LABEL,
          tokens_used: result.tokens_used,
          actions: [],
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!message || typeof message !== "string") {
      return new Response(JSON.stringify({ error: "Missing 'message' in request body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Trial + rate-limit check for AI chat ─────────────────────────
    const { data: userData, error: userError } = await supabaseClient
      .from("users")
      .select("ai_chat_started_at")
      .eq("id", userId)
      .single();

    if (userError || !userData) {
      return new Response(JSON.stringify({ error: "User not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let aiChatStartedAt = userData.ai_chat_started_at;
    if (!aiChatStartedAt) {
      const now = new Date().toISOString();
      await supabaseClient
        .from("users")
        .update({ ai_chat_started_at: now })
        .eq("id", userId);
      aiChatStartedAt = now;
    }

    const daysSinceStart = Math.floor(
      (Date.now() - new Date(aiChatStartedAt).getTime()) / (1000 * 60 * 60 * 24),
    );

    if (daysSinceStart > FREE_TRIAL_DAYS) {
      return new Response(
        JSON.stringify({ error: "Free AI trial expired", code: "TRIAL_EXPIRED", days_used: daysSinceStart }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const todayStart = new Date();
    todayStart.setUTCHours(0, 0, 0, 0);

    const { count: msgCount, error: countError } = await supabaseClient
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("channel", "app")
      .gte("created_at", todayStart.toISOString());

    if (countError) {
      return new Response(JSON.stringify({ error: "Failed to check rate limit" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if ((msgCount ?? 0) >= FREE_DAILY_LIMIT) {
      return new Response(
        JSON.stringify({ error: "Daily message limit reached", code: "RATE_LIMITED", limit: FREE_DAILY_LIMIT }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Deduplication: return cached response if same user sent same message recently ──
    const dedupCutoff = new Date(Date.now() - DEDUP_WINDOW_SECS * 1000).toISOString();
    const { data: recentDup } = await supabaseClient
      .from("ai_coach_interactions")
      .select("ai_response, model_used, tokens_used")
      .eq("user_id", userId)
      .eq("channel", "app")
      .eq("user_message", message)
      .gte("created_at", dedupCutoff)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recentDup?.ai_response) {
      console.log(`[ai-proxy] Dedup hit for user ${userId} — returning cached response`);
      const extracted = extractLogActions(recentDup.ai_response);
      return new Response(
        JSON.stringify({
          reply: extracted.reply,
          model_used: recentDup.model_used ?? FREE_MODEL_LABEL,
          tokens_used: recentDup.tokens_used ?? 0,
          actions: extracted.actions,
          deduplicated: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Build system prompt
    let systemPrompt =
      "You are ICANBEFITTER AI Coach, a caring and knowledgeable fitness coach " +
      "for young professionals in India — like a father who has been watching closely. " +
      "Keep responses concise, actionable, and direct. Be caring but honest. " +
      "Use metric units (kg, cm). Reference Indian foods and context when relevant. " +
      "If coach_notices are present in the snapshot, weave them naturally into your response " +
      "(do NOT list them robotically). Reference specific numbers. Celebrate wins. Call out problems directly." +
      "\n\nFITNESS DATA LOGGING — INSTANT:" +
      "\nWhen the user explicitly states they ALREADY completed an action, embed ONE tag at the END of your response:" +
      '\n<ICBF_LOG>{"action":"log_water","data":{"ml":500}}</ICBF_LOG>' +
      '\n<ICBF_LOG>{"action":"log_weight","data":{"weight_kg":73.5}}</ICBF_LOG>' +
      '\n<ICBF_LOG>{"action":"log_food","data":{"food_name":"Dal Rice","meal_type":"lunch","quantity_g":200,"calories_estimate":280,"protein_estimate":9,"carbs_estimate":55,"fat_estimate":3}}</ICBF_LOG>' +
      '\n<ICBF_LOG>{"action":"log_sleep","data":{"duration_hrs":7,"quality":"good"}}</ICBF_LOG>' +
      '\n<ICBF_LOG>{"action":"log_measurement","data":{"type":"waist","value_cm":82}}</ICBF_LOG>' +
      "\nMeasurement types: waist, chest, hips, arms. Convert inches to cm (multiply by 2.54)." +
      "\nWater: 2 glasses=500ml, 1 bottle=750ml, 1 cup=250ml, 1 litre=1000ml." +
      "\nRULES:" +
      "\n- Only for CONFIRMED PAST actions (I drank, I weighed, I ate, I slept, my waist is). NEVER for future plans or questions." +
      "\n- The tag is stripped server-side — do not mention it in your visible response." +
      "\n- One tag per response maximum." +
      "\n\nWORKOUT LOGGING — MULTI-TURN:" +
      "\n- If user says they finished a workout WITHOUT exercise details, ask them to describe exercises, sets, reps, weights. No tag yet." +
      "\n- If user provides exercise details, parse them and emit:" +
      '\n<ICBF_LOG>{"action":"confirm_workout_log","data":{"exercises":[{"name":"Bench Press","logging_type":"weight_reps","sets":[{"weight_kg":80,"reps":8}]},{"name":"Push-ups","logging_type":"bodyweight_reps","sets":[{"reps":15}]},{"name":"Plank","logging_type":"timed","sets":[{"duration_secs":60}]},{"name":"Running","logging_type":"cardio","duration_mins":30,"distance_km":5}]}}</ICBF_LOG>' +
      '\nParse "5x8 at 80kg" as 5 sets of 8 reps at 80kg. logging_type: weight_reps (weight+reps), bodyweight_reps (reps only), timed (duration), cardio (time/distance).';

    if (snapshot_json) {
      systemPrompt += "\n\nUser's daily snapshot:\n" + JSON.stringify(snapshot_json);
    }

    // Try all 3 Cerebras keys in order — rotate on rate limit.
    let result: { reply: string; tokens_used: number } | null = null;

    for (const key of CEREBRAS_KEYS) {
      if (!key) continue;
      result = await callCerebras(key, systemPrompt, message, TIMEOUT_MS);
      if (result) break;
    }

    if (!result) {
      return new Response(
        JSON.stringify({ error: "AI temporarily unavailable. Please try again." }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Extract structured log actions from AI reply
    const extracted = extractLogActions(result.reply);

    // Fetch latest snapshot_id for logging
    const { data: snapshotData } = await supabaseClient
      .from("user_daily_snapshots")
      .select("id")
      .eq("user_id", userId)
      .order("snapshot_date", { ascending: false })
      .limit(1)
      .single();

    // Log interaction (store clean reply without tags)
    await supabaseClient.from("ai_coach_interactions").insert({
      user_id: userId,
      snapshot_id: snapshotData?.id ?? null,
      channel: "app",
      user_message: message,
      ai_response: extracted.reply,
      model_used: FREE_MODEL_LABEL,
      tokens_used: result.tokens_used,
      created_at: new Date().toISOString(),
    });

    // ── Phase A: Silent embedding accumulation (FREE tier) ─────────────────
    // FREE users do NOT get retrieval — no latency hit, no PRO feature leak.
    // Their embeddings silently accumulate so memory is rich if they upgrade.
    // Fire-and-forget: Response is already built above; this runs after.
    (async () => {
      try {
        const content = `User: ${message}\nCoach: ${extracted.reply}`;
        const embedding = await getEmbedding(content, "RETRIEVAL_DOCUMENT");
        if (!embedding) return;
        await supabaseClient.from("memory_embeddings").insert({
          user_id: userId,
          embedding,
          content,
          source_type: "conversation",
          metadata: {
            date: new Date().toISOString().split("T")[0],
            channel: "app",
            model: FREE_MODEL_LABEL,
          },
        });
      } catch (e) {
        console.error("[ai-proxy] Embed store error:", e);
      }
    })();

    return new Response(
      JSON.stringify({
        reply: extracted.reply,
        model_used: FREE_MODEL_LABEL,
        tokens_used: result.tokens_used,
        actions: extracted.actions,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
