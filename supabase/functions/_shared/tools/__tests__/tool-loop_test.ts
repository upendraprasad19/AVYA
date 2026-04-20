import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import {
  _clearRegistryForTesting,
  _registerToolForTesting,
  allTools,
} from "../registry.ts";
import type { ToolDefinition } from "../types.ts";

// Stub helpers to fake Gemini responses without HTTP calls.
// We monkey-patch by replacing the module's geminiChatWithTools export.
// Deno doesn't natively support module mocking — so we test by registering
// tools whose handlers are called and tracking the invocation.

function makeReadTool(
  name: string,
  returns: Record<string, unknown>,
): ToolDefinition {
  return {
    name,
    family: "progress",
    kind: "read",
    tier: "free",
    description: name,
    schema: z.object({ x: z.string() }),
    handler: async () => returns,
  };
}

function makeWriteTool(
  name: string,
  tier: "free" | "pro" = "free",
): ToolDefinition {
  return {
    name,
    family: "workout",
    kind: "write",
    confirmationClass: "trivial",
    tier,
    description: name,
    schema: z.object({ x: z.string() }),
    intentBuilder: (args) => ({
      type: "test_write",
      payload: args as Record<string, unknown>,
      confirmationClass: "trivial",
      previewSummary: "test",
    }),
  };
}

// NOTE: Most assertions in this file depend on swapping the real
// geminiChatWithTools for a fake. Without Deno module mocking helpers,
// these tests are written as DOCUMENTATION of expected behavior. When
// run in a CI environment with proper module mocking (esm.sh, sinon,
// or hand-rolled stub injection), they should pass.

Deno.test({
  name: "tool-loop — registry filters by tier (PRO tool hidden from free user)",
  fn: () => {
    _clearRegistryForTesting();
    _registerToolForTesting(makeWriteTool("freeOnly", "free"));
    _registerToolForTesting(makeWriteTool("proOnly", "pro"));

    // Just exercise the registry directly — avoids gemini mock
    // (loop tests proper require mocking geminiChatWithTools)
    const free = allTools(false).map((t) => t.name);
    const pro = allTools(true).map((t) => t.name);

    assertEquals(free, ["freeOnly"]);
    assertEquals(pro.sort(), ["freeOnly", "proOnly"]);
  },
});

Deno.test({
  name: "tool-loop — registry returns read tools for free users",
  fn: () => {
    _clearRegistryForTesting();
    _registerToolForTesting(makeReadTool("readFree", { ok: true }));
    _registerToolForTesting(makeWriteTool("writeFree", "free"));
    _registerToolForTesting(makeWriteTool("writePro", "pro"));

    const free = allTools(false).map((t) => t.name).sort();
    assertEquals(free, ["readFree", "writeFree"]);
  },
});

// Reference helpers so unused-symbol lints don't strip them. The full
// multi-round runToolLoop test is gated on a module-mocking shim and is
// the next item to add when CI grows that capability.
void makeReadTool;

// TODO: Add full multi-round loop tests once module mocking is set up.
// Current minimum coverage: schema validation + tier filter + intent builder
// shapes are exercised through framework + per-tool tests.
