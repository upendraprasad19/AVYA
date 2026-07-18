---
review: B-pass (context-blind, adversarial)
branch: workout-adherence-8a3a2
scope: ⑧ Batch 8 · UNIT 3-a2 (W2.5) — ship-dark repeat-default + `({generated,repeated})` return + phase-repeat nudge
blast_radius: account
verdict: accepted
---

# B-pass — ⑧ UNIT 3-a2 (ship-dark repeat-default + nudge)

Self-initiated ≥account B-pass (§4.3) on the implemented, staged diff BEFORE the `--no-ff` merge. A
context-blind adversarial reviewer verified every claim against the actual code, ran the reader-manifest
gate (passes), and ran `flutter analyze` on all changed files (No issues found).

## Verdict: accepted — no P0, no P1.

## Classes verified CLEAN (reviewer read the code)
- **Return-type ripple** — every caller of `autoGenerateNextPhaseIfNeeded` absorbs the
  `Future<bool>`→`Future<({bool generated, bool repeated})>` change: `pro_phase_advance.dart` +
  `simulation_service.dart:560` read `.generated`; the facade `=>`-forwards the record; the public
  `advanceProPhaseIfExpired` signature is UNCHANGED (`Future<bool>`), so `splash_screen`/
  `phase_generating_card` consumers are unaffected. No caller left on the old bool.
- **Cross-account nudge gate (load-bearing P1-A)** — `HiveUserSession.currentOwnerFullId` is the correct
  static accessor and mirrors the codified precedent `subscription_service.dart:300/:368`; the gate is
  genuinely necessary (`MigratedKey.write` falls back to the device-shared `configBox` when the owner is
  null → next-account leak); the write is correctly `await`ed.
- **Clear-on-dismiss / survives-rebuild (P1-C)** — `PhaseRepeatNudgeNotifier.build()` is read-only; `dismiss()`
  persists false + `state=false`. No "clears in build" bug.
- **Inertness (flag OFF) — byte-identical generation path** — `adherenceGateEnabled` false → `&&`
  short-circuits (rate never computed) → `repeatContent:false` → `pins:null` → `repeated:false` → nudge never
  written → provider false → banner `SizedBox.shrink`. The banner adds one inert `MigratedKey.read` returning
  shrink (the intended new UI element, not a generation regression).
- **Null-safety / analyzer / imports / Wardroom tokens** — analyze clean; all banner tokens exist;
  `accent = 0xFFD4B270` (Campaign Gold, not a palette drift); no force-unwraps.
- **Test adequacy** — the `repeat_content_scheduling_test.dart:302-304` `.generated`/`.repeated` asserts are
  meaningful (flag ON at :272); the nudge test's `invalidate→still-true` genuinely fails if build() cleared the
  flag (pins P1-C), dismiss→false→invalidate→still-false pins persistence — non-tautological. The teardown
  `[MigratedKey.read] configBox … threw` log is confirmed benign (fires only from the catch when `configBox.get`
  throws on a CLOSED box in tearDownAll; during assertions the B-read returns null cleanly — no assertion corrupted).
- **SoT** — `reader_manifest_complete: false` is correct + honest (the manifest detector doesn't see
  `MigratedKey.read/write` → `true` would pass vacuously); the `repeat_content_scheduling` refresh is accurate.

## P2 notes (non-blocking)
- **P2-1 (`dismiss()` fire-and-forgets `MigratedKey.write`) — accepted as-is.** Not an analyzer issue (the
  method isn't async); in-session reads are correct because Hive's in-memory `put` is synchronous; only an
  app-kill inside the disk-flush window could resurrect the (dismissible) nudge once — non-data-loss, by-design
  for UI responsiveness, and it matches the sibling expiry-banner `dismissForToday()` pattern.
- **P2-2 (null-owner write-gate not behaviorally exercised) — PARTIALLY CLOSED in-batch.** The
  `currentOwnerFullId != null` runtime state (uid non-null + owner null) is impractical to simulate
  behaviorally, and the gate mirrors the codified+tested `subscription_service` belt. Added a source-anchored
  pin (`phase_repeat_nudge_test.dart`, comment-stripped) that FAILS if the owner-gate is silently removed from
  the nudge write — closing the loop against regression without the impractical null-owner harness.
