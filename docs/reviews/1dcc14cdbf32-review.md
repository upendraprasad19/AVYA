---
reviewed_at: 2026-08-03T18:45:00+05:30
staged_against: 1dcc14cdbf32
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, compact_parameter_isolation, google_button_guard_parity, restoring_screen_fix_completeness]
findings_count: 3
verdict: accepted
---

# Code Review — 1dcc14cdbf32

## Finding 1 — P0 — restoring_screen_fix_completeness
- **file:line:** `lib/features/auth/screens/restoring_screen.dart` `_onContinueAnyway` (the 30s CONTINUE timeout escape hatch), contrasted with the two fixed `_goHome` branches
- **claim:** The diagnose-doc (`docs/diagnoses/2026-08-03-restoring-screen-local-onboarded-flag-not-stamped-a3f6d9.md`) claimed `status: fixed` and that "Two call sites, one per `_goHome` branch" closed the gap. That was false — there is a THIRD path to `/home` in this same file that the fix did not touch: `_onContinueAnyway`, wired to the 30-second timeout escape-hatch CONTINUE button. It opens `HiveUserSession` for the user and then calls `context.go(RestoringScreen.resolveRestoreDestination(widget.next))` directly, bypassing `_goHome` entirely and therefore bypassing both new guards. The exact bug scenario the diagnose-doc describes (a fresh device/browser taking the default/blocking `_goHome` branch, which can await a restore of ~46s+ per the founder's own breadcrumbs) is precisely the scenario most likely to still be waiting on `restoreFuture` when the 30s CTA surfaces.
- **verification:** `grep -n "context.go('/home')\|resolveRestoreDestination(" lib/features/auth/screens/restoring_screen.dart` showed 3 call sites; only 2 had the guard. Read `_onContinueAnyway` in full — confirmed no `UserRepository.instance.isOnboarded`/`setOnboarded()` call anywhere.
- **suggested-fix:** Add the identical guard to `_onContinueAnyway`, placed after ownership is confirmed open and before `context.go(...)`.
- **status:** fixed — verified independently (grep + full method read) before applying; added the guard gated on a new `ownershipOpen` bool. **Superseded by round 2 Finding 1** (`docs/reviews/1cf9f51d2565-round2-review.md`), which found this round-1 fix's own reachability reasoning was wrong and required a further correction (`_committedToGoHome` tracking) — see that file for the final, correct fix. Diagnose-doc, SoT registry, and regression test all updated to the round-2-hardened state.

## Finding 2 — P2 — writer_reader_drift
- **file:line:** `docs/sot_registry.yaml` (new entry for `_goHome`, `onboarding_completed_at` concept)
- **claim:** The new SoT registry entry's `line_range: 220-263` for `_goHome` did not span both branches its own notes described (the second stamp was at 279-280, past the stated range).
- **verification:** `grep -n "Future<void> _goHome\|isOnboarded\|setOnboarded" lib/features/auth/screens/restoring_screen.dart` showed the mismatch.
- **suggested-fix:** Correct the registry entry's line range to span the whole method (or list both sub-ranges).
- **status:** fixed — corrected to `220-284` at the time (later re-corrected to `239-308` after `dart format` reflowed the file during the round-2 fix; both line-range and the writer-list line numbers in the diagnose-doc were re-verified against the final file state).

## Finding 3 — P2 — blast_radius_mismatch
- **file:line:** `lib/features/auth/screens/sign_in_screen.dart` (whole diff hunk — the sign-in card redesign)
- **claim:** `lib/features/auth/**` is `account` tier per `docs/blast_radius.yaml`, so CLAUDE.md §4.6's feature-flag protocol ("default new code path behind a kDebugMode/Hive/RemoteConfig gate, old path preserved") applies by the letter of the rule. No kill-switch was added. Verified the "UI-only, no auth-logic change" claim directly: every `onPressed`/guard callback that existed pre-diff is reproduced verbatim in the new call sites — no new async operation, no new Supabase call, no change to what function runs under what condition. That claim held, but §4.6 as written doesn't carve a "visual-only" exemption, and no explicit decision recording the exemption existed anywhere in the batch materials.
- **verification:** `grep -n "features/auth" docs/blast_radius.yaml` → account tier. Diffed every guard body old vs new — byte-for-byte identical predicates.
- **suggested-fix:** Either explicitly document why this change is exempt from §4.6 (pure presentation, guard predicates diffed unchanged), or wrap it in a kill-switch per §4.6 step 2.
- **status:** accepted_risk — documented in this batch's plan-review record (`docs/plan-reviews/restore-onboarding-signin-fix.md`) per the first option: this is a UI/layout-only redesign with every underlying auth call and guard predicate confirmed byte-identical to pre-diff (see this finding's own verification above), so §4.6's feature-flag protocol — aimed at behavioral/security auth changes — is treated as not applicable here. Rollback path if the redesign proves bad: `git revert` the isolated `sign_in_screen.dart` commit.

## Founder triage notes
<!-- leave blank for founder -->
