---
bug_id: b7e4c1
date: 2026-08-09
batch: train-signout-notif-bugs
status: fixed
blast_radius: account
symptom: |
  TWO defects on the auth/session path, both reported by the founder from live
  web on 2026-08-05, both fixed here because they share the same root class —
  an unbounded or ambiguous state read during a transition.

  (1) SIGN-OUT LANDS ON ONBOARDING. Tapping SIGN OUT sometimes routed to the
  ONBOARDING flow instead of the sign-in screen. Intermittent, not constant.

  ROOT CAUSE: `AuthNotifier.signOut()` tears down in the order
  clearAllData() → deleteAllFilesForCurrentUser() → auth.signOut() →
  unbindSessionIdentity(). Between step 1 and step 3 the app is simultaneously
  AUTHENTICATED and `onboarding_completed == false` — not because the user never
  onboarded, but because the box holding that flag was just wiped.
  `_authRedirect` read that `false` at face value and took its `!isOnboarded`
  branch → `/onboarding`. It is intermittent only because GoRouter has no
  `refreshListenable` on auth state here, so whether a redirect happens to
  evaluate inside that window is timing-dependent.

  The stale doc comment on signOut() actively misled: it claimed "Sign out
  BEFORE clearing Hive so the router never sees authenticated + !onboarded" —
  which the code has NOT done since 2026-04-28 (217a8cbd0, the cross-account
  file-leak fix). The comment described an intent the ordering had already
  abandoned, and the window it warned about was real and open.

  (2) RESTORE HANGS FOREVER. RestoringScreen sat on "Pulling your dispatch"
  indefinitely. There was NO timeout anywhere in the restore chain — verified by
  `grep -c '\.timeout('` returning 0 for sync_service.dart, supabase_service.dart
  AND auth_session_bootstrapper.dart. One wedged Supabase call blocked the entire
  ~30-op fan-out forever. RestoringScreen's 15s/30s timers are pure UI copy and
  were never wired to restore progress, so they could not end it either. The
  wedge class also left NO telemetry trace at all.
concept: signout_teardown_window_and_restore_op_ceiling
sot_registry_entry: signout_teardown_window_and_restore_op_ceiling
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier.signOutInProgress — static flag; the ONLY writer of the teardown-window signal", line: 427 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signOut() — sets the flag true before teardown", line: 462 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signOut() finally — clears the flag; a finally, not a trailing assignment, so an escaping error cannot strand it ON", line: 485 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreOpTimeout — the 45s per-op ceiling constant", line: 1996 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "applyRestoreCeiling — applies the ceiling, or returns the task verbatim when the kill-switch is engaged", line: 2015 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreFailureReason — maps a TimeoutException to its own telemetry reason", line: 2027 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "postSessionRedirect — tests signOutInProgress FIRST, before the ambiguous onboarding read", line: 743 }
  - { file: lib/core/router/app_router.dart, method_or_widget: "_authRedirect — delegates its authenticated-and-session-open tail to the pure function", line: 709 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_safeRestoreOp — awaits through applyRestoreCeiling and reports via restoreFailureReason", line: 2037 }
hive_key_prefix: onboarding_completed
hive_key_formula: "onboarding_completed read via MigratedKey.readWithDefault<bool>(..., false) from the per-user userBox; `disable_restore_op_timeout` read from the SHARED configBox (a device-level kill-switch, deliberately not user-scoped)"
sync_methods: []
restore_methods: [_safeRestoreOp]
cloud_table: users
cloud_columns: [id]
contract_test_path: test/contracts/signout_router_guard_behavioral_test.dart
ist_handling:
  - "Not applicable. Neither fix forms a date key, writes a cloud `date` column, or resets a counter. The 45s ceiling is a DURATION, not a wall-clock time, so it is timezone-independent by construction."
provider_invalidations: []
telemetry_op_types:
  success: [restore_op_done]
  failure: [sync_service_restore_op_timeout, sync_service_safe_restore_op]
cross_account_guard: |
  Load-bearing here, and the reason the teardown ORDER could not simply be
  flipped back to match the stale comment.

  `clearAllData()` clears the 7 user-scoped boxes through `wrapUserScopedBox`,
  which THROWS when the caller is unauthenticated with a non-null owner. End the
  Supabase session first and all 7 clears throw. Each is caught independently
  (user_repository.dart), so teardown still completes via the shared boxes plus
  HiveUserSession.deleteAllFilesForCurrentUser() — but every sign-out would then
  report 7 failures, fire 7 recordNonFatal events, and return
  ClearResult.hasFailures. Two live recovery paths key off exactly that signal
  (_ensureLocalUser, and main.dart's interrupted-logout completion), so flipping
  the order would drown a REAL partial-clear alarm in permanent noise.

  The ordering therefore stays and the AMBIGUITY is resolved instead. That is
  the whole design decision behind signOutInProgress.
forbidden_patterns_checked:
  - "No `--no-verify`; pre-commit ran clean."
  - "No raw `Hive.box(` — the kill-switch read goes through HiveService.instance.configBox and is wrapped in try/catch so a pure unit test with no Hive falls back to BOUNDED (the safe direction)."
  - "No new `.from().select()` column reference — check_schema_column_refs.dart unaffected."
  - "Kill-switch present per §4.6: `disable_restore_op_timeout` restores the verbatim unbounded await. The old path stays reachable and is proven byte-identical by a test."
  - "signOutInProgress is set/cleared in a try/finally, never a bare assignment pair — a stranded ON flag would pin the whole app at /sign-in until process restart."
proposed_fix: |
  (1) SIGN-OUT. Add `AuthNotifier.signOutInProgress`, a static bool (NOT a
  Riverpod provider — `_authRedirect` is a plain static evaluated synchronously
  during navigation with no `ref` in scope; same constraint that makes
  HiveUserSession.currentOwnerFullId static). Set it true before teardown, clear
  it in a `finally`. Extract `_authRedirect`'s authenticated-and-session-open
  tail into the pure, `@visibleForTesting` `AppRouter.postSessionRedirect(...)`
  — same pattern as the existing `shouldGateOnSessionOpen` — and test
  signOutInProgress FIRST, before the ambiguous onboarding read. Rewrite the
  stale doc comment to say why the order CANNOT be flipped.

  (2) RESTORE. Add `SyncService.restoreOpTimeout = 45s` and route
  `_safeRestoreOp`'s await through `applyRestoreCeiling`. Report a timeout under
  its own reason, `sync_service_restore_op_timeout`, distinct from
  `sync_service_safe_restore_op`.

  The 45s is deliberately GENEROUS: it unsticks a WEDGED call, it is not a
  latency budget. A genuinely slow op on a bad Indian mobile connection must
  still be allowed to finish.

  Deliberately NOT done: making the RestoringScreen "Continue" button cancel the
  restore. `cancelInflightRestore()` is already correctly wired
  (restoring_screen.dart) and making Continue abort would kill working restores
  that are seconds from completing.
regression_test_planned: |
  test/contracts/signout_router_guard_behavioral_test.dart — 11 tests. The
  headline case (signOutInProgress + isOnboarded false) must return '/sign-in'
  and explicitly NOT '/onboarding'. A five-test "flag OFF" group proves every
  pre-existing branch is byte-identical, so the guard is additive.
  MUTATION-PROVEN: removing the `if (signOutInProgress)` branch turns 4 tests
  red and the headline one returns '/onboarding' — the founder's exact symptom.

  test/contracts/restore_op_timeout_behavioral_test.dart — 9 tests under
  fakeAsync. Asserts BOTH sides of the boundary (still waiting at 44s, aborted
  at 46s), that the kill-switch restores unbounded behaviour across 10 simulated
  minutes, that a timeout frees the awaiter WITHOUT cancelling the underlying
  request, and that a real failure still propagates. MUTATION-PROVEN: dropping
  the ceiling turns 4 red, including the never-completes case.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on the changed set; 20/20 across the two new test files, 58/58 across the batch." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The ambiguous read IS a Hive read (onboarding_completed via MigratedKey); the truth table covers both its values under both flag states." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud write; sign-out and restore-read only." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function in b7e4c1 (the EF changes in this batch belong to e3b9d7)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron participates in sign-out or client restore." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; restore reads use the existing authenticated session." }
  - { tier: 9, name: storage, status: verified, evidence: "deleteAllFilesForCurrentUser remains step 2 of teardown, unchanged in order and behaviour — the flag wraps the sequence without reordering it." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Supabase Auth is called identically; only the surrounding flag and the await ceiling changed." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Sign-out chain traced end-to-end: signOut() → clearAllData → deleteAllFiles → auth.signOut → unbind, with _authRedirect reading the flag at every redirect evaluation in between. Restore chain traced: _safeRestoreOp → applyRestoreCeiling → telemetry reason. Both writers and readers named by file:line above." }
impact_analysis: |
  BLAST RADIUS account — sign-out and restore are per-account session paths, and
  a mis-route during teardown was the vector for the Test #10.1 cross-account
  data leak class (routing a half-cleared session past /onboarding into /home).

  WHAT IMPROVES: sign-out lands on /sign-in deterministically. A wedged restore
  op now aborts after 45s and the fan-out continues, instead of the screen
  hanging forever with no trace.

  RISK OF FIX (1): a stranded signOutInProgress would pin the app at /sign-in
  until restart. Mitigated by the `finally` and asserted by a test that the flag
  defaults false. The flag is process-local, so a crash mid-teardown resets it.

  RISK OF FIX (2): a 45s ceiling could abort a slow-but-healthy op on a poor
  connection. This is the real trade and why the value is generous rather than
  tight; the test pins BOTH sides of the boundary so a future tightening is a
  visible, deliberate edit rather than a silent regression. The kill-switch
  restores the old unbounded behaviour verbatim.

  IMPORTANT SEMANTIC, pinned by test: a Dart `.timeout()` does NOT cancel the
  underlying request — it frees the AWAITER. That is exactly what was needed,
  but "timed out" must never be read as "the server stopped". Ops with a Hive
  write on the far side may still complete after we stopped waiting.

  NOT FIXED HERE: the absence of a `refreshListenable` on auth state, which is
  what makes the window timing-dependent in the first place. Closing the
  ambiguity is the correct minimal fix; re-architecting router refresh is a
  materially larger change with its own risk surface and no additional benefit
  to this symptom.
related_bugs: [a3f6d9, d4e8a2, c5a1f2]
recurrence: |
  Two known classes, one instance each.

  The sign-out defect is the "ambiguous default read as fact" class: a Hive read
  that returns its DEFAULT during a transition window, indistinguishable from a
  genuine value. Same shape as a3f6d9 (restoring_screen local onboarded flag not
  stamped) and as the FIX-1 Part A work that made owner-null reads SERVE EMPTY
  rather than throw — which is precisely what made the default reachable here.
  The reusable lesson: whenever a read can return its default because state is
  MID-TEARDOWN rather than absent, the transition itself needs a signal.

  The restore wedge is the "no ceiling anywhere on a fan-out" class — new to
  this repo by evidence (the grep for `.timeout(` returned 0 across all three
  restore-path files). Recording it so the next restore-path change checks for a
  bound rather than assuming one exists.
---

# Sign-out redirect race + unbounded restore op

Full writer/reader map, the 12-tier check, and the design reasoning are in the
YAML above.

## Why the teardown order stays

This is the load-bearing decision. The stale comment claimed the opposite
ordering and the obvious "fix" was to restore it. That would have been wrong:
with the session ended first, all 7 user-scoped box clears throw, and every
sign-out would permanently report `ClearResult.hasFailures` — the exact signal
two live recovery paths use to detect a REAL partial clear. The choice was
between a race and a permanently-blinded alarm. Closing the ambiguity keeps both.

## Why a static, not a provider

`_authRedirect` is a plain static function evaluated synchronously during
navigation, with no `WidgetRef` in scope. A Riverpod provider is unreadable from
there. The same constraint already made `HiveUserSession.currentOwnerFullId`
static. A test documents this so a future refactor to a provider fails loudly
rather than silently breaking the guard.
