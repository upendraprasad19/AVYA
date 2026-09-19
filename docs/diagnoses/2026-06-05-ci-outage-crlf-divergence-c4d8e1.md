---
bug_id: c4d8e1
date: 2026-06-05
batch: restore-ci-green
status: fixed
blast_radius: platform
symptom: >
  CI was red on `main` for days (every job died in ~1 min at `flutter pub get`:
  CI pinned Flutter 3.29.x / Dart 3.7.2 while pubspec required sdk ^3.11.1). The
  Flutter-pin bump to 3.41.4 unblocked pub get and UNMASKED four more failures
  the local hooks had never caught: 3 audit gates (check_hooks_installed,
  check_sot_registry_parity, check_sync_fanout) and 1 contract test
  (template_exercises_upsert). Root divergence: core.autocrlf=true checks the
  working tree out as CRLF while the index + Linux CI + Vercel use LF, so the
  ~28 source-grep gates and 200+ contract tests (which read working-tree bytes)
  pass locally but the same code fails in CI — the local pre-commit/pre-push
  gates were giving false confidence.
concept: ci_local_ci_parity
sot_registry_entry: not_applicable
writers: >
  not_applicable — no Hive/cloud writer. Changed surfaces: .gitattributes
  (LF normalization), .github/workflows/test.yml (Flutter pin + hooks-gate
  skip), docs/sot_registry.yaml (refreshed 36 stale method/file citations after
  the sync-split / train-screen-split / ai_coach-repo refactors),
  scripts/check_gate_scripts_wired.dart (allowlist), the new
  scripts/check_ci_flutter_version.dart gate, android/app/build.gradle.kts
  (release-signing hardening), and test/contracts/template_exercises_upsert_test.dart.
readers: >
  not_applicable — the consumers are the pre-commit/pre-push hooks + the CI
  workflow, which now read an LF working tree identical to CI.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/template_exercises_upsert_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "A source-grep gate/test that matches a multi-line pattern with a bare backslash-n while the working tree is CRLF — it silently misses the match locally. Fixed structurally: .gitattributes forces LF for all text files so the working tree == index == CI; verify with `git ls-files --eol` showing w/lf."
  - "The android release buildType silently falling back to the debug signing key when key.properties is absent — it now THROWS on a release assembly (build.gradle.kts), so a release APK can never be accidentally debug-signed (the cross-key-update trap)."
proposed_fix: >
  (A5) Add .gitattributes `* text=auto eol=lf` and renormalise the working tree
  to LF so local source-grep gates/tests match CI. (A1) The template_exercises
  test was over-broad — it forbade ANY `from('template_exercises').delete()`, but
  the bounded tail-vacuum `.delete()...gte('order_index', length)`
  (diagnose b3c8d2) is legitimate; the test now allows the bounded vacuum and
  still forbids the lossy blanket delete-then-insert. (A2/A4) Refresh 36 stale
  SoT-registry method/file citations to the post-refactor symbols (e.g.
  ai_coach readers → buildAiContext, screen.dart → expanded_exercises.dart,
  markScheduleCompleted → markCompleted, SyncService.* sync_methods → bare
  names). (A3) Allowlist check_hooks_installed.dart in CI (runners have no
  installed hooks). (A6) New check_ci_flutter_version gate asserts CI == Vercel
  Flutter pin (exact x.y.z). (A7) Harden release signing to fail without
  key.properties.
regression_test_planned: >
  test/contracts/template_exercises_upsert_test.dart (rewritten — bounded
  tail-vacuum allowed, blanket delete forbidden) is the behavioral regression
  test. The structural prevention is .gitattributes (forces local==CI) +
  scripts/check_ci_flutter_version.dart (CI/Vercel Flutter parity, wired into
  pre-commit + CI) + the build.gradle.kts release-signing throw.
touched_layers_checked:
  - { tier: 1, layer: client_code_and_ci_config, status: fixed_in_this_batch, evidence: "LF flip verified (git ls-files --eol w/crlf 1474->0); flutter analyze clean; check_sot_registry_parity / check_sync_fanout / check_gate_scripts_wired / check_ci_flutter_version all PASS locally on the LF tree" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "CI/Vercel/dev Flutter now pinned to the same 3.41.4 (check_ci_flutter_version PASS); full CI green confirmed on push (all 5 jobs)" }
impact_analysis: >
  Platform blast radius — the whole CI/build pipeline + every developer's local
  hooks. The CRLF divergence silently let regressions reach main (the
  lean-workflow skips the local full suite for feature-tier pushes, and CI was
  dead at pub get, so nothing ran the gates/tests). No user data was affected —
  none of the four unmasked failures was an actual runtime regression (the
  template-delete was a legitimate tail-vacuum; the registry drift + hooks gate
  were doc/CI-env artifacts). Fixed structurally (LF normalization makes local
  == CI permanently) plus two prevention gates so neither the Flutter-pin drift
  nor a debug-signed "release" can silently recur.
---

# CI outage + CRLF source-grep divergence

## What happened
CI was red on `main` for ~2 days. Every job died at `flutter pub get` because
`.github/workflows/test.yml` pinned Flutter 3.29.x (Dart 3.7.2) while
`pubspec.yaml` required `sdk: ^3.11.1`. Bumping the CI Flutter pin to 3.41.4
fixed pub get and revealed that **three audit gates and one contract test had
been failing in CI all along** — hidden because (a) the lean-workflow skips the
local full suite for feature-tier pushes, and (b) CI itself was dying before the
gates ran.

## Root cause
`core.autocrlf=true` checks the working tree out as **CRLF** on Windows while the
git index, Linux CI, and Vercel use **LF** (`git ls-files --eol` = `i/lf w/crlf`).
The ~28 `scripts/check_*.dart` gates and 200+ contract tests read **working-tree
bytes**, so a multi-line pattern matched with a bare `\n` (e.g. the
template_exercises delete-then-insert pin) silently misses on a CRLF checkout but
catches on LF — the local hooks and CI disagreed on identical commits.

## Fix
1. **A5 — `.gitattributes` `* text=auto eol=lf`** + renormalise the working tree
   to LF so local == index == CI. (`w/crlf` 1474 → 0.)
2. **A1** — the over-broad `template_exercises` test now allows the bounded
   tail-vacuum (`.gte('order_index')`, diagnose b3c8d2) and still forbids the
   lossy blanket delete-then-insert (diagnose a8b2c7).
3. **A2/A4** — refreshed 36 stale SoT-registry citations to the post-refactor
   symbols; `SyncService.*` sync_methods → bare names.
4. **A3** — allowlisted `check_hooks_installed.dart` in CI (runners have no hooks).
5. **A6** — new `check_ci_flutter_version.dart` asserts CI == Vercel Flutter pin.
6. **A7** — release builds now FAIL (not silently debug-sign) without
   `key.properties` — the +28/+32/+33 "won't install over" cross-key-update trap.

## Verification
`git ls-files --eol` → `w/lf`; `flutter analyze` clean; the four formerly-failing
gates/test now PASS locally on the LF tree; full CI green on push (all 5 jobs).

## See also
- `.gitattributes`, `scripts/check_ci_flutter_version.dart`
- `android/app/build.gradle.kts` (release-signing throw)
- The CI Flutter pin bump shipped earlier as merge `afa69c2`.
