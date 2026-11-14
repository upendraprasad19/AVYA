// The rows the v14 injury re-check (docs/plans/2026-10-23-library-injury-recheck.md)
// leaves UNtagged: low-load or common rehab moves. Founder decision 2026-10-23
// replaced the 13-B "kept safe for variety" list (k13bKeptSafe) with this one.
//
// Imported by test/contracts/injury_recheck_v14_contract_test.dart and
// test/contracts/injury_undertag_13b_contract_test.dart. No _test.dart file
// imports another, so the list lives here.

/// Exact library names whose `injury_contraindications` must be empty.
///
/// Batch C2a (OI-460) removed seven of the original 33 names from the library (Seal Row, Sled Push, Prowler Push,
/// Thoracic Extension (Foam Roller), Thoracic Rotation, Foam Roll IT Band, Foam Roll Upper Back): a name with no row
/// has nothing to keep untagged, so they left this list with their rows.
const List<String> kV14SafePool = [
  'Machine Chest Press',
  'Floor Press',
  'Chest Squeeze Press',
  'Svend Press',
  'Face Pull',
  'Band Pull Apart',
  'Reverse Fly',
  'Bodyweight Rear Delt Raise',
  'Dumbbell Row',
  'Seated Cable Row',
  'Chest Supported Row',
  'Inverted Row',
  'TRX Row',
  'Machine High Row',
  'Machine Low Row',
  'Glute Bridge',
  'Lateral Band Walk',
  'Plank',
  'Dead Bug',
  'Pallof Press',
  'Cycling (Stationary)',
  'Assault Bike',
  'Slow Walking',
  'Arm Circles',
  'Deep Breathing',
  'Cat-Cow Stretch',
  // Batch C1 (docs/plans/2026-10-25-library-batch-c-new-rows.md, R5): the founder-approved safe-pool additions, equal to
  // safe_pool_additions in scripts/data/library_injury_additions_v15.json (asserted by library_batch_c_injury_coverage_test.dart).
  // Low-load or rehab rows only: seated and supported rows, pelvic tilts, bridges, band rear-delt work, low-impact cardio.
  'Band Hip Lift',
  'Band Reverse Fly',
  'Band Standing Rear Delt Row',
  'Barbell Incline Row',
  'Bird Dog',
  'Bodyweight Row',
  'Cable Floor Seated Wide Grip Row',
  'Cable Low Seated Row',
  'Cable Palm Rotational Row',
  'Cable Rear Delt Row',
  'Cable Seated High Row',
  'Cable Seated Single Arm Alternate Row',
  'Cable Seated Wide Grip Row',
  'Cable Straight Back Seated Row',
  'Clamshell',
  // Library Batch S1b-2: the loaded version of Glute Bridge, untagged like it.
  'Dumbbell Glute Bridge',
  'Dumbbell Incline Row',
  'Dumbbell Lying Rear Delt Row',
  'Elliptical Trainer',
  'Hug Knees to Chest',
  'Inverted Row Bent Knees',
  'Machine Alternating Narrow Grip Seated Row',
  'Machine Narrow Grip Seated Row',
  'Machine Seated Reverse Fly',
  'Machine Seated Row',
  'Pelvic Tilt',
  'Pelvic Tilt Into Bridge',
  'Resistance Band Seated Straight Back Row',
  'Standing Pelvic Tilt',
  'Supported Dumbbell Single Arm Reverse Fly',
];
