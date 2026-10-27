// Regression contract for APK +34 / obs 4 (diagnose b1f3a7): the Profile
// avatar/banner image URL must be VERSIONED at upload time and passed through
// VERBATIM on read — never mutated per-build with a fresh timestamp (the old
// `_ProfileScreenState._addCacheBuster`), which defeated CachedNetworkImage's
// disk cache and forced a network refetch on every navigation to Profile.
//
// Two layers:
//   1. Behavioral spec for ProfileImageUrl (forDisplay stable, versioned busts).
//   2. Comment-stripped source-grep that the read path uses
//      ProfileImageUrl.forDisplay (no _addCacheBuster / no per-build token) and
//      the upload path versions the stored URL. Source-grep is presence-only;
//      the behavioral group is the semantic pin (feedback_source_grep_false_confidence).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/utils/profile_image_url.dart';

/// Strip /* */ and // comments. Uses a colon-lookbehind so it never eats the
/// `//` inside `https://` (feedback_mistake_remote_dep_rot / strip-comments-first).
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
  group('ProfileImageUrl.forDisplay — read path is verbatim + stable', () {
    test('returns the stored URL unchanged', () {
      const url = 'https://cdn.example.com/u/123/avatar.jpg?v=42';
      expect(ProfileImageUrl.forDisplay(url), url);
    });

    test('is STABLE across repeated calls (no per-build mutation)', () {
      const url = 'https://cdn.example.com/u/123/avatar.jpg';
      final a = ProfileImageUrl.forDisplay(url);
      final b = ProfileImageUrl.forDisplay(url);
      expect(a, b, reason: 'two reads of the same stored URL must be identical');
    });

    test('null / empty → null', () {
      expect(ProfileImageUrl.forDisplay(null), isNull);
      expect(ProfileImageUrl.forDisplay(''), isNull);
    });
  });

  group('ProfileImageUrl.versioned — upload path busts only on change', () {
    test('stamps v= and is deterministic for a given version', () {
      const base = 'https://cdn.example.com/u/123/avatar.jpg';
      final v1 = ProfileImageUrl.versioned(base, version: 100);
      expect(Uri.parse(v1).queryParameters['v'], '100');
      expect(ProfileImageUrl.versioned(base, version: 100), v1,
          reason: 'same version → identical URL (cache hit)');
    });

    test('different versions → different URLs (one-time fresh fetch)', () {
      const base = 'https://cdn.example.com/u/123/avatar.jpg';
      expect(ProfileImageUrl.versioned(base, version: 100),
          isNot(ProfileImageUrl.versioned(base, version: 200)));
    });

    test('idempotent — strips any prior v / legacy t before re-stamping', () {
      final once = ProfileImageUrl.versioned(
          'https://cdn.example.com/u/123/avatar.jpg?t=5', version: 100);
      final twice = ProfileImageUrl.versioned(once, version: 200);
      final q = Uri.parse(twice).queryParameters;
      expect(q['v'], '200');
      expect(q.containsKey('t'), isFalse,
          reason: 'legacy read-path ?t= must be dropped');
      // Exactly one v= in the final string.
      expect('v='.allMatches(twice).length, 1);
    });
  });

  group('source-grep: profile image read path no longer self-busts', () {
    test('profile_content uses ProfileImageUrl.forDisplay, not _addCacheBuster',
        () {
      final src = _strip(File(
              'lib/features/profile/screens/profile/profile_content.dart')
          .readAsStringSync());
      expect(src.contains('ProfileImageUrl.forDisplay'), isTrue,
          reason: 'read path must pass the stored URL through verbatim');
      expect(src.contains('_addCacheBuster'), isFalse,
          reason: 'the per-build cache-buster must be gone from the read path');
    });

    test('screen.dart no longer defines a per-build cache-buster', () {
      final src = _strip(
          File('lib/features/profile/screens/profile/screen.dart')
              .readAsStringSync());
      expect(src.contains('_addCacheBuster'), isFalse);
    });

    test('upload path versions the stored URL (avatar + banner)', () {
      final src = _strip(
          File('lib/features/profile/providers/profile_provider.dart')
              .readAsStringSync());
      expect('ProfileImageUrl.versioned'.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: 'both uploadAvatar and uploadBanner must version the URL');
    });
  });
}
