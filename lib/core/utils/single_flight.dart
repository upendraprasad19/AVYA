import 'package:flutter/foundation.dart';

/// One save at a time per key (OI-493 Landing B, B7).
///
/// Founder decision F4: the same meal logged twice is two entries, so a
/// double tap on a log control would now add twice. [run] returns null WITHOUT
/// calling `op` while the same [key] is already in flight; the key is released
/// in `finally`, so a tap after the first save finishes (or fails, or throws)
/// runs again.
///
/// The set is STATIC so a widget remounted mid-save (a sheet tab switch, a
/// chat rebuild) shares it: widget-state flags such as `_saving` start fresh on
/// a remount. Keys name the write identity (food, grams, slot), never just the
/// control, so two different foods tapped quickly both log.
class SingleFlight {
  SingleFlight._();

  static final Set<String> _inFlight = <String>{};

  @visibleForTesting
  static bool isInFlight(String key) => _inFlight.contains(key);

  /// Runs [op] unless [key] is already in flight; returns its result, or null
  /// when skipped. A caller must treat null as "already saving": no toast, no
  /// haptic, no success callback.
  static Future<T?> run<T>(String key, Future<T> Function() op) async {
    if (!_inFlight.add(key)) return null;
    try {
      return await op();
    } finally {
      _inFlight.remove(key);
    }
  }
}
