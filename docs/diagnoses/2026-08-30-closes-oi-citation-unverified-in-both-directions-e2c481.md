---
bug_id: e2c481
date: 2026-08-30
batch: oi-citation-mirror-gate
status: fixed
blast_radius: feature
symptom: >-
  Two OIs a commit declared closed via `closes-oi:` were NOT closed on the
  board. OI-150 (commit `c2534257`): the fix shipped, merged, went 7/7 CI
  green; the board write was simply never done, and an agent then asserted
  "OI-150 closed" in a compaction summary on the strength of the merge alone.
  Founder caught it, 0 automation did. OI-58 (commit `bd91c6eb`): real,
  verified, tested work DID ship (the single-parent bypass half, matching the
  code's own "OI-58a" label), but the citation named the two-part PARENT
  ticket while only one part closed, and the board's prose kept describing
  both halves as unaddressed for 33 days. Measured across all history: of 65
  OIs some commit declared closed, these 2 disagreed with the board.
concept: closes_oi_citation_unverified
sot_registry_entry: not_applicable
writers:
  - "scripts/check_closes_oi_cited.dart (pre-existing) — enforces ONLY
     status-change => citation. Opens with `if (nothing staged for the board)
     exit(0)` (:132-134), so a commit that cites a close and touches no board
     file is invisible to it. This is the WRITER of the one-directional
     contract; the citation => status-change direction had no writer at all."
  - "commit c2534257 — wrote `closes-oi: OI-150` in its body without writing
     the corresponding docs/audit/open_issues.md status change."
  - "commit bd91c6eb — wrote `closes-oi: OI-58` while its own body correctly
     scoped the work to the single-parent half only ('OI-58b … remains OPEN
     and is not claimed here'), an intentional under-scoping the trailer did
     not reflect."
readers:
  - "docs/audit/open_issues.md / closed_issues.md — the board a human or a
     future session reads to answer 'is OI-NN done'. Both entries disagreed
     with what their citing commits claimed."
  - "docs/audit/gate-input-family.closure.yaml's OI-58a entry — a SEPARATE
     per-batch ledger with the identical staleness: `terminal_state:
     upstream_blocked` for 34 days while the file's own header comment, two
     lines above the entry, already said 'closed in code'. Same defect class
     in a second document."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/oi_closure_lib_test.dart, test/scripts/closes_oi_performed_e2e_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Confirmed OI-58b (the genuinely still-open subject-spoof half) was NOT
  touched by the OI-58 correction: `grep -A 15 "id: OI-58b"
  gate-input-family.closure.yaml` still reads `terminal_state:
  upstream_blocked` after the edit, and its board prose in open_issues.md
  still describes it as the residual. Confirmed the single-parent fix is
  real and live, not merely claimed: the 8-test group `OI-58a — direct-to-main
  landings are judged` in test/scripts/gate_input_family_e2e_test.dart passes
  8/8 against the real gate as a subprocess (re-run 2026-08-30, not re-read).
proposed_fix: >-
  New merge-commit gate check_closes_oi_performed.dart, the MIRROR of
  check_closes_oi_cited.dart: for every `closes-oi: OI-NN` across the commits
  a merge brings in (HEAD^1..HEAD^2), OI-NN must read CLOSED on the board AT
  THAT MERGE COMMIT. Placed at the merge (not commit-msg, where its sibling
  lives) because a batch legitimately fixes in one commit and closes the
  board in the next, and only the merge sees the branch whole — same
  reasoning check_plan_review_record_exists.dart already records for its own
  placement. Two failure kinds kept SEPARATE rather than collapsed: a cited
  OI still reading non-CLOSED BLOCKS (the OI-150 shape); a cited OI on
  NEITHER board WARNS only (dangling citation from a renumber or typo — this
  repo's OI numbers have been renumbered on a branch six times, so blocking
  on that would create a false-positive class that trains bypasses). Fails
  open with an explicit SKIPPED line (never a silent PASS) whenever git
  cannot answer, and pins stdoutEncoding/stderrEncoding: utf8 on every git
  read — check_oi_numbering_unique.dart's first live run reported PASS
  against an EMPTY board because the default systemEncoding mangled every
  em-dash heading, and this gate's board headers use the identical character.
  Separately, corrected the two stale artifacts this citation gap left
  behind: gate-input-family.closure.yaml's OI-58a terminal_state
  (upstream_blocked -> closed_in_commit, with commit: + verification: per
  Gate 40's schema) and open_issues.md's OI-58 prose (title + "What's
  missing" narrowed to the genuinely-open residual). OI-150's board close
  itself was already done in a prior commit this session (a6a0ae0a) before
  this gap was understood to be systemic; this batch is the gate that stops
  the NEXT instance, plus the OI-58 half this session had not yet corrected.
regression_test_planned: >-
  test/scripts/oi_closure_lib_test.dart (14 tests) — the pure predicate:
  citation extraction across multiple messages, board-merge with OPEN winning
  on conflict, and the two-kind verdict (unperformed vs unknown) including the
  exact OI-150 shape as a named case.
  test/scripts/closes_oi_performed_e2e_test.dart (6 tests) — real git repos,
  real merge commits, the real gate script as a subprocess: reproduces the
  shipped OI-150 bug exactly and asserts FAIL; asserts PASS when a citation
  is genuinely satisfied; asserts the dangling-citation case WARNS not BLOCKS;
  asserts silent (not merely exit-0) skip on a non-merge HEAD; asserts the
  board is read AT THE MERGE, not from an uncommitted working-tree edit —
  the exact defect class the B-pass found in this same batch's earlier
  safe_merge.sh precheck.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "20/20 green (counted from the test files, not recalled: `grep -c '  test(' <file>` gives 14 in oi_closure_lib_test.dart + 6 in closes_oi_performed_e2e_test.dart = 20, matching the actual `flutter test` run's own +20 tally). Board-tooling only, ships in no APK." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Contract is the PreToolUse/merge-commit wire behaviour, verified by spawning the real gate against real merge commits. MUTATION-PROVEN on THREE protective legs, each applied-check confirmed by grep before running, each restored and diffed byte-identical against a pre-mutation backup afterward. Leg 1 (core predicate, status != 'CLOSED' -> false): reddens 7. Leg 2 (merge-detection guard, parents.length < 2 -> false): FIRST ATTEMPT ABSORBED -- all 6 e2e stayed green because HEAD^2 cannot resolve off any single-parent HEAD regardless of the guard, so a pre-existing _skip() path caught it with the same exit code for an unrelated reason; confirmed absorbed by manually neutering and running before trusting the green. Fixed by asserting on OUTPUT (the real guard is silent; the absorbed path prints SKIPPED), which then reddens 1. Leg 3 (read-at-HEAD, git show HEAD:<path> -> a working-tree File read): reddens the test built specifically for it -- an uncommitted board edit must not satisfy a gate judging a commit, the same defect class the B-pass found in this batch's own safe_merge.sh precheck earlier." }
mutation_evidence: >-
  See touched_layers_checked tier 12 for the full account. Summary: 3
  protective legs, 1 genuinely absorbed on first attempt and caught before
  being trusted (not silently accepted), all 3 confirmed red after fixing,
  all restored byte-identical (`diff` against backup) before the real suite
  was re-run to 20/20 green.
impact_analysis: >-
  No user-facing impact — board/process tooling, ships in no APK. Cost is to
  future sessions and the founder: a citation that goes unchecked in one
  direction reads as done when it is not (OI-150 cost a founder catch and a
  correction cycle) or reads as a scope match when it is a partial fix (OI-58
  cost 33 days of a board describing a bug half that no longer existed,
  meaning anyone reading it before re-verifying would have over-scoped the
  next attempt). The new gate is a genuine backstop going forward; the two
  corrections here are one-time repairs for damage the gap already did.
related_bugs:
  - "OI-150 (this session, diagnose 321062) — the citation half of the same
     defect this gate closes, discovered when founder asked directly why the
     board still read OPEN after the fix's own compaction summary claimed
     closed."
  - "OI-58a / d9b4e7 (2026-07-28) — the real fix whose citation triggered this
     investigation; not a bug in itself, but the source of the over-broad
     `closes-oi: OI-58` citation this doc corrects."
recurrence: >-
  Direct continuation of the OI-150 correction earlier this session
  (feedback_mistake_unverified_done_claims.md gained an entry there: an
  agent's own compaction summary asserted a close that was never performed).
  That correction fixed ONE instance; this gate is the class-level fix. The
  OI-58 finding, surfaced while building this gate's rationale, is a
  DIFFERENT failure mode of the identical unchecked citation (over-broad
  scope rather than zero work) — recorded here rather than treated as
  unrelated, because both trace to the same missing enforcement direction.
---

# e2c481 — a `closes-oi:` citation was never checked against what actually happened

## What shipped

1. `scripts/oi_closure_lib.dart` + `scripts/check_closes_oi_performed.dart` —
   the mirror gate. `check_closes_oi_cited.dart` enforces status-change =>
   citation; this enforces citation => status-change.
2. `docs/audit/gate-input-family.closure.yaml` — OI-58a's `terminal_state`
   corrected from a 34-day-stale `upstream_blocked` to `closed_in_commit`,
   with the commit SHA and re-verified test evidence.
3. `docs/audit/open_issues.md` — OI-58's title and "What's missing" prose
   corrected to describe only the genuinely open subject-spoof residual,
   with a dated correction note explaining what changed and why, in the same
   style as the existing OI-118 precedent in `closed_issues.md`.
4. `docs/audit/gate_test_ledger.yaml` — the new gate's mutation-proven entry.

## The two failure shapes, kept distinct on purpose

**OI-150 — cited, zero work performed.** The board simply never got the
write. Unambiguous: `unsatisfiedCitations` returns it as `unperformed`, the
gate FAILS, full stop.

**OI-58 — cited, real work performed, wrong scope.** `bd91c6eb`'s own commit
body was precise about what it did and did not close ("OI-58b … remains OPEN
and is not claimed here"), but its trailer cited the parent ticket that
bundles both halves. The board's OI-58 entry was — and, correctly, still is —
OPEN, because the ticket as defined covers two things and only one is done.
The new gate would flag this too, and that is the right call: the fix is not
"trust the commit body's nuance", it is "cite the entry you actually closed".
Had OI-58a existed as its own `## OI-58a` heading in `open_issues.md` (the
way it already does in the batch-scoped closure ledger), the citation would
have been exact and satisfied. It did not, so the gate is correctly
conservative here — which is a property worth stating rather than assuming:
a citation against a bundled ticket should wait for the whole bundle.

## Why the merge-commit placement, not commit-msg

The sibling gate lives at commit-msg because `git commit` is the moment a
message exists to check. This one cannot live there: §4.3 explicitly
recommends batching commits and pushing once, so a fix commit citing a close
and a follow-up commit performing the board write is the SUPPORTED shape, not
a violation. Checking at commit-msg would reject that shape outright. The
merge is the first point where the whole branch is visible at once — the same
reasoning `check_plan_review_record_exists.dart` already documents for
itself, and CLAUDE.md §4.12.3 names as "the only structurally-gateable
point".
