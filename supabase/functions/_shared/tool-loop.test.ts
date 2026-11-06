import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { capCoachHistory, repairHistoryAlternation } from "./tool-loop.ts";

// Unit 2 — coach short-term memory. Behavioral tests for the two server-side
// history guards. `history` is CLIENT-CONTROLLED, so both guards treat it as
// untrusted: capCoachHistory bounds size (§4.4 rule 18) and
// repairHistoryAlternation makes it strictly alternating (so Gemini never 400s
// on consecutive same-role `contents`).

// ── repairHistoryAlternation ────────────────────────────────────────────────

Deno.test("repair — clean alternating history passes through unchanged", () => {
  const h = [
    { role: "user", text: "u1" },
    { role: "model", text: "m1" },
    { role: "user", text: "u2" },
    { role: "model", text: "m2" },
  ];
  assertEquals(repairHistoryAlternation(h), h);
});

Deno.test("repair — drops a leading model turn (must open on user)", () => {
  const h = [
    { role: "model", text: "stray" },
    { role: "user", text: "u1" },
    { role: "model", text: "m1" },
  ];
  assertEquals(repairHistoryAlternation(h), [
    { role: "user", text: "u1" },
    { role: "model", text: "m1" },
  ]);
});

Deno.test("repair — drops a trailing user turn (must close on model)", () => {
  const h = [
    { role: "user", text: "u1" },
    { role: "model", text: "m1" },
    { role: "user", text: "danglingUser" },
  ];
  assertEquals(repairHistoryAlternation(h), [
    { role: "user", text: "u1" },
    { role: "model", text: "m1" },
  ]);
});

Deno.test("repair — collapses consecutive same-role, keeping the latest", () => {
  const h = [
    { role: "user", text: "u1a" },
    { role: "user", text: "u1b" },
    { role: "model", text: "m1" },
  ];
  assertEquals(repairHistoryAlternation(h), [
    { role: "user", text: "u1b" },
    { role: "model", text: "m1" },
  ]);
});

Deno.test("repair — drops empty/whitespace-only turns", () => {
  const h = [
    { role: "user", text: "   " },
    { role: "user", text: "real" },
    { role: "model", text: "" },
    { role: "model", text: "reply" },
  ];
  assertEquals(repairHistoryAlternation(h), [
    { role: "user", text: "real" },
    { role: "model", text: "reply" },
  ]);
});

Deno.test("repair — empty/garbage input yields []", () => {
  assertEquals(repairHistoryAlternation([]), []);
  // deno-lint-ignore no-explicit-any
  assertEquals(repairHistoryAlternation(undefined as any), []);
  // all-user history reduces to [] (nothing can close on a model turn)
  assertEquals(
    repairHistoryAlternation([
      { role: "user", text: "a" },
      { role: "user", text: "b" },
    ]),
    [],
  );
});

// ── capCoachHistory ─────────────────────────────────────────────────────────

Deno.test("cap — non-array input yields []", () => {
  assertEquals(capCoachHistory(null), []);
  assertEquals(capCoachHistory({}), []);
  assertEquals(capCoachHistory("nope"), []);
});

Deno.test("cap — normalizes role/text and drops empties", () => {
  const out = capCoachHistory([
    { role: "user", text: "hi" },
    { role: "weird", text: "coerced-to-user" },
    { role: "model", text: "" },
    { text: "no-role" },
    { role: "model" },
  ]);
  assertEquals(out, [
    { role: "user", text: "hi" },
    { role: "user", text: "coerced-to-user" },
    { role: "user", text: "no-role" },
  ]);
});

Deno.test("cap — clamps per-entry length", () => {
  const out = capCoachHistory([{ role: "user", text: "x".repeat(5000) }], {
    maxCharsPerEntry: 100,
  });
  assertEquals(out.length, 1);
  assertEquals(out[0].text.length, 100);
});

Deno.test("cap — keeps only the most-recent maxEntries", () => {
  const many = Array.from({ length: 20 }, (_, i) => ({
    role: i % 2 === 0 ? "user" : "model",
    text: `t${i}`,
  }));
  const out = capCoachHistory(many, { maxEntries: 16 });
  assertEquals(out.length, 16);
  assertEquals(out[0].text, "t4"); // 0..3 dropped
  assertEquals(out[out.length - 1].text, "t19");
});

Deno.test("cap — drops OLDEST first to meet the total char budget", () => {
  const entries = [
    { role: "user", text: "A".repeat(100) },
    { role: "model", text: "B".repeat(100) },
    { role: "user", text: "C".repeat(100) },
  ];
  const out = capCoachHistory(entries, { maxTotalChars: 150 });
  // Two oldest (200 chars) exceed 150 → drop from front until ≤150.
  assertEquals(out.length, 1);
  assertEquals(out[0].text[0], "C");
});

// ── integration: cap → repair (the production order of operations) ───────────

Deno.test("cap then repair — oldest-first truncation can't leave an un-repaired break", () => {
  // A cap that drops the oldest user turn would leave a leading model turn;
  // repair (run AFTER cap in production) removes it.
  const capped = capCoachHistory(
    [
      { role: "user", text: "A".repeat(100) },
      { role: "model", text: "B".repeat(100) },
      { role: "user", text: "C".repeat(100) },
      { role: "model", text: "D".repeat(100) },
    ],
    { maxTotalChars: 250 },
  );
  // Oldest dropped until ≤250 → [model B? ...]; ensure repair fixes the open.
  const repaired = repairHistoryAlternation(capped);
  if (repaired.length > 0) {
    assertEquals(repaired[0].role, "user");
    assertEquals(repaired[repaired.length - 1].role, "model");
  }
});
