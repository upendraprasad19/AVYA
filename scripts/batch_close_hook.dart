// scripts/batch_close_hook.dart — a Stop hook.
//
// Fires when the agent is about to end a turn. If the session LANDED commits
// that are still unpushed, it hands back the CLAUDE.md §5 close-out checklist
// and blocks once, so the rows are ANSWERED rather than assumed.
//
// See scripts/batch_close_lib.dart for why this event and not a gate. In short:
// SessionStart / UserPromptSubmit / PreToolUse all fire BEFORE work, and §5
// lives at the END of a batch — so nothing was watching the place the rows
// actually decay. On 2026-08-25 four §5 rows went unwalked in one batch and
// surfaced only because founder asked.
//
// SAFETY, in the order it matters:
//   1. `stop_hook_active` short-circuits. Blocking on Stop re-triggers Stop; the
//      harness sets this flag once a Stop hook is already driving, and ignoring
//      it is an infinite loop.
//   2. Fires ONCE per HEAD sha (state file, gitignored). Ordinary conversation
//      after a commit is not interrupted again.
//   3. Kill switch: .claude/.batch_close.disabled
//   4. EVERY error path exits 0. A hook that wedges the session is worse than
//      the omission it prevents — the same contract check_oi_numbering_unique
//      and check_worktree_config_integrity already carry.

import 'dart:convert';
import 'dart:io';

import 'batch_close_lib.dart';

const _statePath = '.claude/.batch_close_state';
const _killSwitch = '.claude/.batch_close.disabled';

ProcessResult? _git(List<String> args) {
  try {
    return Process.runSync('git', args, stdoutEncoding: systemEncoding);
  } catch (_) {
    return null;
  }
}

String? _gitOut(List<String> args) {
  final r = _git(args);
  if (r == null || r.exitCode != 0) return null;
  return (r.stdout as String).trim();
}

/// The range of commits that describe THIS batch. See [chooseRange] for why
/// `origin/main..HEAD` alone is wrong — it contaminated three derived rows with
/// another batch's evidence, proven live by the B-pass.
///
/// ⚠ Returning null means UNKNOWN and the hook goes SILENT. That is a deliberate
/// choice, not the accident the earlier comment here described: with no `main`
/// and no `origin/main` there is no mainline to measure a batch against, and a
/// hook that blocked every turn in a fresh clone would be worse than one that
/// says nothing. The behaviour is pinned by a test so it stays deliberate.
String? _range() {
  final mainExists = _gitOut(['rev-parse', '--verify', 'main']) != null;
  final originMainExists =
      _gitOut(['rev-parse', '--verify', 'origin/main']) != null;
  final notInMain = mainExists
      ? int.tryParse(_gitOut(['rev-list', '--count', 'main..HEAD']) ?? '') ?? 0
      : 0;
  return chooseRange(
    mainExists: mainExists,
    commitsNotInMain: notInMain,
    originMainExists: originMainExists,
  );
}

/// The PRIMARY repo root, even when called from a linked worktree.
///
/// ⚠ `--show-toplevel` returns the WORKTREE path, and every session works in a
/// worktree per §4.13 — so deriving the harness directory from it never matches.
/// Found by live-testing this hook: it reported "NO retrospective" for a batch
/// whose retrospective had been written an hour earlier. `--git-common-dir`
/// points at the PRIMARY `.git` from anywhere, and its parent is the root the
/// harness keys on.
String? _primaryRoot() => primaryRootFrom(
    _gitOut(['rev-parse', '--path-format=absolute', '--git-common-dir']));

/// Newest `project_*.md` mtime in the harness memory dir for THIS repo.
///
/// The harness mangles the primary repo path into the directory name (drive
/// colon and separators become `-`). Derived rather than hardcoded so this is
/// not machine-specific.
///
/// ⚠ EXACT DIRECTORY ONLY — deliberately no fallback scan of sibling projects.
/// An earlier version, when the mangled name missed, walked every
/// `~/.claude/projects/*/memory` and took the first with any `project_*.md`.
/// That produced a CONFIDENT WRONG ANSWER from an unrelated project's stale
/// mtime instead of admitting it could not tell. Returning null here renders as
/// UNVERIFIED, which is the honest output — the bad-news-vs-no-news distinction
/// this repo has already paid for twice.
DateTime? _newestRetrospective(String? primaryRoot) {
  try {
    if (primaryRoot == null) return null;
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return null;
    final mangled = mangleProjectPath(primaryRoot);
    final dir = Directory('$home/.claude/projects/$mangled/memory');
    if (!dir.existsSync()) return null;
    DateTime? newest;
    for (final f in dir.listSync()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('project_') || !name.endsWith('.md')) continue;
      final m = f.statSync().modified;
      if (newest == null || m.isAfter(newest)) newest = m;
    }
    return newest;
  } catch (_) {
    return null;
  }
}

/// Read the harness payload without ever hanging.
///
/// ⚠ MUST NOT use `stdin.readLineSync`. That is SYNCHRONOUS and BLOCKING: a
/// caller that does not write-then-close (a terminal-attached manual run, a
/// backpressured write, a future harness change) blocks forever, and a hang is
/// not an exception so the surrounding try/catch cannot rescue it. Reproduced
/// during round 1 of this batch's own review: a delayed writer left the hook
/// still blocked after 8s, exit 124.
///
/// This mirrors the pattern the repo ALREADY arrived at for its two sibling
/// hooks — `git_safety_hook.dart:85-95` and `discipline_hook.dart:82,221` —
/// whose own comment records it as a prior B-pass finding: *"an unresolved read
/// … must never hang the whole session; fail open instead."* That fix existed
/// before this hook was written and a grep for `hasTerminal` would have found
/// it. Stop fires at the END OF EVERY TURN, so a hang here is worse than in
/// either sibling.
Future<String> _readStdin() async {
  if (stdin.hasTerminal) return '';
  return utf8.decoder.bind(stdin).join().timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
}

void main() async {
  try {
    var stopHookActive = false;
    try {
      final raw = await _readStdin();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw.trim());
        if (decoded is Map && decoded['stop_hook_active'] == true) {
          stopHookActive = true;
        }
      }
    } catch (_) {
      // No/!JSON stdin — treat as not-active and carry on. Never throw here.
    }

    final root = _gitOut(['rev-parse', '--show-toplevel']);
    if (root == null) exit(0);

    final range = _range();
    final headSha = _gitOut(['rev-parse', 'HEAD']);
    final count = range == null
        ? 0
        : int.tryParse(_gitOut(['rev-list', '--count', range]) ?? '') ?? 0;

    final stateFile = File('$root/$_statePath');
    String? lastSha;
    try {
      if (stateFile.existsSync()) lastSha = stateFile.readAsStringSync().trim();
    } catch (_) {}

    DateTime? oldestAt;
    var reviews = <String>[];
    var hasFix = false;
    if (range != null && count > 0) {
      final iso = _gitOut(['log', '--reverse', '--format=%aI', range]);
      if (iso != null && iso.isNotEmpty) {
        oldestAt = DateTime.tryParse(iso.split('\n').first.trim());
      }
      final names = _gitOut(['diff', '--name-only', '--diff-filter=A', range]);
      if (names != null) {
        reviews = names
            .split('\n')
            .map((s) => s.trim().replaceAll(r'\', '/'))
            // ANY .md under docs/reviews/, not a suffix allow-list — the same
            // correction the gate needed: 81 of 164 review files use
            // `-bpass.md` and only 79 use `-review.md`, so matching one suffix
            // is blind to the majority convention.
            .where((s) =>
                s.startsWith('docs/reviews/') &&
                s.endsWith('.md') &&
                !const {'INDEX.md', 'README.md'}.contains(s.split('/').last))
            .toList();
      }
      final subjects = _gitOut(['log', '--format=%s', range]) ?? '';
      hasFix = subjects
          .split('\n')
          .any((s) => RegExp(r'^(fix|bug|regression)(\([^)]*\))?:').hasMatch(s.trim()));
    }

    final verdict = evaluateBatchClose(BatchCloseInputs(
      unpushedCommits: count,
      headSha: headSha,
      lastReportedSha: lastSha,
      stopHookActive: stopHookActive,
      killSwitch: File('$root/$_killSwitch').existsSync(),
      newestRetrospective: _newestRetrospective(_primaryRoot()),
      oldestUnpushedAt: oldestAt,
      reviewsAdded: reviews,
      hasBugfixCommit: hasFix,
    ));

    if (!verdict.shouldBlock) exit(0);

    // Record BEFORE emitting, so a crash between the two cannot re-fire forever.
    try {
      stateFile.parent.createSync(recursive: true);
      stateFile.writeAsStringSync('$headSha\n');
    } catch (_) {
      // Could not persist ⇒ do NOT block, or the hook could loop on every turn.
      exit(0);
    }

    stdout.writeln(jsonEncode({
      'decision': 'block',
      'reason': renderBlockReason(verdict),
    }));
    exit(0);
  } catch (_) {
    exit(0); // never wedge a session
  }
}
