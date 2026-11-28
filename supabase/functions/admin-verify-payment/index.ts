// Disabled. One-shot admin payment verify/capture tool used on 2026-04-17
// to recover an authorized-but-not-captured Razorpay test payment. Left
// deployed (MCP has no delete) but neutralised: returns 410 Gone, and
// verify_jwt is true so anon traffic is auto-rejected.
Deno.serve(() => new Response(
  JSON.stringify({ error: "disabled" }),
  { status: 410, headers: { "Content-Type": "application/json" } },
));
