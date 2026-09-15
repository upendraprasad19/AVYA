---
reviewed_at: 2026-07-29T13:45:00+05:30
staged_against: ci-gate-skip-fix
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review — ci-gate-skip-fix (96c6fac2..HEAD)

## Summary verification

The stated story checks out. `scripts/check_closes_oi_cited.dart:105-110` does
`if (args.isEmpty) { stderr.writeln('Usage: ...'); exit(2); }` — a bare
invocation genuinely exits non-zero, confirming the claimed crash mechanism.
`.github/workflows/test.yml`'s "Run all check_*.dart gates" step bare-invokes
every unskipped `scripts/check_*.dart` with zero args, confirming it would hit
that path. The fix adds the script to that step's case-skip block and to
`check_gate_scripts_wired.dart`'s `_allowList`. Both are present and correctly
placed in the current tree.

## Finding 1 — P1 — blast_radius_mismatch
- **file:line:** `docs/plan-reviews/` (file `ci-gate-skip-fix.md` did not exist at review time)
- **claim:** `docs/blast_radius.yaml:98,101,172` classifies `scripts/check_gate_scripts_wired.dart`, `scripts/pre-commit.sh`, and `.github/workflows/test.yml` — all touched by this branch — as `platform` tier. CLAUDE.md §4.12.3's keystone gate (`scripts/check_plan_review_record_exists.dart`) requires `docs/plan-reviews/<branch>.md` with `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`, and `bpass: accepted` (required at ≥platform), enforced at the merge-to-main commit in CI. No such file existed for branch `ci-gate-skip-fix` at review time.
- **verification:** `ls docs/plan-reviews/ | grep -i ci-gate` (no output at review time); `grep -n "check_gate_scripts_wired.dart\|pre-commit.sh\|test.yml" docs/blast_radius.yaml` shows all three at `tier: platform`.
- **suggested-fix:** Author `docs/plan-reviews/ci-gate-skip-fix.md` citing round 1, round 2, and this B-pass before merge.
- **status:** accepted — `docs/plan-reviews/ci-gate-skip-fix.md` authored immediately after this review, citing all three review events.

## Finding 2 — P3 — gate_wiring_parse_precision
- **file:line:** `scripts/gate_scripts_wired_lib.dart` (`extractCaseSkips`, as it stood at review time)
- **claim:** `extractCaseSkips` tracked only the coarse `case "$NAME" in` → `esac` boundary and regex-matched every line in between — including comment lines inside a case arm's command body, not just its pattern-list lines. `.github/workflows/test.yml`'s `check_closes_oi_cited.dart` arm has an explanatory comment restating that exact filename inside its command body, so it was independently (and redundantly) picked up as a case-skip regardless of whether the real pattern line was present. Currently harmless for Gate 33's own PASS/FAIL verdict (a separate literal mention elsewhere in the file protects it via the `inWorkflow = A || (...)` first disjunct), but this fix's own regression test asserts `extractCaseSkips(...).contains(_gate)` directly, with no such protective redundancy — a future edit deleting the real pattern line while leaving the comment would make the test wrongly keep passing.
- **verification:** `sed -n '170,186p' .github/workflows/test.yml` showed the comment inside the case block's command body; extracting the pre-fix `_extractCaseSkips` from commit `f258f6bd` and running it standalone against a synthetic block with a comment-only name confirmed the false positive.
- **suggested-fix:** Make `extractCaseSkips` track the pattern-list portion of each arm separately from its command body, stopping the scan at the line containing the arm's closing `)`.
- **status:** accepted — fixed. `extractCaseSkips` now stops scanning for names at each arm's closing `)` and resumes only after `;;`. New test group `test/contracts/gate_wiring_args_required_test.dart` "B-pass scar" (2 tests): a synthetic case block proves a comment-only name is no longer reported as skipped, confirmed to fail against the extracted pre-fix logic before the fix landed; a second test pins the real `test.yml` file still resolves correctly via its genuine pattern-list entry. Gate 33 re-run: PASS (91). Full related-test sweep (`gate_wiring_args_required_test.dart` + 3 other files referencing `check_gate_scripts_wired.dart`): 46/46 green.

## Lenses checked, clean

1. **writer_reader_drift** — N/A, confirmed rather than assumed. `git diff 96c6fac2..HEAD | grep -inE "\.box\(|Hive\.|supabase\.from\("` returned zero matches. All touched files are CI/gate tooling with no Hive box or Supabase table reference anywhere in the diff.

2. **function_exception_swallow** — N/A, confirmed. `git diff 96c6fac2..HEAD | grep -in "\.functions\.invoke("` returned zero matches. No Edge Function client call exists in this diff.

3. **blast_radius_mismatch** — the tier declaration itself is correct (diagnose-doc frontmatter + `docs/blast_radius.yaml` agree: `platform`). Process gap identified as Finding 1, closed by this same review cycle.

4. **secrets_in_tree** — clean. `git diff 96c6fac2..HEAD | grep -inE "sk-[a-zA-Z0-9]|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN|api[_-]?key|secret|password|token"` returned exactly one hit: the diagnose-doc's own `touched_layers_checked` frontmatter line documenting that no secret is involved — prose, not a credential.

5. **unawaited_no_error_sink** — N/A, confirmed. `git diff 96c6fac2..HEAD | grep -in "unawaited("` returned zero matches.

## Extra risk-surface verification (beyond the 5 lenses)

- **Fix actually executed, not just read:** `dart run scripts/check_gate_scripts_wired.dart` → PASS 91. `flutter test test/contracts/gate_wiring_args_required_test.dart` → all green. `flutter analyze` on the three touched files → No issues found.
- **New case-skip entry syntax:** read directly — valid bash, and exercised live by the gate run above.
- **`extractCaseSkips` equivalence to pre-extraction logic:** diffed both function bodies — byte-identical aside from the deliberate public rename (Finding 2 above then hardened the shared logic further, post-review).
- **`git diff --stat` scope check:** every touched file directly in-scope; no stray files; `docs/diagnoses/INDEX.md` regenerates to an empty diff (not stale/hand-edited).
- **Diagnose-doc validity:** `dart run scripts/validate_diagnose_doc.dart` → OK.
- **Independent numeric verification** (this branch's own history shows two prior miscounts of the same number): "12 other entries" pre-existing in test.yml's skip-list — manually recounted from the real pre-fix blob, confirmed 12. "PASS: all 91 gate/validator scripts covered" — live-executed, confirmed 91. "3/3 new contract tests green" (as of the commit reviewed) — live-executed, confirmed. All independently verified against real output, not assumed from prose.
- **Section citation correction (§4.3 → §7):** verified against the actual root `CLAUDE.md` — accurate.

## Founder triage notes

Both findings closed in the same review cycle: Finding 1 by authoring the plan-review record immediately after; Finding 2 by hardening `extractCaseSkips` and adding the "B-pass scar" test group, verified with a genuine negative control against the pre-fix parsing logic. No P0/P1 defect survives. `verdict: accepted`.
