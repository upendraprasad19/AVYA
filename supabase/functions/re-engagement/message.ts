export function buildReengagementMessage(firstName: string | null): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.`;
}
