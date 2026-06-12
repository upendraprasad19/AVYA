// supabase/functions/delete-account/index.ts
// DPDP §17 hard erasure — full account deletion with Razorpay cancel, OneSignal
// unsubscribe, Storage purge, auth.users cascade, and audit log.
//
// Flow (order matters):
//   1. JWT auth via getUser (server-side verify, not just header)
//   2. Rate limit — 5 attempts per user per hour (audit Hermes-R2 #9, 7ad009)
//   3. Confirmation token check — body must have DELETE-MY-ACCOUNT-<uid8>
//   4. Razorpay subscription cancel — best-effort/NON-FATAL (a2c8e6): cancel-first
//      (protects user from post-deletion charges); a failure is RECORDED in
//      account_deletion_log.razorpay_cancel_status and the erasure PROCEEDS so a
//      Razorpay outage can't block a legally-required DPDP §17 deletion
//   5. OneSignal player unsub — best-effort, non-fatal
//   6. Storage purge (3 buckets) — best-effort, per-bucket errors logged
//   7. auth.users delete (service-role) — CASCADE through public.users + all FKs
//      (5 community surfaces get user_id = NULL per migration 049, not deleted)
//   8. Audit insert to account_deletion_log (no FK, survives auth delete)
//
// verify_jwt: true at deploy (user must be authenticated).
// Error sanitization: every non-200 returns { error: <code>, request_id: <8-hex> }.
// No PII in error response bodies.
//
// closes-diagnose: 7ad009 (audit Hermes-R2 #9 rate limit, 2026-05-11)
// closes-diagnose: e8a1c3 (JWT auth — service-role client + getUser(token); the prior
//   createClient(url, userJWT).getUser() rejected EVERY valid user token → 401. 2026-06-12 Obs#10)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// ── CORS headers (inline — no cors.ts in _shared for this project) ────────────
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Env vars — fail fast at startup if any are missing ──────────────────────
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID");
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET");
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY");

if (
  !SUPABASE_URL ||
  !SERVICE_ROLE ||
  !RAZORPAY_KEY_ID ||
  !RAZORPAY_KEY_SECRET ||
  !ONESIGNAL_APP_ID ||
  !ONESIGNAL_REST_API_KEY
) {
  console.error(
    "[delete-account] STARTUP FAILED — missing env vars:",
    {
      SUPABASE_URL: !!SUPABASE_URL,
      SERVICE_ROLE: !!SERVICE_ROLE,
      RAZORPAY_KEY_ID: !!RAZORPAY_KEY_ID,
      RAZORPAY_KEY_SECRET: !!RAZORPAY_KEY_SECRET,
      ONESIGNAL_APP_ID: !!ONESIGNAL_APP_ID,
      ONESIGNAL_REST_API_KEY: !!ONESIGNAL_REST_API_KEY,
    },
  );
  // Throw to fail the function startup — surfaces as 500 Internal Server Error
  throw new Error("[delete-account] required env vars not set");
}

// Rate-limit config (Hermes-R2 #9): 5 attempts per user per hour. Counted via
// `ai_coach_interactions` rows with channel='delete_account_attempt'. Mirrors
// the verify-payment rate-limit pattern.
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MINUTES = 60;

// ── Helper: sanitized error response (no PII, no stack traces) ───────────────
function jsonError(
  status: number,
  error: string,
  requestId: string,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(
    JSON.stringify({ error, request_id: requestId }),
    {
      status,
      headers: { ...corsHeaders, ...extraHeaders, "Content-Type": "application/json" },
    },
  );
}

// ── Main handler ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  // Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    const requestId = crypto.randomUUID().split("-")[0];
    return jsonError(405, "method_not_allowed", requestId);
  }

  const requestId = crypto.randomUUID().split("-")[0];

  try {
    // ── 1. JWT AUTH ──────────────────────────────────────────────────────────
    // Must re-validate server-side — never trust header alone.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.warn(`[delete-account] request_id=${requestId} missing auth header`);
      return jsonError(401, "unauthenticated", requestId);
    }

    // Validate the user's JWT explicitly via getUser(<token>) — confirms the token
    // is for a real authenticated user. Obs#10 (2026-06-12 live E2E): the prior
    // `createClient(SUPABASE_URL, <userJWT>).auth.getUser()` passed the USER JWT as
    // the supabaseKey, so the apikey header became the userJWT (which GoTrue
    // rejects) AND getUser() got no token to validate → EVERY valid user token got
    // 401 → DPDP §17 erasure was unreachable for ALL users. Mirror the working EFs
    // (daily-snapshot / ai-media-proxy / assess-body-composition): a service-role
    // client + getUser(token). Proven live: /auth/v1/user + ai-proxy accept the same
    // token (200) that the old delete-account path rejected (401, req 84b8f6ad).
    const token = authHeader.replace("Bearer ", "");
    const userClient = createClient(SUPABASE_URL as string, SERVICE_ROLE as string);
    const { data: userRes, error: userErr } = await userClient.auth.getUser(token);
    if (userErr || !userRes?.user) {
      console.warn(
        `[delete-account] request_id=${requestId} auth getUser failed:`,
        userErr?.message,
      );
      return jsonError(401, "unauthenticated", requestId);
    }
    const userId = userRes.user.id;

    // Admin client for all privileged operations below
    const admin = createClient(SUPABASE_URL as string, SERVICE_ROLE as string);

    // ── 2. RATE LIMIT (Hermes-R2 #9, 7ad009) ─────────────────────────────────
    // 5 attempts per user per hour. Counted via ai_coach_interactions rows
    // with channel='delete_account_attempt'. Prevents DoS where a malicious
    // actor knowing a target's 8-char user_id prefix repeatedly attempts
    // deletion (each attempt fires Razorpay + DB queries before the 400 reject).
    const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60_000).toISOString();
    const { count: attemptCount, error: rateErr } = await admin
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("channel", "delete_account_attempt")
      .gte("created_at", windowStart);

    if (rateErr) {
      // Fail-open: log + continue. We don't want a counter-query failure to
      // block account deletion. (Diff from verify-payment which fail-closes;
      // here the user is exercising a right, not making a payment.)
      console.warn(
        `[delete-account] request_id=${requestId} rate-limit query failed (fail-open):`,
        rateErr.message,
      );
    } else if ((attemptCount ?? 0) >= RATE_LIMIT_MAX) {
      console.warn(
        `[delete-account] request_id=${requestId} user=${userId} rate-limited:` +
          ` ${attemptCount}/${RATE_LIMIT_MAX} attempts in last ${RATE_LIMIT_WINDOW_MINUTES}min`,
      );
      return jsonError(
        429,
        "rate_limited",
        requestId,
        { "Retry-After": String(RATE_LIMIT_WINDOW_MINUTES * 60) },
      );
    }

    // Record this attempt (whether it succeeds or fails downstream). Fire-and-
    // forget; counter accuracy is best-effort.
    admin
      .from("ai_coach_interactions")
      .insert({
        user_id: userId,
        channel: "delete_account_attempt",
        prompt_snippet: `request_id=${requestId}`,
        response_snippet: null,
        model_used: "none",
      })
      .then(({ error }) => {
        if (error) {
          console.warn(
            `[delete-account] request_id=${requestId} attempt-counter insert failed (non-fatal):`,
            error.message,
          );
        }
      });

    // ── 3. CONFIRMATION TOKEN ────────────────────────────────────────────────
    // Prevents a stolen JWT replay from triggering deletion without also knowing
    // the user's own ID prefix. Body must contain exact token.
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonError(400, "invalid_request_body", requestId);
    }

    const expected = `DELETE-MY-ACCOUNT-${userId.substring(0, 8)}`;
    if (body.confirmation_token !== expected) {
      console.warn(
        `[delete-account] request_id=${requestId} user=${userId} confirmation_token_mismatch`,
      );
      return jsonError(400, "confirmation_token_mismatch", requestId);
    }

    console.log(
      `[delete-account] request_id=${requestId} user=${userId} confirmed — starting erasure`,
    );

    // ── 4. RAZORPAY CANCEL — best-effort, NON-FATAL (a2c8e6) ─────────────────
    // DPDP §17 erasure is a legal RIGHT that must NOT be indefinitely blocked by
    // an external dependency (a Razorpay API hiccup). Pre-fix ANY cancel failure
    // returned 502 and ABORTED the entire erasure — an external outage could
    // block a legally-required deletion. We still CANCEL FIRST (a healthy cancel
    // protects the user from post-deletion charges), but a FAILURE is now
    // RECORDED DURABLY in account_deletion_log.razorpay_cancel_status (no FK,
    // survives the auth delete) for out-of-band follow-up — the user is NOT
    // silently left subscribed — and the erasure PROCEEDS.
    let razorpayStatus = "no_active_sub";
    const cancelFailures: string[] = [];

    const { data: subs, error: subsErr } = await admin
      .from("subscriptions")
      .select("razorpay_subscription_id")
      .eq("user_id", userId)
      .eq("status", "active");

    if (subsErr) {
      console.error(
        `[delete-account] request_id=${requestId} subscription lookup failed` +
          ` (non-fatal, proceeding with erasure):`,
        subsErr.message,
      );
      razorpayStatus = "lookup_failed";
    }

    for (const sub of subs ?? []) {
      if (!sub.razorpay_subscription_id) continue;

      try {
        const razorRes = await fetch(
          `https://api.razorpay.com/v1/subscriptions/${sub.razorpay_subscription_id}/cancel`,
          {
            method: "POST",
            headers: {
              Authorization:
                "Basic " +
                btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`),
              "Content-Type": "application/json",
            },
          },
        );

        if (!razorRes.ok) {
          const detail = await razorRes.text();
          console.error(
            `[delete-account] request_id=${requestId} razorpay cancel failed` +
              ` (non-fatal) sub=${sub.razorpay_subscription_id} status=${razorRes.status} body=${detail}`,
          );
          cancelFailures.push(`${sub.razorpay_subscription_id}:${razorRes.status}`);
          continue;
        }

        razorpayStatus = "cancelled";
        console.log(
          `[delete-account] request_id=${requestId} razorpay sub=${sub.razorpay_subscription_id} cancelled`,
        );
      } catch (e) {
        console.error(
          `[delete-account] request_id=${requestId} razorpay cancel exception` +
            ` (non-fatal):`,
          e,
        );
        cancelFailures.push(`${sub.razorpay_subscription_id}:exception`);
      }
    }

    // Record any failed cancellation(s) durably so the subscription can be
    // cancelled out-of-band. The erasure still proceeds (DPDP §17).
    if (cancelFailures.length > 0) {
      razorpayStatus = `cancel_failed:${cancelFailures.join(",")}`.slice(0, 400);
    }

    // ── 4. ONESIGNAL UNSUBSCRIBE — best-effort, non-fatal ────────────────────
    // Unsubscribe the device so it stops receiving pushes after account deletion.
    // If this fails, the device just keeps receiving pushes until OS uninstall —
    // annoying but not a data integrity risk.
    try {
      const { data: progress, error: progressErr } = await admin
        .from("user_progress")
        .select("onesignal_player_id")
        .eq("user_id", userId)
        .maybeSingle();

      if (progressErr) {
        console.warn(
          `[delete-account] request_id=${requestId} onesignal lookup error (non-fatal):`,
          progressErr.message,
        );
      } else {
        const playerId = progress?.onesignal_player_id;
        if (playerId) {
          await fetch(
            `https://onesignal.com/api/v1/players/${playerId}?app_id=${ONESIGNAL_APP_ID}`,
            {
              method: "DELETE",
              headers: {
                Authorization: `Basic ${ONESIGNAL_REST_API_KEY}`,
              },
            },
          ).catch((e) =>
            console.warn(
              `[delete-account] request_id=${requestId} onesignal unsub failed (non-fatal):`,
              e,
            )
          );
          console.log(
            `[delete-account] request_id=${requestId} onesignal player_id=${playerId} unsubscribed`,
          );
        } else {
          console.log(
            `[delete-account] request_id=${requestId} no onesignal player_id on record`,
          );
        }
      }
    } catch (e) {
      console.warn(
        `[delete-account] request_id=${requestId} onesignal step error (non-fatal):`,
        e,
      );
    }

    // ── 5. STORAGE PURGE — best-effort, non-fatal ────────────────────────────
    // Purge all user-owned objects in the 3 buckets. Errors are accumulated and
    // logged but never block the delete. A separate orphan-cleanup cron handles
    // objects that might be missed here (not yet implemented — post-Test-#11).
    const purgeStats: { [key: string]: number | string[] } = { errors: [] };

    // OI-32 (audit-2026-05-17 Hermes F7) — recursive Storage purge.
    // Pre-fix this loop only called `.list(userId)` which returns the
    // top-level entries under `userId/` (objects + subdirectory names,
    // not contents of subdirectories). Any nested path like
    // `userId/2026/photo.jpg` survived account deletion. DPDP §17
    // requires erasure of all user-tagged objects — nested or otherwise.
    //
    // Supabase Storage SDK has no `recursive: true` option on .list();
    // we implement DFS ourselves. Folder entries have `id === null`,
    // file entries have a non-null id. Paginated 1000-per-call for
    // users with large photo histories.
    async function listAllObjectsRecursive(
      bucket: string,
      prefix: string,
    ): Promise<string[]> {
      const objectPaths: string[] = [];
      const stack: string[] = [prefix];
      while (stack.length > 0) {
        const current = stack.pop()!;
        let offset = 0;
        while (true) {
          const { data: entries, error } = await admin.storage
            .from(bucket)
            .list(current, { limit: 1000, offset });
          if (error) throw new Error(`list ${current}: ${error.message}`);
          if (!entries || entries.length === 0) break;
          for (const e of entries) {
            const fullPath = current ? `${current}/${e.name}` : e.name;
            if (e.id === null) {
              // Folder entry — recurse into it.
              stack.push(fullPath);
            } else {
              objectPaths.push(fullPath);
            }
          }
          if (entries.length < 1000) break;
          offset += 1000;
        }
      }
      return objectPaths;
    }

    for (const bucket of ["progress-photos", "chat-media", "coach-media"]) {
      try {
        const paths = await listAllObjectsRecursive(bucket, userId);

        if (paths.length > 0) {
          // Storage .remove() takes a flat array; chunk by 1000 (the
          // Supabase REST batch limit) so large purges don't reject.
          let removed = 0;
          for (let i = 0; i < paths.length; i += 1000) {
            const chunk = paths.slice(i, i + 1000);
            const { error: rmErr } = await admin.storage
              .from(bucket)
              .remove(chunk);
            if (rmErr) {
              (purgeStats.errors as string[]).push(
                `${bucket}_rm:${rmErr.message}`,
              );
              console.warn(
                `[delete-account] request_id=${requestId} storage remove error bucket=${bucket} (chunk@${i}):`,
                rmErr.message,
              );
              // Don't break — try remaining chunks.
            } else {
              removed += chunk.length;
            }
          }
          purgeStats[bucket] = removed;
          console.log(
            `[delete-account] request_id=${requestId} purged ${removed}/${paths.length} objects from bucket=${bucket} (recursive)`,
          );
        } else {
          purgeStats[bucket] = 0;
          console.log(
            `[delete-account] request_id=${requestId} bucket=${bucket} empty for user`,
          );
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        (purgeStats.errors as string[]).push(`${bucket}_exception:${msg}`);
        console.warn(
          `[delete-account] request_id=${requestId} storage exception bucket=${bucket} (non-fatal):`,
          e,
        );
      }
    }

    // ── 6. AUTH.USERS DELETE ─────────────────────────────────────────────────
    // Service-role admin call. This cascades through:
    //   auth.users → public.users (FK ON DELETE CASCADE per migration 039)
    //   public.users → user_profile, user_preferences, user_progress,
    //                  workout_logs, nutrition_logs, weight_logs, ... (standard FKs)
    //   5 community surfaces (user_custom_exercises, user_custom_foods,
    //   community_reviews, food_corrections, promo_code_uses) get user_id = NULL
    //   via ON DELETE SET NULL per migration 049.
    //   account_deletion_log has NO FK — survives the delete.
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);

    if (delErr) {
      console.error(
        `[delete-account] request_id=${requestId} auth delete failed:`,
        delErr.message,
      );
      return jsonError(500, "auth_delete_failed", requestId);
    }

    console.log(
      `[delete-account] request_id=${requestId} user=${userId} auth.users deleted`,
    );

    // ── 7. AUDIT LOG ─────────────────────────────────────────────────────────
    // Inserted AFTER auth delete — table has no FK, so the row survives. It MUST
    // NOT rethrow: the account is already gone (point of no return). d5b2f8
    // (2026-06-12 live E2E): a PostgREST builder is a thenable with NO `.catch()`
    // method, so the old `.insert({...}).catch(...)` evaluated `.catch` as
    // undefined and threw a TypeError → the EF 500'd AFTER the successful delete
    // AND the audit row never wrote (insert never ran). This path had NEVER
    // executed before the e8a1c3 auth fix (auth always 401'd). Use the supabase
    // pattern: await + check `error`, all inside a try/catch.
    try {
      const { error: auditErr } = await admin
        .from("account_deletion_log")
        .insert({
          deleted_user_id: userId,
          deleted_at: new Date().toISOString(),
          request_id: requestId,
          razorpay_cancel_status: razorpayStatus,
          storage_purge_status: purgeStats,
        });
      if (auditErr) throw auditErr;
    } catch (e: unknown) {
      // a2c8e6 (B-pass F1): console.ERROR, not warn — this row is the ONLY durable
      // out-of-band record of a FAILED Razorpay cancel. If the audit insert ALSO
      // fails (a correlated Supabase+Razorpay outage), emit a distinctive,
      // greppable last-resort line so ops can still find the active subscription
      // that needs MANUAL cancellation from the raw function logs (which survive
      // independently of the table row) — the user no longer has an account to
      // dispute ongoing charges.
      console.error(
        `[delete-account] request_id=${requestId} audit insert failed (non-fatal):`,
        e,
      );
      if (
        razorpayStatus.startsWith("cancel_failed") ||
        razorpayStatus === "lookup_failed"
      ) {
        console.error(
          `[delete-account] ORPHAN_BILLING request_id=${requestId} ` +
            `user=${userId} razorpay_cancel_status=${razorpayStatus} — audit ` +
            `row NOT persisted; subscription needs MANUAL cancellation.`,
        );
      }
    }

    console.log(
      `[delete-account] request_id=${requestId} erasure complete — razorpay=${razorpayStatus}` +
        ` storage=${JSON.stringify(purgeStats)}`,
    );

    return new Response(
      JSON.stringify({ success: true, request_id: requestId }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Outer catch — log full detail server-side, return sanitized 500 to client.
    console.error(
      `[delete-account] request_id=${requestId} unhandled exception:`,
      err,
    );
    return jsonError(500, "internal_error", requestId);
  }
});
