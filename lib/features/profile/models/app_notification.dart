/// In-app notification inbox entry — one row on the Notifications
/// screen (`design_handoff_wardroom/src/screens/utility.jsx`).
///
/// Persisted as a plain `Map` in `HiveService.instance.notificationsBox`
/// keyed by [id], so no adapter registration is needed. Serialization
/// is JSON-safe (DateTime → ISO-8601 string) so the same shape can
/// later be synced to Supabase if a cross-device inbox is ever built.
///
/// Source: local business logic (streak banner hits, new PR detection)
/// or OneSignal foreground/click events — see [AppNotificationCategory]
/// for what each category means and how it maps to the filter pills.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.priority = AppNotificationPriority.normal,
    this.read = false,
  });

  /// Stable identifier. For OneSignal notifications this is the
  /// `OSNotification.notificationId`; for locally-generated entries
  /// it's `local-<utc ms>`.
  final String id;
  final AppNotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;

  /// [AppNotificationPriority.gold] renders a 2-px accent left-border
  /// and a gold category label, per the JSX spec. [priority] is
  /// typically inferred from the additionalData payload — PRs are
  /// promoted to gold automatically so a new lift PR always pops.
  final AppNotificationPriority priority;

  /// Whether the user has viewed/dismissed the row. Surfaced as a
  /// subtle 40%-opacity treatment; not currently persisted across
  /// inbox sessions (MARK READ clears the whole list).
  final bool read;

  AppNotification copyWith({
    String? id,
    AppNotificationCategory? category,
    String? title,
    String? body,
    DateTime? createdAt,
    AppNotificationPriority? priority,
    bool? read,
  }) =>
      AppNotification(
        id: id ?? this.id,
        category: category ?? this.category,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt ?? this.createdAt,
        priority: priority ?? this.priority,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'title': title,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'priority': priority.name,
        'read': read,
      };

  static AppNotification? fromJson(Map<dynamic, dynamic> raw) {
    try {
      final m = Map<String, dynamic>.from(raw);
      return AppNotification(
        id: m['id'] as String? ?? '',
        category: _parseCategory(m['category'] as String?),
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
        priority: _parsePriority(m['priority'] as String?),
        read: m['read'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static AppNotificationCategory _parseCategory(String? raw) {
    switch (raw) {
      case 'coach':
        return AppNotificationCategory.coach;
      case 'pr':
        return AppNotificationCategory.pr;
      case 'meal':
        return AppNotificationCategory.meal;
      case 'system':
      default:
        return AppNotificationCategory.system;
    }
  }

  static AppNotificationPriority _parsePriority(String? raw) {
    if (raw == 'gold') return AppNotificationPriority.gold;
    return AppNotificationPriority.normal;
  }
}

/// Filter pill categories from the JSX spec (ALL · COACH · PR · SYSTEM).
/// MEAL is included for future "protein shortfall" / "cart auditor"
/// pushes — currently funnels into COACH on display, but stored
/// separately so future filter pills can split them.
enum AppNotificationCategory {
  coach,
  pr,
  system,
  meal;

  String get displayLabel => switch (this) {
        AppNotificationCategory.coach => 'COACH',
        AppNotificationCategory.pr => 'PR',
        AppNotificationCategory.system => 'SYSTEM',
        AppNotificationCategory.meal => 'MEAL',
      };
}

enum AppNotificationPriority { normal, gold }

/// Which group header a notification falls under. Computed fresh each
/// build from `DateTime.now()` vs [AppNotification.createdAt] — no
/// persisted field since the grouping shifts as days pass.
enum AppNotificationGroup {
  today,
  yesterday,
  earlierThisWeek,
  older;

  String get displayLabel => switch (this) {
        AppNotificationGroup.today => 'TODAY',
        AppNotificationGroup.yesterday => 'YESTERDAY',
        AppNotificationGroup.earlierThisWeek => 'EARLIER THIS WEEK',
        AppNotificationGroup.older => 'OLDER',
      };

  static AppNotificationGroup fromCreatedAt(
    DateTime createdAt, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final createdDay =
        DateTime(createdAt.year, createdAt.month, createdAt.day);
    final diffDays = today.difference(createdDay).inDays;
    if (diffDays <= 0) return AppNotificationGroup.today;
    if (diffDays == 1) return AppNotificationGroup.yesterday;
    if (diffDays <= 6) return AppNotificationGroup.earlierThisWeek;
    return AppNotificationGroup.older;
  }
}
