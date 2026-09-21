// supabase/functions/daily-snapshot/index_test.ts
//
// index.ts calls `serve(...)` at module scope with no `import.meta.main`
// guard, so importing it directly would boot a real HTTP server (the exact
// trap supabase/functions/CLAUDE.md warns about). This is a SOURCE-GREP
// wiring test — it proves the handler actually calls the merge-safe path
// fixed for diagnose d8a2f6, not just that the path exists somewhere.
// Behavioral coverage of the merge logic itself lives in
// ../_shared/snapshot_merge_test.ts (mutation-proven).

import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

Deno.test("daily-snapshot imports the shared merge helper", () => {
  assert(
    source.includes('import { mergeSnapshotJson } from "../_shared/snapshot_merge.ts";'),
    "index.ts must import mergeSnapshotJson from the shared module",
  );
});

Deno.test("daily-snapshot reads the existing row with maybeSingle before upserting", () => {
  assert(
    source.includes(".maybeSingle()"),
    "must use maybeSingle() — a first-ever snapshot of the day has no " +
      "existing row, and .single() would throw on that legitimate case",
  );
});

Deno.test("daily-snapshot upserts the MERGED result, not the raw request payload", () => {
  assert(
    source.includes("mergeSnapshotJson("),
    "the merge helper must actually be called",
  );
  assert(
    source.includes("snapshot_json: mergedSnapshotJson"),
    "the upsert must write the merged value — writing raw `snapshot_json` " +
      "here is exactly the pre-fix bug (a blind wholesale replace)",
  );
});

Deno.test("daily-snapshot's merge-safe path has a kill-switch (platform-tier §4.6)", () => {
  assert(
    source.includes('Deno.env.get("DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT")'),
    "platform tier requires a feature_flag per docs/blast_radius.yaml — " +
      "the merge-read must be gated so it can revert to the verbatim " +
      "pre-fix blind-replace upsert without a redeploy",
  );
  assert(
    source.includes("let mergedSnapshotJson: Record<string, unknown> = snapshot_json;"),
    "the kill-switch's fallback value must be the RAW payload (the exact " +
      "pre-fix behavior), not an empty object or the merge result",
  );
});

Deno.test("daily-snapshot logs (not swallows) a failed existing-row read", () => {
  assert(
    source.includes("existingRowError"),
    "the existing-row SELECT's error must be captured, not discarded — an " +
      "unread error silently degrades to the pre-fix blind-replace with " +
      "zero trace, indistinguishable from the legitimate absent-row case",
  );
  assert(
    source.includes("console.error(") &&
      source.includes("existing-row read failed"),
    "a failed read must be logged so the degradation is observable",
  );
});
