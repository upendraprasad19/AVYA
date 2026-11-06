---
reviewed_at: 2026-10-13
staged_against: referral-pay-on-conversion (the B-pass of 2026-10-12 read the working tree before the live apply, migration 159 untracked and the rest staged; the four hermes seats of 2026-10-13 re-read the fixed tree; this file is named after the final staged diff, which also holds the post-apply ledger entry and snapshots)
blast_radius: catastrophic (the migration glob is platform, but the SECURITY DEFINER content rule forces catastrophic: scripts/blast_radius_from_diff.dart, scripts/blast_radius_content_rules_lib.dart)
reviewer: claude-sonnet-b-pass (fresh, context-blind, read-only; ran nothing) + hermes pass 2026-10-13 (4 fresh Sonnet seats A SQL semantics and locking, B tests and mutation adequacy, C docs and gates, D abuse, privacy and apply protocol)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value, documentation_rot]
findings_count: 9
verdict: accepted
---

# Code Review (B-pass) - S1, the referral reward on conversion (migration 159)

A fresh reader (the B-pass, 2026-10-12) with no access to the author's reasoning read the working tree: the untracked migration 159, the replica tests, the Dart contract test, the registry, the ADR and the docs. **No P0, no P1; verdict "sound with fixes".** The reviewer re-derived every literal of the live verify from the SQL, found the rollback body byte-equal to the 158 body, and found no secret in any changed or untracked file. Nine findings; the author verified every one against the tree and resolved all nine in the batch, two of them in the migration itself before the live apply (findings 1 and 7; a comment edit after the apply would falsify the ledger hash).

## Finding 1 - P2 - function_exception_swallow - RESOLVED (reproduced)
A reward stall was invisible. `{"skipped":"locked"}` (a forgotten session holding the job lock) and `skipped_locked` (a referrer key or subscription row held for days) went into a jsonb that pg_cron discards, and only `failed` wrote an alert. The plan's claim that migration 146 sees a job that stops launching was a non sequitur: 146 judges only inactive jobs and jobs with no new run row, and a run that returns `skipped` still writes a `succeeded` row.
Fix: a third alert `referral_conversions_stalled` (warn, 23 h dedup, registered in `alerts/_thresholds.yaml`), written when a row with `converted_at <= now() - 10 days` is still unrewarded. The reviewer suggested placing it with the other alerts inside the job; the author checked the scenario against the code path and moved it to step 0, BEFORE the job try-lock, because a held job lock returns before the credit loop. Pinned by live verify S1-S3, S5, S6 and concurrency C2b (the alert is written while another session holds the job lock); mutants M80-M88, M97, M98 red (M80 moves the watch after the lock). The plan's section 6 row was corrected.

## Finding 2 - P2 - blast_radius_mismatch - RESOLVED (position recorded)
The unit is catastrophic and live on apply (the cron fires at the next :41, the redeem change is immediate); the plan stated no position on `requires: feature_flag` or CLAUDE.md section 4.6.
Position, now in the plan (section 2.1) and in `docs/plan-reviews/referral-pay-on-conversion.md`: no new runtime flag. The off state of the reward is `UPDATE cron.job SET active = false` (the documented kill switch, which migration 146 re-surfaces weekly; pending rows stay and keep vesting); the off state of the redeem change is the inline rollback, verified byte-for-byte on a fresh replica (function md5, columns, constraints, private functions, cron, ACL).

## Finding 3 - P2 - guard_without_its_mirror - RESOLVED (mutant reproduced the hole)
`v_pre` was read after nine job-running groups, so deleting `AND rr.referrer_rewarded IS NOT TRUE` from the credit select produced a failed alert that flipped `v_pre` to true and made F3 pass unconditionally; only the Dart pin and the deletion file's D4 killed it, and the live verify is the only gate runnable on the real project.
Fix: `v_pre` is read at block start and a case Z asserts zero failed alerts before group F; the SUMMARY line reports `skipped=` so a vacuous pass is visible. Mutant M78 (the credit select without the flag filter) is now red in the live verify. This was also a hole in the author's own mutation matrix.

## Finding 4 - P2 - guard_without_its_mirror - RESOLVED
Concurrency C8 (pgbench, job against redeem) could not see a job-side deadlock: a 40P01 victim inside the credit sub-block is absorbed by `WHEN OTHERS`, so the log stayed empty and the follow-up runs still credited the row.
Fix: after the run C8 asserts zero `referral_conversions_failed` alerts (the job writes at most one per 23 h, so any failure shows).

## Finding 5 - P3 - documentation_rot - RESOLVED
"65 cases" in three places (real count 69, later 86), plan line 64 returning `{marked}` while the migration returns `reconciled`, the live-verify header saying "never on the returned totals" while W13 asserts them, the header line about where the pre-159 run fails, the `payment.md` day-versus-timestamp wording, the Dart header missing groups, and the "no top up" date.
Fix: all edited; counts are no longer written down (the SUMMARY line counts the cases); the founder's "no top up" is dated 2026-10-13 IST, i.e. the evening of 2026-10-12 UTC.

## Finding 6 - P3 - guard_without_its_mirror - RESOLVED
Live verify R10 tested only a NULL referrer; dropping `OR p_referee_id IS NULL` still errors (22023 from the helper), differing only in SQLSTATE. The volume alert INSERT was exercised only on the replica.
Fix: R10b (a NULL referee is refused with 23502, not the helper's 22023) and live case S4 (more than 20 redemptions in 24 hours raise a warn volume alert on the live alerts table).

## Finding 7 - P3 - documentation_rot (inside the file that becomes immutable) - RESOLVED before the apply
The rollback note omitted that pending rewards (converted, not credited) vanish when `converted_at` and `referrer_reward_days` are dropped.
Fix: the rollback comment now says so, and opens with `SET lock_timeout = '3s'` (hermes seat D, D5). The file was re-hashed after the edit (final sha256 `74631ee7d4ba2d3fe1b0b3b54a98ddae84652d38e8957fe66a115b09f6740df1`).

## Finding 8 - P3 - documentation_rot / privacy - RESOLVED (founder call recorded)
The plan said the referrer sees "roughly when" a friend subscribed; the existing SELECT policy exposes `converted_at` to the second plus the plan class through PostgREST, and no friend-facing notice is recorded.
Disposition: wording corrected; the exposure itself is `blocked_on_user` in the closure ledger (item X7): a coarsened view or RPC, or a disclosure line in Unit C and the privacy-policy text.

## Finding 9 - P3 - function_exception_swallow - RESOLVED (wording)
The reconcile and the credit select each use `SKIP LOCKED` in separate statements, so a row locked during the reconcile (a referee deletion) can be unlocked by the credit select and credited on its stale `converted_at` instead of being voided. The window is milliseconds per hour and the plan accepts the same class for a cancel.
Fix: the absolute sentence in PROF-19 ("a deleted friend never rewards anyone") is softened; no code change.

## Checked and clean (reviewer's list, abridged)
Writer/reader values across migration, Dart test, yaml, CRON_REGISTRY, ADR, registry and docs (7/30 mapping, 90/97/7 constants, minute 41 and its IST conversion, job and alert names, 23 h dedup, 10/20 thresholds, the refusal text); registry line ranges at review time; only two functions INSERT paid `subscriptions` rows (`razorpay-webhook`, `verify-payment`) and nothing updates or deletes them; every column, role and setting read exists in the live snapshot or in migrations 038/052/076/094/133/140/145; prod is PostgreSQL 17.6 with pg_cron 1.6.4; no secret in any changed or untracked file; exception-handler order (`lock_not_available` before `OTHERS`); the arbiter case 27 insert has a NULL payment id and so does not meet the new refusal; stale references to the deleted `oi320_*` files only in history documents and immutable 158.

## Not verified by the reviewer
The reviewer ran nothing. The author ran, after the fixes: the live verify on the local replica (86 ok, 0 fail), the deletion file (D1-D7), the concurrency script (C1-C13), the inline rollback on a fresh replica, 104 mutants (0 survivors; table in `docs/audit/2026-10-13-hermes-referral-pay-on-conversion.md`), the Dart contract test, `flutter analyze lib/` and the full suite (9365 passed; the 2 reds were the expected pre-apply ones).

After the founder's go the migration was applied to the live project (2026-10-13 04:07 UTC, cloud version 20261013040701; the stored statement's sha256 equals the file's; the three function md5s equal a local apply of the same file) and the same live-verify file was run there through `execute_sql` at 13:24 UTC: **SUMMARY ok=86 fail=0 skipped=0**, with no fixture row, alert or trial left behind. Nine hourly cron runs (04:41-12:41 UTC) succeeded and credited nothing. Honest deviation: the apply was 34 minutes before a `:41` tick, not right after one, and the verify ran about nine hours after the apply because the first call failed with a transport error ("Invalid or expired requestState", nothing ran).

PostgreSQL behaviours the reviewer reasoned from memory (a `FOR ... FOR UPDATE` loop prefetch, advisory xact locks released on subtransaction abort, `pg_try_advisory_xact_lock(NULL)` returning NULL, a unique-index INSERT waiting on an uncommitted updater) were measured on the replica by the author or are covered by the concurrency cases C3, C5 and C10.
