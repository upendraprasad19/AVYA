# Plan: correct the column comment on user_profile.session_duration_minutes (migration 166)

Date 2026-11-03. Branch `session-minutes-comment`. Tier L (schema, live apply) / `platform`. Execution mode: INLINE.
Origin: closure row `SBF-MIGRATION-COMMENT` (`docs/audit/set-budget-flip.closure.yaml`, PR #195). Founder go 2026-11-03: "ok" to the migration apply (comment-only live change). Because 4.3 wants a per-action go, the actual `apply_migration` call is made only after the founder confirms in chat that it may run NOW, with the project id and the exact statement shown (a classifier block is answered by that go, never worked around). The live apply is the only live action.

## Problem
Migration 017 (`supabase/migrations/017_user_profile_missing_columns.sql:18-19`) put this comment on `public.user_profile.session_duration_minutes`: "Preferred workout duration in minutes (30/45/60) ... NOTE: post-V4 the plan generator no longer reads this". Since PR #195 (2026-11-03) the plan generator does read it (`TrainingHistoryAnalyzer.sessionMinutesFromProfile` -> `SessionBudget.resolveMinutes`; the picker also offers 90). Live read on project `dedsavbjuwgarrhphgnl` (2026-11-03, `col_description`) shows the 017 text still on the column.

## Change
- New `supabase/migrations/166_session_duration_minutes_comment.sql` (number reserved with `scripts/mint_migration.sh --stub`, ref `mig/166`; live `list_migrations` has no 166): ONE statement, `COMMENT ON COLUMN public.user_profile.session_duration_minutes IS '<corrected text>'`. Four-tag header, inline rollback (017's text), read-only post-apply check as a comment.
- Migration 017 is applied and IMMUTABLE: it is not edited.
- `backups/applied_migrations.json`: entry `166` with the full key set of entries 163 to 165: `migration`, `applied_at` (the real apply time), `hash` (`dart run scripts/migration_ledger_hash.dart 166`, never a raw sha256sum), `applier` (`claude-via-mcp-apply-migration`), `diagnose` (`n/a`), `slug` (`session_duration_minutes_comment`), `cloud_version` (the 14-digit version the apply returns), `note` (the post-apply live read).
- No column, constraint, policy, grant or row changes, so `backups/live_schema_columns.json` is untouched (comments are not columns); no SoT concept changes; no code.

## Apply protocol (per-action go given; project `dedsavbjuwgarrhphgnl` ONLY, never `krcrkntuwutvnmdnkfqf`)
1. Plan reviewed twice, B-pass on the staged diff. 2. Apply the file's single `COMMENT ON COLUMN` statement VERBATIM (the same bytes as in the final file; header and the trailing comment blocks are not sent, as for migrations 163 and 165) with `mcp__claude_ai_Supabase__apply_migration` (name `session_duration_minutes_comment`), project id re-confirmed in the call. The ledger hash is computed AFTER the last edit of the file. 3. Read back `col_description`: must equal the new text exactly. 4. Write the ledger entry (hash, applied_at, post-apply read) in the SAME commit as the file. 5. Close the closure row `SBF-MIGRATION-COMMENT` in `docs/audit/set-budget-flip.closure.yaml` (`blocked_on_user` to `closed_in_commit`, commit stamped by a second commit, `closed_count` recomputed) and the stale reference at `docs/audit/session-set-budget.closure.yaml:297`. The row `BP3-P3-8B` in `session-set-budget.closure.yaml` (lines 294-297) changes `terminal_state` (line 296) and its reason (line 297) to `closed_in_commit` + `commit:` + `verification:`; both ledgers' `closed_count` are recomputed from entries. 6. Plan-review record `docs/plan-reviews/session-minutes-comment.md` (`review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review:` naming the B-pass file, which carries a bare `verdict: accepted` line), written in the second commit; replay `check_plan_review_record_exists.dart` in a scratch clone before the merge. 7. Gate loop (pre-commit), push, PR, CI, merge via `safe_pr_merge.sh`, retire the worktree.

## Risks / mirror cases
- The SQL string literal must hold exactly two single quotes (no apostrophe inside; a `day's` in the first draft would have ended the string early and the statement would fail or apply a truncated comment). Checked by a script on the file and by the exact-match read-back after the apply.
- A comment cannot change `pg_get_functiondef` or data; the only reader of the text is a human (dashboard) and `scripts/` doc tools: `git grep session_duration_minutes -- scripts test supabase/functions` for any reader of the OLD comment text (value-semantics sweep, 4.1.5(3)).
- Gate 39 hashes the file as applied: the file must not be touched after the apply; the ledger entry is written after the file is final.
- Number race: another branch minting 166 is prevented by the `mig/166` reservation; `check_migration_number_reserved.dart` checks it at commit.
- Rollback: the inline reverse COMMENT (017's text); it needs its own go, as any live apply.

## Out of scope
The Quads / thin-day / repeat-phase work (separate plans / OI-452 / OI-453).
