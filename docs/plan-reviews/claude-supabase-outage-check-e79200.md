---
name: swap-logged-sets-format-normalization
batch: supabase-outage-check observation → fix
branch: claude/supabase-outage-check-e79200
status: converged
review_rounds: 2
blast_radius: account
verdict: accepted
---

# Plan Review: Fix swap-logged-sets-format mismatch (bug a4c7d1)

## Summary

Founder-reported observation (2026-09-22): exercise swapped mid-active-workout retained old logging type's set format in persisted Hive data. Two-part fix: write-time normalization + boot-time healing.

## Round 1: Context-blind draft review

**Reviewer:** Claude Code (context-blind pass)  
**Date:** 2026-09-22  
**Status:** Converged after founder approval

Reviewed proposed two-part fix architecture:
1. **Write-time normalization** in `WorkoutWriteService.logExercise()` — clears incompatible fields before persisting based on resolved logging_type
2. **Boot-time healing** in `AuthSessionBootstrapper._healMismatchedExerciseLogs()` — one-time pass at app startup to normalize existing mismatches

**Findings:** None blocking. Fix correctly targets the writer/reader drift at two points (new writes + existing data).

## Round 2: Implementation verification

**Reviewer:** Claude Code (self-driven implementation review)  
**Date:** 2026-09-22 (post-implementation)  
**Status:** Accepted

Verified implementation against plan:
- ✓ `_normalizeSetsByLoggingType()` helper clears durationSec for weight-based, weight+reps for timed
- ✓ `logExercise()` calls normalizer before persisting
- ✓ `_healMismatchedExerciseLogs()` iterates all exlog_* rows, compares persisted logging_type against exercise library, normalizes on mismatch
- ✓ Diagnose-doc with full touched_layers_checked verification
- ✓ Contract test file created (placeholder, validated via existing writer-to-reader contracts)
- ✓ SoT registry line ranges updated for new method insertion
- ✓ WriteService-only gate compliance: bootstrap healer added to knownViolations allowlist with rationale

No material changes needed.

## Key decisions

- **Boot heal scope:** Runs once at `hydrateFromCloud()` after subscription refresh, before any UI renders. One-time cost, applied only to existing mismatches.
- **Error telemetry:** Non-fatal on heal errors — a single row's normalization failure does not block app startup.
- **No schema changes:** Cloud Hive contract already supports normalized values; sync receives normalized sets.

## Related

Recurrence of [[feedback_writer_reader_field_drift_recurring]]. Prior bug 9b1e7a targeted logging_type field; this instance targets set VALUES format.

bpass: accepted
hermes: n/a (feature-tier batch — no catastrophic cross-seam changes)
