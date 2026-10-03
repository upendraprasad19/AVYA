---
reviewed_at: 2026-09-07T11:17:20+05:30
staged_against: 0acbed4f3155
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [asserted_fixture_value, guard_command_executability, self_matching_check, stale_or_wrong_citation, internal_contradiction, claim_accuracy]
findings_count: 6
verdict: accepted
---

# Review — 0acbed4f3155

Context-blind B-pass over the staged docs/process diff (CLAUDE.md §4.9 row,
`.claude/skills/debugging/SKILL.md`, `docs/audit/open_issues.md` OI-167,
`docs/audit/OPEN_INDEX.md`). Blast-radius `platform`, so per §4.3 the standard
applied was **self-consistency of the wording**, not an adversarial code hunt —
and nearly all effort went into re-deriving the diff's numeric and citation
claims from the files rather than reasoning from its prose.

**6 findings, 0 false alarms.** Every one was independently re-verified by the
author before acting (per the standing rule that subagent numeric claims are
unverified until checked). All six held. Two of them invalidated claims the
author had made confidently and had already "verified" with a command that was
too narrow.

## Findings

### Finding 1 — P1 — asserted_fixture_value
- **file:line:** `docs/audit/open_issues.md` (OI-167 title + Verified bullet); `.claude/skills/debugging/SKILL.md` §2 header
- **claim:** The entry said **ten** duplicated bug-class numbers, listing `2.61` among them.
- **verification:** `grep -oE '^### 2\.[0-9]+' .claude/skills/debugging/SKILL.md | grep -oE '[0-9]+$' | sort -n | uniq -d` → `36 37 38 39 40 41 53 54 55` — **nine**. `grep -cE '^### 2\.61 '` → `1`. The same command against `git show HEAD:...` returns the identical nine, so 2.61 was never duplicated in any committed state.
- **root cause:** 2.61 was duplicated only *transiently*, by this session, and had already been renumbered to 2.63 before the entry was written. The author folded a self-inflicted near-miss into a list of pre-existing defects.
- **suggested-fix:** nine, not ten; drop 2.61 from both lists and record the near-miss separately as the discovery mechanism.
- **resolution:** FIXED. Both lists now say NINE and exclude 2.61; the skill header and OI-167 each state explicitly that 2.61 is *how the mechanism was found*, not a member of the set.
status: accepted

### Finding 2 — P1 — asserted_fixture_value
- **file:line:** `docs/audit/open_issues.md` (OI-167, "why this was NOT renumbered"); `.claude/skills/debugging/SKILL.md` §2 header
- **claim:** "2.36, 2.41, 2.53, 2.54, 2.55 and 2.61 appear to have no external citation, so those six are mechanically safe to renumber", and "2.37–2.40 are cited from **CLAUDE.md**, ADRs and diagnose-docs".
- **verification:** The author's own census filtered to lines ALSO containing `bug.?class|debugging skill`. Real citations mostly do not say that — `docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md:80` reads `2.36 (FunctionException not unpacked → masked errors)` and matches no keyword. Unfiltered census, excluding the skill and the board itself: `2.36→1 2.37→3 2.38→2 2.39→37 2.40→3 2.41→3 2.53→8 2.54→3 2.55→1`. **All nine are non-zero; only 2.61 is zero, and it is not a duplicate.** Separately `find . -iname CLAUDE.md -exec grep -Hn "2\.3[789]\|2\.40" {} \;` returns **nothing** — no CLAUDE.md cites any of them.
- **suggested-fix:** none of the nine is safely renumberable; Option 1 is not the cheap option it appears to be. Correct the source attribution.
- **resolution:** FIXED. OI-167 now carries the unfiltered census with its command, states that the raw totals OVER-COUNT (bare `2.39` matches version strings — most of that 37), strikes Option 1, drops the CLAUDE.md attribution, and records BOTH ways the first pass got it wrong. **A filter narrower than the thing being counted reports zero and looks like proof.**
status: accepted

### Finding 3 — P2 — self_matching_check
- **file:line:** `docs/audit/open_issues.md`, OI-167 Symptom + Verified bullets
- **claim:** The entry's own citation-counting command scores the entry's own text.
- **verification:** Running it returns 2 lines from `open_issues.md` itself — its Symptom example ("debugging skill bug-class 2.38") and its Verified bullet both match. Same shape `check_no_deferral_euphemism.dart` handles with a visible `deu-quote` marker.
- **suggested-fix:** exclude the board files from the prescribed command.
- **resolution:** FIXED — **on the second attempt.** The first fix added `grep -v audit/open_issues.md` / `grep -v audit/OPEN_INDEX.md`, and then *this very review file and the plan-review record* began quoting the same numbers, so the census started counting them within minutes: 2.36 went 1 → 6, 2.53 went 8 → 10. **The remediation for a self-matching check re-created the self-match through the documentation the remediation itself produced** — the same "a fix inherits its finding's blind spot" shape recorded earlier today as instance #25 of the guard-without-its-mirror class. Now excluded by DIRECTORY (`docs/(audit|reviews|plan-reviews)/`).
  ⚠ The deeper resolution is that **the exact count was the wrong claim shape**: 2.53 reads 8, 10 or 5 purely as a function of which directories are excluded. OI-167 now asserts only NON-ZERO-NESS, which is stable under every exclusion choice, and says why.
status: accepted

### Finding 4 — P2 — stale_or_wrong_citation
- **file:line:** `docs/audit/open_issues.md`, OI-167 root-cause bullet (line numbers for the 2.36 pair and the 2.61/2.62/2.53–2.60 positions)
- **claim:** exact line numbers, presented as facts about the file being shipped.
- **verification:** All matched `git show HEAD:...` — but this same diff inserts a 17-line header block ABOVE them. `grep -n "^### 2\.36 "` → `227 578` pre-diff, `244 595` staged. **Every cited line number was wrong the moment the commit existed**; the entry documented the pre-edit file. The "331–1122" range was also imprecise: 331 is 2.53's *first* occurrence, which sits above 692/722, not below.
- **suggested-fix:** re-derive post-staging, or drop exact line numbers for section identity.
- **resolution:** FIXED by removing the line numbers entirely and naming the sections instead. A citation that this very commit invalidates is worse than no citation, and it would rot again on the next edit — the structural claim ("2.61/2.62 sit ABOVE 2.53–2.60") survives without them.
status: accepted

### Finding 5 — P3 — stale_or_wrong_citation
- **file:line:** `docs/audit/open_issues.md`, OI-167 — `build_oi_index.dart:114-115`
- **claim:** the quoted "OI numbers are minted by eyeballing the board's tail" sits at 114-115.
- **verification:** `grep -n "minted by eyeballing" scripts/build_oi_index.dart` → **110**.
- **root cause:** the author copied the citation from CLAUDE.md §7's pre-existing row instead of re-deriving it. **A citation copied from another document is not a verified citation** — the code-review skill's own 2026-09-02 tuning entry says exactly this.
- **resolution:** FIXED to `110-111` in OI-167. ⚠ **The same stale citation remains in CLAUDE.md §7's "OI number uniqueness" row**, which is outside this diff's scope; noted here so it is not lost.
status: accepted

### Finding 6 — P2 — internal_contradiction
- **file:line:** `CLAUDE.md` §4.9, the `@Timeout` row
- **claim:** The row asserts in bold **"The class is 'spawns a subprocess'"**, and the newly added sentence then folds in a LIVE NETWORK CALL — which spawns no subprocess (`grep -c "Process\.\(run\|start\)" test/edge_functions/ai_proxy_test.dart` → **0**). The row's title also still said "spawns subprocesses", so a reader searching for a network timeout would never match it.
- **suggested-fix:** restate the definition as the wider one, or split the case out; consider the title.
- **resolution:** FIXED, both halves. The definition now reads **"the class is 'bounded by work this process does not CONTROL', NOT 'is named `*_e2e_*`'"**, records that it read "spawns a subprocess" until 2026-09-07 and that *the narrower wording is what let the network call through*, and states that a subprocess is one instance of the class rather than its definition. The row title now reads "spawns subprocesses — **or waits on a live service** —" so a skim-search matches.
status: accepted

## Lenses that returned clean

- **guard_command_executability** — the §2 header's prescribed max-number command was run verbatim: `63` against the staged file (correct — matches the 2.63 this diff adds) and `62` against `git show HEAD:...`. Valid POSIX pipeline, no mangled continuation. ⚠ Worth noting an earlier draft of that same guard DID ship a mangled line-continuation (`SKILL.md >   | grep`), caught and fixed before this review; the lens is clean on what was actually staged.
- **claim_accuracy** — the CLAUDE.md sentence about `ai_proxy_test.dart` checks out against `git show 7a6db0f4`: pre-fix the file had `@TestOn('vm')` + `library;` and **no** `@Timeout`, and `callEdgeFunction`'s `http.post` had no `.timeout()`, so it ran on Dart's undeclared 30 s default exactly as claimed. Diagnose `a7c3e9` exists and corroborates.
- **OI-number collision** — `OI-167` appears in neither `open_issues.md` nor `closed_issues.md` at any heading level before this diff; it follows OI-166 sequentially. `grep -cE '^## OI-[0-9]+' docs/audit/open_issues.md` → 86, all carrying `**Status**: OPEN`, and `OPEN_INDEX.md` agrees at 86.

## Founder triage notes

All 6 accepted and fixed in this batch; nothing spawned, nothing carried.

**The two P1s are the same failure wearing different clothes, and both were mine.**
Finding 1 counted a defect I had created and immediately fixed as though it were
pre-existing. Finding 2 ran a census whose filter was narrower than the thing it
was counting, got zero, and reported the zero as a safety property — *"six are
mechanically safe to renumber"* — which would have been acted on. In both cases
a command had been run and its output pasted into a `Verified:` field, which is
exactly what makes them dangerous: they look audited.

**The residue worth remembering** is Finding 4. Those line numbers were correct
when derived and wrong when committed, because the same diff shifted them by 17
lines. Deriving a citation against the pre-edit file and shipping it in the edit
is a self-invalidating claim, and no gate catches it. The fix was to stop citing
lines in prose that will move.
