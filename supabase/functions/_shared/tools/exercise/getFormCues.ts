// supabase/functions/_shared/tools/exercise/getFormCues.ts
//
// Captain coach tool: returns coaching cues, common mistakes, instructions,
// primary/secondary muscles, difficulty level, and logging type for a named exercise.
// Reads from exercise_library.
//
// Source: APK Test #4 Plan C / C6.
//
// Schema note: exercise_library does NOT have breathing_cue / warmup_protocol /
// pro_tip columns. Actual coaching columns are coaching_cues (text[]),
// common_mistakes (text[]), instructions (text), difficulty_level (text).
// Adapt if schema changes in future.

import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  exercise_name: z
    .string()
    .min(1)
    .describe(
      "Exact or close match to exercise_library.name (e.g. 'Bench Press', 'Romanian Deadlift', 'Pull Up'). Use the name from the user's workout if available.",
    ),
});

type Args = z.infer<typeof schema>;

interface FormCuesResult {
  found: boolean;
  exercise_name?: string;
  matched_via?: "exact" | "partial";
  /** Step-by-step coaching cues (text array from exercise_library). */
  coaching_cues?: string[];
  /** Common form errors to watch for. */
  common_mistakes?: string[];
  /** Full instructions / movement description. */
  instructions?: string | null;
  /** Target muscles. */
  primary_muscles?: string[];
  secondary_muscles?: string[];
  /** 'Beginner' | 'Intermediate' | 'Advanced' — from difficulty_level column. */
  difficulty_level?: string | null;
  /** E.g. 'weight_reps', 'timed', 'bodyweight_reps' — helps coach give rep/time cues. */
  logging_type?: string | null;
  /** Set when no match was found. */
  error?: string;
}

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<FormCuesResult> {
  const { sb } = ctx;
  const name = (args.exercise_name ?? "").trim();

  if (name === "") {
    return { found: false, error: "exercise_name is required" };
  }

  const COLUMNS =
    "name, coaching_cues, common_mistakes, instructions, primary_muscles, secondary_muscles, difficulty_level, logging_type";

  // Stage 1: exact case-insensitive match
  const { data: exact, error: exactErr } = await sb
    .from("exercise_library")
    .select(COLUMNS)
    .ilike("name", name)
    .limit(1)
    .maybeSingle();

  if (exactErr) {
    throw new Error(`getFormCues exact query failed: ${exactErr.message}`);
  }

  if (exact) {
    return {
      found: true,
      exercise_name: exact.name,
      matched_via: "exact",
      coaching_cues: exact.coaching_cues ?? [],
      common_mistakes: exact.common_mistakes ?? [],
      instructions: exact.instructions ?? null,
      primary_muscles: exact.primary_muscles ?? [],
      secondary_muscles: exact.secondary_muscles ?? [],
      difficulty_level: exact.difficulty_level ?? null,
      logging_type: exact.logging_type ?? null,
    };
  }

  // Stage 2: partial match (user may have typed "RDL" or "Romanian")
  const { data: partial, error: partialErr } = await sb
    .from("exercise_library")
    .select(COLUMNS)
    .ilike("name", `%${name}%`)
    .limit(1)
    .maybeSingle();

  if (partialErr) {
    throw new Error(`getFormCues partial query failed: ${partialErr.message}`);
  }

  if (partial) {
    return {
      found: true,
      exercise_name: partial.name,
      matched_via: "partial",
      coaching_cues: partial.coaching_cues ?? [],
      common_mistakes: partial.common_mistakes ?? [],
      instructions: partial.instructions ?? null,
      primary_muscles: partial.primary_muscles ?? [],
      secondary_muscles: partial.secondary_muscles ?? [],
      difficulty_level: partial.difficulty_level ?? null,
      logging_type: partial.logging_type ?? null,
    };
  }

  return { found: false, exercise_name: name };
}

export const getFormCuesTool: ToolDefinition<Args, FormCuesResult> = {
  name: "getFormCues",
  family: "progress",
  kind: "read",
  tier: "free",
  description:
    "Returns coaching cues, common mistakes, instructions, target muscles, difficulty level, and logging type for a named exercise. Call when the user asks how to do an exercise, requests a form check, asks 'what should I focus on for X', or asks about technique, breathing, or mistakes to avoid.",
  schema,
  maxLatencyMs: 3000,
  handler,
};
