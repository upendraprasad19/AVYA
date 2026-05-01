import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/stat_snapshot_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';

/// Reports row destination — Progress Comparison.
///
/// Lists all `user_stat_snapshots` rows for the current user, newest
/// first. Tap a non-baseline snapshot → bottom sheet showing the diff
/// between that snapshot and the onboarding baseline.
///
/// Top-right "Take Snapshot Now" button → manual snapshot via
/// `StatSnapshotService.snapshotManual()`. MVP: no measurements UI yet
/// (Test #7 enhancement); fires with empty measurements + photos.
///
/// APK Test #6 / Plan F-11.
class ProgressComparisonScreen extends ConsumerStatefulWidget {
  const ProgressComparisonScreen({super.key});

  @override
  ConsumerState<ProgressComparisonScreen> createState() =>
      _ProgressComparisonScreenState();
}

class _ProgressComparisonScreenState
    extends ConsumerState<ProgressComparisonScreen> {
  List<UserStatSnapshot>? _snapshots;
  UserStatSnapshot? _baseline;
  bool _loading = true;
  bool _takingSnapshot = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await StatSnapshotService.instance.listAll();
      final base = await StatSnapshotService.instance.baseline();
      if (!mounted) return;
      setState(() {
        _snapshots = all;
        _baseline = base;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _takeSnapshotNow() async {
    if (_takingSnapshot) return;
    setState(() => _takingSnapshot = true);
    final result = await StatSnapshotService.instance.snapshotManual();
    if (!mounted) return;
    setState(() => _takingSnapshot = false);
    final messenger = ScaffoldMessenger.of(context);
    if (result.success) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Snapshot captured'),
        duration: Duration(seconds: 2),
      ));
      await _load();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Snapshot failed: ${result.errorMessage ?? 'unknown'}'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  void _openDiff(UserStatSnapshot target) {
    final base = _baseline;
    if (base == null) return;
    if (identical(base, target)) {
      // Tapped the baseline itself — show the baseline as a single row.
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.card,
        showDragHandle: true,
        builder: (_) => _BaselineSheet(snapshot: base),
      );
      return;
    }
    final diff = StatSnapshotService.instance.diff(base, target);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DiffSheet(diff: diff),
    );
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
              'DOSSIER · LEDGER',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Progress comparison', style: AppTypography.h3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _takingSnapshot ? null : _takeSnapshotNow,
            child: _takingSnapshot
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : Text(
                    'Take Snapshot',
                    style: AppTypography.bodyM.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Text(
            'Failed to load snapshots.\n${_error!}',
            textAlign: TextAlign.center,
            style: AppTypography.bodyM.copyWith(color: AppColors.textDim),
          ),
        ),
      );
    }
    final snaps = _snapshots ?? const [];
    if (snaps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No snapshots yet',
                style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Your starting baseline is captured at onboarding. '
                'Promotion snapshots fire automatically as you climb the rank ladder. '
                'You can also tap "Take Snapshot" above to capture a manual checkpoint.',
                textAlign: TextAlign.center,
                style:
                    AppTypography.bodyM.copyWith(color: AppColors.textDim),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.sectionGap,
        ),
        itemCount: snaps.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.inlineGap),
        itemBuilder: (context, i) {
          final s = snaps[i];
          return _SnapshotTile(
            snapshot: s,
            isBaseline: identical(s, _baseline),
            onTap: () => _openDiff(s),
          );
        },
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.snapshot,
    required this.isBaseline,
    required this.onTap,
  });

  final UserStatSnapshot snapshot;
  final bool isBaseline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final src = snapshot.source.toUpperCase();
    final dateText = _fmtDate(snapshot.snapshotAt);
    final w = snapshot.weightKg;
    final subtitle = StringBuffer();
    if (w != null) subtitle.write('${w.toStringAsFixed(1)} kg');
    if (snapshot.rankAtSnapshot != null) {
      if (subtitle.isNotEmpty) subtitle.write(' · ');
      subtitle.write('Rank ${snapshot.rankAtSnapshot}');
    }
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            border: Border.all(
              color: isBaseline
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          src,
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 1.6,
                          ),
                        ),
                        if (isBaseline) ...[
                          const SizedBox(width: 8),
                          Text(
                            'BASELINE',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textDim,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(dateText, style: AppTypography.titleS),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle.toString(),
                        style: AppTypography.bodyS
                            .copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _BaselineSheet extends StatelessWidget {
  const _BaselineSheet({required this.snapshot});
  final UserStatSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding, 0, AppSpacing.screenPadding, AppSpacing.screenPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BASELINE',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text('Starting stats', style: AppTypography.h3),
          const SizedBox(height: 16),
          _StatLine(label: 'Weight', value: _fmtKg(snapshot.weightKg)),
          _StatLine(label: 'Body fat', value: _fmtPct(snapshot.bodyFatPct)),
          _StatLine(
              label: 'Height', value: _fmtCm(snapshot.heightCm)),
          _StatLine(
              label: 'Goal', value: snapshot.primaryGoal ?? '—'),
        ],
      ),
    );
  }
}

class _DiffSheet extends StatelessWidget {
  const _DiffSheet({required this.diff});
  final StatSnapshotDiff diff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding, 0, AppSpacing.screenPadding, AppSpacing.screenPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPARISON',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(diff.shortDescription(), style: AppTypography.h3),
          const SizedBox(height: 16),
          _DiffLine(
            label: 'Weight',
            from: _fmtKg(diff.from.weightKg),
            to: _fmtKg(diff.to.weightKg),
            delta: diff.weightDeltaKg == null
                ? null
                : '${diff.weightDeltaKg! >= 0 ? '+' : ''}${diff.weightDeltaKg!.toStringAsFixed(1)} kg',
            isPositiveDeltaGood: false,
            deltaSign: diff.weightDeltaKg,
          ),
          _DiffLine(
            label: 'Body fat',
            from: _fmtPct(diff.from.bodyFatPct),
            to: _fmtPct(diff.to.bodyFatPct),
            delta: diff.bodyFatDelta == null
                ? null
                : '${diff.bodyFatDelta! >= 0 ? '+' : ''}${diff.bodyFatDelta!.toStringAsFixed(1)}%',
            isPositiveDeltaGood: false,
            deltaSign: diff.bodyFatDelta,
          ),
          _DiffLine(
            label: 'Avg calories',
            from: diff.from.avgCalories7d?.toString() ?? '—',
            to: diff.to.avgCalories7d?.toString() ?? '—',
            delta: diff.caloriesDelta == null
                ? null
                : '${diff.caloriesDelta! >= 0 ? '+' : ''}${diff.caloriesDelta}',
            isPositiveDeltaGood: true,
            deltaSign: diff.caloriesDelta?.toDouble(),
          ),
          _DiffLine(
            label: 'Avg protein',
            from: diff.from.avgProtein7d?.toString() ?? '—',
            to: diff.to.avgProtein7d?.toString() ?? '—',
            delta: diff.proteinDelta == null
                ? null
                : '${diff.proteinDelta! >= 0 ? '+' : ''}${diff.proteinDelta}',
            isPositiveDeltaGood: true,
            deltaSign: diff.proteinDelta?.toDouble(),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTypography.bodyM.copyWith(color: AppColors.textDim)),
          ),
          Text(value, style: AppTypography.bodyM),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.label,
    required this.from,
    required this.to,
    required this.delta,
    required this.isPositiveDeltaGood,
    required this.deltaSign,
  });

  final String label;
  final String from;
  final String to;
  final String? delta;
  final bool isPositiveDeltaGood;
  final double? deltaSign;

  @override
  Widget build(BuildContext context) {
    Color? deltaColor;
    if (delta != null && deltaSign != null && deltaSign != 0) {
      final positive = deltaSign! > 0;
      final good = positive == isPositiveDeltaGood;
      deltaColor = good ? AppColors.ok : AppColors.bad;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: AppTypography.bodyM.copyWith(color: AppColors.textDim)),
          ),
          Expanded(
            flex: 5,
            child: Text(
              '$from → $to',
              style: AppTypography.bodyM,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              delta ?? '—',
              textAlign: TextAlign.right,
              style: AppTypography.bodyM.copyWith(
                color: deltaColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtKg(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} kg';
String _fmtPct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
String _fmtCm(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)} cm';
