---
reviewed_at: 2026-09-18
staged_against: 84987ddb..e8c45e11 (branch discipline-v2 — S/M/L tiering batch)
blast_radius: platform
reviewer: fresh context-blind subagent (B-pass)
record: docs/plan-reviews/discipline-v2.md
---

# B-pass — discipline-v2 (S/M/L tiering)

Verdict: accepted
0 P0 · 0 P1 · 6 P2 — every finding closed in-batch (commit `7de94167`).

## Findings (all verified by the reviewer, all fixed)

1. **Platform-pin the telemetry scripts** — `batch_process_telemetry{,_lib}.dart` fell
   through the `scripts/**` feature catch-all while being part of the Stop hook's output
   contract (the 4th documented "hook pinned, dependencies not" instance). Fixed: both
   pinned `platform` in `docs/blast_radius.yaml`.
2. **Escape-ledger regex unanchored to the key** — any line ending `status: open` (e.g.
   `open_status: open`) counted as an open escape. Fixed: `^\s*status:\s*open\s*$`;
   mutation-proven (removing the anchor reddens exactly the new negative test).
3. **`top_gate=none` beside an unknown count** — with an unparseable/absent log the count
   renders `unknown` while `none` claimed no-news. Fixed: `top_gate=unknown` when
   `gateFailures7d == null`; e2e pins it.
4. **`.gate_failures.log` append-only growth** — accepted as known (one ~40B line per
   failure and a failure aborts the commit; per-worktree copies die at retirement).
   Documented at `scripts/pre-commit.sh:384-385`.
5. **OI-214 numbering gap** — confirmed NOT an orphan: `origin/oi/214` is a live
   reservation from a concurrent session.
6. **`_recentCount` counted all files, not `.md`** — editor temp/lock files could inflate
   `review_files_7d`. Fixed: `.endsWith('.md')` filter.

## Clean (verified, not re-validated)

Full suite hazards (per-test timeout overrides, teardown throws), hook mutation-leg
reachability, `_git` twin parity (`systemEncoding` both files), per-worktree log resolution
(writer `--show-toplevel` / reader same), escape-hatch inventory (only the two sanctioned
silent-degrades), sweep-tolerance spot-checks on the two most load-bearing sites.
