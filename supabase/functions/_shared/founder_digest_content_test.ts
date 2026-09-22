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
  computeNewMrr,
  type DigestInput,
  idPrefix,
  istClock,
  readDigestSections,
  type SubscriptionRow,
} from "./founder_digest_content.ts";

/**
 * B1/B2/B3 (observation-batch-and-digest-redesign, 2026-09-21) added 7 new
 * required `DigestInput` fields. Every pre-existing fixture below predates
 * those fields and does not exercise them, so this spreads a neutral
 * "nothing to report" value for each — `{ rows: [] }` for the RPC sections
 * (renders "none", matching this file's own "never a silent zero, only an
 * explicit unreadable or an explicit none" convention), `{ count: 0 }` for
 * the two new windowed counts, and an empty Map for userNames (falls back to
 * the pre-existing id-prefix format for every user, unaffected by B2).
 */
const EMPTY_B_EXTRAS: Pick<
  DigestInput,
  | "signupsYesterday"
  | "adminMetrics"
  | "opsMetrics"
  | "engagementMetrics"
  | "userNames"
  | "cancelledYesterday"
  | "lapsedYesterday"
> = {
  signupsYesterday: { count: 0 },
  adminMetrics: { rows: [] },
  opsMetrics: { rows: [] },
  engagementMetrics: { rows: [] },
  userNames: new Map(),
  cancelledYesterday: { count: 0 },
  lapsedYesterday: { count: 0 },
};

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
    ...EMPTY_B_EXTRAS,
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
    ...EMPTY_B_EXTRAS,
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
    ...EMPTY_B_EXTRAS,
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "7d: 3");
  assertStringIncludes(text, "30d: 9");
  // B3: New MRR computed inline from these same subscriptions rows.
  // Hermes L1/L21 (2026-09-21): a yearly plan contributes its price DIVIDED
  // BY 12 — MRR is a monthly figure — 2×₹349 + ₹2999/12 = 698 + 249.9166...
  // = ₹947.9166... rounds to ₹948. This assertion previously said ₹3697
  // (the pre-fix bug's own output, from summing the yearly BOOKING price
  // raw) and would have silently stayed green forever, since nothing else
  // in this file exercised computeNewMrr in isolation — see the dedicated
  // computeNewMrr tests below for that isolated coverage.
  assertStringIncludes(text, "New MRR: ₹948");
});

Deno.test("buildDigestText renders 'none' for a quiet day with zero new subscriptions", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    windowed: { rows: [] },
    lifetime: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
    ...EMPTY_B_EXTRAS,
  };
  assertStringIncludes(buildDigestText(input), "none");
});

// ---------------------------------------------------------------------------
// computeNewMrr — isolated coverage (Hermes L1/L21, 2026-09-21). The ONLY
// pre-existing exercise of this function was through buildDigestText's
// rendered string, and that fixture's own expected value baked in the
// pre-fix bug's output (summing the yearly BOOKING price raw instead of
// dividing by 12) — it would have stayed green forever against a correct
// fix, since nothing else called this function directly. See the "New MRR"
// assertion above for how that was corrected.
// ---------------------------------------------------------------------------

function subRow(plan: string): SubscriptionRow {
  return { plan, created_at: "2026-09-12T10:00:00Z" };
}

Deno.test("computeNewMrr divides a yearly plan's price by 12 — MRR is a monthly figure", () => {
  const result = computeNewMrr([subRow("yearly")]);
  // 2999 / 12 = 249.9166... rounds to 250.
  assertEquals(result.rupees, 250);
  assertEquals(result.unknownPlanCount, 0);
});

Deno.test("computeNewMrr sums a monthly plan's price unmodified", () => {
  const result = computeNewMrr([subRow("monthly"), subRow("monthly")]);
  assertEquals(result.rupees, 698);
  assertEquals(result.unknownPlanCount, 0);
});

Deno.test("computeNewMrr mixes monthly (raw) and yearly (÷12) in one sum, rounding only the final total", () => {
  // Same fixture as the buildDigestText test above: 2×monthly + 1×yearly.
  const result = computeNewMrr([subRow("monthly"), subRow("monthly"), subRow("yearly")]);
  assertEquals(result.rupees, 948);
});

Deno.test("computeNewMrr treats referral_trial as a KNOWN zero-price plan, never counted as unknown", () => {
  const result = computeNewMrr([subRow("referral_trial"), subRow("monthly")]);
  // referral_trial contributes ₹0 and must not inflate unknownPlanCount —
  // it is a real, live plan value (4 active rows confirmed during the
  // Hermes pass), and the digest's own "add to PLAN_PRICES_RUPEES" warning
  // would otherwise tell the founder to price a free trial, silently
  // turning every future referral trial into booked revenue.
  assertEquals(result.rupees, 349);
  assertEquals(result.unknownPlanCount, 0);
});

Deno.test("computeNewMrr counts a genuinely unrecognized plan value as unknown, contributing ₹0", () => {
  const result = computeNewMrr([subRow("some_future_plan"), subRow("monthly")]);
  assertEquals(result.rupees, 349);
  assertEquals(result.unknownPlanCount, 1);
});

Deno.test("computeNewMrr returns zero/zero for an empty rows array", () => {
  const result = computeNewMrr([]);
  assertEquals(result.rupees, 0);
  assertEquals(result.unknownPlanCount, 0);
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
    ...EMPTY_B_EXTRAS,
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "unreadable");
});
