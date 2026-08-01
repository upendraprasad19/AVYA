/**
 * re-engagement — Brainstorm §5 trigger #8.
 *
 * Cron: 30 06 * * * (UTC) = 12:00 IST = noon IST daily. Mid-day to maximise
 * the chance the phone is on hand. Cron registration deferred to T6.
 *
 * Goal: nudge users who have gone silent for 3+ days. Two-path candidate
 * detection — both run in the same invocation, results unioned:
 *
 *   Path A (preferred) — coach_memory.dropout_risk_score >= 0.5. The
 *   nightly `compute_coach_signals_for_user` RPC populates this from a
 *   blend of workout frequency, chat silence, weigh-in gap and sleep
 *   averages. One read, multi-signal — strictly better than the raw
 *   per-table check.
 *
 *   Path B (fallback) — for users without a coach_memory row yet (the
 *   warmup gap before the nightly cron has run for them), one RPC
 *   (find_reengagement_silent_candidates, migration 117) computes the
 *   absence-of-activity set across workout_logs/nutrition_logs/weight_logs
 *   plus the last_active_at fast-path, all inside Postgres in one
 *   round-trip (OI-48, 2026-07-31 — was an O(all users) fetch + per-user
 *   3-table sequential-query loop before this).
 *
 * Tier: BOTH free + PRO. Re-engagement matters for everyone — there is
 * no monetisation logic gating the nudge. (Distinct from plateau-alert,
 * which is PRO-only retention.)
 *
 * Copy: single softest-possible message ("no judgment, just check in").
 * Brainstorm rule — coach asks, never tells. The full conversation
 * reset happens when the user taps in.
 *
 * Dedup: shouldSendProactive("re_engagement") gates one nudge per IST
 * day per user. So a user sitting at >3d silence won't get blasted
 * every noon — they get one nudge, then we hold until the next type.
 *
 * Privacy: respects coach_memory.private_mode (suppresses preferred
 * name; nudge still ships). Path B users have no preferred name to
 * suppress.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat, MODEL_FLASH } from "../_shared/gemini.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier, sanitizeJsonForPrompt } from "../_shared/sanitize_for_prompt.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import {
  fetchNotificationPrefs,
  isNotificationEnabled,
} from "../_shared/notification_prefs.ts";
import { fetchAllPages } from "../_shared/paged_fetch.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * Threshold tuned to "medium dropout risk" — the brainstorm spec calls
 * for action at 3 days silence. The compute_coach_signals formula
 * already weights silence heavily so 0.5 is the natural cut-off.
 */
const DROPOUT_THRESHOLD = 0.5;
const SILENCE_DAYS_FALLBACK = 3;

// The local POSTGREST_MAX_ROWS constant and the two saturation warnings that
// used it are gone: both candidate paths now page via `_shared/paged_fetch.ts`,
// so saturation can no longer occur and there is nothing left to warn about.
// The cap itself lives in that module (OI-79 closed).

/**
 * Pure projection of find_reengagement_silent_candidates' RPC rows into the
 * same {candidates, names} shape the old per-user loop built inline —
 * exported so it can be unit-tested independently of the live-DB serve
 * handler, following the buildSnapshotRow / log-client-error convention
 * (see index_test.ts).
 */
export function mapFallbackCandidates(
  rows: Record<string, unknown>[],
): { candidates: string[]; names: Map<string, string | null> } {
  const candidates: string[] = [];
  const names = new Map<string, string | null>();
  for (const row of rows) {
    const userId = row.user_id as string;
    candidates.push(userId);
    names.set(userId, (row.full_name as string | null) ?? null);
  }
  return { candidates, names };
}

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // audit-2026-05-16 E.14.C — replaced inline env-equality JWT auth
  // (Test #16 P1-D drift class) with shared `isAuthorizedCronCall(req)`.
  // Survives Vault/env key rotation: verifies JWT signature against
  // SUPABASE_JWT_SECRET + role-claim === 'service_role'. CRON_SECRET
  // opaque-token escape hatch preserved inside the helper.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const requestId = crypto.randomUUID().split("-")[0];
  const logId = await logCronStart("re-engagement");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ──────────────────────────────────────────────────────────
    // PATH A — coach_memory.dropout_risk_score >= 0.5
    // ──────────────────────────────────────────────────────────
    // OI-79 CLOSED: paged. This read previously stopped at db-max-rows and only
    // logged a saturation warning (added by Unit 5, which detected the condition
    // without fixing it). `orderBy` is `user_id` because coach_memory's PK IS
    // user_id — it has no `id` column (verified live).
    //
    // The Path A / Path B error tagging (Hermes L34 F2) is preserved: the two
    // throws otherwise land in one catch and serialize identically, making a
    // regression in either path invisible without manual edge-log archaeology.
    // `fetchAllPages` already prefixes its own label, and the re-throw below
    // keeps the `path_a` token that cron_call_log.error_summary is read for.
    let memoryRows: Record<string, unknown>[];
    try {
      memoryRows = await fetchAllPages<Record<string, unknown>>(
        () =>
          supabase
            .from("coach_memory")
            .select(
              "user_id, dropout_risk_score, preferred_name, private_mode, signals_computed_at",
            )
            .gte("dropout_risk_score", DROPOUT_THRESHOLD)
            .not("signals_computed_at", "is", null),
        { orderBy: "user_id", label: "re-engagement path_a" },
      );
    } catch (memError) {
      throw new Error(
        `path_a coach_memory fetch failed: ${
          (memError as { message?: string } | null)?.message ?? String(memError)
        }`,
      );
    }

    const candidatesFromMemory = new Set<string>(
      memoryRows.map((r) => r.user_id as string),
    );
    const memoryById = new Map<string, Record<string, unknown>>(
      memoryRows.map((r) => [r.user_id as string, r]),
    );

    // ──────────────────────────────────────────────────────────
    // PATH B — fallback for users without coach_memory rows.
    //
    // OI-48 (2026-07-31, diagnose a4e1c9): replaced the O(all users) fetch +
    // per-user 3-table sequential-query loop (1 initial fetch + 3 per
    // silent user = 37 round-trips at 12 silent users, unbounded at scale)
    // with one Postgres RPC
    // (find_reengagement_silent_candidates, migration 117) expressing the
    // identical absence-check as NOT EXISTS anti-joins in one round-trip —
    // mirrors clean-orphan-media's find_orphan_chat_media shape (migration
    // 071), the closer structural precedent than protein-gap-alert's
    // batched positive-filter for an absence check specifically (this is an
    // anti-join, not a batchable positive filter). The per-row "on a read
    // error, skip this user" fail-closed behavior the old per-user loop
    // needed no longer has a direct analog — a single SQL statement cannot
    // partially fail per-row, so an RPC error now fails the whole Path B
    // fallback (and the whole cron invocation, matching the ALREADY-existing
    // behavior of the old code's initial batched `.from("users")` fetch
    // erroring, which also threw before reaching path A's candidates).
    // ──────────────────────────────────────────────────────────
    const cutoffMs = Date.now() - SILENCE_DAYS_FALLBACK * 86_400_000;
    const cutoffIso = new Date(cutoffMs).toISOString();
    const cutoffDate = cutoffIso.slice(0, 10); // YYYY-MM-DD

    // OI-79 CLOSED: paged. Unit 5 added a saturation WARNING here and left the
    // truncation itself in place, tracked as OI-79; this closes it. `.order()`
    // and `.range()` are accepted on /rpc/ set-returning functions, and paging
    // is correct whether or not db-max-rows applies to RPC responses (if it does
    // not, the loop simply ends on the first short page).
    //
    // Two corrections to what the removed comment here asserted, both measured
    // live 2026-08-01: the truncated response is **HTTP 200, not 206** (206 only
    // appears when the caller sends `Prefer: count=exact`, which supabase-js does
    // not do here) and its Content-Range total is `*`, so there is nothing in the
    // response to compare against; and the cited `morning-alert:583-594`
    // precedent is not a `.range()` loop at all — it passes p_offset/p_limit INTO
    // an RPC. The `.range()` precedent is morning-alert:790-810.
    //
    // The `path_b` error tag is load-bearing and preserved: this leg converted
    // Path B's old per-user "skip this user on read error" handling into a
    // single whole-invocation throw (one SQL statement cannot partially fail
    // per-row), so cron_call_log.error_summary is the ONLY durable record of a
    // Path B failure. A bare String(err) on a supabase-js PostgrestError (a
    // plain {message,details,hint,code} object, NOT an Error subclass) yields
    // "[object Object]" — the bug-class fixed at compute-coach-signals:92-98.
    let fallbackRows: Record<string, unknown>[];
    try {
      fallbackRows = await fetchAllPages<Record<string, unknown>>(
        () =>
          supabase.rpc("find_reengagement_silent_candidates", {
            p_cutoff_date: cutoffDate,
            p_cutoff_ts: cutoffIso,
            p_exclude_user_ids: Array.from(candidatesFromMemory),
          }),
        { orderBy: "user_id", label: "re-engagement path_b" },
      );
    } catch (fallbackErr) {
      throw new Error(
        `path_b find_reengagement_silent_candidates rpc failed: ${
          (fallbackErr as { message?: string } | null)?.message ??
            String(fallbackErr)
        }`,
      );
    }

    const { candidates: fallbackCandidates, names: fallbackNames } =
      mapFallbackCandidates(fallbackRows ?? []);

    const allCandidates = [
      ...Array.from(candidatesFromMemory),
      ...fallbackCandidates,
    ];

    if (allCandidates.length === 0) {
      console.log(
        `[re-engagement] request_id=${requestId} no candidates (path_a=0 path_b=0)`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(
        // Same key set as the main-path response below (Hermes L34 F4) —
        // prefs_off was missing here, so any consumer parsing both shapes
        // saw an inconsistent contract.
        JSON.stringify({
          status: "success",
          from_memory: 0,
          from_fallback: 0,
          sent: 0,
          prefs_off: 0,
          dedup_skipped: 0,
          errors: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Unit E — ONE batched, latest-desc read for the whole run.
    //
    // Batched matters most here: this loop already issues several queries per
    // candidate, so a per-user .single() would multiply round-trips on the
    // function with the largest candidate set.
    //
    // Latest-desc matters even more. This function targets people who have NOT
    // opened the app recently, so their newest snapshot can never be today's.
    // A today-pinned preference read would therefore be guaranteed inert here —
    // not merely usually inert, as it is elsewhere.
    const notifPrefs = await fetchNotificationPrefs(
      supabase,
      [...allCandidates],
    );

    let sent = 0;
    let dedupSkipped = 0;
    let prefsOff = 0;
    let errors = 0;

    for (const userId of allCandidates) {
      // User turned check-ins off. Before the dedup gate so an opted-out user
      // does not burn their one-per-day proactive slot on a discarded push.
      if (!isNotificationEnabled(notifPrefs, userId, "re_engagement")) {
        prefsOff++;
        continue;
      }

      // Dedup gate — one re_engagement push per user per IST day.
      const allow = await shouldSendProactive(supabase, userId, "re_engagement");
      if (!allow) {
        dedupSkipped++;
        continue;
      }

      // Resolve a first name without leaking PII through private_mode.
      // Path A users may have curated `preferred_name` in coach_memory;
      // path B users only have raw `full_name` from the users table.
      let firstName: string | null = null;
      const memory = memoryById.get(userId);
      if (memory) {
        const isPrivate = memory.private_mode === true;
        if (!isPrivate) {
          const preferred = memory.preferred_name as string | null;
          if (preferred && preferred.length > 0) {
            firstName = sanitizeIdentifier(preferred.split(" ")[0], { maxLen: 32 });
          }
        }
      } else {
        const fullName = fallbackNames.get(userId);
        if (fullName && fullName.length > 0) {
          firstName = sanitizeIdentifier(fullName.split(" ")[0], { maxLen: 32 });
        }
      }

      const greeting = firstName ? `${firstName} — ` : "";
      // Fallback: existing hardcoded English copy preserved as safety net.
      const fallbackMessage =
        `${greeting}haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.`;

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          first_name: firstName,
          silence_days_min: SILENCE_DAYS_FALLBACK,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${sanitizeJsonForPrompt(userState)}.\n\n` +
            `Generate a re-engagement nudge for a user who has been silent for ` +
            `${SILENCE_DAYS_FALLBACK}+ days. No judgment — the Captain asks, never tells.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[re-engagement] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: "Just checking in",
          message,
          screen: "/ai_coach",
        });
        if (ok) {
          // No local try around markProactiveSent, and none is needed: it
          // is non-throwing BY CONTRACT — `_shared/proactive_dedup.ts:87-95`
          // wraps its whole body in try/catch and only console.warns ("Non-
          // fatal on failure (the push already went out)"). All 9 sibling
          // cron functions call it bare after `sent++` for the same reason.
          // Hermes L34 F3 proposed wrapping it to stop a `sent`/`errors`
          // double-count; that double-count is UNREACHABLE (nothing can
          // throw here), and the wrapper was reverted after verifying the
          // helper rather than trusting the finding — a `mark_failures`
          // counter would have been a permanent 0, affirmatively asserting
          // "dedup bookkeeping never failed" while real failures are
          // swallowed inside the helper. That swallowing is a genuine
          // pre-existing observability gap, but it lives in the shared
          // helper's deliberate contract across 9 callers, not here.
          sent++;
          await markProactiveSent(supabase, userId, "re_engagement");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(`[re-engagement] send failed for ${userId}:`, e);
        errors++;
      }
    }

    console.log(
      `[re-engagement] request_id=${requestId} from_memory=${candidatesFromMemory.size} from_fallback=${fallbackCandidates.length} sent=${sent} prefs_off=${prefsOff} dedup_skipped=${dedupSkipped} errors=${errors}`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        status: "success",
        from_memory: candidatesFromMemory.size,
        from_fallback: fallbackCandidates.length,
        sent,
        prefs_off: prefsOff,
        dedup_skipped: dedupSkipped,
        errors,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error(`[re-engagement] request_id=${requestId}`, err);
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      requestId,
      // NOT a bare String(err): a supabase-js PostgrestError is a plain
      // {message, details, hint, code} object, not an Error subclass, so
      // String() yields "[object Object]" and the telemetry carries no
      // diagnostic content for exactly the failure it exists to surface.
      // Same guard as compute-coach-signals/index.ts:92-98 (Hermes L34 F1).
      errorSummary: (err as { message?: string } | null)?.message ??
        String(err),
    });
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
