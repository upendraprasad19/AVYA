import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';

/// Thrown when the signed-in account is not on the `ADMIN_USER_IDS`
/// allowlist. The server is the real gate (admin-dashboard-data's admin-gate
/// logic, pinned by supabase/functions/admin-dashboard-data/index_test.ts) —
/// this exception exists purely so the UI can show a clean "not authorized"
/// state instead of a generic error banner.
class AdminNotAuthorizedException implements Exception {
  const AdminNotAuthorizedException();
}

/// Wraps the `admin-dashboard-data` Edge Function call. This is the ONE
/// Hive-first exception in this codebase (root CLAUDE.md §4.4 rule 1) — see
/// lib/features/admin/CLAUDE.md for why: there is no meaningful per-device
/// copy of cross-user aggregate business data to read instead.
class AdminDashboardRepository {
  const AdminDashboardRepository();

  Future<AdminDashboardData> fetch() async {
    try {
      final response =
          await SupabaseService.instance.callFunction('admin-dashboard-data');
      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('admin-dashboard-data returned an empty response');
      }
      return AdminDashboardData.fromJson(data);
    } on FunctionException catch (e) {
      if (e.status == 403) {
        throw const AdminNotAuthorizedException();
      }
      rethrow;
    }
  }
}
