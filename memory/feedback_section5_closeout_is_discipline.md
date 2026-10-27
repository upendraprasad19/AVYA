---
name: CLAUDE.md §5 close-out is discipline, not optional — never call a batch "done" before walking it
description: On 2026-10-07 I said "all done" on issue #78 while the §5 per-batch checklist (retrospective, memory, skill self-evolution, feedback) was unwalked, then called those rows optional because "nothing in CI checks them". The founder corrected it twice. §5 is part of the discipline process whether or not a gate enforces it; a batch is done only when every row is answered (done / not applicable / cannot be done here, with the reason).
metadata:
  node_type: memory
  type: feedback
---

**Rule.** A shipped batch is not "done" until the CLAUDE.md §5 checklist is walked row by row and each row is
answered `[x]` done, `n/a` with the reason, or `cannot` with the reason. "Nothing in CI checks it" is not a
reason to skip: most of §5 is self-attested by design, and the Stop hook (`scripts/batch_close_hook.dart`) exists
because the rows decay exactly at the end of a batch (2026-08-25: four rows went unwalked until the founder asked).

**Why.** 2026-10-07, issue #78. After merge + green CI + issue closed + worktree retired I reported "done" and listed
the retrospective/memory rows as something "I can add if you want". The founder: "are they not part of discipline
process?" then "without following discipline how was our work complete?" Both were right.

**How to apply.**
1. Before the words "done", "complete" or "all done": walk the §5 rows, in this order, and put the answers in the reply.
2. Never describe a discipline row as optional or as "if you want"; if a row truly cannot be done in this environment
   (e.g. the harness memory dir does not exist in a cloud container), say which and why.
3. Self-attested is not the same as optional: the answer to a row is a claim the founder will read.
4. Same family as `feedback_mistake_review_not_self_triggered.md` (the review was waiting to be asked for) and
   `feedback_no_deferrals.md`: the agent owns the close-out, the founder should never have to ask for it.
