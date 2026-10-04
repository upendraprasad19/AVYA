---
bug_id: fa621a
date: 2026-10-03
batch: auth-recovery-code-length (the password-reset code field vs the hosted OTP length)
status: fixed
blast_radius: account
symptom: |
  A real user (Google-only account, no password) chose Forgot password on the web app. The sheet told her a 6-digit code was on its way and its code field accepted at most 6 characters; the hosted Supabase project emailed an 8-digit code. She could not enter the code she had just been sent. The backend saw exactly one POST /recover (200) and no /verify at all, because the client dropped digits 7-8 silently (maxLength 6 with the counter hidden) and rejected anything that was not exactly 6 characters. Nothing was logged client-side either, so the failure was invisible until she reported it.
concept: password_recovery_code_length
sot_registry_entry: password_recovery_code_length
writers:
  - "EXTERNAL, outside git: the hosted Supabase Auth setting mailer_otp_length (dashboard: Authentication > Providers > Email > Email OTP Length). Found at 8, restored to 6 on 2026-10-03. GoTrue clamps it to 6-10 and zero-pads the code. The date it became 8 is UNKNOWN."
  - { file: lib/features/auth/widgets/forgot_password_sheet.dart, method_or_widget: "_send (triggers the email whose code length the hosted project decides)", line: 81 }
readers:
  - "PRE-FIX client mirrors of the hosted value, at base c2bb0f75: forgot_password_sheet.dart:240 maxLength 6 on the code field (+ the hidden counter :241-245), :129 the guard 'code.length != 6 || int.tryParse(code) == null', :225 the copy 'We sent a 6-digit code', :253 the hint '123456', :38/:82/:115 comments; reset_password_screen.dart:308 'a 6-digit code'; sign_in_screen.dart:1283 the phone hint '6-digit OTP'."
  - { file: lib/features/auth/widgets/forgot_password_sheet.dart, method_or_widget: "_verifyCode (post-fix: normalizes the typed text, accepts any plausible code, passes it to verifyOTP unchanged, hands off to /reset outside the try)", line: 139 }
  - { file: lib/core/utils/recovery_code_format.dart, method_or_widget: "normalizeRecoveryCode (removes every separator, control and format character anywhere in the typed text)", line: 44 }
  - { file: lib/core/utils/recovery_code_format.dart, method_or_widget: "isPlausibleRecoveryCode (digits only, floor 6, no ceiling)", line: 52 }
  - { file: lib/features/auth/screens/reset_password_screen.dart, method_or_widget: "_buildNoSessionState (post-fix: the no-session copy states no digit count, names no link and no device)", line: 284 }
hive_key_prefix: n/a
hive_key_formula: "n/a - recovery state lives in GoTrue's own storage adapter, not an app Hive box"
sync_methods: []
restore_methods: []
cloud_table: auth.users
cloud_columns:
  - recovery_sent_at
  - recovery_token
contract_test_path: test/contracts/password_recovery_code_length_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - auth_forgot_password_send_failed
    - auth_password_recovery_verify_failed
cross_account_guard: "n/a - the whole flow runs signed-out against GoTrue; the sheet holds no user-scoped state."
forbidden_patterns_checked:
  - { pattern: "maxLength on the recovery-code field (a silent drop of the trailing digits)", absent: true }
  - { pattern: "a recovery-code length literal in the sheet's guard", absent: true }
  - { pattern: "a user-facing N-digit string for the recovery code or the phone OTP (sheet, reset screen, sign-in screen)", absent: true }
  - { pattern: "int.tryParse as the digits check (it also accepts a sign, 0x hex and surrounding whitespace)", absent: true }
  - { pattern: "a stale 'reset link' string in the sheet (c9e2b7 removed the link)", absent: true }
  - { pattern: "mounted as the predicate for popping the sheet route (it stays true through the exit animation)", absent: true }
  - { pattern: "an error branch calling setState without the shared _fail() guard", absent: true }
proposed_fix: |
  1. Client made length-tolerant, not re-pinned to 8: new lib/core/utils/recovery_code_format.dart. normalizeRecoveryCode removes every separator (Z*), control (Cc) and format (Cf) character anywhere in the typed text; isPlausibleRecoveryCode = ASCII digits only, at least 6, NO ceiling. The sheet's guard uses them; maxLength and the dead buildCounter are deleted; the code is passed to verifyOTP exactly as normalized (a leading zero must survive, so it is never parsed to an int).
  2. No user-facing string states a digit count: sheet confirmation copy, code-step hint ('Code from your email'), error strings ('Enter the code from your email.', 'Could not send the code'), the reset screen's no-session copy, and the phone-OTP hint ('Code from your SMS').
  3. Hosted value restored 8 -> 6 (live, founder-authorised, one key, outside git) so every shipped build is correct again before this fix reaches anyone.
  4. Inventory + guards: docs/operations/AUTH_HOSTED_SETTINGS.md (live values, readers, drift effect, read-only recipe), a config.toml banner (its [auth] block is local-dev only and diverges), the SoT concept password_recovery_code_length, a glossary row, bug classes 2.85 and 2.86, corrections in c9e2b7.
  5. Dismissal-safe async completion (found by the B-pass, reviewer A; present since c9e2b7): the sheet captures its router, navigator and its own route BEFORE the await, a shared _fail() helper ignores a request that finishes after the sheet was dismissed, and a successful verify hands off to /reset even when the sheet is gone. The code is single-use and the session already exists by then; the old early return left the user signed in but never asked for a new password.
  6. The hand-off pops only while the sheet's ROUTE is active (ModalRoute.isActive) and runs OUTSIDE the try (B-pass, reviewer B): the first version of item 5 popped on `mounted`, which stays true through the sheet's exit animation, so an answer landing in that window popped the only page off the stack.
  7. Single-use safety (reviewer B): both handlers return early while a request is in flight. The disabled button only goes inert on the NEXT build, so two taps inside one frame sent two /recover (hosted email quota) or two /verify (the single-use code spent twice).
  8. Test hygiene (reviewer B): password_recovery_code_flow_behavioral_test.dart builds a fresh Supabase singleton per case; it failed under shuffle seeds 1, 31337, 4 and 5 because the WITH-session case leaked its session into the NO-session case.
regression_test_planned: |
  test/contracts/password_recovery_code_length_behavioral_test.dart (99 tests, all new; singleton-free: a per-test recording SupabaseClient through SupabaseService.clientOverrideForTest). The 8-digit case is THE regression: it asserts the field's text equals what was typed (separates TRUNCATION) AND that /verify carries that exact token (separates REJECTION). Also covers 6/10/12 digits, a 10,000-digit paste and a leading zero, refused shapes, a paste table (NBSP, newline, tab, ideographic space, BOM, zero-width space, grouped digits), a 19-character table for normalizeRecoveryCode, back / re-send with a different address, every failure branch with the sheet still on screen, in-flight controls (two taps in one frame, a tap on the in-flight button, Cancel, the back arrow), the field's keyboard and focus, the hand-off (flag, go not push, no sheet left), and the sheet being dismissed while /verify or /recover is in flight at three moments (before, MID exit animation, after). Plus assertions in password_recovery_code_flow_behavioral_test.dart (the reset screen's no-session case pins the new sentence and that no 'link', 'different device' or 'digit' text is on screen) and that file made order-independent. Closes OI-109 (the sheet's two-step flow had no test at all).
mutation_proof: |
  Rule 21, 73 mutation runs through three driver invocations, each confirmed APPLIED by a marker count, run with the covering tests, restored and cmp-checked (all four lib files identical to their backups after every run). 69 went red, none was a compile error; 4 stayed green and are EQUIVALENT mutants with their reason recorded (M25a, M61, M62, M63). M1-M23 (24 runs; M14 was superseded by M36/M36b when trim() became normalizeRecoveryCode) were first run after the first implementation and the reviewer-A round and were all re-run on the final sheet; M24a-M68 were added for the reviewer-B findings, and MA6a-MA6c (listed last) for reviewer A's finding A6 once the reset-screen copy was fixed. Two driver faults were found and fixed along the way: a run in which flutter could not start (0 tests) was reported GREEN (it now counts as an infrastructure error and is retried, and M43 was re-run), and M31c's marker expected a count the field declaration also satisfies (corrected, re-run). Baseline 101 tests, 0 red. Also: the unfixed flow test fails under shuffle seeds 1, 31337, 4, 5 (F11). Full table in the body.
impact_analysis: |
  1 confirmed affected user. Only 5 accounts have EVER requested a password recovery (sends on 2026-07-22, 2026-08-06, 2026-09-13 twice, 2026-10-03; the two 2026-09-13 rows show last_sign_in_at 0.28 s and 0.49 s after the request, a programmatic flow rather than a person typing a code). When the hosted value became 8 is UNKNOWN: no config history is readable, so the claim is NOT "broken since c9e2b7 shipped". Evidence: GoTrue logs for the window show one POST /recover 200 at 07:32:52Z and zero /verify or /otp calls; auth.users.recovery_sent_at 2026-10-03 07:32:51Z with last_sign_in_at unchanged and no password set; the log stream's auth_audit_logs has her events (token_revoked, token_refreshed, user_recovery_requested). BEHAVIOUR CHANGES, accepted and documented: (1) pasting a whole sentence (for example the email's first line) used to be cut to its first 6 characters by maxLength 6 and, at hosted length 6, accepted; it is now refused with 'Enter the code from your email.' because the field no longer truncates. (2) The first version of this fix refused a code carrying a TRAILING zero-width space: the old field cut everything after character 6, so a 6-digit code with one trailing invisible character was accepted by accident. The B-pass (finding B10) caught it, and this document's earlier statement that invisible characters 'were rejected before and still are' was wrong for trailing characters beyond position 6. normalizeRecoveryCode now removes every separator, control and format character anywhere in the typed text. (3) Visible junk and native-script digits are still refused with the plain message, by design: stripping every non-digit would send a different, valid-looking code. (4) There is no ceiling: a 10,000-digit paste is sent to GoTrue and refused there, because a client ceiling would turn a future change of the hosted setting into a silent lockout again. SEPARATE OBSERVATION, not caused by this bug and NOT fixed here (ledger row 15 of the plan): the same user's SDK session was valid the whole time the sign-in screen was showing; it needs its own diagnosis and a founder scope decision. A Google-only account gets no hint to use Google on the email path (ledger row 14, founder: leave for now, to be re-confirmed).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "forgot_password_sheet.dart, recovery_code_format.dart (new), reset_password_screen.dart:284-299 (_buildNoSessionState), sign_in_screen.dart:1283. Final loop on the branch tree, 2026-10-03 and 2026-10-04: flutter analyze lib/ 0 warnings and 0 errors (60 pre-existing infos; the 3 infos in the touched flow test pre-date the batch, same anonKey and two (_, __) sites at base c2bb0f75; --no-fatal-infos exit 0); PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh OK (Gate 40, the context-artifact budget and every other check_*.dart gate); validate_diagnose_doc OK. password_recovery_code_length_behavioral_test 99/99 and password_recovery_code_flow_behavioral_test 2/2 (also under shuffle seeds 1-6, 31337, 777; re-run after the reset-screen copy fix: 101 passed). The full suite (TZ=Asia/Kolkata flutter test test/ --exclude-tags golden) measured 7595 passed, 9 skipped, exit 0 on the tree BEFORE the reset-screen copy fix (A6: one string and its assertions); pre-push re-runs it on the tree that is pushed (after merging origin/main) and CI re-runs it on main, with password_reset_redirect_flow_test, google_oauth_redirect_flow_test and signout_unbinds_sdk_identity_test inside it." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No app Hive box in this path; the recovery exchange lives in GoTrue's storage adapter." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change; GoTrue owns auth.users." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only on 2026-10-03: the affected auth.users row (Google-only, empty encrypted_password, recovery_sent_at 2026-10-03 07:32:51Z, last_sign_in_at unchanged); only 5 accounts have ever requested a recovery." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched; auth_forgot_password_send_failed and auth_password_recovery_verify_failed were already allow-listed in log-client-error." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table access from this flow beyond GoTrue." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "The Management API token (root .supabase/ file, HTTP 200) was used read-only and for the one authorised PATCH; no secret was printed, only allow-listed non-secret keys." }
  - { tier: 11, name: "External services", status: fixed_in_this_batch, evidence: "Supabase Auth hosted mailer_otp_length 8 -> 6, live on 2026-10-03, founder-authorised, one key: the change script aborted unless the value was exactly 8, re-read the whole config and diffed every key by sha256 (only mailer_otp_length differed); both plan reviewers re-read it independently; this batch's inventory re-read it again on 2026-10-03 (mailer_otp_length 6, recovery template code-only, site_url and uri_allow_list unchanged). End to end NOT verified: no recovery email has been sent since." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The new test drives sheet -> POST /auth/v1/recover -> POST /auth/v1/verify against a recording client and asserts the verify body (email, exact token, type recovery). The real email path is not testable here: founder device check pending (request a code, expect 6 digits, enter it, set a password, sign in)." }
recurrence: "Third hosted-setting-vs-client drift on the auth surface. e9f2a4 (bug class 2.45): the hosted Site URL silently beat the client's redirectTo. f2b8a1: the hosted Redirect URLs allowlist had to match the client's OAuth redirect. c9e2b7 built the code flow on an unchecked '6-digit' premise taken from Supabase's documentation, and nothing ever read the live setting. First time the drifting value is an input-length literal; recorded as bug class 2.85."
related_bugs: [e9f2a4, c9e2b7, f2b8a1]
---

# fa621a — the password-reset code field allowed 6 digits; the project emailed 8

## What happened

A real user whose account is Google-only (no password) tried the email path on the web app, did not know a password, and chose Forgot password. The email carried an **8-digit** code. The sheet said a 6-digit code was coming and its field accepted **6 characters**, silently dropping the rest (`maxLength: 6`, counter hidden), and its guard refused anything but exactly 6. No `/verify` ever reached GoTrue, so the backend looked healthy and nothing was logged client-side. We found out because she told us.

## Writers and readers (named before the fix, §4.1)

The WRITER of the code length is **not in git**: the hosted Supabase Auth setting `mailer_otp_length`. It was 8. GoTrue clamps it to 6–10 (`internal/conf/configuration.go`, `ApplyDefaults`; identical at tags v2.50.0 through v2.180.0) and zero-pads the code, so a code is all digits, may start with `0`, and is never shorter than 6.

The READERS were the client's literals, all written by `c9e2b7` (base `c2bb0f75`): `forgot_password_sheet.dart:240` `maxLength: 6` (+ `:241-245` the hidden counter), `:129` the `!= 6` guard, `:225` the copy, `:253` the hint, `reset_password_screen.dart:308`, `sign_in_screen.dart:1283` (phone hint). Writer and readers disagreed and nothing could notice: `supabase/config.toml:215` says `otp_length = 6`, but it only configures local `supabase start`.

## Why it escaped

1. `c9e2b7` took "6-digit" from Supabase's own pages and never read the live setting. (Those pages say `{{ .Token }}` is a 6-digit code; "6 to 10" appears only on the self-hosted SMS page.)
2. The sheet's two-step flow had **no test at all** (OI-109, first filed as OI-100 and renumbered by `babea1a4`).
3. The failure was silent in the UI (a hidden counter) and invisible in the backend (no request).
4. When the hosted value became 8 is unknown. Do not read this as "broken since `c9e2b7` shipped".

## Bug-history lookup (§4.1.5)

`docs/diagnoses/INDEX.md` matches for the surface: `e9f2a4` (hosted Site URL beats `redirectTo`, class 2.45), `9f5c41`, `b7d4e2`, `c8f1d3`, `c9e2b7`, `f2b8a1`. Recurrence: **yes, of the hosted-vs-client family** (e9f2a4, f2b8a1, c9e2b7's unchecked premise); the new element is an input-length literal. The known-good remedy for the family — verify the dashboard layer first — is applied, and the missing step ("nothing reads the hosted value") is now an inventory plus a tolerant client. Bug class 2.85 records it. No `feedback_*.md` for auth/password existed before this batch.

## The fix

See `proposed_fix` above. The decisive design choice is **tolerance, not a new number**: the helper accepts digits, floor 6, no ceiling, because an upper bound only catches over-long typos and turns any future hosted change into a silent total lockout again. The hosted value is nevertheless held at 6 (see "Raising the length" in `docs/operations/AUTH_HOSTED_SETTINGS.md`): every build older than this fix is 6-only, and there is no minimum-version mechanism.

### Found by the B-pass (two context-blind reviewers), fixed in this batch

Full report with every finding and disposition: `docs/reviews/auth-recovery-code-length-bpass.md`; every finding has a terminal state in `docs/audit/auth-recovery-code-length.closure.yaml`. What changed the code:

**Reviewer A: the sheet was not safe against being dismissed mid-request** (pre-existing since `c9e2b7`, found in a function this batch rewrote, so fixed here, §4.2). `_verifyCode` returned early when the sheet had been dismissed (drag or a tap on the barrier) while `/verify` was in flight: the single-use code was already consumed and the recovery session already existed, but `AppRouter.isPasswordRecovery` was never set and `/reset` never opened, so the user ended up signed in on the sign-in screen and was never asked for a new password. The error branches of `_send` and `_verifyCode` also called `setState` unguarded, which throws on a disposed State. Writer: `forgot_password_sheet.dart` `_verifyCode` / `_send`; reader: `reset_password_screen.dart` (the `/reset` guard) via `AppRouter.isPasswordRecovery`.

**Reviewer B (mutate-and-run) found that the first fix of that was wrong, and that most of the sheet was unpinned.** Against the author's 37 tests at that point, 29 mutants and 4 fix candidates:

| B | Sev | Finding | Fix | Pinned by |
|---|---|---|---|---|
| 1 | P1 | the hand-off popped on `mounted`, which stays true through the sheet's ~200 ms exit animation; an answer landing then popped the only page (go_router: "You have popped the last page off of the stack"), the throw sat inside the `try` so it was reported as "Could not verify that code", `/reset` was never reached, the code was spent | `ModalRoute` captured before the await, pop only while `isActive`, hand-off after the `try` | success and failure MID exit animation (last in the file); M43, M19, M45 |
| 2 | P1 | nothing inspected the MOUNTED sheet after a failure or a refusal: `_fail` without `_sending = false`, `_sending = true` above a guard, `_fail` clearing the code, a deleted AuthException branch all passed 37/37 | cases for a rejected code, a rejected send, a refused code / email followed by a good one | M26-M29, M64, M65 |
| 3 | P1 | the whole back / re-send path was untested; a stale `_sentTo` meant `/verify` for the OLD address while the copy named the new one | a different address after back; back clears the code and the error and returns to the email step | M30, M31a-c |
| 4 | P2 | both generic catches were untested | a `[]` body on `/verify`, the PKCE storage throwing on `/recover`, mounted and dismissed | M58, M59 |
| 5 | P2 | `_sending` was not a re-entrancy guard (a rebuild behind) | `if (_sending) return;` in both handlers | M24a, M24b, M25, M55a/b |
| 6 | P2 | trimming was tested with ASCII spaces only; the email trim and the `@` check not at all | paste table; padded and malformed emails | M36, M37, M39, M40 |
| 7 | P2 | the explicit pop is deletable; `go` vs `push` indistinguishable | `canPop()` is false after the hand-off; the pop is kept and recorded as an equivalent mutant (M63) | M35 |
| 8 | P2 | `keyboardType`, `autofocus`, Cancel / back while sending, the per-step `ValueKey` had no test | cases at the widget and at the platform channel | M32-M34, M41, M42 |
| 9 | P3 | the `@` check was untested | see 6 | M40 |
| 10 | P3 | a pasted code with an invisible character was refused (the old `maxLength` field accepted a trailing one by accident); this document had said otherwise | `normalizeRecoveryCode` (a category, not a list); wording corrected in `impact_analysis` | M36-M38, M48-M51 |
| 11 | P3 | the flow test failed when the runner ordered its two cases the other way | a fresh Supabase singleton per case with `persistSession: false` | unfixed file red under seeds 1, 31337, 4, 5 |
| 12 | P3 | swapping the order of flag / pop / go is unobservable | recorded, not pinned | M61, M62 (green, equivalent) |

**Reviewer A, stale copy (A6) and the registry method name (A3a).** The reset screen's no-session sentence still said "…or the link was opened on a different device from the one that requested it." although the email carries a typed code and no link (`c9e2b7`), and a typed code works from any device. It now reads "This reset session has expired or is no longer valid." (`reset_password_screen.dart:299`); the flow test asserts that sentence and that no 'link', 'different device' or 'digit' text is on screen (MA6a-MA6c red), and the registry reader names `_buildNoSessionState`. Both were first held back by an auto-mode read denial and were closed once the read worked.

Decision recorded for B10: there is **no ceiling**. A 10,000-digit paste reaches `/verify` and is refused by GoTrue with its own message; a client cap would turn any future change of the hosted setting into the same silent lockout. A test pins that the paste goes out whole, so adding a cap fails loudly and points here.

## Tests and mutation proof (§4.4 rule 21)

New: `test/contracts/password_recovery_code_length_behavioral_test.dart` (99 tests). Existing, extended: `password_recovery_code_flow_behavioral_test.dart` (the no-session case pins the new sentence and the absence of 'link', 'different device' and 'digit'; its two cases are now order-independent). The new file builds a recording `SupabaseClient` per test in `setUp` (the real zone) and disposes it in `tearDown`; building it inside the `testWidgets` body makes `dispose()` hang. `Supabase.initialize` is deliberately not used there (one-shot singleton). The dismissal cases hold a request open with a `Completer`, dismiss the sheet by tapping the modal barrier, then let the request finish; the invisible characters are built from code points, never typed, because a literal U+200B in the file would be invisible to its next reader.

The harness was first run against the OLD code (31 tests at that point): 18 passed, 13 failed, every failure for the intended reason. Then the fix; then mutations. The table below is **generated** from the drivers' result files, not typed: 73 runs, 69 red, 4 green. The four green runs are equivalent mutants and each says why; none is claimed as protection. "Red" counts failing cases of the 101 in the two files (baseline 101, 0 red).

| # | Mutation | Red | Caught by (first cases) |
|---|---|---|---|
| M1 | re-add maxLength: 6 (+ hidden counter) on the code field | 15 | a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c…; a pasted code padded with spaces -> /verify carries "12345678" (+12 more) |
| M2 | restore the exact-6 / int.tryParse length guard | 22 | a pasted code a zero-width space inside the code -> /verify car…; a pasted code padded with spaces -> /verify carries "12345678"; a pasted code shown in two groups with a space -> /verify carri… (+19 more) |
| M3 | re-add a CEILING: maxLength: 10 | 3 | the code a user can type a 12-digit code "123456789012" is type…; the code a user can type there is no ceiling: a 10,000-digit pa…; pin: the sheet has no hint literal, no stale "reset link", no m… |
| M4 | floor 6 -> 7 | 5 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code grouped with a narrow no-break space -> /verify c…; the code a user can type a 6-digit code "123456" is typed intac… (+2 more) |
| M5a | restore "6-digit" in the sheet confirmation copy | 3 | the two steps a padded email is trimmed on the wire and in the …; the two steps send step -> exactly one /recover, then the code …; pin: lib/features/auth/widgets/forgot_password_sheet.dart state… |
| M5b | restore the code-step hint '123456' | 2 | the two steps send step -> exactly one /recover, then the code …; pin: the sheet has no hint literal, no stale "reset link", no m… |
| M5c | restore "6-digit" in the reset-screen no-session copy | 2 | flow-test: NO session -> refuses the form and offers a new code; pin: lib/features/auth/screens/reset_password_screen.dart state… |
| M6 | replace the regex with int.tryParse != null | 6 | the code a user can type a leading plus is refused locally: no …; the code a user can type there is no ceiling: a 10,000-digit pa…; shape: rejects "+12345" (+3 more) |
| M7 | delete AppRouter.isPasswordRecovery = true | 3 | dismissing the sheet while a request is in flight /verify succe…; dismissing the sheet while a request is in flight /verify succe…; the hand-off to /reset a good code sets the recovery flag and l… |
| M8 | delete router.go('/reset') | 6 | dismissing the sheet while a request is in flight /verify succe…; dismissing the sheet while a request is in flight /verify succe…; failures with the sheet still on screen a locally refused code … (+3 more) |
| M9 | restore "Could not send reset link" (debug + release strings) | 3 | failures with the sheet still on screen a missing client names …; failures with the sheet still on screen a non-Auth failure on /…; pin: the sheet has no hint literal, no stale "reset link", no m… |
| M10 | restore the phone hint '6-digit OTP' | 1 | pin: lib/features/auth/screens/sign_in_screen.dart states no OT… |
| M11 | connective && -> || in the helper | 16 | failures with the sheet still on screen a locally refused code …; going back and sending again back returns to the email step, ke…; the code a user can type a code that is too short is refused lo… (+13 more) |
| M12 | drop the regex anchors (^ and $) | 9 | the code a user can type a leading plus is refused locally: no …; the code a user can type a letter inside the digits is refused …; the code a user can type a visible hyphen is refused locally: n… (+6 more) |
| M13 | floor operator >= -> > | 4 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code grouped with a narrow no-break space -> /verify c…; the code a user can type a 6-digit code "123456" is typed intac… (+1 more) |
| M15 | verifyOTP type recovery -> email | 5 | the code a user can type a 10-digit code "1234567890" is typed …; the code a user can type a 12-digit code "123456789012" is type…; the code a user can type a 6-digit code "123456" is typed intac… (+2 more) |
| M16 | confirmation copy no longer names the address | 3 | going back and sending again a DIFFERENT address after back: th…; the two steps a padded email is trimmed on the wire and in the …; the two steps send step -> exactly one /recover, then the code … |
| M17 | _fail loses its mounted guard | 4 | dismissing the sheet while a request is in flight /recover fail…; dismissing the sheet while a request is in flight /recover reje…; dismissing the sheet while a request is in flight /verify faili… (+1 more) |
| M18 | early return before the /reset hand-off when the sheet is unmounted | 1 | dismissing the sheet while a request is in flight /verify succe… |
| M19 | pop() with NO route check at the hand-off | 7 | dismissing the sheet while a request is in flight /recover fail…; dismissing the sheet while a request is in flight /recover reje…; dismissing the sheet while a request is in flight /verify faili… (+4 more) |
| M20 | _send AuthException branch back to an unguarded setState | 1 | dismissing the sheet while a request is in flight /recover reje… |
| M21 | router/navigator captured AFTER the await (the old order) | 1 | dismissing the sheet while a request is in flight /verify succe… |
| M22 | phone hint 'Enter six-digit code' (the widened pin regex) | 1 | pin: lib/features/auth/screens/sign_in_screen.dart states no OT… |
| M23 | code-step hint '12345678' (the 4+-digit-run assertion) | 1 | the two steps send step -> exactly one /recover, then the code … |
| M24a | _send loses its _sending guard | 1 | controls while a request is in flight two taps on SEND CODE ins… |
| M24b | _verifyCode loses its _sending guard | 1 | controls while a request is in flight two taps on VERIFY CODE i… |
| M25 | both guards AND the onTap null-ing removed | 4 | controls while a request is in flight a tap on the in-flight SE…; controls while a request is in flight a tap on the in-flight VE…; controls while a request is in flight two taps on SEND CODE ins… (+1 more) |
| M25a | ONLY the onTap null-ing removed (handler guards intact: expected GREEN = redundant) | 0 | equivalent: the handler guards (M24a/M24b) already make a second tap a no-op, so nulling `onTap` is redundant defence in depth |
| M26 | _fail no longer resets _sending | 4 | failures with the sheet still on screen a non-Auth failure on /…; failures with the sheet still on screen a non-Auth failure on /…; failures with the sheet still on screen a rejected code: GoTrue… (+1 more) |
| M27 | _fail clears the typed code | 2 | failures with the sheet still on screen a non-Auth failure on /…; failures with the sheet still on screen a rejected code: GoTrue… |
| M28 | _verifyCode's AuthException branch deleted (falls into the generic line) | 1 | failures with the sheet still on screen a rejected code: GoTrue… |
| M29 | _send's AuthException branch deleted | 1 | failures with the sheet still on screen a rejected send: the me… |
| M30 | _sentTo is not refreshed on a second send | 1 | going back and sending again a DIFFERENT address after back: th… |
| M31a | back does not clear the typed code | 1 | going back and sending again back returns to the email step, ke… |
| M31b | back does not clear the error | 1 | going back and sending again back returns to the email step, ke… |
| M31c | back does not return to the email step | 2 | going back and sending again a DIFFERENT address after back: th…; going back and sending again back returns to the email step, ke… |
| M32 | the per-step ValueKey on the TextField removed | 1 | the field the user types into each step gets a NEW field element |
| M33 | code-step keyboardType number -> text | 1 | the field the user types into the keyboard follows the step: em… |
| M34 | autofocus true -> false | 2 | the field the user types into the code field takes focus when t…; the field the user types into the email field takes focus again… |
| M35 | router.go('/reset') -> router.push('/reset') | 2 | dismissing the sheet while a request is in flight /verify succe…; the hand-off to /reset the hand-off REPLACES the stack and leav… |
| M36 | normalizeRecoveryCode replaced by trim() at the call site | 4 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c… (+1 more) |
| M36b | no normalization at all at the call site | 7 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c… (+4 more) |
| M37 | the helper strips \s only (misses every format character) | 12 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; normalize: U+0085 NEXT LINE: gone at the start, in the middle a… (+9 more) |
| M37b | the helper strips ASCII whitespace only | 21 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c… (+18 more) |
| M38 | the helper strips EVERY non-digit (over-eager) | 9 | the code a user can type a leading plus is refused locally: no …; the code a user can type a letter inside the digits is refused …; the code a user can type a visible hyphen is refused locally: n… (+6 more) |
| M39 | the email is not trimmed | 1 | the two steps a padded email is trimmed on the wire and in the … |
| M40 | the @ check is dropped | 1 | the two steps the email "not-an-email" is refused locally and a… |
| M41 | Cancel enabled while a request is in flight | 2 | controls while a request is in flight Cancel does nothing while…; controls while a request is in flight Cancel does nothing while… |
| M42 | back arrow enabled while a request is in flight | 1 | controls while a request is in flight the back arrow is gone wh… |
| M43 | hand-off pop predicate reverted to `mounted` (B-pass P1) | 2 | dismissing the sheet while a request is in flight /verify rejec…; dismissing the sheet while a request is in flight /verify succe… |
| M45 | sheetRoute captured AFTER the await | 1 | dismissing the sheet while a request is in flight /verify succe… |
| M47 | a ceiling of 64 added to the shape check | 1 | the code a user can type there is no ceiling: a 10,000-digit pa… |
| M48 | the helper strips separators only (drops Cc and Cf) | 18 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code wrapped in a no-break space, a newline and a tab … (+15 more) |
| M49 | the helper drops the control (Cc) category | 6 | a pasted code wrapped in a no-break space, a newline and a tab …; normalize: U+0009 CHARACTER TABULATION: gone at the start, in t…; normalize: U+000A LINE FEED: gone at the start, in the middle a… (+3 more) |
| M50 | the helper drops the format (Cf) category | 13 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code wrapped in ideographic spaces and a byte-order ma… (+10 more) |
| M51 | the helper regex loses `unicode: true` | 27 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c… (+24 more) |
| M55a | _verifyCode never sets _sending = true | 5 | controls while a request is in flight Cancel does nothing while…; controls while a request is in flight a tap on the in-flight VE…; controls while a request is in flight the back arrow is gone wh… (+2 more) |
| M55b | _send never sets _sending = true | 6 | controls while a request is in flight Cancel does nothing while…; controls while a request is in flight a tap on the in-flight SE…; controls while a request is in flight the back arrow is gone wh… (+3 more) |
| M56 | _send's success path leaves _sending true | 40 | a pasted code a trailing zero-width space after 6 digits (the o…; a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c… (+37 more) |
| M58 | _send's generic catch uses an unguarded setState | 1 | dismissing the sheet while a request is in flight /recover fail… |
| M59 | _verifyCode's generic catch uses an unguarded setState | 1 | dismissing the sheet while a request is in flight /verify faili… |
| M60 | _verifyCode's AuthException branch uses an unguarded setState | 1 | dismissing the sheet while a request is in flight /verify rejec… |
| M61 | recovery flag set AFTER router.go (B-pass equivalent mutant: expected GREEN) | 0 | equivalent: the real `/reset` screen reads the flag in a post-frame callback, so the order of the two statements is unobservable |
| M62 | router.go BEFORE the pop (B-pass equivalent mutant: expected GREEN) | 0 | equivalent: `go` is applied a frame later in either order; the sheet is gone either way |
| M63 | the explicit pop deleted (B-pass: go() alone removes the sheet, expected GREEN) | 0 | equivalent in `flutter_test`: `router.go` replaces the page stack and takes the page-less sheet with it; the pop is KEPT deliberately (the shipped behavior popped first, only a device can say `go` alone is enough) |
| M64 | _verifyCode sets _sending = true ABOVE the code guard | 2 | failures with the sheet still on screen a locally refused code …; going back and sending again back returns to the email step, ke… |
| M65 | _send sets _sending = true ABOVE the email guard | 2 | the two steps the email "" is refused locally and a good one st…; the two steps the email "not-an-email" is refused locally and a… |
| M66 | truncation re-added through inputFormatters (slips past the maxLength pin) | 14 | a pasted code a zero-width space inside the code -> /verify car…; a pasted code grouped with a narrow no-break space -> /verify c…; a pasted code padded with spaces -> /verify carries "12345678" (+11 more) |
| M67 | digits regex made multiLine | 1 | shape: rejects "123456\n" |
| M68 | floor 6 -> 5 | 5 | failures with the sheet still on screen a locally refused code …; going back and sending again back returns to the email step, ke…; the code a user can type a code that is too short is refused lo… (+2 more) |
| MA6a | the old "link was opened on a different device" sentence restored | 1 | flow-test: NO session -> refuses the form and offers a new code |
| MA6b | a "link" creeps back into the new sentence | 1 | flow-test: NO session -> refuses the form and offers a new code |
| MA6c | a "digit" count creeps back into the new sentence (the fa621a assertion) | 1 | flow-test: NO session -> refuses the form and offers a new code |

Notes on the table: MA6a-MA6c were run last, after the reset-screen copy fix, and are listed last. M14 (the caller's `trim()` dropped) of the first round is superseded by M36 / M36b now that the call is `normalizeRecoveryCode`. M43 reddens two cases because the second mid-animation case is the next `testWidgets` after a broken navigator, which leaks a performance-mode request into it; that is why those two cases are last. All four lib files were byte-identical to their backups after every run (`cmp` and a sha256 check inside the driver, and a final check after the last run).

## What the tests cannot prove

The hosted value and a real email. That is the founder's device check: request a code, expect **6 digits**, enter it, set a password, sign in. Until it is done, "fixed" means: the client accepts any code GoTrue can issue, and the hosted value is back at 6 (read back repeatedly, never exercised end to end). Also not proven here: the release-mode behavior of the mid-animation pop (asserts are compiled out, so the original defect may have been benign in release; the fix does not depend on it), whether `go('/reset')` alone dismisses the sheet on a device (the pop is kept for that reason), real-device keyboard and IME effects, and whether any mail client really appends a zero-width character to a copied code (the normalization is cheap insurance, not a proven need).

## Open items, owned by the founder (terminal state `blocked_on_user`)

- **Device check** and the web deploy that carries the fix (the shipped web build and every shipped APK stay 6-only until replaced).
- **Scope decision** for the separate observation (a client holding a valid session was shown the sign-in screen): join this batch, or its own OI and its own §4.1 diagnosis (recommended: its own).
- **Re-confirm** "leave the Google-only hint": the original premise ("people can use Google or reset") was found incomplete — the user was shown the email path with no hint she had signed up with Google, and the reset path then failed.
- **§4.6 disposition**: this is an auth change shipped without a feature flag, recorded as exempt in the plan-review record (the old path was the bug; the hosted value is the kill-switch). The founder may overrule and ask for a flag.
- **Unread hosted keys**: `password_min_length` and `password_required_characters` (needs a live read; the inventory row says "not read").
- **The date the hosted value became 8** is unknown; only the founder can know whether and when they changed it.
