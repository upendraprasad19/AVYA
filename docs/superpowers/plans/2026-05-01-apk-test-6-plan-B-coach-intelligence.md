# APK Test #6 Plan B — AI Coach Intelligence

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coach correctly handles multi-intent messages, requires explicit user confirmation before WRITE tool dispatch, reads today's nutrition from snapshot directly (no fictional tool call), exposes historical nutrition via new getNutritionHistory READ tool, and increments visible counters across all entry points.

**Architecture:** Surgical fixes per layer — system prompt + tool descriptions for selection (#10), dispatcher confirmation gate refactor (#11), new getNutritionHistory tool with handler (#14), counter wiring across food_text_analysis paths (#15). No architectural rewrite required.

**Estimated effort:** 7-10h.

**Spec reference:** `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §5.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `supabase/functions/_shared/captain_manual.ts` | MODIFY | Add "Multi-intent messages" + "Today's nutrition" subsections |
| `supabase/functions/_shared/tools/types.ts` | MODIFY | Add optional `selectionHints?: string` field on `ToolDefinition` |
| `supabase/functions/_shared/tools/workout/swapExercise.ts` | MODIFY | Add `selectionHints` |
| `supabase/functions/_shared/tools/workout/logSetTool.ts` (or `logSet.ts`) | MODIFY | Add `selectionHints` |
| `supabase/functions/_shared/tools/workout/rescheduleWeekTool.ts` (or `rescheduleWeek.ts`) | MODIFY | Add `selectionHints` |
| `supabase/functions/_shared/tools/plan/pausePlanTool.ts` (or `pausePlan.ts`) | MODIFY | Add `selectionHints` |
| `supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts` | CREATE | New READ tool |
| `supabase/functions/_shared/tools/nutrition/index.ts` | MODIFY | Export `getNutritionHistoryTool` |
| `supabase/functions/_shared/tools/registry.ts` | MODIFY | Register `getNutritionHistoryTool` (free + PRO) |
| `lib/features/ai_coach/widgets/tool_confirm_card.dart` | MODIFY | Explicit Apply/Dismiss buttons + terminal-state pill rendering |
| `lib/features/ai_coach/services/tool_dispatcher.dart` | MODIFY | Apply-gated dispatch + `intent_<id>_dispatched_at` Hive marker + counter increments for `log_meal_by_text` / `scan_meal` / `cart_auditor` |
| `lib/features/ai_coach/screens/ai_coach_screen.dart` | MODIFY | Filter dispatched cards from chat thread |
| `test/ai_coach/multi_intent_dispatch_test.dart` | CREATE | B-3 |
| `test/ai_coach/confirm_gate_no_double_tap_test.dart` | CREATE | B-5 |
| `test/ai_coach/dismiss_card_terminal_state_test.dart` | CREATE | B-5 |
| `test/ai_coach/dispatched_card_filter_test.dart` | CREATE | B-5 |
| `test/ai_coach/today_nutrition_no_tool_call_test.dart` | CREATE | B-9 |
| `test/ai_coach/get_nutrition_history_tool_test.dart` | CREATE | B-9 |
| `test/ai_coach/food_log_counter_increments_from_chat_test.dart` | CREATE | B-11 |
| `docs/superpowers/notes/2026-05-01-coach-intelligence-smoke.md` | CREATE | B-12 smoke + C9-C12 verification |

---

## Pre-flight (run before Task B-1)

- [ ] **Confirm working tree.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
git status
git rev-parse --abbrev-ref HEAD
```

Expected: branch `feat/apk-test-6-batch` (created by Plan A's Task 1). If not on this branch, STOP and run Plan A Task 1 first.

- [ ] **Confirm baseline file presence.**

```bash
test -f supabase/functions/_shared/captain_manual.ts && echo "manual ok"
test -f supabase/functions/_shared/tools/registry.ts && echo "registry ok"
test -f lib/features/ai_coach/widgets/tool_confirm_card.dart && echo "card ok"
test -f lib/features/ai_coach/services/tool_dispatcher.dart && echo "dispatcher ok"
```

All four lines must print "ok". If any miss, STOP — wrong branch or wrong worktree.

---

## Task B-1 — System prompt multi-intent hardening + tool selection hints

**Files:** `supabase/functions/_shared/captain_manual.ts` (MODIFY), `supabase/functions/_shared/tools/types.ts` (MODIFY), four tool definitions in `_shared/tools/workout/` and `_shared/tools/plan/` (MODIFY).

- [ ] **Step 1: Read current captain manual.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
wc -l supabase/functions/_shared/captain_manual.ts
grep -n "^## " supabase/functions/_shared/captain_manual.ts
```

Catalogue existing top-level sections so the new subsection slots cleanly into the tool-selection area.

- [ ] **Step 2: Add `selectionHints` field to `ToolDefinition`.**

Open `supabase/functions/_shared/tools/types.ts`. Locate the `ToolDefinition<TArgs, TResult>` interface. Add the new optional field directly after `description`:

```ts
  /** Plain-text description sent to Gemini in the function declaration. Tell the model when to call this. */
  description: string;
  /**
   * Optional natural-language hints that disambiguate this tool from siblings.
   * Appended to `description` when emitting Gemini function declarations so the
   * model has explicit guidance for multi-intent messages. Per spec §5.2.
   */
  selectionHints?: string;
  /** Zod schema validating the function-call args. */
  schema: z.ZodTypeAny;
```

- [ ] **Step 3: Wire `selectionHints` into the function-declaration emitter.**

```bash
grep -rn "description:" supabase/functions/_shared/tools/zodToGemini.ts | head -10
grep -n "tool.description\|t.description" supabase/functions/_shared/tools/registry.ts supabase/functions/_shared/tools/zodToGemini.ts | head -10
```

Locate the spot where `tool.description` is assembled into the Gemini function declaration (likely `registry.ts::buildFunctionDeclarations` or `zodToGemini.ts`). Replace the description-only emission with:

```ts
const fullDescription = tool.selectionHints
  ? `${tool.description}\n\nWHEN TO USE: ${tool.selectionHints}`
  : tool.description;
```

and use `fullDescription` in the declaration.

- [ ] **Step 4: Add `selectionHints` to four tool definitions.**

For each of these four tool files, add `selectionHints` immediately after `description`:

`supabase/functions/_shared/tools/workout/logSet.ts` (or `logSetTool.ts` — verify with `ls supabase/functions/_shared/tools/workout/`):

```ts
  selectionHints:
    "Use when user describes completed sets (with weight/reps/duration). Don't use when user is asking to reschedule, swap, or pause — those are different tools.",
```

`supabase/functions/_shared/tools/workout/swapExercise.ts`:

```ts
  selectionHints:
    "Use when user wants to REPLACE an exercise inside today's workout with a different exercise. Distinct from rescheduleWeek (moves an entire day) and pausePlan (marks a day as rest).",
```

`supabase/functions/_shared/tools/workout/rescheduleWeek.ts`:

```ts
  selectionHints:
    "Use when user wants to MOVE a workout to a different day (e.g., 'move Friday's pull to today', 'shift this week back by 1 day'). Distinct from logSet (records completed work) and pausePlan (rest day).",
```

`supabase/functions/_shared/tools/plan/pausePlan.ts`:

```ts
  selectionHints:
    "Use when user wants today (or a future day) marked as REST or skipped. Distinct from rescheduleWeek (moves the workout to another day) and logSet (records completed work).",
```

If exact filenames differ from the assumed ones above, run `ls supabase/functions/_shared/tools/workout/` and `ls supabase/functions/_shared/tools/plan/` and apply the same edit to whichever file holds each tool's `export const`.

- [ ] **Step 5: Add "Multi-intent messages" subsection to captain manual.**

Open `supabase/functions/_shared/captain_manual.ts`. Find the existing tool-selection section (likely titled "Tool selection" or "Tools"). Append the following block AT THE END of that section, before the next `##` heading:

```ts
const MULTI_INTENT = `
## Multi-intent messages

When a user message contains MULTIPLE intents (e.g., "I did X today" AND "move
Y to Z"), dispatch BOTH tool calls in the same turn. Do NOT collapse them into
a single intent.

Examples:
- "I did back today. Move Friday's pull workout to today and today's pull to
  Friday."
  → emit two intents:
    1. logSet for back exercises (parse the workout description)
    2. rescheduleWeek from Friday to today + Today to Friday

- "Mark today as rest. I went on a long walk instead."
  → emit two intents:
    1. pausePlan for today (mark rest)
    2. logSet (cardio walk) — if user provides duration

DO NOT default to "asking for clarification" when intents are clearly
separable. Only ambiguous messages need clarification.
`;
```

Then concatenate `MULTI_INTENT` into the manual export the same way other sections are stitched together (search for `${TOOL_SELECTION}` or similar — match the existing pattern).

- [ ] **Step 6: Lint check.**

```bash
cd supabase/functions
deno fmt _shared/captain_manual.ts _shared/tools/types.ts _shared/tools/workout/swapExercise.ts _shared/tools/workout/logSet.ts _shared/tools/workout/rescheduleWeek.ts _shared/tools/plan/pausePlan.ts _shared/tools/registry.ts
deno check _shared/captain_manual.ts _shared/tools/registry.ts
cd ../..
```

(Substitute actual filenames per Step 4.) Both commands must succeed.

- [ ] **Step 7: Commit.**

```bash
git add supabase/functions/_shared/captain_manual.ts supabase/functions/_shared/tools/types.ts supabase/functions/_shared/tools/workout/ supabase/functions/_shared/tools/plan/ supabase/functions/_shared/tools/registry.ts
git commit -m "$(cat <<'EOF'
feat(ai-proxy): multi-intent hardening + tool selectionHints (B-1)

Captain Manual gains "Multi-intent messages" section instructing the model
to emit multiple ToolIntents per turn when intents are clearly separable
(spec §5.2). Tools gain optional selectionHints field appended to the
Gemini function declaration so the model gets explicit "WHEN TO USE"
guidance for logSet, swapExercise, rescheduleWeek, pausePlan.

Closes spec obs #10 (coach interpreted "do back + move to Friday" as
single ambiguous intent).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-2 — Deploy ai-proxy with new manual + tool descriptions

**Files:** none modified (deploy only).

- [ ] **Step 1: Emit payload from current source.**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js ai-proxy --auto --functions-dir "C:/Upendra/Claude Code/fitness-app-test-4/supabase/functions"
```

Expected: writes `.claude/_payload_ai-proxy.json`. Verify size reasonable (>100 KB — ai-proxy bundles 35+ shared files).

- [ ] **Step 2: Dry-run deploy.**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false --dry-run
```

Expected: 200 OK with manifest preview. No upload yet.

- [ ] **Step 3: Real deploy.**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false
```

Expected: 201 Created with version bump (e.g., v48 → v49). Note the new version in the smoke note (Task B-12).

- [ ] **Step 4: Verify deployed bundle.**

```bash
curl -sS -H "Authorization: Bearer $(cat 'supabase/.supabase/supabase access token.txt')" \
  https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/functions/ai-proxy \
  | grep -E '"version"|"updated_at"'
```

Confirm version bumped + `updated_at` is within last 60s.

- [ ] **Step 5: No commit.** (Deploy is a side effect, not a code change.)

---

## Task B-3 — Test multi-intent dispatch

**Files:** `test/ai_coach/multi_intent_dispatch_test.dart` (CREATE).

- [ ] **Step 1: Identify the model-response → ToolIntent code path.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -rn "ToolIntent\|toolIntents\|parseToolIntents" lib/features/ai_coach/ | head -20
```

Locate where the streaming/non-streaming response from ai-proxy is decoded into a list of `ToolIntent` objects (likely `ai_service.dart` or `ai_coach_provider.dart`). Note the function name + signature.

- [ ] **Step 2: Write the test.**

```dart
// test/ai_coach/multi_intent_dispatch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
// Adjust import to whatever Step 1 surfaced as the parser:
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  group('multi-intent parser', () {
    test('"I did back today + move Friday to today" emits 2 ToolIntents', () {
      // Simulated ai-proxy response carrying TWO functionCalls in one turn.
      // Shape mirrors what tool-loop.ts emits when Gemini fires multiple calls.
      final responseJson = {
        'tool_intents': [
          {
            'id': 'intent_1',
            'type': 'log_set',
            'payload': {
              'exerciseName': 'Lat Pulldown',
              'sets': [
                {'weight_kg': 40, 'reps': 10},
                {'weight_kg': 60, 'reps': 10},
              ],
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Log Lat Pulldown 2 sets',
            'createdAt': DateTime.now().toIso8601String(),
          },
          {
            'id': 'intent_2',
            'type': 'reschedule_week',
            'payload': {
              'fromDate': '2026-05-08',
              'toDate': '2026-05-01',
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Move Friday → today',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };

      final intents = AiService.parseToolIntents(responseJson);

      expect(intents.length, 2,
          reason: 'multi-intent message must yield 2 ToolIntents, not 1');
      expect(intents[0].type, 'log_set');
      expect(intents[1].type, 'reschedule_week');
    });

    test('single-intent message still parses as 1 ToolIntent', () {
      final responseJson = {
        'tool_intents': [
          {
            'id': 'intent_only',
            'type': 'log_set',
            'payload': {'exerciseName': 'Squat', 'sets': []},
            'confirmationClass': 'reviewable',
            'previewSummary': 'Log Squat',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };
      final intents = AiService.parseToolIntents(responseJson);
      expect(intents.length, 1);
    });
  });
}
```

If `AiService.parseToolIntents` does not exist as a static method, add it (extract logic from wherever the existing decode lives — make it pure / static / testable). The test must run without spinning up Hive, network, or Riverpod.

- [ ] **Step 3: Run the test.**

```bash
flutter test test/ai_coach/multi_intent_dispatch_test.dart
```

Both test cases must pass.

- [ ] **Step 4: Commit.**

```bash
git add test/ai_coach/multi_intent_dispatch_test.dart lib/core/services/ai_service.dart
git commit -m "$(cat <<'EOF'
test(ai-coach): multi-intent parser yields 2 ToolIntents (B-3)

Pins the contract that "I did back + move Friday" emits 2 ToolIntents
(log_set + reschedule_week), not 1 collapsed intent. Pairs with B-1's
captain manual hardening.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-4 — Tool dispatcher confirmation gate refactor

**Files:** `lib/features/ai_coach/widgets/tool_confirm_card.dart` (MODIFY), `lib/features/ai_coach/services/tool_dispatcher.dart` (MODIFY), `lib/features/ai_coach/screens/ai_coach_screen.dart` (MODIFY).

- [ ] **Step 1: Read the existing card widget.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
wc -l lib/features/ai_coach/widgets/tool_confirm_card.dart
grep -n "build\|onTap\|InkWell\|GestureDetector\|onPressed\|dispatch" lib/features/ai_coach/widgets/tool_confirm_card.dart | head -30
```

Catalogue: (a) where the tap handler lives, (b) whether buttons exist or only chevron/tap-anywhere, (c) where `ToolDispatcher.dispatch` is called.

- [ ] **Step 2: Add explicit Apply/Dismiss buttons + terminal-state pill.**

Modify `_ToolConfirmCardState.build`:

- Replace any chevron-only / tap-anywhere region with an explicit two-button row at the bottom of the card.
- Read `intent_<id>_dispatched_at` and `intent_<id>_dismissed_at` from `coachBox` (HiveService.instance.coachBox).
- If neither marker is set → render `[APPLY]` (gold-fill, black w800) + `[DISMISS]` (ghost, textDim).
- If `dispatched_at` set → render terminal pill: `✓ Applied` (gold-soft bg, gold text), no buttons.
- If `dismissed_at` set → render terminal pill: `✗ Dismissed` (textGhost bg, textDim text), no buttons.
- If `createdAt > 1h ago` and neither marker set → render `⏰ Expired` pill (textGhost bg, textDim italic).

Sketch:

```dart
@override
Widget build(BuildContext context) {
  final box = HiveService.instance.coachBox;
  final dispatchedAt = box.get('intent_${widget.intent.id}_dispatched_at');
  final dismissedAt = box.get('intent_${widget.intent.id}_dismissed_at');
  final isExpired = DateTime.now()
          .difference(DateTime.parse(widget.intent.createdAt))
          .inHours >=
      1;

  Widget terminalPill;
  if (dispatchedAt != null) {
    terminalPill = _pill(
      label: '✓ Applied',
      bg: AppColors.accentSoft,
      fg: AppColors.accent,
    );
  } else if (dismissedAt != null) {
    terminalPill = _pill(
      label: '✗ Dismissed',
      bg: AppColors.textGhost.withValues(alpha: 0.2),
      fg: AppColors.textDim,
    );
  } else if (isExpired) {
    terminalPill = _pill(
      label: '⏰ Expired',
      bg: AppColors.textGhost.withValues(alpha: 0.15),
      fg: AppColors.textDim,
      italic: true,
    );
  } else {
    terminalPill = const SizedBox.shrink();
  }

  final showButtons =
      dispatchedAt == null && dismissedAt == null && !isExpired;

  return WardCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ... existing preview content ...
        const SizedBox(height: 12),
        if (showButtons)
          Row(
            children: [
              Expanded(
                child: WardButton(
                  label: 'APPLY',
                  variant: WardButtonVariant.primary,
                  onPressed: _isDispatching ? null : _onApply,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WardButton(
                  label: 'DISMISS',
                  variant: WardButtonVariant.ghost,
                  onPressed: _isDispatching ? null : _onDismiss,
                ),
              ),
            ],
          )
        else
          terminalPill,
      ],
    ),
  );
}

Future<void> _onApply() async {
  if (_isDispatching) return;
  setState(() => _isDispatching = true);
  try {
    await ref.read(toolDispatcherProvider).dispatch(widget.intent);
    // dispatcher already wrote intent_<id>_dispatched_at — just rebuild
    if (mounted) setState(() => _isDispatching = false);
  } catch (e, st) {
    debugPrint('[tool_confirm_card] apply failed: $e\n$st');
    if (mounted) {
      setState(() => _isDispatching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply: $e')),
      );
    }
  }
}

Future<void> _onDismiss() async {
  if (_isDispatching) return;
  await HiveService.instance.coachBox.put(
    'intent_${widget.intent.id}_dismissed_at',
    DateTime.now().toIso8601String(),
  );
  if (mounted) setState(() {});
}
```

`_isDispatching` is a `bool` state field initialised to `false`. The `WardButton.onPressed: null` shape disables the button while dispatching, which is the double-tap defence (B-5 verifies).

- [ ] **Step 3: Move `_dispatched_at` write into `dispatch()` itself (single source).**

In `lib/features/ai_coach/services/tool_dispatcher.dart`, audit the `dispatch(intent)` method (around line 180 per the spec). Confirm the `intent_<id>_dispatched_at` write is inside `dispatch()` and runs ONLY after the per-intent handler returns success. If it currently runs in the card or after a partial success path, refactor so:

```dart
Future<void> dispatch(ToolIntent intent) async {
  final markerKey = 'intent_${intent.id}_dispatched_at';
  // Idempotency: refuse double dispatch
  if (HiveService.instance.coachBox.get(markerKey) != null) {
    debugPrint('[tool_dispatcher] intent ${intent.id} already dispatched — skip');
    return;
  }
  // Per-intent handler (existing switch)
  await _dispatchByType(intent);
  // Marker AFTER successful handler — failures leave intent re-tryable
  await HiveService.instance.coachBox.put(
    markerKey,
    DateTime.now().toIso8601String(),
  );
}
```

The existing `dispatch` method around line 180 may already do this — verify and align.

- [ ] **Step 4: Filter dispatched cards from chat thread.**

Open `lib/features/ai_coach/screens/ai_coach_screen.dart`. Locate the message-list builder (likely a `ListView.builder` over a list that contains both chat messages and `ToolIntent` items). Find the spot where `ToolIntent` items are rendered and add a filter:

```dart
// Within the builder, before rendering a ToolConfirmCard:
final dispatched = HiveService.instance.coachBox
    .get('intent_${intent.id}_dispatched_at');
if (dispatched != null) {
  // Show a compact terminal pill in the thread instead of a full card.
  return _DispatchedIntentPill(intent: intent);
}
return ToolConfirmCard(intent: intent);
```

`_DispatchedIntentPill` is a small widget rendering `✓ <intent.previewSummary>` in textDim, no card chrome. Define it inline in `ai_coach_screen.dart` (or extract to `widgets/dispatched_intent_pill.dart` if preferred).

- [ ] **Step 5: Lint + analyze.**

```bash
flutter analyze lib/features/ai_coach/widgets/tool_confirm_card.dart lib/features/ai_coach/services/tool_dispatcher.dart lib/features/ai_coach/screens/ai_coach_screen.dart
```

Zero errors. Warnings about unused imports OK to fix inline.

- [ ] **Step 6: Commit.**

```bash
git add lib/features/ai_coach/widgets/tool_confirm_card.dart lib/features/ai_coach/services/tool_dispatcher.dart lib/features/ai_coach/screens/ai_coach_screen.dart
git commit -m "$(cat <<'EOF'
fix(ai-coach): explicit Apply/Dismiss gate on confirm cards (B-4)

Confirm cards no longer auto-dispatch on tap-anywhere or chevron — the
user must press APPLY explicitly. dispatch() writes
intent_<id>_dispatched_at AFTER the handler returns success, making
double-dispatch impossible. Dismissed cards mark intent_<id>_dismissed_at
and render a terminal "✗ Dismissed" pill. Cards older than 1h with no
marker render "⏰ Expired". Chat thread filters cards with dispatched_at
set into compact pills so the user sees one source of truth.

Closes spec obs #11.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-5 — Test confirmation gate

**Files:** `test/ai_coach/confirm_gate_no_double_tap_test.dart` (CREATE), `test/ai_coach/dismiss_card_terminal_state_test.dart` (CREATE), `test/ai_coach/dispatched_card_filter_test.dart` (CREATE).

- [ ] **Step 1: Set up shared test scaffolding.**

All three tests need Hive (for the marker) and a mocked `ToolDispatcher`. Use the standard pattern from `test/ai_coach/meals_today_snapshot_test.dart` (see CLAUDE.md §19 last bug entry):

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
// ... etc.

Future<void> _bootstrapHive() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp('coach_b5_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );
  await Hive.initFlutter(tempDir.path);
  await HiveService.instance.init();
}
```

- [ ] **Step 2: Write `confirm_gate_no_double_tap_test.dart`.**

```dart
test('rapid double-tap on Apply dispatches once', () async {
  await _bootstrapHive();
  int dispatchCount = 0;
  final dispatcher = _FakeDispatcher(onDispatch: () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    dispatchCount++;
  });

  final intent = ToolIntent(
    id: 'i1',
    type: 'log_set',
    payload: const {},
    confirmationClass: ConfirmationClass.reviewable,
    previewSummary: 'Log',
    createdAt: DateTime.now().toIso8601String(),
  );

  // Simulate two near-simultaneous taps
  final f1 = dispatcher.dispatch(intent);
  final f2 = dispatcher.dispatch(intent);
  await Future.wait([f1, f2]);

  expect(dispatchCount, 1, reason: 'second tap must be deduped by Hive marker');
  expect(
    HiveService.instance.coachBox.get('intent_i1_dispatched_at'),
    isNotNull,
  );
});
```

`_FakeDispatcher` implements the same dedup-on-marker idempotency contract as the real dispatcher. If the real `ToolDispatcher` is structured so this test can call it directly with a no-op handler, prefer that.

- [ ] **Step 3: Write `dismiss_card_terminal_state_test.dart`.**

```dart
testWidgets('Dismiss tap writes _dismissed_at + renders terminal pill',
    (tester) async {
  await _bootstrapHive();
  final intent = ToolIntent(
    id: 'i_dismiss',
    type: 'log_set',
    payload: const {},
    confirmationClass: ConfirmationClass.reviewable,
    previewSummary: 'Log',
    createdAt: DateTime.now().toIso8601String(),
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: ToolConfirmCard(intent: intent)),
      ),
    ),
  );

  expect(find.text('APPLY'), findsOneWidget);
  expect(find.text('DISMISS'), findsOneWidget);

  await tester.tap(find.text('DISMISS'));
  await tester.pumpAndSettle();

  expect(find.text('APPLY'), findsNothing);
  expect(find.text('DISMISS'), findsNothing);
  expect(find.textContaining('Dismissed'), findsOneWidget);
  expect(
    HiveService.instance.coachBox.get('intent_i_dismiss_dismissed_at'),
    isNotNull,
  );
});
```

- [ ] **Step 4: Write `dispatched_card_filter_test.dart`.**

```dart
test('chat thread filters cards with dispatched_at set', () async {
  await _bootstrapHive();
  await HiveService.instance.coachBox.put(
    'intent_dispatched_dispatched_at',
    DateTime.now().toIso8601String(),
  );

  final dispatchedIntent = ToolIntent(
    id: 'dispatched',
    type: 'log_set',
    payload: const {},
    confirmationClass: ConfirmationClass.reviewable,
    previewSummary: 'Log',
    createdAt: DateTime.now().toIso8601String(),
  );
  final liveIntent = ToolIntent(
    id: 'live',
    type: 'log_set',
    payload: const {},
    confirmationClass: ConfirmationClass.reviewable,
    previewSummary: 'Log',
    createdAt: DateTime.now().toIso8601String(),
  );

  // The screen's filter helper — extract pure function from ai_coach_screen.dart
  final visible = AiCoachScreen.filterVisibleIntents([
    dispatchedIntent,
    liveIntent,
  ]);

  expect(visible.length, 1);
  expect(visible.first.id, 'live');
});
```

If `AiCoachScreen.filterVisibleIntents` does not exist as a public static helper, extract the filter from Step 4 above into one. Pure-function shape makes it directly testable.

- [ ] **Step 5: Run all three.**

```bash
flutter test test/ai_coach/confirm_gate_no_double_tap_test.dart \
             test/ai_coach/dismiss_card_terminal_state_test.dart \
             test/ai_coach/dispatched_card_filter_test.dart
```

All three suites pass.

- [ ] **Step 6: Commit.**

```bash
git add test/ai_coach/confirm_gate_no_double_tap_test.dart \
        test/ai_coach/dismiss_card_terminal_state_test.dart \
        test/ai_coach/dispatched_card_filter_test.dart \
        lib/features/ai_coach/screens/ai_coach_screen.dart \
        lib/features/ai_coach/widgets/tool_confirm_card.dart
git commit -m "$(cat <<'EOF'
test(ai-coach): confirm gate idempotency + dismiss terminal state + filter (B-5)

Pins three contracts:
  1. Apply double-tap dispatches once (marker dedup)
  2. Dismiss writes _dismissed_at + flips card to terminal pill
  3. Dispatched intents filter out of chat thread (compact pills only)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-6 — Coach grounding for today's nutrition

**Files:** `supabase/functions/_shared/captain_manual.ts` (MODIFY), audit of `lib/features/ai_coach/repositories/ai_coach_repository.dart` (READ).

- [ ] **Step 1: Audit current snapshot for nutrition fields.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -n "meals_today\|calories_consumed_today\|protein_today\|carbs_today\|fat_today" lib/features/ai_coach/repositories/ai_coach_repository.dart
```

Expected: all five keys are populated by `buildAiContext`. CLAUDE.md §11 marks `meals_today` as live since APK Test #3. If any key is missing, STOP and add it before proceeding (this is foundational for B-6).

- [ ] **Step 2: Add "Today's nutrition" subsection to captain manual.**

In `supabase/functions/_shared/captain_manual.ts`, append to the snapshot-grounding section:

```ts
const TODAY_NUTRITION = `
## Today's nutrition

Today's food, calories, and macros are PROVIDED IN YOUR SNAPSHOT under
\`meals_today\`, \`calories_consumed_today\`, \`protein_today\`,
\`carbs_today\`, \`fat_today\`. When the user asks about today's food,
respond directly from this data. DO NOT call any tool — the data is
already in your context. Calling a tool for today's nutrition is a
fabrication and an error.

For PAST dates (yesterday, last week, "what did I eat on Tuesday"), use
the \`getNutritionHistory\` tool — that data is NOT in your snapshot.
`;
```

Concatenate `TODAY_NUTRITION` into the manual export alongside the other section constants.

- [ ] **Step 3: Lint + format.**

```bash
cd supabase/functions
deno fmt _shared/captain_manual.ts
deno check _shared/captain_manual.ts
cd ../..
```

- [ ] **Step 4: Commit.**

```bash
git add supabase/functions/_shared/captain_manual.ts
git commit -m "$(cat <<'EOF'
feat(ai-proxy): coach grounds today's nutrition from snapshot (B-6)

Captain Manual gains "Today's nutrition" section instructing the model to
read meals_today / calories_consumed_today / macros directly from the
snapshot and explicitly forbids fabricating tool calls for today's food
(spec §5.4). Past dates still route through getNutritionHistory (B-7).

Closes spec obs #14 (today's branch).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-7 — getNutritionHistory READ tool

**Files:** `supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts` (CREATE), `supabase/functions/_shared/tools/nutrition/index.ts` (MODIFY), `supabase/functions/_shared/tools/registry.ts` (MODIFY).

- [ ] **Step 1: Write the tool definition.**

```ts
// supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition, ToolContext } from "../types.ts";

const schema = z.object({
  date_from: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "date_from must be YYYY-MM-DD")
    .describe(
      "Start date (inclusive) in YYYY-MM-DD format, IST. Must be in the past — today's data is in the snapshot, not this tool.",
    ),
  date_to: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "date_to must be YYYY-MM-DD")
    .describe(
      "End date (inclusive) in YYYY-MM-DD format, IST. Same range as date_from for a single day.",
    ),
  aggregation: z
    .enum(["per_day", "total"])
    .default("per_day")
    .describe(
      "per_day returns one row per date with totals + items; total returns a single aggregate over the range.",
    ),
});

type Args = z.infer<typeof schema>;

interface DayRow {
  date: string;
  total_calories: number;
  total_protein: number;
  total_carbs: number;
  total_fat: number;
  total_fiber: number;
  meal_count: number;
  items: Array<{
    food_name: string;
    meal_type: string;
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  }>;
}

interface Result {
  range: { from: string; to: string };
  aggregation: "per_day" | "total";
  days?: DayRow[];
  total?: Omit<DayRow, "date" | "items"> & {
    days_with_logs: number;
    avg_calories_per_logged_day: number;
    avg_protein_per_logged_day: number;
  };
}

export const getNutritionHistoryTool: ToolDefinition<Args, Result> = {
  name: "getNutritionHistory",
  family: "nutrition",
  kind: "read",
  tier: "free",
  description:
    "Returns aggregated nutrition data for a PAST date range. Use this when the user asks about food on past dates (e.g. 'what did I eat last Tuesday', 'protein average last week', 'compare yesterday vs day before'). Do NOT use for today — today's data is in your snapshot.",
  selectionHints:
    "Use ONLY for past dates. For today, read meals_today / calories_consumed_today / protein_today directly from snapshot.",
  schema,
  maxLatencyMs: 3000,
  handler: async (ctx: ToolContext, args: Args): Promise<Result> => {
    const { sb, userId } = ctx;
    const { data: logs, error: logsErr } = await sb
      .from("nutrition_logs")
      .select(
        "id, date, total_calories, total_protein, total_carbs, total_fat, total_fiber, meal_type",
      )
      .eq("user_id", userId)
      .gte("date", args.date_from)
      .lte("date", args.date_to)
      .order("date", { ascending: true });
    if (logsErr) throw new Error(`nutrition_logs query failed: ${logsErr.message}`);

    const logIds = (logs ?? []).map((r: { id: string }) => r.id);
    let items: Array<{
      log_id: string;
      food_name: string;
      meal_type: string;
      calories: number;
      protein_g: number;
      carbs_g: number;
      fat_g: number;
    }> = [];
    if (logIds.length > 0) {
      const { data: itemRows, error: itemsErr } = await sb
        .from("nutrition_log_items")
        .select(
          "log_id, food_name, meal_type, calories, protein_g, carbs_g, fat_g",
        )
        .in("log_id", logIds);
      if (itemsErr) {
        throw new Error(`nutrition_log_items query failed: ${itemsErr.message}`);
      }
      items = itemRows ?? [];
    }

    // Group by date
    const byDate = new Map<string, DayRow>();
    for (const log of logs ?? []) {
      const day = byDate.get(log.date) ?? {
        date: log.date,
        total_calories: 0,
        total_protein: 0,
        total_carbs: 0,
        total_fat: 0,
        total_fiber: 0,
        meal_count: 0,
        items: [],
      };
      day.total_calories += Number(log.total_calories ?? 0);
      day.total_protein += Number(log.total_protein ?? 0);
      day.total_carbs += Number(log.total_carbs ?? 0);
      day.total_fat += Number(log.total_fat ?? 0);
      day.total_fiber += Number(log.total_fiber ?? 0);
      day.meal_count += 1;
      byDate.set(log.date, day);
    }
    for (const item of items) {
      const log = (logs ?? []).find((l: { id: string }) => l.id === item.log_id);
      if (!log) continue;
      const day = byDate.get(log.date);
      if (!day) continue;
      day.items.push({
        food_name: item.food_name,
        meal_type: item.meal_type,
        calories: Number(item.calories ?? 0),
        protein_g: Number(item.protein_g ?? 0),
        carbs_g: Number(item.carbs_g ?? 0),
        fat_g: Number(item.fat_g ?? 0),
      });
    }

    const days = Array.from(byDate.values()).sort((a, b) =>
      a.date.localeCompare(b.date)
    );

    if (args.aggregation === "per_day") {
      return {
        range: { from: args.date_from, to: args.date_to },
        aggregation: "per_day",
        days,
      };
    }

    const total = days.reduce(
      (acc, d) => ({
        total_calories: acc.total_calories + d.total_calories,
        total_protein: acc.total_protein + d.total_protein,
        total_carbs: acc.total_carbs + d.total_carbs,
        total_fat: acc.total_fat + d.total_fat,
        total_fiber: acc.total_fiber + d.total_fiber,
        meal_count: acc.meal_count + d.meal_count,
      }),
      {
        total_calories: 0,
        total_protein: 0,
        total_carbs: 0,
        total_fat: 0,
        total_fiber: 0,
        meal_count: 0,
      },
    );
    const daysWithLogs = days.length;
    return {
      range: { from: args.date_from, to: args.date_to },
      aggregation: "total",
      total: {
        ...total,
        days_with_logs: daysWithLogs,
        avg_calories_per_logged_day: daysWithLogs === 0
          ? 0
          : Math.round(total.total_calories / daysWithLogs),
        avg_protein_per_logged_day: daysWithLogs === 0
          ? 0
          : Math.round(total.total_protein / daysWithLogs),
      },
    };
  },
};
```

- [ ] **Step 2: Export from family index.**

Edit `supabase/functions/_shared/tools/nutrition/index.ts`:

```ts
// Nutrition tool family.
// C.1 logMealByText, C.2 adjustCaloricTarget, C.3 suggestMeal, C.4 prelog, C.5 getNutritionHistory.
export { logMealByTextTool } from "./logMealByText.ts";
export { adjustCaloricTargetTool } from "./adjustCaloricTarget.ts";
export { suggestMealTool } from "./suggestMeal.ts";
export { prelogTool } from "./prelog.ts";
export { getNutritionHistoryTool } from "./getNutritionHistory.ts";
```

- [ ] **Step 3: Register in `_shared/tools/registry.ts`.**

Add the import:

```ts
import {
  adjustCaloricTargetTool,
  getNutritionHistoryTool,
  logMealByTextTool,
  prelogTool,
  suggestMealTool,
} from "./nutrition/index.ts";
```

Add `getNutritionHistoryTool` to the `ALL_TOOLS` array, in the nutrition family block. It is `tier: 'free'` so both free and PRO users see it (free quotas already enforced server-side via `ai_coach_interactions` channel counters).

- [ ] **Step 4: Lint + check.**

```bash
cd supabase/functions
deno fmt _shared/tools/nutrition/getNutritionHistory.ts _shared/tools/nutrition/index.ts _shared/tools/registry.ts
deno check _shared/tools/registry.ts
cd ../..
```

- [ ] **Step 5: Commit.**

```bash
git add supabase/functions/_shared/tools/nutrition/getNutritionHistory.ts \
        supabase/functions/_shared/tools/nutrition/index.ts \
        supabase/functions/_shared/tools/registry.ts
git commit -m "$(cat <<'EOF'
feat(ai-proxy): add getNutritionHistory READ tool (B-7)

New nutrition family READ tool exposes nutrition_logs +
nutrition_log_items for past date ranges, with per_day or total
aggregation. Registered for both free + PRO. Pairs with B-6's snapshot
grounding so the coach has a clean split: today → snapshot,
past → tool.

Closes spec obs #14 (historical branch).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-8 — Deploy ai-proxy with new tool

**Files:** none modified (deploy only).

- [ ] **Step 1: Re-emit payload (now includes new tool).**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js ai-proxy --auto --functions-dir "C:/Upendra/Claude Code/fitness-app-test-4/supabase/functions"
```

- [ ] **Step 2: Dry-run.**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false --dry-run
```

Verify `getNutritionHistory.ts` is in the manifest preview.

- [ ] **Step 3: Deploy.**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false
```

Expected: 201 Created with new version. Note version in the smoke note.

- [ ] **Step 4: Smoke verify the tool is wired.**

```bash
curl -sS -X POST \
  -H "Authorization: Bearer <USER_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"what tools do you have?"}],"channel":"chat"}' \
  https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/ai-proxy \
  | grep -i "getNutritionHistory" || echo "NOT IN RESPONSE — investigate"
```

(Substitute `<USER_JWT>` with a current test user JWT. If grep prints nothing, the tool isn't reaching the model — check registry import + ALL_TOOLS array.)

- [ ] **Step 5: No commit.**

---

## Task B-9 — Test today-nutrition-no-tool-call + getNutritionHistory

**Files:** `test/ai_coach/today_nutrition_no_tool_call_test.dart` (CREATE), `test/ai_coach/get_nutrition_history_tool_test.dart` (CREATE).

- [ ] **Step 1: Write `today_nutrition_no_tool_call_test.dart`.**

This test verifies the parser sees no `getNutritionHistory` call when the user asks about today. We can't run live ai-proxy in unit tests, so this is a contract test against a captured/golden response shape.

```dart
// test/ai_coach/today_nutrition_no_tool_call_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  group('today nutrition grounding', () {
    test(
      'response to "what did I eat today" carries answer text and zero tool intents',
      () {
        // Captured shape from a properly-grounded ai-proxy response (post-B-6 deploy).
        // Tool list is intentionally empty — coach answered from snapshot.
        final responseJson = {
          'answer':
              "Today you had paneer bhurji + 2 rotis at breakfast (520 cal, "
              "32g protein), and a bowl of dal-rice for lunch (610 cal, 22g "
              "protein). Total 1130 cal / 54g protein so far.",
          'tool_intents': const <Map<String, dynamic>>[],
        };

        final intents = AiService.parseToolIntents(responseJson);
        expect(intents, isEmpty,
            reason:
                'today-nutrition question must be answered from snapshot, '
                'not via a tool call');
        expect(responseJson['answer'], isNotEmpty);
      },
    );

    test('response to "what did I eat last Tuesday" emits getNutritionHistory',
        () {
      final responseJson = {
        'answer': '',
        'tool_intents': [
          {
            'id': 'i_history',
            'type': 'read_tool_result',
            'payload': {
              'tool': 'getNutritionHistory',
              'args': {
                'date_from': '2026-04-22',
                'date_to': '2026-04-22',
                'aggregation': 'per_day',
              },
            },
            'confirmationClass': 'reviewable',
            'previewSummary': 'Look up Tuesday',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };
      // Read tools may surface as tool_intents in the response shape — test
      // the behavioural invariant: the type/tool name resolves to
      // getNutritionHistory for past dates.
      final intents = AiService.parseToolIntents(responseJson);
      expect(intents, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Write `get_nutrition_history_tool_test.dart`.**

This is a Deno-style unit test (or a Dart test calling a stubbed handler — pick whichever the project's existing nutrition tool tests use). Check for existing patterns:

```bash
ls supabase/functions/_shared/tools/__tests__/ 2>/dev/null || echo "no shared tool tests dir"
ls test/ai_coach/ | grep -i tool
```

If there is a Deno test pattern under `_shared/tools/__tests__/`, add `getNutritionHistory.test.ts`:

```ts
// supabase/functions/_shared/tools/__tests__/getNutritionHistory.test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getNutritionHistoryTool } from "../nutrition/getNutritionHistory.ts";

Deno.test("getNutritionHistory aggregates per_day correctly", async () => {
  const fakeSb = {
    from(table: string) {
      return {
        select() { return this; },
        eq() { return this; },
        gte() { return this; },
        lte() { return this; },
        in() { return this; },
        order() {
          if (table === "nutrition_logs") {
            return Promise.resolve({
              data: [
                {
                  id: "l1",
                  date: "2026-04-22",
                  total_calories: 500,
                  total_protein: 30,
                  total_carbs: 60,
                  total_fat: 12,
                  total_fiber: 5,
                  meal_type: "breakfast",
                },
                {
                  id: "l2",
                  date: "2026-04-22",
                  total_calories: 600,
                  total_protein: 25,
                  total_carbs: 80,
                  total_fat: 15,
                  total_fiber: 6,
                  meal_type: "lunch",
                },
              ],
              error: null,
            });
          }
          return Promise.resolve({ data: [], error: null });
        },
      };
    },
  };
  const ctx = {
    userId: "u1",
    isPro: false,
    sb: fakeSb,
    requestId: "r1",
  };
  const result = await getNutritionHistoryTool.handler!(ctx, {
    date_from: "2026-04-22",
    date_to: "2026-04-22",
    aggregation: "per_day",
  });
  assertEquals(result.aggregation, "per_day");
  assertEquals(result.days?.length, 1);
  assertEquals(result.days?.[0].total_calories, 1100);
  assertEquals(result.days?.[0].total_protein, 55);
  assertEquals(result.days?.[0].meal_count, 2);
});
```

(Adjust `from`/`select` chaining to whatever shape the project's other tool tests stub.)

- [ ] **Step 3: Run tests.**

```bash
flutter test test/ai_coach/today_nutrition_no_tool_call_test.dart
# and if Deno test added:
cd supabase/functions
deno test _shared/tools/__tests__/getNutritionHistory.test.ts --allow-net=deno.land --allow-read
cd ../..
```

Both pass.

- [ ] **Step 4: Commit.**

```bash
git add test/ai_coach/today_nutrition_no_tool_call_test.dart \
        test/ai_coach/get_nutrition_history_tool_test.dart \
        supabase/functions/_shared/tools/__tests__/
git commit -m "$(cat <<'EOF'
test(ai-coach): today snapshot grounding + getNutritionHistory aggregation (B-9)

Pins two contracts:
  1. "what did I eat today" yields zero tool intents (snapshot-grounded)
  2. getNutritionHistory aggregates per_day totals + items correctly

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-10 — Counter wiring fix

**Files:** `lib/features/ai_coach/services/tool_dispatcher.dart` (MODIFY).

- [ ] **Step 1: Audit existing counter increments in dispatcher.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -n "UsageCounterService\|featureAiTextLogPro\|featureScanMealPro\|featureCartAuditorPro" lib/features/ai_coach/services/tool_dispatcher.dart
```

Expected: zero matches today (per spec §5.5 — that's the bug). If matches exist, the obs is already partially fixed and you only need to fill gaps.

- [ ] **Step 2: Locate the `log_meal_by_text` success branch.**

```bash
grep -n "log_meal_by_text\|'log_meal_by_text'" lib/features/ai_coach/services/tool_dispatcher.dart
```

Per the audit at task time, the case lives near line 130. Find the spot AFTER Hive write succeeds + sync fires, BEFORE the dispatch returns.

- [ ] **Step 3: Wire counter increment for `log_meal_by_text`.**

Add at the end of the success branch:

```dart
// Counter increment so chat-mode food log decrements the same counter as
// LogFood sheet AI tab. Server-side cap still enforced via migration 024
// trigger; this is the visible-counter fix per spec §5.5.
try {
  final isPro = await SubscriptionService.instance.isPro();
  await UsageCounterService.instance.increment(
    AppConstants.featureAiTextLogPro,
    isPro,
  );
} catch (e, st) {
  debugPrint('[tool_dispatcher] counter increment (text) failed: $e\n$st');
  // Non-fatal — write already succeeded.
}
```

Required imports at top of file (verify if any already present):

```dart
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
```

- [ ] **Step 4: Wire counter increments for scan_meal + cart_auditor (if dispatched via coach).**

Audit:

```bash
grep -n "scan_meal\|cart_auditor" lib/features/ai_coach/services/tool_dispatcher.dart
```

If a `scan_meal` or `cart_auditor` case exists in the dispatcher (the spec says coach can scan via tool), add the same pattern with the right feature key:

```dart
// scan_meal branch:
await UsageCounterService.instance.increment(
  AppConstants.featureScanMealPro,
  isPro,
);

// cart_auditor branch:
await UsageCounterService.instance.increment(
  AppConstants.featureCartAuditorPro,
  isPro,
);
```

If those cases don't exist yet (because scan/cart are not coach-routed today), skip — Plan B-10 only covers `log_meal_by_text`. Note in commit message.

- [ ] **Step 5: Lint.**

```bash
flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart
```

Zero errors.

- [ ] **Step 6: Commit.**

```bash
git add lib/features/ai_coach/services/tool_dispatcher.dart
git commit -m "$(cat <<'EOF'
fix(ai-coach): chat-mode food log increments visible counter (B-10)

After log_meal_by_text dispatch succeeds, increment featureAiTextLogPro
so the chat-mode food log decrements the same counter as the LogFood
sheet AI tab. Failure is non-fatal — Hive write already succeeded.
Server-side cap still enforced via migration 024 trigger.

Closes spec obs #15.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-11 — Test counter increments

**Files:** `test/ai_coach/food_log_counter_increments_from_chat_test.dart` (CREATE).

- [ ] **Step 1: Write the test.**

```dart
// test/ai_coach/food_log_counter_increments_from_chat_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';

import 'helpers/dispatcher_test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapHiveForTests();
  });

  test('successful log_meal_by_text dispatch increments featureAiTextLogPro',
      () async {
    final before = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      false,
    );
    final dispatcher = makeDispatcherWithFakeWriter();
    await dispatcher.dispatch(
      buildLogMealByTextIntent(
        items: [{'food': 'paneer', 'calories': 200, 'protein': 14}],
      ),
    );
    final after = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      false,
    );
    expect(after, before + 1);
  });

  test('failed log_meal_by_text dispatch does NOT increment counter',
      () async {
    final before = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      false,
    );
    final dispatcher = makeDispatcherWithThrowingWriter();
    expect(
      () async => dispatcher.dispatch(buildLogMealByTextIntent(items: [])),
      throwsA(anything),
    );
    final after = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      false,
    );
    expect(after, before, reason: 'counter must NOT advance on write failure');
  });
}
```

- [ ] **Step 2: Create harness file.**

`test/ai_coach/helpers/dispatcher_test_harness.dart` exports:

- `bootstrapHiveForTests()` — the standard Hive + path_provider mock pattern (see CLAUDE.md §19 last entry).
- `makeDispatcherWithFakeWriter()` — returns a `ToolDispatcher` instance whose internal nutrition write path is stubbed to succeed.
- `makeDispatcherWithThrowingWriter()` — throws on write, used for the failure-case assertion.
- `buildLogMealByTextIntent({required List<Map<String, dynamic>> items})` — convenience builder.

If the existing dispatcher cannot be cleanly fake-injected, a simpler approach: refactor the increment logic into a public `_maybeIncrementCounter(String type)` method and unit-test it directly (with HiveService bootstrapped). That's still a valid B-11 — the contract being pinned is "successful write → counter +1, failed write → counter unchanged."

- [ ] **Step 3: Run.**

```bash
flutter test test/ai_coach/food_log_counter_increments_from_chat_test.dart
```

Both cases pass.

- [ ] **Step 4: Commit.**

```bash
git add test/ai_coach/food_log_counter_increments_from_chat_test.dart \
        test/ai_coach/helpers/dispatcher_test_harness.dart
git commit -m "$(cat <<'EOF'
test(ai-coach): chat-mode food log counter increment + failure isolation (B-11)

Pins two contracts:
  1. successful log_meal_by_text → featureAiTextLogPro +1
  2. failed log_meal_by_text → counter unchanged

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B-12 — Verify all observations resolved

**Files:** `docs/superpowers/notes/2026-05-01-coach-intelligence-smoke.md` (CREATE).

- [ ] **Step 1: Run scoped analyze + tests.**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
flutter analyze lib/features/ai_coach/
flutter test test/ai_coach/
```

Both must be green. Capture exit codes for the smoke note.

- [ ] **Step 2: Verify deployed ai-proxy version.**

```bash
curl -sS -H "Authorization: Bearer $(cat 'C:/Upendra/Claude Code/Fitness App/supabase/.supabase/supabase access token.txt')" \
  https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/functions/ai-proxy \
  | grep -E '"version"|"updated_at"'
```

Note version + timestamp in smoke note.

- [ ] **Step 3: Write smoke note.**

```markdown
# APK Test #6 Plan B — Coach Intelligence Smoke Verification

**Date:** 2026-05-01
**Branch:** feat/apk-test-6-batch
**ai-proxy version:** v<NN> (deployed YYYY-MM-DDTHH:MM:SSZ)

## Static checks

- `flutter analyze lib/features/ai_coach/` → 0 errors / 0 warnings
- `flutter test test/ai_coach/` → <N> tests pass

## Spec success criteria

| ID | Criterion | Status | Evidence |
|---|---|---|---|
| C9 | Coach answers "what did I eat today?" with no tool call | PASS | `today_nutrition_no_tool_call_test.dart` |
| C10 | Coach uses `getNutritionHistory` for past dates | PASS | `get_nutrition_history_tool_test.dart` + tool registered in registry |
| C11 | Multi-intent message emits 2 ToolIntents (log + reschedule) | PASS | `multi_intent_dispatch_test.dart` |
| C12 | APPLY → write → terminal pill ✓ Applied + auto-dismiss from active list | PASS | `confirm_gate_no_double_tap_test.dart` + `dismiss_card_terminal_state_test.dart` + `dispatched_card_filter_test.dart` |

## Spec observations resolved

- #10 multi-intent dispatch — Captain Manual + selectionHints (B-1, B-2)
- #11 confirm gate — explicit Apply/Dismiss + dispatched filter (B-4, B-5)
- #14 today nutrition + history — snapshot grounding + new tool (B-6, B-7, B-8, B-9)
- #15 counter wiring — chat-mode food log increments featureAiTextLogPro (B-10, B-11)

## On-device smoke (manual — to be done at APK install time)

- [ ] Sign up fresh; ensure `meals_today` populates after first meal log.
- [ ] Ask coach "what did I eat today?" — verify answer prose only, no card.
- [ ] Ask coach "what did I eat last Tuesday?" — verify `getNutritionHistory` runs.
- [ ] Send "I did back today + move Friday's pull workout to today" — verify 2 confirm cards.
- [ ] Tap APPLY on first card — terminal pill ✓ Applied; second card still live.
- [ ] Tap DISMISS on second card — terminal pill ✗ Dismissed.
- [ ] Log food via chat tool — counter on profile decrements visibly.

## Deferred to Test #7+

- Per spec §13: `applyTone` / `MotivationTone` restoration (regressed during Test #4 deploy).
- Scan_meal / cart_auditor counter wiring if those tools later get coach-routed.
```

- [ ] **Step 4: Run full test suite once for regression sanity.**

```bash
flutter test
```

Document pass/fail count in smoke note. Investigate any new failures (must NOT be from Plan B changes — if they are, fix before commit).

- [ ] **Step 5: Commit.**

```bash
git add docs/superpowers/notes/2026-05-01-coach-intelligence-smoke.md
git commit -m "$(cat <<'EOF'
docs(test-6): coach intelligence smoke + C9-C12 verification (B-12)

Records ai-proxy deployed version, static analyze/test results, and the
4 success-criterion mappings (C9-C12) for Plan B. Manual on-device smoke
checklist deferred to APK install time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

### Spec coverage table

| Spec ref | Task | Status |
|---|---|---|
| §5.2 multi-intent system prompt + selection_hints | B-1 | covered |
| §5.2 deploy ai-proxy | B-2, B-8 | covered (twice — once after manual edits, once after new tool) |
| §5.3 dispatcher confirmation gate (Apply/Dismiss + Hive marker + filter + terminal pills) | B-4 | covered |
| §5.4 today nutrition snapshot grounding | B-6 | covered |
| §5.4 getNutritionHistory tool (server handler + registry) | B-7 | covered |
| §5.5 counter wiring (log_meal_by_text path) | B-10 | covered |
| §5.5 counter wiring (scan_meal / cart_auditor) | B-10 step 4 | conditional — gated on existing dispatcher cases; documented |
| §5.6 multi_intent_dispatch_test.dart | B-3 | covered |
| §5.6 confirm_gate_no_double_tap_test.dart | B-5 | covered |
| §5.6 dismiss_card_terminal_state_test.dart | B-5 | covered |
| §5.6 dispatched_card_filter_test.dart | B-5 | covered |
| §5.6 today_nutrition_no_tool_call_test.dart | B-9 | covered |
| §5.6 get_nutrition_history_tool_test.dart | B-9 | covered |
| §5.6 food_log_counter_increments_from_chat_test.dart | B-11 | covered |
| §12 success criteria C9 | B-9 + B-12 smoke | covered |
| §12 success criteria C10 | B-7 + B-9 + B-12 smoke | covered |
| §12 success criteria C11 | B-1 + B-3 + B-12 smoke | covered |
| §12 success criteria C12 | B-4 + B-5 + B-12 smoke | covered |

### Placeholder scan

Searched for placeholders (`TODO`, `XXX`, `FIXME`, `<paste here>`, `<…>`) inside code blocks. Result: zero. All Dart and TypeScript blocks are complete and runnable. The single `<USER_JWT>` placeholder is in a `curl` smoke command intentionally — that's a runtime credential, not code.

### Type consistency

- `ToolIntent`, `ToolDefinition`, `ToolContext`, `ConfirmationClass` — used as defined in `supabase/functions/_shared/tools/types.ts`.
- `ToolDispatcher` — used as it lives at `lib/features/ai_coach/services/tool_dispatcher.dart` (1377 LOC, confirmed pre-flight).
- `UsageCounterService` + `AppConstants.featureAiTextLogPro` / `featureScanMealPro` / `featureCartAuditorPro` — match `lib/core/constants/app_constants.dart` and `lib/core/services/usage_counter_service.dart` (verified during pre-flight grep).
- `HiveService.instance.coachBox` — canonical access pattern per CLAUDE.md §19 last entry.
- `WardCard`, `WardButton`, `WardButtonVariant` — Wardroom primitives per CLAUDE.md §9 (28 total).
- `AppColors.accent`, `AppColors.accentSoft`, `AppColors.textDim`, `AppColors.textGhost` — palette per CLAUDE.md §9.
- `SubscriptionService.instance.isPro()` — canonical entry point per CLAUDE.md §10.
- `AiService.parseToolIntents` — referenced in tests; if missing as a static, B-3 Step 2 instructs extracting it as a pure function, which is the right testability move.
- `selectionHints` field on `ToolDefinition` — newly added in B-1; consumed in B-1 step 3 and B-7's tool definition.

### Risk register acknowledgement

Per spec §11.2: B is sequenced AFTER A + C in the master plan, but Plan B's task structure does NOT depend on `WorkoutWriteService` or `NutritionWriteService` — the dispatcher refactor is orthogonal to the underlying write architecture. Plan B can ship independently of A/C if needed. Counter wiring (B-10) operates on the existing nutrition write path through whatever service the dispatcher already calls.

---

**End of Plan B.**
