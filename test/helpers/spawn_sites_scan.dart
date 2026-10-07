// test/helpers/spawn_sites_scan.dart
//
// The pure scans behind test/contracts/spawn_sites_guard_test.dart (PR 2 of batch
// spawn-tests-env-and-stderr). They read SOURCE TEXT only and spawn nothing, so the guard
// cannot trip its own G1. Every scan runs on `blankDart` output (comments and string
// contents blanked, positions preserved) plus, for G1 and G2, the BODIES of `${...}`
// interpolations, which `blankDart` does not follow.

import 'spawn_env_scan.dart';

/// The visible marker a synthetic fixture line carries inside the guard test (the repo's
/// `deu-quote` idiom). It is honoured ONLY in the guard's own file.
const String spawnGuardQuoteMarker = 'spawn-guard-quote';

final RegExp _rawSpawn = RegExp(r'\bProcess\s*\.\s*(runSync|run|start)\s*\(');
final RegExp _aliasRef = RegExp(r'\bProcess\s*\.\s*(runSync|run|start)\b(?!\s*\()');
final RegExp _startMode = RegExp(r'\bProcessStartMode\b');
final RegExp _wholeMap = RegExp(r'\bPlatform\s*\.\s*environment\b(?!\s*\[)');
final RegExp _helperCall = RegExp(r'\b(?:runSpawn|runSpawnAsync|runSpawnWithInput|startSpawn|hermeticEnvironment)\s*\(');
final RegExp _helperImport = RegExp(r'''import\s+['"][^'"]*helpers/spawn\.dart['"]''');
final RegExp _startCall = RegExp(r'\bstartSpawn\s*\(');
final RegExp _reportCall = RegExp(r'\breportSpawn\s*\(');
final RegExp _whichDart = RegExp(r'''['"](?:which|where)['"][^;]{0,200}['"]dart['"]''');
final RegExp _commandVDart = RegExp(r'command\s+-v\s+dart\b');
final RegExp _resolvedExe = RegExp(r'\bPlatform\s*\.\s*resolvedExecutable\b');

/// The text of every `${ ... }` interpolation body in [commentStripped] (the strings-kept
/// view), brace-matched, joined with newlines.
String interpolationBodies(String commentStripped) {
  final out = StringBuffer();
  var from = 0;
  while (true) {
    final at = commentStripped.indexOf(r'${', from);
    if (at < 0) break;
    var depth = 1;
    var i = at + 2;
    while (i < commentStripped.length && depth > 0) {
      final c = commentStripped[i];
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      }
      i++;
    }
    out.writeln(commentStripped.substring(at + 2, depth == 0 ? i - 1 : i));
    from = at + 2;
  }
  return out.toString();
}

/// What the guard learns about one file.
class SpawnFileScan {
  SpawnFileScan({
    required this.rawSpawns,
    required this.aliasRefs,
    required this.startModeUses,
    required this.wholeMapReads,
    required this.usesHelper,
    required this.starts,
    required this.reports,
    required this.unmatchedStarts,
    required this.whichDart,
    required this.resolvedExecutable,
    required this.markerLines,
  });
  final int rawSpawns;
  final int aliasRefs;
  final int startModeUses;
  final int wholeMapReads;
  final bool usesHelper;
  final int starts;
  final int reports;
  final int unmatchedStarts;
  final int whichDart;
  final int resolvedExecutable;
  final int markerLines;
}

/// Starts with no later UNMATCHED report, matching each start in order to a distinct later
/// report (a plain count passes two starts with one report counted twice, and a report that
/// precedes its start).
int unmatchedStartCount(List<int> startPositions, List<int> reportPositions) {
  final used = <int>{};
  var unmatched = 0;
  for (final s in startPositions) {
    var matched = false;
    for (var k = 0; k < reportPositions.length; k++) {
      if (!used.contains(k) && reportPositions[k] > s) {
        used.add(k);
        matched = true;
        break;
      }
    }
    if (!matched) unmatched++;
  }
  return unmatched;
}

/// Scans [source]. When [isGuardFile] is true, lines carrying [spawnGuardQuoteMarker] are
/// removed first (the marker is honoured nowhere else; elsewhere it is only counted).
SpawnFileScan scanSpawnSource(String source, {bool isGuardFile = false}) {
  final markerLines = source.split('\n').where((l) => l.contains(spawnGuardQuoteMarker)).length;
  final text = isGuardFile
      ? source.split('\n').map((l) => l.contains(spawnGuardQuoteMarker) ? '' : l).join('\n')
      : source;
  final blank = blankDart(text);
  final keep = blankDart(text, blankStrings: false);
  final bodies = interpolationBodies(keep);
  final bodiesBlank = blankDart(bodies);
  int count(RegExp re) => re.allMatches(blank).length + re.allMatches(bodiesBlank).length;
  final startPos = _startCall.allMatches(blank).map((m) => m.start).toList();
  final reportPos = _reportCall.allMatches(blank).map((m) => m.start).toList();
  return SpawnFileScan(
    rawSpawns: count(_rawSpawn),
    aliasRefs: _aliasRef.allMatches(blank).length,
    startModeUses: _startMode.allMatches(blank).length,
    wholeMapReads: count(_wholeMap),
    usesHelper: _helperImport.hasMatch(keep) || _helperCall.hasMatch(blank),
    starts: startPos.length,
    reports: reportPos.length,
    unmatchedStarts: unmatchedStartCount(startPos, reportPos),
    whichDart: _whichDart.allMatches(keep).length + _commandVDart.allMatches(keep).length,
    resolvedExecutable: _resolvedExe.allMatches(blank).length,
    markerLines: markerLines,
  );
}
