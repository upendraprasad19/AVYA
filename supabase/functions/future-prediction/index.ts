import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { istDateStr } from "../_shared/ist_date.ts";
import { predictLift, predictStreakWeeks, predictWeight } from "./trend.ts";
import { completionRateOverWindow, windowSinceDateUtc } from "../_shared/rank_engine.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * Generate a local fallback prediction without AI (used for all users).
 * Real trend math where there's enough history; per-field static-formula
 * fallback otherwise — never all-or-nothing.
 */
export async function generateLocalPrediction(
  supabase: SupabaseClient,
  userId: string,
  profile: Record<string, unknown>,
  progress: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const currentWeight = (profile.current_weight_kg as number) ?? 70;
  const targetWeight = (profile.target_weight_kg as number) ?? currentWeight;
  const goal = (profile.primary_goal as string) ?? "general_fitness";
  const experience = (progress.detected_experience_level as string) ?? "beginner";
  const daysPerWeek = (profile.days_per_week as number) ?? 3;

  // Static formulas stay as the FALLBACK for each field individually —
  // never all-or-nothing.
  const weightFallback = Math.round((currentWeight + (targetWeight - currentWeight) * 0.3) * 10) / 10;
  const liftMultipliers: Record<string, Record<string, number>> = {
    beginner: { squat: 0.8, bench: 0.5, deadlift: 1.0 },
    intermediate: { squat: 1.2, bench: 0.8, deadlift: 1.5 },
    advanced: { squat: 1.5, bench: 1.1, deadlift: 1.8 },
  };
  const multipliers = liftMultipliers[experience] ?? liftMultipliers.beginner;
  const liftFallback = {
    squat: Math.round(currentWeight * multipliers.squat),
    bench: Math.round(currentWeight * multipliers.bench),
    deadlift: Math.round(currentWeight * multipliers.deadlift),
  };
  const streakFallback = Math.min(daysPerWeek >= 4 ? 10 : 8, 13);

  const since90 = istDateStr(new Date(Date.now() - 90 * 24 * 3600 * 1000));
  const { data: weightRows } = await supabase
    .from("weight_logs")
    .select("date, weight_kg")
    .eq("user_id", userId)
    .gte("date", since90)
    .order("date", { ascending: true });

  const predictedWeight = predictWeight(
    (weightRows ?? []).map((r: Record<string, unknown>) => ({
      date: r.date as string,
      weight_kg: r.weight_kg as number,
    })),
    weightFallback,
  );

  async function liftPrediction(matchSubstring: string, fallback: number): Promise<number> {
    const { data: rows } = await supabase
      .from("workout_log_exercises")
      .select("completed_at, weight_kg")
      .eq("user_id", userId)
      .eq("is_pr", true)
      .ilike("exercise_id", `%${matchSubstring}%`)
      .order("completed_at", { ascending: true });
    return predictLift(
      (rows ?? []).map((r: Record<string, unknown>) => ({
        completed_at: r.completed_at as string,
        weight_kg: r.weight_kg as number,
      })),
      fallback,
    );
  }

  const [squatKg, benchKg, deadliftKg] = await Promise.all([
    liftPrediction("squat", liftFallback.squat),
    liftPrediction("bench", liftFallback.bench),
    liftPrediction("deadlift", liftFallback.deadlift),
  ]);

  // completionRateOverWindow returns 0.0 for BOTH "zero scheduled rows in
  // the window" (no history — should fall back) AND "real 0% completion on
  // a non-empty schedule" (a genuine signal). It only distinguishes a query
  // ERROR via the -1.0 sentinel, so a bare `adherenceRate < 0` check reads a
  // brand-new user's empty schedule as "0% adherence" and predicts 0
  // streak-weeks instead of falling back. Probe for schedule-row existence
  // directly to tell the two apart, without changing the shared helper's
  // contract (also used by evaluate-rank-promotions). Uses
  // windowSinceDateUtc — the SAME raw-UTC cutoff completionRateOverWindow
  // computes internally — rather than istDateStr, so the probe's window and
  // completionRateOverWindow's window can never disagree about which rows
  // are "in the last 4 weeks" (an IST-shifted cutoff here would drift from
  // completionRateOverWindow's raw-UTC one by up to a day near the
  // IST-midnight boundary).
  const streakWindowSince = windowSinceDateUtc(4);
  const { data: scheduleProbeRows } = await supabase
    .from("scheduled_workouts")
    .select("status")
    .eq("user_id", userId)
    .gte("scheduled_date", streakWindowSince)
    .order("scheduled_date", { ascending: true });
  const hasScheduleHistory = (scheduleProbeRows ?? []).some(
    (r: Record<string, unknown>) => r.status !== "rest",
  );

  const adherenceRate = await completionRateOverWindow(supabase, userId, 4);
  const predictedStreak = predictStreakWeeks(
    !hasScheduleHistory || adherenceRate < 0 ? null : adherenceRate,
    streakFallback,
  );

  const taglines: Record<string, string[]> = {
    build_muscle: [
      "Stronger than yesterday, every single day.",
      "Your muscles are waiting to grow — let's make it happen.",
    ],
    lose_fat: [
      "Every kg lost is a victory earned.",
      "Your transformation starts with today's workout.",
    ],
    general_fitness: [
      "Fitter, faster, stronger — that's your 90-day story.",
      "The best version of you is 90 days away.",
    ],
    strength: [
      "Prepare to surprise yourself with what you can lift.",
      "Heavy iron, strong mind — your future is powerful.",
    ],
  };

  const goalTaglines = taglines[goal] ?? taglines.general_fitness;
  const tagline = goalTaglines[Math.floor(Math.random() * goalTaglines.length)];

  return {
    predicted_weight_kg: predictedWeight,
    predicted_bf_pct: null,
    predicted_lifts: { squat_kg: squatKg, bench_kg: benchKg, deadlift_kg: deadliftKg },
    predicted_streak_weeks: predictedStreak,
    confidence: "medium",
    tagline,
    source: "local",
  };
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
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userId = user.id;

    // Parse request body
    let trigger: "onboarding" | "monthly" = "onboarding";
    try {
      const body = await req.json();
      if (body?.trigger === "monthly") trigger = "monthly";
    } catch {
      // Default to onboarding trigger
    }

    // For monthly predictions, verify PRO subscription
    if (trigger === "monthly") {
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
          JSON.stringify({
            error: "PRO subscription required for monthly predictions",
            code: "NOT_PRO",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Check if user already has a recent prediction (within 30 days for monthly)
    if (trigger === "monthly") {
      // audit-2026-05-11 H-6 — 30-day re-prediction window now
      // IST-anchored so the monthly cycle aligns with the user's
      // calendar instead of UTC's.
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const cutoffStr = istDateStr(thirtyDaysAgo);

      const { data: recentPrediction } = await supabaseClient
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .gte("snapshot_date", cutoffStr)
        .not("snapshot_json->future_prediction", "is", null)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      if (recentPrediction?.snapshot_json?.future_prediction) {
        return new Response(
          JSON.stringify({
            status: "existing",
            prediction: recentPrediction.snapshot_json.future_prediction,
            message: "Recent prediction still active (generated within 30 days)",
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Fetch user_profile
    const { data: profileData, error: profileError } = await supabaseClient
      .from("user_profile")
      .select("*")
      .eq("user_id", userId)
      .single();

    if (profileError || !profileData) {
      return new Response(
        JSON.stringify({ error: "User profile not found. Complete onboarding first." }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch user_progress
    const { data: progressData } = await supabaseClient
      .from("user_progress")
      .select("*")
      .eq("user_id", userId)
      .single();

    const progress = progressData ?? {
      total_workouts_done: 0,
      current_streak_weeks: 0,
      detected_experience_level: "beginner",
      current_phase: 1,
    };

    const prediction = await generateLocalPrediction(
      supabaseClient,
      userId,
      profileData as Record<string, unknown>,
      progress as Record<string, unknown>,
    );

    // Add metadata
    prediction.generated_at = new Date().toISOString();
    prediction.trigger = trigger;
    prediction.prediction_horizon_days = 90;

    // Store prediction in user_daily_snapshots — IST-anchored to
    // match daily-snapshot writer + ai-proxy reader semantics
    // (audit-2026-05-11 H-6).
    const todayStr = istDateStr();

    const { data: existingSnapshot } = await supabaseClient
      .from("user_daily_snapshots")
      .select("id, snapshot_json")
      .eq("user_id", userId)
      .eq("snapshot_date", todayStr)
      .single();

    const updatedJson = {
      ...(existingSnapshot?.snapshot_json ?? {}),
      future_prediction: prediction,
    };

    const { error: upsertError } = await supabaseClient
      .from("user_daily_snapshots")
      .upsert(
        {
          user_id: userId,
          snapshot_date: todayStr,
          snapshot_json: updatedJson,
          created_at: new Date().toISOString(),
        },
        { onConflict: "user_id,snapshot_date" },
      );

    if (upsertError) {
      console.error("Failed to store prediction:", upsertError);
      // Still return the prediction even if storage fails
    }

    return new Response(
      JSON.stringify({
        status: "success",
        prediction,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[future-prediction] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
