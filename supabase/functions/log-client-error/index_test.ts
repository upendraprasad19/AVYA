/**
 * Deno unit tests for `log-client-error` priority-lane classifier.
 *
 * APK Test #16.1 / Theme D (2026-05-16) regression suite.
 *
 * Run:
 *   deno test --allow-env supabase/functions/log-client-error/index_test.ts
 *
 * Scope: pure-function tests of `isHighPriority` + the
 * `HIGH_PRIORITY_OP_TYPES` allowlist. The serve handler is NOT exercised
 * here — it requires `SUPABASE_URL` + service-role env vars and a live
 * `client_errors` table. End-to-end integration testing is deferred to
 * a manual `curl` after deploy (see deploy notes in CLAUDE.md §11).
 *
 * Contract: client + server allowlists must stay in lock-step. The Dart
 * suite `test/safety/error_telemetry_rate_limit_test.dart` pins the
 * same set on the client side.
 */

import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  DAILY_RATE_LIMIT,
  HIGH_PRIORITY_OP_TYPES,
  isHighPriority,
} from "./index.ts";

Deno.test("Theme D — DAILY_RATE_LIMIT is 2000", () => {
  assertStrictEquals(
    DAILY_RATE_LIMIT,
    2000,
    "Test #16.1 bumped the limit 100 → 2000. A future reduction below " +
      "200 (2× founder's worst pre-storm) is almost certainly a bug.",
  );
});

Deno.test("Theme D — crash_ prefix matches sample crash op_types", () => {
  assertStrictEquals(isHighPriority("crash_native_oom"), true);
  assertStrictEquals(isHighPriority("crash_dart_assert"), true);
  assertStrictEquals(isHighPriority("app_crash_isolate_died"), true);
});

Deno.test("Theme D — auth_failure_ prefix matches", () => {
  assertStrictEquals(isHighPriority("auth_failure_session_race"), true);
  assertStrictEquals(isHighPriority("auth_failure_jwt_expired"), true);
});

Deno.test("Theme D — exact-equality matchers", () => {
  assertStrictEquals(isHighPriority("42P10"), true);
  assertStrictEquals(isHighPriority("23505"), true);
  assertStrictEquals(isHighPriority("23502"), true);
  assertStrictEquals(isHighPriority("23503"), true);
  assertStrictEquals(isHighPriority("permission_denied"), true);
  assertStrictEquals(isHighPriority("guarded_box_disagreement"), true);
  assertStrictEquals(isHighPriority("hive_session_owner_mismatch"), true);
  assertStrictEquals(isHighPriority("sync_failure_dead_letter"), true);
  assertStrictEquals(isHighPriority("gate16_violation"), true);
});

Deno.test("Theme D — chatty LOW op_types do NOT match", () => {
  assertStrictEquals(
    isHighPriority("sync_skipped_null_natural_key"),
    false,
    "9f4ab2 defence-in-depth guard must be LOW — can fire thousands/day",
  );
  assertStrictEquals(
    isHighPriority("edge_function_cold_start_retry"),
    false,
    "Up to 3 retries per cold-start; must share the budget",
  );
  assertStrictEquals(isHighPriority("restore_started"), false);
  assertStrictEquals(isHighPriority("restore_completed"), false);
  assertStrictEquals(
    isHighPriority("subscription_refresh_success"),
    false,
    "Happy-path subscription events are pure noise relative to failures",
  );
});

Deno.test("Theme D — null + empty op_type → LOW", () => {
  assertStrictEquals(isHighPriority(null), false);
  assertStrictEquals(isHighPriority(""), false);
});

Deno.test("Theme D — case sensitivity (42p10 lowercase is LOW)", () => {
  // Mirrors the Dart-side test; both sides MUST agree to avoid a
  // server-inserts / client-drops split.
  assertStrictEquals(isHighPriority("42p10"), false);
});

Deno.test("Theme D — substring-not-prefix does NOT match", () => {
  // `auth_failure_` has a trailing `_` → must be a prefix.
  // `authentic_action` contains "auth" but is not prefixed by any
  // marker; must return LOW.
  assertStrictEquals(isHighPriority("authentic_action"), false);
});

Deno.test("Theme D — HIGH_PRIORITY_OP_TYPES is non-empty + contains core markers",
  () => {
    const set = new Set(HIGH_PRIORITY_OP_TYPES);
    // SQL state codes for bug-class signals.
    assertStrictEquals(set.has("42P10"), true);
    assertStrictEquals(set.has("23505"), true);
    assertStrictEquals(set.has("23502"), true);
    // Prefix markers (must include trailing `_`).
    assertStrictEquals(set.has("crash_"), true);
    assertStrictEquals(set.has("auth_failure_"), true);
    assertStrictEquals(set.has("writer_reader_drift_"), true);
    // Discipline gates.
    assertStrictEquals(set.has("gate16_violation"), true);
    assertStrictEquals(set.has("discipline_gate_violation"), true);
  });

Deno.test("Theme D — allowlist must stay reasonable in size", () => {
  // Sanity bound — over-classifying as HIGH defeats the rate limit.
  // If we ever cross ~30 entries, do an audit pass and consolidate.
  const max = 30;
  if (HIGH_PRIORITY_OP_TYPES.length > max) {
    throw new Error(
      `HIGH_PRIORITY_OP_TYPES has ${HIGH_PRIORITY_OP_TYPES.length} entries, ` +
        `exceeding the ${max}-entry sanity cap. Audit and consolidate ` +
        `before adding more — every HIGH entry bypasses the 2000/day budget.`,
    );
  }
  assertEquals(HIGH_PRIORITY_OP_TYPES.length <= max, true);
});
