import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/error_state.dart';

/// F9 · "My Submissions" — user-visible view of their own community
/// contributions (custom foods + exercises) with approval status.
///
/// Free for all users — gamification touch ("You've helped N others").
///
/// Reads from `user_custom_foods` and `user_custom_exercises` filtered to
/// the current user. Status derived from `approved_for_library` (exercises)
/// or `approved` (foods). The F18 auto-promotion Edge Function will flip
/// those flags once 10 approvals accumulate.
class MySubmissionsScreen extends ConsumerStatefulWidget {
  const MySubmissionsScreen({super.key});

  @override
  ConsumerState<MySubmissionsScreen> createState() =>
      _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends ConsumerState<MySubmissionsScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      setState(() => _error = 'Sign in to see your submissions.');
      return;
    }
    try {
      final client = SupabaseService.instance.client;
      final foods = await client
          .from('user_custom_foods')
          .select('id, name, submitted_to_db, approved, created_at')
          .eq('user_id', userId)
          .eq('submitted_to_db', true)
          .order('created_at', ascending: false);
      final exercises = await client
          .from('user_custom_exercises')
          .select('id, name, submitted_to_library, approved_for_library, created_at')
          .eq('user_id', userId)
          .eq('submitted_to_library', true)
          .order('created_at', ascending: false);

      final rows = <Map<String, dynamic>>[
        for (final f in foods)
          {
            ...Map<String, dynamic>.from(f as Map),
            'kind': 'food',
            '_approved': (f as Map)['approved'] == true,
          },
        for (final e in exercises)
          {
            ...Map<String, dynamic>.from(e as Map),
            'kind': 'exercise',
            '_approved': (e as Map)['approved_for_library'] == true,
          },
      ];
      rows.sort((a, b) {
        final ca = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(0);
        final cb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(0);
        return cb.compareTo(ca);
      });

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t load submissions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMMUNITY \u00B7 FILINGS',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('My submissions', style: AppTypography.h3),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ErrorState(
        title: 'Couldn\'t load',
        subtitle: _error,
        onRetry: _load,
      );
    }
    if (_rows == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_rows!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text('No submissions yet',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Add a custom food or exercise and tick "Share with community" to contribute.',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final approvedCount =
        _rows!.where((r) => r['_approved'] == true).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        if (approvedCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You\'ve helped $approvedCount ${approvedCount == 1 ? "other user" : "other users"}',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final row in _rows!) _buildRow(row),
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? 'Unknown';
    final kind = row['kind']?.toString() ?? '';
    final approved = row['_approved'] == true;

    final statusColor = approved ? AppColors.green : AppColors.accent;
    final statusLabel = approved ? 'APPROVED' : 'PENDING';
    final subtitle = approved
        ? 'Live in the app for everyone'
        : 'Awaiting community reviews';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              kind == 'food' ? Icons.restaurant : Icons.fitness_center,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 11,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.getFont('DM Sans',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}
