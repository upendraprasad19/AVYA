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
// Allowlisted files build the string from an ALREADY-IST value (the helper itself, or an
// istNow/istMidnight-derived loop var) or from a fixed calendar date (date-of-birth) — no
// timezone ambiguity. The allowlist is LEGIT sites, not tolerated bugs.
//
// Exit 0 = pass. Exit 1 = a device-local date-key outside the allowlist. `--warn-only` supported.

import 'dart:io';

const allowlist = <String>{
  'lib/core/utils/ist_date.dart', // istDateStr builds the canonical IST string
  'lib/core/utils/date_utils.dart', // formatDateKey == istDateStr
  'lib/core/services/nlog_key_migrator.dart', // re-derives an nlog_ key from an already-IST `istDate`
  'lib/features/profile/screens/edit_profile_screen.dart', // date-of-birth (fixed calendar date)
  'lib/features/train/repositories/workout_repository.dart', // loop var already IST (istNow midnight)
  'lib/core/services/workout_write_service.dart', // its own istDateStr() impl (converts to IST first)
  'lib/core/services/streak_progress_service.dart', // builds from mondayOfIst() — already IST
};

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate ist-date-key] SKIP: lib/ not present.');
    exit(0);
  }
  // `.month...padLeft(2,'0')` then `.day...padLeft` within a small window — catches
  // both single-line and the `-'` line-continuation form.
  final pattern = RegExp(
    r"\.month\.toString\(\)\.padLeft\(2,\s*'0'\)[\s\S]{0,40}\.day\.toString\(\)\.padLeft",
  );
  final violations = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final norm = e.path.replaceAll('\\', '/');
    if (allowlist.contains(norm)) continue;
    final content = e.readAsStringSync();
    for (final m in pattern.allMatches(content)) {
      final lineNum = content.substring(0, m.start).split('\n').length;
      violations.add('$norm:$lineNum');
    }
  }
  final tag = warnOnly ? '[Gate ist-date-key WARN]' : '[Gate ist-date-key]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no device-local YYYY-MM-DD date keys in lib/ (outside the IST/DOB allowlist).');
    exit(0);
  }
  stderr.writeln('${warnOnly ? "$tag WARN" : "$tag FAIL"}: ${violations.length} device-local date-key construction(s):');
  for (final v in violations.take(20)) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: use istDateStr(date) / istTodayStr() (lib/core/utils/ist_date.dart) so the key matches the IST-keyed writer.');
  exit(warnOnly ? 0 : 1);
}
