# Mutation record - L2b Landing C (`coach-measurement-surfaces`)

Generated from `mutants2.py` and the result files of the final runs. Each mutant is a text edit applied inside a COPY of the final tree (three copies outside the repository, re-synced from the worktree before the run), with the anchor asserted to occur exactly once BEFORE any file is opened for write, run with the test files named, and restored byte for byte in a `finally`; a run that exceeded 300 seconds (a mutant that breaks many rows at once is slow to fail) was repeated with `--fail-fast`, which is marked. The runner is not in the repository, which is why this file carries the text. A compile error is not counted as a kill.

**164 mutants, 156 RED, 8 GREEN at their last run, 0 not run or unresolved.** The GREEN ones are listed under *Survivors* with a reason.

## Survivors (last run GREEN)

| id | reason |
|---|---|
| F08 available - kMinListHeight term removed | Equivalent while the header-only card stays under the cap: in compact mode the card's box is its header alone (98 dp at x2 in Ahem, 104.4 dp with the real line height, plus the 20 dp margin), so the `available - kMinListHeight` term of the cap (136 dp at the smallest body that shows the card) never binds. The floor row of the frame test asserts that sum against `kMinCardCap`, so it turns red on the day this label stops being true. |
| R06 base not rounded before the delta | Equivalent (proved, not just unobserved): the delta is `round(v - base)` with `v` a tenth and `base` either the rounded tenth or the unrounded value; the two differ by at most 0.05, so they round to the same tenth unless `v - base` is an exact tie at 0.05. A tie needs `base = t + 0.05` for a tenth `t`, i.e. `cm10 = 25.4 t + 1.27 = 1.27 (2k + 1)` to be an integer, and `127 (2k + 1) / 100` is never an integer. The production code rounds `base` first (`inchesFromCm`), the same as the displayed number. |
| R10 iterate latest.keys (equivalent candidate) | Equivalent: `latestBySiteOf` builds its map by walking `kBodyMeasurementSites`, so `latest.keys` is already in registry order and iterating it instead of the registry yields the same rows. |
| S11 hasFocus -> hasPrimaryFocus (equivalent candidate) | Equivalent while the composer's FocusNode is a leaf: `hasFocus` and `hasPrimaryFocus` differ only for a node with focused descendants, and the node the host passes is the Material `TextField`'s own (pinned by the source pin that `input_bar.dart` binds `focusNode: _inputFocusNode`; a `TextField` attaches no child focus nodes). Re-derived after the pin was added: the label lasts exactly as long as that pin. |
| S22 send added to the slot file | Equivalent by construction: the mutant appends a COMMENT (`/* sendMessage */`), and the presence-only test strips comments before it searches for `sendMessage` (that is its point: a comment may mention the word). The real mutant is S22b (a `sendMessage` member), RED. |
| S17 X excludeSemantics dropped | Equivalent: the X's child is a bare `Icon(Icons.close)` with no `semanticLabel`, so it contributes no semantics, and the `InkWell`'s tap action equals the outer node's `onTap`; with or without `excludeSemantics` the merged node is the same label, button flag and tap action. The flag is load-bearing on the chip (S16 is RED: the pill's text would be announced a second time) and defensive on the X. |
| MUT-19 Retry minimumSize zero (expected equivalent) | Equivalent for the 44 dp rule: Material's default `MaterialTapTargetSize.padded` wraps the button in a 48 dp input target, and the app theme sets no global `shrinkWrap`, so a smaller `minimumSize` does not change the size a widget test can measure (the same label as Landing B's M24). |
| MUT-28 empty state minHeight = maxHeight | Equivalent in the app: `hasBoundedHeight` is false only in an unbounded host, and the empty state is always built under a bounded height (the screen's `Scaffold` body, or the frame's `Expanded`); the guard keeps the widget total for a host that does not exist. |

## All mutants

### F01 frame OFF branch deleted - RED 4

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
if (!ref.watch(measurementsEnabledProvider)) return child;
```
after:
```dart
(removed)
```

### F02 frame OFF branch inverted - RED 32

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
if (!ref.watch(measurementsEnabledProvider)) return child;
```
after:
```dart
if (ref.watch(measurementsEnabledProvider)) return child;
```

### F03 cap removed - RED 33

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
constraints: BoxConstraints(maxHeight: cap),
```
after:
```dart
constraints: const BoxConstraints(),
```

### F04 cap = available (1.0) - RED 12

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = available;
```

### F07 cap max instead of min - RED 7

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = math.max(0.5 * available, available - kMinListHeight);
```

### F08 available - kMinListHeight term removed - GREEN(survived)

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = 0.5 * available;
```

### F09 half term removed - RED 7

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = available - kMinListHeight;
```

### F10 show: >= -> > - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
available >= kMinHostHeightForCard
```
after:
```dart
available > kMinHostHeightForCard
```

### F11 isFinite guard deleted - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
if (!available.isFinite) return child;
```
after:
```dart
(removed)
```

### F13 card narrowed - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
width: double.infinity,
```
after:
```dart
width: 200,
```

### F14 layout height from MediaQuery - RED 15

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final available = constraints.maxHeight;
```
after:
```dart
final available = MediaQuery.sizeOf(context).height;
```

### F15 kMinListHeight +8 - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinListHeight = 150;
```
after:
```dart
const double kMinListHeight = 158;
```

### F16 kMinListHeight -8 - RED 2

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinListHeight = 150;
```
after:
```dart
const double kMinListHeight = 142;
```

### F17 kMinCardCap +8 - RED 5

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinCardCap = 136;
```
after:
```dart
const double kMinCardCap = 144;
```

### F18 kMinCardCap -8 - RED 10

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinCardCap = 136;
```
after:
```dart
const double kMinCardCap = 128;
```

### F19 kMinTileWindow 56 - RED 3

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinTileWindow = 64;
```
after:
```dart
const double kMinTileWindow = 56;
```

### F20 kMinTileWindow 72 - RED 5

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinTileWindow = 64;
```
after:
```dart
const double kMinTileWindow = 72;
```

### F22 margin top 12 -> 0 - RED 6

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kCardMarginTop = 12;
```
after:
```dart
const double kCardMarginTop = 0;
```

### F23 stable shape: Expanded -> Flexible - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
Expanded(child: child),
```
after:
```dart
Flexible(child: child),
```

### C01 anon placeholder removed - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
if (ref.watch(authUserIdTokenProvider) == '<anon>') {
```
after:
```dart
if (false) {
```

### C02 token watch -> read - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
ref.watch(authUserIdTokenProvider) == '<anon>'
```
after:
```dart
ref.read(authUserIdTokenProvider) == '<anon>'
```

### C03 history watch -> read - RED 6

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final history = ref.watch(bodyMeasurementsProvider);
```
after:
```dart
final history = ref.read(bodyMeasurementsProvider);
```

### C04 post-frame invalidate removed - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
      if (!mounted) return;
      ref.invalidate(bodyMeasurementsProvider);
```
after:
```dart
      if (!mounted) return;
```

### C05 mounted guard removed - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
      if (!mounted) return;
```
after:
```dart
(removed)
```

### C06 Retry invalidates another provider - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
onRetry: () => ref.invalidate(bodyMeasurementsProvider),
```
after:
```dart
onRetry: () => ref.invalidate(measurementWriteProvider),
```

### C07 compact removed - RED 7

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final compact = bounded && cap < kMinCardCap + kMinTileWindow;
```
after:
```dart
final compact = false;
```

### C08 error/empty swapped - RED 22

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
child: history.loaded
              ? _Tiles(history: history)
```
after:
```dart
child: !history.loaded
              ? _Tiles(history: history)
```

### C09 empty history shows the tiles region - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
!compact && (!history.loaded || history.entries.isNotEmpty)
```
after:
```dart
!compact
```

### C10 clamp removed (4.0) - RED 3

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
maxScaleFactor: 2.0,
```
after:
```dart
maxScaleFactor: 4.0,
```

### C11 header Row instead of Wrap - RED 64

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
```
after:
```dart
child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
```

### C12 FittedBox neutered - RED 5

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
fit: BoxFit.scaleDown,
```
after:
```dart
fit: BoxFit.none,
```

### C14 delta green on a decrease - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
row.deltaText!,
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
```
after:
```dart
row.deltaText!,
              style: AppTypography.bodyS.copyWith(color: (row.delta ?? 0) < 0 ? AppColors.ok : AppColors.textDim),
```

### C15 delta red on an increase - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
row.deltaText!,
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
```
after:
```dart
row.deltaText!,
              style: AppTypography.bodyS.copyWith(color: (row.delta ?? 0) > 0 ? AppColors.bad : AppColors.textDim),
```

### C16 tile excludeSemantics dropped - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
return Semantics(
      excludeSemantics: true,
      label: row.semanticsLabel,
```
after:
```dart
return Semantics(
      label: row.semanticsLabel,
```

### C17 header button excludeSemantics dropped - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
button: true,
            excludeSemantics: true,
            label: MeasurementCopy.cardAddButton,
```
after:
```dart
button: true,
            label: MeasurementCopy.cardAddButton,
```

### C18 header button not a button - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
button: true,
            excludeSemantics: true,
            label: MeasurementCopy.cardAddButton,
```
after:
```dart
excludeSemantics: true,
            label: MeasurementCopy.cardAddButton,
```

### C19 unit ignored (cm) - RED 5

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
ref.read(measurementWriteProvider.notifier).preferredInches()
```
after:
```dart
false
```

### C20 unit forced inches - RED 21

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
ref.read(measurementWriteProvider.notifier).preferredInches()
```
after:
```dart
true
```

### C22 button inside the scroll region - RED 25

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
              _Header(onAdd: () => BodyMeasurementsSheet.show(context)),
              if (showBody) body,
```
after:
```dart
              if (showBody) body,
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
        Widget body = SingleChildScrollView(
          primary: false,
          child: history.loaded
```
after:
```dart
        Widget body = SingleChildScrollView(
          primary: false,
          child: history.loaded && false ? const SizedBox() : Column(children: [_Header(onAdd: () => BodyMeasurementsSheet.show(context)), history.loaded
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
                  onRetry: () => ref.invalidate(bodyMeasurementsProvider),
                ),
        );
```
after:
```dart
                  onRetry: () => ref.invalidate(bodyMeasurementsProvider),
                )]),
        );
```

### C23 Flexible removed (tiles unbounded) - RED 48

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
if (bounded) body = Flexible(child: body);
```
after:
```dart
(removed)
```

### C24 tiles two-up width wrong (full width) - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final width = (constraints.maxWidth - 8) / 2;
```
after:
```dart
final width = constraints.maxWidth;
```

### R01 delta: dates != -> == - RED 21

- tests run: `test/features/profile/measurement_card_rules_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
since.date != now.date
```
after:
```dart
since.date == now.date
```

### R02 delta sign flipped - RED 13

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
delta = roundMeasurementToTenth(value - base);
```
after:
```dart
delta = roundMeasurementToTenth(base - value);
```

### R03 delta from converted cm difference - RED 3

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
delta = roundMeasurementToTenth(value - base);
```
after:
```dart
delta = roundMeasurementToTenth(inches ? (now.cm - since.cm) / 2.54 : now.cm - since.cm);
```

### R04 delta unrounded - RED 3

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
delta = roundMeasurementToTenth(value - base);
```
after:
```dart
delta = value - base;
```

### R05 display not rounded before the delta - RED 1

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
final value = inches ? inchesFromCm(now.cm) : now.cm;
```
after:
```dart
final value = inches ? now.cm / 2.54 : now.cm;
```

### R06 base not rounded before the delta - GREEN(survived)

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
final base = inches ? inchesFromCm(since.cm) : since.cm;
```
after:
```dart
final base = inches ? since.cm / 2.54 : since.cm;
```

### R07 unit polarity inverted - RED 17

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
final value = inches ? inchesFromCm(now.cm) : now.cm;
```
after:
```dart
final value = !inches ? inchesFromCm(now.cm) : now.cm;
```

### R08 year rule via a fixed year - RED 1

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
formatShortIstDate(now.date, todayIst: todayIst)
```
after:
```dart
formatShortIstDate(now.date, todayIst: '2026-01-01')
```

### R09 first date year rule via a fixed year - RED 1

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
formatShortIstDate(firstDate, todayIst: todayIst)
```
after:
```dart
formatShortIstDate(firstDate, todayIst: '2026-01-01')
```

### R10 iterate latest.keys (equivalent candidate) - GREEN(survived)

- tests run: `test/features/profile/measurement_card_rules_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
for (final site in kBodyMeasurementSites) {
    final now = latest[site];
    if (now == null) continue;
```
after:
```dart
for (final site in latest.keys) {
    final now = latest[site];
    if (now == null) continue;
```

### R11 zero not "no change" - RED 4

- tests run: `test/features/profile/measurement_card_rules_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
if (delta == 0) return 'no change since $shortFirstDate';
```
after:
```dart
if (delta == 12345) return 'no change since $shortFirstDate';
```

### R12 plus sign dropped - RED 6

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
final sign = delta > 0 ? '+' : '';
```
after:
```dart
final sign = '';
```

### R13 semantics Up/Down swapped - RED 3

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
final word = delta > 0 ? 'Up' : 'Down';
```
after:
```dart
final word = delta > 0 ? 'Down' : 'Up';
```

### R14 semantics uses signed delta - RED 2

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
${delta.abs().toStringAsFixed(1)}
```
after:
```dart
${delta.toStringAsFixed(1)}
```

### R15 unit word swapped - RED 4

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
final unit = inches ? 'inches' : 'centimetres';
```
after:
```dart
final unit = inches ? 'centimetres' : 'inches';
```

### R16 title not uppercased - RED 9

- tests run: `test/features/profile/measurement_card_rules_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/core/copy/measurement_copy.dart`

before:
```dart
'${label.toUpperCase()} · $shortDate'
```
after:
```dart
'$label · $shortDate'
```

### H01 firstBySiteOf scans newest first - RED 18

- tests run: `test/contracts/body_measurement_readers_behavioral_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/services/health_read_service.dart`

before:
```dart
for (var i = newestFirst.length - 1; i >= 0; i--) {
```
after:
```dart
for (var i = 0; i < newestFirst.length; i++) {
```

### H02 firstBySiteOf skips the oldest - RED 20

- tests run: `test/contracts/body_measurement_readers_behavioral_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/services/health_read_service.dart`

before:
```dart
for (var i = newestFirst.length - 1; i >= 0; i--) {
```
after:
```dart
for (var i = newestFirst.length - 2; i >= 0; i--) {
```

### H03 firstBySiteOf break removed - RED 18

- tests run: `test/contracts/body_measurement_readers_behavioral_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/services/health_read_service.dart`

before:
```dart
out[site] = (cm: cm, date: newestFirst[i].date);
        break;
```
after:
```dart
out[site] = (cm: cm, date: newestFirst[i].date);
```

### H04 firstBySiteOf assert removed - RED 1

- tests run: `test/contracts/body_measurement_readers_behavioral_test.dart`
- file: `lib/core/services/health_read_service.dart`

before:
```dart
    }(), 'firstBySiteOf needs its input newest first');
```
after:
```dart
    }() || true, 'firstBySiteOf needs its input newest first');
```

### P01 entries reversed - RED 9

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
entries: history,
```
after:
```dart
entries: history.reversed.toList(),
```

### P02 entries left empty - RED 11

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
        entries: history,
```
after:
```dart
(removed)
```

### P03 loaded forced true on a failed read - RED 2

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
message: 'stage=history'));
      return const BodyMeasurementsState();
```
after:
```dart
message: 'stage=history'));
      return const BodyMeasurementsState(loaded: true);
```

### P04 preferredInches guard rethrows - RED 2

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/features/profile/body_measurements_sheet_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
message: 'stage=unit'));
      return false;
```
after:
```dart
message: 'stage=unit'));
      rethrow;
```

### P05 preferredInches device first - RED 2

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
return lastUnitInches() ?? !UserRepository.instance.getUnitsMetric();
```
after:
```dart
return !UserRepository.instance.getUnitsMetric() ? true : (lastUnitInches() ?? false);
```

### P06 preferredInches polarity inverted - RED 3

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
?? !UserRepository.instance.getUnitsMetric();
```
after:
```dart
?? UserRepository.instance.getUnitsMetric();
```

### P07 preferredInches ignores the remembered unit - RED 3

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
return lastUnitInches() ?? !UserRepository.instance.getUnitsMetric();
```
after:
```dart
return !UserRepository.instance.getUnitsMetric();
```

### P08 event name changed - RED 1

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
'measurement_unit_read_failed'
```
after:
```dart
'measurement_unit_read_failedX'
```

### P09 sheet ignores preferredInches - RED 8

- tests run: `test/features/profile/body_measurements_sheet_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/body_measurements_sheet.dart`

before:
```dart
_inches = ref.read(measurementWriteProvider.notifier).preferredInches();
```
after:
```dart
_inches = false;
```

### S01 chip flag check removed - RED 4

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (!ref.watch(measurementsEnabledProvider)) return const SizedBox.shrink();
```
after:
```dart
(removed)
```

### S02 chip flag watch -> read - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
ref.watch(measurementsEnabledProvider)
```
after:
```dart
ref.read(measurementsEnabledProvider)
```

### S03 prompt none check removed - RED 5

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (prompt == MeasurementPrompt.none) return const SizedBox.shrink();
```
after:
```dart
(removed)
```

### S04 baseline treated as none - RED 3

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (prompt == MeasurementPrompt.none) return
```
after:
```dart
if (prompt != MeasurementPrompt.due) return
```

### S05 due treated as none - RED 22

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (prompt == MeasurementPrompt.none) return
```
after:
```dart
if (prompt != MeasurementPrompt.baseline) return
```

### S06 isSending check removed - RED 7

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (isSending) return const SizedBox.shrink();
```
after:
```dart
(removed)
```

### S07 isSending inverted - RED 27

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (isSending) return const SizedBox.shrink();
```
after:
```dart
if (!isSending) return const SizedBox.shrink();
```

### S08 focus check removed - RED 5

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (inputFocusNode.hasFocus) return const SizedBox.shrink();
```
after:
```dart
(removed)
```

### S09 focus check inverted - RED 27

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (inputFocusNode.hasFocus) return const SizedBox.shrink();
```
after:
```dart
if (!inputFocusNode.hasFocus) return const SizedBox.shrink();
```

### S10 ListenableBuilder never notified - RED 5

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
listenable: inputFocusNode,
```
after:
```dart
listenable: ValueNotifier<int>(0),
```

### S11 hasFocus -> hasPrimaryFocus (equivalent candidate) - GREEN(survived)

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
if (inputFocusNode.hasFocus)
```
after:
```dart
if (inputFocusNode.hasPrimaryFocus)
```

### S12 X wired to the wrong method - RED 4

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
prompt == MeasurementPrompt.baseline
              ? notifier.skipBaseline()
              : notifier.dismiss();
```
after:
```dart
prompt == MeasurementPrompt.baseline
              ? notifier.dismiss()
              : notifier.skipBaseline();
```

### S20 target smaller than 44 - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
constraints: const BoxConstraints(minHeight: 44),
```
after:
```dart
constraints: const BoxConstraints(minHeight: 20),
```

### S22 send added to the slot file - GREEN(survived)

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
void open() => BodyMeasurementsSheet.show(context);
```
after:
```dart
void open() => BodyMeasurementsSheet.show(context); /* sendMessage */
```

### X02 chip host without the in_app condition - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
                if (channel == 'in_app')
                  MeasurementChipSlot(
```
after:
```dart
                if (true)
                  MeasurementChipSlot(
```

### X05 progress host line removed - RED 2

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
body: MeasurementsCardFrame(child: _buildBody()),
```
after:
```dart
body: _buildBody(),
```

### E01 empty: minHeight dropped - RED 1

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
```
after:
```dart
minHeight: 0,
```

### E02 empty: Center removed - RED 1

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No snapshots yet',
```
after:
```dart
child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No snapshots yet',
```

### E03 empty: scroll view removed - RED 4

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
SingleChildScrollView(
          key: const ValueKey('progress_empty_scroll'),
```
after:
```dart
Padding(
          key: const ValueKey('progress_empty_scroll'),
          padding: EdgeInsets.zero,
```

### E04 empty: never scrollable - RED 2

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
key: const ValueKey('progress_empty_scroll'),
```
after:
```dart
key: const ValueKey('progress_empty_scroll'),
          physics: const NeverScrollableScrollPhysics(),
```

### F05 cap 0.45 - RED 6

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = math.min(0.45 * available, available - kMinListHeight);
```

### F06 cap 0.35 - RED 13

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final cap = math.min(0.5 * available, available - kMinListHeight);
```
after:
```dart
final cap = math.min(0.35 * available, available - kMinListHeight);
```

### F12 shape: child alone below the threshold - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final show = !anonymous && available >= kMinHostHeightForCard;
```
after:
```dart
final show = !anonymous && available >= kMinHostHeightForCard;
        if (!show) return child;
```

### F21 unit read hoisted above the flag check - RED 2

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
if (!ref.watch(measurementsEnabledProvider)) return child;
```
after:
```dart
ref.read(measurementWriteProvider.notifier);
    if (!ref.watch(measurementsEnabledProvider)) return child;
```

- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
import '../providers/measurement_flag_provider.dart';
```
after:
```dart
import '../providers/measurement_flag_provider.dart';
import '../providers/body_measurements_provider.dart';
```

### C13 fixed-height tile - RED 65

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
              for (final row in rows)
                SizedBox(
                  width: width,
                  child: _Tile(row: row),
                ),
```
after:
```dart
              for (final row in rows)
                SizedBox(
                  width: width,
                  height: 40,
                  child: _Tile(row: row),
                ),
```

### C21 card gated on the prompt - RED 40

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final history = ref.watch(bodyMeasurementsProvider);
```
after:
```dart
final history = ref.watch(bodyMeasurementsProvider);
    if (ref.watch(measurementPromptProvider) == MeasurementPrompt.none) return const SizedBox.shrink();
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
import '../providers/body_measurements_provider.dart';
```
after:
```dart
import '../providers/body_measurements_provider.dart';
import '../providers/measurement_prompt_provider.dart';
import '../services/measurement_prompt_rules.dart';
```

### R17 date year rule inverted (both formatters) - RED 21

- tests run: `test/utils/measurement_units_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/utils/measurement_units.dart`

before:
```dart
return year == currentYear ? base : '$base $year';
```
after:
```dart
return year != currentYear ? base : '$base $year';
```

### R18 date month off by one (both formatters) - RED 21

- tests run: `test/utils/measurement_units_test.dart`, `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/core/utils/measurement_units.dart`

before:
```dart
'$day ${monthNames[month - 1]}'
```
after:
```dart
'$day ${monthNames[month % 12]}'
```

### S13 X also opens the sheet - RED 2

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
                    onTap: dismiss,
                    child: const SizedBox(
```
after:
```dart
                    onTap: () { dismiss(); open(); },
                    child: const SizedBox(
```

### S14 pill InkWell no-op - RED 2

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
child: InkWell(
                          onTap: open,
```
after:
```dart
child: InkWell(
                          onTap: () {},
```

### S15 Align removed (pill stretches to the target) - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
child: const Align(
                            alignment: Alignment.centerLeft,
```
after:
```dart
child: const Padding(
                            padding: EdgeInsets.zero,
```

### S16 chip excludeSemantics dropped - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
button: true,
                      excludeSemantics: true,
                      label: MeasurementCopy.chipLabel,
```
after:
```dart
button: true,
                      label: MeasurementCopy.chipLabel,
```

### S17 X excludeSemantics dropped - GREEN(survived)

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
button: true,
                  excludeSemantics: true,
                  label: MeasurementCopy.bannerDismissLabel,
```
after:
```dart
button: true,
                  label: MeasurementCopy.bannerDismissLabel,
```

### S18 chip not a button - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
button: true,
                      excludeSemantics: true,
                      label: MeasurementCopy.chipLabel,
```
after:
```dart
excludeSemantics: true,
                      label: MeasurementCopy.chipLabel,
```

### S19 X smaller than 44 - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
width: 44,
                      height: 44,
```
after:
```dart
width: 30,
                      height: 30,
```

### S21 dismiss error swallowed silently - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
              unawaited(
                ErrorTelemetry.logEvent(
                  'measurement_chip_dismiss_failed',
                  message: 'stage=chip_dismiss',
                ),
              );
```
after:
```dart
(removed)
```

### X01 chip host line above the quick prompts - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
                if (channel == 'in_app')
                  MeasurementChipSlot(
                    inputFocusNode: _inputFocusNode,
                    isSending: isSending,
                    onShown: (height) =>
                        keepBottomAfterChip(_scrollController, height),
                  ),
```
after:
```dart
(removed)
```

- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
                if (channel == 'in_app' && !isSending && messages.length <= 1)
                  _buildQuickPrompts(),
```
after:
```dart
                if (channel == 'in_app')
                  MeasurementChipSlot(
                    inputFocusNode: _inputFocusNode,
                    isSending: isSending,
                    onShown: (height) =>
                        keepBottomAfterChip(_scrollController, height),
                  ),
                if (channel == 'in_app' && !isSending && messages.length <= 1)
                  _buildQuickPrompts(),
```

### X03 chip host isSending: false - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
isSending: isSending,
                    onShown:
```
after:
```dart
isSending: false,
                    onShown:
```

### X04 chip host line removed - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
                if (channel == 'in_app')
                  MeasurementChipSlot(
                    inputFocusNode: _inputFocusNode,
                    isSending: isSending,
                    onShown: (height) =>
                        keepBottomAfterChip(_scrollController, height),
                  ),
```
after:
```dart
(removed)
```

### X05 chip host onShown removed - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/screen.dart`

before:
```dart
                    onShown: (height) =>
                        keepBottomAfterChip(_scrollController, height),
```
after:
```dart
(removed)
```

### MUT-1 frame watch -> read - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
if (!ref.watch(measurementsEnabledProvider)) return child;
```
after:
```dart
if (!ref.read(measurementsEnabledProvider)) return child;
```

### MUT-2 show threshold -0.05 - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
available >= kMinHostHeightForCard;
```
after:
```dart
available >= kMinHostHeightForCard - 0.05;
```

### MUT-3 compact threshold -0.04 - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
cap < kMinCardCap + kMinTileWindow;
```
after:
```dart
cap < kMinCardCap + kMinTileWindow - 0.04;
```

### MUT-4 card padding 24 - RED 11

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
```
after:
```dart
padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
```

### MUT-5 border width 8 - RED 10

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
border: Border.all(color: AppColors.border),
```
after:
```dart
border: Border.all(color: AppColors.border, width: 8),
```

### MUT-6 button minHeight 64 - RED 8

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
```
after:
```dart
constraints: const BoxConstraints(minHeight: 64, minWidth: 48),
```

### MUT-7 header runSpacing 18 - RED 8

- tests run: `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
        runSpacing: 4,
```
after:
```dart
        runSpacing: 18,
```

### MUT-8 header widthFactor removed - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
                  widthFactor: 1,
```
after:
```dart
(removed)
```

### MUT-9 header alignment start - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
alignment: WrapAlignment.spaceBetween,
```
after:
```dart
alignment: WrapAlignment.start,
```

### MUT-10 card column cross start - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
crossAxisAlignment: CrossAxisAlignment.stretch,
```
after:
```dart
crossAxisAlignment: CrossAxisAlignment.start,
```

### MUT-11 header cross start - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
crossAxisAlignment: WrapCrossAlignment.center,
```
after:
```dart
crossAxisAlignment: WrapCrossAlignment.start,
```

### MUT-12 value colour ok - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
style: AppTypography.titleS.copyWith(color: AppColors.textPrimary),
```
after:
```dart
style: AppTypography.titleS.copyWith(color: AppColors.ok),
```

### MUT-13 title colour bad - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
```
after:
```dart
style: AppTypography.monoXs.copyWith(color: AppColors.bad),
```

### MUT-14 tile spacing 12 - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
            spacing: 8,
            runSpacing: 8,
```
after:
```dart
            spacing: 12,
            runSpacing: 8,
```

### MUT-15 tile width -40 - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final width = (constraints.maxWidth - 8) / 2;
```
after:
```dart
final width = (constraints.maxWidth - 8) / 2 - 40;
```

### MUT-16 rows reversed - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
for (final row in rows)
```
after:
```dart
for (final row in rows.reversed)
```

### MUT-17 tile title/value swapped - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
            row.titleText,
            style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
```
after:
```dart
            row.valueText,
            style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
            row.valueText,
            style: AppTypography.titleS.copyWith(color: AppColors.textPrimary),
```
after:
```dart
            row.titleText,
            style: AppTypography.titleS.copyWith(color: AppColors.textPrimary),
```

### MUT-18 tile wrap end-aligned - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
          return Wrap(
            spacing: 8,
```
after:
```dart
          return Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
```

### MUT-19 Retry minimumSize zero (expected equivalent) - GREEN(survived)

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
minimumSize: const Size(44, 44),
```
after:
```dart
minimumSize: Size.zero,
```

### MUT-20 card button semantic onTap removed - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
            label: MeasurementCopy.cardAddButton,
            onTap: onAdd,
```
after:
```dart
            label: MeasurementCopy.cardAddButton,
```

### MUT-21 chip semantic onTap removed - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
                      label: MeasurementCopy.chipLabel,
                      onTap: open,
```
after:
```dart
                      label: MeasurementCopy.chipLabel,
```

### MUT-22 X semantic onTap removed - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
                  label: MeasurementCopy.bannerDismissLabel,
                  onTap: dismiss,
```
after:
```dart
                  label: MeasurementCopy.bannerDismissLabel,
```

### MUT-23 card hides on a stored dismissal - RED 1

- tests run: `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
final history = ref.watch(bodyMeasurementsProvider);
```
after:
```dart
final history = ref.watch(bodyMeasurementsProvider);
    if (MigratedKey.read<dynamic>('body_measurement_prompt_dismissed_at') != null) return const SizedBox.shrink();
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
import 'package:flutter/material.dart';
```
after:
```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
```

### MUT-24 card year rule by the UTC day - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
todayIst: istTodayStr(),
```
after:
```dart
todayIst: nowWall().toUtc().toIso8601String().substring(0, 10),
```

- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
import 'package:flutter/material.dart';
```
after:
```dart
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/utils/ist_date.dart' show nowWall;
```

### MUT-25 long date month > 13 - RED 2

- tests run: `test/utils/measurement_units_test.dart`
- file: `lib/core/utils/measurement_units.dart`

before:
```dart
if (month < 1 || month > 12 || day < 1 || day > 31) return '';
```
after:
```dart
if (month < 1 || month > 13 || day < 1 || day > 31) return '';
```

### MUT-26 firstBySiteOf assert starts at 2 - RED 1

- tests run: `test/contracts/body_measurement_readers_behavioral_test.dart`
- file: `lib/core/services/health_read_service.dart`

before:
```dart
    assert(() {
      for (var i = 1; i < newestFirst.length; i++) {
        if (newestFirst[i].date.compareTo(newestFirst[i - 1].date) > 0) {
          return false;
        }
      }
      return true;
    }(), 'firstBySiteOf needs its input newest first');
```
after:
```dart
    assert(() {
      for (var i = 2; i < newestFirst.length; i++) {
        if (newestFirst[i].date.compareTo(newestFirst[i - 1].date) > 0) {
          return false;
        }
      }
      return true;
    }(), 'firstBySiteOf needs its input newest first');
```

### MUT-27 input bar focusNode unbound - RED 1

- tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- file: `lib/features/ai_coach/screens/ai_coach/input_bar.dart`

before:
```dart
      focusNode: _inputFocusNode,
```
after:
```dart
(removed)
```

### MUT-28 empty state minHeight = maxHeight - GREEN(survived)

- tests run: `test/features/profile/progress_comparison_screen_measurements_test.dart`
- file: `lib/features/profile/screens/progress_comparison_screen.dart`

before:
```dart
minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
```
after:
```dart
minHeight: constraints.maxHeight,
```

### MUT-29 tile scroll view takes the primary controller - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
          primary: false,
```
after:
```dart
(removed)
```

### MUT-30 unit catch falls back to the device - RED 2

- tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/features/profile/body_measurements_sheet_test.dart`
- file: `lib/features/profile/providers/body_measurements_provider.dart`

before:
```dart
message: 'stage=unit'));
      return false;
```
after:
```dart
message: 'stage=unit'));
      return !UserRepository.instance.getUnitsMetric();
```

### MUT-31 chip tone bad - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
tone: WardChipTone.gold,
```
after:
```dart
tone: WardChipTone.bad,
```

### MUT-32 chip icon add - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
Icons.straighten,
```
after:
```dart
Icons.add,
```

### MUT-33 chip right padding 150 - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
padding: const EdgeInsets.only(left: AppSpacing.gutter, right: 4),
```
after:
```dart
padding: const EdgeInsets.only(left: AppSpacing.gutter, right: 150),
```

### MUT-34 row value -1 - RED 1

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
      value: value,
      delta: delta,
```
after:
```dart
      value: -1,
      delta: delta,
```

### MUT-35 row latestDate empty - RED 1

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
latestDate: now.date,
```
after:
```dart
latestDate: '',
```

### MUT-36 eyebrow clip - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
overflow: TextOverflow.ellipsis,
```
after:
```dart
overflow: TextOverflow.clip,
```

### MUT-37 chip horizontal scroll unwrapped - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Semantics(
```
after:
```dart
                  child: Container(
                    child: Semantics(
```

### MUT-38 rules delta unrounded - RED 3

- tests run: `test/features/profile/measurement_card_rules_test.dart`
- file: `lib/features/profile/services/measurement_card_rules.dart`

before:
```dart
delta = roundMeasurementToTenth(value - base);
```
after:
```dart
delta = value - base;
```

### N01 chip onShown never called - RED 3

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
widget.onShown?.call(height);
```
after:
```dart
(removed)
```

### N02 keepBottom: guard removed (always follows) - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
  if (position.extentAfter > slotHeight + kChipFollowSlack) return;
```
after:
```dart
(removed)
```

### N03 keepBottom: guard inverted - RED 2

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
position.extentAfter > slotHeight + kChipFollowSlack
```
after:
```dart
position.extentAfter < slotHeight + kChipFollowSlack
```

### N04 keepBottom: slack -1 - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
const double kChipFollowSlack = 16;
```
after:
```dart
const double kChipFollowSlack = -1;
```

### N05 _NotifyWhenShown fires on every build - RED 3

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
  @override
  Widget build(BuildContext context) => widget.child;
```
after:
```dart
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown?.call(44);
    });
    return widget.child;
  }
```

### N06 slot height reported as 0 - RED 2

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
```
after:
```dart
const height = 0.0;
```

### N07 keepBottom: no animateTo - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
  controller.animateTo(
    position.maxScrollExtent,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
```
after:
```dart
(removed)
```

### N08 frame: anonymous window still draws the band - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
final show = !anonymous && available
```
after:
```dart
final show = available
```

### N09 frame: Expanded -> Flexible - RED 1

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card_frame.dart`

before:
```dart
Expanded(child: child),
```
after:
```dart
Flexible(child: child),
```

### N10 tiles: unit not re-read on a new history - RED 2

- tests run: `test/features/profile/measurements_card_test.dart`, `test/features/profile/measurement_card_end_to_end_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
    if (!identical(oldWidget.history, widget.history)) _inches = _readUnit();
```
after:
```dart
(removed)
```

### N11 tiles: unit read on every build - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
inches: _inches,
```
after:
```dart
inches: _readUnit(),
```

### N12 header eyebrow letter spacing 3 - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
letterSpacing: 2,
            ),
```
after:
```dart
letterSpacing: 3,
            ),
```

### N13 header label padding 8 - RED 1

- tests run: `test/features/profile/measurements_card_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
padding: const EdgeInsets.symmetric(horizontal: 4),
```
after:
```dart
padding: const EdgeInsets.symmetric(horizontal: 8),
```

### N14 date formatters: shape check dropped for long names only - RED 2

- tests run: `test/utils/measurement_units_test.dart`
- file: `lib/core/utils/measurement_units.dart`

before:
```dart
if (month < 1 || month > 12 || day < 1 || day > 31) return '';
  final currentYear
```
after:
```dart
if (day < 1 || day > 31) return '';
  final currentYear
```

### N15 floor row: kMinCardCap 120 - RED 13

- tests run: `test/features/profile/measurements_card_frame_test.dart`
- file: `lib/features/profile/widgets/measurements_card.dart`

before:
```dart
const double kMinCardCap = 136;
```
after:
```dart
const double kMinCardCap = 120;
```

### S22b a real sendMessage member in the slot file - RED 1

- tests run: `test/ai_coach/measurement_chip_slot_test.dart`
- file: `lib/features/ai_coach/widgets/measurement_chip_slot.dart`

before:
```dart
void open() => BodyMeasurementsSheet.show(context);
```
after:
```dart
void open() => BodyMeasurementsSheet.show(context);
        void sendMessage() {}
```

