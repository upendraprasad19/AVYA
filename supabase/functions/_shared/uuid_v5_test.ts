import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SYNC_NAMESPACE, uuidV5, workoutLogIdForDate } from "./uuid_v5.ts";

// RFC 4122 appendix B namespace and a widely published v5 vector
// (python: uuid.uuid5(uuid.NAMESPACE_DNS, "www.example.com")).
const NAMESPACE_DNS = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";

Deno.test("uuidV5 — matches the published RFC 4122 DNS vector", async () => {
  assertEquals(
    await uuidV5("www.example.com", NAMESPACE_DNS),
    "2ed6657d-e927-568b-95e1-2665a8aea6a2",
  );
});

Deno.test("the app's sync namespace IS the RFC DNS namespace (pinned, not assumed)", () => {
  assertEquals(SYNC_NAMESPACE, NAMESPACE_DNS);
});

Deno.test("workoutLogIdForDate — reproduces real LIVE workout_log_ids written by the Flutter app", async () => {
  // Read-only SELECT on the live project (dedsavbjuwgarrhphgnl) 2026-10-07:
  // each id below is a workout_log_exercises.workout_log_id the app wrote
  // (Dart `Uuid().v5(ns, 'workout_<date>')`), paired with the IST date of that
  // row's completed_at (all rows of one id share the day). The id->date
  // pairing is what the server uses to attribute a row to its DAY.
  const live: Array<[string, string]> = [
    ["31ec0901-0c1c-575f-8010-70cd2106e0c3", "2026-09-29"],
    ["b0c4016e-df58-5905-972a-85307e42da6e", "2026-05-07"],
    ["c08ae89d-54e4-51c5-b039-8f12b3f40e4a", "2026-05-04"],
    ["e333de09-768c-5a38-8597-1a4c6b96f4ea", "2026-05-02"],
  ];
  for (const [id, date] of live) {
    assertEquals(await workoutLogIdForDate(date), id, `v5('workout_${date}')`);
  }
});

Deno.test("uuidV5 — version nibble 5, RFC 4122 variant, lowercase", async () => {
  const id = await workoutLogIdForDate("2026-01-01");
  assertEquals(id[14], "5");
  assertEquals("89ab".includes(id[19]), true);
  assertEquals(id, id.toLowerCase());
});

Deno.test("uuidV5 — a malformed namespace is refused", async () => {
  await assertRejects(() => uuidV5("x", "not-a-uuid"), Error, "not a UUID");
});
