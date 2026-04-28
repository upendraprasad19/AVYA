import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { geminiChat, MODEL_PRO } from "../_shared/gemini.ts";
import { CAPTAIN_MANUAL } from "../_shared/captain_manual.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// 2026-04-18 · Migrated from Cerebras gpt-oss-120b (via OpenRouter) to
// Gemini 2.5 Pro. Weekly report is the ONLY surface using Pro — deepest
// reasoning needed, runs at most once per week per user.
const PRO_MODEL_LABEL = "Gemini 2.5 Pro";

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // ── Auth ────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Missing authorization header" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid or expired token" }, 401);
    }

    const userId = user.id;

    // ── Parse body ─────────────────────────────────────────────
    const body = await req.json();
    const requestUserId = body.user_id as string | undefined;

    // Allow passing user_id in body for server-to-server calls,
    // but always fall back to the authenticated user.
    const targetUserId = requestUserId || userId;

    // Ensure the user can only request their own report
    if (targetUserId !== userId) {
      return jsonResponse({ error: "Forbidden: user_id mismatch" }, 403);
    }

    // ── Verify PRO subscription ────────────────────────────────
    const { data: subscription, error: subError } = await supabase
      .from("subscriptions")
      .select("status, end_date")
      .eq("user_id", targetUserId)
      .eq("status", "active")
      .gt("end_date", new Date().toISOString())
      .order("end_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    // Allow first free report (check if user has ever generated one)
    const { count: previousReportCount } = await supabase
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", targetUserId)
      .eq("channel", "weekly_report");

    const isFirstReport = (previousReportCount ?? 0) === 0;
    const hasPro = subscription && !subError;

    if (!hasPro && !isFirstReport) {
      return jsonResponse(
        {
          error: "PRO subscription required for ongoing weekly reports",
          code: "NOT_PRO",
        },
        403,
      );
    }

    // ── Gather last 7 days of data ─────────────────────────────
    const now = new Date();
    const sevenDaysAgo = new Date(now);
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const sevenDaysAgoStr = sevenDaysAgo.toISOString().split("T")[0];
    const todayStr = now.toISOString().split("T")[0];

    // 1. Nutrition logs for the past 7 days
    const { data: nutritionLogs, error: nutritionError } = await supabase
      .from("nutrition_logs")
      .select(
        "date, total_calories, total_protein, total_carbs, total_fat, meal_type",
      )
      .eq("user_id", targetUserId)
      .gte("date", sevenDaysAgoStr)
      .lte("date", todayStr)
      .order("date", { ascending: true });

    if (nutritionError) {
      console.error("Nutrition query error:", nutritionError);
    }

    // 2. User profile for targets
    const { data: userProfile, error: profileError } = await supabase
      .from("user_profile")
      .select(
        "current_weight_kg, target_weight_kg, primary_goal, fitness_experience, " +
          "days_per_week, activity_level, diet_preference, bmr, tdee",
      )
      .eq("user_id", targetUserId)
      .single();

    if (profileError) {
      console.error("Profile query error:", profileError);
    }

    // 3. User progress
    const { data: userProgress } = await supabase
      .from("user_progress")
      .select("current_phase, current_week, current_streak_weeks, total_workouts_done")
      .eq("user_id", targetUserId)
      .single();

    // 4a. Exercise-level data from workout_log_exercises (per-set granular data)
    // workout_logs now stores summary rows; exercise details are in workout_log_exercises.
    const { data: exerciseLogs, error: exerciseError } = await supabase
      .from("workout_log_exercises")
      .select(
        "exercise_name, set_number, reps, weight_kg, duration_seconds, is_pr, completed_at",
      )
      .eq("user_id", targetUserId)
      .gte("completed_at", sevenDaysAgoStr + "T00:00:00Z")
      .lte("completed_at", todayStr + "T23:59:59Z")
      .order("completed_at", { ascending: true });

    if (exerciseError) {
      console.error("Exercise logs query error:", exerciseError);
    }

    // 4b. Workout-level summary from workout_logs (duration, rpe, workout_name)
    const { data: workoutSummaries, error: summaryError } = await supabase
      .from("workout_logs")
      .select("date, exercise_name, duration_seconds, rpe")
      .eq("user_id", targetUserId)
      .gte("date", sevenDaysAgoStr)
      .lte("date", todayStr)
      .order("date", { ascending: true });

    if (summaryError) {
      console.error("Workout summary query error:", summaryError);
    }

    // Merge into unified workoutLogs format for downstream code.
    // Each row is a per-exercise SUMMARY (not per-set). set_number = total sets for that exercise.
    // Summary logs provide: date, duration_seconds, rpe
    const workoutLogs: Array<Record<string, unknown>> = (exerciseLogs ?? []).map((e: Record<string, unknown>) => ({
      date: e.completed_at ? (e.completed_at as string).split("T")[0] : todayStr,
      exercise_name: e.exercise_name,
      sets_completed: (e.set_number as number) ?? 1, // actual set count from per-exercise summary
      reps_completed: e.reps,
      weight_kg: e.weight_kg,
      duration_seconds: e.duration_seconds,
      is_pr: e.is_pr,
      rpe: null, // RPE is workout-level, not exercise-level
    }));

    // Attach RPE from workout summaries to the first exercise entry of each date
    const rpeByDate: Record<string, number | null> = {};
    for (const ws of workoutSummaries ?? []) {
      const d = (ws as Record<string, unknown>).date as string;
      const rpe = (ws as Record<string, unknown>).rpe as number | null;
      if (rpe && !rpeByDate[d]) rpeByDate[d] = rpe;
    }
    for (const wl of workoutLogs) {
      const d = wl.date as string;
      if (rpeByDate[d] && wl.rpe === null) {
        wl.rpe = rpeByDate[d];
      }
    }

    const workoutError = exerciseError || summaryError;

    // 5. Weight logs for trend
    const { data: weightLogs } = await supabase
      .from("weight_logs")
      .select("date, weight_kg")
      .eq("user_id", targetUserId)
      .order("date", { ascending: false })
      .limit(14);

    // ── Aggregate nutrition data ───────────────────────────────
    const logs = nutritionLogs ?? [];
    const daysLogged = new Set(logs.map((l: Record<string, unknown>) => l.date)).size;

    let totalCalories = 0;
    let totalProtein = 0;
    let totalCarbs = 0;
    let totalFat = 0;

    // Aggregate per-day totals (nutrition_logs may have multiple entries per day for different meals)
    const dailyTotals: Record<
      string,
      { calories: number; protein: number; carbs: number; fat: number }
    > = {};

    for (const log of logs) {
      const date = log.date as string;
      if (!dailyTotals[date]) {
        dailyTotals[date] = { calories: 0, protein: 0, carbs: 0, fat: 0 };
      }
      dailyTotals[date].calories += (log.total_calories as number) || 0;
      dailyTotals[date].protein += (log.total_protein as number) || 0;
      dailyTotals[date].carbs += (log.total_carbs as number) || 0;
      dailyTotals[date].fat += (log.total_fat as number) || 0;
    }

    for (const day of Object.values(dailyTotals)) {
      totalCalories += day.calories;
      totalProtein += day.protein;
      totalCarbs += day.carbs;
      totalFat += day.fat;
    }

    const avgCalories = daysLogged > 0 ? Math.round(totalCalories / daysLogged) : 0;
    const avgProtein = daysLogged > 0 ? Math.round(totalProtein / daysLogged) : 0;
    const avgCarbs = daysLogged > 0 ? Math.round(totalCarbs / daysLogged) : 0;
    const avgFat = daysLogged > 0 ? Math.round(totalFat / daysLogged) : 0;

    // ── Aggregate workout data ─────────────────────────────────
    const workouts = workoutLogs ?? [];
    const workoutDays = new Set(workouts.map((w: Record<string, unknown>) => w.date)).size;
    const totalSets = workouts.reduce(
      (sum: number, w: Record<string, unknown>) => sum + ((w.sets_completed as number) || 0),
      0,
    );
    const prs = workouts.filter((w: Record<string, unknown>) => w.is_pr === true);
    // Guard zero denominator: RPE is workout-level and currently never written
    // by the Flutter app, so all values are null. Avoid NaN.
    const rpeEntries = workouts.filter(
      (w: Record<string, unknown>) => w.rpe != null && (w.rpe as number) > 0,
    );
    const avgRpe =
      rpeEntries.length > 0
        ? (
            rpeEntries.reduce(
              (sum: number, w: Record<string, unknown>) => sum + (w.rpe as number),
              0,
            ) / rpeEntries.length
          ).toFixed(1)
        : "N/A";

    // ── Calorie/protein targets ────────────────────────────────
    const tdee = (userProfile?.tdee as number) || 2000;
    const goal = (userProfile?.primary_goal as string) || "general_fitness";

    // Estimate daily calorie target based on goal
    let calorieTarget = tdee;
    if (goal === "lose_fat") calorieTarget = Math.round(tdee * 0.8);
    else if (goal === "build_muscle") calorieTarget = Math.round(tdee * 1.1);

    // Protein target: ~2g per kg bodyweight for muscle, 1.6g for others
    const weight = (userProfile?.current_weight_kg as number) || 70;
    const proteinTarget =
      goal === "build_muscle" ? Math.round(weight * 2) : Math.round(weight * 1.6);

    // Compliance: how many days met calorie target within +/-10%
    let calorieCompliantDays = 0;
    for (const day of Object.values(dailyTotals)) {
      const lower = calorieTarget * 0.9;
      const upper = calorieTarget * 1.1;
      if (day.calories >= lower && day.calories <= upper) {
        calorieCompliantDays++;
      }
    }

    const compliancePercent =
      daysLogged > 0 ? Math.round((calorieCompliantDays / daysLogged) * 100) : 0;

    // ── Weight trend ───────────────────────────────────────────
    const weights = weightLogs ?? [];
    let weightChange = "N/A";
    if (weights.length >= 2) {
      const latest = (weights[0].weight_kg as number) || 0;
      const oldest = (weights[weights.length - 1].weight_kg as number) || 0;
      const diff = latest - oldest;
      weightChange = `${diff >= 0 ? "+" : ""}${diff.toFixed(1)} kg over ${weights.length} entries`;
    }

    // ── Build AI prompt ────────────────────────────────────────
    // Determine adherence for tone scaling
    const plannedDays = (userProfile?.days_per_week as number) || 4;
    const adherencePct = plannedDays > 0 ? Math.round((workoutDays / plannedDays) * 100) : 0;

    // Determine if user is on a plateau (no PRs this week + weight stalled)
    const noPrsThisWeek = prs.length === 0;
    const weightStalled =
      weights.length >= 2 &&
      Math.abs(
        ((weights[0].weight_kg as number) || 0) -
          ((weights[weights.length - 1].weight_kg as number) || 0),
      ) < 0.3;
    const isOnPlateau = noPrsThisWeek && weightStalled;

    // Determine if user earned a rank promotion this week
    const weekStart = sevenDaysAgoStr;
    const { data: rankPromoThisWeek } = await supabase
      .from("ai_coach_interactions")
      .select("id")
      .eq("user_id", targetUserId)
      .eq("channel", "promotion_ceremony")
      .gte("created_at", weekStart + "T00:00:00Z")
      .limit(1)
      .maybeSingle();
    const hadRankPromotion = rankPromoThisWeek != null;

    // Pick tone register for the briefing
    let toneInstruction: string;
    if (hadRankPromotion) {
      toneInstruction =
        "TONE: CEREMONIAL. User earned a rank promotion this week. Acknowledge it in the header or closing. Brief but distinguished — this is a milestone.";
    } else if (adherencePct < 80) {
      toneInstruction =
        "TONE: MIRROR. Adherence is below 80%. State the count plainly. No comfort. No soft-peddling. Ask one pointed question at the close: why the gap.";
    } else if (isOnPlateau) {
      toneInstruction =
        "TONE: STRATEGIC. No PRs this week, weight stable. Present 2-3 concrete adjustment options (load, volume, split) as choices — not prescriptions. Keep it brief.";
    } else {
      toneInstruction =
        "TONE: BRIEFING (default). Standard weekly debrief. Specific numbers, no filler.";
    }

    // Compute today's date in IST for the brief header
    const istDate = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const briefDate = istDate.toLocaleDateString("en-IN", {
      weekday: "long",
      day: "numeric",
      month: "long",
    });

    const systemPrompt = `${CAPTAIN_MANUAL}

You are delivering the SUNDAY STRATEGIC BRIEF — the weekly briefing the user
receives on Sunday at 21:00 IST. This is a mission debrief and forward order,
not a cheerleading session.

RESPONSE FORMAT (plain text, no markdown headings, no bullet symbols — use em-dash where lists are needed):

1. HEADER LINE: "Sunday brief — ${briefDate}. Stand to."
2. LAST WEEK VERDICT (3-4 lines):
   — Sessions: X/${plannedDays} completed. [One-word verdict: Solid / Acceptable / Below standard / Absent]
   — Volume: reference total sets or weight delta vs prior week if available in user data
   — Top lift: best exercise result this week (exercise name, weight, reps)
   — Nutrition: protein average vs target. Mention fiber if relevant.
3. THIS WEEK MISSION (3-4 lines):
   — Sessions scheduled: X days
   — Risk factors: any pattern worth flagging (low sleep trend, upcoming festival, missed days cluster)
   — One specific focus point for the coming week
4. CLOSING: one of — "Carry on." / "Stand to." / "Eyes on the numbers." — match to tone

${toneInstruction}

HARD RULES:
- No exclamation marks. Period.
- No cheap praise ("great job", "amazing", "you crushed it").
- No performative empathy ("I know it's been tough").
- Every number you cite must come from the user data injected below. If a data point is missing, say "no data" — do not invent.
- Total output: 8-12 lines. Tight. The user reads this in 30 seconds, not 3 minutes.
- DO NOT wrap in JSON. DO NOT use markdown. Plain briefing text only.`;

    // NOTE: The downstream JSON parse + report struct is preserved for
    // backwards compatibility with the client. Gemini is instructed to return
    // plain text above, so the JSON parse will fall through to the fallback
    // struct. The full brief text is stored in "summary"; legacy bullet fields
    // (top_wins / areas_to_improve / recommendations) are empty arrays.
    // Client renders summary as a full multi-line text block (C4 follow-up done).

    const userMessage = `Generate my weekly nutrition and fitness report based on this data:

**USER PROFILE:**
- Current weight: ${weight} kg
- Target weight: ${userProfile?.target_weight_kg ?? "not set"} kg
- Goal: ${goal.replace(/_/g, " ")}
- Experience: ${userProfile?.fitness_experience ?? "unknown"}
- Activity level: ${userProfile?.activity_level ?? "moderate"}
- Diet preference: ${userProfile?.diet_preference ?? "no preference"}
- TDEE: ${tdee} kcal
- Daily calorie target: ${calorieTarget} kcal
- Daily protein target: ${proteinTarget}g

**THIS WEEK'S NUTRITION (last 7 days):**
- Days logged: ${daysLogged}/7
- Average daily calories: ${avgCalories} kcal (target: ${calorieTarget})
- Average daily protein: ${avgProtein}g (target: ${proteinTarget}g)
- Average daily carbs: ${avgCarbs}g
- Average daily fat: ${avgFat}g
- Calorie compliance days (within +/-10%): ${calorieCompliantDays}/${daysLogged}
- Compliance rate: ${compliancePercent}%

**Daily breakdown:**
${Object.entries(dailyTotals)
  .map(
    ([date, d]) =>
      `  ${date}: ${d.calories} kcal, ${d.protein}g protein, ${d.carbs}g carbs, ${d.fat}g fat`,
  )
  .join("\n")}

**THIS WEEK'S WORKOUTS:**
- Workout days: ${workoutDays}/${userProfile?.days_per_week ?? 4} planned
- Total sets completed: ${totalSets}
- PRs hit: ${prs.length}${prs.length > 0 ? ` (${prs.map((p: Record<string, unknown>) => p.exercise_name).join(", ")})` : ""}
- Average RPE: ${avgRpe}

**WEIGHT TREND:**
- ${weightChange}

**PROGRESS:**
- Current phase: ${userProgress?.current_phase ?? 1}
- Current week: ${userProgress?.current_week ?? 1}
- Streak: ${userProgress?.current_streak_weeks ?? 0} weeks
- Total workouts all time: ${userProgress?.total_workouts_done ?? 0}`;

    // ── Call Gemini 2.5 Pro (Flash-Lite fallback on 5xx/429) ──────
    // jsonMode: false — Captain Brief returns plain text, not JSON.
    // The JSON parse below will fall through to fallback, which places
    // the full brief in report.summary (correct client behaviour).
    const { content: aiContent, modelUsed, tokensUsed } = await geminiChat({
      model: MODEL_PRO,
      systemPrompt,
      userPrompt: userMessage,
      maxTokens: 1500,
      temperature: 0.7,
      timeoutMs: 40_000,
      jsonMode: false,
    });

    if (!aiContent) {
      return jsonResponse(
        { error: "Empty response from AI. Please try again." },
        502,
      );
    }

    // ── Parse AI response as JSON ──────────────────────────────
    let report: {
      summary: string;
      compliance_percent: number;
      top_wins: string[];
      areas_to_improve: string[];
      recommendations: string[];
    };

    try {
      // Strip markdown code fences if present
      let cleaned = aiContent.trim();
      if (cleaned.startsWith("```json")) {
        cleaned = cleaned.slice(7);
      } else if (cleaned.startsWith("```")) {
        cleaned = cleaned.slice(3);
      }
      if (cleaned.endsWith("```")) {
        cleaned = cleaned.slice(0, -3);
      }
      cleaned = cleaned.trim();

      report = JSON.parse(cleaned);
    } catch {
      // If AI didn't return valid JSON, the new C4 plain-text brief path
      // lands here by design. Store the full brief text in summary — do not
      // truncate. Legacy bullet fields are left empty so the client can
      // detect the new format (non-empty summary + empty lists).
      console.error(
        "AI response is plain text (new brief format) — using fallback struct",
      );
      report = {
        summary: aiContent.trim(),
        compliance_percent: compliancePercent,
        top_wins: [],
        areas_to_improve: [],
        recommendations: [],
      };
    }

    // ── Override compliance_percent with computed value if AI hallucinated ──
    report.compliance_percent = compliancePercent;

    // ── Log interaction ────────────────────────────────────────
    const { data: snapshotData } = await supabase
      .from("user_daily_snapshots")
      .select("id")
      .eq("user_id", targetUserId)
      .order("snapshot_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    await supabase.from("ai_coach_interactions").insert({
      user_id: targetUserId,
      snapshot_id: snapshotData?.id ?? null,
      channel: "weekly_report",
      user_message: `Weekly report request for ${sevenDaysAgoStr} to ${todayStr}`,
      ai_response: JSON.stringify(report),
      model_used: modelUsed ?? PRO_MODEL_LABEL,
      tokens_used: tokensUsed,
      created_at: new Date().toISOString(),
    });

    // ── Return structured report ───────────────────────────────
    return jsonResponse({
      ...report,
      generated_at: now.toISOString(),
      period_start: sevenDaysAgoStr,
      period_end: todayStr,
      model_used: modelUsed ?? PRO_MODEL_LABEL,
      tokens_used: tokensUsed,
      nutrition_summary: {
        days_logged: daysLogged,
        avg_calories: avgCalories,
        avg_protein: avgProtein,
        avg_carbs: avgCarbs,
        avg_fat: avgFat,
        calorie_target: calorieTarget,
        protein_target: proteinTarget,
      },
      workout_summary: {
        days_trained: workoutDays,
        total_sets: totalSets,
        prs_hit: prs.length,
        avg_rpe: avgRpe,
      },
    });
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[weekly-report] request_id=${requestId}`, err);
    return jsonResponse(
      { error: "Internal server error", request_id: requestId },
      500,
    );
  }
});
