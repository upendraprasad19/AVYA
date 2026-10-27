import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Hermes P1-E / P1-F. rolling-context summarize-and-deletes from
/// ai_coach_interactions. Every one of its reads on that table was unfiltered,
/// so analytics rows (channel='app_event') were:
///
///   * embedded into memory_embeddings as source_type='conversation' — 92 of
///     598 rows (15.4%) when measured 2026-08-20 — and ai-proxy concatenates
///     retrieval into the SYSTEM prompt, so app_event text reached the model;
///   * then DELETED, which silently truncates the rows migration 120's
///     holds_started_* / holders_total count over.
///
/// This is a Deno Edge Function: there is no harness in `flutter test` that can
/// execute it, so this check is structural by necessity (the presence_only
/// class). It is deliberately NOT a bare grep for the filter string — that
/// would pass while a NEW unfiltered read is added beside the filtered ones,
/// which is exactly the shape of the original defect. It ENUMERATES every
/// query on the table and requires each to carry the exclusion.
void main() {
  test('every ai_coach_interactions read in rolling-context excludes app_event',
      () {
    final raw =
        File('supabase/functions/rolling-context/index.ts').readAsStringSync();

    // Strip line and block comments first. The explanatory comments in this
    // very function name both the table and the filter, so a raw-text scan
    // would match the prose and pass with the code reverted.
    final src = raw
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    const table = '.from("ai_coach_interactions")';
    final starts = <int>[];
    for (var i = src.indexOf(table); i != -1; i = src.indexOf(table, i + 1)) {
      starts.add(i);
    }

    expect(starts.length, greaterThanOrEqualTo(3),
        reason: 'guard against the anchor silently matching nothing — if this '
            'trips, the table name or quoting changed and every assertion '
            'below became vacuous');

    for (final start in starts) {
      // A query chain runs to its terminating semicolon or comma-at-depth-0.
      // Taking the rest of the file instead would let one filtered chain
      // satisfy the assertion for an unfiltered one further down.
      final rest = src.substring(start);
      final end = rest.indexOf(';');
      final chain = end == -1 ? rest : rest.substring(0, end);

      // A pure DELETE by primary key is the one legitimate exemption: it acts
      // on ids already narrowed by the filtered fetch above it, so re-filtering
      // would be redundant rather than protective.
      if (chain.contains('.delete()')) continue;

      expect(chain.contains('.neq("channel", "app_event")'), isTrue,
          reason: 'an ai_coach_interactions query at offset $start does not '
              'exclude app_event. Analytics rows are not conversation: '
              'summarizing them poisons memory_embeddings, and deleting them '
              'truncates the migration-120 hold metrics.\nChain:\n$chain');
    }
  });

  // The above enumerates PostgREST chains in the TypeScript source. It is blind
  // by construction to a SQL-side RPC that reaches the same table without one —
  // and that blindness hid a real defect: rolling-context calls
  // get_users_with_message_count() FIRST and only falls back to the manual
  // queries on error. That RPC (migration 010:76-83) has no channel predicate,
  // and its `where summarized = false` is a permanent no-op because nothing in
  // the codebase ever writes summarized = true. So the filters on the manual
  // branch were dead code on the live path while every artifact in the batch
  // claimed all three reads were filtered.
  //
  // A structural test cannot read the RPC's SQL from here. What it CAN pin is
  // that the RPC's result is never trusted as the final candidate list.
  test('RPC candidates are re-validated, not assigned straight through', () {
    final raw =
        File('supabase/functions/rolling-context/index.ts').readAsStringSync();
    final src = raw
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    expect(src.contains('get_users_with_message_count'), isTrue,
        reason: 'anchor guard — if the RPC call is renamed or removed this test '
            'must be revisited rather than passing vacuously');

    expect(RegExp(r'usersToProcess\s*=\s*userCounts').hasMatch(src), isFalse,
        reason: 'the RPC returns a count over EVERY row including app_event, so '
            'assigning it straight to usersToProcess restores the exact defect '
            'the B-pass found: the threshold that decides who gets processed '
            'stops meaning what actually gets summarized, and users whose '
            'app_event volume alone crosses it get a full paged history fetch '
            'every night before being skipped.');

    // The re-validation must itself be filtered, or it is theatre.
    final rpcBranch = src.substring(src.indexOf('get_users_with_message_count'));
    final upToLoop = rpcBranch.substring(
        0, rpcBranch.indexOf('snapshotDate') == -1
            ? rpcBranch.length
            : rpcBranch.indexOf('snapshotDate'));
    expect(upToLoop.contains('.neq("channel", "app_event")'), isTrue,
        reason: 'the RPC candidate list must be re-counted with the app_event '
            'exclusion before the expensive per-user fetch');
  });
}
