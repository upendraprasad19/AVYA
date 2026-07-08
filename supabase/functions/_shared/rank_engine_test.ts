// OPT-E — behavioral tests for the batch-pre-fetch grouping helpers added to
// rank_engine.ts. evaluate-rank-promotions/index.ts used to issue one
// user_progress / rank_promotions / user_profile query PER USER PER TICK;
// OPT-E replaces each with a single .in("user_id", allIds) call + one of
// these pure grouping functions. The risk surface OPT-E introduces is
// entirely in the grouping logic (multi-row-per-user aggregation, absent-user
// handling) — the per-user gate logic itself (qualifies/highestQualified) is
// untouched, so these tests pin the grouping, not the ladder.
//
// Run: deno test supabase/functions/

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildCurrentRankMap,
  buildRankPromotionsMap,
  buildUserProgressMap,
} from "./rank_engine.ts";

Deno.test("buildUserProgressMap — keys rows by user_id, preserves fields", () => {
  const map = buildUserProgressMap([
    { user_id: "u1", current_streak_days: 10, deployments_complete: 2 },
    { user_id: "u2", current_streak_days: 0, deployments_complete: 0 },
  ]);
  assertEquals(map.get("u1")?.current_streak_days, 10);
  assertEquals(map.get("u2")?.deployments_complete, 0);
});

Deno.test("buildUserProgressMap — a user with no row is absent (matches old maybeSingle→null)", () => {
  const map = buildUserProgressMap([{ user_id: "u1", current_streak_days: 10 }]);
  assertEquals(map.get("zero-workout-user"), undefined);
  // Caller does `progressMap.get(userId) ?? null` — confirm that composes correctly.
  assertEquals(map.get("zero-workout-user") ?? null, null);
});

Deno.test("buildUserProgressMap — empty batch produces an empty map", () => {
  const map = buildUserProgressMap([]);
  assertEquals(map.size, 0);
});

Deno.test("buildRankPromotionsMap — groups multiple ranks for the same user into one Set", () => {
  const map = buildRankPromotionsMap([
    { user_id: "u1", rank_code: "SD2" },
    { user_id: "u1", rank_code: "SD1" },
    { user_id: "u1", rank_code: "LS" },
    { user_id: "u2", rank_code: "SD2" },
  ]);
  assertEquals(map.get("u1"), new Set(["SD2", "SD1", "LS"]));
  assertEquals(map.get("u2"), new Set(["SD2"]));
});

Deno.test("buildRankPromotionsMap — a brand-new user with zero earned ranks is absent (matches old empty-array query)", () => {
  const map = buildRankPromotionsMap([{ user_id: "u1", rank_code: "SD2" }]);
  assertEquals(map.get("brand-new-user"), undefined);
  // Caller does `ranksMap.get(userId) ?? new Set<string>()` — confirm equivalence
  // to the old `new Set((existing ?? []).map(...))` on an empty array.
  assertEquals(map.get("brand-new-user") ?? new Set<string>(), new Set());
});

Deno.test("buildRankPromotionsMap — empty batch produces an empty map", () => {
  const map = buildRankPromotionsMap([]);
  assertEquals(map.size, 0);
});

Deno.test("buildCurrentRankMap — a row with an explicit null current_rank_code resolves to null (not absent)", () => {
  // A user_profile row CAN exist with current_rank_code still NULL (new signup,
  // never promoted) — distinct from "no profile row at all". Both must resolve
  // to `null` for the caller, but via different map states (present-with-null
  // vs absent-key) — verify the present-with-null case explicitly.
  const map = buildCurrentRankMap([{ user_id: "u1", current_rank_code: null }]);
  assertEquals(map.has("u1"), true);
  assertEquals(map.get("u1"), null);
});

Deno.test("buildCurrentRankMap — a user with no profile row is absent (matches old maybeSingle→null)", () => {
  const map = buildCurrentRankMap([{ user_id: "u1", current_rank_code: "PO" }]);
  assertEquals(map.get("no-profile-user"), undefined);
  assertEquals(map.get("no-profile-user") ?? null, null);
});

Deno.test("buildCurrentRankMap — preserves a real rank code", () => {
  const map = buildCurrentRankMap([{ user_id: "u1", current_rank_code: "CPO" }]);
  assertEquals(map.get("u1"), "CPO");
});
