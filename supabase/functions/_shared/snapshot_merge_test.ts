// supabase/functions/_shared/snapshot_merge_test.ts
//
// Pure-function regression test for diagnose d8a2f6 (recurrence of
// e4a1b7/OI-98 on `morning_alert`). Mutation-proven: swapping the
// implementation back to `return incoming;` (the pre-fix behaviour daily-
// snapshot/index.ts had) reddens every test below except the two that only
// assert client-owned-key behaviour, which is exactly the class this test
// suite exists to catch.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mergeSnapshotJson } from "./snapshot_merge.ts";

Deno.test("mergeSnapshotJson preserves a server-cron-owned key the incoming payload never mentions", () => {
  const existing = {
    morning_alert: "Recruit, stand by.",
    morning_alert_type: "pro_light",
    today_workout: { status: "planned" },
  };
  const incoming = {
    // A fresh client rebuild never includes morning_alert — it isn't
    // Hive-derived data.
    today_workout: { status: "completed" },
  };

  const result = mergeSnapshotJson(existing, incoming);

  assertEquals(result.morning_alert, "Recruit, stand by.");
  assertEquals(result.morning_alert_type, "pro_light");
});

Deno.test("mergeSnapshotJson lets the incoming payload win on a key both sides carry", () => {
  const existing = { today_workout: { status: "planned" } };
  const incoming = { today_workout: { status: "completed" } };

  const result = mergeSnapshotJson(existing, incoming);

  assertEquals(result.today_workout, { status: "completed" });
});

Deno.test("mergeSnapshotJson handles a first-ever snapshot (no existing row)", () => {
  const incoming = { today_workout: { status: "planned" } };

  assertEquals(mergeSnapshotJson(null, incoming), incoming);
  assertEquals(mergeSnapshotJson(undefined, incoming), incoming);
});

Deno.test("mergeSnapshotJson round-trips the exact reported symptom: morning_alert survives a same-day client push", () => {
  // Mirrors the live sequence observed 2026-09-21: 02:00 IST generate writes
  // morning_alert; later that day the user opens the app and daily-snapshot
  // fires with a fresh Hive rebuild that has never heard of morning_alert.
  const afterGenerate = {
    morning_alert: "Free tier brief.",
    morning_alert_type: "free",
    morning_alert_generated_at: "2026-09-21T02:00:00.000Z",
  };
  const clientRebuildOnAppOpen = {
    today_workout: { status: "completed" },
    current_streak_days: 7,
  };

  const afterClientPush = mergeSnapshotJson(afterGenerate, clientRebuildOnAppOpen);

  assertEquals(afterClientPush.morning_alert, "Free tier brief.");
  assertEquals(afterClientPush.today_workout, { status: "completed" });
});
