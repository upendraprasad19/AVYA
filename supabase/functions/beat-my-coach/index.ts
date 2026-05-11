import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { istDateStr } from "../_shared/ist_date.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CHALLENGE_INTERVAL_DAYS = 14;

// Difficulty presets for challenge generation
interface DifficultyPreset {
  label: string;
  exerciseCount: number;
  repMultiplier: number;
  coachTimeMultiplier: number;
  taglines: string[];
}

const DIFFICULTY_PRESETS: Record<string, DifficultyPreset> = {
  beginner: {
    label: "Starter",
    exerciseCount: 3,
    repMultiplier: 0.6,
    coachTimeMultiplier: 1.3,
    taglines: [
      "Think you can keep up?",
      "Your coach warmed up in 2 minutes. Can you?",
      "Start small, finish strong!",
    ],
  },
  intermediate: {
    label: "Contender",
    exerciseCount: 4,
    repMultiplier: 1.0,
    coachTimeMultiplier: 1.0,
    taglines: [
      "Your coach did this between sets. Your turn.",
      "No equipment, no excuses.",
      "The clock is ticking — beat the coach!",
    ],
  },
  advanced: {
    label: "Beast Mode",
    exerciseCount: 5,
    repMultiplier: 1.4,
    coachTimeMultiplier: 0.8,
    taglines: [
      "Your coach barely broke a sweat. Can you?",
      "Only legends finish this one.",
      "This is what PRO looks like.",
    ],
  },
};

// Base rep ranges for bodyweight exercises
const BASE_REPS: Record<string, { min: number; max: number }> = {
  "Push-ups": { min: 10, max: 20 },
  "Squats": { min: 15, max: 25 },
  "Burpees": { min: 5, max: 12 },
  "Jumping Jacks": { min: 20, max: 40 },
  "Mountain Climbers": { min: 10, max: 20 },
  "High Knees": { min: 15, max: 30 },
  "Plank (seconds)": { min: 20, max: 45 },
  "Lunges (each leg)": { min: 8, max: 15 },
  "Bicycle Crunches": { min: 10, max: 20 },
  "Tuck Jumps": { min: 5, max: 10 },
  default: { min: 8, max: 15 },
};

/**
 * Seeded pseudo-random number generator for deterministic challenges.
 * Uses a simple LCG (linear congruential generator).
 */
function seededRandom(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 1664525 + 1013904223) & 0xffffffff;
    return (s >>> 0) / 0xffffffff;
  };
}

/**
 * Pick random items from an array using the seeded random function.
 */
function pickRandom<T>(arr: T[], count: number, rng: () => number): T[] {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled.slice(0, count);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Parse optional request body
    let userId: string | null = null;
    let forceNew = false;

    try {
      const body = await req.json();
      userId = body?.user_id ?? null;
      forceNew = body?.force_new === true;

      // If user_id provided via JWT instead
      if (!userId) {
        const authHeader = req.headers.get("Authorization");
        if (authHeader) {
          const token = authHeader.replace("Bearer ", "");
          const {
            data: { user },
          } = await supabaseClient.auth.getUser(token);
          userId = user?.id ?? null;
        }
      }
    } catch {
      // No body or invalid body — generate a global challenge
    }

    // Determine difficulty based on user experience level
    let difficulty = "intermediate";
    if (userId) {
      const { data: progress } = await supabaseClient
        .from("user_progress")
        .select("detected_experience_level")
        .eq("user_id", userId)
        .single();

      if (progress?.detected_experience_level) {
        difficulty = progress.detected_experience_level;
      }
    }

    const preset = DIFFICULTY_PRESETS[difficulty] ?? DIFFICULTY_PRESETS.intermediate;

    // Check if user already has a recent challenge (within CHALLENGE_INTERVAL_DAYS)
    if (userId && !forceNew) {
      // audit-2026-05-11 H-5 — cutoff date now IST-anchored so the
      // 14-day re-challenge window aligns with the user's calendar
      // (not UTC's). Otherwise IST-evening generations consumed a
      // window from "tomorrow UTC" and reset 5h30m early.
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - CHALLENGE_INTERVAL_DAYS);
      const cutoffStr = istDateStr(cutoffDate);

      const { data: recentSnap } = await supabaseClient
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .gte("snapshot_date", cutoffStr)
        .not("snapshot_json->beat_my_coach", "is", null)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      if (recentSnap?.snapshot_json?.beat_my_coach) {
        return new Response(
          JSON.stringify({
            status: "existing",
            challenge: recentSnap.snapshot_json.beat_my_coach,
            message: "Recent challenge still active",
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Fetch bodyweight exercises from exercise_library
    const { data: exercises, error: exError } = await supabaseClient
      .from("exercise_library")
      .select("id, name, category, exercise_type, difficulty_level")
      .or("category.eq.Calisthenics,category.eq.Cardio")
      .or(
        "equipment_needed.cs.{bodyweight},equipment_needed.cs.{none},equipment_needed.is.null",
      )
      .eq("is_active", true);

    if (exError || !exercises || exercises.length === 0) {
      // Fallback: use hardcoded bodyweight exercises if DB query fails
      console.log(
        "Exercise library query failed or empty, using fallback exercises",
      );
    }

    // Use a date-based seed so the same day produces the same challenge
    const today = new Date();
    const dateSeed =
      today.getFullYear() * 10000 +
      (today.getMonth() + 1) * 100 +
      today.getDate();
    const rng = seededRandom(dateSeed + (userId ? hashCode(userId) : 0));

    // Build challenge exercises
    interface ChallengeExercise {
      name: string;
      reps: number;
      unit: string;
    }

    const challengeExercises: ChallengeExercise[] = [];

    if (exercises && exercises.length >= preset.exerciseCount) {
      // Use exercises from the DB
      const picked = pickRandom(exercises, preset.exerciseCount, rng);

      for (const ex of picked) {
        const baseRep = BASE_REPS[ex.name] ?? BASE_REPS.default;
        const rawReps =
          baseRep.min + Math.floor(rng() * (baseRep.max - baseRep.min + 1));
        const reps = Math.round(rawReps * preset.repMultiplier);
        const isTimed = ex.name.toLowerCase().includes("plank") ||
          ex.name.toLowerCase().includes("hold") ||
          ex.name.toLowerCase().includes("hang");

        challengeExercises.push({
          name: ex.name,
          reps,
          unit: isTimed ? "seconds" : "reps",
        });
      }
    } else {
      // Fallback: hardcoded bodyweight exercises
      const fallbackNames = [
        "Push-ups",
        "Squats",
        "Burpees",
        "Jumping Jacks",
        "Mountain Climbers",
        "High Knees",
        "Plank (seconds)",
        "Lunges (each leg)",
        "Bicycle Crunches",
      ];

      const picked = pickRandom(fallbackNames, preset.exerciseCount, rng);

      for (const name of picked) {
        const baseRep = BASE_REPS[name] ?? BASE_REPS.default;
        const rawReps =
          baseRep.min + Math.floor(rng() * (baseRep.max - baseRep.min + 1));
        const reps = Math.round(rawReps * preset.repMultiplier);
        const isTimed = name.toLowerCase().includes("plank") ||
          name.toLowerCase().includes("hold");

        challengeExercises.push({
          name,
          reps,
          unit: isTimed ? "seconds" : "reps",
        });
      }
    }

    // Calculate coach's target time
    // Rough estimate: 3 seconds per rep for most exercises, adjusted by difficulty
    const totalWork = challengeExercises.reduce((sum, ex) => {
      const secsPerUnit = ex.unit === "seconds" ? 1 : 3;
      return sum + ex.reps * secsPerUnit;
    }, 0);
    const coachTimeSecs = Math.round(
      totalWork * preset.coachTimeMultiplier,
    );
    const coachTimeMins = Math.floor(coachTimeSecs / 60);
    const coachTimeSec = coachTimeSecs % 60;
    const coachTimeFormatted =
      coachTimeMins > 0
        ? `${coachTimeMins}m ${coachTimeSec}s`
        : `${coachTimeSecs}s`;

    // Pick a random tagline
    const tagline =
      preset.taglines[Math.floor(rng() * preset.taglines.length)];

    const challenge = {
      exercises: challengeExercises,
      coach_time_seconds: coachTimeSecs,
      coach_time_formatted: coachTimeFormatted,
      difficulty: preset.label,
      difficulty_key: difficulty,
      tagline,
      generated_at: new Date().toISOString(),
      valid_until: new Date(
        today.getTime() + CHALLENGE_INTERVAL_DAYS * 24 * 60 * 60 * 1000,
      )
        .toISOString()
        .split("T")[0],
    };

    // Store challenge in user's snapshot if user_id provided
    if (userId) {
      // audit-2026-05-11 H-5 — snapshot_date is the user's IST day,
      // not UTC. Matches daily-snapshot writer + ai-proxy snapshot
      // reader semantics.
      const todayStr = istDateStr();

      const { data: existingSnapshot } = await supabaseClient
        .from("user_daily_snapshots")
        .select("id, snapshot_json")
        .eq("user_id", userId)
        .eq("snapshot_date", todayStr)
        .single();

      const updatedJson = {
        ...(existingSnapshot?.snapshot_json ?? {}),
        beat_my_coach: challenge,
      };

      await supabaseClient.from("user_daily_snapshots").upsert(
        {
          user_id: userId,
          snapshot_date: todayStr,
          snapshot_json: updatedJson,
          created_at: new Date().toISOString(),
        },
        { onConflict: "user_id,snapshot_date" },
      );
    }

    return new Response(
      JSON.stringify({
        status: "success",
        challenge,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / upstream provider text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[beat-my-coach] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Simple string hash code for deterministic seeding.
 */
function hashCode(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  return Math.abs(hash);
}
