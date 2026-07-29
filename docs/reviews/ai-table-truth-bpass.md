---
branch: ai-table-truth
reviewed_at: 2026-07-28T21:40:00+05:30
range: 93f6fe41..363a6344
diff_hash: c3ac23212668
blast_radius: platform
kind: self_consistency
findings_count: 1
verdict: accepted
---

# B-pass — `ai-table-truth`

**Scope note.** §4.3: a docs/process-only ≥account change takes a *self-consistency
review of the wording* rather than an adversarial bug-hunt. This diff touches two
CLAUDE.md files and no code, schema, or Edge Function, so that is what ran. The
adversarial work on this change was the two independent context-blind rounds recorded
in `docs/plan-reviews/ai-table-truth.md`; both returned material findings and both are
folded in at `363a6344`. This pass checks the resulting text against itself and against
source.

## Finding 1 — internal contradiction between the two count statements — FIXED

- **file:line:** `supabase/functions/CLAUDE.md:23` (role-1 bullet)
- **claim:** After folding round 2, the role-1 bullet still read "twelve of the cron
  jobs in role 3 below also call Gemini (15 total)" while the AI Architecture section
  it points at had been corrected to **9 cron + 3 client-invoked**. Two numbers for the
  same fact, one of them stale, in the same file — the precise defect class this whole
  change exists to remove.
- **how found:** grepping the file for every stated count and comparing them, not by
  reading top-to-bottom.
- **status:** accepted — rewritten to "Nine of the cron jobs … as do three
  client-invoked non-proxy functions — **15 in total**", agreeing with the section it
  references.

## Checks that returned clean

- **Every count in the file is mutually consistent.** 3 proxies + 3 client-invoked +
  9 cron = 15, stated identically in both places that state it.
- **Every function named in the AI table exists** as a directory AND in the live
  project list on `dedsavbjuwgarrhphgnl`.
- **Every model attribution traces to a real constant** — `ai-proxy` MODEL_FLASH +
  MODEL_FLASH_LITE (7 call sites), `ai-media-proxy` MODEL_FLASH_LITE (3),
  `weekly-report` MODEL_PRO (2); constants resolve in `_shared/gemini.ts:40-42`.
- **The 3/3/9 split is derived, not asserted** — membership was decided by presence or
  absence of the `isAuthorizedCronCall` gate in each function, checked per function.
  All 9 cron functions have it; all 6 others have none.
- **Every documented `ai-proxy` `type` has a real client call site** —
  `nutrition_provider.dart:733`, `:1356`, `:1445`, each verified to contain that
  `type`.
- **No phantom function name survives as an assertion.** The three names
  `food-text-analysis` / `food-scan-analysis` / `cart-auditor` appear only in sentences
  that explicitly deny they are Edge Functions.
- **Cron job names vs function slugs are disambiguated** and agree with
  `docs/operations/CRON_REGISTRY.md:26,38,39`.
- **No behavioural surface touched:** the diff is two `.md` files. No Dart, no Deno, no
  SQL, no workflow. Nothing to regression-test; nothing to deploy.

## Note carried forward

The durable content of this change is not the corrected list — it is the instruction
now in the file to **derive the list by grep and never maintain it by hand**. The table
has been wrong twice, and both times the cause was a hand-written list: once by the
original author, once by me while fixing it.
