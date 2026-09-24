// Discipline hooks: move the prose-only invariants that no git gate can catch
// into the HARNESS, so it reminds the agent at the trigger moment instead of the
// founder having to. Audit 2026-06-27 — see
// C:/Users/upend/.claude/plans/i-want-to-audit-sunny-quilt.md.
//
// One script, three hook events (branched on `hook_event_name` from stdin):
//   • UserPromptSubmit  → bug/fix/observation-shaped prompt → inject the hot-set
//                         (the 7 highest-recurrence rules) + a TodoWrite nudge.
//   • PreToolUse(Skill) → about to fire a skill → inject "load discipline first"
//                         (§4.12 discipline-before-skill). Registered with
//                         matcher "Skill" in settings.json.
//   • SessionStart      → fires on EVERY source (startup/resume/compact; the
//                         "compact" matcher was REMOVED in settings.json so the
//                         worktree warning can surface at session start). Emits
//                         up to five self-guarded pieces: the hot-set
//                         re-injection (compact source ONLY, so discipline
//                         survives summarization); a worktree-per-session warning
//                         when in the shared main worktree (§4.13); a
//                         main-vs-origin/main sync warning (multi-machine drift —
//                         2026-09-24 VPS 300-commit-behind incident); a MEMORY.md
//                         size nudge (→ /consolidate-memory) when the per-session
//                         memory index has grown past its soft cap; and the OI
//                         board line.
//
// Injection is ALWAYS via structured JSON hookSpecificOutput.additionalContext —
// for PreToolUse, plain stdout goes to the debug log only, so the JSON field is
// the sole channel (verified against code.claude.com/docs/en/hooks 2026-06-27).
//
// CONTRACT: these hooks must NEVER break the session. On ANY error (no stdin,
// malformed JSON, unknown event) the script exits 0 and emits nothing. The
// reminder strings are INLINED (no external file) to keep one moving part.

import 'dart:convert';
import 'dart:io';

import 'batch_close_lib.dart' show primaryRootFrom, mangleProjectPath;
import 'oi_numbering_lib.dart';

// Bug / fix / observation triggers for UserPromptSubmit. Word-bounded where a
// short token would over-match (e.g. "fix" inside "prefix").
final RegExp _trigger = RegExp(
  r'\b(bug|bugs|broke|broken|breaks|breaking|crash|crashes|crashed|'
  r'regression|regress|observation|observations|fix|fixes|fixing|'
  r'wrong|incorrect|fails|failing|failed|'
  r"doesn'?t work|does not work|isn'?t working|is not working|not working|"
  r'unexpected|misbehav|stale data|wrong value)\b',
  caseSensitive: false,
);

// The hot-set: the 7 highest-recurrence prose-only invariants, condensed. Kept
// deliberately short — a bloated injection rebuilds the dilution the audit found.
const String _hotSet = '''
⚠️ DISCIPLINE HOT-SET (harness-injected — this reads like a bug/fix/observation).
Apply these BEFORE touching code; instantiate them as TodoWrite items now:
1. WAIT → BRAINSTORM → PROPOSE. If APK observations, gather ALL first; never reflex-fix (§4.1).
2. BUG-HISTORY FIRST. Grep docs/diagnoses/INDEX.md + feedback_*.md for this symptom/file BEFORE
   hypothesizing a root cause; cite or rule out recurrence (§4.1.5).
3. NAME WRITER + READER by file:line before proposing any fix — writer/reader drift is the
   default suspect class (§4.1, recurring ≥15×).
4. NO DEFERRALS, incl. euphemisms. Banned re-wraps: "dedicated/follow-up/test-maintenance/cleanup
   batch", "gradual population", "can be folded into", "lower-severity", "responsible handoff".
   Fix every surfaced bug in THIS batch (§4.2).
5. DIAGNOSE-DOC + behavioral regression test per fix; verify the FULL chain (write→read), not
   just an HTTP/exit-0 shape (§4.4 r21/r22).
6. SELF-TRIGGER the ≥account /code-review (B-pass) BEFORE the --no-ff merge — don't wait to be
   asked (§4.3).
7. BEFORE any Skill call, load + apply §4 (and the Wardroom brand soul for copy) — never fire a
   skill blind (§4.12).
Verify numeric claims from subagents/memory against the actual file before relying on them.''';

// Discipline-before-skill reminder (§4.12), injected when a Skill is about to run.
const String _skillReminder = '''
⚠️ DISCIPLINE BEFORE SKILL (harness-injected — a Skill is about to run).
Load + apply the governing invariants FIRST — never fire a skill blind (§4.12):
- CLAUDE.md §4 process invariants for the action this skill performs;
- the Wardroom brand soul (lib/shared/widgets/wardroom/CLAUDE.md) for ANY copy/UI/mockup work;
- the observation → bug-history → writer/reader workflow (§4.1/§4.1.5) if this is a fix/debug skill.
If this is /code-review or /hermes-pass: confirm the blast-radius and that the ×2 plan-review
already happened (§4.12). If /build-apk: from main only, explicit approval given (§4.3).''';

// Post-compaction re-injection: discipline must survive the summarization.
const String _compactReinject = '''
⚠️ POST-COMPACTION — the discipline hot-set still applies (re-injected by the harness):
$_hotSet''';

void main() async {
  try {
    final raw = await _readStdin().timeout(const Duration(seconds: 3),
        onTimeout: () => '');
    if (raw.trim().isEmpty) return;

    Map<String, dynamic> input;
    try {
      final decoded = jsonDecode(raw);
      input = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      // Not JSON → treat the whole payload as a UserPromptSubmit prompt (keeps
      // the original bare-text test path working).
      input = {'hook_event_name': 'UserPromptSubmit', 'prompt': raw};
    }

    final event = (input['hook_event_name'] as String?) ?? 'UserPromptSubmit';

    switch (event) {
      case 'PreToolUse':
        // Matcher "Skill" in settings.json already scopes this, but double-check.
        final tool = (input['tool_name'] as String?) ?? '';
        if (tool == 'Skill') _emit('PreToolUse', _skillReminder);
        break;

      case 'SessionStart':
        // Fires on EVERY SessionStart source (startup/resume/compact) — the
        // "compact" matcher was removed from settings.json so the worktree
        // warning can surface at session start. Each piece self-guards on its
        // own condition (compact re-inject only on compact; worktree warning
        // only in the shared main worktree; mem nudge only when over cap).
        final source = (input['source'] as String?) ?? '';
        final parts = <String>[];
        if (source == 'compact') parts.add(_compactReinject);
        final wtWarn = _worktreeWarning();
        if (wtWarn.isNotEmpty) parts.add(wtWarn);
        final syncWarn = await _mainSyncWarning();
        if (syncWarn.isNotEmpty) parts.add(syncWarn);
        final memNudge = _memoryIndexNudge();
        if (memNudge.isNotEmpty) parts.add(memNudge);
        final oiLine = _oiBoardLine();
        if (oiLine.isNotEmpty) parts.add(oiLine);
        if (parts.isNotEmpty) _emit('SessionStart', parts.join('\n\n'));
        break;

      case 'UserPromptSubmit':
      default:
        final prompt = (input['prompt'] as String?) ?? '';
        if (_trigger.hasMatch(prompt)) _emit('UserPromptSubmit', _hotSet);
        break;
    }
  } catch (_) {
    // Never break the session — swallow everything, exit 0.
    return;
  }
}

// Best-effort MEMORY.md size nudge. MEMORY.md (the per-session loaded memory index)
// lives OUTSIDE the repo, under ~/.claude/projects/<mangled-project-path>/memory/.
// The harness mangles the PRIMARY repo root's path into that dir name by replacing
// each of : \ / and space with '-' (so "C:\Upendra\Claude Code\Fitness App" →
// "C--Upendra-Claude-Code-Fitness-App"). If the index is over the soft cap, suggest
// /consolidate-memory. Fail-silent: any resolution / IO error returns '' so the
// session is never affected (honours the top-of-file NEVER-break-the-session contract).
// A DISCIPLINE_HOOK_MEMORY_PATH env override is honoured for testing.
//
// ⚠ FIXED 2026-09-23 (diagnose pending, discipline-v3-phase3 batch): this used to
// mangle `Directory.current.path` directly, which is the WORKTREE path in every
// §4.13 session — not the primary repo root the harness actually keyed the memory
// directory name on. In a linked worktree that mangled to a directory that does
// not exist (e.g. "...--claude-worktrees-<slug>"), so `memFile.existsSync()` was
// always false and the nudge silently never fired from ANY worktree session — the
// exact `--show-toplevel`-vs-`--git-common-dir` bug `batch_close_lib.dart`'s
// `primaryRootFrom` doc comment already names and was written to fix, just never
// applied here. Now reuses that same pure function + `mangleProjectPath` instead
// of re-deriving (and re-breaking) the path a third time.
/// Pure derivation of the harness MEMORY.md path from its three raw inputs.
/// EXTRACTED so a test can drive it directly without a real git repo or a real
/// HOME — the exact "a function no test can reach is a function no test
/// protects" lesson `batch_close_lib.dart`'s own header names, applied to the
/// bug this function exists to fix. Returns null when any input cannot yield
/// an answer (missing home, unresolvable git-common-dir, no PRIMARY root).
String? resolveMemoryIndexPath({
  required String? override,
  required String? home,
  required String? gitCommonDirOutput,
}) {
  if (override != null && override.isNotEmpty) return override;
  if (home == null || home.isEmpty) return null;
  final primaryRoot = primaryRootFrom(gitCommonDirOutput);
  if (primaryRoot == null) return null;
  final mangled = mangleProjectPath(primaryRoot);
  return '$home/.claude/projects/$mangled/memory/MEMORY.md';
}

String _memoryIndexNudge() {
  try {
    const softBytes = 18000; // ~500B of hysteresis above the 17,510 soft target
    const softLines = 150;
    final gitCommonDir = Process.runSync(
        'git', ['rev-parse', '--path-format=absolute', '--git-common-dir']);
    final path = resolveMemoryIndexPath(
      override: Platform.environment['DISCIPLINE_HOOK_MEMORY_PATH'],
      home: Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'],
      gitCommonDirOutput: gitCommonDir.exitCode == 0 ? gitCommonDir.stdout as String? : null,
    );
    if (path == null) return '';
    final memFile = File(path);
    if (!memFile.existsSync()) return '';
    final bytes = memFile.lengthSync();
    final lines = memFile.readAsLinesSync().length;
    if (bytes <= softBytes && lines <= softLines) return '';
    final kb = (bytes / 1024).toStringAsFixed(1);
    return '⚠️ MEMORY.md (the per-session memory index) is ${kb}KB / $lines lines — '
        'over the soft cap. Run /consolidate-memory when convenient: it merges '
        'overlapping feedback/project files + archives shipped batches, without '
        'losing content or breaking a repo citation.';
  } catch (_) {
    return '';
  }
}

// Worktree-per-session warning (CLAUDE.md §4.13). Emits ONLY when the session is
// running in the PRIMARY (shared main) worktree — where the git index is shared
// with any other session in this folder, so concurrent staging mixes files
// (2 incidents 2026-07-07). In a linked worktree (`--git-dir` != `--git-common-dir`)
// the index is isolated → no warning. Fail-silent: any git/IO error returns '' so
// the session is never broken (honours the top-of-file NEVER-break contract).
// Both dirs are resolved ABSOLUTE (--path-format=absolute, git 2.31+) so the
// compare is correct even when the session cwd is a SUBDIRECTORY of the primary
// (where plain `--git-common-dir` returns a relative "../.git" that would spuriously
// differ from the absolute `--git-dir` and suppress the warning).
String _worktreeWarning() {
  try {
    final gd =
        Process.runSync('git', ['rev-parse', '--path-format=absolute', '--git-dir']);
    final cd = Process.runSync(
        'git', ['rev-parse', '--path-format=absolute', '--git-common-dir']);
    if (gd.exitCode != 0 || cd.exitCode != 0) return '';
    String norm(String s) => s
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
    final gitDir = norm(gd.stdout as String);
    final commonDir = norm(cd.stdout as String);
    if (gitDir.isEmpty || commonDir.isEmpty) return '';
    if (gitDir != commonDir) return ''; // linked worktree — isolated index, safe.
    return '⚠️ WORKTREE: you are in the SHARED main worktree. Its git index is shared '
        'with any other Claude session working in this folder, so committing here can '
        'MIX your files with another session\'s work (2 incidents 2026-07-07). Before '
        'ANY edit/commit, create your own worktree:\n'
        '    sh scripts/new-worktree.sh <slug>   →   cd .claude/worktrees/<slug>\n'
        'The main worktree is INTEGRATION-ONLY (git merge + push + /build-apk). A '
        'pre-commit gate (scripts/check_commit_from_worktree.dart) will BLOCK a '
        'non-merge commit made here. See CLAUDE.md §4.13.';
  } catch (_) {
    return '';
  }
}

// Multi-machine main-sync warning (laptop <-> VPS drift, incident 2026-09-24:
// the VPS's local `main` silently drifted 300 commits behind origin/main with
// no warning until someone happened to run `git status`). Unlike
// `_oiBoardLine()` below, this DOES fetch -- deliberately. The OI line's
// "no fetch" precedent exists because that line only reports background info
// on every SessionStart source at a fixed recurring cost; this check exists
// specifically to answer "is my main current" at the one moment that matters
// (session start), so a short, BOUNDED fetch cost paid once per session is
// the right trade, not a tax. A slow/offline network degrades to the
// last-known local comparison (with a staleness caveat) rather than blocking
// the session -- the top-of-file NEVER-break contract still holds.
/// Pure, testable core. '' means "nothing to say" (in sync). `wasFetched`
/// governs whether the message can claim a live answer; `fetchAge` (only
/// meaningful when `wasFetched` is false) is the age of the last successful
/// sync recorded in FETCH_HEAD, or null if there is no local record at all.
String formatMainSyncWarning({
  required int ahead,
  required int behind,
  required bool wasFetched,
  required Duration? fetchAge,
}) {
  if (ahead == 0 && behind == 0) return '';

  String staleness;
  if (wasFetched) {
    staleness = '';
  } else if (fetchAge == null) {
    staleness = ' (offline/fetch failed, and no prior sync on record — '
        'this comparison may be badly stale)';
  } else if (fetchAge > const Duration(hours: 6)) {
    staleness = ' (offline/fetch failed — last known sync was '
        '${_formatAge(fetchAge)} ago, this may itself be stale)';
  } else {
    staleness = ' (offline/fetch failed — last known sync was '
        '${_formatAge(fetchAge)} ago)';
  }

  if (behind > 0 && ahead == 0) {
    return '⚠️ MAIN BEHIND: local main is $behind commit(s) behind '
        'origin/main$staleness. Another machine likely pushed since you '
        'last synced here. Before doing new work:\n'
        '    git pull origin main';
  }
  if (ahead > 0 && behind == 0) {
    return '⚠️ MAIN AHEAD: local main is $ahead commit(s) ahead of '
        'origin/main$staleness. Push before switching machines, or this '
        'work will not exist on the other one:\n'
        '    git push origin main';
  }
  return '⚠️ MAIN DIVERGED: local main is $ahead ahead AND $behind behind '
      'origin/main$staleness. Do not blind-merge. Reconcile deliberately:\n'
      '    git fetch origin main && git log --oneline main..origin/main   '
      '# what they have\n'
      '    git log --oneline origin/main..main                            '
      '# what you have';
}

String _formatAge(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// I/O wrapper. Attempts a short, bounded fetch of origin/main (timeout ~4s);
/// on timeout/failure, falls back to comparing against whatever
/// refs/remotes/origin/main already holds locally. Fail-silent: any
/// unexpected error/inapplicable case returns '' (never breaks the session).
Future<String> _mainSyncWarning() async {
  try {
    final hasLocalMain = await Process.run(
        'git', ['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
    if (hasLocalMain.exitCode != 0) return '';

    bool wasFetched;
    try {
      final fetchResult = await Process.run('git', [
        'fetch',
        '--quiet',
        'origin',
        '+refs/heads/main:refs/remotes/origin/main',
      ]).timeout(const Duration(seconds: 4));
      wasFetched = fetchResult.exitCode == 0;
    } catch (_) {
      // Timeout, missing git, offline, unreachable remote, etc. -- fall back
      // to whatever refs/remotes/origin/main already holds locally.
      wasFetched = false;
    }

    final hasOriginMain = await Process.run(
        'git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main']);
    if (hasOriginMain.exitCode != 0) return '';

    final counts = await Process.run('git', [
      'rev-list',
      '--left-right',
      '--count',
      'refs/heads/main...refs/remotes/origin/main',
    ]);
    if (counts.exitCode != 0) return '';
    final parts = (counts.stdout as String).trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return '';
    final ahead = int.tryParse(parts[0]);
    final behind = int.tryParse(parts[1]);
    if (ahead == null || behind == null) return '';

    Duration? fetchAge;
    if (!wasFetched) {
      final cd = await Process.run(
          'git', ['rev-parse', '--path-format=absolute', '--git-common-dir']);
      if (cd.exitCode == 0) {
        final fetchHead = File('${(cd.stdout as String).trim()}/FETCH_HEAD');
        if (fetchHead.existsSync()) {
          fetchAge = DateTime.now().difference(fetchHead.lastModifiedSync());
        }
      }
    }

    return formatMainSyncWarning(
      ahead: ahead,
      behind: behind,
      wasFetched: wasFetched,
      fetchAge: wasFetched ? null : fetchAge,
    );
  } catch (_) {
    return '';
  }
}

void _emit(String eventName, String context) {
  stdout.writeln(jsonEncode({
    'hookSpecificOutput': {
      'hookEventName': eventName,
      'additionalContext': context,
    }
  }));
}

Future<String> _readStdin() async {
  if (stdin.hasTerminal) return '';
  return utf8.decoder.bind(stdin).join();
}

/// OI allocator (spec docs/superpowers/specs/2026-09-12-oi-allocator-design.md
/// §3.4): tell the session the next free number and the ONE way to mint.
///
/// LOCAL READ ONLY -- no fetch. A `git ls-remote` over the SSH remote measured
/// 2.9-3.2 s here (review round 1, 2026-09-12) and this fires on every
/// SessionStart source including `compact`; spec §7.4 set the rule at 2 s.
/// The number is therefore "at least N as of the last sync"; mint_oi.sh syncs
/// before it reserves, so a stale N here can never cause a collision. Every
/// mint, every `sync_refs`, and any plain `git fetch origin` (default refspec
/// covers oi/*) refreshes the refs this reads. Fail-open: any error => ''.
String _oiBoardLine() {
  try {
    final top = Process.runSync('git', ['rev-parse', '--show-toplevel'], stdoutEncoding: utf8);
    if (top.exitCode != 0) return '';
    final root = (top.stdout as String).trim();
    // No origin/main => nothing to say. A wrong number is worse than none.
    final hasMain = Process.runSync(
        'git', ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main'],
        workingDirectory: root);
    if (hasMain.exitCode != 0) return '';

    String show(String path) {
      final r = Process.runSync('git', ['show', 'refs/remotes/origin/main:$path'],
          workingDirectory: root, stdoutEncoding: utf8); // utf8: the em-dash separator
      return r.exitCode == 0 ? r.stdout as String : '';
    }
    String local(String path) {
      final f = File('$root/$path');
      return f.existsSync() ? f.readAsStringSync() : '';
    }
    const open = 'docs/audit/open_issues.md';
    const closed = 'docs/audit/closed_issues.md';
    final published = mergeBoards(parseBoard(show(open)), parseBoard(show(closed)));
    final working = mergeBoards(parseBoard(local(open)), parseBoard(local(closed)));

    final refs = Process.runSync(
        'git', ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/oi/'],
        workingDirectory: root, stdoutEncoding: utf8);
    final reserved = <int>{};
    for (final l in (refs.stdout as String).split('\n')) {
      final m = RegExp(r'/oi/(\d+)$').firstMatch(l.trim());
      if (m != null) reserved.add(int.parse(m.group(1)!));
    }
    // A number filed on ANY local branch (a sibling worktree's work in flight)
    // is filed, not orphaned -- otherwise this line would tell worktree B to
    // release worktree A's number (review round 2, finding 3).
    // ONE `git grep` per 150 branches over both boards -- 0.2 s for the 205
    // local branches this repo carried on 2026-09-12 -- instead of one
    // `git show` per branch per board, which measured 15.7 s per SessionStart
    // in the same repo (spec §7.4's rule is 2 s). Chunked so the argument list
    // stays under Windows' 32 KB limit. `^## OI-N` is the same heading grep
    // mint_oi.sh uses (a heading without the em-dash counts as filed here,
    // which errs towards NOT calling a number an orphan).
    final onLocalBranches = <int>{};
    final heads = Process.runSync('git', ['for-each-ref', '--format=%(refname)', 'refs/heads/'],
        workingDirectory: root, stdoutEncoding: utf8);
    final headRefs = (heads.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = 0; i < headRefs.length; i += 150) {
      final chunk = headRefs.sublist(i, i + 150 > headRefs.length ? headRefs.length : i + 150);
      final g = Process.runSync(
          'git', ['grep', '-h', '-o', '-E', r'^## OI-[0-9]+', ...chunk, '--', open, closed],
          workingDirectory: root, stdoutEncoding: utf8);
      for (final l in (g.stdout as String).split('\n')) {
        final m = RegExp(r'OI-(\d+)$').firstMatch(l.trim());
        if (m != null) onLocalBranches.add(int.parse(m.group(1)!));
      }
    }

    final next = nextFreeNumber([published, working, {for (final r in reserved) r: ''}]);
    final unfiled = reserved
        .where((n) => !published.containsKey(n) && !working.containsKey(n) && !onLocalBranches.contains(n))
        .toList()
      ..sort();
    String subject(int n) {
      final r = Process.runSync('git', ['log', '-1', '--format=%s', 'refs/remotes/origin/oi/$n'],
          workingDirectory: root, stdoutEncoding: utf8);
      return r.exitCode == 0 ? (r.stdout as String).trim() : '(no ledger line)';
    }
    final unfiledText = unfiled.isEmpty
        ? 'none'
        : '${unfiled.map((n) => 'oi/$n [${subject(n)}]').join('; ')}'
            ' — may belong to a CLOUD branch this clone cannot see; adopt by filing `## OI-N` by '
            'hand, or `sh scripts/mint_oi.sh --release N` ONLY if the reserving branch is dead';
    return 'OI board: next free number is at least $next (as of the last sync; '
        'mint_oi.sh re-syncs before reserving). Reserved-but-unfiled: $unfiledText.\n'
        'File new OIs ONLY with:  sh scripts/mint_oi.sh "<title>"  from YOUR worktree — an '
        'UNRESERVED number fails the commit (CLAUDE.md §7, OI allocator row).';
  } catch (_) {
    return '';
  }
}
