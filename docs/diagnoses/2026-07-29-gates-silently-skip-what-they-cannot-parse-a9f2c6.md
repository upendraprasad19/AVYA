---
bug_id: a9f2c6
date: 2026-07-29
batch: enforcement-infra
status: fixed
blast_radius: platform
symptom: >
  Three gates shipped in this batch exited 0 while doing nothing. An OI whose
  status read `BLOCKED` vanished from OPEN_INDEX.md with no error; an OI whose
  status line read `- **Status:** CLOSED` escaped the closes-oi citation
  requirement with no output at all; and the newly generated OPEN_INDEX.md was
  missing from the euphemism gate's generated-mirror exemption, so a future
  commit could hard-fail on prose it never wrote.
concept: gate_fail_closed_discipline
sot_registry_entry: not_applicable
writers: >
  scripts/build_oi_index.dart unrecognisedStatuses + statusWord + _fieldRe;
  scripts/check_closes_oi_cited.dart unreadableStatuses;
  scripts/check_no_deferral_euphemism.dart _isGeneratedMirror;
  scripts/bug_index_lib.dart parseFrontmatter + blockScalarRe
readers: >
  scripts/pre-commit.sh (regen block + gate loop) and scripts/commit-msg.sh are
  the enforcing consumers; every agent reading docs/audit/OPEN_INDEX.md to answer
  "what is pending"
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/oi_index_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  `continue` on an unrecognised value inside a gate's parse loop; a self-check
  that validates only the entries a lossy parse already collected; a parser that
  omits what it cannot read so the caller sees nothing to enforce; a lazy
  `.*?` regex used to find a structural delimiter; two sibling parsers applying
  different rules to the same file
proposed_fix: >
  Classify every section before rendering and make unknown vocabulary a hard
  exit(1) naming the issue and line. Report any status line the closes-oi gate
  cannot read instead of omitting it. Add OPEN_INDEX.md to the generated-mirror
  exemption. Find the frontmatter's closing delimiter by scanning lines rather
  than a lazy regex, and recognise `|2`/`>2` indentation indicators.
regression_test_planned: >
  test/contracts/oi_index_test.dart (OI-68 scar group: PENDING / BLOCKED /
  REOPENED / IN-PROGESS each reported not dropped, plus sibling-parser parity on
  bolded values); test/contracts/closes_oi_cited_test.dart (colon-inside-bold and
  missing-bullet both reported); test/contracts/bug_index_frontmatter_test.dart
  (indentation indicators, embedded `---`, no-closing-delimiter). 58 total.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — enforcement tooling" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched by this commit" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "58/58 across three contract files (was 43). Negative controls both fire: injecting `- **Status**: BLOCKED` makes build_oi_index.dart exit 1 with 'OI-25 (line 78): unknown status \"BLOCKED\"'; a colon-inside-bold status makes check_closes_oi_cited.dart name the section instead of silently exempting it. Both generators re-run to an empty git diff (idempotent). flutter analyze clean." }
impact_analysis: >
  Enforcement tooling only; no product code, no user-facing behaviour. The change
  can only ADD failures — a board entry with a status word outside
  {OPEN, IN_PROGRESS, CLOSED}, or a status line in a non-canonical shape, now
  blocks instead of passing silently. That is the intended direction: the prior
  behaviour was a gate reporting success while enforcing nothing. Adding a new
  status word is a deliberate one-line edit to _openWords/_closedWords.
---

# Three gates that exited 0 while enforcing nothing

## The one that matters

`docs/audit/open_issues.md` **OI-68** is a postmortem of two prior, withdrawn
attempts at the very backlog mechanism this batch built. It carries a section
headed **"SCARS — read before re-attempting"**, and its third entry says:

> The format gate validated shape but not vocabulary … `PENDING`, `BLOCKED`,
> `REOPENED` and a one-character `IN-PROGRESS` typo all passed the gate and
> vanished from the digest.

`build_oi_index.dart` shipped:

```dart
if (!status.toUpperCase().startsWith('OPEN')) continue;
```

That is the same bug, third generation — written into the file I was actively
splitting, past a warning addressed to exactly this situation.

The self-check could not have caught it. It validated `Blocked on` / `Verified`
on entries already collected into `out`; an entry dropped by the `continue`
never enters `out`, so nothing fails and `exit(0)` fires as though the backlog
were fully accounted for.

## The other two

- **`- **Status:** CLOSED`** — colon inside the bold — made
  `parseBoardStatuses` omit the section entirely. `newlyClosed` never visited
  it, `missing` was never non-empty, and the `closes-oi` gate exited 0 **with no
  output**. A one-character formatting slip disabled the gate for that issue.
- **`OPEN_INDEX.md` was absent from `_isGeneratedMirror`** — the exemption list
  added in `3ae41073` for precisely this class. `pre-commit.sh:71` stages the
  regenerated index *before* Gate-DEU runs at `:139`, so every open entry's
  title and `Blocked on` prose re-renders as an "added" line. Those fields are
  where blocking rationale gets written, which is exactly where a banned phrase
  would legitimately appear.

Plus three parser holes: an unindented `---` inside a folded scalar truncated
the frontmatter (fields after it vanished while `symptom` still looked fine, so
the self-check stayed quiet); `|2`/`>2` indentation indicators parsed as the
literal string `"|2"`; and the two sibling parsers disagreed on `**bold**`
values, so `- **Status**: **OPEN**` vanished from the index while parsing
correctly for the other gate.

## The shape they share

Every one is a parser that **skips what it does not understand** and a caller
that reads the absence as "nothing to do". The fix is the same in each case:
enumerate everything, classify it, and make *unclassifiable* an error rather
than a silent omission.

That is also why the self-checks did not help. A check that only inspects what
the parse collected cannot see what the parse dropped — it validates the survivors
and reports health.

## The method lesson

This is the second §4.1.5 miss in this batch, both in `open_issues.md`. The first
was OI-58's recorded `Fix shape:`, which I contradicted without reading. The
second was OI-68's SCARS, which I rebuilt without reading — while editing that
file.

"I read that file today" does not discharge bug-history lookup. It is per-ISSUE,
not per-file. Before building a mechanism, grep the board for prior attempts at
*that mechanism* and read what killed them.
