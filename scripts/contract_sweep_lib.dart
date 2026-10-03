// scripts/contract_sweep_lib.dart
//
// Pure selection logic for scripts/contract_sweep.dart (OI-220). Three unioned
// arms pick the contract tests a push range can have broken:
//   (a) registry  — a changed path is a `file:` of a concept in
//                   docs/sot_registry.yaml → its behavioral_test_path(s)
//   (b) content   — `git grep -l -F <key> -- test/` for each changed file's
//                   basename (parent/basename for ubiquitous names)
//   (c) changed   — test/**_test.dart files in the range themselves
// Any arm whose INPUT is unreadable makes the whole selection fall back to
// the full test/contracts/ subset: uncertainty must never look like a clean
// sweep (feedback_green_check_input_set_width #47).

const ubiquitousBasenames = <String>{'index.ts', 'index.dart', 'main.dart', 'mod.ts', 'pubspec.yaml'};

bool isDartTest(String p) => p.startsWith('test/') && p.endsWith('_test.dart');
bool isGolden(String p) => p.startsWith('test/goldens/');
/// Doc-like = prose nobody tests by name: `.md`/`.txt` EXCEPT under docs/audit/
/// and docs/architecture/, whose .md files are data contracts with test readers
/// (open_issues.md → 10 tests, sync.md → 29, OPEN_INDEX.md → 5; measured
/// 2026-09-19). docs/*.yaml are never doc-like. Prose that happens to live in
/// those two dirs (hermes reports, oi*-plan.md — 56 of 61 docs/audit/*.md have
/// zero test readers) is STILL a key by design: it costs one `git grep` and
/// surfaces as `unmapped`, which is print-only — never a fallback, never a
/// failure. CLAUDE.md is doc-like not because tests ignore it (77 reference
/// it) but because keying on it over-selects a third of the tree, and it is
/// pinned platform so pre-push runs the full suite for it regardless.
const _contractDocDirs = <String>['docs/audit/', 'docs/architecture/'];
bool isDocLike(String p) =>
    (p.endsWith('.md') || p.endsWith('.txt')) && !_contractDocDirs.any(p.startsWith);

String basenameOf(String p) => p.substring(p.lastIndexOf('/') + 1);

String keyFor(String p) {
  final base = basenameOf(p);
  if (!ubiquitousBasenames.contains(base)) return base;
  final parts = p.split('/');
  return parts.length >= 2 ? '${parts[parts.length - 2]}/$base' : base;
}

/// Arm (b) keys: every changed file that is neither a dart test nor doc-like.
Set<String> contentReferenceKeys(Iterable<String> changedPaths) =>
    {for (final p in changedPaths) if (!isDartTest(p) && !isDocLike(p)) keyFor(p)};

final _conceptRe = RegExp(r'^  - concept:\s*(\S+)');
// 896 `- file: x` list items + 176 `- { file: x, line: N }` inline maps; 0 bare `file:` (2026-09-19).
final _fileRe = RegExp(r'(?:^|[\s{-])file:\s*([^\s,}]+)');
final _btpRe = RegExp(r'^\s+behavioral_test_path(?:_[a-z0-9_]+)?\s*:\s*(.*)$');

String stripTrailingComment(String v) => v.replaceFirst(RegExp(r'\s+#.*$'), '').trim();

/// Arm (a): block-walk, one block per `  - concept:` heading.
List<String> registryTestsFor(String registryYaml, Set<String> changedPaths) {
  final out = <String>[];
  var hit = false;
  var paths = <String>[];
  void flush() {
    if (hit) out.addAll(paths);
    hit = false;
    paths = <String>[];
  }
  for (final line in registryYaml.split('\n')) {
    if (_conceptRe.hasMatch(line)) {
      flush();
      continue;
    }
    final f = _fileRe.firstMatch(line);
    if (f != null && changedPaths.contains(f.group(1))) hit = true;
    final b = _btpRe.firstMatch(line);
    if (b != null) {
      final v = stripTrailingComment(b.group(1)!);
      if (v.isNotEmpty && v != '""' && v != "''") paths.add(v);
    }
  }
  flush();
  return out;
}

Set<String> changedTestFiles(Iterable<String> changedPaths) => changedPaths.where(isDartTest).toSet();

class SweepSelection {
  final List<String> tests;
  final List<String> skipped;         // non-dart cites + goldens (pre-push never runs goldens)
  final List<String> droppedMissing;  // selected but absent on disk (three-dot + a deleted test)
  final List<String> unmappedChanged; // changed files no arm could map to a test
  final String? fallbackReason;
  const SweepSelection({
    required this.tests,
    required this.skipped,
    required this.droppedMissing,
    required this.unmappedChanged,
    this.fallbackReason,
  });
  static const fallbackTarget = 'test/contracts/';
}

/// [grepResults]: key → matching test files; `null` = that grep FAILED (exit >= 2);
/// a key that is absent from the map was never grepped. Both fall back.
SweepSelection buildSelection({
  required List<String> changedPaths,
  required String? registryYaml,
  required Map<String, List<String>?> grepResults,
  required bool Function(String path) exists,
}) {
  SweepSelection fallback(String why) => SweepSelection(
      tests: const [SweepSelection.fallbackTarget], skipped: const [], droppedMissing: const [],
      unmappedChanged: const [], fallbackReason: why);
  if (registryYaml == null) return fallback('docs/sot_registry.yaml unreadable');
  final keys = contentReferenceKeys(changedPaths);
  for (final k in keys) {
    if (!grepResults.containsKey(k)) return fallback('git grep not run for key `$k`');
    if (grepResults[k] == null) return fallback('git grep failed for key `$k`');
  }
  final selected = <String>{}
    ..addAll(registryTestsFor(registryYaml, changedPaths.toSet()))
    ..addAll(changedTestFiles(changedPaths));
  final keyHit = <String, bool>{for (final k in keys) k: grepResults[k]!.isNotEmpty};
  for (final k in keys) {
    selected.addAll(grepResults[k]!);
  }
  final runnable = <String>[];
  final skipped = <String>[];
  final dropped = <String>[];
  for (final f in selected) {
    if (!isDartTest(f) || isGolden(f)) {
      skipped.add(f);
    } else if (!exists(f)) {
      dropped.add(f);
    } else {
      runnable.add(f);
    }
  }
  final unmapped = <String>[];
  for (final p in changedPaths) {
    if (isDartTest(p) || isDocLike(p)) continue;
    final registryHit = registryTestsFor(registryYaml, {p}).isNotEmpty;
    if (!registryHit && keyHit[keyFor(p)] != true) unmapped.add(p);
  }
  return SweepSelection(
    tests: runnable..sort(),
    skipped: skipped..sort(),
    droppedMissing: dropped..sort(),
    unmappedChanged: unmapped..sort(),
  );
}
