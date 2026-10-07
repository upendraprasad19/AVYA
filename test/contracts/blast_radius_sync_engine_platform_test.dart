// test/contracts/blast_radius_sync_engine_platform_test.dart
//
// OI-282 / diagnose f2c8a5 — the sync engine's core files were exempt from the
// platform review tier.
//
// docs/blast_radius.yaml classified only lib/core/services/sync/** as platform.
// The engine's own core — sync_service, sync_queue, sync_retry_controller, ... —
// sits one directory up and fell through to the `lib/core/services/**` account
// catch-all, so a diff touching ONLY those files skipped the platform gate (the
// plan-review record's `bpass: accepted`). Fourth instance of the
// blast_radius_registry_coverage class (docs/sot_registry.yaml; a3d7b1 and
// c9f1d3 before it) — and like them, the earlier fixes were hand-typed lists.
//
// So this file does not just pin a list. Three layers, each answering a
// different question:
//   1. CLASSIFICATION  every engine file is platform. Uses the classifier's OWN
//                      public functions (parseRegistry / tierFor / globToRegExp),
//                      imported — not a re-implementation of the glob engine.
//   2. COMPLETENESS    DERIVED from the engine, not hand-typed: every lib/ file
//                      that an engine file imports, exports or declares as a
//                      `part` (the listed files, sync_domains/**, sync/**), and
//                      every sync_*.dart on disk, must be platform OR be named in
//                      `_declined` below with a reason. A new engine file, or a
//                      new import from one, fails this until its tier is decided
//                      — the same shape as a3d7b1's derivation from
//                      scripts/setup-hooks.sh. `part` is read on purpose: it is
//                      how the engine itself is composed (sync_service.dart is one
//                      library of ten files), so a part file placed outside sync/
//                      would otherwise sit on the account catch-all unseen.
//   3. ROT             an exact-path rule that names a file which does not exist
//                      protects nothing. Exact paths are deliberate (a glob
//                      auto-promotes future files with nobody deciding) and exact
//                      paths rot on a rename, so a rename must update its rule.
//                      This layer found the one dead rule the registry had:
//                      `lib/core/services/profile_write_service.dart`, a path
//                      that has never existed (the file lives under
//                      lib/features/profile/services/), so the account rule
//                      written on 2026-05-28 never fired.
// Plus mirrors (look-alikes keep their tier; exact paths are really exact; no
// other wildcard can claim a services file) and one run of the real CLI.
//
// The BOUNDARY the lists below follow is written once, in docs/blast_radius.yaml
// above the first engine rule. In short, a file is platform when it is engine
// machinery, or cross-account isolation the engine registers with, or shared with
// other code but its own words say a function in it merges the cloud copy with the
// local one, supplies a push's identity, gates a push, or is a rule the restore
// merge delegates to — and then only at no more than one newly-platform commit per
// 60 days. Everything the engine only consults is declined by name, with the
// function the engine calls.
//
// Known limits, stated rather than hidden: the derivation follows what the engine
// files reach, one hop (a file reachable only through a DECLINED file is not
// derived), and it cannot see files that CALL the engine. The two known callers
// (auth_session_bootstrapper.dart, a second restore writer, and
// sync_state_provider.dart, which schedules retries) are decided and pinned by
// name in `_callers`; any other caller is not found by this test. All of it is in
// the diagnose doc's residuals.
//
// Run: flutter test test/contracts/blast_radius_sync_engine_platform_test.dart

@Timeout(Duration(minutes: 3))
library;

// The CLI test spawns real `dart run` subprocesses; a cold one costs seconds, and
// under the merge-commit regression walk the 30s per-test default is too tight
// (diagnose 4f2a9e). File-level, so the next subprocess test added here inherits it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;
import '../helpers/spawn.dart';

const _services = 'lib/core/services/';

/// The sync engine OUTSIDE lib/core/services/sync/** (which has its own platform
/// rule), spelled out. Exact paths on purpose — see docs/blast_radius.yaml.
///
/// Five groups, one reason each (the registry's three prongs):
///   - the push/restore engine itself (orchestrator, queue, retry, coalescer,
///     the SyncDomain contract, error taxonomy, flags, serialiser, probe,
///     paginator, the two cloud-delete queues);
///   - the schedule restore MERGE the engine runs (OI-285 already calls it
///     platform tier): the reconciler and the re-anchor;
///   - shared files that host one decision each: the host of the freeze merge,
///     the rules the schedule merge delegates to, the identity a template push
///     keys on, and the gate that rewrites legacy ids before any push (OI-252);
///   - the cross-account reset hook the engine registers with;
///   - two restore merges hosted outside the services layer: the progress map's
///     (UserRepository.mergeCloudProgress) and the notification preferences'
///     (NotificationPrefsRepository.adoptFromCloud).
/// sync_domains/** is a whole directory, covered by its own glob (like sync/**).
const _engine = <String>[
  '${_services}sync_service.dart',
  '${_services}sync_queue.dart',
  '${_services}sync_retry_controller.dart',
  '${_services}sync_coalescer.dart',
  '${_services}sync_domain.dart',
  '${_services}sync_error.dart',
  '${_services}sync_flags.dart',
  '${_services}serial_slot.dart',
  '${_services}backend_probe.dart',
  '${_services}paginate_all.dart',
  '${_services}pending_exlog_deletes.dart',
  '${_services}pending_template_deletes.dart',
  '${_services}plan_integrity_reconciler.dart',
  '${_services}plan_window_reanchor.dart',
  '${_services}streak_progress_service.dart',
  '${_services}day_swap/day_swap_rules.dart',
  '${_services}template_identity.dart',
  '${_services}template_identity_migrator.dart',
  '${_services}singleton_lifecycle_registry.dart',
  'lib/shared/repositories/user_repository.dart',
  'lib/features/profile/services/notification_prefs_repository.dart',
];

/// lib/ files an engine file reaches that stay BELOW platform — the engine only
/// CONSULTS them.
///
/// Being platform is the DEFAULT for anything the engine reaches; staying out
/// must be argued here. Each reason is the decision, not a description: it names
/// the function the engine calls (for a type, what the engine uses it for) and
/// why that does not make the file engine code. Three entries lean on the COST
/// cap (workout_write_service, nutrition_write_service and, in part,
/// workout_schedule_read_service): by their own words the two write services
/// could count, but other features touch all three constantly. Reverse one by
/// moving its path into docs/blast_radius.yaml and deleting it from this map (the
/// registry is itself platform tier, so a reversal is a full pipeline run). An
/// entry the engine no longer reaches must be deleted: the stale check below
/// fails on it, so the map cannot quietly outlive the code.
///
/// Costs are measured: commits over the 60 days to 2026-10-03 whose whole file
/// list classified below platform under the registry at 4259d0ed.
const _declined = <String, String>{
  // --- lib/core/services/ ---
  '${_services}completed_title_healer.dart':
      'a computation applied to the winners AFTER the restore merge (OI-284): '
      'SyncService.healCompletedTitlesAfterRestore calls CompletedTitleHealer.'
      'run() once a restore SUCCEEDED; it reads only local Hive, never the cloud '
      'copy, so it decides nothing about which copy wins, what is pushed or '
      'which key a push uses, and it sets only workout_name on a completed '
      'non-template row from that row\'s own wlog. Declined by the boundary '
      'above ("a computation applied to the winners after a merge"); one commit '
      'so far. If it ever reads cloud data or touches status it stops being '
      'declined-eligible',
  '${_services}day_swap/day_swap_result.dart':
      'the day-swap engine\'s value types (refusal reasons, origin), pure with no '
      'I/O: day_swap_rules.dart imports them, as do the Train, Home and coach '
      'files; a type, so no merge, gate, identity or push decision lives in it',
  '${_services}error_telemetry.dart':
      'failure telemetry: the engine reports through ErrorTelemetry.'
      'recordNonFatal and redacts row values with redactRowValues '
      '(sync_service.dart); it moves no user data and decides nothing about what '
      'is pushed or which copy wins',
  '${_services}health_sync_service.dart':
      'device health readings into Hive: SyncService.checkAndSync runs '
      'syncToHive() first, so the data is local before the push; it decides '
      'nothing about what is pushed or which copy wins',
  '${_services}migrated_key.dart':
      'userBox-first accessor: the engine reads, writes and deletes plan dates, '
      'the saved diet plan and the pending-onboarding flag through MigratedKey.'
      'read/write/delete; it decides where a value lives, not what is pushed or '
      'which copy wins',
  '${_services}nutrition_write_service.dart':
      'declined on cost: clampRestoredNutritionRow (the restore path\'s entry '
      'point, called from sync_nutrition.dart) bounds absurd values on a '
      'restored row with the same clamp the local write path uses, which is a '
      'borderline rule the restore shares; either way 5 commits touch the file '
      'and 4 would be newly platform on their own, over the cap of 1, and it '
      'keeps its own account rule',
  '${_services}restore_telemetry_policy.dart':
      'decides which restore ops earn a client_errors row '
      '(shouldLogRestoreOpDone): telemetry policy, no data moves',
  '${_services}result.dart':
      'the Result<T, E> value type the engine returns through (its header says '
      'SyncService and SyncQueue use it throughout): a generic type with no '
      'merge, gate, identity or push decision; callers in platform files decide',
  '${_services}subscription_service.dart':
      'entitlement state: the engine asks isPro() before opening the realtime '
      'subscription and calls refreshFromSupabase() during restore '
      '(sync_service.dart), and reads proStateSnapshot() in sync_realtime.dart; '
      'none of that selects which copy of the user\'s data wins or what is '
      'pushed',
  '${_services}supabase_service.dart':
      'the Supabase client and the authed-call plumbing every feature shares: '
      'the engine reaches it for its queries (_supabase.client in the '
      'orchestrator and its part files, SupabaseService.instance.client in the '
      'reconciler and the template migrator), for callFunction (the snapshot '
      'push and the single-call restore, with its cold-start retry) and for '
      'ensureFreshToken (coalesced token refresh before an authed call). That '
      'retry and coalescing serve AI, payments and telemetry equally, so it is '
      'shared transport, not engine logic: what is retried, and when, is '
      'decided in SyncQueue and SyncRetryController (platform). A borderline '
      'call, disclosed: promoting it adds no commit on its own (3 touch it) but '
      'would pull every AI and payments transport change into the sync review',
  '${_services}template_service.dart':
      'custom-template CRUD and scheduling: the engine delegates ONE cleanup to '
      'it (cleanSyncTemplateSchedule, from _cleanScheduleReferencesToTemplate in '
      'sync_workout.dart) and decides what to clean and when itself; 5 commits '
      'touch it, 1 would be newly platform',
  '${_services}workout_schedule_read_service.dart':
      'domain reader the engine consults for isTerminalScheduleRow (in the '
      'scheduled-workout restore merge) and currentWeekColumnProjection (in the '
      'progress push); the decisions are made in platform files, and promoting '
      'this reader alone would add 7 newly-platform commits (18 touch it), over '
      'the cost cap',
  '${_services}workout_write_service.dart':
      'declined on cost: exlogKey is the identity the exercise-log restore keys '
      'Hive rows on (sync_workout.dart: "single SoT for exlog key", so a '
      're-restore is idempotent), which would count on the verb list; but 9 '
      'commits touch the file and 5 would be newly platform on their own, over '
      'the cap of 1, and it keeps its own account rule',
  // --- outside the services layer ---
  'lib/core/constants/app_constants.dart':
      'constants: the engine stamps what it sends with AppConstants.appVersion '
      '(sync_service.dart); a value, no decision',
  'lib/core/utils/bmr_calculator.dart':
      'calorie and macro arithmetic: UserRepository (platform here) calls '
      'BmrCalculator.calculateTargets when it recomputes targets; a pure '
      'calculation, it chooses no copy',
  'lib/core/utils/date_utils.dart':
      'calendar helper: sync_workout.dart falls back to dayOfWeekFromDate(date) '
      'when a restored schedule row carries no day_of_week; it chooses no copy',
  'lib/core/utils/equipment_vocab.dart':
      'vocabulary normaliser: syncCommunityItems (sync_community.dart) passes a '
      'pulled community exercise row through EquipmentVocab.'
      'normalizedEquipmentRow before storing it; it rewrites spelling, it does '
      'not choose between copies',
  'lib/core/utils/ist_date.dart':
      'IST date keys and the dev-clock seam: the engine formats and compares '
      'dates through istDateStr, mondayOfIst and nowWall (sync_service.dart, '
      'streak_progress_service.dart); a clock helper, no decision',
  'lib/features/ai_coach/models/coach_memory.dart':
      'the coach-memory model: pushSnapshot (sync_service.dart) parses the '
      'returned coach_memory row with CoachMemory.fromJson and mirrors it into '
      'Hive; a type, no decision',
  'lib/features/ai_coach/repositories/ai_coach_repository.dart':
      'builds the AI context a snapshot carries: compileDailySnapshot calls '
      'AiCoachRepository.instance.buildAiContext(); a payload builder that '
      'reads local state, the engine decides whether and when to push it',
  'lib/features/profile/services/profile_target_recompute.dart':
      'a computation applied to the merge winners: sync_profile.dart gates the '
      'restore recompute with derivedTargetInputsChanged and calls '
      'recomputeDerivedTargets on the merged map, so the copy that wins is '
      'already chosen. A borderline call, disclosed: it adds 0 newly-platform '
      'commits (1 touches it), so flipping it is one registry rule',
  'lib/features/profile/services/profile_write_service.dart':
      'the canonical profile writer: restore writes the merged map through '
      'ProfileWriteService.instance.updateProfile(merged, skipSync: true) '
      '(sync_profile.dart); the merge that chose it is made in the engine',
};

/// lib/ files that CALL the engine but that no engine file imports, so the
/// derivation cannot reach them. Each is below platform ON PURPOSE and is named
/// here so the decision is a tested fact rather than prose: the entry must still
/// point at a real file, that file must still be below platform (a promoted
/// caller is decided: delete its entry), no engine file may reach it (one that
/// does belongs in `_declined` or in the registry), and it must still make the
/// call named in `calls` (comments stripped), so the map cannot outlive the code.
///
/// The boundary's scope is what the engine files REACH; a caller is judged on its
/// own words, and these are the two whose words come closest. To promote one, add
/// its exact rule above the catch-alls in docs/blast_radius.yaml, delete the entry
/// and list the path in `_engine` (it then becomes a derivation root, so its own
/// imports need a decision too). The registry is itself platform tier, so a
/// reversal is a full pipeline run.
const _callers = <String, ({String calls, String reason})>{
  '${_services}auth_session_bootstrapper.dart': (
    calls: 'UserRepository.mergeCloudProgress(',
    reason: 'a second restore writer: hydrateFromCloud merges the cloud users '
        'row over the local one and routes the progress map through '
        'UserRepository.mergeCloudProgress, and its comment calls it the twin of '
        'sync_profile.dart\'s _restoreUserProgress ("so the two restore writers '
        'cannot drift"). Its own words meet prong 1 ("runs a restore merge"); it '
        'stays account because it is a CALLER the engine does not reach and the '
        'rest of the file is post-auth routing. Promoting it adds 3 '
        'newly-platform commits per 60 days (6 touch it) and puts an '
        'auth-routing file under the feature_flag requirement. A borderline '
        'call, disclosed: the founder can flip it',
  ),
  'lib/shared/providers/sync_state_provider.dart': (
    calls: 'SyncQueue.instance.drain(',
    reason: 'the trigger side: it decides WHEN the engine retries (a 5-minute '
        'auto-drain timer, a drain and a forced retry when connectivity '
        'returns) and maps queue state to the "Sync paused" banner, but WHAT is '
        'retried, capped and dead-lettered is decided in SyncQueue and '
        'SyncRetryController (platform). Prong 1\'s "retries" could be read to '
        'cover a retry scheduler: 3 commits touch it and 1 would be newly '
        'platform on its own. A borderline call, disclosed: the founder can '
        'flip it',
  ),
};

const _tierOrder = ['feature', 'account', 'platform', 'catastrophic'];

String _norm(FileSystemEntity e) => e.path.replaceAll(r'\', '/');

/// [src] without `//` line comments and `/* */` block comments (naive: a marker
/// inside a string literal is not told apart, which is fine for a presence check
/// on a call name).
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Repo paths, under lib/, of every file that [src] (the source of the file at
/// [fromPath]) imports, exports or declares as a `part` / `part of`.
///
/// Reads EVERY quoted URI of a directive — single or double quoted, and the
/// alternative URIs of a conditional import — and resolves a relative URI against
/// the importing file's own directory, not a fixed root. A directive may start
/// its line or follow a `;` (two on one line), and its keyword may touch the
/// quote (`import'x.dart'`), all of which Dart accepts. A directive needs a quote
/// right after its keyword, so an identifier called `part` is not one, and
/// `part of library.name;` carries no URI at all. Comments never match: nothing
/// but whitespace may precede the keyword. (A directive inside a block comment or
/// a multi-line string would match; that errs toward demanding a decision.)
Set<String> libImports(String src, String fromPath) {
  final out = <String>{};
  // `(?<=;)` and not `;`: the previous directive already consumed its own `;`.
  final directive = RegExp(
      r'''(?:^|(?<=;))\s*(?:import|export|part(?:\s+of)?)\s*['"][^;]*;''',
      multiLine: true);
  final quoted = RegExp(r'''['"]([^'"]+)['"]''');
  for (final d in directive.allMatches(src)) {
    for (final u in quoted.allMatches(d.group(0)!)) {
      final uri = u.group(1)!;
      String? path;
      if (uri.startsWith('package:icanbefitter/')) {
        path = 'lib/${uri.substring('package:icanbefitter/'.length)}';
      } else if (!uri.contains(':')) {
        path = Uri.parse(fromPath).resolve(uri).path;
      }
      if (path != null && path.endsWith('.dart') && path.startsWith('lib/')) {
        out.add(path);
      }
    }
  }
  return out;
}

void main() {
  final reg = classifier
      .parseRegistry(File('docs/blast_radius.yaml').readAsStringSync());
  String tier(String p) => classifier.tierFor(p, reg);
  int rank(String t) => _tierOrder.indexOf(t);

  /// The first rule whose glob claims [p], or null when only default_tier would.
  classifier.TierRule? ruleFor(String p) {
    for (final r in reg.rules) {
      if (classifier.globToRegExp(r.glob).hasMatch(p)) return r;
    }
    return null;
  }

  /// Decided as engine code: platform or above, by whichever rule says so.
  bool isPlatform(String p) => rank(tier(p)) >= rank('platform');

  group('classification — every engine file is platform', () {
    for (final p in _engine) {
      test('$p exists and is platform', () {
        expect(File(p).existsSync(), isTrue,
            reason: '$p was renamed or removed: update docs/blast_radius.yaml '
                'and this list together');
        expect(tier(p), 'platform',
            reason: '$p is sync-engine code; at a lower tier a diff touching '
                'only it clears no platform gate (bpass: accepted).');
      });
    }

    test('sync_domains/** is platform at ANY depth', () {
      final onDisk = [
        for (final e in Directory('${_services}sync_domains')
            .listSync(recursive: true))
          if (e is File) _norm(e),
      ];
      expect(onDisk, isNotEmpty);
      for (final p in onDisk) {
        expect(tier(p), 'platform', reason: p);
      }
      // A directory glob must mean the whole directory, nested files included
      // (`sync_domains/*` would not): no such file exists yet, so assert it
      // against the registry rather than the disk.
      expect(tier('${_services}sync_domains/nested/x_sync_domain.dart'),
          'platform');
    });
  });

  group('completeness — derived from the engine, not hand-typed', () {
    /// Every file that is the engine: the listed exact paths, everything under
    /// sync/ and sync_domains/, and any sync_*.dart on disk (so a NEW engine file
    /// is scanned, and caught, before anything imports it).
    Set<String> engineFiles() {
      final out = <String>{..._engine};
      final family = RegExp(
          r'^lib/core/services/(sync_[^/]*\.dart|sync_domains/.+|sync/.+)$');
      for (final e in Directory(_services).listSync(recursive: true)) {
        if (e is File && _norm(e).endsWith('.dart') && family.hasMatch(_norm(e))) {
          out.add(_norm(e));
        }
      }
      return out;
    }

    /// Files whose tier somebody must have decided: every lib/ file an engine
    /// file imports, exports or declares as a part, plus the sync_*.dart /
    /// sync_domains/** family itself.
    Set<String> derived() {
      final engine = engineFiles();
      final out = <String>{
        for (final p in engine)
          if (RegExp(r'^lib/core/services/(sync_[^/]*\.dart|sync_domains/.+)$')
              .hasMatch(p))
            p,
      };
      for (final p in engine) {
        final f = File(p);
        if (f.existsSync()) out.addAll(libImports(f.readAsStringSync(), p));
      }
      return out;
    }

    test('the directive reader sees every shape, so the derivation is not vacuous',
        () {
      const from = '${_services}sync_domains/x_sync_domain.dart';
      expect(
        libImports('''
import 'package:icanbefitter/core/services/a.dart';
import "package:icanbefitter/core/services/b.dart" as b;
import '../c.dart' show C;
import 'sibling.dart' if (dart.library.io) 'd_io.dart' hide D;
export 'package:icanbefitter/core/services/e.dart';
part 'f_part.dart';
part of '../g_library.dart';
import'package:icanbefitter/core/services/h_nospace.dart';
import 'package:icanbefitter/core/services/i.dart'; import 'package:icanbefitter/core/services/j.dart';
import 'package:icanbefitter/shared/repositories/k_repo.dart';
// import 'package:icanbefitter/core/services/commented_out.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../utils/ist_date.dart';
part of some.dotted.library;
''', from),
        {
          '${_services}a.dart',
          '${_services}b.dart',
          '${_services}c.dart',
          '${_services}sync_domains/sibling.dart',
          '${_services}sync_domains/d_io.dart',
          '${_services}e.dart',
          '${_services}sync_domains/f_part.dart',
          '${_services}g_library.dart',
          '${_services}h_nospace.dart',
          '${_services}i.dart',
          '${_services}j.dart',
          'lib/shared/repositories/k_repo.dart',
          'lib/core/utils/ist_date.dart',
        },
        reason: 'the reader must see double-quoted imports, conditional-import '
            'alternatives, exports, part and part of, a keyword with no space '
            'before its quote and a second directive on the same line, resolve '
            'relative URIs against the importing file and keep lib/ files outside '
            'the services layer, and ignore comments, dart: and package:flutter',
      );

      final real = libImports(
          File('${_services}sync_service.dart').readAsStringSync(),
          '${_services}sync_service.dart');
      expect(real.length, greaterThan(50),
          reason: 'read only ${real.length} lib/ references from '
              'sync_service.dart (expected ~60); the reader no longer sees its '
              'directives');
      final d = derived();
      expect(d, contains('${_services}sync_queue.dart'));
      expect(d.any((p) => p.startsWith('${_services}sync_domains/')), isTrue);
      expect(d.length, greaterThan(55),
          reason: 'derived only ${d.length} files; expected ~64');
    });

    test('every part of the engine library is derived', () {
      // sync_service.dart is ONE library of ten files: each `part` file is the
      // engine, wherever it lives, so the guard must see it.
      const lib = '${_services}sync_service.dart';
      final parts = [
        for (final m in RegExp(r'''^part\s+['"]([^'"]+)['"]\s*;''',
                multiLine: true)
            .allMatches(File(lib).readAsStringSync()))
          Uri.parse(lib).resolve(m.group(1)!).path,
      ];
      expect(parts.length, greaterThanOrEqualTo(9),
          reason: 'sync_service.dart declares only ${parts.length} part files');
      final d = derived();
      for (final p in parts) {
        expect(d, contains(p), reason: '$p is part of the engine library');
      }
    });

    test('every derived file is platform or declined with a reason', () {
      final undecided = [
        for (final p in derived())
          if (!isPlatform(p) && !_declined.containsKey(p)) p,
      ]..sort();
      expect(undecided, isEmpty,
          reason: 'These files are part of (or reached by) the sync engine but '
              'are below platform and nobody decided: $undecided. Either add an '
              'exact-path platform rule for each ABOVE the catch-alls in '
              'docs/blast_radius.yaml (and to _engine here), or add it to '
              '_declined in this test with a written reason.');
    });

    test('every declined entry exists, has a reason, is still reached and stays '
        'below platform', () {
      final d = derived();
      for (final e in _declined.entries) {
        expect(File(e.key).existsSync(), isTrue,
            reason: '${e.key} no longer exists: delete it from _declined');
        expect(e.value.trim(), isNotEmpty);
        expect(d, contains(e.key),
            reason: 'no engine file reaches ${e.key} any more: delete it from '
                '_declined, or the map outlives the code');
        expect(isPlatform(e.key), isFalse,
            reason: '${e.key} is platform now, so it is decided: remove it '
                'from _declined');
        expect(_engine.contains(e.key), isFalse,
            reason: '${e.key} is both engine and declined');
      }
    });

    test('every known caller is below platform, not reached by the engine and '
        'still calls it', () {
      final d = derived();
      for (final e in _callers.entries) {
        final path = e.key;
        expect(File(path).existsSync(), isTrue,
            reason: '$path no longer exists: delete it from _callers');
        expect(e.value.reason.trim(), isNotEmpty);
        expect(isPlatform(path), isFalse,
            reason: '$path is platform now, so it is decided: delete it from '
                '_callers');
        expect(d, isNot(contains(path)),
            reason: 'an engine file now reaches $path, so the derivation owns '
                'it: move it to _declined with a reason, or promote it');
        expect(_engine.contains(path), isFalse,
            reason: '$path is both engine and a caller');
        expect(_declined.containsKey(path), isFalse,
            reason: '$path is both declined and a caller');
        expect(
            _stripComments(File(path).readAsStringSync())
                .contains(e.value.calls),
            isTrue,
            reason: '$path no longer calls ${e.value.calls}: it is not a caller '
                'of the engine any more, so delete it from _callers');
      }
    });
  });

  group('rot — a rule that names a missing file protects nothing', () {
    test('no exact-path rule in the registry names a file that does not exist',
        () {
      final dead = [
        for (final r in reg.rules)
          if (!r.glob.contains('*') &&
              !r.glob.contains('?') &&
              !File(r.glob).existsSync())
            r.glob,
      ];
      expect(dead, isEmpty,
          reason: 'These exact-path rules name files that do not exist, so '
              'their real targets silently fall to a catch-all ('
              'profile_write_service.dart sat at feature tier for four months '
              'this way): $dead. Point each at the file\'s real path, or '
              'delete it.');
    });
  });

  group('mirrors — look-alikes and neighbours keep their tier', () {
    test('an unnamed services file still falls to the account catch-all, so the '
        'exact rules are the only thing saving the engine', () {
      expect(tier('${_services}zz_unclassified_probe.dart'), 'account',
          reason: 'if this is not account, the platform assertions above could '
              'pass for the wrong reason and prove nothing');
    });

    test('every engine path is named by its OWN exact rule, and a brand-new '
        'sync_*.dart is not swept in by a wildcard', () {
      for (final p in _engine) {
        expect(ruleFor(p)?.glob, p,
            reason: '$p must be claimed by an exact-path rule of its own, not by '
                'a wildcard: a wildcard auto-promotes future files with nobody '
                'deciding, which is what the completeness test exists to force');
      }
      const fresh = '${_services}sync_zz_brand_new.dart';
      expect(isPlatform(fresh), isFalse,
          reason: 'a new sync_*.dart must be undecided until somebody lists it, '
              'so the completeness test can force the decision');
      expect(tier(fresh), 'account');
    });

    test('no wildcard rule other than the two directory globs claims a services '
        'file at platform', () {
      // The probe above names ONE stem; this closes the others (a `*_queue.dart`
      // would auto-promote every future file of that shape with nobody deciding).
      const directories = {
        'lib/core/services/sync/**',
        'lib/core/services/sync_domains/**',
      };
      final wildcards = [
        for (final r in reg.rules)
          if (r.glob.startsWith(_services) &&
              (r.glob.contains('*') || r.glob.contains('?')) &&
              rank(r.tier) >= rank('platform') &&
              !directories.contains(r.glob))
            r.glob,
      ];
      expect(wildcards, isEmpty,
          reason: 'A platform wildcard under lib/core/services/ promotes future '
              'files unseen: $wildcards. Name each file with an exact path, or '
              'extend this allow-list on purpose.');
    });

    test('the neighbours of the two files promoted outside the services layer '
        'keep their tier', () {
      // user_repository.dart and notification_prefs_repository.dart must beat the
      // directory rules below them, and ONLY they may: a sibling stays where its
      // directory puts it.
      expect(tier('lib/shared/repositories/exercise_repository.dart'), 'account');
      expect(tier('lib/features/profile/services/zz_other_service.dart'),
          'feature');
      expect(tier('lib/shared/repositories/plan_engine/zz_probe.dart'),
          'platform',
          reason: 'plan_engine/** was platform before this change');
    });

    test('the profile write service (real path) is account', () {
      expect(tier('lib/features/profile/services/profile_write_service.dart'),
          'account',
          reason: 'the account rule for it named a path that never existed');
    });

    test('files inside sync/** stay platform', () {
      expect(tier('${_services}sync/sync_resilience.dart'), 'platform');
    });

    test('the write services the engine calls keep their explicit account rule',
        () {
      expect(tier('${_services}workout_write_service.dart'), 'account');
      expect(tier('${_services}nutrition_write_service.dart'), 'account');
    });
  });

  test('the real CLI agrees, and prints the MAX tier of a mixed diff', () {
    String cli(List<String> paths) {
      final r = runSpawn(
        'dart',
        ['run', 'scripts/blast_radius_from_diff.dart', ...paths],
        why: 'blast_radius_from_diff CLI on $paths',
        runInShell: true,
      );
      final m = RegExp(r'Blast-radius:\s*(\w+)')
          .firstMatch((r.stdout as String).trim());
      expect(m, isNotNull, reason: 'no tier printed for $paths:\n${r.stdout}');
      return m!.group(1)!;
    }

    expect(cli(['${_services}template_service.dart']), 'account',
        reason: 'control: a declined service is account');
    expect(cli(['${_services}sync_queue.dart']), 'platform');
    expect(cli(['lib/shared/repositories/user_repository.dart']), 'platform',
        reason: 'a promoted file outside the services layer beats the '
            'repository rule below it');
    expect(
        cli([
          'lib/features/home/screens/home_screen.dart',
          '${_services}backend_probe.dart',
          '${_services}template_service.dart',
        ]),
        'platform',
        reason: 'one engine file in a mixed diff makes the whole diff platform');
  });
}
