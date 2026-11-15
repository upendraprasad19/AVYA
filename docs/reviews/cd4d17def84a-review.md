---
reviewed_at: 2026-10-08T19:00:00+05:30
staged_against: cd4d17def84a
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, rls_table_level, subscription_server_verification, onconflict_arbiter, schema_payload_parity, service_role_paths, reversibility, guard_without_its_mirror, inert_check]
findings_count: 29
verdict: accepted
---

# Review — cd4d17def84a (progress-photos-pro-server-rule, unit B1: the PRO rule for new progress photos)

Acceptance record for the catastrophic-tier gate. The staged diff is the post-apply record of migration 154 (already applied live 2026-10-07 by the founder in the dashboard SQL editor after a production always-aborting dry run) plus its diagnose-doc, closure ledger, ledger entry, SoT reader entry and bug class 2.95.

## What was reviewed, and by whom

- Rounds 1-3 (plan, six smaller-model seats), recorded in docs/plans/progress-photos-pro-server-rule.md.
- Hermes pass, seven lens seats, 24 finding records (0 P0, 0 P1, 2 P2, 22 P3): docs/audit/2026-10-06-hermes-progress-photos-pro-server-rule.md. Disclosure: those seats ran as Opus, before the founder's Sonnet-only rule of 2026-10-07.
- B-pass, five findings (B1-B5), all fixed in the contract test: section 9f of the plan. The model of that seat is not asserted here.
- Live evidence E1-E29 (docs/plans/progress-photos-pro-server-rule.evidence.md): catalog read-back after the apply, live-verify 30 of 30 ok (16 failing before), arbiter 28 of 28 ok (wrapped form), residue reads clean.

## Verdict

Accepted. The executable SQL is the migration the founder applied; its sha256 in backups/applied_migrations.json equals the file's. Residual, carried openly: S9 (the out-of-repo Telegram bot) is blocked_on_user; OI-320 and OI-321 are blocked_on_user; OI-322 is fixed in unit B2.
