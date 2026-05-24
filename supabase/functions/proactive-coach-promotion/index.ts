// proactive-coach-promotion / Theme C (closes-diagnose 8b1f33).
//
// Fired by Postgres trigger trg_dispatch_proactive_coach_promotion on
// every rank_promotions INSERT (migration 073). Composes an AI
// congratulation message via Gemini, writes it to coach_interactions
// (so it surfaces in the AI Coach screen alongside the user's own
// chat history), and sends an OneSignal push so the user gets the
// notification even when the app isn't open.
//
// verify_jwt=false — invoked by the Postgres trigger using the
// service_role_key from Vault. The trigger payload is internal-only.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.42.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID")!;
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

interface TriggerPayload {
  user_id: string;
  rank_code: string;
  achieved_at: string;
  trigger_source: string;
}

interface UserContext {
  full_name: string | null;
  primary_goal: string | null;
  current_streak_weeks: number;
  total_workouts_done: number;
}

// Rank ladder labels mirror lib/core/services/rank_ladder_data.dart.
// Hardcoded here so the Edge Function doesn't reach back into the
// client codebase. If the ladder ever changes, this map updates in
// the same commit as the client one.
const RANK_LABELS: Record<string, string> = {
  SD2: "Seaman Apprentice",
  SD1: "Seaman",
  PO2: "Petty Officer 2nd Class",
  PO1: "Petty Officer 1st Class",
  CPO: "Chief Petty Officer",
  ENS: "Ensign",
  LTJG: "Lieutenant Junior Grade",
  LT: "Lieutenant",
  LCDR: "Lieutenant Commander",
  CDR: "Commander",
  CAPT: "Captain",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let payload: TriggerPayload;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse({ error: "invalid json" }, 400);
  }

  const { user_id, rank_code } = payload;
  if (!user_id || !rank_code) {
    return jsonResponse({ error: "user_id + rank_code required" }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  try {
    // 1. Pull user context (profile + progress snapshot).
    const userCtx = await loadUserContext(admin, user_id);

    // 2. Compose AI congrats via Gemini.
    const congrats = await composeCongrats(userCtx, rank_code);

    // 3. Write to coach_interactions so it surfaces in chat.
    const insertRes = await admin.from("coach_interactions").insert({
      user_id,
      role: "assistant",
      channel: "in_app",
      content: congrats,
      metadata: {
        kind: "proactive_promotion",
        rank_code,
        source: "proactive-coach-promotion",
      },
    });
    if (insertRes.error) {
      await logTelemetry(admin, user_id, "proactive_coach_promotion_failed",
        `insert coach_interactions: ${insertRes.error.message}`);
      return jsonResponse({ error: "coach insert failed" }, 500);
    }

    // 4. OneSignal push so the user gets a notification even when
    //    the app is closed.
    await sendOneSignalPush(user_id, rank_code, congrats);

    // 5. Success telemetry.
    await logTelemetry(admin, user_id,
      "proactive_coach_promotion_dispatched",
      `rank_code=${rank_code} congrats_len=${congrats.length}`);

    return jsonResponse({ ok: true });
  } catch (e) {
    const msg = String(e).slice(0, 500);
    await logTelemetry(admin, user_id,
      "proactive_coach_promotion_failed", msg);
    return jsonResponse({ error: msg }, 500);
  }
});

async function loadUserContext(
  admin: ReturnType<typeof createClient>,
  user_id: string,
): Promise<UserContext> {
  const [profileRes, progressRes] = await Promise.all([
    admin.from("user_profile").select("full_name, primary_goal")
      .eq("user_id", user_id).maybeSingle(),
    admin.from("user_progress")
      .select("current_streak_weeks, total_workouts_done")
      .eq("user_id", user_id).maybeSingle(),
  ]);
  return {
    full_name: profileRes.data?.full_name ?? null,
    primary_goal: profileRes.data?.primary_goal ?? null,
    current_streak_weeks: progressRes.data?.current_streak_weeks ?? 0,
    total_workouts_done: progressRes.data?.total_workouts_done ?? 0,
  };
}

async function composeCongrats(
  ctx: UserContext,
  rankCode: string,
): Promise<string> {
  const rankLabel = RANK_LABELS[rankCode] ?? rankCode;
  const firstName = (ctx.full_name?.split(/\s+/)[0]) ?? "soldier";
  const goalCopy = goalToCopy(ctx.primary_goal);

  const systemPrompt = `You are AVYA, an AI fitness coach for the
Indian Navy-themed fitness app ICANBEFITTER. The user just promoted
to rank ${rankLabel} (code: ${rankCode}). Write a warm but
disciplined congratulation in 80-120 words.

Hard rules:
- Address them by name: "${firstName}".
- Name the specific milestone: ${ctx.total_workouts_done} workouts
  done, ${ctx.current_streak_weeks}-week streak.
- Tie motivation to their primary goal: ${goalCopy}.
- Preview what unlocks at the next rank (don't be too specific —
  the ladder is documented elsewhere).
- Military lexicon allowed sparingly (e.g. "mission", "soldier", "rank").
- NO emojis. NO bullet points. Single flowing paragraph.
- End with a forward-looking line, not a closing salutation.`;

  // Call Gemini 2.5 Flash via the public REST API. The "messages"
  // shape is mapped to Gemini's "contents" + "systemInstruction".
  const url = `https://generativelanguage.googleapis.com/v1beta/models/`
    + `gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{
        role: "user",
        parts: [{ text:
          `Write the congrats for ${firstName} ranking up to ${rankLabel}.`
        }],
      }],
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 256,
      },
    }),
  });
  if (!res.ok) {
    throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    throw new Error("Gemini returned empty content");
  }
  return String(text).trim();
}

function goalToCopy(primaryGoal: string | null): string {
  switch (primaryGoal) {
    case "lose_fat":      return "fat loss";
    case "build_muscle":  return "muscle gain";
    case "gain_strength": return "strength";
    case "general_fitness":
    default:              return "general fitness";
  }
}

async function sendOneSignalPush(
  user_id: string, rank_code: string, congrats: string,
): Promise<void> {
  // OneSignal `external_user_id` is the Supabase user_id by convention
  // (set by client on first sign-in).
  const preview = congrats.length > 80
    ? congrats.slice(0, 77) + "..."
    : congrats;
  const res = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_external_user_ids: [user_id],
      headings: { en: "🎖️ Promotion Day" },
      contents: { en: preview },
      data: { deep_link: "/ai-coach", kind: "proactive_promotion",
              rank_code },
    }),
  });
  if (!res.ok) {
    throw new Error(`OneSignal ${res.status}: ${await res.text()}`);
  }
}

async function logTelemetry(
  admin: ReturnType<typeof createClient>,
  user_id: string, op_type: string, message: string,
): Promise<void> {
  try {
    await admin.from("client_errors").insert({
      user_id, op_type, message,
      severity: op_type.endsWith("_failed") ? "error" : "info",
    });
  } catch (_) {
    // Best-effort — never throw from telemetry.
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
