import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/constants/body_measurement_specs.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/measurement_units.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';

/// The body-measurements entry sheet (L2b Landing B, B4): four optional fields
/// (chest, waist, hips, arms), a cm / inch control, a per-site "Last:" hint and
/// one Save. Nothing here is PRO-gated.
///
/// **The unit control changes how the digits are READ and never rewrites them.**
/// The only per-row state is the text controller (plus whether the row has been
/// touched). Validity, the message, the "switch?" hint, the value Save sends and
/// `inchesUsed` are all derived in [build] from (text, active unit), so a
/// toggle recomputes everything at once and every typed digit stays as typed.
class BodyMeasurementsSheet extends ConsumerStatefulWidget {
  const BodyMeasurementsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // At a large text scale the content can reach the full height; without
      // this the handle and the unit control sit under the status bar.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BodyMeasurementsSheet(),
    );
  }

  @override
  ConsumerState<BodyMeasurementsSheet> createState() =>
      _BodyMeasurementsSheetState();
}

class _BodyMeasurementsSheetState extends ConsumerState<BodyMeasurementsSheet> {
  final Map<String, TextEditingController> _controllers = {
    for (final s in kBodyMeasurementSites) s: TextEditingController(),
  };
  final Map<String, FocusNode> _nodes = {
    for (final s in kBodyMeasurementSites) s: FocusNode(),
  };
  final Set<String> _touched = {};
  late bool _inches;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _inches = ref.read(measurementWriteProvider.notifier).preferredInches();
    for (final site in kBodyMeasurementSites) {
      _nodes[site]!.addListener(() {
        if (!_nodes[site]!.hasFocus && _controllers[site]!.text.isNotEmpty) {
          if (mounted) setState(() => _touched.add(site));
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // ── Derived per-row facts (never stored) ───────────────────────────────

  bool _isBlank(String site) => _controllers[site]!.text.trim().isEmpty;

  double? _cmOf(String site) =>
      parseMeasurementInput(_controllers[site]!.text, metric: !_inches);

  bool _isValid(String site) => isValidBodyMeasurementCm(site, _cmOf(site));

  /// The rows the user filled in, in registry order.
  List<String> get _edited => [
    for (final s in kBodyMeasurementSites)
      if (!_isBlank(s)) s,
  ];

  String _rangeMessage(String site) {
    if (_inches) {
      final b = inchBoundsFor(site);
      return MeasurementCopy.rangeIn(b.min, b.max);
    }
    final spec = kBodyMeasurementSpecs[site]!;
    return MeasurementCopy.rangeCm(spec.minCm, spec.maxCm);
  }

  bool _showsProblem(String site) =>
      _touched.contains(site) && !_isBlank(site) && !_isValid(site);

  void _setInches(bool inches) {
    if (_inches == inches) return;
    setState(() => _inches = inches);
  }

  // ── Save ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final edited = _edited;
    if (edited.isEmpty) return;
    final invalid = [
      for (final s in edited)
        if (!_isValid(s)) s,
    ];
    if (invalid.isNotEmpty) {
      // Show every invalid row's message, focus the first one, write nothing.
      setState(() => _touched.addAll(edited));
      _nodes[invalid.first]!.requestFocus();
      return;
    }
    // Captured at the tap, BEFORE the await: `save()` invalidates the history
    // provider, and a later read would return the new value ("Waist 79.5 ->
    // 79.5").
    final history = ref.read(bodyMeasurementsProvider);
    final before = Map.of(history.latest);
    final known = history.loaded;
    final inchesUsed = _inches;
    final sites = {for (final s in edited) s: _cmOf(s)!};
    final notifier = ref.read(measurementWriteProvider.notifier);
    WriteResult result;
    _saving =
        true; // checked above, before the first await: a second tap is a no-op
    try {
      result = await notifier.save(
        sites: sites,
        source: WriteSource.manual,
        inchesUsed: inchesUsed,
      );
    } finally {
      _saving = false;
    }
    // The user can swipe the sheet away while the write is in flight.
    if (!mounted) return;
    if (!result.success) {
      setState(() => _saveFailed = true);
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _savedLine(sites, before, known),
          style: AppTypography.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// The one-line acknowledgement: a neutral delta for exactly one held site,
  /// "Baseline set" when every edited site is new (and the history was read),
  /// otherwise the plain line. Always centimetres.
  String _savedLine(
    Map<String, double> sites,
    Map<String, ({double cm, String date})> before,
    bool known,
  ) {
    if (known) {
      if (sites.length == 1 && before.containsKey(sites.keys.first)) {
        final site = sites.keys.first;
        return MeasurementCopy.deltaLine(
          kBodyMeasurementSpecs[site]!.label,
          before[site]!.cm,
          sites[site]!,
        );
      }
      if (sites.keys.every((s) => !before.containsKey(s))) {
        return MeasurementCopy.savedBaseline;
      }
    }
    return MeasurementCopy.savedPlain;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(bodyMeasurementsProvider);
    final edited = _edited;
    final todayIst = istTodayStr();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              12,
              AppSpacing.gutter,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        MeasurementCopy.sheetEyebrow,
                        style: AppTypography.mono.copyWith(
                          color: AppColors.accent,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    _UnitControl(inches: _inches, onChanged: _setInches),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  history.loaded && history.latest.isEmpty
                      ? MeasurementCopy.introFirst
                      : MeasurementCopy.introLater,
                  style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
                ),
                if (!history.loaded) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          MeasurementCopy.loadError,
                          style: AppTypography.bodyS.copyWith(
                            color: AppColors.warn,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(bodyMeasurementsProvider),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: AppColors.accent,
                        ),
                        child: Text(
                          MeasurementCopy.retry,
                          style: AppTypography.label,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                for (final site in kBodyMeasurementSites)
                  _buildRow(site, history, todayIst),
                if (_saveFailed) ...[
                  const SizedBox(height: 4),
                  Text(
                    MeasurementCopy.saveFailed,
                    style: AppTypography.bodyS.copyWith(color: AppColors.bad),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: edited.isEmpty ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.input,
                      disabledForegroundColor: AppColors.textDim,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      MeasurementCopy.save,
                      style: AppTypography.mono.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    String site,
    BodyMeasurementsState history,
    String todayIst,
  ) {
    final spec = kBodyMeasurementSpecs[site]!;
    final problem = _showsProblem(site);
    final last = history.latest[site];
    final shortDate = last == null
        ? ''
        : formatShortIstDate(last.date, todayIst: todayIst);
    final cm = _cmOf(site);
    final isLastRow = site == kBodyMeasurementSites.last;
    final suggest =
        problem &&
        suggestOtherUnit(site, _controllers[site]!.text, metric: !_inches);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.label,
            style: AppTypography.titleS.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            spec.guide,
            style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
          ),
          if (last != null && shortDate.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              MeasurementCopy.lastHint(
                cm: last.cm,
                inches: _inches ? inchesFromCm(last.cm) : null,
                shortDate: shortDate,
              ),
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
            ),
          ],
          const SizedBox(height: 6),
          Semantics(
            label: spec.label,
            textField: true,
            child: TextField(
              controller: _controllers[site],
              focusNode: _nodes[site],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: isLastRow
                  ? TextInputAction.done
                  : TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,3}\.?\d{0,1}'),
                ),
              ],
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.input,
                suffixText: _inches ? 'in' : 'cm',
                suffixStyle: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  borderSide: BorderSide(
                    color: problem ? AppColors.bad : AppColors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  borderSide: BorderSide(
                    color: problem ? AppColors.bad : AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
          if (_inches && !_isBlank(site) && cm != null && _isValid(site))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                MeasurementCopy.storedAsCm(cm),
                style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
              ),
            ),
          if (problem)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _rangeMessage(site),
                style: AppTypography.bodyS.copyWith(color: AppColors.bad),
              ),
            ),
          if (suggest)
            Semantics(
              button: true,
              child: InkWell(
                // The keyboard's "next" action must land on the next field,
                // never on this hint (it sits between two fields in focus
                // order).
                canRequestFocus: false,
                onTap: () => _setInches(!_inches),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _inches
                          ? MeasurementCopy.switchToCentimetres
                          : MeasurementCopy.switchToInches,
                      style: AppTypography.bodyS.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The two-option cm / in control. Its own widget: `WardUnitToggle` has 9 pt
/// options with 10x5 padding, well under the 44 dp tap-target floor.
class _UnitControl extends StatelessWidget {
  const _UnitControl({required this.inches, required this.onChanged});

  final bool inches;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool isInches) {
      final selected = inches == isInches;
      return Semantics(
        button: true,
        selected: selected,
        label: isInches
            ? MeasurementCopy.unitInSemantics
            : MeasurementCopy.unitCmSemantics,
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onChanged(isInches),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: AppTypography.mono.copyWith(
                  color: selected ? AppColors.accent : AppColors.textDim,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        option(MeasurementCopy.unitCm, false),
        option(MeasurementCopy.unitIn, true),
      ],
    );
  }
}
