// test/helpers/fake_exercise_media_repository.dart
//
// A stand-in for the exercise-animation repository (Batch M2b). The active-workout harness overrides
// `exerciseMediaRepositoryProvider` with it so a seeded media row never reaches the real Dio client.
// `ensure` answers [bytes] (null by default: the view then keeps the bundled still), and the calls are
// counted, so a test can say how many files a card asked for.
import 'dart:typed_data';

import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';

class FakeExerciseMediaRepository implements ExerciseMediaRepository {
  FakeExerciseMediaRepository({this.bytes});

  /// What `ensure` returns. A decodable image (`kTinyPng`) makes the view hold bytes, which is what puts a
  /// frozen view's PLAY button on screen.
  Uint8List? bytes;

  /// Object names asked for, in order.
  final List<String> ensured = <String>[];
  final List<String> evicted = <String>[];

  @override
  Future<Uint8List?> ensure(ExerciseMedia media) {
    ensured.add(media.objectName);
    return Future<Uint8List?>.value(bytes);
  }

  @override
  Future<void> evict(ExerciseMedia media) async {
    evicted.add(media.objectName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
