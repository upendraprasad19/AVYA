---
reviewed_at: 2026-08-26T14:08:55+05:30
staged_against: 885ebd47f4c0
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 6
verdict: accepted
---

## Finding 1 — P0 — writer_reader_drift / guard_without_its_mirror

**Claim:** `_syncUserPreferences` pushes `NotificationPrefsRepository.read()` — the RAW local Hive value, which can legitimately be a **sparse** subset of the 10-key vocabulary — straight into `user_preferences.notification_preferences`, a jsonb column the client upserts as a plain JSON value with no server-side merge. Postgres/PostgREST replace a jsonb column's *value* wholesale on `UPDATE`; there is no `||` merge in the upsert. So any notification key **absent** from the local read is not "not mentioned" to the server — it is **deleted** from the stored document, silently reverting that key to the ABSENT ⇒ SEND default for every other device/session that had previously set it. This recreates OI-98's own root cause (a device's incomplete local view overwrites another device's real preference) one layer down: the *row* is no longer wholesale-replaced by multiple writers (the fix this batch intends), but the *JSON value inside the one authoritative column* still is, by the client itself.

The guard at the call site only checks **emptiness**, not **completeness**:
```
lib/core/services/sync/sync_profile.dart:497   final notificationPrefs = NotificationPrefsRepository.read();
lib/core/services/sync/sync_profile.dart:516-518
      if (notificationPrefs.isNotEmpty) {
        payload['notification_preferences'] = notificationPrefs;
      }
lib/core/services/sync/sync_profile.dart:531-533
      await _supabase.client
          .from('user_preferences')
          .upsert(payload, onConflict: 'user_id');
```
A single-key (or any-partial-key) map passes `isNotEmpty` and is pushed verbatim.

The map really can be partial in normal use, not just a contrived edge case:
```
lib/features/profile/screens/notification_settings_screen.dart:111-118
  void _toggle(String key, bool value) {
    setState(() {
      final pref = Map<String, dynamic>.from((_prefs[key] as Map?) ?? {});
      pref['enabled'] = value;
      _prefs[key] = pref;               // mutates ONLY the toggled key
    });
    _persist();
  }
lib/features/profile/screens/profile/screen.dart:214-220
    return {
      'morning_checkin': {'enabled': true, 'time': '07:00'},
      'workout_reminders': {'enabled': true, 'time': '18:30'},
      'streak_alerts': {'enabled': true},
      'weekly_recap': {'enabled': true, 'day': 'sunday'},
      'subscription_reminders': {'enabled': true},
    };                                    // 5 of NotificationPrefsRepository.allKeys' 10 keys
```
The empty-box default seeds only **5 of 10** `allKeys`, and `_toggle` only ever adds/mutates the one key the user touches — `_prefs`/`_notifPrefs` never gets filled to the full vocabulary.

The race window that turns this from "theoretical" to "reachable" is documented by the codebase itself:
```
lib/features/auth/screens/restoring_screen.dart:81   static const Duration _ctaAfter = Duration(seconds: 30);
lib/features/auth/screens/restoring_screen.dart:593  // (founder's restore is ~35.9s) can exceed the 30s CONTINUE timer, so
```
Restore can take **longer than its own escape hatch** by the founder's own measured number — i.e. a user reaching the main app (and Notification Settings) before `_restoreUserPreferences`/`adoptFromCloud` has finished is not a corner case, it is the documented common case for a slow restore.

The team already knows the correct pattern for this exact concept and used it for the OTHER (fallback) writer, but not for this one:
```
lib/core/services/sync_service.dart:894-896
    final notificationPrefs = NotificationPrefsRepository.read().isEmpty
        ? null
        : NotificationPrefsRepository.emissionMap();   // ALWAYS pads to all 10 keys
```
And the diagnose-doc itself reasons through the *mirror image* of this exact risk while evaluating a different design and rejects it for the right reason, without applying the same completeness concern to the design it kept:
```
docs/diagnoses/2026-08-26-notification-prefs-push-only-e4a1b7.md:149-155
  (2) "Keep emitting the full padded ten-key map whenever the local blob is non-empty."
  REFUTED, and it would have caused fresh data loss. profile/screen.dart:192-209 hands back a
  FIVE-key default when the box is empty, so the first toggle any user makes persists a partial
  blob; padding it to ten would then push five FABRICATED `true` values, that row becomes the
  newest carrying the key, and another device's real OFF is adopted away.
```
That paragraph is a precise description of what a **padded, incomplete** map does to a sibling device's real setting. A **sparse, incomplete** map — what `_syncUserPreferences` actually sends — does the identical thing via omission instead of fabrication: it silently reverts a sibling device's real OFF back to the default.

**Verification:**
```bash
grep -n "notificationPrefs.isNotEmpty" lib/core/services/sync/sync_profile.dart
sed -n '220,228p' lib/features/profile/services/notification_prefs_repository.dart   # write() replaces the Hive key wholesale, no merge
sed -n '111,118p' lib/features/profile/screens/notification_settings_screen.dart      # _toggle touches exactly one key
sed -n '141,166p' lib/features/profile/services/notification_prefs_repository.dart    # normalize() never adds missing top-level keys
```
Concrete sequence that loses data (no code change needed to observe — this is the shipped shape):
1. Device A: user turns `plateau_alert` OFF. `_syncUserPreferences` pushes `{..., plateau_alert: {enabled:false}, ...}` (whatever Device A has accumulated). Column now has that key.
2. Device B (reinstall, or second device): before `_restoreUserPreferences`/`adoptFromCloud` completes (restoring_screen.dart:81/593 — a real, measured ≥30s window), user opens Notification Settings and toggles `morning_checkin`. `_prefs` on Device B is the 5-key default (`screen.dart:214-220`, no `plateau_alert` in it) with `morning_checkin` flipped.
3. `write()` → `pushUserPreferencesForSyncDomain()` → `_syncUserPreferences` pushes Device B's 5-key map. The upsert's `notification_preferences` value REPLACES the column's prior value. `plateau_alert: false` is gone; the server now reads it as absent ⇒ SEND. Device A's deliberate OFF is silently reverted, with no error, no log, no user-visible signal.

**Suggested fix:** Do not fix this by switching `read()` to `emissionMap()` — that is the diagnose-doc's own refuted hypothesis 2 and just trades this bug for its mirror (fabricated values overwriting a real OFF). Instead make the write itself non-destructive to keys it doesn't name: either (a) have the client fetch-then-merge before every push using the SAME local-wins logic `mergeCloudNotificationPrefs` already provides for restore, applied at push time; or (b), simpler and race-free, do the merge in Postgres: `notification_preferences = COALESCE(user_preferences.notification_preferences, '{}'::jsonb) || EXCLUDED.notification_preferences` in the upsert's conflict clause, so a partial client push can only ever overlay the keys it names.

**status: pending**

---

## Finding 2 — P1 — missing required plan-review artifact (blast_radius_mismatch: a platform-tier change has not met its platform-tier process gate)

**Claim:** `docs/audit/oi98-notification-prefs.closure.yaml:35` declares `plan_review_record: docs/plan-reviews/oi98-notification-prefs.md`, and multiple closure entries narrate a completed multi-round review (`CLI-PUSH-INERT` at :100 says "Found by review round 3"; `DOC-BOARD` at :216-224 references review conclusions). No file at that path exists anywhere in the repository — not staged, not committed on any branch, ever. Per root CLAUDE.md §4.12.3, this record is REQUIRED for any `≥account`-blast-radius merge (this batch is self-declared `platform`, both in this closure yaml and in the review dispatch) and is enforced in CI by `scripts/check_plan_review_record_exists.dart`, which keys the expected filename on the **branch name** — `oi98-notification-prefs`, exactly the missing path. Absent this file, the branch cannot reach `main` through the normal gate, and the closure yaml's own narrative of a 3-round review has no artifact backing it.

**Verification:**
```bash
ls "docs/plan-reviews/oi98-notification-prefs.md"                                    # No such file or directory
git log --all --oneline -- "docs/plan-reviews/oi98-notification-prefs.md"            # (empty)
git log --all --diff-filter=A --name-only | grep -i "plan-reviews.*oi98"             # (empty)
```

**Suggested fix:** Produce `docs/plan-reviews/oi98-notification-prefs.md` with `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`, and `bpass: accepted` (this review can serve as the B-pass leg) before merging — the closure yaml's own notes suggest the rounds genuinely happened, they just were never written down. If a `ship_dark_build` tier is intended, it does not appear to qualify per §4.12.4 (nothing here is behind a kill-switch/default-OFF flag — the migration is already live and the client writes the column unconditionally), so the full record is the right target, not the 1-round exemption.

**status: pending**

---

## Finding 3 — P2 — guard_without_its_mirror

**Claim:** `_restoreUserPreferences`'s new owner re-check protects only the NEW write it was added for, leaving an unguarded sibling write in the very same method reading the very same fetched row under the very same possibly-stale `userId`.
```
lib/core/services/sync/sync_profile.dart:704-706
      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id');
lib/core/services/sync/sync_profile.dart:715   final cloudNotificationPrefs = cloud.remove('notification_preferences');
lib/core/services/sync/sync_profile.dart:722-727
      final merged = <String, dynamic>{
        ...existingMap,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };
      await _hive.userBox.put('preferences', merged);      // <-- NO owner re-check
lib/core/services/sync/sync_profile.dart:734-741
      // OWNER RE-CHECK AT THE SINK ... The GuardedBox assert is NOT
      // sufficient here: it compares the BOX's owner to the live session, while
      // `userId` was captured at this method's entry. After an A -> B account
      // swap where Hive has already reopened for B, that assert passes happily
      // and A's cloud preferences land in B's box.
      if (cloudNotificationPrefs != null && !ownerChangedSince(userId)) {
        await NotificationPrefsRepository.adoptFromCloud(cloudNotificationPrefs);   // <-- guarded
      }
```
The comment's own reasoning ("userId was captured at this method's entry... after an A→B swap the GuardedBox assert passes happily") applies with equal force to `userBox.put('preferences', merged)` at :727, which writes `motivational_style` / `preferred_language` / whatever else the cloud row carried, fetched for the SAME stale `userId`, three lines earlier. That write is pre-existing (not introduced by this diff) and the same shape already exists in `_restoreUserProfile` / `_restoreUserProgress`, so this is not a regression this diff caused — but this diff is exactly the one that had the context loaded to close it, in the one method it was already editing, and chose to protect only the new call.

**Verification:**
```bash
sed -n '693,742p' lib/core/services/sync/sync_profile.dart
```

**Suggested fix:** Move (or duplicate) the `!ownerChangedSince(userId)` check to cover `await _hive.userBox.put('preferences', merged);` as well — re-checked at the last statement before that sink, matching the convention `ownerChangedSince`'s own doc already prescribes and that this diff followed for its own new call.

**status: pending**

---

## Finding 4 — P2 — blast_radius_mismatch (fault-isolation regression on 3 of 4 converted readers)

**Claim:** `fetchNotificationPrefsDetailed` collapses two structurally different failures — "the primary column read failed" and "the snapshot fallback failed for the users the column didn't answer for" — into a single boolean, `degraded`, that is `true` if *either* phase throws for *any* subset of the batch:
```
supabase/functions/_shared/notification_prefs.ts:162-196   primary try/catch sets degraded=true on ANY throw
supabase/functions/_shared/notification_prefs.ts:205-249   fallback try/catch (scoped to `unresolved` only) ALSO sets degraded=true on ANY throw, for the whole call
```
Three of the four converted callers branch on this single flag *inside their per-user loop* and skip/error **every** candidate in the run when it's true:
```
supabase/functions/streak-guardian/index.ts:181-191 (batched call + degraded log), :206-209 (the loop's unconditional `if (prefsDegraded) { skipped++; continue; }`)
supabase/functions/expiry-reminder/index.ts:99-108, :128-131   if (prefsDegraded) { skipped++; continue; }
supabase/functions/workout-window-closing/index.ts:225-229, :245-247   if (prefsDegraded) { errors++; continue; }
```
Before this diff, each of these three ran one query PER USER, so one user's row failing to parse, or a transient blip on one request, skipped only that user. After this diff, if the fallback query throws for even a handful of "unresolved" stragglers (users the primary column query didn't answer for), `degraded` goes `true` for the WHOLE batched result and the loop skips/errors every candidate that run — including users who WERE cleanly resolved via the primary column query moments earlier in the same call. This is a genuine loss of fault isolation, not merely a relabeling: for `expiry-reminder`, whose own comment says "a lapsing PAYING user must still get their reminder," an unrelated subset's fallback hiccup can now suppress that reminder for users who were never at risk of the failure at all.

**Verification:**
```bash
sed -n '136,250p' supabase/functions/_shared/notification_prefs.ts   # one `degraded` var spans both phases, no per-user granularity
sed -n '196,212p' supabase/functions/streak-guardian/index.ts        # unconditional skip on the batch-wide flag
```

**Suggested fix:** Track failures per-user (e.g. return a `Set<string>` of user ids the lookup could not answer for at all, instead of / alongside a single boolean) so a caller can skip exactly the unresolved subset and still act correctly on everyone else.

**status: pending**

---

## Finding 5 — P3 — stale file:line citation, self-inconsistent with this same commit's own citation fixes

**Claim:** `docs/diagnoses/2026-08-26-notification-prefs-push-only-e4a1b7.md:32` cites:
```
- { file: lib/features/profile/services/notification_prefs_repository.dart, method: "write — THE Hive writer; ...", line: 212 }
```
Line 212 of that file is the closing `}` of the *preceding* method (`emissionMap`); `write`'s docblock starts at line 214 and its signature (`static Future<bool> write(Map<String, dynamic> prefs) async {`) is at line 220. Flagged specifically (rather than waved off as noise) because this same diagnose-doc/SoT-registry pair explicitly boasts fixing two OTHER stale citations in this exact commit — `docs/sot_registry.yaml`'s DOC-SOT closure note: *"Two stale `at :842` citations corrected to :899 (wrong by 57 lines, in BOTH places)"* — so citation precision was actively being audited in this batch, and this instance slipped through.

**Verification:**
```bash
sed -n '210,222p' lib/features/profile/services/notification_prefs_repository.dart
```

**Suggested fix:** Update to `line: 220` (method signature) or `line: 214` (docblock start, matching the convention used elsewhere in this same registry edit).

**status: pending**

---

## Finding 6 — P1 — guard_without_its_mirror (the test's blind spot matches the code's blind spot, and explains Finding 1)

**Claim:** `test/contracts/notification_prefs_round_trip_behavioral_test.dart` is thorough on the restore/merge direction (`mergeCloudNotificationPrefs`, `canonicalizeNotificationPrefs`, `adoptFromCloud`) and explicitly tests that the SNAPSHOT FALLBACK write path stays a complete, padded map:
```
test/contracts/notification_prefs_round_trip_behavioral_test.dart:260-265
      final emitted =
          populated['notification_preferences'] as Map<String, dynamic>;
      expect(emitted['streak_alerts']?['enabled'], isFalse);
      expect(emitted.length, NotificationPrefsRepository.allKeys.length,
          reason: 'when it DOES emit, it emits the full padded map — a partial '
              'map in a newer row would shadow a complete older one');
```
That assertion is exactly the property Finding 1 shows is violated — just checked against `compileDailySnapshot()` (the OLD/fallback path) and never checked against `_syncUserPreferences` (the NEW/primary path). Nothing in this file constructs a fake/mock Supabase client, calls `_syncUserPreferences`, calls `pushUserPreferencesForSyncDomain`, or asserts anything about the shape of the JSON actually sent to `user_preferences.notification_preferences`:
```bash
grep -n "_syncUserPreferences\|pushUserPreferencesForSyncDomain\|SupabaseClient\|MockClient\|upsert" test/contracts/notification_prefs_round_trip_behavioral_test.dart
# (no matches)
```
This is the textbook "test written from the same blind spot as the code": the author's mental model — "the emitted map must always be complete" — was correctly turned into an assertion for the path they were staring at (the fallback, because that IS the historical OI-98 bug), and never re-applied to the new path that quietly sources from something narrower. A realistic regression this suite would MISS entirely: leave `_syncUserPreferences` exactly as shipped (per Finding 1) — every test in this file stays green, because none of them exercise that function or its payload.

**Verification:**
```bash
sed -n '239,266p' test/contracts/notification_prefs_round_trip_behavioral_test.dart
grep -c "_syncUserPreferences" test/contracts/notification_prefs_round_trip_behavioral_test.dart   # 0
```

**Suggested fix:** Extract `_syncUserPreferences`'s payload-construction into a pure, directly-testable function (mirroring how `mergeCloudNotificationPrefs` was already extracted to a top-level function for exactly this reason, per its own doc comment), and add a test asserting that a sparse `read()` never causes the payload to represent "these keys don't exist" for keys the device simply hasn't touched — i.e. a test that would catch Finding 1.

**status: pending**

---

## Checked and clean

- **Dart null-aware map-element syntax** (`'notification_preferences': ?notificationPrefs` at `sync_service.dart:915`) — not a typo or unsupported feature. Compiled and ran a standalone repro against the project's actual SDK (`pubspec.yaml:22` pins `sdk: ^3.11.1`, matches `dart --version` in this environment): the key is genuinely *omitted* (`containsKey` false) when the value is null, and present with the unwrapped value otherwise. Does exactly what the surrounding comment claims.
- **`canonicalizeNotificationPrefs` two-pass ordering and canonical-outranks-legacy precedence** (`notification_prefs_repository.dart:318-333`) — traced by hand against the specific case the brief asked about, "both a legacy and canonical key present in CLOUD": Pass 1 copies the canonical key, Pass 2 skips the legacy key because the canonical slot is already filled — canonical wins, consistent with `emissionMap`'s own `direct ?? alias` precedence. Also confirmed this dual-key state is realistic (any user who owned an old APK and later toggles `workout_reminders` via the current UI ends up with both `workout_reminder` and `workout_reminders` in the same box), not a contrived input.
- **`mergeCloudNotificationPrefs` local-wins additive merge** (`:361-371`) — `out` starts as a full copy of `local` and only ever gains keys `local` (in canonical space) doesn't already answer for; no existing local value is ever overwritten or removed. The `adoptFromCloud` no-op guard (`merged.length == local.length ⇒ nothing adopted`) is a sound proxy given that invariant.
- **`fetchNotificationPrefsDetailed` primary/fallback partitioning** (`notification_prefs.ts:162-206`) — `resolved` / `unresolved` sets correctly prevent double-counting or wrong precedence: a user resolved via the primary column is never touched by the fallback query (which only queries `unresolved`), so there is no scenario where a stale snapshot value overrides a fresh column value.
- **Migration 122 — verified LIVE, not just claimed.** Queried `information_schema.columns` on project `dedsavbjuwgarrhphgnl` directly: `notification_preferences | jsonb | is_nullable=YES | column_default=null` — matches the migration file and the applied_migrations.json entry exactly. Also queried row state: `0 non-null / 6 total` rows, consistent with "client is the only writer and hasn't shipped yet."
- **`applied_migrations.json` hash for migration 122** — recomputed `sha256sum supabase/migrations/122_notification_preferences_column.sql` locally; matches the ledger's `sha256:ef4a5800c9f9...` byte-for-byte (64 hex chars, full match). Not a repeat of the OI-135/OI-137 hash-drift class this same ledger documents elsewhere.
- **`live_schema_columns.json` regeneration** — diffed staged vs `HEAD` programmatically: `user_preferences` gained exactly one column (`notification_preferences`); table count 50→51, column count 570→580, consistent with the claimed "purely additive, 9 columns from an unrelated pre-existing table" arithmetic.
- **Gate 11 (`check_sync_fanout.dart`) compatibility** — the new `sync_methods: [pushSnapshotNow, _syncUserPreferences]` / `restore_methods: [_restoreUserPreferences]` registry entries name methods declared in `sync/sync_profile.dart`, not literally in `sync_service.dart`. Read the gate script: it concatenates every `.dart` file under `lib/core/services/sync/` before scanning for declarations, specifically to handle the SyncService part-file split — so this will not spuriously fail.
- **`unawaited_no_error_sink` on the new push call** — `NotificationPrefsRepository.write`'s new `unawaited(SyncService.instance.pushUserPreferencesForSyncDomain().catchError(...))` (`notification_prefs_repository.dart:252-260`) is NOT decorative. `pushUserPreferencesForSyncDomain` calls `await _ensureSessionOpen()` (→ `HiveUserSession.ensureOpenedForCurrentSession()`, `sync_service.dart:453-454`) *before* entering `_syncUserPreferences`'s own try block, so a throw there would otherwise escape an unawaited future unhandled. Confirmed `pushSnapshot()` (the sibling unawaited call with no `.catchError`) does NOT call `_ensureSessionOpen` at its own top level — it goes through the coalescer to `pushSnapshotNow`, matching the code comment's claim that that path already wraps everything internally. The asymmetry in the diff (new call gets `.catchError`, old one doesn't) is therefore correct, not an oversight.
- **`function_exception_swallow`** — no `functions.invoke` call sites were touched by this diff; the new/changed calls are all direct `.from(...).upsert(...)`/`.select(...)` PostgREST builders or Edge Function internals, not `supabase.functions.invoke`, so this lens doesn't apply to the changed surface.
- **`secrets_in_tree`** — nothing in the diff introduces a credential, token, or key. Entirely business logic, SQL DDL with no embedded secrets, and documentation.
- **Ten-Edge-Function-redeploy count** (closure yaml `HOLD-EF-DEPLOY`) — cross-checked by grep: exactly 10 files under `supabase/functions/` import `fetchNotificationPrefs`/`fetchNotificationPrefsDetailed` (6 untouched-but-benefiting: morning-alert, plateau-alert, pr-detection, proactive-coach-promotion, protein-gap-alert, re-engagement; 4 converted: expiry-reminder, streak-guardian, weekly-recap-ready, workout-window-closing). Matches the claim exactly.
- **Closure yaml structural compliance (§4.2)** — 17 findings, `closed_count: 17` matches an actual line-by-line tally; every `terminal_state:` value is one of the four permitted (`closed_in_commit` ×14, `verified_clean` ×1, `blocked_on_user` ×2); no `deferred:` key anywhere (the only occurrence of that string is inside an explanatory comment). The two `blocked_on_user` entries (Edge Function deploy authorization; fallback retirement gated on APK +39 adoption) are legitimately scoped to founder-only actions per §4.3/§4.6, not disguised deferrals.
- **`isNotificationEnabled`** confirmed pre-existing/unchanged by this diff (`git show HEAD:...` matches the current file byte-for-byte for that function) — the four converted readers are adopting an already-reviewed function, not new logic.
- **Diagnose-doc evidentiary citations spot-checked** — `daily-snapshot/index.ts:341` and `rolling-context/index.ts:442` (background/historical citations, not part of this diff's changed files) both land exactly on the `.upsert(` calls they claim to describe.

## Could not determine

- **Whether any of the ten Edge Functions have actually been redeployed.** The closure yaml (`HOLD-EF-DEPLOY`) says this is explicitly pending founder authorization and none has happened yet; I did not query the live Edge Function API versions to double check, since the task scope is the staged diff and this is already tracked as a not-yet-done, correctly-gated action rather than something the diff claims is done.
- **Whether `NotificationSettingsScreen`'s `_prefs` (fed back to `ProfileScreen._notifPrefs` via the `onSave` callback) is mutated anywhere else** besides the `_toggle`/`_setTime`/`_setDay` handlers already examined. I traced the callback wiring (`_persist()` → `widget.onSave(_prefs)`) and believe `screen.dart:352`'s `NotificationPrefsRepository.write(_notifPrefs)` call ultimately writes the same sparse map `NotificationSettingsScreen` builds, but did not exhaustively grep `screen.dart` for a second, independent mutation site for `_notifPrefs` outside that callback.
- **The real-world frequency of the Finding 1 race** (restore still in-flight when a user reaches Notification Settings and toggles something) — the 30s/35.9s timing numbers establish the window is real and not contrived, but I have no telemetry on how often two-device or reinstall-plus-immediate-toggle sequences actually occur in the live user base.

---

## Triage — all six accepted and fixed in-batch (2026-08-26)

Verdict flipped `pending` -> `accepted`. Every finding was verified against the
file before acting, per the standing rule that a subagent's numeric and
structural claims are unverified until read directly. Zero false alarms.

| # | Sev | Disposition |
|---|---|---|
| 1 | P0 | **FIXED — migration 123.** Confirmed exactly: `notification_settings_screen.dart:50-56` seeds `_prefs` from `read()` (`{}` on a fresh device) and each toggle adds ONE key, so a one-key stored map is ordinary, and a jsonb column IS replaced wholesale by an upsert. Device A storing `{streak_alerts:false}` and device B storing `{weekly_recap:false}` would each delete the other's key. Closed by a per-key additive `merge_notification_preferences` RPC (jsonb `\|\|`, SECURITY INVOKER, keyed on `auth.uid()` so the caller's own RLS applies). |
| 2 | P1 | **FIXED** — `docs/plan-reviews/oi98-notification-prefs.md` written. It did not exist because it had not been written yet, not because it was thought unnecessary; the finding is correct that CI would have blocked the merge. |
| 3 | P2 | **FIXED** — the owner re-check now sits ABOVE both writes as a single `if (ownerChangedSince(userId)) return;`, instead of guarding only the new call and leaving its older sibling two lines up exposed to the identical race. Guarding one site and not its mirror is the shape this batch exists to close, so finding it inside the fix is fair. |
| 4 | P2 | **ACCEPTED, behaviour kept, claim corrected.** `degraded` is genuinely batch-wide — `fetchAllByIds` raises on any page, and one lost page makes the whole lookup untrustworthy — so a transient error now skips every candidate for that run rather than one user. Same direction, self-healing on the next run, wider blast radius for a transient fault. The fix was to the COMMENTS: they claimed semantics "preserved verbatim", which was an over-claim, and now state the difference explicitly. |
| 5 | P3 | **FIXED** — and the finding under-counted it. `write` was cited at 212 (actually 220), but my own additions had also shifted `read` (162 -> 170) and `emissionMap` (194 -> 202). All three re-derived by grep rather than patched one at a time. |
| 6 | P1 | **FIXED — and this is the finding that mattered most.** It names *why* Finding 1 survived: the suite exercised the restore path and the snapshot emission, and nothing asserted the shape of what the client SENDS. `buildUserPreferencesPayload` is now a pure extracted function with four tests, **mutation-proven**: reinstating the two removed columns reddens 4 tests. |

**What this review changed about the batch, stated plainly.** Finding 1 is the
third independent review to catch the same class in the same batch — the first
two blocked the in-blob designs, and this one caught the identical defect
surviving into the new home. Per-key merge had been applied on the RESTORE side
and wholesale replace left on the WRITE side. That is
`feedback_mistake_guard_without_its_mirror`, and it is now recorded as such
rather than filed as a one-off.

