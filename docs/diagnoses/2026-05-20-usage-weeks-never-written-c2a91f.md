---
bug_id: c2a91f
date: 2026-05-20
batch: APK Test #16.2 observations (2026-05-20 — obs 3)
status: shipped
symptom: |
  Founder reported "How do I see weekly report? Nothing is happening on
  clicking it?" on 2026-05-20 after almost 4 weeks of use. The Profile
  REPORTS section's Weekly Report hero card permanently rendered
  "Available after Week 1" with no tap target. Every user on every
  device on every launch hit the same state — the card hides its
  "View Full Report" CTA when usageWeeks < 1 (weekly_report_card.dart
  line 83) and usageWeeks was always 0 because the source it reads
  (configBox['first_launch_date']) was never written anywhere in the
  codebase. Verified by repo-wide grep: zero writers, one reader.
concept: usage_weeks_signup_age
sot_registry_entry: subscription
writers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: UsageWeeksNotifier.build (post-fix reads SupabaseService.instance.currentUser?.createdAt), line: 550 }
readers:
  - { file: lib/features/profile/widgets/weekly_report_card.dart, method_or_widget: WeeklyReportCard renders the sparkline grid + CTA only when usageWeeks >= 1, line: 21 }
  - { file: lib/features/profile/screens/profile_screen.dart, method_or_widget: passes usageWeeks into WeeklyReportCard constructor, line: 624 }
hive_key_prefix: "n/a — dead key first_launch_date removed; no Hive write in this batch"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "auth.users (existing — read via Supabase Auth session, no schema change)"
cloud_columns: [created_at]
contract_test_path: test/contracts/usage_weeks_uses_supabase_signup_test.dart
ist_handling:
  - { file: lib/features/profile/providers/profile_provider.dart, line: 565, source: "createdAt is a UTC ISO timestamp from Supabase Auth; the weeks calculation is timezone-agnostic (inDays / 7) so no IST shift needed for this counter" }
provider_invalidations: [usageWeeksProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: UsageWeeksNotifier.build watches authUserIdTokenProvider on line 553; rebuilds on every account switch so the count reflects the current session's createdAt.
forbidden_patterns_checked:
  - "configBox.get('first_launch_date') — dead key with no writer. The contract test scans all of lib/ to ensure nobody re-introduces it without a paired writer + registry update."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "UsageWeeksNotifier rewritten to read currentUser.createdAt instead of unwritten Hive key" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Fix eliminates the Hive read entirely; no key is written or read going forward" }
  - { tier: 5, name: cloud_sync_outbound, status: not_applicable, evidence: "No cloud writes — the timestamp comes from auth.users which is already populated at signup by Supabase Auth, no app code touches it" }
  - { tier: 6, name: cloud_sync_restore, status: verified, evidence: "currentUser.createdAt is restored automatically as part of Supabase auth session restoration on every launch — used at 5 other sites in the codebase without issue" }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "authUserIdTokenProvider watch on line 553 unchanged — usageWeeksProvider rebuilds on every auth state change" }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "test/contracts/usage_weeks_uses_supabase_signup_test.dart pins the new source + dead-key invariant + repo-wide ban on first_launch_date" }
impact_analysis:
  callers_audited:
    - lib/features/profile/screens/profile_screen.dart (passes usageWeeks into WeeklyReportCard)
    - lib/features/profile/widgets/weekly_report_card.dart (renders based on usageWeeks)
  callers_updated_in_this_batch:
    - lib/features/profile/providers/profile_provider.dart (UsageWeeksNotifier rewritten)
  callers_unchanged:
    - lib/features/profile/screens/profile_screen.dart (semantics preserved — usageWeeks now returns the correct value instead of always 0)
    - lib/features/profile/widgets/weekly_report_card.dart (no edit; conditional render at line 83 now exercises the >= 1 path for the first time for users beyond Week 1)
proposed_fix: |
  Replace the dead configBox['first_launch_date'] lookup in
  UsageWeeksNotifier.build() with SupabaseService.instance.currentUser?
  .createdAt — the timestamp Supabase Auth stamps at signup. Same
  source already used at 5 other callsites in the codebase
  (rank_service.dart:68, rank_service.dart:390,
  referral_eligibility_provider.dart:39,
  service_record_section.dart:195, rank_ladder_screen.dart:363).

  No new Hive key is written, no new cloud column is added — we adopt
  an existing signal rather than introducing parallel state. Survives
  reinstalls (Supabase auth session restoration is robust; the dead
  Hive key was per-device and would have failed reinstall even if it
  had been written).

  This is a minimal, surgical fix per founder's locked decision after
  v2 mockup review: keep the existing hero card + sparkline grid
  visual layout (the founder will now see it for the first time
  post-fix), do NOT pursue the visual reorganization that was originally
  considered.

  Why this wasn't caught earlier: the dead Hive key + always-0 counter
  meant the card was visually identical across all users and all
  durations. Every founder/dev install also saw "Available after
  Week 1" — but they were all literally still in Week 1 at the time
  they tested, so the bug looked like correct behavior. It only
  surfaced when a real user crossed past Week 1 (the founder, at
  Week 4) and noticed the card never changed.
regression_test_planned:
  - test/contracts/usage_weeks_uses_supabase_signup_test.dart — pins (a) new currentUser?.createdAt source, (b) absence of dead first_launch_date key in production code, (c) repo-wide invariant that no .dart file under lib/ references first_launch_date.
---
# Body

## What was broken and why no one noticed

The Hive key `first_launch_date` is referenced in exactly one place in
the entire repo:

```
lib/features/profile/providers/profile_provider.dart:555
  final firstLaunchRaw = configBox.get('first_launch_date') as String?;
```

There is no `configBox.put('first_launch_date', ...)` anywhere — in
`lib/`, `supabase/`, `scripts/`, or `test/`. The only other mention is
a historical plan document (`docs/superpowers/plans/2026-05-04-cross-account-leak-hotfix-plan.md`)
that lists the key as if it existed. It doesn't.

Every user, every device, every cold start, every hot resume:
`firstLaunchRaw == null` → `return 0`. `usageWeeks` is permanently 0.

The Weekly Report's hero card (`weekly_report_card.dart`) wraps its
entire body — sparkline grid AND "View Full Report" CTA — in
`if (usageWeeks >= 1)` at line 83. That condition is permanently false.
So the card shows only its eyebrow + the "Available after Week 1"
subtitle, with no tap target.

Why this didn't surface in any dev test cycle: every test install
happened the same day the tester opened the app for the first time on
that device. usageWeeks was correctly 0 in those moments. The bug
materializes only when the tester has been using the app for >= 7 days
on a single device — which never happened in dev cycles.

The founder hit it because they've been on the app for ~4 weeks of
real use and noticed the card never changed.

## The fix is two lines of substance

```dart
final createdAtIso = SupabaseService.instance.currentUser?.createdAt;
if (createdAtIso == null) return 0;
final createdAt = DateTime.tryParse(createdAtIso);
if (createdAt == null) return 0;
return DateTime.now().difference(createdAt).inDays ~/ 7;
```

`SupabaseService.instance.currentUser?.createdAt` is the ISO timestamp
Supabase Auth stamps at signup. It survives reinstalls (Auth state
persists in secure storage) and gives a globally consistent answer
across devices.

We considered introducing a new Hive write to actually populate
`first_launch_date` on first launch. Rejected: that would create a
new race window where a fresh install on a returning user sees
`weeks = 0` until the first launch handler runs, then jumps to N
weeks on the next launch. The Supabase auth signal avoids that
entirely — it's correct from frame 1 of the first launch on any
device.

## Mockups consulted before locking the scope

- `docs/mockups/2026-05-20-profile-reports-section-v1.html` — original
  two-frame BEFORE/AFTER showing the row-conversion proposal.
- `docs/mockups/2026-05-20-profile-reports-section-v2.html` — three-frame
  comparison adding the "what the hero card was supposed to look like"
  intended state. The founder picked the middle frame (counter-fix
  only, keep the hero + sparkline grid layout).

Mockups are gitignored per project convention; they exist on disk for
preview only.

## Recurrence-risk class to watch

This bug is an instance of "Hive key read with no writer" — a
class adjacent to but distinct from writer/reader drift (which has
both sides but with mismatched semantics). Here there is exactly one
side. A general-purpose audit script for this class would `grep` for
every literal Hive key read in `lib/` and check that the same literal
appears in a `.put(` somewhere. Out of scope for this batch, but
worth noting as a follow-up if a second instance surfaces.
