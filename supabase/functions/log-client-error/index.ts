/**
 * log-client-error — Sync failure + product event telemetry sink.
 *
 * Called by the Flutter SyncQueue on dead-letter (after all retries
 * for an operation have been exhausted) AND by ErrorTelemetry.logEvent
 * for structured product events. Transient failures that eventually
 * succeed are NOT reported here.
 *
 * Input:
 *   {
 *     error_code:     string (truncated at 64 chars; any non-empty value),
 *     error_message:  string | null,
 *     op_type:        string | null,    // e.g. "upsert_user_profile"
 *     retry_count:    int,              // how many attempts before dead-lettering
 *     client_version: string,           // "1.2.3+42" from package_info_plus
 *     platform:       "android" | "ios" | "web"
 *   }
 *
 * Output: { ok: true } or { ok: true, rate_limited: true, next_window_at: <iso> }
 *         or { error: "<reason>" }
 *
 * Rate limit (Test #16.1 / Theme D, 2026-05-16):
 *   - DAILY_RATE_LIMIT = 2000 events / user / 24 h (was 100).
 *   - Founder's worst-case 24h pre-Test-#16.1 was 47 unique events; 2000
 *     leaves a ~40× safety margin for a noisy bug class.
 *   - HIGH-priority op_types ALWAYS insert (rate limit bypassed). These
 *     are bug-class signals we must never lose: crashes, auth failures,
 *     known-bad SQL state codes, schema-shape violations.
 *   - LOW-priority chatty op_types share the 2000 budget.
 *   - When the limit IS hit, we return 200 with a distinguishable body
 *     `{ ok: true, rate_limited: true, next_window_at: <iso> }` so the
 *     client can suppress further low-priority POSTs until the window
 *     resets. Pre-Test-#16.1 the response was indistinguishable from a
 *     success, so the client kept spamming + we lost ALL signal once a
 *     user hit 100 events (founder hit 100 by 04:10 UTC 2026-05-15 from
 *     a 42P10 storm; subsequent +25 failures invisible).
 *
 * Reference:
 *   docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar D
 *   docs/diagnoses/2026-05-16-observability-silent-drop-<id>.md (Test #16.1)
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  clientError,
  corsHeaders,
  ok,
  serverError,
} from "../_shared/error.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// APK Test #12.2 / Task #3 — error_code validation widened.
//
// Pre-Test-#12.2 the validator required error_code ∈ a fixed whitelist
// (NetworkError / AuthError / ValidationError / SchemaError /
// RateLimitError / UnknownError). The Flutter client (sync_service.dart
// line 1727) sends `error.runtimeType.toString()` — Dart class names
// like `PostgrestException`, `FormatException`, `TimeoutException`,
// `SocketException`. ZERO overlap with the whitelist → every call
// returned 400 → `client_errors` table had 0 rows total → we were blind
// to all client-side sync failures for the entire app's lifetime.
//
// New rule: accept any non-empty string ≤ MAX_ERROR_CODE_CHARS chars.
// Truncate at the boundary (don't reject) so analytics gets data even
// when clients send slightly oversized strings. This trades type
// safety for visibility — once we have a corpus of real codes from
// production, we can add a normalization step on the client OR a
// canonicalization step here. Visibility now > taxonomy later.
const MAX_ERROR_CODE_CHARS = 64;

const VALID_PLATFORMS = new Set(["android", "ios", "web"]);

const MAX_MESSAGE_CHARS = 2000;
const MAX_OP_TYPE_CHARS = 64;
const MAX_CLIENT_VERSION_CHARS = 32;

// APK Test #16.1 / Theme D — daily budget bumped 100 → 2000.
//
// Pre-Test-#16.1 budget was 100 events/user/24h. Founder hit 100 by
// 04:10 UTC 2026-05-15 from a 42P10 storm; the function then returned
// 200 {rate_limited: true} for every subsequent call but DID NOT
// INSERT. ~hundreds of 200 responses logged with ZERO new rows — we
// were blind to all +25 failures for the rest of the day. 47 unique
// events was the previous worst pre-storm; 2000 leaves a ~40× margin.
const DAILY_RATE_LIMIT = 2000;

// APK Test #16.1 / Theme D — priority lanes.
//
// HIGH-priority op_types ALWAYS insert, even past the rate limit.
// Rationale: these are the signals we explicitly designed the telemetry
// pipeline to capture — crash classes, auth failures, known-bad SQL
// state codes that indicate schema regressions, and the discipline-gate
// violations from `/build-apk`. If a user is producing 2000 of these in
// 24h, we have a P0 incident and need every sample we can get.
//
// LOW-priority op_types (everything else) share the 2000/day budget.
// Examples of LOW: `sync_skipped_null_natural_key` (chatty
// defence-in-depth guard), `edge_function_cold_start_retry` (one event
// per cold-start retry — can be 4× per user-action), and the noisy
// `_telemetry_queue_drain_*` heartbeats from SyncQueue.
//
// Adding a new op_type:
//   - DEFAULT to LOW. Only add to HIGH_PRIORITY_OP_TYPES if it's a P0
//     signal class. Over-classifying as HIGH defeats the rate limit.
//   - Matching is case-sensitive prefix-or-equality. `crash_` matches
//     `crash_native_oom`, `crash_dart_assert`, etc. A literal value
//     (no trailing `_`) matches only an exact equality.
//
// Risk: false-positive HIGH classifications can spam the table from a
// runaway client. We mitigate by (a) keeping the list small and
// curated, (b) the client still respects `rate_limited: true` in the
// response and stops posting LOW events, but HIGH events ALWAYS go
// through — the server-side priority lane is the final arbiter.
const HIGH_PRIORITY_OP_TYPES: readonly string[] = [
  // Crash classes — ErrorWidget.builder + Crashlytics non-fatals.
  "crash_",
  "app_crash_",
  "isolate_unhandled_",

  // Auth failures — sign-in/up, session race, cross-account guard.
  "auth_failure_",
  "auth_signed_out_unexpected",
  "guarded_box_disagreement",
  "hive_session_owner_mismatch",

  // Known-bad SQL state codes (Postgres) — schema regressions.
  "42P10", // invalid_column_reference (onConflict mismatch)
  "23502", // not_null_violation
  "23505", // unique_violation (when surfaced as a bug, not idempotent retry)
  "23503", // foreign_key_violation
  "permission_denied",
  "unique_violation",

  // /build-apk discipline-gate violations — these block CI.
  "gate16_violation",
  "discipline_gate_violation",

  // Bug-class triggers — NEW failure modes we must never miss.
  "bug_class_new_",
  "writer_reader_drift_",
  "sync_failure_dead_letter", // SyncQueue dead-letter — always P1+

  // Streak-freeze lifecycle — money-relevant + once-per-lifecycle (Hermes L37,
  // f9d2e7). MUST stay in sync with the client highPriorityOpTypes (twin test).
  "streak_freeze_first_pro_grant",
  "streak_freeze_lapse_reset",

  // Cross-device optimistic-lock drop events (Hermes C8, 2026-07-30) — MUST
  // stay in sync with the client highPriorityOpTypes (twin test).
  "sync_freezes_retry_dropped",
  "sync_user_progress_retry_dropped",
  "sync_freezes_row_absent_after_conflict",
  "sync_user_progress_row_absent_after_conflict",

  // Restore-side monotonic guard (OI-83 / d1f6b3, 2026-08-03) — MUST stay in
  // sync with the client highPriorityOpTypes (twin test).
  "progress_restore_demotion_declined",
  "progress_restore_field_malformed",

  // Declined-advance stale-rows signal (OI-85) — the frequency measurement that
  // decides whether a repair gets built. MUST stay in sync with the client.
  "phase_advance_declined_rows_stale",
];

function isHighPriority(opType: string | null): boolean {
  if (opType == null || opType.length === 0) return false;
  for (const marker of HIGH_PRIORITY_OP_TYPES) {
    if (marker.endsWith("_")) {
      // Prefix match.
      if (opType.startsWith(marker)) return true;
    } else {
      // Exact equality.
      if (opType === marker) return true;
    }
  }
  return false;
}

/**
 * Compute the next ISO timestamp when the user's rate-limit window will
 * have rolled — defined as 24h after the OLDEST event currently inside
 * the 24h window. This is a tighter bound than `now + 24h` (which would
 * over-suppress the client) but still safe: by `next_window_at` we are
 * guaranteed to have at least one slot freed.
 *
 * Returns null when the count query gave us no rows (caller should fall
 * back to `now + 1h` on the client side, matching the cooldown TTL
 * default in `error_telemetry.dart`).
 */
async function nextWindowAt(
  supabase: SupabaseClient,
  userId: string,
  since: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("client_errors")
    .select("created_at")
    .eq("user_id", userId)
    .gte("created_at", since)
    .order("created_at", { ascending: true })
    .limit(1);
  if (error || !data || data.length === 0) return null;
  const oldest = new Date(data[0].created_at as string);
  return new Date(oldest.getTime() + 24 * 60 * 60 * 1000).toISOString();
}

// Exported handler so unit tests can import without starting a server.
// `serve(handler)` at the bottom of the file is gated by
// `import.meta.main` so importing this module from `index_test.ts`
// only loads the pure helpers + handler reference, not the server.
export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return clientError("Method not allowed", 405);
  }

  try {
    // Manual JWT verification (verify_jwt: true also set in config, belt+braces).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return clientError("Missing authorization header", 401);
    }

    const supabaseAuth = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAuth.auth
      .getUser(token);

    if (authError || !user) {
      return clientError("Invalid or expired token", 401);
    }

    const body = await req.json();
    // APK Test #12.2 / Task #3 — truncate (don't reject) oversized
    // strings so we never lose telemetry on a noisy boundary case.
    const rawErrorCode = String(body?.error_code ?? "");
    const errorCode = rawErrorCode.length > MAX_ERROR_CODE_CHARS
      ? rawErrorCode.slice(0, MAX_ERROR_CODE_CHARS)
      : rawErrorCode;
    let errorMessage = body?.error_message == null
      ? null
      : String(body.error_message);
    if (errorMessage != null && errorMessage.length > MAX_MESSAGE_CHARS) {
      errorMessage = errorMessage.slice(0, MAX_MESSAGE_CHARS);
    }
    let opType = body?.op_type == null ? null : String(body.op_type);
    if (opType != null && opType.length > MAX_OP_TYPE_CHARS) {
      opType = opType.slice(0, MAX_OP_TYPE_CHARS);
    }
    const retryCount = Number.isFinite(body?.retry_count)
      ? Number(body.retry_count)
      : 0;
    const clientVersion = String(body?.client_version ?? "");
    const platform = String(body?.platform ?? "");

    // Validation — only reject what's truly unrecoverable. A 400 here
    // means we lose telemetry forever for that error event, which is
    // strictly worse than storing a noisy row.
    if (errorCode.length === 0) {
      return clientError("Missing error_code", 400);
    }
    if (!VALID_PLATFORMS.has(platform)) {
      return clientError("Invalid platform", 400);
    }
    if (!clientVersion || clientVersion.length > MAX_CLIENT_VERSION_CHARS) {
      return clientError("Invalid client_version", 400);
    }
    // error_message and op_type are now truncated above; never reject.
    if (retryCount < 0 || retryCount > 1000) {
      return clientError("Invalid retry_count", 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Per-user 24h rate limit. HIGH-priority op_types skip the count
    // query AND the budget gate — they always insert.
    const highPriority = isHighPriority(opType);
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    if (!highPriority) {
      const { count, error: countError } = await supabase
        .from("client_errors")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .gte("created_at", since);

      if (countError) {
        return serverError("log-client-error:count", countError);
      }
      if ((count ?? 0) >= DAILY_RATE_LIMIT) {
        // APK Test #16.1 / Theme D — distinguishable rate-limit signal.
        //
        // Pre-Test-#16.1 we returned `{ok: true, rate_limited: true}`
        // but no client honored it — every subsequent call still
        // crossed the network only to be dropped server-side. Now we
        // additionally return `next_window_at` (ISO) and the client
        // (`error_telemetry.dart`) sets an in-memory cooldown until
        // that timestamp so further LOW-priority calls short-circuit
        // before the network round-trip.
        //
        // We KEEP returning 200 (not 429) so the client's fire-and-
        // forget `.invoke` doesn't throw and crash unrelated flows;
        // the body shape is the contract.
        const nextWindow = await nextWindowAt(supabase, user.id, since);
        return ok({
          ok: true,
          rate_limited: true,
          next_window_at: nextWindow,
          priority_lane: "low",
        });
      }
    }

    const { error: insertError } = await supabase
      .from("client_errors")
      .insert({
        user_id: user.id,
        error_code: errorCode,
        error_message: errorMessage,
        op_type: opType,
        retry_count: retryCount,
        client_version: clientVersion,
        platform: platform,
      });

    if (insertError) {
      return serverError("log-client-error:insert", insertError);
    }

    // Surface priority lane in the success response so client tests +
    // ops can sanity-check classification without table scans.
    return ok({
      ok: true,
      priority_lane: highPriority ? "high" : "low",
    });
  } catch (err) {
    return serverError("log-client-error", err);
  }
};

// Only start the HTTP server when run as the main entrypoint (Deno
// deploy / `supabase functions serve`). Importing this module from
// `index_test.ts` skips serve() so tests can exercise pure helpers.
if (import.meta.main) {
  serve(handler);
}

// APK Test #16.1 / Theme D — exports for unit testing.
//
// Deno test runner can import these directly. The serve handler above
// is untouched; only pure helpers + constants are exposed.
export {
  DAILY_RATE_LIMIT,
  HIGH_PRIORITY_OP_TYPES,
  isHighPriority,
  MAX_OP_TYPE_CHARS,
};
