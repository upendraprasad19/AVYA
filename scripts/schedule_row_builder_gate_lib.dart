// scripts/schedule_row_builder_gate_lib.dart
//
// Pure decision logic for check_single_schedule_row_builder.dart.
// No dart:io, no git, no filesystem — so it is directly unit-testable and
// mutation-provable (CLAUDE.md §4.4 rule 24).
//
// WHAT IT DETECTS. A "schedule-row constructor" is any file that builds the
// `schedule_<date>` Hive row map. The signature is the co-occurrence of two
// map-literal keys — `'week_character':` and `'day_of_week':` — which together
// appear in no other row shape in this repo.
//
// WHY THIS GATE EXISTS (OI-166, 2026-09-07). Four independent implementations
// of "lay out schedule rows" had drifted apart while three of them carried
// comments asserting they were in sync. The inventory
// (docs/audit/oi166-regen-implementation-inventory.md) found 8 real drifts,
// 4 of them live user-visible defects. The fourth implementation
// (hotel_workout_planner.dart) was missed by three review rounds AND by two
// versions of that inventory — and was then found in one command by running
// this very heuristic. That is the argument for a gate rather than a comment:
// the detection works, nobody had run it.
//
// ⚠ INPUT SET IS `lib/` ONLY, AND THAT IS LOAD-BEARING (review round 5, P2-11).
// Run repo-wide the same heuristic returns FIVE files — the three in lib/ plus
// test/contracts/deload_eval_behavioral_test.dart and
// test/contracts/deload_reason_staleness_behavioral_test.dart, which
// legitimately seed schedule rows as fixtures. Every behavioural test the
// Unit 2 de-duplication adds will match too. Scoped repo-wide, the hard-fail
// flip would break the build on the batch's own tests. The caller passes only
// lib/ paths; this library does not widen them.
//
// ⚠ KNOWN BLIND SPOT, stated so nobody reads this as wider coverage than it
// has: a row constructor that omits `week_character` is invisible here. Two
// exist — template_service.dart:127-138 (a `custom_template` row carrying
// neither literal) and sync_workout.dart:1965-1980 (the restore overlay,
// `day_of_week` only). Neither is a phase-layout writer, so neither is a
// candidate for the shared builder; the `'week'` stamp contract they do touch
// is pinned by the SoT registry instead.

/// Why a file is allowed to construct schedule rows outside the shared builder.
enum ScheduleRowExemption {
  /// Structurally not a phase layout — will never adopt the shared builder.
  permanent,

  /// A pre-existing implementation the OI-166 Unit 2 de-duplication converts.
  /// Every entry here must be GONE before the gate is flipped to hard-fail.
  pendingUnit2,
}

/// The ONLY files permitted to construct a schedule row.
///
/// ⚠ HARD-CODED AND PINNED BY A TEST ON PURPOSE (review round 5, P2-12).
/// Nothing otherwise stops a fifth implementation being allowlisted instead of
/// using the shared builder — which would make this gate a rubber stamp. The
/// repo already has the idiom: CLAUDE.md §4.4 rule 24's `grandfathered:` list,
/// "enumerated BY NAME" and terminal. `schedule_row_builder_gate_lib_test.dart`
/// asserts these exact contents, so adding an entry means editing an assertion
/// that states why, in a diff a reviewer sees. It is deliberately not a config
/// file, not a glob, and not a directory exemption.
const Map<String, ScheduleRowExemption> scheduleRowAllowlist = {
  // The shared builder itself (created by OI-166 Unit 2).
  'lib/core/services/schedule_row_builder.dart': ScheduleRowExemption.permanent,

  // A hotel workout is a single ad-hoc replacement day, not a phase layout.
  // Forcing it through a builder whose job is to lay weekPlans[rawWeek-1..3]
  // across plan weeks would be the wrong abstraction. Its three wrong stamps
  // are corrected in place instead (OI-166 Unit 1).
  'lib/features/ai_coach/services/hotel_workout_planner.dart':
      ScheduleRowExemption.permanent,

  // A + B — generateAndSchedule / generateAndScheduleFromDate.
  'lib/core/services/workout_schedule_read_service.dart':
      ScheduleRowExemption.pendingUnit2,

  // C — RegeneratePlanPlanner.plan.
  'lib/features/ai_coach/services/regenerate_plan_planner.dart':
      ScheduleRowExemption.pendingUnit2,
};

/// Strips `//` line comments and `/* */` block comments.
///
/// ⚠ MANDATORY before any absent-pattern source-grep in this repo
/// (`feedback_source_grep_strip_comments_first.md`): a commented-out row, or a
/// doc-comment quoting the keys — which several of these files carry, since
/// they document each other — would otherwise register as a live constructor.
String stripDartComments(String source) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  String? quote;

  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';

    if (inString) {
      if (c == r'\') {
        out.write(c);
        if (i + 1 < source.length) out.write(next);
        i += 2;
        continue;
      }
      if (c == quote) {
        inString = false;
        quote = null;
      }
      out.write(c);
      i++;
      continue;
    }

    if (c == "'" || c == '"') {
      inString = true;
      quote = c;
      out.write(c);
      i++;
      continue;
    }

    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }

    if (c == '/' && next == '*') {
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }

    out.write(c);
    i++;
  }

  return out.toString();
}

/// True when [source] writes BOTH schedule-row keys, in either spelling.
///
/// Requires BOTH keys. Either alone is common and innocent: `day_of_week`
/// appears in the sync push/restore and in swap_service; `week_character`
/// appears in the deload evaluator, which mutates an existing row rather than
/// constructing one. Only together do they mean "this file lays out a
/// schedule row from scratch".
///
/// TWO SPELLINGS, because one was a live escape. The first version matched only
/// the map-literal form (`'week_character':`). A B-pass reviewer defeated it on
/// the first attempt (2026-09-08) by building the map and then assigning
/// `row['week_character'] = ...` — an ordinary Dart idiom the gate could not
/// see, on the very gate whose stated purpose is to stop a fifth
/// implementation being added. Each key is now matched by literal-key OR
/// index-assignment, INDEPENDENTLY, which also catches a file that MIXES the
/// two forms. Verified false-positive-free at the time of widening: no file
/// under `lib/` writes both keys by index assignment, so this flags nothing new.
///
/// ⚠ RESIDUAL, AND IT DOES NOT CONVERGE. A source grep is bounded by what its
/// author could imagine writing. `row[_kWeekChar] = ...` with a named constant,
/// an alias, or a computed key still passes, and tightening the pattern further
/// only moves the boundary rather than closing it. The code-review skill states
/// the general rule: the finding is not "the regex is wrong", it is "this needs
/// a runtime test that observes the behaviour". That test is Unit 2's business —
/// the shared `buildScheduleRows` makes a rogue constructor structurally
/// impossible rather than merely detectable, which is the actual fix. This gate
/// is the §4.11 detector that must exist BEFORE that refactor, and it stays
/// WARN-only until then. Recorded here rather than left implicit, so nobody
/// mistakes a PASS for proof that no fifth implementation exists.
bool _writesKey(String code, String key) {
  if (code.contains("'$key':") || code.contains('"$key":')) return true;
  return RegExp('''\\[\\s*['"]$key['"]\\s*\\]\\s*=''').hasMatch(code);
}

bool constructsScheduleRow(String source) {
  final code = stripDartComments(source);
  return _writesKey(code, 'week_character') && _writesKey(code, 'day_of_week');
}

/// Paths (repo-relative, `/`-separated) that construct schedule rows but are
/// not on the allowlist. Sorted, so output is stable across platforms.
List<String> scheduleRowViolations(Map<String, String> libDartFiles) {
  final offenders = <String>[];
  for (final entry in libDartFiles.entries) {
    final path = entry.key.replaceAll(r'\', '/');
    if (scheduleRowAllowlist.containsKey(path)) continue;
    if (constructsScheduleRow(entry.value)) offenders.add(path);
  }
  offenders.sort();
  return offenders;
}

/// Allowlisted files that no longer construct a schedule row, i.e. entries that
/// have become stale and should be deleted.
///
/// An allowlist that only ever grows is how an exemption list rots into a
/// rubber stamp. Reported as a WARNING, never a failure: a stale entry is
/// untidy, not dangerous, and must never block a commit.
List<String> staleAllowlistEntries(Map<String, String> libDartFiles) {
  final normalized = <String, String>{
    for (final e in libDartFiles.entries) e.key.replaceAll(r'\', '/'): e.value,
  };
  final stale = <String>[];
  for (final path in scheduleRowAllowlist.keys) {
    final content = normalized[path];
    // Absent file → not stale; it may simply not exist yet (the shared builder
    // is created by Unit 2). Only a PRESENT file that no longer matches counts.
    if (content == null) continue;
    if (!constructsScheduleRow(content)) stale.add(path);
  }
  stale.sort();
  return stale;
}
