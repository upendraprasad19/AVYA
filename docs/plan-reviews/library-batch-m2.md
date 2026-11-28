---
branch: library-batch-m2
date: 2026-10-31
blast_radius: platform
review_rounds: 10
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/library-batch-m2-bpass.md
---

# Plan-review record — Batch M2a: the app delivers the exercise animations on demand (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`.** Computed over the diff: `pubspec.yaml` (one asset entry, `assets/exercise_stills/`) and `lib/core/services/hive_service.dart` (the web box constant and its opener) are both `platform` in `docs/blast_radius.yaml`; the rest is new files under `lib/core/services/exercise_media/`, `lib/shared/widgets/exercise_plate/`, `lib/shared/providers/`, tests, docs and one bundling script. The board entry OI-440 says `platform` since the B-pass (it said `account`).

## Plan
`docs/plans/2026-10-28-library-batch-m2-app-delivery.md` (r11) implements the on-demand half of OI-440 against the design `docs/superpowers/specs/2026-10-28-exercise-animations-app-delivery-design.md`: a bundled still on every 44 px tile, the animation in the exercise sheet fetched when it opens (one file, on any connection, logged-in non-anonymous account only), one Dio class reading the private bucket, a device cache that keeps its own index and survives sign-out, a kill switch. Executed INLINE (decided at batch start, §4.12.7). Two pieces were split out under §4.12.1 and are drafts with their own future reviews: M2b (hero tile, full-screen viewer, keyboard fold; OI-354) and M2c (Wi-Fi bulk prefetch; the second half of OI-440).

## Review rounds (context-blind Sonnet reviewers; the author re-ran the load-bearing numbers)
Round 1 (two lenses, on r1): 22 P1. Round 2 (on r2): 12 distinct P1, **split 1** (M2b out). Round 3: 7. Round 4: 8, four of them in the Wi-Fi prefetch trigger r4 itself had added, **split 2** (M2c out). Round 5 (the whole of r5): 5A 0 P1, 5B 4 P1, all tests that could not turn red. Round 6: 2 distinct. Round 7: 1. Round 8: 1 (found independently by both lenses). Round 9: 1. Round 10 (the whole of r10, not a delta; one more round before building was the founder's call in chat on 2026-10-31): both lenses converged with 0 P1, folded into r11. The trend 22, 12, 7, 8, 4, 2, 1, 1, 1, 0 converged, and the last five rounds' P1s were all test mechanics (a fake rule the plan had not stated), which is why r10 replaced the scattered fake rules with ONE complete contract table.

## Ground truth
Re-run by the author and again by reviewer B of the B-pass against the files and the founder's folder: 616 bundled stills, 3,102,690 bytes, every sha256 equal to the table and to the founder ledger's thumbnail; 253,550,820 bytes of animations over 616 files (largest 987,558); 924 files in each of the founder's two folders (this corrected OI-443's 923); the library has 914 rows, 617 with `media_slug`, 616 distinct slugs, no duplicate name, no row with both a plate and an animation; the spike scan (S7) of all 924 animation files found 0 RIFF-size violations and loop count 0 (infinite) everywhere; Dio 5.9.2 fires `onReceiveProgress` for in-memory bodies (read from `response_stream_handler.dart`); the web adapter's `xhr.timeout` is the sum of the connect and receive timeouts.

## Execution evidence
The commits on `library-batch-m2` and their per-task mutation evidence are listed in `docs/audit/library-batch-m2.closure.yaml` (49 entries, every one terminal, Gate 40 passes). Mutation proof, task by task: Task 5 48 of 48 killed, Task 6 23 of 23, Task 7 32 of 32, Task 9 23 of 23 (plus its inert control), and the B-pass fix pass 36 of 38 (the two survivors are the `_generation++` lines, a stated review-only limit).

Full `flutter test` on the founder's Windows machine, twice: on `8956d92a` (before the B-pass fix pass) 12,168 passed, 35 skipped, 3 failed; on `10c7ef55` (the final code, the tree the commit holds) **12,201 passed, 35 skipped, 3 failed**. The three failures are the same both times and are the known Windows-only reds on the board, none touching this batch: `gate_index_e2e_test` and `discipline_hook_local_indexes_e2e_test` (OI-415) and `merge_scope_git_test` S21 (OI-446). Whole-project `flutter analyze --no-fatal-infos`: 0 warnings (the only infos in the new files are the `fake_async` ones the other fake-clock tests already carry). `sh scripts/pre-commit.sh` and every commit's pre-commit passed. CI on the PR and pre-push have NOT run; they are the gates that count for the merge.

## B-pass
Two fresh Sonnet reviewers (production code; tests, script, docs, registry, numbers): 28 distinct findings (0 P0, 3 P1, 3 P2, 22 P3), every one verified by the author before acting; 25 fixed in the batch, 3 ruled to stand with their cost stated; 0 false alarms. The author's own mutation proof then found a 29th, which no reviewer could see: two new forbidden-word patterns in a source-grep test held backspace characters instead of word-boundary escapes and could never match. Fixed, and a byte scan of every changed file is clean. Verdict `accepted`, `docs/reviews/library-batch-m2-bpass.md`.

## Founder decisions in chat, 2026-10-31
1. **Waiver, granted.** The Task 1 observations that need a QA login and a phone are WAIVED before the merge and become a post-merge device and web check: S1 (does the animation play on a phone and in Chrome), S2 and S4 (a real user token's read and refusal statuses), S3 and S3b (does the web browser allow the authenticated read), S6 (memory and first-frame time of the 48-frame file on a low-end phone), S8 (does the web store survive a reload). Consequences accepted: both platform switches ship `true`; web ships the direct GET; the signed-link fallback (Task 6 Step 6) is NOT built; "the second open works offline on web" stays documented as unverified until S8; a CORS refusal on web would leave web users with the still pictures until a new OI reopens Task 6 Step 6; an S6 memory problem is answered by the decode-width clamp (720 to 360) or the platform switch. The check is tracked on OI-440 ("Blocked on").
2. **Design call C8 confirmed.** A downloaded animation survives sign-out (the cache is outside every wipe list; pinned by a test on the real web box name and the real `clearAllData()`).

## Still owed (on the board, not in this record)
M2c (Wi-Fi bulk prefetch, OI-440 second half) and M2b (OI-354) as drafts that need their own two reviews; the OI-443 data step (148 old-row pairs, the live upload, the seed bump), the 11 held pairs and the picture check of the 529 shipped rows; OI-444 (Supabase Pro, Spend Cap, usage alert) and OI-445 (sign-up CAPTCHA), both launch gates; the post-merge phone and web check above.
