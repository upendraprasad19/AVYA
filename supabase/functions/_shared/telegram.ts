/**
 * telegram.ts — the hardened Telegram sender pattern for this project. Used
 * by alert-critical-notify (trigger-invoked) and telegram-admin-bot (webhook
 * replies) directly.
 *
 * ⚠ `founder-digest` does NOT import `sendTelegram` from here (review round
 * 1, F9 — this header previously claimed it did). It keeps its OWN sender
 * (`founder-digest/index.ts`) for two real reasons, not an unfinished
 * extraction: (1) an injectable `fetchImpl` its own secret-hygiene tests
 * need, and (2) — the load-bearing one — this module's `truncateForTelegram`
 * is a RAW character slice, while the digest's pre-formatted multi-line HTML
 * needs a LINE-boundary-aware cut or Telegram 400s the whole message on
 * unbalanced HTML (Hermes L21 P0; see `_shared/founder_digest_content.ts`'s
 * header). If you are "finishing" the DRY extraction by switching
 * founder-digest onto THIS sender, you are reintroducing that P0 — don't,
 * unless `truncateForTelegram` itself becomes line-boundary-aware first.
 *
 * The error-handling discipline here IS shared across all three senders
 * (this module's own, and founder-digest's twin): a Deno fetch TypeError's
 * `.message` embeds the request URL, which carries the bot token
 * (`https://api.telegram.org/bot<TOKEN>/sendMessage`). Only `.name` (via
 * telegramErrorSummary, exported from here and reused by founder-digest) is
 * ever allowed to leave either module — never the raw error, never
 * String(err).
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
