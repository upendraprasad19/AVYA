# Hosted Auth Settings the Client Mirrors

> Created for diagnose `fa621a` (2026-10-03). Registry-style inventory, beside
> `SECRET_INVENTORY.md` and `CRON_REGISTRY.md`.
>
> **Why this exists.** The Supabase project's Auth settings live in the
> dashboard, outside git, and the client mirrors some of them by LITERAL or by
> CONTRACT. Nothing in the repo could tell the two had drifted: the hosted
> project emailed 8-digit recovery codes while the app allowed 6, and a real
> user could not finish a password reset. The diagnose that built the code flow
> (`c9e2b7`) took "6-digit" from Supabase's documentation and never read the
> setting.
>
> **Scope.** ONLY hosted values the client depends on. A hosted value the client
> does not mirror does not belong here. **No secret values** — this file is
> committed and public.
>
> The rows come from searching the client for literals and contracts that mirror
> a hosted value; that is not proof nothing else does. **A client literal that
> mirrors anything configured in the dashboard gets its row here in the same
> commit.**
>
> **`supabase/config.toml` is NOT this.** Its `[auth]` block configures local
> `supabase start` only and is known to diverge from the hosted project (see the
> banner there).

Project: `dedsavbjuwgarrhphgnl` (CLAUDE.md §2a — never `krcrkntuwutvnmdnkfqf`).
Last read: **2026-10-03**, read-only, through the Management API recipe below.

| Hosted setting | Live value (2026-10-03) | What the client assumes | What drift does |
|---|---|---|---|
| `mailer_otp_length` | `6` | `lib/core/utils/recovery_code_format.dart` `isPlausibleRecoveryCode`: ASCII digits only, at least 6, **no ceiling** (a 10,000-digit paste is sent to GoTrue and refused there, by design), after `normalizeRecoveryCode` has stripped every invisible character anywhere in the typed text; `forgot_password_sheet.dart` `_verifyCode` is the only caller of both and the field has no `maxLength`. The sheet and `reset_password_screen.dart` state no digit count. | A client that fixes the length (`c9e2b7` did: `maxLength: 6` plus a `length != 6` guard) cannot enter the code the project emails once the setting differs. Today's tolerant client accepts any length GoTrue can issue (see below), so the setting can no longer brick it. **Do not raise it** — see "Raising the length" below. |
| `mailer_templates_recovery_content` | Plain-text template: `{{ .Token }} is your AVYA password reset code. Enter it in the app to set a new password. …` (no link) | The email carries a CODE and nothing else. The sheet's code step calls `verifyOTP(type: recovery)`. | A template with `{{ .ConfirmationURL }}` brings back the PKCE link bound to the device that requested the reset (`c9e2b7`): opened anywhere else, no session is created. |
| `site_url` and `uri_allow_list` | `https://app.icanbefitter.com`; the list is `https://app.icanbefitter.com/reset`, `io.supabase.icanbefitter://login-callback/`, `https://app.icanbefitter.com` | `forgot_password_sheet.dart` `_send` passes `redirectTo: 'https://app.icanbefitter.com/reset'`; `signInWithGoogle` passes the web origin or the `io.supabase.icanbefitter://login-callback/` scheme (`f2b8a1`). | A `redirectTo` that is not on the allow list is silently replaced by `site_url` (`e9f2a4`, bug class 2.45). |
| `sms_otp_length` | `6` | No literal remains: the phone-OTP field's hint says `Code from your SMS` and `verifyOtp` checks no length (`auth_provider.dart`). Phone OTP is not wired in production (functionality-flow `AUTH-04`), so this row is a placeholder against the day it is. | Same class as `mailer_otp_length` if a length ever returns to the client. |
| `mailer_templates_confirmation_content` | The signup template links to `https://app.icanbefitter.com/confirm?token_hash={{ .TokenHash }}&type=signup` | `/confirm` (`confirm_email_screen.dart`, `ConfirmLinkDetector`, the `vercel.json` redirect) reads `token_hash` and calls `verifyOTP(tokenHash:, type: OtpType.signup)`; it is not PKCE-bound. | A template that sends `{{ .ConfirmationURL }}` (PKCE-bound) or another path breaks signup confirmation the way a link template breaks recovery (`c9e2b7`); a wrong host sends users to a dead page. |
| `password_min_length` and `password_required_characters` | **Not read in this batch.** GoTrue's default minimum is 6 with no character-class requirement; the hosted values are unknown. | The password validators say "At least 6 characters" and refuse anything shorter (`sign_in_screen.dart:879` and `:997`; the B-pass review also found the new-password validator on `reset_password_screen.dart`, at about `:220`); none knows about character classes. | If the hosted minimum is raised, or classes are required, the forms accept a password GoTrue then refuses at submit. The refusal is visible (GoTrue's own message is shown), not silent like the OTP case, but the form's promise is wrong. Read both keys with the recipe below (add them to the allow-list) before relying on this row. |

## What GoTrue guarantees about the code length

`internal/conf/configuration.go`, `ApplyDefaults` (supabase/auth, identical at
tags `v2.50.0` through `v2.180.0`, which is what the round-1 plan review
compared): a `Mailer.OtpLength` that is `0`, below 6 or above 10 becomes **6**
(the same clamp applies to `Sms` and `MFA.Phone`). The generator zero-pads, so a
code is all digits, may start with `0`, and is never shorter than 6. That is the
whole basis of the client contract: **floor 6, digits only, no ceiling.**

Supabase's own pages call the email token a "6-digit" code
(customizing-email-templates, auth-email-templates, auth-email-passwordless).
"Any value between 6 and 10" appears only on the self-hosted SMS page. The docs
and the source disagree about the range, which is one reason the client sets no
upper bound.

## Raising the length

Not a client-side question; it is a rollout question.

- **The date `mailer_otp_length` became 8 is unknown.** Auth logs show one
  `POST /recover` and no `/verify` for the affected user. 6 is the standing value
  (restored 2026-10-03, founder-authorised, one key changed, read back).
- **Every build older than the `fa621a` fix stays 6-only until it is replaced:**
  the web build until the next web deploy, each installed APK until its user
  updates. Raising the length strands them.
- **There is no minimum-version / force-update mechanism** in the client or the
  Edge Functions (`grep -rliE "min_?supported|force_?update|update_required"
  lib supabase/functions` returns nothing at the time of writing). The only usage
  signal is `client_version` in error telemetry (`lib/core/services/error_telemetry.dart`).
- Supabase recommends longer codes for security. That trade-off is accepted:
  **do not raise the length until a minimum-version / force-update mechanism
  exists.**

## How to read the live values (read-only)

1. Confirm the project id is `dedsavbjuwgarrhphgnl` (CLAUDE.md §2a).
2. Token: the Personal Access Token the deploy tools use, resolved by
   `.claude/token_path.js` (root `.supabase/supabase access token.txt` on the VPS;
   see `SECRET_INVENTORY.md`). Never paste it anywhere.
3. `GET https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/config/auth`
   with `Authorization: Bearer <token>`.
4. Print **only an allow-list of keys** (the rows above). Never print the raw
   response: it carries SMTP and provider credentials.

## How to change one

A hosted change is a live production change: it needs its own explicit go
(CLAUDE.md §4.3). Dashboard → Authentication → Providers → Email, or a `PATCH`
of that single key through the Management API. Before: read the whole config and
keep a per-key digest. After: read it back and diff — only the intended key may
differ. Update this table and the dated "Last read" line in the same commit.

## History

| Date | Change | Source |
|---|---|---|
| 2026-10-03 | `mailer_otp_length` found at **8** while the client allowed 6; restored to **6**. Client made length-tolerant. First recorded inventory of these settings. | diagnose `fa621a` (`docs/diagnoses/2026-10-03-password-reset-otp-length-mismatch-fa621a.md`) |
