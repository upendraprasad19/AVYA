@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_test_helper.dart';

/// Layer 3: pgvector / semantic memory tests.
///
/// Tests the memory_embeddings table and match_memories RPC function
/// using synthetic 768-dimensional vectors (zero API cost — no Gemini
/// embedding calls needed).
///
/// Run: flutter test test/edge_functions/pgvector_test.dart \
///        --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Delegates to the helper's FOUR-input predicate rather than checking url +
  // anonKey locally. This file's own two-value gate was the hole: with the
  // email and password now environment-driven, a run missing either would have
  // fallen through to a live `signInWithPassword(email: '', password: '')`
  // instead of skipping — failing with the exact error a WRONG password gives.
  if (!SupabaseTestHelper.hasCredentials) {
    test('SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD '
        'not all set', () {});
    return;
  }

  late SupabaseClient client;
  late String userId;

  /// Whether `setUpAll` got all the way through sign-in.
  ///
  /// Both fields above are `late`. When `setUpAll` fails — which it does today,
  /// because the QA account does not exist — they are never assigned, and
  /// `tearDownAll` touching them throws `LateInitializationError`. That error
  /// then REPLACES the real one in the output, so triage starts from a symptom
  /// that has nothing to do with the cause (OI-115, "also in scope" bullet 3).
  var setUpSucceeded = false;

  /// Generates a synthetic 768-dim vector. [seed] controls the direction.
  List<double> syntheticVector(int seed, {double magnitude = 1.0}) {
    final rng = Random(seed);
    final vec = List.generate(768, (_) => rng.nextDouble() * 2 - 1);
    // Normalize to unit length then scale
    final norm = sqrt(vec.fold<double>(0, (sum, v) => sum + v * v));
    return vec.map((v) => (v / norm) * magnitude).toList();
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // That binding stubs ALL HTTP to a synthetic 400 without opening a
    // socket, which kills these INTEGRATION tests in setUpAll before their
    // first assertion (diagnose 3b7e1c). This file installs the binding
    // itself rather than calling SupabaseTestHelper.init(), so it must undo
    // the stub itself too — the original fix reached only test/supabase/.
    SupabaseTestHelper.restoreRealHttp();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getAll') return <String, dynamic>{};
      if (call.method == 'setBool' || call.method == 'setString' || call.method == 'remove') return true;
      return null;
    });

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: anonKey,
    );
    client = Supabase.instance.client;

    final response = await client.auth.signInWithPassword(
      email: SupabaseTestHelper.testEmail,
      password: SupabaseTestHelper.testPassword,
    );
    userId = response.user!.id;
    setUpSucceeded = true;
  });

  setUp(() async {
    if (!setUpSucceeded) return;
    // OUTSIDE the try/catch: `catch (_)` would swallow the guard's StateError
    // and turn a refusal to delete into a silent skip — the delete would look
    // like it simply found no rows. This file deletes OUTSIDE
    // SupabaseTestHelper.cleanup(), so it needs its own call to the same guard.
    // signedInId and targetId are the same value here because this file signs
    // in directly rather than through the helper; the membership check against
    // qaUserIds is what carries the protection on this path.
    SupabaseTestHelper.assertDisposableTarget(
        signedInId: userId, targetId: userId);
    try {
      await client.from('memory_embeddings').delete().eq('user_id', userId);
    } catch (_) {}
  });

  tearDownAll(() async {
    // Guarded: on a failed setUpAll neither `client` nor `userId` is assigned,
    // and touching them here would raise LateInitializationError over the top
    // of the real failure.
    if (!setUpSucceeded) return;
    SupabaseTestHelper.assertDisposableTarget(
        signedInId: userId, targetId: userId);
    try {
      await client.from('memory_embeddings').delete().eq('user_id', userId);
    } catch (_) {}
    await client.auth.signOut();
  });

  group('pgvector — Memory Storage', () {
    // T20: match_memories returns empty for user with no memories
    test('T20: match_memories returns empty when no memories exist', () async {
      final queryVec = syntheticVector(42);

      try {
        final results = await client.rpc('match_memories', params: {
          'p_user_id': userId,
          'p_query_embedding': queryVec.toString(),
          'p_match_count': 5,
          'p_similarity_threshold': 0.65,
        });

        expect(results, isA<List>());
        expect((results as List), isEmpty,
            reason: 'No memories should exist for clean user');
      } catch (e) {
        // If match_memories RPC doesn't exist, skip gracefully
        if (e.toString().contains('function') ||
            e.toString().contains('does not exist')) {
          markTestSkipped('match_memories RPC not deployed');
        } else {
          rethrow;
        }
      }
    });

    // T21: Insert a memory embedding
    test('T21: can insert memory embedding into memory_embeddings', () async {
      final embedding = syntheticVector(100);

      try {
        await client.from('memory_embeddings').insert({
          'user_id': userId,
          'embedding': embedding.toString(),
          'content': 'User prefers morning workouts before 7 AM',
          'source_type': 'conversation',
          'metadata': {'session_date': '2026-04-03'},
        });

        // Verify insertion
        final rows = await client
            .from('memory_embeddings')
            .select()
            .eq('user_id', userId);
        expect(rows, isNotEmpty, reason: 'Memory should be inserted');
        expect(rows.first['content'],
            'User prefers morning workouts before 7 AM');
        expect(rows.first['source_type'], 'conversation');
      } catch (e) {
        if (e.toString().contains('relation') ||
            e.toString().contains('does not exist')) {
          markTestSkipped('memory_embeddings table not deployed');
        } else {
          rethrow;
        }
      }
    });

    // T22: Retrieve similar memories via match_memories
    test('T22: match_memories retrieves similar embeddings', () async {
      final embedding = syntheticVector(200);

      try {
        // Insert a memory
        await client.from('memory_embeddings').insert({
          'user_id': userId,
          'embedding': embedding.toString(),
          'content': 'User does 4-day push/pull/legs split',
          'source_type': 'coaching_note',
          'metadata': {},
        });

        // Query with a very similar vector (same seed = identical)
        final results = await client.rpc('match_memories', params: {
          'p_user_id': userId,
          'p_query_embedding': embedding.toString(),
          'p_match_count': 5,
          'p_similarity_threshold': 0.65,
        });

        expect(results, isA<List>());
        final list = results as List;
        expect(list, isNotEmpty,
            reason: 'Same vector should match with high similarity');
        expect((list.first as Map)['content'], contains('push/pull/legs'));
      } catch (e) {
        if (e.toString().contains('function') ||
            e.toString().contains('does not exist')) {
          markTestSkipped('match_memories RPC not deployed');
        } else {
          rethrow;
        }
      }
    });

    // T23: Threshold filter — orthogonal vector returns empty
    test('T23: orthogonal vector returns no matches (below threshold)',
        () async {
      final embeddingSeed100 = syntheticVector(100);
      final embeddingSeed999 = syntheticVector(999);

      try {
        // Insert a memory with seed=100
        await client.from('memory_embeddings').insert({
          'user_id': userId,
          'embedding': embeddingSeed100.toString(),
          'content': 'User dislikes cardio',
          'source_type': 'conversation',
          'metadata': {},
        });

        // Query with a very different vector (seed=999)
        // Due to random orthogonality, cosine similarity should be near 0
        final results = await client.rpc('match_memories', params: {
          'p_user_id': userId,
          'p_query_embedding': embeddingSeed999.toString(),
          'p_match_count': 5,
          'p_similarity_threshold': 0.65,
        });

        expect(results, isA<List>());
        // With high threshold (0.65) and random vectors, no match expected
        final list = results as List;
        expect(list, isEmpty,
            reason:
                'Random orthogonal vector should not match (similarity < 0.65)');
      } catch (e) {
        if (e.toString().contains('function') ||
            e.toString().contains('does not exist')) {
          markTestSkipped('match_memories RPC not deployed');
        } else {
          rethrow;
        }
      }
    });
  });
}
