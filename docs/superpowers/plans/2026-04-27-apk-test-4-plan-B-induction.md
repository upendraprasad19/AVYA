# APK Test #4 Plan B — Induction Flow (3 messages + I COMMIT + 5-question muster)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a new user taps REPORT FOR DUTY on the Plan screen, route them to the Captain's induction sequence (3 paced messages + I COMMIT contract button + 5 muster questions) instead of straight to home. Persist commitment + answers locally and to Supabase. Idempotent — never replays for returning users.

**Architecture:** New `/coach/induction` and `/coach/muster` routes. Two screens managed by an `InductionService` orchestrator. Migration 042 adds `coach_memory.committed_at`, `committed_to_lt_cdr`, `induction_completed_at` + 6 muster answer columns. Hive `coachBox` is the local source of truth; `SyncService.syncCoachMemoryNow()` mirrors to Supabase fire-and-forget.

**Tech Stack:** Flutter, Riverpod, Hive, Supabase Postgres, GoRouter.

**Spec reference:** `docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md` §9.

**Estimated effort:** 8-12h.

**Depends on:** Plan A (snapshot keys for `committed_at`, `why_now`, etc. must already be wired).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `supabase/migrations/042_coach_memory_induction.sql` | CREATE | Add 9 columns to `coach_memory` table |
| `lib/features/ai_coach/screens/induction_screen.dart` | CREATE | 3-message paced intro + I COMMIT button |
| `lib/features/ai_coach/screens/muster_screen.dart` | CREATE | 5-question form, sequential reveal |
| `lib/features/ai_coach/services/induction_service.dart` | CREATE | Orchestration: write Hive, fire sync, navigate |
| `lib/features/ai_coach/widgets/typing_indicator.dart` | CREATE | 1-2s typing dots between messages |
| `lib/core/router/app_router.dart` | MODIFY | Register `/coach/induction`, `/coach/muster`. Update REPORT FOR DUTY redirect logic. |
| `lib/features/onboarding/screens/plan_screen.dart` | MODIFY | After `completeOnboarding()`, redirect to `/coach/induction` if not yet inducted |
| `lib/core/services/sync_service.dart` | MODIFY | Add `syncCoachMemoryNow(userId)` method |
| `test/onboarding/induction_idempotency_test.dart` | CREATE | Asserts induction shows once, never replays |
| `test/onboarding/muster_persistence_test.dart` | CREATE | Asserts 5 answers land in Hive + sync fires |

---

## Task B1 — Migration 042: coach_memory induction columns

**Files:**
- Create: `supabase/migrations/042_coach_memory_induction.sql`

- [ ] **B1.1: Write the migration**

```sql
-- 042_coach_memory_induction.sql
-- Adds induction-related columns to coach_memory.
-- Source of truth: docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md §9.

ALTER TABLE coach_memory
  ADD COLUMN IF NOT EXISTS committed_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS committed_to_lt_cdr   BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS induction_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS why_now               TEXT,
  ADD COLUMN IF NOT EXISTS definition_of_winning TEXT,
  ADD COLUMN IF NOT EXISTS known_injuries        TEXT[],
  ADD COLUMN IF NOT EXISTS typical_wake_time     TEXT,
  ADD COLUMN IF NOT EXISTS preferred_workout_time TEXT,
  ADD COLUMN IF NOT EXISTS body_part_priorities  TEXT[];

COMMENT ON COLUMN coach_memory.committed_at IS
  'When the user tapped I COMMIT on the induction Lt Cdr contract.';
COMMENT ON COLUMN coach_memory.committed_to_lt_cdr IS
  'True after first contract acceptance. Never reset to false.';
COMMENT ON COLUMN coach_memory.induction_completed_at IS
  'When user finished the 5-question muster. Idempotency check key.';
```

- [ ] **B1.2: Apply via MCP**

Use the Supabase MCP `apply_migration` tool against project `dedsavbjuwgarrhphgnl`:

```
project_id: dedsavbjuwgarrhphgnl
name: 042_coach_memory_induction
query: <contents of file>
```

Expected: success. Verify via `list_tables` or direct `SELECT column_name FROM information_schema.columns WHERE table_name = 'coach_memory'`.

- [ ] **B1.3: Commit**

```bash
git add supabase/migrations/042_coach_memory_induction.sql
git commit -m "feat(db): migration 042 — coach_memory induction columns

Adds: committed_at, committed_to_lt_cdr, induction_completed_at +
6 muster answer columns (why_now, definition_of_winning, known_injuries,
typical_wake_time, preferred_workout_time, body_part_priorities).

Applied to dedsavbjuwgarrhphgnl 2026-04-27."
```

---

## Task B2 — Typing indicator widget

**Files:**
- Create: `lib/features/ai_coach/widgets/typing_indicator.dart`

Reusable 3-dot typing animation. Used between the 3 induction messages and elsewhere.

- [ ] **B2.1: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36, height: 12,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            children: List.generate(3, (i) {
              final t = (_ctrl.value + i / 3) % 1.0;
              final opacity = (0.3 + 0.7 * (1 - (t * 2 - 1).abs())).clamp(0.3, 1.0);
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 2),
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
```

- [ ] **B2.2: Commit**

```bash
git add lib/features/ai_coach/widgets/typing_indicator.dart
git commit -m "feat(ai_coach): TypingIndicator widget (3 dots, gold tint)"
```

---

## Task B3 — InductionService orchestrator

**Files:**
- Create: `lib/features/ai_coach/services/induction_service.dart`

Single source for induction state read/write. Idempotency guard lives here.

- [ ] **B3.1: Implement**

```dart
// lib/features/ai_coach/services/induction_service.dart
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class InductionService {
  static final InductionService instance = InductionService._();
  InductionService._();

  bool get hasCommitted =>
    HiveService.instance.coachBox.get('committed_to_lt_cdr') == true;

  bool get inductionCompleted =>
    HiveService.instance.coachBox.get('induction_completed_at') != null;

  Future<void> recordCommitment() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('committed_at', now);
    await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);
    final userId = (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      // Fire-and-forget per CLAUDE.md §15
      // ignore: unawaited_futures
      SyncService.instance.syncCoachMemoryNow(userId);
    }
  }

  Future<void> recordMusterAnswer(String key, dynamic value) async {
    // Allowed keys: why_now, definition_of_winning, known_injuries,
    //               typical_wake_time, preferred_workout_time, body_part_priorities
    const allowed = {
      'why_now', 'definition_of_winning', 'known_injuries',
      'typical_wake_time', 'preferred_workout_time', 'body_part_priorities',
    };
    if (!allowed.contains(key)) {
      throw ArgumentError('Unknown muster key: $key');
    }
    await HiveService.instance.coachBox.put(key, value);
  }

  Future<void> completeMuster() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('induction_completed_at', now);
    final userId = (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      // ignore: unawaited_futures
      SyncService.instance.syncCoachMemoryNow(userId);
      // ignore: unawaited_futures
      SyncService.instance.pushSnapshot();
    }
  }
}
```

- [ ] **B3.2: Add SyncService.syncCoachMemoryNow()**

In `lib/core/services/sync_service.dart`, add:

```dart
Future<void> syncCoachMemoryNow(String userId) async {
  try {
    final coach = HiveService.instance.coachBox;
    final payload = {
      'user_id': userId,
      'committed_at': coach.get('committed_at'),
      'committed_to_lt_cdr': coach.get('committed_to_lt_cdr') ?? false,
      'induction_completed_at': coach.get('induction_completed_at'),
      'why_now': coach.get('why_now'),
      'definition_of_winning': coach.get('definition_of_winning'),
      'known_injuries': coach.get('known_injuries'),
      'typical_wake_time': coach.get('typical_wake_time'),
      'preferred_workout_time': coach.get('preferred_workout_time'),
      'body_part_priorities': coach.get('body_part_priorities'),
    }..removeWhere((k, v) => v == null && k != 'user_id');

    await Supabase.instance.client
      .from('coach_memory')
      .upsert(payload, onConflict: 'user_id')
      .select()
      .single();  // forces error on constraint violation per audit S3 fix
  } catch (e, st) {
    debugPrint('[sync] coach_memory upsert failed: $e');
    // log to client_errors per CLAUDE.md §11
    unawaited(_logClientError('coach_memory_sync_failed', e, st));
  }
}
```

- [ ] **B3.3: Test the service (idempotency)**

Create `test/onboarding/induction_idempotency_test.dart`:

```dart
test('hasCommitted reads from Hive and is false initially', () async {
  await HiveService.instance.coachBox.clear();
  expect(InductionService.instance.hasCommitted, false);
});

test('recordCommitment sets committed flag and committed_at', () async {
  await HiveService.instance.coachBox.clear();
  await InductionService.instance.recordCommitment();
  expect(InductionService.instance.hasCommitted, true);
  expect(HiveService.instance.coachBox.get('committed_at'), isA<String>());
});

test('inductionCompleted is false until completeMuster called', () async {
  await HiveService.instance.coachBox.clear();
  await InductionService.instance.recordCommitment();
  expect(InductionService.instance.inductionCompleted, false);
  await InductionService.instance.completeMuster();
  expect(InductionService.instance.inductionCompleted, true);
});
```

- [ ] **B3.4: Run, commit**

```bash
flutter test test/onboarding/induction_idempotency_test.dart
git add -A
git commit -m "feat(ai_coach): InductionService orchestrator + syncCoachMemoryNow

- Idempotency guards (hasCommitted, inductionCompleted)
- recordCommitment / recordMusterAnswer / completeMuster
- Fire-and-forget sync to Supabase coach_memory per CLAUDE.md §15"
```

---

## Task B4 — Induction Screen (3 messages + I COMMIT)

**Files:**
- Create: `lib/features/ai_coach/screens/induction_screen.dart`

3 paced messages with typing indicators between. After Message 2, the I COMMIT button appears. Tap → records commitment + transitions to muster.

- [ ] **B4.1: Implement screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/ai_coach/widgets/typing_indicator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class InductionScreen extends ConsumerStatefulWidget {
  const InductionScreen({super.key});
  @override
  ConsumerState<InductionScreen> createState() => _InductionScreenState();
}

class _InductionScreenState extends ConsumerState<InductionScreen> {
  int _stage = 0;  // 0=hidden 1=msg1 2=typing 3=msg2 4=typing 5=msg3+button 6=button-pressed
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance(1));
  }

  Future<void> _advance(int target) async {
    if (target == 1 || target == 3 || target == 5) {
      setState(() => _stage = target - 1);  // typing first
      await Future.delayed(Duration(milliseconds: 1400));
      setState(() => _stage = target);
    } else {
      setState(() => _stage = target);
    }
  }

  Future<void> _onCommit() async {
    setState(() => _committed = true);
    await InductionService.instance.recordCommitment();
    if (!mounted) return;
    // Brief pause for user to feel the commit, then proceed
    await Future.delayed(Duration(milliseconds: 600));
    if (!mounted) return;
    context.go('/coach/muster');
  }

  String get _userFirstName {
    final profile = HiveService.instance.userBox.get('profile') as Map?;
    final name = profile?['full_name'] as String?;
    if (name == null || name.isEmpty) return 'Recruit';
    return name.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 40),
              if (_stage >= 1) _buildMessage1(),
              if (_stage == 2 || _stage == 4) Padding(padding: EdgeInsets.symmetric(vertical: 12), child: TypingIndicator()),
              if (_stage >= 3) _buildMessage2(),
              if (_stage >= 5) _buildMessage3(),
              if (_stage >= 5 && !_committed)
                Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: WardButton(
                    label: 'I COMMIT.',
                    onPressed: _onCommit,
                  ),
                ),
              if (_committed) Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: Text('Contract sealed.',
                    style: AppTypography.title.copyWith(color: AppColors.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessage1() {
    return _CoachBubble(
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Recruit ${_userFirstName} — welcome aboard.\n\n'),
          TextSpan(text: 'I am your AI Coach. I have trained sailors at sea and recruits in the gym for longer than I care to count. I will be working you through this deployment — your first 12 weeks and beyond. You will know me by my voice. I will know you by your data.\n\n'),
          TextSpan(text: "Here's the deal, plain.\n\n"),
          TextSpan(text: 'Show up. Log honestly. Don\'t lie to me about reps or meals — I see the numbers, I just want them straight. Follow the plan I write for you. Tell me when something hurts. Tell me when life happens.'),
        ]),
        style: AppTypography.body,
      ),
    );
  }

  Widget _buildMessage2() {
    return _CoachBubble(
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'In return, here\'s what I commit:\n\n'),
          TextSpan(
            text: 'Make Lieutenant Commander rank — 200 workouts on this app — and your life will change. Physically, and in every possible way I can measure. That\'s not a slogan. That\'s a guarantee.\n\n',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: '200 workouts is roughly twelve months of disciplined training. Most don\'t make it past month two. The ones who do — they don\'t recognize themselves in the mirror, in their work, in their relationships. Compounding return. I\'ve seen it happen. I\'ll show you the way.\n\n'),
          TextSpan(text: 'Tap below to seal it.'),
        ]),
        style: AppTypography.body,
      ),
    );
  }

  Widget _buildMessage3() {
    return _CoachBubble(
      child: Text(
        'Before we deploy, your file is missing a few entries. Quick muster — five questions, three minutes. Then we\'re operational.',
        style: AppTypography.body,
      ),
    );
  }
}

class _CoachBubble extends StatelessWidget {
  final Widget child;
  const _CoachBubble({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
```

- [ ] **B4.2: Manual smoke check**

Run app, force user to un-inducted state (`coachBox.clear()`), navigate to `/coach/induction`. Verify:
- Message 1 appears immediately
- ~1.4s typing indicator → Message 2 appears (with gold-emphasized commitment line)
- ~1.4s typing indicator → Message 3 + I COMMIT button
- Tap I COMMIT → "Contract sealed." → navigates to `/coach/muster`

- [ ] **B4.3: Commit**

```bash
git add lib/features/ai_coach/screens/induction_screen.dart
git commit -m "feat(ai_coach): InductionScreen — 3 paced messages + I COMMIT button

Paced reveal: Msg1 (intro) → typing → Msg2 (Lt Cdr promise, gold-emphasized) →
typing → Msg3 (muster bridge) + I COMMIT button. Tap records commitment via
InductionService and routes to /coach/muster."
```

---

## Task B5 — Muster Screen (5 questions, sequential reveal)

**Files:**
- Create: `lib/features/ai_coach/screens/muster_screen.dart`

5 questions (per spec §9.4). Q1 (why now) is free text. Q2 (winning) free text. Q3 (injuries) free text + skip. Q4 (wake/workout time) two time pickers. Q5 (body parts) multi-select chips.

- [ ] **B5.1: Implement screen with progressive reveal**

Pseudocode shape (full implementation follows the Q-list per §9.4):

```dart
class MusterScreen extends StatefulWidget {
  // Sequential reveal: Q1 visible → answered → Q2 reveals → ... → after Q5 → completeMuster + navigate /home
  // Each answer calls InductionService.recordMusterAnswer(key, value) immediately on commit
  // Final tap → completeMuster() + GoRouter.go('/home')
}
```

Key keys to use (matching B1 migration column names):
- Q1 key: `'why_now'` (String)
- Q2 key: `'definition_of_winning'` (String)
- Q3 key: `'known_injuries'` (List<String>) — split on commas, strip whitespace, default `['none']` if user skips
- Q4 keys: `'typical_wake_time'` and `'preferred_workout_time'` (Strings, format "HH:mm")
- Q5 key: `'body_part_priorities'` (List<String>) — each from {Back, Chest, Shoulders, Arms, Legs, Glutes, Core}

After Q5 confirmed:

```dart
await InductionService.instance.completeMuster();
if (!mounted) return;
// Final coach message before nav
await _showFinalBrief();  // "Muster complete, Recruit. File updated. Tomorrow at 06:30 IST you receive your first daily brief. Carry on."
context.go('/home');
```

- [ ] **B5.2: Test answer persistence**

Create `test/onboarding/muster_persistence_test.dart`:

```dart
test('all 5 muster answers land in Hive', () async {
  await HiveService.instance.coachBox.clear();
  await InductionService.instance.recordMusterAnswer('why_now', 'wedding in October');
  await InductionService.instance.recordMusterAnswer('definition_of_winning', 'feel strong');
  await InductionService.instance.recordMusterAnswer('known_injuries', ['lower back']);
  await InductionService.instance.recordMusterAnswer('typical_wake_time', '06:30');
  await InductionService.instance.recordMusterAnswer('preferred_workout_time', '07:00');
  await InductionService.instance.recordMusterAnswer('body_part_priorities', ['back', 'shoulders']);

  expect(HiveService.instance.coachBox.get('why_now'), 'wedding in October');
  expect(HiveService.instance.coachBox.get('known_injuries'), ['lower back']);
  expect(HiveService.instance.coachBox.get('body_part_priorities'), ['back', 'shoulders']);
});

test('recordMusterAnswer rejects unknown key', () async {
  expect(() => InductionService.instance.recordMusterAnswer('blah', 'x'),
    throwsArgumentError);
});
```

- [ ] **B5.3: Run, commit**

```bash
flutter test test/onboarding/muster_persistence_test.dart
git add -A
git commit -m "feat(ai_coach): MusterScreen — 5-question induction interview

Q1 why_now, Q2 definition_of_winning, Q3 known_injuries, Q4 typical_wake_time +
preferred_workout_time, Q5 body_part_priorities. Sequential reveal. Each answer
persisted via InductionService. Final completeMuster() fires sync + pushSnapshot."
```

---

## Task B6 — Router wiring + idempotency redirect

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/onboarding/screens/plan_screen.dart`

After REPORT FOR DUTY tap, route to `/coach/induction` if not yet inducted, else `/home`.

- [ ] **B6.1: Register routes**

In `app_router.dart`, add to the GoRouter routes list:

```dart
GoRoute(
  path: '/coach/induction',
  builder: (_, __) => const InductionScreen(),
),
GoRoute(
  path: '/coach/muster',
  builder: (_, __) => const MusterScreen(),
),
```

- [ ] **B6.2: Update REPORT FOR DUTY handler in plan_screen.dart**

Find the `_onReportForDuty` (or equivalent) handler. After `OnboardingNotifier.completeOnboarding()` succeeds, replace the current navigation with:

```dart
final inducted = InductionService.instance.inductionCompleted;
if (mounted) {
  context.go(inducted ? '/home' : '/coach/induction');
}
```

- [ ] **B6.3: Add redirect guard for direct visits**

In `_authRedirect` of `app_router.dart`, add a guard so that:
- Returning users (already inducted) navigating to `/coach/induction` → bounced to `/home`
- New users skipping onboarding directly to `/home` → not affected (separate concern)

```dart
final isInductionRoute = location == '/coach/induction' || location == '/coach/muster';
if (isInductionRoute && InductionService.instance.inductionCompleted) {
  return '/home';
}
```

- [ ] **B6.4: Idempotency end-to-end test**

Update `test/onboarding/induction_idempotency_test.dart`:

```dart
testWidgets('REPORT FOR DUTY routes to induction for new user', (tester) async {
  await HiveService.instance.coachBox.clear();
  // ... setup widget ...
  // Tap REPORT FOR DUTY
  // Verify navigation went to /coach/induction (not /home)
});

testWidgets('REPORT FOR DUTY routes to home for already-inducted user', (tester) async {
  await HiveService.instance.coachBox.clear();
  await InductionService.instance.recordCommitment();
  await InductionService.instance.completeMuster();
  // Tap REPORT FOR DUTY
  // Verify navigation went to /home (not /coach/induction)
});
```

- [ ] **B6.5: Run, commit**

```bash
flutter test test/onboarding/induction_idempotency_test.dart
git add -A
git commit -m "feat(router): wire /coach/induction + /coach/muster + idempotency guard

- New users (REPORT FOR DUTY) → /coach/induction
- Returning users (already inducted) → /home (bypass)
- Direct visits to induction route by inducted users → bounced to /home"
```

---

## Task B7 — Logout/restore behavior verification

**Files:**
- Modify: `lib/features/auth/screens/restoring_screen.dart` (if needed)

When user logs out + back in, the cloud `coach_memory.induction_completed_at` must be pulled into local Hive on restore so they don't see induction again.

- [ ] **B7.1: Verify SyncService.restoreFromCloud pulls coach_memory**

```bash
grep -n "coach_memory" lib/core/services/sync_service.dart
```

If `restoreFromCloud()` doesn't include coach_memory in its parallel restore tasks, add it.

- [ ] **B7.2: If missing, add restore method**

```dart
Future<void> _restoreCoachMemory(String userId) async {
  try {
    final row = await Supabase.instance.client
      .from('coach_memory')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
    if (row == null) return;
    final coach = HiveService.instance.coachBox;
    for (final key in [
      'committed_at', 'committed_to_lt_cdr', 'induction_completed_at',
      'why_now', 'definition_of_winning', 'known_injuries',
      'typical_wake_time', 'preferred_workout_time', 'body_part_priorities',
    ]) {
      if (row[key] != null) {
        await coach.put(key, row[key]);
      }
    }
  } catch (e) {
    debugPrint('[restore] coach_memory failed: $e');
  }
}
```

Wire into `restoreFromCloud` task list.

- [ ] **B7.3: Test the restore flow**

```dart
testWidgets('logout + login skips induction if previously completed', (tester) async {
  // 1. Simulate: user previously completed induction (cloud has the row)
  // 2. Local Hive cleared (logout effect)
  // 3. Login → restoreFromCloud → coach_memory pulled
  // 4. Verify InductionService.inductionCompleted is true
});
```

- [ ] **B7.4: Run, commit**

```bash
flutter test
git add -A
git commit -m "feat(sync): pull coach_memory on restoreFromCloud

Returning users skip induction after logout/login because cloud
induction_completed_at is mirrored back into local coachBox."
```

---

## Self-review

- [ ] Spec §9 fully covered: 3 messages (B4), I COMMIT (B3+B4), 5 muster questions (B5), persistence (B3+sync), idempotency (B6), restore (B7)
- [ ] Migration 042 has 9 columns matching spec §9 exactly
- [ ] Hive keys consistent: `committed_at`, `committed_to_lt_cdr`, `induction_completed_at`, `why_now`, `definition_of_winning`, `known_injuries`, `typical_wake_time`, `preferred_workout_time`, `body_part_priorities`
- [ ] These match Plan A's snapshot key reads (Task A8)
- [ ] No placeholders. Where MusterScreen UI is sketched (B5.1), the keys + question texts are explicit per spec §9.4

## Out of scope (handled elsewhere)

- Snapshot keys for committed_at / muster answers → Plan A (Task A8)
- Captain's Manual references to committed_at → Plan A (Task A1, Section 2)
- Promotion ceremonies, why-now recall in chat → Plan C
- Audit P0/P1 cleanup → Plan D
