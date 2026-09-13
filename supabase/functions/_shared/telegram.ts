/**
 * telegram.ts — the ONE hardened Telegram sender for this project. Used by
 * founder-digest (daily cron), alert-critical-notify (trigger-invoked), and
 * telegram-admin-bot (webhook replies). Do not duplicate this in a new
 * function — import it.
 *
 * The error-handling discipline here is load-bearing: a Deno fetch
 * TypeError's `.message` embeds the request URL, which carries the bot
 * token (`https://api.telegram.org/bot<TOKEN>/sendMessage`). Only `.name`
 * (via telegramErrorSummary) is ever allowed to leave this module — never
 * the raw error, never String(err).
 */

export const TELEGRAM_MAX_CHARS = 4096;

/** Telegram `parse_mode: "HTML"` treats these three as markup. */
export function escapeHtml(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

/** Caps text at TELEGRAM_MAX_CHARS, appending a truncation marker if trimmed. */
export function truncateForTelegram(text: string): string {
  if (text.length <= TELEGRAM_MAX_CHARS) return text;
  const marker = "\n… (truncated)";
  return text.slice(0, TELEGRAM_MAX_CHARS - marker.length) + marker;
}

/** The name of an error and NOTHING else — see module header. */
export function telegramErrorSummary(err: unknown): string {
  const name = err instanceof Error ? err.name : typeof err;
  return `telegram send threw ${name}`;
}

export async function sendTelegram(
  token: string,
  chatId: string,
  text: string,
): Promise<{ ok: true } | { ok: false; summary: string }> {
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: truncateForTelegram(text),
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
