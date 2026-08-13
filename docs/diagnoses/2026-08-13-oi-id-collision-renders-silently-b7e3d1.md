---
bug_id: b7e3d1
date: 2026-08-13
batch: post38-auth-fixes (PR #22 merge-resolution — the collision surfaced while resolving it)
status: fixed
blast_radius: feature
symptom: >
  Six OI ids — OI-100 through OI-105 — each named TWO entirely different issues:
  one set filed on `main`, one on branch `post38-auth-fixes`. Merging the two
  boards produced NO conflict: git saw additions sitting in different regions of
  `docs/audit/open_issues.md` and combined them cleanly. `build_oi_index.dart`
  then read the corrupt board, rendered an index containing each id twice, and
  exited 0. Nothing anywhere reported a problem. The only visible symptom was a
  conflict in the GENERATED `OPEN_INDEX.md` — the symptom, not the disease, and
  one a regeneration would have "resolved" while leaving the board corrupt.
concept: oi_board_id_uniqueness
sot_registry_entry: not_applicable — process/tooling artifact; no Hive or cloud writer/reader contract
writers: >
  Any session appending a `## OI-NN` section to docs/audit/open_issues.md. There
  is NO allocator: the id is chosen by eyeballing the board's tail on whatever
  base that session happens to hold. Two sessions on two branches therefore both
  pick "the next free number" correctly and independently, and each board is
  individually duplicate-free — which is why both sides validate clean right up
  to the merge.
readers: >
  scripts/build_oi_index.dart:172 main() — renders docs/audit/OPEN_INDEX.md, one
  row per id; scripts/check_closes_oi_cited.dart — resolves `closes-oi: OI-NN`
  at commit-msg time; and every diagnose-doc, closure YAML and commit message
  that cites an OI number as a stable citation target. A duplicate silently
  repoints one session's citation at another session's issue.
hive_key_prefix: "not_applicable — no Hive involvement"
hive_key_formula: "not_applicable"
sync_methods: "not_applicable — repo-local docs tooling, no runtime sync path"
restore_methods: "not_applicable"
cloud_table: "not_applicable"
cloud_columns: "not_applicable"
contract_test_path: test/contracts/oi_index_test.dart
ist_handling: "not_applicable — no date keys or counter resets in this path"
provider_invalidations: "None — no Riverpod state involved"
telemetry_op_types: "None — build-time tooling, not a runtime path"
cross_account_guard: "not_applicable — no user-scoped data path"
forbidden_patterns_checked: >
  No raw Hive.box; no setState; no inline isPro; no secrets in the diff; no
  Container(color:+decoration:). The renumber touched only markdown/YAML docs
  plus one generator and its test.
proposed_fix: >
  TWO PARTS, and only the first is complete.
  (1) THE INSTANCE — renumber the branch's six ids to the next free block. The
  block was re-derived at execution time by sweeping EVERY local branch and
  remote ref, not by reading two boards: the ceiling moved from 105 to 106 to
  108 during the review rounds alone, so a block chosen from two refs would have
  collided a seventh time. Landed as OI-109..114.
  (2) THE CLASS — build_oi_index.dart now fails closed on duplicate ids
  (duplicateIds()). It scans ALL `## OI-NN` headers rather than parseOpenIssues'
  result, deliberately: that parser drops CLOSED entries, so an OPEN id
  colliding with a CLOSED one would have been invisible to the obvious
  implementation. A corrupt board can no longer render, so corruption cannot
  LAND — the merge commit regenerates the index and the gate fires.
  WHAT THIS DOES NOT DO, stated plainly: it gives no warning at MINT time. Two
  sessions on two branches still both validate clean in isolation. That half
  needs a cross-branch comparison against origin/main, whose placement
  (pre-commit reads a possibly-stale ref; CI only catches it post-push) is an
  open design decision recorded on OI-112. OI-112 therefore stays OPEN with its
  scope narrowed, rather than being claimed closed.
  REJECTED — a new standalone check_*.dart gate. It would carry rule 24's
  mutation-proof plus a gate_test_ledger.yaml entry and become its own unit with
  its own review cycle. Extending a generator that ALREADY fails closed four
  other ways is strictly smaller and needs no new ledger state.
  REJECTED — allocating from a high per-session reserved block. It reduces the
  odds without detecting anything, and the failure it leaves behind is the same
  silent one.
regression_test_planned: >
  test/contracts/oi_index_test.dart, group "OI-112 scar: an id minted twice must
  ERROR, never render" — 5 cases. MUTATION-PROVEN, both directions measured by
  actually running them:
  (a) rebuilding duplicateIds over parseOpenIssues (the plausible wrong
  implementation) reddens EXACTLY 1 test — the OPEN-vs-CLOSED case written to
  discriminate it. 24 pass / 1 fail.
  (b) neutering it to `return const []` reddens 4 of the 5. 21 pass / 4 fail.
  The clean-board case correctly survives (b), since an empty result is right
  there — a detail that shows the suite is not merely counting failures.
  E2E, because unit tests certify the helper and not the gate: planting a second
  `## OI-111` in the real board made `dart run scripts/build_oi_index.dart` exit
  1 naming the id; the board was restored and md5-verified byte-identical.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "scripts/build_oi_index.dart gains duplicateIds() plus a fail-closed branch in main(). flutter test test/contracts/oi_index_test.dart -> 25/25 pass. Both mutations measured red: rebuilding the check over parseOpenIssues reddens exactly 1 (the OPEN-vs-CLOSED case), neutering it reddens 4." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive access — repo-local docs tooling" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no DDL" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no data surface" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this change" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secrets in the diff" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service involved" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "no client/server contract exists here, so the analogous end-to-end check is generator WIRING rather than the helper alone — unit tests certify the helper, not the gate. Planting a second '## OI-111' in the real board made dart run scripts/build_oi_index.dart exit 1 naming the duplicate; the board was restored and md5-verified byte-identical, then regenerated clean at 39 open issues." }
impact_analysis: >
  ZERO end-user impact — no shipped code path, no runtime behaviour, no data.
  The damage is entirely to the project's own record-keeping, and it is the kind
  that compounds silently: an OI number is a citation target used by
  diagnose-docs, closure YAMLs, commit messages and `closes-oi:` enforcement, so
  a duplicate quietly repoints one session's citation at another session's
  issue. Both readers then look correct while describing different things. Six
  ids were affected in this instance; two prior instances affected three and one.
  Nothing shipped to users was ever at risk, which is precisely why nothing
  caught it — there is no crash, no failing test, and no alert to notice.
related_bugs: >
  NONE CITABLE, and that is the finding rather than an omission. §4.1.5 asks for
  prior instances in BOTH `related_bugs:` and `recurrence:`; the three earlier
  collisions enumerated below produced no diagnose-doc of their own — each was
  patched by renumbering and moved past — so there is no bug id to cite. Their
  only durable record is OI-112's board entry and the plan-review record named
  in `recurrence:`. Left explicit rather than silently empty: an empty list here
  would read as "no prior art was looked for", which is the opposite of true.
recurrence: >
  FOURTH recorded instance at least, and the largest. OI-112 records the first
  two, both 2026-08-08/09 and both on this branch: OI-96/97/98 collided and were
  renumbered to 99/100/101; within hours origin/main advanced with its own OI-99
  and they moved again to 100/101/102.
  A THIRD hit a DIFFERENT session in parallel and was found while verifying this
  merge — `docs/plan-reviews/claude-commit-merge-push-process-aae061.md:56-58`:
  "Filed as OI-105 on this branch; renumbered to OI-106 at merge time — an
  unrelated batch landed its own OI-105 on `main` first." Two sessions therefore
  hit the same class independently, within a day, neither aware of the other.
  This instance is the fourth: six ids at once, and the renumber went stale TWICE
  MORE during this change's own review rounds (ceiling 105 → 106 → 108) before
  landing at 109..114.
  The pattern across all four: a manual renumber is a patch against a moving
  target, and every previous fix was a renumber with no detector left behind.
  This is the first one that leaves a check.
---

# OI ids collide across sessions, and the board renders the corruption silently

## What made this invisible

Three things had to line up, and all three are ordinary:

1. **No allocator.** An OI number is chosen by looking at the board's tail. Two
   sessions on two branches both choose correctly, against different bases.
2. **Git cannot see it.** The two sets of additions sit in different regions of
   one file, so the three-way merge is clean. There is no conflict to resolve
   and nothing prompts a human to look.
3. **The generator iterated a List.** `build_oi_index.dart` already failed closed
   four ways — unknown status vocabulary, missing `Blocked on`/`Verified`, zero
   parsed issues, board absent — but never asked whether an id repeated. It
   rendered two rows with the same id and exited 0.

The only thing that surfaced was a conflict in the **generated** `OPEN_INDEX.md`.
That is the symptom presenting as the disease: regenerating the index "resolves"
it while the board underneath stays corrupt.

## Why the check scans headers, not parsed issues

The obvious implementation counts ids in `parseOpenIssues(content)`. It is wrong,
and wrong in the repo's most-recurrent way: that parser drops CLOSED entries
(`build_oi_index.dart:127`), so an OPEN id colliding with a CLOSED one — perfectly
possible, since closed entries stay on the board until archived — is invisible to
it. The check would have been narrower than the claim it made.

That is not a hypothetical: it is the mutation measured in (a) above, and it
reddens exactly one test, the one written for it.

## What is still open

Detection now stops corruption **landing**. It does not stop it being **created**.
Two sessions can still mint the same id and each will validate clean until the
merge. Closing that needs a cross-branch check, and where it runs is a real
decision rather than an oversight — a pre-commit gate reads a possibly-stale
`origin/main`, while CI is authoritative but only after the push. OI-112 carries
that remaining half with its scope narrowed and its evidence updated; it is
deliberately NOT claimed closed here.
