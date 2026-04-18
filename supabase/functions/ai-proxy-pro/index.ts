/**
 * ai-proxy-pro — deprecated 2026-04-18. Returns 410 Gone.
 *
 * Used to be the PRO-only AI coach endpoint (Cerebras Llama 3.3 70B).
 * As part of the Gemini-only consolidation we merged PRO chat into the
 * single `ai-proxy` function which now gates free vs PRO server-side.
 * Clients on the new APK (commit that ships this change or later) no
 * longer call this endpoint.
 *
 * Keeping the function alive as a 410 stub — instead of deleting it
 * outright — so orphan APK installs that still route PRO chat here get
 * a clear, structured error response with a redirect hint, rather than
 * a hard 500 or a timeout. Same pattern used for `admin-verify-payment`
 * when it was retired.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(
    JSON.stringify({
      error:
        "This endpoint has been merged into ai-proxy. Please update your app.",
      redirect: "ai-proxy",
      deprecated_at: "2026-04-18",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
