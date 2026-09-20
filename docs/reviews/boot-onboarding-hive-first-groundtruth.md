# Ground-truth review — `fix-boot-onboarding-hive-first` (diagnose a1f9c4)

**Reviewer:** fresh, context-blind ground-truth pass. Every claim verified against
the actual code on branch `fix-boot-onboarding-hive-first` (working tree == staged).
**Date:** 2026-06-26.

## Verdict

**The fix is CORRECT and substantially COMPLETE. No P0/P1 must-fix correctness
gaps found.** The two un-timed-cloud-await hangs are genuinely closed:

- Splash: the 12s `.timeout` wraps the WHOLE `_runDeferredInit`, which covers all
  three of its blocking awaits (`Supabase.initialize`, `seedIfNeeded`, conditional
  `syncToHive`). `_navigateNext` runs synchronously after, so the seal can no longer
  hang.
- Onboarding: every LOCAL write before navigation is pure-local Hive (verified
  through the repository chain) — the cloud chain is correctly extracted into the
  unawaited `_syncOnboardingAndPostActions`, with the sync-before-referral order
  preserved and the `ref` reads captured synchronously before the fire-and-forget.

The regression test is a TRUE pinning test (verified: FAILS on pre-fix HEAD, PASSES
on the fix). `flutter analyze` is clean on all three changed files.

Findings below are **P2 (process/doc) only** — none block the merge on correctness,
but the SoT-registry one (F1) is a real §4.5 discipline miss that should be closed
in this commit.

---

## Claim-by-claim verification

### Claim 1 — Did the fix bound ALL un-timed cloud/IO awaits on each critical path?  → YES (verified)

**Splash (`splash_screen.dart`).** `_runDeferredInit` has exactly three *awaited*
blocking calls, all network/IO:
- `:121` `await SupabaseService.instance.initialize()` — the original culprit.
- `:140` `await ref.read(seedServiceProvider).seedIfNeeded()` — first-launch JSON DB
  seed (disk/CPU, can be slow on a cold device).
- `:159` `await HealthSyncService.instance.syncToHive()` — guarded `!kIsWeb &&
  HealthSyncService.isEnabled()`; not on the web path that surfaced the bug, but
  still a potential blocker on mobile.

All three sit INSIDE `guardedInit` (`:98`), which is what gets `.timeout(_kInitTimeout)`
at `:105`. So the 12s bound covers the whole init, not just `Supabase.initialize`.
`_navigateNext` (`:289`) is synchronous. **The author's claim that wrapping the whole
`_runDeferredInit` covers every blocking await is correct.** (The diagnose-doc only
*names* `Supabase.initialize`; it happens to also cover `seedIfNeeded` and
`syncToHive`, which is the right outcome — noted as a doc-completeness nit, not a gap.)

**Onboarding LOCAL writes (`completeOnboarding`, before the cloud chain).** Traced
each to ground truth:
- `saveProfile` (`:398`) → `ProfileWriteService.updateProfile` → `userBox.put` then
  `_fireSync()` which is `unawaited(...syncProfileNow)` (`profile_write_service.dart:69,122-126`).
  **Pure-local + fire-and-forget cloud. Does NOT block.** ✔
- weight-log seed (`:425`) → `HealthWriteService.logWeight` → `healthBox.put` then
  `unawaited(syncWeightNow)` + `unawaited(pushSnapshot)` (`health_write_service.dart:136-139`).
  **Pure-local.** ✔
- `seedIfNeeded` (`:441`) — local Hive seed, only if `exerciseBox.isEmpty`. ✔
- `generateAndSchedule` (`:446`) — local plan generation (CLAUDE.md rule 8: plan
  generator is local Dart, queries Hive, never an API). ✔
- `saveProgress` (`:463`) → `userBox.put` (`user_repository.dart:89-96`). **Pure-local.** ✔
- `setOnboarded` (`:472`) → `MigratedKey.write` → `userBox.put` (`migrated_key.dart:80-101`).
  **Pure-local.** ✔

**Conclusion:** no awaited network call remains on either critical path. Claim 1 holds.

### Claim 2 — Does the splash timeout degrade SAFELY?  → YES, with one nuance (verified)

On timeout, `onTimeout` just logs and lets `Future.wait` resolve; `_navigateNext`
reads `SupabaseService.instance.isAuthenticated` (`:292`).

- If `Supabase.initialize()` itself is what stalled past 12s, the SDK likely hasn't
  restored the session → `isAuthenticated == false` → `/sign-in`. A re-auth is a far
  better outcome than an infinite seal, and the user's Hive data is intact (offline-
  first). **Acceptable.**
- Nuance: an *onboarded* user who hits the timeout lands on `/sign-in`, not `/home`.
  That is the intended degrade, and it only fires on a genuine >12s init stall (the
  doc claims a warm init is <2s, which is plausible for the web SDK). The user re-auths
  and `_authRedirect` routes them correctly. No state loss (Hive is the source of
  truth). **Safe.**
- 12s is a reasonable choice: long enough not to false-trip a slow-but-working cold
  start (warm <2s, generous headroom), short enough to escape a true hang. Not
  flagged.

### Claim 3 — Does navigate-first preserve correctness?  → YES (verified)

**(a) Cloud `onboarding_completed_at` stamp + self-heal.** The cloud stamp is written
by `_syncOnboardingToSupabase` (`:716`) → `UserRepository.syncOnboardingToSupabase`
→ `user_profile.upsert({onboarding_completed_at: NOW()})` (`user_repository.dart:419-422`).
This is now inside the background `_syncOnboardingAndPostActions`, so it is no longer
guaranteed to have been *attempted* before the user leaves the Plan screen.

Recovery path verified: if the background sync never lands (app closed immediately,
or the same 57014/546 backend failure), the cloud `onboarding_completed_at` stays
NULL while Hive has `onboarding_completed=true` + a populated profile. On next sign-in,
`RestoringScreen._kickoffRestore` → `resolveDestination` returns `ResumeOnboarding`,
and the handler (`restoring_screen.dart:114-150`) checks `flagOnboarded ||
hasCorePlanFields` from **Hive**, fires the Plan-A self-heal re-stamp, and routes to
`_goHome`. **So a missed background sync self-heals — the user is NOT bounced back
into onboarding.** ✔ Belt: `pending_onboarding_sync` flag + bootstrap replay (the flag
is set at `:502` and only deleted on a confirmed upsert at `:557`).

**(b) Referral grant.** Order preserved: `_syncOnboardingAndPostActions` awaits
`_syncOnboardingToSupabase` (which upserts the `users` row) BEFORE
`callFunction('redeem-referral')` (`:556` then `:600`). The EF reads `public.users`,
so the row exists first. The referral code is captured synchronously at `:503` and
the stash cleared at `:506` (before the unawaited fire), so a screen dispose can't
lose it. **Preserved.** ✔

**(c) Induction race.** `plan_screen` navigates to `/coach/induction` immediately
after `completeOnboarding` returns (`plan_screen.dart:540`). Verified what induction
reads on mount: `InductionScreen` reads ONLY `HiveService.instance.userBox.get('profile')`
for the first name (`induction_screen.dart:100-104`) — no cloud read, no AI-snapshot
dependency. `recordCommitment()` is "Hive + fire-and-forget sync". The AI snapshot
(`pushSnapshot`) was ALSO fire-and-forget in the pre-fix code, so nothing regressed.
Additionally, the Hive session owner is opened during sign-up
(`auth_provider._ensureLocalUser:372` `openForUser`) — long before Plan — so the FIX-1
session-open race does not apply here. **No race introduced.** ✔

### Claim 4 — Anything the author MISSED?  → No correctness misses; see findings

- **Other un-timed-cloud-await-on-nav screens.** `/restoring` is the other post-auth
  nav gate. It is NOT at risk: `_kickoffRestore` awaits `destinationFuture`
  (`resolveDestination` — a bounded cloud SELECT) but `_goHome` runs the long restore
  EITHER in the background (returning users, default) OR awaited with a **30s CONTINUE
  escape** (`restoring_screen.dart:71,79-81,586-621`). (Note: the prompt said "15s
  CONTINUE" — the actual current value is **30s** (`_ctaAfter`), bumped from 15s per
  diagnose 4a3b08; a 15s *soft hint* also exists. Either way there IS an escape, so
  `/restoring` cannot hang forever.) ✔ The splash itself fires many OTHER cloud calls
  but every one of them past the init is already `unawaited(...)` (`:126,169,178,183,
  186,192,204,209,213`), so they never blocked navigation even pre-fix.

- **Kill-switch path safety.** `disable_onboarding_async_sync == true` → `await
  cloudCatchUp` (`:512`), which restores the OLD blocking behaviour (the very hang the
  fix removes — intentional, it's the escape hatch). The restored path can't throw an
  *uncaught* exception: `_syncOnboardingAndPostActions` wraps the sync in try/catch and
  the referral block in its own try/catch, so `await cloudCatchUp` completes normally
  even on failure. The non-kill-switch path additionally guards with `.catchError`
  (`:514`). ✔

---

## Findings

### F1 — (P2, process) Diagnose-doc says `sot_registry_entry: not_applicable`, but this fix touches a REGISTERED SoT writer

`docs/sot_registry.yaml:3284` registers the concept `onboarding_completed_at` with a
writer `lib/features/onboarding/providers/onboarding_provider.dart` / `completeOnboarding`
(note: "stamps onboarding_completed_at in profile map **synced via onboarding_sync**")
and a `behavioral_test_path: test/contracts/onboarding_completed_at_behavioral_test.dart`.

The fix changes the *timing contract* of that writer's cloud side: the
`onboarding_completed_at` cloud stamp moves from an awaited critical-path call to the
unawaited background `_syncOnboardingAndPostActions`. Per CLAUDE.md §4.5 ("SoT registry
update for new writer/reader contracts") + the per-batch protocol, the registry entry
should be reviewed and (if needed) annotated in the SAME commit — at minimum a note
that the cloud stamp is now fire-and-forget and recovery leans on the RestoringScreen
Plan-A self-heal. The doc's `not_applicable` is inaccurate.

**Also:** the registry writer entry's `line_range: 265-285` is stale (the method now
spans 271-544); and the existing behavioral test `onboarding_completed_at_behavioral_test.dart`
should be run to confirm it still passes under the new timing (it asserts Hive+cloud
stamping; if it awaited a synchronous cloud stamp it could now be racy).

**Suggested fix:** set `sot_registry_entry: onboarding_completed_at` in the diagnose-doc;
add a one-line note to the registry writer entry (cloud stamp now backgrounded; recovery
via RestoringScreen self-heal); refresh the stale `line_range`; run
`onboarding_completed_at_behavioral_test.dart` and cite it green.

**Verification:** `docs/sot_registry.yaml:3284-3300`; diagnose-doc frontmatter line 17.

### F2 — (P2, doc) Diagnose-doc "What happened" cites slightly-off line numbers

The doc cites the pre-fix awaited calls as `_syncOnboardingToSupabase (:491)`,
`redeem-referral (:557)`, `verifyFromServer (:563)`. Against pre-fix HEAD the actual
lines are `:491` (correct), `:555` (callFunction redeem-referral; doc says :557), and
`:561` (verifyFromServer; doc says :563) — each off by ~2. Cosmetic; the calls and the
root-cause structure are described correctly. Per the founder's "verify numeric claims"
rule, worth a one-line correction but not material.

**Verification:** `git show HEAD:.../onboarding_provider.dart` lines 491/555/561.

### F3 — (P2, coverage) Behavioral hang-test deferred — acceptable bar, but note the residual

The regression test is a comment-stripped **source-structure** contract (verified TRUE:
fails pre-fix, passes post-fix). It pins the *shape* (timeout present; cloud chain
extracted + unawaited; redeem/verify off the critical path; sync-before-referral order).
It does NOT prove the *behavior* that a hanging Supabase future no longer strands the
UI — that needs a fakeAsync + service-fake/DI seam, which the doc explicitly tracks as a
follow-up and substitutes with the founder's live re-walk. Given `feedback_source_grep_false_confidence.md`
(source-grep == presence only), this is the known-acceptable bar for THIS fix (structural
test + kill-switch + live verify), but the residual is real: a future refactor that keeps
the structure but reintroduces an awaited cloud call *elsewhere* on the path would pass
this test. Acceptable to ship; worth a `behavioral_test_required: true`-style marker if a
DI seam ever lands.

---

## Tier coverage spot-check (against the diagnose-doc's `touched_layers_checked`)

- Tier 1 (client): verified — analyze clean, test green, both files traced.
- Tier 2 (Hive local): verified — all local writes confirmed pure-local Hive; onboarding
  durability before nav holds.
- Tier 12 (client↔server contract): the claim "rows still land, just backgrounded,
  order preserved" is correct in CODE. The live evidence (test6 referral both-party
  grant) is asserted by the author from a prior live walk — I did not re-run live DB
  queries (context-blind code review), but the code path supports the claim and the
  self-heal covers the miss case.

## Bottom line

Ship-able on correctness. Close F1 (SoT registry annotation + run the existing
`onboarding_completed_at` behavioral test) in this commit to satisfy §4.5; F2/F3 are
optional polish.
