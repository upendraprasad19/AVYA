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
import { timingSafeEqual } from "../_shared/cron_auth.ts";
import { istYesterdayWindow } from "../_shared/ist_date.ts";
import { buildDigestText, gatherDigestInput } from "../_shared/founder_digest_content.ts";
import { fetchAllPages } from "../_shared/paged_fetch.ts";


export const HELP_TEXT = [
  "<b>Admin commands</b>",
  "/status — open alerts, today's signups, cron health",
  "/revenue — MRR, active subs by plan",
  "/subs — new subscriptions today/yesterday",
  "/expiring — users expiring in 7/30 days",
  "/users [page] — browse all users",
  "/find [text] — search by partial name or email",
  "/user [email-or-id] — one user's detail",
  "/alerts — open alerts",
  "/errors — yesterday's errors, grouped by source",
  "/cron — cron job health",
  "/digest — re-send today's digest",
  "/help — this list",
].join("\n");

/**
 * Both the secret token AND the chat id must match — either alone is not
 * enough. The secret-token comparison is constant-time (review round 1
 * F11): this is the ONLY gate on a publicly-reachable endpoint, the same
 * threat model `_shared/cron_auth.ts`'s own `timingSafeEqual` was written
 * for. The chat id is not a secret — a plain `===` is fine there.
 */
export async function isAuthorizedTelegramSender(opts: {
  secretTokenHeader: string | null;
  expectedSecretToken: string;
  chatId: string | number;
  expectedChatId: string;
}): Promise<boolean> {
  if (!opts.secretTokenHeader) return false;
  if (!await timingSafeEqual(opts.secretTokenHeader, opts.expectedSecretToken)) return false;
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

  const authorized = await isAuthorizedTelegramSender({
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
  // Gate check_unbounded_cron_reads.dart: this was a bare unbounded read
  // (no .limit() at all) — genuinely invisible to the gate until the F11
  // fix (importing _shared/cron_auth.ts for timingSafeEqual) pulled this
  // file into the gate's scan roster for the first time. A hard row cap
  // would be WRONG here (it would silently undercount MRR past the cap,
  // the opposite of every other command's "page + total" shape) — this
  // genuinely needs every active row. Routed through fetchAllPages,
  // mirroring _shared/subscription.ts's own `subscriptions` read.
  const data = await fetchAllPages<{ plan: string }>(
    () => supabase.from("subscriptions").select("plan").eq("status", "active"),
    { orderBy: "id", label: "telegram-admin-bot cmdRevenue" },
  );
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

// Pure. Splits subscription-creation rows into "today" (>= tStart) and
// "yesterday" (< tStart) IST buckets, each counted by plan.
export function bucketSubsByPlan(
  rows: { plan: string; created_at: string }[],
  tStart: string,
): { today: Map<string, number>; yesterday: Map<string, number> } {
  const tStartMs = Date.parse(tStart);
  const today = new Map<string, number>();
  const yesterday = new Map<string, number>();
  for (const row of rows) {
    const bucket = Date.parse(row.created_at) >= tStartMs ? today : yesterday;
    bucket.set(row.plan, (bucket.get(row.plan) ?? 0) + 1);
  }
  return { today, yesterday };
}

function renderPlanCounts(counts: Map<string, number>): string {
  if (counts.size === 0) return "none";
  return [...counts.entries()].map(([plan, n]) => `${escapeHtml(plan)}: ${n}`).join(", ");
}

// deno-lint-ignore no-explicit-any
// Same PostgREST db-max-rows cap as CLIENT_ERRORS_QUERY_CAP — B-pass finding
// 2 (2026-09-14): cmdSubs had no upper bound at all, unlike cmdErrors's
// already-explicit cap+marker. Unlikely to bite at current signup volume,
// but the honesty pattern should be consistent across every uncapped read.
const SUBS_QUERY_CAP = 1000;

// deno-lint-ignore no-explicit-any
export async function cmdSubs(supabase: any): Promise<string> {
  // Review round 1 F8: the spec ("New subscriptions today/yesterday"),
  // HELP_TEXT, and this function's own (previously-mistitled) test all
  // promised BOTH windows; only yesterday was ever queried. Both windows
  // share one contiguous >= yStart read, bucketed client-side on tStart —
  // cheaper than two round trips and the boundary can't drift between them.
  const { yStart, tStart } = istYesterdayWindow();
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan, created_at")
    .eq("status", "active")
    .gte("created_at", yStart)
    .limit(1000); // keep in sync with SUBS_QUERY_CAP — literal digit required by check_unbounded_cron_reads.dart
  if (error) throw error;
  const rows = data ?? [];
  const { today, yesterday } = bucketSubsByPlan(rows, tStart);
  const lines = [
    "<b>New subscriptions</b>",
    `Today: ${renderPlanCounts(today)}`,
    `Yesterday: ${renderPlanCounts(yesterday)}`,
  ];
  if (rows.length >= SUBS_QUERY_CAP) {
    lines.push(`⚠ counts capped at ${SUBS_QUERY_CAP} rows — actual total may be higher`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdExpiring(supabase: any): Promise<string> {
  // Deliberately reads `users.subscription_expires_at`, NOT `subscriptions`
  // (unlike cmdRevenue/cmdSubs/cmdUser) — this mirrors founder_digest_content.ts's
  // own `expiringSoon` section, which already reads this denormalised
  // mirror column for the same "who's coming due" question. Review round 1
  // F10: this is a structural drift RISK against the Global Constraint that
  // `subscriptions` is the entitlement source of truth (no live divergence
  // found as of 2026-09-14 — both read 0 for the 30d window) — if the two
  // ever disagree, trust `subscriptions` and fix this column's writer.
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

const MAX_FIND_LINES = 10;

// Pure. PostgREST's `or=` filter grammar treats `,` `.` `(` `)` as structural
// (a comma injects an extra disjunct, an unbalanced paren 400s), and `%`/`*`
// are wildcard characters this function already wraps around the query
// itself — a caller-supplied one would let the search escape the intended
// "contains" match. Stripping them is defence-in-depth (this is a
// founder-only, dual-authed command against a table it may read anyway)
// AND a real robustness fix: any name/email containing a comma previously
// broke the command outright (review round 1 F7).
export function sanitizeFindQuery(raw: string): string {
  return raw.replace(/[,.()%*\\]/g, "");
}

// deno-lint-ignore no-explicit-any
export async function cmdFind(supabase: any, args: string[]): Promise<string> {
  const rawQuery = args.join(" ").trim();
  if (!rawQuery) {
    return "Usage: /find [partial name or email]";
  }
  const query = sanitizeFindQuery(rawQuery);
  if (!query) {
    return "Usage: /find [partial name or email]";
  }
  const { data, error, count } = await supabase
    .from("users")
    .select("id, email, full_name", { count: "exact" })
    .or(`email.ilike.%${query}%,full_name.ilike.%${query}%`)
    .limit(10); // keep in sync with MAX_FIND_LINES — literal digit required by check_unbounded_cron_reads.dart
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return `No users match "${escapeHtml(query)}".`;
  }
  const total = count ?? rows.length;
  const lines = [`<b>Matches for "${escapeHtml(query)}"</b> (${total}):`];
  for (const u of rows) {
    lines.push(`${escapeHtml(u.full_name ?? "(no name)")} — ${escapeHtml(u.email ?? "(no email)")} — ${u.id.slice(0, 8)}`);
  }
  if (total > MAX_FIND_LINES) {
    lines.push(`… +${total - MAX_FIND_LINES} more`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdUser(supabase: any, args: string[]): Promise<string> {
  const query = args[0]?.trim();
  if (!query) {
    return "Usage: /user [email-or-id]";
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
  // (status='active'), never users.subscription_status. A user can hold
  // more than one active row across a renewal (live evidence, review round
  // 1 F3) — `.maybeSingle()` throws PGRST116 on >1 row, so order + limit(1)
  // and take the latest-ending one rather than assuming uniqueness.
  const { data: subRows, error: subError } = await supabase
    .from("subscriptions")
    .select("plan, status, end_date")
    .eq("user_id", data.id)
    .eq("status", "active")
    .order("end_date", { ascending: false })
    .limit(1);
  if (subError) throw subError;
  const sub = subRows?.[0] ?? null;

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
  // Review round 1 F5: a bare page of MAX_ALERT_LINES with no total left
  // the founder unable to tell "10 alerts" from "10 of 29 alerts" — live
  // data on 2026-09-14 had 29 open, silently showing only the newest 10.
  // `{ count: "exact" }` mirrors founder_digest_content.ts's already-fixed
  // pattern (Hermes L22) so this can't regress independently of it.
  const { data, error, count } = await supabase
    .from("alerts")
    .select("source, severity, summary, detected_at", { count: "exact" })
    .is("resolved_at", null)
    .order("detected_at", { ascending: false })
    .limit(10); // keep in sync with MAX_ALERT_LINES — literal digit required by check_unbounded_cron_reads.dart
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return "<b>Open alerts</b>\nnone";
  }
  const total = count ?? rows.length;
  const lines = [`<b>Open alerts</b> (${total}):`];
  for (const a of rows) {
    lines.push(`[${escapeHtml(a.severity)}] ${escapeHtml(a.source)} — ${escapeHtml(a.summary)}`);
  }
  if (total > MAX_ALERT_LINES) {
    lines.push(`… +${total - MAX_ALERT_LINES} more`);
  }
  return lines.join("\n");
}

// This project's PostgREST `db-max-rows` is 1000 (see
// scripts/check_unbounded_cron_reads.dart's header) — it silently CAPS any
// `.limit(n > 1000)` to 1000 with HTTP 200 / error === null / no signal
// that truncation happened. The prior `.limit(2000)` here was never a real
// bound (review round 1 F6); it read as generous and was actually a lie.
const CLIENT_ERRORS_QUERY_CAP = 1000;

// deno-lint-ignore no-explicit-any
export async function cmdErrors(supabase: any): Promise<string> {
  const { yStart, tStart } = istYesterdayWindow();
  const { data, error } = await supabase
    .from("client_errors")
    .select("op_type, error_code")
    .gte("created_at", yStart)
    .lt("created_at", tStart)
    .limit(1000); // keep in sync with CLIENT_ERRORS_QUERY_CAP — literal digit required by check_unbounded_cron_reads.dart
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
  // The read itself was capped at CLIENT_ERRORS_QUERY_CAP rows — an honest
  // marker beats a silent undercount on a day busy enough to hit it.
  if (rows.length >= CLIENT_ERRORS_QUERY_CAP) {
    lines.push(`⚠ counts capped at ${CLIENT_ERRORS_QUERY_CAP} rows — actual total may be higher`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdCron(supabase: any): Promise<string> {
  // Review round 1 F4: a bare `.limit(200)` on `started_at desc` silently
  // DROPS the stalest (most important) jobs once they fall out of the
  // recency window — live evidence 2026-09-14 showed 3 genuinely-silent
  // functions (plateau-alert, protein-gap-alert, streak-guardian) missing
  // from the 200 most recent rows entirely. A 7-day `.gte()` time window
  // (not a row count) closes that specific gap: every function that has
  // run in the last 7 days shows up regardless of how many OTHER rows
  // exist, which `.limit(200)` could never guarantee.
  // ⚠ NOT a complete fix, corrected by the B-pass on this diff (2026-09-14):
  // `cleanup_cron_call_log()` (migration 109) does NOT spare each
  // function's most recent row — it spares exactly ONE row globally (the
  // single latest `status='success'` row table-wide). A function silent
  // for longer than 7 days has ALL its rows purged by the next nightly
  // cleanup and becomes invisible here too, past 7 days instead of past
  // 200 rows — same class of blind spot, smaller window. `.limit(1000)`
  // is a defence-in-depth cap only — PostgREST's own hard max — not the
  // real bound. See OI (filed same day) for widening the retention
  // function to a per-function exemption, which is the actual fix for
  // true beyond-7-day silence; that is separate production infrastructure
  // (migration 109 predates this branch) and out of this diff's scope.
  const sevenDaysAgoIso = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("cron_call_log")
    .select("function_name, status, started_at")
    .gte("started_at", sevenDaysAgoIso)
    .order("started_at", { ascending: false })
    .limit(1000);
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
