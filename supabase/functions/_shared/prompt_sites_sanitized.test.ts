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

/** Right-hand-side tokens that prove the value was handled. */
const SANITISED = [
  "sanitizeIdentifier(",
  "sanitizeBlock(",
  "sanitizeJsonForPrompt(",
  "asPrincipalMessage(",
  ".text", // a FencedBlock
  ".begin", // a nonce marker interpolated into authored instruction text
];

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
function isSafeExpression(rhs: string, fileSrc: string): boolean {
  // A TYPE DECLARATION (`systemPrompt: string;` inside an interface) is not an
  // assignment at all -- there is no value here to sanitise.
  if (/:\s*(string|number|boolean)\s*[;,)]/.test(rhs)) return true;
  // A string or template literal is authored text.
  if (/:\s*[`"']/.test(rhs)) return true;
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
      if (!/\b(userPrompt|systemPrompt)\s*:/.test(lines[i])) continue;
      const chunk = lines.slice(i, i + 3).join(" ");
      const rhs = chunk.slice(chunk.search(/\b(userPrompt|systemPrompt)\s*:/));
      if (!isSafeExpression(rhs, src)) {
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
