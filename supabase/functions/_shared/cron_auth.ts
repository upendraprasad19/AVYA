/**
 * cron_auth.ts — JWT signature + role-claim auth for cron Edge Functions.
 *
 * Audit 2026-05-16 / E.14.C (closes-diagnose: telemetry-hardening).
 *
 * BACKGROUND
 * ----------
 * Test #16 / P1-D documented a 401-storm root-cause class: every cron
 * Edge Function inlines an env-equality check shaped like:
 *
 *   const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
 *
 * This is brittle. When the Vault-stored JWT and the env-injected
 * `SUPABASE_SERVICE_ROLE_KEY` drift (platform rotation, manual Vault
 * re-save), the equality check fails and every cron tick returns 401
 * for hours/days before anyone notices — `cron.job_run_details` reports
 * "succeeded" regardless of the HTTP response.
 *
 * F9.1 (Agent 7 findings) flagged the lack of a shared helper as a
 * framework gap. This module is the replacement.
 *
 * AUTH MODEL
 * ----------
 * We decode the bearer token's JWT, verify the signature using the
 * project's `SUPABASE_JWT_SECRET` (Supabase auth signs all keys with
 * the same HS256 secret), and require `role === 'service_role'`.
 * Signature verification means a rotated key still authenticates as
 * long as it was signed by the same project secret — no env-drift
 * silent failure.
 *
 * The legacy `CRON_SECRET` opaque-token escape hatch is preserved so
 * we can rollback per-function if jose import or signature verify
 * misbehaves on Deno Deploy edge.
 *
 * USAGE (per-cron-function)
 * -------------------------
 *   import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
 *
 *   Deno.serve(async (req) => {
 *     if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
 *     if (!await isAuthorizedCronCall(req)) {
 *       return new Response(
 *         JSON.stringify({ error: "Unauthorized" }),
 *         { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
 *       );
 *     }
 *     // ... handler body
 *   });
 *
 * NOTE — DO NOT DEPLOY in this batch. Source edit only; founder must
 * approve per-function deploys (live Edge Function deploys are gated).
 */

import { jwtVerify } from "https://deno.land/x/jose@v5.6.3/index.ts";

/**
 * Returns true when the request's Authorization header carries either:
 *
 *   (a) a JWT signed by `SUPABASE_JWT_SECRET` with `role === 'service_role'`, OR
 *   (b) an opaque token exactly matching `CRON_SECRET` (legacy/escape hatch).
 *
 * False on missing header, malformed bearer, invalid signature, expired
 * token, wrong role claim, or any internal error. Safe to call without
 * try/catch — never throws.
 *
 * Env vars consulted:
 *   - SUPABASE_JWT_SECRET (required for JWT path)
 *   - CRON_SECRET         (optional escape hatch)
 *
 * Pinned by the diagnose-doc; not unit-tested at this revision because
 * jose's WebCrypto path is hard to mock in-process. Replace with a
 * decode-only mock in tests when adding coverage.
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

    // Escape hatch — opaque CRON_SECRET match. Kept so a per-function
    // rollback is one env var away if jose / signature verify breaks.
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && cronSecret.length > 0 && token === cronSecret) {
      return true;
    }

    // JWT signature + role-claim path.
    const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET");
    if (!jwtSecret || jwtSecret.length === 0) {
      console.warn("[cron_auth] SUPABASE_JWT_SECRET unset; cannot verify JWT");
      return false;
    }
    const secretKey = new TextEncoder().encode(jwtSecret);

    let payload: Record<string, unknown>;
    try {
      const verified = await jwtVerify(token, secretKey);
      payload = verified.payload as Record<string, unknown>;
    } catch (err) {
      console.warn(`[cron_auth] jwtVerify failed: ${(err as Error).message}`);
      return false;
    }

    const role = payload["role"];
    if (role !== "service_role") {
      console.warn(`[cron_auth] role claim mismatch: got ${String(role)}`);
      return false;
    }

    return true;
  } catch (err) {
    // Defensive — never let auth-gate code crash the caller.
    console.error("[cron_auth] unexpected error:", err);
    return false;
  }
}
