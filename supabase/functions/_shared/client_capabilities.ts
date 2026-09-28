// supabase/functions/_shared/client_capabilities.ts
//
// Parses `client_capabilities` from an ai-proxy chat request body into a
// validated Set<string>. CLIENT-CONTROLLED input, so validated defensively:
// non-array -> empty set; only the first 32 raw entries are considered (a
// client cannot force unbounded validation work); each surviving entry must
// match ^[a-z_]{1,48}$ or is dropped; duplicates dedupe via Set.
//
// Spec: docs/superpowers/specs/2026-09-26-day-swapper-design.md §5.8.
// Capability string used by this batch: "swap_workout_days".

const MAX_ENTRIES = 32;
const ENTRY_PATTERN = /^[a-z_]{1,48}$/;

export function parseClientCapabilities(raw: unknown): Set<string> {
  if (!Array.isArray(raw)) return new Set();
  const out = new Set<string>();
  for (const entry of raw.slice(0, MAX_ENTRIES)) {
    if (typeof entry === "string" && ENTRY_PATTERN.test(entry)) {
      out.add(entry);
    }
  }
  return out;
}
