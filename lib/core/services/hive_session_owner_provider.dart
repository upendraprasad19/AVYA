import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hive_user_session.dart';

/// Riverpod wrapper around [HiveUserSession.currentOwnerListenable].
///
/// Returns the current Hive owner's full user.id, or `null` when no
/// user-scoped boxes are open (cold start before sign-in, post-sign-out
/// before next sign-in).
///
/// Consumers watching this rebuild automatically when the listenable
/// fires (i.e. when `openForUser` or `closeAll` finishes mutating
/// `_currentOwnerFullId`).
///
/// Used by `authUserIdTokenProvider` to gate on agreement between
/// Supabase auth and Hive box owner. See APK Test #15.4 / B1 Layer B.
final hiveSessionOwnerProvider = Provider<String?>((ref) {
  final notifier = HiveUserSession.currentOwnerListenable;
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  return notifier.value;
});
