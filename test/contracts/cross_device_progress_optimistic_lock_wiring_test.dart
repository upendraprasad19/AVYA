// Unit 3b (OI-45 cross-device half, progress-map-consolidation batch,
// diagnose e6b9c4) — source-structure contract pinning the client-side
// wiring of the two optimistic-lock RPCs. The RPCs' own optimistic-lock
// SEMANTICS (version mismatch -> NULL, shared whole-row counter, COALESCE
// partial update, the p_freezes_last_refill TEXT-vs-`date` cast bug, the
// round-1-review P0 grant fix, the P2 COALESCE-default fix) are verified
// live against real Postgres in
// test/sql/cross_device_progress_optimistic_lock_verify.sql (14 cases
// green, re-run 2026-07-30 post-round-1-fixes) — that is the behavioral
// proof; this file pins the CLIENT wiring shape so a future edit can't
// silently regress it back to a raw, version-blind upsert (the exact bug
// this unit closes) without a test failing, PLUS pins the round-1-review
// P0/P1/P2 fixes (anon-grant regex, COALESCE-default regex,
// SyncService.pushOnboardingProgressSnapshot + UserRepository.
// syncOnboardingToSupabase's THIRD-writer fix). No Supabase client mock
// exists in this suite (confirmed by grep) — source-structure regex
// assertions are the established pattern for this class of fix (mirrors
// health_sync_service_dedup_test.dart, Unit 3a).
//
// Run: flutter test test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart

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
  final restoreCompletenessSource = _strip(File(
          'lib/core/services/sync/sync_restore_completeness.dart')
      .readAsStringSync());
  final syncProfileSource = _strip(
      File('lib/core/services/sync/sync_profile.dart').readAsStringSync());
  final syncServiceSource =
      _strip(File('lib/core/services/sync_service.dart').readAsStringSync());
  final userRepositorySource = _strip(
      File('lib/shared/repositories/user_repository.dart').readAsStringSync());
  // SQL line comments (--) stripped before any presence-count assertion —
  // this migration's own header prose describes the fix in English and
  // would otherwise inflate a naive count (feedback_source_grep_strip_
  // comments_first.md).
  final migration115Source = File(
          'supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql')
      .readAsStringSync()
      .split('\n')
      .map((line) {
        final idx = line.indexOf('--');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');

  group('syncFreezes() routes through update_streak_progress (was dormant)',
      () {
    final sig = RegExp(
      r'Future<void>\s+syncFreezes\(\)\s*async\s*\{([\s\S]*?)\n  \}\n',
    ).firstMatch(restoreCompletenessSource);

    test('signature resolves — update this regex if the method shape moved',
        () {
      expect(sig, isNotNull);
    });

    final body = sig!.group(1)!;

    test('calls the update_streak_progress RPC, not a raw upsert on the '
        'freeze columns', () {
      expect(body.contains("rpc(\n        'update_streak_progress',"), isTrue,
          reason: 'this is the exact bug OI-45 finding 2 named: the RPC '
              '(migration 056/090/091/096) existed, was live and correct, '
              'but had zero callers — syncFreezes must call it, not upsert '
              'the freeze columns directly.');
      expect(
        RegExp(r"upsert\(\{\s*'user_id':\s*userId,\s*'streak_freezes_available'")
            .hasMatch(body),
        isFalse,
        reason: 'the OLD version-blind raw upsert on the freeze columns '
            'must be gone, not left as a second, competing writer.',
      );
    });

    test('derives expected_version from the local streak_progress_version, '
        'defaulting to 0 for a never-synced install', () {
      expect(
        RegExp(r"expectedVersion\s*=\s*\(p\['streak_progress_version'\] as num\?\)\?\.toInt\(\)\s*\?\?\s*0")
            .hasMatch(body),
        isTrue,
        reason: 'must match update_streak_progress\'s own fresh-row '
            'contract (p_expected_version <> 0 on a NOT-FOUND row returns '
            'NULL) — defaulting anywhere other than 0 would make every '
            'brand-new install\'s first sync spuriously fail.',
      );
    });

    test('on a NULL (version-mismatch) result, retries exactly once via the '
        'dedicated retry helper, not a loop', () {
      expect(body.contains('_retrySyncFreezesOnceAfterConflict'), isTrue,
          reason: 'the bounded single-retry-then-drop path must exist.');
      // "Once" is enforced by the retry helper itself calling the RPC
      // exactly one more time with no further branching on its own result
      // other than success-vs-drop — pinned in the retry helper's own test
      // below, not re-derived here from caller-side text alone.
    });

    test('the streak_freezes_first_pro_grant_done flag stays on a plain '
        'upsert, deliberately excluded from the optimistic lock', () {
      expect(
        RegExp(r"upsert\(\{\s*'user_id':\s*userId,\s*'streak_freezes_first_pro_grant_done':\s*true")
            .hasMatch(body),
        isTrue,
        reason: 'monotonic one-directional (false->true) fields are '
            'provably race-safe without a version lock — this must stay a '
            'plain upsert, not be forced through the RPC (which does not '
            'have a parameter for it).',
      );
    });
  });

  group('_retrySyncFreezesOnceAfterConflict — bounded, reconciling retry',
      () {
    final sig = RegExp(
      r'Future<void>\s+_retrySyncFreezesOnceAfterConflict\(\{([\s\S]*?)\n  \}\n',
    ).firstMatch(restoreCompletenessSource);

    test('signature resolves', () => expect(sig, isNotNull));

    final body = sig!.group(1)!;

    test('reconciles via the SAME pure merge the restore path already uses '
        '(mergeFreezeProgress), not a fresh ad-hoc merge algorithm', () {
      expect(body.contains('StreakProgressService.mergeFreezeProgress'),
          isTrue,
          reason: 'freeze fields have genuine dual-writer conflict '
              'semantics (device A consume vs device B refill) — the '
              'existing, tested merge helper is the correct reconciliation, '
              'not last-write-wins.');
    });

    test('calls the RPC exactly once more (bounded — no loop)', () {
      final rpcCalls = RegExp(r"\.rpc\(\s*'update_streak_progress'")
          .allMatches(body)
          .length;
      expect(rpcCalls, 1,
          reason: 'the retry is bounded to a SINGLE re-attempt — a second '
              'mismatch must drop, not recurse or loop.');
    });

    test('drops (logs telemetry) rather than looping on a second mismatch',
        () {
      expect(body.contains('sync_freezes_retry_dropped'), isTrue);
      expect(body.contains('ErrorTelemetry.logEvent'), isTrue,
          reason: 'a dropped reconciliation must be observable in '
              'telemetry, not silently swallowed.');
    });

    test('on success, writes the MERGED values back to local Hive too, not '
        'just the cloud', () {
      expect(
        body.contains("p['streak_freezes_available'] = finalMerge.available"),
        isTrue,
        reason: 'otherwise local state stays diverged from what the cloud '
            'now holds after reconciliation — the whole point of merging '
            'instead of blind-retrying. B-pass round-2 Finding 1: renamed '
            'from `merged` to `finalMerge` when Hermes C2 added a SECOND '
            'merge pass so the RPC round-trip await window is closed too.',
      );
    });

    test('the final write-back is itself ownership-guarded (B-pass '
        'round-2 Finding 4)', () {
      expect(body.contains('HiveUserSession.currentOwnerFullId != userId'),
          isTrue,
          reason: 'without this, a sign-out/sign-in-as-different-user race '
              'landing inside the RPC await above would write device-A '
              'freeze data into whatever account is live now — the same '
              'guard _stampProgressVersion already has, applied here too.');
    });
  });

  group('_restoreFreezes captures streak_progress_version on restore', () {
    test('the explicit select list includes streak_progress_version', () {
      final selectCall = RegExp(
        r"\.select\(\s*\n(?:[^)]*\n)*?\s*\)\s*\n\s*\.eq\('user_id', userId\)\s*\n\s*\.maybeSingle\(\)\s*\n\s*: preFetched;",
      ).firstMatch(restoreCompletenessSource);
      expect(selectCall, isNotNull,
          reason: '_restoreFreezes select shape changed — update this regex');
      expect(selectCall!.group(0)!.contains('streak_progress_version'), isTrue,
          reason: 'without this, a device that only ever restores (never '
              'syncs first) would have no real expected_version and would '
              'default to 0 forever, spuriously mismatching against any '
              'nonzero real cloud version.');
    });

    test('cloud version unconditionally wins on restore (pure server-side '
        'monotonic counter, never merged like available/used_dates)', () {
      expect(
        restoreCompletenessSource
            .contains("existingMap['streak_progress_version'] = cloudVersion"),
        isTrue,
      );
    });
  });

  group(
      '_buildUserProgressRpcParams — shared params builder '
      '(B-pass round-2, extracted so _syncUserProgress and its retry '
      'helper cannot drift apart)', () {
    final sig = RegExp(
      r'Map<String, dynamic> _buildUserProgressRpcParams\(Map<String, dynamic> p\)\s*\{([\s\S]*?)\n  \}\n',
    ).firstMatch(syncProfileSource);

    test('signature resolves', () => expect(sig, isNotNull));

    final body = sig!.group(1)!;

    test('every RPC param key is always present (explicit null), never '
        'conditionally omitted like the old upsert', () {
      // The old code used `if (p['x'] != null) 'x': p['x']` — the new RPC
      // params map must NOT use that pattern, since PostgREST requires
      // every declared function parameter by name (no DEFAULT NULL in
      // migration 115's signature) and relies on COALESCE server-side
      // instead of client-side conditional-omit for the same
      // "don't touch this column" effect.
      expect(body.contains("if (p['current_phase'] != null)"), isFalse);
    });

    test('uses defensive (x as num?)?.toInt() casts, not hard as int? '
        '(Hermes C9)', () {
      expect(
        body.contains(
            "'p_current_phase': (p['current_phase'] as num?)?.toInt()"),
        isTrue,
        reason: 'a hard `as int?` throws on any non-int numeric shape '
            '(e.g. a value that round-tripped through JSON as a double); '
            'this cast is the only guard in the path.',
      );
    });
  });

  group('_syncUserProgress() routes through update_user_progress_snapshot',
      () {
    // OI-150 — REPOINTED, not loosened. `_syncUserProgress` gained an optional
    // `{bool fromQueue = false}` so the SyncQueue drain executor can observe
    // failure (the method otherwise swallows, which made the executor's own
    // catch unreachable and every drain re-enqueue a duplicate). The parameter
    // list is now matched permissively so a future named parameter does not
    // break this pin again, while the leading `String userId` stays required.
    final sig = RegExp(
      r'Future<void>\s+_syncUserProgress\(\s*String userId[^)]*\)\s*async\s*\{([\s\S]*?)\n  \}\n',
    ).firstMatch(syncProfileSource);

    test('signature resolves', () => expect(sig, isNotNull));

    final body = sig!.group(1)!;

    test('OI-150: the queue contract is intact — fromQueue rethrows so a '
        'drain can see failure, and does not re-enqueue from inside a drain',
        () {
      expect(body.contains('if (fromQueue) rethrow;'), isTrue,
          reason: 'without the rethrow the executor\'s catch is unreachable '
              'and every drain reports Ok for a push that failed');
      final rethrowAt = body.indexOf('if (fromQueue) rethrow;');
      final enqueueAt = body.indexOf('SyncQueue.instance.enqueue');
      expect(enqueueAt, greaterThan(rethrowAt),
          reason: 'the enqueue must sit AFTER the rethrow, so a drain never '
              'mints a fresh marker — that would reset retryCount forever '
              'and the op would never dead-letter');
    });

    test('calls the update_user_progress_snapshot RPC, not a raw upsert',
        () {
      expect(body.contains("rpc(\n        'update_user_progress_snapshot',"),
          isTrue);
      expect(
        RegExp(r"upsert\(\{\s*'user_id':\s*userId,\s*if\s*\(p\['current_phase'\]")
            .hasMatch(body),
        isFalse,
        reason: 'the OLD version-blind conditional-upsert must be gone.',
      );
    });

    test('builds its rpcParams via the shared _buildUserProgressRpcParams '
        'helper, not an inline duplicate (B-pass round-2)', () {
      expect(body.contains('_buildUserProgressRpcParams(p)'), isTrue,
          reason: 'the retry helper below rebuilds from a fresh Hive read '
              'using this SAME helper; a duplicated inline copy here could '
              'silently drift from that rebuild.');
    });

    test('retries exactly once via the dedicated retry helper on mismatch',
        () {
      expect(body.contains('_retrySyncUserProgressOnceAfterConflict'),
          isTrue);
    });
  });

  group(
      '_retrySyncUserProgressOnceAfterConflict — rebuilds from a FRESH '
      'Hive read, not a stale caller-supplied snapshot (B-pass round-2 '
      'Finding 2: the exact bug class Hermes C2 fixed on the freezes side '
      'but missed here)', () {
    final sig = RegExp(
      r'Future<void>\s+_retrySyncUserProgressOnceAfterConflict\(\{([\s\S]*?)\n  \}\n',
    ).firstMatch(syncProfileSource);

    test('signature resolves', () => expect(sig, isNotNull));

    final body = sig!.group(1)!;

    test('selects only streak_progress_version, not the full row — these '
        'fields are client-authoritative, not merged like freezes', () {
      expect(body.contains("select('streak_progress_version')"), isTrue);
    });

    test('rebuilds params from a fresh Hive read via the shared helper '
        'when a progress map exists', () {
      expect(
        body.contains("final freshLocal = _hive.userBox.get('progress');"),
        isTrue,
      );
      expect(body.contains('_buildUserProgressRpcParams('), isTrue);
    });

    test('merges the fresh-Hive rebuild with the original rpcParams via '
        'mergeRpcParamsPreferringNonNull, not an all-or-nothing swap '
        '(B-pass round-3 Finding 1: the round-2 fix above silently dropped '
        'detected_experience_level for the onboarding caller)', () {
      expect(
        body.contains('SyncService.mergeRpcParamsPreferringNonNull('),
        isTrue,
        reason: 'an all-or-nothing swap (freshLocal is Map ? '
            '_buildUserProgressRpcParams(...) : rpcParams) regresses any '
            'field the fresh-Hive source does not track — e.g. '
            'p_detected_experience_level for pushOnboardingProgressSnapshot '
            "'s caller — to null. The per-field merge must wrap the rebuilt "
            'params, preferring their non-null values but falling back to '
            'the original rpcParams per-field.',
      );
    });

    test('falls back to the caller-supplied rpcParams only when Hive has '
        'no progress map yet (brand-new-account onboarding path)', () {
      expect(body.contains(': rpcParams;'), isTrue,
          reason: 'pushOnboardingProgressSnapshot\'s progressData is a '
              'hardcoded fresh-account default on a brand-new account, not '
              'a Hive read — the fallback preserves current (unregressed) '
              'behavior for that case.');
    });

    test('calls the RPC exactly once more (bounded)', () {
      final rpcCalls =
          RegExp(r"\.rpc\(\s*\n\s*'update_user_progress_snapshot'")
              .allMatches(body)
              .length;
      expect(rpcCalls, 1);
    });

    test('drops (logs telemetry) rather than looping on a second mismatch',
        () {
      expect(body.contains('sync_user_progress_retry_dropped'), isTrue);
    });
  });

  group('SyncService._stampProgressVersion — shared local writer', () {
    test('exists as a static method on SyncService (cross-part-file '
        'sharing convention, mirrors _hasValue/_hasNumber); takes an '
        'explicit userId (Hermes C5 ownership guard)', () {
      expect(
        RegExp(r'static void _stampProgressVersion\(int newVersion, '
                r'\{required String userId\}\)')
            .hasMatch(syncServiceSource),
        isTrue,
      );
    });

    test('checks the caller-supplied userId against the live session owner '
        'before writing (Hermes C5)', () {
      expect(
        syncServiceSource
            .contains('HiveUserSession.currentOwnerFullId != userId'),
        isTrue,
        reason: 'without this, a sign-out/sign-in-as-different-user race '
            'could land this device\'s stamp into a different account\'s box.',
      );
    });

    test('does a fresh Hive read immediately before the write, not reusing '
        'a caller-supplied stale snapshot', () {
      final sig = RegExp(
        r'static void _stampProgressVersion\(int newVersion, '
        r'\{required String userId\}\)\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(syncServiceSource);
      expect(sig, isNotNull);
      final body = sig!.group(1)!;
      final getIdx = body.indexOf('.get(');
      final putIdx = body.indexOf('.put(');
      expect(getIdx, greaterThanOrEqualTo(0));
      expect(putIdx, greaterThan(getIdx));
      // No await between get and put in this method — matches the
      // established "Hive write is sync" invariant (Unit 3a), so a
      // same-device concurrent write landed between the two RPC callers'
      // own async gaps still isn't clobbered by this narrow read-modify-write.
      final between = body.substring(getIdx, putIdx);
      expect(between.contains('await'), isFalse,
          reason: 'a real await between the fresh read and the write would '
              'reopen exactly the stale-snapshot race Unit 3a fixed '
              'elsewhere in this same batch.');
    });

    test('never regresses an already-newer stamp (Hermes C6 monotonic '
        'guard)', () {
      final sig = RegExp(
        r'static void _stampProgressVersion\(int newVersion, '
        r'\{required String userId\}\)\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(syncServiceSource);
      final body = sig!.group(1)!;
      expect(body.contains('if (newVersion <= existingVersion) return;'),
          isTrue,
          reason: '3+ overlapping same-device writers fire this method — '
              'without a monotonic guard the last one to run could regress '
              'an already-newer stamp.');
    });
  });

  group('migration 115 — the p_freezes_last_refill TEXT-vs-date cast fix '
      'stays in place', () {
    test('both the INSERT and UPDATE branches of the hardened '
        'update_streak_progress cast the parameter to ::date', () {
      final casts =
          RegExp(r'p_freezes_last_refill::date').allMatches(migration115Source).length;
      expect(casts, 2,
          reason: 'one in the fresh-insert VALUES list, one in the UPDATE '
              'SET clause — this is the P0 this migration found and fixed '
              'via live testing (test/sql/'
              'cross_device_progress_optimistic_lock_verify.sql case '
              'streak_fresh_insert_and_date_cast_fix): every call reaching '
              'either branch pre-fix threw 42804 on live Postgres, because '
              'TEXT does not implicitly cast to `date` in an assignment '
              'context. Regressing this cast reopens a P0 that would break '
              'every brand-new user\'s first-ever streak sync.');
    });

    test('both RPCs\' fresh-insert branches use ON CONFLICT (user_id) DO '
        'NOTHING, not a bare INSERT', () {
      final onConflicts =
          RegExp(r'ON CONFLICT \(user_id\) DO NOTHING').allMatches(migration115Source).length;
      expect(onConflicts, 2,
          reason: 'one per RPC — closes the 23505 unique-violation race '
              'between two concurrent first-ever syncs for a brand-new '
              'account (found in passing while writing this migration).');
    });
  });

  group('round-1-review P0 fix — anon-executable grant stays closed', () {
    test('update_user_progress_snapshot is revoked from PUBLIC, anon, AND '
        'authenticated (not PUBLIC alone)', () {
      expect(
        migration115Source.contains(
            ') FROM PUBLIC, anon, authenticated;'),
        isTrue,
        reason: 'REVOKE ... FROM PUBLIC alone is a no-op against Supabase\'s '
            'per-role default ACL (postgres role grants EXECUTE on every new '
            'public-schema function DIRECTLY to anon/authenticated via '
            'pg_default_acl, bypassing PUBLIC entirely) — live-reproduced by '
            'round-1 review AND independently by me before this fix. '
            'Regressing this line re-opens a real privilege-escalation bug: '
            'any anon-key holder could overwrite an arbitrary victim\'s '
            'phase/streak/workout-count row.',
      );
    });

    test('the FROM-PUBLIC-only shape does not appear anywhere in the grant '
        'block (would silently reopen the P0)', () {
      expect(
        RegExp(r'update_user_progress_snapshot[\s\S]*?\)\s*FROM PUBLIC;')
            .hasMatch(migration115Source),
        isFalse,
      );
    });
  });

  group('round-1-review P2 fix — fresh-insert COALESCEs to schema defaults',
      () {
    test('current_phase/current_week/total_workouts_done/'
        'current_streak_weeks are COALESCE-wrapped on the fresh-insert '
        'branch, matching their real schema defaults', () {
      // Schema defaults confirmed live via information_schema.columns:
      // current_phase=1, current_week=1, total_workouts_done=0,
      // current_streak_weeks=0 (all nullable) — an un-COALESCE'd NULL param
      // would silently insert NULL instead of the intended default.
      expect(migration115Source.contains('COALESCE(p_current_phase, 1)'),
          isTrue);
      expect(migration115Source.contains('COALESCE(p_current_week, 1)'),
          isTrue);
      expect(
          migration115Source.contains('COALESCE(p_total_workouts_done, 0)'),
          isTrue);
      expect(
          migration115Source
              .contains('COALESCE(p_current_streak_weeks, 0)'),
          isTrue,
          reason: 'not reachable by any writer in the original pass, but '
              'made newly reachable by the P1 fix (onboarding-replay sends '
              'current_week=NULL to preserve the program-week projection on '
              'a fresh-insert path) — must be fixed together, not left as a '
              'landmine for the P1 fix to step on.');
    });
  });

  group('round-1-review P1 fix — SyncService.pushOnboardingProgressSnapshot',
      () {
    final sig = RegExp(
      r'Future<void>\s+pushOnboardingProgressSnapshot\(\{([\s\S]*?)\n  \}\n',
    ).firstMatch(syncProfileSource);

    test('signature resolves — update this regex if the method shape moved',
        () {
      expect(sig, isNotNull);
    });

    final body = sig!.group(1)!;

    test('calls the update_user_progress_snapshot RPC, not a raw upsert', () {
      expect(
        body.contains("rpc(\n      'update_user_progress_snapshot',"),
        isTrue,
        reason: 'this is the P1 fix itself: UserRepository.'
            'syncOnboardingToSupabase was a THIRD unprotected raw-upsert '
            'writer to the same 11 fields, found by round-1 review.',
      );
    });

    test('builds rpcParams from the passed-in progressData map, not from '
        'Hive (this is the onboarding-time explicit-params path, not the '
        'regular Hive-sourced periodic sync), using the same defensive '
        'casts as the shared helper (Hermes C9)', () {
      expect(
        body.contains(
            "'p_current_phase': (progressData['current_phase'] as num?)?.toInt()"),
        isTrue,
      );
    });

    test('reads expectedVersion from Hive, defaulting to 0 for a genuinely '
        'fresh account', () {
      expect(body.contains("expectedVersion = rawProgress == null"), isTrue);
    });

    test('on a NULL (version-mismatch) result, delegates to the SAME '
        'bounded retry helper _syncUserProgress uses (no separate retry '
        'logic duplicated)', () {
      expect(body.contains('_retrySyncUserProgressOnceAfterConflict'),
          isTrue);
    });

    test('stamps the version into Hive on success, matching the shared '
        'writer convention, passing its own userId (Hermes C5)', () {
      expect(
        body.contains(
            'SyncService._stampProgressVersion(firstVersion, userId: userId)'),
        isTrue,
      );
    });
  });

  group('round-1-review P1 fix — UserRepository.syncOnboardingToSupabase '
      'routes user_progress through the RPC', () {
    final sig = RegExp(
      r'static Future<void>\s+syncOnboardingToSupabase\(\{([\s\S]*?)\n  \}\n',
    ).firstMatch(userRepositorySource);

    test('signature resolves', () => expect(sig, isNotNull));

    final body = sig!.group(1)!;

    test('calls SyncService.instance.pushOnboardingProgressSnapshot for '
        'user_progress, not a raw upsert', () {
      expect(body.contains('SyncService.instance.pushOnboardingProgressSnapshot'),
          isTrue);
    });

    test('the OLD version-blind raw upsert on user_progress is gone', () {
      expect(
        RegExp(r"supabase\.from\('user_progress'\)\.upsert\(\{")
            .hasMatch(body),
        isFalse,
        reason: 'this was the P1 bug itself: a third, unprotected writer to '
            'the same fields update_user_progress_snapshot exists to guard. '
            'Both real callers (onboarding_provider.dart\'s first-ever sync '
            'and 10s retry; sync_service.dart\'s _replayPendingOnboardingSync) '
            'get this fix for free since this method\'s public signature is '
            'unchanged — only its internal write mechanism changed.',
      );
    });
  });
}
