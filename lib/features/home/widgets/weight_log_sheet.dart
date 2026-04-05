import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import '../providers/home_provider.dart';
import '../../profile/providers/profile_provider.dart';

/// Bottom sheet for quickly logging today's weight from the home screen.
class WeightLogSheet extends ConsumerStatefulWidget {
  const WeightLogSheet({super.key});

  @override
  ConsumerState<WeightLogSheet> createState() => _WeightLogSheetState();
}

class _WeightLogSheetState extends ConsumerState<WeightLogSheet> {
  late TextEditingController _controller;
  double _weight = 70.0;
  String? _lastDate;
  double? _lastWeight;

  @override
  void initState() {
    super.initState();
    _loadLastWeightData();
    _controller = TextEditingController(text: _weight.toStringAsFixed(1));
  }

  /// Read last weight from Hive — sets _weight, _lastWeight, _lastDate
  /// but does NOT touch _controller (not yet initialized).
  void _loadLastWeightData() {
    final healthBox = HiveService.instance.healthBox;
    String latestDate = '';
    double? latestWeight;

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'weight_log' || log['weight_kg'] != null) {
        final date = log['date'] as String? ?? '';
        final w = (log['weight_kg'] as num?)?.toDouble();
        if (w != null && date.compareTo(latestDate) > 0) {
          latestDate = date;
          latestWeight = w;
        }
      }
    }

    final userBox = HiveService.instance.userBox;
    final profile = userBox.get('profile');
    if (profile is Map) {
      final profileWeight =
          (profile['current_weight_kg'] as num?)?.toDouble();
      if (latestWeight == null && profileWeight != null) {
        latestWeight = profileWeight;
      }
    }

    if (latestWeight != null) {
      _weight = latestWeight;
      _lastWeight = latestWeight;
      _lastDate = latestDate.isNotEmpty ? latestDate : null;
    }
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _increment(double delta) {
    setState(() {
      _weight = ((_weight + delta) * 10).roundToDouble() / 10;
      if (_weight < 20) _weight = 20;
      if (_weight > 300) _weight = 300;
      _controller.text = _weight.toStringAsFixed(1);
    });
  }

  void _save() {
    // Parse from text field in case user typed manually
    final parsed = double.tryParse(_controller.text);
    if (parsed != null && parsed >= 20 && parsed <= 300) {
      _weight = parsed;
    }

    ref.read(weightLogNotifierProvider.notifier).logWeight(_weight);
    ref.invalidate(weightHistoryProvider);
    ref.invalidate(todayWeightLoggedProvider);
    ref.invalidate(userProfileProvider);

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Weight logged \u2713',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        12,
        AppSpacing.screenPadding,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'LOG WEIGHT',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),

          // Last logged
          if (_lastWeight != null)
            Text(
              'Last: ${_lastWeight!.toStringAsFixed(1)} kg${_lastDate != null ? ' on ${_formatDate(_lastDate!)}' : ''}',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 20),

          // Weight input row: [-] [weight] [+]
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus button
              _RoundButton(
                icon: Icons.remove,
                onTap: () => _increment(-0.1),
              ),
              const SizedBox(width: 16),

              // Weight display / input
              SizedBox(
                width: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    IntrinsicWidth(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d{0,3}\.?\d{0,1}')),
                        ],
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: AppColors.accent,
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            _weight = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'kg',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Plus button
              _RoundButton(
                icon: Icons.add,
                onTap: () => _increment(0.1),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                elevation: 0,
              ),
              child: Text(
                'SAVE',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    // dateStr is YYYY-MM-DD
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return '${months[month - 1]} $day';
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.bg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}
