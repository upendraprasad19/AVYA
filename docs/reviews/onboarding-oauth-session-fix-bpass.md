---
branch: onboarding-oauth-session-fix
diagnose: d4e8a2
date: 2026-08-04
blast_radius: platform
pass: B
verdict: accepted
---

# B-pass — onboarding-oauth-session-fix (Unit 1, diagnose d4e8a2)

Adversarial pass over the final state, run by a fresh context-blind reviewer
after two independent review rounds had already landed fixes. Brief was
explicitly biased toward finding what those rounds MISSED and defects in the
fixes themselves, rather than re-deriving their findings.

**Initial verdict: rejected** — 1 × P1, 5 × P2. All fixed and re-verified;
**final verdict: accepted**.

## P1 — six SoT registry citations silently broken by this batch, while the doc attested the sweep was complete

The new `debugCurrentUidResolverForTests` seam grew `hive_user_session.dart`.
Round 2 had swept the citations that shift invalidated — but only in
`onboarding_provider.dart` — and then wrote "All corrected." in the
diagnose-doc. Six citations into `hive_user_session.dart` that were **correct
before this batch** were left stale:

| Site | Was | Now |
|---|---|---|
| `sot_registry.yaml:6174` `_openForUserLocked → notifyUserChanged()` | 255 | **268** |
| `sot_registry.yaml:6175` `_closeAllLocked → notifyUserChanged()` | 387 | **400** |
| `sot_registry.yaml:6176` `_deleteAllFilesForCurrentUserLocked → …` | 424 | **437** |
| `sot_registry.yaml:4613` `deleteAllFilesForCurrentUser` | 389-410 | **402-423** |
| `sot_registry.yaml:4489` + `:4648` lifecycle ranges | 77-240 | **83-253** |
| `scripts/cqrs_query_naming_lib.dart` allow-list rationale | :208 | **:221** |

Failure scenario: an agent following §4.1 ("name writer + reader by file:line
BEFORE proposing") opens `hive_user_session.dart:255` from registry line 6174
and lands on a blank line inside a `catch`, not on the writer.

**Nothing catches this.** `check_sot_registry_parity.dart` PASSes — its
±5 staleness check drops these entries (prose in `method:` defeats symbol
extraction), and `line_range:` is only bounds-checked against file length, so
wrong-but-in-bounds values are invisible.

**Correction to the B-pass's own numbers, found while fixing:** the reviewer
assumed a uniform +13 shift and proposed `77-240 → 90-253`. The diff is two
hunks — +6 at line 34, +7 at ~114 — so a range *starting* above the second
hunk shifts only +6. Correct value is **83**-253. Each corrected line was
verified by reading it, not by arithmetic.

## P2s

1. **Diagnose-doc frontmatter stale** — said "3 tests" / "all 3 pass again"
   (there are 4), and forwarded readers to a rationale for "Group C is
   presence-only" that round 2 had explicitly withdrawn.
2. **`onboarding_provider.dart:559-567`** cited for the catch block — actually
   `550-560`.
3. **`hive_user_session.dart:132-133`** cited for the `recordNonFatal` reason —
   actually `133-134`.
4. **The doc claimed this plan-review record already existed.** It did not at
   the time of the pass — a false completed-work attestation. Now true.
5. **C1's `catch (_) {}` with a false comment.** The comment claimed
   `completeOnboarding` "cannot finish in a pure-VM harness"; the reviewer
   showed execution reaches later stages. The bare catch would swallow a real
   regression while instructing the next reader not to investigate — the same
   "documented as impossible" move the doc's own durable lesson warns against.
   Removing it immediately surfaced a genuinely swallowed
   `onboarding_complete_failed: HiveError: Box not found` (unseeded exercise
   library). Final shape asserts no swallowed failure is of the
   **session-ordering class** (`GuardedBox` / `HiveUserSession`) — neither
   blind nor falsely strict.

## Attacked and found sound

- **Negative control, re-run independently.** Guard deleted (verified
  `grep -c` → 0, not commented). C1 fails with
  `Expected: 'b00b1e5e-…' / Actual: <null>` plus captured telemetry
  `guarded_box_null_owner_authenticated` → `GuardedBox.empty: rawBox
  unavailable`; C2 fails with `Actual: <-1>`. A and B correctly still pass
  (they exercise the mechanism generically). Restored → identical → 4/4 green.
- **The new seam.** 3 write sites repo-wide, all test lifecycle; 1 read, same
  library. Production leaves it null → `null ?? SupabaseService…` is
  byte-equivalent to the pre-change expression. `flutter analyze` clean of
  `invalid_use_of_visible_for_testing_member`. It is *stronger* than both
  local precedents (`debugAuthUidResolverForTests`,
  `GuardedBox.testBypassOwnership`), which carry no annotation at all — a
  question already adjudicated in this repo as `false_alarm (local
  convention)`.
- **Wrong-user hazard traced, not assumed.** A seam/Supabase mismatch takes
  the disagreement branch → `GuardedBox.empty` + HIGH-priority telemetry; any
  real op hits `_assertOwnership`, which reads Supabase with **no seam** →
  `HiveOwnershipException`. Cannot silently cross accounts.
- **tearDown on a throwing `setUp`** — verified against `test_api` source that
  tearDowns register before setUps run; `tearDownAll` and isolate-per-file
  both backstop it.
- **Order-independence** — verified by execution under a randomized seed.
- **Test A's message matcher is load-bearing** — all three owner-null sites
  throw `StateError`; the reachable one is `rawBox:172` via
  `hive_service.dart:226`. Round 2's B2-1 fix is real.
- **Guard placement** — only pre-guard Hive touch is the shared `configBox`;
  the sole other user-scoped access under `lib/features/onboarding/` is a
  guarded *read* in `plan_screen.dart` with a fallback, not a writer.
- **Guard introduces no new failure mode** — `currentUser` returns null rather
  than throwing when uninitialised, and `ensureOpenedForCurrentSession`
  catches every `openForUser` throw.
- **The round-1-misdiagnosis narrative is TRUE** — `'fat_loss'` is absent from
  `FitnessGoals._byToken`; `'lose_fat'` is real; the assert is at
  `fitness_goals.dart:128` col 7, matching the quoted text exactly.

## Noted, out of scope, filed rather than fixed

`GuardedBox.empty`'s "reads serve empty, writes throw loud" design is bypassed
by the seven plain `Box` getters in `hive_service.dart:225-231`, which call
`.rawBox` and therefore throw on *reads* too. Pre-existing and unrelated to
this batch — folding a core-services change into an already-reviewed
`account` diff would invalidate the review it just passed.
