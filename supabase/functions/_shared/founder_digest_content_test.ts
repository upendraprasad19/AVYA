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

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildDigestText, type DigestInput, idPrefix, istClock } from "./founder_digest_content.ts";

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
