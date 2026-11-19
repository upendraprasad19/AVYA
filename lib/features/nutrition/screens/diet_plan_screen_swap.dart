// ignore_for_file: invalid_use_of_protected_member
//
// The Diet Plan screen's swap flow, moved out of diet_plan_screen.dart (diet
// chart v3, 2026-11-17, docs/plans/diet-chart-v3.md §4.2, §4.3: the screen sits
// near its 800-line ceiling, scripts/check_god_screen_max_lines.dart, which
// counts only files ending `_screen.dart`). An extension on the state, in the
// same library, so it reads the private plan fields; `setState` is @protected,
// hence the ignore above (the precedent is profile_content.dart).
//
// A pick (a catalog alternative or a free food) goes through `_applyPick`:
// when it ADDS carbs and the day then fits only a less strict strategy than the
// plan's (Keto -> Low carb -> Balanced), the app asks and, on a yes, writes the
// PROFILE strategy and keeps the edited plan WITHOUT regenerating it:
// `_requestedStrategy` is set BEFORE the write, so when the write moves the
// effective strategy to `next` the regeneration listener
// (`_onEffectiveStrategy`) finds the plan already asked for it. That is
// ORDERING, not an invariant: both fields are set again after the await, and
// a provisional request that did not commit (cancel, failed write, a throw)
// is handed back in the `finally`. Nothing here ever saves the plan.
part of 'diet_plan_screen.dart';

extension _DietPlanSwapFlow on _DietPlanScreenState {
  /// The day's four numbers, with [replace] taking the place of one item.
  DietPlanTotals _planTotals({
    int? mealIndex,
    int? itemIndex,
    _PlanFoodItem? replace,
  }) {
    DietMacroTuple t(_PlanFoodItem i) =>
        (calories: i.calories, protein: i.protein, carbs: i.carbs, fat: i.fat);
    return sumDietPlanTotals([
      for (var m = 0; m < _mealPlans.length; m++)
        for (var k = 0; k < _mealPlans[m].items.length; k++)
          t(replace != null && m == mealIndex && k == itemIndex
              ? replace
              : _mealPlans[m].items[k]),
    ]);
  }

  void _swapItem(int mealIndex, int itemIndex) {
    if (_pickBusy) return;
    final meal = _mealPlans[mealIndex];
    final item = meal.items[itemIndex];
    if (isSupplementShake(item.foodId)) return;
    final slotKey = meal.slotKey ?? kDietMealNameToSlotKey[meal.name] ?? '';
    final planIds = [
      for (final m in _mealPlans)
        for (final i in m.items) i.foodId,
    ];
    // Diet plan Unit 1: catalog-only alternatives (diet_plan_swap.dart), now
    // ALL of them (diet chart v3: the 6 cap hid 9-25 valid options).
    final alternatives = swapAlternatives(
      foodId: item.foodId,
      category: item.category,
      calories: item.calories,
      role: item.role,
      slotKey: slotKey,
      dietPreference: _foodType.storageKey,
      strategy: _planStrategy,
      planFoodIds: planIds,
      slotOtherNames: [
        for (var j = 0; j < meal.items.length; j++)
          if (j != itemIndex) meal.items[j].name,
      ],
      repo: FoodRepository.instance,
      limit: 100,
    );
    // A free pick fills the REPLACED item's role (a later swap of it then
    // finds that role's catalog alternatives).
    final role = resolveSwapRole(
      foodId: item.foodId,
      category: item.category,
      role: item.role,
      slotKey: slotKey,
      strategy: _planStrategy,
    )?.name;
    final epoch = _planEpoch;
    final others = [...planIds]..remove(item.foodId);
    final servingView = ref.read(dietServingViewProvider);
    showDietPlanSwapSheet(
      context,
      itemName: item.name,
      view: servingView,
      alternatives: alternatives,
      onPick: (alt) =>
          _applyPick(epoch, mealIndex, itemIndex, item.foodId, alt),
      onSearch: (sheetContext) {
        final repo = FoodRepository.instance;
        final foods = repo.getAll();
        final custom = repo.getCustomFoods();
        final adult = dietSupplementsEligible(
            profile: UserRepository.instance.getProfile(),
            enabled: true,
            now: DateTime.now());
        return showDietPlanFoodSearchSheet(
          sheetContext,
          role: role,
          view: servingView,
          search: (q) => searchDietPlanFoods(
            query: q,
            foods: foods,
            customFoods: custom,
            dietPreference: _foodType.storageKey,
            adult: adult,
            powdersAllowed: adult && DietSupplementsFlags.enabled,
            excludeIds: others.toSet(),
          ),
        );
      },
    );
  }

  _PlanFoodItem _planItemOf(DietPlanFoodItem alt) => _PlanFoodItem(
        foodId: alt.foodId,
        name: alt.name,
        servingDesc: alt.servingDesc,
        servingG: alt.servingG,
        calories: alt.calories,
        protein: alt.protein,
        carbs: alt.carbs,
        fat: alt.fat,
        // the NEW row's category; the role is inherited
        // (alt.role is the resolved role of the replaced item)
        category: alt.category,
        role: alt.role,
      );

  void _note(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: AppTypography.body.copyWith(fontSize: 13)),
        backgroundColor: AppColors.card,
      ),
    );
  }

  bool get _allowKeto =>
      !dietStrategiesDisabledFor(_foodType).contains(DietStrategy.keto);

  Future<void> _applyPick(
    int epoch,
    int mealIndex,
    int itemIndex,
    String replacedId,
    DietPlanFoodItem alt,
  ) async {
    // Unit 3b §3.6: a sheet opened before a regeneration changes nothing.
    if (_pickBusy || epoch != _planEpoch || !mounted) return;
    if (mealIndex >= _mealPlans.length ||
        itemIndex >= _mealPlans[mealIndex].items.length ||
        _mealPlans[mealIndex].items[itemIndex].foodId != replacedId) {
      return;
    }
    _pickBusy = true;
    // The provisional request (set before the write) is handed back on EVERY
    // exit that did not commit the pick: a cancel, a failed write, or a throw.
    var provisional = false;
    var committed = false;
    final previousRequested = _requestedStrategy;
    try {
      final newItem = _planItemOf(alt);
      final before = _planTotals();
      final after = _planTotals(
          mealIndex: mealIndex, itemIndex: itemIndex, replace: newItem);
      final base = resolveBaseMacroPack(UserRepository.instance.getProfile());
      final next = DietStrategyFlags.enabled
          ? shiftTargetFor(
              planStrategy: _planStrategy,
              beforeCarbs: before.carbs,
              afterCarbs: after.carbs,
              base: base,
              allowKeto: _allowKeto)
          : null;
      if (next == null) {
        setState(() {
          _mealPlans[mealIndex].items[itemIndex] = newItem;
          _saved = false;
        });
        return;
      }
      final effective = dietStrategyOfTargets(ref.read(macroTargetsProvider));
      final from = _planStrategy;
      var written = true;
      if (effective != next) {
        provisional = true;
        _requestedStrategy = planStrategyFor(next, _foodType);
        written = await handleDietStrategyTap(
          context,
          ref,
          next,
          current: effective,
          reason: _shiftReason(from, next, effective, after.carbs, base),
          alwaysAsk: true,
          isStale: () => epoch != _planEpoch || !mounted,
          silent: true,
        );
        if (epoch != _planEpoch || !mounted) {
          // A newer generation owns the plan and `_requestedStrategy`; the
          // profile may already be written (the listener then followed it).
          _note(written
              ? 'Your plan was rebuilt for ${next.label}.'
              : 'The plan changed. Pick again.');
          return;
        }
        if (!written) return;
      }
      setState(() {
        _mealPlans[mealIndex].items[itemIndex] = newItem;
        _saved = false;
        _droppedFrom ??= from;
        _planStrategy = next;
        _requestedStrategy = planStrategyFor(next, _foodType);
      });
      committed = true;
      _note('Plan updated for ${next.label}. Save to keep it.');
    } finally {
      // A newer generation (epoch) owns `_requestedStrategy`: leave it alone.
      if (provisional && !committed && mounted && epoch == _planEpoch) {
        _requestedStrategy = previousRequested;
      }
      _pickBusy = false;
    }
  }

  String _shiftReason(DietStrategy from, DietStrategy next,
      DietStrategy effective, num carbs, MacroPack? base) {
    final ceiling = dietStrategyCarbCeiling(from, base);
    final limit = ceiling == null ? '' : ' over the ${from.label} limit of $ceiling g';
    final replaces = effective != from
        ? ' Switching your strategy to ${next.label} replaces ${effective.label}.'
        : '';
    return 'This swap puts your plan at ${carbs.round()} g of carbs,'
        '$limit. Your plan is now ${next.label}.$replaces '
        'Save the plan afterwards to keep your changes.';
  }

  /// "Back to Keto": the plan fits the strategy it dropped from again.
  Future<void> _backUpStrategy(DietStrategy target) async {
    if (_pickBusy || !mounted) return;
    final epoch = _planEpoch;
    _pickBusy = true;
    var provisional = false;
    var committed = false;
    final previousRequested = _requestedStrategy;
    try {
      final effective = dietStrategyOfTargets(ref.read(macroTargetsProvider));
      var written = true;
      if (effective != target) {
        provisional = true;
        _requestedStrategy = planStrategyFor(target, _foodType);
        written = await handleDietStrategyTap(
          context,
          ref,
          target,
          current: effective,
          reason: 'Your plan fits ${target.label} again. '
              'Save the plan afterwards to keep your changes.',
          alwaysAsk: true,
          isStale: () => epoch != _planEpoch || !mounted,
          silent: true,
        );
        if (epoch != _planEpoch || !mounted) return;
        if (!written) return;
      }
      setState(() {
        _planStrategy = target;
        _requestedStrategy = planStrategyFor(target, _foodType);
        _saved = false;
        if (_droppedFrom == target) _droppedFrom = null;
      });
      committed = true;
      _note('Plan is back on ${target.label}. Save to keep it.');
    } finally {
      if (provisional && !committed && mounted && epoch == _planEpoch) {
        _requestedStrategy = previousRequested;
      }
      _pickBusy = false;
    }
  }

  /// The targets the totals row (and the PDF total line) compare with: the
  /// shown ones, or the plan strategy's when the plan is built for another
  /// strategy than the targets cards show (a Keto + Vegan profile, whose plan
  /// is Low carb), with that strategy's name as the caption.
  ({DietTotalsTargets targets, String? caption}) _planTargets(
      Map<String, double> shown, MacroPack? base) {
    var t = (
      calories: shown['calories'] ?? 0,
      protein: shown['protein'] ?? 0,
      carbs: shown['carbs'] ?? 0,
      fat: shown['fat'] ?? 0,
    );
    String? caption;
    if (DietStrategyFlags.enabled &&
        _planStrategy != dietStrategyOfTargets(shown) &&
        base != null) {
      final alt = effectiveMacroTargets(base, _planStrategy.storageKey,
          pro: true, enabled: true);
      if (alt != null) {
        t = (
          calories: alt.calories,
          protein: alt.protein,
          carbs: alt.carbs,
          fat: alt.fat,
        );
        caption = _planStrategy.label;
      }
    }
    return (targets: t, caption: caption);
  }

  /// The PDF's plan-total line (the same numbers as the totals row).
  String _planTotalLine(Map<String, double> shown) {
    final base = resolveBaseMacroPack(UserRepository.instance.getProfile());
    final p = _planTargets(shown, base);
    return dietPlanPdfTotalLine(
      totals: _planTotals(),
      calorieTarget: p.targets.calories.round(),
      proteinTarget: p.targets.protein.round(),
      carbTarget: p.targets.carbs.round(),
      fatTarget: p.targets.fat.round(),
      caption: p.caption,
    );
  }

  /// The "your plan vs target" row (diet chart v3 §4.1).
  Widget _buildTotalsRow(Map<String, double> targets) {
    final totals = _planTotals();
    final base = resolveBaseMacroPack(UserRepository.instance.getProfile());
    final p = _planTargets(targets, base);
    final ceiling = DietStrategyFlags.enabled
        ? dietStrategyCarbCeiling(_planStrategy, base)
        : null;
    final back = DietStrategyFlags.enabled
        ? backUpTargetFor(
            droppedFrom: _droppedFrom,
            planStrategy: _planStrategy,
            dayCarbs: totals.carbs,
            base: base,
            allowKeto: _allowKeto)
        : null;
    return DietPlanTotalsRow(
      totals: totals,
      targets: p.targets,
      targetCaption: p.caption,
      fitLine: DietStrategyFlags.enabled
          ? dietPlanFitLine(
              planStrategy: _planStrategy, dayCarbs: totals.carbs, base: base)
          : null,
      fitOk: ceiling == null || totals.carbs <= ceiling,
      backLabel: back == null ? null : 'Back to ${back.label}',
      onBack: back == null ? null : () => _backUpStrategy(back),
    );
  }

  /// goal-change-targets B4: the stale-targets banner, or null when the plan's stamp still matches
  /// the targets on screen (or there is no stamp, or the targets are the fallback defaults).
  Widget? _staleBanner(Map<String, double> targets) {
    final stale = staleTargetsOf(
      _planStamp,
      calories: targets['calories'] ?? 0,
      protein: targets['protein'] ?? 0,
      usingFallback:
          resolveBaseMacroPack(UserRepository.instance.getProfile()) == null,
    );
    if (stale == null) return null;
    final key = '${stale.stamp.calories}/${stale.stamp.protein}->'
        '${stale.current.calories}/${stale.current.protein}';
    if (_dismissedStale == key) return null;
    return DietPlanStaleBanner(
      stamp: stale.stamp,
      current: stale.current,
      onRegenerate: _regenerateFromBanner,
      onDismiss: () => setState(() => _dismissedStale = key),
    );
  }

  /// The banner's Regenerate: same as the app bar refresh, plus the reminder that the new plan is
  /// not saved until the user taps Save (the old saved chart stays as it is until then).
  void _regenerateFromBanner() {
    _regenerations++;
    _generateFreshPlan();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Plan regenerated for your new targets. Save to keep it.',
          style: AppTypography.body.copyWith(fontSize: 13),
        ),
        backgroundColor: AppColors.card,
      ),
    );
  }
}
