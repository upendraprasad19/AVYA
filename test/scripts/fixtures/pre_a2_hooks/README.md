# Frozen pre-A2 git hooks

`pre-commit.sh.txt` and `pre-merge-commit.sh.txt` are the two hooks exactly as `origin/main` carried
them at `bcb1af2a` (landing A0 of the merge-conflict-treadmill plan, before landing A2): the
tracked-only `git add -u` guard is there, `build_local_indexes.dart` is not. They are what both
installed copies (the VPS and the Windows clone) held until the A2 roll-out reinstalled them. They
are stored as `.txt`, under `test/`, so nothing that scans `scripts/*.sh` (the installer, the gate
wiring checks) can mistake them for live hooks.

**Why they exist.** Hooks are COPIES, installed once per machine, and shared by every worktree of
it. For a while after A2 merges a machine runs an OLD hook against a NEW tree: the tree is
updated by `git merge --ff-only`, the hook only by `sh scripts/setup-hooks.sh`. A fixture that
runs the CURRENT hook can never see what the old one does to an A2 tree, which is how a merge
commit blocked by a "regression catalog" failure (the diagnose index is a local build product
the old hook never builds) went unseen until the B-pass.

Used by `test/scripts/pre_commit_index_add_e2e_test.dart` (cases 9h-9j) and
`test/scripts/pre_merge_commit_e2e_test.dart` (the `old hook, A2 tree` group). Do not "update"
these files: their value is that they are the OLD behaviour.
