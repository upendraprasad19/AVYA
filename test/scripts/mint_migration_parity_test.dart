// test/scripts/mint_migration_parity_test.dart
//
// scripts/mint_migration.sh carries a COPY of scripts/mint_oi.sh's transport core (bounded,
// sync_refs, owner_repo, cas_write, delete_reservation) with `oi/` -> `mig/`. Extracting a shared
// helper would have meant editing a heavily-tested, load-bearing script for a one-off saving, so
// the duplication is accepted (plan D5) — and pinned HERE, so a fix to the compare-and-swap in one
// script cannot silently miss the other.
//
// Normalisation is ANCHORED (`oi/`, `MINT_OI_`, `OI-`), never a bare `oi`->`mig` replace, which
// would corrupt any token that merely contains "oi". `do_prune`, `next_free` and the readers are
// deliberately NOT compared: the OI script reads boards, this one reads a directory listing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _shared = ['bounded', 'sync_refs', 'owner_repo', 'cas_write', 'delete_reservation'];

/// The text of shell function [name]: from `name() {` to the first `}` at column 0.
String? _extract(String src, String name) {
  final m = RegExp('^$name\\(\\) \\{[^\\n]*\\n.*?^\\}\\n', dotAll: true, multiLine: true).firstMatch(src);
  return m?.group(0);
}

String _normaliseOi(String s) =>
    s.replaceAll('oi/', 'mig/').replaceAll('MINT_OI_', 'MINT_MIG_').replaceAll('OI-', 'MIG-');

void main() {
  final oi = File('scripts/mint_oi.sh').readAsStringSync();
  final mig = File('scripts/mint_migration.sh').readAsStringSync();

  for (final fn in _shared) {
    test('$fn is identical in both scripts after anchored oi->mig normalisation', () {
      final a = _extract(oi, fn);
      final b = _extract(mig, fn);
      expect(a, isNotNull, reason: '$fn missing from mint_oi.sh — did it get renamed?');
      expect(b, isNotNull, reason: '$fn missing from mint_migration.sh');
      expect(b, _normaliseOi(a!),
          reason: '$fn drifted between mint_oi.sh and mint_migration.sh — a fix to the compare-and-swap '
              'must be made in BOTH');
    });
  }

  test('the extractor is not vacuous: every shared function is non-trivial and the CAS core is present', () {
    for (final fn in _shared) {
      expect((_extract(mig, fn) ?? '').split('\n').length, greaterThan(3), reason: fn);
    }
    expect(_extract(mig, 'cas_write'), contains('--force-with-lease="refs/heads/mig/\$1:"'));
    expect(_extract(mig, 'cas_write'), contains('already exists'));
  });

  test('no OI-specific env var or ref namespace leaked into the copy', () {
    expect(mig.contains('MINT_OI_'), isFalse);
    expect(RegExp(r'refs/heads/oi/').hasMatch(mig), isFalse);
    expect(RegExp(r'refs/remotes/[^\s"]*/oi/').hasMatch(mig), isFalse);
  });
}
