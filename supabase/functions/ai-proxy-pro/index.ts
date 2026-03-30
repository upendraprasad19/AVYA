import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { getEmbedding } from "../_shared/embeddings.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// PRO: rotate across all 3 keys for higher throughput.
const CEREBRAS_KEYS = [
  Deno.env.get("CEREBRAS_API_KEY_1")!,
  Deno.env.get("CEREBRAS_API_KEY_2")!,
  Deno.env.get("CEREBRAS_API_KEY_3")!,
];

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Best available Cerebras model for PRO users.
const PRO_MODEL = "llama-3.3-70b";
const PRO_MODEL_LABEL = "Cerebras Llama 3.3 70B";
const CEREBRAS_URL = "https://api.cerebras.ai/v1/chat/completions";

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
    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;

    // Verify PRO subscription
    const { data: subscription, error: subError } = await supabaseClient
      .from("subscriptions")
      .select("status, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .gt("end_date", new Date().toISOString())
      .order("end_date", { ascending: false })
      .limit(1)
      .single();

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({ error: "PRO subscription required", code: "NOT_PRO" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Parse request body
    const body = await req.json();
    const { message, snapshot_json } = body;

    if (!message || typeof message !== "string") {
      return new Response(JSON.stringify({ error: "Missing 'message' in request body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Phase B: Retrieve relevant long-term memories (PRO only) ──────────
    // Embed the user query → cosine similarity search → inject top 5 memories.
    // Wrapped in try/catch: retrieval failure must never break the chat response.
    let memoryBlock = "";
    try {
      const queryEmbedding = await getEmbedding(message, "RETRIEVAL_QUERY");
      if (queryEmbedding) {
        const { data: memories, error: memError } = await supabaseClient.rpc(
          "match_memories",
          {
            p_user_id: userId,
            p_query_embedding: queryEmbedding,
            p_match_count: 5,
            p_similarity_threshold: 0.65,
          },
        );

        if (!memError && memories && memories.length > 0) {
          const lines = (memories as Array<{
            content: string;
            source_type: string;
            created_at: string;
          }>).map((m) => {
            const date = new Date(m.created_at).toISOString().split("T")[0];
            return `[${date}] (${m.source_type}) ${m.content}`;
          });

          memoryBlock =
            "\n\n--- Long-term memory (retrieved from past conversations) ---\n" +
            lines.join("\n") +
            "\n--- End of memory context ---";

          console.log(
            `[ai-proxy-pro] Memory retrieved: ${memories.length} items, ${memoryBlock.length} chars`,
          );
        }
      }
    } catch (memErr) {
      console.error("[ai-proxy-pro] Memory retrieval error:", memErr);
    }

    // Build system prompt
    let systemPrompt =
      "You are ICANBEFITTER PRO AI Coach — like a father who knows everything about this person. " +
      "You are an elite fitness and nutrition coach for young professionals in India. " +
      "Provide deep, personalised coaching with detailed analysis. Be thorough, insightful, " +
      "caring but direct. Use metric units (kg, cm). Reference Indian foods and cultural context. " +
      "If coach_notices are present in the snapshot, weave them naturally into conversation " +
      "(reference specific numbers, celebrate wins, call out problems directly, never list robotically)." +
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

    // Inject retrieved memories after snapshot — historical context sits after
    // current state so the model weighs recency correctly.
    if (memoryBlock) {
      systemPrompt += memoryBlock;
    }

    // Try all 3 keys — rotate on rate limit for higher PRO throughput.
    let reply = "";
    let tokensUsed = 0;
    let success = false;

    for (const key of CEREBRAS_KEYS) {
      if (!key) continue;

      try {
        const response = await fetch(CEREBRAS_URL, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${key}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: PRO_MODEL,
            messages: [
              { role: "system", content: systemPrompt },
              { role: "user", content: message },
            ],
            max_tokens: 2048,
            temperature: 0.7,
          }),
        });

        if (!response.ok) continue;

        const data = await response.json();
        const content = data.choices?.[0]?.message?.content;
        if (!content) continue;

        reply = content;
        tokensUsed = data.usage?.total_tokens ?? 0;
        success = true;
        break;
      } catch {
        continue;
      }
    }

    if (!success) {
      return new Response(
        JSON.stringify({ error: "AI temporarily unavailable. Please try again." }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Extract structured log actions from AI reply
    const extracted = extractLogActions(reply);

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
      model_used: PRO_MODEL_LABEL,
      tokens_used: tokensUsed,
      created_at: new Date().toISOString(),
    });

    // ── Phase A: Store this conversation turn as an embedding (PRO) ────────
    // Fire-and-forget — Response is already built; this runs after return.
    // PRO users get BOTH store (Phase A) and retrieval (Phase B).
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
            model: PRO_MODEL_LABEL,
          },
        });
      } catch (e) {
        console.error("[ai-proxy-pro] Embed store error:", e);
      }
    })();

    return new Response(
      JSON.stringify({
        reply: extracted.reply,
        model_used: PRO_MODEL_LABEL,
        tokens_used: tokensUsed,
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
