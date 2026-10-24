// The rows the v14 injury re-check (docs/plans/2026-10-23-library-injury-recheck.md)
// leaves UNtagged: low-load or common rehab moves. Founder decision 2026-10-23
// replaced the 13-B "kept safe for variety" list (k13bKeptSafe) with this one.
//
// Imported by test/contracts/injury_recheck_v14_contract_test.dart and
// test/contracts/injury_undertag_13b_contract_test.dart. No _test.dart file
// imports another, so the list lives here.

/// Exact library names whose `injury_contraindications` must be empty.
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
  'Seal Row',
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
  'Sled Push',
  'Prowler Push',
  'Slow Walking',
  'Arm Circles',
  'Deep Breathing',
  'Cat-Cow Stretch',
  'Thoracic Extension (Foam Roller)',
  'Thoracic Rotation',
  'Foam Roll IT Band',
  'Foam Roll Upper Back',
];
