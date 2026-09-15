/// A single input combination for the V4 diagnostic harness.
class DiagnosticCombo {
  final String label;
  final String goal;
  final String equipment;
  final int daysPerWeek;
  final String experience;
  final int phase;
  final int? sessionDuration;
  final List<String> injuries;
  final List<String> weekCharacters;

  const DiagnosticCombo({
    required this.label,
    required this.goal,
    required this.equipment,
    required this.daysPerWeek,
    required this.experience,
    required this.phase,
    required this.sessionDuration,
    required this.injuries,
    required this.weekCharacters,
  });
}

class DiagnosticCombos {
  static const List<DiagnosticCombo> all = [
    // 1. Bug-repro baseline — Upendra's exact on-phone inputs
    DiagnosticCombo(
      label: 'bug-repro baseline (advanced/full_gym/build_muscle/5d/P1/sd=null)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 2. Low-tier sanity
    DiagnosticCombo(
      label: 'beginner/bodyweight/general_fitness/3d/P1',
      goal: 'general_fitness',
      equipment: 'bodyweight',
      daysPerWeek: 3,
      experience: 'beginner',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 3. Mid tier + phase 2
    DiagnosticCombo(
      label: 'intermediate/home_dumbbells/lose_fat/4d/P2',
      goal: 'lose_fat',
      equipment: 'home_dumbbells',
      daysPerWeek: 4,
      experience: 'intermediate',
      phase: 2,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 4. High phase + strength
    DiagnosticCombo(
      label: 'advanced/full_gym/strength/5d/P3',
      goal: 'strength',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 3,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 5. 6-day split (naming / slot count differences)
    DiagnosticCombo(
      label: 'advanced/basic_gym/build_muscle/6d/P1',
      goal: 'build_muscle',
      equipment: 'basic_gym',
      daysPerWeek: 6,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 6. Beginner vs Advanced isolation (same equip, different experience)
    DiagnosticCombo(
      label: 'beginner/full_gym/build_muscle/4d/P1 (vs combo 1 — tests suitable_for path)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      experience: 'beginner',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 7. VolumeFilter toggle
    DiagnosticCombo(
      label: 'advanced/full_gym/build_muscle/5d/P1/sd=60 (vs combo 1 — isolates VolumeFilter)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: 60,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 8. Real-profile replay (same inputs as combo 1 today; future: swap for
    //    dumped Hive values if they differ from synthetic assumption)
    DiagnosticCombo(
      label: 'real-profile replay (Upendra; currently same shape as combo 1)',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline'],
    ),
    // 9. Knee injury exclusion path
    DiagnosticCombo(
      label: 'advanced/full_gym/build_muscle/5d/P1/injuries=[knee]',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: ['knee'],
      weekCharacters: ['baseline'],
    ),
    // 10. All 4 week characters on bug-repro
    DiagnosticCombo(
      label: 'combo-1 inputs × all 4 week characters',
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 5,
      experience: 'advanced',
      phase: 1,
      sessionDuration: null,
      injuries: [],
      weekCharacters: ['baseline', 'overreach', 'peak', 'deload'],
    ),
  ];
}
