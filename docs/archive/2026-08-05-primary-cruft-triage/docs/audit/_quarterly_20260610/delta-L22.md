# Delta audit — Lens L22 (schema-vs-payload parity / column-ref correctness)

Scope: `git diff 969c117..HEAD` ∪ `git show a767725`. Focus: migrations 088
(add `razorpay_subscription_id`), 089 (widen `set_number` CHECK ≤10→≤50), and
any client/EF read/write of those columns. Snapshot currency + gate run + 090/091
(GRANT/REVOKE-only) regen-need confirmation.

## Verdict: CLEAN — 0 findings.

All L22 parity checks pass. Evidence:

1. **088 `razorpay_subscription_id` — name parity OK.** Only consumer is the
   delete-account EF: `supabase/functions/delete-account/index.ts:211`
   `.select("razorpay_subscription_id")` + reads at lines 224/228/244/251 — all
   use the exact column name added by `088_add_razorpay_subscription_id.sql:7`.
   No insert/update writes the column yet (additive nullable, populated later by
   verify-payment/razorpay-webhook when recurring billing launches — matches the
   migration COMMENT). No payload-omission risk because it is nullable, not NOT NULL
   (this is the inverse of precedent F2, where a NOT NULL column was omitted).

2. **Snapshot IS current with 088/089.** `backups/live_schema_columns.json:38`
   lists `subscriptions` with `razorpay_subscription_id` present (last element).
   `_meta.captured_at = "2026-06-08"` — regenerated in the 088 commit per the gate
   header rule. 089 changes a CHECK constraint, not the column set, so no column
   delta to capture (correctly unchanged).

3. **089 `set_number` widen — no stale client clamp.** Grep of `lib/` +
   `supabase/functions/` for `set_number` bounds: the only numeric clamps in
   `lib/core/services/sync/sync_workout.dart:259-260` and `:329-330` apply to
   **`reps`** (`clamp(0,10000)`), NOT `set_number`. `set_number` is written as a
   count (`summarySetCount` :277, `newSets.length` `workout_write_service.dart:736`)
   with no client-side upper bound — so the ≤50 widen has nothing client-side to
   contradict. Column name `set_number` is consistent across all writers
   (sync_workout, workout_write_service) and readers (workout_read_service:105,
   week_selector:776, getProgressSummary.ts:59, getPRTimeline.ts:106).

4. **Gate green.** `dart run scripts/check_schema_column_refs.dart` →
   `OK: 751 column references validated against live schema snapshot (lib/ +
   supabase/functions/); 0 drift.` The gate scans BOTH client and EF surfaces
   (server-seam extension WI-1).

5. **090/091 correctly need NO snapshot regen.** Both are GRANT/REVOKE/ALTER-
   function (search_path) only — `090` and `091` contain no `ADD/DROP/RENAME
   COLUMN`. They change EXECUTE privileges on SECURITY DEFINER functions, not the
   public-schema column set that `live_schema_columns.json` mirrors. Confirmed:
   the gate stays green at 751/0 without a regen. (Self-noted by 090's header:
   role-specific revoke was a no-op, corrected by 091's REVOKE-FROM-PUBLIC pattern
   — orthogonal to L22.)

6. **Bookkeeping parity.** 088 + 089 both recorded in
   `backups/applied_migrations.json` (entries at "migration":"088" / "089").
   SoT registry `docs/sot_registry.yaml:875` `subscriptions.columns` includes
   `razorpay_subscription_id`. Diagnose-docs b4e2a9 + a3e8f1 present.

## Findings table

| # | severity | file:line | quote | claim | verification | verdict |
|---|----------|-----------|-------|-------|--------------|---------|
| — | — | — | — | No schema-vs-payload drift in the delta scope | `check_schema_column_refs.dart` → 751 refs / 0 drift; snapshot incl. razorpay_subscription_id; delete-account EF reads exact name | CLEAN |

No fixes proposed (consolidation phase per charter).
