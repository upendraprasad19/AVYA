---
branch: signin-redesign-password-reset-fix
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/69297d4aefb4-review.md
hermes_report: not_required
---

# Plan review — `signin-redesign-password-reset-fix`

Two unrelated auth changes, approved together as one plan from two founder
observations: (A) merge the Google-OAuth and email-entry screens into one
sign-in entry view (3 screens → 2), and (B) fix a bug where a successful
password reset left the user stuck on `/reset` forever. Diagnose-doc:
`docs/diagnoses/2026-08-01-password-reset-stuck-screen-c8f1d3.md`.

## Tier

```
git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
→ platform
```

Every `lib/` file here is individually `account`
(`docs/blast_radius.yaml:176`); `platform` comes entirely from
`pubspec.yaml`/`pubspec.lock` (`:247-248`) — `http` added as a direct
`dev_dependency` (previously only transitive) so the new behavioral test in
`password_reset_redirect_flow_test.dart` can use `package:http/testing.dart`'s
`MockClient` without tripping the `depend_on_referenced_packages` lint.
Confirmed dev-only via the `pubspec.lock` diff (`transitive` → `direct dev`,
same resolved version) — no production dependency-graph change.

## Ground truth verified

- `sign_in_screen.dart`'s `_SignInView`/`_EmailStep` state-machine
  transitions: read directly, no unreachable states after the 3→2 enum prune.
- `GoRouter` construction has no `refreshListenable`
  (`app_router.dart:83-87`, `app.dart:105`) — grepped, zero matches — and
  `/reset` is deliberately exempt from `_authRedirect` (`:644`). Both
  independently reconfirmed by the round-1 reviewer, the round-2 reviewer,
  and the final B-pass — four separate reads of the same citation, all
  agreeing.
- `releaseDeviceSessionIdentity()` (`auth_provider.dart:48-63`) has no
  Supabase session dependency and try/catches its own two steps internally —
  confirmed safe to call unconditionally, which is what round 2's fix relies
  on.
- The pinned `gotrue` SDK version's `signOut()` behavior for the default
  `SignOutScope.local`: `_removeSession()` runs synchronously before the
  network revoke call that can throw — read directly from
  `gotrue-2.20.0/lib/src/gotrue_client.dart` (pinned per `pubspec.lock`), not
  assumed. Rules out a stale-valid-local-session risk after a swallowed
  `signOut()` failure.
- Every new/changed test's ability to discriminate was verified by actually
  reverting the fix and re-running, not just reading the assertion: the new
  cross-button race test (`sign_in_screen_email_gate_test.dart`) and the
  original stuck-screen behavioral test (`password_reset_redirect_flow_test.dart`)
  were both confirmed to fail pre-fix and pass post-fix.

## Round 1 — 3 findings (0 P0, 2 P2, 1 P3)

1. **P2 — cross-button reentrancy race, not actually fixed by the prior
   B-pass.** `docs/reviews/03a8ce7c088d-review.md` Finding 2 had gated
   Google/Phone's `onPressed` with `(isLoading || _checkingEmail) ? null :
   callback` — but that ternary is evaluated once per `build()`; a same-frame
   tap on Google right after CONTINUE can still fire the stale non-null
   callback captured in the PRIOR build, before the `setState`-triggered
   rebuild disables it. Reproduced with a throwaway test before proposing the
   fix. Fixed by moving the `_checkingEmail` check inside the callback body
   (a live field read at call time, not a build-time snapshot) —
   `sign_in_screen.dart`. New regression test added and verified to
   discriminate (fails pre-fix, passes post-fix).
2. **P2 — `signOut()` exception after successful `updateUser()` surfaces a
   false error and skips navigation.** `reset_password_screen.dart`'s
   original single try block meant a transient `signOut()` network failure
   hit the outer `catch` and set `_error = 'Could not update password...'`
   even though the password update had already succeeded — and never
   reached the new `context.go('/sign-in')` call. Fixed by wrapping
   `signOut()` in its own inner try/catch (logs via `ErrorTelemetry`,
   swallows).
3. **P3 — `if (!mounted) return;` skipped session cleanup, not just
   navigation.** The early return right after `updateUser()` would also skip
   `signOut()`/`releaseDeviceSessionIdentity()`/flag-reset if the widget
   unmounted mid-await. Fixed by removing the early return; the SnackBar and
   final `context.go` are individually `if (mounted)`-gated, but the
   cleanup runs unconditionally.

## Round 2 — 1 finding (0 P0, 1 P2, 0 P3), attacking round 1's fixes

Told explicitly to attack round 1's corrections, not re-review from scratch.

1. **P2 — round 1's `signOut()` fix nested `releaseDeviceSessionIdentity()`
   inside the same try, so a `signOut()` throw skipped the identity release
   too** — defeating OI-51 in exactly the failure mode it exists for (a
   push aimed at the old session landing in the gap). Not strictly a NEW
   regression from round 1 (the pre-round-1 code had the same gap via a
   different path — no try/catch at all, so a throw propagated and skipped
   the release either way) but round 1's fix touched exactly this code and
   had the matching sibling pattern sitting in the same codebase to copy
   from (`auth_provider.dart:573-579`, `perform_sign_out.dart`,
   `settings_screen.dart`, `main.dart` — all four call
   `releaseDeviceSessionIdentity()` unconditionally after a swallowed
   `signOut()` failure, each carrying an "OI-51 round 2" comment making the
   same point). Fixed by separating the try blocks to match that
   established pattern.

Round 2 also independently re-verified round 1's Finding 1 fix by reverting
and re-running (confirmed it discriminates), traced the `gotrue` SDK source
to rule out a stale-session risk from the swallowed `signOut()` exception,
and confirmed no new issue in the `!mounted`-removal or test isolation.

## Convergence

| | P0/P1 | P2 | P3 | new in ORIGINAL work |
|---|---|---|---|---|
| Round 1 | 0 | 2 | 1 | 3 |
| Round 2 | 0 | 1 | 0 | 1 (missed by round 1, not a round-1 regression) |
| B-pass | 0 | 0 | 0 | 0 |

Severity did not increase and the final B-pass found nothing further.
Round 2's one finding was a residual gap in the original code that round 1
missed while fixing an adjacent symptom, not a defect round 1's remediation
introduced — the same "keep finding new material issues" signal from
§4.12.1 that would indicate splitting the unit did not fire here. **Verdict:
converged.**

## B-pass — accepted

0 findings on the final diff (`docs/reviews/69297d4aefb4-review.md`) — 5
lenses run, all clean, including an independent re-verification that both
plan-review fixes actually landed as described (not just source-grep: ran
the behavioral tests). Supersedes the earlier `03a8ce7c088d-review.md`,
which reviewed a pre-round-1/2 snapshot; that file's Finding 1
(`accepted_risk` — no kill-switch on the sign-in redesign, founder decision
2026-08-02) still stands and was explicitly not re-litigated by either
round or the final B-pass.

## Hermes

`not_required` — Hermes is catastrophic-tier only. This is `platform`.

## Filed, not folded in

Nothing filed. Both bugs are fully closed within this batch; no residual
scope was identified that needed a separate OI.
