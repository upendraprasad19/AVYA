# /gate-feature — Wire a PRO feature gate

Add a subscription gate to the feature specified in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Section 10 (Subscription Gate Pattern)
2. Identify the screen file and the action to gate
3. Import `subscription_service.dart` and `paywall_sheet.dart`
4. Add state variable: `bool _paywallVisible = false;`
5. Wrap the PRO action with:
   ```dart
   await subscriptionService.gate(
     '{feature_key}',
     onPro: () => _doProAction(),
     onFree: () => setState(() => _paywallVisible = true),
   );
   ```
6. Add PaywallSheet at the bottom of the widget tree:
   ```dart
   if (_paywallVisible)
     PaywallSheet(
       onClose: () => setState(() => _paywallVisible = false),
       feature: '{Feature Name}',
       headline: '{Compelling headline}',
       bullets: ['{Benefit 1}', '{Benefit 2}', '{Benefit 3}'],
     ),
   ```

## PRO Feature Keys (from CLAUDE.md)
```
phases_2_to_12, active_workout_mode, ai_food_analysis,
ai_coach_unlimited, reasoning_tab, weekly_ai_report,
progress_photos, adjustable_portions, pro_tips,
scan_meal, diet_plan_pdf
```

## Rules
- NEVER use inline `if (isPro)` checks
- Phase 1 is ALWAYS free — never gate it
- PaywallSheet is the ONLY paywall UI — never create custom modals
