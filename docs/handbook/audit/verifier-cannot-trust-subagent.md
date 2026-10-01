---
title: Verifier cannot trust their own subagent's summary either
category: audit
source_memory: feedback_audit_verifier_cannot_trust_own_subagent.md
last_reviewed: 2026-05-28
---

# Verifier cannot trust their own subagent's summary either

## The rule

When verifying an audit finding via a dispatched subagent (a level of indirection from direct file read), apply the same discipline as for the original audit. The subagent's verdict is itself "unverified" until you read the file yourself.

Subagents are reliable for "does this string exist in this file?" but unreliable for "is this code correct?" — they can correctly quote a source and then reason wrong about its semantics (execution order, async control flow, race conditions, type coercion, exception propagation, scope rules, TDZ).

## How to detect the trap

You're about to fall in when:

- The subagent's verdict relies on a semantic-level claim (execution order, async behavior, scope).
- The subagent's quote is accurate but the verdict prose ("execution order is safe", "design choice", "intentional fail-open") primes you toward their conclusion.
- You're about to label a P0 finding FALSE_ALARM and ship the report without re-reading the file.

The classic "looks right because it cites the right text" trap.

## Prevention

1. **Never accept a subagent's REAL/FALSE_ALARM verdict for a semantic-level claim without reading the cited file yourself.** Quoting accuracy does not imply reasoning accuracy.

2. **For high-blast-radius findings (any P0), re-read the file with a specifically-formed question.** Form the question by inverting the subagent's verdict: if the subagent says FALSE_ALARM, ask "under what condition would this actually break?". If that can't be answered "never", re-verify.

3. **Reset the framing before reading.** Subagent prose primes you toward the subagent's verdict. Reset by asking the plain-language reverse question first.

4. **Add a step to the verification loop:** for each subagent verdict on a P0/P1, explicitly note in the report:

   > "Verifier re-read file:line and confirms verdict"

   OR

   > "Verifier disagrees with subagent — see <detail>"

   If neither, the finding is unresolved.

## Instances

When verifying a Hermes audit, three parallel Explore subagents read the cited files and labeled each finding REAL / FALSE_ALARM / PARTIAL. A verification report was almost shipped labeling F1 (razorpay-webhook variable hoisting) as **FALSE_ALARM** based on the subagent's reasoning that "both `supabaseClient` usage (line 301) and declaration (line 431) are inside the same `serve()` handler, making execution order safe."

Actual: F1 is REAL P0. The `const supabaseClient = createClient(...)` on line 431 is in temporal dead zone before line 431 executes. Line 301 is BEFORE line 431 in the same function body, runs FIRST, throws `ReferenceError: Cannot access 'supabaseClient' before initialization`. The webhook broke on every non-idempotent-skip path. Combined with F2, users could pay and never unlock PRO.

The catch came only by asking a sharper question mid-write: "could a `const` declared at line 431 be reached by an `await` at line 301 in the same function body?" Stating the question explicitly made the answer obvious (no — TDZ throws). The subagent's "execution order is safe" framing had obscured the question.

## Class rule

Every level of audit indirection requires its own verification discipline. Audit → subagent verifies → you verify subagent. Each link is a possible misread.

## References

- Related: [`live-verification.md`](live-verification.md), [`lens-methodology.md`](lens-methodology.md).
