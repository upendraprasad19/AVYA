/**
 * promote-community-item — F18 auto-promotion of user submissions.
 *
 * Scans `community_reviews` for items with ≥10 approve votes that haven't
 * been promoted yet, copies them into the global library tables
 * (`food_database` / `exercise_library`), and flips the source row's
 * `approved` / `approved_for_library` flag. Fires a OneSignal push to the
 * submitter ("Your submission 'X' is now live").
 *
 * Trigger: invoked by cron (pg_cron schedule) OR manually by admin.
 *
 * Audit C-5 (2026-05-11, closes-diagnose 7ad0c5): caller-identity gate.
 *
 * v7 had a bug: anon JWT bypassed the gate because auth.getUser(anon_key)
 * returns null, and the code treated null user as 'service-role caller'.
 * v8: explicit token comparison — service-role key matches the env var
 * literally; authenticated JWTs are admin-checked against ADMIN_USER_IDS;
 * everything else 401/403.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import { fetchAllPages } from "../_shared/paged_fetch.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

// Admin allowlist for direct invocation. Comma-separated UUIDs.
// If empty, end-user calls are auto-rejected (fail-secure default).
// Service-role callers bypass this — they match SUPABASE_SERVICE_ROLE_KEY
// literally and don't need to be on the admin list.
const ADMIN_USER_IDS = (Deno.env.get("ADMIN_USER_IDS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const APPROVAL_THRESHOLD = 10;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return clientError("Method not allowed", 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return clientError("Missing authorization header", 401);
  }
  const token = authHeader.slice("Bearer ".length);

  // ── Caller-identity gate (C-5 + 2026-05-17 OI-11 retrofit) ──────────
  // Three accepted paths:
  //   1. Service-role JWT (cron / dashboard / MCP) — verified via
  //      `isAuthorizedCronCall` which decodes the JWT signature against
  //      SUPABASE_JWT_SECRET and requires `role === 'service_role'`.
  //      Pre-fix this was a brittle `token === SUPABASE_SERVICE_ROLE_KEY`
  //      literal compare — broke silently when Vault JWT and env-injected
  //      key drifted, producing the 401-storm class (OI-11 root cause).
  //   2. Authenticated admin JWT — user.id ∈ ADMIN_USER_IDS
  // Everything else is rejected. Anon JWT is rejected via path 2 because
  // anon JWT has no user_id claim → auth.getUser returns null.

  const isServiceRole = await isAuthorizedCronCall(req);

  if (!isServiceRole) {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user } } = await userClient.auth.getUser(token);

    if (!user) {
      return clientError("Admin only", 403);
    }

    if (ADMIN_USER_IDS.length === 0) {
      console.error("[promote-community-item] ADMIN_USER_IDS env var not set; rejecting end-user call by default");
      return clientError("Admin only", 403);
    }

    if (!ADMIN_USER_IDS.includes(user.id)) {
      console.warn(`[promote-community-item] non-admin caller rejected: user_id=${user.id}`);
      return clientError("Admin only", 403);
    }
  }

  const logId = await logCronStart("promote-community-item");

  try {
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── Promote foods ────────────────────────────────────────────
    const foodPromotions = await promoteFoods(admin);

    // ── Promote exercises ────────────────────────────────────────
    const exercisePromotions = await promoteExercises(admin);

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({
      ok: true,
      foods_promoted: foodPromotions,
      exercises_promoted: exercisePromotions,
    });
  } catch (err) {
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      errorSummary: String(err),
    });
    return serverError("promote-community-item", err);
  }
});

async function promoteFoods(
  admin: SupabaseClient,
): Promise<number> {
  // Count approve votes per food item and pick those with ≥ threshold.
  const list = await countApproveVotes(admin, "food");

  let promoted = 0;
  for (const row of list) {
    if (row.approves < APPROVAL_THRESHOLD) continue;

    // Pull source user_custom_foods row.
    const { data: source, error: sErr } = await admin
      .from("user_custom_foods")
      .select("*")
      .eq("id", row.item_id)
      .maybeSingle();
    if (sErr || !source) continue;
    if (source.approved === true) continue; // already promoted

    // Copy into food_database.
    const { error: copyErr } = await admin.from("food_database").insert({
      id: source.id,
      name: source.name,
      category: "community",
      calories_per_100g: source.calories_per_100g,
      protein_per_100g: source.protein_per_100g,
      carbs_per_100g: source.carbs_per_100g,
      fat_per_100g: source.fat_per_100g,
      fiber_per_100g: source.fiber_per_100g,
      standard_serving_desc: source.standard_serving_desc,
      standard_serving_g: source.standard_serving_g,
      calories_std: source.calories_std,
      protein_std: source.protein_std,
      carbs_std: source.carbs_std,
      fat_std: source.fat_std,
      source: "community",
    });
    if (copyErr) {
      console.warn("[promote:food:copy]", row.item_id, copyErr);
      continue;
    }

    // Mark source as approved.
    await admin
      .from("user_custom_foods")
      .update({ approved: true })
      .eq("id", source.id);

    if (source.user_id) {
      await notifySubmitter(source.user_id, source.name, "food");
    }
    promoted++;
  }
  return promoted;
}

async function promoteExercises(
  admin: SupabaseClient,
): Promise<number> {
  const list = await countApproveVotes(admin, "exercise");

  let promoted = 0;
  for (const row of list) {
    if (row.approves < APPROVAL_THRESHOLD) continue;

    const { data: source, error: sErr } = await admin
      .from("user_custom_exercises")
      .select("*")
      .eq("id", row.item_id)
      .maybeSingle();
    if (sErr || !source) continue;
    if (source.approved_for_library === true) continue;

    const { error: copyErr } = await admin.from("exercise_library").insert({
      id: source.id,
      name: source.name,
      category: source.category ?? "community",
      logging_type: source.logging_type,
      primary_muscles: source.primary_muscles ?? [],
      equipment_needed: source.equipment_needed ?? [],
      default_sets: source.default_sets,
      default_reps: source.default_reps,
      default_rest_secs: source.default_rest_secs,
      default_duration_secs: source.default_duration_secs,
      source: "community",
      is_active: true,
    });
    if (copyErr) {
      console.warn("[promote:exercise:copy]", row.item_id, copyErr);
      continue;
    }

    await admin
      .from("user_custom_exercises")
      .update({ approved_for_library: true })
      .eq("id", source.id);

    if (source.user_id) {
      await notifySubmitter(source.user_id, source.name, "exercise");
    }
    promoted++;
  }
  return promoted;
}

/**
 * THE approve-vote tally. Counts approve votes per item and returns
 * `{item_id, approves}` for the caller to threshold.
 *
 * It used to be named `fallbackCount` and sat behind a
 * `.rpc("community_votes_summary")` call. That RPC has never existed in any
 * schema on this project (verified live 2026-08-01 via pg_proc, confirmed twice
 * independently), so `.rpc()` returned `{data: null, error}` on every tick —
 * PostgREST reports a missing function as an error object rather than throwing —
 * and the `??` fell through to here every single time. The primary path had
 * therefore never executed in production, and no migration anywhere defines the
 * function, so there was nothing to "restore": the call was speculative code
 * whose helper was never written. Removed in OI-82 rather than implemented,
 * because this tally already computes exactly what the RPC's name promises.
 *
 * The reason it went unnoticed for so long is worth keeping: the error was
 * guarded by `if (countErr && !list)`, and `list` was always an array — `![]` is
 * `false` in JS — so the warning could not fire even when `countErr` was set. A
 * dead guard around a dead call reads as error handling and is worse than none.
 *
 * OI-79: paged. This reads one row per VOTE, not per item, so an un-ranged read
 * clipped at 1000 votes and every count derived after it was too low — items at
 * or above the approval threshold silently never got promoted, with no error.
 * That made it a wrong-result path, not just an incomplete one.
 */
async function countApproveVotes(
  admin: SupabaseClient,
  itemType: "food" | "exercise",
): Promise<Array<{ item_id: string; approves: number }>> {
  let data: Array<{ item_id: string }>;
  try {
    data = await fetchAllPages<{ item_id: string }>(
      () =>
        admin
          .from("community_reviews")
          .select("item_id")
          .eq("item_type", itemType)
          .eq("vote", "approve"),
      { orderBy: "id", label: `promote-community-item votes:${itemType}` },
    );
  } catch (err) {
    // Preserves the existing contract: this helper returns [] on failure and
    // the caller treats that as "nothing to promote this tick".
    console.warn(`[promote:${itemType}] vote count failed`, err);
    return [];
  }
  const counts = new Map<string, number>();
  for (const r of data as Array<{ item_id: string }>) {
    counts.set(r.item_id, (counts.get(r.item_id) ?? 0) + 1);
  }
  return Array.from(counts.entries()).map(([item_id, approves]) => ({
    item_id,
    approves,
  }));
}

/** Fire a OneSignal push to the submitter. Non-fatal on failure. */
async function notifySubmitter(
  userId: string,
  itemName: string,
  kind: "food" | "exercise",
) {
  if (!ONESIGNAL_APP_ID || !ONESIGNAL_REST_API_KEY) return;
  try {
    await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: [userId],
        headings: { en: "Your submission went live!" },
        contents: {
          en: `Your ${kind} "${itemName}" is now available for every ICANBEFITTER user.`,
        },
      }),
    });
  } catch (e) {
    console.warn("[promote:notify]", e);
  }
}
