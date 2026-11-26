---
unit: a2b-1
parent_plan: docs/plans/2026-09-26-single-owner-batch-a.md
supersedes: docs/plans/2026-09-27-single-owner-a2b-plan.SUPERSEDED.md (split per
  §4.12.1 after round-1 review found 14 findings and explicitly recommended
  splitting into three pieces)
depends_on: single-owner-a2 (a2a) — rebased onto a2a's real commits, not main,
  since a2a has not yet merged
blast_radius: account
status: REWRITTEN twice. Round 1 found 3 of 6 fixes underspecified in ways that
  risk shipping something WORSE than the bug (silent-skip-on-outage, an unbounded
  metering fix, a sibling-guard regression) — folded in. Round 2 (live-verified)
  found round 1's OWN fixes still had 3 material gaps in the SAME three
  mechanisms (the raw-string comparison anti-pattern round 1 named was still
  present in round 1's own reference code; the consume-quota fix specified WHEN
  but not what happens on exhaustion/error; the const-identifier requirement for
  `founder_digest_caps_mirror_test.dart` covers only 1 of 3 required RPC
  arguments) plus 2 P2s (an unnecessary re-embed on every empty-extraction cycle;
  a second unpatched copy of the timestamp bug in `sync_coach.dart` itself) and 2
  P3s. Round 3 (live-verified) confirmed all of round 2's fixes hold correctly
  against real code/tests and found only ONE new item — a P2 dead-literal +
  unstated scope-narrowing in the channel allowlist (`"chat"` never persisted;
  `food_text_analysis` silently dropped despite carrying real content) — now
  fixed. CONVERGED per the reviewer's own recommendation: this is a
  scoping/citation-class fix, not a redesign. `review_rounds: 3`,
  `verdict: converged`.
date: 2026-09-27
---

# a2b-1 — coaching-notes extraction: watermark, meter, channel filter (EF + client only)

Split from the original unified a2b plan per round-1 review's explicit recommendation.
This is the EDGE-FUNCTION-AND-CLIENT-ONLY piece: it does not touch `user_profile`'s
manual-edit-lock question (that's `a2b-2`, blocked on a founder decision) or the
snapshot size bound (`a2b-3`, also blocked on a founder decision). Scope: fix the
watermark read so it correctly advances, correctly bounds itself, and correctly meters
extraction — closing the recurrence-class bug this whole batch traces back to (OI-162,
unmetered Gemini calls).

## Ground truth (from round-1 review, verified live — re-confirm at implementation
time since more time may have passed)

1. **Current read** (`daily-snapshot/index.ts:67-74`, post-a2a): selects
   `user_message, ai_response` filtered ONLY by `.eq(user_id)` + the whole IST
   calendar day, ascending, `.limit(30)` — no channel filter.
2. **Live channel composition over 60 days** (round-1 F1): `app_event` rows (52,
   `user_message` like `{event: …}`, empty `ai_response`); `food_text_analysis`
   (meal text + nutrition JSON); `scan_meal` (`"[scan_meal] analysis"` /
   `"success"`); `in_app` (14) and `promotion_ceremony` (11, empty `user_message`);
   `in_app_orphan` (34 — the LARGEST chat channel, bigger than `app`'s 21) and `app`
   (21). The channel allowlist alone does not close the `app_event`-shaped rows that
   land inside `in_app_orphan` — needs an additional content filter (item 3 below).
3. **CRITICAL — `in_app_orphan` rows carry FUTURE-DATED `created_at` values, live
   confirmed** (round-1 F2): `sync_coach.dart:208` writes `created_at:
   entry['created_at']`, and the client creates that value with
   `DateTime.now().toIso8601String()` (`coach_interaction_repository.dart:53,121`) —
   LOCAL time with NO UTC offset, so when read back it is misinterpreted as UTC and
   ends up ~5h30m in the FUTURE relative to the actual event. Live-verified pairs: the
   same message appears as `app` at 09:38:32 and as `in_app_orphan` at 15:08:29
   (+05:29:56 — i.e. exactly IST's UTC offset). A naive `.gt(watermark)` read with no
   upper bound reads the future-dated orphan row and jumps the watermark ~5.5h ahead,
   silently skipping every real `app` chat in that window.
4. **Microsecond precision is lost in a JS Date round-trip** (round-1 F3):
   `created_at` has microsecond precision (e.g. `13:21:25.447837`);
   `new Date(existing.last_extraction_at).toISOString()` truncates to milliseconds,
   so the last row read always still satisfies `created_at > (truncated) watermark`
   — causing a PERMANENT re-read loop on every single bucket, re-consuming a quota
   unit and re-running Gemini on the same already-processed turn every time.
5. **`extractCoachingNotes` returns `null` for `{}`** (`:188`) — an empty extraction
   (the NORMAL case per the parent plan's own framing) must still count as "the read
   succeeded" for watermark-advancement purposes; gating advancement on
   `extractedFacts` being non-null would leave every no-fact turn stuck being
   re-read every bucket until it ages past the 48h floor.
6. **`mergeCoachMemoryFields:291` is a SECOND writer of `last_extraction_at`**,
   writing wall-clock `new Date().toISOString()` — if left in place, a successful
   extraction over a >30-row backlog jumps the watermark past unread rows 31+ and
   past anything inserted during the ~15s Gemini call itself.
7. **The `isStale` guard (`index.ts:460-466`) still exists post-a2a** and, combined
   with item 3's future-dated rows, can suppress extraction entirely by comparing
   `now` against a `created_at` that is already in the future. The a2a-shipped test
   (`index_test.ts:192-212`) pins its presence — this fix must repoint that test to
   assert its ABSENCE, not merely leave it be.
8. **`consume_quota`'s limit is per `(user_id, quota_key, window_start)`**
   (migration 128) — `consume_quota(uid, 'coach_extraction', <6h bucket>, 4)` allows
   **16/day**, not "≤4/day" as intended. The correct call is `limit = 1` per 6h
   bucket (4 buckets/day × 1 = 4/day).
9. **`founder_digest_caps_mirror_test.dart`'s mirror check SKIPS cap validation for
   sub-day quota keys** — it would NOT catch item 8's wrong limit on its own. A
   dedicated Deno test must pin `p_limit = 1` directly.
10. **`usage_quota_ledger_writer_to_reader_test.dart`'s census requires the literal
    substring `consume_quota` to appear in `daily-snapshot/index.ts` itself** (not
    merely imported via a shared constant) — the fix must keep this literal string
    present and add this file to the test's allowlist (its `consume_quota`
    call-site allowlist specifically — this file has no advisory `usage_counters`
    SELECT, so it does not belong on that separate, second allowlist).
11. **P1 (review) — deleting `mergeCoachMemoryFields:291`'s wall-clock write
    breaks a sibling guard 2 lines below it, and the two must land together.**
    `index.ts:293` reads `if (Object.keys(patch).length > 1) { await
    upsertCoachMemory(...) }`. That `> 1` only works today BECAUSE
    `last_extraction_at` is unconditionally added to `patch` as a guaranteed
    extra key — the real intent is "at least one identity field besides the
    timestamp." Delete line 291 alone and a single-fact extraction (e.g. only
    `preferred_name` set) yields `Object.keys(patch).length === 1`, fails `> 1`,
    and SILENTLY STOPS PERSISTING — a real regression in coach identity capture,
    introduced by this exact fix. **Design §1's deletion of line 291 must land in
    the SAME commit as changing `:293`'s `> 1` to `> 0`.**
12. **P1 (review) — item 5's "`{}` must still advance the watermark" fix has no
    specified mechanism, and the current code structurally prevents the naive
    one.** `extractCoachingNotes` returns `null` for BOTH "Gemini call failed"
    (`!rawText`, `:164-179`) and "Gemini succeeded, extracted nothing" (`:187-188`)
    — the SAME return value for two outcomes that need OPPOSITE watermark
    behavior (advance on the second, retry on the first). Design §1 below must
    give this function an explicit third state distinguishing them BEFORE
    implementation — advancing on every `null` resurrects a silent-skip-forever
    failure mode on a genuine Gemini outage; advancing on neither reproduces the
    original recurrence bug this unit exists to close.
13. **P1/P2 (review) — consume-quota ordering vs. the Gemini call is
    unspecified, and this is the EXACT OI-162 unmetered-Gemini-call bug class
    this batch traces back to.** Every OTHER quota-gated Gemini caller in this
    codebase (`ai-proxy`'s food_text/chat/vision triggers, `ai-media-proxy`,
    `weekly-report`) consumes BEFORE calling Gemini (the reservation pattern) —
    if this unit's consume happens AFTER a successful parse instead, two
    overlapping `daily-snapshot` invocations inside the same 6h bucket can both
    pass the (unmoved) watermark, both spend a real Gemini call, and only the
    SECOND `consume_quota` call returns `-1` — an unmetered Gemini call slips
    through, the exact class OI-162 exists to close. **Design §3 below now states
    explicitly: consume immediately after the non-empty-read check, BEFORE
    calling Gemini** — client-side coalescing (`pushSnapshot`) bounds one
    device's own call rate but does not serialize two near-simultaneous
    edge-function invocations against each other, so this cannot be left
    implicit.
14. **P2 (review) — "IST 6h-bucket-aligned window_start" phrasing risks a hard
    CI break via naming convention, not just semantics.** `delete-account/
    index.ts:161-169` and `verify-payment/index.ts` both argue explicitly
    (Hermes L21 F3) that sub-day rate-limit buckets should be UTC epoch-floor
    (`Math.floor(Date.now()/WINDOW_MS)*WINDOW_MS`), not IST-aligned, since a
    sub-day bucket has no user-visible reset. More concretely:
    `founder_digest_caps_mirror_test.dart`'s `_resolveKind()` classifies a
    `p_window_start` binding as `subday` ONLY if its initializer expression
    contains the literal substring `bucketStartMs`; anything else is `null`, and
    `_efSites()` calls `fail()` outright ("unresolvable consume_quota site")
    rather than merely mis-tagging it. Design §3 below now says explicitly to
    reuse the `bucketStartMs` idiom from `delete-account`/`verify-payment`
    (UTC epoch-floor, 6h window), not "IST-aligned" — literal adherence to the
    old phrasing would hard-fail the whole test file at commit/CI time, not just
    mis-tag one assertion.
15. **P1 (round 2, live-verified) — round 1's OWN reference code (Design §1)
    still contained the exact raw-string-`>` anti-pattern round 1's own P3
    flagged, unfixed.** `existing.last_extraction_at > floorIso` compares
    Postgres-native text (offset + microseconds) against JS `toISOString()`
    output (`Z` suffix, milliseconds) — the same fragile cross-format `>` round
    1 named. **Simpler fix than a `Date.parse()` walk, and structurally immune
    to the format mismatch entirely: Postgres's `.order("created_at",
    {ascending: true})` already sorts by the real `timestamptz` value at full
    precision, so the client never needs to re-compare timestamps to find "the
    latest row" — just take `convos[convos.length - 1].created_at` (raw string,
    unmodified) as the new watermark.** The `readFromIso` FALLBACK comparison
    (deciding whether to trust the stored watermark or fall back to the 48h
    floor) is a genuine cross-format comparison and must use
    `Date.parse(existing.last_extraction_at) > Date.parse(floorIso)`, not a
    raw string `>`.
16. **P1 (round 2, live-verified) — no specified behavior when `consume_quota`
    returns `-1` or errors, and this is the exact hazard the ordering fix (item
    13) exists to prevent.** Every OTHER quota-gated Gemini caller in this
    codebase branches explicitly: `ai-media-proxy/index.ts:843-870` fails
    CLOSED on error/non-number and also skips Gemini on `-1`;
    `delete-account/index.ts:180-190` fails OPEN on RPC error (deliberate) but
    still an explicit `-1` branch; `verify-payment/index.ts:250-262` fails
    CLOSED with an explicit `-1` branch. Without an equivalent branch here, an
    implementer could plausibly call `consume_quota` and unconditionally
    proceed to Gemini regardless of the result — defeating item 13's fix
    entirely and reproducing OI-162's exact bug class. Separately, on a genuine
    `-1`/error the watermark must NOT advance (the rows were read but not
    actually processed by Gemini this cycle), so a later successful bucket
    still picks them up.
17. **P1 (round 2, live-verified) — `founder_digest_caps_mirror_test.dart`'s
    `_efSites()` requires ALL THREE of `p_quota_key`/`p_window_start`/
    `p_limit` to be bare `const NAME = <literal>;` identifiers referenced by
    name, not just `p_window_start` (which item 14 already covers).** Verified
    via the file's own regex (`:141-143`):
    `p_quota_key:\s*(\w+)\s*,\s*p_window_start:\s*(\w+)\s*,\s*p_limit:\s*(\w+)`,
    each group resolved through `_resolveStrings`/`_resolveInts` against a
    `const <that-name> = ...;` declaration. A quoted string literal
    (`"coach_extraction"`) breaks the `\w+` match entirely; a bare numeric
    literal (`1`) matches syntactically but fails resolution (looks for
    `const 1 = ...;`, which can never exist) — either shape hits an explicit
    `fail('unresolvable consume_quota site …')`, hard-failing the whole test
    file, the SAME hazard class item 14 already flagged for window-start,
    unaddressed for the other two arguments.
18. **P2 (round 2, live-verified) — calling `mergeCoachingNotes` on an
    empty-but-`ok` extraction wastes an upsert + a Gemini embedding call, up to
    4×/day/user.** `mergeCoachingNotes` (`:203-254`) unconditionally re-embeds
    ALL existing `coaching_notes` keys via `getEmbedding` whenever
    `flat.length > 0` (true for any user with pre-existing notes). Under the
    OLD code this only ever fired when `extractedFacts` was truthy AND
    non-empty. Under the NEW tri-state design, `result.facts` can be `{}`
    while `result.ok === true` — and `{}` is truthy in JS, so a naive
    `if (result.ok && result.facts)` gate would still invoke
    `mergeCoachingNotes({})` every "nothing new said" cycle. The decision to
    CALL `mergeCoachingNotes`/`mergeCoachMemoryFields` must stay gated on
    `Object.keys(facts).length > 0`, fully decoupled from the watermark-advance
    decision (which correctly fires on any `ok:true`, empty or not).
19. **P2 (round 2, live-verified) — `sync_coach.dart:208` has its OWN unpatched
    copy of the exact bug item 3 fixes, in the very file this unit already
    touches.** `'created_at': entry['created_at'] ?? DateTime.now()
    .toIso8601String()` — same non-UTC `DateTime.now()` pattern as
    `coach_interaction_repository.dart:53,121`. Low-probability trigger today
    (only fires when a Hive `coach_*` entry lacks `created_at`, which neither
    current writer produces) but zero-cost to patch (`.toUtc()`) in the SAME
    commit — leaving it is a second live copy of the anti-pattern this unit's
    stated goal ("fix the ROOT CAUSE, not just the symptom") exists to
    eliminate.
20. **P3 (round 2) — item 8's framing describes a hypothetical wrong
    implementation, not a live bug in shipped code.** `grep -n
    "consume_quota" supabase/functions/daily-snapshot/index.ts` returns
    nothing today — metering is entirely NEW code this unit adds, not an
    existing call being corrected. (Wording nit only, folded in for clarity —
    no design change.)
21. **P2 (round 3, live-verified) — Design §1's channel allowlist has a dead
    literal and an unstated scope narrowing.** The proposed `.in("channel",
    ["app", "chat", "in_app_orphan", "free_image_analysis"])`: **`"chat"` is
    never written as a channel value anywhere in the codebase** — grepped
    every Edge Function for `channel:` literals; the only chat-shaped
    persisted value is `"app"` (`ai-proxy/index.ts:797,1187`); `"chat"` only
    exists as the client's request `type` param, a DIFFERENT field, never the
    persisted `channel` column — harmless (matches zero rows) but confused,
    reads like the author conflated request-type with channel-column value.
    **`food_text_analysis` is silently excluded — an unstated, real scope
    narrowing.** The CURRENT pre-fix code has NO channel filter, so it scans
    every channel including `food_text_analysis`, whose `user_message` is the
    user's REAL typed meal-log text (`ai-proxy/index.ts:375`) — genuinely
    capable of carrying diet/food-preference facts (e.g. "grilled paneer, I'm
    vegetarian" typed while logging a meal). By contrast, `scan_meal`/
    `cart_auditor` only ever write a fixed system label (never real free
    text) and `in_app`/`promotion_ceremony` both write `user_message: ""`
    (excluded by the existing `.not(is null)/.neq("")` filters regardless of
    channel membership) — confirmed those three are harmless to drop, but
    `food_text_analysis` is the one exception with real content actually
    lost, and dropping it was never a stated design decision.

## Design

### 1. Watermark read — bounded both directions, string-cursor, correct advancement

```ts
// readStartIso is captured ONCE at the top of the function, before any query.
const readStartIso = new Date().toISOString();
const floorIso = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
// existing.last_extraction_at is the RAW Postgres string — never round-tripped
// through `new Date(...).toISOString()`, which truncates microseconds (item 4).
// CORRECTED (round 2, item 15): the fallback comparison is a genuine
// cross-format comparison (Postgres microsecond-precision text vs JS
// millisecond-precision text) and MUST use Date.parse() on both sides, never
// a raw string `>`.
const readFromIso = existing?.last_extraction_at &&
    Date.parse(existing.last_extraction_at) > Date.parse(floorIso)
  ? existing.last_extraction_at
  : floorIso;

const { data: convos } = await supabase
  .from("ai_coach_interactions")
  .select("user_message, ai_response, channel, created_at")
  .eq("user_id", userId)
  // CORRECTED (round 3, item 21): "chat" is a dead literal — it is never a
  // persisted channel value (only the client's request `type` param uses
  // it), never a "channel" column value. `food_text_analysis` is added back
  // deliberately — the pre-fix code scans it today and its user_message is
  // real free-typed meal-log text that can carry diet/preference facts (e.g.
  // "grilled paneer, I'm vegetarian"), unlike scan_meal/cart_auditor (fixed
  // system labels) or in_app/promotion_ceremony (empty user_message, already
  // excluded below regardless of channel).
  .in("channel", ["app", "food_text_analysis", "in_app_orphan", "free_image_analysis"])
  .gt("created_at", readFromIso)
  .lte("created_at", readStartIso)   // item 3 fix: bounds the future-dated-row problem
  .not("user_message", "is", null)
  .neq("user_message", "")
  .not("user_message", "like", "{event:%")  // item 2 fix: drops app_event-shaped rows
  .order("created_at", { ascending: true })
  .limit(30);
```

- **Advance the watermark to `convos[convos.length - 1].created_at` — the raw
  string of the LAST row returned, unmodified, never re-compared client-side**
  (item 15 fix, round 2 correction: round 1 proposed a `Date.parse()`-based
  "latest among rows read" comparison, which is unnecessary — the query's own
  `.order("created_at", {ascending: true})` already sorts by the real
  `timestamptz` value in Postgres at full precision, so taking the last array
  element is correct by construction and structurally immune to the
  Postgres-microsecond-vs-JS-millisecond format mismatch that motivated the
  comparison in the first place) — whenever Gemini returned content that
  PARSED, including an empty `{}` (item 5 fix). Do NOT advance on `!rawText`
  (a genuine call failure) — those turns must be retried next run. Do NOT
  advance on a `consume_quota` exhaustion/error either (item 16 — see Design
  §3).
- **`extractCoachingNotes` must return a THREE-STATE result, not a bare
  nullable** (item 12 fix, required BEFORE this can be implemented): something
  shaped like `{ok: true, facts: FactsOrNull}` on a genuine Gemini response
  (including an empty extraction) vs. a distinct failure signal (a thrown error,
  or `{ok: false}`) on `!rawText`. **CORRECTED (round 2) — this is genuinely a
  THREE-state contract, not two: the JSON.parse `catch` block on a non-empty
  but MALFORMED `rawText` (`:190-192`) is a third null-returning branch the
  original fix never named.** That catch must ALSO return `{ok: false}` — an
  implementer who folds it into `ok:true` (since `rawText` was technically
  non-null) would advance the watermark despite the extraction genuinely
  failing, silently losing that window's facts forever, reproducing this
  unit's own bug class via a different trigger. The watermark-advance decision
  reads this discriminant, never the bare return value — advancing on a
  genuine call/parse failure risks silently skipping messages forever during
  an outage; advancing on neither reproduces the original bug.
- **Delete `mergeCoachMemoryFields:291`'s wall-clock write, AND in the SAME
  change widen `:293`'s guard from `Object.keys(patch).length > 1` to `> 0`**
  (item 11 fix, non-optional pairing) — the advancement above becomes the ONLY
  writer of `last_extraction_at`, and the guard no longer silently relies on
  that timestamp write to supply its "one extra key."
- **Remove the `isStale` guard** (`index.ts:460-466`) (item 7 fix) — the watermark
  itself is now the staleness mechanism; repoint a2a's `index_test.ts:192-212` test
  to assert the guard's ABSENCE.
- **No consume, no Gemini call when the read returns zero rows** — unchanged from
  the existing "none → return without consuming" logic.
- Zero rows for a user with NO prior `coach_memory` row: confirm at implementation
  time that a `coach_memory` upsert creating a row whose only non-null field is
  `last_extraction_at` doesn't break restore or induction logic elsewhere (round-1
  F14 flagged this as an untested edge case).
- **CORRECTED (round 2, item 18) — decouple "call `mergeCoachingNotes`/
  `mergeCoachMemoryFields`" from "advance the watermark".** The watermark
  advances on any `ok:true` result (empty or not, per item 5). The MERGE call
  itself stays gated on `Object.keys(facts).length > 0` — an empty `{}`
  extraction advances the watermark but must NOT trigger
  `mergeCoachingNotes`'s unconditional re-embed of every existing key, which
  would otherwise fire on every "nothing new said" cycle (up to 4×/day/user).

### 1b. `sync_coach.dart:208` — patch the second unpatched copy of item 3's bug

`'created_at': entry['created_at'] ?? DateTime.now().toIso8601String()` at
`sync_coach.dart:208` has the identical non-UTC `DateTime.now()` pattern as
`coach_interaction_repository.dart:53,121` (item 19 fix) — add `.toUtc()` here
too, in the SAME commit as Design §2 below, even though this fallback branch
is rarely exercised today.

### 2. Client-side timestamp fix (`sync_coach.dart` / `coach_interaction_repository.dart`)

Fix the ROOT CAUSE of item 3, not just the server-side symptom: change
`DateTime.now().toIso8601String()` to `DateTime.now().toUtc().toIso8601String()` at
`coach_interaction_repository.dart:53,121`. This also fixes the 5-minute
cross-channel dedup at `sync_coach.dart:170-188`, which the same skew was defeating
(the `in_app_orphan` duplicates exist BECAUSE the dedup window couldn't match a
future-dated row against its same-content `app` counterpart).

### 3. Metering fix

```ts
const COACH_EXTRACTION_QUOTA_KEY = "coach_extraction";
const COACH_EXTRACTION_CAP = 1;
const bucketStartMs = Math.floor(Date.now() / SIX_HOURS_MS) * SIX_HOURS_MS;
const bucketStart = new Date(bucketStartMs).toISOString();

const { data: consumed, error: consumeError } = await supabase.rpc(
  "consume_quota",
  { p_user_id: userId, p_quota_key: COACH_EXTRACTION_QUOTA_KEY,
    p_window_start: bucketStart, p_limit: COACH_EXTRACTION_CAP },
);
if (consumeError || typeof consumed !== "number") {
  // fail CLOSED: log and skip Gemini this cycle; do NOT advance the watermark
  // (the rows were read but not processed — a later successful bucket must
  // still pick them up).
  console.error("[daily-snapshot.coach_extraction] consume_quota failed:", consumeError);
  return; // no Gemini call, no watermark advance
}
if (consumed === -1) {
  // already extracted this bucket — the normal "quota exhausted" case,
  // replacing the old isStale skip. No Gemini call, no watermark advance.
  return;
}
// consumed is a genuine positive integer — proceed to call Gemini.
```

**CORRECTED (round 2, item 16) — the exhaustion/error branch is now explicit,
non-optional.** Round 1 stated ONLY "consume before Gemini," with no specified
behavior on `-1`/error — every OTHER quota-gated Gemini caller in this codebase
(`ai-media-proxy`, `delete-account`, `verify-payment`) branches explicitly on
this, and without it an implementer could plausibly call `consume_quota` and
proceed to Gemini regardless of the result, defeating the ordering fix
entirely. On error/non-number: fail CLOSED (skip Gemini, log, do NOT advance
watermark). On `-1`: skip Gemini, do NOT advance watermark (already-processed
this bucket). Only a genuine positive integer proceeds to Gemini.

**CORRECTED (round 2, item 17) — name const identifiers for the quota key AND
the limit, not just the window-start (item 14).**
`founder_digest_caps_mirror_test.dart`'s `_efSites()` requires ALL THREE of
`p_quota_key`/`p_window_start`/`p_limit` to resolve through a bare
`const NAME = <literal>;` declaration — a quoted string or bare numeric
literal inline breaks its regex or its resolution and hard-fails the whole
test file. `COACH_EXTRACTION_QUOTA_KEY`/`COACH_EXTRACTION_CAP` above mirror
the `RATE_LIMIT_QUOTA_KEY`/`RATE_LIMIT_MAX` naming precedent from
`delete-account`/`verify-payment`. Preserve the field ORDER `p_quota_key,
p_window_start, p_limit` consecutively — the regex requires that adjacency.

`bucketStartMs`/`bucketStart` reuse the EXACT variable-naming idiom from
`delete-account`/`verify-payment` (item 14 fix) — not a differently-named/
shaped "IST-aligned" expression.

`DIGEST_KEYS` gains `{ key: "coach_extraction", label: "Coach
extraction", kind: "subday" }` — re-derive the exact "N of M" section-count wording
from the live `founder-digest` source at implementation time (per the original
plan's own caution: this has shifted since a3/a4's migrations landed).

## Dependents

- `daily-snapshot/index_test.ts` — repoint the `isStale`-presence assertion to
  assert absence (item 7); add tests per the Process section below.
- `usage_quota_ledger_writer_to_reader_test.dart` — add `daily-snapshot/index.ts` to
  the allowlist (item 10), keep the literal `consume_quota` substring present.
- `founder_digest_caps_mirror_test.dart` — add a dedicated assertion (not relying on
  the mirror's own sub-day skip) pinning `p_limit = 1` for `coach_extraction` (item
  9).
- `docs/architecture/ai.md`, `docs/architecture/sync.md`, `supabase/functions/CLAUDE.md`'s
  testing note — update to describe the watermark read replacing the whole-day
  window.

## Process

Diagnose-doc (rule 22, FULL template — this is a recurrence of the OI-162
unmetered-Gemini class). Tests (Deno, per round-1's explicit list):
- Microsecond-precision fixture: a row whose `created_at` differs from the stored
  watermark by microseconds only must NOT be re-read.
- Future-dated `in_app_orphan` row: present in the table but excluded by the
  `.lte(readStartIso)` bound.
- `{}` extraction (no facts) still advances the watermark.
- `mergeCoachMemoryFields` no longer writes `last_extraction_at` (grep-based
  regression test acceptable here, since it's a presence/absence check on a single
  line, not a behavioral claim).
- `isStale` guard removed. **CORRECTED (round 2, P3):** repointing
  `index_test.ts:192-212` to assert ABSENCE satisfies presence/absence but not
  the test's other job — it also currently asserts ORDERING (private_mode
  gates before the read/consume/extract sequence). The rewritten test must
  keep asserting that ordering, not just drop the isStale-specific assertion.
- Kill switch (`DISABLE_COACH_EXTRACTION`) — reconfirm untouched, a2a's existing
  test still covers it.
- Channel filter excludes `app_event`-shaped `user_message` content even inside an
  allowlisted channel.
- Metering: `p_limit = 1`, not 4.
- Metering ORDER (item 13): consume happens before the Gemini call, not after —
  a fake-transport test asserting `consume_quota` is called even when the
  downstream Gemini call is mocked to hang/fail, proving the two are not
  ordered the other way around.
- `mergeCoachMemoryFields`'s `:293` guard (item 11): a single-fact patch (one
  identity field, no timestamp) still triggers `upsertCoachMemory` — mutation:
  revert the guard to `> 1`, confirm this test reddens.
- `extractCoachingNotes`'s tri-state contract (item 12): a Gemini-call-failure
  and an empty-but-successful extraction must be distinguishable by the
  watermark-advance logic — two tests, one per outcome, asserting opposite
  watermark behavior. **A THIRD state is required too (round 2 finding, folded
  into item 12's own contract): the JSON.parse `catch` block on a non-empty,
  malformed `rawText` (`:190-192`) must ALSO return the failure discriminant
  (`{ok:false}`), same as `!rawText` — not silently folded into `ok:true`
  (which would advance the watermark despite the extraction genuinely
  failing).** Add a third test for this malformed-response case.
- Watermark advances to `convos[convos.length-1].created_at` (item 15) —
  mutation: feed rows out of the query's sort order into the test fixture,
  confirm the watermark still tracks the LAST element per array position, not
  a recomputed max.
- `consume_quota` exhaustion/error branches (item 16): on `-1`, Gemini is
  skipped AND the watermark does not advance; on an RPC error, Gemini is
  skipped AND the watermark does not advance; only on a positive integer does
  Gemini get called. Three tests, mutation-proven by deleting each branch in
  turn.
- `founder_digest_caps_mirror_test.dart` const-identifier resolution (item 17):
  confirm `COACH_EXTRACTION_QUOTA_KEY`/`COACH_EXTRACTION_CAP` resolve correctly
  through the file's own `_efSites()`/`_resolveStrings`/`_resolveInts` — this
  is best verified by actually running that test file against the real
  implementation, not a new isolated test.
- `mergeCoachingNotes` call gating (item 18): an empty `{}` extraction advances
  the watermark but does NOT call `mergeCoachingNotes`/`mergeCoachMemoryFields`
  — mutation: remove the `Object.keys(facts).length > 0` gate, confirm this
  test reddens (an unwanted merge call fires).
- `sync_coach.dart:208`'s fallback timestamp (item 19): a Hive entry missing
  `created_at` produces a UTC-suffixed fallback, not a naive local one.
Note for the diagnose-doc (not a blocker): a user offline >48h then back online
still only recovers the last 48h/30-turn window on first read — a real but
PRE-EXISTING gap (the old whole-IST-day read recovered even less), not a
regression introduced by this fix.
Mutate every NEW test per §4.4 rule 21 (e.g., revert the `.lte()` bound,
confirm the future-dated-row test reddens). Full gate loop before dispatch per
§4.12.5/.8. Fresh ×2 context-blind review of THIS document (not a continuation of
round-1's findings against the old unified plan — those are folded in above, but a
fresh round must verify the fold-in itself).
