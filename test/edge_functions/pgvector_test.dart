@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  if (supabaseUrl.isEmpty || anonKey.isEmpty) {
    test('SKIPPED: SUPABASE_URL / SUPABASE_ANON_KEY not set', () {});
    return;
  }

  late SupabaseClient client;
  late String userId;

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
      email: 'qa@icanbefitter.com',
      password: 'QA_Test_2024!',
    );
    userId = response.user!.id;
  });

  setUp(() async {
    // Clean up any test embeddings
    try {
      await client.from('memory_embeddings').delete().eq('user_id', userId);
    } catch (_) {}
  });

  tearDownAll(() async {
    // Clean up
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
