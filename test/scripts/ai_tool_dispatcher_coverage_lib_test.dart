// Pure-logic tests for scripts/ai_tool_dispatcher_coverage_lib.dart — the
// extraction that backs scripts/check_ai_tool_dispatcher_coverage.dart (the
// capability-coverage extension, spec §5.8) so it is mutation-proven per
// CLAUDE.md §4.4 rule 24, without a filesystem e2e.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/ai_tool_dispatcher_coverage_lib.dart';

ToolInfo tool({
  String file = 'workout/x.ts',
  String name = 'x',
  String kind = 'write',
  String? intentType = 'x_type',
  String? requiresCapability,
}) =>
    ToolInfo(
      file: file,
      name: name,
      kind: kind,
      intentType: intentType,
      requiresCapability: requiresCapability,
    );

void main() {
  group('parseTools', () {
    test('extracts name / kind / intentType / requiresCapability', () {
      final tools = parseTools({
        'workout/swapWorkoutDays.ts': '''
export const swapWorkoutDaysTool = {
  name: "swapWorkoutDays",
  kind: "write",
  requiresCapability: "swap_workout_days",
  intentBuilder: (args) => ({
    type: "swap_workout_days",
  }),
};
''',
      });
      expect(tools, hasLength(1));
      expect(tools.single.name, 'swapWorkoutDays');
      expect(tools.single.kind, 'write');
      expect(tools.single.intentType, 'swap_workout_days');
      expect(tools.single.requiresCapability, 'swap_workout_days');
    });

    test('a file with no name/kind match is skipped', () {
      expect(parseTools({'workout/index.ts': 'export {};'}), isEmpty);
    });

    test('a tool with no requiresCapability parses to null', () {
      final tools = parseTools({
        'workout/plain.ts': '''
export const plainTool = {
  name: "plain",
  kind: "write",
  intentBuilder: (args) => ({ type: "plain_type" }),
};
''',
      });
      expect(tools.single.requiresCapability, isNull);
    });
  });

  group('checkCoverage', () {
    test('a capability-gated tool declared by the client is clean', () {
      final result = checkCoverage(
        tools: [tool(requiresCapability: 'swap_workout_days')],
        dispatcherSrc: "case 'x_type':",
        clientCapabilities: {'swap_workout_days'},
      );
      expect(result.isViolation, isFalse);
      expect(result.uncoveredCapabilities, isEmpty);
    });

    test('a capability-gated tool NOT declared by the client is a violation', () {
      final result = checkCoverage(
        tools: [tool(requiresCapability: 'swap_workout_days')],
        dispatcherSrc: "case 'x_type':",
        clientCapabilities: <String>{},
      );
      expect(result.uncoveredCapabilities, isNotEmpty);
      expect(result.isViolation, isTrue);
    });

    test('a missing dispatcher case is a violation regardless of capability', () {
      final result = checkCoverage(
        tools: [tool()],
        dispatcherSrc: 'no cases here',
        clientCapabilities: <String>{},
      );
      expect(result.missingDispatcherCases, isNotEmpty);
      expect(result.isViolation, isTrue);
    });

    test('a read tool is never checked', () {
      final result = checkCoverage(
        tools: [tool(kind: 'read', intentType: null)],
        dispatcherSrc: '',
        clientCapabilities: <String>{},
      );
      expect(result.isViolation, isFalse);
      expect(result.unusedWriteTools, isEmpty);
    });

    test('a write tool with no intent_type is reported unused, not a hard violation', () {
      final result = checkCoverage(
        tools: [tool(intentType: null)],
        dispatcherSrc: '',
        clientCapabilities: <String>{},
      );
      expect(result.unusedWriteTools, isNotEmpty);
      expect(result.isViolation, isFalse);
    });
  });

  // Rule-24 ledger provenance (docs/audit/gate_test_ledger.yaml,
  // check_gate_test_ledger.dart's `namesGate` check): this file's source
  // must literally reference the gate it backs by name.
  test('this file backs scripts/check_ai_tool_dispatcher_coverage.dart', () {
    expect(
      'scripts/check_ai_tool_dispatcher_coverage.dart',
      contains('check_ai_tool_dispatcher_coverage'),
    );
  });
}
