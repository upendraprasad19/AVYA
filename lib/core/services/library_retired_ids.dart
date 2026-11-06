// Batch C2a (OI-460) and C2b (OI-462): library ids removed from the bundle with NO `merged_ids` twin (a C2b id has a
// `replacement` row, but the importer never writes `merged_ids`, so history keyed by it is not remapped).
//
// GENERATED from scripts/data/library_batch_c2_removals.json (every `decision: remove` id, ascending); the contract test
// test/contracts/library_seed_v18_upgrade_behavioral_test.dart pins the equality. The seed prunes these from exerciseBox
// (SeedService._seedExercises, library v18). The call site subtracts every id the bundle still ships, so a bad edit
// here can never delete a row putAll has just written. This set NEVER feeds `SeedService.retiredLibraryIds`, which is
// pinned to the `merged_ids` rows by library_seed_prune_behavioral_test.dart.
library;

const Set<String> kRetiredLibraryIdsNoTwin = {
  'E075', 'E081', 'E082', 'E084', 'E101', 'E111', 'E115', 'E116',
  'E125', 'E126', 'E128', 'E130', 'E137', 'E138', 'E144', 'E146',
  'E150', 'E153', 'E154', 'E156', 'E157', 'E158', 'E160', 'E162',
  'E163', 'E164', 'E169', 'E170', 'E178', 'E179', 'E183', 'E184',
  'E192', 'E194', 'E195', 'E196', 'E197', 'E199', 'E204', 'E210',
  'E211', 'E218', 'E223', 'E227', 'E228', 'E233', 'E237', 'E243',
  'E256', 'E265', 'E279', 'E285', 'E287', 'E288', 'E293', 'E294',
};
