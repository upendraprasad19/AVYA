---
branch: google-signin-misroute
date: 2026-08-10
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — Google sign-in → Mission Brief misroute (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Account-tier
(`lib/features/auth/**` :188, `lib/core/services/**` :267 in `docs/blast_radius.yaml`) — confirm
with `scripts/blast_radius_from_diff.dart` at merge time rather than trusting this line. `bpass: pending` — the gate only compels `accepted` at ≥platform, and §4.3 requires the
self-initiated `/code-review` **before the `--no-ff` merge**, which has not been reached: nothing
in this batch is committed. Flip to `accepted` with a real `bpass_review:` path once it runs. It
is recorded as pending rather than pre-filled, because a record citing a review file that does
not exist is the phantom-citation failure this repo has corrected three times already
(`check_writer_reader_drift.dart`, `restore_completeness_test.dart`,
`check_open_issues_reconciled.dart`).

## Scope

`resolveDestination` conflated "the profile read failed" with "this user has no profile", so a
failed read routed a fully-onboarded account into onboarding. Diagnose `c2e9f4`. Four units:

0. Extract two functions from `restoring_screen.dart` to sibling `part` files (Gate 43 headroom;
   also completes OI-88's extraction).
1. `DestinationUnknown` added to the `sealed` destination hierarchy; `ensureFreshToken()` + one
   hard-refresh retry before giving up.
2. The local-evidence predicate extracted to `local_onboarding_evidence.dart` and consulted by
   all three not-onboarded branches, after `ensureOpenedForCurrentSession()`.
3. `completeOnboarding` refuses to overwrite an already-onboarded cloud profile.

## Round 1 — pre-implementation, on the written plan

Ran against the plan document before any code was written. **Four material corrections**, all
folded in:

| # | Finding | Correction |
|---|---|---|
| 1 | "four tests read `restoring_screen.dart` by literal path" — a figure carried in from an earlier session | It is **17**. Verified by grepping for `File(...)` + `readAsStringSync()`. A 4× underestimate of the batch's largest mechanical chunk. |
| 2 | Unit 3 was specified as "before the `user_profile` upsert" in `completeOnboarding` | There is no upsert in that method. It stamps Hive at :399; the cloud write happens later via `sync_profile.dart:255`. Guard moved to the method ENTRY, the only point where both writes are still preventable. |
| 3 | "the evidence read happens before `openForUser`" stated as fact | It is a **race**: `restoreFromCloudForUser` calls `ensureOpenedForCurrentSession()` at `sync_service.dart:454` **without `await`**. Non-determinism makes it worse, and explains why a3f6d9's self-heal passed review and still let this through. |
| 4 | Claimed the `active_workout/` layout as precedent | That layout puts the head file *inside* the folder as `screen.dart`, which would move `restoring_screen.dart` outside Gate 43's `*_screen.dart` regex. Deliberately deviated; documented in the head file. |

Claims re-verified as correct in the same round: `_healAfterRestoreInBackground` is top-level
(hence ref-free by construction); `_AnimatedDots` survives as a same-library part; owner-null
serves `GuardedBox.empty` (`guarded_box.dart:333`); Gate 43 is 800 lines with an allow-list and a
filename regex; blast radius is `account`.

## Round 2 — adversarial verification against ground truth

Ran on the implemented batch: live SQL and `pg_policy` re-queried, every cited file:line re-read,
the a3f6d9-is-in-+38 claim proven by `git merge-base`, and the five-mutation sweep below. It found
and closed two real defects (mutations C and D) plus one stale citation (`line_range: 52-92` on an
89-line file, caught by `sot_registry_completeness_test.dart` — a gate doing exactly its job).

**Two deviations from the §4.12.1 ideal, stated plainly rather than smoothed over:**

1. Round 2 ran on the *implementation*, not on the hardened *plan*. The founder approved the
   corrected plan and directed implementation to start, so the second look landed after the code
   existed. That is a weaker ordering than the rule prescribes — the rule exists precisely because
   corrections introduce defects, which round 1 demonstrated by finding four.
2. Neither round used a **context-blind independent reviewer**; both were self-review by the
   implementing session. §4.12.1 calls for dispatched context-blind reviewers. The mutation sweep
   is the closest thing here to an adversarial check that does not share the author's mental
   model — and it earned that description by reddening zero tests twice, which no amount of
   self-reading had surfaced. The owed `/code-review` B-pass before merge is the genuine
   independent round.

## Adversarial pass — mutation testing (this is what actually caught things)

Five mutations, each applied to the working tree, run, and reverted:

| Mutation | Tests reddened |
|---|---|
| A — `hasLocalOnboardedEvidence` always returns false | 4 |
| B — `StartMissionBrief` branch skips the evidence gate | 1 |
| C — the catch returns `StartMissionBrief` (i.e. re-create `c2e9f4`) | **0 → 1** |
| D — overwrite guard fails CLOSED | **0 → 1** |
| E — `shouldRefuseOnboardingOverwrite` always refuses | 1 |

C and D initially reddened **nothing**. C is the exact revert of the defect this batch exists to
prevent, and no test could see it. D's "fails open" test turned out to exercise the no-session
path, never reaching the catch it claimed to cover.

Both are the `feedback_mistake_guard_without_its_mirror` class — **twice in one batch**. The tests
had been written from the same mental model as the fix, so they asserted what the fix *does*
rather than what its absence looks like. Fixed by adding a behavioral test that drives the real
`resolveDestination` against an unreachable backend, and by extracting
`shouldRefuseOnboardingOverwrite` as a pure decision (the house pattern:
`classifyDestination`, `shouldStampFallbackTermsConsent`) so the decision is directly
mutation-provable, with the catch's direction pinned structurally and its scope limit stated in
the test file.

## Ground truth verified

- Live SQL (`dedsavbjuwgarrhphgnl`): cloud row fully onboarded; `user_profile.updated_at` still
  `2026-05-01 10:05:21`, proving no overwrite occurred.
- `pg_policy` on `public.user_profile`: `user_profile_select_own` is own-row-only — the mechanism
  by which a stale token yields 200-with-zero-rows.
- One `auth.users` row, two `auth.identities` (`email`, `google`) — identity linking is correct.
- `git merge-base --is-ancestor 6971e267 2470953e` → a3f6d9's fix **is** in the `1.0.0+38` build,
  confirmed against telemetry showing `client_version 1.0.0+38`. This is a survival, not a
  regression of an unshipped fix.
- Telemetry gap acknowledged, not papered over: no `client_errors` rows 06:50–07:13 UTC, and
  `log-client-error` returning 503s at 07:17. The fix is built to be correct without knowing
  which of the two entrances fired.

## Residual risk

- **Highest-risk edit:** moving `HiveUserSession.openForUser` earlier (via
  `ensureOpenedForCurrentSession`) on the boot path. Idempotent, `_sessionLock`-guarded, same user
  id from the same live session, and both `_goHome` branches already call it — but it is an
  ordering change on the cross-account-critical path.
- **Owed and not done:** device-level end-to-end verification (sign out → Google sign-in → confirm
  `/home`; repeat with airplane mode toggled mid-restore). The mechanism is a live-network race no
  unit test reproduces. This is a real gap in the evidence.
- **Unproven lead:** `supabase_flutter` 2.12.4 → 2.17.1 is in `+38`, the build this first appeared
  on, and cold-start session/token attachment is the subsystem involved. No specific behaviour
  change was verified; the fix does not depend on it.
