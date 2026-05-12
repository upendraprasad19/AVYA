// Disabled. Was a one-shot admin Storage wipe used on 2026-04-17 to
// clean orphaned bucket objects after a full DB reset. Left deployed
// (MCP has no delete) but neutralised: returns 410 Gone for every call,
// and verify_jwt is true so anon traffic is auto-rejected.
Deno.serve(() => new Response(
  JSON.stringify({ error: "disabled" }),
  { status: 410, headers: { "Content-Type": "application/json" } },
));
