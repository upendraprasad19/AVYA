// lib/core/services/sync_flags.dart
//
// Per-domain feature flag for the SyncDomain interface migration
// (tech-debt audit 2026-05-20 / finding A6 — part-file → wrapper
// migration, B5 D7-D8 batch).
//
// Background
// ----------
// Each of the 8 part-files under `lib/core/services/sync/` historically
// hosts its own pair of `_syncX(userId)` + `_restoreX(userId)` private
// helpers. The A6 migration introduces per-domain wrapper classes
// implementing [SyncDomain] (`lib/core/services/sync_domains/*.dart`)
// that delegate to the existing helpers via public forwarders.
//
// CLAUDE.md §4.11 (gates-before-refactor) demands that any refactor
// touching a known bug class ships behind a feature flag so the legacy
// path stays reachable until the wrapper is independently smoke-tested.
// The recurring restore↔sync drift class (Test #12.8, 16/16 wrong-key
// restores) qualifies — A6 is explicitly the structural fix for it.
//
// Contract
// --------
// [SyncFlags.useDomainFor] reads a per-domain boolean from `configBox`
// at key `sync_domain_<name>` (defaulting FALSE — legacy path runs).
// Each follow-up batch can flip ONE domain on, smoke for 24h, and
// proceed to the next, never modifying the wrapper or the legacy
// helper in the same commit as the flip.
//
// Behaviour
// ---------
// All flags default FALSE on the B5 D7-D8 wrapper-landing batch. The
// wrappers and their public forwarders ship dual-path-ready; the
// SyncService fan-out continues to call the private `_syncX` /
// `_restoreX` helpers directly until a follow-up batch flips a flag.
//
// Flag flip plan (FUTURE BATCH — not this one)
// --------------------------------------------
// 1. Land all 8 wrappers (this batch — B5 D7-D8 A6 migration).
// 2. 24h smoke: build + ship; verify legacy path still runs; no new
//    telemetry events under `sync_domain_*` op_types.
// 3. Flip `streaks` first (smallest, already proven by the scaffold
//    behavioural test). Smoke 24h.
// 4. Flip remaining 7 domains in dependency order (workout_plan +
//    templates last per APK Test #14 / Bug B.1 ordering quirk).
// 5. Once all 8 flags are TRUE for 7+ days with no regressions, delete
//    the legacy `_syncX` / `_restoreX` private helpers in one batch.
//
// See diagnose-doc:
//   docs/diagnoses/2026-05-21-a6-sync-domain-full-migration-<hash>.md

import 'package:icanbefitter/core/services/hive_service.dart';

/// Per-domain feature flag for the [SyncDomain] migration. Reads from
/// `configBox` under key `sync_domain_<name>`. All flags default FALSE
/// so the legacy fan-out path (direct `_syncX` / `_restoreX` calls on
/// the SyncService singleton) runs unchanged on every device that has
/// not had its `configBox` row flipped.
class SyncFlags {
  SyncFlags._();

  /// Canonical configBox key prefix. Concatenated with the domain
  /// [name] (matches `SyncDomain.name`) to produce the final key.
  static const String _keyPrefix = 'sync_domain_';

  /// Returns `true` if the SyncService fan-out should dispatch through
  /// the [SyncDomain] wrapper for [name], or `false` if the legacy
  /// `_syncX` / `_restoreX` private helpers should run directly.
  ///
  /// Defaults to `false` on read-miss so cold-start devices continue
  /// to exercise the legacy path until a future batch explicitly
  /// flips the flag.
  ///
  /// Safe to call before Hive has been initialised — falls back to
  /// `false` if `configBox` is not open yet (e.g. very early boot,
  /// pure unit tests without a Hive temp dir).
  static bool useDomainFor(String name) {
    try {
      final box = HiveService.instance.configBox;
      final raw = box.get('$_keyPrefix$name');
      if (raw is bool) return raw;
      return false;
    } catch (_) {
      // configBox not opened yet — legacy path is safe default.
      return false;
    }
  }

  /// Kill-switch for the OI-170 `day_of_week` derivation on RESTORE.
  ///
  /// **Opt-OUT polarity — the fix is LIVE by default.** Set
  /// `configBox['disable_day_of_week_derive'] = true` to fall back to the
  /// legacy behaviour of trusting the value the cloud transmitted.
  ///
  /// WHY OPT-OUT RATHER THAN SHIP-DARK, since §4.6 step 1 reads as
  /// "default the NEW path behind a gate". Default-OFF here would preserve a
  /// path that is KNOWN BROKEN: the push wrote Dart's 1..7 while every reader
  /// expects 0..6, so a dark default keeps every restored row's `D<n>` badge
  /// one too high — Monday of week 1 rendering `D2`, Sunday `D8`. A flag whose
  /// safe-looking default is the bug is not a safety mechanism. §4.6's actual
  /// requirement — *"old path preserved verbatim, reachable when the gate is
  /// closed"* — is satisfied exactly as written, and the repo already uses this
  /// `disable_*` polarity for `disable_phase_arc` and `disable_triggered_deload`.
  ///
  /// FAIL DIRECTION IS TOWARD THE FIX, deliberately. On any read failure
  /// (`configBox` not open — very early boot, or a pure unit test with no Hive
  /// temp dir) this returns TRUE and derives. Deriving is a pure function of the
  /// row's own `scheduled_date` and cannot be wrong in a way trusting the wire
  /// is not; the sibling [useDomainFor] fails toward its legacy path because
  /// there the legacy path is the proven one, which is the opposite situation.
  ///
  /// Scope, so the asymmetry is not read as an oversight: the PUSH side is
  /// deliberately NOT gated. Reverting the push would re-introduce writing 1..7
  /// to the cloud, which is the defect itself, and with the restore deriving,
  /// the transmitted value is never read — so a push kill-switch would protect
  /// nothing while doubling the branch count on a sync path.
  static bool get deriveDayOfWeekOnRestore {
    try {
      return HiveService.instance.configBox.get('disable_day_of_week_derive') !=
          true;
    } catch (_) {
      return true;
    }
  }

  /// Test-only setter. Production callers MUST NOT toggle flags in
  /// code — they flip via `configBox.put` from a one-shot migration
  /// or remote-config write only.
  static Future<void> debugSetForTests(String name, bool value) async {
    final box = HiveService.instance.configBox;
    await box.put('$_keyPrefix$name', value);
  }

  /// Test-only — clears every per-domain flag to the legacy default.
  static Future<void> debugResetAllForTests() async {
    final box = HiveService.instance.configBox;
    final keys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith(_keyPrefix))
        .toList();
    for (final k in keys) {
      await box.delete(k);
    }
  }
}
