import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildWindowClosingMessage } from "./message.ts";

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
