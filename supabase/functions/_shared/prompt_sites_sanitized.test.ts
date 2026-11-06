// supabase/functions/_shared/prompt_sites_sanitized.test.ts
//
// OI-47 coverage gate: every prompt value must be VISIBLY safe at the point of
// assignment.
//
// THIS GATE HAS BEEN WRONG THREE TIMES, EACH TIME IN A WAY THAT PASSED.
//   v1  asked "does this FILE import the sanitiser?" -- `ai-proxy` read clean
//       while formatRetrievalBlock piped raw memories into the system prompt,
//       because the file imported the module for two OTHER sites. It also kept
//       a hand-written allowlist, and the entry written for `food_parser.ts`
//       explained lines :104/:149 while never mentioning `userPrompt:
//       description` at :84 -- a wrong justification silencing a right
//       detection.
//   v2  required a COLON, so ES6 shorthand was invisible -- and that is exactly
//       how ai-proxy hands the assembled system prompt to runToolLoop.
//   v3  TRACED identifiers to their declarations. Five rounds of tuning, and
//       negative controls STILL showed false passes: windows bleeding past the
//       statement, `.exec()` matching a declaration in a different scope, a
//       semicolon inside a COMMENT truncating a body.
//
// A regex taint-tracker over TypeScript is the wrong tool, and a gate that
// cannot be trusted to fail is worse than no gate -- it converts "unreviewed"
// into "reviewed and clean". So v4 drops tracing entirely:
//
//   A prompt value must CONTAIN a recognised safe marker, or be an inline
//   literal with no interpolation. Nothing is inferred. Nothing is traced.
//
// If a value is authored by us, say so with asAuthoredPrompt(). If it is the
// user's own message on the chat channel, say so with asPrincipalMessage().
// Both are identity functions whose only job is to put the decision in the diff
// of the file that carries the risk.
//
// And this file now TESTS ITSELF. Every false pass listed above would have been
// caught on the first run by the SELF test below.

import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";

/** Tokens that make a prompt value visibly safe. */
const SAFE_MARKERS = [
  "sanitizeIdentifier(",
  "sanitizeBlock(",
  "sanitizeJsonForPrompt(",
  "asPrincipalMessage(",
  "asAuthoredPrompt(",
  "captainPrompt(",
  "CAPTAIN_MANUAL",
  "SYSTEM_PROMPT",
  ".text", // a FencedBlock
  ".begin", // a nonce marker named in authored instruction text
];

/**
 * A prompt site is an ASSIGNMENT of a prompt value:
 *   `systemPrompt: <value>`   an object property
 *   `const systemPrompt = …`  a local declaration
 *
 * Including the DECLARATION is what removes the ES6-shorthand ambiguity that
 * defeated v2. `systemPrompt,` at a call site is just a reference; the value was
 * decided where it was declared, and that line is now gated. So shorthand needs
 * no special rule, and a destructured parameter (which has no declaration in
 * this file) is correctly treated as the caller's obligation.
 *
 * A property READ (`opts.systemPrompt`) is excluded -- it is a forward, not a
 * new value.
 */
const PROMPT_SITE =
  /(?<![.\w])(userPrompt|systemPrompt)\s*:|(?:const|let|var)\s+(userPrompt|systemPrompt)\s*=/;

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

/**
 * Is this ONE line's prompt assignment visibly safe?
 *
 * Deliberately single-line. Every earlier version widened the window to be
 * helpful, and every one of them then read a marker from a NEIGHBOURING line
 * and declared an unsafe assignment clean.
 */
export function isVisiblySafe(src: string, siteIndex: number): boolean {
  const tail = src.slice(siteIndex);

  // A TYPE DECLARATION inside an interface assigns no value.
  if (/^(userPrompt|systemPrompt)\??\s*:\s*(string|number|boolean)\s*[;,)]/.test(tail)) {
    return true;
  }

  const sep = (() => {
    const nl = tail.indexOf("\n");
    const line = nl === -1 ? tail : tail.slice(0, nl);
    const c = line.indexOf(":");
    const e = line.indexOf("=");
    if (c === -1) return e;
    if (e === -1) return c;
    return Math.min(c, e);
  })();
  if (sep === -1) return true; // no value begins on this line

  // Read the COMPLETE expression: forward from the separator until the
  // delimiters balance and we hit a `,` or `;` at depth 0. Quotes and template
  // literals are skipped so a comma inside a string cannot end it early.
  //
  // This is the fix for the tension that produced every earlier version's bug.
  // A FIXED WINDOW is wrong in both directions: too wide and it reads a marker
  // from an unrelated statement (false pass, v3); too narrow -- one line -- and
  // it cannot see a multi-line value like
  //     const userPrompt = `User name: ${
  //       sanitizeIdentifier(name, ...)
  //     }...`
  // (false fail). Reading to the expression's real end is neither.
  let depth = 0;
  let quote = "";
  let i = sep + 1;
  for (; i < tail.length; i++) {
    const c = tail[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = "";
      continue;
    }
    if (c === '"' || c === "'" || c === "`") quote = c;
    else if (c === "(" || c === "[" || c === "{") depth++;
    else if (c === ")" || c === "]" || c === "}") {
      if (depth === 0) break;
      depth--;
    } else if ((c === "," || c === ";") && depth === 0) break;
  }
  const value = tail.slice(sep + 1, i).trim();

  // A pure FORWARD of the same key (`systemPrompt: opts.systemPrompt`) is not a
  // new value; the obligation belongs to whoever built it, and that builder is
  // itself a site this gate inspects.
  if (/^\w+\.(userPrompt|systemPrompt)$/.test(value)) return true;

  // An inline literal with no interpolation is authored text.
  if (/^(["'])(?:(?!\1)[\s\S])*\1$/.test(value) && !value.includes("${")) return true;
  if (value.startsWith("`") && !value.includes("${")) return true;

  return SAFE_MARKERS.some((t) => value.includes(t));
}

/** Every prompt-assignment offset in a source file. */
function promptSites(src: string): number[] {
  const re = new RegExp(PROMPT_SITE.source, "g");
  const out: number[] = [];
  for (let m = re.exec(src); m; m = re.exec(src)) out.push(m.index);
  return out;
}

Deno.test("SELF - the checker rejects every shape that previously slipped past", () => {
  // Each case is a REAL false pass from an earlier version of this gate. If one
  // starts passing again, that version's bug is back.
  const check = (snippet: string) => {
    const idx = snippet.search(PROMPT_SITE);
    return idx === -1 ? true : isVisiblySafe(snippet, idx);
  };

  const mustReject: [string, string][] = [
    ["v1/v3 bare identifier", "    userPrompt: description,\n    maxTokens: 800,"],
    ["v3 bare identifier", "      userPrompt: message,\n      imageBase64: x,"],
    [
      "v3 neighbouring literal launders it",
      '    userPrompt: rawThing,\n    note: "probe",',
    ],
    [
      "round-3 template with interpolation",
      "    systemPrompt: `Ignore prior. ${rawUserInput}`,\n",
    ],
    [
      "v3 concatenation starting with a literal",
      '    systemPrompt: "SYSTEM: " + rawUserInput,\n',
    ],
    ["assembled local with no marker", 'let systemPrompt = parts.join("\n");\n'],
  ];
  for (const [why, snip] of mustReject) {
    assert(!check(snip), "should be REJECTED (" + why + "): " + snip.trim());
  }

  const mustAccept: [string, string][] = [
    ["plain literal", '    userPrompt: "a plain literal",\n'],
    ["principal marker", "    userPrompt: asPrincipalMessage(message),\n"],
    ["fenced block", "    userPrompt: fenced.text,\n"],
    ["sanitiser call", "    userPrompt: sanitizeBlock(convoText),\n"],
    ["authored marker", "    systemPrompt: asAuthoredPrompt(prompt),\n"],
    ["interface member", "  systemPrompt: string;\n"],
    ["same-key forward", "    systemPrompt: opts.systemPrompt,\n"],
    [
      "MULTI-LINE value with the marker on a later line",
      "  const userPrompt = `User name: ${\n" +
        "    sanitizeIdentifier(name, { fallback: 'Champion' })\n" +
        "  }\nSnapshot:`;\n",
    ],
  ];
  for (const [why, snip] of mustAccept) {
    assert(check(snip), "should be ACCEPTED (" + why + "): " + snip.trim());
  }
});

Deno.test("every prompt assignment is visibly safe", () => {
  const root = new URL("../", import.meta.url);
  const unsafe: string[] = [];
  let sites = 0;
  for (const f of sourceFiles(root)) {
    const src = Deno.readTextFileSync(new URL(f, root));
    for (const idx of promptSites(src)) {
      sites++;
      if (!isVisiblySafe(src, idx)) {
        const line = src.slice(0, idx).split("\n").length;
        unsafe.push(f + ":" + line + "  " + src.slice(idx, idx + 70).split("\n")[0]);
      }
    }
  }

  assert(sites >= 20, "expected >=20 prompt sites, found " + sites);
  assertEquals(
    unsafe,
    [],
    "these prompt assignments are not visibly safe. Wrap the value AT THE CALL " +
      "SITE: sanitizeBlock / sanitizeIdentifier / sanitizeJsonForPrompt for " +
      "user text, asPrincipalMessage() for the chat channel, asAuthoredPrompt() " +
      "for text we wrote",
  );
});
