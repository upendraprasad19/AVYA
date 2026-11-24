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

import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { escapeLike } from "../../like_escape.ts";

const schema = z.object({
  exercise_name: z
    .string()
    .min(1)
    // The longest library name is 50 characters and the longest alias 27; escapeLike can double the
    // length in the URL, so an oversized model-supplied name is refused before any read (rule 18).
    .max(200)
    .describe(
      "Exact or close match to exercise_library.name (e.g. 'Bench Press', 'Romanian Deadlift', 'Pull Up'). Use the name from the user's workout if available.",
    ),
});

type Args = z.infer<typeof schema>;

interface FormCuesResult {
  found: boolean;
  exercise_name?: string;
  matched_via?: "exact" | "alias" | "partial";
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
  /** Set when no saved cues exist: tells the model to answer briefly from general knowledge (OI-507). */
  hint?: string;
}

/** Shown to the model when no saved cues exist (OI-507 item 4). */
const NOT_FOUND_HINT =
  "No saved cues exist for this exercise (it may be the user's own custom exercise). " +
  "Give 2-4 brief coaching cues and 1-2 common mistakes from general knowledge, in the same " +
  "short style as the library cues. Say in one short line that these are general cues, not the " +
  "app's saved ones. Do not invent app data.";

const MIN_PARTIAL_LENGTH = 3;
const ALIAS_READ_CAP = 200;

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<FormCuesResult> {
  const { sb } = ctx;
  // `*` is removed first: PostgREST reads it as `%` and it cannot be escaped (OI-507).
  const name = (args.exercise_name ?? "").replace(/\*/g, "").trim();

  if (name === "") {
    return { found: false, error: "exercise_name is required" };
  }

  const COLUMNS =
    "name, coaching_cues, common_mistakes, instructions, primary_muscles, secondary_muscles, difficulty_level, logging_type";

  const shape = (
    row: Record<string, any>,
    matched_via: "exact" | "alias" | "partial",
  ): FormCuesResult => ({
    found: true,
    exercise_name: row.name,
    matched_via,
    coaching_cues: row.coaching_cues ?? [],
    common_mistakes: row.common_mistakes ?? [],
    instructions: row.instructions ?? null,
    primary_muscles: row.primary_muscles ?? [],
    secondary_muscles: row.secondary_muscles ?? [],
    difficulty_level: row.difficulty_level ?? null,
    logging_type: row.logging_type ?? null,
  });

  // Retired rows (is_active = false) are hidden, never deleted (workout_logs /
  // template_exercises reference them by FK). Every stage skips them (OI-438, OI-469).
  // Every ORDER BY name, id makes the pick deterministic where `limit(1)` alone left it to
  // the planner (OI-507 item 1); id breaks a tie between two active rows that share a name. The name is LIKE-escaped on both ilike stages (item 2).
  // Stage 1: exact case-insensitive match
  const { data: exact, error: exactErr } = await sb
    .from("exercise_library")
    .select(COLUMNS)
    .ilike("name", escapeLike(name))
    .eq("is_active", true)
    .order("name")
    .order("id")
    .limit(1)
    .maybeSingle();

  if (exactErr) {
    throw new Error(`getFormCues exact query failed: ${exactErr.message}`);
  }

  if (exact) return shape(exact, "exact");

  // Stage 1b: a name another row lists in name_aliases (OI-507 item 3). Fails OPEN:
  // an error or a capped read is logged and the lookup goes on to stage 2, so a
  // problem here never breaks an exact-miss query that stage 2 answers today.
  try {
    const { data: aliased, error: aliasErr } = await sb
      .from("exercise_library")
      .select(`${COLUMNS}, name_aliases`)
      .eq("is_active", true)
      .neq("name_aliases", "{}")
      .order("name")
      .order("id")
      .limit(200); // literal for the unbounded-read gate; MUST equal ALIAS_READ_CAP
    if (aliasErr) {
      console.error(`getFormCues alias read failed: ${aliasErr.message}`);
    } else if ((aliased ?? []).length >= ALIAS_READ_CAP) {
      console.error(`getFormCues alias read hit the ${ALIAS_READ_CAP}-row cap; alias stage skipped`);
    } else {
      const want = name.toLowerCase();
      const hit = (aliased ?? []).find((r: Record<string, any>) =>
        (r.name_aliases ?? []).some((a: string) => String(a).trim().toLowerCase() === want)
      );
      if (hit) return shape(hit, "alias");
    }
  } catch (e) {
    console.error(`getFormCues alias stage threw: ${(e as Error).message}`);
  }

  // Stage 2: partial match (user may have typed "RDL" or "Romanian"). A 1-2 character
  // query would match a large slice of the library, so it goes straight to the hint.
  if (name.length >= MIN_PARTIAL_LENGTH) {
    const { data: partial, error: partialErr } = await sb
      .from("exercise_library")
      .select(COLUMNS)
      .ilike("name", `%${escapeLike(name)}%`)
      .eq("is_active", true)
      .order("name")
      .order("id")
      .limit(1)
      .maybeSingle();

    if (partialErr) {
      throw new Error(`getFormCues partial query failed: ${partialErr.message}`);
    }

    if (partial) return shape(partial, "partial");
  }

  return { found: false, exercise_name: name, hint: NOT_FOUND_HINT };
}

export const getFormCuesTool: ToolDefinition<Args, FormCuesResult> = {
  name: "getFormCues",
  family: "progress",
  kind: "read",
  tier: "free",
  description:
    "Returns coaching cues, common mistakes, instructions, target muscles, difficulty level, and logging type for a named exercise. Call when the user asks how to do an exercise, requests a form check, asks 'what should I focus on for X', or asks about technique, breathing, or mistakes to avoid. When matched_via is 'partial' or 'alias', tell the user which exercise's cues you are giving (exercise_name).",
  schema,
  maxLatencyMs: 3000,
  handler,
};
