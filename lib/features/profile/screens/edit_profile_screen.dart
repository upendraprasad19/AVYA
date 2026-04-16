import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
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
  late final TextEditingController _phoneController;

  String _gender = 'male';
  String _goal = 'general_fitness';
  String _equipment = 'full_gym';
  int _daysPerWeek = 4;
  String _lifestyleActivity = 'desk_job';
  String _dietPreference = 'non_veg';
  String _pacePreference = 'balanced'; // Bug #24
  int? _sessionDuration; // 30, 45, 60, 90
  String _physiqueFocus = 'balanced'; // balanced, glutes_legs, chest_shoulders_arms, strength
  String _fitnessExperience = 'intermediate'; // beginner, intermediate, advanced
  List<String> _injuries = ['none'];
  late final TextEditingController _bodyFatController;
  String? _bodyFatAssessedAt;
  bool _isAssessingBf = false;
  bool _isSaving = false;
  late bool _isMetric; // true = KG/CM, false = LBS/IN

  // Track original plan-affecting values for rescheduling detection
  late int _originalDaysPerWeek;
  late String _originalGoal;
  late String _originalEquipment;

  // Track original target weight for prediction invalidation (Bug #12)
  late double _originalTargetWeight;

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

  @override
  void initState() {
    super.initState();
    _isMetric = UserRepository.instance.getUnitsMetric();
    final profile = ref.read(userProfileProvider);

    _nameController =
        TextEditingController(text: profile['full_name'] as String? ?? '');

    // Convert height/weight values to the user's preferred units for display.
    // Storage is always metric (cm, kg); we convert on the way in and out.
    final heightCmRaw = (profile['height_cm'] as num?)?.toDouble();
    final weightKgRaw = (profile['current_weight_kg'] as num?)?.toDouble();
    final targetKgRaw = (profile['target_weight_kg'] as num?)?.toDouble();

    _heightController = TextEditingController(
        text: heightCmRaw == null
            ? ''
            : _isMetric
                ? heightCmRaw.toStringAsFixed(0)
                : (heightCmRaw / 2.54).toStringAsFixed(1));
    _weightController = TextEditingController(
        text: weightKgRaw == null
            ? ''
            : _isMetric
                ? weightKgRaw.toStringAsFixed(1)
                : (weightKgRaw * 2.20462).toStringAsFixed(0));
    _targetWeightController = TextEditingController(
        text: targetKgRaw == null
            ? ''
            : _isMetric
                ? targetKgRaw.toStringAsFixed(1)
                : (targetKgRaw * 2.20462).toStringAsFixed(0));

    _cityController =
        TextEditingController(text: profile['city'] as String? ?? '');
    _phoneController =
        TextEditingController(text: profile['phone'] as String? ?? '');

    _gender = (profile['gender'] as String?) ?? 'male';
    _goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
    _equipment = (profile['equipment_access'] as String?) ?? 'full_gym';
    _daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    _lifestyleActivity =
        (profile['lifestyle_activity'] as String?) ?? 'desk_job';
    _dietPreference = (profile['diet_preference'] as String?) ?? 'non_veg';
    _pacePreference = (profile['pace_preference'] as String?) ?? 'balanced'; // Bug #24
    _sessionDuration = profile['session_duration_minutes'] as int?;
    _physiqueFocus = (profile['physique_focus'] as String?) ?? 'balanced';
    _fitnessExperience = (profile['fitness_experience'] as String?) ?? 'intermediate';
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

    // Capture original values for rescheduling detection
    _originalDaysPerWeek = _daysPerWeek;
    _originalGoal = _goal;
    _originalEquipment = _equipment;
    _originalTargetWeight = targetKgRaw ?? 0.0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
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
              _buildEmailField(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildTextField(
                controller: _phoneController,
                label: 'Phone',
                icon: Icons.phone,
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
                      label: _isMetric ? 'Height (cm)' : 'Height (in)',
                      icon: Icons.height,
                      isDecimal: !_isMetric,
                      isNumeric: _isMetric,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.gridGap),
                  Expanded(
                    child: _buildTextField(
                      controller: _weightController,
                      label: _isMetric ? 'Weight (kg)' : 'Weight (lbs)',
                      icon: Icons.monitor_weight_outlined,
                      isDecimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildTextField(
                controller: _targetWeightController,
                label: _isMetric ? 'Target Weight (kg)' : 'Target Weight (lbs)',
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
              const SizedBox(height: AppSpacing.gridGap),
              _buildPaceSelector(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildSessionDurationSelector(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildPhysiqueFocusSelector(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildExperienceSelector(),
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

  Widget _buildEmailField() {
    final email = SupabaseService.instance.currentUser?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.row),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.email_outlined,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isNotEmpty ? email : 'Not set',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            'Used for sign-in',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]
          : isDecimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]')), LengthLimitingTextInputFormatter(5)]
              : [LengthLimitingTextInputFormatter(50)],
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
      initialValue: options.containsKey(value) ? value : options.keys.first,
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

  // ── Goal Pace (Bug #24) ──────────────────────────────────────────

  Widget _buildPaceSelector() {
    const options = {
      'slow': 'Slow',
      'balanced': 'Balanced',
      'aggressive': 'Aggressive',
    };
    const subtitles = {
      'slow': '~0.25%/week — easiest to stick with',
      'balanced': '~0.5%/week — evidence-based standard',
      'aggressive': '~0.75%/week — near upper safe limit',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Goal pace',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...options.entries.map((entry) {
          final isSelected = _pacePreference == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _pacePreference = entry.key),
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

  // ── Session Duration ─────────────────────────────────────────────

  Widget _buildSessionDurationSelector() {
    const options = [30, 45, 60, 90];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Session Duration',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((min) {
            final selected = _sessionDuration == min;
            return GestureDetector(
              onTap: () => setState(() => _sessionDuration = min),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  '$min min',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Physique Focus ───────────────────────────────────────────────

  Widget _buildPhysiqueFocusSelector() {
    const options = <(String, String)>[
      ('balanced', 'Balanced'),
      ('glutes_legs', 'Glutes & Legs'),
      ('chest_shoulders_arms', 'Chest & Shoulders'),
      ('strength', 'Strength'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Physique Focus',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = _physiqueFocus == opt.$1;
            return GestureDetector(
              onTap: () => setState(() => _physiqueFocus = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  opt.$2,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Experience Level ─────────────────────────────────────────────

  Widget _buildExperienceSelector() {
    const options = <(String, String)>[
      ('beginner', 'Beginner'),
      ('intermediate', 'Intermediate'),
      ('advanced', 'Advanced'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Experience Level',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = _fitnessExperience == opt.$1;
            return GestureDetector(
              onTap: () => setState(() => _fitnessExperience = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.input,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  opt.$2,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
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

      if (!mounted) return;
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

    // Parse height — stored in cm, displayed in user's preferred units.
    final heightRaw = double.tryParse(_heightController.text);
    if (_isMetric) {
      if (heightRaw == null || heightRaw < 100 || heightRaw > 250) {
        _showError('Height must be between 100 and 250 cm.');
        return;
      }
    } else {
      if (heightRaw == null || heightRaw < 39.4 || heightRaw > 98.4) {
        _showError('Height must be between 39 and 98 in.');
        return;
      }
    }
    // Always store in cm.
    final height = _isMetric ? heightRaw : heightRaw * 2.54;

    // Parse weight — stored in kg, displayed in user's preferred units.
    final weightRaw = double.tryParse(_weightController.text);
    if (_isMetric) {
      if (weightRaw == null || weightRaw < 30 || weightRaw > 300) {
        _showError('Weight must be between 30 and 300 kg.');
        return;
      }
    } else {
      if (weightRaw == null || weightRaw < 66 || weightRaw > 661) {
        _showError('Weight must be between 66 and 661 lbs.');
        return;
      }
    }
    // Always store in kg.
    final weight = _isMetric ? weightRaw : weightRaw / 2.20462;

    final targetWeightText = _targetWeightController.text.trim();
    final targetWeightRaw = targetWeightText.isEmpty
        ? 0.0
        : double.tryParse(targetWeightText);
    if (targetWeightRaw == null || (_isMetric ? targetWeightRaw > 300 : targetWeightRaw > 661)) {
      _showError(_isMetric
          ? 'Target weight must be between 0 and 300 kg.'
          : 'Target weight must be between 0 and 661 lbs.');
      return;
    }
    // Always store in kg.
    final targetWeight = _isMetric ? targetWeightRaw : targetWeightRaw / 2.20462;

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
        'pace_preference': _pacePreference, // Bug #24
        'activity_level': derivedActivityLevel,
        'days_per_week': _daysPerWeek,
        'diet_preference': _dietPreference,
        'injuries': _injuries,
        'city': _cityController.text.trim(),
        'phone': _phoneController.text.trim(),
        if (_bodyFatController.text.isNotEmpty)
          'body_fat_percent': double.tryParse(_bodyFatController.text),
        if (_bodyFatAssessedAt != null)
          'body_fat_assessed_at': _bodyFatAssessedAt,
        if (_sessionDuration != null)
          'session_duration_minutes': _sessionDuration,
        'physique_focus': _physiqueFocus,
        'fitness_experience': _fitnessExperience,
      };

      await ref.read(userProfileProvider.notifier).updateProfile(updates);
      await ref.read(userProfileProvider.notifier).recalculateTargets();

      // Refresh downstream views that cache profile-derived targets/state.
      ref.invalidate(userStatsProvider);
      ref.invalidate(nutritionSummaryProvider);
      ref.invalidate(dailyNutritionProvider);
      ref.invalidate(macroTargetsProvider);
      // Refresh home screen name/greeting — these are separate providers
      // in home_provider.dart that cache the name independently.
      ref.invalidate(userFirstNameProvider);
      ref.invalidate(userInitialProvider);
      ref.invalidate(userGreetingProvider);

      // Detect plan-affecting field changes and offer rescheduling
      final planChanged = _daysPerWeek != _originalDaysPerWeek ||
          _goal != _originalGoal ||
          _equipment != _originalEquipment;

      if (planChanged && WorkoutScheduleService.instance.hasPlan() && mounted) {
        final changes = <String>[];
        if (_daysPerWeek != _originalDaysPerWeek) {
          changes.add('$_originalDaysPerWeek → $_daysPerWeek days/week');
        }
        if (_goal != _originalGoal) {
          changes.add('Goal: ${_goals[_originalGoal]} → ${_goals[_goal]}');
        }
        if (_equipment != _originalEquipment) {
          changes.add('Equipment: ${_equipmentOptions[_originalEquipment]} → ${_equipmentOptions[_equipment]}');
        }

        final shouldReschedule = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.cardM),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Text(
              'Reschedule Workouts?',
              style: GoogleFonts.getFont('DM Sans',
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You changed:',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                ...changes.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_forward, size: 12, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(c,
                          style: GoogleFonts.getFont('DM Sans',
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 10),
                Text(
                  'Regenerate future workouts from today? Past completed workouts will be kept.',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Keep Current Plan',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                ),
                child: Text('Reschedule',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ),
            ],
          ),
        );

        if (shouldReschedule == true && mounted) {
          final profile = ref.read(userProfileProvider);
          final experience = (profile['detected_experience_level'] as String?) ?? 'beginner';
          final currentPhase = (profile['current_phase'] as num?)?.toInt() ?? 1;

          final savedDays = HiveService.instance.configBox
              .get('preferred_training_days');
          final preferredDays = savedDays is List
              ? savedDays.cast<int>()
              : null;

          await WorkoutScheduleService.instance.generateAndScheduleFromDate(
            goal: _goal,
            equipment: _equipment,
            daysPerWeek: _daysPerWeek,
            fromDate: DateTime.now(),
            experienceLevel: experience,
            phase: currentPhase,
            preferredDays: preferredDays,
          );
        }
      }

      // Refresh train plan providers after potential rescheduling.
      ref.invalidate(currentPlanProvider);
      ref.invalidate(todayWorkoutProvider);
      ref.invalidate(calendarWeekProvider);

      // Push updated profile to Supabase immediately (fire-and-forget).
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId != null) {
        SyncService.instance.syncProfileNow(userId);
      }

      // Bug #12: Invalidate/regenerate prediction when target weight changes.
      final targetWeightChanged =
          (targetWeight - _originalTargetWeight).abs() > 0.1;
      if (targetWeightChanged) {
        final isPro = SubscriptionService.instance.isPro();
        if (isPro) {
          // PRO: auto-regenerate prediction with new goal in background.
          // Don't await — let user proceed while prediction generates.
          PredictionService.instance.regeneratePrediction().then((success) {
            if (success && mounted) {
              ref.invalidate(predictionProvider);
            }
          });
        } else {
          // FREE: mark cached prediction as stale so UI shows badge.
          PredictionService.instance.markStale();
          ref.invalidate(predictionProvider);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              planChanged && WorkoutScheduleService.instance.hasPlan()
                  ? 'Profile saved & workouts rescheduled'
                  : 'Profile saved',
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
