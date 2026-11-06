---
branch: telegram-surface-off
date: 2026-11-06
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/telegram-surface-off-bpass.md
---

# Plan-review record — take the Telegram promises out of the app (OI-466, closes OI-227's residue)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). `bpass` was `pending` until the
B-pass had actually run; it is `accepted` now because `docs/reviews/telegram-surface-off-bpass.md` exists, carries a
bare line-anchored `verdict: accepted` and a `## Tuning entry`, and has no finding left pending. This record lands in
its own commit after the fix commit (the review hash covers the staged diff, and `docs/plan-reviews/` is not excluded
from it).

**Tier `platform`, COMPUTED** with `dart run scripts/blast_radius_from_diff.dart <paths>`: `account` for the code,
tests and feature docs (the paywall counts as account); `platform` once root `CLAUDE.md` is in the set (two table cells
that told every session the app has a Telegram toggle and that the bot is "NOT in this repo").

Plan: `docs/plans/2026-11-06-telegram-surface-off.md` (v3). Execution mode: inline (one worktree, one writer).

## Round 1 — three context-blind Sonnet reviewers on v1

| Reviewer | Lens | Material findings (all verified by the coordinator before acting) |
|---|---|---|
| A | ground truth of every code claim | v1 said the `source: 'telegram'` value "is read by the UI" (copied from OI-467; no reader exists in `lib/`); `telegram-bot/` is TRACKED although root `CLAUDE.md` says "NOT in this repo", and closing OI-227 would bury its only warning about `receive_email`; docs list incomplete; `url_launcher` import removal certain, not conditional |
| B | tests, mutation plan, process | two source pins on the literal `if(channel=='in_app')` in `measurement_flag_off_identity_test.dart` go red (v1 swept symbol names, not the literal); `AiCoachScreen` cannot be pumped (three in-repo statements), so the v1 stranded-user test was unbuildable; the T3 scan missed `t.me/` and `@AVYACOACHBOT`, per-file allow-list instead of exact counts, naive comment stripper; v1 mutant M3 did not compile; trailer needs one `closes-oi:` line per OI; full diagnose template (recurrence class) |
| C | line-shift and grep blast | `coach_chat_reply_sanitization_test.dart` slices `send(` to the next `class`; deleting the Telegram block moves that to `PredictionData` and the slice swallows a top-level definition (count 2 to 3): REPRODUCED by simulation on the real file; registry `line_range` 479-486 for `screen.dart` overflows the shortened file (gate `[range-overflow]`); `COACH-17` dangling id; diagnose `{file,line}` maps must resolve |

All round-1 findings are folded into v3 (marked `[R1]` in the plan). There was no separate v2 on disk.

## Round 2 — two fresh context-blind Sonnet reviewers on v3

| Reviewer | Lens | Findings |
|---|---|---|
| R2-A | a SECOND consumer of each late-found class (slice terminators, registry ranges near a file's length, literal pins) | no P0, no P1. One P2 that was NOT mechanical: v3's repointed chip pin (count 1 plus order) would pass under ANY re-gating such as `if(!isPro)MeasurementChipSlot(`; fixed by pinning the chip's neighbours (mutants M14 and M15 added). Also: the registry gate counts lines with `readAsLinesSync`, and `screen.dart` has no trailing newline (498 vs `wc -l` 497); the `OI-232` comment in `coach_chat_log_train_refresh_behavioral_test.dart`; `ai_coach/CLAUDE.md:20` named a file that does not exist; `sot_registry_entry: not_applicable` |
| R2-B | can this be executed and committed | no P0. Mechanics the plan under-specified: record fields (`branch`, `bpass_review`, file at the merge rev, tuning-entry section in the review file), Gate 40 ledger schema and the stamp commit, the full diagnose frontmatter (and the index-row trap on test paths), CLOSED entry format and delete-from-open rule, `mint_oi.sh` creating a REMOTE ref, VPS test flags, commit order, `hooks.md:482`, text-file filter for `assets/` and `web/` |

Round 2 was NOT all-mechanical (R2-A's pin-strength finding changed a test's design), so `mechanical_only` is not claimed.
Round 2 produced no P0 and no P1, and every finding was a concrete edit, which is the convergence signal: the
reviews stopped surfacing new breakage classes rather than chasing the same one.

## B-pass — two fresh Sonnet seats on the implemented, gate-green diff

| Seat | Lens | Result |
|---|---|---|
| A | code and tests: deleted-symbol readers, the screen build, saved-key traces, the new test as a guard, repointed pins, analyze | no P0 or P1; 3 P2 and 3 P3. Mirror gaps in my own test (menu values vs case labels, chat area unpinned, scan bypasses, paywall pumped for one subtitle of 15) and one pre-existing no-op (`Clear conversation`, OI-479). Proposed 8 mutants as text; 6 were real survivors |
| B | docs, registry, board, ledger, claim accuracy, gate readings | no P0 or P1; 3 P2 and 6 P3. An overstated exploit paragraph in OI-476, a wrong review-finding number, six live statements of a corrected claim, a registry range one line short |

Every finding was verified against the files by the coordinator before acting and is `fixed` or `spawned` (OI-479) in the
review file; none is `false_alarm`. The whole mutation table was re-run on the final code (23 of 24 red, M10 the declared
survivor, N7 the green control, M13 red). The fixes were self-verified (mutation table, whole-project analyze, gate loop,
full suite), not given a third reviewer round: they are test assertions with a mutant each, doc corrections with a grep
each, and one rewritten paragraph checked against the cited code.

## Ground truth

Every file:line in the plan was re-read by at least two reviewers and the load-bearing ones by the coordinator
(sanitization slice by simulation, registry ranges by byte-for-byte comparison of main 1620-1651 with the worktree
1588-1619, screen line count by `awk`, the gates by running them).

## Copy review

`psychology-pass-fitness` run on the ONE changed paywall line: verdict keep the plain cut `Weekly AI nutrition report`;
the feature's name remains OI-325's open founder decision and was deliberately not touched.
