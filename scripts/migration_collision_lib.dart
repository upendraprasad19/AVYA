// scripts/migration_collision_lib.dart
//
// Pure logic for Gate 14's migration-number-collision check (OI-255).
// Detects two `supabase/migrations/*.sql` filenames sharing the exact same
// bare prefix (the token before the first `_`) -- the exact shape that let
// `template-stable-identity` and `ops-alerting` both mint 145 and 146
// independently before either branch saw the other's draft file.
//
// Deliberately NOT the same thing as the "unapplied" check
// `check_migrations_applied.dart` already runs -- a shared prefix can
// satisfy that check for BOTH files (`a.startsWith(prefix)` matches either
// applied entry), which is exactly how the 145/146 collision landed twice
// without ever failing a gate.

/// Migration number prefixes that pre-date this check (OI-255, 2026-09-27):
/// two branches each independently minted 145 and 146 before seeing the
/// other's file, and both pairs were applied live before the collision was
/// noticed. All four files are immutable once applied (see
/// supabase/migrations/CLAUDE.md), so these two prefixes can never be
/// un-collided -- they are grandfathered PERMANENTLY, not pending cleanup.
///
/// Never add a new prefix here. A future collision must be avoided at draft
/// time (re-derive the next free number fresh from origin/main plus any
/// active sibling branch before naming a new migration file), not
/// grandfathered in -- that is the entire point of this check existing.
const Set<String> grandfatheredMigrationCollisionPrefixes = {'145', '146'};

/// Groups [filenames] (bare basenames, e.g. "145_alert_sql_job_failures.sql")
/// by their bare prefix (the token before the first `_`) and returns only
/// the groups that (a) have more than one file and (b) are not in
/// [grandfathered]. An empty result means no NEW collision.
///
/// Each returned value is sorted for deterministic output.
Map<String, List<String>> findMigrationPrefixCollisions(
  List<String> filenames, {
  Set<String> grandfathered = grandfatheredMigrationCollisionPrefixes,
}) {
  final byPrefix = <String, List<String>>{};
  for (final name in filenames) {
    final prefix = name.split('_').first;
    byPrefix.putIfAbsent(prefix, () => []).add(name);
  }

  final collisions = <String, List<String>>{};
  for (final entry in byPrefix.entries) {
    if (entry.value.length > 1 && !grandfathered.contains(entry.key)) {
      final sorted = List<String>.from(entry.value)..sort();
      collisions[entry.key] = sorted;
    }
  }
  return collisions;
}
