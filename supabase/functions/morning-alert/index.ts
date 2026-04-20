import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "./_shared/send_notification.ts";
import { geminiChat, MODEL_FLASH } from "./_shared/gemini.ts";
import { fetchCoachMemory, upsertCoachMemory } from "./_shared/coach_memory.ts";

type MotivationTone = "tough_love" | "gentle" | "data_driven";

/**
 * Wrap a base alert with a tone-specific lead-in. `name` is the user's
 * preferred_name (from coach_memory) when present, falling back to the
 * full_name first token. `tone` is motivation_style from coach_memory; when
 * null/unknown we treat it as "gentle" (the existing default voice).
 */
function applyTone(
  baseAlert: string,
  name: string,
  tone: MotivationTone | null,
  snapshotJson: Record<string, unknown> | null,
): string {
  const firstName = name?.split(" ")[0] ?? "there";

  if (tone === "tough_love") {
    return `${firstName}, no excuses today. ${baseAlert}`;
  }
  if (tone === "data_driven") {
    const snap = snapshotJson ?? {};
    // "today_steps" in yesterday's snapshot = steps recorded yesterday
    const stepsYday = snap.today_steps as number | null;
    if (stepsYday != null) {
      return `${firstName} — yesterday: ${stepsYday} steps. ${baseAlert}`;
    }
    return `${firstName} — ${baseAlert}`;
  }
  // gentle (default) — warm greeting prefix when the base doesn't already lead with the name
  if (baseAlert.startsWith("Good morning")) return baseAlert;
  return `Morning ${firstName}! ${baseAlert}`;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

// 2026-04-18 · Migrated to Gemini 2.5 Flash (was cerebras/gpt-oss-120b via
// OpenRouter). Part of the single-provider consolidation.
const AI_TIMEOUT_MS = 15_000;
const PAGE_SIZE = 200; // Users fetched per page to cap memory
const CONCURRENCY = 20; // Parallel AI calls within each chunk

// ── Counters (module-level so generateAndStoreAlert can increment) ────
let proAlerts = 0;
let proLightAlerts = 0;
let freeAlerts = 0;
let errorCount = 0;
let successCount = 0;

/**
 * Returns today's date string in IST (UTC+5:30) as YYYY-MM-DD.
 */
function getTodayIST(): string {
  const now = new Date();
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  return istDate.toISOString().split("T")[0];
}

/**
 * Returns yesterday's date string in IST.
 */
function getYesterdayIST(): string {
  const now = new Date();
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  istDate.setDate(istDate.getDate() - 1);
  return istDate.toISOString().split("T")[0];
}

/**
 * Generate a FREE template-based morning alert (no AI cost).
 * Enhanced with milestone celebrations, PR shoutouts, and weight progress.
 */
function generateFreeAlert(
  name: string,
  snapshotJson: Record<string, unknown> | null,
): string {
  const firstName = name?.split(" ")[0] ?? "Champion";
  const snap = snapshotJson ?? {};
  const streakWeeks = (snap.current_streak_weeks as number) ?? 0;
  const streakDays = (snap.current_streak_days as number) ?? streakWeeks * 7;
  const todayWorkout = snap.today_workout_name as string | null;
  const totalWorkouts = (snap.total_workouts_done as number) ?? 0;
  const recentPR = snap.recent_pr_exercise as string | null;
  const recentPRWeight = snap.recent_pr_weight as number | null;
  const weight = snap.current_weight_kg as number | null;
  const targetWeight = snap.target_weight_kg as number | null;
  const yesterdayCalories = snap.yesterday_calories as number | null;
  const calorieTarget = snap.daily_calorie_target as number | null;

  // Check for milestone events first — these take priority
  // Streak milestones
  if (streakDays === 7) {
    return `${firstName}, you just hit 7 DAYS straight! First week complete — that's the hardest one. ${todayWorkout ? `${todayWorkout} is up today.` : "Keep the momentum!"} Let's make it 14!`;
  }
  if (streakDays === 30) {
    return `30 DAYS, ${firstName}! A full month of consistency. You're in the top 5% of AVYA users. ${todayWorkout ? `${todayWorkout} today — let's go!` : "What a milestone!"}`;
  }
  if (streakDays === 50) {
    return `FIFTY DAYS, ${firstName}! Half a century of showing up for yourself. ${todayWorkout ? `${todayWorkout} is scheduled.` : "Legendary consistency."} You're built different.`;
  }
  if (streakDays === 100) {
    return `${firstName}, 100 DAYS! Triple digits. You've done what 99% of people only dream about. ${todayWorkout ? `Day 101 starts with ${todayWorkout}.` : "Unstoppable."}`;
  }

  // Workout count milestones
  if (totalWorkouts === 10) {
    return `Good morning ${firstName}! You've completed 10 workouts total — double digits! ${todayWorkout ? `${todayWorkout} is up next.` : "Keep building!"} Every session counts.`;
  }
  if (totalWorkouts === 50) {
    return `${firstName}, 50 workouts logged! That's serious dedication. ${todayWorkout ? `${todayWorkout} today.` : "You're crushing it."} Here's to the next 50!`;
  }
  if (totalWorkouts === 100) {
    return `100 WORKOUTS, ${firstName}! You've put in the work and it shows. ${todayWorkout ? `${todayWorkout} makes it 101.` : "Triple-digit warrior!"} Incredible.`;
  }

  // PR celebration
  if (recentPR) {
    const prDetail = recentPRWeight ? ` (${recentPRWeight}kg)` : "";
    return `Good morning ${firstName}! You hit a new PR on ${recentPR}${prDetail} recently! Momentum is real. ${todayWorkout ? `${todayWorkout} today — keep pushing.` : "Ride that wave!"}`;
  }

  // Weight milestone — close to target
  if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
    return `${firstName}, you're within 2kg of your goal weight! So close. ${todayWorkout ? `${todayWorkout} is scheduled today.` : "Every session brings you closer."} Keep going!`;
  }

  // Yesterday's nutrition win
  if (yesterdayCalories && calorieTarget && Math.abs(yesterdayCalories - calorieTarget) < 100) {
    return `Good morning ${firstName}! Yesterday you nailed your calorie target (${yesterdayCalories} kcal). ${todayWorkout ? `${todayWorkout} today.` : "Keep that precision going!"} Consistency wins.`;
  }

  // Default: standard greeting with workout + streak + motivational line
  let message = `Good morning ${firstName}!`;

  if (todayWorkout) {
    message += ` ${todayWorkout} is scheduled today.`;
  } else {
    message += ` Ready to crush your goals today?`;
  }

  if (streakDays > 0) {
    message += ` ${streakDays}-day streak going strong!`;
  } else if (streakWeeks > 0) {
    message += ` ${streakWeeks} week streak going strong!`;
  }

  const dayOfWeek = new Date().getDay();
  const motivationalLines = [
    "Make today count!",
    "Consistency beats perfection.",
    "One workout at a time.",
    "Your future self will thank you.",
    "Small steps, big results.",
    "Show up for yourself today.",
    "Every rep matters.",
  ];
  message += ` ${motivationalLines[dayOfWeek]}`;

  return message;
}

/**
 * Bug #18 — PRO-light fallback. Used when a PRO user has no `user_daily_snapshots`
 * row for yesterday (e.g. they haven't been active enough for `pushSnapshot()` to fire).
 * Without this branch, PRO users would silently fall through to the generic free copy
 * — which is what Upen experienced. Personalised on name + primary_goal only, no AI cost.
 */
function generateProLightAlert(name: string, primaryGoal: string | null): string {
  const firstName = name?.split(" ")[0] ?? "Champion";
  const goal = (primaryGoal ?? "").toLowerCase();

  if (goal === "build_muscle" || goal.includes("muscle")) {
    return `Good morning ${firstName}! Muscle is built one rep at a time — and today's another rep on the journey. Train hard, eat enough, and recover well. Let's get after it.`;
  }
  if (goal === "lose_fat" || goal.includes("fat") || goal.includes("loss")) {
    return `Good morning ${firstName}! Fat loss is won at the dinner table and the gym both. Stay disciplined with your calories today and move your body — small daily wins compound fast.`;
  }
  if (goal === "strength" || goal.includes("strong")) {
    return `Good morning ${firstName}! Strength is a long game. Focus on quality reps, log every set, and chase progressive overload. Today is another deposit in the bank.`;
  }
  if (goal.includes("endurance") || goal.includes("cardio")) {
    return `Good morning ${firstName}! Endurance is built mile by mile. Keep showing up, keep moving, and your aerobic base will thank you. Make today count.`;
  }
  if (goal === "general_fitness" || goal.includes("general") || goal.includes("fit")) {
    return `Good morning ${firstName}! Fitness isn't a destination — it's a daily habit. Move your body today, eat well, hydrate, and rest. You've got this.`;
  }

  // Generic fallback (still better than free copy because it uses the name)
  return `Good morning ${firstName}! Today is another opportunity to show up for the goals you set. Train smart, eat well, and trust the process. Let's go.`;
}

async function generateProAlert(
  name: string,
  snapshotJson: Record<string, unknown>,
  tone: MotivationTone | null,
): Promise<string | null> {
  const toneGuidance = tone === "tough_love"
    ? "Tone: tough_love — be direct, no soft padding, challenge them."
    : tone === "data_driven"
    ? "Tone: data_driven — lead with a specific number from the snapshot, then the suggestion."
    : "Tone: gentle — warm and validating before suggesting.";

  const systemPrompt =
    "You are ICANBEFITTER's morning coach. Generate a short, personalised morning alert " +
    "(2-3 sentences, under 100 tokens) for the user. Reference specific numbers from their data: " +
    "workout name, weight lifted, streak count, yesterday's calories, or recent PRs. " +
    "Be encouraging, specific, and actionable. Use the user's first name. " +
    `${toneGuidance} ` +
    "Output ONLY the alert message, no preamble or formatting.";

  const userPrompt =
    `User name: ${name}\nYesterday's snapshot data:\n${JSON.stringify(snapshotJson)}`;

  const { content } = await geminiChat({
    model: MODEL_FLASH,
    systemPrompt,
    userPrompt,
    maxTokens: 150,
    timeoutMs: AI_TIMEOUT_MS,
  });

  return content;
}

/**
 * Send push notification via OneSignal.
 */
async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
): Promise<boolean> {
  return sendPushNotification({
    userId,
    title,
    message: body,
    screen: "/home",
  });
}

/**
 * Send Telegram message (if bot token is configured and user is connected).
 */
async function sendTelegramMessage(
  chatId: string,
  message: string,
): Promise<boolean> {
  if (!TELEGRAM_BOT_TOKEN || !chatId) return false;

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text: message,
          parse_mode: "HTML",
        }),
      },
    );

    if (!response.ok) {
      const errorBody = await response.text();
      console.error(`Telegram send failed for ${chatId}:`, errorBody);
      return false;
    }

    return true;
  } catch (err) {
    console.error(`Telegram error for ${chatId}:`, err);
    return false;
  }
}

// ── Core: generate alert for a single user and upsert to snapshot ─────

interface ActiveUser {
  id: string;
  full_name: string | null;
  subscription_status: string | null;
}

async function generateAndStoreAlert(
  user: ActiveUser,
  supabaseClient: SupabaseClient,
  todayIST: string,
  yesterdayIST: string,
): Promise<void> {
  try {
    const isPro = user.subscription_status === "pro";

    // Read coach_memory ONCE per user.
    // private_mode users get default copy — explicit guard since fetchCoachMemory
    // returns the row regardless of private_mode (only renderCoachMemoryBlock
    // short-circuits on it). Without nullifying here, preferred_name +
    // motivation_style would leak personalised copy to private_mode users.
    const memory = await fetchCoachMemory(supabaseClient, user.id);
    const usableMemory = memory?.private_mode ? null : memory;
    const userName = usableMemory?.preferred_name ?? user.full_name ?? "Champion";
    const tone = (usableMemory?.motivation_style ?? null) as MotivationTone | null;

    // Fetch yesterday's snapshot for context
    const { data: yesterdaySnap } = await supabaseClient
      .from("user_daily_snapshots")
      .select("snapshot_json")
      .eq("user_id", user.id)
      .eq("snapshot_date", yesterdayIST)
      .single();

    const snapshotJson = yesterdaySnap?.snapshot_json ?? null;

    let alertMessage: string;
    let msgType: "pro" | "pro_light" | "free" = "free";
    let aiSucceeded = false;

    if (isPro && snapshotJson) {
      // PRO: AI-personalised message (8s timeout, immediate fallback)
      const proMsg = await generateProAlert(userName, snapshotJson, tone);
      if (proMsg) {
        alertMessage = proMsg;
        msgType = "pro";
        aiSucceeded = true;
        proAlerts++;
      } else {
        // AI failed — fall back to free template (still has yesterday's data)
        const baseFree = generateFreeAlert(userName, snapshotJson);
        alertMessage = applyTone(baseFree, userName, tone, snapshotJson);
        msgType = "free";
        freeAlerts++;
      }
    } else if (isPro && !snapshotJson) {
      // Bug #18 — PRO user with no snapshot (e.g. wasn't active enough yesterday).
      // Use PRO-light personalised template instead of generic free copy.
      // Fetch primary_goal from user_profile for goal-aware messaging.
      const { data: profileRow } = await supabaseClient
        .from("user_profile")
        .select("primary_goal")
        .eq("user_id", user.id)
        .single();

      const primaryGoal = profileRow?.primary_goal ?? null;
      const baseProLight = generateProLightAlert(userName, primaryGoal);
      alertMessage = applyTone(baseProLight, userName, tone, snapshotJson);
      msgType = "pro_light";
      proLightAlerts++;
    } else {
      // FREE: template message (no AI cost)
      const baseFree = generateFreeAlert(userName, snapshotJson);
      alertMessage = applyTone(baseFree, userName, tone, snapshotJson);
      msgType = "free";
      freeAlerts++;
    }

    // Bug #18 — Structured per-user log line. Greppable for debugging fallback paths.
    console.log(
      `[morning-alert] user=${user.id} pro=${isPro} snapshot=${!!snapshotJson} ai_succeeded=${aiSucceeded} msg_type=${msgType}`,
    );

    // Store alert in today's snapshot
    const { data: existingSnapshot } = await supabaseClient
      .from("user_daily_snapshots")
      .select("id, snapshot_json")
      .eq("user_id", user.id)
      .eq("snapshot_date", todayIST)
      .single();

    const updatedJson = {
      ...(existingSnapshot?.snapshot_json ?? {}),
      morning_alert: alertMessage,
      morning_alert_type: msgType,
      morning_alert_generated_at: new Date().toISOString(),
    };

    const { error: upsertError } = await supabaseClient
      .from("user_daily_snapshots")
      .upsert(
        {
          user_id: user.id,
          snapshot_date: todayIST,
          snapshot_json: updatedJson,
          created_at: new Date().toISOString(),
        },
        { onConflict: "user_id,snapshot_date" },
      );

    if (upsertError) {
      console.error(
        `Failed to store alert for user ${user.id}:`,
        upsertError,
      );
      errorCount++;
      return;
    }

    successCount++;
  } catch (userErr) {
    console.error(`Error generating alert for user ${user.id}:`, userErr);
    errorCount++;
  }
}

// ── Process a batch of users with bounded concurrency ─────────────────

async function processBatch(
  users: ActiveUser[],
  supabaseClient: SupabaseClient,
  todayIST: string,
  yesterdayIST: string,
): Promise<void> {
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    await Promise.allSettled(
      chunk.map((user) =>
        generateAndStoreAlert(user, supabaseClient, todayIST, yesterdayIST)
      ),
    );
  }
}

// ── Delivery mode: paginated fetch + bounded concurrency ──────────────

async function deliverAlerts(
  supabaseClient: SupabaseClient,
  todayIST: string,
): Promise<{ totalAlerts: number; pushSent: number; telegramSent: number }> {
  let pushSent = 0;
  let telegramSent = 0;
  let totalAlerts = 0;
  let offset = 0;
  let hasMore = true;

  while (hasMore) {
    const { data: snapshots, error: snapError } = await supabaseClient
      .from("user_daily_snapshots")
      .select("user_id, snapshot_json")
      .eq("snapshot_date", todayIST)
      .not("snapshot_json->morning_alert", "is", null)
      .range(offset, offset + PAGE_SIZE - 1);

    if (snapError) {
      console.error(`Delivery fetch error at offset ${offset}:`, snapError);
      break;
    }

    if (!snapshots || snapshots.length === 0) break;
    if (snapshots.length < PAGE_SIZE) hasMore = false;
    offset += PAGE_SIZE;

    totalAlerts += snapshots.length;
    console.log(
      `morning-alert [deliver]: delivering batch at offset ${offset - PAGE_SIZE}, ${snapshots.length} alerts`,
    );

    // Deliver with bounded concurrency
    for (let i = 0; i < snapshots.length; i += CONCURRENCY) {
      const chunk = snapshots.slice(i, i + CONCURRENCY);
      await Promise.allSettled(
        chunk.map(async (snap) => {
          const alertMsg = snap.snapshot_json?.morning_alert;
          if (!alertMsg) return;

          // Check notification preferences for morning_checkin.
          const prefs = snap.snapshot_json?.notification_preferences;
          if (prefs?.morning_checkin?.enabled === false) return;

          // Send push via OneSignal
          // [TODO] FCM not implemented — alert stored in DB only for user ${snap.user_id}
          const pushOk = await sendPushToUser(
            snap.user_id,
            "ICANBEFITTER",
            alertMsg,
          );
          if (pushOk) {
            pushSent++;
            // Fire-and-forget: tag coach_memory so other proactive triggers
            // (rolling-context, weekly-recap-ready, etc.) can avoid duplicate
            // same-day pings. Non-fatal — push has already gone out.
            try {
              await upsertCoachMemory(supabaseClient, snap.user_id, {
                last_proactive_type: "morning_brief",
              });
            } catch (memErr) {
              console.warn(
                `[morning-alert] last_proactive_type tag failed for ${snap.user_id}:`,
                memErr,
              );
            }
          }

          // Try Telegram if connected
          const { data: tgConn } = await supabaseClient
            .from("telegram_connections")
            .select("chat_id")
            .eq("user_id", snap.user_id)
            .eq("is_active", true)
            .single();

          if (tgConn?.chat_id) {
            const tgOk = await sendTelegramMessage(
              tgConn.chat_id,
              `<b>Good Morning!</b>\n\n${alertMsg}`,
            );
            if (tgOk) telegramSent++;
          }
        }),
      );
    }
  }

  return { totalAlerts, pushSent, telegramSent };
}

// ── Main handler ──────────────────────────────────────────────────────

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
    const startTime = Date.now();
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Parse request to determine mode: "generate" (2AM) or "deliver" (7AM)
    let mode = "generate";
    try {
      const body = await req.json();
      if (body?.mode === "deliver") mode = "deliver";
    } catch {
      // No body — default to generate
    }

    const todayIST = getTodayIST();
    const yesterdayIST = getYesterdayIST();

    if (mode === "deliver") {
      // ── DELIVERY MODE (7AM IST) ──────────────────────────────
      // Read stored alerts page by page and deliver via push + Telegram
      console.log("morning-alert [deliver]: starting delivery run");

      const { totalAlerts, pushSent, telegramSent } = await deliverAlerts(
        supabaseClient,
        todayIST,
      );

      const elapsed = Date.now() - startTime;
      console.log(
        `morning-alert [deliver]: completed in ${elapsed}ms, ` +
          `${totalAlerts} alerts, ${pushSent} push sent, ${telegramSent} telegram sent`,
      );

      return new Response(
        JSON.stringify({
          status: "success",
          mode: "deliver",
          total_alerts: totalAlerts,
          push_sent: pushSent,
          telegram_sent: telegramSent,
          elapsed_ms: elapsed,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── GENERATION MODE (2AM IST) ────────────────────────────
    // Paginated fetch of active users — never loads all into memory at once
    console.log("morning-alert [generate]: starting generation run");

    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const sevenDaysAgoISO = sevenDaysAgo.toISOString();

    // Reset counters
    proAlerts = 0;
    proLightAlerts = 0;
    freeAlerts = 0;
    errorCount = 0;
    successCount = 0;

    let offset = 0;
    let hasMore = true;
    let batchNum = 0;
    let totalUsers = 0;

    while (hasMore) {
      const { data: users, error: usersError } = await supabaseClient
        .from("users")
        .select("id, full_name, subscription_status")
        .gte("last_active_at", sevenDaysAgoISO)
        .range(offset, offset + PAGE_SIZE - 1);

      if (usersError) {
        console.error(`Failed to fetch users at offset ${offset}:`, usersError);
        // If first page fails, return error; otherwise continue with what we have
        if (offset === 0) {
          return new Response(
            JSON.stringify({ error: "Failed to fetch active users" }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        break;
      }

      if (!users || users.length === 0) break;
      if (users.length < PAGE_SIZE) hasMore = false;

      batchNum++;
      totalUsers += users.length;
      const batchStart = Date.now();

      console.log(
        `morning-alert [generate]: processing batch ${batchNum}, ` +
          `${users.length} users (offset ${offset})`,
      );

      await processBatch(users, supabaseClient, todayIST, yesterdayIST);

      console.log(
        `morning-alert [generate]: batch ${batchNum} done in ${Date.now() - batchStart}ms`,
      );

      offset += PAGE_SIZE;
    }

    const elapsed = Date.now() - startTime;
    console.log(
      `morning-alert [generate]: completed in ${elapsed}ms, ` +
        `${totalUsers} users across ${batchNum} batches, ` +
        `${successCount} success, ${proAlerts} pro, ${proLightAlerts} pro_light, ${freeAlerts} free, ${errorCount} errors`,
    );

    return new Response(
      JSON.stringify({
        status: "success",
        mode: "generate",
        users_processed: successCount,
        pro_alerts: proAlerts,
        pro_light_alerts: proLightAlerts,
        free_alerts: freeAlerts,
        errors: errorCount,
        total_active: totalUsers,
        batches: batchNum,
        elapsed_ms: elapsed,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[morning-alert] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
