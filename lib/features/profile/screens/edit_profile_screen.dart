import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
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
  String _activityLevel = 'moderate';
  int _daysPerWeek = 4;
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    _cityController.dispose();
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
              _buildDropdown(
                label: 'Activity Level',
                value: _activityLevel,
                options: _activityLevels,
                onChanged: (v) => setState(() => _activityLevel = v!),
              ),
              const SizedBox(height: AppSpacing.gridGap),
              _buildDaysSelector(),
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

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final updates = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'gender': _gender,
        'height_cm': double.tryParse(_heightController.text) ?? 0,
        'current_weight_kg': double.tryParse(_weightController.text) ?? 0,
        'target_weight_kg':
            double.tryParse(_targetWeightController.text) ?? 0,
        'primary_goal': _goal,
        'equipment_access': _equipment,
        'activity_level': _activityLevel,
        'days_per_week': _daysPerWeek,
        'city': _cityController.text.trim(),
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
