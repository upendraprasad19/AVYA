// 2026-06-25 — pins the positional-ref guard in scripts/blast_radius_from_diff.dart.
//
// The Unit-C blast-radius miss: `blast_radius_from_diff.dart <baseSHA> <headSHA>`
// (positional 2-ref form) treats args as FILE PATHS, so two commit SHAs matched
// no glob and BOTH fell to default_tier (feature) — masking a real account-tier
// range, which let an account-tier branch merge to main without the §4.12
// plan-review record. The CI keystone gate (which classifies via the stdin
// file-list mode) correctly saw `account` and failed. Guard: positional args
// that resolve to git commits now FAIL LOUD with the correct stdin-range usage
// instead of silently returning `feature`.
//
// Source-grep over the COMMENT-STRIPPED script so the explanatory header (which
// names the same tokens in prose) can't false-pass — the asserted strings must
// live in real CODE. Per feedback_source_grep_strip_comments_first.md. Behaviour
// was verified manually (`... <sha> <sha>` → stderr + exit 2; stdin range →
// account); recorded in docs/diagnoses/2026-06-23-e2e-cosmetics-copy-e5c1a2.md.
//
// Run: flutter test test/contracts/blast_radius_positional_ref_guard_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File('scripts/blast_radius_from_diff.dart');
    expect(f.existsSync(), isTrue,
        reason: 'scripts/blast_radius_from_diff.dart must exist');
    src = _stripDartComments(f.readAsStringSync());
  });

  test('probes each positional arg with git rev-parse to detect commit refs', () {
    expect(src.contains("'rev-parse'"), isTrue,
        reason: 'must probe positional args with git rev-parse');
    expect(src.contains(r"'$a^{commit}'"), isTrue,
        reason: 'must resolve each arg as a commit-ish ref');
  });

  test('fails loud (non-zero exit) with the correct stdin-range usage', () {
    expect(src.contains('FILE PATHS, not git refs'), isTrue,
        reason: 'must tell the operator positional args are paths, not refs');
    expect(src.contains('git diff --name-only <base> <head> | dart run'), isTrue,
        reason: 'must show the correct stdin-range invocation');
    expect(src.contains('exit(2)'), isTrue,
        reason: 'must exit non-zero on the misuse, not silently return feature');
  });
}

/// Strips `/* */` blocks then `// ...` line comments so assertions match real
/// CODE, not the explanatory header.
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}
