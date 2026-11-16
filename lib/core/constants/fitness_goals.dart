/// Canonical source-of-truth for the app's fitness goals.
///
/// Onboarding emits a goal *key* (`goal_screen.dart`) which `plan_screen._mapGoal`
/// translates to a canonical *token* stored at `user_profile.primary_goal`. EVERY
/// consumer of that token reads from this one map:
///  - `BmrCalculator` — calorie + protein + fat targets (via `deltaMult` /
///    `proteinPerKg` / `fatPercentage`),
///  - the plan engine (`PlanGenerator` → `SplitResolver` + `ExerciseSelector`) —
///    training architecture (via `planGoal`),
///  - `CardioFinisher` / `PlanGenerator` — whether to attach cardio (via `cardio`),
///  - the display readers (profile + coach diffs) — human label (via `label`).
///
/// So a goal token can never again silently fall through a `default` branch
/// (which is exactly how `'recompose'` got maintenance calories + the lowest
/// protein — diagnose 2026-06-07 recompose-default-maintenance / audit F19).
///
/// Adding or changing a goal is a one-row edit here; the exhaustiveness gate
/// (`scripts/check_goal_token_exhaustiveness.dart`) then forces every consumer +
/// every onboarding key to line up.
class FitnessGoalSpec {
  /// Canonical `primary_goal` token.
  final String token;

  /// Human label for the goal value (profile card, coach goal diffs, etc.).
  final String label;

  /// Multiplier applied to the pace-derived daily kcal delta:
  /// `dailyCalories = tdee + deltaMult * dailyKcalDelta`.
  /// +1.0 full surplus · -1.0 full deficit · +0.5 / -0.5 modest · 0.0 maintenance.
  final double deltaMult;

  /// Protein target in grams per kg of (target) body weight.
  final double proteinPerKg;

  /// Fat as a fraction of daily calories.
  final double fatPercentage;

  /// Token the plan engine (split resolver + exercise selector) should use.
  /// Recomposition trains like a hypertrophy build, so it maps to `build_muscle`
  /// — the plan engine therefore never sees `'recompose'`.
  final String planGoal;

  /// Whether the plan generator attaches a `CardioFinisher`.
  final bool cardio;

  const FitnessGoalSpec({
    required this.token,
    required this.label,
    required this.deltaMult,
    required this.proteinPerKg,
    required this.fatPercentage,
    required this.planGoal,
    required this.cardio,
  });
}

class FitnessGoals {
  FitnessGoals._();

  /// Applied when a token is missing/unknown — defensive only; the onboarding
  /// keys are all mapped (enforced by the exhaustiveness gate).
  static const String defaultToken = 'general_fitness';

  static const Map<String, FitnessGoalSpec> _byToken = {
    'build_muscle': FitnessGoalSpec(
      token: 'build_muscle',
      label: 'Build',
      deltaMult: 1.0, // full pace-scaled surplus
      proteinPerKg: 1.8,
      fatPercentage: 0.25,
      planGoal: 'build_muscle',
      cardio: false,
    ),
    'lose_fat': FitnessGoalSpec(
      token: 'lose_fat',
      label: 'Cut',
      deltaMult: -1.0, // full pace-scaled deficit
      proteinPerKg: 2.0, // higher protein during a cut
      fatPercentage: 0.25,
      planGoal: 'lose_fat',
      cardio: true,
    ),
    'strength': FitnessGoalSpec(
      token: 'strength',
      label: 'Strength',
      deltaMult: 0.5, // modest surplus (half pace delta)
      proteinPerKg: 1.8,
      fatPercentage: 0.30,
      planGoal: 'strength',
      cardio: false,
    ),
    'general_fitness': FitnessGoalSpec(
      token: 'general_fitness',
      label: 'Maintain',
      deltaMult: 0.0, // maintenance — pace has no effect
      proteinPerKg: 1.6,
      fatPercentage: 0.25,
      planGoal: 'general_fitness',
      cardio: true,
    ),
    // Recomposition: lose fat + hold/build muscle at once. Slight deficit (half
    // the pace delta) + high protein + a hypertrophy split + light cardio.
    // Brainstorm-locked 2026-06-07 — was silently hitting BmrCalculator's
    // `default` (maintenance calories + 1.6 protein) and the fat-loss split.
    'recompose': FitnessGoalSpec(
      token: 'recompose',
      label: 'Recomposition',
      deltaMult: -0.5, // modest deficit
      proteinPerKg: 2.0, // hold muscle through the deficit
      fatPercentage: 0.25,
      planGoal: 'build_muscle', // hypertrophy training architecture
      cardio: true, // light cardio finisher (shape from cardioPreference)
    ),
  };

  /// Every canonical goal token, legacy ones included: a stored value may still hold `strength` or `recompose`
  /// (older builds write them; restore brings them back), and every reader keeps serving them until
  /// `LegacyGoalHealer` moves the stored value (Unit 3B, d69).
  static List<String> get tokens => _byToken.keys.toList(growable: false);

  /// The goals a user can choose (Unit 3B, founder d69: "We only have build, cut and maintain"), in the onboarding
  /// cards' order. Every goal picker (onboarding cards, Edit Profile, the coach compass form) and every goal check
  /// on a write the user or the coach starts (the coach dispatcher, the server tool enums) uses this list.
  static const List<String> selectableTokens = ['build_muscle', 'lose_fat', 'general_fitness'];

  /// Whether [token] is a goal a user can choose ([selectableTokens]).
  static bool isSelectable(String? token) => token != null && selectableTokens.contains(token);

  /// Where a legacy goal goes (Unit 3B: d4 Strength -> Build, with the Strength focus applied by
  /// `legacyGoalPatch`; d72 Recomposition -> Cut). Its keys are exactly [tokens] minus [selectableTokens], and equal
  /// the goal gate's `kLegacyReachableOnlyGoalTokens` (pinned by `fitness_goals_selectable_test.dart`).
  static const Map<String, String> legacyTargets = {'strength': 'build_muscle', 'recompose': 'lose_fat'};

  /// What the coach's goal previews and the dispatcher say when a proposed goal is not selectable (a live coach
  /// can still propose `strength` / `recompose` until ai-proxy carries the three-goal enums, or a replayed intent).
  static const String notOfferedMessage = "That goal isn't offered any more. Choose Build, Cut or Maintain.";

  static bool isKnown(String token) => _byToken.containsKey(token);

  /// The spec for [token]. Falls back to [defaultToken] for an unknown token,
  /// asserting in debug so tests + the gate surface a missing mapping rather
  /// than letting it silently default (the F19 failure mode).
  static FitnessGoalSpec of(String token) {
    final spec = _byToken[token];
    if (spec != null) return spec;
    assert(
      false,
      'Unknown fitness goal token "$token". Add it to FitnessGoals._byToken '
      '(scripts/check_goal_token_exhaustiveness.dart enforces this).',
    );
    return _byToken[defaultToken]!;
  }

  /// Human label for a goal token (profile + coach goal-diff display readers).
  static String label(String token) => of(token).label;
}
