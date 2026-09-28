---
unit: a2b
parent_plan: docs/plans/2026-09-26-single-owner-batch-a.md
blast_radius: platform
status: drafted — pending ×2 context-blind review (not yet dispatched: capacity —
  4 review agents already in flight for a3/a4, founder's max-4-concurrent-
  subagents rule)
date: 2026-09-27
depends_on: single-owner-a2 (a2a) — this branch is rebased onto a2a's real
  commits (0ea87ae3), not main, since a2a has not yet merged
---

# a2b — coaching-notes extraction: watermark reads, channel filter, size bound, manual-edit precedence

Builds directly on a2a's seam (exported `extractCoachingNotes` with injectable
`geminiChatFn`, `import.meta.main` guard, `DISABLE_COACH_EXTRACTION` kill switch,
private_mode gate before any read). a2a converged in round 4 (§4.12.1 split);
this unit continues under its own ×2 review, per round 4's own framing.

## Ground truth confirmed (2026-09-27, before drafting)

1. **Current read query, live** (`daily-snapshot/index.ts`, post-a2a):
   `extractCoachingNotes` selects `user_message, ai_response` from
   `ai_coach_interactions` filtered ONLY by `user_id` + the WHOLE IST calendar
   day (`.gte(...T00:00:00+05:30).lte(...T23:59:59+05:30)`), ascending,
   `.limit(30)` — **no channel filter at all**. This reads every row for the
   day regardless of channel, including non-conversational rows (`food_text_analysis`,
   `scan_meal`, `cart_auditor` — need to confirm at implementation time whether
   those rows even populate `user_message`/`ai_response` in a way that would
   corrupt the extraction prompt, or whether they're naturally empty/JSON-shaped
   there; if the former, the channel filter below is ALSO a correctness fix, not
   just a scope-widening one).
2. **Client's chat-render allowlist** (`coach_interaction_repository.dart:315`):
   `coachChatChannels = {'app', 'chat', 'in_app_orphan'}` — this deliberately
   EXCLUDES `free_image_analysis` because the client never renders vision-scan
   chats as coach conversation. Round-3's #3 finding requires daily-snapshot's
   OWN allowlist to be a SUPERSET adding `free_image_analysis` (extraction wants
   to learn from what a free-tier user said about their photo, even though the
   client never shows that exchange as "coach chat").
3. **`coach_memory.last_extraction_at`** already exists as a column
   (read by a2a's own private_mode gate at `fetchCoachMemory`) — the watermark
   design reuses this EXISTING column as the cursor rather than adding a new one.
4. **Manual-edit-wins precedence — real, load-bearing gap found during this
   ground-truth pass, not in the parent plan's own text.** `user_profile` (live
   schema, confirmed via `information_schema.columns`) has exactly ONE
   `updated_at` for the WHOLE ROW — no per-field timestamp, no existing
   "user manually set this" marker anywhere in the schema or in
   `daily-snapshot/index.ts`'s `mergeCoachingNotes` tail (`profileUpdates`
   block, writes `diet_preference`/`lifestyle_activity`/`injuries` into
   `user_profile` unconditionally whenever `extracted` carries them).
   `edit_profile_screen.dart` DOES write these same 3 fields
   (lines 1848/1852/1853), synced via `sync_profile.dart:226-229`. **But**:
   only `injuries` has an `_original*` tracker (`_originalInjuries`, line 95) —
   `diet_preference`/`lifestyle_activity` have NO such tracker, and the screen
   ALWAYS re-sends both on every save regardless of whether the user actually
   touched them (they're pre-filled from the existing profile at load time,
   lines 222-225, with hardcoded fallback defaults `'desk_job'`/`'veg'` if
   absent). **This means a naive "lock the field the moment edit_profile_screen
   saves" would over-lock**: ANY profile save for an unrelated reason (e.g. a
   weight update) would silently and permanently lock diet_preference/
   lifestyle_activity out of extraction for every user who has ever saved their
   profile once — defeating extraction's purpose for those two fields from day
   one. The design below closes this by adding the SAME kind of `_original*`
   guard the file already uses for injuries, to the other two fields, BEFORE
   locking on a save.
5. **`digest`/ledger allowlist mechanism** — `CONSUME_QUOTA_RPC` constant lives
   in `_shared/prediction_handler.ts:41` (`"consume_quota"`), consumed by
   `test/contracts/usage_quota_ledger_writer_to_reader_test.dart`'s reader-side
   group (not yet read in full at plan time — confirm the exact allowlist
   shape at implementation time before assuming the `coach_extraction` key
   slots in the same way `prediction_daily` did).

## Design

### Watermark read (replaces the whole-day window)

```ts
// Read strictly newer than the watermark, oldest-first, capped, with a
// 48h floor so a user who was never extracted (or whose watermark is very
// stale) doesn't pull an unbounded backlog into one Gemini call.
const watermark = existing?.last_extraction_at
  ? new Date(existing.last_extraction_at)
  : new Date(Date.now() - 48 * 60 * 60 * 1000);
const floor = new Date(Date.now() - 48 * 60 * 60 * 1000);
const readFrom = watermark > floor ? watermark : floor;

const { data: convos } = await supabase
  .from("ai_coach_interactions")
  .select("user_message, ai_response, channel, created_at")
  .eq("user_id", userId)
  .in("channel", ["app", "chat", "in_app_orphan", "free_image_analysis"])
  .gt("created_at", readFrom.toISOString())
  .not("user_message", "is", null)
  .neq("user_message", "")
  .order("created_at", { ascending: true })
  .limit(30);
```

- Watermark ADVANCES to the LATEST `created_at` among the rows actually read,
  written back to `coach_memory.last_extraction_at` ONLY after a non-null
  Gemini result (a failed extraction must not advance the watermark and lose
  those turns — they get picked up on the next run instead).
- `.not("user_message", "is", null).neq("user_message", "")` closes the
  ground-truth item 1 concern defensively even if non-chat channels turn out
  to populate `user_message` in some empty/JSON form — belt-and-suspenders
  with the channel filter, not a replacement for it.
- No consume/no Gemini call when the read returns zero rows (existing
  "none → return without consuming" logic from the round-3 disposition,
  unchanged by this redesign).

### Manual-edit precedence

1. **Migration**: add `coach_extraction_locked_fields text[] NOT NULL DEFAULT '{}'`
   to `user_profile` — one array column listing which of
   `diet_preference`/`lifestyle_activity`/`injuries` the user has manually set.
2. **`edit_profile_screen.dart`**: add `_originalDietPreference`/
   `_originalLifestyleActivity` trackers, captured at the SAME point
   `_originalInjuries` already is (line 294) — mirroring the existing pattern
   exactly, not inventing a new one. On save, for each of the 3 fields, if the
   CURRENT value differs from its `_original*` value, add that field's name to
   a `newlyLockedFields` set. `sync_profile.dart`'s `_syncUserPreferences`
   payload (or wherever `user_profile` itself gets upserted — confirm the exact
   upsert call site at implementation time, this may be a different sync method
   than the one already read for `user_preferences`) unions
   `newlyLockedFields` into the existing `coach_extraction_locked_fields` array
   server-side (`array_cat` + `array(select distinct unnest(...))` dedup, or a
   dedicated small RPC mirroring `merge_notification_preferences`'s own
   per-key-additive pattern already used for a different field on the same
   table family — confirm which is more consistent with existing conventions
   at implementation time).
3. **`daily-snapshot/index.ts`'s `mergeCoachingNotes` tail** (`profileUpdates`
   block): before adding `diet_preference`/`lifestyle_activity`/`injuries` to
   `profileUpdates`, read `coach_extraction_locked_fields` from the SAME
   `user_profile` row already being touched, and skip any field present in
   that array. The user_preferences.coaching_notes JSON blob (a2a's own newly
   registered SoT concept) is UNCHANGED by this — the lock applies only to the
   `user_profile` tail-write, never to the coaching_notes JSON itself (the
   coach can still SEE what it extracted from the JSON blob; it just can't push
   a locked field back onto the user's own profile settings).

### Rule 18 — size bound (founder decision needed to finalize: this doc proposes
16 KiB TRUNCATE, per the earlier session's confirmed token-cost math — NOT the
parent plan's stale 64 KiB/413-reject text, which predates that math)

- `snapshot_json` stored max observed live: 10,844 B, p95 9,031 B (round-3's own
  measurement). Truncate (never reject) at **16 KiB serialised**, preserving
  the JSON's OUTER shape (drop lowest-priority keys first — exact priority
  order TBD against `ai_snapshot_builder.dart`'s own trim-order convention,
  the same one `_compactContext` already uses for `coaching_notes` at 1000
  chars) so a legitimate push is never hard-rejected (a 413 would surface as
  a client-visible failure with no good retry story, per the earlier
  session's own reasoning for preferring truncate-with-a-counter over
  reject).
- **Logged counter**: increment a simple counter (log line + a `usage_counters`-
  style row, or reuse `client_errors`' telemetry pattern — confirm which at
  implementation time) each time truncation actually removes content, so this
  is observable rather than silent.
- `docs/sot_registry.yaml:~843`'s stale "server limit 10K" line gets corrected
  to 16 KiB in the same commit.

### `coach_extraction` metering

- Quota key `coach_extraction`, `consume_quota(user_id, 'coach_extraction', <IST
  6h-bucket-aligned window_start>, 4)` — ≤4 units/user/IST-day, one per 6h
  bucket-worth of newly-read turns (matches round-3's "IST-aligned buckets,
  ≤4/day" disposition).
- Consume ONLY when the watermark read actually returned turns (never on an
  empty read) — matches the existing "none → return without consuming" logic.
- DIGEST_KEYS gains `{ key: "coach_extraction", label: "Coach extraction", kind:
  "subday" }` (capless mirror requirement, per parent-plan line 165) and the
  digest's "ten sections / 7 of 10" comment becomes "eleven / 7 of 11" — EXACT
  wording/count to be re-derived from the live `founder-digest` source at
  implementation time, not assumed from this plan's own prose (the parent
  plan's citation predates a3/a4's own migrations, which may have shifted
  section counts further).

## Dependents (carried from parent plan line 165, re-verify each at
implementation time — do not trust these line numbers, they predate a2a/a3/a4)

`daily-snapshot/index_test.ts` header + anchors; `supabase/functions/CLAUDE.md`'s
testing note; `docs/architecture/ai.md`; `docs/architecture/sync.md`;
`index.ts`'s own inline comments describing the old whole-day-window behavior;
SoT registry — `usage_quota_ledger` gains `coach_extraction` as a new reader,
AND the new `user_profile.coach_extraction_locked_fields` column needs its own
writer/reader SoT entry (a2a's B-pass already established the precedent and
exact template for registering a concept like this — reuse that pattern, not
reinvent it).

## Process

Diagnose-doc (rule 22, full template — this is explicitly a recurrence-class
fix per round-3's own framing: "recurrence of the OI-162 unmetered-Gemini
class"). Tests (Deno, per round-3's own list): `consumeExtractionQuota` with a
fake RPC; `extractCoachingNotes` with fakes covering private mode / non-chat
rows / RPC failure / happy-path-consumes-once-before-Gemini; the watermark
read's exact boundary (both sides of the 48h floor, both sides of a stale vs.
fresh watermark); the channel filter; the kill switch (already covered by
a2a, re-confirm untouched). NEW: the manual-edit-lock round-trip (a
`_originalDietPreference`-style test mirroring the existing injuries test, if
one exists — check `test/` for an existing injuries-change-detection test as
the template) and daily-snapshot honoring `coach_extraction_locked_fields`.
Mutation-proof every new test per §4.4 rule 21. Full gate loop before dispatch
per §4.12.5/.8. ×2 context-blind review — QUEUED, dispatch when a subagent
slot frees (currently 4/4 in use for a3/a4's own reviews).
