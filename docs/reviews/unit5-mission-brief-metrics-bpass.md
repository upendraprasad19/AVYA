---
reviewed_at: 2026-06-14
batch: unit5-mission-brief-metrics
blast_radius: platform
reviewer: context-blind B-pass (Claude Sonnet 4.6)
findings_count: 4
verdict: ACCEPTED — 0 P0; all 4 findings (2 P1 + 2 P2) FIXED in-batch (§4.2 no-deferrals). Security CLEAN.
---

## Author triage (2026-06-14) — all 4 fixed before merge

- **F1 (migration missing the 4-tag header) — FIXED.** Added `Intent: / Destructive?: no /
  Rollback strategy: inline / Linked diagnose-doc: n/a` to `093` + a commented inline reverse
  DDL (`drop function … private.founder_metrics()`) at file end, per `supabase/migrations/CLAUDE.md`.
  (No gate currently greps these — `grep -rl` over `scripts/check_*.dart` found none, and 092
  predates the convention — but the doc says MUST, so added.) Ledger hash recomputed for the new
  file content.
- **F2 (test's `find.byType(GestureDetector) findsNothing` may be brittle/coincidental) — FIXED.**
  The assertion DID pass (Material buttons don't expose a public `GestureDetector` widget), but the
  reviewer's point stands. Replaced with a SEMANTIC check that walks every `RichText`'s
  `toPlainText()` for `icanbefitter` and asserts absence — robust (find.text can't see RichText
  spans) and immune to the CONTINUE button's gesture layer. 6/6 tests green.
- **F2-P2a (ConsumerWidget with no ref usage) — FIXED.** Converted `MissionBriefScreen` to
  `StatelessWidget` + dropped the unused `flutter_riverpod` import. (Was pre-existing, but this
  rewrite is the right moment.)
- **F2-P2b (applied_migrations.json missing trailing newline) — FIXED.** Ledger now written with a
  trailing newline.

Post-fix: `flutter analyze` clean on the screen + test (2 residual info lints are pre-existing
`(_, __)` GoRoute underscores in the test, untouched by this batch). Migration 093 was applied +
live-verified before this review (anon/authenticated `has_function_privilege` = false).

# B-pass Code Review — Unit 5: Mission Brief Rewrite + founder_metrics SQL Function

Staged files reviewed:
- `backups/applied_migrations.json`
- `lib/features/onboarding/CLAUDE.md`
- `lib/features/onboarding/screens/mission_brief_screen.dart`
- `supabase/migrations/093_founder_metrics_admin_function.sql`
- `test/onboarding/mission_brief_screen_test.dart`

---

## FINDINGS

### F1 — MISSING MIGRATION HEADER CONVENTION (P1)

**File:** `supabase/migrations/093_founder_metrics_admin_function.sql:1-4`

**Claim:** Migration 093 is compliant with the project migration header convention.

**What I found:** The migration CLAUDE.md (`supabase/migrations/CLAUDE.md`) mandates a four-line header on every migration file:

```sql
-- Intent: <description>
-- Destructive?: <yes | no>
-- Rollback strategy: <inline | migration NNN | not applicable>
-- Linked diagnose-doc: <bug-id | n/a>
```

Migration 093 contains none of these four tags. The file opens with:
```sql
-- 093_founder_metrics_admin_function.sql
-- Unit 5 (2026-06-14): an admin-gated growth-metrics snapshot for the founder
```

Verification: `grep -n "Intent:\|Destructive\?:\|Rollback strategy:\|Linked diagnose" supabase/migrations/093_founder_metrics_admin_function.sql` → zero results.

Comparison: Migration 092 (`092_community_reviews_select_own_only.sql`) also lacks the four-tag header (it has a freeform comment block). This appears to be a recurring pattern — the header convention may not be enforced by a gate yet. However the CLAUDE.md rule is unambiguous, and the pre-commit hook is documented to grep for these tags.

**Suggested fix:**
```sql
-- Intent: Create private.founder_metrics() SECURITY DEFINER function for admin growth-metrics snapshot.
-- Destructive?: no
-- Rollback strategy: inline -- DROP FUNCTION private.founder_metrics(); DROP SCHEMA IF EXISTS private;
-- Linked diagnose-doc: n/a
```

Add these four lines at the top of the file (before any other content).

**Severity: P1** — the header is a CLAUDE.md §supabase/migrations mandatory convention. The SECURITY DEFINER nature of this migration makes the absence of `Destructive?: no` and `Rollback strategy:` particularly risky — a future audit cannot quickly triage this.

---

### F2 — TEST ASSERTION CORRECTNESS RISK: GestureDetector findsNothing WITH ElevatedButton PRESENT (P1)

**File:** `test/onboarding/mission_brief_screen_test.dart:49-56`

**Claim:** "The Instagram link was the screen's only GestureDetector. Removing the CTA means no tappable RichText remains — pin its absence with `findsNothing`."

**What I found:** The test builds `MissionBriefScreen()` with the default `readOnly: false`. In this mode, the screen renders an `ElevatedButton` (the CONTINUE CTA, line 202 of `mission_brief_screen.dart`). Flutter's `ElevatedButton` internally uses `InkWell`, which itself wraps a `GestureDetector` in the widget tree. The `find.byType(GestureDetector)` finder in widget tests descends into framework-internal widget trees.

If `ElevatedButton` produces `GestureDetector` instances in the widget tree (which it does via `InkWell → GestureDetector`), then `expect(find.byType(GestureDetector), findsNothing)` will **fail** even though the Instagram CTA has been correctly removed.

The comment's claim that the Instagram link was "the screen's only GestureDetector" is false: `ElevatedButton` also creates one.

**Verification command:**
```bash
flutter test test/onboarding/mission_brief_screen_test.dart --name "does NOT render"
```
If this test fails, it confirms the false-negative.

**Possible outcomes:**
1. The test fails at runtime → the assertion is broken and must be fixed before commit.
2. The test passes → Flutter's `find.byType` does not descend into `ElevatedButton` internals in this version, but the comment reasoning is still misleading and fragile (could break on Flutter SDK update).

**Suggested fix:** Replace the brittle `GestureDetector` assertion with a targeted text-content check:
```dart
testWidgets('does NOT render an Instagram CTA (removed Unit 5 2026-06-14)', (tester) async {
  await tester.pumpWidget(buildScreen());
  expect(find.textContaining('@icanbefitter'), findsNothing);
  expect(find.textContaining('Instagram'), findsNothing);
  expect(find.textContaining('Daily wins'), findsNothing);
});
```
This pins the SEMANTIC absence (the Instagram content) rather than the structural widget type, which is far more robust.

**Severity: P1** — if the test is currently failing (likely), it's a gate violation that blocks the commit under CLAUDE.md §4.4 rule 20.

---

### F3 — ConsumerWidget WITH NO REF USAGE (P2)

**File:** `lib/features/onboarding/screens/mission_brief_screen.dart:14,20`

**Claim:** The removal of `_openInstagram()` properly cleans up the screen.

**What I found:** `MissionBriefScreen` still extends `ConsumerWidget` and its `build()` method still has `WidgetRef ref` in the signature. After removing the Instagram CTA (which was the only reason for the original Riverpod import — or more likely, the `ConsumerWidget` was inherited from an earlier version), there is zero `ref.watch`, `ref.read`, or `ref.listen` usage in the entire file.

Confirmed: the only line with `ref` is:
```
20:  Widget build(BuildContext context, WidgetRef ref) {
```

The Dart analyzer will not warn on an unused `WidgetRef ref` parameter because `ConsumerWidget.build` mandates this exact signature. However, the class no longer needs Riverpod at all. It should be a `StatelessWidget`.

**Suggested fix:**
```dart
class MissionBriefScreen extends StatelessWidget {
  const MissionBriefScreen({super.key, this.readOnly = false});
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    // ...same body...
  }
}
```
Also remove `import 'package:flutter_riverpod/flutter_riverpod.dart';`.

**Severity: P2** — no runtime impact, no analyzer warning. Unnecessary dependency on Riverpod for a purely static screen is a code quality issue and a misleading signal to future readers who might expect state consumption.

---

### F4 — MISSING NEWLINE AT END OF FILE in applied_migrations.json (P2)

**File:** `backups/applied_migrations.json` (diff hunk end)

**What I found:** The diff shows:
```
-]
+]
\ No newline at end of file
```

The file previously ended with a trailing newline (standard POSIX text file). The new entry removes it. This is a format regression. The project enforces LF line endings via `.gitattributes` (migration A5 batch); EOF newline is a related POSIX convention. Some tooling (linters, the `applied_migrations_parity_test.dart` if it does JSON parsing) will be unaffected, but `diff` output and the pre-commit source-grep passes may behave differently.

**Suggested fix:** Add a trailing newline after the closing `]` in `backups/applied_migrations.json`.

**Severity: P2** — no functional impact but violates project text-file hygiene and may produce noisy diffs.

---

## CLEAN LENSES

### Lens 1 — writer_reader_drift (Instagram CTA removal)

**Checked:**
- `url_launcher` import: removed from `mission_brief_screen.dart`. Verified no other dart file in `lib/` imports `url_launcher` via a grep that was scoped to `.dart` files — 6 other files still use `url_launcher` legitimately (`sign_in_screen.dart`, `terms_modal.dart`, `ai_coach/screen.dart`, `welcome_screen.dart`, `profile/screen.dart`, `test/auth/terms_skip_test.dart`). None are mission_brief. The package remains in `pubspec.yaml:51` (`url_launcher: ^6.3.2`) and is correctly retained.
- `_openInstagram` method: fully deleted (no remnant).
- Route/navigation: `context.go('/onboarding/identity')` on CONTINUE is intact (line 203). The `readOnly` back-button calls `context.pop()` (line 41). Both are correct.
- No dangling route references to Instagram anywhere in the router or other screens.
- The `flutter_riverpod` import is still present and compiles (even if the class should be simplified — this is F3 above, not a drift issue).
- **CLEAN** (no writer/reader drift from the removal).

### Lens 2 — function_exception_swallow

**Checked:**
- `mission_brief_screen.dart` has no async operations whatsoever after the `_openInstagram` removal. No try/catch, no swallowed errors.
- The `Image.asset` error path (line 83-87) renders a fallback `Icon(Icons.person)` — this is correct and defensive.
- **CLEAN**.

### Lens 3 — blast_radius_mismatch (SQL SECURITY scrutiny)

**SQL security checks passed:**

1. **Schema isolation:** Function lives in `private` schema. PostgREST only exposes `public` schema by default. Anon/authenticated clients cannot reach `private.founder_metrics()` via the REST API at all, regardless of EXECUTE grants. This is a defense-in-depth layer on top of the REVOKE.

2. **REVOKE target:** `revoke all on function private.founder_metrics() from public;` — correct. Revokes from `PUBLIC` (the inherited grant holder), not from `anon`/`authenticated` alone (which would be a no-op while PUBLIC holds the grant). This explicitly references the bug class from debugging skill §2.32 and migrations 090/091.

3. **GRANT scope:** `grant execute on function private.founder_metrics() to service_role;` — narrow, correct.

4. **No GRANT to anon/authenticated/PUBLIC anywhere:** confirmed by reading the full file.

5. **search_path injection:** `set search_path = public, private`. ALL table references in the CTE and queries are schema-qualified:
   - `from public.users` (line 47)
   - `from public.subscriptions` (line 67)
   No unqualified table names. The `private` schema is in the path but the function body does not reference any objects there — it's present for forward compatibility and creates no injection surface with the current code.

6. **Column existence (verified against `backups/live_schema_columns.json`):**
   - `users` table has: `id`, `subscription_status`, `subscription_expires_at`, `last_active_at`, `created_at`, `is_deleted` — ALL present. Confirmed from live_schema_columns.json line 49.
   - `subscriptions` table has: `id`, `user_id`, `status` — ALL present for the `count(distinct user_id) ... where status='active'` query. Confirmed from live_schema_columns.json line 38.

7. **IST date math (signups_today_ist):**
   ```sql
   created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
   ```
   Walk-through:
   - `now() at time zone 'Asia/Kolkata'` → converts UTC now to a `timestamp without tz` representing local IST time
   - `date_trunc('day', <IST_local_timestamp>)` → truncates to IST midnight (00:00:00 IST, still no tz tag)
   - `<IST_midnight_no_tz> at time zone 'Asia/Kolkata'` → interprets that timestamp as being in IST and converts to UTC `timestamptz`
   - Net result: the right-hand side is the UTC instant corresponding to IST midnight today
   - `created_at >=` that value = "users who signed up since IST midnight today"
   - **CORRECT**. This is the standard PostgreSQL double-AT idiom for IST-anchored date math; consistent with `ist_date.ts` app-wide convention.

8. **Double-count / gap analysis:**
   - `pro_active` and `free_users` are mutually exclusive (pro_active requires `subscription_status='pro'`; free_users requires `coalesce(subscription_status,'free')='free'`, which cannot match 'pro').
   - `pro_active` and `pro_expired` are mutually exclusive by the `expires_at > now()` vs `<= now()` condition.
   - Gap: a user with `subscription_status` not in `{pro, free, NULL}` (e.g., a future 'cancelled' status value) would be in `total_users` but not in any of `pro_active + pro_expired + free_users`. The comment acknowledges only `{free, pro}` exist currently. This is a known limitation, not a bug given current data, and is noted as informational.
   - **EFFECTIVELY CLEAN** given documented schema state.

### Lens 4 — secrets_in_tree

**Checked:** Full text of both new files. No credential-shaped literals, no API keys, no JWT tokens, no connection strings. **CLEAN**.

### Lens 5 — unawaited_no_error_sink

**Checked:** `mission_brief_screen.dart` has no async code whatsoever after the removal. **CLEAN**.

---

## Copy-fidelity check (Mission Brief)

- Founder story (injury/comeback): present and complete (lines 141-146).
- "discipline isn't motivation" phrase: present with gold-italic accent (line 153).
- "AVYA holds the line": present with gold-italic accent (line 166).
- "Show up. Earn your promotions. Become the man who lasts": present (line 169).
- "No one is coming to save you, Recruit. The one who can → is you.": present as closing accent (line 172).
- "Jai Hind." closer: present (line 179).
- Signed "— Upendra" (line 190).
- CONTINUE button → `/onboarding/identity`: intact (line 203). GoRouter route confirmed in app_router.dart.
- `readOnly` back-button (`context.pop()`): intact (line 41). The `readOnly: true` variant is registered in app_router.dart at line 136.
- No broken RichText spans: all `accent()` calls produce `TextSpan` with consistent style. The local `accent()` helper (lines 22-30) correctly inherits `AppTypography.bodyL` + gold color + italic. The base style on the parent `TextSpan` uses `AppColors.textPrimary` with `height: 1.6`, which all `const TextSpan` children inherit. No orphaned style.
- **Copy is coherent. No typos detected in the diff.**

---

## Summary Table

| ID | File | Severity | One-line description |
|----|------|----------|----------------------|
| F1 | `093_founder_metrics_admin_function.sql:1` | P1 | Missing 4-tag migration header convention (Intent/Destructive/Rollback/Diagnose) |
| F2 | `test/onboarding/mission_brief_screen_test.dart:55` | P1 | `GestureDetector findsNothing` may fail with ElevatedButton present; replace with content-based assertion |
| F3 | `lib/features/onboarding/screens/mission_brief_screen.dart:14` | P2 | ConsumerWidget with zero ref usage — should be StatelessWidget |
| F4 | `backups/applied_migrations.json` (EOF) | P2 | Missing trailing newline at end of file |

**P0: 0 | P1: 2 | P2: 2**

**Most important finding: F2.** The `expect(find.byType(GestureDetector), findsNothing)` test assertion is likely broken because `ElevatedButton` creates `GestureDetector` instances internally. If so, the test currently fails and this is a P0-by-gate (CLAUDE.md §4.4 rule 20: failing tests on main are P0 blockers). Run `flutter test test/onboarding/mission_brief_screen_test.dart --name "does NOT"` to confirm before committing.
