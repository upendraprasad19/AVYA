// supabase/functions/_shared/prompt_sites_sanitized.test.ts
//
// OI-47 coverage gate. Every Edge Function that builds an LLM prompt must
// import the sanitiser.
//
// WHY THIS IS DERIVED AND NOT A LIST. OI-47 named 5 sites. A grep keyed on
// `geminiChat(` found 14. Widening to `systemPrompt|prompt:` found a 15th --
// `proactive-coach-promotion`, which calls the Gemini REST endpoint through
// `fetch` directly and interpolates a user-editable first name into the SYSTEM
// INSTRUCTION. Three passes, three different answers, each one confidently
// "complete". A hard-coded list of 15 would be the fourth wrong answer the day
// a 16th function is added.
//
// So the required set is COMPUTED from the tree on every run. A new
// prompt-building function joins it automatically and fails until it is either
// sanitised or explicitly recorded as clean below, with a reason.
//
// WHAT THIS DOES AND DOES NOT PROVE. Presence-only, deliberately
// (feedback_source_grep_false_confidence): it proves the module is REACHED, not
// that every interpolation inside is wrapped. The behavioural proof that the
// sanitiser actually removes the levers lives in sanitize_for_prompt.test.ts.
// The two together are what make the coverage claim meaningful; either alone is
// false confidence.

import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";

/** Signals that a file constructs a prompt for a model. */
const PROMPT_MARKERS = ["userPrompt", "systemPrompt", "generateContent"];

/**
 * Functions that build a prompt but legitimately need no sanitiser, each with
 * the reason it is safe. Anything not listed here MUST import the module.
 *
 * Keep this SMALL and keep the reasons concrete -- an allowlist is how a
 * coverage gate quietly becomes decorative.
 */
const VERIFIED_CLEAN: Record<string, string> = {
  // (currently empty -- every prompt-building function reaches the sanitiser)
};

function functionDirsWithPrompts(root: URL): string[] {
  const hits: string[] = [];
  for (const entry of Deno.readDirSync(root)) {
    if (!entry.isDirectory) continue;
    const indexPath = new URL(entry.name + "/index.ts", root);
    let src: string;
    try {
      src = Deno.readTextFileSync(indexPath);
    } catch {
      continue; // no index.ts in this directory
    }
    if (PROMPT_MARKERS.some((m) => src.includes(m))) hits.push(entry.name);
  }
  return hits.sort();
}

Deno.test("every prompt-building Edge Function imports the sanitiser", () => {
  const root = new URL("../", import.meta.url);
  const dirs = functionDirsWithPrompts(root);

  // Guard against the enumerator silently finding nothing -- a vacuously green
  // coverage gate is worse than no gate, because it reads as proof.
  assert(
    dirs.length >= 15,
    "expected at least 15 prompt-building functions, found " + dirs.length +
      " -- the enumerator is probably broken, not the tree",
  );

  const missing: string[] = [];
  for (const dir of dirs) {
    if (dir in VERIFIED_CLEAN) continue;
    const src = Deno.readTextFileSync(new URL(dir + "/index.ts", root));
    if (!src.includes("_shared/sanitize_for_prompt.ts")) missing.push(dir);
  }

  assertEquals(
    missing,
    [],
    "these build prompts but never import the sanitiser: " + missing.join(", ") +
      " -- either wrap the user-controlled interpolations or add the function " +
      "to VERIFIED_CLEAN with a concrete reason",
  );
});

Deno.test("VERIFIED_CLEAN entries are real directories, so the allowlist cannot rot", () => {
  // An allowlist keyed on a renamed or deleted function silently exempts
  // nothing while looking like it exempts something -- and the next reader
  // trusts it.
  const root = new URL("../", import.meta.url);
  for (const dir of Object.keys(VERIFIED_CLEAN)) {
    let ok = true;
    try {
      Deno.readTextFileSync(new URL(dir + "/index.ts", root));
    } catch {
      ok = false;
    }
    assert(ok, "VERIFIED_CLEAN names '" + dir + "', which has no index.ts");
    assert(
      VERIFIED_CLEAN[dir].trim().length > 20,
      "VERIFIED_CLEAN['" + dir + "'] needs a real reason, not a placeholder",
    );
  }
});
