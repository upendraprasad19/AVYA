// APK Test #12.7 — pin that every fire-and-forget sync catch in
// `sync_service.dart` funnels through ErrorTelemetry.
//
// Pre-fix: `_reportSyncFailure` posted only to `log-client-error`. When
// that Edge Function itself was down, failures got enqueued in syncBox
// for retry but Crashlytics never saw them — the founder's 30+
// `client_errors` rows per cold start had no matching crash dashboard
// signal, making remote diagnosis blind. Wiring ErrorTelemetry into
// the single funnel means every catch in this file (and there are 50+)
// gets the Crashlytics non-fatal record automatically.
//
// Source-grep test — production singletons aren't DI'able.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  group('Test #12.7 — sync error telemetry sweep', () {
    test('SyncService imports ErrorTelemetry', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(
        src,
        contains(
            "import 'package:icanbefitter/core/services/error_telemetry.dart'"),
        reason: 'sync_service.dart must import ErrorTelemetry to wire '
            'Crashlytics into every sync failure.',
      );
    });

    test(
      '_reportSyncFailure invokes ErrorTelemetry.recordNonFatal — single funnel',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        final fnIdx = src.indexOf('Future<void> _reportSyncFailure(');
        expect(fnIdx, greaterThan(0),
            reason: '_reportSyncFailure must exist.');

        // The body must call ErrorTelemetry.recordNonFatal. Slice to
        // the next sibling helper to avoid matching the inner `})` of
        // the function signature.
        final nextSibling = src.indexOf('\n  /// ', fnIdx + 1);
        final endIdx = nextSibling > 0 ? nextSibling : (fnIdx + 4000);
        final body = src.substring(
            fnIdx, endIdx > src.length ? src.length : endIdx);

        expect(
          body,
          contains('ErrorTelemetry.recordNonFatal('),
          reason: '_reportSyncFailure is the single funnel for every '
              'sync catch in this file. It must forward to '
              'ErrorTelemetry.recordNonFatal so Crashlytics sees every '
              'non-fatal sync failure (currently blind).',
        );
      },
    );

    test(
      '_reportSyncFailure passes skipServerPost:true — dual-write fix '
      '(diagnose — see docs/diagnoses/, B2a-2b)',
      () {
        // Pre-fix: _reportSyncFailure called recordNonFatal WITHOUT
        // skipServerPost, so recordNonFatal's OWN log-client-error POST
        // ran in addition to _reportSyncFailure's own separate invoke()
        // call a few lines below — two client_errors rows per failure,
        // across all 18 call sites / 11 op_types in this file. Mutating
        // this literal away (removing `skipServerPost: true`) must redden
        // this test — verified: reddens, confirmed via grep -c before/after.
        final src = loadSyncServiceSource().readAsStringSync();
        final fnIdx = src.indexOf('Future<void> _reportSyncFailure(');
        expect(fnIdx, greaterThan(0));
        final nextSibling = src.indexOf('\n  /// ', fnIdx + 1);
        final endIdx = nextSibling > 0 ? nextSibling : (fnIdx + 4000);
        final body = src.substring(
            fnIdx, endIdx > src.length ? src.length : endIdx);

        expect(
          body,
          contains('skipServerPost: true'),
          reason: '_reportSyncFailure must pass skipServerPost: true to '
              'recordNonFatal so it does ONLY the Crashlytics leg — the '
              'log-client-error POST a few lines below (already wired to '
              '_enqueueTelemetryFailure for retry) is the sole client_errors '
              'writer for this function. Without this flag, every sync '
              'failure inserts TWO client_errors rows for the one event.',
        );

        // Exactly one `functions.invoke('log-client-error'` call inside
        // this function body — the retry-tracked one. If a second appears
        // (or recordNonFatal's own network leg re-fires because the flag
        // above was dropped), the count-based check on
        // ErrorTelemetry.recordNonFatal's OWN source (below) is what
        // catches that half of the regression.
        final invokeCount = RegExp(r"functions\.invoke\(\s*'log-client-error'")
            .allMatches(body)
            .length;
        expect(invokeCount, 1,
            reason: '_reportSyncFailure must make exactly ONE direct '
                "functions.invoke('log-client-error', ...) call — this is "
                'the retry-tracked write. A second direct call here would '
                'be the same dual-write class this test guards against.');
      },
    );

    test(
      'ErrorTelemetry.recordNonFatal returns before the log-client-error '
      'leg when skipServerPost is true — dual-write fix',
      () {
        final src = File(
          '${Directory.current.path}/lib/core/services/error_telemetry.dart',
        ).readAsStringSync();
        final fnIdx = src.indexOf('static Future<void> recordNonFatal(');
        expect(fnIdx, greaterThan(0));
        final legIdx = src.indexOf('// log-client-error leg.', fnIdx);
        expect(legIdx, greaterThan(fnIdx),
            reason: 'recordNonFatal must still have a log-client-error leg '
                'for the default (skipServerPost: false) case.');
        final guardRegion = src.substring(fnIdx, legIdx);
        expect(
          guardRegion,
          contains('if (skipServerPost) return;'),
          reason: 'The skipServerPost early-return must sit BEFORE the '
              'log-client-error leg (the Crashlytics leg above it must '
              'still run unconditionally) — mutation-proven: deleting this '
              'line reddens this test AND reopens the dual-write bug for '
              '_reportSyncFailure.',
        );
      },
    );

    test(
      '_ensureSessionOpen reports openForUser failures via ErrorTelemetry',
      () {
        // C-7 (audit-2026-05-11) — the helper now delegates to the
        // shared `HiveUserSession.ensureOpenedForCurrentSession` static
        // (so RankService / SubscriptionService / migrators / splash
        // all share one entry). Either form is acceptable as long as
        // openForUser failures still funnel through ErrorTelemetry
        // somewhere downstream.
        final syncSrc = loadSyncServiceSource().readAsStringSync();
        final fnIdx =
            syncSrc.indexOf('Future<String?> _ensureSessionOpen()');
        expect(fnIdx, greaterThan(0));
        final endIdx = syncSrc.indexOf('// ──', fnIdx);
        final body = syncSrc.substring(
            fnIdx,
            endIdx > fnIdx
                ? endIdx
                : (fnIdx + 1500).clamp(0, syncSrc.length));

        final reportsInline =
            body.contains('ErrorTelemetry.recordNonFatal');
        final delegatesToShared =
            body.contains('HiveUserSession.ensureOpenedForCurrentSession');
        expect(
          reportsInline || delegatesToShared,
          isTrue,
          reason: '_ensureSessionOpen must either call '
              'ErrorTelemetry.recordNonFatal inline OR delegate to '
              'HiveUserSession.ensureOpenedForCurrentSession (which '
              'does). Both forms preserve the Crashlytics signal.',
        );

        if (delegatesToShared) {
          // Verify the downstream helper still funnels through
          // ErrorTelemetry — otherwise the delegation drops the signal.
          final hsSrc =
              _src('lib/core/services/hive_user_session.dart');
          final ensureIdx = hsSrc.indexOf(
              'static Future<String?> ensureOpenedForCurrentSession()');
          expect(ensureIdx, greaterThan(0),
              reason:
                  'shared helper must exist if SyncService delegates to it');
          final ensureEnd = hsSrc.indexOf('\n  }', ensureIdx);
          final ensureBody = hsSrc.substring(
              ensureIdx,
              ensureEnd > ensureIdx
                  ? ensureEnd
                  : (ensureIdx + 2000).clamp(0, hsSrc.length));
          expect(
            ensureBody,
            contains('ErrorTelemetry.recordNonFatal'),
            reason:
                'HiveUserSession.ensureOpenedForCurrentSession must '
                'forward openForUser failures to ErrorTelemetry — '
                'else the delegation drops the only signal we have if '
                'openForUser is itself broken.',
          );
        }
      },
    );

    test(
      'EVERY caller-level recordNonFatal that precedes a _reportSyncFailure '
      'call passes skipServerPost:true — H-42 telemetry-pair dual-write fix '
      '(B2a-2b round-1 review P0, diagnose — see docs/diagnoses/)',
      () {
        // Round 1 of this batch's own plan-review found that the original
        // fix (skipServerPost:true INSIDE _reportSyncFailure) only closed
        // the duplication _reportSyncFailure caused BY ITSELF — it missed
        // an entirely separate, pre-existing pattern: callers across
        // sync_service.dart AND every `part of` domain file under
        // lib/core/services/sync/ (sync_workout/nutrition/health/coach/
        // profile/community/realtime/restore_completeness.dart — all
        // literally the same class via Dart `part of`) follow the
        // "audit-2026-05-11 H-42 — telemetry pair" idiom, where the CALLER
        // ALSO calls ErrorTelemetry.recordNonFatal (generic reason)
        // immediately before calling _reportSyncFailure (specific opType).
        // Before this test existed, every one of those caller-level calls
        // defaulted to skipServerPost:false and silently reintroduced a
        // second client_errors row per failure — invisible to the original
        // test because it only inspected _reportSyncFailure's own body, and
        // invisible to this test's OWN first draft because a manual grep of
        // `H-42` in sync_service.dart alone (13 hits) missed the part
        // files entirely. The regex-based sweep below, run against
        // [loadSyncServiceSource]'s concatenated source (which already
        // includes every part file — see its own doc comment), found the
        // TRUE count: 87 paired sites across 8 files, not 13.
        final src = loadSyncServiceSource().readAsStringSync();

        // Non-greedy match up to the first "));" correctly closes each
        // call even when an argument itself contains a paren pair (e.g.
        // `restoreFailureReason(e)`, `StateError('${err.code}: ...')`),
        // since no legitimate argument list here contains a literal "));"
        // of its own.
        final callPattern = RegExp(
          r'unawaited\(ErrorTelemetry\.recordNonFatal\([^;]*?\)\);',
          dotAll: true,
        );
        final matches = callPattern.allMatches(src).toList();
        expect(matches.length, greaterThanOrEqualTo(100),
            reason: 'sanity floor — this regex should match at least the '
                '106 known unawaited(ErrorTelemetry.recordNonFatal( call '
                'sites across sync_service.dart + lib/core/services/sync/ '
                '(verified live 2026-09-27); if it matches far fewer, '
                'either the pattern has drifted or loadSyncServiceSource '
                'stopped concatenating the part files, and this test is '
                'not exercising what it claims to');

        // Pairing scope = the REST OF THE ENCLOSING BLOCK after the call
        // (brace-matched), not a fixed character window. A fixed 300-char
        // window was blind to a pair separated by a long comment: the
        // merge-resolution review (2026-09-28) found sync_nutrition.dart's
        // nlog item catch with a 583-char comment between its
        // recordNonFatal and its _reportSyncFailure, missing
        // skipServerPost -- a live dual-write this test reported green.
        int enclosingBlockEnd(int from) {
          var depth = 0;
          for (var i = from; i < src.length; i++) {
            final c = src[i];
            if (c == '{') depth++;
            if (c == '}') {
              if (depth == 0) return i;
              depth--;
            }
          }
          return src.length;
        }

        var pairedSiteCount = 0;
        for (final m in matches) {
          final callText = m.group(0)!;
          final windowStart = m.end;
          final windowEnd = enclosingBlockEnd(windowStart);
          final window = src.substring(windowStart, windowEnd);
          final isPaired = window.contains('_reportSyncFailure(');
          if (!isPaired) continue;
          pairedSiteCount++;
          expect(
            callText,
            contains('skipServerPost: true'),
            reason: 'a recordNonFatal call immediately followed by a '
                '_reportSyncFailure call must pass skipServerPost:true, or '
                'it double-posts to client_errors alongside '
                '_reportSyncFailure\'s own (now-fixed) internal write. '
                'Offending call: $callText',
          );
        }
        // 87 on main (2026-09-27); 70 after the day-swapper-sync-load merge
        // (2026-09-28): that batch moved the per-row push loops onto
        // SyncSkipIndex, whose own reportFailure sink calls
        // _reportSyncFailure once per failing opType per pass with no caller-
        // level recordNonFatal pair — net 17 fewer (measured: this test's own
        // matcher run per file); the batch's one NEW pair, the
        // restore_user_progress_fetch catch, needed the flag and now has it.
        // 75 after the pairing scope moved from a 300-char window to the
        // enclosing block (same day): 5 pairs the window could not see, 4
        // already flagged and 1 (the nlog item catch) fixed with it.
        expect(
          pairedSiteCount,
          equals(75),
          reason: 'expected exactly 75 caller-level H-42 telemetry-pair '
              'sites across sync_service.dart + lib/core/services/sync/ '
              '(verified live 2026-09-28) — if this count changes, a new '
              'pair was added (it needs skipServerPost:true from the '
              'start) or an existing one was removed/refactored (update '
              'this count deliberately, don\'t let it drift silently)',
        );
      },
    );
  });
}
