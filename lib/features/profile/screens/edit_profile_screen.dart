import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
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
import '../providers/profile_completeness_provider.dart';

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

  // Added 2026-04-18: date of birth + wake-up time were collected during
  // onboarding but had no edit surface, so users couldn't retroactively
  // fill them. Observed: profile completeness stuck at 94% because DOB
  // was still null on a post-onboarding account.
  DateTime? _dateOfBirth; // stored as ISO date string in Hive/Supabase
  TimeOfDay? _wakeUpTime; // stored as 'HH:MM:SS' string in Hive/Supabase
  late final TextEditingController _bodyFatController;
  String? _bodyFatAssessedAt;
  bool _isAssessingBf = false;
  bool _isSaving = false;
  late bool _isMetric; // true = KG/CM, false = LBS/IN

  // Track original plan-affecting values for rescheduling detection.
  // V4 pipeline plan-driving inputs (per CLAUDE.md §12 + plan_engine/):
  //   daysPerWeek + goal + equipment + fitness_experience drive the split
  //   resolver + volume filter + exercise selector. session_duration_minutes
  //   + physique_focus + injuries drive sequencing + warmup/cooldown +
  //   exclusion masks. ALL must trigger reschedule on change.
  late int _originalDaysPerWeek;
  late String _originalGoal;
  late String _originalEquipment;
  late String _originalFitnessExperience;
  late int? _originalSessionDuration;
  late String _originalPhysiqueFocus;
  late List<String> _originalInjuries;

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

    // Date of birth: stored as "YYYY-MM-DD" string. Parse if present.
    final dobStr = (profile['date_of_birth'] as String?)?.trim() ?? '';
    if (dobStr.isNotEmpty) {
      _dateOfBirth = DateTime.tryParse(dobStr);
    }

    // Wake-up time: stored as "HH:MM" or "HH:MM:SS" string. Parse if present.
    final wakeStr = (profile['wake_up_time'] as String?)?.trim() ?? '';
    if (wakeStr.isNotEmpty) {
      final parts = wakeStr.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          _wakeUpTime = TimeOfDay(hour: h, minute: m);
        }
      }
    }

    // Capture original values for rescheduling detection.
    // _injuries is captured as List.of(...) so later edits via the chip
    // row don't mutate the original snapshot (List references are aliased
    // in Dart; without List.of we'd compare a list to itself).
    _originalDaysPerWeek = _daysPerWeek;
    _originalGoal = _goal;
    _originalEquipment = _equipment;
    _originalFitnessExperience = _fitnessExperience;
    _originalSessionDuration = _sessionDuration;
    _originalPhysiqueFocus = _physiqueFocus;
    _originalInjuries = List<String>.of(_injuries);
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
      // Handoff header: double gold rule + mono "← BACK" left / Fraunces
      // h3 "Edit Profile" centre / mono gold "SAVE" right. Matches
      // `design_handoff_wardroom/src/screens/utility.jsx` EditProfileScreen
      // lines 386–406.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(
              bottom: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/profile'),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    child: Text(
                      '\u2190 BACK',
                      style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: AppColors.textDim,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Edit Profile',
                      style: AppTypography.h3.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _isSaving ? null : _save,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                    child: Text(
                      'SAVE',
                      style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: _isSaving
                            ? AppColors.textDisabled
                            : AppColors.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
              const SizedBox(height: AppSpacing.gridGap),
              _buildDateOfBirthField(),
              const SizedBox(height: AppSpacing.gridGap),
              _buildWakeUpTimeField(),
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
      style: AppTypography.mono.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
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
                      style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isNotEmpty ? email : 'Not set',
                      style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textDim),
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
            style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textDim),
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
      style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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

  /// Date-of-birth picker row. Renders as a tappable field matching the
  /// _buildTextField visual style. Tap opens a standard Material
  /// showDatePicker with reasonable bounds (13 yrs ago as most-recent,
  /// 100 yrs ago as oldest).
  Widget _buildDateOfBirthField() {
    final displayText = _dateOfBirth == null
        ? 'Date of Birth'
        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: _pickDateOfBirth,
      borderRadius: BorderRadius.circular(AppRadius.row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.row),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cake, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: _dateOfBirth == null
                      ? AppColors.textDim
                      : AppColors.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final min = DateTime(now.year - 100, now.month, now.day);
    final max = DateTime(now.year - 13, now.month, now.day);
    final initial = _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(max) ? max : initial,
      firstDate: min,
      lastDate: max,
    );
    if (picked != null && mounted) {
      setState(() => _dateOfBirth = picked);
    }
  }

  /// Wake-up time picker row — same visual pattern as DOB.
  Widget _buildWakeUpTimeField() {
    final displayText = _wakeUpTime == null
        ? 'Wake-up Time'
        : _wakeUpTime!.format(context);
    return InkWell(
      onTap: _pickWakeUpTime,
      borderRadius: BorderRadius.circular(AppRadius.row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.row),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: _wakeUpTime == null
                      ? AppColors.textDim
                      : AppColors.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickWakeUpTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wakeUpTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _wakeUpTime = picked);
    }
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
              style: AppTypography.body.copyWith(fontSize: 13, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400, color: isSelected ? AppColors.accent : AppColors.textDim),
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
    if (options.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : options.keys.first,
      items: options.entries
          .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(
                  e.value,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w400, color: AppColors.textPrimary),
                ),
              ))
          .toList(),
      onChanged: onChanged,
      dropdownColor: AppColors.card,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                      style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: isSelected
                            ? Colors.black
                            : AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                        style: AppTypography.body.copyWith(fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400, color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textPrimary),
                      ),
                      Text(
                        subtitles[entry.key]!,
                        style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                        style: AppTypography.body.copyWith(fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400, color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textPrimary),
                      ),
                      Text(
                        subtitles[entry.key]!,
                        style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim),
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
                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected
                        ? AppColors.accent
                        : AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim),
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
                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected
                        ? AppColors.accent
                        : AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim),
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
                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected
                        ? AppColors.accent
                        : AppColors.textDim),
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
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400, color: isSelected
                        ? AppColors.accent
                        : AppColors.textPrimary),
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
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400, color: isSelected
                        ? (option == 'none'
                            ? AppColors.accent
                            : AppColors.bad)
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
                style: AppTypography.body.copyWith(fontSize: 15, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Body Fat % (optional)',
                  labelStyle: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.proGold),
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
            style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Used for lean-mass protein targets. AI photo assessment is PRO, once per month.',
          style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
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
              style: AppTypography.body.copyWith(color: Colors.white),
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
        content: Text(message, style: AppTypography.bodySm.copyWith(color: Colors.white)),
        backgroundColor: AppColors.bad,
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

      // DOB + wake-up-time: format for storage ("YYYY-MM-DD" + "HH:MM:SS").
      // Empty string for un-set values — sync_service._sanitize/_hasValue
      // will drop them before Postgres sees the empty column write.
      final dobIso = _dateOfBirth == null
          ? null
          : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';
      final wakeIso = _wakeUpTime == null
          ? null
          : '${_wakeUpTime!.hour.toString().padLeft(2, '0')}:${_wakeUpTime!.minute.toString().padLeft(2, '0')}:00';

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
        'date_of_birth': ?dobIso,
        'wake_up_time': ?wakeIso,
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

      // Bug B fix (APK Test #3, 2026-04-26): Edit Profile previously wrote
      // only to Hive. user_profile in Supabase stayed empty/stale forever,
      // which broke AI coach context (the snapshot reads from Hive but
      // server-side helpers like rolling-context need the cloud row).
      // Fire-and-forget so sync failures don't block the Save UX.
      final supaUserId = SupabaseService.instance.client.auth.currentUser?.id;
      if (supaUserId != null) {
        unawaited(SyncService.instance.syncProfileNow(supaUserId));
        unawaited(SyncService.instance.pushSnapshot());
      }

      // Refresh downstream views that cache profile-derived targets/state.
      ref.invalidate(userStatsProvider);
      ref.invalidate(nutritionSummaryProvider);
      ref.invalidate(dailyNutritionProvider);
      ref.invalidate(macroTargetsProvider);
      // Profile completeness nudge caches its tier-1/tier-2 count until
      // invalidated. Without this, the progress bar stays at the pre-save
      // value until the app is force-restarted. Observed 2026-04-17 on
      // icanbefitter@gmail.com — bar stuck at 61% until a kill-and-relaunch.
      ref.invalidate(profileCompletenessProvider);
      // Refresh home screen name/greeting — these are separate providers
      // in home_provider.dart that cache the name independently.
      ref.invalidate(userFirstNameProvider);
      ref.invalidate(userInitialProvider);
      ref.invalidate(userGreetingProvider);

      // Detect plan-affecting field changes and offer rescheduling.
      // Experience drives VolumeFilter.targetCount → exercise count per day.
      // Beginner/Inter/Advanced × 3-6 days = 4 to 10 exercises. Without this,
      // bumping intermediate→advanced wouldn't trigger reschedule and today's
      // plan would keep showing the old 4-7 exercises forever.
      //
      // session_duration_minutes drives split count + cardio finisher length;
      // physique_focus drives muscle slot weighting (e.g. glutes_legs adds
      // posterior chain priority); injuries drive exclusion masks in the
      // exercise selector. ALL must trigger reschedule on change to keep
      // today's schedule consistent with the saved profile.
      final planChanged = computePlanChanged(
        daysPerWeek: _daysPerWeek,
        originalDaysPerWeek: _originalDaysPerWeek,
        goal: _goal,
        originalGoal: _originalGoal,
        equipment: _equipment,
        originalEquipment: _originalEquipment,
        fitnessExperience: _fitnessExperience,
        originalFitnessExperience: _originalFitnessExperience,
        sessionDuration: _sessionDuration,
        originalSessionDuration: _originalSessionDuration,
        physiqueFocus: _physiqueFocus,
        originalPhysiqueFocus: _originalPhysiqueFocus,
        injuries: _injuries,
        originalInjuries: _originalInjuries,
      );

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
        if (_fitnessExperience != _originalFitnessExperience) {
          String label(String e) => e[0].toUpperCase() + e.substring(1);
          changes.add('Experience: ${label(_originalFitnessExperience)} → ${label(_fitnessExperience)}');
        }
        if (_sessionDuration != _originalSessionDuration) {
          String fmt(int? d) => d == null ? '—' : '$d min';
          changes.add('Session: ${fmt(_originalSessionDuration)} → ${fmt(_sessionDuration)}');
        }
        if (_physiqueFocus != _originalPhysiqueFocus) {
          String label(String f) {
            switch (f) {
              case 'glutes_legs':
                return 'Glutes & Legs';
              case 'chest_shoulders_arms':
                return 'Chest, Shoulders & Arms';
              case 'strength':
                return 'Strength';
              case 'balanced':
              default:
                return 'Balanced';
            }
          }
          changes.add('Focus: ${label(_originalPhysiqueFocus)} → ${label(_physiqueFocus)}');
        }
        if (!listEquals(_injuries, _originalInjuries)) {
          changes.add('Injuries: ${_originalInjuries.length} → ${_injuries.length} listed');
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
              style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You changed:',
                  style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
                          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 10),
                Text(
                  'Regenerate future workouts from today? Past completed workouts will be kept.',
                  style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Keep Current Plan',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textDim)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                ),
                child: Text('Reschedule',
                    style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
            ],
          ),
        );

        if (shouldReschedule == true && mounted) {
          final profile = ref.read(userProfileProvider);
          final experience = (profile['fitness_experience'] as String?) ?? 'intermediate';
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
      ref.invalidate(aiInsightProvider);  // F5 — refresh home insight after regen

      // Push updated profile to Supabase immediately (fire-and-forget).
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId != null) {
        SyncService.instance.syncProfileNow(userId);
      }
      unawaited(SyncService.instance.pushSnapshot());

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
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.ok,
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
              style: AppTypography.bodySm.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.bad,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Pure helper extracted from `_EditProfileScreenState._save` so the
/// reschedule trigger can be unit-tested without instantiating the
/// widget. Mirrors the boolean exactly — keep in sync with B-2.
@visibleForTesting
bool computePlanChanged({
  required int daysPerWeek,
  required int originalDaysPerWeek,
  required String goal,
  required String originalGoal,
  required String equipment,
  required String originalEquipment,
  required String fitnessExperience,
  required String originalFitnessExperience,
  required int? sessionDuration,
  required int? originalSessionDuration,
  required String physiqueFocus,
  required String originalPhysiqueFocus,
  required List<String> injuries,
  required List<String> originalInjuries,
}) {
  return daysPerWeek != originalDaysPerWeek ||
      goal != originalGoal ||
      equipment != originalEquipment ||
      fitnessExperience != originalFitnessExperience ||
      sessionDuration != originalSessionDuration ||
      physiqueFocus != originalPhysiqueFocus ||
      !listEquals(injuries, originalInjuries);
}
