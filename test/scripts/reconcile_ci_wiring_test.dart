import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against the `check_open_issues_reconciled.dart` failure mode: a
/// script cited across the repo as shipped that was never actually written,
/// and whose absence read as coverage for 70 days.
///
/// Asserting the files exist is the cheap half. The half that matters is that
/// the hook is REGISTERED — an unregistered SessionStart script never runs, and
/// nothing else in the suite would notice.
void main() {
  final root = Directory.current.path;

  group('reconcile_ci is wired, not merely present', () {
    test('every new file exists on disk', () {
      for (final path in const [
        'scripts/reconcile_ci.dart',
        'scripts/ci_reconcile_state_lib.dart',
        'scripts/gh_run_lib.dart',
        'scripts/arm_ci_reconcile.sh',
      ]) {
        expect(File('$root/$path').existsSync(), isTrue,
            reason: '$path is referenced by the CI reconciler but is missing');
      }
    });

    test('a SessionStart hook actually invokes scripts/reconcile_ci.dart', () {
      final settings = File('$root/.claude/settings.json');
      expect(settings.existsSync(), isTrue);

      final parsed = jsonDecode(settings.readAsStringSync()) as Map;
      final hooks = parsed['hooks'] as Map?;
      final sessionStart = hooks?['SessionStart'] as List<dynamic>?;
      expect(sessionStart, isNotNull,
          reason: '.claude/settings.json has no hooks.SessionStart array');

      final commands = <String>[];
      for (final entry in sessionStart!) {
        for (final hook in (entry as Map)['hooks'] as List<dynamic>? ?? const []) {
          final cmd = (hook as Map)['command'];
          if (cmd is String) commands.add(cmd);
        }
      }

      expect(
        commands.where((c) => c.contains('scripts/reconcile_ci.dart')),
        isNotEmpty,
        reason: 'reconcile_ci.dart is not registered as a SessionStart hook, '
            'so it would never run. Registered commands: $commands',
      );
    });

    test('safe_push.sh arms through the arm script on its landed path', () {
      final src = File('$root/scripts/safe_push.sh').readAsStringSync();

      expect(src, contains('arm_ci_reconcile.sh'),
          reason: 'safe_push.sh must arm a reconcile entry when a push lands');
      expect(src, contains(r'$REPO_ROOT/scripts/arm_ci_reconcile.sh'),
          reason: 'the arm call must resolve via \$REPO_ROOT (git-derived, '
              'invocation-path-independent), not \$(dirname "\$0"), which '
              'breaks under an absolute path or PATH lookup — and would do so '
              'SILENTLY, since the call is || true-wrapped');
      expect(src, contains('|| true'),
          reason: 'a failure to arm must never change the push verdict');
    });

    test('the state file, its temp sibling, and the kill switch are gitignored',
        () {
      final ignore = File('$root/.gitignore').readAsStringSync();
      expect(ignore, contains('.claude/.ci_reconcile_pending.jsonl'),
          reason: 'the reconciler state file is machine-local and must never '
              'be committed');
      expect(ignore, contains('.claude/.ci_reconcile_pending.jsonl.tmp'),
          reason: 'the atomic-rename staging file must be ignored too');
      expect(ignore, contains('.claude/.reconcile_ci.disabled'),
          reason: 'disabling the hook in one clone must not disable it for '
              'everyone, and the marker must not show up as untracked');
    });

    test('the kill switch is honoured before any work is done', () {
      // Platform tier requires a feature_flag (docs/blast_radius.yaml); a
      // SessionStart hook is otherwise live from the next session after merge
      // with no way off short of editing settings.json.
      final src = File('$root/scripts/reconcile_ci.dart').readAsStringSync();
      expect(src, contains('.claude/.reconcile_ci.disabled'),
          reason: 'the hook must have a kill switch');

      final killIdx = src.indexOf('_killSwitchPath).existsSync()');
      final stateIdx = src.indexOf('File(_statePath)');
      expect(killIdx, greaterThan(-1),
          reason: 'the kill switch must actually be CHECKED, not just declared');
      expect(killIdx, lessThan(stateIdx),
          reason: 'the switch must be checked BEFORE the state file is read, '
              'so a disabled hook does no I/O and no gh call at all');
    });
  });
}
