// supabase/functions/delete-account/index.ts
// DPDP §17 hard erasure — full account deletion with Razorpay cancel, OneSignal
// unsubscribe, Storage purge, auth.users cascade, and audit log.
//
// Flow (order matters):
//   1. JWT auth via getUser (server-side verify, not just header)
//   2. Confirmation token check — body must have DELETE-MY-ACCOUNT-<uid8>
//   3. Razorpay subscription cancel — MUST succeed or 502 abort
//   4. OneSignal player unsub — best-effort, non-fatal
//   5. Storage purge (3 buckets) — best-effort, per-bucket errors logged
//   6. auth.users delete (service-role) — CASCADE through public.users + all FKs
//      (5 community surfaces get user_id = NULL per migration 049, not deleted)
//   7. Audit insert to account_deletion_log (no FK, survives auth delete)
//
// verify_jwt: true at deploy (user must be authenticated).
// Error sanitization: every non-200 returns { error: <code>, request_id: <8-hex> }.
// No PII in error response bodies.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
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

// ── Helper: sanitized error response (no PII, no stack traces) ───────────────
function jsonError(
  status: number,
  error: string,
  requestId: string,
): Response {
  return new Response(
    JSON.stringify({ error, request_id: requestId }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
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

    // Use the user's JWT to get their identity (not service-role — so we verify
    // the token is actually for an authenticated user, not a forged one).
    const userClient = createClient(
      SUPABASE_URL as string,
      authHeader.replace("Bearer ", ""),
    );
    const { data: userRes, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userRes?.user) {
      console.warn(
        `[delete-account] request_id=${requestId} auth getUser failed:`,
        userErr?.message,
      );
      return jsonError(401, "unauthenticated", requestId);
    }
    const userId = userRes.user.id;

    // ── 2. CONFIRMATION TOKEN ────────────────────────────────────────────────
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

    // Admin client for all privileged operations below
    const admin = createClient(SUPABASE_URL as string, SERVICE_ROLE as string);

    // ── 3. RAZORPAY CANCEL — must succeed or abort ───────────────────────────
    // Risk: if we delete the user first and Razorpay cancel fails, the user has
    // no account to dispute the charge. Cancel first, delete after.
    let razorpayStatus = "no_active_sub";

    const { data: subs, error: subsErr } = await admin
      .from("subscriptions")
      .select("razorpay_subscription_id")
      .eq("user_id", userId)
      .eq("status", "active");

    if (subsErr) {
      console.error(
        `[delete-account] request_id=${requestId} subscription lookup failed:`,
        subsErr.message,
      );
      return jsonError(502, "razorpay_cancel_failed", requestId);
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
              ` sub=${sub.razorpay_subscription_id} status=${razorRes.status} body=${detail}`,
          );
          return jsonError(502, "razorpay_cancel_failed", requestId);
        }

        razorpayStatus = "cancelled";
        console.log(
          `[delete-account] request_id=${requestId} razorpay sub=${sub.razorpay_subscription_id} cancelled`,
        );
      } catch (e) {
        console.error(
          `[delete-account] request_id=${requestId} razorpay cancel exception:`,
          e,
        );
        return jsonError(502, "razorpay_cancel_failed", requestId);
      }
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

    for (const bucket of ["progress-photos", "chat-media", "coach-media"]) {
      try {
        const { data: files, error: lsErr } = await admin.storage
          .from(bucket)
          .list(userId);

        if (lsErr) {
          (purgeStats.errors as string[]).push(
            `${bucket}_list:${lsErr.message}`,
          );
          console.warn(
            `[delete-account] request_id=${requestId} storage list error bucket=${bucket}:`,
            lsErr.message,
          );
          continue;
        }

        if (files && files.length > 0) {
          const paths = files.map((f) => `${userId}/${f.name}`);
          const { error: rmErr } = await admin.storage
            .from(bucket)
            .remove(paths);

          if (rmErr) {
            purgeStats[bucket] = 0;
            (purgeStats.errors as string[]).push(
              `${bucket}_rm:${rmErr.message}`,
            );
            console.warn(
              `[delete-account] request_id=${requestId} storage remove error bucket=${bucket}:`,
              rmErr.message,
            );
          } else {
            purgeStats[bucket] = paths.length;
            console.log(
              `[delete-account] request_id=${requestId} purged ${paths.length} objects from bucket=${bucket}`,
            );
          }
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
    // Inserted AFTER auth delete — table has no FK, so the row survives.
    // Wrapped in .catch() so an audit insert failure never rewinds the already-
    // successful delete (and we've already passed the point of no return).
    await admin
      .from("account_deletion_log")
      .insert({
        deleted_user_id: userId,
        deleted_at: new Date().toISOString(),
        request_id: requestId,
        razorpay_cancel_status: razorpayStatus,
        storage_purge_status: purgeStats,
      })
      .catch((e) =>
        console.warn(
          `[delete-account] request_id=${requestId} audit insert failed (non-fatal):`,
          e,
        )
      );

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
