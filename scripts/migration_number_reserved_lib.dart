// scripts/migration_number_reserved_lib.dart
//
// Pure logic for check_migration_number_reserved.dart (OI-263, 2026-09-29).
//
// WHAT THIS ENFORCES, stated as narrowly as it is true: a NEW migration file's number has a
// `mig/N` reservation (made by scripts/mint_migration.sh), i.e. the author LOOKED at the
// server-side allocator instead of guessing `ls | tail`. It does NOT prove this branch OWNS the
// reservation, and it does NOT prevent two branches from sharing one — that collision is still
// caught only at merge by Gate 14 (`migration_collision_lib.dart`), as before. Do not read this
// as collision-freedom.
//
// The number-space grammar is the STRICT one: exactly 3 digits + optional letter. Timestamp-scheme
// files (`20260328000001_…`, frozen) and files under `041_chunks/` are OUT OF SCOPE here — they are
// not allocated numbers. (Ledger PAIRING deliberately keeps the looser `\d{3,}` grammar; see
// check_migration_ledger_paired.dart.)

import 'migration_collision_lib.dart';

/// A top-level migration path in the allocation grammar. Anchored on the FULL path: a
/// `.split('/').last` on `git diff --name-only` output would read `041_chunks/041_00_alter.sql`
/// as top-level migration 041.
final RegExp allocatedMigrationPath = RegExp(r'^supabase/migrations/([0-9]{3})([a-z]?)_[^/]*\.sql$');

/// The token before the first `_` of a top-level migration BASENAME (`152`, `050b`), or null when
/// the name is not in the allocation grammar.
String? allocatedToken(String basename) {
  final m = RegExp(r'^([0-9]{3}[a-z]?)_[^/]*\.sql$').firstMatch(basename);
  return m?.group(1);
}

/// `origin/mig/152` -> 152 for each line of `for-each-ref` / `ls-remote` output; ignores anything
/// that is not a bare positive integer with no leading zero.
Set<int> reservationNumbers(String refLines) {
  final out = <int>{};
  for (final line in refLines.split('\n')) {
    final m = RegExp(r'(?:^|/)mig/([1-9][0-9]*)\s*$').firstMatch(line.trim());
    if (m != null) out.add(int.parse(m.group(1)!));
  }
  return out;
}

class ReservationVerdict {
  ReservationVerdict(this.violations, this.notes);
  final List<String> violations;

  /// Informational: a check that could not be answered and was SKIPPED (never "passed").
  final List<String> notes;
}

/// [addedPaths]: repo-relative paths ADDED on this branch (renames already split into A+D).
/// [originMainNames]: top-level basenames under supabase/migrations/ at origin/main.
/// [ledgerIdsOnOriginMain]: `migration:` ids in origin/main's ledger.
/// [reserved]: reservation numbers, or null when they could not be determined (offline).
ReservationVerdict evaluateReservations({
  required List<String> addedPaths,
  required Set<String> originMainNames,
  required Set<String> ledgerIdsOnOriginMain,
  required Set<int>? reserved,
  Set<String> grandfathered = grandfatheredMigrationCollisionPrefixes,
}) {
  final violations = <String>[];
  final notes = <String>[];
  var skippedReservation = false;

  final mainByToken = <String, List<String>>{};
  for (final n in originMainNames) {
    final t = allocatedToken(n);
    if (t != null) mainByToken.putIfAbsent(t, () => []).add(n);
  }

  for (final path in addedPaths) {
    final m = allocatedMigrationPath.firstMatch(path);
    if (m == null) continue; // timestamp scheme, chunk dir, non-migration: out of scope
    final base = path.substring(path.lastIndexOf('/') + 1);
    if (originMainNames.contains(base)) continue; // PUBLISHED — already on origin/main

    final digits = m.group(1)!;
    final letter = m.group(2)!;
    final token = '$digits$letter';
    final n = int.parse(digits);

    final clash = (mainByToken[token] ?? const <String>[]).where((f) => f != base).toList()..sort();
    if (clash.isNotEmpty && !grandfathered.contains(token)) {
      violations.add('$base: number $token is already taken on origin/main by ${clash.join(', ')} '
          '— re-mint with `sh scripts/mint_migration.sh <slug>` and rename');
      continue;
    }

    if (letter.isEmpty) {
      if (reserved == null) {
        skippedReservation = true;
      } else if (!reserved.contains(n)) {
        violations.add('$base: no `mig/$n` reservation on origin — reserve it with '
            '`sh scripts/mint_migration.sh <slug>` (or `--reserve $n <slug>` to adopt a number you already used)');
      }
    } else {
      // Letter-suffix follow-up (050b, 068b): the BASE number must be published or reserved; the
      // suffix itself is never reserved (D6) — same-token collisions were checked above.
      final basePublished = mainByToken.containsKey(digits) || ledgerIdsOnOriginMain.contains(digits);
      if (basePublished) continue;
      if (reserved == null) {
        skippedReservation = true;
      } else if (!reserved.contains(n)) {
        violations.add('$base: follow-up to $digits, but $digits is neither published on origin/main nor reserved as `mig/$n`');
      }
    }
  }

  if (skippedReservation) {
    notes.add('reservation lookup SKIPPED — could not read refs/heads/mig/* (offline or no remote); '
        'existence of `mig/N` was NOT checked');
  }
  return ReservationVerdict(violations, notes);
}
