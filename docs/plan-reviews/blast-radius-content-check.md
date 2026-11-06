---
branch: blast-radius-content-check
scope: Content-aware SECURITY DEFINER escalation for the blast-radius classifier (follow-up from sign-in-simplify B-pass Finding 5) — a migration with an innocuous filename but SECURITY DEFINER content now auto-escalates to catastrophic tier across every script that independently computes blast-radius, instead of just the ones matching a filename glob
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3dae1353a27a-review.md
---

# Plan-review record — blast-radius-content-check

## Ground-truth verified (against live repo, pre-implementation)
`scripts/blast_radius_from_diff.dart` and `scripts/check_plan_review_record_exists.dart`
independently duplicate the whole `docs/blast_radius.yaml` path-glob engine (confirmed via direct
read — no shared import between them). Catastrophic-tier migration detection is filename-
substring-based (`*security_definer*.sql`, `*rls*.sql`, ...) — migration `106_email_is_registered_check.sql`
(a real `SECURITY DEFINER` RPC, already merged) has neither substring in its name and classified
as `platform` instead of `catastrophic`. Confirmed via live corpus grep: 20 existing migrations
contain `SECURITY DEFINER`; only 2 (`053_security_definer_hardening.sql`,
`090_revoke_anon_security_definer_execute.sql`) have a matching filename substring — the other 18
were silently under-classified before this batch, including `106`.

## Implementation
- New `scripts/blast_radius_content_rules_lib.dart`: `isMigrationSqlPath`, `containsSecurityDefiner`,
  `contentForcesCatastrophic` (injectable I/O, fails open on non-eligible/deleted/unreadable paths).
- Wired into the tier-computation loop of `scripts/blast_radius_from_diff.dart` and
  `scripts/check_plan_review_record_exists.dart` (the original two-script scope).
- Rollout: ran the rule against every existing `.sql` file under `supabase/migrations/` once —
  exactly 20 escalations, byte-identical to the independent `grep -rli "security definer"` list,
  zero false positives — then wired directly at hard-fail in the same session (no separate warn-only
  flag or 24h bake-in), per the founder's explicit choice: a static, already-scanned-clean file
  corpus doesn't need calendar-time baking the way a live-traffic gate would.
- New tests: `test/scripts/blast_radius_content_rules_lib_test.dart` (unit, injected fakes + real
  disk I/O against this repo's own migrations) and
  `test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart` (wiring pin + a real
  subprocess behavioral assertion).

## Round 1 (×2 context-blind — fresh agents, independently re-derived every claim against the
live repo, ran `flutter analyze`/`flutter test` and the full-corpus scan themselves)
- Confirmed correct: fail-open semantics, regex correctness against real repo syntax, path
  normalization (Windows `\`, the `041_chunks/` subdirectory, excluding `CLAUDE.md`), per-path (not
  diff-wide) escalation, full-corpus scan matching `grep` exactly (20/20).
- **1 P1 found — a scope gap, not a bug in what was built:** a THIRD script,
  `scripts/check_code_review_pass_exists.dart`, independently duplicates the same tier-glob engine
  and was missed by the original "two scripts" framing. Unlike the other two (one purely
  informational, one a CI-only merge gate), this one is a **blocking local pre-commit gate** —
  confirmed auto-wired into `pre-commit.sh`'s `for GATE in scripts/check_*.dart` loop and absent
  from `check_gate_scripts_wired.dart`'s allowlist. Missing it would have been the MOST
  load-bearing gap of the three, not the least. Fixed by wiring the same rule into it.
- 2 P2s fixed: a misleading code comment claimed stdout-vs-stderr was the deciding factor for local
  hook visibility, but the reviewer traced the actual 3 invocation sites and found stdout is ALSO
  piped through `grep -oE` locally, stripping the NOTE line regardless (the escalated TIER itself
  still propagates correctly — corrected the comment to state this precisely); the wiring-pin test
  only proved the function was referenced, not that its return value gated anything (a future
  `if (false && contentForcesCatastrophic(...))` would still pass) — strengthened to an if-guard
  shape assertion plus a real subprocess behavioral test against a genuine on-disk migration.

## Round 2 (×2 — on the Round-1-hardened diff, now 3 scripts not 2) — findings, fixed
- Re-verified every Round-1 fix fresh: confirmed exactly 3 scripts wired (grepped the whole
  `scripts/` tree + `.github/workflows/test.yml` for any other independent tier-computation logic —
  none found); confirmed the third script's escalation correctly short-circuits when already
  catastrophic and feeds the same `maxTier` used for the review-file requirement; re-ran the
  full-corpus scan from scratch (still 20/20 matching grep); 34 tests green.
- **1 new P1 found:** `check_code_review_pass_exists.dart` is the one gate that runs
  post-staging/pre-commit, but `contentForcesCatastrophic`'s default I/O reads the WORKING-TREE
  file (`File.readAsStringSync()`), not the staged index blob. Concrete failure: stage a
  SECURITY-DEFINER migration, then further-edit the working copy (without re-staging) to strip the
  marker before `git commit` — the STAGED blob that actually lands in the commit still carries
  SECURITY DEFINER, but the gate would read the now-clean working-tree file and miss it, reopening
  the exact gap this batch exists to close. Fixed by reading the staged blob via `git show :<path>`
  / `git cat-file -e :<path>` for this specific caller only (the other two scripts don't need this:
  one is purely advisory, the other runs in a clean CI checkout where working-tree == HEAD). New
  regression test `test/contracts/review_gate_staged_content_not_working_tree_test.dart` (isolated
  temp git repo, same technique as the existing `review_gate_hash_raw_bytes_test.dart` precedent)
  proves a working-tree read misses the staged content and a `git show :<path>` read doesn't.
- 2 cosmetic P2s fixed: a doc comment said "19 existing SECURITY DEFINER migrations" (stale —
  actually 20, including migration 106 merged before this branch); the if-guard regex in the wiring
  test needed broadening to match the new multi-arg `contentForcesCatastrophic(p, fileExists:
  ..., readFile: ...)` call shape introduced by the staged-content fix (caught by the test suite
  itself failing, not by review — confirms the test is genuinely load-bearing).
- I independently re-verified both rounds' load-bearing claims myself (read the exact lines,
  re-ran analyze/tests, re-ran the corpus scan) before accepting them.

## Verdict: converged
Root design (shared content-rule library, wired into every script that independently duplicates
the tier-glob engine) validated across 2 rounds; Round 1 found the true scope (3 scripts, not 2)
and Round 2 found a real correctness gap in the newest fix (staged-vs-working-tree divergence in
the one blocking gate) — exactly the "review #2 on the hardened plan can surface defects the
corrections themselves introduce" pattern CLAUDE.md §4.12 exists for. `flutter analyze` clean;
`flutter test test/scripts/` + all touched `test/contracts/` files green (29+ tests, including a
real subprocess behavioral test and an isolated-git-repo regression test for the staged-content
fix). Self-initiated B-pass to run before merge per §4.3.
