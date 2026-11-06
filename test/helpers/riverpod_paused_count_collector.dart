import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Riverpod 3.2.1 raises `actualPausedCount == expectedPausedCount` when an
/// invalidated provider resumes under `TickerMode(false)` (upstream, OI-378).
/// It reports through the zone captured when the container is built, so the
/// container is built in a zone whose handler keeps ONLY that assertion and
/// forwards every other error.
bool isPausedCountAssertion(Object e) =>
    '$e'.contains('actualPausedCount == expectedPausedCount');

void Function(Object, StackTrace) pausedCountHandler(
  List<Object> paused,
  void Function(Object, StackTrace) forward,
) {
  return (e, st) {
    if (isPausedCountAssertion(e)) {
      paused.add(e);
    } else {
      forward(e, st);
    }
  };
}

ProviderContainer containerCollectingPausedCount(
  List<Object> paused,
  List<Override> overrides,
) {
  final testZone = Zone.current;
  late ProviderContainer c;
  runZonedGuarded(() {
    c = ProviderContainer(overrides: overrides);
  }, pausedCountHandler(paused, testZone.handleUncaughtError));
  return c;
}
