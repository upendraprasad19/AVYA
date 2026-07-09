// supabase/functions/_shared/coach_memory.ts
// Shared accessors for the coach_memory table. Used by ai-proxy,
// daily-snapshot, compute-coach-signals, morning-alert.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

export interface CoachMemory {
  user_id: string;
  preferred_name: string | null;
  communication_style: "hinglish" | "english" | "formal" | "casual" | null;
  humor_tolerance: "high" | "low" | "none" | null;
  depth_preference: "explanation_seeker" | "action_taker" | null;
  motivation_style: "tough_love" | "gentle" | "data_driven" | null;
  injuries: unknown[];
  food_preferences: Record<string, unknown>;
  equipment_notes: string | null;
  excuse_patterns: unknown[];
  lifestyle: Record<string, unknown>;
  supplement_stack: unknown[];
  peak_activity_hour: number | null;
  weak_day: string | null;
  cheat_day_pattern: string | null;
  dropout_risk_score: number | null;
  plateau_risk_score: number | null;
  pro_upgrade_probability: number | null;
  signals_computed_at: string | null;
  last_proactive_type: string | null;
  last_extraction_at: string | null;
  consent_version: string;
  private_mode: boolean;
  coach_notes: string | null;
  updated_at: string;
}

export type CoachMemoryPatch = Partial<Omit<CoachMemory, "user_id" | "updated_at">>;

export async function fetchCoachMemory(
  supabase: SupabaseClient,
  userId: string,
): Promise<CoachMemory | null> {
  const { data, error } = await supabase
    .from("coach_memory")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("[coach_memory.fetch] error:", error.message);
    return null;
  }
  return (data as CoachMemory) ?? null;
}

export async function upsertCoachMemory(
  supabase: SupabaseClient,
  userId: string,
  patch: CoachMemoryPatch,
): Promise<void> {
  // Strip undefined so we don't overwrite existing values with NULL.
  const cleanPatch: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(patch)) {
    if (v !== undefined) cleanPatch[k] = v;
  }
  if (Object.keys(cleanPatch).length === 0) return;

  const { error } = await supabase
    .from("coach_memory")
    .upsert({ user_id: userId, ...cleanPatch }, { onConflict: "user_id" });
  if (error) {
    console.error("[coach_memory.upsert] error:", error.message);
    throw error;
  }
}

/**
 * Renders the coach_memory row as a system-prompt fragment (block [3]
 * of the 7-block context layout). Returns empty string when row is null
 * or private_mode is on.
 */
export function renderCoachMemoryBlock(mem: CoachMemory | null): string {
  if (!mem || mem.private_mode) return "";

  const lines: string[] = ["[3] COACH MEMORY"];
  if (mem.preferred_name) lines.push(`- The user prefers to be called "${mem.preferred_name}".`);
  if (mem.communication_style) {
    lines.push(`- They communicate in ${mem.communication_style} — mirror that tone.`);
  }
  if (mem.depth_preference) {
    const guidance = mem.depth_preference === "action_taker"
      ? "keep replies short and action-focused"
      : "include the why and brief reasoning";
    lines.push(`- They are an ${mem.depth_preference} — ${guidance}.`);
  }
  if (mem.motivation_style) {
    const tone = {
      tough_love: "be direct, no soft padding",
      gentle: "be warm and validating before suggesting",
      data_driven: "lead with the number, then the suggestion",
    }[mem.motivation_style];
    lines.push(`- Motivation style: ${mem.motivation_style} — ${tone}.`);
  }
  if (mem.dropout_risk_score !== null && mem.dropout_risk_score >= 0.5) {
    lines.push(`- Risk: dropout_risk=${mem.dropout_risk_score.toFixed(2)} (be encouraging, do not pile on demands).`);
  }
  if (mem.plateau_risk_score !== null && mem.plateau_risk_score >= 0.5) {
    lines.push(`- Risk: plateau_risk=${mem.plateau_risk_score.toFixed(2)} (acknowledge if user mentions weight stuck).`);
  }
  if (mem.injuries && Array.isArray(mem.injuries) && mem.injuries.length > 0) {
    lines.push(`- Active injuries: ${JSON.stringify(mem.injuries)}.`);
  }
  if (mem.last_proactive_type) {
    lines.push(`- Last proactive nudge sent today: ${mem.last_proactive_type} — do not repeat this type.`);
  }
  if (lines.length === 1) return "";
  return lines.join("\n");
}
