---
branch: memory-index-nudge
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/memory-index-nudge-bpass.md
---

# Plan-review record — memory-index-nudge (§4.12)

Phase D of the 2026-07-04 memory-consolidation batch: wire a **MEMORY.md size nudge**
into `scripts/discipline_hook.dart` (SessionStart → suggest `/consolidate-memory` when the
per-session memory index exceeds its soft cap) + a root `CLAUDE.md` §7 doc-sync row.

**Blast radius = platform, driven SOLELY by the CLAUDE.md path** (the hook script alone
classifies `feature` — confirmed via `blast_radius_from_diff` on each file). Per CLAUDE.md
§4.3, a CLAUDE.md/docs-process change takes a **self-consistency review of the wording +
logic**, not an adversarial product bug-hunt. The keystone gate still requires this record,
so it is authored honestly rather than the doc-sync dropped to dodge the tier.

## Round 1 — context-blind exploration (the consolidation plan)
Two independent Explore agents mapped the memory dir (inventory, overlap clusters, wiki-link
graph, stale in-flight files) and every repo citation of memory filenames. Ground-truth
verified by me: I re-ran the citation grep and caught that **3 of 15 "safe to absorb" files
were actually cited by LIVE skills** (`e2e-sim-testing`, `debugging`) + dated records — the
first sweep missed them. Resolution: host-in-place / tombstone, never a dangling pointer.

## Round 2 — context-blind Plan-agent validation on the hardened merge map
A Plan agent read all 15 candidate files end-to-end and validated each merge (FIT/ADJUST/
REJECT), the merged frontmatter (recall-trigger preservation), the wiki-link rewrite table,
and the byte arithmetic. It surfaced the prior-CUT precedent (2026-06-27) which I surfaced to
the founder; the founder chose full-merge scope via AskUserQuestion. I verified every
load-bearing claim (the 3 cited files, the git topology, the blast-radius tiers) directly.
Convergence: no open issues; scope locked by founder.

## Implementation review — self-triggered self-consistency B-pass over the Phase D diff
`docs/reviews/memory-index-nudge-bpass.md` (verdict: accepted) — 5 lenses on the actual
diff: fail-silent contract, threshold De-Morgan correctness, path-mangling
robustness-by-degradation, matcher scope (no settings change), and CLAUDE.md wording
self-consistency. Evidence: `dart analyze` clean + an 8-scenario hook test matrix (over-cap
fires, under-cap/missing-file silent, all existing hot-set/skill/empty-stdin behaviors
intact). No material findings — the change is fail-silent, additive tooling + a doc row; no
product code / schema / EF / auth touched. Hermes not required (not catastrophic).

## Convergence
Phases A–C of the batch already landed in the memory dir + user-level `~/.claude` (13
overlapping files → 5 class/host files + 2 tombstones; MEMORY.md 20,202 → 17,502 B, −13.4 %,
under the soft cap; new `/consolidate-memory` skill + `MEMORY_ARCHIVED.md`). Verification:
16/16 union-completeness greps, 12/12 repo-intact (0 hits for deleted basenames), 0 dangling
wiki-links. Phase D is the sole repo change; committed feature-scoped code + this platform
doc-sync together. Converged.

> Founder-gated (per-action): the `--no-ff` merge to `main` (this "commit" go) lands it
> locally; **push is a separate go** (not taken here).
