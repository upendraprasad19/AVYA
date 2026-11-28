---
reviewed_at: 2026-08-11T17:55:00+05:30
staged_against: memory-batch-archive
blast_radius: platform
reviewer: claude-opus-self-consistency
lens_set: [factual_accuracy, naming_ambiguity, internal_consistency, proportionality, prior_art]
findings_count: 3
verdict: accepted
---

# Review — memory-batch-archive (§5 checklist row)

**Docs/process-only change → §4.3 prescribes a self-consistency review of the wording rather
than an adversarial bug-hunt.** That is what this is; it is not a code B-pass and does not
claim to be. It found 3 defects, all in my own draft, all fixed before commit.

## Finding 1 — P1 — factual_accuracy — FIXED

- **claim:** the draft row asserted a batch was "still labelled IN-FLIGHT **weeks** after it
  merged."
- **verification:** `git log --merges --format="%h %ad %s" --date=short main | grep train-signout`
  → `be74bf63 2026-08-10`. The stale label was found 2026-08-11. **One day, not weeks.**
- **fix:** changed to "the day after it merged". A governing document asserting a false
  timeline is the failure mode `docs/audit/oi-mechanism.closure.yaml` names directly — *"a
  false claim inside it is worse than an absent one."*
- **status:** accepted

## Finding 2 — P1 — naming_ambiguity — FIXED

- **claim:** the draft said "MEMORY.md" unqualified. **Two files bear that name**, and the
  repo one exists *because* the ambiguity already caused harm: `memory/MEMORY.md` is a stub
  headed *"⚠️ NOT the live memory index"*, written after its mirror sat ~3 months stale
  (`oi-mechanism.closure.yaml` D4). An unqualified reference in §5 points a reader at the
  stub — and the new row's whole subject is where batch lines go.
- **verification:** `git ls-files memory/` → 6 tracked files incl. `memory/MEMORY.md`;
  `head -8 memory/MEMORY.md` → the NOT-the-live-index stub header.
- **fix:** row now names the harness path explicitly
  (`~/.claude/projects/<mangled>/memory/MEMORY.md`, matching `discipline_hook.dart:155`'s own
  `$mangled` resolution) and states that repo `memory/MEMORY.md` is a pointer stub.
- **status:** accepted

## Finding 3 — P2 — proportionality — FIXED (defect introduced by finding 2's fix)

- **claim:** after the finding-1 and finding-2 corrections the row was **12 lines** in a
  checklist whose other rows are 1 line each (the next longest, worktree retirement, is 3).
  A checklist whose rows are essays stops being scannable, which defeats the artifact.
- **verification:** measured every row in the §5 block — nine 1-line rows, one 3-line row,
  mine at 12.
- **fix:** compressed to 10 lines with the rationale moved to the consolidation retrospective;
  kept the three load-bearing parts (the rule, the harness/repo disambiguation, the
  no-detector warning). Still the longest row, but within range of the 3-line precedent
  rather than 4× it.
- **note:** this is the §4.12 mechanism working as documented — *"the corrections themselves
  can introduce new defects."* Round 1's fixes caused it.
- **status:** accepted

## Checks that returned clean

- **prior_art** — the row's central instruction ("no detector") is itself the finding of a
  prior attempt: `oi-mechanism.closure.yaml` D5 records a SessionStart digest + two gates
  built, ×2-reviewed, and **withdrawn wholesale**; scars at **OI-68** (`open_issues.md:1162`)
  and **OI-69** (open, "Nothing detects this backlog going stale AGAIN"). Both citations
  verified present. The row encodes that verdict rather than contradicting it.
- **internal_consistency** — Gate 18 (`check_doc_internal_consistency.dart`) PASS;
  `check_claude_md_citations.dart` exit 0 (the row cites §4.13 point 6, which exists);
  `check_no_deferral_euphemism.dart` PASS on the staged addition.
- **numeric claim "each of the last three passes archived 4"** — verified against all three
  retrospectives, not asserted: 08-03 *"3 merges + 4 batch archives"*, 08-08 *"Archived 4
  shipped batch entries"*, 08-11 *"Archived 4 SHIPPED batches"*. Exactly 4 each.
- **scope** — one checklist row changed; no other §5 row, no §4 invariant, no gate touched.
  `git diff --cached --stat` → `CLAUDE.md` only.
