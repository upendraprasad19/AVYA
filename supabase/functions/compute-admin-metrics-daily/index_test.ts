/**
 * Deno unit tests for `compute-admin-metrics-daily`'s pure snapshot-row builder.
 *
 * Run:
 *   deno test --allow-env supabase/functions/compute-admin-metrics-daily/index_test.ts
 *
 * Scope: pure-function tests of `buildSnapshotRow`, following the
 * log-client-error/index_test.ts convention — the serve handler is NOT
 * exercised here (needs live SUPABASE_URL + service-role env + the deployed
 * public.founder_metrics_*() functions). End-to-end verification is the
 * manual smoke test in the plan's Verification section.
 */

import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildSnapshotRow } from "./index.ts";

const GROWTH = {
  total_users: 13,
  signups_today_ist: 1,
  signups_7d: 2,
  signups_30d: 5,
  pro_active: 6,
  pro_expired: 1,
  free_users: 7,
  active_subscriptions: 5,
  active_last_7d: 9,
  generated_at: "2026-07-12T18:15:00Z",
};
const ENGAGEMENT = {
  workouts_logged_today: 4,
  food_logs_today: 6,
  ai_messages_today: 20,
  streak_maintained_current_week: 3,
  generated_at: "2026-07-12T18:15:00Z",
};
const OPS = {
  client_errors_today: 12,
  client_errors_7d: 90,
  open_alerts_count: 2,
  cron_failures_24h: 0,
  generated_at: "2026-07-12T18:15:00Z",
};

Deno.test("buildSnapshotRow merges all three sources under snapshot_date, dropping the per-source generated_at fields", () => {
  const row = buildSnapshotRow("2026-07-12", GROWTH, ENGAGEMENT, OPS);
  assertEquals(row.snapshot_date, "2026-07-12");
  assertEquals(row.total_users, 13);
  assertEquals(row.workouts_logged_today, 4);
  assertEquals(row.client_errors_today, 12);
  assertEquals("generated_at" in row, false);
});

Deno.test("buildSnapshotRow carries every documented column through untouched", () => {
  const row = buildSnapshotRow("2026-07-12", GROWTH, ENGAGEMENT, OPS);
  assertEquals(row.signups_today_ist, 1);
  assertEquals(row.signups_7d, 2);
  assertEquals(row.signups_30d, 5);
  assertEquals(row.pro_active, 6);
  assertEquals(row.pro_expired, 1);
  assertEquals(row.free_users, 7);
  assertEquals(row.active_subscriptions, 5);
  assertEquals(row.active_last_7d, 9);
  assertEquals(row.food_logs_today, 6);
  assertEquals(row.ai_messages_today, 20);
  assertEquals(row.streak_maintained_current_week, 3);
  assertEquals(row.client_errors_7d, 90);
  assertEquals(row.open_alerts_count, 2);
  assertEquals(row.cron_failures_24h, 0);
});

Deno.test("buildSnapshotRow defaults a null numeric field to 0, not null — a null in a trend chart silently breaks delta/divide math downstream", () => {
  const partialGrowth = { ...GROWTH, signups_today_ist: null };
  const row = buildSnapshotRow("2026-07-12", partialGrowth, ENGAGEMENT, OPS);
  assertEquals(row.signups_today_ist, 0);
});

Deno.test("buildSnapshotRow is pure — same inputs always produce the same output", () => {
  const a = buildSnapshotRow("2026-07-12", GROWTH, ENGAGEMENT, OPS);
  const b = buildSnapshotRow("2026-07-12", GROWTH, ENGAGEMENT, OPS);
  assertEquals(a, b);
});
