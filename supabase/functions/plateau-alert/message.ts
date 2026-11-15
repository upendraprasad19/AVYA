export function buildPlateauMessage(firstName: string | null): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?`;
}
