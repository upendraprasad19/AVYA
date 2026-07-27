// supabase/functions/_shared/prompt_sites_sanitized.test.ts
//
// OI-47 coverage gate. Every ASSIGNMENT of prompt text must be traceable to a
// literal, a sanitiser call, or an explicit decision.
//
// WHY THIS WAS REWRITTEN, twice over. The first version asked "does this FILE
// import the sanitiser?" and kept a hand-written allowlist for the rest. Both
// halves failed, and review round 2 found both:
//
//   - File-level presence let `ai-proxy/index.ts` read CLEAN while
//     `formatRetrievalBlock` piped retrieved memories raw into the system
//     prompt. The file did import the module -- for two other sites.
//   - The allowlist actively HID a real bug. `food_parser.ts` was correctly
//     flagged, and the exemption written for it explained the template literals
//     at :104/:149 while never mentioning `userPrompt: description` at :84. A
//     wrong justification silenced a right detection.
//
// So: assignments, not files. No allowlist. A deliberate raw pass has to be
// stated in CODE, via asPrincipalMessage(), at the call site -- where it shows
// up in the diff of the file that carries the risk.

import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";

/**
 * A prompt SITE: either `systemPrompt:` or the ES6 shorthand `systemPrompt,`.
 *
 * Round 3 found the colon-only version blind to ai-proxy:864, which hands the
 * fully assembled system prompt to runToolLoop as shorthand -- the single line
 * that delivers the vulnerable prompt to Gemini. The gate was green because it
 * never looked at it.
 */
const PROMPT_SITE = /\b(userPrompt|systemPrompt)\s*[:,}]|\b(userPrompt|systemPrompt)\s*$/;

/** Right-hand-side tokens that prove the value was handled. */
const SANITISED = [
  "sanitizeIdentifier(",
  "sanitizeBlock(",
  "sanitizeJsonForPrompt(",
  "asPrincipalMessage(",
  ".text", // a FencedBlock
  ".begin", // a nonce marker interpolated into authored instruction text
];

/**
 * Module-level AUTHORED prompt sources -- constants and builders whose content
 * is written by us, not by a user. Naming these is not the allowlist mistake:
 * an allowlist exempted FILES from inspection, whereas this names the specific
 * authored VALUES a prompt may legitimately be assembled from. A user-derived
 * value still has to be sanitised even inside the same expression.
 */
const AUTHORED = ["captainPrompt(", "CAPTAIN_MANUAL", "SYSTEM_PROMPT"];

/** Every .ts under supabase/functions/, excluding test files. */
function sourceFiles(root: URL): string[] {
  const out: string[] = [];
  const walk = (dir: URL, prefix: string) => {
    for (const e of Deno.readDirSync(dir)) {
      const rel = prefix + e.name;
      if (e.isDirectory) walk(new URL(e.name + "/", dir), rel + "/");
      else if (
        e.name.endsWith(".ts") && !e.name.includes("_test") &&
        !e.name.endsWith(".test.ts")
      ) out.push(rel);
    }
  };
  walk(root, "");
  return out.sort();
}

/** True when the value assigned to a prompt key is provably safe. */
function isSafeExpression(
  rhs: string,
  fileSrc: string,
  siteLine: number,
): boolean {
  // ES6 SHORTHAND (`systemPrompt,`) has no right-hand side, so the value is
  // whatever the local of that name holds.
  if (/^(userPrompt|systemPrompt)\s*[,}]/.test(rhs.trim())) {
    const name = rhs.trim().replace(/[^A-Za-z].*$/, "");
    // NEAREST-PRECEDING declaration, not the first one in the file. Searching
    // the whole source matched ai-proxy's prediction-branch
    // `const systemPrompt = sanitizeBlock(...)` at :550 while the site under
    // test was :882 -- the gate validated an unrelated, safe declaration and
    // passed. Only a negative control exposes that, because the gate is green
    // either way.
    const declRe = new RegExp(
      "(?:const|let|var)\\s+" + name + "\\s*(?::[^=]+)?=\\s*([\\s\\S]{0,200})",
      "g",
    );
    const beforeSite = fileSrc.split("\n").slice(0, siteLine).join("\n");
    let decl: RegExpExecArray | null = null;
    for (let hit = declRe.exec(beforeSite); hit; hit = declRe.exec(beforeSite)) {
      decl = hit;
    }

    // NO local declaration => this is a destructured PARAMETER (gemini.ts's
    // `{ systemPrompt, userPrompt, ... }`), not an assignment of a new value.
    // The obligation sits with the caller, which is itself a site this gate
    // inspects.
    if (!decl) return true;

    // BOUND the declaration to its own statement. Taking a fixed window ran past
    // the `;` into unrelated code and picked up a sanitiser token from there --
    // the same bleed that made the push-argument check false-pass. Both were
    // found by negative-controlling the round-3 P0 back in and watching the gate
    // stay green, which is the only reason to ever run a negative control.
    const body = decl[1].split(";")[0];
    if (SANITISED.some((t) => body.includes(t))) return true;
    if (AUTHORED.some((t) => body.includes(t))) return true;
    // An interpolation-free literal.
    if (/^["'`][^$]*$/.test(body.split("\n")[0].trim())) return true;

    // ASSEMBLED via `parts.join(...)`: check every `parts.push(` argument.
    // This is the rule that would have caught the round-3 P0 -- the raw
    // `"..." + retrievalBlock + "..."` push carried neither a literal-only
    // argument nor a sanitiser token.
    const join = /^(\w+)\.join\(/.exec(body.trim());
    if (join) {
      const parts = join[1];
      const pushes = fileSrc.split(parts + ".push(").slice(1);
      return pushes.every((chunk) => {
        // BOUND the argument to this call's own parentheses. The first version
        // took a fixed 600-char window, which bled into the FOLLOWING code and
        // picked up a sanitiser token from an unrelated statement -- a
        // false PASS, caught by negative-controlling the round-3 P0 back in and
        // watching the gate stay green.
        let depth = 1;
        let end = 0;
        for (; end < chunk.length && depth > 0; end++) {
          if (chunk[end] === "(") depth++;
          else if (chunk[end] === ")") depth--;
        }
        const arg = chunk.slice(0, Math.max(0, end - 1));
        if (SANITISED.some((t) => arg.includes(t))) return true;
        if (AUTHORED.some((t) => arg.includes(t))) return true;
        // Otherwise it must be literal-only: no bare identifier concatenated in.
        return !/\+\s*[A-Za-z_$][\w$]*\s*[,)+]|^\s*[A-Za-z_$][\w$]*\s*[,)]/
          .test(arg);
      });
    }
    return false;
  }
  // A TYPE DECLARATION (`systemPrompt: string;` inside an interface) is not an
  // assignment at all -- there is no value here to sanitise.
  if (/:\s*(string|number|boolean)\s*[;,)]/.test(rhs)) return true;
  // A string or template literal is authored text -- BUT a template literal can
  // interpolate anything, and the first version of this rule fired on the
  // opening backtick alone. Round 3: `systemPrompt: \`... ${rawUserInput}\`` was
  // declared SAFE. So a template with interpolation has to prove ITS pieces are
  // handled; only an interpolation-free literal passes on sight.
  if (/:\s*["']/.test(rhs)) return true;
  if (/:\s*`/.test(rhs)) {
    if (!rhs.includes("${")) return true;
    return SANITISED.some((t) => rhs.includes(t));
  }
  // A direct sanitiser call, a fence marker, or the explicit principal marker.
  if (SANITISED.some((t) => rhs.includes(t))) return true;

  // A pure FORWARD of the same key off a params object -- `systemPrompt:
  // opts.systemPrompt`. This is not a new value, so the obligation belongs to
  // whoever built it, and that builder is itself a prompt assignment this gate
  // inspects. Deliberately narrow: only the IDENTICAL key name off an object.
  // `systemPrompt: opts.somethingElse` still fails, because that would be a
  // different value wearing a forwarding shape.
  const fwd = /\b(userPrompt|systemPrompt)\s*:\s*\w+\.(userPrompt|systemPrompt)\s*[,)]/
    .exec(rhs);
  if (fwd && fwd[1] === fwd[2]) return true;

  // A bare identifier: TRACE it to its declaration in the same file and check
  // THAT. This is the step a file-level check could never do, and it is exactly
  // what let formatRetrievalBlock hide behind two unrelated safe call sites.
  const m = /:\s*([A-Za-z_$][\w$]*)\s*[,)]/.exec(rhs);
  if (m) {
    const name = m[1];
    const decl = new RegExp(
      "(?:const|let|var)\\s+" + name + "\\s*(?::[^=]+)?=([\\s\\S]{0,900})",
    ).exec(fileSrc);
    if (decl) {
      const body = decl[1];
      if (/^\s*[`"']/.test(body)) return true;
      if (SANITISED.some((t) => body.includes(t))) return true;
    }
    // A value threaded in as a typed parameter is the caller's obligation, and
    // the caller is a prompt assignment this same gate inspects.
    if (new RegExp("\\b" + name + "\\s*:\\s*string").test(fileSrc)) return true;
  }
  return false;
}

Deno.test("every prompt ASSIGNMENT is a literal or a traceably sanitised value", () => {
  const root = new URL("../", import.meta.url);
  const unsafe: string[] = [];
  for (const f of sourceFiles(root)) {
    const src = Deno.readTextFileSync(new URL(f, root));
    const lines = src.split("\n");
    for (let i = 0; i < lines.length; i++) {
      // Round 3 P0: the scanner required a COLON, so ES6 shorthand
      // (`systemPrompt,`) was invisible -- and ai-proxy:864 passes the fully
      // assembled system prompt to runToolLoop exactly that way. The gate ran
      // green while never looking at the line that actually delivers the prompt
      // to Gemini. Shorthand is now a first-class site.
      if (!PROMPT_SITE.test(lines[i])) continue;
      const chunk = lines.slice(i, i + 3).join(" ");
      const rhs = chunk.slice(chunk.search(PROMPT_SITE));
      if (!isSafeExpression(rhs, src, i)) {
        unsafe.push(f + ":" + (i + 1) + "  " + rhs.trim().slice(0, 90));
      }
    }
  }

  assertEquals(
    unsafe,
    [],
    "these prompt assignments take a value this gate cannot trace to a " +
      "sanitiser, a literal, or an explicit asPrincipalMessage() decision",
  );
});

Deno.test("the enumerator actually finds the prompt sites", () => {
  // Guards against a vacuously green gate: if the scan silently found nothing,
  // the assertion above would pass while checking zero call sites. The old
  // version reported 15/15 clean partly because of what it never opened, so
  // "did we look at anything?" is worth asserting separately.
  const root = new URL("../", import.meta.url);
  let count = 0;
  for (const f of sourceFiles(root)) {
    const src = Deno.readTextFileSync(new URL(f, root));
    for (const ln of src.split("\n")) {
      if (/\b(userPrompt|systemPrompt)\s*:/.test(ln)) count++;
    }
  }
  assert(count >= 20, "expected >=20 prompt-key occurrences, found " + count);
});
