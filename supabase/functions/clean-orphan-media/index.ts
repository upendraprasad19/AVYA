import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
// 2.39.3, not 2.39.0 — this was the ONLY file in the tree on 2.39.0, and that
// lone version 522'd from esm.sh twice in 25 CI runs (2c4cbddd 2026-07-27,
// 93f6fe41 2026-07-28) while 2.39.3 (36 files) fetched fine in the very same
// runs. A version nobody else requests is cold at the CDN edge. Patch-level
// move, and it deletes the failing URL from the repo.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { isAuthorizedCronCall } from '../_shared/cron_auth.ts';
import { logCronStart, logCronEnd } from '../_shared/cron_telemetry.ts';
import { fetchAllPages } from '../_shared/paged_fetch.ts';
import { isSystematicFailure, runErrorSummary, runSweep } from './logic.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // audit-2026-05-16 E.14.C — replaced inline env-equality JWT auth
  // (Test #16 P1-D drift class) with shared `isAuthorizedCronCall(req)`.
  // Survives Vault/env key rotation: verifies JWT signature against
  // SUPABASE_JWT_SECRET + role-claim === 'service_role'. CRON_SECRET
  // opaque-token escape hatch preserved inside the helper.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID().split('-')[0];
  const logId = await logCronStart('clean-orphan-media');
  const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    // OI-30 (audit-2026-05-17 Hermes F5) — switched to chat-media. Migration
    // 070 designates `coach-media` as long-term consented retention (user
    // explicitly saved the photo for future reference); `chat-media` is the
    // transient analysis bucket with documented 30-day TTL for free users.
    // Pre-fix this RPC + the storage.remove below targeted `coach-media`,
    // which would silently delete consented saves. Migration 071 renamed
    // the RPC + flipped the bucket filter; the old function is dropped to
    // make any stale caller fail loudly.
    // OI-79: paged. Truncation here failed SAFE (orphans survive rather than
    // live objects being deleted), which is why it is not Class 1 — but it
    // still meant the cleanup silently stopped at 1000 objects per tick and
    // never caught up, growing the orphan backlog without any signal.
    // Shape matches the RPC's live signature: TABLE(user_id uuid, path text).
    let candidates: Array<{ user_id: string; path: string }> | null = null;
    let error: unknown = null;
    try {
      candidates = await fetchAllPages<{ user_id: string; path: string }>(
        () => supabaseClient.rpc('find_orphan_chat_media', { p_cutoff: cutoff }),
        { orderBy: 'path', label: 'clean-orphan-media orphans' },
      );
    } catch (e) {
      error = e;
    }

    if (error) {
      console.error(`[clean-orphan-media] request_id=${requestId} rpc_error`, error);
      await logCronEnd(logId, 'failed', {
        httpStatus: 500,
        requestId,
        errorSummary: String(error),
      });
      return new Response(
        JSON.stringify({ error: 'Internal server error', request_id: requestId }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // OI-321 (bug class 2.49): the per-candidate PRO recheck and the removal live
    // in ./logic.ts. An object is removed ONLY when the subscription read
    // succeeded and found no active unexpired row; an unreadable read leaves it
    // for tomorrow's run. The counts below say how many were left and why.
    const result = await runSweep(supabaseClient, candidates ?? []);

    const line =
      `[clean-orphan-media] request_id=${requestId} scanned=${result.scanned} deleted=${result.deleted} ` +
      `skipped_pro=${result.skippedPro} skipped_unknown=${result.skippedUnknown} ` +
      `failed=${result.failed} already_gone=${result.alreadyGone}`;
    if (result.skippedUnknown > 0 || result.failed > 0) console.warn(line);
    else console.log(line);

    // A run that could not decide or remove MOST of its candidates is a failed
    // run (see isSystematicFailure): it pages through alert_cron_failures instead
    // of ending `success` with nothing deleted. Anything milder stays `success`
    // and is recorded on error_summary.
    const status = isSystematicFailure(result) ? 'failed' : 'success';
    const httpStatus = status === 'failed' ? 500 : 200;
    await logCronEnd(logId, status, {
      httpStatus,
      requestId,
      errorSummary: runErrorSummary(result),
    });
    return new Response(
      JSON.stringify({
        ...(status === 'failed' ? { error: 'Sweep could not decide most candidates' } : {}),
        scanned: result.scanned,
        deleted: result.deleted,
        skipped_pro: result.skippedPro,
        skipped_unknown: result.skippedUnknown,
        failed: result.failed,
        already_gone: result.alreadyGone,
        request_id: requestId,
      }),
      { status: httpStatus, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error(`[clean-orphan-media] request_id=${requestId}`, err);
    await logCronEnd(logId, 'failed', {
      httpStatus: 500,
      requestId,
      errorSummary: String(err),
    });
    return new Response(
      JSON.stringify({ error: 'Internal server error', request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
