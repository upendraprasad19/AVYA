import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  escapeHtml,
  telegramErrorSummary,
  TELEGRAM_MAX_CHARS,
  truncateForTelegram,
} from "./telegram.ts";

Deno.test("escapeHtml escapes the 3 chars Telegram HTML parse_mode treats as markup", () => {
  assertEquals(escapeHtml("<b>a & b</b>"), "&lt;b&gt;a &amp; b&lt;/b&gt;");
});

Deno.test("truncateForTelegram leaves short text untouched", () => {
  assertEquals(truncateForTelegram("hello"), "hello");
});

Deno.test("truncateForTelegram caps at TELEGRAM_MAX_CHARS with a trailing marker", () => {
  const long = "x".repeat(TELEGRAM_MAX_CHARS + 500);
  const out = truncateForTelegram(long);
  assertEquals(out.length <= TELEGRAM_MAX_CHARS, true);
  assertEquals(out.endsWith("(truncated)"), true);
});

Deno.test("telegramErrorSummary never includes the error's own message (token-in-URL risk)", () => {
  const err = new TypeError("fetch failed: https://api.telegram.org/botSECRETTOKEN/sendMessage");
  const summary = telegramErrorSummary(err);
  assertEquals(summary.includes("SECRETTOKEN"), false);
  assertEquals(summary, "telegram send threw TypeError");
});
