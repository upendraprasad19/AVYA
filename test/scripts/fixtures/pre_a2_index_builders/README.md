# Frozen pre-A2 index builders

`build_oi_index.dart.txt`, `build_bug_index.dart.txt` and `bug_index_lib.dart.txt` are the three
scripts exactly as they were at `4c46e91d` (the merge of A0, before landing A2 of the
merge-conflict-treadmill plan). They are stored as `.txt` so `flutter analyze`, the gate loop and
the test runner never treat them as live code.

Used by `test/scripts/pre_commit_index_add_e2e_test.dart` to build a **mixed-fleet** fixture: a
worktree cut before A2 (indexes TRACKED, old builders that ignore `--lenient`, no
`scripts/build_local_indexes.dart`) running the A2 `pre-commit.sh`, which every worktree shares.
The old builder writes no stamp, so a rebuild of an unchanged tracked index is byte-identical,
which the A2 builders (their line 1 is a stat digest) cannot be. Do not "update" these files:
their value is that they are the OLD behaviour.
