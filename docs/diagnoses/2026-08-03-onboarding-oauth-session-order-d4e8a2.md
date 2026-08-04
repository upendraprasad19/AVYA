---
bug_id: d4e8a2
date: 2026-08-03
batch: onboarding-oauth-session-fix (Unit 1 of the 4-unit batch that succeeded terms-accepted-fix, 2026-08-03)
status: fixed
blast_radius: account
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
  (:272-561) — the only writer touched. Its first Hive write
  (_userRepo.saveProfile(profile), :414) is now preceded by
  HiveUserSession.ensureOpenedForCurrentSession() (:409), the same idempotent
  helper SyncService._ensureSessionOpen and 8+ other call sites already use
  (lib/core/services/hive_user_session.dart:123-139). No other writer changed.
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
  (hive_user_session.dart:133-134) — this fix adds a new CALLER of that
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
  test/contracts/onboarding_hive_session_open_before_write_test.dart — 4
  tests (A, B, C1, C2). Three are behaviorally grounded against real Hive;
  the fourth (C2) is a deliberate source-pin on ORDERING that complements —
  rather than substitutes for — C1's behavioral coverage. Group A
  behaviorally proves the FAILURE MODE on
  the branch onboarding can actually reach: an AUTHENTICATED user whose Hive
  session was never opened gets GuardedBox.empty (guarded_box.dart:333), and
  the write then throws StateError('GuardedBox.empty: rawBox unavailable...')
  from GuardedBox.rawBox (:172) — reached because HiveService.userBox
  (hive_service.dart:226) unwraps to .rawBox before any put. The assertion
  pins that MESSAGE, not merely the StateError type: all three owner-null
  failures throw StateError, so a type-only matcher cannot distinguish this
  from the UNAUTHENTICATED branch (:335) that onboarding never hits — round 2
  proved a type-only matcher passes green while silently pinning the wrong
  branch. Group B behaviorally proves the FIX's causal mechanism by calling
  the REAL guard (ensureOpenedForCurrentSession, via the
  debugCurrentUidResolverForTests seam) and asserting the same write then
  succeeds and round-trips through real Hive. Group C1 is the BEHAVIORAL
  end-to-end proof: it drives the real completeOnboarding() through a
  ProviderContainer and asserts the Hive session was opened AND the profile
  landed. Group C2 source-pins that the guard precedes the write. Both
  DISCRIMINATE, verified by negative control (deleting the guard call fails
  C1 with "Expected: 'b00b1e5e-...' / Actual: <null>" plus captured telemetry
  naming the real production failure — guarded_box_null_owner_authenticated
  then GuardedBox.empty — and fails C2 with "Expected: a value greater than
  or equal to <0> / Actual: <-1>"; restoring makes all 4 pass again).
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "1 lib/ file changed (onboarding_provider.dart, +8/-0 net lines: 1 import + a defensive call + its explanatory comment). `flutter analyze` on the 2 touched files (the lib/ file + the new test) reports 0 issues in onboarding_provider.dart and 2 pre-existing-pattern infos (depend_on_referenced_packages for path_provider_platform_interface + plugin_platform_interface) in the new test file, identical in kind to the same 2 infos pro_phase_advance_behavioral_test.dart already carries for the same imports (non-fatal, matches established pattern)." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "3 behavioral tests run against real Hive boxes in a temp dir (Groups A, B, C1), asserting the actual throw, the actual successful round-trip through ProfileWriteService.updateProfile -> HiveService.instance.userBox -> the real namespaced Hive box, and (C1) that the real completeOnboarding() opens the session and lands its profile write. A 4th test (C2) source-pins the guard-before-write ORDERING." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No DDL, no column touched." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No backfill. This fix addresses a risk that was never live (see symptom) — there is no historical data to repair." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "Client-only change, no supabase/functions/ file touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron reads or writes userBox['profile']." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No policy changed." }
  - { tier: 9_storage, status: not_applicable, evidence: "No bucket or object touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12_client_server_contract, status: verified, evidence: "Traced by direct read: completeOnboarding (onboarding_provider.dart:409,420) -> ProfileWriteService.updateProfile (profile_write_service.dart:60-77) -> HiveService.instance.userBox.put (via wrapUserScopedBox) -> unawaited SyncService.instance.syncProfileNow. The chain is unchanged by this fix except for the new precondition at :409; the cloud contract shape is identical to before." }
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
  (`onboarding_provider.dart:550-560`) is **not** a b3f9e7-style silent
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
[`onboarding_provider.dart:409`](lib/features/onboarding/providers/onboarding_provider.dart:409)
`await HiveUserSession.ensureOpenedForCurrentSession();` — inserted
immediately before the method's first Hive write at
[`:414`](lib/features/onboarding/providers/onboarding_provider.dart:414).
`ensureOpenedForCurrentSession` is the same helper 8+ other call sites already
rely on (`hive_user_session.dart:123-139`): it is a fast no-op when the
session is already open for the current user, so it changes nothing on the
path that is already safe today.

## Verification

`flutter test test/contracts/onboarding_hive_session_open_before_write_test.dart`
— 4/4 passing (A, B, C1 behavioral, C2 source-pin). `flutter analyze` on every
touched file — exit 0; the only remaining output is pre-existing
`depend_on_referenced_packages` infos on imports that were already present
before this batch.

**Negative control, re-run independently in BOTH review rounds (never taken
on the previous author's word).** The guard line was physically removed from
`completeOnboarding` — deleted, not commented, since an early draft showed a
commented-out line leaves the substring intact and silently keeps a source-pin
green — and the suite re-run. After round 2's fixes, BOTH failing modes fire:

- **C1 (behavioral)** — `Expected: 'b00b1e5e-…' / Actual: <null>`: the Hive
  session was never opened. Its captured telemetry names the exact production
  failure mode, which is the point of the test:
  `guarded_box_null_owner_authenticated: root=userBox authUid=b00b1e5e`
  followed by `onboarding_complete_failed: Bad state: GuardedBox.empty: rawBox
  unavailable during auth/Hive disagreement`.
- **C2 (source-pin on ordering)** — `Expected: a value greater than or equal
  to <0> / Actual: <-1>`, "the defensive guard call is missing".

The file was then restored and verified **md5-identical** to its
pre-experiment copy, and the suite re-run green (4/4). So the fail-without /
pass-with property is confirmed by execution on the real runtime path, not
assumed and not merely source-matched.

## Round-1 independent review (context-blind, per CLAUDE.md §4.12)

This batch was originally merged to local `main` (`f0b98c8b`) believing it was
`feature`-tier. It is `account` — `lib/features/onboarding/**` is pinned
`account` in `docs/blast_radius.yaml:185`, confirmed by re-running
`blast_radius_from_diff.dart` over the real merge diff. §4.12's ×2 independent
review therefore applies and had not been run. It was run retroactively, before
any push. (The same gap was independently detected by another session on this
machine, whose unrelated push CI's keystone gate correctly blocked — filed as
OI-87. Authoring a record without actually running the review would have been a
false attestation; the review below is real.)

Verdict: NOT CONVERGED. 2 blocking + 4 should-fix, all resolved in this round.

**B1 — duplicated comment block.** The 6-line explanatory comment above the
guard was pasted twice, verbatim. No behavioral impact; removed.

**B2 — no plan-review record.** `docs/plan-reviews/onboarding-oauth-session-fix.md`
did not exist, which fails the merge-to-main keystone gate at `account` tier.
Authored as part of this round.

**S1 — the diagnose-doc's own `blast_radius` said `feature`.** Factually wrong
against the registry, and `validate_diagnose_doc.dart` does not cross-check the
field against `blast_radius_from_diff.dart`, so nothing caught it. Corrected to
`account`.

**S2 (most material) — the test pinned a failure branch onboarding can never
reach.** `wrapUserScopedBox` has TWO owner-null branches
(`guarded_box.dart:320-338`): UNAUTHENTICATED throws
`StateError('HiveUserSession not opened …')` at `:335`; AUTHENTICATED-but-owner-null
returns `GuardedBox.empty` at `:333`, whose write methods throw a *different*
error at `:88-90`. An onboarding user is authenticated by definition, so only
the second is production-reachable — but the pure-VM harness never initialises
Supabase, so the original test silently took the first. It asserted a real
throw, from the wrong cause. Group A now drives the authenticated branch via
the existing `debugAuthUidResolverForTests` seam.

**S3 — only a source-grep actually detected the regression. RESOLVED, but
only after round 2 caught round 1 giving up too early.** Groups A and B
exercised `HiveUserSession`/`ProfileWriteService` generically and never touched
`completeOnboarding`, so both passed identically with and without the fix; the
sole regression-detecting assertion was a text search for the guard call, which
rule 21 classes as presence-only.

Round 1 attempted the right replacement — drive the real `completeOnboarding()`
through a `ProviderContainer` and assert the profile actually landed — hit an
opaque `_AssertionError` from inside the method, and **wrote it off as an
undiagnosable pure-VM harness limitation**, documenting that conclusion here
and in the test file. Round 2 refuted it. The reasoning round 1 used ("the
stack is discarded, so the assertion cannot be identified without adding stack
logging to production code") was wrong on the decisive point: `completeOnboarding`'s
own catch passes `e.toString()` to `ErrorTelemetry.logEvent`
([`onboarding_provider.dart:550-554`](lib/features/onboarding/providers/onboarding_provider.dart:550)),
`AssertionError.toString()` embeds the failing file:line and condition, and
[`ErrorTelemetry.debugOnLogEventForTests`](lib/core/services/error_telemetry.dart:69)
exists for exactly this purpose. Reading it took **one run** and zero
production changes, and produced:

> `'package:icanbefitter/core/constants/fitness_goals.dart': Failed assertion:`
> `line 128 pos 7: 'false': Unknown fitness goal token "fat_loss".`

Round 1's own test data was invalid — `'fat_loss'` is not a token; the real one
is `'lose_fat'` ([`fitness_goals.dart:74`](lib/core/constants/fitness_goals.dart:74)).
The "environmental blocker" was a typo in the test. With the token corrected,
the behavioral test works, and it now ships as **Group C1** alongside the
ordering source-pin **C2** (they catch different regressions: C1 proves the
guard RAN; C2 pins that it runs BEFORE the write). C1 also installs the
telemetry seam itself, so any future failure there is self-diagnosing rather
than opaque.

**The B-pass then caught the same reflex one level down, in C1's own
scaffolding.** C1 was first written with a bare `catch (_) {}` around
`completeOnboarding()`, commented "cannot finish in a pure-VM harness". That
comment was wrong AND the swallow was dangerous: it would hide a genuine
session-ordering regression while instructing the next reader not to look.
Removing the catch and asserting on the swallowed telemetry immediately
surfaced what it had been hiding — `onboarding_complete_failed: HiveError:
Box not found`, because plan generation needs a seeded exercise library this
test deliberately does not build. So the honest shape is neither "nothing was
swallowed" (false) nor a blind catch (blind): C1 asserts that no swallowed
failure is of the **session-ordering class** (`GuardedBox` / `HiveUserSession`),
which is precisely the regression this file exists to catch, while tolerating
the unrelated harness limitation.

The durable lesson, recorded because the recovery is the instructive part: an
opaque failure is a reason to find the seam that makes it legible, not a
licence to document it as impossible — and a `catch (_) {}` paired with a
confident comment is the same move wearing different clothes. Same family as
`feedback_source_grep_false_confidence.md` — a plausible-sounding reason to
accept weaker coverage is exactly when to push harder.

Also materially improved: Group B now calls the REAL guard
(`ensureOpenedForCurrentSession`) instead of standing in for it with
`openForUser`. That required one new production seam,
`HiveUserSession.debugCurrentUidResolverForTests`, mirroring the established
`debugAuthUidResolverForTests` (`guarded_box.dart:227`) pattern —
`ensureOpenedForCurrentSession` reads `SupabaseService.currentUser` directly
and had no seam of its own.

**S4 — a stale comment actively contradicted this fix.**
`app_router.dart`'s `shouldGateOnSessionOpen` doc justified onboarding's
exemption from the session gate with "Onboarding self-navigates pre-session, so
it is exempt (its own writes open/own the boxes via the sign-up bootstrap)" —
the precise claim this diagnose disproves, sitting exactly where a future
refactorer would look. Rewritten to cite the guard as the actual reason, with
an explicit warning not to weaken it on the assumption the router gates for it.

### Round-2 independent review (runs on the round-1-hardened state, per §4.12)

Verdict: NOT CONVERGED. 1 blocking + 3 should-fix — **every one of them
introduced by round 1's own fixes**, none present in the original. The
production change itself (the guard) was re-verified sound.

**B2-1 (blocking) — round 1 fixed S2 and simultaneously removed the only
thing keeping it fixed.** Rewriting Group A, round 1 replaced
`isA<StateError>().having(message, contains('HiveUserSession not opened'))`
with a bare `isA<StateError>()`. But ALL THREE reachable owner-null failures
throw `StateError` (`guarded_box.dart:335`, `:172`, `:87-91`), so a type-only
matcher cannot distinguish the production-reachable AUTHENTICATED branch from
the unreachable UNAUTHENTICATED one. The reviewer proved it: deleting the
`debugAuthUidResolverForTests` line from `setUp` — reproducing exactly the S2
defect — left the suite GREEN while pinning the wrong branch again. Fixed by
pinning the message on `'GuardedBox.empty'`. This is the repo's own
"a green check is only as wide as its input set" class, 7th instance.

**B2-2 — the S2 comment named the wrong throw site.** It cited the write
methods' `_emptyStubWriteError` (`guarded_box.dart:87-91`); the actual throw
on this path is `GuardedBox.rawBox` (`:172`), because `HiveService.userBox`
(`hive_service.dart:226`) unwraps to `.rawBox` before any `put` is reached.
The write-method site is dead code on this path — a future reader hardening it
per that comment would harden nothing.

**B2-3 — round 1's own edits silently invalidated line citations, and no gate
catches it.** Deleting the 6 duplicated comment lines (B1) and adding 12 lines
to `hive_user_session.dart` (the new seam) shifted: the guard/write to
`:409`/`:414` (cited as `:415`/`:420` in 6 places here), `completeOnboarding`
to `272-561` and `_syncOnboardingAndPostActions` to `570-637` (the SoT
registry still said `272-567` / `576-643`), and
`ensureOpenedForCurrentSession` to `123-139` (cited as `111-126`). Confirmed
non-blocking at the gate level — `check_sot_registry_parity.dart` only
bounds-checks `end <= file length`, and the stale values are in-bounds — so
this would have shipped silently wrong.

**And the round-2 sweep was itself incomplete — the B-pass caught that.**
Round 2 fixed only the `onboarding_provider.dart` citations and wrote "All
corrected", which was a false attestation. The new seam shifted
`hive_user_session.dart` too (+6 below line 34, then +13 below ~116 — NOT a
uniform offset), invalidating six further registry citations that had been
*correct* before this batch: the three `notifyUserChanged()` writer lines
(255→268, 387→400, 424→437), `deleteAllFilesForCurrentUser`
(389-410→402-423), and two lifecycle ranges (77-240→**83**-253 — note the
start shifts +6, not +13, because it sits above the second hunk). One live
gate script also carried a stale pointer in its allow-list rationale
(`scripts/cqrs_query_naming_lib.dart`, `hive_user_session.dart:208`→`:221`).
All now corrected and re-verified by reading the cited lines, not by
assuming the offset.

**B2-4 — round 1's S3 "blocker" was refuted, and the refutation produced the
real fix.** See the S3 entry above: the claim that the assertion was
undiagnosable without production changes was false, the actual cause was
round 1's own invalid test token, and the behavioral test now ships as C1.

**Round 2 verified and found sound:** the new production seam
(`hive_user_session.dart:41`) — grep-confirmed the only writes repo-wide are
the test's own `setUp`/`tearDown`/`tearDownAll`, the only read is same-library,
production leaves it null so behavior is verbatim-unchanged via the `??`
fallback; it is *stronger* than both local precedents
(`debugAuthUidResolverForTests`, `GuardedBox.testBypassOwnership`), which are
un-annotated public mutable statics — a question already adjudicated in this
repo as `false_alarm (local convention)`
(`docs/reviews/fix-session-open-race-bpass.md` F6). A seam/Supabase mismatch
cannot silently cross accounts: it trips the disagreement guard
(`guarded_box.dart:244-254`, HIGH-priority telemetry) and `_assertOwnership`
(`:80-84`, which has no seam) → `HiveOwnershipException`. Test
order-independence also confirmed (`setUp`'s `closeAll()` prevents a
randomized order from diverting Group A into the auto-open-fallback branch).

**Noted, out of scope, worth filing separately:** `GuardedBox.empty`'s designed
"reads serve empty, writes throw loud" semantics (the b8e3f1 fix) are bypassed
by all 7 plain `Box` getters in `hive_service.dart:225-231`, which call
`.rawBox` and therefore throw on *reads* too. Pre-existing, unrelated to this
batch, not introduced here — flagged for the board rather than fixed in a
review of an unrelated fix.

**Verified and found sound (no change needed):** the guard's placement (no
user-scoped write precedes it; the only earlier Hive touch is the shared
`configBox`); `ensureOpenedForCurrentSession`'s idempotency and cross-account
safety (same uid → early return; different uid → closes the prior session
first, which is correct, not a leak; no auth → clean null; catches every
`openForUser` throw so it cannot fail the call site); fix completeness across
onboarding (every other Hive writer there runs after the guard or
post-onboarding); and the entry-path audit — with one addition the reviewer
supplied and this doc now records: beyond the `RestoringScreen` argument, a web
deep-link or reload straight onto `/onboarding/*` cannot reach a session-less
write either, because `SupabaseService.initialize()` has exactly one call site
(`splash_screen.dart:122`), so such a load finds `isAuthenticated == false` and
is bounced to `/sign-in`.
