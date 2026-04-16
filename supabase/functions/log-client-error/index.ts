/**
 * log-client-error — Sync failure telemetry sink.
 *
 * Called by the Flutter SyncQueue ONLY on dead-letter (after all retries
 * for an operation have been exhausted). Transient failures that
 * eventually succeed are NOT reported here.
 *
 * Input:
 *   {
 *     error_code:     "NetworkError" | "AuthError" | "ValidationError" |
 *                     "SchemaError" | "RateLimitError" | "UnknownError",
 *     error_message:  string | null,
 *     op_type:        string | null,    // e.g. "upsert_user_profile"
 *     retry_count:    int,              // how many attempts before dead-lettering
 *     client_version: string,           // "1.2.3+42" from package_info_plus
 *     platform:       "android" | "ios" | "web"
 *   }
 *
 * Output: { ok: true } or { error: "<reason>" }
 *
 * Rate limit: 100 dead-letters / user / 24h. Prevents a runaway sync loop
 * from writing thousands of rows.
 *
 * Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar D
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  clientError,
  corsHeaders,
  ok,
  serverError,
} from "../_shared/error.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const VALID_ERROR_CODES = new Set([
  "NetworkError",
  "AuthError",
  "ValidationError",
  "SchemaError",
  "RateLimitError",
  "UnknownError",
]);

const VALID_PLATFORMS = new Set(["android", "ios", "web"]);

const MAX_MESSAGE_CHARS = 2000;
const MAX_OP_TYPE_CHARS = 64;
const MAX_CLIENT_VERSION_CHARS = 32;
const DAILY_RATE_LIMIT = 100;

serve(async (req: Request) => {
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
    const errorCode = String(body?.error_code ?? "");
    const errorMessage = body?.error_message == null
      ? null
      : String(body.error_message);
    const opType = body?.op_type == null ? null : String(body.op_type);
    const retryCount = Number.isFinite(body?.retry_count)
      ? Number(body.retry_count)
      : 0;
    const clientVersion = String(body?.client_version ?? "");
    const platform = String(body?.platform ?? "");

    // Validation — reject malformed input with specific reasons (user-safe).
    if (!VALID_ERROR_CODES.has(errorCode)) {
      return clientError("Invalid error_code", 400);
    }
    if (!VALID_PLATFORMS.has(platform)) {
      return clientError("Invalid platform", 400);
    }
    if (!clientVersion || clientVersion.length > MAX_CLIENT_VERSION_CHARS) {
      return clientError("Invalid client_version", 400);
    }
    if (errorMessage != null && errorMessage.length > MAX_MESSAGE_CHARS) {
      return clientError(
        `error_message too long (max ${MAX_MESSAGE_CHARS} chars)`,
        400,
      );
    }
    if (opType != null && opType.length > MAX_OP_TYPE_CHARS) {
      return clientError(
        `op_type too long (max ${MAX_OP_TYPE_CHARS} chars)`,
        400,
      );
    }
    if (retryCount < 0 || retryCount > 1000) {
      return clientError("Invalid retry_count", 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Per-user 24h rate limit.
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await supabase
      .from("client_errors")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", since);

    if (countError) {
      return serverError("log-client-error:count", countError);
    }
    if ((count ?? 0) >= DAILY_RATE_LIMIT) {
      // Quietly succeed — we've already captured enough samples from this
      // user today. No point spamming the table or charging the client
      // extra network cost for something we'll discard.
      return ok({ ok: true, rate_limited: true });
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

    return ok({ ok: true });
  } catch (err) {
    return serverError("log-client-error", err);
  }
});
