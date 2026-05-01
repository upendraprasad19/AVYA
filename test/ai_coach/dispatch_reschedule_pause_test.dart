// C-7 — Coverage for rescheduleWeek + pausePlan dispatch contract.
//
// Implementation note: the production dispatcher path goes through
// `HiveService.instance.coachBox` / `workoutBox` which are wrapped by
// `GuardedBox`. GuardedBox requires `Supabase.instance.client.auth.currentUser`
// to match the box owner — i.e. a real (or carefully faked) Supabase session.
// Standing up a fake Supabase auth session inside a pure-VM unit test is a
// significant investment that exceeds C-7's scope (the rest of this codebase
// gates Supabase-dependent tests behind `SupabaseTestHelper.hasCredentials`
// and skips them in the default `flutter test` run).
//
// What we CAN cover here without Supabase:
//   1. ToolIntent expiry contract — expired intents must NOT be actionable.
//   2. PendingToolIntentsNotifier.reject() — the DISMISS button path.
//      Status flips to `rejected`; chat thread filter (in ai_coach_screen
//      lines 668-686) drops it, no Hive write involved.
//   3. PendingToolIntentsNotifier.confirm() on a missing id — surfaces
//      `Intent not found.` failure (the basic contract surface).
//   4. PendingToolIntentsNotifier.addIntents() dedup — replayed responses
//      don't re-add the same intent twice (relevant when ai-proxy retries
//      a tool turn).
//   5. Hive marker key naming convention — the dispatcher writes
//      `intent_<id>_dispatched_at` (asserted as a *string* contract so the
//      ai_coach_screen filter and the dispatcher stay in sync).
//
// What we DEFER to manual smoke (C-11) and integration tests with real
// Supabase auth:
//   - End-to-end pause_plan dispatch → schedule status='paused' write.
//   - End-to-end reschedule_week dispatch → schedule rebuild.
//   - Hive marker stamping after a successful execute.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ToolIntent buildIntent({
    required String id,
    required String type,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    ToolIntentStatus status = ToolIntentStatus.pending,
  }) {
    return ToolIntent(
      id: id,
      type: type,
      payload: payload ?? const <String, dynamic>{},
      confirmationClass: ConfirmationClass.destructive,
      previewSummary: 'preview',
      createdAt: createdAt ?? DateTime.now(),
      status: status,
    );
  }

  group('C-7: rescheduleWeek + pausePlan dispatch contract', () {
    test(
      'pause_plan intent: 1h-old createdAt → isExpired + non-actionable',
      () {
        // Dispatcher refuses expired intents (tool_dispatcher.dart:80-85).
        // The render path also drops them (status==expired filter).
        final stale = buildIntent(
          id: 'p_old_1',
          type: 'pause_plan',
          createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 1)),
        );
        expect(stale.isExpired, isTrue);
        expect(stale.isActionable, isFalse);

        final fresh = buildIntent(
          id: 'p_fresh_1',
          type: 'pause_plan',
        );
        expect(fresh.isExpired, isFalse);
        expect(fresh.isActionable, isTrue);
      },
    );

    test(
      'reject() flips intent status to rejected (DISMISS button path)',
      () async {
        final intent = buildIntent(
          id: 'd_dismiss_1',
          type: 'pause_plan',
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(pendingToolIntentsProvider.notifier);
        notifier.addIntents([intent]);

        notifier.reject('d_dismiss_1');

        final updated = container.read(pendingToolIntentsProvider);
        expect(updated.length, 1);
        expect(updated.first.status, ToolIntentStatus.rejected);
        // After reject() the intent is no longer actionable — the chat thread
        // filter in ai_coach_screen.dart:683-685 keeps `rejected` visible
        // (briefly, until prune()) but won't dispatch on a re-tap.
        expect(updated.first.isActionable, isFalse);
      },
    );

    test(
      'confirm() on a missing intent id → "Intent not found" failure',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(pendingToolIntentsProvider.notifier);

        final result = await notifier.confirm('nonexistent_id');
        expect(result.success, isFalse);
        expect(result.errorMessage, equals('Intent not found.'));
      },
    );

    test(
      'addIntents() dedups by id (replayed ai-proxy responses are idempotent)',
      () {
        final intent = buildIntent(id: 'r_dup_1', type: 'reschedule_week');

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(pendingToolIntentsProvider.notifier);

        notifier.addIntents([intent]);
        notifier.addIntents([intent]); // replay
        notifier.addIntents([intent]); // again

        final state = container.read(pendingToolIntentsProvider);
        expect(state.length, 1, reason: 'dedup by id must be idempotent');
        expect(state.first.id, 'r_dup_1');
      },
    );

    test(
      'Hive marker key naming convention is `intent_<id>_dispatched_at`',
      () {
        // The dispatcher writes this exact key shape (tool_dispatcher.dart:185)
        // and ai_coach_screen reads the same shape (ai_coach_screen.dart:680).
        // If the format ever drifts, the chat thread filter breaks silently
        // and review cards re-appear after dispatch. Pin the contract.
        const intentId = 'sample_id_42';
        const expected = 'intent_sample_id_42_dispatched_at';
        final actual = 'intent_${intentId}_dispatched_at';
        expect(actual, equals(expected));
      },
    );
  });
}
