---
unit: a2b-2
parent_plan: docs/plans/2026-09-26-single-owner-batch-a.md
supersedes: docs/plans/2026-09-27-single-owner-a2b-plan.SUPERSEDED.md (split per §4.12.1)
depends_on: a2b-1
related: OI-256 (the general per-field profile conflict-resolution architecture —
  this unit deliberately does NOT wait on it)
blast_radius: account
status: CONVERGED after 5 rounds.
  Round 1 found a P0 (day-one clobber of every existing
  user's real, pre-existing profile edits) plus 4 P1s and 2 P2s, all fixed below.
  Round 2 (live-verified) found 2 NEW material P1s — the injuries onboarding-lock
  trigger condition was wrong given a `['none']` default sentinel, and the
  "suggest" mechanism added no lock-aware distinguishing framing — plus 2 P2s and
  2 P3s, all folded in. Round 3 (live-verified) found the round-2 fix ITSELF had
  a Dart list-equality bug (`_injuries != ['none']` is reference inequality, not
  value comparison — always true, would have silently reproduced the exact
  100%-of-signups bug round 2 just fixed) and a genuine sequencing gap between
  Design §4 and §5 (both need the current profile values + lock array, but
  neither shares a read, and §5's marker can't land in the same write as §4's
  guard as separately anchored) — both fixed below — plus a P2 (the lock call's
  swallowed-failure path has no retry, unlike the rest of its write chain) and a
  P3 citation fix (mergeCoachMemoryFields → mergeCoachingNotes). **Round 4
  (live-verified against `daily-snapshot/index.ts`, `edit_profile_screen.dart`,
  live schema, and live `user_profile` data) confirmed every round-1/2/3 fix
  correct, byte-for-byte on the file:line citations — AND found the SAME
  reference-vs-value-equality bug class recurring, unaddressed, in the TypeScript
  half of the very section round 3 just rewrote: Design §4/5's generic "differs
  from" comparison is `!==`, which for the `injuries` array field (schema
  `text[]`) is reference inequality — always true for two distinct array
  instances — not value comparison. Fixed below (P1/P2: wrong AI-coach narration
  from a false conflict marker, not data loss).** Round 4 also tightened one
  imprecise mutation description and one stale illustrative notation (both
  mechanical). Per round 4's own assessment, this tapering trend
  (5→2→2→1 material findings) was genuine convergence, not a signal to
  split (§4.12.1). **Round 5 (live-verified — schema check on `injuries`'
  `text[]` type + `column_default`, byte-exact re-verification of every
  `mergeCoachingNotes` line citation, both `syncOnboardingToSupabase` call
  sites, and a fresh independent spot-check of untouched sections) found
  NOTHING material — every citation held exactly.** One non-blocking
  implementation note (round 5): the injuries-comparison fix's suggested
  `.sort()` technique must sort COPIES of the arrays, since
  `Array.prototype.sort()` mutates in place — folded into Design §4/5 above.
  `review_rounds: 5`, `verdict: converged` per §4.12.6 (round 5's only finding
  was mechanical). **Ready for implementation.**
date: 2026-09-27
---

# a2b-2 — coach-extraction → user_profile: apply-while-default, lock once touched (REWRITTEN)

## The decision (recap, for the record)

Founder chose: keep coach-extraction writing `diet_preference`/`lifestyle_activity`/
`injuries` back onto the user's real profile — but only while a field is still at
its default/never-touched state. The underlying architectural problem (whole-object
sync eventually clobbering any per-field lock) is filed separately as **OI-256**.

## Corrected scope, stated plainly (round-1 review, P0 + P1)

**P0 — day-one clobber.** `daily-snapshot/index.ts:258-269` (a2a, already shipped)
unconditionally writes `diet_preference`/`lifestyle_activity`/`injuries` into
`profileUpdates` whenever extraction produced a value — with no "is this still
default" check anywhere, in that code OR in this plan's original design. A brand
new `coach_extraction_locked_fields text[] DEFAULT '{}'` column, added by a plain
`ALTER TABLE`, reads as UNLOCKED for every EXISTING row — including a user who
deliberately set `diet_preference='keto'` weeks before this feature shipped. The
very next nightly extraction run would silently overwrite that real, deliberate
edit — exactly the bug this feature exists to prevent, guaranteed to fire on day
one for anyone with a genuine non-default value. **Fixed in Design §1**: the
migration locks ALL THREE fields for every row that exists AT MIGRATION-APPLY
TIME. Only accounts created AFTER this migration start unlocked (matching
"apply-while-default" going forward); every pre-existing user's current state is
fully protected from day one, full stop — this is deliberately MORE conservative
than the original framing (a locked field on an existing user just means one fewer
opportunity for auto-fill, never a correctness risk), and closes the gap cleanly
without needing to solve "what even counts as still-default" for a value that
happens to equal the hardcoded default by coincidence.

**P1 — the "suggest" half of the approved decision was silently dropped.** The
original draft's status line said "lock-and-suggest-once-touched" but had no
suggestion mechanism anywhere. **Fixed in Design §5**: reuses the EXISTING
`coaching_notes` pipe (already unaffected by the lock, per Design §4) — no new UI.

**P1 — the onboarding lock-wiring citation targeted a line that persists
nothing.** `details_screen.dart:139-149`'s `_onContinue` only builds an in-memory
map and navigates; no `user_profile` row exists yet at that point (created later,
in `completeOnboarding`/`UserRepository.syncOnboardingToSupabase` — confirmed via
`lib/features/onboarding/CLAUDE.md`). **Fixed in Design §3**: the lock call moves
to fire from `completeOnboarding`, after the profile row genuinely exists.

**P1 — the proposed RPC could silently no-op on a missing row, masking data
loss**, unlike migration 123's own upsert-safe precedent it claimed to mirror.
**Fixed in Design §2**: the RPC now raises loudly on zero rows affected, rather
than the original bare `UPDATE`.

**P2 — "Why this doesn't need OI-256" mischaracterized the actual sync risk.**
`sync_profile.dart:188-256`'s `_syncUserProfile` is a per-field ALLOWLIST (each
field appears as an explicit `if (_hasValue(...)) 'x': p['x']` line) — a NEW
column is invisible to it automatically, unless someone explicitly adds a line
for it. The real blind-spread risk is `UserRepository.syncOnboardingToSupabase`
(`user_repository.dart:880-883`, `...{ ..._sanitize(profileData) }`), used ONCE at
onboarding completion. **Fixed below**: exclude the new column from BOTH paths
explicitly (harmless for the allowlist since it wouldn't be included anyway;
load-bearing for the blind-spread onboarding path).

**P2 — missing the recurring Supabase default-privileges trap.** A `SECURITY
INVOKER` function still needs an explicit `REVOKE`, because Supabase grants
EXECUTE to `anon`/`authenticated` by default regardless of security mode — this
hit migration 123 itself, the very precedent this unit cites. **Fixed in Design
§2.**

**P1 (vocabulary), scope corrected.** The original fix normalized only
extraction's OWN output. Round-1 review found the mismatch is WIDER: a real human
tapping "Vegetarian" in `edit_profile_screen.dart`'s diet chip UI
(`:1253-1259`) writes `diet_preference='vegetarian'`, and
`protein-gap-alert/message.ts`'s `isVeg` (`=== 'veg' || === 'vegan'`) would
misclassify that user as non-veg — `diet_plan_generator.dart:1328` already
treats `'veg'`/`'vegetarian'` as equivalent, so this is genuine writer/reader
vocabulary drift across MULTIPLE existing writers, not something extraction
introduces. **Fixed in Design §6**: widen `isVeg` itself (the reader), not just
extraction's output (one writer) — this fixes the bug for every writer
uniformly, including the pre-existing one this batch didn't create. **Round-2
correction: live query of all 27 `user_profile` rows found ZERO currently hold
`'vegetarian'`** (live values: `veg`=22, `non_veg`=3, null=1, and a
previously-uncatalogued THIRD spelling variant `non_vegetarian`=1 — doesn't
break `isVeg` either way since it's correctly non-veg on both sides of the fix,
noted here so no future audit re-discovers it as new). So this fix has ZERO
current live-user impact — worth shipping to close the vocabulary-drift class,
but "already misclassifies that user" overstates today's exposure; it is a
latent bug, not an active one.

## Ground truth (re-confirmed; carries the round-1 fold-ins above)

1. Only `injuries` has an `_original*` change-detection tracker today
   (`_originalInjuries`, `edit_profile_screen.dart:95`, captured at `:294`) — and
   even that tracker gates only the RESCHEDULE-PROMPT, not the save write itself;
   all three fields are unconditionally written on every save (`:1848,1852,1853`)
   regardless of whether they changed.
2. `diet_preference` defaults to hard-coded `'veg'`; `lifestyle_activity` is
   DERIVED from `activity_level` — neither is a genuine onboarding answer.
   `injuries` IS a real onboarding answer. Confirmed via
   `lib/features/onboarding/CLAUDE.md`'s own "fields still defaulted" list.
3. `induction_service.dart` and the onboarding injuries chips touch ONLY
   `injuries`, never `diet_preference`/`lifestyle_activity` (confirmed by grep) —
   so item 3's lock-wiring below is injuries-only, not all three fields.

## Design

### 1. Migration: `coach_extraction_locked_fields`, WITH backfill

```sql
ALTER TABLE user_profile
  ADD COLUMN coach_extraction_locked_fields text[] NOT NULL DEFAULT '{}';

-- Backfill: every row that exists AT MIGRATION-APPLY TIME predates this feature.
-- Its current value (whatever it is — default or genuinely chosen) is protected
-- from silent AI overwrite from day one. Only accounts created AFTER this
-- migration start unlocked.
UPDATE user_profile
SET coach_extraction_locked_fields = ARRAY['diet_preference','lifestyle_activity','injuries'];
```
(Re-derive the actual next-free migration number at implementation time —
coordinate with a3b/a4, both drafting migrations in the same window.)

### 2. Additive-merge RPC — loud on a missing row, correctly revoked

```sql
CREATE OR REPLACE FUNCTION public.lock_coach_extraction_fields(p_fields text[])
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  IF p_fields IS NULL OR array_length(p_fields, 1) IS NULL THEN
    RAISE EXCEPTION 'lock_coach_extraction_fields: p_fields must not be null or empty';
  END IF;

  UPDATE user_profile
  SET coach_extraction_locked_fields = (
    SELECT array_agg(DISTINCT f) FROM unnest(
      coach_extraction_locked_fields || p_fields
    ) AS f
  )
  WHERE user_id = auth.uid();
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'lock_coach_extraction_fields: no user_profile row for %', auth.uid();
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.lock_coach_extraction_fields(text[]) TO authenticated;
```
**Round-2 additions (P2):** `SET search_path = public, pg_temp` — the
live-confirmed house convention for this exact function shape, per migration
123's sibling `merge_notification_preferences` (even on SECURITY INVOKER, still
this repo's own hardening precedent). And an explicit NULL/empty guard on
`p_fields` — without it, `coach_extraction_locked_fields || NULL` evaluates to
NULL and the UPDATE fails on the column's `NOT NULL` constraint with a generic
Postgres error instead of a clear diagnostic.
Called BY THE USER'S OWN CLIENT as themselves (not `service_role` — this is the
opposite grant shape from a3b's sibling RPC, since here the caller IS the row
owner). Raising loudly on zero rows affected surfaces a "called before the profile
row exists" bug immediately instead of masking it as silent success — this is
exactly the class of bug the onboarding-wiring fix below exists to prevent from
happening in the first place, and the raise is the backstop if it recurs anyway.
Live post-apply check: `SELECT has_function_privilege('anon',
'lock_coach_extraction_fields(text[])', 'execute');` must return `false`.

Two devices independently locking different fields at nearly the same time both
land — additive UNION, never a blind replace. `array_agg(DISTINCT f)` gives no
guaranteed element order — fine for the reader's `.includes()`-style membership
check (Design §4), never compare this array by equality.

The lock is permanent and one-way by design — once a field is locked, there is no
unlock path in this unit. Stated here as an accepted limitation, not an oversight.

### 3. Client: extend the `_original*` tracker; move onboarding lock-call to the real persist point

`edit_profile_screen.dart`: add `_originalDietPreference`/
`_originalLifestyleActivity`, captured at the SAME point `_originalInjuries`
already is (`:294`). On save, for each of the three fields, if the CURRENT value
differs from its `_original*` snapshot, add that field's name to a
`newlyLockedFields` set and call `lock_coach_extraction_fields(newlyLockedFields)`
(queue for retry if offline, matching this app's existing offline-write patterns).

For injuries specifically entered at ONBOARDING (not the profile screen): call the
SAME lock RPC from **`completeOnboarding`/`UserRepository.syncOnboardingToSupabase`**
(`user_repository.dart:880-883`) — AFTER the `user_profile` row has actually been
created there, NOT from `details_screen.dart:139-149`'s `_onContinue` (that line
persists nothing; the corrected citation above is the real fix location).

**CORRECTED (round 2, P1) — the trigger condition "non-empty" is WRONG.**
`details_screen.dart:124-128` seeds `_injuries = ['none']` whenever the user
never answers (`if (_injuries.isEmpty) _injuries = <String>['none'];`) — the
onboarding answer is therefore NEVER actually empty, so a plain non-empty check
would lock `injuries` for 100% of new signups regardless of whether a real
answer was given, defeating apply-while-default specifically for the one field
this feature most needs it for. **Correct condition: lock `injuries` only when
the onboarding answer is genuinely non-default.** **CORRECTED (round 3, P3) —
`_injuries != ['none']` as literally written is a Dart bug, not just loose
phrasing: `List` does not override `==` in Dart, so a bare `!=` between two
list literals is REFERENCE inequality, always `true` — this would silently
reproduce the exact "locks 100% of new signups" bug this very fix exists to
close, just via a different mechanism. Use the value-equality idiom this same
file already uses elsewhere (`listEquals(_injuries, _originalInjuries)`,
`edit_profile_screen.dart:1973`): `!listEquals(_injuries, const ['none'])`.**
(Drop the `known_injuries` reference from the
original text — that coachBox/muster key was retired, diagnose `d6f1b8`,
2026-09-19; `InductionService`'s `_allowedMusterKeys` now rejects it — say "the
onboarding `injuries` answer" instead.)

**CORRECTED (round 2, P2) — do not let this new RPC call block or fail the
existing onboarding-sync write chain.** `UserRepository.syncOnboardingToSupabase`
is called from TWO places (fresh onboarding AND `_replayPendingOnboardingSync`'s
bootstrap replay) and its surrounding code already documents this chain as
fragile (23505 conflicts, mandatory sequencing, a 10s-retry + pending-flag-replay
safety net) — inserting a new synchronous, throwable RPC call into the middle of
it risks a lock-RPC failure silently blocking the unrelated `user_progress` push
that follows it in the same attempt. Call the lock RPC LAST in that sequence, and
wrap it so a failure logs but never throws past this call site (the RPC's own
`RAISE EXCEPTION` on a missing row is still the right internal behavior — it's
this call SITE that must not propagate the failure into the shared chain).
**Wiring point, stated explicitly (round 4) — call the lock RPC from INSIDE the
shared `syncOnboardingToSupabase` itself, not from either individual calling
context**, so both the fresh-onboarding path and the replay path get it for
free from one call site; the additive-union RPC (Design §2) makes firing it
twice (once per path, on a replay that already succeeded once) harmless
regardless, so this is a placement clarification, not a new correctness
requirement.

**CORRECTED (round 3, P2) — the swallowed-failure path has no safety net,
unlike the rest of this chain.** Because the lock call's failure is
deliberately never re-thrown, if it fails ALONE (the surrounding
users/profile/progress upserts succeed on the same attempt), the whole
`syncOnboardingToSupabase` call reports success, `pending_onboarding_sync`
gets cleared, and the injuries lock is PERMANENTLY missed with zero retry —
unlike those other writes, which ARE protected by the existing 10s-retry +
pending-flag-replay mechanism (itself built specifically to catch "JWT may
need refresh after sign-up", the exact failure class most likely to also hit
this new RPC call at the same moment). Fix: give the lock call ONE inline
retry (a short delay, then one re-attempt) before swallowing and logging —
cheap, and closes the gap without re-coupling it into the shared chain's own
retry/replay mechanism.

Exclude `coach_extraction_locked_fields` from BOTH sync paths explicitly: it's
naturally excluded from `_syncUserProfile`'s allowlist (`sync_profile.dart:188-256`)
unless someone deliberately adds a line for it — leave it out; but it MUST be
explicitly stripped from `UserRepository.syncOnboardingToSupabase`'s blind-spread
payload (`...{ ..._sanitize(profileData) }`), since that path would otherwise
overwrite it wholesale on every onboarding-completion call.

### 4/5. `daily-snapshot/index.ts`'s extraction tail-write + the "suggest" half — ONE shared read, two consumers

**CORRECTED (round 3, P1, live-verified) — §4 and §5 were originally two
independently-anchored edits that don't share a read, and their ordering
matters: `mergeCoachingNotes` (`:196-270`) upserts `coaching_notes` at
`:224-227`, BEFORE the `profileUpdates` section §4 anchors to (`:258-269`), and
`mergeCoachingNotes` never SELECTs the current `user_profile` row at all
(zero SELECTs against `user_profile` in the file today). Implementing §4 and
§5 exactly as originally cited — as two separate line-anchored edits — would
very plausibly ship §5's headline fix (the locked-conflict marker) in a form
that never actually writes into the `coaching_notes` upsert it's supposed to
enrich, since that upsert already ran by the time §4's guard code would even
see the lock array.** (Also, round 3 found the round-2 citation itself named
the WRONG function — "per `mergeCoachMemoryFields`'s existing structure" should
read `mergeCoachingNotes`, a different function entirely that writes to a
different table; corrected here.)

**Fix: add ONE `SELECT coach_extraction_locked_fields, diet_preference,
lifestyle_activity, injuries FROM user_profile WHERE user_id = $1` near the top
of `mergeCoachingNotes`, BEFORE the `merged` object is built (before `:216`).**
This single read feeds BOTH consumers:
- **(§5) Building the locked-conflict marker, written into the SAME
  `coaching_notes` upsert at `:224-227`:** for each of the three fields, if it's
  in the locked-fields array AND extraction produced a value that DIFFERS from
  the just-read current profile value, add an entry to a distinctly-keyed
  `locked_field_conflicts` object (e.g. `{"locked_field_conflicts":
  {"diet_preference": {"profile_value": "veg", "recent_signal": "keto"}}}`),
  separate from the generic merged-facts blob — never indistinguishable from an
  ordinary fact, which the original always-on merge produced. The AI coach's
  system prompt then has a structural signal to phrase this distinctly ("your
  profile says X, but you recently mentioned Y") rather than treating it as an
  undifferentiated fact.
  **CORRECTED (round 4, P1/P2, live-verified) — "differs" must be VALUE
  comparison for `injuries`, not `!==`.** `user_profile.injuries` is `text[]`
  (confirmed via live schema check) and `ExtractedFacts.injuries?: string[]`
  (`index.ts:41`) is likewise an array; a plain `!==` between two array
  instances in TypeScript/JS is reference inequality — always `true` for two
  distinct arrays even when their contents are identical. This is the EXACT
  bug class round 3 just found and fixed on the Dart side
  (`_injuries != ['none']`), recurring unaddressed here in the section that was
  rewritten specifically to fix a sequencing gap in this same area. Left as
  `!==`, this means every time `injuries` is locked and extraction produces
  ANY value — even one identical to the current profile — it gets spuriously
  flagged as a conflict, polluting `coaching_notes` with a false "your profile
  says X, but you recently mentioned Y" marker where X and Y are the same list.
  **Fix: `diet_preference`/`lifestyle_activity` (plain `text`) compare with
  `!==` correctly as-is; `injuries` must use a VALUE-based array comparison** —
  e.g. sort COPIES of both arrays (`[...arr].sort()`, never a bare `arr.sort()`
  — round 5 flagged that `Array.prototype.sort()` mutates in place, which would
  silently reorder `injuries` before it's later written into `profileUpdates`
  at Design §4's guard step; harmless today since `injuries` is an unordered
  tag-set everywhere else in the app, but a latent footgun worth avoiding) and
  compare via `JSON.stringify`, or a small local array-equality helper. No
  existing precedent for this in `supabase/functions/` today (confirmed by
  grep) — write the smallest local helper needed, do not import a new
  dependency for it.
- **(§4) Guarding the LATER `profileUpdates` section (`:258-269`):** using the
  SAME already-fetched locked-fields array (no second query), skip adding any
  field present in it to `profileUpdates` via a membership check (never array
  equality, per §2's ordering note).

This is still one function, one added read, additive to the existing pipe —
not a redesign — but it must be written as ONE coordinated change, not two
independently-anchored ones that happen to reference the same array.

### 6. Vocabulary fix — widen the READER, not just one writer

`protein-gap-alert/message.ts`'s `isVeg` check is widened to match
`'veg'`/`'vegetarian'`/`'vegan'` (aligning with `diet_plan_generator.dart:1328`'s
existing `veg`/`vegetarian` equivalence) — this fixes the bug for EVERY writer
uniformly, including the pre-existing one (`edit_profile_screen.dart`'s diet chip,
`:1253-1259`) that has nothing to do with AI extraction. **Round-2 addition:**
`supabase/functions/protein-gap-alert/index.ts:270-271` carries an explicit
comment claiming "Indian app uses 'veg'/'non_veg'/'vegan'/'eggetarian' — NOT
'vegetarian'" — this becomes stale and self-contradicting the moment
`message.ts`'s `isVeg` is widened to accept `'vegetarian'`; update that comment
in the same commit. Injury free-text canonicalization (e.g. `'back'` →
`lower_back`) still happens at extraction's own write point, reusing whatever
lookup table `details_screen.dart`'s onboarding chips already use, if one exists
(confirm at implementation time).

## Dependents

- `edit_profile_screen_test.dart` (likely net-new) — mirror the `_originalInjuries`
  change-detection template, extended to the two new trackers.
- `user_repository_test.dart` (or wherever `syncOnboardingToSupabase` is tested) —
  confirm `coach_extraction_locked_fields` is excluded from the blind-spread
  payload, and that the lock RPC fires AFTER the profile row is created.
- New SoT registry entry for `coach_extraction_locked_fields` (writer: this unit's
  client save path + `completeOnboarding`; reader: `daily-snapshot/index.ts`'s
  tail-write guard).
- `test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart`:
  locked field skipped by tail-write; unlocked (still-default) field still
  applied; two devices locking different fields both survive (additive union);
  **existing-user backfill migration locks all three fields for pre-existing
  rows, new signups start unlocked** (the P0 fix, needs its own explicit test).
- `protein-gap-alert` test coverage for the widened `isVeg` — confirm existing
  tests still pass and add a `'vegetarian'` case if none exists.
- **Round-2 addition:** a regression test asserting the onboarding injuries-lock
  trigger fires on a genuine answer (value-different from the `['none']`
  sentinel default, per round 3's `!listEquals(_injuries, const ['none'])` fix —
  **reworded here for consistency; the original bare `_injuries != ['none']`
  notation was illustrative prose only, not proposing that literal code, but
  round 4 flagged it as stale relative to round 3's own fix**) and does NOT
  fire on the `['none']` sentinel default — mutation: revert the condition to a
  plain non-empty check, confirm this test reddens (the exact bug round 2 found).
- **Round-2 addition:** a regression test for Design §5's locked-conflict
  framing — asserts a locked field with a differing extracted value produces a
  distinctly-keyed `coaching_notes` entry, not indistinguishable from an
  ordinary merged fact.
- **Round-3 additions:**
  - A regression test asserting the injuries-lock trigger uses value equality:
    mutation — revert `!listEquals(_injuries, const ['none'])` to a bare
    `_injuries != ['none']`, confirm the "locks 100% of new signups" test
    reddens (Dart reference-inequality is always true, so this mutation must
    visibly break the assertion, not silently pass).
  - A regression test proving §4/§5's shared read actually lands the
    locked-conflict marker IN THE SAME `coaching_notes` upsert as the ordinary
    merged facts (not two independent writes that happen to agree on schema).
    **Tightened (round 4, mechanical) — the mutation must target the actual
    failure mode named in the prose above (the `locked_field_conflicts` key
    never landing inside the `merged` object before the `:224-227` upsert
    runs), not a vaguer "revert to two separate SELECTs" — the tighter
    mutation is: omit the `locked_field_conflicts` key from `merged{}` before
    `JSON.stringify`, then assert directly against the PERSISTED
    `coaching_notes` JSON that the key is present, confirming this test
    reddens.**
  - A regression test for the lock-RPC's one inline retry: first call fails,
    second succeeds, lock is still recorded — mutation: remove the retry,
    confirm a "transient failure loses the lock permanently" test reddens.
  - **Round-4 addition:** a regression test for the injuries value-equality fix
    above: a locked `injuries` field whose extracted value is CONTENT-EQUAL to
    the current profile value (different array instance, same elements)
    produces NO conflict marker; a content-DIFFERENT value DOES — mutation:
    revert the comparison to a plain `!==`, confirm the "content-equal, no
    marker" half of this test reddens (the array is always a new instance, so
    `!==` is always true and would spuriously flag every locked-injuries case).

## Process

Diagnose-doc (rule 22) — this is a recurrence-class fix (writer/reader vocabulary
drift, same class as several other fixes in this batch) AND fixes a real
pre-existing bug (the `isVeg` mismatch) discovered as a side effect, both need
citing. Regression tests per Dependents, mutation-proven per rule 21 (e.g. remove
the backfill UPDATE, confirm the "existing user's real value survives the next
extraction run" test reddens; remove the lock-check in the tail-write, confirm the
"locked field stays untouched" test reddens). Full gate loop before dispatch
(§4.12.5/.8). Fresh ×2 context-blind review of THIS document.
