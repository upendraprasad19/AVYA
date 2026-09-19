---
branch: oi91-claude-md-citations
date: 2026-08-08
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/82917310f7be-review.md
hermes: accepted
hermes_report: docs/audit/2026-08-08-hermes-oi91-claude-md-citations.md
---

# Plan-review record — OI-91 (catastrophic)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Catastrophic tier because `supabase/functions/razorpay-webhook/index.ts` carries
2 of the swept citations and `docs/blast_radius.yaml:41` maps that path with no
comment-only carve-out — confirmed by `blast_radius_from_diff.dart` against the
committed diff, reproduced independently by both review rounds below.

## Scope

OI-91: 138 dead `CLAUDE.md §N` citations in source comments (root `CLAUDE.md`'s
2026-05-18 declutter renumbered sections down to §0,1,2,2a,3,4,5,6,7) across 101
files, plus 11 further "wrong-but-live" citations found only by reading, plus a
new zone in `scripts/check_claude_md_citations.dart` (Gate 26) scanning code
comments, landed hard-fail in the same commit. Diagnose-doc `b2f7a4`; closure
ledger `docs/audit/oi91_claude_md_citations.closure.yaml` (5/5 terminal); test
`test/scripts/claude_md_citations_letter_suffix_test.dart`; commit `49c1b7c`,
pushed to `origin/oi91-claude-md-citations`. `closes-oi: OI-91`; a structural
follow-up (Gate 26 has no `docs/` zone) filed as **OI-99**.

## Review round 1 — independent, ground-truth verification

Dispatched against the staged, pre-commit diff. Re-derived every headline claim
from scratch (the 0-count survey, the 113-file diff shape, the declutter plan's
task-by-task mapping, the audit doc's per-§19-entry classification, the
`catastrophic` blast-radius result, the zero-`SECURITY DEFINER` migrations, the
`_codeZoneEnforced=true` gate PASS) and reproduced all of them. Independently
executed the gate's negative control itself rather than trusting the diagnose-
doc's account (appended a probe citation, confirmed FAIL naming the exact
file:line, reverted, confirmed PASS restored).

Raised one material finding: the diagnose-doc's §19 citation count (11) looked
wrong against a `grep -c '^-.*§19'` diff-line count, which returned 12. **This
was investigated further after round 1 and rejected as a false alarm** — see
"§19 = 11, not 12" below. Also flagged two cosmetic-only findings (comment
over-indentation in 2 test files; a stale `_codeZoneEnforced = false` sentence
in the test file's own header comment), both fixed in the landed commit.

### §19 = 11, not 12 — independently re-derived twice, not just once

Two independent reviewers — this round-1 pass and, separately, the B-pass
review — both proposed the diagnose-doc's §19 count should be 12. Both used the
same method (`grep -c '^-.*§19'` over the diff), and both were wrong the same
way: `test/contracts/supabase_functions_no_cerebras_openrouter_test.dart`'s
pre-fix line 10 read `` `lib/CLAUDE.md` §11 model matrix and §19 entry
"Cerebras/OpenRouter calls anywhere" `` — a bare "§19" word 20+ characters from
the nearest "CLAUDE.md" token, sitting on the same line as a real, separately-
cited, separately-fixed `§11`. The code zone's own anchor pattern
(`CLAUDE\.md.{0,3}§N`) never matched it; a diff-line grep can't see that
distinction, reading the file can. Re-verified from a clean pre-fix tree
extraction (`git archive 0f2268a | tar -x`, the actual merge-base — not `HEAD`,
which post-commit is the fixed tree and returns 0): **exactly 11** matches, 11
distinct files, grand total exactly 138. **Round 2 independently reproduced
this same extraction and got the same answer**, so this is now verified by two
separate rounds using the recommended method (clean-tree extraction) against
two rounds that got it wrong using the same flawed method (diff-line counting) —
the convergence is real, not one round trusting the other's prose.

## Review round 2 — independent, on the round-1-hardened, committed and pushed state

Dispatched against commit `49c1b7c` on `origin/oi91-claude-md-citations`, per
§4.12's explicit warning that round-1's own corrections can introduce new
defects. Re-ran the full ground truth from scratch (survey → 0, gate → PASS,
7/7 gate tests, `flutter analyze` → 0/0/242, SoT registry parity → PASS,
Gate 40 → PASS, euphemism gate → PASS, `closes-oi`/`closes-diagnose` trailers →
valid) and independently re-derived the §19 dispute (above). Confirmed the
gate is genuinely wired hard-fail via `pre-commit.sh`'s gate loop and CI's
identical `audit-gates` job, with its own fresh negative control.

It also did exactly what round 2 exists to do — found real problems in round
1's own corrections and in material B-pass didn't cover. All investigated and
resolved in a follow-up commit on this same branch (kept as a separate commit
rather than amending `49c1b7c`, since the first commit is already pushed and
CLAUDE.md §4.3 defaults to new commits over amends):

- **Migration 070's caps citation was newly wrong-but-live.** The mechanical
  §10→`subscription.md` bulk map was applied to
  `supabase/migrations/070_coach_media_bucket_and_caps.sql:23`'s "client-side
  caps documented in [...]" pointer, but `subscription.md` contains none of the
  cap values — the content actually lives at `docs/audit/closed_issues.md`
  (OI-24). **Fixed**: repointed to the real location.
- **The regex-gap paragraph added as hardening contained two false claims.**
  `"CLAUDE.md (§7)"` was offered as a second non-matching example; round 2
  re-ran the actual pattern and it DOES match (2-char gap, inside `.{0,3}`).
  Separately, "the one live 2-dot citation in scope" is six, across five files.
  **Fixed**: the bad example removed, the count corrected to six with each
  site named, and a further, previously-unmentioned symmetry noted (the gate's
  own heading parser can't recognise CLAUDE.md's one 2-dot heading either, so
  `§4.1.5` citations validate by truncation, not genuine resolution).
- **`food_parser.ts:18,129` quoted an anchor that doesn't exist at its cited
  destination.** Both cited `docs/architecture/sync.md "Scan meal saves 0
  kcal"` — that exact phrase is a retired §19 entry TITLE, not text present in
  sync.md (which has the substantive rule, just not that quoted string). This
  is the one §19-shaped title that rode inside a §15 bulk citation instead of
  getting the individual §19 treatment the other 11 got. **Fixed**: both sites
  now name the retired entry (#35, Class A) and its surviving test, matching
  the treatment already given to the 11 direct §19 citations.
- **"138 citations, 100 files" was wrong in 3 places** (diagnose-doc ×2,
  closure ledger ×1) — the true count, reproduced from the same clean
  extraction used for the §19 recount, is **101** files. The commit message
  already had this right; only the doc/ledger prose was off by one. **Fixed**
  in all 3 locations.
- **The `git archive HEAD` reproducibility recipe went stale the moment the
  commit landed** (`HEAD` now means the fixed tree, returns 0 not 11).
  **Fixed**: recipe now names the actual merge-base sha (`0f2268a`).

One finding could not be fixed in place: **the commit message's prose points to
`docs/reviews/9cdef6497f2e-review.md`, which has never existed.** The B-pass
review went through 3 hash-dance renames during triage (staging changed after
the review ran, each change is included in the gate's own hash computation
except `docs/reviews/` itself) and the commit message — written once, before
the last two renames — was never updated to match. The real file, confirmed
present and gate-satisfying, is **`docs/reviews/82917310f7be-review.md`**
(see `bpass_review:` above). `49c1b7c` is already pushed; per CLAUDE.md §4.3
("always create NEW commits rather than amending... unless the user explicitly
requests"), this record does not amend it — the correct filename is recorded
here instead, so it is recoverable from the one place a future reader would
actually look when the commit's own pointer dead-ends.

## Verdict

**Converged.** Both rounds independently re-derived the batch's substance from
scratch and it holds: the sweep is complete (0 remaining), the gate is real and
hard-fails under live negative controls (verified 3 times across both rounds
plus the original implementation), analyze and the full contract suite are
clean, and the one live citation-count dispute that recurred across two
independent reviewers was resolved by a third, more rigorous method and then
independently reproduced by round 2. Round 2's own findings — the two
newly-introduced documentation inaccuracies in round 1's hardening paragraph,
the one substantive wrong-but-live citation the sweep itself minted, the one
inaccurate quoted anchor, and the file-count off-by-one — were all fixed in a
follow-up commit on this branch before this record was written, which is what
makes `ground_truth_verified: true` here mean "round 2's findings were
resolved," not merely "round 2 ran."
