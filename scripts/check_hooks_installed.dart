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
// STILL OPEN -- OI-104: this gate checks hook PRESENCE and IDENTITY (the
// HOOK_SOURCE anchor), not FRESHNESS. Because setup-hooks.sh installs by `cp`,
// an EDITED hook script is inert until the installer is re-run, and this gate
// reports green throughout. Content-hash comparison is OI-104's job and is
// deliberately not smuggled in here.
//
// Exit 0 = pass: every hook setup-hooks.sh installs is present and canonical.
// Exit 1 = fail: at least one is missing or is not the canonical script.

import 'dart:convert';
import 'dart:io';

const _installer = 'scripts/setup-hooks.sh';

/// Every (sourceScript, hookName) pair `setup-hooks.sh` installs, read from the
/// installer itself so a newly added hook cannot be silently unchecked.
///
/// Matches the canonical call shape:
///   install_hook "$REPO_ROOT/scripts/<src>.sh" "$HOOKS_DIR/<dst>"
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

    // IDENTITY, NOT FRESHNESS -- and the distinction is deliberate.
    //
    // setup-hooks.sh installs by `cp`, so an installed hook does NOT reference
    // its source path; it IS the source. Checking for the string
    // "scripts/<name>.sh" therefore fails on 3 of the 5 real hooks (only
    // pre-commit.sh and pre-merge-commit.sh happen to set a HOOK_SOURCE
    // anchor). That false-positive shape was caught by running this gate before
    // trusting it.
    //
    // So the anchor is the source script's own first comment line, which is
    // distinctive per hook and survives a `cp`. It answers "is the right script
    // installed here", which is this gate's question.
    //
    // It deliberately does NOT compare full content. That would be OI-104's
    // freshness check, and folding it in here would hard-FAIL every commit
    // whenever a hook script is edited but the installer has not been re-run --
    // i.e. exactly during the batch that improves a hook. Worse, the remedy
    // (`setup-hooks.sh`) writes to the COMMON git dir shared by every worktree,
    // so it would force a fix that reaches into other live sessions. A gate
    // must not make a ship-stop out of a hygiene gap (§4.13 point 6's lesson).
    final srcFile = File('scripts/${h.src}');
    String? anchor;
    if (srcFile.existsSync()) {
      for (final line in srcFile.readAsLinesSync().take(6)) {
        final t = line.trim();
        if (t.startsWith('#') && !t.startsWith('#!') && t.length > 12) {
          anchor = t;
          break;
        }
      }
    }
    // IDENTITY MISMATCH IS A WARNING, NOT A FAILURE — and that asymmetry is
    // the whole point of the gate's stated scope.
    //
    // The anchor is a line of CONTENT, so it drifts the moment anyone edits a
    // hook's header comment without re-running the installer. Review round 2
    // (2026-08-17) executed exactly that: reword line 2 of scripts/pre-commit.sh
    // and this gate hard-FAILED every commit, in every worktree, with rc=1.
    //
    // That is the deadlock this file's own header says it refuses to create.
    // The remedy it prints (`sh scripts/setup-hooks.sh`) writes to the COMMON
    // git dir shared by every concurrent session, from whatever branch happens
    // to be checked out — so a hard failure here forces a fix that reaches into
    // other people's live sessions, over a cosmetic edit. Presence is the
    // contract; sameness is OI-104's job and is warned about, not enforced.
    if (anchor != null && !content.contains(anchor)) {
      warnings.add('hooks/${h.dst} does not carry scripts/${h.src}\'s header '
          'line — it may be STALE (setup-hooks.sh installs by `cp`, so an '
          'edited script is inert until re-installed) or hand-written.');
    }
    if (anchor == null) {
      // Fail-open on a missing source, but say so: with no anchor the identity
      // check silently degrades to presence-only, and an impostor hook would
      // pass it unnoticed.
      warnings.add('scripts/${h.src} is absent, so hooks/${h.dst} was checked '
          'for PRESENCE only — its contents were not verified against anything.');
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
