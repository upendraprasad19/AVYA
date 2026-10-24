// supabase/functions/_shared/write_claim_detector_test.ts
//
// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §2.4).
// The detector only LABELS a reply (never rewrites it). These cases pin the
// labels on the three real transcripts of 2026-10-21, every prescribed line, a
// fixture table of authored replies, word boundaries, and the log helper's
// privacy and never-throw contract.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DetectCtx,
  detectWriteClaim,
  logWriteClaimDetection,
  replayCtxOf,
} from "./write_claim_detector.ts";

const none: DetectCtx = {
  typedIntentTypes: [],
  legacyActions: [],
  replay: false,
  userAskedQuestion: false,
};

Deno.test("the three real transcripts (2026-10-21)", () => {
  // 13:19:59 — "log bench press": nothing proposed (OI-368).
  const a = detectWriteClaim(
    "Roger. Logged.\n\nI need the specifics for that session: sets, reps, and weight used. Stand to.",
    none,
  )!;
  assertEquals(a.token, "logged");
  assertEquals(a.safe_marker, null);
  assertEquals(a.negation, false);
  assertEquals(a.typed_log + a.typed_other + a.legacy_workout + a.legacy_auto, 0);

  // 13:21:37 — a logSet card was queued (OI-369).
  const b = detectWriteClaim(
    "Roger. Bench Press, 3 sets of 8, 60 kg. Logged. Carry on.",
    { ...none, typedIntentTypes: ["log_set"] },
  )!;
  assertEquals(b.token, "logged");
  assertEquals(b.typed_log, 1);

  // 13:29:24 — the legacy workout tag (stripped from the stored text).
  const c = detectWriteClaim(
    "Roger. Bench Press, 3 sets of 8, 60 kg. Logged. Carry on.",
    { ...none, legacyActions: [{ action: "confirm_workout_log", data: {} }] },
  )!;
  assertEquals(c.legacy_workout, 1);
});

Deno.test("every prescribed line gets its label; a mixed reply gets two, in order", () => {
  const cases: Array<[string, string]> = [
    ["Queued. Tap APPLY to log it.", "apply_log"],
    ["Queued. Tap APPLY to confirm.", "apply_confirm"],
    ["Queued. Tap APPLY on each card.", "apply_each"],
    ["Queued. Tap APPLY to save it. Want me to schedule it for Mon/Wed/Fri?", "apply_save"],
    ["Aye. Friday and Saturday trade places. Tap APPLY below to swap them.", "apply_swap"],
    [
      "Copy that, Recruit — I've queued that below. Review the details and tap APPLY to confirm.",
      "fc2",
    ],
    ["Queued. Tap CONFIRM to log it.", "confirm"],
    ["Queued. It logs in 5 seconds unless you tap SKIP.", "skip"],
  ];
  for (const [reply, label] of cases) {
    const d = detectWriteClaim(reply, none);
    assert(d !== null, reply);
    assertEquals(d.queued_lines, [label], reply);
  }
  const mixed = detectWriteClaim(
    "Queued. Tap APPLY to log it.\nQueued. It logs in 5 seconds unless you tap SKIP.",
    none,
  )!;
  assertEquals(mixed.queued_lines, ["apply_log", "skip"]);
});

Deno.test("the added tokens are labelled", () => {
  assertEquals(detectWriteClaim("Squared away.", none)!.token, "squared away");
  assertEquals(detectWriteClaim("Added.", none)!.token, "added");
  assertEquals(detectWriteClaim("On the books.", none)!.token, "on the books");
});

// [reply, token, safe_marker, negation]
const TABLE: Array<[string, string | null, string | null, boolean]> = [
  ["Logged.", "logged", null, false],
  ["Saved your water.", "saved", null, false],
  ["Recorded, Recruit.", "recorded", null, false],
  ["2 L added to today.", "added", null, false],
  ["Tracked.", "tracked", null, false],
  ["Locked in.", "locked in", null, false],
  ["Done. Carry on.", "done", null, false],
  ["Monday and Tuesday swapped.", "swapped", null, false],
  ["Plan paused for the week.", "paused", null, false],
  ["Goal switched to strength.", "switched", null, false],
  ["Friday moved to Saturday.", "moved", null, false],
  ["Week rescheduled.", "rescheduled", null, false],
  ["Today marked as rest.", "marked", null, false],
  ["Workout completed.", "completed", null, false],
  ["Target updated.", "updated", null, false],
  ["All set for tomorrow.", "all set", null, false],
  ["Tap APPLY and it's logged.", "logged", "tap", false],
  ["Queued; it will be logged once you confirm.", "logged", "queued", false],
  ["You logged 3 sets yesterday.", "logged", "yesterday", false],
  ["Your bench was logged 2 days ago.", "logged", "ago", false],
  ["You logged 7 hours last night.", "logged", "last night", false],
  ["You saved 3 meals last week.", "saved", "last week", false],
  ["Same as you logged last session.", "logged", "last session", false],
  ["The day shows as complete; it was marked earlier.", "marked", "as complete", false],
  ["Your snapshot shows it logged.", "logged", "snapshot", false],
  ["It will be saved when you tap CONFIRM.", "saved", "tap", false],
  ["Nothing logged yet. Send the sets and I'll queue it.", "logged", null, true],
  ["Squat not logged.", "logged", null, true],
  ["It isn't saved yet.", "saved", null, true],
  ["No workout recorded today.", "recorded", null, true],
  ["Logged ho gaya.", "logged", null, false],
  ["**Logged.**", "logged", null, false],
  ["You can log it from the Train tab.", null, null, false],
  ["How was your sleep?", null, null, false],
  ["Want me to queue 2 L of water?", null, null, false],
];

Deno.test("fixture table: token, safe marker, negation", () => {
  assert(TABLE.length >= 28);
  for (const [reply, token, marker, neg] of TABLE) {
    const d = detectWriteClaim(reply, none);
    if (token === null) {
      assertEquals(d, null, reply);
      continue;
    }
    assert(d !== null, reply);
    assertEquals(d.token, token, reply);
    assertEquals(d.safe_marker, marker, reply);
    assertEquals(d.negation, neg, reply);
  }
});

Deno.test("word boundaries on tokens and on markers", () => {
  for (const r of ["That set is undone.", "Unsaved draft.", "Plan abandoned."]) {
    assertEquals(detectWriteClaim(r, none), null, r);
  }
  assertEquals(detectWriteClaim("Logged with willpower.", none)!.safe_marker, null);
  assertEquals(detectWriteClaim("Logged after a blast night.", none)!.safe_marker, null);
});

Deno.test("untyped inputs never throw", () => {
  assertEquals(detectWriteClaim(undefined, none), null);
  assertEquals(detectWriteClaim(42, none), null);
  const d = detectWriteClaim("Logged.", {
    ...none,
    legacyActions: [{ action: 123 }, { data: null }, null, "x", { action: "log_water" }],
  })!;
  assertEquals(d.legacy_auto, 1);
  assertEquals(d.legacy_workout, 0);
});

Deno.test("replayCtxOf: no typed intents, the stored tags, replay true", () => {
  const actions = [{ action: "log_water", data: { ml: 500 } }];
  assertEquals(replayCtxOf({ actions }), {
    typedIntentTypes: [],
    legacyActions: actions,
    replay: true,
    userAskedQuestion: false,
  });
});

Deno.test("logWriteClaimDetection: one line, ids passed through, no reply text, no user id", () => {
  const lines: unknown[][] = [];
  const warns: unknown[][] = [];
  const reply = "Roger. Bench Press, 3 sets of 8, 60 kg. Logged. Carry on.";
  logWriteClaimDetection(
    "ai-proxy",
    "row-123",
    true,
    reply,
    () => ({ ...none, typedIntentTypes: ["log_set"], userAskedQuestion: true }),
    (...a) => lines.push(a),
    (...a) => warns.push(a),
  );
  assertEquals(lines.length, 1);
  assertEquals(warns.length, 0);
  assertEquals(lines[0][0], "[write-claim-detect]");
  const body = JSON.parse(lines[0][1] as string);
  assertEquals(body.fn, "ai-proxy");
  assertEquals(body.interaction_id, "row-123");
  assertEquals(body.rule_on, true);
  assertEquals(body.token, "logged");
  assertEquals(body.typed_log, 1);
  assertEquals(body.user_question, true);
  const text = JSON.stringify(lines);
  assert(!text.includes("Bench Press"), "reply text leaked");
  assert(!text.includes("Carry on"), "reply text leaked");
  assert(!("user_id" in body));
});

Deno.test("logWriteClaimDetection: nothing logged when there is no claim", () => {
  const lines: unknown[][] = [];
  logWriteClaimDetection("ai-proxy", null, true, "How was your sleep?", () => none, (...a) =>
    lines.push(a));
  assertEquals(lines.length, 0);
});

Deno.test("logWriteClaimDetection: a throwing ctx logs exactly the fixed string", () => {
  const lines: unknown[][] = [];
  const warns: unknown[][] = [];
  const secret = "my private reply text 42 kg";
  const ctx = {
    get typedIntentTypes(): string[] {
      throw new Error(secret);
    },
    legacyActions: [],
    replay: false,
    userAskedQuestion: false,
  } as DetectCtx;
  logWriteClaimDetection(
    "ai-proxy",
    "row-1",
    true,
    "Logged.",
    () => ctx,
    (...a) => lines.push(a),
    (...a) => warns.push(a),
  );
  assertEquals(lines.length, 0);
  assertEquals(warns, [["[write-claim-detect] skipped"]]);
});

Deno.test("logWriteClaimDetection: the ctx is built inside the try (a throwing ctx expression)", () => {
  // B-pass 1ed091ce8263 F3: the handler's ctx expressions run inside the
  // helper's try, so a future throw there cannot fail the reply.
  const lines: unknown[][] = [];
  const warns: unknown[][] = [];
  logWriteClaimDetection(
    "ai-proxy",
    "row-2",
    true,
    "Logged.",
    () => {
      throw new Error("my private reply text 42 kg");
    },
    (...a) => lines.push(a),
    (...a) => warns.push(a),
  );
  assertEquals(lines.length, 0);
  assertEquals(warns, [["[write-claim-detect] skipped"]]);
});

Deno.test("every claim sentence is read: a later false claim counts in unsafe_claims", () => {
  // B-pass 1ed091ce8263 F1: the first-hit fields stay; unsafe_claims counts
  // every claim sentence with neither a safe marker nor a negation.
  const behindSafe = detectWriteClaim(
    "Squat logged yesterday at 80kg. Bench Press, 3 sets of 8, 60 kg. Logged.",
    none,
  )!;
  assertEquals(behindSafe.token, "logged");
  assertEquals(behindSafe.safe_marker, "yesterday");
  assertEquals(behindSafe.unsafe_claims, 1);

  const behindNegation = detectWriteClaim("You haven't logged anything yet. Done.", none)!;
  assertEquals(behindNegation.negation, true);
  assertEquals(behindNegation.unsafe_claims, 1);

  assertEquals(detectWriteClaim("Roger. Logged. Carry on.", none)!.unsafe_claims, 1);
  assertEquals(detectWriteClaim("Logged. Saved. Done.", none)!.unsafe_claims, 3);
  assertEquals(detectWriteClaim("Queued. Tap APPLY to log it.", none)!.unsafe_claims, 0);
  assertEquals(detectWriteClaim("Nothing logged yet. Send the sets and I'll queue it.", none)!
    .unsafe_claims, 0);
});

Deno.test("a wrapped or double-spaced prescribed line still matches; a curly apostrophe negates", () => {
  // B-pass 1ed091ce8263 F2.
  const nb = String.fromCharCode(0xa0);
  for (const reply of [
    "Queued.\nTap APPLY to log it.",
    "Queued.  Tap APPLY to log it.",
    `Queued.${nb}Tap APPLY to log it.`,
  ]) {
    assertEquals(detectWriteClaim(reply, none)?.queued_lines, ["apply_log"], JSON.stringify(reply));
  }
  const curly = String.fromCharCode(0x2019);
  const d = detectWriteClaim(`It isn${curly}t saved yet.`, none)!;
  assertEquals(d.token, "saved");
  assertEquals(d.negation, true);
  assertEquals(d.unsafe_claims, 0);
});
