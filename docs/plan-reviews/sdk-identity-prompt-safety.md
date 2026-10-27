---
branch: sdk-identity-prompt-safety
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3275c28e6a5b-review.md
blast_radius: platform
open_issues: OI-47, OI-51
date: 2026-07-27
---

# Plan review record — sdk-identity-prompt-safety

Closes OI-51 (device identity released on sign-out) and OI-47 (prompt-injection
sanitisation across Edge Functions). 11 commits off `99e145d2`.

## Rounds

Three independent context-blind rounds, six reviewers, none given conversation
context and all instructed to refute rather than validate.

| Round | Lenses | Outcome |
|---|---|---|
| 1 | sanitiser bypass · behavioural regression across the edited functions · the Flutter sign-out unit | 3 P0 |
| 2 | adversarial pass over round-1's corrections · completeness critic | 1 P0 (structural), 2 P1, 3 completeness gaps |
| 3 | the redesign only — forge the nonce, destroy Indic text | 2 P0 |

**Six P0s total, and four of them were defects in this batch's own fixes.** That
is the honest headline. The rounds were not a formality; they repeatedly caught
work that had already been declared done.

## Why round 3 was necessary and why there is no round 4

Rounds 1–2 were spent extending a denylist that could not be completed. Round 2
proved it structurally: every regex was built without the `u` flag, so a
character class cannot match astral code points at all — adding Unicode Tag
characters would not have worked, and each Tag character carries an ASCII byte,
making it a covert channel rather than a delimiter trick. The stated premise was
also wrong on its own terms (U+3164 is `Lo`, U+FE00–FE0F are `Mn`, not `Cf`).

So the design was replaced rather than patched (`f402938e`): per-call **nonce**
delimiters, plus a Unicode **allowlist**. Round 3 reviewed that design — a
different question from rounds 1–2, and worth asking exactly once. It found two
more P0s, both of them incomplete application of the new design rather than
flaws in it: three hand-rolled tags in `ai-proxy` that had never been migrated,
and a coverage gate blind to ES6 shorthand. Both are folded (`05861776`).

§4.12.1's split trigger was evaluated explicitly and reported to the founder
after round 2, who directed continuing as one unit rather than splitting.

## Ground-truth audit

Every claim below was verified against code or live state, not against reviewer
prose (`feedback_audit_verifier_cannot_trust_own_subagent`):

- **Tier** — `platform`, from the real diff via `blast_radius_from_diff.dart -`
  on stdin. Tracked-only returns `account` and understates it.
- **The astral gap** — reproduced with an external probe: a BMP class returns
  `false` on U+E0041 and the character survives a strip.
- **Conversation sizes** — measured, not guessed: `ai_coach_interactions` by user
  and IST day, 47 user-days, max 5,668 chars, p95 1,801, zero above 8,000.
- **Callback install sites** — `grep -rn "onStateChanged = " lib/` returns
  installs only in `app.dart` initState, which is why nulling them on sign-out
  was a regression.
- **Sign-out paths** — six, not the two originally wired; the sixth was found by
  the derived gate itself.
- **Data preservation** — Devanagari, Tamil, Hindi, Hinglish and emoji
  round-trip byte-identical under the allowlist, asserted in the suite.

## What is NOT claimed

- **Nothing server-side is live.** Every Edge Function change takes effect only
  on a separately authorised redeploy (§4.3). Deployed versions are unchanged.
- **Sanitising is mitigation, not a guarantee.** It removes the structural lever;
  no escaping makes a model immune to persuasion in prose it is asked to read.
- **`ai-proxy`'s client-settable `system_prompt`** is now sanitised, but whether
  that endpoint should accept a caller-supplied system prompt at all remains an
  open product decision, recorded in the closure YAML.

## Artifacts

- Diagnose-docs: `e7b3c5` (OI-51), `f4a9c2` (OI-47)
- Closure ledger: `docs/audit/sdk-identity-prompt-safety.closure.yaml` — 20/20 terminal
- B-pass: `docs/reviews/3275c28e6a5b-review.md`
- SoT concepts: `device_session_identity_binding`, `llm_prompt_input_sanitization`
