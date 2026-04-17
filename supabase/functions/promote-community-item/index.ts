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
 * `verify_jwt: true` — admins call via service-role key or a signed-in
 * admin JWT; end users can't invoke.
 *
 * Reference: docs/superpowers/plans... plan file Part 4 F18.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

const APPROVAL_THRESHOLD = 10;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return clientError("Method not allowed", 405);
  }

  try {
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── Promote foods ────────────────────────────────────────────
    const foodPromotions = await promoteFoods(admin);

    // ── Promote exercises ────────────────────────────────────────
    const exercisePromotions = await promoteExercises(admin);

    return ok({
      ok: true,
      foods_promoted: foodPromotions,
      exercises_promoted: exercisePromotions,
    });
  } catch (err) {
    return serverError("promote-community-item", err);
  }
});

async function promoteFoods(
  admin: ReturnType<typeof createClient>,
): Promise<number> {
  // Count approve votes per food item and pick those with ≥ threshold.
  const { data: candidates, error: countErr } = await admin.rpc(
    "community_votes_summary",
    { p_item_type: "food" },
  );
  const list = (candidates as Array<{ item_id: string; approves: number }> | null) ??
    (await fallbackCount(admin, "food"));
  if (countErr && !list) {
    console.warn("[promote:foods] count failed", countErr);
  }

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

    await notifySubmitter(source.user_id, source.name, "food");
    promoted++;
  }
  return promoted;
}

async function promoteExercises(
  admin: ReturnType<typeof createClient>,
): Promise<number> {
  const { data: candidates, error: countErr } = await admin.rpc(
    "community_votes_summary",
    { p_item_type: "exercise" },
  );
  const list =
    (candidates as Array<{ item_id: string; approves: number }> | null) ??
      (await fallbackCount(admin, "exercise"));
  if (countErr && !list) {
    console.warn("[promote:exercises] count failed", countErr);
  }

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

    await notifySubmitter(source.user_id, source.name, "exercise");
    promoted++;
  }
  return promoted;
}

/** Fallback count query if the RPC helper doesn't exist yet. */
async function fallbackCount(
  admin: ReturnType<typeof createClient>,
  itemType: "food" | "exercise",
): Promise<Array<{ item_id: string; approves: number }>> {
  const { data, error } = await admin
    .from("community_reviews")
    .select("item_id")
    .eq("item_type", itemType)
    .eq("vote", "approve");
  if (error || !data) return [];
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
