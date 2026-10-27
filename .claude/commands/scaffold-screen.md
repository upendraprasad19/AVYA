# /scaffold-screen — Generate a new feature screen

Create a complete feature folder for the screen specified in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Sections 5 (Directory Structure), 6 (Coding Rules), 9 (Design System)
2. Create the folder structure:
   ```
   lib/features/{name}/
     screens/{name}_screen.dart
     widgets/
     providers/{name}_provider.dart
     repositories/{name}_repository.dart (if data access needed)
     models/
   ```
3. Scaffold the screen widget with:
   - `ConsumerStatefulWidget` (Riverpod)
   - Dark theme from `AppColors`, `AppTypography`
   - Switzer font via `GoogleFonts.switzer()`
   - Loading skeleton state
   - Error state with retry
   - Empty state
   - SafeArea wrapper
4. Scaffold the provider with `@riverpod` annotation
5. If the screen has PRO features, import `subscription_service.dart` and add `gate()` calls
6. Add the route to `lib/core/router/app_router.dart`

## Template
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

class {Name}Screen extends ConsumerStatefulWidget {
  const {Name}Screen({super.key});
  @override
  ConsumerState<{Name}Screen> createState() => _{Name}ScreenState();
}

class _{Name}ScreenState extends ConsumerState<{Name}Screen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: /* content */),
    );
  }
}
```
