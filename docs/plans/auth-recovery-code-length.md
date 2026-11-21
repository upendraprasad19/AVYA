# Plan (v3, post rounds 1 and 2) — auth-recovery-code-length: the password-reset code field must accept whatever code the hosted project issues

Branch `auth-recovery-code-length` off `origin/main` `c2bb0f75` (worktree `.claude/worktrees/auth-recovery-code-length`).
Precedes code per CLAUDE.md §4.12: this plan → ×2 context-blind review (done; both returned `harden`, all findings folded — §0) →
`docs/plan-reviews/auth-recovery-code-length.md` → implement → local gate loop → B-pass → founder decides commit/push/merge.

**Tier.** §4.12.6 fix tier **L** (auth). Blast-radius tier **account**: `docs/blast_radius.yaml:304` (`lib/features/auth/**`), `:423`
(`lib/core/**` = account — `lib/core/utils` falls here), `:79` (`docs/architecture/auth-detail.md`), `:399` (`docs/**` = feature). ≥account ⇒
plan-review record at merge (`scripts/check_plan_review_record_exists.dart`) and a SELF-INITIATED B-pass before the `--no-ff` merge (§4.3).
**Execution mode (decided now, §4.12.7): INLINE** — one worktree, one writer; subagents only for the two plan reviews (done) and the B-pass. Never switched mid-batch.
**§4.6 disposition (R2-4): EXEMPT, recorded here and in the plan-review record.** §4.6 names auth; this diff changes one guard predicate. Rationale: the old path IS the defect, so a default-OFF
flag with the old path "reachable" would preserve the lockout; for every code GoTrue can issue the new predicate accepts a superset (the old one required exactly 6 chars; GoTrue issues ≥ 6 digits, so
6-digit codes behave identically and 7+-digit codes newly work); the only strings newly rejected (`+12345`, `-123456`, `0x1234`, …) can never be issued, and previously cost a doomed request. Rollback =
`git revert` of the single fix commit. Same disposition shape as `docs/plan-reviews/restore-onboarding-signin-fix.md:50-60`. **The founder may overrule this and ask for a flag.**
**Lenses in scope (docs/audit/LENS_REGISTRY.md):** L1 writer/reader drift · L8 contract-test coverage gap · L10 SoT registry completeness · L17 live verification of every claim · L20 diagnose-doc +
memory pair · L25 intra-document drift · L37 empty/malformed/wrong-shape readers · L41 cross-document semantic consistency.

## 0. Review rounds — folded (both rounds returned `harden`; every finding accepted, none rejected)

**Round 1** (fresh Sonnet context, read-only, 166 tool calls): re-verified the cited file:line at the base, the value-semantics sweep, the GoTrue clamp (identical at 9 tags back to v2.50.0), the
harness facts from the installed gotrue 2.27.1 / supabase_flutter 2.17.1 sources, the registry gates and the live claims it could read. Folded: **F1 (P1)** `Supabase.initialize` is a one-shot singleton
(`supabase_flutter-2.17.1 lib/src/supabase.dart:104-107`, re-verified by the main thread) so a per-case recording client must be injected through `SupabaseService.clientOverrideForTest`
(`lib/core/services/supabase_service.dart:65-67`; precedent `test/sync/sync_domain_skip_harness.dart:23,32`). **F2 (P1)** drop the client ceiling and `maxLength` — the 6–10 range is documented only for
SMS; Supabase's email docs say `{{ .Token }}` is a "6-digit" code → D2 digits-only, floor 6. **F3** impact/date wording. **F4** ledger rows for the founder device check and honest row-12 notes.
**F5/F6** reset-screen + hint assertions, controller-text assertion, static-flag reset, mutations M7/M8. **F7** a new bug class §2.85. **F8** VPS test command. **F9** the "do not raise the length"
constraint is undecidable-by-design. **F10** c9e2b7's `OI-100` is a STALE cite. **F11** live-doc sweep + two stale sheet strings. **F12** wording. **F13** §6 rationale. **F14** `config.toml` banner.
**F15 hygiene (a)** name the B-pass file, (b) list the `project_*.md` retrospective, (c) use the file's real "Detail:" idiom, (d) keep only the settings the client mirrors, (e) avoid TBD/TODO/`???`/`<…>` in
diagnose frontmatter, (f) record paste-cleaning as `verified_clean` with evidence.
**Round 2** (fresh Opus context, read-only, 159 tool calls, a different reviewer): confirmed round 1's folding is mostly faithful; reported two P1s and sixteen P2/P3s. Folded:
**R2-1 (P1)** a `SupabaseClient` built INSIDE the `testWidgets` body spawns a real isolate in the FakeAsync zone and `dispose()` then never completes (10-minute timeout) — the reviewer reproduced it with
`package:fake_async`; building the client in **`setUp` (real zone)** and disposing in **`tearDown`** completes in ms → D5. **R2-2 (P1)** a NEW, separate observation — see §1b; verified by the main thread
(edge_logs JWT attributes, auth_audit_logs); it is NOT folded into this batch's code, it gets a terminal ledger row and a founder decision. **R2-3** Gate 40 counts EVERY terminal entry, so
`closed_count == total_findings` (re-verified: `validate_audit_closure.dart:240-262`). **R2-4** §4.6 disposition (above). **R2-5** adding ANY `docs/reviews/*.md` requires a same-dated entry in
`.claude/skills/code-review/tuning-history.md` (`check_skill_tuning_history.dart:78-100`, re-verified) → D7. **R2-6** the existing concept `password_recovery_session` is edited and cross-linked, not ignored → D6.
**R2-7** the forbidden-pattern idea carried an escaping trap (`_readQuoted` returns raw text, so the registry's majority `\\.` idiom is dead) and is redundant with D5(c) → **dropped** (smaller unit, §4.12.1).
**R2-8** post-merge numbering-collision check for §2.85 → §7. **R2-9** the reset-screen "no digit" assertion needs `Supabase.instance`, so it moves into the existing no-session test and the new file
stays singleton-free. **R2-10** §0 and the mutation list now agree (M1–M10) and F15 is enumerated. **R2-11** ERE grep recipe. **R2-12** source pins are case-sensitive and comment-stripped. **R2-13** row 12 carries
`commit:` + `verification:`. **R2-14** the behaviour change for whole-email paste is stated. **R2-15** the phone hint `'6-digit OTP'` is an instance of the same class → changed (row 4), not waved through.
**R2-16** nested `lib/features/auth/CLAUDE.md` stale "magic-link" wording fixed and the new test listed. **R2-17** evidence cites `auth_audit_logs`. **R2-18** memory corrected.
**Unit size (reviewer's opinion, adopted):** the D1–D5 unit is small and converging; the only large item (R2-2) is split out, per §4.12.1. There is **no third review round**: both reviewed rounds are done, the folds
are mechanical (a test-harness setup order, wording, ledger counts, doc edits), and the B-pass reviews the real diff; precedent `docs/plans/resume-banner-batch.md` ("harden → converged after fold").

## 1. What happened (verified read-only on 2026-10-03 unless marked "session-sourced")

A real user (id withheld from this committed file; Google-only: `raw_app_meta_data.provider='google'`, `encrypted_password` empty, one `google` identity, one iPhone-Safari session created 2026-10-02 04:48:45Z) tried the
email path, did not know a password, and chose Forgot password on the web app. The sheet's code field accepts at most **6** characters; the hosted project was configured to email **8**-digit codes. GoTrue logs
(window 2026-10-02T08:00Z → 2026-10-03T08:00Z+): exactly one `POST /recover` 200 at 07:32:52Z and **zero** `/verify` or `/otp` calls — **no code attempt ever reached GoTrue; what she typed is unknown**.
`auth.users.recovery_sent_at = 2026-10-03 07:32:51Z`, `last_sign_in_at` unchanged, still no password, recovery token still present. `auth.audit_log_entries` has 0 rows all-time, but the log stream's
`auth_audit_logs` has her events (`token_revoked` + `token_refreshed` 07:29:52Z, `user_recovery_requested` 07:32:51Z). **Blast radius: 1 confirmed affected user; only 5 accounts have EVER requested a recovery
(latest sends 2026-07-22, 08-06, 09-13 ×2, 10-03; the two Sep-13 rows show `last_sign_in_at` 0.28 s / 0.49 s after the request — a programmatic flow, not a human typing a code). When the hosted value became 8
is UNKNOWN: no config history is readable, and the claim is NOT "broken since c9e2b7 shipped".**

**Hosted config as read (Management API `GET /v1/projects/dedsavbjuwgarrhphgnl/config/auth`, allow-listed non-secret keys only):** BEFORE the change (session-sourced): `mailer_otp_length = 8`,
`mailer_otp_exp = 3600`, `mailer_templates_recovery_content = "{{ .Token }} is your AVYA password reset code. Enter it in the app to set a new password. It expires shortly — if you didn't request this, ignore this email."`
(no link), `site_url = https://app.icanbefitter.com`, `uri_allow_list = https://app.icanbefitter.com/reset,io.supabase.icanbefitter://login-callback/,https://app.icanbefitter.com`,
`sms_otp_length = 6`, `external_google_enabled = true`, `smtp_host = smtp-relay.brevo.com`. AFTER (re-read independently by BOTH reviewers): `mailer_otp_length = 6`, all others unchanged.
**Founder-authorised live change, done 2026-10-03, NOT part of this diff:** `PATCH` of that one key 8 → 6; the script (session-sourced) aborted unless the value was exactly 8, re-read the whole config and
diffed every key by sha256: only `mailer_otp_length` changed. **Not verified end-to-end** — no recovery email has been sent since. It restores writer == reader for the shipped web build and every shipped APK;
it does not remove the cause.
**GoTrue contract (read from source 2026-10-03; re-confirmed by round 1 at tags v2.50.0 … v2.180.0):** `internal/conf/configuration.go` `ApplyDefaults`: `if config.Mailer.OtpLength == 0 || < 6 || > 10 { …= 6 }`
(same clamp for `Sms` and `MFA.Phone`); the generator zero-pads (`internal/crypto/crypto.go`), so leading zeros are legal. Supabase's own pages say `{{ .Token }}` is a **6-digit** code
(customizing-email-templates, auth-email-templates, auth-email-passwordless — re-verified by the main thread); "any value between 6 and 10" appears only on the self-hosted SMS page. c9e2b7 was built on that premise.

### 1b. NEW observation, separate defect — NOT caused by or fixed in this batch (R2-2, re-verified by the main thread)

Her SDK session was **valid the whole time** while the sign-in screen was showing. `edge_logs` JWT attributes: `rpc/email_is_registered` — whose only caller is the sign-in screen's email step
(`sign_in_screen.dart:459` → `auth_provider.dart:196`) — carried `role=authenticated`, subject and session ids withheld from this committed file, JWT `iat` 1791012592 = **07:29:52Z** at **07:29:53.7Z** and **07:30:36.5Z**
(i.e. 1.5 s after a successful refresh-token rotation). The SAME session/JWT then made `/auth/v1/user` (07:33:11Z) and normal app traffic — `user_profile`, `update_streak_progress`, `users` PATCH 204,
`user_progress`, `readiness_daily`, `subscriptions` — from 07:40:39Z to 07:41:19Z. Only non-200 `/token` calls in 07:15–07:40Z: a 504 (10.6 s) at 07:24:23Z and a 400 at 07:31:34Z (consistent with a wrong-password attempt;
not attributable). **Mechanism UNPROVEN.** A candidate, not a finding: `splash_screen.dart` bounded init (12 s) routes an unauthenticated-at-that-moment client to `/sign-in`, and the router has no
`refreshListenable` (auth CLAUDE.md pitfall) so a session recovered afterwards does not move the user. It needs its own §4.1 diagnosis (bug-history: e5b2a9, c2e9f4, ab1886b7, 7bfc0b22). **Disposition: ledger row 15
(`blocked_on_user`) — founder decides whether it joins this batch or gets its own OI + batch (recommended: its own — different area, unproven mechanism, and folding it would make this unit too large).**
It also changes the premise of the founder's earlier "leave the Google-only hint": she did not lack a way in, she was already signed in. Row 14 is therefore re-presented, not silently kept.

## 2. Writers and readers (file:line at `c2bb0f75`)

| Role | Where | What |
|---|---|---|
| **Writer of the code's LENGTH (external, no in-repo writer)** | hosted Supabase Auth config `mailer_otp_length` (Dashboard → Authentication → Providers → Email → Email OTP Length) | was 8; GoTrue clamps to [6,10] |
| Look-alike that is NOT the writer | `supabase/config.toml:215` (`[auth.email] otp_length = 6`; also `:154` `site_url = "http://127.0.0.1:3000"`, the e9f2a4 trap) | governs only the local `supabase start` stack; nothing pushes it to hosted (`grep -rnE "config push\|supabase link" .github scripts` = 0) |
| In-repo trigger | `lib/features/auth/widgets/forgot_password_sheet.dart:77` `resetPasswordForEmail` → `POST /recover` (PKCE: writes a code-challenge, `gotrue_client.dart:1113-1122`) | GoTrue mints a code of the hosted length |
| **Reader literal 1** | `forgot_password_sheet.dart:240` `maxLength: _step == _Step.email ? null : 6` (+ counter hidden `:241-245`) | digits 7–8 silently dropped — no message |
| **Reader literal 2** | `forgot_password_sheet.dart:129-130` `code.length != 6 \|\| int.tryParse(code) == null` → `'Enter the 6-digit code from your email.'` | rejects any other length before any request; `int.tryParse` also wrongly passes `+12345`, `-123456`, `0x1234` |
| Reader literal 3 | `forgot_password_sheet.dart:225` "We sent a 6-digit code to …" | states a wrong number |
| Reader literal 4 | `forgot_password_sheet.dart:253` hint `'123456'` | |
| Reader literal 5 | `lib/features/auth/screens/reset_password_screen.dart:308` (inside `_buildNoSessionState` `:284`) "…we will email you a 6-digit code…" | |
| Reader literal 6 (same class, phone) | `sign_in_screen.dart:1283` hint `'6-digit OTP'` (no length enforced: `:1321` only `isEmpty`; `auth_provider.dart:664-671` `verifyOtp` checks no length; live `sms_otp_length = 6`; Twilio not wired) | harmless today; an instance of the §2.85 class and of D1 → changed (row 4) |
| Comments repeating it | `forgot_password_sheet.dart:38, :82, :115` | |
| **Stale non-digit wording from c9e2b7 (same flow)** | `forgot_password_sheet.dart:17-20` class doc ("sends a reset link … shows a snackbar") and `:108-110` ("Could not send reset link"); `lib/features/auth/CLAUDE.md:90` pitfall title "Forgot-password sends magic-link…" | the email carries a CODE, not a link; no test pins any of these strings (grep 0) |
| Live docs repeating it | `docs/architecture/auth-detail.md:188`; `docs/audit/open_issues.md:3666` (inside OI-205, a LIVE board entry); `docs/architecture/functionality-flow.md:45` AUTH-03 still describes a reset **link**, and `:311` lists it | |
| Historical records repeating it (kept VERBATIM) | `docs/plan-reviews/email-confirm-ux.md:44`; c9e2b7 `:4,:70,:137,:171`; diagnoses/reviews generally | policy: historical records are never rewritten, only given dated CORRECTED notes where a fact was wrong |
| Consumer of the code | `forgot_password_sheet.dart:138-142` `verifyOTP(email:, token:, type: OtpType.recovery)`; success `:147-149` sets `AppRouter.isPasswordRecovery = true` (static, default false, `app_router.dart:76`), pops, `router.go('/reset')` | |

**Other OTP consumers checked:** signup confirmation is token-hash based (`auth_provider.dart:889` `verifyOTP(tokenHash:)`, `:362` `resend(type: signup)`). No 8-digit assumption exists anywhere in
`lib/ test/ integration_test/ supabase/functions/ scripts/ .claude/skills/` (only UUID/referral `{8}` regexes). **Value-semantics sweep (§4.1.5.3):** `grep -rnE "6-digit|'123456'|length != 6|maxLength: ?6" test/` → 0 hits.
Four test files reference the sheet/reset (`signout_unbinds_sdk_identity_test` scans all of `lib/` at `:61,:287`; `google_oauth_redirect_flow_test` names the sheet only in a message string `:74`;
`password_reset_redirect_flow_test.dart:54,64` reads both files but pins only the `redirectTo` literal `:71-85`; `password_recovery_code_flow_behavioral_test` imports the reset screen) — none pins a digit count; the executor re-runs all four.

## 3. Bug-history lookup (§4.1.5) and recurrence verdict

`docs/diagnoses/INDEX.md` grep (password / recovery / OTP / reset): **e9f2a4** (2026-07-22, dashboard Site URL overrides client `redirectTo`), **9f5c41**, **b7d4e2**, **c8f1d3** (link parsing / navigation),
**c9e2b7** (2026-08-06, link → typed code; the design that introduced the literal 6), **b6e4f2** (pre-auth telemetry lane), **f2b8a1** (docs asserted Google OAuth worked while no Google client existed).
`.claude/skills/debugging/bug-classes.md` **§2.45** (from e9f2a4, at `:479`) is the SAME FAMILY and already says *"Before touching any Supabase Auth email-link flow, verify the cloud dashboard… Dashboard config
overrides config.toml for all cloud environments."* — c9e2b7 changed the email flow (link → `{{ .Token }}` code) and never read the setting that decides what `{{ .Token }}` renders:
`grep -ci "otp length|mailer_otp|otp_length|digits? (long|setting)"` on the c9e2b7 doc → **0**; its tier-11 evidence is "template switched to `{{ .Token }}` (screenshot)". **Verdict: RECURRENCE** of the §2.45
family (dashboard-vs-client assumption), not of the link-parsing class. c9e2b7 `:105-106` cites "OI-100 tracks writing [the sheet tests]": OI-100..105 were **renumbered to OI-109..114** (`babea1a4`;
`docs/diagnoses/2026-08-13-oi-id-collision-renders-silently-b7e3d1.md`), so that cite is **stale, not wrong at the time**; the sheet-test OI is **OI-109** (open since 2026-08-07, "nothing — bounded work").
Harness memory dir: no auth/password feedback file exists. The diagnose-doc takes the **FULL template** (recurrence class at any tier, §4.4 rule 22) with `related_bugs: e9f2a4, c9e2b7, f2b8a1` and a `recurrence:` field.
The §1b observation is a different symptom and gets its own bug-history lookup when it is scoped.

## 4. Design

**D1 — contract.** The recovery code is the numeric `{{ .Token }}` GoTrue emails. Its length is a hosted value the client does not own. The client must accept every code GoTrue can issue and must never state a
digit count to the user (recovery code AND the phone OTP hint).

**D2 — one pure helper, digits-only, floor 6, NO ceiling.** New `lib/core/utils/recovery_code_format.dart` (beside `password_recovery_detector.dart`):
`const int kRecoveryCodeMinLength = 6;` and `bool isPlausibleRecoveryCode(String code)` = `code.length >= kRecoveryCodeMinLength && RegExp(r'^[0-9]+$').hasMatch(code)` (no trimming inside — the caller trims
once, as today; the regex is ECMAScript-style so a trailing `\n` is rejected; non-ASCII digits are rejected). Replaces `code.length != 6 || int.tryParse(code) == null`. The floor is safe because GoTrue never issues
fewer than 6 (clamp, above); there is deliberately no upper bound and no `maxLength` — an upper bound only catches 11+ digit typos and exposes a total lockout if the range ever widens (docs and source already
disagree about the range), and a `maxLength` with a hidden counter is the exact silent-drop failure of this incident. The doc comment names the clamp by file + symbol (no master line numbers); the docs cite a tag
permalink. *Alternative considered and rejected:* no client check at all — loses instant feedback for the one real client-side failure (a too-short or non-numeric typo) for no safety gain.

**D3 — sheet (`forgot_password_sheet.dart`).** `:129-130` → `if (!isPlausibleRecoveryCode(code)) { _error = 'Enter the code from your email.'; return; }`; **delete** `maxLength` `:240` and the dead
`buildCounter` `:241-245`; `:225` copy → "We sent a code to $_sentTo. Enter it here — it works on this device even if you opened the email elsewhere."; `:253` hint → `'Code from your email'`; comments `:38/:82/:115`
de-numbered; class doc `:17-20` rewritten ("…sends a recovery code to that email…"); `:108-110` error strings → "Could not send the code…" (debug and release). No digitsOnly formatter, no autofill hint.

**D4 — reset screen + phone hint.** `reset_password_screen.dart:308` → "Start again and we will email you a code you can enter right here." `sign_in_screen.dart:1283` → `hintText: 'Code from your SMS'` (copy only; row 4).

**D5 — tests (closes OI-109) — new `test/contracts/password_recovery_code_length_behavioral_test.dart` (singleton-free) + one assertion added to the existing no-session case.**
**Isolation (F1 + R2-1):** a `late SupabaseClient client` is built in **`setUp`** (real zone — NEVER inside the `testWidgets` body: constructing it there spawns a real isolate in the FakeAsync zone and `dispose()` then
never completes) as `SupabaseClient('https://fake-project.supabase.co', 'fake-anon-key', httpClient: <recording MockClient>, authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: <in-memory GotrueAsyncStorage fake with
getItem/setItem/removeItem>))`, assigned to `SupabaseService.clientOverrideForTest`, and in **`tearDown`**: `SupabaseService.clientOverrideForTest = null; await client.dispose();`. `autoRefreshToken: false` is mandatory (periodic timer,
`gotrue_client.dart:176-178`). The sheet reads only `SupabaseService.instance.client` (`forgot_password_sheet.dart:77,138`), so no `Supabase.initialize`, no shared-prefs mock, no cross-test singleton. The harness page is a
GoRouter with a button that opens `ForgotPasswordSheet.show(context)` and a placeholder `/reset` route. The recording client answers `POST …/auth/v1/recover` → 200 `{}` and `POST …/auth/v1/verify` → a session JSON
(`access_token`, `token_type: bearer`, `expires_in: 3600`, `refresh_token`, `user{id,aud,email,app_metadata,user_metadata,created_at}`; both reviewers confirmed `Session` parsing does not decode the JWT eagerly). `setUp` also sets
`AppRouter.isPasswordRecovery = false`; each success case asserts it is false BEFORE tapping. One real `flutter test` run confirms these source-derived conclusions.
 (a) pure table — accept: `123456`, `00123456` (leading zero), `12345678`, `1234567890`, `123456789012`; reject: `12345`, `''`, `+12345`, `-123456`, `0x1234`, `123 456`, `123456\n`, `12a45678`, full-width `１２３４５６`, Devanagari `१२३४५६`.
 (b) widget — 1. email step → `SEND CODE` → exactly one `POST …/recover`; the code step names the target address, and `find.textContaining('digit')` and `find.text('123456')` find nothing;
     2. for code ∈ {6, 8, 10, 12 digits, and `00123456`}: `enterText(code)` → assert the field's `controller.text == code` immediately (separates truncation from the guard) → `VERIFY CODE` → exactly one `POST …/verify` whose JSON
        body has `token == <the exact string>`, `type == 'recovery'`, `email == <address>` — **the 8-digit case is THE regression** (today's `maxLength: 6` makes the body token `123456`; both reviewers confirmed `tester.enterText` is
        subject to the TextField's formatter);
     3. `12345`, `abcdefgh`, `12a45678` → NO `/verify` request and the error `Enter the code from your email.` is shown;
     4. a good code + session-bearing `/verify` → `AppRouter.isPasswordRecovery == true` and the router lands on the placeholder `/reset`;
     5. **send failure, behavioural (M9):** with `clientOverrideForTest == null` and Supabase never initialised in this file, tapping `SEND CODE` makes `SupabaseService.instance.client` throw a non-Auth error, which reaches the
        generic `catch`, and (tests run with `kDebugMode`) the debug string renders — assert it contains `Could not send` and NOT `link`.
 (c) source pins (presence-only, supplementary; **case-sensitive, comment-stripped** — the sheet keeps the comment `// No longer "SEND RESET LINK"`): `forgot_password_sheet.dart`, `reset_password_screen.dart`, `sign_in_screen.dart` contain
     no `\d-digit` in code; the sheet contains no `'123456'`, no `reset link`, no `maxLength`.
 (d) **existing** `password_recovery_code_flow_behavioral_test.dart` NO-session case (`:79-110`): add "no text containing `digit`" (the real `ResetPasswordScreen` reads `Supabase.instance`, so it stays in that file's harness).
 **Mutation plan (§4.4 rule 21) — each confirmed APPLIED with `grep -c`, run, restored and `cmp`-checked; the diagnose-doc records what was mutated and how many tests reddened:**
 M1 re-add `maxLength: 6` → 8/10/12 cases red at the controller-text assertion · M2 restore the `length != 6` guard → red at "exact `/verify` token" · M3 re-add `maxLength: 10` → the 12-digit case red · M4 floor 6 → 7 → the 6-digit case + table row red ·
 M5a restore "6-digit" sheet copy · M5b restore hint `'123456'` · M5c restore "6-digit" reset-screen copy (red in (d)) · M6 replace the regex with `int.tryParse != null` → the sign/hex rows red · M7 delete `AppRouter.isPasswordRecovery = true` → case 4 red ·
 M8 delete `router.go('/reset')` → case 4 red · M9 restore "Could not send reset link" → case 5 red (+ source pin) · M10 restore the phone hint `'6-digit OTP'` → source pin red.
 **What the tests cannot prove:** the hosted value and a real email. That is a founder-run device check (§5 "Runtime verified on device"), ledger row 16: request a code → it has 6 digits → enter it → set a password → sign in.

**D6 — docs, registries, guards (each marked *required* by a rule or *judgment* for review).**
 - `docs/architecture/functionality-flow.md:45` AUTH-03 rewritten for the code flow (recovery email carries a numeric code, no link; the sheet accepts any all-digit code of ≥ 6 digits and states no count; `verifyOTP(recovery)` → `/reset`;
   redirect clause kept), `Verify:` → `password_reset_redirect_flow_test.dart` + the new test; `:311` checked. *(required — L25)*
 - De-number the LIVE docs: `docs/architecture/auth-detail.md:188`, `docs/audit/open_issues.md:3666` (OI-205 body), and fix `lib/features/auth/CLAUDE.md:90` ("magic-link" → "recovery email"). Historical records stay verbatim. *(required — L25/L41)*
 - **New `docs/operations/AUTH_HOSTED_SETTINGS.md`** (registry-style inventory beside `SECRET_INVENTORY.md`/`CRON_REGISTRY.md`; nothing enumerates that directory): ONLY the hosted values the client mirrors by literal or contract — `mailer_otp_length`
   (client: digits, ≥ 6, no ceiling), `mailer_templates_recovery_content` (the client expects a CODE; a link template strands users — c9e2b7), `site_url` + `uri_allow_list` (client `redirectTo = https://app.icanbefitter.com/reset`; e9f2a4),
   `sms_otp_length` (no client literal after row 4) — each with live value + date verified, reader, what drift does, and the read-only recipe (Management API `GET …/config/auth`, token per `.claude/token_path.js`, print allow-listed keys only,
   never the raw response). States plainly: **the date `mailer_otp_length` became 8 is unknown; 6 is the standing value; there is NO min-version / force-update mechanism (`grep -rliE "min_?supported|force_?update|update_required" lib supabase/functions` = 0),
   so raising the length strands every older build — the only usage signal is `client_version` in error telemetry (`error_telemetry.dart:356-408`); Supabase docs recommend longer codes, so this is a conscious security trade-off to revisit only
   together with a min-version gate.** *(judgment — the root cause was "never read the live setting")*
 - `lib/features/auth/CLAUDE.md` (budget-tracked, baseline 18261 B): ONE short pitfall row in the file's real idiom ("… Detail: `docs/operations/AUTH_HOSTED_SETTINGS.md`, bug class 2.85"), the `:90` wording fix, and the new test under "Tests pinning the rules
   here" (`:107-110`); then `dart run scripts/check_context_artifact_budget.dart` (`--record` only if a band demands it). *(required — §5 row)*
 - `supabase/config.toml` `[auth]`: a 3-line banner — local `supabase start` only; hosted values live in the dashboard and DIVERGE (e9f2a4, this batch); see `docs/operations/AUTH_HOSTED_SETTINGS.md`. *(judgment — the look-alike misled c9e2b7)*
 - `docs/diagnoses/2026-08-06-reset-link-device-bound-pkce-c9e2b7.md`: dated `⚠ CORRECTED` notes — "OI-100 renumbered to OI-109 by babea1a4 (b7e3d1)" and "the '6-digit' premise was never checked against the hosted setting — see fa621a". *(required — L41)*
 - `docs/sot_registry.yaml`: **new sibling concept** `password_recovery_code_length` (`domain: auth_profile`, `behavioral_test_path:` the new test). Why a sibling and not an extension: its WRITER is an external hosted setting and its readers differ from
   `password_recovery_session` (session gate / link detection), whose `behavioral_test_path` stays on the existing test. The external writer is stated in `description`/`class_constraints` (round 1 simulated this shape: parity, completeness, Gate 42,
   Gate 50 pass; there is no precedent for a non-file writer); `writers:` lists the in-repo trigger (`_send`); `readers:` the sheet's `_verifyCode`, the helper and the reset-screen copy. **Cross-link both ways** (as `confirm_link_token_hash_recovery`
   does) and add the hosted-length constraint sentence to `password_recovery_session`'s `class_constraints`. No `forbidden_legacy_patterns` (dropped, R2-7). The citation gate's cutoff (2026-08-01) means fa621a's `sot_registry_entry:` must resolve in the same commit. *(required — §4.5)*
 - `docs/naming_conventions.md` §8: one glossary row "recovery code". *(required — §9.3)*
 - `.claude/skills/debugging/bug-classes.md`: **new class §2.85** ("a hosted, dashboard-owned setting mirrored by a client literal that nothing reads back"), cross-linking §2.45 (unchanged); next free number confirmed (highest is 2.84) — re-derive with
   SKILL.md's `sort -n | tail -1` recipe at authoring; `.claude/skills/debugging/SKILL.md` index row + `## Changelog` entry (budget-tracked: run the budget check). *(required — §5.1)*

**D7 — process artifacts.** FULL diagnose-doc `docs/diagnoses/2026-10-03-password-reset-otp-length-mismatch-fa621a.md` (regenerate `INDEX.md`), validated by `dart run scripts/validate_diagnose_doc.dart` (avoid the substrings TBD/TODO/???/`<…>` in the frontmatter);
tier-11 `fixed_in_this_batch` evidence = the config read-back (re-read by both reviewers) plus the session-sourced before-values in §1; `impact_analysis` states 1 confirmed affected user of 5 ever, date-became-8 UNKNOWN, links §1b, notes the
**behaviour change** that pasting a whole sentence (e.g. "123456 is your AVYA…") used to be truncated to the code by `maxLength: 6` at hosted length 6 and is now rejected (invisible characters were rejected before and are now), and cites `auth_audit_logs` /
`auth_logs`. OI-109 moved to `docs/audit/closed_issues.md` + `dart run scripts/build_oi_index.dart`; commit trailers `closes-diagnose: fa621a` and `closes-oi: OI-109`; closure ledger `docs/audit/auth-recovery-code-length.closure.yaml` (Gate 40);
plan-review record `docs/plan-reviews/auth-recovery-code-length.md` (carries the §4.6 disposition); B-pass file `docs/reviews/auth-recovery-code-length-bpass.md` **plus a same-dated entry in `.claude/skills/code-review/tuning-history.md` in the same commit**
(gate: ANY `.md` under `docs/reviews/`); at close-out: the `project_*.md` retrospective update, the `MEMORY_ARCHIVED.md` step for a shipped batch, and a `feedback_*.md` for the class.

## 5. Closure ledger (terminal states; no `deferred:`; `closed_count == total_findings` — Gate 40 counts every terminal entry)

| # | Unit | Terminal state |
|---|---|---|
| 1 | helper + floor constant (D2) | closed_in_commit |
| 2 | sheet: guard, no maxLength, copy, hint, comments, stale class-doc + error strings (D3) | closed_in_commit |
| 3 | reset-screen copy (D4) | closed_in_commit |
| 4 | phone-OTP hint copy `sign_in_screen.dart:1283` (D4) | closed_in_commit |
| 5 | tests + mutation proof M1–M10, closes OI-109 (D5) | closed_in_commit |
| 6 | live-doc de-numbering: AUTH-03, auth-detail `:188`, OI-205 body, auth CLAUDE.md `:90` wording (D6) | closed_in_commit |
| 7 | `docs/operations/AUTH_HOSTED_SETTINGS.md` + auth CLAUDE.md row + Tests-pinning line + `config.toml` banner (D6) | closed_in_commit |
| 8 | c9e2b7 dated CORRECTED notes (D6) | closed_in_commit |
| 9 | SoT sibling concept + cross-links + existing concept constraint + glossary row (D6) | closed_in_commit |
| 10 | debugging skill §2.85 + index row + Changelog (D6) | closed_in_commit |
| 11 | diagnose-doc fa621a + INDEX + OI-109 board move + code-review tuning-history entry (D7) | closed_in_commit |
| 12 | hosted `mailer_otp_length` 8 → 6 (live, 2026-10-03, outside git) | closed_in_commit — `commit:` the batch's fix commit; `verification:` the independent config read-back (6, others unchanged); `notes:` the pre-change value and per-key sha256 diff are session-sourced; end-to-end NOT verified |
| 13 | paste handling in the code field | verified_clean — separators cannot come from our bare `{{ .Token }}` template; the whole-sentence-paste behaviour change is accepted and documented in fa621a |
| 14 | Google-only account gets no "use Google" hint on email sign-in | blocked_on_user — founder 2026-10-03: "leave this for now"; the premise predates §1b, so it is RE-PRESENTED for confirmation |
| 15 | NEW observation §1b: client holding a valid session was shown `/sign-in` | blocked_on_user — founder scope decision: join this batch, or own OI + own §4.1 diagnosis (recommended). Not filed as an OI yet: `scripts/mint_oi.sh` pushes a remote ref, so the founder is asked first |
| 16 | founder device check + post-merge web deploy confirmation (request code → 6 digits → enter → set password → sign in) | blocked_on_user |

`total_findings: 16`, `closed_count: 16`.

## 6. Out of scope / considered and not included

Telemetry for client-side code rejection: `auth_password_recovery_verify_failed` is already allow-listed (`supabase/functions/log-client-error/index.ts:119-123`), so no deploy would be needed — but with a floor-only check the client rejects only short or
non-numeric typos, which is not a systemic signal, and the code is a credential and must never be logged. `FilteringTextInputFormatter.digitsOnly` (a silent filter is the failure class this batch removes), `AutofillHints.oneTimeCode`, cleaning a pasted
sentence down to its leading digits. `forbidden_legacy_patterns` on the new concept (redundant with D5(c); an escaping trap; Gate 50 and Gate 8 both enforce them). A new `scripts/check_*.dart` gate or an executable that reads hosted config (CI has no
token; rule 24 would add a mutation-ledger obligation for no new protection once the reader is tolerant). Edits to root `CLAUDE.md`. Any change for §1b.

## 7. Ship path and risks

Merge to `main` is founder-owned; the web client reaches users on the next web deploy; Android only on the next `/build-apk` (founder-initiated). Shipped APKs and the current web build stay 6-only until replaced, so the hosted value stays 6 (D6 inventory).
Risk: the hosted value later set outside [6,10] → GoTrue clamps to 6 (verified), and the tolerant client has no ceiling, so the setting cannot brick it. Risk: gotrue/supabase_flutter harness quirks in D5 (isolation + setUp/tearDown order are specified; the
executor confirms with one real run). **Verification at execution (§4.12.8, the COMPLETE loop, never a subset), VPS form:** `flutter analyze lib/`; `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` (without the exclude the run writes
`test/goldens/wardroom/failures/`, a non-regenerable ignored dir that blocks `retire_worktree.dart`); `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh` (the parallel loop flakes under load; it runs Gates 8/40/42/44/50 etc.); `dart run scripts/validate_diagnose_doc.dart <doc>`;
Gate 40 on the ledger; `dart run scripts/check_context_artifact_budget.dart`; the four reference tests re-run. **After merge:** `grep -oE "^### [0-9]+\.[0-9]+" .claude/skills/debugging/bug-classes.md | sort | uniq -d` and compare with the nine pre-existing
duplicates (2.36–2.41, 2.53–2.55) — §2.85 must not appear (CLAUDE.md §4.9, last row).

## 8. Execution notes (written after the B-pass; the plan above is the reviewed v3 and is left as reviewed)

Execution mode: inline, one worktree (`auth-recovery-code-length`), as declared in the plan-review record. The reviewed design (D1-D4) survived unchanged; what execution added, all driven by the two-reviewer B-pass (`docs/reviews/auth-recovery-code-length-bpass.md`):

- **D2 grew a second function.** The plan said "no trimming inside the helper, the caller trims". The B-pass showed `trim()` is not enough (a pasted code can carry a zero-width space or a group separator the user cannot see, and the old `maxLength: 6` field only coped with a trailing one by accident), so `normalizeRecoveryCode` (every separator, control and format character removed anywhere) now sits between the text field and `isPlausibleRecoveryCode`, which is unchanged and still strict.
- **D3 grew robustness the plan did not list.** Both handlers return early while a request is in flight; the router, navigator and the sheet's own route are captured before the await; one `_fail()` helper is the only error exit and no-ops once the sheet is gone; the hand-off to `/reset` runs after the `try`, outside it, even if the sheet was dismissed, and pops only while the sheet's route is active (`ModalRoute.isActive`, not `mounted`).
- **D5 (the test) is 99 tests, not the planned handful.** The plan's harness (a per-test `SupabaseClient` through `SupabaseService.clientOverrideForTest`, built in `setUp`) worked as reviewed. Reviewer B's probes became permanent cases; the two mid-exit-animation cases are last in the file because a regression there leaks a performance-mode request into the next test.
- **The flow test had to change too.** `password_recovery_code_flow_behavioral_test.dart` failed under shuffle seeds 1, 31337, 4 and 5 (a one-shot Supabase singleton leaked a session between its two cases); it now builds a fresh singleton per case. Signing out from a later case does not work (it never returns), and re-initialising alone still restores the persisted session, so `persistSession: false` is part of the fix.
- **Mutation proof is 73 runs, not 25** (69 red, 4 equivalent mutants with reasons), generated into the diagnose-doc by script.
- **Added to the ledger** beyond the planned rows: the reviewers' findings (A1-A8, B1-B12), the reviewer-A live-gate incident (X1, X2), and three founder items (the §4.6 disposition, the unread hosted password keys, the unknown date the hosted value became 8). Two reviewer-A findings (A3a, the registry reader's method name, and A6, the stale "…or the link was opened on a different device…" copy) were first held back by an auto-mode read denial; the read worked later and both were closed in this batch (`_buildNoSessionState` now reads "This reset session has expired or is no longer valid.", pinned by the flow test, mutants MA6a-MA6c).
- **Not done, by decision:** a per-keystroke length hint, a resend control, a digit-folding step for native-script digits (no evidence anyone types them; GoTrue compares the ASCII string), and any change to §1b (its own diagnosis).
