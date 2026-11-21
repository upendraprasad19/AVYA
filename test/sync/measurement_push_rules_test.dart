@Timeout(Duration(minutes: 2))
library;

// L2a (plan docs/plans/coach-measurement-entry-l2a.md, unit U1; OI-297): the
// pure rules behind the body_measurements push and pull.
//
// The two HEAD literals below were captured from the UNMODIFIED tree
// (`_syncMeasurements` at 03aca41c, through the sync harness) so the
// "byte-identical legacy shape" and "no re-push after upgrade" claims are not
// checked against the code under change.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/services/sync/measurement_push_rules.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;

const _headBodyWaistOnly =
    '{"user_id":"$kTestUserId","date":"2026-09-20","chest":null,"waist":80.0,'
    '"hips":null,"arms":null,"notes":null,"created_at":"2026-09-20T06:00:00.000Z"}';
const _headFingerprintWaistOnly = '7f56e459-2867-508f-b1fc-7db509714c49';
const _headBodyFull =
    '{"user_id":"$kTestUserId","date":"2026-09-21","chest":100.5,"waist":82.0,'
    '"hips":95.0,"arms":33.0,"notes":"after run",'
    '"created_at":"2026-09-21T06:00:00.000Z"}';
const _headFingerprintFull = '91da4819-4221-5262-8393-0e247bb99d38';

Map<String, dynamic> _legacy(
  Map<String, dynamic> log, {
  String date = '2026-09-20',
  String? createdAt,
}) => measurementLegacyPayload(
  userId: kTestUserId,
  date: date,
  log: log,
  createdAt: createdAt ?? log['created_at'] as String?,
);

void main() {
  group('HEAD literals (captured from the unmodified tree)', () {
    final waistOnly = _legacy({
      'date': '2026-09-20',
      'waist': 80.0,
      'created_at': '2026-09-20T06:00:00.000Z',
    });
    final full = _legacy({
      'date': '2026-09-21',
      'chest': 100.5,
      'waist': 82.0,
      'hips': 95.0,
      'arms': 33.0,
      'notes': 'after run',
      'created_at': '2026-09-21T06:00:00.000Z',
    }, date: '2026-09-21');

    test('the legacy payload is HEAD\'s wire body, key order included', () {
      expect(jsonEncode(waistOnly), _headBodyWaistOnly);
      expect(jsonEncode(full), _headBodyFull);
    });

    test('the fingerprint content hashes to what HEAD stored (no re-push)', () {
      expect(
        SyncFingerprint.of(measurementFingerprintContent(waistOnly)),
        _headFingerprintWaistOnly,
      );
      // The boundary: a fully populated record is identical to HEAD.
      expect(
        SyncFingerprint.of(measurementFingerprintContent(full)),
        _headFingerprintFull,
      );
    });
  });

  group('measurementMergeSafeBody', () {
    test(
      'a site-only record sends only that site (and user_id/date/created_at)',
      () {
        final body = measurementMergeSafeBody(
          _legacy({
            'date': '2026-09-20',
            'waist': 80.0,
            'created_at': '2026-09-20T06:00:00.000Z',
          }),
        )!;
        expect(body.keys.toList(), ['user_id', 'date', 'waist', 'created_at']);
      },
    );

    test('a notes-only record is pushed; an empty-String notes is a value', () {
      expect(
        measurementMergeSafeBody(_legacy({'date': 'd', 'notes': 'hi'})),
        isNotNull,
      );
      final empty = measurementMergeSafeBody(
        _legacy({'date': 'd', 'notes': ''}),
      )!;
      expect(empty['notes'], '');
    });

    test('a record with no site and no notes String pushes nothing', () {
      expect(measurementMergeSafeBody(_legacy({'date': 'd'})), isNull);
      expect(
        measurementMergeSafeBody(_legacy({'date': 'd', 'notes': 42})),
        isNull,
      );
      expect(
        measurementMergeSafeBody(
          _legacy({'date': 'd', 'chest': null, 'notes': null}),
        ),
        isNull,
      );
    });

    test(
      'non-finite and non-number sites are not pushed; a finite sibling is',
      () {
        final body = measurementMergeSafeBody(
          _legacy({
            'date': 'd',
            'chest': double.nan,
            'waist': double.infinity,
            'hips': double.negativeInfinity,
            'arms': 33,
          }),
        )!;
        expect(body.containsKey('chest'), isFalse);
        expect(body.containsKey('waist'), isFalse);
        expect(body.containsKey('hips'), isFalse);
        expect(body['arms'], 33);
        expect(
          measurementMergeSafeBody(
            _legacy({'date': 'd', 'waist': '82', 'hips': true}),
          ),
          isNull,
        );
      },
    );

    test(
      'zero is a finite number and is pushed (only the cloud can hold one)',
      () {
        expect(
          measurementMergeSafeBody(
            _legacy({'date': 'd', 'waist': 0}),
          )!['waist'],
          0,
        );
      },
    );

    test('created_at is absent when none is known', () {
      final body = measurementMergeSafeBody(
        measurementLegacyPayload(
          userId: kTestUserId,
          date: 'd',
          log: {'waist': 80.0},
          createdAt: null,
        ),
      )!;
      expect(body.containsKey('created_at'), isFalse);
    });

    test(
      'a restore-shaped record (explicit nulls, id, source) pushes held sites only',
      () {
        final body = measurementMergeSafeBody(
          _legacy({
            'id': 'x',
            'user_id': 'other',
            'date': '2026-09-20',
            'chest': null,
            'waist': 81.0,
            'hips': null,
            'arms': null,
            'notes': null,
            'source': 'cloud_restore',
            'created_at': '2026-09-20T06:00:00.000Z',
          }),
        )!;
        expect(body.keys.toList(), ['user_id', 'date', 'waist', 'created_at']);
        expect(
          body['user_id'],
          kTestUserId,
          reason: 'the live user, never the row',
        );
      },
    );
  });

  group('measurementFingerprintContent', () {
    test('non-pushable values normalise to null, valid ones are untouched', () {
      final content = measurementFingerprintContent(
        _legacy({
          'date': 'd',
          'chest': double.nan,
          'waist': 82,
          'hips': '95',
          'arms': 33.5,
          'notes': 42,
        }),
      );
      expect(content['chest'], isNull);
      expect(content['waist'], 82, reason: '82 stays an int, 82.0 a double');
      expect(content['hips'], isNull);
      expect(content['arms'], 33.5);
      expect(content['notes'], isNull);
      // The fingerprint never throws on a NaN record (HEAD's did, fail-open).
      expect(() => SyncFingerprint.of(content), returnsNormally);
    });

    test(
      'IDENTITY: a record the in-repo writers can produce hashes as its own '
      'legacy payload (zero, negative, int, empty-String notes included)',
      () {
        final records = <Map<String, dynamic>>[
          {'date': 'd', 'waist': 80.0},
          {
            'date': 'd',
            'chest': 100.5,
            'waist': 82.0,
            'hips': 95.0,
            'arms': 33.0,
            'notes': 'after run',
          },
          {'date': 'd', 'notes': ''},
          {'date': 'd', 'waist': 0},
          {'date': 'd', 'waist': 0.0, 'arms': -1.5},
          {'date': 'd', 'hips': 82},
          {
            'date': 'd',
            'chest': null,
            'waist': null,
            'hips': null,
            'arms': null,
            'notes': null,
          },
        ];
        for (final r in records) {
          final legacy = _legacy(r);
          expect(
            measurementFingerprintContent(legacy),
            equals(legacy),
            reason: 'content must equal the legacy payload for $r',
          );
          expect(
            SyncFingerprint.of(measurementFingerprintContent(legacy)),
            SyncFingerprint.of(legacy),
          );
        }
      },
    );

    test('an int and a double site fingerprint differently, as at HEAD', () {
      final a = SyncFingerprint.of(
        measurementFingerprintContent(_legacy({'date': 'd', 'waist': 80})),
      );
      final b = SyncFingerprint.of(
        measurementFingerprintContent(_legacy({'date': 'd', 'waist': 80.0})),
      );
      expect(a, isNot(b));
    });
  });

  group('mergeCloudSitesIntoLocal (the pull rule)', () {
    test('fills a site only where local is null, for every site', () {
      for (final site in kBodyMeasurementSites) {
        final merged = mergeCloudSitesIntoLocal(
          {'date': 'd'},
          {site: 70.0, 'source': 'x'},
        );
        expect(merged[site], 70.0, reason: site);
        expect(
          merged.containsKey('source'),
          isFalse,
          reason: 'only sites are copied',
        );
      }
    });

    test('never overwrites a local value and ignores a null cloud value', () {
      final merged = mergeCloudSitesIntoLocal(
        {'chest': 100.0, 'waist': null},
        {'chest': 90.0, 'waist': null},
      );
      expect(merged['chest'], 100.0);
      expect(merged['waist'], isNull);
    });

    test('a null or absent cloud site adds no key (explicit null and absent '
        'are different records)', () {
      final merged = mergeCloudSitesIntoLocal(
        {'chest': 100.0},
        {'waist': null, 'hips': null},
      );
      expect(merged.containsKey('waist'), isFalse);
      expect(merged.containsKey('hips'), isFalse);
      expect(merged.keys.toSet(), {'chest'});
    });

    test('notes are not a site: never copied in, never replaced', () {
      expect(
        mergeCloudSitesIntoLocal(
          {'waist': 80.0},
          {'notes': 'cloud note'},
        ).containsKey('notes'),
        isFalse,
      );
      expect(
        mergeCloudSitesIntoLocal(
          {'notes': 'local note'},
          {'notes': 'cloud'},
        )['notes'],
        'local note',
      );
    });

    test('does not mutate its inputs', () {
      final existing = <String, dynamic>{'waist': null};
      mergeCloudSitesIntoLocal(existing, {'waist': 80.0});
      expect(existing['waist'], isNull);
    });
  });

  group('isPushableMeasurementSite', () {
    test('every finite number is pushable: zero, negative, int, double', () {
      for (final v in <num>[0, 0.0, -1.5, -0.0, 82, 33.5, 1e9]) {
        expect(isPushableMeasurementSite(v), isTrue, reason: '$v');
      }
    });
    test(
      'nothing else is: non-finite numbers, strings, bools, null, lists',
      () {
        for (final v in <Object?>[
          double.nan,
          double.infinity,
          double.negativeInfinity,
          '82',
          true,
          null,
          <num>[80],
        ]) {
          expect(isPushableMeasurementSite(v), isFalse, reason: '$v');
        }
      },
    );
  });

  group('the registry', () {
    test('four tokens, in the cloud column order', () {
      expect(kBodyMeasurementSites, ['chest', 'waist', 'hips', 'arms']);
    });
    test('isBodyMeasurementSite accepts exactly the tokens', () {
      for (final s in kBodyMeasurementSites) {
        expect(isBodyMeasurementSite(s), isTrue, reason: s);
      }
      expect(isBodyMeasurementSite(null), isFalse);
      expect(isBodyMeasurementSite('thighs'), isFalse);
      expect(isBodyMeasurementSite('Waist'), isFalse);
      expect(isBodyMeasurementSite(''), isFalse);
    });
  });
}
