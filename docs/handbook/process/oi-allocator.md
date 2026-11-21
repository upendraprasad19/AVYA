---
title: OI numbers are allocated, never eyeballed
category: process
source_memory: project_oi_allocator_brainstorm_inflight.md
last_reviewed: 2026-09-12
---

# OI numbers are allocated, never eyeballed

## The rule

File a new open issue with `sh scripts/mint_oi.sh "<title>"`. Never type `## OI-N` with a number you
chose by reading the board's tail. A commit that adds an unreserved number fails
(`check_oi_numbering_unique.dart`, Check C) with the exact repair command.

## Why

Sequential integers need a single allocator. This repo has many concurrent allocators — laptop
worktrees and cloud sessions — each reading its own copy of the board. Six manual renumbers
(100–105, 106–108, 128, 167–169, 177/178) proved that detection after the fact is the wrong shape:
by then the number is in pushed commit messages that are never rewritten.

## How it works

The remote branch `oi/N` is the reservation. Creating a ref that already exists is refused by
GitHub, so the second session to ask for N is told no and takes N+1. The laptop creates it through
`gh api` (no `git push`, so no pre-push hook cost); the cloud through
`git push --force-with-lease=refs/heads/oi/N:`. `git fetch` is the sync. The board remains the only
source of truth for content; `git log -1 origin/oi/N` shows who reserved it and when.

## Orphans and siblings

A reservation nobody filed (a session died between the reservation and the stub) is listed at every
SessionStart as reserved-but-unfiled, with its ledger line. Adopt it by filing `## OI-N` by hand, or
`sh scripts/mint_oi.sh --release N`. `--release` refuses a number filed on any local branch — from
your worktree a sibling worktree's in-flight number looks exactly like an orphan. A cloud branch's
in-flight number is invisible to your clone; read the ledger line before releasing. The cloud never
prunes; the next laptop mint prunes for it.

## Offline

`mint_oi.sh` refuses to mint offline. That is the point: a local-only number is a promise the
remote has not seen, and it is exactly how collisions are born. Everything else — gates, the
SessionStart line — fails open to SKIPPED or silence.

## Spec

`docs/superpowers/specs/2026-09-12-oi-allocator-design.md`
