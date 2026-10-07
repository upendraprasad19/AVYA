---
reviewed_at: 2026-09-02T21:05:00+05:30
staged_against: d8f51f77c896
blast_radius: platform
reviewer: claude-sonnet-via-skill (B-pass) + 2 context-blind rounds
lens_set: [guard_without_its_mirror, ordering, stale_or_wrong_citation, asserted_fixture_value, behavior_change_regression, missing_input, trigger_provenance, completeness_of_reader_enumeration]
findings_count: 18
verdict: accepted
---

# Code Review — d8f51f77c896 (branch `profile-stale-restore`, diagnose b3c9d4)

> `staged_against` is the staged-diff hash at REVIEW time. The plan-review
> record and the SKILL.md tuning entry were written afterwards *because of*
> this review, and both are inside the hash's input set while `docs/reviews/`
> is excluded — so no filename can name a hash that includes them. Stated
> rather than left as a number that quietly stops matching. The gate that
> keys on this filename (`check_code_review_pass_exists.dart`) blocks only at
> `catastrophic`; at `platform` the binding requirement is `bpass: accepted`
> in the plan-review record, which points here.

Three independent context-blind passes: an adversarial B-pass (8 findings) and
two plan-review rounds (7 + 3). **Zero false alarms across all 18** — every
finding was verified against source by the author before action, and every one
held. 17 fixed in-batch, 1 declined with evidence.

## B-pass — 8 findings

### Finding 1 — P1 — trigger_provenance — FIXED
- **file:line:** `lib/shared/mixins/hive_tab_scaffold.dart` (tick handler) →
  `lib/features/nutrition/screens/nutrition_screen.dart:44` →
  `lib/features/nutrition/widgets/log_food_modes/ai_mode_body.dart:41` →
  `lib/features/nutrition/widgets/log_food_sheet.dart:157,54`
- **claim:** Moving the `restoreCompletedTick` listener into the shared mixin made
  every tab's `invalidateOnRetry` fire on a background event. Nutrition's set
  includes `aiBreakdownProvider`, whose non-null→null transition `ai_mode_body`
  reads as "the user committed or cancelled" and uses to pop the Log Food sheet.
  A restore completing while a user reviewed an AI food analysis would have
  closed the sheet and discarded the analysis, silently.
- **verification:** `grep -n "void invalidateOnRetry" -A6 lib/features/nutrition/screens/nutrition_screen.dart`;
  read `ai_mode_body.dart:25-52`; `grep -n "AiModeBody(\|void _dismiss" lib/features/nutrition/widgets/log_food_sheet.dart`
- **evidence:** `AiBreakdownNotifier.build()` is unconditionally `=> null`, so an
  invalidate always produces the non-null→null transition. The diagnose-doc had
  asserted the opposite in writing ("no provider is being invalidated that was
  not already designed to be").
- **fix:** New `invalidateOnBackgroundRestore(WidgetRef ref)` hook on the mixin,
  defaulting to `invalidateOnRetry`. Nutrition overrides it to exclude
  `aiBreakdownProvider`. Mutation-proven: reverting the handler to call
  `invalidateOnRetry(ref)` reddens the new test.
- **status:** accepted

### Finding 2 — P2 — completeness — FIXED
- **file:line:** `lib/features/onboarding/screens/onboarding_chat_screen.dart:725`
- **claim:** A second hand-maintained list of the same three name providers was
  not audited against the new derivation. `completeOnboarding` writes Hive via
  `ProfileWriteService` without touching `UserProfileNotifier`'s Riverpod state,
  so the derived providers would rebuild against a stale source.
- **verification:** traced `onboarding_provider.dart:506` → `_userRepo.saveProfile` → `ProfileWriteService.updateProfile`
- **evidence:** Currently unreachable (the route runs before the tab shell mounts), so latent rather than live.
- **fix:** `ref.invalidate(userProfileProvider)` added with a comment stating it is defence-in-depth, plus the missing import.
- **status:** accepted

### Finding 3 — P2 — stale_or_wrong_citation — FIXED
- **claim:** `sync_profile.dart:648` and `home_screen.dart:303` are both wrong.
- **verification:** `grep -n "Future<void> _restoreUserProfile" lib/core/services/sync/sync_profile.dart` → 701; the merge itself → 764. `grep -n "ref.watch(userProfileProvider)" lib/features/home/screens/home_screen.dart` → 309.
- **evidence:** `:648` was **copied forward from the prior diagnose-doc (d4e9a2)** without re-derivation. A citation inherited from an older document is not a verified citation — the file has moved since, by definition.
- **fix:** corrected to `764` and `309`.
- **status:** accepted

### Finding 4 — P2 — stale_or_wrong_citation (SoT registry) — FIXED
- **claim:** The batch's mechanical "+6 shift" preserved two entries' pre-existing drift; the cited ranges never covered their cited method.
- **verification:** `AiInsightNotifier` 648, `_getLatestCoachTip` 689; `RecentFoodLogsNotifier` 740, body to 782.
- **evidence:** `check_sot_registry_parity.dart` extracts only the FIRST identifier of a dotted `Class.method` citation, so a range containing just the class line satisfies it while excluding the method entirely.
- **fix:** all seven affected ranges re-derived from verified locations, not shifted.
- **status:** accepted

### Finding 5 — P3 — stale documentation — FIXED
- **file:line:** `lib/features/home/CLAUDE.md:53`
- **fix:** row rewritten to name `HiveTabScaffoldMixin` as listener owner, all four tabs, and the Nutrition exclusion.
- **status:** accepted

### Finding 6 — P3 — coupled invariant — FIXED
- **claim:** `hasProfile=${profile.isNotEmpty}` is equivalent to the old `!= null` only because every writer stamps `updated_at`, an invariant living in another file.
- **fix:** comment added at the probe recording the coupling.
- **status:** accepted

### Finding 7 — P3 — redundant invalidation — **DECLINED, with evidence**
- **claim:** Home's `currentPlanProvider`/`selectedWeekProvider` invalidation is now redundant because Train has its own mixin listener.
- **verification:** `app_router.dart:359` — `StatefulShellRoute.indexedStack`, `grep -n "preload" lib/core/router/app_router.dart` → no matches.
- **evidence:** Branches build lazily. A user who has never opened Train has no Train `State`, therefore no listener, and those two lines are the only thing refreshing its plan providers. Redundant only AFTER Train has been visited; load-bearing before that. Removing them would regress the 2026-06-06 fix.
- **resolution:** kept, with the reasoning recorded in-source so the next reader does not re-propose it. A reviewer's "this is now redundant" is a hypothesis about runtime lifetime, and lifetime is what static reading cannot see.
- **status:** declined

### Finding 8 — P3 — informational — accepted as-is
- Redundant-but-harmless `ref.watch(authUserIdTokenProvider)` in the derived providers. Kept deliberately: each provider retains its own c4055a auth-change guard rather than relying on the source transitively.
- **status:** accepted (no change)

## Round 1 — 7 findings (only those not duplicating the B-pass)

### Finding 1 — P1 — completeness_of_reader_enumeration — FIXED
- **file:line:** `lib/features/profile/providers/profile_completeness_provider.dart:36`
- **claim:** `profileCompletenessProvider` is a FOURTH independent reader of the profile map, a plain `Provider` in NO tab's `invalidateOnRetry`, rendering the completeness bar on the same Profile screen as the wrong name.
- **verification:** `grep -rn "profileCompletenessProvider" lib/` → no hits in any `invalidateOnRetry`; `full_name` is 1 of 10 `kTier1Fields`, tier 1 weighted 60%.
- **evidence:** 9/10 tier-1 filled + full tier-2 = 54 + 40 = **94** — exactly the "PROFILE · 94% COMPLETE" in the founder's screenshot. The batch's own doc had claimed "nothing exposed is left unfixed"; that was false.
- **fix:** derived from `userProfileProvider`; `user_repository` import removed (it was the only reference, so leaving it would have been an unused-import warning and a failed push). Mutation-proven: reverting to `getProfile()` makes the 6-point delta 0 and reddens the test.
- **status:** accepted

### Finding 5 — P2 — FIXED
- **file:line:** `lib/features/profile/screens/edit_profile_screen.dart:148`
- **claim:** A `TextEditingController` seeded once in `initState` cannot react to a later heal, so a restore landing while Edit Profile is OPEN leaves the field blank — and `_save()` hard-refuses an empty name, locking the user out of saving ANY profile edit until they navigate away and back.
- **fix:** `ref.listenManual` re-seeds the controller when `full_name` arrives, guarded so a real user edit is never clobbered; subscription closed in `dispose`.
- **status:** accepted

### Finding 3 — P2 — under-argued evidence — FIXED
- **claim:** "Zero `restore_users_row_*` rows proves nothing failed" is weaker than it reads, because that telemetry lives on the LEGACY path and the founder's restore ran C3.
- **verification (author, live):** `path=singlecall` in the founder's own `restore_step_done` rows; `restore_users_row_null_via_singlecall` also silent.
- **fix:** doc now states the C3 distinction explicitly and adds the decisive timeline (`restore_started` 19:23:23.492 → probe 19:23:27.267 → `step=A path=singlecall` 19:23:31.194 — the read beat the restore by 3.8s).
- **status:** accepted

### Findings 2, 6, 7 — P2/P3 citation + count corrections — FIXED
`sync_profile.dart:648`→`764`; `home_screen.dart:303`→`309`; "15 entries"→"14".

## Round 2 — 3 findings (on the hardened diff)

### Finding 1 — P2 — stale_or_wrong_citation — FIXED
- **claim:** 5 of 11 `file:line` entries in the new diagnose-doc's writers/readers block point at the wrong line; one at a completely unrelated symbol.
- **verification (author, all 11 re-derived):** `UserInitialNotifier.build` 221→**227**; edit-profile probe 117→**122**; the new `listenManual` 134→**148**; mixin initState 127→**142**; completeness provider 38→**36**. The other six were correct.
- **evidence:** Nothing gates these — `validate_diagnose_doc.dart` has zero references to `writers`/`readers`/`line`, and `check_sot_registry_parity.dart` only reads `docs/sot_registry.yaml`.
- **fix:** all five corrected; `profileCompletenessProvider` added to `provider_invalidations:`; the `ai_mode_body.dart:33`→`:41` citation corrected in all five places it had been copied to.
- **status:** accepted

### Finding 2 — P3 — guard cannot see its own blind spot — FIXED
- **claim:** `_nameController.text != _seededName` cannot distinguish "untouched" from "user retyped the identical string", and would overwrite a deliberate re-entry.
- **fix:** replaced with an explicit `_userEditedName` flag set by a controller listener that compares text before flagging (so cursor/selection moves do not count), plus `_applyingNameHeal` so our own write is never mistaken for a user edit.
- **status:** accepted

### Finding 3 — P3 — now-redundant explicit invalidate — accepted as-is
- `edit_profile_screen.dart`'s post-save `ref.invalidate(profileCompletenessProvider)` is a harmless no-op now that the provider derives from `userProfileProvider` (which `updateProfile` sets directly). Reviewer's own verdict: "None required." Kept as defence if the derivation ever changes; Riverpod invalidation is idempotent.
- **status:** accepted (no change)

## Founder triage notes

Every finding was verified against source by the author before being acted on;
none were taken on the reviewer's word. Two findings were the batch's own fix
introducing a new defect (B-pass 1, round-1 1), which is the documented reason
these rounds exist. One was declined on evidence the reviewer could not see
statically. Verdict: **accepted**.
