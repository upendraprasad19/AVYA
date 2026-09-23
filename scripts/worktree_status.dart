import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

// Worktree status report — shows which worktrees can be retired.
// Mirrors ICANBEFITTER's worktree-status.mjs.
//
// Usage: dart run scripts/worktree_status.dart
//
// Output: lists all registered worktrees + retirement eligibility for each,
// plus any orphan directories (on disk but not in git registry).
// NEVER deletes anything — just reports.

Future<void> main() async {
  try {
    stdout.writeln('\n[worktree-status] Registered worktrees:');

    // Get list of worktrees from git
    final result = Process.runSync('git', ['worktree', 'list', '--porcelain']);
    if (result.exitCode != 0) {
      stdout.writeln('  ERROR: git worktree list failed');
      return;
    }

    final lines = (result.stdout as String).split('\n');
    final worktrees = <Map<String, String>>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('worktree ')) {
        worktrees.add({'path': line.substring('worktree '.length), 'branch': 'unknown'});
      } else if (line.startsWith('branch ')) {
        if (worktrees.isNotEmpty) {
          worktrees.last['branch'] = line.substring('branch '.length).replaceAll('refs/heads/', '');
        }
      }
    }

    if (worktrees.isEmpty) {
      stdout.writeln('  (none)');
      return;
    }

    for (final wt in worktrees) {
      final path = wt['path']!;
      final branch = wt['branch']!;
      final dir = Directory(path);
      final exists = dir.existsSync();

      stdout.writeln('  $branch');
      stdout.writeln('    path: $path');
      stdout.writeln('    exists: ${exists ? "yes" : "MISSING"}');

      if (!exists) {
        stdout.writeln('    status: orphan (in git but not on disk)');
        continue;
      }

      // Check if merged
      final mergeResult = Process.runSync('git',
        ['merge-base', '--is-ancestor', 'HEAD', 'main'],
        workingDirectory: path,
        runInShell: true
      );
      final isMerged = mergeResult.exitCode == 0;
      stdout.writeln('    merged into main: ${isMerged ? "yes" : "no"}');

      if (!isMerged) {
        stdout.writeln('    status: not ready (branch not yet merged)');
        continue;
      }

      // Check if clean
      final statusResult = Process.runSync('git', ['status', '--porcelain'],
        workingDirectory: path);
      final isClean = (statusResult.stdout as String).isEmpty;
      stdout.writeln('    working tree clean: ${isClean ? "yes" : "no"}');

      if (!isClean) {
        stdout.writeln('    status: not ready (uncommitted changes)');
        continue;
      }

      // Check if pushed
      final logResult = Process.runSync('git',
        ['rev-list', 'origin/main..HEAD'],
        workingDirectory: path,
        runInShell: true
      );
      final unpushed = (logResult.stdout as String).isNotEmpty;
      stdout.writeln('    has unpushed commits: ${unpushed ? "yes" : "no"}');

      if (unpushed) {
        stdout.writeln('    status: not ready (unpushed commits)');
        continue;
      }

      stdout.writeln('    status: ✓ ready to retire');
      stdout.writeln('    command: dart run scripts/retire_worktree.dart --execute -- $branch');
    }

    // Check for orphans
    final wtDir = Directory('.claude/worktrees');
    if (wtDir.existsSync()) {
      stdout.writeln('\n[worktree-status] Orphan directories (on disk, not in git registry):');
      final entries = wtDir.listSync();
      var foundOrphans = false;

      for (final entry in entries) {
        if (entry is Directory) {
          final inRegistry = worktrees.any((w) => w['path']!.endsWith(p.basename(entry.path)));
          if (!inRegistry) {
            stdout.writeln('  ${p.basename(entry.path)} — manually delete or restore to git');
            foundOrphans = true;
          }
        }
      }

      if (!foundOrphans) {
        stdout.writeln('  (none)');
      }
    }
  } catch (e) {
    stdout.writeln('ERROR: $e');
  }
}
