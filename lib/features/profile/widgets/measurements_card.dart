import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import '../providers/body_measurements_provider.dart';
import '../services/measurement_card_rules.dart';
import 'body_measurements_sheet.dart';

/// Smallest height the card is ever given when it shows at all: the pinned
/// header at its worst (two wrapped runs at the clamped x2.0 scale), the card's
/// own padding and border, and the frame's margin around it. Derived and
/// measured by `measurements_card_frame_test.dart`; a red test raises this, it
/// never relaxes the test.
const double kMinCardCap = 136;

/// The snapshot list below the card is worth more than the card: the card never
/// takes the room under this.
const double kMinListHeight = 150;

/// Below this body height the frame shows the child alone.
const double kMinHostHeightForCard = kMinCardCap + kMinListHeight;

/// The space the frame leaves above and below the card INSIDE the capped box
/// (so [kMinCardCap] includes it).
const double kCardMarginTop = 12;
const double kCardMarginBottom = 8;

/// One two-up tile row. The tiles show only when the cap leaves at least this
/// much beyond [kMinCardCap]; between that and the tile threshold the card is
/// COMPACT: the header (eyebrow and button) only.
const double kMinTileWindow = 64;

/// The "Body measurements" card on Profile -> Progress comparison (L2b
/// Landing C, E3): per site the latest value and day, the change since the
/// FIRST entry holding that site, and a permanent "Add measurements" button.
///
/// Hosted by `MeasurementsCardFrame`, which owns the flag and the height cap;
/// this card fills the height it is given. It ignores the due state and the
/// dismissal (D4): it shows whenever the flag is ON. Numbers are neutral: the
/// change is always `textDim`, never green or red (a waist that grew is not bad
/// for someone bulking).
class MeasurementsCard extends ConsumerStatefulWidget {
  const MeasurementsCard({super.key});

  @override
  ConsumerState<MeasurementsCard> createState() => _MeasurementsCardState();
}

class _MeasurementsCardState extends ConsumerState<MeasurementsCard> {
  @override
  void initState() {
    super.initState();
    // An entry the Telegram pull wrote since the provider last built appears
    // when the screen opens. After the first frame (never during build), and
    // guarded: invalidating through an unmounted element throws a StateError.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(bodyMeasurementsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authUserIdTokenProvider) == '<anon>') {
      // The account-swap window: nothing, not an error caption whose Retry
      // cannot help.
      return const SizedBox.shrink();
    }
    final history = ref.watch(bodyMeasurementsProvider);
    // The frame caps this card's box at `cap` and puts the margin INSIDE the
    // cap, so the height this widget is offered plus the margin is the cap.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final cap = constraints.maxHeight + kCardMarginTop + kCardMarginBottom;
        final compact = bounded && cap < kMinCardCap + kMinTileWindow;
        final showBody =
            !compact && (!history.loaded || history.entries.isNotEmpty);
        Widget body = SingleChildScrollView(
          primary: false,
          child: history.loaded
              ? _Tiles(history: history)
              : _ErrorLine(
                  onRetry: () => ref.invalidate(bodyMeasurementsProvider),
                ),
        );
        if (bounded) body = Flexible(child: body);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.cardM),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onAdd: () => BodyMeasurementsSheet.show(context)),
              if (showBody) body,
            ],
          ),
        );
      },
    );
  }
}

/// The pinned header: the eyebrow and the Add button. A `Wrap`, so a label
/// that does not fit beside the eyebrow drops to a second run instead of
/// overflowing; clamped to x2.0 text so its height is bounded by design (the
/// tiles below keep the person's full scale).
///
/// The text is JetBrains Mono (0.6 em advance, 1.32 em line height, measured
/// from the font file). At a 360 dp phone and the default text size the two
/// runs together are 17 x (6 + 2) + 16 x (6 + 2) + 8 = 272 dp of the 282 dp
/// between the card's padding, so the header is ONE run there (with the
/// eyebrow's +3 spacing and 8 dp either side of the label it was 297 dp and
/// wrapped on that phone); `measurements_card_test.dart` pins that at an
/// Ahem scale of 0.6, whose advance is the same 0.6 em.
class _Header extends StatelessWidget {
  const _Header({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2.0,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Text(
            MeasurementCopy.sheetEyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 2,
            ),
          ),
          Semantics(
            button: true,
            excludeSemantics: true,
            label: MeasurementCopy.cardAddButton,
            onTap: onAdd,
            child: InkWell(
              onTap: onAdd,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        MeasurementCopy.cardAddButton,
                        maxLines: 1,
                        style: AppTypography.label.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
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

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            MeasurementCopy.loadError,
            style: AppTypography.bodyS.copyWith(color: AppColors.warn),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            foregroundColor: AppColors.accent,
          ),
          child: Text(MeasurementCopy.retry, style: AppTypography.label),
        ),
      ],
    );
  }
}

/// The two-up tiles, derived in `build()` from the history and the unit.
///
/// The unit is read once per history state, not once per layout pass: the card
/// rebuilds this widget on every constraint change (the keyboard animating
/// behind the sheet), and a unit read that keeps failing would otherwise report
/// `measurement_unit_read_failed` on each pass. A new history (the only way the
/// unit changes while the card is on screen: a save invalidates it) reads again.
class _Tiles extends ConsumerStatefulWidget {
  const _Tiles({required this.history});

  final BodyMeasurementsState history;

  @override
  ConsumerState<_Tiles> createState() => _TilesState();
}

class _TilesState extends ConsumerState<_Tiles> {
  late bool _inches;

  bool _readUnit() =>
      ref.read(measurementWriteProvider.notifier).preferredInches();

  @override
  void initState() {
    super.initState();
    // Only a card with tiles to show builds this widget, so a card with nothing
    // to show reads no unit at all.
    _inches = _readUnit();
  }

  @override
  void didUpdateWidget(_Tiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.history, widget.history)) _inches = _readUnit();
  }

  @override
  Widget build(BuildContext context) {
    final rows = measurementCardRows(
      entries: widget.history.entries,
      inches: _inches,
      todayIst: istTodayStr(),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final row in rows)
                SizedBox(
                  width: width,
                  child: _Tile(row: row),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.row});

  final MeasurementCardRow row;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      label: row.semanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.titleText,
            style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 2),
          Text(
            row.valueText,
            style: AppTypography.titleS.copyWith(color: AppColors.textPrimary),
          ),
          if (row.deltaText != null)
            Text(
              row.deltaText!,
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
            ),
        ],
      ),
    );
  }
}
