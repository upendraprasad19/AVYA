---
reviewed_at: 2026-08-09T09:40:00+05:30
staged_against: d4a8de00
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, gate_self_defeat, migration_safety, edge_function, internal_consistency]
findings_count: 7
verdict: accepted
---

# Code Review (B-pass) — d4a8de00

Self-initiated per §4.3 (platform tier, before the merge). Reviewer had no
conversation context and was instructed to find bugs, not validate. It found
seven, including one P1 that would have shipped a false claim about a P0.

All seven are resolved below. Four are fixed in code; three are corrected in
docs. Nothing is carried forward unaddressed.

## Finding 1 — P1 — internal_consistency — **ACCEPTED, FIXED**

14 entries carried `terminal_state: closed_in_commit` + `commit: *slice0` for
fixes that exist only as uncommitted working-tree edits. The starkest:
**R1-P0-1**, a P0 auth defect, whose own `notes:` said "the code carrying this
fix ships in slice 2" while its terminal_state claimed slice 0. A reader
trusting the ledger would have believed a P0 was safe in git history when it
existed nowhere but one machine's working tree.

**Fix:** all 14 reclassified to `blocked_on_user` + `reason: *sN` + an explicit
`fix_state: "written, NOT yet in any commit"`. The ledger header now states the
rule outright: *`closed_in_commit` means the fix is in a commit that exists; if
you cannot name the commit that carries it, it is not closed.*
Counts after: 7 `closed_in_commit`, 28 `blocked_on_user`, 35 total.
- **verification:** `grep -c 'terminal_state: closed_in_commit' docs/audit/post38-auth-fixes.closure.yaml` → 7

## Finding 2 — P2 — gate_self_defeat — **ACCEPTED, FIXED**

`prose` was never added to `failures`, in `--strict` too — so a doc could evade
the resolve-check permanently by writing `sot_registry_entry: some new concept`
(spaces instead of underscores). The gate's entire purpose was opt-out.

**Fix:** a POST-cutoff doc whose citation is prose is now a **violation**.
Pre-cutoff prose stays a WARN (grandfathered).
- **verification:** `flutter test test/contracts/sot_registry_citations_test.dart --plain-name "hides behind PROSE"`

## Finding 3 — P2 — gate_self_defeat — **ACCEPTED, FIXED**

The contract test imported only the pure lib and never executed the gate's
`main()`. Replacing `failures` with `<String>[]` — a total neutering — left the
whole suite green. Presence-only confidence, in the test of the gate built to
stop presence-only confidence.

**Fix:** 7 new subprocess cases that run the real gate in a throwaway git repo
(with `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE` scrubbed, per the known
hook-env-leak trap) and assert exit codes. **Mutation-proven:** the exact
neutering the reviewer described now turns 3 cases red.
- **verification:** apply the mutation, `flutter test test/contracts/sot_registry_citations_test.dart` → 3 failures

## Finding 4 — P2 — internal_consistency — **ACCEPTED, FIXED**

`origin/main` advanced to `c90fc4c0` mid-review and independently created its
own `## OI-99`. R2-N15's claim to have closed the numbering collision was stale
within hours — the same bug-class, recurring live, for the second time in a day.

**Fix:** mine renumbered OI-99 → **OI-111** (109/110 verified free). Overlap
with origin/main now stops at OI-98. The structural gap is filed as **OI-112**
rather than patched again by hand.
- **verification:** `comm -12 <(git show origin/main:docs/audit/open_issues.md | grep -oE '^## OI-[0-9]+' | sort -u) <(grep -oE '^## OI-[0-9]+' docs/audit/open_issues.md | sort -u) | tail -1` → `## OI-98`

## Finding 5 — P3 — gate_self_defeat — **ACCEPTED, FIXED**

A missing registry exited 0 ("SKIP", fail OPEN) while a registry parsing to zero
concepts exited 1 (fail closed) — two states that both mean "citations cannot be
verified", handled opposite ways. A rename would have silently disabled the gate.

**Fix:** missing registry now exits 1 with a message saying so.
- **verification:** `--plain-name "FAIL CLOSED"` case in the contract test

## Finding 6 — P3 — gate_self_defeat — **ACCEPTED, PARTIALLY FIXED, LIMIT STATED**

The cutoff read only the filename, so a new doc could exempt itself by being
NAMED with a pre-cutoff date.

**Fix:** the cutoff is now the LATER of the filename date and the doc's `date:`
frontmatter, so both must be backdated and the disagreement is visible in review.
**Stated limit, not papered over:** an author controlling both fields can still
opt out. This is a grandfathering mechanism, not a security boundary — that
sentence is now in the function's own doc comment. The reviewer's second half
(pre-commit never passes `--strict`) is accurate and intended: `--strict` is for
clearing the OI-110 backlog, not for daily commits.
- **verification:** `--plain-name "backdating the FILENAME"` case

## Finding 7 — P3 — internal_consistency — **ACCEPTED, CORRECTED HERE**

The `d4a8de00` commit message says "34 findings"; the ledger says 35. The count
moved after the message was written. The commit is already made and its message
cannot be corrected without a history rewrite, so the correction lives here and
in the follow-up commit. **35 is the correct number** at d4a8de00; it is 42
after this review's own findings are entered.

## Lenses returning CLEAN

`migration_safety` (policy `auth.uid() = user_id` untouched by 119; NULL
correctly rejected for authenticated writers; recorded sha256 matches the file),
`edge_function` (verify_jwt true live; allow-list-only op_type; no leak beyond
`ok`/`rate_limited`/`next_window_at`/`priority_lane`), `writer_reader_drift`
(`.is("user_id", null)` applied symmetrically to count and window queries),
`blast_radius_mismatch` (classifier returns `platform`, matching the claim),
`secrets_in_tree`, `function_exception_swallow`, `unawaited_no_error_sink`.

**Reviewer's one un-raised caveat, recorded rather than dropped:** the anon-lane
budget is a non-atomic count-then-insert, now reachable with the public anon key
— a soft rather than hard 200/day cap. It follows the codebase's pre-existing
pattern and is not a regression from this commit; filed as **OI-113**.

## Founder triage

Verdict `accepted`: every finding is fixed or explicitly bounded, and the two
that would have misled a reader (F1, F4) are corrected in the artifacts
themselves rather than only in prose.
