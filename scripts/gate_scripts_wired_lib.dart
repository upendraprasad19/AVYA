// scripts/gate_scripts_wired_lib.dart
//
// Pure parsing logic extracted from check_gate_scripts_wired.dart (Gate 33)
// so it can be imported by both the gate itself and its regression test —
// a single definition instead of two independently-maintained copies that
// can silently drift, which is the exact root-cause shape d7a3f9 fixed one
// level up (test.yml's case-skip list vs pre-commit.sh's). Round-1 review of
// that fix flagged the new test for repeating the pattern it was written to
// guard against.
//
// Deliberately NOT named check_gate_scripts_wired_lib.dart: Gate 33 itself
// scans every scripts/check_*.dart file as a gate script the dynamic
// pre-commit.sh / test.yml loops must invoke. A check_*-prefixed library
// file with no main() would match that glob, get bare-invoked by both
// loops, and crash with "Invoked Dart programs must have a 'main' function
// defined" — the same failure mode this file exists to prevent, one file
// over. Confirmed live: naming it with the check_ prefix during this fix's
// own development pushed Gate 33's count from 91 to 92 and reproduced the
// crash on `dart run`. Matches the existing convention of every OTHER pure
// script library in this repo (bug_index_lib.dart, worktree_guard_lib.dart,
// git_safety_lib.dart, plan_review_record_lib.dart) — none carry a
// gate-triggering prefix.

/// Matches a `check_<name>.dart` script filename inside a shell case block.
final caseSkipRegex = RegExp(r'check_[a-z0-9_]+\.dart');

/// Return script filenames that appear inside the PATTERN-LIST portion of a
/// shell `case "$NAME" in ... esac` block's arms (the `name|\` lines up to
/// and including the one closing with `)`) — these are intentionally skipped
/// by the dynamic `for GATE in scripts/check_*.dart` loop (present in both
/// scripts/pre-commit.sh and .github/workflows/test.yml).
///
/// Deliberately does NOT scan a matched arm's COMMAND BODY (the lines
/// between its closing `)` and its `;;`) — B-pass review of d7a3f9 found
/// that scanning the whole arm let an explanatory comment restating a script
/// name (e.g. "# check_closes_oi_cited.dart: a commit-msg gate...") register
/// as a case-skip even with no real pattern for it. That is silent, not
/// fail-closed: `check_gate_scripts_wired.dart`'s wiring check for THAT
/// script never used the false positive on its own (a separate, real mention
/// elsewhere in the same file happened to also satisfy it), but this
/// function's own regression test uses the false positive directly — a
/// future edit removing a real case pattern while leaving its explanatory
/// comment behind would make the test wrongly keep passing.
Set<String> extractCaseSkips(String content, RegExp pattern) {
  final skips = <String>{};
  final lines = content.split('\n');
  var inCase = false;
  var inPatternList = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('case ') && trimmed.contains(' in')) {
      inCase = true;
      inPatternList = true;
      continue;
    }
    if (inCase && trimmed == 'esac') {
      inCase = false;
      inPatternList = false;
      continue;
    }
    if (!inCase) continue;
    if (inPatternList) {
      for (final m in pattern.allMatches(line)) {
        skips.add(m.group(0)!);
      }
      if (line.contains(')')) {
        inPatternList = false; // the closing paren ends this arm's pattern list
      }
      continue;
    }
    // Inside an arm's command body — do not scan for names here. `;;` ends
    // the arm and opens the next one's pattern list (or is immediately
    // followed by `esac` when there is only one arm, as in every case block
    // in this repo today).
    if (trimmed == ';;') {
      inPatternList = true;
    }
  }
  return skips;
}

// ---------------------------------------------------------------------------
// Typed allowlist runners (OI-155, gate-integrity batch 2026-09-19).
//
// Gate 33's `_allowList` used to be `Map<String, String>` — gate name to free
// prose — and the prose was read by nothing: an allowlisted gate was simply
// skipped. Six entries claimed a runner that did not exist ("runs in
// /build-apk skill Gate 14b" — no such section), so six gates ran NOWHERE
// while Gate 33 reported PASS on every commit. A runner is now a typed CLAIM
// the gate re-verifies on every commit.
// ---------------------------------------------------------------------------

enum RunnerKind { file, loop, manual }

/// Where an allowlisted gate actually runs, as a checkable claim.
///
///   file(path)   — [path] INVOKES the gate: `run scripts/<gate>` on a
///                  non-comment line (see [invokesGate]).
///   loop(name)   — the named dynamic `for GATE in scripts/check_*.dart` loop
///                  (`preCommit` | `ci`, see [loopFiles]) exists and does NOT
///                  case-skip the gate.
///   manual(OI-N) — nothing automated runs it; the cited OI on the merged
///                  boards is OPEN or IN_PROGRESS. CLOSED, absent, or an
///                  unreadable board all FAIL, so the entry re-opens itself
///                  the moment its blocker is closed without the gate getting
///                  a real runner.
class GateRunner {
  final RunnerKind kind;
  final String target; // file path | 'preCommit' / 'ci' | 'OI-NNN'
  final String reason;
  const GateRunner._(this.kind, this.target, this.reason);
  const GateRunner.file(String path, String reason)
      : this._(RunnerKind.file, path, reason);
  const GateRunner.loop(String loop, String reason)
      : this._(RunnerKind.loop, loop, reason);
  const GateRunner.manual(String oi, String reason)
      : this._(RunnerKind.manual, oi, reason);
}

/// The two dynamic `check_*` loops, by the name a `loop()` runner cites.
const loopFiles = <String, String>{
  'preCommit': 'scripts/pre-commit.sh',
  'ci': '.github/workflows/test.yml',
};

/// The literal both loops key on (`for GATE in scripts/check_*.dart`).
const dynamicLoopMarker = 'scripts/check_*.dart';

/// True iff some non-comment line INVOKES the gate: `run scripts/<gate>`.
///
/// A comment, a prose sentence, or a case-skip entry naming the gate is not
/// an invocation — the free-prose "runs in X" class OI-155 exists to kill.
/// Every live invocation line of an allowlisted gate in the repo carries
/// this shape (measured 2026-09-19 across build-apk.md, test.yml,
/// pre-commit.sh and commit-msg.sh: `grep -n 'run scripts/check_'`), so an
/// invocation-shaped predicate has zero false negatives today. A
/// skill/command doc counts: `.claude/commands/build-apk.md` is executed by
/// being read, and its `dart run scripts/<gate>` lines are real invocations.
///
/// B-pass finding 1 (gate-integrity, 2026-09-19): the first version was a
/// bare `contains('run scripts/<gate>')` on non-comment lines, so PRINTED text
/// counted — a heredoc body (`cat <<'EOF' … dart run scripts/x … EOF`) or a
/// prose sentence ("You should run scripts/x by hand") both read as wired,
/// the exact shape `extractCaseSkips` above was hardened against. Two
/// tightenings: (1) the needle must be INVOKER-prefixed — every live
/// invocation line in the repo (19, census 2026-09-19 across pre-commit.sh,
/// commit-msg.sh, test.yml, build-apk.md) is `"$DART_BIN" run scripts/…`,
/// `$DART_BIN run …`, `${DART_BIN} run …` or `dart run …`; (2) heredoc bodies
/// are skipped, the opener line itself still counting (an invocation whose
/// STDIN is a heredoc is real).
bool invokesGate(String content, String gate) {
  final invocation = RegExp(
      r'''(?:"\$DART_BIN"|'\$DART_BIN'|\$\{DART_BIN\}|\$DART_BIN|\bdart)\s+run\s+scripts/'''
      '${RegExp.escape(gate)}'
      r'(?![A-Za-z0-9_])');
  String? heredocTag;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (heredocTag != null) {
      if (line == heredocTag) heredocTag = null; // terminator ends the body
      continue;
    }
    if (line.startsWith('#')) continue;
    if (invocation.hasMatch(line)) return true;
    final open = _heredocOpenRe.firstMatch(line);
    if (open != null) heredocTag = open.group(2);
  }
  return false;
}

/// `<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"` — the tag is group 2. Applied only
/// to a line that did NOT itself invoke the gate, so `dart run scripts/x <<EOF`
/// counts while the body that follows it does not.
final _heredocOpenRe =
    RegExp('''<<-?\\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\\1''');

final _oiRe = RegExp(r'^OI-\d+$');

/// Violations for one allowlisted [gate] against its declared [runners].
///
/// [read] returns a file's content or `null` when unreadable. [caseSkipsOf]
/// extracts a loop file's case-skip set (pass `extractCaseSkips` with
/// [caseSkipRegex]). [boardStatuses] is `mergedBoardStatuses(open, closed)`
/// from oi_closure_lib.dart — `null` means the OPEN board was unreadable,
/// which fails CLOSED for every `manual:` runner (an unverifiable claim is
/// not a satisfied one). Every branch that cannot verify the claim adds a
/// violation; silence means the claim held.
List<String> runnerViolations({
  required String gate,
  required List<GateRunner> runners,
  required String? Function(String path) read,
  required Set<String> Function(String content) caseSkipsOf,
  required Map<String, String>? boardStatuses,
}) {
  final out = <String>[];
  if (runners.isEmpty) out.add('$gate: allowlist entry declares no runner');
  for (final r in runners) {
    switch (r.kind) {
      case RunnerKind.file:
        final c = read(r.target);
        if (c == null) {
          out.add('$gate: runner file ${r.target} is unreadable');
        } else if (!invokesGate(c, gate)) {
          out.add('$gate: ${r.target} never invokes it '
              '(`run scripts/$gate` on a non-comment line)');
        }
      case RunnerKind.loop:
        final path = loopFiles[r.target];
        final c = path == null ? null : read(path);
        if (c == null) {
          out.add('$gate: loop `${r.target}` is not a known loop '
              '(${loopFiles.keys.join('|')}) or its file is unreadable');
        } else if (!c.contains(dynamicLoopMarker)) {
          out.add('$gate: $path has no dynamic check_* loop');
        } else if (caseSkipsOf(c).contains(gate)) {
          out.add('$gate: declared loop:${r.target} but $path case-skips it');
        }
      case RunnerKind.manual:
        if (!_oiRe.hasMatch(r.target)) {
          out.add('$gate: manual runner must cite OI-NNN, got `${r.target}`');
        } else if (boardStatuses == null) {
          out.add('$gate: manual:${r.target} but the OI board is unreadable '
              '(fail CLOSED)');
        } else {
          final status = boardStatuses[r.target];
          if (status == null) {
            out.add('$gate: manual:${r.target} names no OI on either board');
          } else if (status == 'CLOSED') {
            out.add('$gate: manual:${r.target} is CLOSED -- give the gate a '
                'real runner or re-file the blocker');
          }
        }
    }
  }
  return out;
}

/// Mirror of gate_test_ledger_lib.dart's "ledger entry but no `scripts/<gate>`
/// on disk": an allowlist entry for a gate that no longer exists is stale
/// bookkeeping (the retire path of OI-101 / OI-223 must delete the entry too).
List<String> staleAllowlistViolations(
        Set<String> gatesOnDisk, Iterable<String> allowlistKeys) =>
    [
      for (final k in allowlistKeys)
        if (!gatesOnDisk.contains(k))
          '$k: allowlist entry but no scripts/$k on disk (stale -- delete the entry)',
    ];
