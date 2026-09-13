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
import { sendTelegram, truncateForTelegram } from "../_shared/telegram.ts";


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

export async function routeCommand(
  cmd: string,
  args: string[],
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<string> {
  switch (cmd) {
    case "help":
      return HELP_TEXT;
    default:
      return `Unknown command: /${cmd}. Try /help.`;
  }
}

if (import.meta.main) {
  serve(handler);
}
