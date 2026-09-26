import { sanitizeIdentifier } from "../_shared/sanitize_for_prompt.ts";
import { istDayOfWeek } from "../_shared/ist_date.ts";

/**
 * Generate a FREE template-based morning alert (no AI cost).
 * Enhanced with milestone celebrations, PR shoutouts, and weight progress.
 */
export function generateFreeAlert(
  name: string,
  snapshotJson: Record<string, unknown> | null,
): string {
  const firstName = sanitizeIdentifier(name?.split(" ")[0], {
    fallback: "Champion",
    maxLen: 32,
  });
  const snap = snapshotJson ?? {};
  const streakWeeks = (snap.current_streak_weeks as number) ?? 0;
  const streakDays = (snap.current_streak_days as number) ?? streakWeeks * 7;
  const todayWorkout = snap.today_workout_name as string | null;
  const totalWorkouts = (snap.total_workouts_done as number) ?? 0;
  const recentPR = snap.recent_pr_exercise as string | null;
  const recentPRWeight = snap.recent_pr_weight as number | null;
  const weight = snap.current_weight_kg as number | null;
  const targetWeight = snap.target_weight_kg as number | null;
  const yesterdayCalories = snap.yesterday_calories as number | null;
  const calorieTarget = snap.daily_calorie_target as number | null;

  // Check for milestone events first — these take priority
  // Streak milestones
  if (streakDays === 7) {
    return `${firstName}, you just hit 7 DAYS straight! First week complete — that's the hardest one. ${todayWorkout ? `${todayWorkout} is up today.` : "Keep the momentum!"} Let's make it 14!`;
  }
  if (streakDays === 30) {
    return `30 DAYS, ${firstName}! A full month of consistency. You're in the top 5% of AVYA users. ${todayWorkout ? `${todayWorkout} today — let's go!` : "What a milestone!"}`;
  }
  if (streakDays === 50) {
    return `FIFTY DAYS, ${firstName}! Half a century of showing up for yourself. ${todayWorkout ? `${todayWorkout} is scheduled.` : "Legendary consistency."} You're built different.`;
  }
  if (streakDays === 100) {
    return `${firstName}, 100 DAYS! Triple digits. You've done what 99% of people only dream about. ${todayWorkout ? `Day 101 starts with ${todayWorkout}.` : "Unstoppable."}`;
  }

  // Workout count milestones
  if (totalWorkouts === 10) {
    return `Good morning ${firstName}! You've completed 10 workouts total — double digits! ${todayWorkout ? `${todayWorkout} is up next.` : "Keep building!"} Every session counts.`;
  }
  if (totalWorkouts === 50) {
    return `${firstName}, 50 workouts logged! That's serious dedication. ${todayWorkout ? `${todayWorkout} today.` : "You're crushing it."} Here's to the next 50!`;
  }
  if (totalWorkouts === 100) {
    return `100 WORKOUTS, ${firstName}! You've put in the work and it shows. ${todayWorkout ? `${todayWorkout} makes it 101.` : "Triple-digit warrior!"} Incredible.`;
  }

  // PR celebration
  if (recentPR) {
    const prDetail = recentPRWeight ? ` (${recentPRWeight}kg)` : "";
    return `Good morning ${firstName}! You hit a new PR on ${recentPR}${prDetail} recently! Momentum is real. ${todayWorkout ? `${todayWorkout} today — keep pushing.` : "Ride that wave!"}`;
  }

  // Weight milestone — close to target
  if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
    return `${firstName}, you're within 2kg of your goal weight! So close. ${todayWorkout ? `${todayWorkout} is scheduled today.` : "Every session brings you closer."} Keep going!`;
  }

  // Yesterday's nutrition win
  if (yesterdayCalories && calorieTarget && Math.abs(yesterdayCalories - calorieTarget) < 100) {
    return `Good morning ${firstName}! Yesterday you nailed your calorie target (${yesterdayCalories} kcal). ${todayWorkout ? `${todayWorkout} today.` : "Keep that precision going!"} Consistency wins.`;
  }

  // Default: standard greeting with workout + streak + motivational line
  let message = `Good morning ${firstName}!`;

  if (todayWorkout) {
    message += ` ${todayWorkout} is scheduled today.`;
  } else {
    message += ` Ready to crush your goals today?`;
  }

  if (streakDays > 0) {
    message += ` ${streakDays}-day streak going strong!`;
  } else if (streakWeeks > 0) {
    message += ` ${streakWeeks} week streak going strong!`;
  }

  const dayOfWeek = istDayOfWeek();
  const motivationalLines = [
    "Make today count!",
    "Consistency beats perfection.",
    "One workout at a time.",
    "Your future self will thank you.",
    "Small steps, big results.",
    "Show up for yourself today.",
    "Every rep matters.",
  ];
  message += ` ${motivationalLines[dayOfWeek]}`;

  return message;
}

/**
 * Bug #18 — PRO-light fallback. Used when a PRO user has no `user_daily_snapshots`
 * row for yesterday (e.g. they haven't been active enough for `pushSnapshot()` to fire).
 * Without this branch, PRO users would silently fall through to the generic free copy
 * — which is what Upen experienced. Personalised on name + primary_goal only, no AI cost.
 */
export function generateProLightAlert(name: string, primaryGoal: string | null): string {
  const firstName = sanitizeIdentifier(name?.split(" ")[0], {
    fallback: "Champion",
    maxLen: 32,
  });
  const goal = (primaryGoal ?? "").toLowerCase();

  if (goal === "build_muscle" || goal.includes("muscle")) {
    return `Good morning ${firstName}! Muscle is built one rep at a time — and today's another rep on the journey. Train hard, eat enough, and recover well. Let's get after it.`;
  }
  if (goal === "lose_fat" || goal.includes("fat") || goal.includes("loss")) {
    return `Good morning ${firstName}! Fat loss is won at the dinner table and the gym both. Stay disciplined with your calories today and move your body — small daily wins compound fast.`;
  }
  if (goal === "strength" || goal.includes("strong")) {
    return `Good morning ${firstName}! Strength is a long game. Focus on quality reps, log every set, and chase progressive overload. Today is another deposit in the bank.`;
  }
  if (goal.includes("endurance") || goal.includes("cardio")) {
    return `Good morning ${firstName}! Endurance is built mile by mile. Keep showing up, keep moving, and your aerobic base will thank you. Make today count.`;
  }
  if (goal === "general_fitness" || goal.includes("general") || goal.includes("fit")) {
    return `Good morning ${firstName}! Fitness isn't a destination — it's a daily habit. Move your body today, eat well, hydrate, and rest. You've got this.`;
  }

  // Generic fallback (still better than free copy because it uses the name)
  return `Good morning ${firstName}! Today is another opportunity to show up for the goals you set. Train smart, eat well, and trust the process. Let's go.`;
}
