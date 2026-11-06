import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildPlateauMessage } from "./message.ts";

Deno.test("buildPlateauMessage: with a name, greeting is prefixed", () => {
  assertEquals(
    buildPlateauMessage("Rahul"),
    "Rahul — weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?",
  );
});

Deno.test("buildPlateauMessage: null name (private mode) omits the greeting", () => {
  assertEquals(
    buildPlateauMessage(null),
    "weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?",
  );
});

Deno.test("plateau-alert no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from plateau-alert/index.ts");
  }
});
