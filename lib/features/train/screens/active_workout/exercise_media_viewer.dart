// The logging viewer (Batch M2b Part B, OI-354): the full-screen view an
// exercise's 44 px still or ENLARGE chip opens on the active-workout screen.
//
// It is a LOGGING screen, not a picture: the animation, the set rows, the
// steppers and LOG pinned at the bottom, the four coaching sections below. The
// rows and LOG come from the card through an [ExerciseEntryHandle] and edit the
// card's OWN controllers, so there is one input surface with two hosts and one
// LOG path. LOG logs the exercise and returns to the workout; the back arrow
// returns to the same exercise WITHOUT logging.
//
// ⚠ The route is NON-opaque and sits on the BRANCH navigator (the one the
// screen's own page lives on), like every sheet on this screen:
//   * An opaque route would make the overlay build the covered entries with
//     `TickerMode` off, and flutter_riverpod PAUSES every `ref.watch` of a
//     consumer under it (`consumer.dart:390-413`): the screen and the card would
//     stop rebuilding, a `+` here would change the provider and no controller
//     would be appended.
//   * Only this route's own Scaffold paints, so the Scaffold is the ROOT and the
//     SafeArea goes INSIDE its body (a SafeArea above it would leave strips
//     through which the covered header shows).
//   * The covered tile freezes through Part A's `ModalRoute.isCurrentOf` rule;
//     a re-route inside the branch removes this pageless route with the page; a
//     branch switch hides it with its branch; the shell's bottom bar stays
//     visible and tappable.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_cues.dart';

import '../../providers/train_provider.dart';
import '../../services/log_exercise_logic.dart';
import 'exercise_entry_handle.dart';
import 'exercise_last_try_lines.dart';

/// The scroll region never gets less than this once an animation is drawn:
/// stacked LAST/TRY 32 + an 8 dp gap + the table header 13 + a 4 dp gap + three
/// 46 dp rows = 195 to the bottom of row 3, plus the scroll view's 10 dp top
/// padding (measured under Ahem).
const double kViewerScrollMinDp = 210;

/// Below this a square animation is a postage stamp: it is not drawn.
const double kViewerMinAnimDp = 100;

/// The animation is a square of at most this side, however wide the view.
const double kViewerMaxAnimDp = 480;

class ExerciseMediaViewer extends ConsumerStatefulWidget {
  const ExerciseMediaViewer({
    super.key,
    required this.exerciseName,
    required this.exerciseIndex,
    required this.media,
    this.entry,
  });

  final String exerciseName;
  final int exerciseIndex;
  final ExerciseMedia media;

  /// The card's rows and LOG row. Null when the LOG flag is off: the viewer is
  /// then the animation, LAST/TRY and the cues only.
  final ExerciseEntryHandle? entry;

  /// Pushes the viewer on the BRANCH navigator of [context] and returns the
  /// route, so the caller can await `route.popped` (it completes when the pop
  /// STARTS or the route is removed).
  static PageRoute<void> show(
    BuildContext context, {
    required String exerciseName,
    required int exerciseIndex,
    required ExerciseMedia media,
    ExerciseEntryHandle? entry,
  }) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final route = PageRouteBuilder<void>(
      opaque: false,
      maintainState: true,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, _, _) => ExerciseMediaViewer(
        exerciseName: exerciseName,
        exerciseIndex: exerciseIndex,
        media: media,
        entry: entry,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    unawaited(Navigator.of(context).push(route));
    return route;
  }

  @override
  ConsumerState<ExerciseMediaViewer> createState() =>
      _ExerciseMediaViewerState();
}

class _ExerciseMediaViewerState extends ConsumerState<ExerciseMediaViewer> {
  // Resolved ONCE: the viewer rebuilds every second (the workout timer) and on
  // every keystroke, so a library lookup in build() is out.
  late final ExerciseCues _cues;

  // This host's own focus nodes (one node cannot sit under two fields), created
  // on demand and disposed after the fields that hold them.
  final Map<(int, SetField), FocusNode> _nodes = {};

  // Cached in didChangeDependencies: both lookups throw once this State is
  // unmounted, and a late close (a LOG tap racing the back arrow, a post-frame
  // self-close after Android back) must stay a no-op rather than throw.
  ModalRoute<dynamic>? _route;
  NavigatorState? _navigator;

  bool _closeScheduled = false;

  @override
  void initState() {
    super.initState();
    _cues = exerciseCuesOf(
        ExerciseRepository.instance.getByExactName(widget.exerciseName));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _navigator = Navigator.of(context);
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode? _nodeFor(int setIdx, SetField field) =>
      _nodes.putIfAbsent((setIdx, field), FocusNode.new);

  /// EVERY way out goes through here: the back arrow, the LOG that logged, and
  /// the self-closing cases. It holds no flag: once a pop has started both
  /// `isCurrent` and `isActive` are false, so a second call does nothing (a
  /// bare `pop()` would take the screen's page). A route above the viewer (a
  /// sheet) makes it not current but still active: remove it from underneath.
  void _close() {
    final route = _route;
    final navigator = _navigator;
    if (route == null || navigator == null) return;
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  }

  /// The exercise this viewer was opened for is no longer at its index (swapped
  /// or removed) or the workout is over: close, once, after this frame.
  bool _gone(ActiveWorkoutData data) {
    final i = widget.exerciseIndex;
    return i < 0 ||
        i >= data.exercises.length ||
        data.exercises[i].name != widget.exerciseName ||
        data.isComplete;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(activeWorkoutProvider);
    final gone = _gone(data);
    if (gone && !_closeScheduled) {
      _closeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
    final entry = gone ? null : widget.entry;

    // `explicitChildNodes` is mandatory with `scopesRoute` (an assertion fires on
    // every build without it) and keeps the rows, LOG and cues out of the name.
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      container: true,
      label: widget.exerciseName,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          bottom: false,
          child: gone
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: LayoutBuilder(
                        key: const Key('exercise-viewer-body'),
                        builder: (context, c) => _body(context, c, data, entry),
                      ),
                    ),
                    if (entry != null) _pinnedLog(context, data, entry),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: WardroomCopy.activeViewerBackSemantics,
              excludeSemantics: true,
              onTap: _close,
              child: GestureDetector(
                key: const Key('exercise-viewer-back'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _close,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back,
                          size: 20, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          WardroomCopy.activeViewerBackLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              widget.exerciseName.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textPrimary,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The animation (a square sized by layout alone, so a keyboard shrinks it
  /// with no observer and no card fold) over ONE scroll view.
  Widget _body(
    BuildContext context,
    BoxConstraints c,
    ActiveWorkoutData data,
    ExerciseEntryHandle? entry,
  ) {
    final maxSide = math.min(c.maxWidth, kViewerMaxAnimDp);
    final side =
        (c.maxHeight - kViewerScrollMinDp).clamp(0.0, maxSide).toDouble();
    final exercise = data.exercises[widget.exerciseIndex];
    return Column(
      children: [
        if (side >= kViewerMinAnimDp)
          SizedBox(
            width: c.maxWidth,
            height: side,
            child: Center(
              child: SizedBox(
                key: const Key('exercise-viewer-animation'),
                width: side,
                height: side,
                child: ColoredBox(
                  color: AppColors.cardHi,
                  child: ExerciseAnimationView(
                    media: widget.media,
                    exerciseName: widget.exerciseName,
                    size: side,
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExerciseLastTryLines(
                  exerciseName: widget.exerciseName,
                  showTry: data.effectiveLoadFactor(exercise) >= 1.0,
                  fallbackReps: exercise.reps,
                  inline: true,
                ),
                if (entry != null) ...[
                  const SizedBox(height: 8),
                  entry.buildRows(context, data, _nodeFor),
                ],
                ..._cueSections(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// FORM, COMMON MISTAKES, BREATHING, WARM-UP: each hidden when empty.
  List<Widget> _cueSections() {
    return [
      if (_cues.cues.isNotEmpty)
        _CueSection(title: WardroomCopy.activeViewerFormTitle, lines: _cues.cues),
      if (_cues.mistakes.isNotEmpty)
        _CueSection(
            title: WardroomCopy.activeViewerMistakesTitle,
            lines: _cues.mistakes),
      if (_cues.breathing != null)
        _CueSection(
            title: WardroomCopy.activeViewerBreathingTitle,
            text: _cues.breathing),
      if (_cues.warmup != null)
        _CueSection(
            title: WardroomCopy.activeViewerWarmupTitle, text: _cues.warmup),
    ];
  }

  /// LOG pinned at the bottom of the BODY (not a `bottomNavigationBar`, which
  /// sits at the very bottom of a Scaffold, under the keyboard,
  /// `scaffold.dart:1048-1055`). The Scaffold resizes its body above the
  /// keyboard, so this row stays visible while typing.
  Widget _pinnedLog(
    BuildContext context,
    ActiveWorkoutData data,
    ExerciseEntryHandle entry,
  ) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: entry.buildLogRow(context, data, _nodeFor, _close),
        ),
      ),
    );
  }
}

/// One titled block of the cue area: dashed lines (FORM, COMMON MISTAKES) or a
/// plain sentence (BREATHING, WARM-UP).
class _CueSection extends StatelessWidget {
  const _CueSection({required this.title, this.lines = const [], this.text});

  final String title;
  final List<String> lines;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.textMute, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('–  ',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.accent)),
                  Expanded(
                    child: Text(line,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          if (text != null)
            Text(text!,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
