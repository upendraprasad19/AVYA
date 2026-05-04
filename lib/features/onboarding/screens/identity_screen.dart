import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Step 01 · 05 of the stepped onboarding flow — identity capture.
///
/// Collects the three "who are you" basics before any body-metric or
/// goal-specific questions:
///   * `full_name`  — text input, required
///   * `date_of_birth` — date picker, required, min age 10
///   * `sex` — Male / Female / Other, required
///
/// Moved here from Stats (sex) and derived-from-age (DOB) so the flow
/// groups identity fields together and Stats is left with only body
/// metrics. Age is no longer captured directly — `plan_screen` computes
/// it from DOB when building the profile map.
///
/// Progress: `01 · 05`. BACK goes to `/onboarding` (welcome). CONTINUE
/// passes `{full_name, date_of_birth, sex}` to `/onboarding/goal` via
/// route extras.
class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key, this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  late final TextEditingController _name;
  DateTime? _dob;
  String? _sex;
  /// Inline validation error for the name field. Cleared when the user
  /// resumes typing. Shown as bodySm-bad below the field's labelled tile.
  String? _nameError;
  /// Inline validation error for the sex selector. Set when the user taps
  /// CONTINUE without picking a pill. Cleared on the next pill tap.
  String? _sexError;

  /// Letters + spaces + `.`-`'` allowed; digits and emoji rejected.
  /// Matches the validation spec in the APK-test-1-batch plan (D2).
  static final RegExp _nameAllowed = RegExp(r"^[A-Za-z\u00C0-\u024F .'\-]+$");

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? const <String, dynamic>{};
    _name = TextEditingController(text: init['full_name'] as String? ?? '');
    _name.addListener(() {
      if (_nameError != null) {
        setState(() => _nameError = null);
      }
    });
    final initDob = init['date_of_birth'];
    if (initDob is String) {
      _dob = DateTime.tryParse(initDob);
    } else if (initDob is DateTime) {
      _dob = initDob;
    }
    _sex = init['sex'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // Min-age 10: max selectable DOB is today-10y.
    // U10 fix (Test #4 hotfix): lowered from 13 → 10 per user observation
    // ("i tried inserting date of my son as 2019, i was unable").
    // Trade-off: less COPPA-aligned but simpler. Track for legal review
    // post-Test #4. Guardian-managed accounts for under-10 remain out of scope.
    final max = DateTime(now.year - 10, now.month, now.day);
    final seed = _dob ?? DateTime(now.year - 25, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: seed.isAfter(max) ? max : seed,
      firstDate: DateTime(now.year - 100, 1, 1),
      lastDate: max,
      helpText: 'DATE OF BIRTH',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.accent,
                onPrimary: AppColors.bgDeep,
                surface: AppColors.card,
                onSurface: AppColors.textPrimary,
              ),
          dialogTheme: const DialogThemeData(backgroundColor: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                const SizedBox(height: 24),
                _header(),
                const SizedBox(height: 22),
                Expanded(child: _fields()),
                const SizedBox(height: 16),
                _cta(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    return Row(
      children: [
        Text(
          '01 \u00B7 05',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            children: [
              Container(height: 1, color: AppColors.line2),
              FractionallySizedBox(
                widthFactor: 1 / 5,
                child: Container(height: 1, color: AppColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'IDENTITY',
          style: AppTypography.mono.copyWith(
            color: AppColors.textDim,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '01 · 05',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: AppTypography.h1.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
              height: 1.08,
            ),
            children: const [
              TextSpan(text: 'Who are '),
              TextSpan(
                text: 'you?',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "The basics. We'll use them for your plan, your targets, and a "
          "greeting that doesn't say \"USER\".",
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _fields() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _labeledField(
          label: 'NAME',
          child: TextField(
            controller: _name,
            // Focus on entry so the keyboard pops up immediately — user
            // lands on the screen and can start typing without reaching
            // for the field. Placeholder removed: the NAME label above
            // already tells them what goes here.
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
            cursorColor: AppColors.accent,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (_nameError != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _nameError!,
              style: AppTypography.bodySm.copyWith(color: AppColors.bad),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _labeledField(
          label: 'DATE OF BIRTH',
          child: GestureDetector(
            onTap: _pickDob,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dob == null ? 'Tap to pick' : _formatDob(_dob!),
                    style: AppTypography.body.copyWith(
                      color: _dob == null
                          ? AppColors.textMute
                          : AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _sexSelector(),
      ],
    );
  }

  Widget _labeledField({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              fontSize: 8,
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _sexSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SEX',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _pill('MALE', 'male'),
            _pill('FEMALE', 'female'),
            _pill('OTHER', 'other'),
          ],
        ),
        if (_sexError != null) ...[
          const SizedBox(height: 8),
          Text(
            _sexError!,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.bad,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _pill(String label, String value) {
    final selected = _sex == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GestureDetector(
          onTap: () => setState(() {
            _sex = value;
            _sexError = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.card,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line2,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                color: selected ? AppColors.bgDeep : AppColors.textDim,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cta(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go('/onboarding'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line2),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Text(
              'BACK',
              style: AppTypography.mono.copyWith(
                fontSize: 12,
                color: AppColors.textDim,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _onContinue,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              alignment: Alignment.center,
              child: Text(
                'CONTINUE \u2192',
                style: AppTypography.mono.copyWith(
                  fontSize: 12,
                  color: AppColors.bgDeep,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onContinue() {
    final name = _name.text.trim();

    // Validate name with actionable inline feedback (D2 spec).
    String? nameError;
    if (name.isEmpty) {
      nameError = 'Tell us your name first.';
    } else if (name.length < 2) {
      nameError = 'Name must be at least 2 characters.';
    } else if (name.length > 40) {
      nameError = 'Name is too long (max 40 characters).';
    } else if (!_nameAllowed.hasMatch(name)) {
      nameError = 'Letters only \u2014 no digits or emoji.';
    }

    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }

    // DOB still uses a snackbar because it's a separate tile without an
    // inline surface — the calendar picker is the primary affordance.
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pick your date of birth.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          backgroundColor: AppColors.bad,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Sex is required — every BMR formula branches on it. An unset value
    // silently defaults downstream; block here with an inline error instead.
    if (_sex == null) {
      setState(() =>
          _sexError = 'Please pick one to calibrate your plan accurately.');
      return;
    }

    setState(() => _nameError = null);
    context.go(
      '/onboarding/goal',
      extra: {
        'full_name': name,
        'date_of_birth': _dob!.toIso8601String(),
        'sex': _sex!,
      },
    );
  }

  static String _formatDob(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
