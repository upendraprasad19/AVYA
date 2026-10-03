// scripts/gemini_retry_coverage_lib.dart
//
// Pure logic for check_gemini_retry_and_telemetry_coverage.dart (A5/OI-226,
// f7a2c9, 2026-09-21). No filesystem, no process spawning — the runner reads
// real files and passes them here as {path: contents} maps so tests can pass
// fixture maps instead.
//
// Part (a): every `geminiChat({` call site in supabase/functions/ must pass
// a `retries:` argument inside its own balanced options object.
// `geminiChatWithTools(` is a DIFFERENT function (its own TOOLS_MAX_PASSES
// bounded-pass resilience, no `retries` parameter) and is deliberately
// excluded.
//
// Part (b): every registered AI/network entry-point method (see
// [aiNetworkEntryPoints] below) must telemeter its own catch block via
// ErrorTelemetry. The registry is EXPLICIT, not auto-derived from a text
// heuristic — confirmed by grep before choosing this design that
// ai_coach_provider.dart's send/sendWithMedia never reference
// AppConstants.aiProxyFunction directly (the real network call lives behind
// AiService, a different file), so no "does this catch wrap a network call"
// text heuristic reliably covers exactly the methods A5/OI-226 was about.
// Same trust model as derive_only_tool_surface_test.dart's tool registry: a
// NEW AI-calling method needs a NEW entry here, caught by review.

/// Strip block comments (`/* … */`) and line comments (`// …`) from [s].
/// Applied to an already-EXTRACTED block/catch-body before a `.contains()`
/// check — never to the raw source used for brace-matching or line-number
/// computation, so a comment mentioning `retries:` or `ErrorTelemetry.` (to
/// explain why it was removed, or as leftover commented-out code) can't
/// satisfy a check whose whole point is confirming the REAL call is still
/// there. Added by the self-triggered B-pass review on this batch's own
/// staged diff (2026-09-21) — the gate's first version did the raw,
/// comment-blind `.contains()` this helper now guards against; the same
/// batch's `alert_cron_failures_sync_test.dart` independently hit the
/// sibling trap (a migration's explanatory comment about NOT using
/// `resolved_at` satisfied a naive `sql.contains('resolved_at')` check for
/// its absence), which is exactly the class this file's own doc comment
/// above warns readers about but had not, until now, applied to itself.
String stripComments(String s) {
  s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
  s = s.replaceAll(RegExp(r'//[^\n]*'), ' ');
  return s;
}

/// Extracts the substring from [openBraceIndex] (which MUST point at a `{`)
/// to its matching closing `}`, inclusive. Returns null if unbalanced or the
/// index doesn't point at an opening brace.
String? extractBalancedBraces(String src, int openBraceIndex) {
  if (openBraceIndex < 0 ||
      openBraceIndex >= src.length ||
      src[openBraceIndex] != '{') {
    return null;
  }
  var depth = 0;
  for (var i = openBraceIndex; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(openBraceIndex, i + 1);
    }
  }
  return null;
}

/// 1-indexed line number of [charIndex] within [src].
int lineOf(String src, int charIndex) =>
    '\n'.allMatches(src.substring(0, charIndex)).length + 1;

/// Part (a). Returns one violation string per `geminiChat({` call site whose
/// balanced options object lacks `retries:`.
List<String> findGeminiChatMissingRetries(Map<String, String> filesByPath) {
  final violations = <String>[];
  for (final entry in filesByPath.entries) {
    final path = entry.key;
    final src = entry.value;
    var from = 0;
    while (true) {
      final idx = src.indexOf('geminiChat({', from);
      if (idx < 0) break;
      final openBrace = idx + 'geminiChat('.length;
      final block = extractBalancedBraces(src, openBrace);
      if (block == null) {
        violations.add(
            '$path:${lineOf(src, idx)} — geminiChat( call has unbalanced '
            'braces, cannot verify retries:');
      } else if (!stripComments(block).contains('retries:')) {
        violations.add('$path:${lineOf(src, idx)} — geminiChat( call '
            'missing a retries: argument');
      }
      from = idx + 1;
    }
  }
  return violations;
}

/// A known AI/network entry-point method: the file it lives in, a literal
/// anchor unique to its signature, and a human label for violation messages.
class AiEntryPoint {
  const AiEntryPoint(this.file, this.methodAnchor, this.label);
  final String file;
  final String methodAnchor;
  final String label;
}

const aiNetworkEntryPoints = <AiEntryPoint>[
  AiEntryPoint('lib/features/ai_coach/providers/ai_coach_provider.dart',
      'Future<void> send(', 'SendMessageNotifier.send'),
  AiEntryPoint('lib/features/ai_coach/providers/ai_coach_provider.dart',
      'Future<void> sendWithMedia(', 'SendMessageNotifier.sendWithMedia'),
  AiEntryPoint('lib/features/nutrition/providers/nutrition_provider.dart',
      'Future<void> analyse(String text)', 'AiBreakdownNotifier.analyse'),
  AiEntryPoint('lib/features/nutrition/providers/nutrition_provider.dart',
      'Future<void> scanImage(', 'ScanMealNotifier.scanImage'),
  AiEntryPoint('lib/features/nutrition/providers/nutrition_provider.dart',
      'Future<void> analyseCart(', 'CartAuditorNotifier.analyseCart'),
];

const _telemetryMarkers = [
  'ErrorTelemetry.recordNonFatal(',
  'ErrorTelemetry.logEvent(',
];

/// Generous enough to reach the real outer catch in the longest registered
/// method (send(): 6610 chars anchor-to-telemetry, measured directly against
/// the real file) with comfortable margin, while staying far short of the
/// distance to an unrelated NEXT method in the same file.
const _methodSearchWindowChars = 8000;

/// Part (b). Returns one violation string per registered [AiEntryPoint]
/// whose method anchor is missing, whose file is missing, whose method has
/// no `catch (` at all within the search window, or where NONE of the
/// catch blocks found in that window contain an ErrorTelemetry call.
///
/// Checks "ANY catch in the window", not "the first" or "the last" — these
/// methods commonly nest a deliberately-silent inner catch (e.g. a
/// best-effort `verifyFromServer()` refresh wrapped in `catch (_) {}`)
/// BEFORE the outer catch that actually shows the user an error and
/// telemeters. Measured directly against the real files: send()'s
/// telemetry-bearing catch is its SECOND of three (913/976/1044, telemetry
/// at 976); analyse()'s is its SECOND of two (717/784, telemetry at 784).
/// Neither "first catch" nor "last catch" would have found the right one in
/// both cases at once, which is why this checks the whole window instead of
/// picking one catch to inspect.
///
/// [filesByPath] is keyed by the SAME literal path each [AiEntryPoint.file]
/// uses — the registry IS the file scope, not a recursive directory walk.
List<String> findAiEntryPointsMissingTelemetry(
    Map<String, String> filesByPath) {
  final violations = <String>[];
  for (final entryPoint in aiNetworkEntryPoints) {
    final src = filesByPath[entryPoint.file];
    if (src == null) {
      violations.add('${entryPoint.file} — registered ("${entryPoint.label}"'
          ') but file not found; renamed/moved without updating the '
          'registry in gemini_retry_coverage_lib.dart?');
      continue;
    }
    final methodIdx = src.indexOf(entryPoint.methodAnchor);
    if (methodIdx < 0) {
      violations.add('${entryPoint.file} — registered method anchor for '
          '"${entryPoint.label}" not found; renamed without updating the '
          'registry?');
      continue;
    }
    final windowEnd =
        (methodIdx + _methodSearchWindowChars).clamp(0, src.length);

    var anyCatchFound = false;
    var anyTelemetryFound = false;
    var searchFrom = methodIdx;
    while (true) {
      final catchIdx = src.indexOf('catch (', searchFrom);
      if (catchIdx < 0 || catchIdx >= windowEnd) break;
      anyCatchFound = true;
      final catchBraceIdx = src.indexOf('{', catchIdx);
      final catchBody = extractBalancedBraces(src, catchBraceIdx);
      final strippedCatchBody =
          catchBody == null ? null : stripComments(catchBody);
      if (strippedCatchBody != null &&
          _telemetryMarkers.any(strippedCatchBody.contains)) {
        anyTelemetryFound = true;
        break;
      }
      searchFrom = catchIdx + 1;
    }

    if (!anyCatchFound) {
      violations.add('${entryPoint.file}:${lineOf(src, methodIdx)} — '
          '"${entryPoint.label}" has no catch block within '
          '$_methodSearchWindowChars chars of its signature');
    } else if (!anyTelemetryFound) {
      violations.add('${entryPoint.file}:${lineOf(src, methodIdx)} — '
          '"${entryPoint.label}" has catch block(s) but none contain an '
          'ErrorTelemetry call');
    }
  }
  return violations;
}
