---
reviewed_at: 2026-07-26
branch: notif-prefs
staged_against: notif-prefs Unit B (8 files)
blast_radius: platform
reviewer: independent context-blind B-pass (Sonnet), dispatched per §4.3
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# B-pass — notif-prefs Unit B

Scope: the PRO-predicate fix in `morning-alert`, the new `_shared/subscription.ts`,
the `check_snapshot_contract.dart` parser repair, the `snapshot_contract.yaml`
corrections, the new regression test, the diagnose-doc, the closure ledger, and
the naming-conventions entry.

**No P0 or P1.** Three findings, all low-severity, **all three fixed in this same
commit** per §4.2 — they carry terminal states B8, B9 and B10 in
`docs/audit/notif-prefs-unit-b.closure.yaml`.

## What the reviewer actually did

Worth recording, because it is the reason a P3 was catchable at all: the reviewer
**executed** both regexes against probe strings rather than reading them, ran the
gate script and the test suite live, and re-queried production for every numeric
claim in the diagnose-doc instead of trusting the doc's own prose. It also
independently re-read the six other Edge Functions the diagnose-doc asserts have
correct predicates, rather than accepting that sentence.

An assertion about a regex is not verified by reading the regex. That is finding
3's whole story.

## Findings

### 1 — P2 — `fetchProUserIds` had no row cap (`_shared/subscription.ts`)

The select was unbounded. PostgREST truncates such a select at the project's
max-rows setting **with no error and no log**, so past that point PRO users would
be silently classified free — the exact silent-misclassification shape this unit
exists to remove, reintroduced one layer down. Inert today (live active-PRO count
is 0), but the same file paginates its sibling `users` fetch for precisely this
reason, so the omission was inconsistent as well as latent.

**Fixed:** explicit `.limit(_proFetchCap)` so the ceiling is ours rather than the
platform's, plus a `console.warn` canary that fires at the cap.

### 2 — P2 — the "never throws" contract held for API errors, not transport errors

The `{ data, error }` destructure converts PostgREST-level failures into a soft
`error`, which the code correctly turns into an empty set. A **transport-level**
fetch rejection (DNS, reset, timeout before any HTTP response) may reject the
promise instead — which would propagate into `morning-alert`'s single outer `try`
and abort **the whole nightly run for every user**, rather than degrade to the
free template.

The reviewer flagged this as **unverified** rather than confirmed: settling it
needs the pinned library's source, which is a remote Deno URL import. It also
noted two mitigations — the same exposure already existed for the adjacent
`users` select, and the failure is not silent (`logCronEnd` records `failed`).

**Fixed by making the answer not matter:** both exported functions now wrap the
query in `try/catch` and return the fail-safe value on a throw. The documented
contract is now literally true instead of probably true.

### 3 — P3 — the new guard's regex missed loose `==`

`[!=]==` structurally requires three characters after the property access, so it
matched `===` and `!==` but **not** a bare `==` — while the comment directly above
it claimed all three. Confirmed by running it, not by reading it.

Low impact in practice (a bare `==` violation would almost certainly also trip
the sibling `.select(...)` rule), but a comment that overstates its code is how a
guard quietly stops guarding.

**Fixed:** `[!=]?==`, and the positive control now asserts all three forms are
flagged, so a future edit that breaks either the code or the claim fails the
build.

## Lens coverage — what came back clean

- **writer_reader_drift** — `subscriptions.end_date` is `timestamptz NOT NULL`
  (verified against `information_schema`), so `.gt(..., toISOString())` is a
  same-type comparison with no truncation risk. `subscription_status` is gone
  from `morning-alert` entirely (2 remaining hits, both prose). Removing it from
  `ActiveUser` orphaned no consumer. The only surviving repo-wide references are
  legitimate **writes** in `razorpay-webhook` and `verify-payment`, correctly
  exempted. Every live figure in the diagnose-doc re-queried and matched exactly:
  9 rows / 5 `active` / **0** genuinely PRO / newest active expired 2026-07-13 /
  `users.subscription_status='pro'` = 6.
- **function_exception_swallow** — the empty-set path degrades every user to the
  free template, which is the correct fail-safe direction. Only the transport
  edge case above was open.
- **blast_radius_mismatch** — `_shared/subscription.ts` has exactly one importer.
  `morning-alert` is live at v27 and this diff is not deployed, so rollback is
  "don't merge." No path downgrades a genuinely-PRO user (live count: 0). The
  doc's claim that six other predicates are correct was **independently
  re-verified** against all six files.
- **secrets_in_tree** — clean (one self-match on the diagnose-doc's own
  `10_secrets` YAML line).
- **unawaited_no_error_sink** — clean; no fire-and-forget introduced.

## Specifically checked, no defect

- **Generate vs deliver** — `fetchProUserIds` is called only in the generation
  branch; `deliverAlerts` makes no tier decision at all, so no inconsistency
  exists. The one real trade-off is intra-run staleness (a subscription expiring
  mid-run gets one extra run of PRO copy) — deliberate, commented, and strictly
  better than the permanent staleness it replaces.
- **Gate state machine** — `flush()` always precedes the `inExtraBlock` reset at
  all three transition sites, so no entry can be mis-tagged. Ran live:
  `57 keys checked, 10 reader citations checked. OK`.
- **Probe `\b` boundary** — `morning_alert` does **not** match
  `x.morning_alert_generated_at` (underscore is a word char). A bare object-literal
  key does not match either. Noted as a design trade-off: the unrooted alternative
  is a superset of the old rooted pattern, so a short generic key added to
  `extra_server_written_keys` in future could collide within the ±15-line window.
- **Validators** — `validate_diagnose_doc.dart` PASS;
  `validate_audit_closure.dart` PASS. `snapshot_json ? 'notification_preferences'`
  re-queried live: 91 rows, **0** carrying the key — matches the doc.
- **`flutter analyze`** — 8 info-level lints, all pre-existing lines merely
  shifted by the diff. Nothing new.

## Post-fix verification

`flutter test test/contracts/pro_predicate_adoption_test.dart` → **4/4 passing**
with the widened regex and the three added equality-form assertions.

`dart run scripts/check_snapshot_contract.dart` → `57 keys checked, 10 reader
citations checked. OK`.

Deno type-checking was **not** run — `deno` is not on PATH on this machine and
there is no Deno gate in the pre-commit set, so the TS changes are verified by
reading and by the repo's existing static gates only. Stated rather than implied.
