export function buildWindowClosingMessage(firstName: string | null, workoutName: string): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}haven't seen ${workoutName} logged yet. Still happening? Even 20 mins counts.`;
}
