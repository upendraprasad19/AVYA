---
branch: ops-alerting-b2a2b
date: 2026-09-27
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/af6a1b2fe201-review.md
---

# Plan-review record — Unit B2a-2b: sync telemetry dual-write, OI-254 op_type rename, offline-signature client mirror

Keystone record for the §4.12 merge gate. Platform tier (`lib/core/services/sync/**` glob pins
platform; touches 5+ files under it) ⇒ ×2 review + a B-pass; no Hermes (no `SECURITY DEFINER`,
no schema/migration/EF/auth/payment/plan-engine change). Diagnose doc:
`docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md` (bug id
`f7b2c9`). Third and final unit of the ops-alerting batch's "client classification, queue drift,
dual write" scope (following B2a-1's migration 145 and B2a-2a's migration 147, which filed
OI-254 as this unit's carry-forward work).

## Round 1 (converged, findings widened the fix scope materially)

Reviewed the initial drafted diff, which closed the dual-write defect only inside
`_reportSyncFailure`'s own body (its internal `recordNonFatal` call vs. its own direct
`functions.invoke` — 1 site). Findings:

- **P0 (the headline finding):** the true dual-write scope is 87 caller-level "H-42 telemetry
  pair" sites across `sync_service.dart` and all 8 of its `part of` files under
  `lib/core/services/sync/`, not the 1 site the original fix addressed — each caller
  independently calls `ErrorTelemetry.recordNonFatal` immediately before calling
  `_reportSyncFailure`, double-writing to `client_errors` regardless of the round-0 fix. Found by
  the round-1 reviewer reading caller context around `_reportSyncFailure` call sites rather than
  trusting a `grep "H-42" sync_service.dart` (13 hits — misses every part file). The regression
  test written to pin the narrower fix (using `loadSyncServiceSource()`, which concatenates all
  9 files) caught the true 87-site count on its own first run, independent of and before this
  finding was even filed — confirming the finding rather than merely repeating it.
- **P1 (queue-drift investigation):** `sync_queue.dart`'s `enqueueFresh` doc comment claimed it
  was "used for push-snapshot", which a full-codebase grep showed is false (zero production
  callers). Not a live bug (dead code) but a misleading comment; fixed in-place, not filed as an
  OI since no behavior depended on the false claim.
- **P1 (unstaged registry fix):** a pre-existing `docs/sot_registry.yaml` line-range correction
  for `error_telemetry_helper` existed in the working tree but had never been `git add`-ed.
  Staged.
- **P3 (stale threshold comment):** `alerts/_thresholds.yaml`'s comment for the per-user breadth
  arm still named the pre-rename op_type. Fixed to name the new one and cross-reference OI-254.

Fixed programmatically (a script matched every `unawaited(ErrorTelemetry.recordNonFatal(...));`
call, checked whether a `_reportSyncFailure(` call followed within 300 chars, and inserted
`skipServerPost: true` into every unfixed match), then verified complete via re-scan (0
remaining) and `flutter analyze` (0 errors).

## Round 2 (converged, `mechanical_only`)

Dispatched against the post-round-1 (widened) diff. 2 findings, both mechanical/citation-class:

- **P2:** `error_telemetry.dart`'s doc comment for `skipServerPost` still said "only
  `_reportSyncFailure` sets it" after round 1 widened the fix to 87 caller-level sites — stale
  the moment round 1 landed. Rewritten to describe both the internal call and the 87 caller-level
  sites' shared idiom.
- **P2:** the diagnose-doc's `writers:` frontmatter and "Root cause" prose both cited
  `sync_service.dart:2516` for `_reportSyncFailure` — stale after round 1's edits shifted the
  method to line 2553 (2516 is now the closing brace of an unrelated method). Both occurrences
  corrected.

Both findings are citation/documentation drift caused by round 1's own remediation, not new
material defects — converges per §4.12.6's `mechanical_only: true` shortcut.

## Self-triggered B-pass (`docs/reviews/af6a1b2fe201-review.md`) — accepted

Dispatched against the full staged diff before the merge, per §4.3's self-initiation
requirement. Fresh, context-blind reviewer; independently re-derived the 87-site count from
scratch (own regex, matched exactly), live-mutated 2 of the diff's own claimed mutation-proofs
(the `skipServerPost` guard, the offline-signature case-sensitivity override) and reproduced
both exactly. 5 findings, all documentation/process-completeness gaps — zero code defects:

- **P1 (`self_attesting_artifact`):** the diagnose-doc and a staged test comment both asserted
  OI-254 was closed, but `docs/audit/open_issues.md` — untouched by the diff — still carried
  `Status: OPEN`. Resolved by re-auditing OI-254's own "Fix shape" instruction to check "~24
  other call-sites" for the same `_null`-suffix classification defect (found 6 matches, each
  independently spot-verified to carry a pre-existing code comment proving deliberate
  instrumentation, zero further renames needed) before moving the entry to
  `docs/audit/closed_issues.md` with a full closure record and regenerating `OPEN_INDEX.md`.
- **P2 (stale SoT citation, compounding the diagnose-doc's own false "unchanged" claim):** the
  diagnose-doc's frontmatter claimed the `error_telemetry_helper` concept's registry entries were
  "unchanged by this batch" (false — 3 line_ranges were touched), and the new
  `sync_service.dart` reader range (2500-2565) covered `_reportSyncFailure`'s declaration but not
  its body (the method runs 2553-2600; the `recordNonFatal` call this diff modifies sits at
  2569, outside the cited range) — `check_sot_registry_parity.dart` passes regardless, since it
  only checks the declaration line is in-bounds. Fixed: widened to `2540-2605`, widened the
  writer's range `19-416`→`19-423` (Finding 5, same root cause), corrected the diagnose-doc's
  frontmatter claim.
- **P3 (`blast_radius_mismatch`):** platform tier's `requires: feature_flag` is unmet (no
  kill-switch on any of the 3 fixes) — a well-precedented, repo-wide unenforced-`requires:` gap
  per this skill's own 2026-08-11/2026-09-16(d) history, not unique to this diff. Resolved by
  documenting a per-fix rationale in the diagnose-doc rather than a blanket wave-through: Fix 1
  is a write-COUNT change with the retained writer already durability-guaranteed; Fix 2 is a
  pure rename with a confirmed zero-reader cross-tree sweep; Fix 3 is a pure function with zero
  production callers today.
- **P4 ×2 (informational):** a copy-paste typo in a `touched_layers_checked` evidence field
  ("connectivity restore x2" → "connectivity restore, periodic timer") and the writer line_range
  off-by-7 already covered by the P2 fix above. Both fixed.

Skill self-evolution: `.claude/skills/code-review/SKILL.md` Tuning history gets a same-dated
entry describing the OI-board self-attesting-artifact sub-shape (a claim about a DIFFERENT,
untouched file, not the diagnose-doc's own internal consistency) and the per-fix blast-radius
rationale pattern.

## Regression tests

- `test/sync/sync_telemetry_test.dart` (6 tests) — including the 87-site sweep, mutation-proven
  (removing `skipServerPost: true` from any one of the 87 sites reddens exactly this test).
- `test/contracts/oi254_subscription_refresh_op_type_rename_test.dart` (new, 5 tests).
- `test/contracts/offline_signature_migration_147_parity_test.dart` (new, 12 tests) — byte-parity
  with migration 147's regex, including the case-sensitivity asymmetry, mutation-proven on 3
  axes.
- `test/contracts/ops_alerts_spike_breadth_test.dart` (1 comment line updated to the new
  op_type name; count unchanged at 11).
- All 34 tests across the 4 files green; full suite green; `flutter analyze lib/`: 0
  errors/warnings (45 pre-existing `info`-level notes, none in touched files).

## Ground truth

Every numeric/structural claim (the 87-site count, the case-sensitivity parity, the
`skipServerPost` default/guard ordering, the OI-254 cross-tree sweep, the 6-op_type audit) was
independently re-derived from the live source tree by at least one of: the round-1 reviewer, the
round-2 reviewer, or the B-pass reviewer — never accepted from the diagnose-doc's prose alone.
