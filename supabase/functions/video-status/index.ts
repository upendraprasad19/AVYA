/**
 * video-status — deprecated 2026-04-18. Returns 410 Gone.
 *
 * Used to be the polling endpoint for Remotion/Lambda video render jobs
 * (shareable workout highlight reels). The video-share feature is
 * DEFERRED per docs/architecture/subscription.md "Shareable Cards" table — hidden until
 * post-launch. The old implementation had zero auth (used
 * SERVICE_ROLE_KEY without auth.getUser or user_id filter), which meant
 * anyone knowing a jobId could poll anyone else's render status (IDOR).
 *
 * Rather than half-fix the auth on a dormant feature, we're 410-Gone
 * stubbing it. When the video-share feature is un-deferred, rewrite
 * this function with proper JWT + user_id filter before deploying.
 *
 * Same pattern used for `ai-proxy-pro` (retired 2026-04-18) and
 * `admin-verify-payment` (one-off admin tool, retired earlier).
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(
    JSON.stringify({
      error:
        "video-status is deprecated. The video-share feature is deferred.",
      deprecated_at: "2026-04-18",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
