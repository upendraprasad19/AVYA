// supabase/functions/weekly-recap-ready/index_test.ts
//
// Unit 3D-a (OI-175 / FOB-4): the Sunday Brief push names a Phase-I user's hold week ("Hold H2 debrief ready")
// instead of the clamped "Week 4". index.ts calls `serve(...)` at module scope, so importing it would boot a server:
// these are SOURCE pins (presence only), comment-stripped before every check. The behavioural proof is
// `_shared/hold_week_test.ts` (the message builder, the fail-closed phase filter, the IST week bounds and the
// never-throwing read against a stub client).
//
// Run:
//   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/weekly-recap-ready/

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

const code = stripComments(source);

Deno.test("weekly-recap-ready reads current_phase with the progress batch", () => {
  assert(
    code.includes('.select("user_id, current_week, current_phase")'),
    "the progress read must select current_phase (the hold filter needs it)",
  );
});

Deno.test("weekly-recap-ready asks for holds only for Phase-I users, only when the progress read succeeded", () => {
  const fulfilled = code.indexOf('if (progressResult.status === "fulfilled") {');
  const rejected = code.indexOf("} else {", fulfilled);
  assert(fulfilled > 0 && rejected > fulfilled, "the fulfilled branch must exist");
  const branch = code.slice(fulfilled, rejected);
  // B-pass F1: the batch step is one tested helper (recapHoldsForBatch: the phase gate and the window order are
  // proven end to end in _shared/hold_week_test.ts); this pins the call and that its map reaches the texts.
  assert(
    branch.includes("const holds = await recapHoldsForBatch(supabase, progressResult.value, week);"),
    "the hold read must be the batch helper inside the fulfilled branch",
  );
  assert(branch.includes("holdMap = holds.map;"), "the read's map must reach processUser (B-pass F2)");
  assert(code.includes("const week = istWeekBounds(new Date());"), "the bounds must come from istWeekBounds");
});

Deno.test("weekly-recap-ready builds the push text with recapMessage and the hold map", () => {
  assert(
    code.includes("message: recapMessage(firstName, currentWeek, holdMap.get(userId) ?? null),"),
    "the push text must come from recapMessage with the user's hold",
  );
  assert(!code.includes("debrief ready. Stand to.`"), "no hand-built debrief text may remain in index.ts");
  assert(
    code.includes("processUser(user, notifPrefs, progressMap, holdMap, supabase)"),
    "processUser must receive the hold map",
  );
});

Deno.test("weekly-recap-ready reports a failed hold read in its response and summary", () => {
  assert(code.includes("if (holds.failed) holdReadFailed = true;"), "a failed read must be recorded");
  assert(code.includes("hold_read_failed: holdReadFailed,"), "the response JSON must carry hold_read_failed");
  assert(code.includes("hold_read_failed=${holdReadFailed}"), "the summary line must carry hold_read_failed");
  assert(
    code.includes('...(holdReadFailed ? { errorSummary: "hold_read_failed" } : {}),'),
    "cron_call_log must carry the failed hold read (B-pass F3)",
  );
});
