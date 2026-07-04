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
//   • SessionStart(compact) → context was just compacted → re-inject the hot-set
//                         so discipline survives the summarization. Registered
//                         with matcher "compact". ALSO appends a MEMORY.md
//                         size nudge (→ /consolidate-memory) when the per-session
//                         memory index has grown past its soft cap.
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
        // Matcher "compact" scopes this; re-check defensively so a mis-config
        // can't make us inject on every startup (where check_alerts runs).
        final source = (input['source'] as String?) ?? '';
        final memNudge = _memoryIndexNudge();
        if (source == 'compact') {
          // Post-compaction: re-inject the hot-set; append the memory-size nudge
          // if MEMORY.md is over its soft cap.
          _emit('SessionStart',
              memNudge.isEmpty ? _compactReinject : '$_compactReinject\n\n$memNudge');
        } else if (memNudge.isNotEmpty) {
          // If the matcher is ever broadened to non-compact SessionStart sources,
          // still surface the memory-size nudge (never the compact re-inject here).
          _emit('SessionStart', memNudge);
        }
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
// The harness mangles the project path into that dir name by replacing each of
// : \ / and space with '-' (so "C:\Upendra\Claude Code\Fitness App" →
// "C--Upendra-Claude-Code-Fitness-App"). If the index is over the soft cap, suggest
// /consolidate-memory. Fail-silent: any resolution / IO error returns '' so the
// session is never affected (honours the top-of-file NEVER-break-the-session contract).
// A DISCIPLINE_HOOK_MEMORY_PATH env override is honoured for testing.
String _memoryIndexNudge() {
  try {
    const softBytes = 18000; // ~500B of hysteresis above the 17,510 soft target
    const softLines = 150;
    final override = Platform.environment['DISCIPLINE_HOOK_MEMORY_PATH'];
    final String path;
    if (override != null && override.isNotEmpty) {
      path = override;
    } else {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (home.isEmpty) return '';
      final mangled = Directory.current.path.replaceAll(RegExp(r'[:\\/ ]'), '-');
      path = '$home/.claude/projects/$mangled/memory/MEMORY.md';
    }
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
