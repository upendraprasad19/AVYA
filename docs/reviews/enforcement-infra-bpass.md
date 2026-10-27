---
reviewed_at: 2026-07-29
branch: enforcement-infra
reviewed_range: main...HEAD (3ae41073, defd0ae7, e4bc9040)
blast_radius: platform
reviewer: fresh context-blind sonnet subagent (/code-review B-pass)
lens_set: [fail_open_paths, gate_soundness, content_integrity, claim_accuracy, gate_wiring, ci_semantics]
findings_count: 8
verdict: accepted
---

# B-pass — enforcement-infra

**3 P1, 3 P2, 2 P3. All six actionable findings fixed.** Every claim was
re-derived against the files before being acted on, per
`feedback_audit_verifier_cannot_trust_own_subagent`.

This pass earned its place on one finding alone.

## P1 — I rebuilt a failure the board itself warned about, in the file I was splitting

`open_issues.md` **OI-68** is a postmortem of two prior, withdrawn attempts at
this exact backlog mechanism. It carries a section headed **"SCARS — read before
re-attempting"**, whose third entry reads verbatim:

> the format gate validated shape but not vocabulary … `PENDING`, `BLOCKED`,
> `REOPENED` and a one-character `IN-PROGRESS` typo all passed the gate and
> vanished from the digest

`build_oi_index.dart` shipped `if (!status.toUpperCase().startsWith('OPEN'))
continue;` — the same bug, third generation. An entry with `- **Status**:
BLOCKED` would be silently absent from `OPEN_INDEX.md` while the generator
exited 0 and the backlog looked complete. The self-check could not catch it: it
only validated entries already collected, and a dropped entry never enters the
list.

This is the **second §4.1.5 miss of this batch**, in the same file as the first
(OI-58's recorded fix shape). The warning was addressed to precisely this
situation and I did not read it.

Fixed: `unrecognisedStatuses()` classifies **every** `## OI-NN` header before
anything renders, and unknown vocabulary is a hard `exit(1)` naming the issue
and line. Verified — injecting `BLOCKED` now fails with
`OI-25 (line 78): unknown status "BLOCKED" (known: OPEN, IN_PROGRESS, CLOSED)`.
Controls for all four words OI-68 names.

## P1 — a formatting slip disabled the `closes-oi` gate silently

`_statusRe` requires the literal `- **Status**:`. Writing `- **Status:**
CLOSED` (colon inside the bold) made `parseBoardStatuses` omit the section
entirely, so `newlyClosed` never visited it, no citation was demanded, and
**nothing was printed** — the gate turned itself off for that issue.

Fixed: `unreadableStatuses()` reports any section whose status line cannot be
read, and the gate exits 1 naming it. Silence is no longer a pass.

## P1 — the new generated index was missing from the exemption added in this same batch

`pre-commit.sh:71` regenerates and stages `OPEN_INDEX.md` **before** Gate-DEU
runs at `:139`, so the whole file re-renders as "added" lines. `OPEN_INDEX.md`
was absent from `_isGeneratedMirror` — the very list added in `3ae41073` to fix
this exact class for four other files. Any future commit touching the board
could have hard-failed on a phrase in an untouched entry's `Blocked on` prose.
Fixed: added to the list.

## P2 — three parser holes

- **An unindented `---` inside a folded scalar truncated the frontmatter**, so
  every field after it (`concept`, `contract_test_path`, `recurrence`) vanished
  while `symptom` still looked fine and the self-check stayed quiet. The closing
  delimiter is now found by scanning lines for one that is exactly `---` and not
  indented, instead of a lazy `.*?` regex.
- **`|2` / `>2` indentation indicators** parsed as the literal string `"|2"`,
  which the self-check accepted (neither empty nor a *bare* indicator).
  `blockScalarRe` now covers the digit forms.
- **The two sibling parsers disagreed on bolded values.**
  `check_closes_oi_cited.dart` stripped `**`; `build_oi_index.dart` did not, so
  `- **Status**: **OPEN**` vanished from the index while parsing fine for the
  other gate. Now shared.

## P3 — accepted as-is

- OI-72 lost one trailing blank line in the split (whitespace only; it is now
  physically last in `closed_issues.md`). Confirmed by the reviewer's exhaustive
  section-by-section diff — 46/47 closed sections byte-identical.
- `closes-oi` can be laundered by deleting an OPEN section and re-adding it
  under a fresh number in one commit. Deliberate-only, conspicuous in a diff,
  and closing it is materially larger than this gate's scope. Recorded, not hidden.

## Claims of mine that were WRONG

| I wrote | Actual |
|---|---|
| "345 entries" indexed | **346** |
| `t1m5b0`/`s1n4c0`/`w7r4c3` in "10 commit messages" | **3 commits** (one of them this branch's own) |
| slug ids "in 3 more" commits | **1** (`818ba30e`) |
| `Verified: 2026-07-26` on "the 8 audited" | **6** entries |

None changes a decision — the don't-rename conclusion still holds, since 15
source/test files reference those ids — but all four were stated as measured
when they were not.

## Lenses that returned clean, with evidence

- **Content integrity of the split** — exhaustive, not sampled: all 73 sections
  extracted from `e4bc9040^` and diffed against their post-split counterparts.
  46/47 closed byte-identical, all 26 open gained (never lost) fields, no
  section duplicated, stranded or orphaned.
- **Generator stability** — both `build_bug_index.dart` and `build_oi_index.dart`
  produce an empty `git diff` on re-run. An unstable generator shifts the
  staged-diff hash other gates key on (`f4d1b7`).
- **CI retry-loop `set -e` semantics** — `[ "$i" = 3 ] && break` is exempt from
  `errexit` (it is the first command in an `&&` list), so the loop can only reach
  `exit 1` after three genuine failures. It neither masks a failure nor exits 0
  wrongly.
- **`setup-hooks.sh`** — `--git-common-dir` resolves correctly from both the
  primary and a linked worktree; nothing newly installed that a clean clone lacks.
- **Gate wiring** — Gate 33 PASS (91 scripts); `check_closes_oi_cited.dart` is in
  the pre-commit skip list *and* still counted covered via `commit-msg.sh`.
- **`denoland/setup-deno@v2` `cache`/`cache-hash`** — confirmed against the live
  `action.yml` fetched from the action's own repo, not from memory.
- **Line anchors** — 4/4 spot-checked against the committed board, all exact.
