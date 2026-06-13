/**
 * get-community-review-items — returns pending community submissions from OTHER
 * users for the Profile → Submissions → COMMUNITY REVIEW queue.
 *
 * Why an Edge Function (diagnose: community-review-rls-context, 2026-06-13 Unit 2):
 *   The review queue must read OTHER users' submitted-but-not-approved custom
 *   foods / exercises. Both tables enforce own-only SELECT RLS
 *   (`auth.uid() = user_id`), so the client's cross-user `.neq('user_id', me)`
 *   read returned 0 rows → the queue was ALWAYS empty for everyone, and the
 *   community-vote → auto-promotion pipeline was inert. Relaxing the table RLS
 *   to world-read would expose every user's ENTIRE custom catalog (incl. private
 *   un-submitted rows) — a far larger hole. Instead this scoped service-role
 *   function returns ONLY `submitted && !approved` rows from OTHER users, with a
 *   narrow column projection and the submitter's `user_id` stripped (anonymized).
 *
 * Auth (CLAUDE.md rule #9 / e8a1c3): a PURE service-role client (no global
 * headers → BYPASSRLS) authenticates the caller via getUser(token). The caller
 * identity comes from the verified JWT — never from a client-supplied id.
 *
 * Input:  { kind: "food" | "exercise" }   (verify_jwt = true)
 * Output: { items: [...] }   (200)  |  { error: "..." }  (4xx/5xx)
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGE_LIMIT = 20;

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

  // PURE service-role client (no global headers → BYPASSRLS). Authenticate the
  // caller explicitly with getUser(token); the cross-user read below runs on
  // this same BYPASSRLS client.
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: authData, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authData?.user) {
    return clientError("Unauthorized", 401);
  }
  const callerId = authData.user.id;

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    // empty / non-JSON body tolerated → falls through to the kind check below
  }
  const kind = body?.kind;
  if (kind !== "food" && kind !== "exercise") {
    return clientError("kind must be 'food' or 'exercise'", 400);
  }

  try {
    if (kind === "food") {
      // `user_id` deliberately omitted from select() (anonymized); it is still a
      // valid filter target — PostgREST emits `user_id=neq.<id>` independent of
      // the projection.
      const { data, error } = await admin
        .from("user_custom_foods")
        .select(
          "id, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g",
        )
        .eq("submitted_to_db", true)
        .eq("approved", false)
        .neq("user_id", callerId)
        .limit(PAGE_LIMIT);
      if (error) throw error;
      return ok({ items: data ?? [] });
    }

    const { data, error } = await admin
      .from("user_custom_exercises")
      .select("id, name, category, logging_type")
      .eq("submitted_to_library", true)
      .eq("approved_for_library", false)
      .neq("user_id", callerId)
      .limit(PAGE_LIMIT);
    if (error) throw error;
    return ok({ items: data ?? [] });
  } catch (err) {
    return serverError("get-community-review-items", err);
  }
});
