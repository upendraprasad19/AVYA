---
adr_id: 0001
title: Hive as primary storage; Supabase as backup
status: accepted
date: 2026-03-23
deciders: Upendra
---

# ADR-0001: Hive as primary storage; Supabase as backup

## Context

ICANBEFITTER is a fitness app for Indian young professionals (22-35). Two
non-negotiable constraints from product validation:

1. **The app must work offline.** Indian network conditions are unreliable;
   gym locations often have poor connectivity. A user logging a set must
   not block on a network round trip.
2. **Reads must feel instant.** A fitness app that lags on "what was my
   last bench press?" or "what did I eat yesterday?" loses users.
   Sub-100ms read latency is the bar.

The standard pattern in 2024-era cross-platform apps — read-through cloud
cache with optimistic local writes — violates both constraints. Cache miss
= network call = UI lag. Defeats offline-first.

## Decision

**Hive (local NoSQL key-value store) is the primary store for ALL reads
and writes.** Every user-facing read goes to Hive synchronously. Every
write goes to Hive first; cloud is a follower.

Cloud sync (Supabase, ADR-0002) is a **write-through fan-out**:
asynchronous, retry-on-fail, never blocks UI.

On sign-in to a new device, a **paginated restore** runs from cloud →
Hive. Once restore completes, the device behaves as if it had been
the original writer.

Encoded in CLAUDE.md rule 1: "Hive-first for ALL reads/writes. Never
block UI on Supabase response."

## Alternatives considered

1. **Supabase Postgres as primary; Hive as cache.** Rejected. Cache miss
   on cold-start would force a network call before any UI render. The
   "what was my last bench press" question would have user-visible
   latency proportional to network quality. Unacceptable for Indian
   gym conditions.

2. **SQLite via `drift` or `sqflite`.** Rejected. SQLite drivers are
   heavier (~5MB bundled), introduce platform-channel overhead, and
   require SQL for what are mostly key/value access patterns. Migration
   ergonomics are also more painful (each schema change requires a
   numbered migration step; Hive supports add-field-with-default at the
   adapter level).

3. **Isar.** Rejected at the time of decision (2026-03). Isar had known
   migration footguns and the maintainer's roadmap was less predictable
   than Hive's. Reconsider if Isar's footguns are resolved in a future
   batch.

4. **Realm (MongoDB).** Rejected. Vendor lock-in to MongoDB ecosystem;
   sync server costs scale per-user; cloud sync is opinionated in ways
   that don't match Supabase as the backend choice. Heavier APK.

5. **Pure in-memory + JSON file persistence.** Rejected. Loses on every
   crash; no transactional guarantees; doesn't scale past a few hundred
   workout logs per user.

## Consequences

Good:
- App works offline. PRO users can log workouts in a gym basement.
- Reads are <1ms. UI feels instant.
- Sync race conditions are encapsulated in `WriteServices` (one writer
  per concept; CLAUDE.md rule 4).
- New-device restore is a paginated cloud-read flow that can be tested
  independently (`test/contracts/restore_*_test.dart`).

Bad:
- **Writer/reader drift is a recurring bug class.** Two stores = two
  schemas. They drift. We have ≥15 instances tracked in
  `feedback_writer_reader_field_drift_recurring.md`. The drift-detector
  agent + Gate 17 + Gate 23 + behavioral_test_path requirement exist
  to compensate. The fundamental cost of this decision is paid here.
- **Schema migrations require coordinating Hive box version + Supabase
  migration + restore path.** Three places to update for one column
  change. Codified in CLAUDE.md §4.5 + `feedback_migration_apply_record_pair.md`.
- **"What's the truth?" on sync conflict needs explicit per-concept
  resolution rules.** Captured in `docs/sot_registry.yaml` — every
  concept names its canonical writer.
- **Cold-boot restore is a feature**, not a hidden behavior. We had to
  build `RestoringScreen` (Test #2) so users understand why their data
  is "loading" on a new device.

## Status

Active and load-bearing. Reverting this decision would require
rewriting every read site in the app. Don't.

## See also

- CLAUDE.md rule 1 (Hive-first)
- `docs/architecture/sync.md` — sync schedule + SoT rules
- `docs/sot_registry.yaml` — per-concept canonical writer/reader
- `feedback_writer_reader_field_drift_recurring.md` — the cost
- ADR-0002 (Supabase as backup) — the complementary decision
