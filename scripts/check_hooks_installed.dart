// scripts/check_hooks_installed.dart
//
// Gate: 32
//
// Gate 32 (Tech-debt audit 2026-05-20, finding I8): assert that the repo's git
// hooks are installed -- i.e. each `.git/hooks/<name>` exists and is the
// canonical script from `scripts/`.
//
// The audit finding: `setup-hooks.sh` install is opt-in and never verified.
// Fresh clone or new contributor can commit without the discipline gates.
// CI catches it on PR but local hygiene degrades + dirty pushes hit main.
//
// 2026-08-11 (ADR-0018): this used to say "without the analyze/test gate".
// There is no commit-time analyze/test gate any more -- both moved to pre-push --
// so the thing an uninstalled hook loses is the ~75 discipline gates.
//
// 2026-08-17 -- THE LIST IS NOW DERIVED, NOT RESTATED, AND THAT IS THE POINT.
// This gate previously hardcoded `hooks/pre-commit` and checked nothing else.
// `setup-hooks.sh` installs FIVE hooks; four of them could be missing and this
// gate still printed PASS. Review round 1 found it live: `pre-merge-commit` --
// added that same day, and the ONLY thing git runs for an automatically-created
// merge commit -- was not installed, while Gate 32 reported green.
//
// That mattered more than a missing hook usually would. `pre-merge-commit` is
// the only place anywhere that catches an OI-number collision LANDING:
// `build_oi_index.dart`'s duplicate check runs from `pre-commit.sh` only when
// the board is in the staged diff, and a `--no-ff` merge never fires the local
// pre-commit hook at all. So the gate said "hooks installed", the merge ran no
// hook, and the defect the whole batch documented stayed exactly as true.
//
// The fix is structural rather than "add the fifth name": PARSE the install
// list out of `setup-hooks.sh` and require every hook it installs. A restated
// list rots the moment a sixth hook is added -- silently, and in the reassuring
// direction. This mirrors
// test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart, which
// derives the same list for tiering and is what caught the new hook missing
// from docs/blast_radius.yaml in this very batch.
//
// OI-104 (2026-09-23, discipline-v3-phase3 batch) -- ADDRESSED, not CLOSED.
// This gate now compares FULL CONTENT (scripts/<hook>.sh vs the installed
// copy), not just a header-line anchor, so it catches a body-only edit --
// exactly the 2026-08-20 recurrence (`exclude-tags golden` added mid-file,
// invisible to a 6-line anchor). Still a WARNING, not the OI's suggested
// hard-fail: setup-hooks.sh writes to the COMMON git dir shared by every
// worktree (§4.13), so failing hard here would block every worktree's next
// commit the instant any hook script changes, until someone re-runs the
// installer once from anywhere. See the per-hook loop below for the full
// reasoning. Escalating to hard-fail is a separate, explicit decision.
//
// Exit 0 = pass: every hook setup-hooks.sh installs is present (freshness
//          mismatches print as WARNINGS, not failures).
// Exit 1 = fail: at least one hook setup-hooks.sh installs is NOT PRESENT.

import 'dart:convert';
import 'dart:io';

const _installer = 'scripts/setup-hooks.sh';

/// Every (sourceScript, hookName) pair `setup-hooks.sh` installs, read from the
/// installer itself so a newly added hook cannot be silently unchecked.
///
/// Matches the canonical call shape:
///   `install_hook "$REPO_ROOT/scripts/<src>.sh" "$HOOKS_DIR/<dst>"`
List<({String src, String dst})> parseInstalledHooks(String installerSource) {
  final re = RegExp(
    r'^\s*install_hook\s+"[^"]*?scripts/([A-Za-z0-9._-]+)"\s+"[^"]*?/([A-Za-z0-9._-]+)"',
    multiLine: true,
  );
  return re
      .allMatches(installerSource)
      .map((m) => (src: m.group(1)!, dst: m.group(2)!))
      .toList();
}

String _gitHookPath(String hookName) {
  // Worktree-aware: in a git worktree `.git` is a FILE (gitdir pointer) and the
  // hooks live in the COMMON dir, so a hardcoded `.git/hooks/<name>` is absent
  // even though the hook IS installed and running (it invoked this gate).
  try {
    final r = Process.runSync(
      'git',
      ['rev-parse', '--git-path', 'hooks/$hookName'],
      stdoutEncoding: utf8,
    );
    final out = (r.stdout as String).trim();
    if (r.exitCode == 0 && out.isNotEmpty) return out;
  } catch (_) {}
  return '.git/hooks/$hookName';
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');

  final installerFile = File(_installer);
  if (!installerFile.existsSync()) {
    // Fail OPEN on a missing installer: that is an environment problem, and
    // wedging every commit over it would be worse than the gap. Say so loudly
    // rather than printing PASS -- an absent input must never read as clean.
    stderr.writeln('[Gate 32] UNDETERMINED (passing): $_installer not found, '
        'so the hook list could not be derived. This is NOT a pass.');
    exit(0);
  }

  final installerSource = installerFile.readAsStringSync();
  final hooks = parseInstalledHooks(installerSource);

  // CROSS-CHECK THE PARSE AGAINST A COUNT THAT DOES NOT DEPEND ON IT.
  //
  // "Derive, don't restate" removes the rot from the LIST — it does not remove
  // it from the PARSER, and review round 2 (2026-08-17) proved that by mutation:
  // change one install_hook line to leave its destination unquoted, delete that
  // hook, and this gate printed `PASS: all 4 hook(s) installed`. A partial parse
  // read as a complete one, which is the same reassuring-direction failure the
  // hardcoded list had.
  //
  // The independent count is simply how many times `install_hook` is invoked.
  // If the structured parse finds fewer, some call shape is not understood and
  // the gate has no idea what it is missing — so it must not answer.
  final invocationCount = RegExp(r'^\s*install_hook\s', multiLine: true)
      .allMatches(installerSource)
      .length;

  if (hooks.isEmpty) {
    stderr.writeln('[Gate 32] UNDETERMINED (passing): parsed ZERO install_hook '
        'lines from $_installer (found $invocationCount invocation(s) by a '
        'looser count). The installer exists, so either its call shape changed '
        'or this parser is stale -- either way nothing was verified. '
        'An empty input set must never report the same colour as "all present".');
    exit(0);
  }

  // A DUPLICATE line keeps the two counts equal while a DIFFERENT hook goes
  // missing — the cross-check above only catches UNDER-parsing.
  //
  // B-pass 2026-08-17 (P1): duplicate `pre-commit`'s install_hook line and drop
  // `pre-merge-commit`'s entirely, and the installer still has 5 lines parsing
  // to 5 pairs. The counts agree, the cross-check passes, and the per-hook loop
  // never looks at pre-merge-commit at all — reproducing the exact "PASS while
  // the flagship hook is not installed" failure this gate was rewritten to stop,
  // through a different corruption (a bad merge-conflict resolution that keeps
  // both sides) than the malformed-line case already closed.
  final dsts = hooks.map((h) => h.dst).toList();
  final duplicates = <String>{
    for (final d in dsts)
      if (dsts.where((x) => x == d).length > 1) d,
  };
  if (duplicates.isNotEmpty) {
    stderr.writeln('[Gate 32] UNDETERMINED (passing): $_installer installs '
        'these destination(s) more than once: ${duplicates.join(', ')}. A '
        'duplicated line keeps the invocation count correct while a DIFFERENT '
        'hook can be missing entirely, so this gate cannot tell whether the '
        'full set is installed. Most likely a merge-conflict resolution that '
        'kept both sides. Not reported as clean.');
    exit(0);
  }

  if (hooks.length != invocationCount) {
    stderr.writeln('[Gate 32] UNDETERMINED (passing): $_installer invokes '
        'install_hook $invocationCount time(s) but only ${hooks.length} could '
        'be parsed into (source, destination) pairs. The unparsed one(s) are '
        'invisible to this gate, so a hook could be missing and this would '
        'still say PASS. Fix the parser or normalise the call shape to:\n'
        '    install_hook "\$REPO_ROOT/scripts/<name>.sh" "\$HOOKS_DIR/<name>"');
    exit(0);
  }

  final failures = <String>[];
  final warnings = <String>[];
  for (final h in hooks) {
    final path = _gitHookPath(h.dst);
    final f = File(path);
    if (!f.existsSync()) {
      failures.add('hooks/${h.dst} NOT INSTALLED (expected a copy of '
          'scripts/${h.src}).');
      continue;
    }
    final content = f.readAsStringSync();

    // FRESHNESS (OI-104, 2026-09-23) -- full content comparison, the exact
    // "fix shape" the OI itself names: "compare content, not presence -- hash
    // scripts/<hook>.sh against .git/hooks/<hook> and fail on mismatch". This
    // gate previously compared only a header-line ANCHOR (see the identity
    // fallback below), which is why OI-104 RECURRED on 2026-08-20 three days
    // after the anchor check shipped: the drift that day was a body change
    // (`exclude-tags golden` added mid-file), invisible to any check that
    // only reads the first 6 lines. Two real incidents (2026-08-11, 2026-08-20)
    // both cost real debugging time because a fix looked broken while the
    // STALE INSTALLED COPY, not the fix, was at fault -- "silent-inert-gate,
    // the highest-consequence shape, because everything downstream looks
    // green" (OI-104's own words).
    //
    // STILL a WARNING, not a hard fail, deliberately diverging from the OI's
    // suggested fail-on-mismatch: setup-hooks.sh writes to the COMMON git dir
    // shared by every worktree (§4.13), so a hard fail here would force
    // EVERY worktree's next commit to block the instant any hook script
    // changes, until someone re-runs the installer once from anywhere -- a
    // hygiene gap must not become a ship-stop (§4.13 point 6's own lesson,
    // and the exact deadlock this file's history already lived through once
    // for the anchor-only version at 2026-08-17). Full-content comparison
    // closes the FALSE-NEGATIVE gap OI-104 documents (green when it should
    // warn) without opening a new false-ship-stop one; flipping to hard-fail
    // is a separate, explicit escalation decision, not bundled here.
    final srcFile = File('scripts/${h.src}');
    if (srcFile.existsSync()) {
      final srcContent = srcFile.readAsStringSync();
      if (content != srcContent) {
        warnings.add('hooks/${h.dst} content does NOT match scripts/${h.src} '
            '-- STALE installed copy (setup-hooks.sh installs by `cp`, so an '
            'edited script is inert until re-installed). Fix: '
            '`sh scripts/setup-hooks.sh`.');
      }
    } else {
      // Fail-open on a missing source, but say so: with no source the
      // freshness check silently degrades to presence-only, and an impostor
      // hook would pass it unnoticed.
      warnings.add('scripts/${h.src} is absent, so hooks/${h.dst} was checked '
          'for PRESENCE only -- its contents were not verified against anything.');
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('[Gate 32] FAIL: ${failures.length} of ${hooks.length} '
        'hook(s) not correctly installed:');
    for (final f in failures) {
      stderr.writeln('  - $f');
    }
    stderr.writeln('  Fix: run `sh scripts/setup-hooks.sh` (see CLAUDE.md §0).');
    stderr.writeln('  Note hooks live in the COMMON git dir, shared by every '
        'worktree -- installing from one worktree installs for all of them, so '
        'do it when no other session is mid-commit.');
    exit(warnOnly ? 0 : 1);
  }

  for (final w in warnings) {
    stderr.writeln('[Gate 32] WARN: $w');
  }
  stdout.writeln('[Gate 32] PASS: all ${hooks.length} hook(s) installed '
      '(${hooks.map((h) => h.dst).join(', ')}), list derived from $_installer'
      '${warnings.isEmpty ? "" : " — ${warnings.length} staleness warning(s) above"}.');
  exit(0);
}
