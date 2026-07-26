/**
 * cron_auth.ts — shared-secret auth gate for cron-dispatched Edge Functions.
 *
 * Rewritten 2026-07-26 (closes-diagnose: c3f8a1). See HISTORY at the bottom —
 * the two previous designs both failed in production, and the second failed
 * silently for roughly eight weeks.
 *
 * AUTH MODEL
 * ----------
 * A single opaque shared secret. The caller must present
 * `Authorization: Bearer <CRON_SECRET>`, where `CRON_SECRET` is an Edge
 * Function secret whose value also lives in the Vault row `cron_secret`, read
 * by `private.cron_get_secret()` and interpolated into every `cron.job`
 * command (migrations 107/108).
 *
 * WHY A SHARED SECRET RATHER THAN A JWT
 * -------------------------------------
 * This is machine-to-machine auth between pg_cron and the Edge runtime. There
 * is no user identity to carry, no claims to inspect and no delegation — a
 * signed token buys nothing here, and every JWT-shaped attempt has coupled the
 * gate to platform key management that then changed underneath it:
 *
 *   - Attempt 1 compared the token to `SUPABASE_SERVICE_ROLE_KEY`. Broke when
 *     the Vault copy and the env copy drifted (diagnose 5a65bd).
 *   - Attempt 2 verified the signature against `SUPABASE_JWT_SECRET` — a
 *     variable Supabase does not inject and **forbids creating**, because the
 *     platform reserves the `SUPABASE_` prefix for secret names. Unsatisfiable
 *     by construction; every cron call 401'd from the day it deployed.
 *
 * A string comparison has no such coupling. It is unaffected by the JWT
 * signing-key migration now underway on this project and by the deprecation of
 * `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`.
 *
 * ⚠ THE SECRET IS THE ONLY GATE. Cron functions run `verify_jwt=false`, so
 * their URLs accept unauthenticated POSTs from anywhere and this comparison is
 * all that stands between the open internet and a privileged fan-out (push
 * sends, Gemini spend, storage deletion). `CRON_SECRET` must be long and
 * cryptographically random — `openssl rand -hex 32`. Never a memorable phrase.
 *
 * USAGE (per cron function)
 * -------------------------
 *   import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
 *
 *   Deno.serve(async (req) => {
 *     if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
 *     if (!await isAuthorizedCronCall(req)) {
 *       return new Response(JSON.stringify({ error: "Unauthorized" }), {
 *         status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
 *       });
 *     }
 *     const logId = await logCronStart("<slug>");   // AFTER the gate — see below
 *     // ... handler body
 *   });
 *
 * ⚠ KEEP `logCronStart` AFTER THIS GATE. It is tempting to move it earlier so
 * that rejected calls leave a telemetry row — the 2026-07-26 batch considered
 * exactly that. Don't: on a `verify_jwt=false` endpoint it would hand every
 * anonymous caller an unauthenticated INSERT into `public.cron_call_log`.
 * Outage visibility is provided instead by `alert_cron_silence` (migration
 * 109), which alerts on the ABSENCE of successful runs and therefore needs no
 * writes from unauthenticated callers.
 */

/**
 * Constant-time string comparison.
 *
 * Both sides are hashed to a fixed 32-byte digest first, then compared with an
 * XOR-accumulate that always walks the full length. This leaks neither the
 * secret's length nor the position of the first differing byte, whereas a plain
 * `!==` short-circuits on the first mismatch and is measurable over enough
 * requests.
 *
 * Worth the few microseconds here specifically because this comparison is the
 * ONLY gate on 16 publicly-reachable endpoints (see the warning above), and the
 * secret in production is currently low-entropy by explicit accepted risk
 * (migration 107 header) — a weak secret plus a timing oracle is materially
 * worse than either alone.
 */
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [da, db] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const va = new Uint8Array(da);
  const vb = new Uint8Array(db);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

/**
 * True when the request carries `Authorization: Bearer <CRON_SECRET>`.
 *
 * False on a missing header, a malformed bearer, an unset `CRON_SECRET`, or any
 * mismatch. Never throws — safe to call without try/catch.
 */
export async function isAuthorizedCronCall(req: Request): Promise<boolean> {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      console.warn("[cron_auth] missing or malformed Authorization header");
      return false;
    }
    const token = authHeader.slice("Bearer ".length).trim();
    if (token.length === 0) {
      console.warn("[cron_auth] empty bearer token");
      return false;
    }

    // Trimmed on BOTH sides. A trailing newline pasted into the dashboard
    // secret would otherwise reject every call with no visible reason.
    const cronSecret = (Deno.env.get("CRON_SECRET") ?? "").trim();
    if (cronSecret.length === 0) {
      console.warn(
        "[cron_auth] CRON_SECRET is unset — every cron call will be rejected. " +
          "Set it in Project Settings -> Edge Functions -> Secrets, matching " +
          "the `cron_secret` Vault row exactly.",
      );
      return false;
    }

    if (!await timingSafeEqual(token, cronSecret)) {
      console.warn("[cron_auth] bearer token does not match CRON_SECRET");
      return false;
    }

    return true;
  } catch (err) {
    // Defensive — never let the auth gate crash its caller.
    console.error("[cron_auth] unexpected error:", err);
    return false;
  }
}

/*
 * HISTORY
 * -------
 * 2026-05-11 (7ad0c4)  Gate introduced; 8 cron functions were publicly callable.
 * 2026-05-12 (audit P0) Vault `service_role_key` row was empty, so the header
 *                       went out as `Bearer null` → 401 on every tick, 12 jobs.
 * 2026-05-15 (5a65bd)  Env-equality check broke on Vault/env key drift. That
 *                       write-up proposed "replace the brittle env-equality
 *                       check with a JWT signature+role decode" as the
 *                       permanent class fix.
 * 2026-05-16           The class fix shipped. It depended on
 *                       `SUPABASE_JWT_SECRET`, which cannot exist. The fix
 *                       made the bug permanent instead of ending it.
 * 2026-07-26 (c3f8a1)  Discovered: ~8 weeks of total cron silence. Three
 *                       safeguards had failed together — telemetry sat behind
 *                       the failing gate, pg_cron reports `succeeded` for any
 *                       dispatch regardless of HTTP status, and the health
 *                       alert computed a rate from the table the failure kept
 *                       empty. Replaced with this shared-secret gate; the
 *                       `deno.land/x/jose` dependency is gone with it, closing
 *                       a remote-dep-rot risk this repo has already been bitten
 *                       by (feedback_mistake_remote_dep_rot).
 */
