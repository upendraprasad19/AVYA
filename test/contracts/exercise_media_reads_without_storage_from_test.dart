// test/contracts/exercise_media_reads_without_storage_from_test.dart
//
// Batch M2a (plan Task 6, mutations v and w): PRESENCE-ONLY source pins over the new animation files (comments stripped first).
//   [v] none of them reads the bucket through the Supabase storage client or the `http` package: the ONE route is the Dio client
//       (`exercise_media_client.dart`, G2). Forbidden: `storage.from`, `.storage.`, `bucket:`, `destinationBucket:`, `package:http`.
//       (A lib file that names the bucket through `storage.from` also trips delete_account_purges_all_user_buckets_test.dart.)
//   [w] none of them gates on the subscription (C7, free to every tier): no `.gate(`, no whole word `isPro` (not `isProgress`),
//       no `SubscriptionService`, no `subscriptionServiceProvider`.
// Files that do not exist yet at this task (the view is Task 9, the provider Task 7) are skipped; Task 10 Step 1 re-runs this with
// all of them present. As a positive control the client file itself must have been scanned.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_slice.dart';

const _client = 'lib/core/services/exercise_media/exercise_media_client.dart';

List<String> _files() {
  final out = <String>[
    ...Directory('lib/core/services/exercise_media')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart')),
    'lib/shared/widgets/exercise_plate/exercise_media_resolver.dart',
    'lib/shared/widgets/exercise_plate/exercise_animation_view.dart',
    'lib/shared/providers/exercise_media_provider.dart',
  ];
  return out.where((p) => File(p).existsSync()).toSet().toList()..sort();
}

void main() {
  final files = _files();
  final stripped = <String, String>{for (final p in files) p: stripDartComments(File(p).readAsStringSync())};

  test('positive control: the client file and the other new files were scanned', () {
    expect(files, contains(_client));
    expect(files, contains('lib/core/services/exercise_media/exercise_media_store.dart'));
    expect(files, contains('lib/core/services/exercise_media/exercise_media_webp.dart'));
    expect(files, contains('lib/shared/widgets/exercise_plate/exercise_media_resolver.dart'));
  });

  test('[v] no new animation file reads the bucket through storage.from, .storage., bucket: or package:http', () {
    const forbidden = ['storage.from', '.storage.', 'bucket:', 'destinationBucket:', 'package:http'];
    final hits = <String>[
      for (final e in stripped.entries)
        for (final f in forbidden)
          if (e.value.contains(f)) '${e.key} contains "$f"',
    ];
    expect(hits, isEmpty);
  });

  test('[w] no new animation file gates on the subscription (C7: free to every tier)', () {
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
