---
bug_id: d0c352
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  CLAUDE.md §2 (Tech Stack quick-summary) line 130 claimed "21 tables".
  CLAUDE.md §7 (Database Schema header) line 380 said "46 Tables".
  AGENTS.md line 95 mirrored the §2 stale figure. §7 was bumped on
  2026-05-11 but the propagation never happened — any agent reading
  §2 first got the wrong count.
concept: doc_internal_consistency_table_count
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: CLAUDE.md, method: §2 table count corrected, line: 130 }
  - { file: AGENTS.md, method: tech stack table count corrected, line: 95 }
  - { file: scripts/check_doc_internal_consistency.dart, method: permanent gate, line: 1 }
readers:
  - { file: CLAUDE.md, method_or_widget: §7 detailed schema (canonical), line: 380 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: scripts/check_doc_internal_consistency.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — docs"
forbidden_patterns_checked:
  - { pattern: "CLAUDE.md table-count drift between §2 and §7", absent: true }
proposed_fix: |
  Updated both CLAUDE.md §2 and AGENTS.md to "46 tables" matching §7
  header (the canonical source per 2026-05-11 verification).

  New permanent gate `scripts/check_doc_internal_consistency.dart`
  pins known-drift pairs as regex captures across multiple files;
  fails if captures disagree. Initial pair set: database_table_count
  (3 locations), hive_compaction_box_count (1 location pinned, more
  can be added when a sibling claim appears).

  Lens L25 (intra-document drift) — the canonical gate this lens
  pre-creates.
regression_test_planned:
  - scripts/check_doc_internal_consistency.dart
---

# Bug d0c352 — CLAUDE.md table count drift

closes-oi: OI-35

Intra-document drift lens (L25, new). §7 was bumped 2026-05-11 from 21 → 46 but §2 quick-summary never updated. Permanent gate prevents future cases.
