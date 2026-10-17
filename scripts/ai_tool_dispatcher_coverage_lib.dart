// scripts/ai_tool_dispatcher_coverage_lib.dart
//
// Pure logic for scripts/check_ai_tool_dispatcher_coverage.dart. Extracted
// (day-swapper-sync-load batch, Task 27, spec §5.8) so the NEW
// capability-coverage check can be mutation-proven per CLAUDE.md §4.4 rule
// 24 without a filesystem-backed e2e test. No I/O in this file.

class ToolInfo {
  final String file;
  final String name;
  final String kind;
  final String? intentType;
  final String? requiresCapability;
  const ToolInfo({
    required this.file,
    required this.name,
    required this.kind,
    required this.intentType,
    required this.requiresCapability,
  });
}

/// Parses `{name, kind, intentType, requiresCapability}` out of each tool
/// FILE's source (already comment-agnostic — the same regexes the original
/// gate used). [filesByRelPath] maps a repo-relative path to its raw source.
List<ToolInfo> parseTools(Map<String, String> filesByRelPath) {
  final out = <ToolInfo>[];
  for (final entry in filesByRelPath.entries) {
    final rel = entry.key;
    final content = entry.value;
    final nameMatch = RegExp(r'name:\s*"([^"]+)"').firstMatch(content);
    final kindMatch = RegExp(r'kind:\s*"([^"]+)"').firstMatch(content);
    if (nameMatch == null || kindMatch == null) continue;
    // intent type — look inside `intentBuilder` for `type: "<...>"`.
    final intentMatch =
        RegExp(r'intentBuilder[\s\S]*?type:\s*"([^"]+)"').firstMatch(content);
    final capMatch =
        RegExp(r'requiresCapability:\s*"([^"]+)"').firstMatch(content);
    out.add(ToolInfo(
      file: rel,
      name: nameMatch.group(1)!,
      kind: kindMatch.group(1)!,
      intentType: intentMatch?.group(1),
      requiresCapability: capMatch?.group(1),
    ));
  }
  return out;
}

class CoverageResult {
  /// Write tool has an intent_type, but no matching `case` in the dispatcher.
  final List<String> missingDispatcherCases;
  /// Write tool has no intent_type at all (WARN, not a hard failure — mirrors
  /// the pre-extraction gate's behaviour).
  final List<String> unusedWriteTools;
  /// Tool declares `requiresCapability` but the client const doesn't list it
  /// (spec §5.8 — "its capability must be in the client const").
  final List<String> uncoveredCapabilities;

  const CoverageResult({
    required this.missingDispatcherCases,
    required this.unusedWriteTools,
    required this.uncoveredCapabilities,
  });

  bool get isViolation =>
      missingDispatcherCases.isNotEmpty || uncoveredCapabilities.isNotEmpty;
}

CoverageResult checkCoverage({
  required List<ToolInfo> tools,
  required String dispatcherSrc,
  required Set<String> clientCapabilities,
}) {
  final missing = <String>[];
  final unused = <String>[];
  final uncoveredCaps = <String>[];
  for (final t in tools) {
    if (t.kind != 'write') continue;
    if (t.intentType == null) {
      unused.add('${t.file} — write tool `${t.name}` has no intent_type');
      continue;
    }
    final pattern = "case '${t.intentType}':";
    if (!dispatcherSrc.contains(pattern)) {
      missing.add('${t.file} — write tool `${t.name}` intent=`${t.intentType}` '
          'has no `$pattern` in tool_dispatcher.dart');
    }
    if (t.requiresCapability != null &&
        !clientCapabilities.contains(t.requiresCapability)) {
      uncoveredCaps.add('${t.file} — write tool `${t.name}` requires capability '
          '`${t.requiresCapability}` which kCoachClientCapabilities does not declare');
    }
  }
  return CoverageResult(
    missingDispatcherCases: missing,
    unusedWriteTools: unused,
    uncoveredCapabilities: uncoveredCaps,
  );
}
