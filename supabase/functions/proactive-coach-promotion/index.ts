// proactive-coach-promotion / Theme C (closes-diagnose 8b1f33).
//
// Fired by Postgres trigger trg_dispatch_proactive_coach_promotion on
// every rank_promotions INSERT (migration 073). Composes an AI
// congratulation message via Gemini, writes it to ai_coach_interactions
// (the canonical chat table — offline-first: the in-app chat UI reads
// Hive, this cloud row is the upward-sync target that surfaces once the
// coach domain syncs down to the device), and sends an OneSignal push so
// the user gets the notification even when the app isn't open.
//
// 2026-05-29 audit EF-1 fix (closes-diagnose 9e1d4c): the prior version
// inserted into a nonexistent table `coach_interactions` with columns
// (role/content/metadata) that do not exist on ai_coach_interactions, so
// every promotion returned HTTP 500 BEFORE the OneSignal push — the whole
// celebration was inert. Telemetry also targeted nonexistent client_errors
// columns (message/severity) so the failure was invisible.
//
// verify_jwt=false — invoked by the Postgres trigger using the
// service_role_key from Vault. The trigger payload is internal-only.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.42.0";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier } from "../_shared/sanitize_for_prompt.ts";

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
// Codes + labels MUST match lib/core/services/rank_ladder_data.dart
// (kRankLadder) EXACTLY. The prior map used codes (PO2/PO1/ENS/LTJG/
// LCDR/CDR/CAPT) that exist in no ladder — 7 of 11 ranks fell through to
// the raw code in the AI prompt. Canonical ladder: SD2, SD1, LS, PO, CPO,
// MCPO, SubLt, Lt, LtCdr, Cdr, Capt.
const RANK_LABELS: Record<string, string> = {
  SD2: "Seaman 2nd Class",
  SD1: "Seaman 1st Class",
  LS: "Leading Seaman",
  PO: "Petty Officer",
  CPO: "Chief Petty Officer",
  MCPO: "Master Chief Petty Officer",
  SubLt: "Sub Lieutenant",
  Lt: "Lieutenant",
  LtCdr: "Lieutenant Commander",
  Cdr: "Commander",
  Capt: "Captain",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // ── F44 (2026-06-07 audit) — cron/service auth gate.
  //
  // verify_jwt=false (the Postgres trigger trg_dispatch_proactive_coach_promotion
  // dispatches via pg_net, not an end-user JWT). Without a manual gate an
  // unauthenticated POST could drive Gemini cost + OneSignal push +
  // ai_coach_interactions writes to ANY user_id. The trigger sends
  // `Authorization: Bearer <service_role_jwt>` (migration 078, resolved from
  // Vault via private.morning_alert_get_service_key()), so the SAME shared
  // `isAuthorizedCronCall(req)` gate the sibling cron functions use
  // (pr-detection, streak-guardian, i-see-you-callout, re-engagement,
  // evaluate-rank-promotions, …) authenticates the existing dispatch while
  // rejecting anonymous callers. Verifies the JWT signature against
  // SUPABASE_JWT_SECRET + role-claim === 'service_role'; CRON_SECRET opaque
  // token is the escape hatch inside the helper. Reject BEFORE any
  // Gemini/push/DB work.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[proactive-coach-promotion] unauthorized caller; status=401`);
    return jsonResponse({ error: "Unauthorized" }, 401);
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

    // 3. Write to ai_coach_interactions (canonical chat table). The
    //    proactive message is an assistant turn with no user prompt, so
    //    user_message is empty (column is NOT NULL — empty string, not
    //    null) and the congrats goes in ai_response. The proactive tag +
    //    rank_code live in the tool_calls jsonb column for downstream
    //    filtering (ai_coach_interactions has no role/metadata columns).
    const insertRes = await admin.from("ai_coach_interactions").insert({
      user_id,
      channel: "in_app",
      user_message: "",
      ai_response: congrats,
      model_used: "gemini-2.5-flash",
      tool_calls: {
        kind: "proactive_promotion",
        rank_code,
        source: "proactive-coach-promotion",
      },
    });
    if (insertRes.error) {
      await logTelemetry(admin, user_id, "proactive_coach_promotion_failed",
        `insert ai_coach_interactions: ${insertRes.error.message}`);
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
  admin: SupabaseClient,
  user_id: string,
): Promise<UserContext> {
  // Schema split: `full_name` lives on the `users` table (migration 001
  // / line 28 — `users.full_name text`). `primary_goal` lives on
  // `user_profile`. Querying `user_profile.full_name` returns
  // PostgrestError 42703 (column not found) — caught by Gate 18's
  // `check_reader_manifest_complete.dart` forbidden-pattern
  // `from.*user_profile.*select.*full_name`. Must hit both tables.
  const [userRes, profileRes, progressRes] = await Promise.all([
    admin.from("users").select("full_name")
      .eq("id", user_id).maybeSingle(),
    admin.from("user_profile").select("primary_goal")
      .eq("user_id", user_id).maybeSingle(),
    admin.from("user_progress")
      .select("current_streak_weeks, total_workouts_done")
      .eq("user_id", user_id).maybeSingle(),
  ]);
  // Unit C (§2.24) — surface a query failure instead of coercing to a null/0
  // context (which sends a de-personalized "Congratulations, soldier" push). This
  // runs first in the per-invocation flow, so a throw here happens BEFORE the
  // Gemini compose + the ai_coach_interactions insert + the OneSignal push.
  const ctxErr = userRes.error ?? profileRes.error ?? progressRes.error;
  if (ctxErr) throw ctxErr;
  return {
    full_name: userRes.data?.full_name ?? null,
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
  // OI-47: `full_name` is user-editable and this is the sharpest placement of
  // it anywhere in the tree -- `firstName` is interpolated into the SYSTEM
  // INSTRUCTION at :204, not into a user turn. Splitting on whitespace already
  // drops spaces and \n, but NOT \r, U+2028/U+2029/U+0085 or control
  // characters, all of which survive `.split(/\s+/)` in a Deno regex without
  // the `u` flag and would land inside the quoted `"..."` in the system prompt.
  //
  // This function was ALSO missed by the first survey pass: it calls the Gemini
  // REST endpoint via `fetch` directly instead of `geminiChat`, so a grep keyed
  // on the helper did not see it. Widening the search to `systemPrompt|prompt:`
  // is what surfaced it.
  const firstName = sanitizeIdentifier(
    ctx.full_name?.split(/\s+/)[0],
    { fallback: "soldier", maxLen: 32 },
  );
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
  admin: SupabaseClient,
  user_id: string, op_type: string, message: string,
): Promise<void> {
  try {
    // client_errors columns are: error_code, error_message, op_type
    // (verified live 2026-05-29). There is NO `message`/`severity`
    // column — the prior insert silently failed, hiding EF-1.
    await admin.from("client_errors").insert({
      user_id,
      op_type,
      error_code: op_type,
      error_message: message,
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
