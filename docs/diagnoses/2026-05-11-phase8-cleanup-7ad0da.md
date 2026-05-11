---
bug_id: 7ad0da
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: Phase 8 cleanup catch-all. (Hive sequential) `HiveService.init` opened 9 shared boxes serially via a for-loop — sequential file I/O wasted 150-300 ms of cold-start time. (community_review_sheet `as Map`) two `f as Map` / `e as Map` casts at lines 71+77 would TypeError on a non-Map row (PostgREST schema drift would crash the sheet). (H-42 retrofit batch) 28 grandfathered `catch (e) { debugPrint(...) }` sites remain after the audit's first batch; 4 hot-path services retained the silent-swallow pattern — health_sync_service (4 sites — fires on every splash), razorpay_service (8 sites — payment flow), stat_snapshot_service (5 sites — onboarding + promotion + manual snapshots), subscription_service (1 site — refreshFromSupabase failures only surfaced via the log-client-error helper, not Crashlytics).
concept: phase8_cleanup
sot_registry_entry: error_telemetry_funnel
writers:
  - { file: lib/core/services/hive_service.dart, method_or_widget: init (Future.wait parallel open), line: 71 }
  - { file: lib/shared/widgets/community_review_sheet.dart, method_or_widget: row-iteration is Map guards, line: 67 }
  - { file: lib/core/services/health_sync_service.dart, method_or_widget: 4 catches retrofitted with ErrorTelemetry.recordNonFatal, line: 51 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: 8 catches retrofitted, line: 142 }
  - { file: lib/core/services/stat_snapshot_service.dart, method_or_widget: 5 catches retrofitted, line: 227 }
  - { file: lib/core/services/subscription_service.dart, method_or_widget: refreshFromSupabase catch (Crashlytics defense-in-depth), line: 469 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns: [error_code, error_message, op_type, retry_count, client_version, platform]
contract_test_path: test/contracts/no_silent_debugprint_in_services_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [health_sync_request_permissions, health_sync_quiet_permission_check, health_sync_fetch_steps_today, health_sync_fetch_latest_weight, razorpay_session_refresh, razorpay_mark_payment_in_flight, razorpay_write_subscription_state, razorpay_local_activation_at_write, razorpay_poll_and_activate, razorpay_poll_attempt, razorpay_verify_payment_edge_function, razorpay_verify_payment_retry, razorpay_create_order, razorpay_already_pro_handler, stat_snapshot_onboarding, stat_snapshot_on_promotion, stat_snapshot_manual, stat_snapshot_list_all, stat_snapshot_compute_7d_averages, subscription_refresh_from_supabase]
cross_account_guard: n/a
forbidden_patterns_checked: ["sequential_hive_init_open", "as_Map_no_is_guard", "silent_debugPrint_catch_in_services"]
proposed_fix: (Hive parallel) replace the for-loop in `HiveService.init` with `Future.wait(_sharedBoxNames.map(_safeOpenBox))`. (community_review_sheet) add `if (f is! Map) continue` / `if (e is! Map) continue` guards + null-safe id extraction. (H-42 retrofit) wire `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<site>'))` into each catch in the 4 hot services. Each reason is unique + descriptive so the dashboard groups failures by site. Update the grandfathered set in the no-silent-debugprint contract test to remove the 4 retrofitted files.
regression_test_planned:
  - test/contracts/no_silent_debugprint_in_services_test.dart (grandfathered set shrunk from 28 → 21)
---
# Audit Phase 8: cleanup — perf + correctness + telemetry retrofit

## Quick-win perf: Hive parallel init

`HiveService.init` was opening 9 shared boxes via a sequential
`for (final name in _sharedBoxNames) await _safeOpenBox(name)`.
Each `Hive.openBox` is dominated by file I/O which can overlap.
Switched to `Future.wait(_sharedBoxNames.map(_safeOpenBox))` —
estimated saving: 150-300 ms cold-start on typical devices.

Each `_safeOpenBox` already has its own try/recover + corruption-
delete fallback, so parallel execution doesn't lose any safety.

## Correctness: community_review_sheet `as Map` guards

Lines 71+77 cast PostgREST rows as `Map` without checking. A schema-
drift response or non-Map row (unusual but possible) would TypeError
and crash the whole sheet. Added `is! Map` guards + null-safe `id`
extraction; non-Map rows now silently skip rather than crash.

## H-42 retrofit: 4 hot-path services

The H-42 audit shipped a grandfathered allowlist of 28 files with
silent `catch (e) { debugPrint(...) }` patterns. This batch retrofits
4 hot-path services that were the highest-risk in production:

- **health_sync_service.dart** (4 catches) — fires on every splash;
  silent failures meant the device-permission edge cases were
  invisible to Crashlytics.
- **razorpay_service.dart** (8 catches) — payment-flow critical path
  including poll-and-activate retries, session refresh, and the
  inner 409 already_pro handler. Silent failure here = paying user
  sees the upgrade pill stuck on grey with no signal in any
  dashboard.
- **stat_snapshot_service.dart** (5 catches) — onboarding, rank
  promotion, and manual snapshot writes. Silent failure leaves the
  rank-ladder dashboard with no row for the promotion event.
- **subscription_service.dart** (`refreshFromSupabase` catch) —
  the existing `_logRefreshFailure` helper routes to log-client-error
  (server-side `client_errors` table). Added direct Crashlytics
  defense-in-depth: if Edge Functions are down, Crashlytics still
  gets the signal.

Each retrofit:

```dart
} catch (e, st) {
  debugPrint('...');
  unawaited(ErrorTelemetry.recordNonFatal(e, st,
      reason: '<service>_<method>'));
}
```

20 new `op_type` reasons hit the `client_errors` table + Crashlytics
non-fatal dashboard. Dashboard grouping by `op_type` lets us see
which sites are firing most often in production.

Grandfathered set in
`test/contracts/no_silent_debugprint_in_services_test.dart`
updated: 28 → 21 (rank_service + progression_resolver from earlier
batch + the 5 retrofitted now = 7 removed; 21 remaining for future
batches).

## What's deferred to a future batch

The audit also lists:
- ProGuard rules audit, lint rules, .env.example sync, web manifest.
- Dep updates (firebase, share_plus, image_cropper, mobile_scanner).
- `sync_service.dart` split (4000+ line file).
- Wardroom barrel doc sync.
- CLAUDE.md §7 table list refresh.
- APK size analysis (target 100MB → 60MB).
- 21 remaining grandfathered debugPrint sites.

These are scoped for a follow-up cleanup batch — they're cleanup
chores rather than audit-critical fixes. Documented here so the
trail is explicit; per `feedback_no_deferrals.md` if they don't
ship in this batch they MUST ship in the next named batch (not
"someday").

## Suite

1598 pass / 0 fail / 2 skip (unchanged).

## Related

- 7ad0d0 (H-42 first batch — rank_service + progression_resolver)
- CLAUDE.md `ErrorTelemetry.recordNonFatal` funnel
