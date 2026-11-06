import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/home/widgets/measurement_due_banner.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';

/// The Home slot for the body-measurements banner (L2b Landing B, E1 / E5).
///
/// A slot OWNS its flag and state check, so the host adds one line and an OFF
/// build creates no measurements provider at all: the flag is read first, and
/// only then the prompt provider (which is itself flag-first). It watches its
/// own providers, so it rebuilds without its parent.
class MeasurementDueSlot extends ConsumerWidget {
  const MeasurementDueSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(measurementsEnabledProvider)) return const SizedBox.shrink();
    final prompt = ref.watch(measurementPromptProvider);
    if (prompt == MeasurementPrompt.none) return const SizedBox.shrink();
    final baseline = prompt == MeasurementPrompt.baseline;
    return MeasurementDueBanner(
      baseline: baseline,
      onOpen: () => BodyMeasurementsSheet.show(context),
      onDismiss: () {
        final notifier = ref.read(measurementPromptProvider.notifier);
        if (baseline) {
          notifier.skipBaseline();
        } else {
          notifier.dismiss();
        }
      },
    );
  }
}
