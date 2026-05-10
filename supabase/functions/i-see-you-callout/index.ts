// supabase/functions/i-see-you-callout/index.ts
//
// Daily 19:30 IST scan for "the Captain noticed something" moments.
// Writes ai_coach_interactions row with channel='proactive_i_see_you'.
// Dedup'd via _shared/proactive_dedup.ts (1/user/day/type).
//
// Phase 1 heuristics (4 of 5):
//   - Recovery after slip  (first workout back after 3+ day gap)
//   - PR after bad sleep   (PR set when previous night's sleep < 6h)
//   - Pre-dawn workout     (logged_at IST hour < 6)
//   - First in-streak Saturday (Saturday + 14+ workouts in last 28 days)
//
// Festival/wedding heuristic deferred to Test #5 (festival calendar not wired).
//
// Source: APK Test #4 Plan C / C3.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { shouldSendProactive, markProactiveSent } from "../_shared/proactive_dedup.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface Moment {
  type: string;  // dedup key suffix e.g. 'pre_dawn', 'pr_after_bad_sleep'
  text: string;  // callout message body
}

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── C-4 cron-auth gate ───────────────────────────────────────────────
  // Audit 2026-05-11 / closes-diagnose 7ad0c4. These cron functions had
  // `verify_jwt: false` and no manual auth. Now require Bearer == either
  // SUPABASE_SERVICE_ROLE_KEY (existing pg_cron path) OR CRON_SECRET
  // (rotatable hardening). If CRON_SECRET env var is unset, only the
  // service-role-key path works — graceful rollout.
  {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length)
      : "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const cronSecret = Deno.env.get("CRON_SECRET");
    const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
    const isCronSecret = !!cronSecret && token === cronSecret;
    if (!isServiceRole && !isCronSecret) {
      console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    // Pull all users — could optimize to active-only later
    const { data: users, error: userErr } = await supabase
      .from("users")
      .select("id");

    if (userErr) throw userErr;
    if (!users || users.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, processed: 0, sent: 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let sent = 0;
    let processed = 0;

    for (const u of users) {
      processed++;
      try {
        const moment = await detectMoment(supabase, u.id);
        if (!moment) continue;

        // Cast to any — proactive_dedup has a closed union; our custom types extend it.
        // deno-lint-ignore no-explicit-any
        const allowed = await shouldSendProactive(supabase, u.id, `i_see_you_${moment.type}` as any);
        if (!allowed) continue;

        const { error: insertErr } = await supabase.from("ai_coach_interactions").insert({
          user_id: u.id,
          channel: "proactive_i_see_you",
          user_message: "",
          ai_response: moment.text,
          model_used: "i_see_you_template",
          created_at: new Date().toISOString(),
        });

        if (insertErr) {
          console.error(`[i-see-you] insert failed for ${u.id}: ${insertErr.message}`);
          continue;
        }

        // deno-lint-ignore no-explicit-any
        await markProactiveSent(supabase, u.id, `i_see_you_${moment.type}` as any);
        sent++;
      } catch (perUserErr) {
        console.warn(`[i-see-you] per-user error for ${u.id}:`, perUserErr);
      }
    }

    return new Response(
      JSON.stringify({ ok: true, processed, sent }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[i-see-you-callout] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

// ── Moment detector ────────────────────────────────────────────────────────────

async function detectMoment(supabase: SupabaseClient, userId: string): Promise<Moment | null> {
  // Check moments in priority order — return first match.

  // 1. Recovery after slip (most impactful — first workout back after 3+ day gap)
  const recovery = await checkRecoveryAfterSlip(supabase, userId);
  if (recovery) return recovery;

  // 2. PR after bad sleep
  const prBadSleep = await checkPRAfterBadSleep(supabase, userId);
  if (prBadSleep) return prBadSleep;

  // 3. Pre-dawn workout
  const preDawn = await checkPreDawnWorkout(supabase, userId);
  if (preDawn) return preDawn;

  // 4. First in-streak Saturday
  const streakSat = await checkFirstInStreakSaturday(supabase, userId);
  if (streakSat) return streakSat;

  // 5. Festival/wedding nutrition hold — DEFERRED (festival calendar not wired in Phase 1)

  return null;
}

// ── Individual heuristics ──────────────────────────────────────────────────────

async function checkRecoveryAfterSlip(
  supabase: SupabaseClient,
  userId: string,
): Promise<Moment | null> {
  // Get last 2 distinct workout dates ordered by logged_at desc
  const { data: recent } = await supabase
    .from("workout_logs")
    .select("logged_at")
    .eq("user_id", userId)
    .order("logged_at", { ascending: false })
    .limit(5);

  if (!recent || recent.length < 2) return null;

  const last = new Date(recent[0].logged_at);
  const prev = new Date(recent[1].logged_at);

  // Most recent workout must be within last 24h
  const hoursAgoLast = (Date.now() - last.getTime()) / (1000 * 60 * 60);
  if (hoursAgoLast > 24) return null;

  // Gap between last two workouts must be 3+ days
  const gapDays = (last.getTime() - prev.getTime()) / (1000 * 60 * 60 * 24);
  if (gapDays < 3) return null;

  return {
    type: "recovery",
    text: "Coming back after a stretch off. Comeback session in the books, Sailor. The break didn't break you. Carry on.",
  };
}

async function checkPRAfterBadSleep(
  supabase: SupabaseClient,
  userId: string,
): Promise<Moment | null> {
  // Find any PR set in last 24h
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: prs } = await supabase
    .from("workout_log_exercises")
    .select("exercise_id, exercise_name, weight_kg, reps, completed_at")
    .eq("user_id", userId)
    .eq("is_pr", true)
    .gte("completed_at", yesterday)
    .order("completed_at", { ascending: false })
    .limit(1);

  if (!prs || prs.length === 0) return null;

  const pr = prs[0];
  const prDate = new Date(pr.completed_at);

  // Look up sleep logged for the night before the PR workout (date - 1 day in IST)
  const istOffsetMs = 5.5 * 60 * 60 * 1000;
  const prDateIst = new Date(prDate.getTime() + istOffsetMs);
  const prDateIstStr = prDateIst.toISOString().substring(0, 10);
  // Previous night = same IST date as the workout (sleep on the night of day-1, i.e. the night before)
  const prDateObj = new Date(prDateIstStr);
  const sleepDateStr = new Date(prDateObj.getTime() - 24 * 60 * 60 * 1000)
    .toISOString()
    .substring(0, 10);

  const { data: sleep } = await supabase
    .from("sleep_logs")
    .select("duration_hrs")  // ← actual column name (not 'hours')
    .eq("user_id", userId)
    .eq("date", sleepDateStr)
    .maybeSingle();

  if (!sleep) return null;
  const hrs = Number(sleep.duration_hrs);
  if (isNaN(hrs) || hrs >= 6) return null;

  const exName = pr.exercise_name ?? pr.exercise_id ?? "that lift";
  const w = pr.weight_kg != null ? `${pr.weight_kg} kg` : null;
  const r = pr.reps != null ? `${pr.reps} reps` : null;
  const liftStr = [w, r].filter(Boolean).join(" × ");
  const sleepStr = hrs.toFixed(1);

  return {
    type: "pr_after_bad_sleep",
    text: `${sleepStr}h of sleep last night and you still hit a PR on ${exName}${liftStr ? ": " + liftStr : ""}. Dum hai, Sailor. Carry on.`,
  };
}

async function checkPreDawnWorkout(
  supabase: SupabaseClient,
  userId: string,
): Promise<Moment | null> {
  // Find workouts logged in the last 24h
  // workout_logs has no started_at — use logged_at as proxy for session time
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: recent } = await supabase
    .from("workout_logs")
    .select("logged_at")
    .eq("user_id", userId)
    .gte("logged_at", since)
    .order("logged_at", { ascending: false })
    .limit(3);

  if (!recent || recent.length === 0) return null;

  // Check if the earliest logged_at in the batch (start of session) is pre-dawn IST
  const earliest = recent[recent.length - 1];
  const utc = new Date(earliest.logged_at);
  const istOffsetMinutes = 5 * 60 + 30;
  const ist = new Date(utc.getTime() + istOffsetMinutes * 60 * 1000);
  const istHour = ist.getUTCHours();

  if (istHour >= 6) return null;  // not pre-dawn

  const hh = String(istHour).padStart(2, "0");
  const mm = String(ist.getUTCMinutes()).padStart(2, "0");

  return {
    type: "pre_dawn",
    text: `${hh}:${mm} IST workout logged. Stand to. Discipline noted, Sailor. Carry on.`,
  };
}

async function checkFirstInStreakSaturday(
  supabase: SupabaseClient,
  userId: string,
): Promise<Moment | null> {
  // Today must be Saturday in IST
  const istNow = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
  if (istNow.getUTCDay() !== 6) return null;  // 6 = Saturday

  // Count distinct workout days in last 28 days as proxy for streak depth
  const since28d = new Date(Date.now() - 28 * 24 * 60 * 60 * 1000).toISOString();
  const { count } = await supabase
    .from("workout_logs")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("logged_at", since28d);

  if ((count ?? 0) < 14) return null;  // fewer than 14 sessions in 28 days — not a deep streak

  // Confirm a workout was actually logged today (IST)
  const todayIST = istNow.toISOString().substring(0, 10);
  const tomorrowIST = new Date(istNow.getTime() + 24 * 60 * 60 * 1000)
    .toISOString()
    .substring(0, 10);

  const { count: todayCount } = await supabase
    .from("workout_logs")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("logged_at", todayIST + "T00:00:00+05:30")
    .lt("logged_at", tomorrowIST + "T00:00:00+05:30");

  if ((todayCount ?? 0) === 0) return null;  // no workout today, skip

  return {
    type: "saturday_in_streak",
    text: "Saturday session, two weeks of consistent work behind you. The discipline is holding, Sailor. Carry on.",
  };
}
