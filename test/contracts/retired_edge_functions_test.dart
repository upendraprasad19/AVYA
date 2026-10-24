// Regression test for retired root §19 entry #56 (Class B, 2026-05-18
// declutter Milestone 4) — this test is the entry's surviving record.
//
// Pins the rule: `ai-proxy-pro` Edge Function was retired 2026-04-18
// (merged into `ai-proxy` with server-side isPro gate; returns 410 Gone in
// production). Client code under `lib/` must not invoke it via
// `Supabase.instance.client.functions.invoke('ai-proxy-pro')` or
// `SupabaseService.callFunction('ai-proxy-pro')`.
//
// Scope note (2026-05-18 decluttering): The original §19 entry also forbade
// `video-status`. That part of the rule was conditional ("if the video
// feature ever un-defers, rewrite first"). Commit `5c40925` un-deferred the
// video-share feature and added a `video-status` callsite at
// `lib/features/train/providers/video_render_provider.dart:103-107`. The
// `video-status` half of the §19 entry is therefore stale; only the
// `ai-proxy-pro` invariant remains durable. Re-deploying the video-status
// function with proper JWT + user_id filter validation is tracked
// separately (out of scope here).
//
// Source-grep contract — strips comments first per
// feedback_source_grep_strip_comments_first.md. Migration comments in
// `app_constants.dart`, `ai_service.dart`, `ai_coach_screen.dart` quote the
// retired name; un-stripped grep would false-positive.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip Dart line + block comments before source-grep.
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('§19 #56 — no callsites to retired ai-proxy-pro Edge Function', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue,
        reason: 'lib/ must exist for this test to run.');

    // Source-grep targets the .invoke('ai-proxy-pro') / callFunction('ai-proxy-pro')
    // shape; both yield the same quoted literal in stripped source.
    const forbiddenPatterns = <String>[
      "'ai-proxy-pro'",
      '"ai-proxy-pro"',
    ];

    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      final stripped = _stripComments(src);
      for (final pattern in forbiddenPatterns) {
        if (stripped.contains(pattern)) {
          offenders.add('${entity.path}: contains $pattern outside comments');
        }
      }
    }

    expect(offenders, isEmpty,
        reason:
            'Callsite to retired Edge Function `ai-proxy-pro` found in lib/. '
            'It was merged into `ai-proxy` 2026-04-18 with a server-side isPro '
            'gate and returns 410 Gone. Route through `ai-proxy` instead.\n\n'
            'Offenders:\n  ${offenders.join("\n  ")}');
  });
}
