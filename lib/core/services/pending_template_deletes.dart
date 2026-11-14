import 'hive_service.dart';

/// OI-252 (stable ID rework) — the queue of template deletes not yet
/// confirmed against the cloud. Written by `WorkoutWriteService.deleteTemplate`
/// at local-delete time; drained (removed) by `SyncService._drainPendingTemplateDeletes`
/// on every template push, which UPSERTs a tombstone for each queued id.
///
/// Stored directly in `userBox` (not through a `MigratedKey`-style shared
/// namespace) because it is small, user-scoped by the box's own cross-account
/// guard, and never read by any other feature.
///
/// A queued entry survives app restarts and offline periods. It does NOT
/// survive logout — `userBox` is cleared on sign-out, so an undrained delete
/// is lost on that device (stated in the plan; tracked as OI-253, since a
/// durable cross-session delete queue is separate scope from this unit).
class PendingTemplateDeletes {
  PendingTemplateDeletes._();

  static const String _key = 'pending_template_deletes';

  /// The queued deletes, each `{'id': cloud uuid OR null, 'name': name at
  /// delete time}`. `name` is carried so the drain's tombstone UPSERT can
  /// create the row directly (with a NOT NULL `name`) even if the
  /// creating push for that id hasn't landed in the cloud yet — the exact
  /// race round-1 plan review's finding 2 required a fix for.
  ///
  /// A null `id` means the template was deleted while still on a LEGACY
  /// (pre-migration) Hive key — `WorkoutWriteService` never talks to
  /// Supabase directly (layering: WriteServices are Hive-only), so it
  /// cannot resolve the cloud id itself. The drain (which runs inside
  /// `SyncService` and DOES have Supabase access) resolves a null-id entry
  /// by name immediately before tombstoning it.
  static List<Map<String, dynamic>> read() {
    final raw = HiveService.instance.userBox.get(_key);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['id'] == null || m['id'] is String) && m['name'] is String)
        .toList();
  }

  /// Queues a template for deletion. [id] is the cloud `workout_templates.id`
  /// when known (the template's Hive key was already the stable `tmpl_<uuid>`
  /// shape), or null when it was still on a legacy key. [name] is always
  /// required — see the class doc for why. A no-op if an entry for this
  /// [id] (when non-null) or [name] is already queued.
  static Future<void> add({required String? id, required String name}) async {
    final list = read();
    final alreadyQueued = list.any((e) =>
        (id != null && e['id'] == id) || (id == null && e['name'] == name));
    if (alreadyQueued) return;
    list.add({'id': id, 'name': name});
    await HiveService.instance.userBox.put(_key, list);
  }

  /// Removes the entry identified by [id] (its resolved cloud id, even if
  /// it was queued with a null id and only resolved later by the drain)
  /// from the queue — called once the drain confirms the cloud tombstone
  /// exists (or the write raised no exception).
  static Future<void> remove(String id) async {
    final list = read()..removeWhere((e) => e['id'] == id);
    await HiveService.instance.userBox.put(_key, list);
  }

  /// Removes the entry queued under [name] with a null `id` — called by
  /// the drain when a name-based resolve found no live cloud row (nothing
  /// to delete).
  static Future<void> removeByName(String name) async {
    final list = read()
      ..removeWhere((e) => e['id'] == null && e['name'] == name);
    await HiveService.instance.userBox.put(_key, list);
  }
}
