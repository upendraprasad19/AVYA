import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { getEmbedding } from "../_shared/embeddings.ts";
import { cascadeChat, FREE_VISION_MODELS } from "../_shared/openrouter.ts";

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

// OpenRouter free models for AI Coach chat (text + image capable).
const FREE_CHAT_MODELS = [
  "google/gemma-4-27b-it:free",
  "google/gemma-4-31b-it:free",
  "google/gemma-4-26b-a4b-it:free",
];

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
    // Validate JWT via Supabase Auth (server-side signature verification).
    // verify_jwt is DISABLED on this function's config because the Supabase
    // gateway middleware was silently rejecting valid JWTs (100% 401 rate).
    // Instead, we use supabaseClient.auth.getUser() which validates the
    // JWT signature + expiry via the Auth API — same pattern as ai-proxy-pro.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: authUser }, error: authError } = await supabaseClient.auth.getUser(token);

    if (authError || !authUser) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = authUser.id;

    // Parse request body early — needed to route food_text_analysis
    // before trial/rate-limit checks (food logging is always free).
    const body = await req.json();
    const { message, snapshot_json, type, text, context, image_base64 } = body;

    // ── Food text analysis ─────────────────────────────────────
    // Primary: OpenRouter Gemma 4 cascade (free). Fallback: Gemini 2.5 Flash Lite.
    //
    // Server-side daily cap — prevents a modified client from burning the
    // Gemini fallback key or inflating ai_coach_interactions with
    // free-tier costs. Counts distinct food_text_analysis rows per user
    // per UTC day. Client-side limits (advisory) are still the primary
    // UX; this is a safety ceiling generous enough that genuine users
    // will never hit it (50/day free, 200/day PRO).
    if (type === "food_text_analysis" && text) {
      const todayFoodStr = new Date().toISOString().split("T")[0];
      const { count: foodCount } = await supabaseClient
        .from("ai_coach_interactions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("channel", "food_text_analysis")
        .gte("created_at", todayFoodStr + "T00:00:00Z");

      // Check PRO for higher cap (server-side verification — don't trust
      // client state). isPro derived from subscriptions table row.
      const { data: sub } = await supabaseClient
        .from("subscriptions")
        .select("status, end_date")
        .eq("user_id", userId)
        .eq("status", "active")
        .gt("end_date", new Date().toISOString())
        .maybeSingle();
      const isProUser = sub !== null;
      const dailyFoodCap = isProUser ? 200 : 50;

      if ((foodCount ?? 0) >= dailyFoodCap) {
        return new Response(
          JSON.stringify({
            error: `Daily food analysis limit reached (${dailyFoodCap}/day). Try again tomorrow.`,
          }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const prompt = `You are a nutritionist with deep knowledge of Indian foods. The user says: "${text}"

Analyse this as a meal and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"meal_name":"short name for the meal","items":[{"name":"food item name","quantity":"e.g. 1 scoop, 2 rotis, 100g","calories":120,"protein":25,"carbs":3,"fat":2,"fiber":4}]}
Rules: Use ACCURATE nutrition values based on standard USDA/ICMR data for the exact quantity mentioned. One item per distinct food. All values (protein, carbs, fat, fiber) are in grams — numbers only, no "g" suffix. Fiber must reflect actual dietary fiber content. If quantity is unclear, assume a typical single serving for an Indian adult. Return ONLY the JSON object, nothing else.`;

      // Try OpenRouter free models first
      const { content: orContent } = await cascadeChat({
        models: ["google/gemma-4-31b-it:free", "google/gemma-4-26b-a4b-it:free"],
        systemPrompt: "You are a nutritionist. Return ONLY valid JSON, no markdown.",
        userPrompt: prompt,
        maxTokens: 1024,
        temperature: 0.2,
        timeoutMs: 12000,
        title: "ICANBEFITTER Food Analysis",
      });

      // Helper: log a food_text_analysis interaction row so the daily
      // cap counter sees this call. Fire-and-forget — logging failure
      // must NOT block the nutrition result.
      const logFoodInteraction = (modelLabel: string) => {
        supabaseClient
          .from("ai_coach_interactions")
          .insert({
            user_id: userId,
            channel: "food_text_analysis",
            user_message: text.substring(0, 500),
            ai_response: "",
            model_used: modelLabel,
            tokens_used: 0,
          })
          .then((r: { error: unknown }) => {
            if (r.error) console.error("food interaction log failed:", r.error);
          });
      };

      if (orContent) {
        try {
          const jsonStr = orContent.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(jsonStr);
          logFoodInteraction("openrouter-gemma-4");
          return new Response(JSON.stringify(parsed), {
            status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        } catch (_) {
          console.warn("[ai-proxy] OpenRouter food analysis returned non-JSON, falling back to Gemini");
        }
      }

      // Fallback: Gemini 2.5 Flash Lite
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (geminiKey) {
        try {
          const geminiRes = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${geminiKey}`,
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
            const jsonStr = rawText.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
            const parsed = JSON.parse(jsonStr);
            logFoodInteraction("gemini-2.5-flash-lite");
            return new Response(JSON.stringify(parsed), {
              status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
        } catch (_) {}
      }

      return new Response(JSON.stringify({ error: "Food analysis failed" }), {
        status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Vision abuse cap (scan_meal + cart_auditor: 15/day per user) ─────
    // Client-side limits handle exact free/PRO tiers; this is a server-side
    // safety net to prevent modified clients from unlimited Gemini calls.
    if (type === "scan_meal" || type === "cart_auditor") {
      const todayVisionStr = new Date().toISOString().split("T")[0];
      const { count: visionCount } = await supabaseClient
        .from("ai_coach_interactions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .in("channel", ["scan_meal", "cart_auditor"])
        .gte("created_at", todayVisionStr + "T00:00:00Z");

      if ((visionCount ?? 0) >= 15) {
        return new Response(
          JSON.stringify({ error: "Daily vision analysis limit reached. Try again tomorrow." }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
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
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${geminiKey}`,
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

          // Log usage for rate limiting
          try {
            await supabaseClient.from("ai_coach_interactions").insert({
              user_id: userId,
              channel: "scan_meal",
              user_message: "[scan_meal] analysis",
              ai_response: "success",
              model_used: "Gemini 2.5 Flash Lite",
              tokens_used: geminiData?.usageMetadata?.totalTokenCount ?? 0,
              created_at: new Date().toISOString(),
            });
          } catch (_) {}

          return new Response(JSON.stringify(parsed), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        }
      } catch (_) {}
      return new Response(JSON.stringify({ error: "Image analysis failed" }), {
        status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Cart auditor (grocery screenshot analysis) ───────────────────
    // Primary: OpenRouter Gemma 4 cascade (free, multimodal). Fallback: Gemini 2.5 Flash Lite.
    if (type === "cart_auditor" && body.image) {
      const cartPrompt = `You are a nutrition expert with deep knowledge of Indian grocery products. Analyse this grocery cart, receipt, or shopping screenshot carefully. Identify all food/grocery items visible and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"items":[{"name":"product name","category":"e.g. dairy, snack, staple, beverage, protein","quantity":"e.g. 1 pack, 500g, 1L","calories_per_serving":120,"protein_per_serving":5,"carbs_per_serving":20,"fat_per_serving":3,"is_healthy":true,"concern":"brief note if unhealthy e.g. high sugar, ultra-processed"}],"summary":{"total_items":5,"healthy_count":3,"unhealthy_count":2,"total_estimated_calories":1500,"total_estimated_protein":45,"health_score":65,"top_suggestion":"Replace Maggi with whole wheat pasta for more fiber and protein"}}
Rules: identify every distinct food product, use ACCURATE nutrition values from standard USDA/FSSAI data, is_healthy=false for ultra-processed/high-sugar/high-sodium items, health_score is 0-100, provide actionable suggestions for healthier alternatives, return ONLY the JSON object nothing else`;

      let modelUsed = "unknown";

      // Try OpenRouter Gemma free models first (multimodal)
      const { content: orContent, modelUsed: orModel } = await cascadeChat({
        models: [...FREE_VISION_MODELS],
        systemPrompt: "You are a nutrition expert. Return ONLY valid JSON, no markdown.",
        userPrompt: cartPrompt,
        imageBase64: body.image,
        imageMimeType: "image/jpeg",
        maxTokens: 2048,
        temperature: 0.2,
        timeoutMs: 15000,
        title: "ICANBEFITTER Cart Auditor",
      });

      if (orContent) {
        try {
          const jsonStr = orContent.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(jsonStr);
          modelUsed = orModel ?? "Gemma 4";
          // Log usage
          try {
            await supabaseClient.from("ai_coach_interactions").insert({
              user_id: userId, channel: "cart_auditor",
              user_message: "[cart_auditor] analysis", ai_response: "success",
              model_used: modelUsed, tokens_used: 0, created_at: new Date().toISOString(),
            });
          } catch (_) {}
          return new Response(JSON.stringify(parsed), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        } catch (_) {
          console.warn("[ai-proxy] OpenRouter cart auditor returned non-JSON, falling back to Gemini");
        }
      }

      // Fallback: Gemini 2.5 Flash Lite
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (geminiKey) {
        try {
          const geminiRes = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${geminiKey}`,
            {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                contents: [{ parts: [{ inline_data: { mime_type: "image/jpeg", data: body.image } }, { text: cartPrompt }] }],
                generationConfig: { temperature: 0.2, maxOutputTokens: 2048 },
              }),
            },
          );
          if (geminiRes.ok) {
            const geminiData = await geminiRes.json();
            const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
            const jsonStr = rawText.replace(/```json?\n?/gi, "").replace(/```/g, "").trim();
            const parsed = JSON.parse(jsonStr);
            try {
              await supabaseClient.from("ai_coach_interactions").insert({
                user_id: userId, channel: "cart_auditor",
                user_message: "[cart_auditor] analysis", ai_response: "success",
                model_used: "Gemini 2.5 Flash Lite",
                tokens_used: geminiData?.usageMetadata?.totalTokenCount ?? 0,
                created_at: new Date().toISOString(),
              });
            } catch (_) {}
            return new Response(JSON.stringify(parsed), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
          }
        } catch (_) {}
      }

      return new Response(JSON.stringify({ error: "Cart analysis failed" }), {
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

      // Try OpenRouter Gemma 4 cascade first
      const { content: predContent, modelUsed: predModel, tokensUsed: predTokens } = await cascadeChat({
        models: [...FREE_CHAT_MODELS],
        systemPrompt,
        userPrompt: message,
        maxTokens: 1024,
        temperature: 0.7,
        timeoutMs: 12000,
        title: "ICANBEFITTER Prediction",
      });

      if (predContent) {
        return new Response(
          JSON.stringify({
            reply: predContent,
            model_used: predModel ?? "Gemma 4 27B",
            tokens_used: predTokens ?? 0,
            actions: [],
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Fallback: Cerebras (text-only)
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

    // Prevent abuse: reject oversized messages and snapshots
    if (message.length > 5000) {
      return new Response(JSON.stringify({ error: "Message too long (max 5000 chars)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (snapshot_json && JSON.stringify(snapshot_json).length > 10000) {
      return new Response(JSON.stringify({ error: "Snapshot too large" }), {
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

    // Try OpenRouter Gemma 4 cascade (text + optional image).
    const { content: orContent, modelUsed: orModel, tokensUsed: orTokens } = await cascadeChat({
      models: [...FREE_CHAT_MODELS],
      systemPrompt,
      userPrompt: message,
      ...(image_base64 ? { imageBase64: image_base64, imageMimeType: "image/jpeg" } : {}),
      maxTokens: 1024,
      temperature: 0.7,
      timeoutMs: image_base64 ? 15000 : 12000,
      title: "ICANBEFITTER AI Coach",
    });

    if (!orContent) {
      // Fallback: try Cerebras keys if OpenRouter fails
      let cerebrasResult: { reply: string; tokens_used: number } | null = null;
      if (!image_base64) {
        for (const key of CEREBRAS_KEYS) {
          if (!key) continue;
          cerebrasResult = await callCerebras(key, systemPrompt, message, TIMEOUT_MS);
          if (cerebrasResult) break;
        }
      }
      if (!cerebrasResult) {
        return new Response(
          JSON.stringify({ error: "AI temporarily unavailable. Please try again." }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      // Use Cerebras fallback result
      const extracted = extractLogActions(cerebrasResult.reply);
      const modelLabel = FREE_MODEL_LABEL;

      const { data: snapshotData } = await supabaseClient
        .from("user_daily_snapshots")
        .select("id")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      await supabaseClient.from("ai_coach_interactions").insert({
        user_id: userId,
        snapshot_id: snapshotData?.id ?? null,
        channel: "app",
        user_message: message,
        ai_response: extracted.reply,
        model_used: modelLabel,
        tokens_used: cerebrasResult.tokens_used,
        created_at: new Date().toISOString(),
      });

      (async () => {
        try {
          const content = `User: ${message}\nCoach: ${extracted.reply}`;
          const embedding = await getEmbedding(content, "RETRIEVAL_DOCUMENT");
          if (!embedding) return;
          await supabaseClient.from("memory_embeddings").insert({
            user_id: userId, embedding, content, source_type: "conversation",
            metadata: { date: new Date().toISOString().split("T")[0], channel: "app", model: modelLabel },
          });
        } catch (e) { console.error("[ai-proxy] Embed store error:", e); }
      })();

      return new Response(
        JSON.stringify({ reply: extracted.reply, model_used: modelLabel, tokens_used: cerebrasResult.tokens_used, actions: extracted.actions }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const result = { reply: orContent, tokens_used: orTokens ?? 0 };
    const modelLabel = orModel ?? "Gemma 4 27B";

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
      model_used: modelLabel,
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
            model: modelLabel,
          },
        });
      } catch (e) {
        console.error("[ai-proxy] Embed store error:", e);
      }
    })();

    return new Response(
      JSON.stringify({
        reply: extracted.reply,
        model_used: modelLabel,
        tokens_used: result.tokens_used,
        actions: extracted.actions,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[ai-proxy] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
