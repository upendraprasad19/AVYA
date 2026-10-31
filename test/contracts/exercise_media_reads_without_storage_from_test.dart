// test/contracts/exercise_media_reads_without_storage_from_test.dart
//
// Batch M2a (plan Tasks 6 and 9, mutations v and w): PRESENCE-ONLY source pins over the animation files (comments stripped first).
//   [v] none of them reads the bucket through the Supabase storage client or the `http` package: the ONE route is the Dio client
//       (`exercise_media_client.dart`, G2). Forbidden: `storage.from`, `.storage.`, `bucket:`, `destinationBucket:`, `package:http`.
//       (A lib file that names the bucket through `storage.from` also trips delete_account_purges_all_user_buckets_test.dart.)
//   [w] none of them gates on the subscription (C7, free to every tier): no `.gate(`, no whole word `isPro` (not `isProgress`),
//       no `SubscriptionService`, no `subscriptionServiceProvider`.
// THE SCANNED SET IS PINNED. `_expected` is the full list; a file that is missing, renamed or mistyped FAILS the existence test (a
// skip for an absent file would turn the whole pin into a pass over nothing), and a NEW file in the `exercise_media` directory that
// is not on the list FAILS the completeness test, so adding one is a conscious edit of this list.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_slice.dart';

const _client = 'lib/core/services/exercise_media/exercise_media_client.dart';
const _dir = 'lib/core/services/exercise_media';

const _expected = <String>[
  'lib/core/services/exercise_media/exercise_media.dart',
  _client,
  'lib/core/services/exercise_media/exercise_media_repository.dart',
  'lib/core/services/exercise_media/exercise_media_store.dart',
  'lib/core/services/exercise_media/exercise_media_webp.dart',
  'lib/shared/providers/exercise_media_provider.dart',
  'lib/shared/widgets/exercise_plate/exercise_animation_view.dart',
  'lib/shared/widgets/exercise_plate/exercise_media_resolver.dart',
  'lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart',
  'lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart',
];

Map<String, String> _stripped() => <String, String>{
      for (final p in _expected) p: File(p).existsSync() ? stripDartComments(File(p).readAsStringSync()) : '',
    };

void main() {
  final stripped = _stripped();

  test('every expected file exists and is not empty (a missing path FAILS, it is never skipped)', () {
    final problems = <String>[
      for (final p in _expected)
        if (!File(p).existsSync())
          '$p does not exist'
        else if ((stripped[p] ?? '').trim().isEmpty)
          '$p is empty after stripping comments',
    ];
    expect(problems, isEmpty);
  });

  test('completeness: the exercise_media directory holds no Dart file that is not on the list', () {
    final onDisk = Directory(_dir)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .toSet();
    expect(onDisk.difference(_expected.toSet()), isEmpty);
    expect(_expected.where((p) => p.startsWith('$_dir/')).toSet().difference(onDisk), isEmpty);
  });

  test('positive control: the client file was scanned and really builds the one route', () {
    expect(stripped.keys, contains(_client));
    expect(stripped[_client], contains('/storage/v1/object/authenticated/exercise-media/'));
  });

  test('[v] no animation file reads the bucket through storage.from, .storage., bucket: or package:http', () {
    const forbidden = ['storage.from', '.storage.', 'bucket:', 'destinationBucket:', 'package:http'];
    final hits = <String>[
      for (final e in stripped.entries)
        for (final f in forbidden)
          if (e.value.contains(f)) '${e.key} contains "$f"',
    ];
    expect(hits, isEmpty);
  });

  test('[w] no animation file gates on the subscription (C7: free to every tier)', () {
    final patterns = <String, RegExp>{
      '.gate(': RegExp(r'\.gate\('),
      'isPro': RegExp(r'\bisPro\b'),
      'SubscriptionService': RegExp(r'SubscriptionService'),
      'subscriptionServiceProvider': RegExp(r'subscriptionServiceProvider'),
    };
    final hits = <String>[
      for (final e in stripped.entries)
        for (final p in patterns.entries)
          if (p.value.hasMatch(e.value)) '${e.key} uses ${p.key}',
    ];
    expect(hits, isEmpty);
  });
}
