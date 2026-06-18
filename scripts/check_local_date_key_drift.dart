// scripts/check_local_date_key_drift.dart
//
// Gate (psych-skill-and-audit 2026-06-07, audit IST cluster — F4/F6/F7/F8/F9/F23/F24/F27/F36):
// Ban device-local `YYYY-MM-DD` date-key construction in lib/, i.e.
//   '${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day.toString().padLeft(2,'0')}'
// Date keys + "today"/"this week" logic MUST go through the IST helpers
// (istDateStr / istTodayStr / istMidnight / mondayOfIst — lib/core/utils/ist_date.dart),
// because a device-local string drifts vs the IST-keyed Hive/cloud data on any device
// whose local date != IST. This is the recurring IST-sweep-gap class
// (feedback_use_ist_throughout / feedback_ist_sweep_gap) — 21 reader/writer sites were
// swept in this batch; the gate stops it recurring.
//
// Extended (discipline-overhaul P1.F 2026-06-18): also scans supabase/functions/**/*.ts
// for raw `.toISOString().slice(0, 10)` / `.substring(0, 10)` that derive from a raw
// `new Date()` or `new Date(Date.now()…)` (UTC). On the server (Deno, UTC system clock),
// these produce the UTC date, not IST — wrong day near IST midnight (05:30 UTC). Only
// flag TS sites where the value flows from a raw UTC `new Date()` construction; skip sites
// where the variable/expression name contains an IST-helper signal word (istNow, istNow,
// istDateStr, istToday, istDayStart, prDateIst, etc.) or where it's inside the IST helper
// file itself.
//
// Allowlisted files build the string from an ALREADY-IST value (the helper itself, or an
// istNow/istMidnight-derived loop var) or from a fixed calendar date (date-of-birth) — no
// timezone ambiguity. The allowlist is LEGIT sites, not tolerated bugs.
//
// Exit 0 = pass. Exit 1 = a device-local date-key outside the allowlist. `--warn-only` supported.

import 'dart:io';

const dartAllowlist = <String>{
  'lib/core/utils/ist_date.dart', // istDateStr builds the canonical IST string
  'lib/core/utils/date_utils.dart', // formatDateKey == istDateStr
  'lib/core/services/nlog_key_migrator.dart', // re-derives an nlog_ key from an already-IST `istDate`
  'lib/features/profile/screens/edit_profile_screen.dart', // date-of-birth (fixed calendar date)
  'lib/features/train/repositories/workout_repository.dart', // loop var already IST (istNow midnight)
  'lib/core/services/workout_write_service.dart', // its own istDateStr() impl (converts to IST first)
  'lib/core/services/streak_progress_service.dart', // builds from mondayOfIst() — already IST
  // Manual-IST-correct: applies +5:30 Duration offset before slicing — equivalent to istDateStr.
  'lib/features/onboarding/providers/onboarding_provider.dart',
};

// TS files where a .toISOString().slice/substring(0,10) is KNOWN-CORRECT (IST-derived).
// The _shared/ist_date.ts file is the canonical IST helper itself — its own usage is correct
// by definition.
const tsAllowlist = <String>{
  'supabase/functions/_shared/ist_date.ts', // IST helper itself; its toISOString() is on an already-shifted Date
};

// IST-helper signal words: if the expression or its immediately-preceding variable
// assignment contains any of these words, the site is IST-derived and should NOT be flagged.
// Pattern: `istNow`, `istToday`, `istDateStr`, `istDayStart`, `prDateIst`, `ist_date`, or
// a variable named with these prefixes.
final istHelperSignal = RegExp(
  r'istNow|istToday|istDateStr|istDayStart|prDateIst|ist_date|IST_OFFSET',
  caseSensitive: false,
);

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final violations = <String>[];

  // ── Dart: lib/ — hand-rolled `.month.padLeft(2,'0')…day.padLeft` form ──────
  final libDir = Directory('lib');
  if (libDir.existsSync()) {
    final dartPadLeftPattern = RegExp(
      r"\.month\.toString\(\)\.padLeft\(2,\s*'0'\)[\s\S]{0,40}\.day\.toString\(\)\.padLeft",
    );
    for (final e in libDir.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final norm = e.path.replaceAll('\\', '/');
      if (dartAllowlist.contains(norm)) continue;
      final content = e.readAsStringSync();
      for (final m in dartPadLeftPattern.allMatches(content)) {
        final lineNum = content.substring(0, m.start).split('\n').length;
        violations.add('$norm:$lineNum  [Dart hand-rolled YYYY-MM-DD key]');
      }
    }
  }

  // ── Dart: lib/ — toIso8601String().substring(0, 10) form (prevention-only) ─
  if (libDir.existsSync()) {
    final dartIsoPattern = RegExp(
      r'\.toIso8601String\(\)\s*\.substring\s*\(\s*0\s*,\s*10\s*\)',
    );
    for (final e in libDir.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final norm = e.path.replaceAll('\\', '/');
      if (dartAllowlist.contains(norm)) continue;
      final content = e.readAsStringSync();
      for (final m in dartIsoPattern.allMatches(content)) {
        final lineNum = content.substring(0, m.start).split('\n').length;
        violations.add('$norm:$lineNum  [Dart toIso8601String().substring(0,10) — use istDateStr() instead]');
      }
    }
  }

  // ── TypeScript: supabase/functions/ — raw-UTC `.toISOString().slice/substring(0,10)` ──
  //
  // Detection strategy: scan for `.toISOString().slice(0, 10)` or `.substring(0, 10)`.
  // For each match, look at the surrounding ~200 chars of context to determine whether
  // the Date object derives from a raw `new Date()` / `Date.now()` (UTC — BAD) or from
  // an IST helper call (GOOD). We look at up to 3 lines before the match for an IST
  // signal word. If found: skip (IST-correct). If not found: flag as violation.
  final functionsDir = Directory('supabase/functions');
  if (functionsDir.existsSync()) {
    // Matches `.toISOString().slice(0, 10)` or `.toISOString().substring(0, 10)`
    // with optional whitespace.
    final tsIsoPattern = RegExp(
      r'\.toISOString\(\)\s*\.(?:slice|substring)\s*\(\s*0\s*,\s*10\s*\)',
    );
    for (final e in functionsDir.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.ts')) continue;
      final norm = e.path.replaceAll('\\', '/');
      if (tsAllowlist.contains(norm)) continue;
      final content = e.readAsStringSync();
      final lines = content.split('\n');
      for (final m in tsIsoPattern.allMatches(content)) {
        final lineNum = content.substring(0, m.start).split('\n').length; // 1-based
        // Gather context: the current line plus up to 3 lines before it.
        final startLine = (lineNum - 4).clamp(0, lines.length - 1); // 3 lines before
        final contextLines = lines.sublist(startLine, lineNum).join('\n');
        // If IST helper signal is present in context, this is an IST-derived call — skip.
        if (istHelperSignal.hasMatch(contextLines)) continue;
        violations.add(
          '$norm:$lineNum  [TS raw-UTC new Date().toISOString().slice(0,10) — use istDateStr() from _shared/ist_date.ts]',
        );
      }
    }
  }

  final tag = warnOnly ? '[Gate ist-date-key WARN]' : '[Gate ist-date-key]';
  if (violations.isEmpty) {
    stdout.writeln(
      '$tag PASS: no device-local/raw-UTC YYYY-MM-DD date keys in lib/ or supabase/functions/ (outside the IST allowlists).',
    );
    exit(0);
  }
  stderr.writeln(
    '${warnOnly ? "$tag WARN" : "$tag FAIL"}: ${violations.length} raw-UTC or device-local date-key construction(s):',
  );
  for (final v in violations.take(20)) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln(
    'Dart fix: use istDateStr(date) / istTodayStr() (lib/core/utils/ist_date.dart).\n'
    'TS fix:   use istDateStr(new Date(Date.now() ± offset)) from supabase/functions/_shared/ist_date.ts.',
  );
  exit(warnOnly ? 0 : 1);
}
