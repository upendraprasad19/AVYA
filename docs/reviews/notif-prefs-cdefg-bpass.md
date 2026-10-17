---
reviewed_at: 2026-07-27
branch: notif-prefs-cdefg
blast_radius: platform
reviewer: independent context-blind adversarial B-pass
lens_set: [fail_safe_direction, cross_account_leak, emission_survival, guard_placement, legacy_alias, ui_lock_state, test_vacuity]
findings_count: 14
verdict: accepted
---

# B-pass — notif-prefs Units C..G

**One P0, three P1s, six P2s, four P3s.** Four of the five blockers were defects
I introduced. All blockers and the two highest-value P2s are fixed in `e4897a98`.

## P0 — the guard was wired into the wrong mode

`morning-alert/index.ts` — I threaded the preferences through **generate** mode
(`processBatch` → `generateAndStoreAlert`, where nothing consulted them) while
the actual check sits in **deliver** mode, referencing `notifPrefs` and `user`.
Neither exists in `deliverAlerts`; its callback parameter is `snap`.

CI's Deno type-check would have failed on TS2304. Had it reached production the
ReferenceError fires inside `Promise.allSettled` and is swallowed — **every
morning alert silently stops being delivered, for every user**, with `pushSent`
stuck at 0 and no error surface.

**The test lesson is worth more than the fix.** My own
`notification_prefs_server_guard_test` asserts the file *contains*
`isNotificationEnabled(` — which it did. All 27 new tests passed on the broken
file. Presence is not placement, and a source-grep adoption test cannot tell the
difference.

Fixed: guard moved into `deliverAlerts` using `snap.user_id`, prefs fetched per
chunk there, dead generate-mode threading removed.

## P1 — Unit A turned three dead links into three lying controls

`settings_screen.dart` pushes the route with **no `extra`**, so the router's
defaults applied: empty prefs (every toggle renders ON regardless of stored
state), `isPro: false` (a *paying PRO user* sees a lock), and an `onSave` that
discards. A dead link fails visibly; this failed silently while looking like it
worked — strictly worse than the bug it replaced.

The route test I wrote is the one that should have caught it and instead
ratified it: it asserts `src.contains('onSave')`, trivially true.

Fixed: the screen is self-sufficient — reads through the repository when the
caller supplied nothing, and persists the same way.

## P1 — writes never reached the server until the next launch

The repository wrote Hive and stopped. Every sibling WriteService fires
`unawaited(SyncService.instance.pushSnapshot())`; this one did not. A user
turning Morning Check-in off at 22:00 still received the 07:00 push, because
both the 02:00 generate and 07:00 deliver read the pre-change snapshot — the
exact "my toggle did nothing" failure the batch exists to remove. Fixed.

## P1 — `== true` was the one surviving inversion

`pref['enabled'] == true` in the settings screen, in a batch whose thesis is
*only a literal `false` disables*. `_setTime`/`_setDay` write `{time: ...}` with
no `enabled`, so **changing a reminder time flipped its own toggle off** — a
guaranteed repro, no corruption needed. Three readers disagreed on the same
value. Fixed to `!= false`, matching `normalize()` and the server.

## P2 — fixed

- **Promotion guard suppressed the chat message too.** The early return skipped
  the `ai_coach_interactions` insert, so opting out of a *notification* deleted
  the coach's congratulation from chat history. It is the only guarded function
  writing a persistent in-app record. Now gates the push only.
- **The cited parity test did not exist.** The repository's docstring claimed
  key parity was "pinned by `notification_prefs_parity_test.dart`". Written.
- **Nothing pinned the emission.** Deleting the single line that makes the arc
  work left all 27 other tests green — the TRAP-1 test proves the trimmer *would*
  drop the key but says nothing about where it is emitted. Now pinned, with a
  negative control showing removal fails 2 assertions.

## P2/P3 — accepted as accurate, recorded not fixed

Each is real and none blocks the merge; all are in the closure ledger with a
terminal state and in `docs/audit/open_issues.md`.

- **Unbounded `snapshot_json` fetch** in the shared helper — no `.limit`, no
  JSON-path projection, so it re-imports each page's whole snapshot history.
  Real scale risk (EF memory, PostgREST truncation → degrades to SEND). The fix
  shape is a `snapshot_json->notification_preferences` projection or a
  `DISTINCT ON (user_id)` RPC — a schema-adjacent change that deserves its own
  review rather than a late edit here.
- **SoT registry entry** for the new writer/reader contract.
- **The legacy alias cannot do what it claims** (P3, and the reviewer is right):
  the singular key only ever lived in `configBox`, which Unit C *deletes*, so
  the alias can only resolve the app's own default. Harmless — the server never
  saw those values — but the "TRAP 2 closed" phrasing overstates it. Corrected
  in the ledger.
- **Count includes 2 PRO-locked rows** a free user cannot disable.
- **Paywall feature id** is `featureProgressPhotos` — wrong copy for a
  notification row.

## Verified clean under attack

- **Fail-safe direction** — `normalize`, `emissionMap`, `isNotificationEnabled`
  and the helper's error/throw paths all default to SEND. Only a literal `false`
  silences. (The `== true` exception is fixed above.)
- **Cross-account** — the purge is genuinely delete-only, `userBox` is
  namespaced per user, the repository session-gates before touching the box, and
  the A→B→A behavioural test proves isolation rather than data loss.
- **Emission survival** — confirmed `buildAiContext` ends
  `return trimSnapshotToBudget(context, budget: 9500)`; `daily-snapshot`
  upserts wholesale with no size cap; the 10K AI cap is not in this path.
- **Guard placement** before the dedup gate is correct; no `continue` skips
  cleanup; counters reach both the log line and the JSON body.
- **The four non-adopter guards really are latest-desc** — that test is not
  false-passing.
