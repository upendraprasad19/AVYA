# /add-repository — Create a Supabase/Hive repository class

Create a repository class for the entity specified in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Section 7 (Database Schema) for the table definition
2. Create `lib/features/{feature}/repositories/{name}_repository.dart` or `lib/shared/repositories/{name}_repository.dart`
3. Follow the repository pattern:
   - Read operations: Hive first (primary)
   - Write operations: Hive first, then async Supabase push
   - All methods are async
   - All methods have try/catch with meaningful error handling
   - Never call Supabase directly from widgets — always through this repository

## Template
```dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class {Name}Repository {
  final Box _box;
  final SupabaseClient _supabase;

  {Name}Repository({required Box box, required SupabaseClient supabase})
      : _box = box, _supabase = supabase;

  // READ — from Hive (offline-first)
  Future<List<{Model}>> getAll() async {
    try {
      return _box.values.cast<{Model}>().toList();
    } catch (e) {
      return [];
    }
  }

  // WRITE — Hive first, then Supabase async
  Future<void> add({Model} item) async {
    await _box.put(item.id, item);
    // Background sync to Supabase (don't await in UI)
    _syncToSupabase(item);
  }

  Future<void> _syncToSupabase({Model} item) async {
    try {
      await _supabase.from('{table}').upsert(item.toJson());
    } catch (_) {
      // Queue for next sync cycle
    }
  }
}
```
