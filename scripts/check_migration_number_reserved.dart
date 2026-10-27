// scripts/check_migration_number_reserved.dart
//
// (A new gate takes no number — the filename is the identity, CLAUDE.md §4.4 rule 24.)
//
// OI-263 (2026-09-29): every NEW `supabase/migrations/NNN_*.sql` must carry a `mig/NNN`
// reservation minted by `scripts/mint_migration.sh`. Before this, nothing allocated migration
// numbers: the next number was read off `ls supabase/migrations/` by whoever wrote the file, and
// a number applied LIVE from an unmerged branch (148, 2026-09-28) was invisible to every other
// branch until merge.
//
// WHAT IT PROVES (read scripts/migration_number_reserved_lib.dart's header): a `mig/N` ref EXISTS
// — not that this branch owns it, and not that two branches cannot share it. The ls-remote
// fallback proves EXISTENCE only (ls-remote returns shas, not the reservation's subject).
// Same-number collisions with a DIFFERENT file already on origin/main are a hard FAIL.
// A LOCAL tracking ref is trusted as-is (it is "existence as of this clone's last sync"): a
// reservation another session `--release`d since is still honoured until the next fetch. That is
// the accepted contract — the alternative is one ls-remote on EVERY commit that adds a migration —
// and Gate 14 (`check_migrations_applied.dart`) is the merge-time backstop for a shared number.
//
// PLACEMENT: pre-commit + CI (auto-wired by the `scripts/check_*.dart` glob). VACUOUS by design at
// CI-on-push-to-main (origin/main == HEAD, so nothing is "added"). Meaningful at pre-commit and on
// a PR. Fails OPEN: any git failure, an unresolvable `origin/main`, or an unreachable remote is a
// SKIP that names which check was skipped — never a silent pass and never a wedge.
//
// Exit 0 = pass or skip. Exit 1 = violation. `--warn-only` reports but exits 0.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'migration_number_reserved_lib.dart';

Future<String?> _git(List<String> args) async {
  try {
    final r = await Process.run('git', args, stdoutEncoding: utf8, stderrEncoding: utf8);
    return r.exitCode == 0 ? r.stdout as String : null;
  } catch (_) {
    return null;
  }
}

/// ONE bounded ls-remote for the whole namespace (no `--exit-code`: an EMPTY namespace must be
/// distinguishable from a failure). null = could not answer — UNDETERMINED, never "not reserved".
Future<Set<int>?> _remoteReservations() async {
  try {
    final p = await Process.start('git', ['ls-remote', '--refs', 'origin', 'refs/heads/mig/*']);
    final out = p.stdout.transform(utf8.decoder).join();
    unawaited(p.stderr.drain<void>());
    final code = await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      p.kill();
      return -1;
    });
    if (code != 0) return null;
    return reservationNumbers(await out);
  } catch (_) {
    return null;
  }
}

Future<void> main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[migration-number-reserved WARN]' : '[migration-number-reserved]';

  // Added files: the committed range vs origin/main (three-dot) ∪ the staged set.
  // `--no-renames` so a `git mv 148_x 149_x` is A(149) + D(148) and cannot dodge the check.
  final staged = await _git(['diff', '--cached', '--no-renames', '--diff-filter=A', '--name-only']);
  if (staged == null) {
    stdout.writeln('$tag SKIP: git diff failed (no repo context).');
    exit(0);
  }
  final added = <String>{...staged.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)};
  final hasOriginMain = await _git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main']) != null;
  // A FAILED range diff (no merge base on an orphan/unrelated branch, a shallow clone) is not "no
  // committed adds" — it is "did not look". Say so, or the empty-set PASS below reads as coverage.
  var rangeFailed = false;
  if (hasOriginMain) {
    final range = await _git(['diff', '--no-renames', '--diff-filter=A', '--name-only', 'origin/main...HEAD']);
    if (range != null) {
      added.addAll(range.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty));
    } else {
      rangeFailed = true;
      stdout.writeln('$tag NOTE: SKIPPED the committed-range check — `git diff origin/main...HEAD` failed '
          '(no merge base, or a shallow clone). Only STAGED additions were checked.');
    }
  }

  final candidates = added.where(allocatedMigrationPath.hasMatch).toList()..sort();
  if (candidates.isEmpty) {
    // Early exit: no ls-remote, no ledger read — this gate runs on EVERY commit.
    stdout.writeln(rangeFailed
        ? '$tag SKIP: no STAGED allocated-number migration files, and the committed range could not be read.'
        : '$tag PASS: no added allocated-number migration files.');
    exit(0);
  }
  if (!hasOriginMain) {
    stdout.writeln('$tag SKIP: refs/remotes/origin/main not present — cannot tell published from new; '
        'checked NOTHING for ${candidates.length} added migration file(s).');
    exit(0);
  }

  final tree = await _git(['ls-tree', '--name-only', 'origin/main', 'supabase/migrations/']);
  if (tree == null) {
    stdout.writeln('$tag SKIP: could not list supabase/migrations/ at origin/main.');
    exit(0);
  }
  final mainNames = <String>{
    for (final l in tree.split('\n'))
      if (l.trim().isNotEmpty) l.trim().substring(l.trim().lastIndexOf('/') + 1),
  };

  final ledgerRaw = await _git(['show', 'origin/main:backups/applied_migrations.json']);
  final ledgerIds = <String>{};
  if (ledgerRaw != null) {
    try {
      for (final e in jsonDecode(ledgerRaw) as List<dynamic>) {
        if (e is Map && e['migration'] is String) ledgerIds.add((e['migration'] as String).trim());
      }
    } catch (_) {
      // unreadable ledger: only the letter-suffix "base published" leg loses information
    }
  }

  // Reservations: local tracking refs first (the mint updates them; sibling worktrees share .git),
  // then ONE bounded ls-remote only if a needed number is missing locally.
  final localRefs = await _git(['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/mig/']);
  var reserved = localRefs == null ? <int>{} : reservationNumbers(localRefs);
  var verdict = evaluateReservations(
    addedPaths: candidates,
    originMainNames: mainNames,
    ledgerIdsOnOriginMain: ledgerIds,
    reserved: reserved,
  );
  if (verdict.violations.any((v) => v.contains('mig/'))) {
    final remote = await _remoteReservations();
    verdict = evaluateReservations(
      addedPaths: candidates,
      originMainNames: mainNames,
      ledgerIdsOnOriginMain: ledgerIds,
      reserved: remote == null ? null : {...reserved, ...remote},
    );
  }

  for (final n in verdict.notes) {
    stdout.writeln('$tag NOTE: $n');
  }
  if (verdict.violations.isEmpty) {
    stdout.writeln('$tag PASS: ${candidates.length} added migration file(s) checked.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${verdict.violations.length} violation(s):');
  for (final v in verdict.violations) {
    stderr.writeln('  - $v');
  }
  exit(warnOnly ? 0 : 1);
}
