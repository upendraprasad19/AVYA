---
reviewed_at: 2026-08-06
branch: deps-board-equipment
reviewed_range: a307fdc8..85f17767
blast_radius: platform
reviewer: fresh context-blind subagent (5-lens B-pass, .claude/skills/code-review/SKILL.md)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, dependency_version_table, analyze_clean]
findings_count: 2
verdict: accepted
---

# B-pass — deps-board-equipment

Run before the `--no-ff` merge per §4.3 (self-initiated, ≥account). The reviewer was
context-blind and told to find bugs, not validate.

## Findings

### Finding 1 — P1 — blast_radius_mismatch (§4.6 rollback operability)
- **file:line:** `lib/core/router/app_router.dart:336-341`, `lib/features/dev/dev_panel_screen.dart:297-302` + `:275-286`
- **claim:** The diagnose-doc and closure R5 asserted the pre-flip path stays "reachable"
  via the new dev-panel toggle. False for the shipped artifact: `/dev` is registered only
  `if (kDebugMode)`, and the screen additionally short-circuits on `kReleaseMode`. A release
  APK compiles the control out. No RemoteConfig exists (`sync_service.dart:254`). Reverting
  a platform-tier change in production still costs a code change + APK respin.
- **verification:** `grep -n "if (kDebugMode)" lib/core/router/app_router.dart`;
  `sed -n '295,303p' lib/features/dev/dev_panel_screen.dart`; `grep -rn "RemoteConfig" lib/`
- **status:** accepted — fixed. Claim scoped honestly in the closure ledger (R12), the flip
  commit message and the plan-review record; **OI-95** filed for the general capability.
  Deliberately NOT "fixed" by exposing a plan-engine kill-switch in a release build.
- **note:** the reviewer independently found and disclosed that an uncommitted round-2 pass
  in the same worktree had already caught this with identical citations. Two independent
  reviewers converging on the same P1 is the strongest signal in this batch.

### Finding 2 — P3 — latent test vacuity
- **file:line:** `test/contracts/warmup_injury_filter_behavioral_test.dart` (converse
  wrist-drop loop)
- **claim:** `if (!base.contains(m)) continue;` means the assertion proves nothing if the
  move ever stops reaching the baseline — the same failure mode the R3 fix one line above
  explicitly exists to kill. Live today, structurally fragile.
- **verification:** `flutter test test/contracts/warmup_injury_filter_behavioral_test.dart`
- **status:** accepted — fixed (R13). Replaced with an explicit
  `expect(base.intersection(wristTagged), isNotEmpty)` reachability guard before the loop.

## Lenses returning clean (with what was actually run)

- **writer_reader_drift** — repo-wide grep for the retired `enable_equipment_exclusions`:
  every `lib/` hit is a doc comment, zero live reads/writes. New key has exactly one
  production reader (`plan_engine_flags.dart:172`). Full profile chain traced with no name
  drift: `edit_profile_screen.dart:1686` → `sync_profile.dart:200-201` → cloud
  `user_profile.equipment_exclusions` → `training_history_analyzer.dart:168,182`. All four
  changed test `setFlag` helpers verified to invert correctly against the getter's
  `!= true` semantics. All four files re-run green.
- **function_exception_swallow** — zero new `functions.invoke(` in the diff. Read
  `error_telemetry.dart` in full: `recordNonFatal` wraps both its Crashlytics leg and its
  Edge Function POST in their own swallowing try/catch, so the `unawaited(...)` is backed by
  a self-contained sink, and the catch logs before falling back to a safe empty set.
- **secrets_in_tree** — credential-shaped grep over the whole diff: zero hits. The large
  `pubspec.lock` diff is package/version/sha256 churn only.
- **unawaited_no_error_sink** — zero new `unawaited(` added.
- **dependency version table** — every number cross-checked line-by-line against
  `pubspec.lock`. **Zero mismatches** (the previous version of that message had four). The
  `^2.16.0` floor vs 2.17.1 lock nuance is self-disclosed in the commit body.
- **flutter analyze** — run independently: 0 errors, 0 warnings, 240 infos. Matches the
  commit's claim exactly.
- **blast radius** — `platform`, matching `docs/blast_radius.yaml:67,277-278`.
- **validators** — `validate_audit_closure.dart` and `validate_diagnose_doc.dart` both PASS.
