---
reviewed_at: 2026-11-14T18:59:50+05:30
staged_against: b55bc328 (round 1, committed three-dot diff origin/main...b55bc328, CI green on the head) and f3c9fc41 (delta round, diff b55bc328..f3c9fc41, CI green on the merged head f3db5175)
blast_radius: account
reviewer: claude-sonnet-via-skill (round 1: three fresh agents, no conversation context, split engine / hosts / docs-registry-manifest; delta round: one fresh agent on the fix commit; read-only, no file edits, lens 6 by reading)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 22
verdict: accepted
verdict_note: 29 raw findings from 4 reviewers (24 + 5; one P1 reported by all three round-1 reviewers) collapse to 22 unique; every one is fixed, documented as a known limit, or routed to a named device check; none deferred (ledger docs/audit/voice-input-unified.closure.yaml)
---

# Code Review (B-pass) — one speech input for the coach, the nutrition Log sheet and the web app (`voice-input-unified`, PR #273)

Two rounds. No P0. One P1 (found independently by all three round-1 reviewers), five P2, sixteen P3. Triage was done by the coordinator against the code, the plugin source (`speech_to_text` 7.4.0 Dart and Android Kotlin) and the tests; every finding below was verified before it was accepted. The reviewers were told the founder's scope decisions and the plan's rejected alternatives and none re-opened one.

## Round 1 (b55bc328): three reviewers

### Finding 1 — P1 — guard_without_its_mirror / missing_input (all three reviewers)
- **file:line:** `lib/core/services/speech_input_controller.dart` `_start` / `_armStartTimeout`; `speech_input_service.dart` `begin`
- **claim:** the 4 s native start timeout and the one-restart window were armed at the tap, but the first `initialize` is where Android shows the system microphone dialog, so a slow Allow gave "Could not hear you" and abandoned the session.
- **verification:** `sed -n 201,247p lib/core/services/speech_input_controller.dart`; plugin `SpeechToTextPlugin.kt:503-520, 711-720` (initialize completes only from `onRequestPermissionsResult`); no other `RECORD_AUDIO` request in `lib/`.
- **status:** accepted, fixed in f3c9fc41 (45 s first-use pre-listen budget, listen budget and restart window armed by an `onListenIssuing` hook right before `engine.listen`, `initialize` bounded at 60 s). Diagnose `abe150`. Mutants M1, M2, M3b reddened 2, 2, 6 tests; M3 was equivalent.

### Finding 2 — P2 — guard_without_its_mirror
- `_retry` cancelled `_endGrace` / `_errorGrace` without nulling; `engineNotListening` / `engineDone` arm with `??=`, so a native end with no final hung after a retry. **status:** accepted, fixed (null them); two retry-grace tests; mutants M4a (2 reddened), M4b (1), M4c (1).

### Finding 3 — P2 — guard_without_its_mirror
- A Stop commit requested keyboard focus for every commit reason, so a hidden tab could raise the keyboard (offstage children take focus). **status:** accepted, fixed (`speechEndWantsFocus`, false for hidden and preempted); mutants H2, H3, H7, H8.

### Finding 4 — P2 — guard_without_its_mirror
- `FoodLoggerSection` lives in a modal bottom sheet with no Scaffold, so its snackbars drew behind the sheet. **status:** accepted, fixed (inline `speech_notice`, cleared on mic tap, analyse and typing); the harness is now Scaffold-free; mutants H4, H5a, H5b.

### Finding 5 — P2 — asserted_fixture_value
- Coach Send with typed text had no test (`onSend(end.transcript)` survived). **status:** accepted, fixed; mutant H6.

### Findings 6 to 16 — P3
6. Preempt only at call time, so a second host tapping while the first waits in the slot made both listen. Fixed (`_inFlight`); mutants M5, M6. 7. `await _ensureReady()` in the slot had no bound. Fixed (60 s, memo kept); mutant M7. 8. Host busy callback unguarded (two reviewers). Fixed (`_notifyBusy`); mutant M8. 9. `doneNoResult` / `recognizerNotAvailable` comparisons never reach the service on 7.4.0. Kept as defensive and commented, no behaviour change. 10. Fake delivered `done` while partial; fixed (then corrected by the delta round, finding 18). 11. Web `listen` exception clears `_engineActive`: NOT established, routed to OI-348 S6 (T9-WEB). 12. "written THEN analyse" order unobservable: test and plan statement reworded. 13. One-frame measurement-chip flash after Stop: fixed (busy:false deferred past the focus request); mutant H1. 14. Stale header and no behavioral cap test: header fixed, presence-pin test added. 15. Doc misattribution (`VoiceNotesButton`), an undefined mutant id and a missing blank line in bug-class text: fixed. 16. Docs: "drops every engine event" over-claim, `newController`, a typo, registry `box` convention, "not a plugin limit" and `en_IN` in the flow doc, "3 permission categories", stale on-device comments and a PRO row for free voice: fixed, and `speech_privacy_copy_test` now scans three more files.

Not established, routed to a device step (not defects): the nutrition field may not scroll to the newest words (A19 step 8); the merged release manifest `INTERNET` permission (A19 step 5).

## Delta round (f3c9fc41): one reviewer

### Finding 17 — P2 — asserted_fixture_value
- The fake swallowed every `done` until a final, but Android sends `doneNoResult` when no result was sent and Dart rewrites it to `done` and DELIVERS it. So a silent session's `done` was withheld, the "device never produces" comments were false, and a real order was untested. This was the coordinator's own over-generalisation of round-1 finding 10. **verification:** `SpeechToTextPlugin.kt:418-427`, `speech_to_text.dart:734-737`, the plugin's own test "done sent with no results on doneNoResult". **status:** accepted, fixed (`_resultSent` in the fake, silent-session tests restored, five comments and two docs corrected); mutant D1 reddened 2.

### Finding 18 — P3 — guard_without_its_mirror
- An older `begin` of the SAME controller clears the newer one's `_inFlight` marker (`identical(_inFlight, sink)` is true for both). **status:** accepted, fixed (per-call `_inFlightSeq` token); mutant D2.

### Findings 19 to 22 — P3
19. An `initialize` that never answers leaves the microphone unavailable until restart (a second plugin initialize answers `multipleRequests`): documented as a KNOWN LIMIT, a hypothesis not an observation. 20. A misplaced comment in the options test: moved. 21. The at-the-cap test is a presence pin (three guards): renamed and commented. 22. Web allows 15 s for the browser prompt (raised by the listen): stated as the intended allowance, a slow-Allow step added to OI-348 S6.

## Lenses checked clean (both rounds)
Lens 2 (no `functions.invoke` in the diff), lens 3 (blast radius `account` is the highest tier the touched paths imply: `docs/blast_radius.yaml:424, 651, 655, 659`), lens 4 (a credential-regex scan of every `+` line found only test strings), lens 1 registry ranges (re-opened by hand after each round, every range brackets its method), lens 5 (every new `unawaited` target has an error sink).

## Mutation record (rule 21, self-attested)
Build time: controller 42 mutants, coach composer 21, nutrition 21, manifest 1. Remediation: 11 engine mutants (M1 M2 M3b M4a M4b M4c M5 M6 M7 M8 M9), 9 host mutants (H1 H2 H3 H4 H5a H5b H6 H7 H8), 2 delta mutants (D1 D2); each reddened a named test and each was restored and confirmed (`cmp`). Equivalent: M3. Not run on a device or a browser.

## Founder triage notes
Triaged by the coordinator, not by the founder. The founder-only items stay open on the ledger: T8-DEVICE, T9-WEB, WEBSITE-POLICY and MERGE-GO.

## Tuning entry
- **2026-11-14** - blast-radius account - 22 unique findings (29 raw from 4 reviewers); 0 false_alarm; tuning: lens 8 gains a test-double sub-check (read BOTH sides of a platform rule before modelling it: the coordinator's own fix to a round-1 finding over-generalised the plugin's `done` filter and only the delta round caught it), and the brief practice that worked is kept: name the plugin source path, give the reviewers the founder's scope decisions, and let two reviewers overlap on the engine slice (all three found the P1 independently).
