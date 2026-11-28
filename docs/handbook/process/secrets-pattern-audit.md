---
title: Verify gitignore before first push of any secret artifact
category: process
source_memory: feedback_secrets_pattern_audit_before_first_push.md
last_reviewed: 2026-05-28
---

# Verify gitignore before first push of any secret artifact

## The rule

Before the first `git push` involving any new artifact that could hold a secret (`.env`, `.env.*`, `*.jks`, `*.keystore`, `key.properties`, `*.p12`, `*.pem`, `*.cert`, `*.pat`, `service-account*.json`):

1. Run `git check-ignore -v <path>` — authoritative answer on whether ANY `.gitignore` rule matches the file. Treat empty output as "NOT ignored."
2. Run `git ls-files <path>` — definitive answer on whether the file is tracked. Empty = not tracked.
3. If `check-ignore` returns empty AND the file exists on disk, add a `.gitignore` rule AT EVERY LEVEL the file could be reached (root + nested). Defense in depth.

## Never trust

- "I didn't `git add` it explicitly" — `git add -A` from a parent directory picks up everything.
- `cat .gitignore` then eyeballing it — nested `.gitignore` files in subdirs can match what root doesn't (e.g. `android/.gitignore:12 key.properties` matches `android/key.properties` even when root `.gitignore` doesn't).
- Editor auto-stage / IDE auto-commit features.

## How to apply

- **New build-machine setup:** after restoring secrets from password manager, run `dart run scripts/check_secrets_gitignored.dart` (Gate 23) before any commit.
- **New credential file creation:** same gate.
- **Pre-commit hook** runs Gate 23 automatically — never bypass via `--no-verify`.
- **Audit subagent dispatch templates:** when investigating "is X gitignored?", the brief MUST instruct the use of `git check-ignore -v` AND `git ls-files`, never just `cat .gitignore`.

## Anti-pattern (banned)

Concluding "this file is/isn't ignored" from a `cat .gitignore` of any single file. Always verify with `git check-ignore -v`.

## Instances

A tech-debt audit initially scored a finding P0 (50 points) because the audit subagent ran `cat .gitignore` at root, saw no `key.properties` rule, and assumed the keystore + plaintext password were "untracked but one accidental `git add android/` away from leaking." Verification via `git check-ignore -v` revealed `android/.gitignore:12-14` already covered it — the file was properly ignored, just at a level the subagent didn't check.

The mistake costs both ways: P0 false alarms waste audit cycles, AND a real exposure (e.g. someone adds a new credential file in a path NO `.gitignore` covers) gets missed if the audit only checks one level.

## References

- Gate: `scripts/check_secrets_gitignored.dart` (Gate 23).
- `docs/operations/SECRET_INVENTORY.md`.
- Debugging skill §2.14.
- Related: [`live-verification.md`](../audit/live-verification.md), [`verifier-cannot-trust-subagent.md`](../audit/verifier-cannot-trust-subagent.md).
