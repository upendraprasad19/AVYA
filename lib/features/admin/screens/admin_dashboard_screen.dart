import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/admin/providers/admin_dashboard_provider.dart';
import 'package:icanbefitter/features/admin/repositories/admin_dashboard_repository.dart';
import 'package:icanbefitter/features/admin/widgets/engagement_tab.dart';
import 'package:icanbefitter/features/admin/widgets/growth_tab.dart';
import 'package:icanbefitter/features/admin/widgets/ops_health_tab.dart';
import 'package:icanbefitter/features/admin/widgets/revenue_tab.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Founder-only business-metrics dashboard. Reachable ONLY via direct URL
/// navigation to `/admin` on the web build — no bottom-nav entry, no link
/// anywhere else in the app. Real access control is server-side
/// (admin-dashboard-data's ADMIN_USER_IDS gate); a non-founder account
/// lands on the "not authorized" EmptyState below, not a crash.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(adminDashboardProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              const WardLetterhead(
                eyebrow: 'FOUNDER ONLY',
                title: 'Business Dashboard',
                dividerStyle: WardDivider.single,
                padding: EdgeInsets.fromLTRB(22, 24, 22, 0),
              ),
              TabBar(
                isScrollable: true,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.textDim,
                labelStyle:
                    AppTypography.bodyM.copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Growth'),
                  Tab(text: 'Engagement'),
                  Tab(text: 'Revenue'),
                  Tab(text: 'Ops Health'),
                ],
              ),
              Expanded(
                child: dataAsync.when(
                  loading: () => const ScreenLoadingSkeleton(),
                  error: (err, st) => _AdminErrorBody(
                    error: err,
                    onRetry: () => ref.invalidate(adminDashboardProvider),
                  ),
                  data: (data) => TabBarView(
                    children: [
                      GrowthTab(data: data),
                      EngagementTab(data: data),
                      RevenueTab(data: data),
                      OpsHealthTab(data: data),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminErrorBody extends StatelessWidget {
  const _AdminErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.all(18.0);
    if (error is AdminNotAuthorizedException) {
      return Padding(
        padding: padding,
        child: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Not authorized',
          subtitle: 'This account is not on the admin allowlist.',
        ),
      );
    }
    return Padding(
      padding: padding,
      child: ErrorState(
        title: 'Could not load dashboard',
        subtitle: 'Check your connection and try again.',
        onRetry: onRetry,
      ),
    );
  }
}
