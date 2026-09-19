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

import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  bucketActivePlans,
  bucketSubscriptionsByExpiry,
  computeDerivedMrr,
  isAuthorizedAdminCaller,
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
