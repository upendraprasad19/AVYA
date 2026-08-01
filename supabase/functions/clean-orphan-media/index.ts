import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
// 2.39.3, not 2.39.0 — this was the ONLY file in the tree on 2.39.0, and that
// lone version 522'd from esm.sh twice in 25 CI runs (2c4cbddd 2026-07-27,
// 93f6fe41 2026-07-28) while 2.39.3 (36 files) fetched fine in the very same
// runs. A version nobody else requests is cold at the CDN edge. Patch-level
// move, and it deletes the failing URL from the repo.
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { isAuthorizedCronCall } from '../_shared/cron_auth.ts';
import { logCronStart, logCronEnd } from '../_shared/cron_telemetry.ts';
import { fetchAllPages } from '../_shared/paged_fetch.ts';

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

    let scanned = 0;
    let deleted = 0;
    for (const obj of candidates ?? []) {
      scanned++;
      // Re-check isPro at delete time — user may have upgraded mid-window.
      const isPro = await rechecksIsPro(supabaseClient, obj.user_id);
      if (isPro) continue;
      await supabaseClient.storage.from('chat-media').remove([obj.path]);
      deleted++;
    }

    console.log(`[clean-orphan-media] request_id=${requestId} scanned=${scanned} deleted=${deleted}`);
    await logCronEnd(logId, 'success', { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({ scanned, deleted, request_id: requestId }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
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

async function rechecksIsPro(client: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await client
    .from('subscriptions')
    .select('end_date')
    .eq('user_id', userId)
    .eq('status', 'active')
    .gt('end_date', new Date().toISOString())
    .maybeSingle();
  return !!data;
}
