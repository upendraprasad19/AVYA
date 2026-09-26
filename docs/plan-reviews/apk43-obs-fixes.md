---
branch: apk43-obs-fixes
date: 2026-09-16
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6f1e4db85459-review.md
---

# Plan-review record — APK 1.0.0+43 Obs 1+2 fixes (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Platform-tier, computed not estimated — the B-pass review
(`docs/reviews/6f1e4db85459-review.md`) ran
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
directly on the staged diff → `platform` (driven by `supabase/functions/ai-proxy/**`
and `supabase/functions/_shared/**`, both pinned `platform` in
`docs/blast_radius.yaml:54,61`). Not catastrophic → no Hermes.

## Scope

Two founder-reported observations against APK 1.0.0+43, fixed together per the
founder's own explicit scoping decision (AskUserQuestion, prior session): fix
Obs 2 and Obs 1 now with mutation-proven regression tests + diagnose-docs;
document-and-file Obs 3 (OI-204) without fixing it this batch.

**Obs 2** (diagnose `a1c6b9`) — AI Coach history-poisoning: a hardcoded,
non-model apology text ("I had trouble reaching the model...") was persisted
to the coach's chat history like a real reply and replayed into the next
turn's `history`, so the model echoed/continued the apology after Gemini had
already recovered — one transient quota-exhaustion outage became a
self-perpetuating "stuck" chat.

**Obs 1** (diagnose `d8e2f4`) — silent nutrition-save telemetry gap:
`AiBreakdownNotifier.saveMeal`'s outer catch block only `debugPrint`ed on a
thrown exception, so a founder-reported repeating "Could not save" had
nothing in `client_errors` to diagnose it by.

## Rounds

| round | dispatched on | findings | outcome |
|---|---|---|---|
| B-pass | staged diff, pre-round-1 | 3 (1 P1, 0 P2, 2 P3) | all 3 accepted, fixed in-batch, 0 false alarms |
| 1 | post-B-pass-hardened state | 3 (2 P1, 1 P2, 0 P3) | all 3 accepted, fixed in-batch |
| 2 | post-round-1-hardened state | 5 (0 P1, 1 P2, 4 P3) | all 5 accepted, fixed in-batch |

**11 findings, 0 false alarms, 0 rejected, across three independent
context-blind passes (B-pass + 2 plan-review rounds).**

### Why 2 review rounds and no round 3

Severity genuinely converged rather than a new-material-issues pattern
emerging: B-pass found the batch's most substantive gap (1 P1 — the
loop-exhausted apology's `hadHardFailure` site was missing entirely); round 1
found two MORE real P1s of a different shape (the restore-path had no
defense at all; `failed` reuse collided with its other reader) plus a P2;
round 2 — reviewing round 1's own corrections, per §4.12 point 1 — found no
new P1/P0 at all, only one narrow P2 (round 1's restore-path defense itself
had a mirror gap, a third failure-text shape it didn't cover) and four P3s,
all citation/verification-claim accuracy with zero functional or behavioral
consequence. Decreasing severity across three independent passes on the same
code is the convergence signal §4.12 point 1 describes, not the "successive
rounds keep surfacing new material issues" signal that calls for splitting
the unit. `review_rounds: 2` (the ×2 minimum) is met, not stretched to meet
it.

## Ground truth verified

Not inferred — each of these was run directly, this session, independent of
any reviewer's or subagent's own reported numbers (per this project's
standing rule to treat subagent numeric claims as unverified until
independently confirmed by reading the file):

- **Every citation correction re-derived via direct `grep -n`/`Read` against
  the CURRENT file, never from a reviewer's reported number or a prior
  round's number** — this was necessary because several citations had
  drifted MULTIPLE times across the session (round 1 fixed some, round 2
  found others had drifted again, and round 2's OWN code fix shifted
  `sync_coach.dart` a third time after round 2's review had already run,
  requiring re-derivation post-fix, not pre-fix). `docs/sot_registry.yaml`'s
  `coach_chat_history_replay` writers/readers corrected 7 line_ranges total
  (5 flagged by round 2, 1 found independently while re-verifying its
  neighbours, plus `sync_coach.dart`'s own re-derivation after the code
  change); this diagnose-doc's own frontmatter + body prose corrected 10
  more. All re-verified green against `scripts/check_sot_registry_parity.dart`
  after every correction (run repeatedly, not once).
- **Round 2's Finding 1 fix, mutation-proven 3 ways:** (1) removed the
  `modelUsed == kModelUsedLoopThrewSentinel` clause from
  `isRestoredHardFailureRow` — reddened exactly 1 of 17 tests (the
  sentinel-alone case); the "both signals fire" test stayed green, confirming
  it wasn't silently relying on the removed clause. (2) reverted
  `_restoreCoachInteractions`'s call from the composed
  `isRestoredHardFailureRow(...)` back to the single-text
  `isKnownHardFailureApologyText(...)` — reddened exactly 1 of 17 (the wiring
  test). (3) drifted the TS `MODEL_USED_LOOP_THREW_SENTINEL` constant's value
  away from the Dart mirror — reddened exactly 1 of 17 (the parity
  assertion), confirming the NEW parity test actually detects the exact
  drift class this fix exists to close. All three restored via Edit, re-ran
  green (17/17) after each.
- **B-pass Finding 3's claimed new test** (`real Hive — REAL
  NutritionWriteService.instance.logMeal` group in
  `ai_breakdown_notifier_save_meal_telemetry_test.dart`) — independently
  confirmed present via `grep -n` rather than trusting the review's own
  `status: accepted` marker, before flipping that review's `verdict:` from
  `pending` to `accepted`.
- **`flutter analyze --no-fatal-infos` run bare, whole-repo — the EXACT
  invocation `scripts/pre-push.sh:112` runs**, not a path-scoped substitute:
  exit 0, "277 issues found" (372.7s). Since `--no-fatal-infos` makes only
  warnings/errors fatal, the exit-0 itself is the proof all 277 are
  info-level — deliberately not re-derived via a severity grep over analyzer
  stdout, which is its own documented trap (CLAUDE.md §4.9 — the analyzer's
  fixed-width-7 column alignment makes a naive `^\s+warning` anchor
  structurally blind to `warning` specifically).
- **`ai_coach_repository.dart:32:8`'s info-level issue** (round 2 Finding 5):
  confirmed present in a file this batch's fix commit DID touch (`git show
  --stat 444ba20f` — 2 insertions) and confirmed pre-existing, not
  introduced, via `git blame -L 32,32` (commit `b34bbafe2`, 2026-05-22).
- **Every targeted test file re-run combined, this session, after all fixes
  landed:** 36 Dart tests (parity 17 + replay 11 + ai_service-parse 3 +
  telemetry 3 + save-confirmation 2) — 0 failures. 16 Deno tests
  (`tool-loop_hard_failure_flag_test.ts` 4 + `tool-loop.test.ts` 12) — 0
  failures. `deno check --node-modules-dir=none` on `ai-proxy/index.ts` — clean.
  `dart run scripts/validate_diagnose_doc.dart` on both diagnose-docs — OK.

## Residues, stated rather than closed

1. **The B-pass review file's own citations (`tool-loop.ts:114/271`,
   `ai-proxy/index.ts:1120/1161`, `coach_interaction_repository.dart`
   ranges) are left exactly as originally written**, not retroactively
   corrected to match the current file state — it is a point-in-time record
   of what was verified when the B-pass ran, and rewriting it after the fact
   would misrepresent what that review actually checked at that moment. The
   diagnose-doc itself carries the current, re-derived numbers.
2. **No gate mechanically re-verifies the diagnose-doc's own inline prose
   citations** (as opposed to `docs/sot_registry.yaml`'s `line_range:`
   fields, which `check_sot_registry_parity.dart` does check) — this class of
   drift (round 1 and round 2 both caught instances of it, in different
   files, at different points) remains a self-attested, review-caught
   category, same trust model as rule 21's `presence_only:` and rule 24's
   ledger. Stated rather than treated as solved.
3. **Obs 3 (OI-204, sync/restore timeout storm) is documented and filed, not
   fixed** — an explicit founder product-scope decision from before this
   batch, not a §4.2 deferral (it has its own OI and its own
   investigation-quality doc; it is simply not being coded against in this
   batch).
4. **The Gemini API billing/quota exhaustion that originally triggered Obs
   2's symptom is a founder action item**, not code-fixable in this batch —
   called out in both the diagnose-doc and the original commit message.

## Found and fixed in-batch, not planned

While re-verifying round 2's citation-drift findings, independently found
(not flagged by the B-pass, round 1, or round 2) that
`docs/sot_registry.yaml`'s `ai-proxy/index.ts` READER entry for this same
concept (`capCoachHistory()`/`runToolLoop(history)`) cited `line_range:
180-820` — but line 180 sits inside an unrelated function, and the actual
`capCoachHistory`/`runToolLoop` call sites are at `1032`/`1041`, both outside
the cited range. Corrected to `257-1045` (the `history` destructure through
the `runToolLoop` call). Re-verified green against
`scripts/check_sot_registry_parity.dart`.
