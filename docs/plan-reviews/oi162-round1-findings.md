# OI-162 — review findings of record (rounds on the superseded plan, and on slice 1)

Written 2026-09-04 because round 1's findings existed **only in conversation**. The slice-1
reviewer could not verify the plan's claim that every finding was dispositioned, and said so —
correctly. This file is the durable record; the plan cites it rather than re-narrating it.

---

## Round 1 on `docs/audit/oi162-plan.md` (the all-at-once design) — NOT CONVERGED, 8 blocking

| # | Finding | Disposition |
|---|---|---|
| 1 | Vision cap is **20**, not 15 — migration 114 `CREATE OR REPLACE`d 111's function; the plan would have silently lowered a live PRO cap | **CLOSED** in the food-text batch (`b8f4c2`, merged `57706f74`). The number was corrected, and the underlying trap — a function's live body is the highest-numbered `CREATE OR REPLACE` — is now a root CLAUDE.md §4.9 row and is encoded in `test/helpers/migration_cap_reader.dart`. Not slice-1 work. |
| 2 | `consume_quota` moves consumption from success-time to request-time; a Gemini 502 would permanently burn a free user's lifetime quota | **SLICE 3.** It is a design question about the lifetime meters, not about the table. |
| 3 | `ai-media-proxy:687` is a SECOND call to the same counter (a display re-count) and would double-consume, turning a 5-image cap into 2 | **SLICE 3.** |
| 4 | A 9th reader exists in `lib/` — `ai_coach_repository.dart:279` `getFreeImageAnalysisCount()`, a client-side twin invisible to an EF-scoped sweep | **SLICE 3.** |
| 5 | No `REVOKE EXECUTE … FROM PUBLIC` on a `SECURITY DEFINER` RPC taking `p_user_id` — a cross-account quota-burn surface | **DISSOLVED by the slice-1 redesign.** The function is now `SECURITY INVOKER`, so there is no privilege-escalation surface to revoke against; RLS is the guard. See slice-1 §4. |
| 6 | Blast radius is catastrophic (both `verify-payment` and `delete-account` are catastrophic-tier globs) ⇒ Hermes required | **SLICE 4** owns those two files. ⚠ But see slice-1 round-1 finding A below — this nearly recurred inside slice 1 for a different reason. |
| 7 | The headline test needs `CRON_SECRET` to invoke `rolling-context`; CI has no such secret | **SLICE 3** (the prune interaction only becomes testable once a meter is migrated). |
| 8 | §7's other three tests were also unrunnable: RLS blocks the QA client from reading `usage_counters`; no test in the repo queries `pg_catalog`; the shared QA account makes windowed counters stateful across CI runs | **ANSWERED in slice-1 §6** — the test plan was rewritten around the repo's existing precedent (source-grep + recorded live check) instead of inventing coverage. |

**MAJOR/MINOR from the same round** (9 contract underspecified, 10 gate baselines wrong, 11
board scope conflict OI-153 vs OI-162, 12 the PRO image cap is inert and activating it is a
product decision, 13 no IST bucket spec, 14 column named `count`, 15-18 citation drift):
9, 10, 14 answered in slice 1; 11 closed by the board edits in `dba59b15`; 12 belongs to
OI-153 and is with the founder; 13 belongs to slice 2.

---

## Round 1 on `docs/audit/oi162-slice1-plan.md` — NOT CONVERGED, 2 blocking

**A. BLOCKING — the `platform` claim was false; migration CONTENT forces `catastrophic`.**
`scripts/blast_radius_content_rules_lib.dart` escalates any `supabase/migrations/*.sql`
containing `SECURITY DEFINER` to catastrophic regardless of path tier. The plan's
"computed not estimated" verification ran against **a path that did not exist on disk**, so
the content rule had nothing to read and failed open to `platform`. Reproduced independently:
writing a real file with the proposed body yields
`SECURITY DEFINER content forces catastrophic (path-tier was platform)`.

**B. BLOCKING — "triggers fire regardless of role EXECUTE grants" was handed to slice 2 as
settled fact and is false for nested calls.** True of the trigger function *itself*; false for
a call from inside it to a separately-revoked function. Demonstrated by execution:
`SET ROLE authenticated; INSERT …` → `permission denied for function`.

**Both are resolved by one change — `SECURITY INVOKER` instead of `SECURITY DEFINER`** —
verified live in a rolled-back transaction on `dedsavbjuwgarrhphgnl`:

| Caller | Outcome |
|---|---|
| `service_role` (the Edge Functions) | writes OK, returns `1` |
| `authenticated` (holding EXECUTE) | **BLOCKED `42501`** — `new row violates row-level security policy` |
| `anon` (holding EXECUTE) | **BLOCKED `42501`** — same |

So RLS-with-no-policy provides the protection the revokes were reaching for, without the
escalation surface (A dissolved) and without needing to revoke EXECUTE at all (B dissolved).
Probe objects confirmed dropped; `usage_counters`/`consume_quota` confirmed non-existent.

**C. MAJOR — findings 1 and 8 were never mentioned.** The cause: they existed only in
conversation. This file is the fix.

**D. MAJOR — §6 overclaimed.** "No CI behavioural test is possible" is true of *this* CI
architecture, not structurally. An ephemeral Postgres service in CI would allow it; that is
its own infrastructure project and is not proposed here, but the wording must not imply
impossibility.

**E. MINOR — `p_limit = 0` grants one free use.** The `VALUES (…, 1)` INSERT arm is not
limit-gated, so the first-ever call returns `1` rather than `-1`. Latent (no caller uses 0).

**F. MINOR — the `count` justification was wrong.** `count` reaches PostgREST via the
`Prefer: count=exact` HEADER, not a reserved query parameter; a column named `count` would not
collide. `used` is still the better name (it reads correctly in `used >= p_limit`), but the
stated reason was false.

**G. MINOR — the "Meter" citation was overweighted.** `naming_conventions.md:210` is a
category subheading in the UI-primitives section, not an entry in the reserved-domain
glossary. Avoiding the term stays reasonable; calling it "reserved" overstated it.

**H. MINOR — `search_path = public, pg_temp` diverges from repo convention.** Every existing
`SECURITY DEFINER` function here uses `public`, `public, private`, or
`public, extensions, vault, private`. Moot under `SECURITY INVOKER`, which does not take a
`search_path` hardening clause for the same reason.

### Verified clean by that round (worth not re-testing)

Postgres 17.6. `ON CONFLICT DO UPDATE … WHERE … RETURNING` with an `AS uc` alias is valid;
first call returns `1`; increments correctly; at the limit returns `-1` repeatedly with the
stored value unchanged; null/negative arguments raise. **19 concurrent calls on one key
returned exactly 1…19 — no duplicates, no gaps, no lost updates.** Migration 128 is next and
unused. The dual-revoke reasoning was correct *for a DEFINER function* (090/091 and the
`supabase/migrations/CLAUDE.md` pitfalls row document opposite no-ops). CI carries exactly
four Supabase secrets and no service-role key.
