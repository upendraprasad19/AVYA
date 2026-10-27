import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/features/admin/repositories/admin_dashboard_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

const _repository = AdminDashboardRepository();

/// Loading/error/data states are the `AsyncValue` this FutureProvider emits —
/// consumed via `.when(...)` in AdminDashboardScreen, per the standard
/// screen contract (root CLAUDE.md §4.4 rule 13). A 403 surfaces as
/// `AdminNotAuthorizedException` inside the error state so the screen can
/// tell "you're not the founder" apart from a transient network failure.
final adminDashboardProvider = FutureProvider<AdminDashboardData>((ref) async {
  ref.watch(authUserIdTokenProvider); // rebuild on auth change
  return _repository.fetch();
});
