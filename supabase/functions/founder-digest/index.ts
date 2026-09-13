/**
 * founder-digest — one Telegram message a day to the founder: yesterday's
 * usage per quota_key, users at a ceiling, top users by id prefix, and the
 * alerts the cron rules raised. READ-ONLY over the database; it decides no
 * quota and writes nothing but its own cron_call_log row.
 *
 * Triggers: pg_cron job `founder_digest_daily`, `30 2 * * *` UTC = 08:00 IST
 *   (migration 131). Every day, including all-quiet days: the message's
 *   ARRIVAL is the liveness signal — its absence means the cron or the bot
 *   is dead. Nothing else watches this function: `alert_cron_function_dead`
 *   cannot fire at all (OI-179, threshold above the log's retention), and
 *   `cron_call_log` is lossy at the 02:30Z burst — the FIRST natural fire
 *   (2026-09-13) delivered and left no row, because its `logCronStart`
 *   insert lost the race to a PostgREST 504 (OI-194). A manual re-run sends
 *   a duplicate; acceptable.
 * Edge Function secrets: TELEGRAM_BOT_TOKEN, FOUNDER_TELEGRAM_CHAT_ID (both
 *   stored 2026-09-12 and proven by a delivered message), CRON_SECRET (the
 *   gate), platform-injected SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.
 * Owner: founder
 * Created: 2026-09-12 (OI-153)
 *
 * Three states per section, never two (feedback_bad_news_vs_no_news): data ·
 * "none" · an explicit "unreadable" marker. An unreadable section is never
 * rendered as zeros.
 *
 * What leaves the project (to Telegram's servers — a third party, not E2E):
 * per-key totals, distinct-user and at-cap COUNTS, up to five 8-char user-id
 * PREFIXES with their day's usage, and the alert rows' source/severity/
 * summary (templated counts and function names — the alert writers
 * interpolate no user data). The prefix is a correlation key, not
 * anonymisation: at today's scale every user has a distinct one. No message
 * text, no health data, no media and no email ever enters this text.
 *
 * The Telegram send is a private twin of morning-alert's, with ONE deliberate
 * difference: the fetch is wrapped in its own try/catch and NEITHER the error
 * object nor String(err) is ever logged or passed to logCronEnd. A Deno fetch
 * TypeError's message embeds the request URL — `api.telegram.org/bot<TOKEN>/…`
 * — so logging it would put the bot token in the function logs. Only
 * `err.name`, and for a non-2xx the status + the first 200 chars of Telegram's
 * body (which never echoes the token), ever leave this function.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import { telegramErrorSummary } from "../_shared/telegram.ts";
import {
  buildDigestText,
  gatherDigestInput,
} from "../_shared/founder_digest_content.ts";

// Re-exported so founder-digest/index_test.ts's existing imports (and any
// other consumer that used to pull these from this file) keep working
// unchanged — the definitions now live in the shared module (telegram-admin-bot
// Task 4), this file just forwards them.
export {
  buildDigestText,
  DIGEST_KEYS,
  type DigestClient,
  type DigestInput,
  type DigestKey,
  gatherDigestInput,
  idPrefix,
  istClock,
  LIFETIME_WINDOW,
  MAX_ALERT_LINES,
  MAX_PAGES,
  readDigestSections,
  type SectionRead,
  TOP_USERS,
  type UsageRow,
  type AlertRow,
} from "../_shared/founder_digest_content.ts";
export { escapeHtml, telegramErrorSummary, TELEGRAM_MAX_CHARS } from "../_shared/telegram.ts";
export { istYesterdayWindow } from "../_shared/ist_date.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * Twin of morning-alert's sender — see the header for the difference.
 * Exported, with `fetchImpl` injectable, so `index_test.ts` can drive the
 * catch arm with a URL-bearing TypeError and assert the token never reaches
 * the summary: the guard used to be structural only, and a one-token edit to
 * `String(err)` would have leaked with every test green (Hermes L40).
 */
export async function sendTelegram(
  token: string,
  chatId: string,
  text: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ ok: true } | { ok: false; summary: string }> {
  try {
    const res = await fetchImpl(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      const body = (await res.text().catch(() => "")).slice(0, 200);
      return { ok: false, summary: `telegram HTTP ${res.status}: ${body}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, summary: telegramErrorSummary(err) };
  }
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!await isAuthorizedCronCall(req)) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("founder-digest");

  try {
    const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
    const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
    if (!token || !chatId) {
      // Loud, never a silent `return false` (the shape morning-alert has).
      const errorSummary = "TELEGRAM_BOT_TOKEN / FOUNDER_TELEGRAM_CHAT_ID not configured";
      await logCronEnd(logId, "failed", { httpStatus: 500, errorSummary });
      return serverError("founder-digest:secrets", new Error(errorSummary));
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const input = await gatherDigestInput(supabase);
    const label = input.dayLabel;
    const text = buildDigestText(input);

    const sent = await sendTelegram(token, chatId, text);
    if (!sent.ok) {
      await logCronEnd(logId, "failed", { httpStatus: 502, errorSummary: sent.summary });
      return new Response(
        JSON.stringify({ error: "telegram send failed" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({ ok: true, day: label, chars: text.length });
  } catch (err) {
    // Reads and rendering only reach here — the send catches its own errors
    // internally, so a fetch error (URL-bearing) can never be stringified.
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      errorSummary: String(err).slice(0, 500),
    });
    return serverError("founder-digest", err);
  }
};

if (import.meta.main) {
  serve(handler);
}
