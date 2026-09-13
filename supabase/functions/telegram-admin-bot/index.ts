/**
 * telegram-admin-bot — the founder's on-demand admin console over Telegram.
 * verify_jwt=false (Telegram never sends a Supabase JWT). Internet-facing —
 * the ONLY auth is (1) Telegram's own webhook secret token header and (2)
 * an allowlist of exactly one chat id (the founder's). Anything failing
 * either check gets a bare 200 with no body and no identifying detail
 * logged — this endpoint must never confirm to a stranger that it does
 * anything at all.
 *
 * Read-only v1: every command answers a question. None of them change any
 * state. See docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { corsHeaders } from "../_shared/error.ts";
import { sendTelegram, truncateForTelegram, escapeHtml } from "../_shared/telegram.ts";
import { istDateStr, istYesterdayWindow } from "../_shared/ist_date.ts";
import { buildDigestText, gatherDigestInput } from "../_shared/founder_digest_content.ts";


export const HELP_TEXT = [
  "<b>Admin commands</b>",
  "/status — open alerts, today's signups, cron health",
  "/revenue — MRR, active subs by plan",
  "/subs — new subscriptions today/yesterday",
  "/expiring — users expiring in 7/30 days",
  "/users [page] — browse all users",
  "/find <text> — search by partial name or email",
  "/user <email-or-id> — one user's detail",
  "/alerts — open alerts",
  "/errors — yesterday's errors, grouped by source",
  "/cron — cron job health",
  "/digest — re-send today's digest",
  "/help — this list",
].join("\n");

/** Pure. Both the secret token AND the chat id must match — either alone is not enough. */
export function isAuthorizedTelegramSender(opts: {
  secretTokenHeader: string | null;
  expectedSecretToken: string;
  chatId: string | number;
  expectedChatId: string;
}): boolean {
  if (!opts.secretTokenHeader) return false;
  if (opts.secretTokenHeader !== opts.expectedSecretToken) return false;
  return String(opts.chatId) === opts.expectedChatId;
}

/** Pure. Strips a leading "/" and any "@BotName" suffix; lowercases the command. Returns null for non-commands. */
export function parseCommand(text: string): { cmd: string; args: string[] } | null {
  const trimmed = text.trim();
  if (!trimmed.startsWith("/")) return null;
  const tokens = trimmed.split(/\s+/);
  const first = tokens[0].slice(1).split("@")[0].toLowerCase();
  if (!first) return null;
  return { cmd: first, args: tokens.slice(1) };
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("", { status: 200 });
  }

  const expectedSecretToken = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const expectedChatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  let update: { message?: { chat?: { id?: number | string }; text?: string } } | null;
  try {
    update = await req.json();
  } catch {
    return new Response("", { status: 200 });
  }

  // `update` can be `null` here — a request body of the JSON literal `null`
  // parses successfully (no throw above), so this chain MUST start from the
  // root `update`, not from `.message`. `update.message?.chat?.id` protects
  // `.chat`/`.id` but not `.message` itself off a null `update`, which threw
  // an uncaught TypeError and broke the silent-200 invariant (see index_test.ts).
  const chatId = update?.message?.chat?.id;
  const text = update?.message?.text;
  if (chatId == null || !text) {
    return new Response("", { status: 200 });
  }

  const authorized = isAuthorizedTelegramSender({
    secretTokenHeader: req.headers.get("X-Telegram-Bot-Api-Secret-Token"),
    expectedSecretToken,
    chatId,
    expectedChatId,
  });
  if (!authorized) {
    // Silent — no reply, no identifying detail logged. This endpoint is
    // internet-facing; an unauthorized sender must learn nothing from it.
    return new Response("", { status: 200 });
  }

  const parsed = parseCommand(text);
  if (!parsed) {
    return new Response("", { status: 200 });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const chatIdStr = String(chatId);

  let reply: string;
  try {
    reply = await routeCommand(parsed.cmd, parsed.args, supabase);
  } catch (err) {
    const requestId = crypto.randomUUID().slice(0, 8);
    console.error(`[telegram-admin-bot] request_id=${requestId}`, err);
    reply = "Something went wrong. Try again.";
  }

  const sendResult = await sendTelegram(token, chatIdStr, truncateForTelegram(reply));
  if (!sendResult.ok) {
    console.error(`[telegram-admin-bot] send failed: ${sendResult.summary}`);
  }

  // Always 200 — a non-200 makes Telegram retry the same update.
  return new Response("", { status: 200 });
};

const MONTHLY_PRICE_INR = 349;
const YEARLY_PRICE_INR = 2999;

// deno-lint-ignore no-explicit-any
export async function cmdStatus(supabase: any): Promise<string> {
  const [growth, ops] = await Promise.all([
    supabase.rpc("founder_metrics_for_admin_api").single(),
    supabase.rpc("founder_metrics_ops").single(),
  ]);
  if (growth.error) throw growth.error;
  if (ops.error) throw ops.error;
  return [
    "<b>Status</b>",
    `Signups today: ${growth.data.signups_today_ist}`,
    `PRO active: ${growth.data.pro_active}`,
    `Open alerts: ${ops.data.open_alerts_count}`,
    `Cron failures (24h): ${ops.data.cron_failures_24h}`,
    `Client errors today: ${ops.data.client_errors_today}`,
  ].join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdRevenue(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan")
    .eq("status", "active");
  if (error) throw error;
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    counts.set(row.plan, (counts.get(row.plan) ?? 0) + 1);
  }
  const monthly = counts.get("monthly") ?? 0;
  const yearly = counts.get("yearly") ?? 0;
  const mrr = monthly * MONTHLY_PRICE_INR + yearly * (YEARLY_PRICE_INR / 12);
  const lines = ["<b>Revenue</b>", `MRR: ₹${Math.round(mrr)}`];
  for (const [plan, n] of counts) {
    lines.push(`${escapeHtml(plan)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdSubs(supabase: any): Promise<string> {
  const { yStart, tStart } = istYesterdayWindow();
  const todayStart = istDateStr(new Date()); // used only for the label below
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan, created_at")
    .eq("status", "active")
    .gte("created_at", yStart)
    .lt("created_at", tStart);
  if (error) throw error;
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    counts.set(row.plan, (counts.get(row.plan) ?? 0) + 1);
  }
  if (counts.size === 0) {
    return `<b>New subscriptions (yesterday)</b>\nnone`;
  }
  const lines = ["<b>New subscriptions (yesterday)</b>"];
  for (const [plan, n] of counts) {
    lines.push(`${escapeHtml(plan)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdExpiring(supabase: any): Promise<string> {
  const now = new Date();
  const in7d = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const in30d = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const [r7, r30] = await Promise.all([
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in7d),
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in30d),
  ]);
  if (r7.error) throw r7.error;
  if (r30.error) throw r30.error;
  return `<b>Expiring soon</b>\n7d: ${r7.count ?? 0}\n30d: ${r30.count ?? 0}`;
}

const USERS_PAGE_SIZE = 10;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Pure. */
export function looksLikeUuid(s: string): boolean {
  return UUID_RE.test(s.trim());
}

// deno-lint-ignore no-explicit-any
export async function cmdUsers(supabase: any, args: string[]): Promise<string> {
  const page = Math.max(1, parseInt(args[0] ?? "1", 10) || 1);
  const from = (page - 1) * USERS_PAGE_SIZE;
  const to = from + USERS_PAGE_SIZE - 1;
  const { data, error } = await supabase
    .from("users")
    .select("id, email, created_at")
    .order("created_at", { ascending: false })
    .range(from, to);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return `<b>Users — page ${page}</b>\nnone`;
  }
  const lines = [`<b>Users — page ${page}</b>`];
  for (const u of rows) {
    lines.push(`${escapeHtml(u.email ?? "(no email)")} — ${u.id.slice(0, 8)}`);
  }
  lines.push(`\n/users ${page + 1} for more`);
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdFind(supabase: any, args: string[]): Promise<string> {
  const query = args.join(" ").trim();
  if (!query) {
    return "Usage: /find <partial name or email>";
  }
  const { data, error } = await supabase
    .from("users")
    .select("id, email, full_name")
    .or(`email.ilike.%${query}%,full_name.ilike.%${query}%`)
    .limit(10);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return `No users match "${escapeHtml(query)}".`;
  }
  const lines = [`<b>Matches for "${escapeHtml(query)}"</b>`];
  for (const u of rows) {
    lines.push(`${escapeHtml(u.full_name ?? "(no name)")} — ${escapeHtml(u.email ?? "(no email)")} — ${u.id.slice(0, 8)}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdUser(supabase: any, args: string[]): Promise<string> {
  const query = args[0]?.trim();
  if (!query) {
    return "Usage: /user <email-or-id>";
  }
  const column = looksLikeUuid(query) ? "id" : "email";
  const { data, error } = await supabase
    .from("users")
    .select("id, email, full_name, created_at, last_active_at, subscription_expires_at")
    .eq(column, query)
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    return `User not found for "${escapeHtml(query)}".`;
  }
  // Entitlement per this batch's Global Constraints: read `subscriptions`
  // (status='active'), never users.subscription_status.
  const { data: sub, error: subError } = await supabase
    .from("subscriptions")
    .select("plan, status, end_date")
    .eq("user_id", data.id)
    .eq("status", "active")
    .maybeSingle();
  if (subError) throw subError;

  const lines = [
    `<b>${escapeHtml(data.full_name ?? "(no name)")}</b>`,
    escapeHtml(data.email ?? "(no email)"),
    `id: ${data.id.slice(0, 8)}`,
    `signed up: ${data.created_at?.slice(0, 10) ?? "unknown"}`,
    `last active: ${data.last_active_at?.slice(0, 10) ?? "never"}`,
    sub ? `plan: ${escapeHtml(sub.plan)} (ends ${sub.end_date?.slice(0, 10) ?? "?"})` : "plan: free",
  ];
  return lines.join("\n");
}

const MAX_ALERT_LINES = 10;

// deno-lint-ignore no-explicit-any
export async function cmdAlerts(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("alerts")
    .select("source, severity, summary, detected_at")
    .is("resolved_at", null)
    .order("detected_at", { ascending: false })
    .limit(MAX_ALERT_LINES);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return "<b>Open alerts</b>\nnone";
  }
  const lines = ["<b>Open alerts</b>"];
  for (const a of rows) {
    lines.push(`[${escapeHtml(a.severity)}] ${escapeHtml(a.source)} — ${escapeHtml(a.summary)}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdErrors(supabase: any): Promise<string> {
  const { yStart, tStart } = istYesterdayWindow();
  const { data, error } = await supabase
    .from("client_errors")
    .select("op_type, error_code")
    .gte("created_at", yStart)
    .lt("created_at", tStart)
    .limit(2000);
  if (error) throw error;
  const rows = (data ?? []).filter((r: { error_code: string }) =>
    r.error_code !== "event" && r.error_code !== "info"
  );
  if (rows.length === 0) {
    return "<b>Errors (yesterday)</b>\nnone";
  }
  const counts = new Map<string, number>();
  for (const r of rows) {
    counts.set(r.op_type, (counts.get(r.op_type) ?? 0) + 1);
  }
  const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  const lines = ["<b>Errors (yesterday)</b>"];
  for (const [opType, n] of sorted.slice(0, 10)) {
    lines.push(`${escapeHtml(opType)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdCron(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("cron_call_log")
    .select("function_name, status, started_at")
    .order("started_at", { ascending: false })
    .limit(200);
  if (error) throw error;
  const latestByFn = new Map<string, { status: string; started_at: string }>();
  for (const row of data ?? []) {
    if (!latestByFn.has(row.function_name)) {
      latestByFn.set(row.function_name, { status: row.status, started_at: row.started_at });
    }
  }
  const now = Date.now();
  const entries = [...latestByFn.entries()].sort((a, b) =>
    new Date(a[1].started_at).getTime() - new Date(b[1].started_at).getTime()
  );
  const lines = ["<b>Cron (most stale first)</b>"];
  for (const [fn, info] of entries.slice(0, 15)) {
    const ageMin = Math.round((now - new Date(info.started_at).getTime()) / 60000);
    lines.push(`${escapeHtml(fn)}: ${escapeHtml(info.status)}, ${ageMin}m ago`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdDigest(supabase: any): Promise<string> {
  const input = await gatherDigestInput(supabase, new Date());
  return buildDigestText(input);
}

export async function routeCommand(
  cmd: string,
  args: string[],
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<string> {
  switch (cmd) {
    case "help":
      return HELP_TEXT;
    case "status":
      return cmdStatus(supabase);
    case "revenue":
      return cmdRevenue(supabase);
    case "subs":
      return cmdSubs(supabase);
    case "expiring":
      return cmdExpiring(supabase);
    case "users":
      return cmdUsers(supabase, args);
    case "find":
      return cmdFind(supabase, args);
    case "user":
      return cmdUser(supabase, args);
    case "alerts":
      return cmdAlerts(supabase);
    case "errors":
      return cmdErrors(supabase);
    case "cron":
      return cmdCron(supabase);
    case "digest":
      return cmdDigest(supabase);
    default:
      return `Unknown command: /${cmd}. Try /help.`;
  }
}

if (import.meta.main) {
  serve(handler);
}
