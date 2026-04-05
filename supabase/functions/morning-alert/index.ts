import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

const PRO_MODEL = "cerebras/gpt-oss-120b";
const AI_TIMEOUT_MS = 3000; // 3s hard limit — fail fast, fallback to free template
const PAGE_SIZE = 200; // Users fetched per page to cap memory
const CONCURRENCY = 20; // Parallel AI calls within each chunk

// ── Counters (module-level so generateAndStoreAlert can increment) ────
let proAlerts = 0;
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
 */
function generateFreeAlert(
  name: string,
  snapshotJson: Record<string, unknown> | null,
): string {
  const firstName = name?.split(" ")[0] ?? "Champion";
  const streak = snapshotJson?.current_streak_weeks ?? 0;
  const todayWorkout = snapshotJson?.today_workout_name ?? null;

  let message = `Good morning ${firstName}!`;

  if (todayWorkout) {
    message += ` ${todayWorkout} is scheduled today.`;
  } else {
    message += ` Ready to crush your goals today?`;
  }

  if (typeof streak === "number" && streak > 0) {
    message += ` ${streak} week streak going strong!`;
  }

  // Add a rotating motivational line based on day of week
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
 * Generate a PRO personalised morning alert using Cerebras 120B.
 * Single attempt with 3s hard timeout — no retries (fail fast at scale).
 */
async function generateProAlert(
  name: string,
  snapshotJson: Record<string, unknown>,
): Promise<string | null> {
  const systemPrompt =
    "You are ICANBEFITTER's morning coach. Generate a short, personalised morning alert " +
    "(2-3 sentences, under 100 tokens) for the user. Reference specific numbers from their data: " +
    "workout name, weight lifted, streak count, yesterday's calories, or recent PRs. " +
    "Be encouraging, specific, and actionable. Use the user's first name. " +
    "Output ONLY the alert message, no preamble or formatting.";

  const userPrompt =
    `User name: ${name}\nYesterday's snapshot data:\n${JSON.stringify(snapshotJson)}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);

  try {
    const response = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${OPENROUTER_API_KEY}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://icanbefitter.app",
          "X-Title": "ICANBEFITTER Morning Alert",
        },
        body: JSON.stringify({
          model: PRO_MODEL,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
          max_tokens: 150,
        }),
        signal: controller.signal,
      },
    );

    clearTimeout(timer);

    if (!response.ok) {
      console.error(`PRO alert AI error: HTTP ${response.status}`);
      return null;
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (content && typeof content === "string") {
      return content.trim();
    }
    return null;
  } catch (err) {
    clearTimeout(timer);
    // AbortError = timeout, anything else = network failure — both get free fallback
    if (err instanceof DOMException && err.name === "AbortError") {
      console.warn("PRO alert AI timed out (3s limit) — falling back to free template");
    } else {
      console.error("PRO alert AI error:", err);
    }
    return null;
  }
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
    const userName = user.full_name ?? "Champion";

    // Fetch yesterday's snapshot for context
    const { data: yesterdaySnap } = await supabaseClient
      .from("user_daily_snapshots")
      .select("snapshot_json")
      .eq("user_id", user.id)
      .eq("snapshot_date", yesterdayIST)
      .single();

    const snapshotJson = yesterdaySnap?.snapshot_json ?? null;

    let alertMessage: string;

    if (isPro && snapshotJson) {
      // PRO: AI-personalised message (3s timeout, immediate fallback)
      const proMsg = await generateProAlert(userName, snapshotJson);
      if (proMsg) {
        alertMessage = proMsg;
        proAlerts++;
      } else {
        // Fallback to free template if AI fails
        alertMessage = generateFreeAlert(userName, snapshotJson);
        freeAlerts++;
      }
    } else {
      // FREE: template message (no AI cost)
      alertMessage = generateFreeAlert(userName, snapshotJson);
      freeAlerts++;
    }

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
      morning_alert_type: isPro && snapshotJson ? "pro" : "free",
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
          if (pushOk) pushSent++;

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
        `${successCount} success, ${proAlerts} pro, ${freeAlerts} free, ${errorCount} errors`,
    );

    return new Response(
      JSON.stringify({
        status: "success",
        mode: "generate",
        users_processed: successCount,
        pro_alerts: proAlerts,
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
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("Morning alert error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
