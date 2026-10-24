// scripts/migration_ledger_hash_lib.dart
//
// Pure logic for Gate 39's hash verification (OI-135 + OI-137 step 1).
// No dart:io, no package imports: Gate 39 runs on EVERY commit, `package:crypto`
// is only a TRANSITIVE dependency (not in pubspec.yaml), and a fresh worktree has
// no `.dart_tool`, so a lib that imported it would break the gate there.
//
// CONVENTION (resolved 2026-09-29, plan docs/plan-reviews/migration-ledger-integrity.md):
// a ledger `hash` is the sha256 of the migration file AS APPLIED. A ledger hash is
// valid iff it equals the sha256 of the file's LF form OR its CRLF form — the same
// content under either line ending. 56 entries were hashed on a Windows CRLF working
// copy before `.gitattributes` forced `eol=lf`; they are content-identical and stay
// byte-for-byte as recorded. New entries use the LF form (`migration_ledger_hash.dart`).
//
// WHAT THIS DOES NOT CATCH: a deliberate edit + re-stamp of the hash in one commit.
// It catches a FORGOTTEN re-stamp (file changed, ledger did not).

const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
const List<int> _h0 = <int>[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

/// sha256 of [data] as lowercase hex. Pinned by NIST vectors and by a test that
/// asserts equality with `sha256sum` on a real migration.
String sha256Hex(List<int> data) {
  final h = List<int>.from(_h0);
  final bitLen = data.length * 8;
  final padded = List<int>.from(data)..add(0x80);
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    padded.add((bitLen >> (8 * i)) & 0xff);
  }
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < padded.length; off += 64) {
    for (var t = 0; t < 16; t++) {
      final j = off + t * 4;
      w[t] = (padded[j] << 24) | (padded[j + 1] << 16) | (padded[j + 2] << 8) | padded[j + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final s1 = _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var t = 0; t < 64; t++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (hh + s1 + ch + _k[t] + w[t]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

/// [bytes] with every `\r\n` collapsed to `\n`.
List<int> toLf(List<int> bytes) {
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0d && i + 1 < bytes.length && bytes[i + 1] == 0x0a) continue;
    out.add(bytes[i]);
  }
  return out;
}

/// The LF form with every `\n` expanded to `\r\n`.
List<int> toCrlf(List<int> bytes) {
  final out = <int>[];
  for (final b in toLf(bytes)) {
    if (b == 0x0a) out.add(0x0d);
    out.add(b);
  }
  return out;
}

/// `sha256:<hex>` of the LF form — the ONLY form new ledger entries are written in.
String canonicalLedgerHash(List<int> bytes) => 'sha256:${sha256Hex(toLf(bytes))}';

/// Both accepted forms for [bytes], LF first.
List<String> acceptedLedgerHashes(List<int> bytes) =>
    ['sha256:${sha256Hex(toLf(bytes))}', 'sha256:${sha256Hex(toCrlf(bytes))}'];

final RegExp _realHash = RegExp(r'^sha256:[0-9a-f]{64}$');
final RegExp _sentinel = RegExp(r'^unverifiable:[a-z0-9-]+$');

enum HashShape { real, sentinel, malformed }

HashShape classifyHash(Object? value) {
  if (value is! String) return HashShape.malformed;
  if (_realHash.hasMatch(value)) return HashShape.real;
  if (_sentinel.hasMatch(value)) return HashShape.sentinel;
  return HashShape.malformed;
}

/// Ledger entries whose recorded hash matches NO form of the file at HEAD.
/// A CLOSED list — terminal, enumerated by name, never added to (same precedent as
/// `grandfatheredMigrationCollisionPrefixes` and `check_gate_test_ledger.dart`).
/// Each value PINS the LF sha256 of the file as it stands, so a further edit to a
/// grandfathered file is still detected. A pin that starts matching the ledger is a
/// STALE exemption and fails, so the list can only shrink.
///
/// 057 / 069 / 070: the ledger hash equals the CRLF form of the file at the commit that
/// introduced it (`4f74ed14`, `35005b31`, `06afc810`); `49c1b7cd` (OI-91) later edited a
/// comment / a COMMENT ON string in each. The ledger is the honest as-applied value.
/// 108 / 123: single commit each, the recorded hash matches no historical variant
/// (edited after hashing, before the first commit) — as-applied bytes unrecoverable.
const Map<String, String> grandfatheredLedgerHashDrift = {
  '057': '4deceea501a86277fceeeb7263a971fa96459a92adf4ed6e46c43f0ab4936396',
  '069': '162bc56776c86b635be363e2fe19be7c7daa8611b1020be5b7eea3aee0912eb0',
  '070': '6a13bd1e9562c58dc0eb3febf77db36bc70bb4e064b3dd391f373dd74e9b9d37',
  '108': '26aea0c533399e36a1336cb425570d3fa0d7ae5bccdf5fcbb7c642b5c93e8c6d',
  '123': '74ec692ba8b5ca426f345acb1086b440412d1d2a8e4d792be3d77991261d69c0',
};

/// Top-level `<id>_*.sql` basenames matching ledger id [id]; when several match, [slug]
/// disambiguates. Deliberately NOT the 3-digit number-space grammar: three real ledger ids
/// are timestamp-scheme (`20260328000001`, `20260330`, `20260331000001`).
List<String> resolveMigrationFiles(String id, String? slug, Iterable<String> basenames) {
  // `all_*` is the combined dump, never a migration (Gate 14 skips it the same way).
  final byId = basenames
      .where((n) => !n.startsWith('all_') && n.startsWith('${id}_') && n.endsWith('.sql'))
      .toList()
    ..sort();
  if (byId.length <= 1 || slug == null || slug.isEmpty) return byId;
  final bySlug = byId.where((n) => n.contains(slug)).toList();
  return bySlug.isEmpty ? byId : bySlug;
}

/// Verifies every ledger entry's `hash`. [fileBytes] maps a top-level migration
/// basename to its bytes. Returns human-readable violations; empty = pass.
List<String> verifyLedgerHashes(
  List<Map<String, dynamic>> entries,
  Map<String, List<int>> fileBytes, {
  Map<String, String> grandfathered = grandfatheredLedgerHashDrift,
}) {
  final violations = <String>[];
  final names = fileBytes.keys.toList();
  final seenGrandfathered = <String>{};

  for (final entry in entries) {
    final id = '${entry['migration']}';
    final raw = entry['hash'];
    final shape = classifyHash(raw);
    final files = resolveMigrationFiles(id, entry['slug'] as String?, names);

    if (shape == HashShape.malformed) {
      violations.add('$id: `hash` is not `sha256:<64 hex>` or `unverifiable:<reason>` (got: $raw)');
      continue;
    }
    if (shape == HashShape.sentinel) {
      if (files.isNotEmpty) {
        violations.add('$id: sentinel `$raw` on a migration that HAS a file (${files.first}) — a sentinel is only legal when there is no .sql artifact of its own');
      }
      continue;
    }
    if (files.isEmpty) {
      violations.add('$id: real hash but no top-level `${id}_*.sql` file — use an `unverifiable:` sentinel if none exists by design');
      continue;
    }
    if (files.length > 1) {
      violations.add('$id: ambiguous — ${files.length} files match (${files.join(', ')}); add a `slug` to the entry');
      continue;
    }
    final file = files.single;
    final bytes = fileBytes[file]!;
    final accepted = acceptedLedgerHashes(bytes);
    final matches = accepted.contains(raw);
    final pin = grandfathered[id];

    if (pin != null) {
      seenGrandfathered.add(id);
      if (matches) {
        violations.add('$id: STALE grandfather entry — the ledger hash now matches $file; remove $id from grandfatheredLedgerHashDrift');
      } else if (sha256Hex(toLf(bytes)) != pin) {
        violations.add('$id: grandfathered file $file changed since it was pinned (pin ${pin.substring(0, 12)}…, now ${sha256Hex(toLf(bytes)).substring(0, 12)}…) — an applied migration is immutable');
      }
      continue;
    }
    if (!matches) {
      violations.add('$id: ledger hash does not match $file (expected ${accepted.first}, or the CRLF form ${accepted.last.substring(0, 19)}…) — an applied migration is immutable; if the file is genuinely unapplied, re-stamp with `dart run scripts/migration_ledger_hash.dart $id`');
    }
  }

  for (final id in grandfathered.keys) {
    if (!seenGrandfathered.contains(id)) {
      violations.add('$id: grandfathered but no such ledger entry with a real hash exists — remove it from grandfatheredLedgerHashDrift');
    }
  }
  return violations;
}
