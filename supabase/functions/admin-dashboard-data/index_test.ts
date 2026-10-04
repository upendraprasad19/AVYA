/**
 * Deno unit tests for `admin-dashboard-data`'s admin-gate + expiry-bucketing
 * pure functions.
 *
 * Run:
 *   deno test --allow-env supabase/functions/admin-dashboard-data/index_test.ts
 *
 * Scope: pure-function tests only, following the log-client-error/
 * index_test.ts convention. The serve handler is NOT exercised here (needs
 * live env + a real JWT). End-to-end verification is the manual smoke test
 * in the plan's Verification section (founder account -> 4 tabs render;
 * non-admin account -> clean "not authorized").
 */

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  bucketActivePlans,
  bucketSubscriptionsByExpiry,
  computeDerivedMrr,
  isAuthorizedAdminCaller,
  loadExpiryRows,
} from "./index.ts";

const ADMIN_UUID = "11111111-1111-1111-1111-111111111111";
const OTHER_UUID = "22222222-2222-2222-2222-222222222222";

Deno.test("isAuthorizedAdminCaller — service-role always passes, regardless of userId", () => {
  assertEquals(
    isAuthorizedAdminCaller({ isServiceRole: true, userId: null, adminUserIds: [] }),
    true,
  );
});

Deno.test("isAuthorizedAdminCaller — admin UUID in the allowlist passes", () => {
  assertEquals(
    isAuthorizedAdminCaller({
      isServiceRole: false,
      userId: ADMIN_UUID,
      adminUserIds: [ADMIN_UUID],
    }),
    true,
  );
});

Deno.test("isAuthorizedAdminCaller — authenticated but non-admin UUID is rejected", () => {
  assertEquals(
    isAuthorizedAdminCaller({
      isServiceRole: false,
      userId: OTHER_UUID,
      adminUserIds: [ADMIN_UUID],
    }),
    false,
  );
});

Deno.test("isAuthorizedAdminCaller — null userId (anon JWT / no session) is rejected, even with a non-empty allowlist", () => {
  assertEquals(
    isAuthorizedAdminCaller({
      isServiceRole: false,
      userId: null,
      adminUserIds: [ADMIN_UUID],
    }),
    false,
  );
});

Deno.test("isAuthorizedAdminCaller — fail-secure: empty allowlist rejects every authenticated caller", () => {
  assertEquals(
    isAuthorizedAdminCaller({
      isServiceRole: false,
      userId: ADMIN_UUID,
      adminUserIds: [],
    }),
    false,
  );
});

const NOW = new Date("2026-07-12T12:00:00Z");

function daysFromNow(days: number): string {
  return new Date(NOW.getTime() + days * 24 * 60 * 60 * 1000).toISOString();
}

const ROWS = [
  { user_id: "u-expired-30d", email: "a@x.com", subscription_expires_at: daysFromNow(-30) },
  { user_id: "u-expired-1d", email: "b@x.com", subscription_expires_at: daysFromNow(-1) },
  { user_id: "u-expiring-tomorrow", email: "c@x.com", subscription_expires_at: daysFromNow(1) },
  { user_id: "u-expiring-6d", email: "d@x.com", subscription_expires_at: daysFromNow(6.9) },
  { user_id: "u-expiring-10d", email: "e@x.com", subscription_expires_at: daysFromNow(10) },
  { user_id: "u-expiring-29d", email: "f@x.com", subscription_expires_at: daysFromNow(29) },
  { user_id: "u-expiring-90d", email: "g@x.com", subscription_expires_at: daysFromNow(90) },
];

Deno.test("bucketSubscriptionsByExpiry — sorts each row into exactly one of expired/expiring7d/expiring30d/beyond", () => {
  const buckets = bucketSubscriptionsByExpiry(ROWS, NOW);
  assertEquals(buckets.expired.map((r) => r.user_id), ["u-expired-30d", "u-expired-1d"]);
  assertEquals(
    buckets.expiring7d.map((r) => r.user_id),
    ["u-expiring-tomorrow", "u-expiring-6d"],
  );
  assertEquals(
    buckets.expiring30d.map((r) => r.user_id),
    ["u-expiring-10d", "u-expiring-29d"],
  );
  // u-expiring-90d belongs in none of the three buckets — not asserted
  // present anywhere above; total accounted-for rows is 6 of 7.
  const accountedFor = buckets.expired.length + buckets.expiring7d.length +
    buckets.expiring30d.length;
  assertEquals(accountedFor, 6);
});

Deno.test("bucketSubscriptionsByExpiry — boundary: expires_at exactly equal to `now` counts as expired, not expiring", () => {
  const buckets = bucketSubscriptionsByExpiry(
    [{ user_id: "u-exact", email: "x@x.com", subscription_expires_at: NOW.toISOString() }],
    NOW,
  );
  assertEquals(buckets.expired.length, 1);
  assertEquals(buckets.expiring7d.length, 0);
});

Deno.test("bucketSubscriptionsByExpiry — empty input returns empty buckets, not an error", () => {
  const buckets = bucketSubscriptionsByExpiry([], NOW);
  assertEquals(buckets.expired, []);
  assertEquals(buckets.expiring7d, []);
  assertEquals(buckets.expiring30d, []);
});

const PRICES = { monthlyInr: 349, yearlyInr: 2999 };

Deno.test("computeDerivedMrr — normalizes yearly plans to a monthly-equivalent (yearly price / 12), the standard MRR convention", () => {
  // 5 monthly @ 349 + 1 yearly @ 2999/12 = 1745 + 249.9166... = 1994.9166...
  const mrr = computeDerivedMrr({ monthlyActive: 5, yearlyActive: 1 }, PRICES);
  assertEquals(Math.round(mrr * 100) / 100, 1994.92);
});

Deno.test("computeDerivedMrr — zero active subscriptions of either plan is zero MRR, not NaN", () => {
  assertEquals(computeDerivedMrr({ monthlyActive: 0, yearlyActive: 0 }, PRICES), 0);
});

Deno.test("computeDerivedMrr — monthly-only matches simple multiplication", () => {
  assertEquals(computeDerivedMrr({ monthlyActive: 6, yearlyActive: 0 }, PRICES), 6 * 349);
});

// bucketActivePlans — mirrors the live distinct plan values (2026-07-13:
// {monthly, referral_trial}; yearly=0 rows today but a valid future plan).
Deno.test("bucketActivePlans — counts monthly / yearly / referral_trial into their own buckets", () => {
  const counts = bucketActivePlans([
    { plan: "monthly" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
    { plan: "yearly" },
  ]);
  assertEquals(counts, {
    monthlyActive: 1,
    yearlyActive: 1,
    trialActive: 2,
    otherActive: 0, // none unrecognized
  });
});

Deno.test("bucketActivePlans — the live-shape case: 1 monthly + 6 referral_trial reconciles to 7 active, MRR counts only the monthly", () => {
  const rows = [
    { plan: "monthly" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
    { plan: "referral_trial" },
  ];
  const counts = bucketActivePlans(rows);
  assertEquals(counts.monthlyActive, 1);
  assertEquals(counts.trialActive, 6);
  // Split reconciles against the active-sub total — no silently-dropped rows.
  assertEquals(
    counts.monthlyActive + counts.yearlyActive + counts.trialActive +
      counts.otherActive,
    rows.length,
  );
  // Trials pay nothing — MRR reflects only the 1 monthly.
  assertEquals(
    computeDerivedMrr(counts, PRICES),
    349,
  );
});

Deno.test("bucketActivePlans — an unforeseen plan value lands in otherActive, never silently dropped", () => {
  const counts = bucketActivePlans([
    { plan: "quarterly" },
    { plan: null },
    { plan: "monthly" },
  ]);
  assertEquals(counts.monthlyActive, 1);
  assertEquals(counts.otherActive, 2);
  assertEquals(
    counts.monthlyActive + counts.yearlyActive + counts.trialActive +
      counts.otherActive,
    3,
  );
});

Deno.test("bucketActivePlans — empty input returns all-zero counts, not an error", () => {
  assertEquals(bucketActivePlans([]), {
    monthlyActive: 0,
    yearlyActive: 0,
    trialActive: 0,
    otherActive: 0,
  });
});

// ── OI-202: loadExpiryRows derives the list from `subscriptions` ───────────

interface FakeSub {
  id: number;
  user_id: string;
  status: string;
  end_date: string;
}

/**
 * Filter-evaluating fake: `subscriptions` honours .eq(status) and .gte(end_date);
 * `users` honours .in(id). A wrong status filter, a missing floor, or an email
 * lookup keyed on the wrong column changes the answer.
 */
function adminFake(
  subs: FakeSub[],
  users: Array<{ id: string; email: string | null }>,
  opts: { subsError?: boolean; usersError?: boolean } = {},
) {
  const queried: string[] = [];
  return {
    queried,
    from(table: string) {
      queried.push(table);
      const filters: Array<[string, string, unknown]> = [];
      const b: Record<string, unknown> = {};
      b.select = () => b;
      b.eq = (c: string, v: unknown) => (filters.push(["eq", c, v]), b);
      b.gte = (c: string, v: unknown) => (filters.push(["gte", c, v]), b);
      b.in = (c: string, v: unknown) => (filters.push(["in", c, v]), b);
      b.order = () => b;
      b.range = (from: number, to: number) => {
        if ((table === "subscriptions" && opts.subsError) || (table === "users" && opts.usersError)) {
          return Promise.resolve({ data: null, error: { message: "boom" } });
        }
        const src: Array<Record<string, unknown>> = table === "subscriptions"
          ? subs as unknown as Array<Record<string, unknown>>
          : users as unknown as Array<Record<string, unknown>>;
        const rows = src.filter((r) =>
          filters.every(([op, c, v]) =>
            op === "eq"
              ? r[c] === v
              : op === "gte"
              ? String(r[c]) >= String(v)
              : (v as unknown[]).includes(r[c])
          )
        );
        return Promise.resolve({ data: rows.slice(from, to + 1), error: null });
      };
      return b;
    },
  };
}

const FLOOR = daysFromNow(-30);
const WINDOW = daysFromNow(30);

Deno.test("loadExpiryRows — latest active end per user, in [floor, window], with emails from users", async () => {
  const fake = adminFake(
    [
      // lapsed 5d ago, never renewed -> listed
      { id: 1, user_id: "u-lapsed", status: "active", end_date: daysFromNow(-5) },
      // renewed: old row lapsed 3d ago, NEW row 60d out -> NOT listed at all
      // (its latest end is beyond the window)
      { id: 2, user_id: "u-renewed", status: "active", end_date: daysFromNow(-3) },
      { id: 3, user_id: "u-renewed", status: "active", end_date: daysFromNow(60) },
      // expiring in 4d -> listed
      { id: 4, user_id: "u-soon", status: "active", end_date: daysFromNow(4) },
      // cancelled row must never count, however recent
      { id: 5, user_id: "u-cancelled", status: "cancelled", end_date: daysFromNow(2) },
      // lapsed 90d ago -> below the floor, not fetched
      { id: 6, user_id: "u-ancient", status: "active", end_date: daysFromNow(-90) },
    ],
    [
      { id: "u-lapsed", email: "lapsed@x.com" },
      { id: "u-soon", email: "soon@x.com" },
      { id: "u-renewed", email: "renewed@x.com" },
    ],
  );
  const rows = await loadExpiryRows(fake, FLOOR, WINDOW);
  assertEquals(
    rows!.map((r) => [r.user_id, r.email]).sort(),
    [["u-lapsed", "lapsed@x.com"], ["u-soon", "soon@x.com"]],
  );
  // The response key stays `subscription_expires_at` (the Flutter model reads it).
  assertEquals(
    rows!.find((r) => r.user_id === "u-soon")!.subscription_expires_at,
    daysFromNow(4),
  );
  // and it composes with the existing pure bucketer:
  const buckets = bucketSubscriptionsByExpiry(rows!, NOW);
  assertEquals(buckets.expired.map((r) => r.user_id), ["u-lapsed"]);
  assertEquals(buckets.expiring7d.map((r) => r.user_id), ["u-soon"]);
  assertEquals(buckets.expiring30d, []);
});

Deno.test("loadExpiryRows — the window is CLOSED at both ends: end == floor and end == window are listed", async () => {
  const fake = adminFake(
    [
      { id: 1, user_id: "u-floor", status: "active", end_date: FLOOR },
      { id: 2, user_id: "u-top", status: "active", end_date: WINDOW },
      { id: 3, user_id: "u-past-top", status: "active", end_date: new Date(new Date(WINDOW).getTime() + 1000).toISOString() },
    ],
    [],
  );
  const rows = await loadExpiryRows(fake, FLOOR, WINDOW);
  assertEquals(rows!.map((r) => r.user_id).sort(), ["u-floor", "u-top"]);
});

Deno.test("loadExpiryRows — a user with no users row still appears, email null", async () => {
  const fake = adminFake(
    [{ id: 1, user_id: "u-orphan", status: "active", end_date: daysFromNow(3) }],
    [],
  );
  const rows = await loadExpiryRows(fake, FLOOR, WINDOW);
  assertEquals(rows, [{ user_id: "u-orphan", email: null, subscription_expires_at: daysFromNow(3) }]);
});

Deno.test("loadExpiryRows — the users lookup selects only id, email (never a dropped mirror column)", async () => {
  const selects: Array<[string, string]> = [];
  const base = adminFake(
    [{ id: 1, user_id: "u1", status: "active", end_date: daysFromNow(3) }],
    [{ id: "u1", email: "a@x.com" }],
  );
  const wrapped = {
    from(table: string) {
      const b = base.from(table);
      const origSelect = b.select as () => unknown;
      b.select = (cols: string) => {
        selects.push([table, cols]);
        return origSelect();
      };
      return b;
    },
  };
  await loadExpiryRows(wrapped, FLOOR, WINDOW);
  const userSelects = selects.filter(([t]) => t === "users").map(([, c]) => c);
  assertEquals(userSelects.length >= 1, true);
  for (const c of userSelects) assertEquals(c, "id, email");
  const subSelects = selects.filter(([t]) => t === "subscriptions").map(([, c]) => c);
  assertEquals(subSelects.length >= 1, true);
  for (const c of subSelects) assertEquals(c, "user_id, end_date");
});

Deno.test("loadExpiryRows — returns null (NOT []) when the subscriptions read fails", async () => {
  const rows = await loadExpiryRows(adminFake([], [], { subsError: true }), FLOOR, WINDOW);
  assertEquals(rows, null);
});

Deno.test("loadExpiryRows — a failed email lookup throws (handler turns it into a 500)", async () => {
  const fake = adminFake(
    [{ id: 1, user_id: "u1", status: "active", end_date: daysFromNow(3) }],
    [],
    { usersError: true },
  );
  await assertRejects(() => loadExpiryRows(fake, FLOOR, WINDOW));
});
