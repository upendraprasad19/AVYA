import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { pickStreakMessage } from "./message.ts";

Deno.test("pickStreakMessage: day 7 milestone", () => {
  const r = pickStreakMessage({ streakDays: 7, streakWeeks: 1, weight: null, targetWeight: null });
  assertEquals(r.title, "1 week strong!");
  assertEquals(r.message, "You've hit 7 days straight — that's the hardest week done. Don't stop now!");
});

Deno.test("pickStreakMessage: day 14 milestone", () => {
  const r = pickStreakMessage({ streakDays: 14, streakWeeks: 2, weight: null, targetWeight: null });
  assertEquals(r.title, "2 weeks! You're building a habit.");
  assertEquals(r.message, "14 days of consistency. Most people quit by now — you didn't. Keep going!");
});

Deno.test("pickStreakMessage: day 30 milestone", () => {
  const r = pickStreakMessage({ streakDays: 30, streakWeeks: 4, weight: null, targetWeight: null });
  assertEquals(r.title, "30-day warrior!");
});

Deno.test("pickStreakMessage: day 50 milestone", () => {
  const r = pickStreakMessage({ streakDays: 50, streakWeeks: 7, weight: null, targetWeight: null });
  assertEquals(r.title, "50 days. Legendary.");
});

Deno.test("pickStreakMessage: day 100 milestone", () => {
  const r = pickStreakMessage({ streakDays: 100, streakWeeks: 14, weight: null, targetWeight: null });
  assertEquals(r.title, "100-DAY STREAK!");
});

Deno.test("pickStreakMessage: every-10-day milestone (e.g. 60) uses the templated title/message", () => {
  const r = pickStreakMessage({ streakDays: 60, streakWeeks: 8, weight: null, targetWeight: null });
  assertEquals(r.title, "60-day milestone!");
  assertEquals(r.message, "60 days of showing up. That's elite. Don't let today be the one you miss.");
});

Deno.test("pickStreakMessage: near goal weight (within 2kg) takes priority over the standard nudge", () => {
  const r = pickStreakMessage({ streakDays: 12, streakWeeks: 1, weight: 70, targetWeight: 71 });
  assertEquals(r.title, "Almost at your goal weight!");
});

Deno.test("pickStreakMessage: standard nudge rotates through 4 variants by streakDays % 4, title fixed", () => {
  const seen = new Set<string>();
  for (const days of [12, 13, 22, 23]) {
    const r = pickStreakMessage({ streakDays: days, streakWeeks: 2, weight: null, targetWeight: null });
    assertEquals(r.title, "Don't break your streak!");
    seen.add(r.message);
  }
  assertEquals(seen.size, 4);
});

Deno.test("streak-guardian no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from streak-guardian/index.ts");
  }
});
