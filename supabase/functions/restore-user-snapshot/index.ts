// supabase/functions/restore-user-snapshot/index.ts
//
// C3 of the restore-performance overhaul — SINGLE-CALL cloud→client restore.
// Replaces the gated `restoreFromCloudForUser` ~27 client round-trips (web p95 97s)
// with ONE service_role read that returns the WHOLE per-user snapshot as a jsonb
// bundle the client writes to Hive in one pass.
//
// ── SECURITY (catastrophic — service_role BYPASSES RLS; this body is the ONLY guard) ──
//   • Auth via getUser(token) on a SERVICE_ROLE client (e8a1c3 contract). NEVER pass
//     the user JWT as the supabaseKey.
//   • v_uid is derived from the VALIDATED token and asserted NON-EMPTY + UUID-shaped
//     BEFORE any query is built — else 401 (H-4 / F3-F4 fail-open guard).
//   • NO client-supplied user-id param ever. EVERY table read is scoped to v_uid.
//     The three user_id-LESS tables are scoped via parent / dual-FK (live-verified):
//       - nutrition_log_items  → embedded under nutrition_logs (parent user_id)
//       - template_exercises   → embedded under workout_templates / scheduled_workouts
//       - referral_redemptions → dual-FK .or(referrer_id=v_uid, referee_id=v_uid)  (H-8:
//         v_uid is UUID-validated above, so the .or() string interpolation is injection-safe)
//     (workout_log_sets / workout_log_exercises DO carry user_id → scoped directly.)
//
// ── FAIL-CLOSED (H-2) ──
//   ANY single table-query error → throw → caught → 500 (non-200). NO per-table swallow
//   that returns a partial 200 (the legacy `_safeRestoreOp` swallow pattern is BANNED
//   here). The bundle emits EVERY table key UNCONDITIONALLY ([] / null when empty) plus a
//   top-level `schema_version` sentinel. The client treats an ABSENT key OR a missing
//   sentinel OR a non-200 as a FAULT → runs the verbatim legacy per-op restore this pass.
//
// ── SHAPE (H-1) ──
//   Each table value reproduces the legacy PostgREST response VERBATIM, including embed
//   nesting (nutrition_logs→nutrition_log_items(*); workout_templates→template_exercises(*);
//   scheduled_workouts→template:template_id(...template_exercises(*))) and the exact column
//   projections (coach_memory 10-col, freezes 4-col, referral_codes 3-col, redemptions
//   5-col, users 2-col), so the client `_restoreX` parsers hydrate UNCHANGED. Caps inherit
//   today's behaviour verbatim (H-9). Column names are verbatim (H-11).
//
// verify_jwt: true at deploy (user must be authenticated; gateway pre-check + getUser here).
// Plan: ~/.claude/plans/restore-single-call-c3.md. NOT YET DEPLOYED — deploy is founder-gated.
// closes-diagnose: (restore-perf single-call) — see docs/diagnoses on impl.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// Bump SCHEMA_VERSION whenever the bundle shape or table set changes — the client
// rejects a bundle whose schema_version it does not recognise (→ legacy fallback).
const SCHEMA_VERSION = 1;

// Full-history restore window — UNCHANGED from the legacy client (sync_service.dart:1280).
const SINCE = "2020-01-01T00:00:00Z";
const SINCE_DATE = SINCE.substring(0, 10); // '2020-01-01' for date-typed columns (daily_steps / water_logs / scheduled_workouts)

// Mirrors `_fetchAllRows` maxRows ceiling (sync_service.dart:1867). One .range() fetch
// covers it for the paginated tables (payload is sub-MB at live volumes; verified).
const PAGINATED_CEILING = 50000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SERVICE_ROLE) {
  console.error("[restore-user-snapshot] STARTUP FAILED — missing env vars:", {
    SUPABASE_URL: !!SUPABASE_URL,
    SERVICE_ROLE: !!SERVICE_ROLE,
  });
  throw new Error("[restore-user-snapshot] required env vars not set");
}

// RFC-4122 UUID shape — the H-4 guard. A token-derived user.id that is null / empty /
// non-UUID is rejected BEFORE any query, so a fail-open cross-user read is impossible.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function jsonError(status: number, error: string, requestId: string): Response {
  return new Response(JSON.stringify({ error, request_id: requestId }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const requestId = crypto.randomUUID().split("-")[0];

  if (req.method !== "POST") {
    return jsonError(405, "method_not_allowed", requestId);
  }

  try {
    // ── 1. AUTH — getUser(token) on a service_role client (e8a1c3) ───────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonError(401, "unauthenticated", requestId);
    }
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();

    // Service-role client: bypasses RLS for the reads below, and re-validates the
    // caller's JWT. NEVER createClient(url, token) — that 401s every valid token.
    const db = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await db.auth.getUser(token);
    const vUid = userData?.user?.id;
    // H-4: bind the non-empty UUID invariant BEFORE building ANY query. Covers
    // getUser → {user:null, error:null} (deleted user / edge) and empty/non-UUID id.
    if (userErr || !vUid || typeof vUid !== "string" || !UUID_RE.test(vUid)) {
      return jsonError(401, "unauthenticated", requestId);
    }

    // ── 2. ASSEMBLE THE BUNDLE — fail-closed. Any q() throw → caught below → 500. ──
    // Every builder is scoped to vUid. `q` throws on a PostgREST error (NOT on a
    // legitimately-empty maybeSingle, which returns null) so a real read failure
    // aborts the WHOLE call rather than shipping a partial bundle.
    const q = async <T>(label: string, builder: PromiseLike<{ data: T; error: unknown }>): Promise<T> => {
      const { data, error } = await builder;
      if (error) {
        const msg = (error as { message?: string })?.message ?? String(error);
        throw new Error(`query_failed:${label}:${msg}`);
      }
      return data;
    };

    const tables: Record<string, unknown> = {};

    // ── Step A — profile + lightweight ──────────────────────────────────────────
    tables["user_profile"] = await q(
      "user_profile",
      db.from("user_profile").select("*").eq("user_id", vUid).limit(1),
    );
    tables["users"] = await q(
      "users",
      db.from("users").select("full_name, email").eq("id", vUid).maybeSingle(),
    );
    tables["user_progress"] = await q(
      "user_progress",
      db.from("user_progress").select("*").eq("user_id", vUid).limit(1),
    );
    tables["user_preferences"] = await q(
      "user_preferences",
      db.from("user_preferences").select("*").eq("user_id", vUid).limit(1),
    );
    tables["workout_templates"] = await q(
      "workout_templates",
      db.from("workout_templates")
        .select("*, template_exercises(*)")
        .eq("user_id", vUid)
        .eq("is_active", true)
        .limit(500),
    );
    // workout_plan = the plan_json snapshot on user_progress (parser reads rows.first['plan_json']).
    tables["workout_plan"] = await q(
      "workout_plan",
      db.from("user_progress").select("plan_json").eq("user_id", vUid).limit(1),
    );
    tables["user_custom_exercises"] = await q(
      "user_custom_exercises",
      db.from("user_custom_exercises").select("*").eq("user_id", vUid),
    );
    tables["user_custom_foods"] = await q(
      "user_custom_foods",
      db.from("user_custom_foods").select("*").eq("user_id", vUid),
    );

    // ── Step B — bulk history ─────────────────────────────────────────────────────
    tables["workout_logs"] = await q(
      "workout_logs",
      db.from("workout_logs").select("*").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["workout_log_exercises"] = await q(
      "workout_log_exercises",
      db.from("workout_log_exercises").select("*").eq("user_id", vUid)
        .gte("completed_at", SINCE).order("completed_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["workout_log_sets"] = await q(
      "workout_log_sets",
      db.from("workout_log_sets").select("*").eq("user_id", vUid)
        .gte("completed_at", SINCE).order("completed_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["workout_schedule_completions"] = await q(
      "workout_schedule_completions",
      // No .limit() — inherits the legacy PostgREST default cap verbatim (H-9).
      db.from("workout_schedule_completions").select("*").eq("user_id", vUid)
        .gte("completed_at", SINCE).order("scheduled_date"),
    );
    tables["weight_logs"] = await q(
      "weight_logs",
      db.from("weight_logs").select("*").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["daily_steps"] = await q(
      "daily_steps",
      db.from("daily_steps").select("*").eq("user_id", vUid)
        .gte("date", SINCE_DATE).order("date").range(0, PAGINATED_CEILING - 1),
    );
    tables["nutrition_logs"] = await q(
      "nutrition_logs",
      db.from("nutrition_logs").select("*, nutrition_log_items(*)").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["body_measurements"] = await q(
      "body_measurements",
      db.from("body_measurements").select("*").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["water_logs"] = await q(
      "water_logs",
      db.from("water_logs").select("*").eq("user_id", vUid)
        .gte("date", SINCE_DATE).order("date").range(0, PAGINATED_CEILING - 1),
    );
    tables["sleep_logs"] = await q(
      "sleep_logs",
      db.from("sleep_logs").select("*").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").range(0, PAGINATED_CEILING - 1),
    );
    tables["streaks"] = await q(
      "streaks",
      db.from("streaks").select("*").eq("user_id", vUid)
        .order("week_start", { ascending: false }).limit(52),
    );
    tables["scheduled_workouts"] = await q(
      "scheduled_workouts",
      db.from("scheduled_workouts")
        .select("*, template:template_id(id, name, workout_type, template_exercises(*))")
        .eq("user_id", vUid)
        .gte("scheduled_date", SINCE_DATE)
        .order("scheduled_date")
        .range(0, 999),
    );
    tables["user_saved_meals"] = await q(
      "user_saved_meals",
      db.from("user_saved_meals").select("*").eq("user_id", vUid).limit(500),
    );
    tables["ai_coach_interactions"] = await q(
      "ai_coach_interactions",
      db.from("ai_coach_interactions").select("*").eq("user_id", vUid)
        .gte("created_at", SINCE).order("created_at").limit(1000),
    );
    tables["coach_memory"] = await q(
      "coach_memory",
      // 10-column projection ONLY (H-12) — never SELECT * (keeps server-only risk
      // scores / private fields off the wire). Mirrors sync_coach.dart:222-230.
      db.from("coach_memory")
        .select(
          "committed_at, committed_to_lt_cdr, induction_completed_at, why_now, " +
            "definition_of_winning, known_injuries, typical_wake_time, " +
            "preferred_workout_time, body_part_priorities, coach_notes",
        )
        .eq("user_id", vUid)
        .maybeSingle(),
    );

    // ── Step C — restore-completeness surfaces ────────────────────────────────────
    tables["freezes"] = await q(
      "freezes",
      db.from("user_progress")
        .select(
          "streak_freezes_available, streak_freezes_used_dates, " +
            "streak_freezes_last_refill, streak_freezes_first_pro_grant_done",
        )
        .eq("user_id", vUid)
        .maybeSingle(),
    );
    tables["notifications_inbox"] = await q(
      "notifications_inbox",
      db.from("notifications_inbox").select("*").eq("user_id", vUid)
        .order("created_at", { ascending: false }).limit(200),
    );
    tables["saved_diet_plan"] = await q(
      "saved_diet_plan",
      db.from("saved_diet_plans").select("plan_json").eq("user_id", vUid).maybeSingle(),
    );
    tables["rank_promotions"] = await q(
      "rank_promotions",
      db.from("rank_promotions").select("*").eq("user_id", vUid)
        .order("achieved_at", { ascending: false }).limit(20),
    );
    tables["referral_codes"] = await q(
      "referral_codes",
      db.from("referral_codes").select("code, expires_at, created_at").eq("user_id", vUid)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false }).limit(1).maybeSingle(),
    );
    tables["referral_redemptions"] = await q(
      "referral_redemptions",
      // Dual-FK self-scope (H-8). vUid is UUID-validated → .or() interpolation is safe.
      db.from("referral_redemptions")
        .select("code, referrer_id, referee_id, days_granted_each, created_at")
        .or(`referrer_id.eq.${vUid},referee_id.eq.${vUid}`)
        .order("created_at", { ascending: false }).limit(50),
    );

    // ── 3. RETURN — all keys present + sentinel. (subscriptions is NOT in the bundle;
    //     the client keeps the separate refreshFromSupabase() call — H-3.) ──────────
    const bundle = {
      schema_version: SCHEMA_VERSION,
      generated_at: new Date().toISOString(),
      tables,
    };
    return new Response(JSON.stringify(bundle), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    // FAIL-CLOSED: any read error → 500 (non-200). The client falls back to the
    // verbatim legacy per-op restore this pass. No PII / no stack in the body.
    console.error(`[restore-user-snapshot] request_id=${requestId}`, e);
    return jsonError(500, "restore_snapshot_failed", requestId);
  }
});
