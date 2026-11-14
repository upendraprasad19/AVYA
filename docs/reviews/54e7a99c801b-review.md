---
reviewed_at: 2026-09-29T19:51:28+05:30
staged_against: 09d6fdf91519
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
---

# Code Review — 54e7a99c801b

> **Provenance, stated plainly.** The fresh Sonnet reviewer ran against the staged tree whose
> staging hash was `09d6fdf91519` (39 files). The findings below were then FIXED, and one further
> unit (U6, `plan_engine/CLAUDE.md` trim) was added at the founder's request, so the FINAL staged
> tree hashes to `54e7a99c801b` (44 files) — the name of this file, which is what
> `check_code_review_pass_exists.dart` looks up. `staged_against:` records the tree that was
> actually reviewed. The post-review changes are listed under "Changes after the reviewed tree"
> together with how each was verified; they were NOT reviewed by the B-pass reviewer itself
> (two independent round-2 reviewers and a coordinator mutation run covered the fixes).

Scope of the change: documentation lean-down (root CLAUDE.md 152,740 B -> ~40.8 KB; two skills
split; six nested CLAUDE.md files trimmed; 22 closed OI entries archived) plus the gate/test/
registry edits that keep the moved text enforced. Prose moves were checked line-by-line by
earlier rounds (`docs/plan-reviews/context-lean.md`); this pass concentrated on the ~10 code,
test and YAML files and on the prose that binds agent behaviour.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** scripts/check_context_artifact_budget.dart:50-58 (kTrackedArtifacts), test/scripts/context_artifact_tracked_list_test.dart:29-40
- **claim:** The added comment said the batch tracks "the five largest nested CLAUDE.md files". False: `lib/shared/repositories/plan_engine/CLAUDE.md` (40,328 B, second-largest CLAUDE.md), `supabase/migrations/CLAUDE.md` (18,244 B) and `lib/features/onboarding/CLAUDE.md` (17,384 B) were untracked and could regrow silently; the tracked-list test pins names so it could never notice a missing eleventh.
- **verification:** `find . -name CLAUDE.md -not -path "./node_modules/*" -not -path "./.claude/worktrees/*" -exec wc -c {} + | sort -rn | head -8`
- **suggested-fix:** track plan_engine, migrations and onboarding CLAUDE.md, or reword the comment.
- **status:** fixed — all three now tracked (13 paths), comment reworded, `_pinned` extended, baselines re-recorded. plan_engine was additionally TRIMMED (40,328 -> 16,986 B, new `docs/architecture/plan-engine-detail.md`) at the founder's direction.

## Finding 2 — P2 — blast_radius_mismatch
- **file:line:** docs/blast_radius.yaml:69-77
- **claim:** `docs/architecture/hooks.md` classified `feature` although it now holds the full §0 hook/CI wording, the discipline_hook rows, the OI allocator row and the safe_push/_git_lock rules that were `platform` while inline in root CLAUDE.md. Editing the doc that tells agents how the gates work cleared no plan-review or B-pass gate.
- **verification:** `dart run scripts/blast_radius_from_diff.dart docs/architecture/hooks.md 2>&1 | tail -1`
- **suggested-fix:** add `{ glob: "docs/architecture/hooks.md", tier: platform }`.
- **status:** fixed — glob added; `plan-engine-detail.md` also added (platform) to mirror its parent directory. `check_blast_radius_coverage.dart` PASS. (This reverses the coordinator's earlier "leave at feature" default; two independent reviewers recommended platform.)

## Finding 3 — P3 — writer_reader_drift
- **file:line:** scripts/check_no_deferral_euphemism.dart:139-150 (`_governingDocs()`), :175
- **claim:** The gate's FULL sweep covered only root CLAUDE.md plus `**/SKILL.md`. Binding prose that moved out of those files (process-invariants-detail.md, hooks.md, common-pitfalls.md's appended §4.9 block, bug-classes.md, tuning-history.md) fell outside the sweep; only the staged-diff scan (`*.md`) would see new edits to them. The gate's own header says the full sweep exists because "a diff-scoped gate can never see a violation older than itself" — that class was reopened for the moved text.
- **verification:** `grep -n "endsWith('/SKILL.md')" scripts/check_no_deferral_euphemism.dart`
- **suggested-fix:** add the moved docs to `_governingDocs()`.
- **status:** fixed — sweep now reads 21 documents (was 16): SKILL.md files plus `bug-classes.md`, `tuning-history.md`, `hooks.md`, `process-invariants-detail.md`, `common-pitfalls.md`; all pass. 6 tests added to `test/contracts/deferral_euphemism_gate_test.dart` (5 committed-euphemism-caught + 1 non-governing control). Mutations: moved-docs loop disabled -> 3 red on `Expected: <1> Actual: <0>`; skill-file filter narrowed -> 2 red; both restored, 18/18 green. A later full gate loop also caught `check_gate_existssync_file_vs_dir` flagging the new `File(...).existsSync()`; fixed with the gate's own `// file-only:` justification.

## Finding 4 — P3 — missing_input (pre-existing, moved unchanged)
- **file:line:** docs/architecture/services-detail.md, docs/architecture/train-detail.md
- **claim:** Test paths cited in moved prose do not exist: `test/contracts/sync_fanout_workout_domain_writer_to_reader_test.dart`, `test/contracts/workout_completion_status_test.dart` (and `restore_completeness_test.dart` under contracts). Dead at HEAD already.
- **verification:** `ls test/contracts | grep -i "restore_complete\|workout_completion\|sync_fanout"`
- **suggested-fix:** repoint while the docs are being moved.
- **status:** fixed for the two live cites (now `sync_fanout_workout_domain_behavioral_test.dart` + nutrition sibling, and `workout_completion_status_writer_to_reader_test.dart`; both successors verified to test the same SoT concept). The `restore_completeness_test.dart` occurrence is a deliberate "this file does not exist" phantom-citation warning note (the real test is `test/sync/restore_completeness_test.dart`, which exists) and was left as written.

## Lenses returned clean
- **writer_reader_drift (main):** path-existence sweep of every backticked `*.md/.dart/.sh/.yaml/.json/.ts/.sql` path in root CLAUDE.md, the 7 detail docs, hooks.md, the 5 nested files and the 2 skills — 0 missing beyond Finding 4. Every reader of the tuning-history path repointed (`check_skill_tuning_history.dart:24`, `skill_tuning_lib.dart:193`, e2e fixtures); `:(top,exclude)` appears in exactly 3 places (gate, contract test, SKILL.md:180) and all carry the new exclude; 87 index ids == 87 `bug-classes.md` heading ids; headings root cites exist in the detail docs. 19 targeted test files, 175 tests green; `check_claude_md_citations`, `check_doc_internal_consistency`, `check_nested_claude_md_content`, `check_context_artifact_budget`, `check_gate_test_ledger`, `check_blast_radius_coverage` all PASS.
- **function_exception_swallow:** 1 `functions.invoke(` hit in the whole staged diff, a moved prose table row in bug-classes.md; 0 in changed Dart/TS.
- **blast_radius_mismatch (globs):** process-invariants-detail/functions-detail `platform`, services/auth/ai-coach-detail `account`, matching their parent CLAUDE.md files; changed scripts `platform`; overall `platform`.
- **secrets_in_tree:** grep of `^+` lines of the full staged diff for `sk-`, `rzp_live`, `rzp_test_<8+>`, `AKIA`, `BEGIN (RSA|PRIVATE)`, `eyJ…`, `AIza`, 60+ char base64/hex runs — 0 hits; only public identifiers already in HEAD (Supabase project id, OneSignal app id, Firebase sender id).
- **unawaited_no_error_sink:** 0 `unawaited(` in changed Dart.
- **guard_without_its_mirror (mutation run by the reviewer):** deleted the `:(top,exclude).claude/skills/code-review/tuning-history.md` pathspec line in `check_code_review_pass_exists.dart` (`grep -c` 1 -> 0) — `review_gate_staged_content_not_working_tree_test.dart` 1 red of 5 on `Expected: <0> Actual: <1>` (assertion, not compile error); restored, sha256 identical. Mirror cases: only-SKILL.md-staged BLOCKS (safe); unreadable tuning-history.md fails OPEN (unchanged); absent tracked path is now caught by the tracked-list test's exists-on-disk leg.
- **missing_input:** `## 7. Tuning history` at `tuning-history.md:9` with 111 dated bullets, so the lib's matcher still finds its input; `blast_radius_from_diff` run on real paths only.
- **asserted_fixture_value:** the `_pinned` paths equal the keys of `backups/context_artifact_sizes.json` and `kTrackedArtifacts`; the tracked-list test fails on list removal, baseline drift and missing files (verified by the coordinator's mutation: 2 of 3 red naming the dropped path).
- **Root CLAUDE.md P0-class instruction check:** still carries no-commit-unless-asked ("continue" does NOT count), safe wrappers + `ALLOW_RAW_GIT`, `--no-verify` approval path, live-prod-apply needs its own go, no-deferrals (semantic ban + rule 20), §4.13 points 6–8, the §2a project-id guard and the self-initiated B-pass. No lost binding rule.

## Changes after the reviewed tree
1. **U6:** `lib/shared/repositories/plan_engine/CLAUDE.md` 40,328 -> 16,986 B; detail in `docs/architecture/plan-engine-detail.md` (37,785 B). Coordinator re-check: 310 original non-blank lines, 1 not found verbatim (the intentionally bumped `updated:` date). Only one test names the file (in comments/`reason:` strings); Gate 26 mutation red on assertion.
2. Root CLAUDE.md §7 row names `plan-engine-detail`; budget baseline re-recorded (13 tracked, all within band).
3. `check_no_deferral_euphemism.dart` `// file-only:` justification (see Finding 3).
Verification after all of the above: pre-commit loop exit 0; `flutter analyze lib/` 60 infos / 0 warnings / 0 errors; full suite `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` 7064 passed, 9 skipped, 0 failed.

## Founder triage notes
All four findings are resolved as above; `verdict: accepted` reflects that every finding has a non-pending status. Left to founder judgement: the coordinator's reversal on `hooks.md` (now `platform`), and the still-uncommitted `lib/core/services/CLAUDE.md` row in the primary checkout (diagnose f7b2c9), which will conflict with the trimmed file when it lands.
