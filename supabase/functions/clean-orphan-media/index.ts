import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

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

  // ── C-4 cron-auth gate ───────────────────────────────────────────────
  // Audit 2026-05-11 / closes-diagnose 7ad0c4. These cron functions had
  // `verify_jwt: false` and no manual auth. Now require Bearer == either
  // SUPABASE_SERVICE_ROLE_KEY (existing pg_cron path) OR CRON_SECRET
  // (rotatable hardening). If CRON_SECRET env var is unset, only the
  // service-role-key path works — graceful rollout.
  {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.slice('Bearer '.length)
      : '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const cronSecret = Deno.env.get('CRON_SECRET');
    const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
    const isCronSecret = !!cronSecret && token === cronSecret;
    if (!isServiceRole && !isCronSecret) {
      console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID().split('-')[0];
  const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data: candidates, error } = await supabaseClient.rpc('find_orphan_coach_media', {
      p_cutoff: cutoff,
    });

    if (error) {
      console.error(`[clean-orphan-media] request_id=${requestId} rpc_error`, error);
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
      await supabaseClient.storage.from('coach-media').remove([obj.path]);
      deleted++;
    }

    console.log(`[clean-orphan-media] request_id=${requestId} scanned=${scanned} deleted=${deleted}`);
    return new Response(
      JSON.stringify({ scanned, deleted, request_id: requestId }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error(`[clean-orphan-media] request_id=${requestId}`, err);
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
