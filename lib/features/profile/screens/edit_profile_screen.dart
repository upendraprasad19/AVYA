import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import '../providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _targetWeightController;
  late final TextEditingController _cityController;

  String _gender = 'male';
  String _goal = 'general_fitness';
  String _equipment = 'full_gym';
  String _activityLevel = 'moderate'; // kept for backwards-compat read; derived on save
  int _daysPerWeek = 4;
  String _lifestyleActivity = 'desk_job';
  String _dietPreference = 'non_veg';
  List<String> _injuries = ['none'];
  late final TextEditingController _bodyFatController;
  String? _bodyFatAssessedAt;
  bool _isAssessingBf = false;
  bool _isSaving = false;

  static const _goals = {
    'build_muscle': 'Build Muscle',
    'lose_fat': 'Lose Fat',
    'general_fitness': 'General Fitness',
    'strength': 'Build Strength',
  };

  static const _equipmentOptions = {
    'bodyweight': 'Bodyweight Only',
    'home_dumbbells': 'Home Dumbbells',
    'basic_gym': 'Basic Gym',
    'full_gym': 'Full Gym',
  };

  static const _activityLevels = {
    'sedentary': 'Sedentary',
    'light': 'Lightly Active',
    'moderate': 'Moderately Active',
    'active': 'Very Active',
    'very_active': 'Extremely Active',
  };

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);

    _nameController =
        TextEditingController(text: profile['full_name'] as String? ?? '');
    _heightController = TextEditingController(
        text: (profile['height_cm'] as num?)?.toString() ?? '');
    _weightController = TextEditingController(
        text: (profile['current_weight_kg'] as num?)?.toString() ?? '');
    _targetWeightController = TextEditingController(
        text: (profile['target_weight_kg'] as num?)?.toString() ?? '');
    _cityController =
        TextEditingController(text: profile['city'] as String? ?? '');

    _gender = (profile['gender'] as String?) ?? 'male';
    _goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
    _equipment = (profile['equipment_access'] as String?) ?? 'full_gym';
    _activityLevel = (profile['activity_level'] as String?) ?? 'moderate';
    _daysPerWeek = (profile['days_per_week'] as int?) ?? 4;
    _lifestyleActivity =
        (profile['lifestyle_activity'] as String?) ?? 'desk_job';
    _dietPreference = (profile['diet_preference'] as String?) ?? 'non_veg';
    final rawInjuries = profile['injuries'];
    if (rawInjuries is List && rawInjuries.isNotEmpty) {
      _injuries = rawInjuries.map((e) => e.toString()).toList();
    } else {
      _injuries = ['none'];
    }
    final bfPercent = profile['body_fat_percent'];
    _bodyFatController = TextEditingController(
      text: bfPercent != null ? bfPercent.toString() : '',
    );
    _bodyFatAssessedAt = profile['body_fat_assessed_at'] as String?;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    _cityController.dispose();
    _bodyFatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/profile'),
        ),
        title: Text(
          'Edit Profile',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(
              'Save',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _isSaving ? AppColors.textDisabled : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              _sectionHeader('Personal Info'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person,
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildGenderSelector(),
              const SizedBox(height: AppSpacing.sectionGap),

              _sectionHeader('Body'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _heightController,
                      label: 'Height (cm)',
                      icon: Icons.height,
                      isNumeric: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.gridGap),
                  Expanded(
                    child: _buildTextField(
                      controller: _weightController,
                      label: 'Weight (kg)',
                      icon: Icons.monitor_weight_outlined,
                      isDecimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildTextField(
                controller: _targetWeightController,
                label: 'Target Weight (kg)',
                icon: Icons.flag,
                isDecimal: true,
              ),
              const SizedBox(height: AppSpacing.sectionGap),

              _sectionHeader('Fitness'),
              const SizedBox(height: 10),
              _buildDropdown(
                label: 'Goal',
                value: _goal,
                options: _goals,
                onChanged: (v) => setState(() => _goal = v!),
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildDropdown(
                label: 'Equipment',
                value: _equipment,
                options: _equipmentOptions,
                onChanged: (v) => setState(() => _equipment = v!),
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildDaysSelector(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildLifestyleSelector(),
              const SizedBox(height: AppSpacing.sectionGap),

              _sectionHeader('Diet & Health'),
              const SizedBox(height: 10),
              _buildDietPreferenceChips(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildInjuriesChips(),
              const SizedBox(height: AppSpacing.sectionGap),

              _sectionHeader('Body Composition'),
              const SizedBox(height: 10),
              _buildBodyFatField(),
              const SizedBox(height: AppSpacing.sectionGap),

              _sectionHeader('Location'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _cityController,
                label: 'City',
                icon: Icons.location_city,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumeric = false,
    bool isDecimal = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : isNumeric
              ? TextInputType.number
              : TextInputType.text,
      inputFormatters: isNumeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : isDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
              : null,
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: AppColors.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Row(
      children: [
        Expanded(
          child: _selectableChip(
            label: 'Male',
            icon: Icons.male,
            isSelected: _gender == 'male',
            onTap: () => setState(() => _gender = 'male'),
          ),
        ),
        const SizedBox(width: AppSpacing.gridGap),
        Expanded(
          child: _selectableChip(
            label: 'Female',
            icon: Icons.female,
            isSelected: _gender == 'female',
            onTap: () => setState(() => _gender = 'female'),
          ),
        ),
      ],
    );
  }

  Widget _selectableChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentTint : AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.row),
          border: Border.all(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required Map<String, String> options,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: options.containsKey(value) ? value : options.keys.first,
      items: options.entries
          .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ))
          .toList(),
      onChanged: onChanged,
      dropdownColor: AppColors.card,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: AppColors.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDaysSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Training Days per Week',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [3, 4, 5, 6].map((days) {
            final isSelected = _daysPerWeek == days;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _daysPerWeek = days),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent : AppColors.input,
                    borderRadius: BorderRadius.circular(AppRadius.row),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : AppColors.border,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$days',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.black
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Lifestyle Activity ───────────────────────────────────────────

  Widget _buildLifestyleSelector() {
    const options = {
      'desk_job': 'Desk Job',
      'lightly_active': 'Lightly Active',
      'very_active_job': 'Very Active Job',
    };
    const subtitles = {
      'desk_job': 'Office / WFH / Student',
      'lightly_active': 'Retail / Teacher / Housework',
      'very_active_job': 'Construction / Delivery / Sports',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Lifestyle (outside gym)',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...options.entries.map((entry) {
          final isSelected = _lifestyleActivity == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _lifestyleActivity = entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentTint : AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.row),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent.withValues(alpha: 0.4)
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitles[entry.key]!,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Diet Preference ──────────────────────────────────────────────

  Widget _buildDietPreferenceChips() {
    const options = {
      'non_veg': 'Non-Veg',
      'vegetarian': 'Vegetarian',
      'vegan': 'Vegan',
      'pescatarian': 'Pescatarian',
      'keto': 'Keto',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Diet Preference',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            final isSelected = _dietPreference == entry.key;
            return GestureDetector(
              onTap: () => setState(() => _dietPreference = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accentTint : AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  entry.value,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Injuries / Areas to Avoid ────────────────────────────────────

  Widget _buildInjuriesChips() {
    const options = [
      'none', 'knee', 'back', 'shoulder', 'hip', 'wrist', 'ankle'
    ];
    const labels = {
      'none': 'No injuries',
      'knee': 'Knee',
      'back': 'Back',
      'shoulder': 'Shoulder',
      'hip': 'Hip',
      'wrist': 'Wrist',
      'ankle': 'Ankle',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Injuries / Areas to Avoid',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = _injuries.contains(option);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (option == 'none') {
                    _injuries = ['none'];
                  } else {
                    _injuries.remove('none');
                    if (isSelected) {
                      _injuries.remove(option);
                      if (_injuries.isEmpty) _injuries = ['none'];
                    } else {
                      _injuries.add(option);
                    }
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (option == 'none'
                          ? AppColors.accentTint
                          : AppColors.red.withValues(alpha: 0.12))
                      : AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isSelected
                        ? (option == 'none'
                            ? AppColors.accent.withValues(alpha: 0.4)
                            : AppColors.red.withValues(alpha: 0.4))
                        : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  labels[option]!,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected
                        ? (option == 'none'
                            ? AppColors.accent
                            : AppColors.red)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Body Fat % ───────────────────────────────────────────────────

  Widget _buildBodyFatField() {
    final hasValue = _bodyFatController.text.isNotEmpty;
    final assessedLabel = _bodyFatAssessedAt != null
        ? 'Last assessed: ${_formatDate(_bodyFatAssessedAt!)}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _bodyFatController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Body Fat % (optional)',
                  labelStyle: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  suffixText: hasValue ? '%' : null,
                  prefixIcon: const Icon(
                    Icons.monitor_heart_outlined,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  filled: true,
                  fillColor: AppColors.input,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.row),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.row),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.row),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // AI assess button (PRO)
            GestureDetector(
              onTap: _isAssessingBf ? null : _assessBodyFat,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.proGoldTint,
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  border: Border.all(
                    color: AppColors.proGold.withValues(alpha: 0.4),
                  ),
                ),
                child: _isAssessingBf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.proGold),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.camera_alt_outlined,
                            size: 16,
                            color: AppColors.proGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AI Assess',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.proGold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        if (assessedLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            assessedLabel,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Used for lean-mass protein targets. AI photo assessment is PRO, once per month.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _assessBodyFat() {
    SubscriptionService.instance.gate(
      'ai_body_composition',
      onPro: _runBfAssessment,
      onFree: () => showPaywallSheet(
        context,
        feature: 'AI Body Composition Assessment',
      ),
    );
  }

  Future<void> _runBfAssessment() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;

    setState(() => _isAssessingBf = true);

    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final profile = ref.read(userProfileProvider);
      final weightKg =
          (profile['current_weight_kg'] as num?)?.toDouble() ?? 70.0;
      final heightCm = (profile['height_cm'] as num?)?.toDouble() ?? 170.0;
      final gender = (profile['gender'] as String?) ?? 'male';
      final dobStr = profile['date_of_birth'] as String? ?? '';
      final dob = DateTime.tryParse(dobStr);
      final age = dob != null ? DateTime.now().year - dob.year : 25;

      final response = await SupabaseService.instance.client.functions.invoke(
        'assess-body-composition',
        body: {
          'image_base64': base64Image,
          'mime_type': kIsWeb ? 'image/jpeg' : 'image/jpeg',
          'weight_kg': weightKg,
          'height_cm': heightCm,
          'gender': gender,
          'age': age,
        },
      );

      if (response.status != 200) {
        final code = response.data?['code'] as String?;
        final err = response.data?['error'] as String? ?? 'Assessment failed';
        if (code == 'pro_required') {
          showPaywallSheet(context, feature: 'AI Body Composition Assessment');
        } else if (code == 'rate_limited') {
          final next = response.data?['next_allowed_at'] as String?;
          _showError(next != null
              ? 'Next assessment available: ${_formatDate(next)}'
              : 'Already assessed this month. Try again in 30 days.');
        } else if (code == 'unsuitable_image') {
          _showError(err);
        } else {
          _showError(err);
        }
        return;
      }

      final bfLow = (response.data!['bf_low'] as num).toDouble();
      final bfHigh = (response.data!['bf_high'] as num).toDouble();
      final bfMid = ((bfLow + bfHigh) / 2).roundToDouble();
      final assessedAt = response.data!['assessed_at'] as String;

      setState(() {
        _bodyFatController.text = bfMid.toStringAsFixed(1);
        _bodyFatAssessedAt = assessedAt;
      });

      // Immediately persist so it's not lost if user closes without saving
      await ref.read(userProfileProvider.notifier).updateProfile({
        'body_fat_percent': bfMid,
        'body_fat_assessed_at': assessedAt,
        'body_fat_range': '${bfLow.round()}-${bfHigh.round()}%',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Body fat estimated: ${bfLow.round()}–${bfHigh.round()}%  (using ${bfMid.toStringAsFixed(1)}%)',
              style: GoogleFonts.getFont('DM Sans', color: Colors.white),
            ),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Assessment failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isAssessingBf = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.getFont('DM Sans')),
        backgroundColor: AppColors.red,
      ),
    );
  }

  Future<void> _save() async {
    // Validate required numeric fields before saving to prevent
    // downstream division-by-zero in BMR/TDEE calculations.
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name.');
      return;
    }

    final height = double.tryParse(_heightController.text);
    if (height == null || height < 100 || height > 250) {
      _showError('Height must be between 100 and 250 cm.');
      return;
    }

    final weight = double.tryParse(_weightController.text);
    if (weight == null || weight < 30 || weight > 300) {
      _showError('Weight must be between 30 and 300 kg.');
      return;
    }

    final targetWeightText = _targetWeightController.text.trim();
    final targetWeight = targetWeightText.isEmpty
        ? 0.0
        : double.tryParse(targetWeightText);
    if (targetWeight == null || targetWeight < 0 || targetWeight > 300) {
      _showError('Target weight must be between 0 and 300 kg.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Derive activity_level from lifestyle + training days (more accurate
      // than the old direct-selection approach).
      final derivedActivityLevel =
          BmrCalculator.resolveActivityLevel(_lifestyleActivity, _daysPerWeek);

      final updates = <String, dynamic>{
        'full_name': name,
        'gender': _gender,
        'height_cm': height,
        'current_weight_kg': weight,
        'target_weight_kg': targetWeight,
        'primary_goal': _goal,
        'equipment_access': _equipment,
        'lifestyle_activity': _lifestyleActivity,
        'activity_level': derivedActivityLevel,
        'days_per_week': _daysPerWeek,
        'diet_preference': _dietPreference,
        'injuries': _injuries,
        'city': _cityController.text.trim(),
        if (_bodyFatController.text.isNotEmpty)
          'body_fat_percent': double.tryParse(_bodyFatController.text),
        if (_bodyFatAssessedAt != null)
          'body_fat_assessed_at': _bodyFatAssessedAt,
      };

      await ref.read(userProfileProvider.notifier).updateProfile(updates);
      await ref.read(userProfileProvider.notifier).recalculateTargets();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile saved',
              style: GoogleFonts.getFont('DM Sans'),
            ),
            backgroundColor: AppColors.green,
          ),
        );
        context.go('/profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save: $e',
              style: GoogleFonts.getFont('DM Sans'),
            ),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
