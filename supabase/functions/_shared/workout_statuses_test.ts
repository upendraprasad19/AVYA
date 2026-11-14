import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { NON_WORKOUT_STATUSES } from "./workout_statuses.ts";

async function read(rel: string): Promise<string> {
  return await Deno.readTextFile(new URL(rel, import.meta.url));
}

// Statuses `completionRateOverWindow` skips in rank_engine.ts (`row.status === '<x>'` chain).
function rankEngineSkipSet(src: string): Set<string> {
  const start = src.indexOf("row.status === 'rest'");
  assert(start > -1, "rank_engine skip chain not found");
  const chunk = src.slice(start, src.indexOf(") continue;", start));
  return new Set([...chunk.matchAll(/row\.status === '([a-z_]+)'/g)].map((m) => m[1]));
}

// Client `invisibleScheduleStatuses` literal set.
function clientInvisibleSet(src: string): Set<string> {
  const m = /invisibleScheduleStatuses\s*=\s*\{([^}]*)\}/.exec(src);
  assert(m, "invisibleScheduleStatuses not found");
  return new Set([...m![1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]));
}

Deno.test("parity: tool set ⊇ rank_engine skip set ⊇ client invisibleScheduleStatuses", async () => {
  const rank = rankEngineSkipSet(await read("./rank_engine.ts"));
  const client = clientInvisibleSet(await read("../../../lib/core/services/workout_schedule_read_service.dart"));
  assert(client.size >= 3, "client set parsed empty");
  for (const s of client) assert(rank.has(s), `rank_engine must skip client-invisible status '${s}'`);
  for (const s of rank) assert(NON_WORKOUT_STATUSES.has(s), `tool set must exclude rank_engine-skipped status '${s}'`);
});

Deno.test("deliberate tool-only additions: skipped (and null, handled by the caller)", async () => {
  const rank = rankEngineSkipSet(await read("./rank_engine.ts"));
  const toolOnly = [...NON_WORKOUT_STATUSES].filter((s) => !rank.has(s));
  assertEquals(toolOnly, ["skipped"]);
});
