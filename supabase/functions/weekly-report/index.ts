import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { cascadeChat } from "./_shared/openrouter.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PRO_MODEL = "cerebras/gpt-oss-120b";
const PRO_MODEL_LABEL = "Cerebras gpt-oss-120B";

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
    const systemPrompt = `You are ICANBEFITTER PRO AI Coach, an elite fitness and nutrition analyst for young professionals in India. Generate a structured weekly nutrition and fitness report.

IMPORTANT: You MUST respond with valid JSON only. No markdown, no code fences, no explanations outside the JSON. The JSON must have exactly these keys:
- "summary": A 2-3 sentence overview of the week (string)
- "compliance_percent": Overall nutrition compliance as integer 0-100
- "top_wins": Array of 2-4 strings highlighting positive achievements
- "areas_to_improve": Array of 2-4 strings with specific improvement suggestions
- "recommendations": Array of 3-5 actionable recommendation strings for the coming week

Use metric units (kg, kcal). Reference Indian foods when making meal suggestions. Be motivating but honest.`;

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

    // ── Call AI via cascade (PRO model → free fallbacks) ──────────
    const { content: aiContent, modelUsed, tokensUsed } = await cascadeChat({
      models: [
        PRO_MODEL,
        "qwen/qwen3.6-plus:free",
        "nvidia/nemotron-3-super-120b-a12b:free",
        "minimax/minimax-m2.5:free",
      ],
      systemPrompt,
      userPrompt: userMessage,
      maxTokens: 1500,
      temperature: 0.7,
      timeoutMs: 15000,
      title: "ICANBEFITTER PRO Weekly Report",
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
      // If AI didn't return valid JSON, build a fallback
      console.error("Failed to parse AI response as JSON, using fallback");
      report = {
        summary: aiContent.slice(0, 300),
        compliance_percent: compliancePercent,
        top_wins: ["Logged nutrition data this week"],
        areas_to_improve: ["Try to hit your calorie target more consistently"],
        recommendations: [
          "Focus on protein intake at every meal",
          "Log all meals for better tracking accuracy",
          "Stay consistent with your workout schedule",
        ],
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
    const message =
      err instanceof Error ? err.message : "Internal server error";
    console.error("Weekly report error:", message);
    return jsonResponse({ error: message }, 500);
  }
});
