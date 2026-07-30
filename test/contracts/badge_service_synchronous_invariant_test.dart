// OI-45 finding 3 / Unit 3a (progress-map-consolidation, 2026-07-30) —
// source-grep tripwire (comment-stripped so a describing comment can't
// satisfy the assertion, per feedback_source_grep_strip_comments_first.md).
//
// BadgeService.checkAndUnlock / checkAll were investigated and confirmed
// NOT racing today: both bodies are fully synchronous (no `await` between
// the badges-map read and its write), so under Dart's single-threaded event
// loop nothing can interleave within one call. Downgraded from a claimed
// HIGH-severity race on that basis — see docs/diagnoses (Unit 3a).
//
// This is deliberately NOT given a mutex: adding lock machinery for a race
// that cannot occur today would be unjustified complexity (CLAUDE.md: don't
// add guards for scenarios that can't happen). Instead, this test pins the
// INVARIANT the safety argument depends on — neither method may become
// `async` — so a future edit that adds an `await` (reopening a genuine,
// unguarded read-modify-write race) fails a test instead of silently
// shipping.
//
// Run: flutter test test/contracts/badge_service_synchronous_invariant_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  group('OI-45 finding 3 — BadgeService stays synchronous (no mutex needed)',
      () {
    final source =
        _strip(File('lib/core/services/badge_service.dart').readAsStringSync());

    test('checkAndUnlock is not declared async', () {
      // Matches the signature up to its opening brace — Dart requires the
      // `async` keyword to sit right there for a body to use `await` at
      // all, so checking its absence at the signature is a complete,
      // robust proxy for "this method cannot contain an await" (no need to
      // balance-match the body itself, which has nested blocks).
      final sig = RegExp(
        r'List<BadgeId>\s+checkAndUnlock\s*\(\s*\{[\s\S]*?\}\s*\)\s*(async\s*)?\{',
      ).firstMatch(source);
      expect(sig, isNotNull,
          reason: 'checkAndUnlock signature shape changed — update this regex '
              'before trusting its result either way');
      expect(sig!.group(1), isNull,
          reason: 'checkAndUnlock must stay synchronous — OI-45 finding 3: '
              'there is no lock around its read-modify-write of the badges '
              'map, safe ONLY because nothing can interleave within one '
              'synchronous call. Marking it async (enabling await) reopens a '
              'genuine unguarded race — add a mutex FIRST if this is needed.');
    });

    test('checkAll is not declared async', () {
      final sig = RegExp(
        r'List<BadgeId>\s+checkAll\s*\(\s*\)\s*(async\s*)?\{',
      ).firstMatch(source);
      expect(sig, isNotNull,
          reason: 'checkAll signature shape changed — update this regex '
              'before trusting its result either way');
      expect(sig!.group(1), isNull,
          reason: 'checkAll must stay synchronous for the same reason as '
              'checkAndUnlock — it reads the progress/workout/health boxes '
              'then calls straight into checkAndUnlock with no await.');
    });

    test('neither method contains an await keyword in its source', () {
      // Belt-and-suspenders: even if a future edit added `async` to satisfy
      // some other tool without actually needing await yet, catch the
      // moment an await is actually introduced.
      //
      // Round-2 review P3: this used to scan only
      // source.substring(checkAndUnlockStart, checkAllStart) — everything
      // FROM checkAndUnlock's signature UP TO (not including) checkAll's
      // signature. Since checkAll is declared textually AFTER
      // checkAndUnlock in this file, that range covered checkAndUnlock's
      // own body plus the private helpers between the two methods, but
      // excluded checkAll's own body entirely — contradicting this test's
      // name. checkAll is the LAST method in the class, so scanning to the
      // end of the source captures both bodies (and everything already-
      // covered in between) with no risk of picking up an unrelated
      // method's legitimate await from further down the file.
      final checkAndUnlockStart = source.indexOf('checkAndUnlock(');
      final checkAllStart = source.indexOf('checkAll()');
      expect(checkAndUnlockStart, greaterThanOrEqualTo(0));
      expect(checkAllStart, greaterThanOrEqualTo(0));
      expect(checkAllStart, greaterThan(checkAndUnlockStart),
          reason: 'this test assumes checkAll is declared AFTER '
              'checkAndUnlock so scanning-to-end-of-source covers both '
              'bodies — method order changed, re-derive the scan range.');
      final combinedRegion = source.substring(checkAndUnlockStart);
      expect(combinedRegion.contains('await '), isFalse,
          reason: 'no await may appear in checkAndUnlock or checkAll — '
              'see the synchronous-invariant reasoning above.');
    });
  });
}
