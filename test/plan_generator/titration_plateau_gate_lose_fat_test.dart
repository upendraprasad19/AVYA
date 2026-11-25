// Generator step 4 (OI-53) gate, goal `lose_fat`: volume titration and plateau escalation over a simulated history.
// One of three per-goal files (the gate was one 3-goal file until 2026-11-24, see the lib's header). Harness, checks
// and this goal's pins: test/helpers/titration_plateau_gate_lib.dart.
@Timeout(Duration(minutes: 40))
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/titration_plateau_gate_lib.dart';

void main() => defineTitrationPlateauGate('lose_fat');
