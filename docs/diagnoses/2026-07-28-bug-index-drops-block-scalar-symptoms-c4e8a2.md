---
bug_id: c4e8a2
date: 2026-07-28
batch: enforcement-infra
status: fixed
blast_radius: feature
symptom: >
  237 of 344 entries in docs/diagnoses/INDEX.md carried no symptom text — just
  a bare `>`, `>-` or `|`. CLAUDE.md §4.1.5 makes grepping that index the
  mandatory first step before any root-cause hypothesis, so ~70% of bug history
  was unsearchable by symptom while the file still looked fully populated.
concept: bug_history_index
sot_registry_entry: not_applicable
writers: >
  scripts/build_bug_index.dart main() (renders INDEX.md and now self-checks);
  scripts/bug_index_lib.dart parseFrontmatter + foldScalar + summarize +
  blockScalarRe (pure helpers, split out to be testable)
readers: >
  every agent and human following CLAUDE.md §4.1.5 greps
  docs/diagnoses/INDEX.md for a matching symptom before proposing a root cause;
  scripts/pre-commit.sh:49-54 regenerates it whenever a diagnose-doc is touched
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/bug_index_frontmatter_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  `.split('\n').first` applied to a field that may be a YAML block scalar;
  a generator that exits 0 while emitting placeholder output; treating a blank
  line as the end of a block scalar; renaming an identifier that existing
  commit messages cite
proposed_fix: >
  Fold YAML block scalars in the frontmatter parser, terminating only on a
  line that is both non-blank AND at key indentation. Replace
  `.split('\n').first` with a flatten-and-cap summary so a multi-paragraph
  symptom stays greppable on one line. Make the generator FAIL rather than emit
  an empty or placeholder symptom. Backfill `symptom:` for 8 older docs that
  carried it only as a `## Symptom` markdown section.
regression_test_planned: >
  test/contracts/bug_index_frontmatter_test.dart — 12 controls organised by
  attack: the bare-indicator bug, all six chomping variants, folded-vs-literal
  joining, the internal-blank-line truncation (the 9f4ab2 shape), scalar
  termination at the next key, a plain scalar merely starting with `>`, CRLF,
  and summarize's flatten/fallback/word-boundary behaviour.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — documentation tooling" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "INDEX.md regenerated: placeholder count 237 -> 0, empty-symptom count -> 0, 344 entries. Mutation-tested: neutering blockScalarRe regresses it to 237. Negative control: blanking one doc's symptom makes the generator exit 1 naming that file. 12/12 in test/contracts/bug_index_frontmatter_test.dart." }
impact_analysis: >
  Documentation tooling only; no product code and no user-facing behaviour. The
  change can only ADD failures: a diagnose-doc with no usable symptom now blocks
  the generator, which runs in pre-commit whenever a diagnose-doc is touched.
  INDEX.md grows 118,600 -> 188,740 bytes, which is the honest size of an index
  that actually contains its symptoms; it is a grep target, not a read-whole
  file. No bug_id was renamed — 13 of the 16 malformed ids are cited in real
  commit messages, so renaming would trade one broken link for another.
---

# The bug index had no symptoms in it

## What was wrong

`scripts/build_bug_index.dart` read the symptom with
`e['symptom']?.toString().split('\n').first` at four render sites. The
frontmatter parser stored whatever followed the key on the same line, so for the
modern convention —

```yaml
symptom: >
  Commits pushed straight to main skipped the keystone gate entirely…
```

— the stored value was the literal string `>`. Every doc written that way
indexed as `— >`. Docs using the older single-line `symptom: <text>` form were
fine, which is why the file looked half-populated rather than obviously broken.

Measured before the fix: **231** placeholders among well-formed entries, **6**
more among entries whose `bug_id` is not 6-hex, **237** total of **344**.

## Why it mattered

CLAUDE.md §4.1.5 is explicit: after observations are captured and *before*
brainstorming a root cause, grep `docs/diagnoses/INDEX.md` for a matching
symptom. For 70% of recorded bugs that grep could not match, so the mandatory
recurrence check silently returned nothing and every such bug looked new.

## The fix, and the trap inside it

Fold block scalars in the parser. The obvious rule — *consume while
more-indented than the key* — is wrong, and independent review caught it before
it shipped: a blank line is not indented, so the scalar would terminate at the
first paragraph break. **36 diagnose docs have an internal blank line in
`symptom:`.** `2026-05-15-sync-null-key-guard-9f4ab2.md` would have indexed as
"Hypothetical (defence-in-depth) — no production occurrence yet." and dropped
the data-loss description entirely — *while still passing a placeholder check*,
because the value is no longer literally `>`. A vacuous fix that measures as a
complete one.

So termination requires a line that is **non-blank AND at key indentation**, and
`summarize()` flattens paragraphs onto one line instead of taking the first.

Three supporting pieces:

- **The generator now fails closed.** It exits 1, naming each offending file,
  rather than emitting a blank symptom. This index sat 70% empty for months
  precisely because nothing ever asserted its output was meaningful.
- **8 older docs backfilled.** They carried their symptom only as a `## Symptom`
  markdown section (the 2026-05-16 convention, which also used `regression_test:`
  instead of `contract_test_path:`), so they indexed blank rather than as a
  placeholder — invisible to a placeholder-shaped search.
- **No `bug_id` was renamed.** The plan proposed normalising 16 malformed ids to
  6-hex. Grepping first showed `t1m5b0`, `s1n4c0` and `w7r4c3` appear in **10**
  commit messages and the slug-shaped ids in **3** more. Renaming would have
  broken 13 live citations to fix a cosmetic inconsistency. They are greppable
  now that they carry real symptoms, which was the actual goal.

## The method lesson

This is the same shape as the fix it sits beside: **a check that cannot fail is
not a check.** The placeholder count going to zero proves nothing on its own —
it also goes to zero under a fix that truncates every symptom to its first
sentence. What makes it evidence is the mutation test (neuter `blockScalarRe`,
watch it regress to 237) and the negative control (blank one symptom, watch the
generator exit 1 naming that file).
