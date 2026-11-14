---
reviewed_at: 2026-09-27T20:23:17+05:30
staged_against: af6a1b2fe201
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, self_attesting_artifact]
findings_count: 5
verdict: accepted
---

# Code Review — af6a1b2fe201

> Renamed from `d763fd5fd6cc-review.md` — the fixes below (moving OI-254's board entry,
> correcting `docs/sot_registry.yaml` line_ranges, the diagnose-doc corrections) moved the
> staged-diff hash, per this skill's own documented hash-fixed-point convention (see
> SKILL.md's tuning history, e.g. the 2026-09-11/2026-09-13 entries).

Branch: `ops-alerting-b2a2b` (unit B2a-2b of the ops-alerting batch). Reviewed the full staged
diff (20 files) against the working tree, with two live mutation-verification experiments run
and reverted (both confirmed exact matches to the diagnose-doc's own mutation-proof claims —
see "Verified clean" section).

## Finding 1 — P1 — self_attesting_artifact
- **file:line:** `docs/audit/open_issues.md:6084` (OI-254's `Status:` field) vs.
  `docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md:192`
  and `test/contracts/ops_alerts_spike_breadth_test.dart:78` (staged diff, comment block above
  `cntDef`)
- **claim:** The diagnose-doc's own prose states outright *"OI-254 is closed (the one genuine
  false-positive op_type no longer inflates cnt...)"*, and the staged edit to
  `ops_alerts_spike_breadth_test.dart`'s comment independently says *"tracked as OI-254, closed
  in B2a-2b"*. But `docs/audit/open_issues.md` is **not part of the staged diff at all**
  (`git diff --cached --name-only` does not list it), and its OI-254 entry still reads
  `**Status**: OPEN` with no `closes-oi:` transition anywhere in this commit. The generated
  `docs/audit/OPEN_INDEX.md` (also untouched) still lists OI-254 as open
  (`| OI-254 | ... | none | never | ...`). This is exactly the class CLAUDE.md's own OI-board
  row documents (`closes-oi: OI-NN` enforced by `check_closes_oi_cited.dart` only on an
  OPEN→CLOSED transition) — because this diff never performs that transition, the gate has
  nothing to catch here, and the board will silently keep telling the next session OI-254 is
  unresolved while two other files in the same commit assert it is done.
- **verification:**
  `git diff --cached --name-only | grep -c open_issues` (returns nothing / exit 1 — confirms the
  file isn't staged); `grep -n "^## OI-254" -A3 docs/audit/open_issues.md` (shows `Status: OPEN`
  live on disk).
- **suggested-fix:** In the same commit, update `docs/audit/open_issues.md`'s OI-254 entry to
  `Status: CLOSED` (or move it to `closed_issues.md` per the repo's archival convention) with a
  `closes-oi: OI-254` reference in the eventual commit message, and regenerate
  `docs/audit/OPEN_INDEX.md` (`dart run scripts/build_oi_index.dart`, or let pre-commit do it).
  If the intent is instead to leave OI-254 open until the migration-side asymmetry it also
  describes is separately resolved, then the diagnose-doc's and test comment's "closed" language
  should be softened to "the client-side half of OI-254 is fixed; the SQL-side asymmetry
  remains open" — the current wording overstates what this diff does to the board's own record
  of the issue.
- **status:** accepted / fixed. OI-254 confirmed fully resolvable (not just the client-side
  half): re-audited the "~24 other call-sites" the OI's own "Fix shape" called for and found 6
  matches, each carrying a pre-existing code comment proving deliberate instrumentation, not an
  accidental `_null` collision — zero further renames needed, so the SQL-side asymmetry closes
  by removing its one cause rather than needing a separate SQL fix. Moved OI-254 from
  `docs/audit/open_issues.md` to `docs/audit/closed_issues.md` with a full closure entry
  (Status: CLOSED, Verified, Closes fields), regenerated `docs/audit/OPEN_INDEX.md`
  (`dart run scripts/build_oi_index.dart` — confirms 0 `OI-254` hits post-regen), and the
  commit landing this cites `closes-oi: OI-254` in its trailer.

## Finding 2 — P2 — self_attesting_artifact / asserted_fixture_value (stale SoT citation)
- **file:line:** `docs/sot_registry.yaml:5209-5214` (the `error_telemetry_helper` concept's
  `readers:` entry for `lib/core/services/sync_service.dart`) vs.
  `docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md:36`
  (`sot_registry_entry: error_telemetry_helper (docs/sot_registry.yaml — writer/reader
  unchanged by this batch; ...)`)
- **claim:** Two problems, one compounding the other. (a) The diagnose-doc's own frontmatter
  explicitly claims the `error_telemetry_helper` concept's writer/reader entries are *"unchanged
  by this batch"* — false: the staged diff to `docs/sot_registry.yaml` widens the writer's
  `line_range` from `19-280` to `19-416`, the `sync_service.dart` reader's from `350-510` to
  `2500-2565`, AND the `subscription_service.dart` reader's from `197-605` to `197-1237` — all
  three are touched. (b) The NEW range chosen for the `sync_service.dart` reader
  (`_reportSyncFailure`, 2500-2565) is itself imprecise in exactly the way that matters for this
  diff: `_reportSyncFailure`'s method declaration is at line 2553 (inside the cited range, so
  `check_sot_registry_parity.dart`'s symbol-presence check passes), but the method's actual body
  — including the `ErrorTelemetry.recordNonFatal(...)` call this concept exists to describe, and
  which THIS SAME DIFF modifies to add `skipServerPost: true` — sits at line **2569**, four lines
  past the cited range's end (2565), and the method itself doesn't close until line 2600, 35
  lines past the cited end. The gate mechanically passes because it only checks that the
  symbol's declaration line is in-bounds, not that the range actually spans the method body.
- **verification:**
  `git diff --cached docs/sot_registry.yaml | grep -A2 'line_range: 350-510'` (shows the change);
  `grep -n "Future<void> _reportSyncFailure" lib/core/services/sync_service.dart` → `2553`;
  `awk 'NR==2553{print NR} NR>=2553 && /^  }$/{print NR; exit}' lib/core/services/sync_service.dart`
  → `2553` and `2600`; `grep -n "recordNonFatal(error, null" lib/core/services/sync_service.dart`
  → `2569` (outside `2500-2565`); `dart run scripts/check_sot_registry_parity.dart` (passes
  anyway — confirms the gate cannot see this class of incompleteness).
- **suggested-fix:** Correct the diagnose-doc's `sot_registry_entry:` line to acknowledge the
  registry WAS touched (drop "unchanged by this batch", or scope the claim precisely to "no
  writer/reader/semantic CHANGE, only line-range drift correction"). Separately, widen the
  `sync_service.dart` reader's `line_range` to at least `2540-2600` so it actually covers
  `_reportSyncFailure`'s full body including the `recordNonFatal` call site.
- **status:** accepted / fixed. `sync_service.dart` reader's `line_range` widened to
  `2540-2605` (confirmed via `grep -n "Future<void> _reportSyncFailure"` → 2553 and the
  method's closing brace → 2600, both now inside range). Writer's `line_range` also widened
  19-416→19-423 (see Finding 5). Diagnose-doc's `sot_registry_entry:` frontmatter line
  corrected to describe the actual line_range corrections instead of claiming "unchanged".
  `dart run scripts/check_sot_registry_parity.dart` re-run: still PASS.

## Finding 3 — P3 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml:23-25` (`platform` tier `requires: [regression_test,
  behavioral_test_path, code_review_b_pass, feature_flag]`) vs. the whole staged diff (no
  kill-switch/flag anywhere)
- **claim:** This diff's blast-radius is `platform` (confirmed: `lib/core/services/sync/**`
  glob), and CLAUDE.md §4.6 says the feature-flag protocol applies "when touching ... sync" —
  this diff touches `sync_service.dart` and all 8 of its `part of` files directly. None of the
  three fixes (the `skipServerPost` dual-write correction, the OI-254 op_type rename, or the new
  `isOfflineNoiseSignature`/`isOfflineNoise` pure functions) is gated behind a kill-switch,
  `kDebugMode` check, or Hive/RemoteConfig flag — `grep -c "kill.switch\|disable_\|feature_flag"`
  over the new diagnose-doc returns 0. Per the letter of `blast_radius.yaml`'s `requires:` list,
  this is unmet. **Mitigating context, stated because this is a well-precedented, repo-wide gap
  and not unique to this diff:** no gate in the repo actually enforces the `requires:` list
  (`check_blast_radius_coverage.dart` does not read it — confirmed by this same skill's own
  2026-08-11 and 2026-09-16(d) tuning-history entries, which found and recorded the identical
  gap on unrelated diffs), and the actual behavioral risk here is narrow: every change is
  telemetry-SHAPE (which table gets which row, what an op_type is named, a pure classification
  helper with zero production callers) rather than a write-path or user-data change — the worst
  failure mode of a defect in this diff is a wrong/missing `client_errors` row, not data loss or
  a broken user flow. Recorded per this lens's "show your work" convention rather than because
  it's a novel risk.
- **verification:** `grep -c "kill.switch\|disable_\|feature_flag\|kDebugMode" docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md` → 0;
  `sed -n '23,25p' docs/blast_radius.yaml`.
- **suggested-fix:** Either add a one-line acknowledgment to the diagnose-doc's
  `touched_layers_checked` or a dedicated note explaining why a kill-switch was judged
  unnecessary here (telemetry-shape-only, trivially revertible via a follow-up EF/client
  redeploy), matching the pattern other platform-tier telemetry-only diffs in this repo's
  history have used — or accept this as a known, already-tracked process gap and take no
  action, consistent with prior precedent.
- **status:** accepted / documented (no kill-switch added). Added a "Kill-switch decision"
  paragraph to the diagnose-doc's Fix section, giving a per-fix rationale (write-count-only
  change with a durable retained writer; a pure rename with no reader keying decision logic on
  the old literal; a pure function with zero production callers) rather than a blanket
  exemption, citing this skill's own 2026-08-11/2026-09-16(d) precedent that the `requires:`
  list is not mechanically enforced repo-wide.

## Finding 4 — P4 — asserted_fixture_value (minor, informational)
- **file:line:**
  `docs/diagnoses/2026-09-27-sync-telemetry-dual-write-oi254-offline-signature-f7b2c9.md:167`
  (`touched_layers_checked` tier 4 evidence field)
- **claim:** The evidence string reads *"...4/4 SyncQueue.instance.drain() call sites confirmed
  wired (app launch, connectivity restore x2, manual retry)."* The parenthetical almost
  certainly has a copy/paste slip — the doc's OWN earlier prose (line 95) correctly names the
  four distinct triggers as *"app launch, connectivity restore, periodic timer, manual retry"*,
  but this later evidence field repeats "connectivity restore" a second time instead of naming
  the periodic-timer trigger. The underlying numeric claim ("4/4") IS independently verified
  accurate: `grep -rn "SyncQueue.instance.drain()" lib/` returns exactly 4 production call sites
  (`sync_state_provider.dart:168,182,224` + `splash_screen.dart:256`) plus one self-referential
  match inside `sync_queue.dart`'s own doc comment quoting the grep command itself (which the
  doc correctly doesn't count).
- **verification:** `grep -rn "SyncQueue.instance.drain()" lib/` (5 hits, 1 of which is the
  doc-comment's own self-quote); compare doc line 95 vs. line 167's parenthetical wording.
- **suggested-fix:** Fix the parenthetical to read "(app launch, connectivity restore, periodic
  timer, manual retry)" for consistency with the doc's own earlier, correct listing. Cosmetic
  only — no code or test change needed.
- **status:** accepted / fixed. Corrected the parenthetical to "(app launch, connectivity
  restore, periodic timer, manual retry)".

## Finding 5 — P4 — asserted_fixture_value (minor, informational)
- **file:line:** `docs/sot_registry.yaml:5200-5202` (`error_telemetry_helper` writer entry,
  `line_range: 19-416`, `method: ErrorTelemetry (whole class)`)
- **claim:** `lib/core/services/error_telemetry.dart`'s `ErrorTelemetry` class actually closes
  at line 423 (`wc -l` confirms the file is 423 lines total, with the class's final closing
  brace on the last line), not 416. Line 416 falls inside the doc-comment for
  `_currentClientVersion()`, so the cited range for "whole class" misses that entire helper
  method (7 lines). Low materiality: `_currentClientVersion()` is unrelated to anything this
  diff touches (`skipServerPost`, `recordNonFatal`'s server leg), and the gate
  (`check_sot_registry_parity.dart`) passes regardless since it only checks the class-name
  symbol is in-bounds, not that the range spans to the true closing brace.
- **verification:** `wc -l lib/core/services/error_telemetry.dart` → 423; `sed -n '414,423p'
  lib/core/services/error_telemetry.dart` shows the actual closing `}` at line 423, with
  `_currentClientVersion()` (lines 417-422) entirely outside the cited 19-416 range.
- **suggested-fix:** Widen to `19-423` (or `19-9999`, the repo's "to EOF" convention used
  elsewhere in this same registry file) next time this entry is touched. Not worth a
  dedicated commit on its own.
- **status:** accepted / fixed. Since Finding 2's fix already touches this same writer entry,
  widened it to `19-423` in the same edit rather than leaving it for a later commit.

## Verified clean (lenses that returned no finding — showing the work)

- **writer_reader_drift (the 87-site count, the diff's own headline claim):**
  Independently re-derived the caller-level "H-42 telemetry pair" count from scratch using the
  SAME concatenation approach `test/contracts/_sync_service_source.dart` uses (root
  `sync_service.dart` + all 8 files under `lib/core/services/sync/`), with my own Python
  regex mirroring the Dart test's exact pattern
  (`unawaited\(ErrorTelemetry\.recordNonFatal\([^;]*?\)\);` non-greedy, then checking for
  `_reportSyncFailure(` within 300 chars of the match end). Result: **106** total
  `recordNonFatal` call sites, of which **exactly 87** are genuinely paired (immediately
  followed by a `_reportSyncFailure` call reporting the SAME caught error variable — spot-
  checked several pairs by hand, e.g. `sync_workout.dart:1389-1396` and `:1841-1847`, both
  pass the identical error object to both calls), and **all 87** carry `skipServerPost: true`
  in the staged diff — zero missing. Per-file breakdown matches the diagnose-doc's own claimed
  counts exactly: sync_service.dart 13, sync_workout.dart 19, sync_health.dart 16,
  sync_community.dart 9, sync_nutrition.dart 9, sync_restore_completeness.dart 9,
  sync_profile.dart 8, sync_coach.dart 4 (sync_realtime.dart correctly 0, omitted from the
  doc's list since it's zero). Of the 19 unpaired sites, spot-checked several
  (`sync_domain_push_${domain.name}`, `sync_service_check_and_sync`,
  `sync_service_if_20`/templates-resync) and confirmed each is a genuine single-post site with
  no accompanying `_reportSyncFailure` call for the same error — none are a missed pair. Also
  checked the discrepancy between 92 raw "H-42" comment mentions and 87 code-detected pairs:
  the extra 5 are either doc-comment prose (`_safeRestoreOp`'s docstring, no adjacent call) or
  genuinely single-post catch blocks whose "H-42" comment label is a stale leftover — not a
  missed double-write.
  `grep -rln "functions.invoke(\s*'log-client-error'" lib/` also confirms `sync_service.dart`
  is the ONLY file outside `error_telemetry.dart` making a direct `log-client-error` EF call —
  no sibling "canonical writer" elsewhere in the codebase (e.g. `razorpay_service.dart`, which
  mentions `_reportSyncFailure` in a comment) actually calls it, so the fix's scope
  (sync_service.dart + its 8 part files) is complete and correctly bounded.

- **error_telemetry.dart's `skipServerPost` parameter — sane default, misuse risk assessed:**
  Default is `false`, matching every pre-existing call site's behavior (no silent behavior
  change for the ~35+ other `recordNonFatal` callers across the app). Live-mutated the guard
  (`if (skipServerPost) return;` → a no-op comment) and re-ran `test/sync/sync_telemetry_test.dart`:
  exactly 1 test reddens (`sha256sum` before/after confirms the file was restored byte-identical
  to its pre-mutation state), matching the diagnose-doc's own claimed mutation-proof exactly.
  A future caller COULD misuse the parameter (set `skipServerPost: true` without a paired
  canonical writer, silently losing that failure's `client_errors` row) — this is enforced by
  doc-comment discipline only, not a gate — but this is an existing, pre-diff risk shape (the
  parameter didn't exist before; its contract is thoroughly documented in the 15-line doc
  comment above `recordNonFatal`) and not something this diff makes worse.

- **isOfflineNoiseSignature / migration 147 byte-parity (asserted_fixture_value +
  guard_without_its_mirror):** Read `supabase/migrations/147_alert_client_errors_spike_breadth.sql`
  directly (not the test's claim of parity) and compared all three regex literals character-by-
  character against `lib/core/services/sync_error.dart`'s three `RegExp` constants: the
  connectivity-loss signature and the never-offline status-code override are `~*` (case-
  insensitive) in SQL and `caseSensitive: false` in Dart; the never-offline exception-type
  override is bare `~` (case-SENSITIVE) in SQL and has NO `caseSensitive: false` in Dart (i.e.
  case-sensitive by Dart's default) — matches exactly, both ways. Live-mutated
  `_offlineNoiseTypeOverride` to add `caseSensitive: false` and re-ran
  `test/contracts/offline_signature_migration_147_parity_test.dart`: exactly 1 test reddens
  (the dedicated case-sensitivity-parity assertion), file restored byte-identical after
  (`sha256sum` before/after match). Also verified the boolean logic: the SQL's exclusion
  predicate is `NOT (A AND NOT (B OR C))`; the Dart function returns `true` (= "is offline
  noise") exactly when `A && !B && !C`, which is the logical negation of the SQL's inclusion
  condition — i.e., the two sides classify identically. `isOfflineNoise`/`isOfflineNoiseSignature`
  have zero production callers today (`grep -n "isOfflineNoise\b" lib/ test/` outside
  `sync_error.dart` and its own test only matches the test file) — this is explicitly and
  honestly disclosed in the diagnose-doc ("no production reader yet (deliberately...)"), not a
  hidden gap.

- **sync_queue.dart "queue drift" comment fix (writer_reader_drift / missing_input):**
  Confirmed `enqueueFresh` genuinely has zero production callers
  (`grep -rn "enqueueFresh" lib/` matches only its own definition and doc comment) — the old
  doc comment's claim that it was "used for push-snapshot" was false, and the new comment
  correctly says so without introducing a behavior change (dead code, comment-only fix,
  correctly NOT filed as a new bug per the diagnose-doc's own reasoning).

- **supabase/functions/ cross-tree sweep:** `grep -rn "subscription_refresh_query_returned_null\|subscription_refresh_no_active_row\|H-42" supabase/functions/` returns zero hits in actual EF code (one unrelated documentation reference to `recordNonFatal` in `supabase/functions/CLAUDE.md`, describing the general client→EF telemetry flow, not this op_type or pattern specifically). No server-side code needs updating for either fix.

- **secrets_in_tree:** No credential-shaped literals anywhere in the staged diff
  (`git diff --cached | grep -iE "sk-|rzp_live_|AKIA|-----BEGIN"` → 0 hits).

- **Test-count arithmetic:** Independently ran all 34 tests across the 4 touched/added test
  files (`test/sync/sync_telemetry_test.dart` 6, `test/contracts/oi254_subscription_refresh_op_type_rename_test.dart`
  5, `test/contracts/offline_signature_migration_147_parity_test.dart` 12,
  `test/contracts/ops_alerts_spike_breadth_test.dart` 11 — counted via `grep -c "^\s*test("` per
  file, matching the diagnose-doc's claimed 6+5+12+11=34 exactly) — all green.

- **`flutter analyze lib/core/services/`:** 17 pre-existing `info`-level lint notes, zero
  `warning`/`error`, none introduced by or related to this diff's changed lines (spot-checked
  line numbers against the diff hunks).

## Method notes
- Gate re-run: `dart run scripts/check_sot_registry_parity.dart` and
  `dart run scripts/check_sot_behavioral_test_paths.dart` both PASS on the staged tree (Finding 2
  demonstrates the parity gate's pass is not sufficient evidence of a fully-accurate citation).
- Two live mutations were performed (`lib/core/services/sync_error.dart`'s
  `_offlineNoiseTypeOverride`, `lib/core/services/error_telemetry.dart`'s `skipServerPost` guard),
  each immediately reverted via `git checkout --` and confirmed via `sha256sum` match against the
  pre-mutation state. `git status --porcelain` at the end of this review shows only the original
  20 staged files (18 `M`/`A` from the task) plus this new, untracked review file — no residual
  working-tree changes.

## Founder triage notes

All 5 findings triaged `accepted` and fixed/documented in the same commit (`ops-alerting-b2a2b`,
2026-09-27): Finding 1 (P1) resolved by closing OI-254 for real on the board (after re-auditing
the OI's own "~24 other call-sites" instruction and finding it already clean); Finding 2 (P2)
resolved by correcting the SoT registry line_ranges and the diagnose-doc's false "unchanged"
claim; Finding 3 (P3) resolved by documenting the kill-switch decision rationale; Findings 4-5
(P4) resolved by the two cosmetic corrections. 0/5 false alarms — no code defects found, all
findings were documentation/process-completeness gaps in a batch whose underlying fixes were
already independently mutation-proven and behaviorally verified correct.
