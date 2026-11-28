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

  // Coach workout parity S3 (plan 3.1 step 5, M40): fail CLOSED when a tool
  // sets requiresCapability with something the literal regex cannot read.
  group('unreadable capability (fail closed)', () {
    const identifierTool = '''
import { CAPABILITY_X } from "../../x_routing.ts";
export const xTool = {
  name: "xTool",
  kind: "write",
  requiresCapability: CAPABILITY_X,
  intentBuilder: (args) => ({ type: "x_type" }),
};
''';

    test('an identifier capability is reported and is a violation', () {
      final tools = parseTools({'workout/x.ts': identifierTool});
      expect(tools.single.unreadableCapability, isTrue);
      expect(tools.single.requiresCapability, isNull);
      final result = checkCoverage(
        tools: tools,
        dispatcherSrc: "case 'x_type':",
        clientCapabilities: {'x'},
      );
      expect(result.unreadableCapabilities, hasLength(1));
      expect(result.unreadableCapabilities.single,
          contains('write the capability as a string literal'));
      expect(result.unreadableCapabilities.single, contains('workout/x.ts'));
      expect(result.isViolation, isTrue);
    });

    test('a read tool with an identifier capability is reported too', () {
      final tools = parseTools({
        'progress/r.ts': identifierTool.replaceFirst('"write"', '"read"'),
      });
      final result = checkCoverage(
        tools: tools,
        dispatcherSrc: '',
        clientCapabilities: const {},
      );
      expect(result.unreadableCapabilities, hasLength(1));
      expect(result.isViolation, isTrue);
    });

    test('a literal capability is clean', () {
      final tools = parseTools({
        'workout/x.ts':
            identifierTool.replaceFirst('CAPABILITY_X,', '"x",'),
      });
      expect(tools.single.unreadableCapability, isFalse);
      expect(tools.single.requiresCapability, 'x');
      final result = checkCoverage(
        tools: tools,
        dispatcherSrc: "case 'x_type':",
        clientCapabilities: {'x'},
      );
      expect(result.unreadableCapabilities, isEmpty);
      expect(result.isViolation, isFalse);
    });

    test('a commented-out requiresCapability is not flagged', () {
      final tools = parseTools({
        'workout/c.ts': '''
export const cTool = {
  name: "cTool",
  kind: "write",
  // requiresCapability: SOME_CONST,
  /* requiresCapability: OTHER_CONST, */
  intentBuilder: (args) => ({ type: "c_type" }),
};
''',
      });
      expect(tools.single.unreadableCapability, isFalse);
      final result = checkCoverage(
        tools: tools,
        dispatcherSrc: "case 'c_type':",
        clientCapabilities: const {},
      );
      expect(result.isViolation, isFalse);
    });

    test('a commented-out LITERAL next to a live identifier still fails '
        'closed (B-pass seat 1 F3)', () {
      for (final comment in [
        '  // requiresCapability: "x",\n',
        '  /* requiresCapability: "x", */\n',
      ]) {
        final tools = parseTools({
          'workout/x.ts': identifierTool.replaceFirst(
              '  requiresCapability: CAPABILITY_X,',
              '$comment  requiresCapability: CAPABILITY_X,'),
        });
        expect(tools.single.requiresCapability, isNull, reason: comment);
        expect(tools.single.unreadableCapability, isTrue, reason: comment);
        final result = checkCoverage(
          tools: tools,
          dispatcherSrc: "case 'x_type':",
          clientCapabilities: {'x'},
        );
        expect(result.isViolation, isTrue, reason: comment);
      }
    });

    test('a tool without requiresCapability is not flagged', () {
      final tools = parseTools({
        'workout/p.ts': '''
export const pTool = {
  name: "pTool",
  kind: "write",
  intentBuilder: (args) => ({ type: "p_type" }),
};
''',
      });
      expect(tools.single.unreadableCapability, isFalse);
    });
  });
}
