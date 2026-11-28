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
//       - template_exercises   → embedded under workout_templates (parent user_id). The
//                                scheduled_workouts→template embed is NOT parent-scoped (the FK is
//                                caller-writable): paged_reads.ts scopeEmbed nulls a foreign owner (C13).
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
//   projections (coach_memory 10-col, freezes 5-col, referral_codes 3-col, redemptions
//   5-col, users 2-col), so the client `_restoreX` parsers hydrate UNCHANGED. The caps of the
//   NON-paged reads (limit 1/20/50/52/200/500) inherit today's behaviour verbatim (H-9); the
//   thirteen paged reads return EVERY row up to 50,000 per table. Column names are verbatim (H-11).
//   Unit 3b (OI-45 cross-device half, e6b9c4): freezes went 4-col -> 5-col to add
//   streak_progress_version — the legacy client-side _restoreFreezes select was updated in
//   the same commit, and this projection must keep matching it per H-1's own contract.
//
// ── PAGED READS (diagnose: restore-user-snapshot returns every row) ──
//   PostgREST clamps every response to `db-max-rows` (1000) with HTTP 200 and error === null, so a
//   single `.range(0, 49999)` silently returned at most 1000 rows. The thirteen bulk reads and the
//   coach window now live in `./paged_reads.ts` (testable without booting this module): every one
//   pages through `_shared/paged_fetch.ts` until an EMPTY page, applies its own `user_id` scope
//   (code-owned, never data), and orders by an explicit, unique-ended key. Beyond 50,000 rows in
//   one table, or beyond the per-request page budget across all of them, a read THROWS → the catch
//   below → 500 → the client's verbatim legacy restore (fail-closed).
//
// verify_jwt: true at deploy (user must be authenticated; gateway pre-check + getUser here).
// Plan: ~/.claude/plans/restore-single-call-c3.md.
// Live version: ask `list_edge_functions` (the deploy skill records each deploy in its diagnose
// doc); SyncService._singleCallKillSwitch defaults OFF, so the client attempts this path by
// default. Any edit to this file's response shape is a LIVE behavior change, not future-proofing —
// redeploy + smoke-test accordingly.
// closes-diagnose: (restore-perf single-call) — see docs/diagnoses on impl.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { createPageBudget, rowCountLogLine, UUID_RE } from "./paged_reads.ts";
import { assembleTables, parseReadConcurrency } from "./restore_reads.ts";

// Bump SCHEMA_VERSION whenever the bundle shape or table set changes — the client
// rejects a bundle whose schema_version it does not recognise (→ legacy fallback).
const SCHEMA_VERSION = 1;

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

// The H-4 guard uses the ONE UUID_RE exported by paged_reads.ts (the readers re-validate with the
// same regexp): a token-derived user.id that is null / empty / non-UUID is rejected BEFORE any
// query, so a fail-open cross-user read is impossible.

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

    const authStarted = performance.now();
    const { data: userData, error: userErr } = await db.auth.getUser(token);
    const vUid = userData?.user?.id;
    // H-4: bind the non-empty UUID invariant BEFORE building ANY query. Covers
    // getUser → {user:null, error:null} (deleted user / edge) and empty/non-UUID id.
    if (userErr || !vUid || typeof vUid !== "string" || !UUID_RE.test(vUid)) {
      return jsonError(401, "unauthenticated", requestId);
    }

    // ── 2. ASSEMBLE THE BUNDLE — fail-closed. Any read throw → caught below → 500. ──
    // OI-348 B10 (a0d5f7): the reads live in ./restore_reads.ts (READS, in the bundle's key
    // order) and run with at most RESTORE_READ_CONCURRENCY in flight (read PER REQUEST, so a
    // dashboard change applies on the next call; 1 = the old serial order). Every read is scoped
    // to the vUid validated above. ONE page budget per request, shared by every paged read
    // (paged_reads.ts: TOTAL_PAGE_BUDGET, charged per page).
    const budget = createPageBudget();
    const limit = parseReadConcurrency(Deno.env.get("RESTORE_READ_CONCURRENCY"));
    const { tables } = await assembleTables(db, vUid, budget, limit, {
      authMs: performance.now() - authStarted,
      requestId,
    });

    // Table names and row COUNTS only (never a row value): the live behaviour of the paged reads
    // is read from the function logs, since no user token is available to smoke-test with.
    console.log(rowCountLogLine(requestId, tables));

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
