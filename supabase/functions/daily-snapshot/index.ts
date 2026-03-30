import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

// ── Coaching Notes Extraction ────────────────────────────────────────────────
//
// Scans today's AI conversations and extracts structured facts the user
// revealed. Merges with existing coaching_notes in user_preferences.
// Uses Gemini Flash (cheap, fast for simple extraction tasks).

interface ExtractedFacts {
  diet_preference?: string;
  injuries?: string[];
  lifestyle_notes?: string;
  food_preferences?: string;
  schedule_constraints?: string;
  supplement_use?: string;
  motivation_notes?: string;
  lifestyle_activity?: string; // desk_job | lightly_active | very_active_job
}

async function extractCoachingNotes(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  todayIST: string,
): Promise<ExtractedFacts | null> {
  // Fetch today's conversations
  const { data: convos } = await supabase
    .from("ai_coach_interactions")
    .select("user_message, ai_response")
    .eq("user_id", userId)
    .gte("created_at", `${todayIST}T00:00:00+05:30`)
    .lte("created_at", `${todayIST}T23:59:59+05:30`)
    .order("created_at", { ascending: true })
    .limit(30); // cap to avoid huge prompts

  if (!convos || convos.length === 0) return null;

  // Build conversation text
  const convoText = convos
    .map(
      (c: { user_message: string; ai_response: string }) =>
        `User: ${c.user_message}\nCoach: ${c.ai_response}`,
    )
    .join("\n\n");

  const prompt =
    `You are extracting factual profile data from a fitness coaching conversation.

Review the conversation below and extract ONLY facts the user explicitly stated about themselves.
Do not infer or assume. Only include a field if the user clearly said it.

Conversation:
${convoText}

Return ONLY valid JSON (no markdown, no code fences). Include only fields that were explicitly mentioned:
{
  "diet_preference": "vegetarian|vegan|non_veg|keto|pescatarian",
  "injuries": ["knee","back","shoulder","hip","wrist","ankle"],
  "lifestyle_activity": "desk_job|lightly_active|very_active_job",
  "lifestyle_notes": "brief note on lifestyle context they mentioned",
  "food_preferences": "foods they like, dislike, or are allergic to",
  "schedule_constraints": "schedule constraints they mentioned (e.g. travels on Fridays)",
  "supplement_use": "supplements they mentioned taking",
  "motivation_notes": "motivation patterns, obstacles, or triggers they mentioned"
}

If nothing was found, return: {}`;

  const geminiRes = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.1, maxOutputTokens: 512 },
    }),
  });

  if (!geminiRes.ok) {
    console.error("Gemini extraction error:", await geminiRes.text());
    return null;
  }

  const geminiData = await geminiRes.json();
  const rawText: string =
    geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";

  try {
    const cleaned = rawText
      .replace(/```json\n?/g, "")
      .replace(/```\n?/g, "")
      .trim();
    const extracted = JSON.parse(cleaned) as ExtractedFacts;
    // Return null if empty object
    if (Object.keys(extracted).length === 0) return null;
    return extracted;
  } catch {
    console.error("Failed to parse extraction response:", rawText);
    return null;
  }
}

async function mergeCoachingNotes(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  extracted: ExtractedFacts,
): Promise<void> {
  // Load existing coaching_notes
  const { data: prefRow } = await supabase
    .from("user_preferences")
    .select("coaching_notes")
    .eq("user_id", userId)
    .maybeSingle();

  let existing: Record<string, unknown> = {};
  if (prefRow?.coaching_notes) {
    try {
      existing = JSON.parse(prefRow.coaching_notes as string);
    } catch { /* start fresh */ }
  }

  // Merge: extracted values overwrite existing only if non-empty
  const merged = { ...existing };
  for (const [key, value] of Object.entries(extracted)) {
    if (value !== undefined && value !== null && value !== "") {
      merged[key] = value;
    }
  }
  merged["last_extracted_at"] = new Date().toISOString();

  await supabase.from("user_preferences").upsert(
    { user_id: userId, coaching_notes: JSON.stringify(merged) },
    { onConflict: "user_id" },
  );

  // Also update lifestyle_activity and diet_preference directly on user_profile
  // if extracted, so recalculateTargets() picks them up immediately.
  const profileUpdates: Record<string, unknown> = {};
  if (extracted.diet_preference) profileUpdates["diet_preference"] = extracted.diet_preference;
  if (extracted.lifestyle_activity) profileUpdates["lifestyle_activity"] = extracted.lifestyle_activity;
  if (extracted.injuries) profileUpdates["injuries"] = extracted.injuries;

  if (Object.keys(profileUpdates).length > 0) {
    await supabase
      .from("user_profile")
      .upsert({ user_id: userId, ...profileUpdates }, { onConflict: "user_id" });
  }
}

/**
 * Returns today's date string in IST (UTC+5:30) as YYYY-MM-DD.
 */
function getTodayIST(): string {
  const now = new Date();
  // UTC+5:30 = 330 minutes offset
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  return istDate.toISOString().split("T")[0];
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

    // Parse request body
    const body = await req.json();
    const { snapshot_json } = body;

    if (!snapshot_json || typeof snapshot_json !== "object") {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'snapshot_json' in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const snapshotDate = getTodayIST();

    // UPSERT: user_id + snapshot_date is unique
    const { error: upsertError } = await supabaseClient
      .from("user_daily_snapshots")
      .upsert(
        {
          user_id: userId,
          snapshot_date: snapshotDate,
          snapshot_json,
          created_at: new Date().toISOString(),
        },
        {
          onConflict: "user_id,snapshot_date",
        },
      );

    if (upsertError) {
      console.error("Failed to upsert snapshot:", upsertError);
      return new Response(
        JSON.stringify({ error: "Failed to save daily snapshot" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Coaching notes extraction (fire-and-forget, non-blocking) ──
    // Run after responding to the client so latency is unaffected.
    // EdgeRuntime.waitUntil keeps the process alive until completion.
    let extractedFacts: ExtractedFacts | null = null;
    try {
      if (GEMINI_API_KEY) {
        extractedFacts = await extractCoachingNotes(
          supabaseClient,
          userId,
          snapshotDate,
        );
        if (extractedFacts) {
          await mergeCoachingNotes(supabaseClient, userId, extractedFacts);
        }
      }
    } catch (extractErr) {
      // Never let extraction failure affect the snapshot response.
      console.error("Coaching extraction error (non-fatal):", extractErr);
    }

    return new Response(
      JSON.stringify({
        status: "success",
        snapshot_date: snapshotDate,
        coaching_extracted: extractedFacts !== null,
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
