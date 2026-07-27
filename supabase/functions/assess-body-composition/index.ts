import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { geminiChat, MODEL_FLASH_LITE } from "../_shared/gemini.ts";
import { sanitizeIdentifier } from "../_shared/sanitize_for_prompt.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 2026-04-18 · Migrated off OpenRouter Gemma cascade → Flash-Lite only
// via the shared gemini.ts helper.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Renders a request-body measurement for the prompt.
 *
 * `Number(x) || "unknown"` conflates "invalid" with "legitimately zero" — a
 * posted `0` became "unknown" rather than "0". It also silently accepted
 * `Number(null) === 0`. Absent/blank/non-numeric is reported as unknown;
 * everything finite is reported verbatim, including 0, so the prompt never
 * states a measurement the caller did not send. (Round-1 review P2.)
 */
function _num(v: unknown): string {
  if (v === null || v === undefined || v === "") return "unknown";
  const n = Number(v);
  return Number.isFinite(n) ? String(n) : "unknown";
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    // ── Auth ─────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing authorization" }, 401);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) return json({ error: "Unauthorized" }, 401);

    const userId = user.id;

    // ── PRO check ────────────────────────────────────────────────
    const { data: sub } = await supabase
      .from("subscriptions")
      .select("status, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("end_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    const isPro = sub != null && new Date(sub.end_date) > new Date();
    if (!isPro) {
      return json({ error: "PRO required", code: "pro_required" }, 403);
    }

    // ── 30-day rate limit ────────────────────────────────────────
    // We piggyback on user_preferences.coaching_notes (already a JSON blob)
    // to avoid adding a migration just for this timestamp.
    const { data: prefRow } = await supabase
      .from("user_preferences")
      .select("coaching_notes")
      .eq("user_id", userId)
      .maybeSingle();

    let coachingNotes: Record<string, unknown> = {};
    if (prefRow?.coaching_notes) {
      try {
        coachingNotes = JSON.parse(prefRow.coaching_notes as string);
      } catch { /* ignore parse error, start fresh */ }
    }

    const lastAssessed = coachingNotes["last_bf_assessed_at"] as string | undefined;
    if (lastAssessed) {
      const daysSince =
        (Date.now() - new Date(lastAssessed).getTime()) / 86_400_000;
      if (daysSince < 30) {
        const nextAllowed = new Date(
          new Date(lastAssessed).getTime() + 30 * 86_400_000,
        ).toISOString();
        return json(
          {
            error: "Body composition can only be assessed once every 30 days.",
            code: "rate_limited",
            next_allowed_at: nextAllowed,
          },
          429,
        );
      }
    }

    // ── Parse request ────────────────────────────────────────────
    const body = await req.json();
    const {
      image_base64,
      mime_type = "image/jpeg",
      weight_kg,
      height_cm,
      gender = "male",
      age = 25,
    } = body;

    if (!image_base64 || typeof image_base64 !== "string") {
      return json({ error: "Missing image_base64" }, 400);
    }

    // ── Gemini Vision call ───────────────────────────────────────
    const prompt =
      `You are a clinical body composition assessment tool. Estimate the body fat percentage from this photo.

User stats: ${
        // OI-47: these four come straight off the REQUEST BODY, so the UI's
        // enum/number widgets are not the constraint -- an authenticated caller
        // POSTs whatever JSON it likes. `gender` is the free-text one; the
        // three numerics are coerced with Number() so a string payload cannot
        // smuggle prose through a field the prompt presents as a measurement.
        sanitizeIdentifier(gender as string | null, { fallback: "unspecified" })
      }, ${_num(age)} years old, ${_num(height_cm)} cm tall, ${_num(weight_kg)} kg.

Rules:
- Be objective and clinical. Only assess visible body composition markers (muscle definition, fat distribution).
- Provide a realistic percentage range (e.g. 18-22%), not a single number.
- confidence: "low" if the image is unclear/clothed/unsuitable, "medium" for standard cases, "high" if markers are very clear.
- If the photo is not a body photo (face only, blurry, fully clothed, object), set "suitable": false.
- Do not comment on aesthetics, attractiveness, or make any value judgements.
- Do not make assumptions beyond what's visible.

Return ONLY valid JSON — no markdown, no code fences:
{"bf_low": 18, "bf_high": 22, "confidence": "medium", "suitable": true, "note": "One brief clinical observation"}`;

    const { content: rawText } = await geminiChat({
      model: MODEL_FLASH_LITE,
      systemPrompt: "You are a clinical body composition assessment tool. Return ONLY valid JSON.",
      userPrompt: prompt,
      imageBase64: image_base64,
      imageMimeType: mime_type,
      maxTokens: 256,
      temperature: 0.1,
      timeoutMs: 20_000,
      jsonMode: true,
      fallbackToLite: false, // already on Flash-Lite
    });

    if (!rawText) {
      return json({ error: "AI assessment failed" }, 502);
    }

    let result: Record<string, unknown>;
    try {
      const cleaned = rawText
        .replace(/```json\n?/g, "")
        .replace(/```\n?/g, "")
        .trim();
      result = JSON.parse(cleaned);
    } catch {
      console.error("Failed to parse AI response:", rawText);
      return json({ error: "Could not parse AI response" }, 502);
    }

    // ── Validation ───────────────────────────────────────────────
    if (result["suitable"] === false) {
      return json(
        {
          error:
            "Photo not suitable for assessment. Please use a clear full-body or torso photo in fitted clothing.",
          code: "unsuitable_image",
        },
        422,
      );
    }

    const bfLow = Number(result["bf_low"]);
    const bfHigh = Number(result["bf_high"]);
    if (isNaN(bfLow) || isNaN(bfHigh) || bfLow < 3 || bfHigh > 60) {
      console.error("Unrealistic BF% values from Gemini:", result);
      return json({ error: "AI returned unrealistic values. Please try again." }, 502);
    }

    const assessedAt = new Date().toISOString();

    // ── Persist rate-limit timestamp ─────────────────────────────
    coachingNotes["last_bf_assessed_at"] = assessedAt;
    await supabase.from("user_preferences").upsert(
      { user_id: userId, coaching_notes: JSON.stringify(coachingNotes) },
      { onConflict: "user_id" },
    );

    return json({
      bf_low: bfLow,
      bf_high: bfHigh,
      confidence: result["confidence"] ?? "medium",
      note: result["note"] ?? null,
      assessed_at: assessedAt,
    });
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[assess-body-composition] request_id=${requestId}`, err);
    return json(
      { error: "Internal server error", request_id: requestId },
      500,
    );
  }
});
