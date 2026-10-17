/// Workout template identity helpers — OI-252 (stable ID rework,
/// `docs/superpowers/plans/2026-09-26-template-stable-identity.md`).
///
/// A workout template has exactly ONE identity: a UUID minted on the client
/// when the template is created. It is the cloud `workout_templates.id`
/// primary key. Locally it is spelled `tmpl_<uuid>` — the Hive key, the row's
/// own `id` field, every `schedule_*`/`displaced_*`/plan_json `template_id`,
/// and the AI snapshot `saved_templates[].id`.
///
/// These two functions are PURE — no Hive read, no Supabase call, no name
/// lookup. A legacy pre-migration key (`tmpl_<ms>` or `tmpl_<namehash>`) is
/// simply not UUID-shaped, so [cloudIdFromKey] returns null for it; callers
/// use that null to route legacy rows through `TemplateIdentityMigrator`
/// instead of the cloud push/restore path.
library;

/// RFC 4122 UUID shape (case-insensitive, any of the 8 defined versions).
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The Hive key / local `id` field for a template whose cloud id is [uuid].
String templateKeyFor(String uuid) => 'tmpl_$uuid';

/// The cloud `workout_templates.id` a template [key] refers to, or null when
/// [key] is not of the form `tmpl_<uuid>` (a legacy pre-migration key, or not
/// a template key at all).
String? cloudIdFromKey(String key) {
  const prefix = 'tmpl_';
  if (!key.startsWith(prefix)) return null;
  final candidate = key.substring(prefix.length);
  return _uuidPattern.hasMatch(candidate) ? candidate : null;
}
