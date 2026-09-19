/// Pure logic for check_sync_hash_skip_atomicity.dart (OI-204 gate-before-refactor,
/// CLAUDE.md §4.11). Verifies the atomicity invariant the OI-204 fingerprint-skip
/// design requires: a sync fingerprint may only be recorded as "confirmed pushed"
/// when every constituent network write for that key/slot succeeded. See
/// docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md §5.1/§5.2/§6.
library;

class HashSkipDomainSpec {
  final String flagName;
  final String indexAssignPrefix;
  final String fingerprintVarName;
  final int expectedSwallowCatches;

  const HashSkipDomainSpec({
    required this.flagName,
    required this.indexAssignPrefix,
    required this.fingerprintVarName,
    required this.expectedSwallowCatches,
  });
}

const exlogSpec = HashSkipDomainSpec(
  flagName: 'exlogBundleSynced',
  indexAssignPrefix: 'exlogHashIndex[',
  fingerprintVarName: 'fp',
  expectedSwallowCatches: 1,
);

const nlogSpec = HashSkipDomainSpec(
  flagName: 'nlogSlotSynced',
  indexAssignPrefix: 'nlogHashIndex[',
  fingerprintVarName: 'nlogFp',
  expectedSwallowCatches: 2,
);

/// Strips `//` line comments so a comment mentioning the flag/store cannot
/// satisfy the checks below. Not string-literal-aware — matches this repo's
/// existing comment-stripping gates (good enough for Dart source; a `//`
/// inside a string literal in these two files would be unusual and is an
/// accepted limitation, same as the other comment-stripping gates in this repo).
String stripLineComments(String source) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    final idx = line.indexOf('//');
    out.writeln(idx == -1 ? line : line.substring(0, idx));
  }
  return out.toString();
}

class AtomicityViolation {
  final String message;
  AtomicityViolation(this.message);
}

/// Returns null when the domain's mechanism doesn't exist YET in [source]
/// (vacuously fine — nothing to check before the flag is introduced) or is
/// fully correct. Returns a violation describing exactly what's wrong otherwise.
AtomicityViolation? checkDomainAtomicity(String source, HashSkipDomainSpec spec) {
  final stripped = stripLineComments(source);
  final declRe = RegExp('bool\\s+${spec.flagName}\\s*=\\s*true\\s*;');
  // OI-204 C1 (plan-review round 1): the store must be an ASSIGNMENT of the
  // confirmed fingerprint specifically — `<indexAssignPrefix>...] = <fpVar>;`
  // — not merely a line containing the index-variable substring. The real
  // code has TWO other lines that contain that bare substring and are NOT
  // stores: the preamble's index-hydration loop (`exlogHashIndex[k] = v;`,
  // an assignment too, but of the hydration value `v`, never the fingerprint
  // var) and the skip-check's read (`storedFingerprint: exlogHashIndex[key],`
  // — no `=` follows the `]` at all). Requiring the specific fingerprint
  // variable name as the assigned value excludes both by construction.
  final storeRe = RegExp(
      '${RegExp.escape(spec.indexAssignPrefix)}[^\\]]*\\]\\s*=\\s*${spec.fingerprintVarName}\\s*;');

  final hasDecl = declRe.hasMatch(stripped);
  final hasStore = storeRe.hasMatch(stripped);

  if (!hasDecl && !hasStore) return null;

  if (hasStore && !hasDecl) {
    return AtomicityViolation(
        '${spec.indexAssignPrefix} is written but ${spec.flagName} is never declared '
        'true — the store is unconditional, violating the atomicity requirement.');
  }
  if (hasDecl && !hasStore) {
    return AtomicityViolation(
        '${spec.flagName} is declared but ${spec.indexAssignPrefix} is never '
        'assigned from ${spec.fingerprintVarName} — the flag is dead.');
  }

  final lines = stripped.split('\n');
  // OI-204 B-pass Finding 1 (2026-09-19): `storeRe`'s `\s*` matches `\n`
  // (Dart's `\s` spans newlines regardless of any regex flag), so `hasStore`
  // above tolerates a store statement wrapped across two lines (e.g. by
  // `dart format` on a line past 80 columns) -- but re-running `storeRe`
  // against each SPLIT line in isolation, as this used to do, can never
  // match either half. That silently emptied `storeLineIdxs`, skipped the
  // guard-scan loop entirely, and let an UNGUARDED multi-line store pass as
  // if it were vacuously fine. Fixed by finding matches against the SAME
  // whole `stripped` text `hasStore` uses, then mapping each match's START
  // offset to a line index -- so both checks agree on what counts as "a
  // store", regardless of how many lines it spans.
  int lineIndexForOffset(int offset) {
    var pos = 0;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = pos + lines[i].length;
      if (offset <= lineEnd) return i;
      pos = lineEnd + 1; // +1 for the '\n' this split() consumed.
    }
    return lines.length - 1;
  }

  final storeLineIdxs = <int>[
    for (final m in storeRe.allMatches(stripped)) lineIndexForOffset(m.start),
  ];
  // The flag may appear anywhere inside an `if (...)` condition, not only as
  // the sole condition — the real code guards with `if (flagName && fp !=
  // null)` (spec §5.4's fingerprint-failure safety net adds the second
  // clause), so the check must accept a compound condition. It must NOT
  // accept a NEGATED flag (`if (!flagName)`) as a guard — that shape stores
  // exactly when sync failed, which is backwards — so any line matching the
  // positive form is discarded if it also contains the negated form.
  final guardRe = RegExp('if\\s*\\([^)]*\\b${spec.flagName}\\b[^)]*\\)');
  final negatedRe = RegExp('!\\s*${spec.flagName}\\b');
  for (final lineIdx in storeLineIdxs) {
    var guarded = false;
    for (var back = lineIdx; back >= 0 && lineIdx - back < 6; back--) {
      if (guardRe.hasMatch(lines[back]) && !negatedRe.hasMatch(lines[back])) {
        guarded = true;
        break;
      }
    }
    if (!guarded) {
      return AtomicityViolation(
          'Line ${lineIdx + 1}: ${spec.indexAssignPrefix} store is not visibly '
          'guarded by a positive `if (... ${spec.flagName} ...)` within 6 lines '
          'above it (a negated `if (!${spec.flagName})` does not count as a guard).');
    }
  }

  final setFalseCount =
      RegExp('${spec.flagName}\\s*=\\s*false\\s*;').allMatches(stripped).length;
  if (setFalseCount != spec.expectedSwallowCatches) {
    return AtomicityViolation(
        '${spec.flagName} is set false in $setFalseCount place(s); expected '
        'exactly ${spec.expectedSwallowCatches} (one per swallowing catch block '
        'for this domain). A mismatch means either a new swallowing catch forgot '
        'to guard the flag, or the expected count in '
        'sync_hash_skip_atomicity_lib.dart is stale.');
  }

  return null;
}
