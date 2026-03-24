import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FREE_DAILY_LIMIT = 15;
const FREE_TRIAL_DAYS = 30;
const TIMEOUT_MS = 3000;

interface FallbackModel {
  id: string;
  label: string;
}

const FALLBACK_CHAIN: FallbackModel[] = [
  { id: "cerebras/llama-3.1-8b", label: "Cerebras Llama 3.1 8B" },
  { id: "groq/llama-4", label: "Groq Llama 4" },
  { id: "google/gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite" },
];

async function callOpenRouter(
  model: string,
  systemPrompt: string,
  userMessage: string,
  timeoutMs: number,
): Promise<{ reply: string; tokens_used: number } | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://icanbefitter.app",
        "X-Title": "ICANBEFITTER",
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        max_tokens: 1024,
      }),
      signal: controller.signal,
    });

    if (!response.ok) return null;

    const data = await response.json();
    const choice = data.choices?.[0];
    if (!choice?.message?.content) return null;

    return {
      reply: choice.message.content,
      tokens_used: data.usage?.total_tokens ?? 0,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
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

    // Check 30-day free trial
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
      // First AI chat — set start date
      const now = new Date().toISOString();
      await supabaseClient
        .from("users")
        .update({ ai_chat_started_at: now })
        .eq("id", userId);
      aiChatStartedAt = now;
    }

    const trialStart = new Date(aiChatStartedAt);
    const now = new Date();
    const daysSinceStart = Math.floor(
      (now.getTime() - trialStart.getTime()) / (1000 * 60 * 60 * 24),
    );

    if (daysSinceStart > FREE_TRIAL_DAYS) {
      return new Response(
        JSON.stringify({
          error: "Free AI trial expired",
          code: "TRIAL_EXPIRED",
          days_used: daysSinceStart,
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check daily message limit (15 msg/day)
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
        JSON.stringify({
          error: "Daily message limit reached",
          code: "RATE_LIMITED",
          limit: FREE_DAILY_LIMIT,
          messages_used: msgCount,
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
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

    // Build system prompt with daily snapshot context
    let systemPrompt =
      "You are ICANBEFITTER AI Coach, a friendly and knowledgeable fitness and nutrition coach " +
      "for young professionals in India. Keep responses concise, actionable, and motivating. " +
      "Use metric units (kg, cm). Reference Indian foods and context when relevant.";

    if (snapshot_json) {
      systemPrompt +=
        "\n\nHere is the user's current daily snapshot for context:\n" +
        JSON.stringify(snapshot_json);
    }

    // 3-tier fallback
    let result: { reply: string; tokens_used: number } | null = null;
    let modelUsed = "";

    for (const model of FALLBACK_CHAIN) {
      result = await callOpenRouter(model.id, systemPrompt, message, TIMEOUT_MS);
      if (result) {
        modelUsed = model.label;
        break;
      }
    }

    if (!result) {
      return new Response(
        JSON.stringify({ error: "All AI providers failed. Please try again later." }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch latest snapshot_id for logging
    const { data: snapshotData } = await supabaseClient
      .from("user_daily_snapshots")
      .select("id")
      .eq("user_id", userId)
      .order("snapshot_date", { ascending: false })
      .limit(1)
      .single();

    // Log interaction
    await supabaseClient.from("ai_coach_interactions").insert({
      user_id: userId,
      snapshot_id: snapshotData?.id ?? null,
      channel: "app",
      user_message: message,
      ai_response: result.reply,
      model_used: modelUsed,
      tokens_used: result.tokens_used,
      created_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({
        reply: result.reply,
        model_used: modelUsed,
        tokens_used: result.tokens_used,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
