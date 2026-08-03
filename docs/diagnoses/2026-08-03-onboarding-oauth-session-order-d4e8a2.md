---
bug_id: d4e8a2
date: 2026-08-03
batch: onboarding-oauth-session-fix (Unit 1 of the 4-unit batch that succeeded terms-accepted-fix, 2026-08-03)
status: fixed
blast_radius: feature
symptom: >
  NOT a live incident — a static-tracing risk flagged in b3f9e7's own "Known
  residual gap" section, investigated and closed here. Nothing under
  lib/features/onboarding/ called HiveUserSession.openForUser or
  ensureOpenedForCurrentSession, so completeOnboarding()'s first Hive write
  had no defensive guard of its own. It stayed safe today only because of an
  INCIDENTAL ordering property of a different screen: RestoringScreen
  unconditionally starts SyncService.restoreFromCloudForUser() (whose first
  substantive line opens the Hive session) in parallel with destination
  resolution, before the brand-new-user branch can navigate to onboarding — so
  by the time a user clicks through 6 onboarding screens, the session is
  already open. Nothing awaits or joins that future before allowing
  navigation, so a future RestoringScreen refactor could silently reintroduce
  the same StateError b3f9e7's email-signup write hit for 2.5 months, with no
  test catching it.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at (docs/sot_registry.yaml:3847) — no
  new concept introduced; this fix hardens the existing registered writer with
  an idempotent defensive precondition, so no new registry entry is needed.
writers: >
  lib/features/onboarding/providers/onboarding_provider.dart completeOnboarding
  (:272-567) — the only writer touched. Its first Hive write
  (_userRepo.saveProfile(profile), :420) is now preceded by
  HiveUserSession.ensureOpenedForCurrentSession() (:415), the same idempotent
  helper SyncService._ensureSessionOpen and 8+ other call sites already use
  (lib/core/services/hive_user_session.dart:111-126). No other writer changed.
readers: >
  Not applicable to this fix — no reader changed. The write's existing readers
  (userProfileProvider, RestoringScreen's post-auth classification, etc.) are
  unaffected; this fix only changes whether the write can be REACHED without
  throwing, never what it writes.
hive_key_prefix: userBox key 'profile' (existing, unchanged).
hive_key_formula: not_applicable — 'profile' is a single fixed userBox key.
sync_methods: >
  Unchanged. ProfileWriteService.updateProfile still fires
  unawaited(SyncService.instance.syncProfileNow(userId)) after the Hive write,
  exactly as before this fix.
restore_methods: not_applicable — no restore path touched.
cloud_table: user_profile
cloud_columns: >
  No column added, dropped or renamed. This fix is Hive-side session ordering
  only; the cloud sync payload shape is unchanged.
contract_test_path: test/contracts/onboarding_hive_session_open_before_write_test.dart
ist_handling: not_applicable — no date-key or timestamp logic touched.
provider_invalidations: not_applicable — unchanged from before this fix.
telemetry_op_types: >
  None added. HiveUserSession.ensureOpenedForCurrentSession already emits its
  own ErrorTelemetry.recordNonFatal(reason: 'ensure_session_open') on failure
  (hive_user_session.dart:120-121) — this fix adds a new CALLER of that
  existing, already-telemetered helper, not new telemetry.
cross_account_guard: >
  Strengthens it. HiveUserSession.ensureOpenedForCurrentSession() is the same
  helper the cross-account guard family already relies on elsewhere
  (RankService, SubscriptionService, splash startup). Calling it defensively
  in completeOnboarding cannot weaken the guard — it is idempotent (returns
  immediately if `_currentOwnerFullId == userId`) and a no-op when there is no
  live Supabase session (returns null, falls through to the pre-existing
  StateError path unchanged).
forbidden_patterns_checked: >
  - Container(color:+decoration:) — n/a, no widget touched.
  - unawaited() without an error sink — n/a, the new call is `await`ed, not
    fire-and-forget.
  - .functions.invoke without FunctionException handling — n/a, no invoke.
  - Source-grep without stripping comments — Group C's presence check matches
    against the LIVE call site text; verified by deliberately deleting the
    call (not commenting it — an earlier draft of this test commented the
    line out and the substring survived inside the comment, silently keeping
    the test green; caught before landing and fixed by using a genuine
    deletion for the negative control instead) and re-running to confirm a
    real failure, then restoring.
  - BuildContext across an async gap — n/a, no BuildContext in this method.
proposed_fix: >
  One idempotent defensive call: HiveUserSession.ensureOpenedForCurrentSession()
  inserted immediately before completeOnboarding's first Hive write. No
  behavior change on the path that is already safe today (RestoringScreen's
  incidental early open) — the call is a fast no-op when
  `_currentOwnerFullId == userId` already. Only changes behavior on the
  hypothetical future-regression path this doc exists to guard against.
regression_test_planned: >
  test/contracts/onboarding_hive_session_open_before_write_test.dart — 3
  tests, all behaviorally grounded against real Hive (not source-grep-only;
  see the file's own header for why Group C is presence-only and why that is
  honest rather than a gap). Group A behaviorally proves the FAILURE MODE:
  writing the profile before HiveUserSession.openForUser has run throws
  StateError('HiveUserSession not opened...') from
  guarded_box.dart wrapUserScopedBox (:335) — the exact class of throw that
  silently killed b3f9e7's write for 2.5 months. Group B behaviorally proves
  the FIX's causal mechanism: opening the session first lets the write
  succeed and round-trip through real Hive. Group C source-pins that the
  guard call actually precedes the write inside completeOnboarding — verified
  to DISCRIMINATE by negative control (deleting the guard call makes Group C
  fail: "Expected: a value greater than or equal to <0> / Actual: <-1>";
  restoring it makes all 3 pass again).
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "1 lib/ file changed (onboarding_provider.dart, +8/-0 net lines: 1 import + a defensive call + its explanatory comment). `flutter analyze` on the 2 touched files (the lib/ file + the new test) reports 0 issues in onboarding_provider.dart and 2 pre-existing-pattern infos (depend_on_referenced_packages for path_provider_platform_interface + plugin_platform_interface) in the new test file, identical in kind to the same 2 infos pro_phase_advance_behavioral_test.dart already carries for the same imports (non-fatal, matches established pattern)." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "3 behavioral tests run against real Hive boxes in a temp dir (Group A/B), asserting the actual throw and the actual successful round-trip through ProfileWriteService.updateProfile -> HiveService.instance.userBox -> the real namespaced Hive box." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No DDL, no column touched." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No backfill. This fix addresses a risk that was never live (see symptom) — there is no historical data to repair." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "Client-only change, no supabase/functions/ file touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron reads or writes userBox['profile']." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No policy changed." }
  - { tier: 9_storage, status: not_applicable, evidence: "No bucket or object touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12_client_server_contract, status: verified, evidence: "Traced by direct read: completeOnboarding (onboarding_provider.dart:415,420) -> ProfileWriteService.updateProfile (profile_write_service.dart:60-77) -> HiveService.instance.userBox.put (via wrapUserScopedBox) -> unawaited SyncService.instance.syncProfileNow. The chain is unchanged by this fix except for the new precondition at :415; the cloud contract shape is identical to before." }
impact_analysis: >
  Zero user-visible impact today — confirmed via the same file:line trace
  b3f9e7's own residual-gap note called for, and the premise (RestoringScreen
  always opens the session first) held up under direct verification, not
  assumption. What this fix removes is a LATENT risk: a plausible-looking
  future simplification of RestoringScreen (e.g. moving the brand-new-user
  navigation ahead of kicking off restoreFromCloudForUser, which reads as a
  harmless reordering) could reintroduce the exact StateError-swallowed-by-
  catch class that diagnose b3f9e7 spent weeks invisible in production. The
  defensive call costs nothing on the already-safe path (idempotent, already
  a no-op) and closes that door structurally rather than by convention.
---

# d4e8a2 — Onboarding's first Hive write had no defensive session-open guard of its own

Unit 1 of the 4-unit batch that succeeded diagnose b3f9e7 (terms-accepted-fix,
2026-08-03). Closes the investigation `task_a3c7b7b3` was spawned to run.

## What was actually wrong

Nothing — today. `docs/diagnoses/2026-08-02-terms-accepted-dead-write-b3f9e7.md`'s
"Known residual gap" section flagged, but explicitly did **not** live-confirm,
a suspicion that brand-new Google OAuth signups might hit the same
dead-Hive-write bug class during onboarding, since
`grep -rn "HiveUserSession.openForUser" lib/features/onboarding/` returns
nothing.

Direct verification (not another guess) traced the actual call graph:

- [`restoring_screen.dart:116-117`](lib/features/auth/screens/restoring_screen.dart:116)
  (`_kickoffRestore`) unconditionally starts
  `SyncService.restoreFromCloudForUser()` in parallel with destination
  resolution, **before** the `switch` that branches to `StartMissionBrief`
  (the brand-new-user case, `:122-129`).
- [`sync_service.dart:1296`](lib/core/services/sync_service.dart:1296) —
  inside `restoreFromCloudForUser`, `await HiveUserSession.openForUser(userId)`
  is the first substantive action, a full 61 lines **before** the method's
  first `_restoreCancelled` check at
  [`sync_service.dart:1357`](lib/core/services/sync_service.dart:1357).
  `cancelInflightRestore()` (called from the `StartMissionBrief` branch)
  cannot unwind a call that already fired.
- Net effect: for every `/restoring` mount, including a brand-new Google
  OAuth signup, the Hive session is opened well before the user can click
  through 6 onboarding screens to reach `completeOnboarding()`.
- Also confirmed: `completeOnboarding()`'s failure path
  (`onboarding_provider.dart:559-567`) is **not** a b3f9e7-style silent
  swallow — it logs `ErrorTelemetry.logEvent('onboarding_complete_failed', ...)`
  and surfaces a visible, retryable on-screen error, so even in the
  hypothetical regression scenario a user would see a "Something went wrong"
  message and a retry button, not silent data loss.

**Why this still needed a fix, not just "false alarm, close the task":** the
protection above is an *incidental ordering property* of `RestoringScreen`,
not an invariant `completeOnboarding()` enforces itself. A future refactor
that looks like a harmless simplification (e.g. navigating the
`StartMissionBrief` branch before kicking off the restore future) could
silently reintroduce the throw with no test catching it — exactly the shape
of change that caused b3f9e7 in the first place (a write moved earlier than
session-open, invisible until 2.5 months of production data confirmed it).

## Related bugs

- **b3f9e7** (2026-08-02) — same bug CLASS (a user-scoped Hive write reachable
  before `HiveUserSession.openForUser`), different call site (email-signup's
  terms-consent write, not onboarding's profile write). That fix relocated
  the write; this fix adds a structural guard so onboarding's write can never
  regress into the same class even if its upstream ordering changes.
- **b8e3f1** (2026-06-21) — adjacent but distinct. b8e3f1 fixed
  `GuardedBox.empty`'s **read** methods to serve empty instead of throwing
  during the owner-null-but-authenticated window. Confirmed by reading
  `guarded_box.dart` directly: `GuardedBox.empty`'s **write** methods
  (`put`/`putAll`/`delete`/`clear`) still throw `StateError` unconditionally
  regardless of read/write intent (`_emptyStubWriteError`, `guarded_box.dart:87-91`)
  — b8e3f1's fix does not and cannot cover onboarding's write path.

## The fix

One idempotent defensive call —
[`onboarding_provider.dart:415`](lib/features/onboarding/providers/onboarding_provider.dart:415)
`await HiveUserSession.ensureOpenedForCurrentSession();` — inserted
immediately before the method's first Hive write at
[`:420`](lib/features/onboarding/providers/onboarding_provider.dart:420).
`ensureOpenedForCurrentSession` is the same helper 8+ other call sites already
rely on (`hive_user_session.dart:111-126`): it is a fast no-op when the
session is already open for the current user, so it changes nothing on the
path that is already safe today.

## Verification

`flutter test test/contracts/onboarding_hive_session_open_before_write_test.dart`
— 3/3 passing. `flutter analyze` on both touched files — 0 issues in the
`lib/` file, 2 pre-existing-pattern infos in the new test file (see
`touched_layers_checked` tier 1).
