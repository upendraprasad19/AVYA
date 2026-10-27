// Nutrition tool family.
// C.1 logMealByText, C.3 suggestMeal, C.5 getNutritionHistory.
// (C.2 adjustCaloricTarget + C.4 prelog removed 2026-05-31 — derive-only
// surface: calorie target stays derived; no pre-logging of future meals.)
export { logMealByTextTool } from "./logMealByText.ts";
export { suggestMealTool } from "./suggestMeal.ts";
export { getNutritionHistoryTool } from "./getNutritionHistory.ts";
