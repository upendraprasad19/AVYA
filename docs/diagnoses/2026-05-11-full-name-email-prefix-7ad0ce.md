---
bug_id: 7ad0ce
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: Email-signup users (Supabase Auth's email flow carries no metadata) had `public.users.full_name` permanently seeded with `email.split('@').first`. The `_ensureLocalUser` upsert ran with `ignoreDuplicates: true` so the email-prefix seed stuck FOREVER. AI coach + weekly recap + every greeting addressed users by their email prefix for the lifetime of the account.
concept: full_name_email_prefix
sot_registry_entry: users_full_name
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: _ensureLocalUser, line: 451 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: system_prompt_greeting, line: 1 }
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: userProfileProvider, line: 1 }
hive_key_prefix: "userBox: profile"
hive_key_formula: "profile['full_name']"
sync_methods: []
restore_methods: []
cloud_table: users
cloud_columns: [id, full_name]
contract_test_path: test/contracts/full_name_backfill_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["full_name_seeded_with_email_prefix_then_ignoreDuplicates"]
proposed_fix: After the existing `users` upsert + `last_active_at` update, run a self-heal `.update({'full_name': localName}).eq('id', user.id)` when the local Hive userBox profile carries a real-looking name (non-empty + contains a letter + not equal to the email prefix). Idempotent — once names match, subsequent updates are a no-op. Catches the email-prefix seed AND any user who edited their name post-signup but whose cloud `full_name` lagged the local edit.
regression_test_planned:
  - test/contracts/full_name_backfill_test.dart
---
# Audit H-3: full_name permanently seeded with email-prefix

## Bug

`_ensureLocalUser` (auth_provider.dart:455) sets `full_name` as:

```dart
'full_name': user.userMetadata?['full_name']
    ?? (user.email?.isNotEmpty == true
        ? user.email!.split('@').first
        : 'User'),
```

For email signup, `user.userMetadata` is empty — `full_name` becomes
the email prefix. Examples:

- `priya@gmail.com` → full_name = `'priya'`
- `upendra.prasad@thinkingcode.com` → full_name = `'upendra.prasad'`
- `firstname.lastname@x.io` → full_name = `'firstname.lastname'`

With `ignoreDuplicates: true`, this seed only runs on first sign-up
and is NEVER overwritten on subsequent sign-ins. Even if the user
goes to Profile → Edit Profile → "Full Name: Priya Sharma", the local
Hive write goes through but the cloud `public.users.full_name` row
keeps the lowercase email prefix forever (the existing
`syncProfileNow` path writes to `user_profile`, not `users`).

Downstream:

- **AI coach** — Edge Functions read `public.users.full_name` for
  the system prompt greeting. Coach addresses user as "priya" for
  life.
- **Weekly recap** — same.
- **Server-side logs / admin queries** — see email prefix instead of
  real name.

## Cause

`ignoreDuplicates: true` is correct for `created_at` (don't reset it)
but wrong for `full_name` which needs to be updated when the real
name becomes available (post-onboarding). The original implementation
treated `users` as write-once.

## Fix

After the existing upsert + `last_active_at` update, run an explicit
self-heal:

```dart
final localProfile = userBox.get('profile');
if (localProfile is Map) {
  final localName = (localProfile['full_name'] as String?)?.trim();
  final emailPrefix = (user.email?.contains('@') == true)
      ? user.email!.split('@').first
      : null;
  final looksReal = localName != null &&
      localName.isNotEmpty &&
      RegExp(r'[A-Za-z]').hasMatch(localName) &&
      localName != emailPrefix;
  if (looksReal) {
    await _supabase.client
        .from('users')
        .update({'full_name': localName})
        .eq('id', user.id);
  }
}
```

Three guards prevent the self-heal from making things worse:

1. **Non-empty.** A blank `localName` would wipe whatever the user
   typed during onboarding.
2. **Contains a letter.** Defends against ASCII garbage / placeholder
   values like "—" or "?".
3. **Not equal to email prefix.** If the local profile still carries
   the email-prefix seed (user never edited), the update would no-op
   into re-writing the same buggy value. The guard makes the
   self-heal idempotent: once a real name is set anywhere, it
   propagates; if neither side has a real name, neither gets a fake
   one.

Idempotent — once `localName == cloud_name`, the update is a no-op on
every cold start.

## Regression test

`test/contracts/full_name_backfill_test.dart` — 2 cases:

1. `_ensureLocalUser` contains a `users.full_name` self-heal update
   reading `userBox.get('profile')`.
2. The three guards (non-empty + letter + ≠ email-prefix) are
   present.

Plus `test/contracts/auth_provider_error_surfacing_test.dart` window
bumped from 8000 → 10000 chars to fit the added self-heal block.

Suite: 1559 pass / 0 fail / 2 skip.

## Related

- Bug A (2026-04-26) — orphan public.users + 23505/23503 silent swallow
- CLAUDE.md bug class: "AI coach greets 'Good morning.' with no name"
