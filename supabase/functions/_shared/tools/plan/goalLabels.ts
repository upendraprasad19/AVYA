// Unit 3B (founder d73): the names a user sees for the three selectable goals, mirror of the client's
// `FitnessGoals.label` (lib/core/constants/fitness_goals.dart). Used by the plan tools' previewSummary, which the
// app shows verbatim on the confirm sheet, the in-chat bar and the confirm card. Pinned against the Dart table by
// test/contracts/ai_proxy_goal_enum_parity_test.dart.
export const GOAL_LABELS: Readonly<Record<string, string>> = {
  build_muscle: "Build",
  lose_fat: "Cut",
  general_fitness: "Maintain",
};

/** The label for [token]; an unknown token is shown as it is (the enums only admit the three). */
export function goalLabel(token: string): string {
  return GOAL_LABELS[token] ?? token;
}
