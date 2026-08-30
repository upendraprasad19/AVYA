---
reviewed_at: 2026-08-30T00:00:00+05:30
staged_against: 56e7d3cf49d0
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — 56e7d3cf49d0 (profile-phase-fixes, staged)

> Note on process: the review was dispatched fresh (context-blind) against staging hash
> `81429739f3d3`. The subagent misread `git cat-file -t <hash>` failing on a
> `git hash-object` (without `-w`) output as evidence the hash was wrong, and substituted the
> HEAD commit sha into its own report instead — that substitution was incorrect and is not
> reflected here; `git hash-object` deliberately never writes the blob, so `cat-file` failing is
> expected, not an error. The hash below (`56e7d3cf49d0`) is recomputed twice over from the
> hash the reviewer was dispatched against: once for the post-remediation diff (all 6 findings
> fixed), and again after staging this review file's own required tuning-history entry in
> `.claude/skills/code-review/SKILL.md` (§5.1) — `docs/reviews/**` is excluded from the hash,
> but the skill file is not, so adding that entry shifted the hash a second time. Both
> recomputes were verified live via `git diff --cached ... | git hash-object --stdin`, not
> assumed.
>
> This is self-referential: this file's content cites its own hash-derived filename, and the
> skill file's tuning entry cites this file's name — so fixing either after the other changes
> the hash again, with no fixed point under naive iteration. Deliberately NOT chased further
> after this point: `scripts/check_code_review_pass_exists.dart` only hard-requires an exact
> `<hash>-review.md` match at blast-radius `catastrophic` (verified by reading the gate's own
> source, not assumed from its header comment, which says something else and is stale); this
> branch is `platform`, where the gate passes regardless and the file's existence + content is
> what carries the review, not its filename's exactness against the final staged byte range.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `lib/core/services/sync/sync_profile.dart:598-617` (the injection branch), `lib/core/services/sync_service.dart:1620-1622` (C3 call site), `lib/core/services/sync_service.dart:1417` (C3 attempted first for every restore)
- **claim:** The retry protection in `_fetchUsersRowForRestore` was only reachable when `_restoreUserProfile` is called with no `preFetchedUsers` argument. The C3 single-call restore (tried FIRST for every restore) injects `preFetchedUsers: row('users')` directly — a real `null` there bypassed the retry helper AND its telemetry entirely, silently narrower coverage than the diagnose-doc claimed.
- **verification:** Independently confirmed by reading `sync_service.dart:113,1417,1620-1622` and `supabase/functions/restore-user-snapshot/index.ts:116,128-151` directly — the EF behind C3 uses a SERVICE_ROLE client (RLS-immune) and its `q()` wrapper throws on real Postgres errors rather than returning ambiguous nulls, so a null there cannot be the stale-token race this fix targets (a retry would gain nothing) — but the branch was silently doing nothing instead of surfacing that.
- **suggested-fix:** Add a distinguishing telemetry event on the C3-path null case; correct the diagnose-doc's coverage claims.
- **status:** accepted — fixed. Added an `else if (!identical(preFetchedUsers, _kNoInject))` branch in `_restoreUserProfile` (now `sync_profile.dart:603-617`) that logs `restore_users_row_null_via_singlecall` distinctly, without a pointless retry. Regression test added: `test/contracts/restore_users_row_retry_test.dart` group "C3 single-call null-injection coverage (B-pass finding 1)". Diagnose-doc `d4e9a2`'s `impact_analysis`, `writers:`, `telemetry_op_types`, and `forbidden_patterns_checked` updated with the full coverage-boundary explanation; `docs/sot_registry.yaml`'s note and `lib/core/services/CLAUDE.md`'s pitfall row updated with the same nuance for future readers.

## Finding 2 — P1 — asserted_fixture_value
- **file:line:** `docs/diagnoses/2026-08-30-profile-full-name-restore-race-d4e9a2.md` (symptom section), mirrored into `docs/sot_registry.yaml`
- **claim:** The diagnose-doc's central telemetry evidence misidentified the second affected account as `amar@gmail.com`; live `client_errors`/`users` data shows it is actually `anoopdd13@gmail.com` ("Bruce Wayne") — a genuinely different account. Per-account occurrence counts (2/3 split) were also wrong (actual: founder 4×, other account 2×).
- **verification:** Independently re-ran both SQL queries myself (not just trusted the reviewer's transcript):
  ```sql
  select ce.created_at, ce.user_id, u.email, u.full_name, ce.op_type
  from public.client_errors ce left join public.users u on u.id = ce.user_id
  where ce.op_type = 'profile_full_name_empty_at_read' order by ce.created_at;
  -- 6 rows: 4× d7a67a37... (upendraprasad19@gmail.com), 2× 8c8a1d03... (anoopdd13@gmail.com)

  select id, email, full_name from public.users
  where email in ('amar@gmail.com','anoopdd13@gmail.com') or id = '8c8a1d03-c844-4307-9789-6717028155e0';
  -- confirms these are two distinct users; amar@gmail.com has zero matching client_errors rows
  ```
  Confirmed correct — this was a real mistake in the original investigation, not a reviewer hallucination.
- **suggested-fix:** Correct the account identity and occurrence split in the diagnose-doc and SoT note.
- **status:** accepted — fixed. Symptom section rewritten with the corrected account (`anoopdd13@gmail.com`) and occurrence split (4/2), with an explicit "CORRECTED (B-pass review)" note explaining what changed and that it doesn't affect the diagnosis or fix — only the evidence citation. `docs/sot_registry.yaml`'s note corrected identically.

## Finding 3 — P2 — guard_without_its_mirror
- **file:line:** `lib/core/services/sync/sync_profile.dart:700-701` (pre-fix)
- **claim:** The hard-refresh (`auth.refreshSession()`) and retried `select()` had no try/catch of their own — a throw from the refresh itself (e.g. a revoked/expired refresh token) fell into `_restoreUserProfile`'s generic outer catch (`reason: 'sync_service_if_14'`, shared with any unrelated failure), less observable than the `resolveDestination` precedent this fix claims to mirror, which DOES wrap its equivalent block.
- **verification:** Independently confirmed by reading `sync_profile.dart:688-708` (pre-fix) directly — no catch around the hard-refresh block — and `auth_session_bootstrapper.dart:188-206`, which does wrap its equivalent.
- **suggested-fix:** Wrap the hard-refresh + retry in its own try/catch with a distinct telemetry reason.
- **status:** accepted — fixed. `_fetchUsersRowForRestore` (now `sync_profile.dart:714-732`) wraps the hard refresh + retry in its own try/catch, logging `restore_users_row_retry_threw` via `ErrorTelemetry.recordNonFatal` and returning `null` rather than propagating. Regression test added: `restore_users_row_retry_test.dart` group "hard-refresh failure isolation (B-pass finding 3)".

## Finding 4 — P3 — blast_radius_mismatch
- **file:line:** `docs/diagnoses/2026-08-30-deployment-label-and-phase-tripwire-b7f1c8.md` (`impact_analysis`), `docs/blast_radius.yaml:240,297,313`
- **claim:** The diagnose-doc claimed `workout_schedule_read_service.dart` was individually `feature`-tier. Checking the path directly against the live registry: line 240 pins the OLD monolith filename `workout_schedule_service.dart` (different file — a stale citation), not the actually-touched `workout_schedule_read_service.dart`, which falls through to the `lib/core/services/**` catch-all (line 313) at `account`.
- **verification:** Independently confirmed via `grep -n "workout_schedule\|lib/core/services/\*\*\|lib/features/train" docs/blast_radius.yaml` — exactly as claimed. Doesn't change the branch-level `platform` verdict (re-ran `blast_radius_from_diff.dart` against the full staged list, still `platform`) or even this doc's own `account` verdict (now doubly-driven, since `hold_week_labels.dart` independently hits `account` via a different catch-all at line 317).
- **suggested-fix:** Correct the reasoning sentence.
- **status:** accepted — fixed. `impact_analysis` rewritten to cite the correct catch-all (line 313) and note the stale-filename trap explicitly, with a "CORRECTED (B-pass finding 4)" note.

## Finding 5 — P3 — asserted_fixture_value
- **file:line:** `docs/sot_registry.yaml` (`_restoreUserProfile` `line_range:`), `docs/diagnoses/2026-08-30-profile-full-name-restore-race-d4e9a2.md` (`writers:`, `line: 632`)
- **claim:** `line_range: 579-659` overstated `_restoreUserProfile`'s actual span (579-655 pre-fix); `line: 632` pointed at a comment, not the actual merge-loop statement (line 634 pre-fix).
- **verification:** Independently confirmed by reading `sync_profile.dart` directly at the cited lines — both citations were off by a small amount, exactly as claimed. Neither gate (Gate 7, Gate 42) validates exact-span/exact-statement accuracy, only in-bounds.
- **suggested-fix:** Correct both citations.
- **status:** accepted — fixed. Both fixed as part of the larger rewrite (the function's fixed span is now 579-669 post-fix, correctly reflecting the two new branches; the merge-loop citation now correctly points at line 648 post-fix).

## Finding 6 — P3 — informational (no action required in this diff)
- **file:line:** `lib/core/services/auth_session_bootstrapper.dart:151-208, 253-255`
- **claim:** The cited precedent (`resolveDestination`) only retries on a THROWN exception — `classifyDestination(null)` returns normally for a null/empty result, so the precedent does not actually cover the null-result case its own doc comment describes as the motivation. The new code in this diff (`_fetchUsersRowForRestore`) is written correctly and independently — it explicitly checks `if (first != null) return first;` rather than relying on a catch — so this doesn't affect the diff under review.
- **verification:** Independently spot-read `auth_session_bootstrapper.dart:172-174,253-255` — confirms the shape described. Not re-verified exhaustively since the finding explicitly requires no action here.
- **suggested-fix:** None required in this diff. Worth a separate, smaller follow-up on `resolveDestination` itself if the founder wants that precedent to actually retry the null case too — not filed as an OI in this batch since it's outside this batch's scope and the finding itself frames it as optional, not a defect in what's being reviewed.
- **status:** no_change_needed — informational only, confirmed no action was warranted in this diff.

## Lenses that found nothing

(As reported by the reviewer; independently spot-checked function_exception_swallow, secrets_in_tree, and unawaited_no_error_sink via the same grep commands during remediation — all still clean after the fixes, since no new `.functions.invoke(`, credential-shaped literal, or unguarded `unawaited(` was introduced by the remediation itself.)

- **function_exception_swallow** — no `.functions.invoke(` in the diff.
- **secrets_in_tree** — no credential-shaped literals.
- **unawaited_no_error_sink** — every `unawaited(` (6 after remediation, up from 4) routes through `ErrorTelemetry.logEvent`/`recordNonFatal`, both of which swallow internally.
- **writer_reader_drift** — no new Hive or cloud writes; all changes are reads, pure formatting, or telemetry.
- **missing_input** — all fixtures/helpers the tests use were confirmed to exist with the assumed shape; all touched/adjacent test files re-run green (61/61 across 5 files) after remediation.

## Founder triage notes

All 6 findings fixed in this same batch — two real code changes (Findings 1 and 3, both closing genuine observability gaps on the C3 single-call restore path and the hard-refresh failure path respectively, each with a new regression test), and four documentation corrections (Findings 2, 4, 5, and the disclosure that Finding 6 needs no action). Re-verified independently rather than trusting the reviewing subagent's transcript: re-ran all 5 relevant pre-commit gates (Gate 7, Gate 42, container-color, schema-column-refs, deferral-euphemism) directly, re-ran all 61 tests across the 5 touched/adjacent test files, re-validated both diagnose-docs, and re-ran two of the live SQL queries myself against Postgres to confirm Finding 2's correction and Finding 4's blast-radius claim before writing anything.

Blast-radius unchanged: still `platform` (driven by `sync_profile.dart` under `lib/core/services/sync/**`).
