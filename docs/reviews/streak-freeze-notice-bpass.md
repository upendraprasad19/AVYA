---
reviewed_at: 2026-10-07T18:00:00+05:30
staged_against: working tree of claude/avya-streak-data-check-b506de on top of HEAD 22265aee (Slice U6: lib/core/copy/streak_freeze_copy.dart, lib/core/services/streak_progress_service.dart, lib/shared/repositories/user_repository.dart, lib/features/home/screens/home_screen.dart, lib/features/home/widgets/streak_explainer_sheet.dart, lib/features/auth/screens/restoring_screen.dart, test/contracts/streak_freeze_notice_copy_test.dart, test/contracts/streak_freeze_notice_behavioral_test.dart, the repointed pin in test/contracts/streak_freeze_refill_race_test.dart, the two integration_test files, and the docs)
blast_radius: platform
reviewer: fresh-context-blind-agents (Sonnet; round 1 two seats: A correctness / copy fidelity / writer-reader map, B test adequacy; round 2 one seat: C re-review of what round 1 changed; read-only, no command beyond git diff/show/grep, Read, Grep, Glob)
lens_set: [L1, L8, L17, writer_reader_drift, guard_without_its_mirror, function_exception_swallow, asserted_fixture_value, blast_radius_mismatch, missing_input]
findings_count: 19
verdict: accepted
---

# Code Review (B-pass) — the freeze notice and the explainer sheet say what the rule is, and the count is the live one (diagnose a5e3c7)

Scope: `streakFreezeUsedNotice` / `streakFreezeNoticeFromProgress` / the rule strings in the new
`lib/core/copy/streak_freeze_copy.dart`, `StreakProgressService.commitConsume`
(`freezeNoticeCountAfterConsume`, `takeFreezeNotice`), `UserRepository.clearStreakFreezeNotice`, Home's
`_checkStreakFreezeUsed`, `StreakExplainerSheet`, the cold-start clear in `restoring_screen.dart`, and the two new test
files. Self-attested (rule 21): the mutation drivers are scratch scripts, not in the repo. Reviewers were told to find
defects and to say what they checked; the coordinator re-read every cited file:line (and re-ran every count by hand)
before accepting a finding, and treated a reviewer's suggested fix as a separate claim. The rule itself (a freeze is a
KEPT stock, still spent when the streak breaks anyway) and the approved wording were not up for review.

No reviewer found a P0 or P1 in any round. Round 1 confirmed: no other writer or reader of the three notice keys exists in
`lib/`, `supabase/` or `scripts/`; the keys are local-only (every progress push builder names its keys); every approved
sentence matches the code character for character; every count in the accumulation table is right; the stale-snapshot
sequence (`commitConsume(after: 0)` then `commitRefill(maxFreezes: 1)` leaves live 1, snapshot 0) is real; the cold-start
clear keeps `restoring_screen.dart` at 796 lines (cap 800). Round 2 re-reviewed the changes made for round 1.

## Findings (19: 0 P0, 0 P1, 4 P2, 15 P3) and what happened to each

### Round 1, seat A (correctness: 1 P2, 4 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| A1 | P2 | `freezeNoticeCountAfterConsume` read the stored count with a throwing `as num?` cast while the `updateProgress` argument map was being built; a non-num stored value would leave `commitConsume` before the debit was written. The reader side was tolerant, the writer was not. | FIXED: `raw is num && raw.isFinite` in the writer helper and the reader; a wrong-type, NaN and infinity row in both test files; a behavioral test that a string or NaN stored count still lets the debit land. |
| A2 | P3 | The diagnose said a restore "drops" the notice keys like the flag; `mergeCloudProgress` starts from `{...local}` so a restore KEEPS them (which is why the snapshot goes stale). Its `ist_handling` also credited the rollover order for "next Monday" when the real reason is the `streak_freezes_last_refill` gate. | FIXED: both sentences rewritten to the real mechanism. |
| A3 | P3 | Integration test T11's comment still quoted the retired wording and its seed helper wrote only the snapshot. | FIXED: comment updated, `setStreakFreezeJustUsed({remaining, used})` seeds the count and the live key. |
| A4 | P3 | `kStreakFreezeProNote` hard-coded "3 ... instead of 1", a separate copy of the cap. | FIXED: `streakFreezeProNote({freeMax, proMax})`, built from the caps the sheet passes; a test pins the sheet's constants to the service's `isPro ? 3 : 1` (see B6). |
| A5 | P3 | The registry range for `lockCoachExtractionFields` was not shifted after 13 inserted lines (the parity gate still passed because the range still held the symbol). | FIXED: repointed with the other shifted ranges. |

### Round 1, seat B (test adequacy: 2 P2, 6 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| B1 | P2 | Home's wiring was presence-only: `streakFreezeNoticeFromProgress(null)` in `_checkStreakFreezeUsed`, or moving the clear after the `mounted` check, passed every test. | FIXED in the part that can be: the read-and-clear moved into `StreakProgressService.takeFreezeNotice()`, which a real-Hive test drives (handed out once; no debit gives null and writes nothing; the live count at take time; a debit after a take restarts at one). Home's call to it and `Text(notice,` stay presence-only (the SnackBar is not pumped); stated in the diagnose Limits and the SoT row. |
| B2 | P2 | A missed ripple: the Profile service-record tile still reads "FREEZES LEFT n / max THIS WEEK" (`rank_service_record_sheet.dart:225-227`), the weekly-allowance wording this change retires; T11 and its helper were stale (see A3). | PARTLY FIXED, PARTLY LEDGERED: T11 and the helper fixed. The tile is NOT in the approved copy, so it needs the product owner's wording, not a silent edit: ledger entry `U6-PROFILE-TILE-COPY`, `blocked_on_user` (suggested unit line "IN RESERVE"). |
| B3 | P3 | Writer stricter than reader (same defect as A1) and no writer-side test with a string count. | FIXED with A1. |
| B4 | P3 | The registry's class constraint 2 said a literal flag-false write elsewhere "leaves a stale count that would inflate the next notice"; the code ignores a count behind a false flag. Its `forbidden_patterns_checked` claimed "no literal flag-false write outside the clearer" with only the restoring screen pinned. | FIXED: constraint reworded to the real reason; a repo-wide `lib/` scan test that only `user_repository.dart` writes `'streak_freeze_just_used': false`; mutant H04 is caught by it. |
| B5 | P3 | The wiring group read only the head `restoring_screen.dart` (a library with `part` files at 796 of 800 lines) and its local `_stripComments` cut `//` inside strings. | FIXED: `readRestoringScreenSource()` and `readSourceFileStripped`; the local stripper keeps `(?<!:)//`. |
| B6 | P3 | Sheet-wiring greps duplicated what the rendered widget tests prove; the PRO note's 3 and 1 were untied from the five other copies of `isPro ? 3 : 1`. | FIXED: the sheet-wiring greps cut to the absence of the old words plus the two cap constants; a caps pin ties the sheet's `freeMax` / `proMax` to the service's `isPro ? 3 : 1`; a pure test shows the PRO note follows the caps it is given (`freeMax 2, proMax 5`). The Home provider and the Profile tile keep their own copies of the cap; round 2 (C4) found the diagnose did not name them and the pin did not cover them, and fixed both. |
| B7 | P3 | The snapshot-key fallback is unreachable through the production writer (it writes the live key and the snapshot in one call), and the diagnose said "other code may still read" the snapshot. | FIXED: the false claim removed (its only reader is the copy module); the unreachable fallback is stated as such in Limits and kept for old maps; it is not the stale-count bug's cause. |
| B8 | P3 | The 'no progress map yet' clearer test asserted only that the notice was null; on an absent map `updateProgress` mints a default progress map. | FIXED: the clearer returns early on an absent map, and the test asserts the `progress` entry is still null. |

### Round 2, seat C (the changes made for round 1: 1 P2, 5 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| C1 | P2 | Three docs (the home CLAUDE.md row, the diagnose, this review's tables) cited ledger ids `U6-PROFILE-TILE-COPY` and `U6-BPASS-A/B/C` that did not exist in the closure ledger, so the Profile "THIS WEEK" residue had no terminal state anywhere. | FIXED: the four entries are in the ledger in this commit (`U6-BPASS-A/B/C` closed_in_commit, `U6-PROFILE-TILE-COPY` blocked_on_user with the reason); Gate 40 passes. |
| C2 | P3 | The diagnose's prose writer/reader map cited `streak_progress_service.dart:149` and `:120` and `streak_explainer_sheet.dart:88` (real: 167, 121, 92-93) and still said Home builds the text through `streakFreezeNoticeFromProgress`. | FIXED: re-derived by grep and the sentence now names `takeFreezeNotice` (line 140) as Home's entry. |
| C3 | P3 | The ledger's F8 text still said "35 mutants" after the diagnose moved to 45. | FIXED: 45, run on the post-review tree, and F8 names `takeFreezeNotice`. |
| C4 | P3 | The caps pin tied the sheet only to the weekly refill's `isPro ? 3 : 1`; the two copies in `home_provider.dart` and the one in the Profile tile were unpinned, and row B6 above said the diagnose named them when it did not. | FIXED: the pin counts `isPro ? 3 : 1` in all three other files (1, 2 and 1, so changing ONE of two copies in a file also reddens it); the diagnose Limits name all five statements; mutants N01-N04 red. Row B6 corrected. |
| C5 | P3 | The repo-wide "only the one clearer writes the flag false" scan matched only the map-literal form and skipped `user_repository.dart` wholesale, so an indexed assignment anywhere, or a second literal write inside `user_repository.dart`, passed it. | FIXED: both forms are scanned, and the scan counts exactly one write inside `user_repository.dart`; mutants N05, N06, N07 red. |
| C6 | P3 | Registry hygiene: the new concept's class constraints were numbered 1, 2, 4, 3; the clearer's range stopped at 861 (closing brace 862); the pre-existing reader range `172-179` for the idempotency check of `grantFirstProFreezes` was already stale at HEAD (the method sits at 258 now); the restoring screen's comment still named Home as the flag's reader. | FIXED: constraints reordered, the clearer range is 846-862, the idempotency range is 258-265, the comment now names `takeFreezeNotice` in place (the file stays at 796 lines). |

Seat C also confirmed, by its own reads: the wording byte for byte (no em dash, no exclamation mark); `take*` is outside the CQRS gate's prefix list; the clear is synchronous end to end (no `await` before the Hive `put`); the old and new order in `_checkStreakFreezeUsed` is the same (read, clear, `mounted` check, post-frame SnackBar); `clearStreakFreezeNotice`'s early return is unreachable from both callers; the only caller of `commitConsume` passes only dates newly flagged in that pass, so the count is not inflated; no file still carries the retired wording; and it agreed the Profile tile belongs outside this slice (it lives on a different surface from every sentence this change touches, and no screen shows the old and new wording together).

## Could not verify (carried to the diagnose Limits)

The SnackBar widget itself is not pumped (Home's `takeFreezeNotice()` call and `Text(notice,` are presence-only, as is the
cold-start clear in `restoring_screen.dart`), and no reviewer ran the explainer sheet on a phone-width screen; both owe the
CLAUDE.md section 5 device check. Whether the Monday refill and a restore interleave as the stale-snapshot test models was
read, not exercised on a device.
