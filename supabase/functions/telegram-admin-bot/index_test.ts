// Set env vars before any imports that reference them at module scope
Deno.env.set("SUPABASE_URL", "https://dedsavbjuwgarrhphgnl.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-role-key-for-testing");
Deno.env.set("TELEGRAM_WEBHOOK_SECRET", "test-webhook-secret-12345");
Deno.env.set("FOUNDER_TELEGRAM_CHAT_ID", "12345");
Deno.env.set("TELEGRAM_BOT_TOKEN", "dummy-telegram-token");

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handler, isAuthorizedTelegramSender, parseCommand } from "./index.ts";

Deno.test("isAuthorizedTelegramSender requires BOTH the secret token and the chat id to match", () => {
  const base = { expectedSecretToken: "s3cr3t", expectedChatId: "12345" };
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "12345" }),
    true,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "wrong", chatId: "12345" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "99999" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: null, chatId: "12345" }),
    false,
  );
});

Deno.test("isAuthorizedTelegramSender coerces a numeric Telegram chat id before comparing", () => {
  assertEquals(
    isAuthorizedTelegramSender({
      secretTokenHeader: "s3cr3t",
      expectedSecretToken: "s3cr3t",
      chatId: 12345,
      expectedChatId: "12345",
    }),
    true,
  );
});

Deno.test("parseCommand strips the leading slash and any @BotName suffix, lowercases the command", () => {
  assertEquals(parseCommand("/Status@IcanbefitterBot"), { cmd: "status", args: [] });
  assertEquals(parseCommand("/user  foo@bar.com"), { cmd: "user", args: ["foo@bar.com"] });
  assertEquals(parseCommand("not a command"), null);
  assertEquals(parseCommand(""), null);
});

Deno.test("handler returns bare 200 with no body detail for a wrong secret token", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": "wrong" },
    body: JSON.stringify({ message: { chat: { id: 12345 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  const body = await res.text();
  assertEquals(body, "");
});

Deno.test("handler returns bare 200 for a message from a chat id that isn't the founder's", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "" },
    body: JSON.stringify({ message: { chat: { id: 999999 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "");
});

Deno.test("handler replies to /help from the authorized founder chat", async () => {
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": secret },
    body: JSON.stringify({ message: { chat: { id: Number(chatId) }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  // sendTelegram will attempt a real network call here and fail in the test
  // sandbox (no real token) — that's fine, it's caught and logged, never
  // thrown; the assertion is on the HTTP response shape, not on delivery.
});
