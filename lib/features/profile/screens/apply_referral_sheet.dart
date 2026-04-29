import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class ApplyReferralSheet extends ConsumerStatefulWidget {
  const ApplyReferralSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ApplyReferralSheet(),
    );
  }

  @override
  ConsumerState<ApplyReferralSheet> createState() =>
      _ApplyReferralSheetState();
}

class _ApplyReferralSheetState extends ConsumerState<ApplyReferralSheet> {
  final _controller = TextEditingController();
  String _statusMessage = '';
  bool _statusIsError = false;
  bool _submitting = false;

  static final RegExp _format = RegExp(r'^AVYA-[A-Z0-9]{8}$');

  bool get _isValidFormat => _format.hasMatch(_controller.text.trim());

  void _onChange(String value) {
    setState(() {
      if (value.isEmpty) {
        _statusMessage = '';
      } else if (!_isValidFormat) {
        _statusMessage = 'Codes look like AVYA-XXXXXXXX.';
        _statusIsError = true;
      } else {
        _statusMessage = '';
      }
    });
  }

  Future<void> _submit() async {
    if (!_isValidFormat || _submitting) return;
    setState(() {
      _submitting = true;
      _statusMessage = '';
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'redeem-referral',
        body: {'code': _controller.text.trim()},
      );
      final body = response.data as Map?;
      if (response.status == 200) {
        await SubscriptionService.instance.verifyFromServer();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _statusMessage = (body?['error'] as String?) ??
              'Could not apply that code. Please try again.';
          _statusIsError = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Network error. Try again in a moment.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Apply Referral Code',
                  style: AppTypography.titleL.copyWith(fontSize: 20),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textDim),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(width: 60, height: 1, color: AppColors.accent),
            const SizedBox(height: 20),
            Text(
              "We'll apply this within 7 days of your signup.",
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('apply-referral-input'),
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: AppTypography.mono.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'AVYA-XXXXXXXX',
                hintStyle: AppTypography.mono.copyWith(
                  color: AppColors.textGhost,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
              onChanged: _onChange,
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: AppTypography.bodyS.copyWith(
                  color: _statusIsError ? AppColors.bad : AppColors.ok,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isValidFormat && !_submitting ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  shape: const StadiumBorder(),
                  disabledBackgroundColor: AppColors.input,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'APPLY CODE  →',
                        style: AppTypography.mono.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
