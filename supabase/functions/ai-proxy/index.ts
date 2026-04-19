/**
 * ai-proxy — single Gemini-backed endpoint for all AI coach traffic.
 *
 * Rewrite history (2026-04-18):
 *   Collapsed the previous three-tier stack (Cerebras direct +
 *   OpenRouter Gemma cascade + Gemini vision fallback) down to a
 *   single Google Gemini provider. Also merged the separate
 *   `ai-proxy-pro` endpoint into this one — the PRO branch used to
 *   require a distinct function for unlimited chat, but since both
 *   paths now target the same provider, a single function with an
 *   `isPro` gate is simpler.
 *
 * Routing table (set by request body `type`):
 *   food_text_analysis  → gemini-2.5-flash, JSON mode, 50/day free · 200/day PRO
 *   scan_meal           → gemini-2.5-flash-lite (vision), JSON mode, 15/day server cap
 *   cart_auditor        → gemini-2.5-flash-lite (vision), JSON mode, 15/day server cap
 *   prediction          → gemini-2.5-flash, JSON mode, no daily cap (onboarding/monthly)
 *   (default)           → gemini-2.5-flash, chat — 15/day free cap, PRO unlimited
 *
 * Gating (server-side, never trust client):
 *   isPro = SELECT 1 FROM subscriptions WHERE user_id AND status='active' AND end_date > now()
 *   Free-tier chat: 15/day in `ai_coach_interactions` (channel='app') + 30-day trial window
 *   PRO: no daily cap, no trial window
 *
 * Auth: verify_jwt is DISABLED on this function's gateway config because
 * of the Supabase middleware bug that 401's valid JWTs. We validate the
 * bearer token ourselves via `auth.getUser(token)`.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { getEmbedding } from "../_shared/embeddings.ts";
import {
  geminiChat,
  MODEL_FLASH,
  MODEL_FLASH_LITE,
} from "../_shared/gemini.ts";
import {
  fetchCoachMemory,
  renderCoachMemoryBlock,
} from "../_shared/coach_memory.ts";
import { runToolLoop } from "../_shared/tool-loop.ts";
import type { ToolContext } from "../_shared/tools/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FREE_DAILY_LIMIT = 15;
const FREE_TRIAL_DAYS = 30;
const DEDUP_WINDOW_SECS = 30; // Ignore duplicate messages within 30 seconds

// Human-readable labels for the ai_coach_interactions.model_used column.
const LABEL_FLASH = "Gemini 2.5 Flash";
const LABEL_FLASH_LITE = "Gemini 2.5 Flash Lite";

/**
 * Check if a user holds an active PRO subscription. Returns false on any
 * error (fail closed — cheaper to incorrectly gate a PRO user than to
 * leak unlimited chat to a free user).
 */
async function checkPro(
  client: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  try {
    const { data } = await client
      .from("subscriptions")
      .select("status")
      .eq("user_id", userId)
      .eq("status", "active")
      .gt("end_date", new Date().toISOString())
      .maybeSingle();
    return data !== null;
  } catch (_) {
    return false;
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

/** Strip markdown code fences before JSON.parse. Gemini sometimes wraps. */
function stripJsonFences(raw: string): string {
  return raw
    .replace(/```json?\n?/gi, "")
    .replace(/```/g, "")
    .trim();
}

/** Uniform error response shape. */
function err(status: number, message: string, extra: Record<string, unknown> = {}) {
  return new Response(
    JSON.stringify({ error: message, ...extra }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return err(405, "Method not allowed");

  try {
    // ── JWT ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return err(401, "Missing authorization header");

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: authUser }, error: authError } =
      await supabaseClient.auth.getUser(token);

    if (authError || !authUser) return err(401, "Invalid or expired token");
    const userId = authUser.id;

    // ── Body ──
    const body = await req.json();
    const { message, snapshot_json, type, text, context, image_base64 } = body;

    // ── Food text analysis ────────────────────────────────────────
    // Free: 50/day  ·  PRO: 200/day. Enforced atomically by Postgres
    // trigger `trg_food_text_rate_limit` (migration 024) on the
    // `ai_coach_interactions` table — not by a check-then-insert dance
    // inside this handler. The old TOCTOU race (two simultaneous
    // requests both seeing count=49 and both inserting) is closed.
    //
    // Flow:
    //   1. Insert a placeholder row with channel='food_text_analysis'
    //      (awaited). Trigger raises P0001 if over cap — we catch and
    //      return 429 without calling Gemini, saving tokens.
    //   2. Call Gemini on the valid reservation.
    //   3. UPDATE the row with the response + model + tokens.
    if (type === "food_text_analysis" && text) {
      // Step 1 — reserve a slot (or get rejected by the trigger).
      const { data: reservation, error: insertErr } = await supabaseClient
        .from("ai_coach_interactions")
        .insert({
          user_id: userId,
          channel: "food_text_analysis",
          user_message: text.substring(0, 500),
          ai_response: "",
          model_used: "pending",
          tokens_used: 0,
        })
        .select("id")
        .single();

      if (insertErr) {
        const msg = String(insertErr.message ?? "");
        if (msg.includes("food_text_daily_limit_reached")) {
          const isProUser = await checkPro(supabaseClient, userId);
          const cap = isProUser ? 200 : 50;
          return err(
            429,
            `Daily food analysis limit reached (${cap}/day). Try again tomorrow.`,
          );
        }
        console.error("[ai-proxy.food] reservation insert failed:", insertErr);
        return err(500, "Food analysis unavailable");
      }

      const reservationId = reservation?.id as string | undefined;

      const prompt = `You are a nutritionist with deep knowledge of Indian foods. The user says: "${text}"

Analyse this as a meal and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"meal_name":"short name for the meal","items":[{"name":"food item name","quantity":"e.g. 1 scoop, 2 rotis, 100g","calories":120,"protein":25,"carbs":3,"fat":2,"fiber":4}]}
Rules: Use ACCURATE nutrition values based on standard USDA/ICMR data for the exact quantity mentioned. One item per distinct food. All values (protein, carbs, fat, fiber) are in grams — numbers only, no "g" suffix. Fiber must reflect actual dietary fiber content. If quantity is unclear, assume a typical single serving for an Indian adult. Return ONLY the JSON object, nothing else.`;

      // Step 2 — call Gemini on the valid reservation.
      const { content, modelUsed, tokensUsed } = await geminiChat({
        model: MODEL_FLASH,
        systemPrompt: "You are a nutritionist. Return ONLY valid JSON, no markdown.",
        userPrompt: prompt,
        maxTokens: 1024,
        temperature: 0.2,
        timeoutMs: 15_000,
        jsonMode: true,
      });

      if (!content) return err(502, "Food analysis failed");

      try {
        const parsed = JSON.parse(stripJsonFences(content));
        // Step 3 — update the reserved row with real telemetry. Fire-and-forget
        // so the response doesn't block on this final write.
        if (reservationId) {
          supabaseClient
            .from("ai_coach_interactions")
            .update({
              model_used: modelUsed === MODEL_FLASH_LITE ? LABEL_FLASH_LITE : LABEL_FLASH,
              tokens_used: tokensUsed,
            })
            .eq("id", reservationId)
            .then((r: { error: unknown }) => {
              if (r.error) console.error("food interaction update failed:", r.error);
            });
        }

        return new Response(JSON.stringify(parsed), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (_) {
        return err(502, "Food analysis returned invalid JSON");
      }
    }

    // ── Vision abuse cap (scan_meal + cart_auditor: 15/day per user) ─────
    if (type === "scan_meal" || type === "cart_auditor") {
      const todayVisionStr = new Date().toISOString().split("T")[0];
      const { count: visionCount } = await supabaseClient
        .from("ai_coach_interactions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .in("channel", ["scan_meal", "cart_auditor"])
        .gte("created_at", todayVisionStr + "T00:00:00Z");

      if ((visionCount ?? 0) >= 15) {
        return err(429, "Daily vision analysis limit reached. Try again tomorrow.");
      }
    }

    // ── Scan meal (image → nutrition JSON) ────────────────────────
    if (type === "scan_meal" && body.image) {
      const scanPrompt =
        `You are a nutritionist with deep knowledge of Indian foods. Look at this food photo carefully. Identify all food items visible and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"meal_name":"short name describing the meal","items":[{"name":"food item name","quantity":"estimated quantity e.g. 1 bowl, 2 rotis, 100g","calories":120,"protein":25,"carbs":3,"fat":2,"fiber":4}]}
Rules: identify every distinct food item, estimate realistic portion sizes for an Indian adult, use ACCURATE USDA/ICMR nutrition values, all macro values are numbers in grams no g suffix, fiber must reflect actual dietary fiber never return 0 for high-fiber foods, return ONLY the JSON object nothing else`;

      const { content, tokensUsed } = await geminiChat({
        model: MODEL_FLASH_LITE,
        systemPrompt: "You are a nutritionist. Return ONLY valid JSON, no markdown.",
        userPrompt: scanPrompt,
        imageBase64: body.image,
        imageMimeType: "image/jpeg",
        maxTokens: 1024,
        temperature: 0.2,
        timeoutMs: 20_000,
        jsonMode: true,
        fallbackToLite: false, // already Flash-Lite; no point
      });

      if (!content) return err(502, "Image analysis failed");

      try {
        const parsed = JSON.parse(stripJsonFences(content));
        try {
          await supabaseClient.from("ai_coach_interactions").insert({
            user_id: userId,
            channel: "scan_meal",
            user_message: "[scan_meal] analysis",
            ai_response: "success",
            model_used: LABEL_FLASH_LITE,
            tokens_used: tokensUsed,
            created_at: new Date().toISOString(),
          });
        } catch (_) {}
        return new Response(JSON.stringify(parsed), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (_) {
        return err(502, "Image analysis returned invalid JSON");
      }
    }

    // ── Cart auditor (grocery screenshot → audit JSON) ────────────
    if (type === "cart_auditor" && body.image) {
      const cartPrompt =
        `You are a nutrition expert with deep knowledge of Indian grocery products. Analyse this grocery cart, receipt, or shopping screenshot carefully. Identify all food/grocery items visible and return ONLY a JSON object (no markdown, no code block) in this exact format:
{"items":[{"name":"product name","category":"e.g. dairy, snack, staple, beverage, protein","quantity":"e.g. 1 pack, 500g, 1L","calories_per_serving":120,"protein_per_serving":5,"carbs_per_serving":20,"fat_per_serving":3,"is_healthy":true,"concern":"brief note if unhealthy e.g. high sugar, ultra-processed"}],"summary":{"total_items":5,"healthy_count":3,"unhealthy_count":2,"total_estimated_calories":1500,"total_estimated_protein":45,"health_score":65,"top_suggestion":"Replace Maggi with whole wheat pasta for more fiber and protein"}}
Rules: identify every distinct food product, use ACCURATE nutrition values from standard USDA/FSSAI data, is_healthy=false for ultra-processed/high-sugar/high-sodium items, health_score is 0-100, provide actionable suggestions for healthier alternatives, return ONLY the JSON object nothing else`;

      const { content, tokensUsed } = await geminiChat({
        model: MODEL_FLASH_LITE,
        systemPrompt: "You are a nutrition expert. Return ONLY valid JSON, no markdown.",
        userPrompt: cartPrompt,
        imageBase64: body.image,
        imageMimeType: "image/jpeg",
        maxTokens: 2048,
        temperature: 0.2,
        timeoutMs: 25_000,
        jsonMode: true,
        fallbackToLite: false,
      });

      if (!content) return err(502, "Cart analysis failed");

      try {
        const parsed = JSON.parse(stripJsonFences(content));
        try {
          await supabaseClient.from("ai_coach_interactions").insert({
            user_id: userId,
            channel: "cart_auditor",
            user_message: "[cart_auditor] analysis",
            ai_response: "success",
            model_used: LABEL_FLASH_LITE,
            tokens_used: tokensUsed,
            created_at: new Date().toISOString(),
          });
        } catch (_) {}
        return new Response(JSON.stringify(parsed), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (_) {
        return err(502, "Cart analysis returned invalid JSON");
      }
    }

    // ── Prediction handler ────────────────────────────────────────
    // Onboarding predictions + PRO monthly refreshes. Free system
    // function; no daily limits, no interaction logging.
    if (type === "prediction") {
      if (!message || typeof message !== "string") {
        return err(400, "Missing 'message' for prediction");
      }

      const systemPrompt = (context?.system_prompt as string) ??
        "You are a sports science expert making evidence-based fitness predictions. Be specific with numbers but realistic.";

      const { content, modelUsed, tokensUsed } = await geminiChat({
        model: MODEL_FLASH,
        systemPrompt,
        userPrompt: message,
        maxTokens: 1024,
        temperature: 0.7,
        timeoutMs: 15_000,
        jsonMode: true,
      });

      if (!content) return err(502, "AI temporarily unavailable");

      return new Response(
        JSON.stringify({
          reply: content,
          model_used: modelUsed === MODEL_FLASH_LITE ? LABEL_FLASH_LITE : LABEL_FLASH,
          tokens_used: tokensUsed,
          actions: [],
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── AI coach chat (free + PRO via single function) ────────────
    if (!message || typeof message !== "string") {
      return err(400, "Missing 'message' in request body");
    }
    if (message.length > 5000) {
      return err(400, "Message too long (max 5000 chars)");
    }
    if (snapshot_json && JSON.stringify(snapshot_json).length > 10000) {
      return err(400, "Snapshot too large");
    }

    // ── isPro gate: PRO → no trial, no daily cap. Free → trial + 15/day. ──
    const isProUser = await checkPro(supabaseClient, userId);

    if (!isProUser) {
      // Free-tier gates: start/bump trial window, count today's messages.
      const { data: userData, error: userError } = await supabaseClient
        .from("users")
        .select("ai_chat_started_at")
        .eq("id", userId)
        .single();

      if (userError || !userData) return err(404, "User not found");

      let aiChatStartedAt = userData.ai_chat_started_at as string | null;
      if (!aiChatStartedAt) {
        const now = new Date().toISOString();
        await supabaseClient
          .from("users")
          .update({ ai_chat_started_at: now })
          .eq("id", userId);
        aiChatStartedAt = now;
      }

      const daysSinceStart = Math.floor(
        (Date.now() - new Date(aiChatStartedAt).getTime()) /
          (1000 * 60 * 60 * 24),
      );

      if (daysSinceStart > FREE_TRIAL_DAYS) {
        return err(403, "Free AI trial expired", {
          code: "TRIAL_EXPIRED",
          days_used: daysSinceStart,
        });
      }

      const todayStart = new Date();
      todayStart.setUTCHours(0, 0, 0, 0);

      const { count: msgCount, error: countError } = await supabaseClient
        .from("ai_coach_interactions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("channel", "app")
        .gte("created_at", todayStart.toISOString());

      if (countError) return err(500, "Failed to check rate limit");

      if ((msgCount ?? 0) >= FREE_DAILY_LIMIT) {
        return err(429, "Daily message limit reached", {
          code: "RATE_LIMITED",
          limit: FREE_DAILY_LIMIT,
        });
      }
    }

    // ── Deduplication: return cached response for same user+message in last 30s ──
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
      const extracted = extractLogActions(recentDup.ai_response as string);
      return new Response(
        JSON.stringify({
          reply: extracted.reply,
          model_used: recentDup.model_used ?? LABEL_FLASH,
          tokens_used: recentDup.tokens_used ?? 0,
          actions: extracted.actions,
          deduplicated: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Fetch coach_memory for identity-mirroring (chat path only) ──
    // Block [3] of the 7-block context layout. Helper returns "" when
    // private_mode=true or no row exists, so the truthy check below drops
    // it silently. Wrapped in try/catch — a memory fetch failure must
    // never kill the chat response.
    //
    // Channel guard: every non-chat channel (food_text_analysis,
    // scan_meal, cart_auditor, prediction) returns earlier in this
    // handler. The explicit `isChatChannel` check below is a defensive
    // belt-and-braces — if a future channel forgets the early return,
    // this gate prevents the +1 SELECT and the prompt pollution.
    //
    // Cost note: this adds +1 SELECT per chat call (coach_memory row).
    const isChatChannel = !type || type === "chat";
    let coachMemoryBlock = "";
    // Reuse the request_id minted in the outer catch when available; the
    // outer scope's `requestId` only exists in the catch block, so mint a
    // local one here for the non-fatal warn log to satisfy the project's
    // standard catch-block format (CLAUDE.md §11).
    const chatRequestId = crypto.randomUUID().split("-")[0];
    if (isChatChannel) {
      try {
        const coachMemory = await fetchCoachMemory(supabaseClient, userId);
        coachMemoryBlock = renderCoachMemoryBlock(coachMemory);
      } catch (e) {
        console.warn(
          `[ai-proxy] coach_memory fetch failed (non-fatal) request_id=${chatRequestId}`,
          e,
        );
      }
    }

    // ── Build system prompt ───────────────────────────────────────
    const baseSystemPrompt =
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

    // Assemble in the spec'd order: base prompt → [3] coach_memory →
    // snapshot. The block self-labels [3] in renderCoachMemoryBlock,
    // and prepending it to the base used to put it before blocks
    // [1]/[2] of the 7-block layout. Empty coachMemoryBlock (private
    // mode, no row, or non-chat channel) is dropped by the truthy
    // check.
    const promptParts: string[] = [baseSystemPrompt];
    if (coachMemoryBlock) promptParts.push(coachMemoryBlock);
    if (snapshot_json) {
      promptParts.push("User's daily snapshot:\n" + JSON.stringify(snapshot_json));
    }
    const systemPrompt = promptParts.join("\n\n");

    // ── Multi-round tool-calling loop (Phase A, 2026-04-19) ────────
    // Replaces the previous single-shot geminiChat() with a 3-round
    // loop that lets Gemini call server-side read tools (executed in
    // place) and emit typed write intents (returned to the client for
    // user confirmation + Hive execution).
    //
    // Other channels above (food_text_analysis / scan_meal /
    // cart_auditor / prediction) still use the single-shot helper —
    // tool calling is chat-only.
    //
    // image_base64 vision-on-chat is dropped at this point: the loop
    // helper does not currently accept inline_data parts. The only
    // production caller of vision-on-chat (the PRO photo-upload chat
    // surface) routes through `ai-media-proxy`, not this function, so
    // there is no live regression. If we need to support inline images
    // here in future, plumb them through `geminiChatWithTools`.
    const toolCtx: ToolContext = {
      userId,
      isPro: isProUser,
      sb: supabaseClient,
      requestId: chatRequestId,
    };

    let loop;
    try {
      loop = await runToolLoop({
        systemPrompt,
        userMessage: message,
        ctx: toolCtx,
        model: MODEL_FLASH,
      });
    } catch (loopErr) {
      console.error(
        `[ai-proxy] runToolLoop threw request_id=${chatRequestId}`,
        loopErr,
      );
      return err(502, "AI temporarily unavailable. Please try again.", {
        request_id: chatRequestId,
      });
    }

    // The loop's final text may still contain legacy <ICBF_LOG> tags
    // until Phase E removes those instructions from the system prompt.
    // Keep the extractor wired so existing log_water/log_food/etc. paths
    // still work end-to-end during the migration.
    const extracted = extractLogActions(loop.text);
    const cleanReply = extracted.reply;

    // If the loop fell back to Flash-Lite at any round, label the row
    // accordingly so analytics see the actual provider that produced
    // the final response.
    const modelLabel = loop.usedFallback ? LABEL_FLASH_LITE : LABEL_FLASH;

    // Fetch latest snapshot_id for logging
    const { data: snapshotData } = await supabaseClient
      .from("user_daily_snapshots")
      .select("id")
      .eq("user_id", userId)
      .order("snapshot_date", { ascending: false })
      .limit(1)
      .single();

    // Log interaction (store clean reply without tags) + tool-call telemetry.
    await supabaseClient.from("ai_coach_interactions").insert({
      user_id: userId,
      snapshot_id: snapshotData?.id ?? null,
      channel: "app",
      user_message: message,
      ai_response: cleanReply,
      model_used: modelLabel,
      tokens_used: loop.tokensUsed,
      tool_calls: loop.toolCallsLog.length > 0 ? loop.toolCallsLog : null,
      created_at: new Date().toISOString(),
    });

    // Silent embedding accumulation for both free + PRO tiers. Free
    // users don't get retrieval (no latency), but their memory is
    // ready if they upgrade. Fire-and-forget.
    //
    // Skip when the model emitted only tool calls (no conversational
    // text to embed). Append a one-line intent summary so retrieval
    // still has a hook on the structured action when there IS prose.
    if (cleanReply.trim().length > 0 || loop.intents.length === 0) {
      (async () => {
        try {
          const intentSummary = loop.intents.length > 0
            ? ` [queued: ${loop.intents.map((i) => i.type).join(", ")}]`
            : "";
          const content_ = `User: ${message}\nCoach: ${cleanReply}${intentSummary}`;
          const embedding = await getEmbedding(content_, "RETRIEVAL_DOCUMENT");
          if (!embedding) return;
          await supabaseClient.from("memory_embeddings").insert({
            user_id: userId,
            embedding,
            content: content_,
            source_type: "conversation",
            metadata: {
              date: new Date().toISOString().split("T")[0],
              channel: "app",
              model: modelLabel,
              is_pro: isProUser,
            },
          });
        } catch (e) {
          console.error("[ai-proxy] Embed store error:", e);
        }
      })();
    }

    return new Response(
      JSON.stringify({
        reply: cleanReply,
        model_used: modelLabel,
        tokens_used: loop.tokensUsed,
        actions: extracted.actions, // legacy <ICBF_LOG> back-compat
        tool_intents: loop.intents, // NEW — typed write intents
        tool_calls_log: loop.toolCallsLog, // NEW — per-call telemetry
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err_) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[ai-proxy] request_id=${requestId}`, err_);
    return err(500, "Internal server error", { request_id: requestId });
  }
});
