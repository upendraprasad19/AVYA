import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_chip.dart';

/// The AI Coach chat's door to the body-measurements sheet (L2b Landing C, E4).
///
/// A slot OWNS its flag and state check, so the host adds one line and an OFF
/// build creates no measurements provider: the flag is read first, then the
/// prompt (itself flag-first). The chip shows for the same two prompts as the
/// Home banner, `due` and `baseline`, and:
///
/// * hides while the composer has focus ([inputFocusNode]) and while a message
///   is being sent ([isSending]), and comes back under the reply;
/// * is ONE tap target (one `InkWell`, one screen-reader node) that opens the
///   sheet and nothing else: the slot is given no send callback, so a tap on it
///   cannot put words in the conversation;
/// * has its own X, outside the chip's tap target, with the same effect as the
///   Home banner's X (7 days for `due`, 28 for `baseline`, every nag surface).
///
/// Built from [WardChip] directly and not from the quick-prompt chip, which
/// carries its own tap handler and a required callback.
///
/// The chip takes room from the chat above it, and it appears AFTER the reply
/// landed and the chat scrolled to it (it comes back when `isSending` ends), so
/// the last message would end up under the input bar. [onShown] is called once,
/// after the first frame, each time the chip appears, with the height the slot
/// took; the host passes [keepBottomAfterChip] to scroll that room back.
class MeasurementChipSlot extends ConsumerWidget {
  const MeasurementChipSlot({
    super.key,
    required this.inputFocusNode,
    required this.isSending,
    this.onShown,
  });

  final FocusNode inputFocusNode;
  final bool isSending;
  final ValueChanged<double>? onShown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(measurementsEnabledProvider)) return const SizedBox.shrink();
    final prompt = ref.watch(measurementPromptProvider);
    if (prompt == MeasurementPrompt.none) return const SizedBox.shrink();
    if (isSending) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: inputFocusNode,
      builder: (context, _) {
        if (inputFocusNode.hasFocus) return const SizedBox.shrink();
        void open() => BodyMeasurementsSheet.show(context);
        void dismiss() {
          final notifier = ref.read(measurementPromptProvider.notifier);
          final done = prompt == MeasurementPrompt.baseline
              ? notifier.skipBaseline()
              : notifier.dismiss();
          unawaited(
            done.catchError((Object _) {
              unawaited(
                ErrorTelemetry.logEvent(
                  'measurement_chip_dismiss_failed',
                  message: 'stage=chip_dismiss',
                ),
              );
            }),
          );
        }

        return _NotifyWhenShown(
          onShown: onShown,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.gutter, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Semantics(
                      button: true,
                      excludeSemantics: true,
                      label: MeasurementCopy.chipLabel,
                      onTap: open,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: InkWell(
                          onTap: open,
                          child: const Align(
                            alignment: Alignment.centerLeft,
                            child: WardChip(
                              label: MeasurementCopy.chipLabel,
                              tone: WardChipTone.gold,
                              leading: Icon(
                                Icons.straighten,
                                size: 14,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: MeasurementCopy.bannerDismissLabel,
                  onTap: dismiss,
                  child: InkWell(
                    onTap: dismiss,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Calls [onShown] with the slot's height once, after the frame in which it was
/// first built: it is mounted each time the chip goes from hidden to visible
/// and keeps its state while the chip stays, so a rebuild does not repeat it.
class _NotifyWhenShown extends StatefulWidget {
  const _NotifyWhenShown({required this.onShown, required this.child});

  final ValueChanged<double>? onShown;
  final Widget child;

  @override
  State<_NotifyWhenShown> createState() => _NotifyWhenShownState();
}

class _NotifyWhenShownState extends State<_NotifyWhenShown> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
      widget.onShown?.call(height);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// How far from the bottom the chat may be for [keepBottomAfterChip] to follow
/// it: a person reading older messages is not moved.
const double kChipFollowSlack = 16;

/// After the chip appeared and took [slotHeight] from the chat, keeps a chat
/// that was at (or within [kChipFollowSlack] of) its bottom at its bottom, so
/// the last message stays above the chip. A chat scrolled further up, and a
/// controller with no list attached (the Telegram view), are left alone.
void keepBottomAfterChip(ScrollController controller, double slotHeight) {
  if (!controller.hasClients) return;
  final position = controller.position;
  if (position.extentAfter > slotHeight + kChipFollowSlack) return;
  controller.animateTo(
    position.maxScrollExtent,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
}
