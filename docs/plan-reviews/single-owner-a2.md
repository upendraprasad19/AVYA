---
branch: single-owner-a2
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/aa943309c727-review.md
tier: platform
date: 2026-09-27
---

# Plan review — single-owner-a2 (unit a2a)

**Scope:** `daily-snapshot`'s coaching-notes extraction gains a test seam
(exported `extractCoachingNotes` with an injectable `geminiChatFn`, and
`serve()` moved behind `if (import.meta.main)`), a `DISABLE_COACH_EXTRACTION`
kill switch, and a `coach_memory.private_mode` gate moved to run BEFORE any
read or Gemini spend — not after, as it was pre-fix (diagnose `c3f8e6`). This
is the converged plumbing half of the original a2 unit
(`docs/plans/2026-09-26-single-owner-batch-a.md`), split from a2b (the
metering/watermark rewrite, still under its own review) per §4.12.1 after
round 4 kept surfacing material findings against the metering logic while
this half had already converged.

**Blast radius: platform** (`docs/blast_radius.yaml:58` pins
`supabase/functions/daily-snapshot/**`).

## Round 3 (pre-implementation, context-blind, on the Revision-4 plan)
Findings: seam untested (#1) → `import.meta.main` + injected `geminiChat`;
bound untested (#2, a2b scope); lost chats (#3, a2b scope); rule-18 size bound
(#4, a2b scope, founder decision pending); kill switch missing (#5) → this
unit; IST-aligned buckets (#6, a2b scope); dependents (#7/#8, split across
both units); private mode checked too late (#9) → this unit, moved to run
before `isStale` and before any extraction call, fail-open on absent/error
matching this function's existing non-fatal posture.

## Round 4 (pre-implementation, context-blind, on the Round-3-hardened plan)
3 material defects, all in what a2b reads/meters (two-bucket window drop,
chat-channel allowlist gap, re-read-overwrite semantics) — none touching this
unit's plumbing. Independently re-verified against live code before the
split: `import.meta.main` safety, the exact pre-fix ordering of the
`private_mode` check inside `mergeCoachMemoryFields` (running AFTER
`extractCoachingNotes` had already spent a Gemini call and AFTER
`mergeCoachingNotes` had already written into `user_preferences`,
`memory_embeddings` and `user_profile` unconditionally), and that no
client-side writer currently sets `private_mode = true` (latent, 0 rows).
Fourth consecutive round with new material findings against the metering
logic ⇒ split per §4.12.1: **a2a converges here** with zero material
findings against this narrower scope; a2b continues under its own ×2 review,
building on a2a's seam once merged.

## Implementation, then B-pass (fresh adversarial reviewer)
Full findings + verification + fix detail: `docs/reviews/aa943309c727-review.md`.

**2 findings (1 P2, 1 P3); 0 false_alarm — both resolved in the same commit**
(diagnose `c3f8e6`'s "B-pass remediation" section): the converged plan's own
dependents list for this unit (#7 above) had not fully landed — 3 sibling
test-file headers (`weekly-report`, `assess-body-composition`,
`rolling-context`) still cited `daily-snapshot` as a same-shaped sibling
still lacking the `import.meta.main` guard, and no SoT registry entry existed
for the distinct `user_preferences.coaching_notes` concept this extraction
writes to (different table/column from the pre-existing Hive-singleton
`coaching_notes` concept — same English name only). Both fixed: headers
repointed, new `user_preferences_coaching_notes` concept added (writers
daily-snapshot + assess-body-composition, readers sync_profile.dart +
restore-user-snapshot), cross-reference guard note added to the pre-existing
concept, new test `test/contracts/user_preferences_coaching_notes_writer_to_reader_test.dart`
(5 tests, mutation-proven on 2 legs). The second finding (source-grep tests
never behaviorally invoke the seam) was accepted with no code change — a
disclosed, codebase-wide limitation shared by 5 sibling Edge Functions
booting the same module-scope way, for which the mutation-proof table is
this repo's documented substitute.

## Mutation evidence
4 mutations on the a2a implementation itself (A–D, diagnose `c3f8e6`): moving
the `private_mode` guard back after `isStale` (2/13 red), neutering the kill
switch (1/13), removing the `import.meta.main` guard (1/13), reverting
`extractCoachingNotes` to unexported/uninjectable (2/13). 2 more mutations on
the B-pass remediation's new test (E–F): breaking the read-before-merge
`.select("coaching_notes")` (1/5 red), reintroducing the exact pre-OI-98
forbidden `p['coaching_notes']` client pattern (1/5). All 6 applied by
exact-string replacement (match count confirmed), run once, then restored
byte-for-byte and reconfirmed clean.

## Verification state at record time
- Full pre-commit gate loop (`sh scripts/pre-commit.sh`): green, including
  `check_sot_registry_citations.dart` (the new concept + the cross-reference
  note both resolve) and `check_skill_tuning_history.dart` (dated entry
  appended to `.claude/skills/code-review/SKILL.md`).
- `deno check --node-modules-dir=none` on `daily-snapshot`, `weekly-report`,
  `assess-body-composition`, `rolling-context` (all 4 touched functions):
  all OK.
- `deno test --no-check --allow-all --node-modules-dir=none` on the same 4
  functions: 13 + 3 + 3 + 6 = 25 passed, 0 failed.
- `flutter test test/contracts/user_preferences_coaching_notes_writer_to_reader_test.dart`:
  5 passed.
- `flutter analyze lib/`: 45 pre-existing `info`-level issues, 0 in any file
  this unit touches, 0 warnings/errors.
- Not yet run at record time: the pushed-range full `flutter test` /
  pre-push gate (this unit has not been pushed to `origin/main`; not required
  before a local `--no-ff` merge, only before the push per §4.3).
