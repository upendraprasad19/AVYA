# OI-89 + OI-98 — rebuild spec

> **Status:** HELD. This branch (`launch-blockers-1` @ `d45d7182`) contains a first attempt at both
> fixes that a five-lens Hermes pass proved **does not work**. The converged remainder of that
> batch shipped separately as `launch-blockers-1a`.
>
> **Do not merge this branch as-is.** Rebuild from this spec.
>
> Written 2026-08-25 so the evidence survives the split. Everything below was verified against code
> or live data — where a claim is unverified it says so.

---

## Why this exists

The first attempt was reviewed three times. A B-pass found 3 findings (all fixed). A Hermes pass
across L1, L11, L15, L37 and L39 then found **~15 more, including two P0s that broke both headline
fixes**. Per §4.12.1 — *"when successive reviews keep surfacing new material issues, that is the
signal the unit is too large"* — the unit was split rather than reviewed a fifth time.

The most useful thing this batch produced is not its code. It is the evidence below.

---

## OI-89 — a bodyweight-only user is still prescribed gym lifts

### The defect the first attempt did NOT fix

`Chin Up` (needs a pull-up bar) and `Standing Calf Raise` (needs a barbell) still reach a user who
selected "Bodyweight — no equipment needed". `Chin Up` is **one of the three exercises OI-89
literally reported**.

### Root cause — the guard keys on the wrong field

The attempt added `isBodyweightOnlyTier` and gated `_cascadeFill` attempts 4 and 5 on
`equipment_tier`. That field is the wrong signal, and the repo already says so.

`docs/sot_registry.yaml` (concept `exercise_equipment_tier`), verbatim:

> `equipment_tier ← current ∪ {T : EquipmentVocab.tierItems[T] ⊇ normalize(equipment_needed)}`
> on 90 rows (ADD-only). Invariant: derive ⊆ equipment_tier (no under-tag); **over-tags
> tolerated** (a separate later drop-side pass).

and its `readers:` says `queryV4` is the *"sole production reader"*.

So a **hard safety floor** was built on a field whose own contract documents it as imprecise in
exactly the unsafe direction — and became a second reader of it without registering as one.

**Four bundled rows are tiered `bodyweight` while `equipment_needed` names real kit** (verified by
parsing `assets/data/exercise_library.json`):

| name | `equipment_needed` | `movement_pattern` |
|---|---|---|
| Standing Calf Raise | `['barbell']` | `knee_dominant` |
| Chin Up | `['pull-up bar']` | `vertical_pull`, `warmup` |
| Reverse Crunch | `['bodyweight','bench']` | `core` |
| Decline Push Up | `['bodyweight','bench']` | `horizontal_push` |

A Hermes probe driving the **real** `ExerciseSelector.pickV4` against the real library at
`d45d7182` (`equipmentTier: bodyweight`, `beginner`, `phase: 1`) found **6 leaks across 3
patterns**. `Chin Up` reached `elbow_flexion` via `universalPoolV4` — i.e. it passed the brand-new
attempt-5 skip, because `_isBodyweightTierRow(ChinUp)` is `true`.

### Why the test could not catch it — three independent reasons

1. **The oracle copies the code's blind spot.** `_isBodyweightRow` in the test reads
   `equipment_tier`, the same field as the production predicate. The assertion is tautological with
   respect to the harm.
2. **The patterns exclude both leaks.** `_shallowPatterns` covers `elbow_flexion`,
   `elbow_extension`, `shoulder_isolation`, `vertical_push`. Both leaks live in `knee_dominant`
   and `vertical_pull`.
3. **`'chin up'` was dropped from the banned list.** The test bans `'barbell curl'` and
   `'close-grip bench press'` with the reason *"the literal exercise OI-89 reported"* — and omits
   the third, which is the one that still ships.

### The rebuild

- Key the floor on **`equipment_needed`**: a row is bodyweight-performable iff
  `EquipmentVocab.fromProfile(row['equipment_needed'])` ⊆ `{bodyweight, none}`. Reuse that helper —
  it already absorbs the String-vs-List crash class (`e9d1c7`).
- Register the new reader in `sot_registry.yaml`'s `exercise_equipment_tier` entry, whose
  `readers:` still claims a sole production reader.
- **Fail CLOSED** for a bodyweight user on an unreadable `equipment_needed`. The current
  `_isBodyweightTierRow` returns `true` for a non-List value — a permissive default that is right
  for `queryV4`'s soft curation and wrong for a hard floor.
- Move the attempt-5 skip **above** the `matches.isNotEmpty` branch. Today a pool name with no
  library row reaches `_buildUniversalFallback` with no tier check. Latent (all 36 pool names
  currently resolve) but the test oracle assumes it away.
- **Test oracle must read `equipment_needed`**, add `knee_dominant` + `vertical_pull` to the
  patterns, and restore `'chin up'` to the banned list.
- Consider instead/additionally fixing the four library rows, plus a contract test asserting
  `derive(equipment_needed) == equipment_tier` for the bodyweight tier — but the code guard is the
  durable fix, since community/cloud rows are not under seed control.

### Also found, same area

`equipment_access` defaults inconsistently: `'basic_gym'` at three generation call sites
(`train_provider.dart:641`, `phase2_preview_card.dart:73`, `pro_phase_advance.dart:553`,
`auth_session_bootstrapper.dart:571`) vs `'bodyweight'` at `onboarding_provider.dart:381`. If a
bodyweight user's profile loses the key, they are generated a full basic-gym plan and the floor
never runs. Pick one default; `bodyweight` is the fail-safe direction.

---

## OI-98 — reinstalling re-enables every notification

### The defect the first attempt did NOT fix

The restore leg reads the **newest** `user_daily_snapshots` row — which the device's own push
overwrites with the all-enabled default **before** the leg runs.

### Root cause — ordering, and it is the other push

The attempt's docstring claims *"ORDERING IS THE WHOLE FIX … this leg runs inside restore Step C,
before that push"*. It enumerated the wrong push.

- `splash_screen.dart:189` fires `unawaited(pushSnapshot())` — **14 lines before**
  `checkAndSync()` at `:203`.
- `SyncCoalescer.trigger` is **leading-edge** (`if (_inFlight) {…return;} _inFlight = true; …
  await task();`), so that first push runs immediately, not debounced.
- `emissionMap()` emits all 10 keys as `enabled: true` when the local blob is absent.
- `daily-snapshot` upserts `snapshot_json` **wholesale** on `(user_id, snapshot_date)`.
- The leg then selects `order('snapshot_date', desc).limit(1)` — the row just poisoned.
- Once adopted, local is full, the `normalized.length == local.length` guard makes the leg a
  permanent no-op, and **the loss is unrecoverable**.

The `.not('snapshot_json->notification_preferences','is',null)` filter cannot help: `emissionMap()`
emits the key unconditionally.

**Already happening in production.** Live query: of **126** snapshot rows, **14** carry
`notification_preferences`, and every one is 10 keys with `off_count = 0`.

### The rebuild

Primary fix — stop the push asserting a preference it does not have:

- In `compileDailySnapshot` (`sync_service.dart:899` — note the method is **`compileDailySnapshot`**,
  NOT `_buildSnapshot`, which does not exist), **omit** `notification_preferences` when
  `NotificationPrefsRepository.read().isEmpty`. The server rule is already ABSENT ⇒ SEND, so server
  behaviour is unchanged, and the leg's existing not-null filter then correctly skips rows written
  by an unrestored device.
- Alternatives considered by the reviewers: constrain the read to `snapshot_date < today`, or move
  the blob to a real column (`user_preferences` already has a restore leg with a cloud-wins merge).

Then the rest, all independently found:

- **Wire the 5th mirror.** `restoreNotificationPrefsForSyncDomain()` is declared and never called.
  `RestoreCompletenessSyncDomain.restore()` invokes six siblings and not this one. Flipping
  `SyncFlags.useDomainFor('restore_completeness')` reopens OI-98 on that path.
- **Alias-blindness.** The merge tests `local.containsKey(canonical)` only. A box holding the legacy
  singular `workout_reminder` has no canonical key, so the cloud's `workout_reminders` is adopted
  and `emissionMap`'s `direct ?? alias` then prefers it forever — flipping a deliberate OFF back
  ON. Reproduced by a Hermes probe: `BEFORE false → AFTER true`. Fires on **every sign-in** via
  `restoreLightweightAlways`. Canonicalise both sides through `_legacyAliases` before the
  containment test.
- **Owner re-check at the sink.** The repo has a named helper for exactly this —
  `ownerChangedSince(userId)`, whose doc says *"Call this AT THE WRITE SINK — one statement before
  the network write — never at function entry."* The leg does not call it. (Its siblings don't
  either, so this is a class the leg joins rather than creates — but the leg's own comment claims
  the protection.)
- **`read()`/write session-precondition mismatch.** `read()` short-circuits to `{}` when
  `HiveUserSession.currentOwnerFullId == null`; the write path does not consult `_hasSession`. In
  that window `local` is spuriously empty, the merge degrades to cloud-wins, and real preferences
  are clobbered. Use one handle for both.
- **`_hive.userBox` is `userBoxGuarded.rawBox`** — the RAW box, asserted once at getter-evaluation
  time. The attempt's comment calling it "the guarded box" is wrong. Prefer `_hive.userBoxGuarded`.
- **The behavioral test never executes the leg.** It re-implements the merge inline and asserts
  against the copy; replacing the production merge with cloud-wins leaves it green. Extract the
  merge to a pure function and have both call it — the pattern `paywallLetterheadTitle` already
  uses in this repo for exactly this reason.
- **The wiring test omits `_attemptSingleCallRestore`** — the DEFAULT path, since the kill switch
  defaults false. Deleting the leg there passes every test.
- **SoT registry.** The `notification_preferences` concept **exists** (added `cc6d29c0`) and
  currently says `restore_methods: []` plus prose asserting no restore path reads it back. The
  attempt's diagnose-doc claims the entry does not exist and cites OI-75 — which is **CLOSED**
  (2026-08-07). Update the entry; correct the doc.
- **Gate 21 is structurally blind to this class** — it pairs `syncX` ↔ `_restoreX` by method name,
  and this surface's push side is a key inside a snapshot map. Worth a detector.

---

## Traps — do not re-derive these

- **`_buildSnapshot` does not exist.** The real method is `compileDailySnapshot`
  (`sync_service.dart:899`). The first attempt cited the phantom in six places.
- **`equipment_tier` is deliberately over-tagged.** Read the SoT entry before keying anything
  safety-critical on it.
- **Never verify this suite under `TZ=UTC`.** The app is IST-throughout (§4.5); UTC breaks 19
  unrelated tests. CI already sets `TZ: Asia/Kolkata` (`.github/workflows/test.yml:27`).
- **`_broadenSelection`'s identical `dropEquipment` is DEAD** — V3 `pick()` is called from nowhere
  in `lib/` or tests. Do not re-flag it.
- **A COUNT assertion cannot prove wiring.** `calls.length >= 2` was satisfied by two branches of
  one function. Enumerate by name — and make sure the enumeration includes every entry point,
  including `_attemptSingleCallRestore`.
- **Two concurrent `flutter test` runs corrupt each other's Hive state** (OI-86). This cost an hour
  in the session that produced this spec.

## Source

Five Hermes lens reports (L1, L11, L15, L37, L39) and two B-passes, 2026-08-25. The shipped half's
record is `docs/plan-reviews/launch-blockers-1a.md`; its B-pass is
`docs/reviews/a51a2ba9de14-review.md`; the superset's is `docs/reviews/eb37932a4218-review.md`.
