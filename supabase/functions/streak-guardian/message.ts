export interface StreakInput {
  streakDays: number;
  streakWeeks: number;
  weight: number | null;
  targetWeight: number | null;
}

export interface StreakMessage {
  title: string;
  message: string;
}

function standardVariants(weeks: number, days: number): string[] {
  return [
    `It's getting late. Your ${weeks}-week streak is waiting for today's workout.`,
    `${days} days of consistency so far. One workout keeps it alive.`,
    `You didn't come this far to only come this far. ${weeks} weeks and counting!`,
    `Your future self will thank you. Log a workout before midnight to keep your streak.`,
  ];
}

export function pickStreakMessage(input: StreakInput): StreakMessage {
  const { streakDays, streakWeeks, weight, targetWeight } = input;

  if (streakDays === 7) {
    return { title: "1 week strong!", message: "You've hit 7 days straight — that's the hardest week done. Don't stop now!" };
  }
  if (streakDays === 14) {
    return { title: "2 weeks! You're building a habit.", message: "14 days of consistency. Most people quit by now — you didn't. Keep going!" };
  }
  if (streakDays === 30) {
    return { title: "30-day warrior!", message: "A full month of training. You're in the top 5% of users. Log today to keep it alive!" };
  }
  if (streakDays === 50) {
    return { title: "50 days. Legendary.", message: "Half a century of consistency. This streak is worth protecting — don't miss today!" };
  }
  if (streakDays === 100) {
    return { title: "100-DAY STREAK!", message: "Triple digits. You're officially unstoppable. One workout away from 101!" };
  }
  if (streakDays % 10 === 0 && streakDays > 10) {
    return {
      title: `${streakDays}-day milestone!`,
      message: `${streakDays} days of showing up. That's elite. Don't let today be the one you miss.`,
    };
  }
  if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
    return { title: "Almost at your goal weight!", message: "You're within 2kg of your target. Don't miss today — every session counts now." };
  }

  const variants = standardVariants(streakWeeks, streakDays);
  return { title: "Don't break your streak!", message: variants[streakDays % variants.length] };
}
