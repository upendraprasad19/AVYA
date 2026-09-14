/**
 * Deno unit tests for the extracted digest content module (telegram-admin-bot
 * Task 4). This is a SMALL smoke suite over the module's public surface —
 * `idPrefix`, `istClock`, and the three-state rendering contract of
 * `buildDigestText`. The exhaustive behavioural coverage of `buildDigestText`
 * (counting, caps, top-users, alert truncation, escaping…) and of
 * `readDigestSections`/`gatherDigestInput`'s query shapes already lives in
 * `founder-digest/index_test.ts`, moved there to import from this module
 * instead of `./index.ts` — duplicating it here would just be two copies of
 * the same assertions to keep in sync.
 *
 * Note: the real `DigestInput` shape is `{ dayLabel, windowed, lifetime,
 * alerts }` (NOT the plan brief's illustrative `{ dayLabel, usage, alerts }`
 * — that shape does not exist in this codebase; adapted per Task 4's brief
 * Step 2 note to use the real interface).
 *
 * Run:
 *   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/founder_digest_content_test.ts
 */

import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildDigestText,
  type DigestInput,
  idPrefix,
  istClock,
  readDigestSections,
} from "./founder_digest_content.ts";

Deno.test("idPrefix returns the first 8 chars of a user id, never the whole uuid", () => {
  assertEquals(idPrefix("12345678-abcd-ef01-2345-6789abcdef01"), "12345678");
});

Deno.test("istClock renders HH:MM for an ISO instant", () => {
  // 2026-09-13T02:30:00Z = 08:00 IST
  assertEquals(istClock("2026-09-13T02:30:00.000Z"), "08:00 ");
});

Deno.test("buildDigestText renders 'none' for an empty-but-readable section, never a silent zero", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "none");
});

Deno.test("buildDigestText renders an explicit unreadable marker, never renders zeros for a failed read", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { unreadable: "connection reset" },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "unreadable");
  assertStringIncludes(text, "connection reset");
});

// --- Task 5: Subscriptions (new, yesterday) + Expiring soon sections ---
//
// The plan brief's illustrative fixtures use the sketch shape `{ dayLabel,
// usage, alerts }`; the real `DigestInput` (Task 4) is `{ dayLabel, windowed,
// lifetime, alerts, subscriptions, expiringSoon }`, so every fixture below
// carries `windowed`/`lifetime`/`alerts` too even though these tests don't
// exercise those sections.

Deno.test("buildDigestText renders a per-plan breakdown of yesterday's new subscriptions", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: {
      rows: [
        { plan: "monthly", created_at: "2026-09-12T10:00:00Z" },
        { plan: "monthly", created_at: "2026-09-12T11:00:00Z" },
        { plan: "yearly", created_at: "2026-09-12T12:00:00Z" },
      ],
    },
    expiringSoon: { count7d: 3, count30d: 9 },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "7d: 3");
  assertStringIncludes(text, "30d: 9");
});

Deno.test("buildDigestText renders 'none' for a quiet day with zero new subscriptions", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
  };
  assertStringIncludes(buildDigestText(input), "none");
});

// ---------------------------------------------------------------------------
// R2-15: the module is now called by BOTH founder-digest's daily cron AND
// telegram-admin-bot's /digest command. A section read-failure log line used
// to be hardcoded "[founder-digest]" regardless of who called it.
// ---------------------------------------------------------------------------

/** A fake client whose every builder rejects with `{table} unreadable`. */
function failingClient() {
  return {
    from(table: string) {
      const builder: Record<string, unknown> = {};
      for (const m of ["select", "eq", "gte", "lt", "order", "limit"]) {
        builder[m] = () => builder;
      }
      builder.then = (resolve: (v: unknown) => void) =>
        resolve({ data: null, error: { message: `${table} unreadable` }, count: null });
      return builder;
    },
  };
}

const WINDOW = { yStart: "2026-09-10T18:30:00.000Z", tStart: "2026-09-11T18:30:00.000Z" };

Deno.test("readDigestSections logs the REAL caller's label on a read failure, not a hardcoded one (R2-15)", async () => {
  const originalError = console.error;
  const logs: unknown[][] = [];
  console.error = (...args: unknown[]) => {
    logs.push(args);
  };
  try {
    // deno-lint-ignore no-explicit-any
    await readDigestSections(failingClient() as any, WINDOW, "telegram-admin-bot");
  } finally {
    console.error = originalError;
  }
  assert(
    logs.some((args) => String(args[0]).includes("[telegram-admin-bot] section read failed:")),
    `expected a "[telegram-admin-bot] section read failed:" log line, got ${JSON.stringify(logs)}`,
  );
  assert(
    !logs.some((args) => String(args[0]).includes("[founder-digest]")),
    `must never say "[founder-digest]" when the caller is telegram-admin-bot, got ${JSON.stringify(logs)}`,
  );
});

Deno.test("readDigestSections defaults the caller label to 'founder-digest' when omitted", async () => {
  const originalError = console.error;
  const logs: unknown[][] = [];
  console.error = (...args: unknown[]) => {
    logs.push(args);
  };
  try {
    // deno-lint-ignore no-explicit-any
    await readDigestSections(failingClient() as any, WINDOW);
  } finally {
    console.error = originalError;
  }
  assert(
    logs.some((args) => String(args[0]).includes("[founder-digest] section read failed:")),
    `expected the default "[founder-digest]" label, got ${JSON.stringify(logs)}`,
  );
});

Deno.test("buildDigestText renders an unreadable marker for a failed subscriptions read, never zeros", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { unreadable: "timeout" },
    expiringSoon: { unreadable: "timeout" },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "unreadable");
});
