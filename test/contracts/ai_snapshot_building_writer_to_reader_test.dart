import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `ai_snapshot_building`
/// from docs/sot_registry.yaml.
///
/// Writer: AiCoachRepository.buildAiContext
/// Reader: AiService._compactContext
///
/// buildAiContext is the ONE snapshot builder. _compactContext is the ONE
/// trimmer. Never construct ad-hoc snapshots in provider code.
/// Forbidden: istDateStr(istNow()) — double-shifts +5:30.
void main() {
  late String repoSrc;
  late String aiSvcSrc;

  setUpAll(() {
    final rf = File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(rf.existsSync(), isTrue,
        reason: 'ai_coach_repository.dart must exist (writer for ai_snapshot_building)');
    repoSrc = rf.readAsStringSync();

    final af = File('lib/core/services/ai_service.dart');
    expect(af.existsSync(), isTrue,
        reason: 'ai_service.dart must exist (reader _compactContext)');
    aiSvcSrc = af.readAsStringSync();
  });

  group('ai_snapshot_building writer↔reader source contract', () {
    test('writer buildAiContext exists in ai_coach_repository', () {
      expect(repoSrc.contains('buildAiContext'), isTrue,
          reason:
              'ai_coach_repository must define buildAiContext — the ONE snapshot builder per sot_registry');
    });

    test('reader _compactContext exists in ai_service', () {
      expect(aiSvcSrc.contains('_compactContext'), isTrue,
          reason:
              'ai_service must define _compactContext — the ONE snapshot trimmer per sot_registry');
    });

    test('_compactContext has trim target under 9500 bytes', () {
      expect(aiSvcSrc.contains('9500') || aiSvcSrc.contains('9_500'), isTrue,
          reason:
              '_compactContext must enforce <9500 bytes target to stay under 10KB server limit');
    });

    test('snapshot includes coaching_notes key', () {
      // coaching_notes is a required field in the snapshot
      expect(repoSrc.contains("'coaching_notes'"), isTrue,
          reason:
              'buildAiContext must include coaching_notes in the snapshot for AI context');
    });

    test('forbidden: istDateStr(istNow()) double-shift pattern absent in non-comment code', () {
      // The double-shift pattern causes +10:30 UTC offset — IST midnight boundary
      // affected ai_coach_repository in Test #11.1 / #12.5.
      // Strip single-line comments before checking so a comment explaining
      // WHY not to use it doesn't trigger a false positive.
      final stripComments = RegExp(r'//[^\n]*');
      final repoNoComments = repoSrc.replaceAll(stripComments, '');
      final aiSvcNoComments = aiSvcSrc.replaceAll(stripComments, '');

      final doubleShift = RegExp(r'istDateStr\s*\(\s*istNow\s*\(');
      expect(doubleShift.hasMatch(repoNoComments), isFalse,
          reason:
              'ai_coach_repository must not call istDateStr(istNow()) — this double-shifts +5:30; '
              'use istDateStr(DateTime.now()) instead');
      expect(doubleShift.hasMatch(aiSvcNoComments), isFalse,
          reason:
              'ai_service must not call istDateStr(istNow()) — double-shift bug (Test #11.1 fix)');
    });

    test('no ad-hoc snapshot construction in provider code', () {
      // Providers must NOT build their own context maps — only buildAiContext
      final providerFile =
          File('lib/features/ai_coach/providers/ai_coach_provider.dart');
      if (!providerFile.existsSync()) return;
      final src = providerFile.readAsStringSync();
      // Should reference buildAiContext, not construct its own 'snapshot' map
      expect(src.contains('buildAiContext'), isTrue,
          reason:
              'ai_coach_provider must call buildAiContext (not build an ad-hoc snapshot)');
    });
  });
}
