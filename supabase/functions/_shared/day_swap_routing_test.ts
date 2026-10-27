import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DAY_SWAP_FREE_FALLBACK_LINE,
  DAY_SWAP_OLD_APP_LINE,
  daySwapRoutingBlock,
  daySwapRoutingCase,
} from "./day_swap_routing.ts";

Deno.test("free user -> free case, block carries the exact fallback line verbatim", () => {
  assertEquals(daySwapRoutingCase(false, new Set()), "free");
  assertEquals(
    daySwapRoutingCase(false, new Set(["swap_workout_days"])),
    "free",
  );
  const block = daySwapRoutingBlock(false, new Set());
  assertStringIncludes(block, DAY_SWAP_FREE_FALLBACK_LINE);
});

Deno.test("PRO + capability declared -> pro_capable, routes to swapWorkoutDays not rescheduleWeek", () => {
  const caps = new Set(["swap_workout_days"]);
  assertEquals(daySwapRoutingCase(true, caps), "pro_capable");
  const block = daySwapRoutingBlock(true, caps);
  assertStringIncludes(block, "call swapWorkoutDays with the two dates");
  assertStringIncludes(block, "Do NOT call rescheduleWeek");
});

Deno.test("PRO without capability -> pro_old_app, block carries the exact old-app line verbatim", () => {
  assertEquals(daySwapRoutingCase(true, new Set()), "pro_old_app");
  assertEquals(daySwapRoutingCase(true, new Set(["some_other_cap"])), "pro_old_app");
  const block = daySwapRoutingBlock(true, new Set());
  assertStringIncludes(block, DAY_SWAP_OLD_APP_LINE);
});

Deno.test("pro_old_app and free blocks never instruct the model to call the tool", () => {
  assertEquals(
    daySwapRoutingBlock(true, new Set()).includes(
      "call swapWorkoutDays with the two dates",
    ),
    false,
  );
  assertEquals(
    daySwapRoutingBlock(false, new Set()).includes(
      "call swapWorkoutDays with the two dates",
    ),
    false,
  );
});

Deno.test("exactly one block is returned per case (no leakage of the other two lines)", () => {
  const proCapableBlock = daySwapRoutingBlock(true, new Set(["swap_workout_days"]));
  assertEquals(proCapableBlock.includes(DAY_SWAP_FREE_FALLBACK_LINE), false);
  assertEquals(proCapableBlock.includes(DAY_SWAP_OLD_APP_LINE), false);
});
