---
reviewed_at: 2026-09-26T17:30:00+05:30
staged_against: reuse-audit-fixes (staged diff, pre-commit)
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
---

# Code Review — reuse-audit-fixes (B1 + C + D)

Each finding was verified by the author against the files and live state before triage.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** lib/features/onboarding/providers/onboarding_provider.dart:683-737
- **claim:** If the first `_syncOnboardingToSupabase` attempt throws, the catch only schedules a 10s unawaited retry and falls through, so `redeem-referral` fires before the users row exists. `redeem_referral_atomic` inserts into `subscriptions` (FK → users.id) → 500, only debugPrinted, code not retried or persisted. Pre-existing ordering gap, but it is now the ONLY redeem path for sign-up codes (c7b4d2).
- **verification:** `sed -n '683,737p' lib/features/onboarding/providers/onboarding_provider.dart`
- **suggested-fix:** redeem only after a confirmed users upsert (first try or retry), or retry the redeem once on non-2xx.
- **status:** false_alarm — the FK mechanism does not occur: `on_auth_user_created` (migration 039, `handle_new_auth_user`) is LIVE and enabled, and a read-only 2026-09-26 query found 0 of 36 auth users without a public.users row — the row exists from sign-up, before onboarding. The remaining transient-failure case is already covered at the transport layer: `SupabaseService.callFunction` refreshes the token first and retries 502/503/504 for ~20 s (supabase_service.dart:387-420). No change.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** lib/features/train/repositories/workout_repository.dart:1394-1403 + workout_write_service.dart:1229
- **claim:** duplicate-name guard runs before the write, but the lock keys on the ms key, not the id; the sheet has no in-flight guard on SAVE, so a double tap can create two rows with the same id.
- **verification:** `grep -n "_isSaving" lib/features/train/widgets/create_custom_exercise_sheet.dart` → none
- **suggested-fix:** disable SAVE while `_save` runs; re-check the duplicate inside an id-keyed lock.
- **status:** accepted — fixed: createCustomExercise serializes its check-then-write (static Completer chain) and never reuses a same-millisecond key; the sheet ignores SAVE while a save is in flight. Two new behavioral tests, each mutation-proven 2/2 (diagnose d5c2e8).

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** lib/features/train/widgets/create_custom_exercise_sheet.dart:294-313
- **claim:** the "created but not found on read-back" branch is effectively unreachable and, if hit, falsely tells the user the save failed.
- **verification:** both reads use HiveService.instance.customBox; row always stamped type:'exercise'.
- **suggested-fix:** word the fallback as "saved, couldn't refresh" or drop the branch.
- **status:** accepted — fixed: a read-back miss now pops the sheet with "Saved — find it under YOUR EXERCISES." instead of claiming the save failed.

## Clean lenses
function_exception_swallow, secrets_in_tree, blast_radius_mismatch, missing_input (all 4 onCreated callers tolerate the stored-row map), writer_reader_drift (default_reps already read as String everywhere; no double times_used bump). 78 targeted tests + analyze on 8 lib files clean per reviewer.
