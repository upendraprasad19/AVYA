---
reviewed_at: 2026-08-10T14:20:00+05:30
staged_against: main...gate-registry (ed164459 + 023dfa12 + e23ca86c)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [parser_correctness, gate_false_pass, gate_false_fail_wedge, renumbering_completeness, grandfather_list_exactness, internal_consistency, secrets_in_tree]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — gate-registry (platform)

Self-initiated before the `--no-ff` merge per §4.3 — not on request. Required at ≥platform
(`check_plan_review_record_exists.dart:14-19` makes `bpass: accepted` unconditional at that tier).

Reviewed the whole branch diff (66 files, +2251/-14) rather than a single staged commit, because the
batch ships as three sequenced commits (§4.11) and no one of them is independently meaningful.

**No P0. No P1.** Both findings are P2 documentation-quality bugs. Both were independently verified
by the main thread against source before acceptance (`feedback_audit_verifier_cannot_trust_own_subagent`)
and both are **fixed in this batch**, not carried (§4.2).

## Finding 1 — P2 — parser_correctness — FIXED

- **file:line:** `scripts/gate_index_lib.dart:147-180` (`extractPurpose`)
- **claim:** A header whose first substantive line is consumed entirely by `_purposeStrip` except
  for trailing punctuation — e.g. `// Gate (Track 2 of the six-industry-gap closure batch).` —
  yields `piece == "."`. The loop only rejected an EMPTY piece, so `"."` was accepted as the
  purpose; the blank comment line immediately after then ended the loop, so the real description one
  paragraph down never surfaced.
- **verification:** `grep -nE '\| \. \|' docs/audit/GATE_INDEX.md` returned **2 of 87 rows** —
  `check_blast_radius_coverage.dart` and `check_code_review_pass_exists.dart` — both of which have
  real one-line summaries two lines further down. Confirmed against
  `scripts/check_blast_radius_coverage.dart:1-6` directly.
- **fix:** reject a piece with no word character (`RegExp(r'[A-Za-z0-9]')`) rather than merely an
  empty one, so the loop advances to the real description.
- **regression test:** `test/scripts/gate_index_lib_test.dart` — "a line consumed to bare punctuation
  does NOT become the purpose", built from the verbatim `check_blast_radius_coverage.dart` header.
- **mutation proof:** reverting the guard to the original `piece.isEmpty` check → **1 test red**.
- **verified after fix:** `grep -cE '\| \. \|' docs/audit/GATE_INDEX.md` → **0**.
- **status:** fixed

## Finding 2 — P2 — internal_consistency — FIXED

- **file:line:** `docs/audit/gate_test_ledger.yaml:8`
- **claim:** The header comment read `Enforced by scripts/check_gate_test_ledger.dart (Gate 55)`.
  That script carries no `// Gate: N` — correctly, per the forward-minting rule this very batch
  introduces. "55" was just `nextFreeNumber()` at authoring time. The prose contradicted the rule
  its own commit establishes.
- **why it is more than cosmetic:** the string is in the exact `scripts/xxx.dart (Gate N)` shape
  `_mintForward` (`gate_index_lib.dart:232-233`) looks for. It is inert today only because
  `build_gate_index.dart`'s `isLedger` predicate matches `*_closures.yaml` / `*.closure.yaml` /
  `closed_issues.md` and not this filename — so it is a landmine if that glob is ever widened.
- **fix:** replaced with an explicit statement that the gate carries NO number and why.
- **verified after fix:** `grep -c 'Gate 55' docs/audit/gate_test_ledger.yaml` → **0**.
- **status:** fixed

## Lenses that returned clean, and what was checked

- **gate_false_pass.** The supersede rule was attacked directly: a ledger mint is dropped only when
  *the same script* already declares a *different* number, so it cannot suppress a claim belonging to
  another script and structurally cannot hide a two-script collision. Pinned by the e2e test
  "supersession does NOT hide a collision between two declarations". Live run against the real tree:
  `PASS — 87 gates, 49 numbered, no collisions`, byte-identical to the committed index.
- **gate_false_fail_wedge.** The `pre-commit.sh` regen regex was checked against 15 representative
  paths including `.bak` variants, a nested-subdir ledger, and the generated index itself — matches
  the intended set, no self-trigger loop. The freshness gate ran clean and left no dirty tree.
- **renumbering_completeness, both directions.** All 6 live citations of an old number were updated
  (`build-apk.md` 23→53, `debugging/SKILL.md` 19→52, `writer-reader-drift-detector/SKILL.md` 7→49,
  `DEVICE_TESTING.md` 44→54, `common-pitfalls.md` 23→53). Reverse direction confirmed: citations of
  the scripts that KEPT 18 and 44 were left unedited, and the historical corpus is untouched.
- **grandfather_list_exactness.** The 84 literal names were extracted and `diff`ed against
  `ls scripts/check_*.dart` minus the 2 new gates — identical.
- **secrets_in_tree.** No credential-shaped literals; the only `key`/`secret`/`token` hits are gate
  filenames.

## Founder triage notes

Both findings accepted and fixed in-batch with a regression test and a mutation proof for finding 1.
Nothing carried forward. Verdict flipped to `accepted` on that basis.

One correction to the reviewer, recorded because a review's own errors belong in the record: it
reported `gate_test_ledger_lib_test.dart` as 24 tests; the file has **20**. Immaterial to every
finding, but the figure is not reproducible as stated.
