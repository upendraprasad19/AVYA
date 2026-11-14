---
reviewed_at: 2026-07-07T20:10:00+05:30
staged_against: worktree-enforcement (commit 21617b1) vs main
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass)
lens_set: [gate_wedges_legit_commit, gate_false_passes_mixing, hook_breaks_session, helper_path_and_primary_detection, contract_test_soundness, doc_drift]
findings_count: 7
verdict: accepted
---

# Code Review (B-pass) — worktree-per-session enforcement (`worktree-enforcement`)

A fresh, context-blind Sonnet agent adversarially reviewed the committed change set (gate +
pure lib + SessionStart hook + `new-worktree.sh` helper + `.claude/settings.json` matcher change
+ CLAUDE.md §4.13/§7 + contract test). It was told to find bugs, not validate — with special
weight on a **commit-blocking gate** (a bug could wedge every commit or silently fail to prevent
the mixing it targets).

**Overall B-pass verdict: SHIP-WITH-FIXES. No P0.** The core is sound: primary-vs-linked
detection holds on this Windows/git-2.53 repo, the fail-open design never wedges a normal commit,
CI is exempt, staged deletions are detected, and the pure lib + 32-combo truth table are correct.
Findings: one P1 (a documented integration op the gate silently blocked) and several P2s. **All
material findings were verified by me against live git and folded in the same batch** (§4.2 — no
deferrals). Dispositions below.

## Findings + disposition

### P1-1 — cherry-pick / revert in the primary folder was BLOCKED — **FIXED**
`check_commit_from_worktree.dart`. The only integration exemption was `MERGE_HEAD`; `git
cherry-pick` / `git revert` create a *normal* commit (no `MERGE_HEAD`) → blocked in the primary,
yet the docs call the primary "integration-only". **Verified live:** the gate exempted only
`MERGE_HEAD` (line 67 pre-fix). **Fix folded:** the exemption now also checks `CHERRY_PICK_HEAD`
and `REVERT_HEAD` (each set by git *only* during an active cherry-pick/revert, so no
over-exemption outside one). Docs (§4.13, memory, diagnose) reworded "merges" → "integration ops
(merge/cherry-pick/revert)".

### P2-1 — `_worktreeWarning()` false-negative from a primary SUBDIRECTORY — **FIXED**
`discipline_hook.dart`. From e.g. `.../Fitness App/lib`, plain `--git-dir` is absolute but
`--git-common-dir` is relative `../.git`, so after `norm()` they differ → treated as a linked
worktree → warning suppressed in the shared primary. (The *gate* was immune — pre-commit cd's to
`--show-toplevel` first — only the advisory warning was affected.) **Verified live:** plain
`--git-common-dir` in `lib/` returns `../.git`; with `--path-format=absolute` both resolve to the
same `.git`. **Fix folded:** both the gate and the hook now resolve the two dirs with
`--path-format=absolute` (git 2.31+; empty → fail-open). **Re-verified live post-fix:** the hook
now emits the ⚠️ WORKTREE warning from the `lib/` subdirectory.

### P2-5 — a local `CI=true` silently exempted primary commits — **FIXED**
`worktree_guard_lib.dart` / gate. Some dev tools export `CI=true`, which exempted the guard.
**Fix folded:** the gate's CI exemption now checks `GITHUB_ACTIONS` only (real CI has no staged
diff anyway, so the no-staged exemption already covers a CI run).

### P2-4 / P2-6 — doc drift after the SessionStart matcher was broadened — **FIXED**
The hook file-header and the CLAUDE.md §7 row still said `SessionStart:compact`, and §4.13/memory/
diagnose still described only "merges" as exempt. **Fix folded:** header + §7 row now describe the
all-source SessionStart (compact re-inject + worktree warning + mem nudge, each self-guarded); the
exemption wording synced across §4.13, `feedback_worktree_per_session.md`, and diagnose `f0c2d5`.

### P2-2 — no `--warn-only` soak before hard-fail (§4.11) — **considered, N/A (documented)**
§4.11's warn-only-then-hard-fail exists to baseline *existing* violations of a heuristic gate
before it blocks. This gate is **deterministic** (git-fact truth table, not statistical) and there
is **no backlog of violations to grandfather** — it only affects future commits. The founder
explicitly chose the **hard block**, the one real edge a soak would have surfaced (P1-1) is fixed
directly, and the documented `ALLOW_MAIN_COMMIT=1` valve covers any residual false-positive without
wedging. So the soak is genuinely not applicable here — the gate ships fully enabled. This is a
terminal decision, not a deferral.

### P2-3 — the gate's recovery hint is shown only on a re-run — **considered, accepted (documented)**
`pre-commit.sh` runs every gate as `dart run "$GATE" >/dev/null 2>&1` and prints "re-run for
details" on failure — the **uniform** pattern for all ~72 gates. For this workflow gate the recovery
guidance is *also* delivered proactively (the SessionStart ⚠️ WORKTREE warning fires at session
start in the primary; CLAUDE.md §4.13 documents the flow), and on the block the "re-run for details"
line surfaces the full `_fixHint` (worktree steps + `ALLOW_MAIN_COMMIT=1`). Special-casing the
parallel gate loop would risk Gate 33 (loop-structure check) for a P2 UX nicety, so the uniform
pattern + the proactive warning are kept. Accepted as-is.

## Post-fix verification
- `dart analyze` on gate + lib + hook → **No issues found**.
- `test/contracts/check_commit_from_worktree_test.dart` → **10/10 green** (the pure lib is unchanged;
  only the gate's git-fact-gathering and the hook changed).
- Live: gate PASSES from the linked worktree; the SessionStart warning is silent in the worktree,
  fires in the primary root **and** (post-fix) from a primary subdirectory.

**Verdict: accepted** — no P0; the one P1 and the actionable P2s are fixed and re-verified in this
batch; the two non-code P2s (soak, hint-visibility) are dispositioned with recorded reasons.
