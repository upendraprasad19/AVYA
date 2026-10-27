---
reviewed_at: 2026-09-19T12:09:11+05:30
staged_against: gate-integrity (commit a566f94c) vs main (8ffe28fb)
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass, own worktree)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, L24_gate_strictness, L37_empty_null_shape_readers, L52_gate_scripts_wired, L25_intra_document_drift, L20_diagnose_doc_pairing, L8_contract_test_coverage, L54_context_artifact_cost]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — gate-integrity (OI-220 · OI-155 · OI-195 · OI-181)

A fresh, context-blind Sonnet agent, in its OWN worktree (`git reset --hard a566f94c`, HEAD
confirmed), adversarially reviewed the integrated branch: four gate fixes with zero file overlap
(pre-push contract sweep; Gate 33 typed allowlist; Gate 42 path resolution; safe_merge
absent-record precheck) plus the integration docs. It was told to find bugs, not validate, and
to run every probe rather than read it. It ran the full `sh scripts/pre-commit.sh` loop on the
integrated tree (green), every touched/new test file individually (all green, counts
re-derived), live mutation probes against `contract_sweep_lib.dart` and Gate 33's allowlist
(both reddened correctly), and a from-scratch git-repo probe of `safe_merge.sh`'s precheck
(slash-branch, tag-only branch, missing classifier — all silent, as documented).

**Overall B-pass verdict: SHIP-WITH-FIXES. No P0, no P1.** One latent gate-strictness gap
(P2) and one date typo (P3). Both fixed in-branch in `e993a345`; triage below.

## Finding 1 — P2 — guard_without_its_mirror / L24 (gate-strictness)
- **file:line:** `scripts/gate_scripts_wired_lib.dart:139-147` (`invokesGate`, at the reviewed commit)
- **claim:** `invokesGate` treated any non-`#` line containing the substring `run scripts/<gate>`
  as an invocation, with no check that the line is EXECUTED rather than PRINTED — the exact class
  `extractCaseSkips` in the same file was hardened against one function above it. A heredoc body
  (`cat <<'EOF' … dart run scripts/check_foo.dart … EOF`) and plain prose ("You should run
  scripts/check_x.dart by hand before releasing.") both returned `true`. Not exploited today:
  every live `file()` runner target (`build-apk.md` ×3, `pre-commit.sh` ×2, `commit-msg.sh` ×1,
  `test.yml` ×1) resolves to a genuinely executed line.
- **verification:** throwaway probe importing the lib: `invokesGate("cat <<'EOF'\ndart run
  scripts/check_foo.dart\nEOF\n", 'check_foo.dart')` → `true`; `invokesGate('You should run
  scripts/check_x.dart by hand before releasing.\n', 'check_x.dart')` → `true`. Live exposure:
  `grep -n "run scripts/check" scripts/pre-commit.sh .github/workflows/test.yml scripts/commit-msg.sh`
  → all 6 hits are executed lines.
- **suggested-fix:** track heredoc state the way `extractCaseSkips` tracks case-block state and
  exclude bodies; require the line to look like an invocation (`"$DART_BIN" run` / `dart run` /
  a YAML `run:` step) rather than a bare substring match.
- **status:** accepted — fixed in `e993a345`. Coordinator reproduced both probes RED-first as
  tests, then tightened `invokesGate` exactly as suggested: invoker-prefixed match (`"$DART_BIN"`
  / `$DART_BIN` / `${DART_BIN}` / `dart` before `run scripts/<gate>`; a census of all 19 live
  invocation lines shows no other spelling, and Gate 33 still passes on the real tree) plus
  heredoc-body skipping with the opener line itself still counting (an invocation whose stdin is
  a heredoc is real). Tests 22 → 26 (two RED-first, two mirrors). Mutations: invoker prefix →
  bare `contains` reddens exactly the prose test; heredoc tracking dropped reddens exactly the
  heredoc test. Recorded in `b3e7a1`'s mutation ledger; closure entry BP-1.

## Finding 2 — P3 — L25 (intra/cross-document drift)
- **file:line:** `CLAUDE.md:1000`; `docs/audit/open_issues.md:3655`;
  `docs/audit/gate-integrity.closure.yaml:105-106` (U4)
- **claim:** all three cite commit `0768a0ce`'s date as 2026-09-18 in one identical sentence;
  the commit is 2026-09-19. The correct date already appeared in the same batch in diagnose
  `b7e2d4` (twice), the OI-222 board entry and the OI-181 fix commit's own message — one wrong
  draft sentence was pasted into three authoritative documents without re-deriving the date.
- **verification:** `git show -s --format=%ad 0768a0ce` → `2026-09-19` (00:34 +0530).
- **suggested-fix:** change `2026-09-18` → `2026-09-19` in the three locations.
- **status:** accepted — fixed in `e993a345` in all three plus the spec and plan (found by
  widening to `git grep 0768a0ce | grep 09-18` → 0 afterwards; the closure YAML's instance was
  line-wrapped and invisible to the reviewer's adjacency grep, which is why the sweep was
  widened). Closure entry BP-2.

## Lenses returning clean (reviewer's commands, condensed)

1. **writer_reader_drift** — zero `lib/` files in `git diff --name-only 8ffe28fb..a566f94c`;
   diff grep for `.put(`, `.box`, `.from(...).insert/update` → 0.
2. **function_exception_swallow** — `git diff 8ffe28fb..a566f94c | grep -c "\.functions\.invoke("` → 0.
3. **blast_radius_mismatch** — tier re-derived `platform` via the classifier (bare `-`); the six
   new `docs/blast_radius.yaml` pins diff-counted and each targets a load-bearing file
   (`oi_closure_lib.dart` really imports `check_closes_oi_cited.dart`'s `parseBoardStatuses`).
4. **secrets_in_tree** — `grep -icE "sk-|rzp_live_|AKIA|-----BEGIN"` over the diff → 0.
5. **unawaited_no_error_sink** — `grep -c "unawaited("` over the diff → 0.
6. **guard_without_its_mirror** — Finding 1. Mirrors that HELD: Gate 33 `manual:` → CLOSED OI
   and → nonexistent OI both FAIL exit 1 (and print the failure under `--warn-only` while exiting
   0); only ONE test executes the real `pre-push.sh` (`grep -rn "pre-push.sh" test/` → 6
   source-grep hits, one `exec sh scripts/pre-push.sh`) and it carries `CONTRACT_SWEEP_SKIP=1`
   in both its `runHook()` and its feature-tier scratch-repo scenario.
7. **missing_input** — every diagnose-doc / `test_path:` / allowlist citation names a file present
   in the batch or repo; `validate_diagnose_doc.dart` PASS ×3; `existsSync` on every cited path.
8. **asserted_fixture_value** — all four new fixture-heavy test files build isolated temp repos /
   registries per test (no shared quota-bearing state); every "stays silent" test is paired with a
   positive "warns" test.
- **L24** — Finding 1 is the one gap; the sweep's `--warn-only || true` is a disclosed §4.11
  baseline with the flip criterion on OI-220.
- **L37** — `contract_sweep_lib` distinguishes grep exit 1 (empty) from exit ≥ 2 (`null` →
  fallback), reproduced via mutation; Gate 42's `typeSync` accepts a real directory citation with
  a trailing slash on Windows; Gate 33's `boardStatuses` distinguishes unreadable / absent /
  CLOSED / OPEN-or-IN_PROGRESS (two states re-verified by mutation); CRLF handled (Gate 42
  normalises `\r\n`, the sweep trims every git line, the classifier token round-trips through
  the shell `case`).
- **L52** — `contract_sweep.dart` deliberately not a `check_*` gate; wiring pinned by
  `contract_sweep_wired_test.dart` (source order) AND `pre_push_analyze_always_e2e_test.dart`
  (behavioural, 3/3 in ~5 s — the recursion guard holds live on Windows). Gate 33 live PASS:
  97 `check_*` / 11 `validate_*`+`audit_*`, matching `ls`.
- **L25** — Finding 2 is the one hit. Re-derived and matching: 97 `check_*`; pre-commit case-skips
  13 and test.yml 11 (via the REAL `extractCaseSkips`); `presence_only: true` = 17; Gate 42's live
  PASS line matches CLAUDE.md verbatim; `safe_merge_test.dart` = 15; the OI-220 commit's "53
  files" reconciles with the current 55 (two added by later commits in the batch); 9 of the 13
  `compass_redesign_test.dart` line citations in the new playbook section spot-checked, all exact.
- **L20** — `validate_diagnose_doc.dart` PASS on all three docs; every `fix(` commit carries a
  matching `closes-diagnose:`; the `feat(` commit correctly has none; `b3e7a1.md` created in the
  SAME commit as its fix.
- **L8** — every new/modified test file run directly: 10/10, 1/1, hermetic (extended) green,
  3/3, 32/32 (Gate 33 runners + Gate 42), 17/17, 15/15; full pre-commit loop green.
- **L54** — `check_context_artifact_budget.dart` → `PASS: 3 within band, 0 warned, 0 skipped`.

## Founder triage notes

Both findings accepted and fixed in-branch (`e993a345`); 0 false_alarm. Nothing spawned.
