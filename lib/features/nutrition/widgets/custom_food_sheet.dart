import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../providers/nutrition_provider.dart';

/// Bottom sheet for adding a custom food item.
/// Saves to customBox + syncs to Supabase (background).
void showCustomFoodSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CustomFoodSheet(),
  );
}

class _CustomFoodSheet extends ConsumerStatefulWidget {
  const _CustomFoodSheet();

  @override
  ConsumerState<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends ConsumerState<_CustomFoodSheet> {
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final _servingDescController = TextEditingController(text: '1 serving');
  final _servingGController = TextEditingController(text: '100');

  bool _shareWithCommunity = false;

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      (double.tryParse(_caloriesController.text) ?? 0) > 0;

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    _servingDescController.dispose();
    _servingGController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: Row(
              children: [
                Text(
                  'Add Custom Food',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                _buildField('Food Name *', _nameController,
                    hint: 'e.g. Homemade Dal Makhani'),
                const SizedBox(height: 12),

                Text(
                  'NUTRITION PER 100g',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                        child: _buildNumberField(
                            'Calories *', _caloriesController, 'kcal')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildNumberField(
                            'Protein', _proteinController, 'g')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildNumberField(
                            'Carbs', _carbsController, 'g')),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            _buildNumberField('Fat', _fatController, 'g')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildNumberField(
                            'Fiber', _fiberController, 'g')),
                    const SizedBox(width: 8),
                    const Expanded(child: SizedBox()),
                  ],
                ),

                const SizedBox(height: 16),

                Text(
                  'STANDARD SERVING',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildField(
                            'Description', _servingDescController,
                            hint: '1 bowl')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildNumberField(
                            'Weight', _servingGController, 'g')),
                  ],
                ),
              ],
            ),
          ),

          // Share with community toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Share with AVYA community',
                    style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                Switch(
                  value: _shareWithCommunity,
                  onChanged: (v) => setState(() => _shareWithCommunity = v),
                  activeThumbColor: AppColors.accent,
                  activeTrackColor: AppColors.accent.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Save button
          Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                8,
                AppSpacing.screenPadding,
                16 + bottomInset),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValid ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  disabledBackgroundColor: AppColors.input,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: Text(
                  'Save Custom Food',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _isValid ? Colors.black : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final calories = double.tryParse(_caloriesController.text) ?? 0;
    final protein = double.tryParse(_proteinController.text) ?? 0;
    final carbs = double.tryParse(_carbsController.text) ?? 0;
    final fat = double.tryParse(_fatController.text) ?? 0;
    final fiber = double.tryParse(_fiberController.text) ?? 0;

    // Range validation — prevents nonsensical data from reaching Hive/Supabase.
    if (calories < 0.1 || calories > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Calories must be 0.1–2000 kcal per 100g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    if (protein < 0 || protein > 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Protein must be 0–100 g per 100g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    if (carbs < 0 || carbs > 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Carbs must be 0–100 g per 100g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    if (fat < 0 || fat > 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fat must be 0–100 g per 100g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    if (fiber < 0 || fiber > 50) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fiber must be 0–50 g per 100g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }

    final servingG = double.tryParse(_servingGController.text) ?? 0;
    if (servingG < 1 || servingG > 10000) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Serving weight must be 1–10,000 g',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
        backgroundColor: AppColors.red,
      ));
      return;
    }

    ref.read(customFoodProvider.notifier).addCustomFood(
          name: _nameController.text.trim(),
          caloriesPer100g: calories,
          proteinPer100g: protein,
          carbsPer100g: carbs,
          fatPer100g: fat,
          fiberPer100g: fiber,
          servingDesc: _servingDescController.text.trim().isEmpty
              ? null
              : _servingDescController.text.trim(),
          servingG: double.tryParse(_servingGController.text),
          submittedToDb: _shareWithCommunity,
        );

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added "${_nameController.text.trim()}" to your foods',
          style: GoogleFonts.getFont('DM Sans', fontSize: 13),
        ),
        backgroundColor: AppColors.card,
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                color: AppColors.textDisabled,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberField(
      String label, TextEditingController controller, String suffix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,1}')),
                  ],
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      color: AppColors.textDisabled,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              Text(
                suffix,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
