---
bug_id: a2b2f1
date: 2026-09-27
batch: single-owner-a2b-2 (single-owner remediation batch, docs/plans/2026-09-27-single-owner-a2b-2-plan.md — CONVERGED after 5 plan-review rounds; this diagnose-doc also records a ground-truth correction to the converged plan discovered during implementation)
status: fixed
blast_radius: platform
symptom: |
  Two independent, unsynchronized writers to the same three `user_profile`
  columns (`diet_preference`, `lifestyle_activity`, `injuries`):
    1. The user, directly — via Profile → Edit Profile
       (`edit_profile_screen.dart`) and, for `injuries` specifically, at
       onboarding (`details_screen.dart` / `plan_screen.dart`).
    2. `daily-snapshot`'s nightly Gemini extraction
       (`mergeCoachingNotes`, `supabase/functions/daily-snapshot/index.ts`),
       which proposes the same three fields from conversational signal
       ("I'm actually vegetarian now", "I hurt my knee") and — before this
       fix — wrote them unconditionally, with NO awareness of what the user
       had explicitly set.
  This is the exact writer/reader-drift shape CLAUDE.md §4.1 names as the
  default suspect class: a user who deliberately picks "Vegetarian" in Edit
  Profile could have that choice silently reverted to "non_veg" by the next
  nightly extraction pass if the AI misread an ambiguous chat message, with
  no signal to the user that anything happened.

  **Ground-truth correction during implementation (the part that makes this
  diagnose-doc worth reading even though the plan converged cleanly):** the
  plan's own Design §5 specified writing the "extraction wanted to change a
  locked field" conflict marker into `user_preferences.coaching_notes`, so
  "the AI coach's system prompt then has a structural signal to phrase this
  distinctly." Grepping every reader of that column
  (`ai-proxy`/`_shared`/`rolling-context`/`weekly-report`) found ZERO hits.
  `ai_snapshot_builder.dart`'s own `_getCoachingNotes()` reads a COMPLETELY
  DIFFERENT concept (Hive `coachBox['coaching_notes']`, shape `{notes:[...]}`,
  fed from `coach_memory.coach_notes` — not `user_preferences.coaching_notes`
  at all). Had this been implemented literally as designed, the batch would
  have shipped a "suggest" mechanism that could never reach the AI or the
  user — satisfying the plan's own test-shape while being functionally
  inert. **This was NOT caught by any of the plan's 5 converged review
  rounds** — all five apparently read the write side of Design §5 and
  accepted its stated rationale without independently verifying the read
  side had a real subscriber, the exact discipline CLAUDE.md §4.1 demands
  ("name writer + reader by file:line BEFORE proposing the fix") applied one
  level up, to a PLAN's premise rather than a review FINDING's suggested fix
  (see `feedback_verify_suggested_fix_independently.md` for the closely
  related, already-recorded sibling lesson from a2b-1's own B-pass).
concept: coach_extraction_locked_fields (new SoT concept — docs/sot_registry.yaml)
sot_registry_entry: coach_extraction_locked_fields (new entry, this commit)
related_bugs:
  - a2b1c7 — the immediately-preceding unit in this same batch (daily-snapshot
    watermark/metering rewrite); this unit extends the SAME `mergeCoachingNotes`
    function it left in place.
  - OI-256 — filed during THIS unit's own design phase: a more general
    per-field profile conflict-resolution architecture gap
    (`_syncUserProfile`'s whole-object overwrite). Not blocking this unit,
    which ships a narrower, field-specific lock per founder decision; OI-256
    remains open for the general case.
  - OI-257 — filed DURING this unit's implementation, while fixing the
    protein-gap-alert `isVeg` vocabulary bug below: onboarding's
    `diet_preference: 'veg'` default doesn't match Edit Profile's own chip
    vocabulary (`non_veg`/`vegetarian`/`vegan`/`pescatarian`/`keto`). Not a
    live correctness bug for `isVeg` anymore (now accepts both), but the
    underlying vocabulary mismatch is real and independent — filed rather
    than silently expanded into this batch's scope.
recurrence: "yes — writer/reader drift (9+ instances since APK Test #6,
  `feedback_writer_reader_field_drift_recurring.md`), PLUS a NEW variant of
  the reference-equality-recurs-cross-language class
  (`feedback_reference_equality_recurs_cross_language.md`): `injuries` is a
  string[] and a naive `!==`/`==` comparison between two distinct array
  instances is always 'different' regardless of content, which would have
  marked every unchanged re-extraction as a false conflict forever. Closed
  here with a sorted-copy comparison (TS) — the same lesson the harness
  memory already tracks for a Dart `List`, now recurring on the TS side of
  the SAME feature."
writers:
  - { file: supabase/migrations/148_coach_extraction_locked_fields.sql, method_or_widget: "lock_coach_extraction_fields RPC — additive-only UNION into user_profile.coach_extraction_locked_fields; allowlist-filters p_fields to {diet_preference, lifestyle_activity, injuries} inside the function; SECURITY INVOKER + auth.uid() scoped by the caller's own user_profile_update_own RLS policy; no unlock RPC by design", line: 1 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "lockCoachExtractionFields — .rpc('lock_coach_extraction_fields', ...), best-effort with one inline retry, never throws", line: 921 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "syncOnboardingToSupabase — locks 'injuries' only when onboarding collected a REAL selection (not the ['none'] default), positioned AFTER the user_profile upsert so the just-written injuries value is what gets checked", line: 883 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save — via the pure computeCoachExtractionFieldsToLock helper, locks only fields that actually changed THIS save (never a field re-saved with its unchanged value)", line: 1893 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "mergeCoachingNotes — reads coach_extraction_locked_fields + the three current field values in ONE select; for a locked field, compares the extracted attempted value against the current (locked) value via valuesEqualForLockCheck (sorted-copy for arrays) and — only on a genuine mismatch — writes a conflict marker to coach_memory.locked_field_conflicts, MERGED over any existing conflicts (never a bare replace, which would silently erase a prior conflict recorded for a DIFFERENT field — the same jsonb-wholesale-replace shape migration 123 fixed for notification_preferences, one column over)", line: 354 }
readers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "mergeCoachingNotes — the only reader of the lock list itself", line: 431 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: "_getCoachMemoryForContext — wholesale CoachMemory.toJson() pass-through (subject to private_mode) — the conflict marker reaches the AI's prompt context with NO field-specific plumbing once the field exists on the CoachMemory schema", line: 999 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: user_profile, coach_memory
cloud_columns: [coach_extraction_locked_fields, locked_field_conflicts]
contract_test_path: test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart
ist_handling:
  - "Conflict-marker timestamps (coach_memory.locked_field_conflicts[field].at) use new Date().toISOString() (UTC) — this is a server-side, machine-consumed marker for prompt phrasing, not a user-visible date key, so no IST conversion applies (matches this repo's own convention that IST is for user-visible date keys and counter resets, not internal bookkeeping timestamps)."
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: "lock_coach_extraction_fields is SECURITY INVOKER + auth.uid()-scoped — the caller's own user_profile_update_own RLS policy ((select auth.uid()) = user_id) applies, so a user cannot lock or read another user's fields. daily-snapshot's mergeCoachingNotes reads/writes via the service-role client (bypasses RLS by design, same as every other coach_memory/user_profile write in this function), scoped to the userId parameter it is called with — no cross-account exposure introduced."
forbidden_patterns_checked:
  - "writing the conflict marker into user_preferences.coaching_notes as the plan's Design §5 literally specified — REJECTED after grep found zero readers of that column anywhere in the AI-facing code; redirected to coach_memory.locked_field_conflicts, which has a confirmed live reader (_getCoachMemoryForContext's wholesale toJson() pass-through). See the symptom section above for the full ground-truth trail."
  - "comparing extracted injuries arrays via !== / === — rejected: two distinct array instances are never reference-equal regardless of content in TS, which would mark every unchanged re-extraction as a false conflict forever. Fixed with a sorted-copy value comparison in valuesEqualForLockCheck."
  - "a plain UPDATE/upsert of user_profile.coach_extraction_locked_fields from any call site — rejected: with THREE independent call sites (Edit Profile save, onboarding injuries trigger, and potentially future ones) able to lock different fields, a plain assignment from one site would silently un-lock a field a DIFFERENT site had already locked. The RPC is additive-UNION-only; there is no unlock RPC at all, by design — unlocking was not a feature any ground truth or plan review round identified a need for."
  - "an unlock RPC, or a mechanism to clear a lock — deliberately not built. Adding one un-asked-for would be scope creep this repo's process explicitly discourages; the founder can revisit if a real need surfaces."
  - "shipping the migration WITHOUT a backfill UPDATE for existing rows — this was the first draft's actual mistake, caught before commit by re-reading the plan's own P0 finding (round 1): a plain ADD COLUMN ... DEFAULT '{}' reads as unlocked for every row that predates this feature, so the very next nightly extraction run would silently overwrite any existing user's genuine diet_preference/lifestyle_activity/injuries — exactly the bug this feature exists to prevent, on day one. Fixed by adding UPDATE user_profile SET coach_extraction_locked_fields = ARRAY[...] immediately after the ADD COLUMN, locking all three fields for every pre-existing row; only post-migration signups start unlocked."
  - "a fallback INSERT when lock_coach_extraction_fields finds no user_profile row for the caller — this was the first draft's actual mistake too, caught the same pass: the plan's converged design deliberately RAISEs EXCEPTION on zero rows affected so a 'called before the profile row exists' bug surfaces immediately in Postgres logs. A silent fallback insert would have masked exactly that bug class instead."
  - "a CHECK constraint on user_profile.coach_extraction_locked_fields's array contents — rejected in favor of an allowlist filter INSIDE the RPC (see the migration's own header for the reasoning: Postgres has no clean per-element CHECK for a text[] without a second lookup table, and keeping the allowlist in one place — the function — avoids duplicating it in a constraint definition too)."
proposed_fix: |
  Migration 148 (`supabase/migrations/148_coach_extraction_locked_fields.sql`):
  - `user_profile.coach_extraction_locked_fields text[] NOT NULL DEFAULT '{}'`
    — additive-only lock list, written ONLY via the new RPC.
  - **P0 backfill** (round-1 review finding, caught in this batch's own
    first implementation draft before commit): an immediate
    `UPDATE user_profile SET coach_extraction_locked_fields = ARRAY[
    'diet_preference','lifestyle_activity','injuries']` locks ALL THREE
    fields for every row that exists at migration-apply time. Only accounts
    created AFTER this migration start unlocked.
  - `lock_coach_extraction_fields(p_fields text[])` RPC — allowlist-filters
    to `{diet_preference, lifestyle_activity, injuries}`, UNION-merges onto
    the existing array (never replaces), SECURITY INVOKER + `auth.uid()`,
    both REVOKE forms applied (Supabase's `ALTER DEFAULT PRIVILEGES` grants
    EXECUTE directly to `anon`/`authenticated` on every new `public`
    function — `REVOKE ... FROM PUBLIC` alone is a no-op; migration 123's
    documented trap, re-applied here). Raises `EXCEPTION` on zero rows
    affected (never a silent fallback insert) — surfaces a "called before
    the profile row exists" bug immediately instead of masking it.
  - `coach_memory.locked_field_conflicts jsonb NOT NULL DEFAULT '{}'::jsonb`
    — the corrected Design §5 destination (see symptom section).

  Client (`lib/shared/repositories/user_repository.dart`):
  - `lockCoachExtractionFields(List<String> fields)` — best-effort RPC call,
    one inline retry, never throws (a lock that never lands costs at most
    one more overwrite next extraction, a much smaller harm than blocking
    the save it runs alongside).
  - `syncOnboardingToSupabase` locks `injuries` only when onboarding
    collected a real selection, not the `['none']` default — matching
    `details_screen.dart`'s own "no injuries" convention (a filled-in
    default is not a deliberate user statement; the AI should stay free to
    populate real injuries from chat for a user who skipped this step).

  Client (`lib/features/profile/screens/edit_profile_screen.dart`):
  - New `_originalDietPreference` / `_originalLifestyleActivity` trackers
    (mirroring the existing `_originalInjuries` pattern).
  - New pure helper `computeCoachExtractionFieldsToLock` (mirrors the
    existing `computePlanChanged` extraction pattern) — locks only fields
    that ACTUALLY changed this save.

  Server (`supabase/functions/daily-snapshot/index.ts`):
  - `mergeCoachingNotes` now SELECTs `coach_extraction_locked_fields` plus
    the three current field values in ONE query alongside the candidate
    updates, partitions into `profileUpdates` (unlocked fields, applied
    normally) and `conflicts` (locked fields whose attempted value
    genuinely differs — re-confirming the SAME value is a no-op, not a
    conflict), and merges `conflicts` over the EXISTING
    `coach_memory.locked_field_conflicts` (fetched via `fetchCoachMemory`
    first) before writing, since `upsertCoachMemory`'s
    `ON CONFLICT DO UPDATE SET` replaces a jsonb column wholesale.
  - New `valuesEqualForLockCheck(a, b)` — sorted-copy array comparison for
    `injuries`, plain `===` for scalars.
  - `mergeCoachingNotes` and the `CoachMemory` TS interface
    (`_shared/coach_memory.ts`) both export/declare `locked_field_conflicts`.

  Vocabulary fix (`supabase/functions/protein-gap-alert/message.ts` +
  `index.ts`): `isVeg` widened from `diet === "veg" || diet === "vegan"` to
  ALSO accept `"vegetarian"` — the value the client's own Edit Profile chips
  actually write (`edit_profile_screen.dart`'s `_buildDietPreferenceChips`
  options: `non_veg`/`vegetarian`/`vegan`/`pescatarian`/`keto`). `'veg'`
  stays accepted too (onboarding's live default per
  `lib/features/onboarding/CLAUDE.md`). `'eggetarian'`, named in the OLD
  comment and the OLD test, does not exist anywhere in this app's real
  vocabulary — confirmed by grep across `lib/` and `supabase/` — and was
  itself an `asserted_fixture_value` defect (code-review lens 8): a test
  asserting a value production can never produce.
regression_test_planned: |
  16 new source-structure Dart tests
  (`test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart`
  — migration shape, client wiring, server-side guard shape, AI-reach
  wiring) + 6 new genuinely behavioral Deno tests
  (`supabase/functions/daily-snapshot/index_test.ts`, exercising the real
  `mergeCoachingNotes` function against a fake-but-realistic Postgres-shaped
  client: unlocked-applies-normally, locked-with-real-conflict,
  locked-with-same-value-is-a-no-op, injuries array-value-equality across
  reorder, injuries genuine-difference, new-conflict-merges-over-existing)
  + 6 new pure-function Dart tests
  (`test/profile/edit_profile_coach_extraction_lock_test.dart` for
  `computeCoachExtractionFieldsToLock`) + 5 new pure-function Dart tests
  (`test/shared/user_repository_coach_extraction_lock_test.dart` for
  `shouldLockOnboardingInjuries`, extracted from
  `syncOnboardingToSupabase`'s onboarding-injuries trigger so the
  value-equality requirement is genuinely behaviorally tested rather than
  only source-grep pinned) + 4 new Dart model tests
  (`test/ai_coach/coach_memory_model_test.dart` for
  `lockedFieldConflicts`'s round-trip/omit-when-empty/merge behavior) + 2 new
  Deno tests + 1 corrected Deno test in `protein-gap-alert/index_test.ts`
  (the `isVeg` vocabulary fix, including replacing the phantom `eggetarian`
  assertion with a real `pescatarian` one).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean; flutter test on all new/touched Dart files green (see Mutation proof below for exact counts)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "This concept has no Hive-side storage — the lock list and conflict markers are cloud-only (user_profile / coach_memory columns), read server-side only. The client never reads coach_extraction_locked_fields or locked_field_conflicts back." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Migration 148 adds both columns; not yet APPLIED live — apply needs its own explicit founder authorization per §4.3, tracked with the rest of this batch's deploy list." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean on daily-snapshot/index.ts and protein-gap-alert/{index,message}.ts; deno test green on both function's test files. Not yet deployed — same §4.3 gate as the migration." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "lock_coach_extraction_fields is SECURITY INVOKER, scoped by the pre-existing user_profile_update_own policy ((select auth.uid()) = user_id, migration 100) — no new RLS policy needed or added." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "Traced the full flow end-to-end by reading (not assuming): Edit Profile save -> lockCoachExtractionFields RPC -> migration 148's additive UNION -> daily-snapshot's mergeCoachingNotes SELECT -> skip/apply decision -> conflict marker on coach_memory -> ai_snapshot_builder's wholesale toJson() pass-through -> AI prompt context. Every hop confirmed against live source, not inherited from the plan's own claims." }
impact_analysis: |
  No behavior change for a user who has NEVER touched Edit Profile or
  entered real injuries at onboarding: extraction still writes
  diet_preference/lifestyle_activity/injuries exactly as before (an empty
  lock list locks nothing). For a user who HAS explicitly set one of these
  three fields, the AI-coach extraction pass can no longer silently
  overwrite it — the extraction's attempted value is instead recorded as a
  conflict marker the AI's own prompt context can see, so a future turn can
  surface it conversationally ("I noticed you mentioned X, but your profile
  says Y — want me to update it?") rather than the app silently reverting a
  deliberate choice. This is the P1 fix the plan's own "suggest" mechanism
  was designed to close; the ground-truth correction above is what makes it
  actually reach the AI rather than shipping inert. The `isVeg` fix changes
  the protein-gap-alert message's food suggestion for any user whose
  diet_preference is literally `'vegetarian'` (the value Edit Profile's own
  chips write) — those users now correctly get vegetarian quick-fix
  suggestions (paneer/milk/almonds) instead of the wrong non-veg ones
  (chicken/eggs) they were silently getting before.
---

# coach_extraction_locked_fields: writer/reader drift between Edit Profile and AI-coach extraction, plus a converged plan's own dead-end write target

## Mutation proof (rule 21)

Each mutation applied by exact-string replacement (anchor confirmed present
via the edit tooling before mutating), full relevant test suite run, then
reverted byte-for-byte and re-confirmed clean before moving to the next
mutation.

| Mutation | File | What was neutered | Tests reddened |
|---|---|---|---|
| A | `protein-gap-alert/message.ts` | Reverted `isVeg` to `diet === "veg" \|\| diet === "vegan"` (dropping `"vegetarian"`) | 1 (`pickQuickFix: >=40g gap, vegetarian counts as veg`) — confirmed a real assertion failure (wrong quick-fix string), not a compile error |
| B | `daily-snapshot/index.ts` | `if (!lockedFields.has(field))` → `if (true)` (every field always treated as unlocked) | 5 (all locked-field tests: real-conflict, same-value-no-op, injuries-reorder, injuries-genuine-diff, merge-over-existing) |
| C | `daily-snapshot/index.ts` | `valuesEqualForLockCheck` reduced to bare `a === b` (dropping the sorted-copy array compare) | 1 (`locked injuries — array VALUE equality, not reference/order`) — confirmed a real assertion failure |
| D | `daily-snapshot/index.ts` | `{ ...existingConflicts, ...conflicts }` → bare `conflicts` (dropping the merge-over-existing fetch) | 1 (`a NEW conflict merges over an EXISTING one for a different field`) — confirmed a real assertion failure naming the exact regression |
| E | `lib/features/ai_coach/models/coach_memory.dart` | `merge()`'s `lockedFieldConflicts` overlay reduced to always keep the base value (dropping the patch-wins-when-non-empty branch) | 1 (`merge() overlays lockedFieldConflicts only when the patch is non-empty`) |
| F | `edit_profile_screen.dart` | `computeCoachExtractionFieldsToLock` reduced to drop the `injuries` clause entirely | 3 (`injuries changed`, `injuries reordered`, `all three changed`) |
| G | `user_repository.dart` | `shouldLockOnboardingInjuries` reverted to `injuries != const ['none']` (bare reference inequality) | 2 (`the ["none"] default is NOT locked`, `a DIFFERENT list instance with the SAME single "none" content is NOT locked`) — the exact reference-equality regression the plan's round-3 finding named |

All six mutations reddened EXACTLY the tests expected to catch that specific
protection, with real assertion-mismatch failures (not compile errors —
`deno check` / `flutter analyze` stayed clean throughout every mutation),
and every file was restored to its intended post-fix state and re-verified
green before moving on.

## Migration numbering coordination risk (OI-255 class — flagged, not resolved)

This repo has **no collision-proof migration-number allocator** (OI-255,
open). Before writing migration 148, checked `origin/main` (fresh
`git fetch`) plus every local AND remote branch's highest migration file via
`git show <branch>:supabase/migrations/` — as of 2026-09-27, ~23:20 IST,
`main`/`origin/main`/`ops-alerting-b2a2a`/`ops-alerting-b2a2b` all top out
at **147**; no branch anywhere has a file numbered 148 on disk. However, a
prior harness-memory note (`project_ops_alerting_b2a2b_2026_09_27.md`,
MEMORY.md line 12) records that the `ops-alerting` track's OWN next unit
("B2b") was PLANNED to use migration 148 — a plan, not yet a file, as of
this check. **This is a real, live, unresolved coordination risk**, not a
false alarm dismissed: two independent batches may both be about to author
a file named `148_...sql`. Nothing in this repo currently prevents that.
Mitigation taken: documented here per this repo's own prescribed practice
("explicitly flag the coordination risk... rather than assuming a number is
safely free" — root CLAUDE.md's migration-numbering common-pitfalls row).
**Before this migration is ever APPLIED live** (which requires its own
separate founder authorization regardless — a natural re-check point), the
number must be re-verified fresh against `origin/main` and every active
sibling branch one more time; if `ops-alerting`'s B2b has landed 148 first
by then, THIS migration must be renumbered before landing (safe to do —
unapplied migrations are not yet immutable, per `supabase/migrations/CLAUDE.md`).

**UPDATE, post-apply (2026-09-27/28): the risk materialized — not at 148, at
145/146.** The re-check immediately before applying (fresh `git fetch
origin main`, `git ls-tree -r origin/main -- supabase/migrations/` for
`14[8-9]`) confirmed 148 was still free on both `main` and `origin/main` at
apply time, and it was applied clean (`list_migrations` now shows
`20260927224028` / `148_coach_extraction_locked_fields`). But investigating
the ledger-parity test failure surfaced that `origin/main` (12 commits ahead
of local `main`, likely `avya-c4` — shown `busy` in a `ListAgents` check run
during this same investigation) had ALREADY landed
`145_workout_templates_stable_delete.sql` and
`146_workout_templates_delete_trigger_insert_path.sql` — different files,
same numbers as THIS branch's own `145_alert_sql_job_failures.sql` /
`146_alert_cron_job_silent.sql` — and **both pairs are already live-applied
to the same prod database** (`origin/main`'s pair at `cloud_version`
`20260927011446` / `20260927045029`, strictly AFTER this branch's own
145/146 landed at `20260926183009` / `20260926183056`). The mitigation this
section originally relied on — comparing each branch's HIGHEST migration
number — is **confirmed insufficient**: both branches' highest number
matched (147) at every check performed, which is exactly why the 145/146
collision went undetected until a completely unrelated investigation
(ledger-parity, not numbering) tripped over it. A real per-number diff
across branches, not a max-number comparison, is required to catch this
class. Filed as **OI-258** (does not touch 148 — 148 itself is clean; this
is a separate, already-live collision from an earlier pair of branches,
filed rather than fixed in this batch since one side's file isn't even
present on this branch to hash/verify against).

## Third discovery en route: `.claude/emit_payload.js` mis-named same-directory sibling files

Deploying the two Edge Functions this batch touches (`daily-snapshot`,
`protein-gap-alert`) via the documented host-shell flow (CLAUDE.md §0) hit a
genuine, generalizable bug: `daily-snapshot` deployed clean, but
`protein-gap-alert` failed with `Failed to bundle the function (reason:
Module not found ".../source/message.ts")`.

**Writer:** `.claude/emit_payload.js`'s `payloadName()` (pre-fix) named
EVERY non-entry file `../<path-relative-to-functions-dir>` unconditionally
— correct for a `_shared/` file (climbs out of the entry's own directory,
matching what its `../_shared/x.ts` import expects) but wrong for a
same-directory sibling of `index.ts`. `protein-gap-alert/index.ts` imports
`./message.ts` (same directory); the old scheme named it
`../protein-gap-alert/message.ts`, which the Supabase deploy API places as
a SIBLING of the `source/` directory the entrypoint lives in, not INSIDE
it — so Deno's bundler could not resolve the entry's own `./message.ts`
import. **Reader:** the live Supabase Edge Function bundler
(`file:///tmp/user_fn_.../source/index.ts`'s module resolution), confirmed
via the exact error message quoting that path.

**Not a one-off**: `grep -oE 'from "\./[^"]+\.ts"'` across every
`supabase/functions/*/index.ts` found the SAME same-directory-sibling shape
in 9 functions total — `future-prediction` (`./trend.ts`), `morning-alert`,
`plateau-alert`, `pr-detection`, `protein-gap-alert`, `re-engagement`,
`streak-guardian`, `workout-window-closing` (all `./message.ts`), and
`proactive-coach-promotion` (`./congrats.ts`). The bug was latent for all
nine; only `protein-gap-alert` happened to need a real host-shell deploy in
this batch, which is how it surfaced. `ai-proxy` — the function the
scheme's own header comment cited as its original verification case
("matches what ai-proxy v42 was deployed with") — has ZERO same-directory
siblings, which is exactly why this shape was never exercised before.

**Fix:** `payloadName()` now computes the relative path from the ENTRY's
OWN DIRECTORY (`path.dirname(entryPath)`), not `functionsDir`, and returns
it as-is rather than unconditionally prefixing `../`. `path.relative`
already produces `../_shared/x.ts` for a file outside the entry's
directory and a bare `message.ts` for one inside it, so this single change
fixes both shapes without a conditional.

**Mutate it and run it (rule 21):** wrote
`.claude/emit_payload_payloadname_test.js` — a black-box test spinning up a
temp fixture function directory with both shapes (a same-dir sibling AND a
`_shared/` file one level up), running the REAL CLI against it, and
asserting both resulting payload names. Ran green post-fix (3/3). Reverted
`payloadName()` to the pre-fix body (via `cp` from a manual backup taken
before mutating, restored the same way after — never `git checkout`, per
this same file's own EOL-mangling warning for a different file class,
applied here defensively even though `.js` carries no `eol=lf`
`.gitattributes` rule) and re-ran: reddened exactly the expected assertion
(`same-directory sibling named bare "message.ts"`), while the entry-name
and `_shared`-climb assertions stayed green — confirming the test isolates
the actual regression rather than passing/failing as a block. Restored the
fix and confirmed 3/3 green again before proceeding.

**Verified against the real, already-deployed case too**: regenerated
`daily-snapshot`'s payload with the fixed script and confirmed its file
names are BYTE-IDENTICAL to before the fix (`index.ts` +
`../_shared/*.ts`, unchanged) — the fix does not alter behavior for a
function with no same-directory siblings.

**Both Edge Functions deployed live** to `dedsavbjuwgarrhphgnl` with the
fixed tool: `daily-snapshot` → version 28 (HTTP 201, smoke-reachable),
`protein-gap-alert` → version 16 (HTTP 201, smoke-reachable). Founder
authorized both deploys explicitly via `AskUserQuestion`, separate from the
migration-148 apply authorization.

**Same bug, second copy — `.claude/deploy_via_api.js`'s `--rollback`
path.** `docs/diagnoses/2026-05-21-edge-function-rollback-I3-b3ecf2.md`
records that the rollback feature deliberately DUPLICATES
`payloadName()`'s naming scheme inline (`emitPayloadAtSha()`, reused rather
than refactored per that batch's own brief) "so both surfaces produce
byte-identical payloads for the same SHA" — which means it inherited the
exact same bug. Fixed identically: name every non-entry file relative to
the entry's own directory (`path.posix.dirname(entryAbs)`), not
`functionsDirRel`. **Verified against REAL git history in this repo**
(no synthetic fixture needed — `protein-gap-alert/message.ts` already
exists in this branch's own history): `node .claude/deploy_via_api.js
--rollback protein-gap-alert <HEAD-sha> --dry-run` reconstructs the
payload and names it `message.ts` (bare) post-fix. **Mutate it and run it**
— reverted just this one change, re-ran the identical dry-run: reproduced
the exact pre-fix bug (`../protein-gap-alert/message.ts` in the
reconstructed payload). Restored via `cp` from a manual backup (never `git
checkout`) and re-confirmed `message.ts` (bare) one more time before
moving on.

## Why the plan's own review process didn't catch the dead-end write target

Five converged review rounds each independently verified Design §5's
CLAIM (writing a conflict marker gives the AI "a structural signal to
phrase this distinctly") without independently verifying the claim's
PREMISE — that `user_preferences.coaching_notes` has any reader at all in
the AI-facing code. This is the same failure shape as
`feedback_verify_suggested_fix_independently.md` (verify a review finding's
*suggested fix*, not just the finding) one level up: verify a plan's
*write target*, not just its stated rationale for writing there. Both
lessons reduce to the same root habit this repo's memory already names —
"a plausible-sounding claim still needs independent verification against
the actual code, not just the reasoning that produced it" — recurring here
against a PLAN's own premise rather than a REVIEWER's suggestion.

The one verification step that would have caught this earlier: for any
"write X so that Y can read it" design step, grep for Y's actual read of X
BEFORE the review round signs off, not just read the prose claiming Y reads
it. Filed as a new harness memory
(`feedback_verify_plan_write_target_has_a_reader.md`) alongside this
diagnose-doc.

## B-pass findings (self-triggered, 2026-09-28, staged-against b56bd6f49571): both fixed

The mandatory ≥account self-triggered B-pass (`docs/reviews/b56bd6f49571-review.md`)
found 2 real gaps, both now fixed and mutation-proven in this same commit.

**Finding 1 (P2, blast_radius_mismatch) — the new locked-field guard shipped
live with no kill-switch.** `mergeCoachingNotes`'s lock-check-and-skip logic
(the section documented above) is platform-tier per `docs/blast_radius.yaml`,
which requires `feature_flag` for that tier (§4.6). It shipped with none —
only the pre-existing, much coarser `DISABLE_COACH_EXTRACTION` switch existed,
which disables ALL of `extractCoachingNotes()` (the Gemini call, the
coaching_notes/embedding merge, AND the locked-field guard together), giving
no way to revert just the new guard while keeping extraction itself running.

**Fix:** a new, narrower `DISABLE_COACH_EXTRACTION_LOCK_GUARD` switch,
`supabase/functions/daily-snapshot/index.ts:439-450`, checked immediately
after the `candidateUpdates` empty-check and BEFORE the `lockRow` SELECT —
mirroring the exact `DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT` precedent already in
this same file. When set, it writes every candidate field to `user_profile`
unconditionally (the verbatim pre-a2b-2 behavior) and returns, skipping the
lock read, the value-equality check, and the conflict-marker write entirely.

**Mutate it and run it (rule 21):** added 4 new Deno tests to
`supabase/functions/daily-snapshot/index_test.ts` (a source-grep for the
switch + its ordering before the lock read, a behavioral test that the
switch-on path writes unconditionally with no conflict marker, and a
behavioral test that the switch-OFF default still enforces the lock).
Ran green (40/40 total in the file). Reverted the fix (`lockGuardDisabled =
false` hardcoded) and re-ran: reddened exactly the 2 new tests that assert
the switch actually works (the source-grep test and the switch-on
behavioral test), while all 38 others — including the switch-OFF
behavioral test, which asserts the OLD/default behavior and is unaffected
by this specific mutation — stayed green. Restored the fix via `cp` from a
manual backup (never `git checkout`) and confirmed 40/40 green again.
`deno check --node-modules-dir=none` clean on the fixed file.

**Not yet redeployed as of this section** — `daily-snapshot` was already
deployed live (v28) as part of this unit's earlier work, BEFORE this
kill-switch fix landed in source. A redeploy is required to make the live
function actually carry this switch, and per §4.3 that redeploy needs its
own fresh explicit founder authorization, separate from both the v28 deploy
authorization and the migration-148 apply authorization already obtained.

**Finding 2 (P3, guard_without_its_mirror / rule 21) — `deploy_via_api.js`'s
`--rollback` fix (documented above, "Same bug, second copy") had no
persisted automated regression test**, only a manual dry-run + manual
mutation check recorded in prose. **Fix:** added
`.claude/deploy_via_api_rollback_payloadname_test.js` — a black-box
subprocess test that, per this same file's earlier lesson ("confirm the
FIXTURE reproduces a state the real workflow actually produces"), does NOT
use a synthetic temp-repo fixture (`emitPayloadAtSha()`'s `REPO_ROOT` is
hardcoded to `path.resolve(__dirname, '..')` — not configurable — so a fake
repo would test nothing about the real function). It instead runs
`node .claude/deploy_via_api.js --rollback protein-gap-alert <HEAD-sha>
--dry-run --yes` against this repo's own real, currently-committed history
(first asserting the fixture ASSUMPTION itself — that
`protein-gap-alert/index.ts` at HEAD really does import both a
same-directory sibling and a `_shared/` file — before trusting the tool's
output against it), then inspects the reconstructed
`_payload_protein-gap-alert_rollback_<sha>.json`.

**Mutate it and run it:** ran green (7/7). Reverted `emitPayloadAtSha`'s
fix to the exact pre-fix formula (unconditionally `../${fnName}/<relative-
to-functions-dir>`) and re-ran: reddened exactly the 3 assertions that
depend on the naming scheme (bare `message.ts`, the `_shared/` climb-out,
and the old-buggy-name-absence check), while the 2 fixture-assumption
assertions and the entry-name assertion stayed green — confirming the test
isolates the naming regression rather than failing as an undifferentiated
block. Restored via `cp` from a manual backup (never `git checkout`) and
confirmed 7/7 green again.

Both fixes are in this same commit; `docs/reviews/b56bd6f49571-review.md`'s
two findings are updated to `status: fixed` / `verdict: accepted` in the
same commit per the code-review skill's triage workflow, with a same-dated
`.claude/skills/code-review/SKILL.md` tuning-history entry (§5.1 gate).
