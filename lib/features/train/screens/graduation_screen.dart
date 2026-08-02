import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/features/train/widgets/keep_training_phase1_action.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';
import 'package:icanbefitter/shared/services/pro_phase_advance.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/train_provider.dart';
import '../widgets/advance_choice_sheet.dart';

/// Phase 1 Graduation Ceremony — the #1 conversion moment.
///
/// Full-screen celebration with:
/// - Stats from Phase 1 (streak, workouts, PRs)
/// - Blurred Phase 2 structure preview
/// - "Continue Your Journey" CTA -> PaywallSheet for phases_2_to_12
class GraduationScreen extends ConsumerWidget {
  const GraduationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(graduationStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding),
              children: [
                const SizedBox(height: 32),

                // Trophy icon
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.proGold.withValues(alpha: 0.2),
                          AppColors.proGold.withValues(alpha: 0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.proGold.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: AppColors.proGold,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Congrats headline
                Center(
                  child: Text(
                    'PHASE 1 COMPLETE',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      color: AppColors.proGold,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Week Four',
                    style: AppTypography.display.copyWith(height: 1.05),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'You built the foundation. Time to level up.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textDim,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 18),
                const WardRule(gold: true, margin: EdgeInsets.zero),
                const SizedBox(height: 22),

                // Stats grid
                _buildStatsGrid(stats),
                const SizedBox(height: 24),

                // Phase 2 Preview (blurred)
                _buildPhase2Preview(),
                const SizedBox(height: 24),

                // What Phase 2 unlocks
                _buildPhase2Benefits(),
                const SizedBox(height: 24),

                // CTA — Continue Your Journey
                _buildCta(context, ref),
                const SizedBox(height: 12),

                // Stay on Phase 1 link — runs redoWeek4() first so the
                // user actually HAS workouts to land on. Before the
                // 2026-04-18 fix (audit M22) this button routed to
                // /train on an exhausted Phase 1 schedule → empty page
                // → dead link.
                Center(
                  child: GestureDetector(
                    onTap: () => keepTrainingPhase1(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'KEEP TRAINING PHASE 1',
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(GraduationStatsData stats) {
    return WardCard(
      variant: WardCardVariant.hero,
      child: Column(
        children: [
          Text(
            'YOUR PHASE 1 JOURNEY',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${stats.totalWorkouts}',
                  label: 'WORKOUTS',
                  icon: Icons.fitness_center,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.streakWeeks}',
                  label: 'WEEK STREAK',
                  icon: Icons.local_fire_department,
                  color: AppColors.warn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${stats.totalSets}',
                  label: 'TOTAL SETS',
                  icon: Icons.repeat,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.personalRecords}',
                  label: 'PRS SET',
                  icon: Icons.emoji_events,
                  color: AppColors.proGold,
                ),
              ),
            ],
          ),

          // Top PRs
          if (stats.topPrs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const WardRule(margin: EdgeInsets.zero),
            const SizedBox(height: 12),
            Text(
              'TOP PERSONAL RECORDS',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            ...stats.topPrs.take(3).map((pr) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: AppColors.proGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pr.exerciseName,
                          style: AppTypography.h3.copyWith(fontSize: 13),
                        ),
                      ),
                      Text(
                        pr.value,
                        style: AppTypography.h3.copyWith(
                          fontSize: 13,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _statTile({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase2Preview() {
    // Theme J (diagnose 2026-05-23 14e8a5) — pre-fix this was hardcoded to
    // '5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY' + a static 5-day
    // template (Day 1: Upper Power, …). For a 4-day-per-week user, the
    // preview misrepresents what they're about to unlock — the actual
    // generateAndSchedule call at line 533 uses their real days_per_week
    // and generates a different split. Fix: dry-run PlanGenerator.generateV4
    // with the user's actual profile + next phase number, then render the
    // returned WeekPlan.workoutDays. Pure call (no Hive writes, no side
    // effects); same code path previewPlanProvider uses.
    final profile = UserRepository.instance.getProfile() ?? {};
    final progress = UserRepository.instance.getProgress() ?? {};
    final currentPhase = (progress['current_phase'] as int?) ?? 1;
    // 2026-05-31 (post-12 deployment cycles): phase number is MONOTONIC so
    // deployments_complete keeps counting. The plan engine recycles the
    // advanced phase-9-12 CONTENT internally (PlanGenerator._getPhaseMeta +
    // periodization) — the number itself never cycles back.
    final nextPhase = currentPhase + 1;
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    final goal =
        profile['primary_goal'] as String? ?? 'general_fitness';
    final equipment =
        profile['equipment_access'] as String? ?? 'basic_gym';
    final experienceLevel =
        profile['fitness_experience'] as String? ?? 'intermediate';
    final injuries = (profile['injuries'] as List?)
            ?.whereType<String>()
            .where((s) => s != 'none')
            .toList() ??
        const <String>[];

    // Phase title + focus line. Phase 2 (Progressive Overload) was the
    // canonical pre-fix copy; later phases extend the same pattern.
    final phaseLabel = 'PHASE $nextPhase';
    final weekRange =
        'WEEKS ${(nextPhase - 1) * 4 + 1}-${nextPhase * 4}';

    // Try the real plan generator; fall back to a single summary line
    // if the call throws (defensive — never block graduation render).
    List<_PreviewDay>? previewDays;
    String? phaseTitle;
    String? focus;
    try {
      final phase = PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        phase: nextPhase,
        experienceLevel: experienceLevel,
        injuries: injuries,
      );
      phaseTitle = _phaseDisplayName(nextPhase);
      focus = _phaseFocus(nextPhase);
      final firstWeek = phase.weekPlans.isNotEmpty
          ? phase.weekPlans.first
          : null;
      final days = firstWeek?.workoutDays ?? phase.workouts;
      previewDays = days
          .take(5)
          .map((d) => _PreviewDay(
                title: d.name,
                exercises: d.exercises
                    .take(3)
                    .map((e) => e.exerciseName)
                    .join(', '),
              ))
          .toList();
    } catch (e, st) {
      debugPrint('[GraduationScreen._buildPhase2Preview] $e\n$st');
      unawaited(ErrorTelemetry.logEvent('graduation_phase2_preview_failed',
          message: 'phase=$nextPhase err=${e.toString().substring(0, e.toString().length.clamp(0, 200))}'));
    }

    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WardChip(label: phaseLabel, tone: WardChipTone.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phaseTitle ?? 'Progressive Overload',
                  style: AppTypography.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$daysPerWeek DAYS/WEEK · $weekRange · '
            '${focus ?? "Power + Hypertrophy".toUpperCase()}',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          // Day names visible (actual generator output), exercise names blurred.
          // Local non-nullable alias so List.generate closure captures a
          // promoted type (Dart flow analysis doesn't promote across
          // closure boundaries).
          if (previewDays != null && previewDays.isNotEmpty) ...[
            for (final entry in previewDays.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Day ${entry.key + 1}: ${entry.value.title}',
                      style: AppTypography.h3.copyWith(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Text(
                          entry.value.exercises.isNotEmpty
                              ? entry.value.exercises
                              : 'Exercises personalised to you...',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.textDim,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ]
          else
            // Defensive fallback when generateV4 throws — single
            // descriptive line keeps the surface meaningful.
            Text(
              '$daysPerWeek workout days personalised to your goal + equipment',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhase2Benefits() {
    const benefits = [
      'New exercises with progressive overload',
      'Power + hypertrophy split for faster gains',
      'AI-personalised workout adjustments',
      'Advanced coaching cues and PRO tips',
      'Phases 2-12 unlock full 48-week journey',
    ];

    return WardCard(
      variant: WardCardVariant.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT PHASE 2 UNLOCKS',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          ...benefits.map((benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        benefit,
                        style: AppTypography.body,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildCta(BuildContext context, WidgetRef ref) {
    return const _GenerateNextPhaseButton();
  }
}

/// Theme F (diagnose 2026-05-22 ec4d27) — extracted into a ConsumerStatefulWidget
/// so we can drive `_isGenerating` loading state, fire the 4 lifecycle
/// telemetry events, run the canonical provider-invalidation set after
/// successful generation, and show a success snackbar before navigation.
///
/// Pre-fix: the whole flow was a one-shot async lambda — button looked
/// dead during the multi-second generate; on success the user landed on
/// /train with stale providers (currentPlanProvider / todayWorkoutProvider
/// / calendarWeekProvider all cached the pre-unlock state) and saw the
/// "PHASE I COMPLETE" graduation card still in the UI.
class _GenerateNextPhaseButton extends ConsumerStatefulWidget {
  const _GenerateNextPhaseButton();

  @override
  ConsumerState<_GenerateNextPhaseButton> createState() =>
      _GenerateNextPhaseButtonState();
}

class _GenerateNextPhaseButtonState
    extends ConsumerState<_GenerateNextPhaseButton> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return WardButton(
      label: _isGenerating ? 'LOCKING IN YOUR PLAN…' : 'GENERATE NEXT PHASE',
      leading: _isGenerating
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.bgDeep),
              ),
            )
          : const Icon(Icons.rocket_launch,
              size: 16, color: AppColors.bgDeep),
      onPressed: _isGenerating ? null : _onTap,
    );
  }

  void _onTap() {
    // Theme F telemetry — fire BEFORE the gate so we know the tap fired
    // even when the gate routes onFree (paywall) or onPro (continue).
    unawaited(ErrorTelemetry.logEvent('phase_unlock_initiated',
        message: 'tap=GENERATE_NEXT_PHASE'));
    SubscriptionService.instance.gateAndVerify(
      AppConstants.featurePhases2To12,
      onPro: _onPro,
      onFree: () {
        unawaited(ErrorTelemetry.logEvent('phase_unlock_gate_routed_free',
            message: 'feature=phases_2_to_12'));
        showPaywallSheet(context, feature: 'Phases 2-12');
      },
    );
  }

  Future<void> _onPro() async {
    unawaited(ErrorTelemetry.logEvent('phase_unlock_gate_routed_pro',
        message: 'feature=phases_2_to_12'));
    if (!mounted) return;
    final stopwatch = Stopwatch()..start();
    try {
      final profile = UserRepository.instance.getProfile() ?? {};
      final progress = UserRepository.instance.getProgress() ?? {};
      final currentPhase = (progress['current_phase'] as int?) ?? 1;
      // 2026-05-31 (post-12 deployment cycles): MONOTONIC phase number so
      // deployments_complete keeps counting toward PO/CPO/officer ranks. The
      // plan engine recycles phase-9-12 content internally; the number doesn't
      // cycle back (the old `9 + ((currentPhase-8) % 4)` froze the counter).
      final nextPhase = currentPhase + 1;

      final scheduleSvc = ref.read(workoutScheduleReadServiceProvider);

      // ⑧ 3-b (W2.5, ship-dark): on a LOW-adherence advance, OFFER a choice —
      // repeat the just-finished phase's drills (detrained) or take fresh
      // orders; the phase advances EITHER way (F3). The flag short-circuits so
      // the ~90-Hive-read currentPhaseCompletionRate() is NEVER evaluated when
      // OFF → then no sheet, no abort-check, VERBATIM generation.
      var choice = AdvanceChoice.advance;
      final offerChoice = PlanEngineFlags.adherenceGateEnabled &&
          shouldOfferAdvanceChoice(
            completionRate: scheduleSvc.currentPhaseCompletionRate(),
            threshold: AppConstants.phaseUnlockCompletionRate,
          );
      if (offerChoice) {
        choice = await showAdvanceChoiceSheet(context) ?? AdvanceChoice.advance;
        if (!mounted) return;
      }

      if (!mounted) return;
      // abort-if-changed: if a concurrent splash/card/coach advance bumped the
      // phase — while the choice sheet was open, or at any point before this
      // tap — DON'T recompute nextPhase (that would SKIP a phase), and don't
      // regenerate a plan for a phase the user is already on. Route to /train.
      //
      // Unit 3c (OI-45 finding 5): this check used to sit INSIDE the
      // `if (offerChoice)` block above, and `offerChoice` requires
      // PlanEngineFlags.adherenceGateEnabled — ship-dark, DEFAULT OFF
      // (plan_engine_flags.dart) — so on the production default path it never
      // executed at all. Hoisted out so it runs on every unlock.
      //
      // Precise about what that buys, because round-1 review caught the
      // over-claim: on the flag-OFF path there is NO await between the
      // `progress` read above and this line, so `live == currentPhase` always
      // and this early-out cannot fire. It is load-bearing only across the
      // choice-sheet await (flag ON) — and it becomes so the moment that flag
      // flips. The default path's real protection is the shared advance lock
      // below plus commitPhaseAdvance's re-read at write time.
      final live =
          (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
      if (live >= nextPhase) {
        // The concurrent advancer bumped the phase — refresh the plan views
        // before routing so /train doesn't briefly show the pre-advance plan.
        ref.invalidate(currentPlanProvider);
        ref.invalidate(todayWorkoutProvider);
        context.go('/train');
        return;
      }

      setState(() => _isGenerating = true);

      // Unit 3c (OI-45 finding 5): generation + the progress write run under the
      // SHARED phase-advance mutex, the same one advanceProPhaseIfExpired uses.
      // Before this, graduation generated entirely outside that guard, so the
      // splash's unawaited pass (or the Home/Train card CTA) could be generating
      // this very phase concurrently — two generateAndSchedule runs writing
      // overlapping schedule_* rows and each moving plan_start, the second
      // silently overwriting the first under a user already looking at the plan.
      //
      // The lock is taken AFTER the choice sheet closes, never across it: a
      // modal waiting on human input must not block the splash's advance.
      // `null` (not `false`) means "someone else holds it" — distinct from
      // `false`, which means we generated but the monotonic writer declined.
      final advanced = await withPhaseAdvanceLock<bool?>(
        () async {
          // B-pass F1: re-check the live phase ONCE MORE, now that the lock is
          // actually held. The check above ran before acquisition, and the
          // restore-path writers tracked as OI-83 do not take this lock at all
          // — so a bump could have landed in between. Catching it HERE avoids
          // running a full plan generation whose schedule_* rows would then be
          // written for a phase the user is already past, with commitPhaseAdvance
          // correctly declining the counter write afterwards and nothing
          // reconciling the rows. Cheap (one Hive read) versus a generate.
          final liveInLock =
              (UserRepository.instance.getProgress()?['current_phase'] as int?) ??
                  1;
          if (liveInLock >= nextPhase) {
            // Distinct from the post-generate decline below: nothing was
            // generated here, so the two must not share one event name.
            unawaited(ErrorTelemetry.logEvent(
                'phase_unlock_preempted_before_generate',
                message: 'live=$liveInLock intended=$nextPhase'));
            return false;
          }

          // graduation's OWN profile defaults — the SAME values MUST feed both the
          // pin-build and the generate, or repeatPinsFrom's G5 gate validates a
          // different frame-shape than the one generated (writer/reader value drift).
          final goal = profile['primary_goal'] as String? ?? 'general_fitness';
          final equipment =
              profile['equipment_access'] as String? ?? 'basic_gym';
          final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
          final experienceLevel =
              profile['fitness_experience'] as String? ?? 'beginner';

          final savedDays = MigratedKey.read<List>('preferred_training_days');
          final preferredDays =
              savedDays is List ? savedDays.cast<int>() : null;

          // Theme H fix — nextPhaseStartDate computes max(today, currentPhaseEnd + 1)
          // Monday-normalized (was DateTime.now() → overwrote the current W4 rows).
          final startDate = scheduleSvc.nextPhaseStartDate();

          // Build repeat pins BEFORE generateAndSchedule overwrites plan_start
          // (getWeek reads the just-finished window). Only on an explicit "repeat".
          final pins = choice == AdvanceChoice.repeat
              ? scheduleSvc.buildRepeatPinsForAdvance(
                  goal: goal,
                  equipment: equipment,
                  daysPerWeek: daysPerWeek,
                  experienceLevel: experienceLevel,
                  newPhase: nextPhase,
                )
              : null;

          // W3.4 (Batch 11-B): variety avoid-names on a fresh advance (reader self-gates on the flag; read before plan_start moves, like pins).
          final previousPhaseByDay =
              pins == null ? scheduleSvc.previousPhaseNamesByDay() : null;

          await scheduleSvc.generateAndSchedule(
            goal: goal,
            equipment: equipment,
            daysPerWeek: daysPerWeek,
            startDate: startDate,
            phase: nextPhase,
            // U4: thread injuries so the graduated next-phase plan excludes
            // contraindicated exercises (vocab canonicalized in generateV4).
            injuries: InjuryVocab.fromProfile(profile['injuries']),
            experienceLevel: experienceLevel,
            preferredDays: preferredDays,
            pinnedExercisesByDay: pins,
            // W2.7 (Batch 9): titrate ONLY a FRESH advance (pins == null) — a
            // low-adherence "repeat" (pins != null) must not gain volume.
            applyVolumeTitration: pins == null,
            previousPhaseByDay: previousPhaseByDay,
            applyPlateauEscalation:
                pins == null, // W3.5 12-A: fresh-advance-only
          );
          unawaited(ErrorTelemetry.logEvent('phase_unlock_plan_generated',
              message: 'phase=$nextPhase ms=${stopwatch.elapsedMilliseconds}'));

          // Theme F — stamp plan_generated_at; UserRepository.updateProgress
          // fires syncProgressNow so this push lands on cloud.
          //
          // Unit 3c (OI-45 finding 5): `nextPhase` was computed at the TOP of
          // this method, before the tens-to-hundreds-of-ms generateAndSchedule
          // above. commitPhaseAdvance re-reads the live phase HERE and refuses
          // to write a lower one — `current_phase` has no monotonic guard in
          // saveProgress, so a concurrent advancer landing in that window used
          // to be silently demoted.
          final committed = await commitPhaseAdvance(
            intendedPhase: nextPhase,
            source: 'graduation_screen',
          );

          // ⑧ 3-b: a chosen "repeat" (pins applied) flags the Home "step it up
          // next time" nudge (cross-account gated in the shared writer) +
          // invalidates the provider so it surfaces this session, not only
          // after an app relaunch.
          if (pins != null) {
            await markPhaseRepeatNudgePending();
            ref.invalidate(phaseRepeatNudgeProvider);
          }
          return committed;
        },
        ifBusy: null,
      );

      if (!mounted) return;
      if (advanced == null) {
        // Another advance path holds the lock and is generating this same phase
        // right now. Same recourse the PhaseGeneratingCard already gives on its
        // own busy path — tell the user plainly and put them on /train, where
        // the plan appears the moment that pass lands.
        unawaited(ErrorTelemetry.logEvent('phase_unlock_advance_busy',
            message: 'phase=$nextPhase'));
        ref.invalidate(currentPlanProvider);
        ref.invalidate(todayWorkoutProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.card,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              'Still finishing up your next phase — opening your plan…',
              style: AppTypography.bodySm.copyWith(color: AppColors.accent),
            ),
          ),
        );
        context.go('/train');
        return;
      }

      // Theme F — provider invalidation set. Matches the canonical post-
      // workout-completion batch from train_provider.dart:1494-1500. The
      // train screen + home screen pull from these providers; without
      // invalidation they cache pre-unlock state and the founder lands
      // on /train still seeing "PHASE I COMPLETE".
      ref.invalidate(currentPlanProvider);
      ref.invalidate(todayWorkoutProvider);
      ref.invalidate(calendarWeekProvider);
      ref.invalidate(workoutStatsProvider);
      ref.invalidate(streakProvider);
      ref.invalidate(allExercisePRsProvider);
      ref.invalidate(aiInsightProvider);
      ref.invalidate(graduationStatsProvider);

      // Unit 3c: `advanced == false` means the plan rows for nextPhase WERE
      // generated but commitPhaseAdvance declined the counter write, because a
      // concurrent advancer had already moved it to this phase or past it.
      // Firing phase_unlock_completed there would assert a write that never
      // happened — the false-signal class this whole batch exists to remove —
      // so the two outcomes get distinct events and distinct copy.
      unawaited(ErrorTelemetry.logEvent(
          advanced
              ? 'phase_unlock_completed'
              : 'phase_unlock_counter_already_advanced',
          message: 'phase=$nextPhase ms=${stopwatch.elapsedMilliseconds}'));

      if (!mounted) return;
      // Success snackbar — pre-fix the user got no feedback on success;
      // the immediate navigate hid the "did anything happen?" question.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            side: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.5)),
          ),
          content: Text(
            advanced
                ? 'Phase $nextPhase unlocked — opening your new plan…'
                : 'Your new plan is ready — opening it now…',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.accent),
          ),
        ),
      );
      context.go('/train');
    } catch (e) {
      final errStr = e.toString();
      final clipped =
          errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'train_graduation_generate_phase_2_failed',
          message:
              'ms=${stopwatch.elapsedMilliseconds} err=$clipped'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            side: BorderSide(color: AppColors.bad.withValues(alpha: 0.3)),
          ),
          content: Text(
            'Failed to generate next phase: $e',
            style: AppTypography.bodySm.copyWith(color: AppColors.bad),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}

/// Theme J — preview day cell used by graduation phase 2 card. Holds the
/// generated workout-day name + a comma-joined string of the first 3
/// exercises (rendered behind a blur to tease without revealing).
class _PreviewDay {
  final String title;
  final String exercises;
  const _PreviewDay({required this.title, required this.exercises});
}

/// Display name per phase. Mirrors the canonical plan-generator copy.
/// Falls back to `'Phase $n'` if the phase number is outside 1-12.
String _phaseDisplayName(int phase) {
  const names = {
    1: 'Foundation',
    2: 'Progressive Overload',
    3: 'Intensification',
    4: 'Power Build',
    5: 'Hypertrophy Peak',
    6: 'Strength Cycle',
    7: 'Conditioning Push',
    8: 'Power Hypertrophy',
    9: 'Specialisation',
    10: 'Strength Peak',
    11: 'Conditioning Peak',
    12: 'Mastery',
  };
  return names[phase] ?? 'Phase $phase';
}

/// Per-phase focus subtitle. Used in the meta line. Uppercased at the
/// callsite.
String _phaseFocus(int phase) {
  const focus = {
    1: 'Foundation + technique',
    2: 'Power + hypertrophy',
    3: 'Volume + intensification',
    4: 'Power build',
    5: 'Hypertrophy peak',
    6: 'Strength cycle',
    7: 'Conditioning + power',
    8: 'Power + hypertrophy',
    9: 'Specialisation',
    10: 'Strength peak',
    11: 'Conditioning peak',
    12: 'Mastery',
  };
  return (focus[phase] ?? 'Progressive overload').toUpperCase();
}
