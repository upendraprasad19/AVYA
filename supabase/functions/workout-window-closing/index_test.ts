import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildWindowClosingMessage } from "./message.ts";
import {
  deletedTemplateIds,
  excludeDeletedTemplateRows,
} from "./deleted_template_filter.ts";

Deno.test("buildWindowClosingMessage: with a name and workout name", () => {
  assertEquals(
    buildWindowClosingMessage("Rahul", "Push Day"),
    "Rahul — haven't seen Push Day logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("buildWindowClosingMessage: null name omits greeting", () => {
  assertEquals(
    buildWindowClosingMessage(null, "your workout"),
    "haven't seen your workout logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("workout-window-closing no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from workout-window-closing/index.ts");
  }
});

// OI-252 (stable ID rework) -- deleted_template_filter.ts.

Deno.test("deletedTemplateIds: collects only rows with a non-null deleted_at", () => {
  const ids = deletedTemplateIds([
    { id: "live-1", deleted_at: null },
    { id: "dead-1", deleted_at: "2026-09-26T00:00:00Z" },
    { id: "dead-2", deleted_at: "2026-09-25T00:00:00Z" },
  ]);
  assertEquals([...ids].sort(), ["dead-1", "dead-2"]);
});

Deno.test("deletedTemplateIds: empty input yields an empty set", () => {
  assertEquals(deletedTemplateIds([]).size, 0);
});

Deno.test("excludeDeletedTemplateRows: drops a user whose scheduled template is deleted", () => {
  const byUser = new Map([
    ["user-a", { template_id: "dead-1" }],
    ["user-b", { template_id: "live-1" }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-b"]);
});

Deno.test("excludeDeletedTemplateRows: a null template_id is NEVER excluded", () => {
  // This is exactly the case a `!inner` embed join would have wrongly
  // dropped (round-2 plan review) -- a plain, non-template workout day
  // must survive the filter regardless of what is deleted.
  const byUser = new Map([
    ["user-a", { template_id: null }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-a"]);
});

Deno.test("excludeDeletedTemplateRows: an unrelated deleted id does not affect a live row", () => {
  const byUser = new Map([
    ["user-a", { template_id: "live-1" }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-a"]);
});
