/// UX class — drives which widget renders the confirmation.
enum ConfirmationClass {
  /// Inline card, 5s auto-confirm. For low-stakes reversible actions.
  trivial,

  /// Inline card, explicit confirm only (no countdown). For mid-stakes actions
  /// like swapExercise where the user wants to review before committing.
  reviewable,

  /// Bottom sheet modal with full diff preview. For destructive/wide-impact
  /// actions like regeneratePlanBlock, pausePlan, switchGoal.
  destructive,
}

/// Lifecycle state of a queued tool intent.
enum ToolIntentStatus {
  /// Just received from server, awaiting user confirmation.
  pending,

  /// User confirmed, dispatcher about to execute.
  confirming,

  /// Dispatcher running execute().
  executing,

  /// Successfully executed.
  executed,

  /// Execution failed; retry button shown to user.
  failed,

  /// User explicitly rejected the intent.
  rejected,

  /// 1h TTL expired, intent is stale and cannot be executed.
  expired,
}

/// A typed write intent emitted by the server-side AI coach tool registry.
/// The client confirms with the user, then [ToolDispatcher.execute]s it
/// against the right Hive repository.
class ToolIntent {
  /// Stable unique ID assigned server-side. Used for lifecycle tracking,
  /// concurrent-edit guards, and dedup if a chat is retried.
  final String id;

  /// Tool name that emitted this intent (e.g. 'swap_exercise', 'log_set').
  /// The dispatcher's switch statement keys off this.
  final String type;

  /// Validated payload — exactly the shape the tool's Zod schema parsed.
  final Map<String, dynamic> payload;

  /// Drives which widget renders the confirmation.
  final ConfirmationClass confirmationClass;

  /// Server-supplied human-readable summary. Client may compute a richer
  /// version from local Hive (e.g. exercise names instead of IDs).
  final String previewSummary;

  /// ISO 8601. The dispatcher enforces a 1h TTL.
  final DateTime createdAt;

  /// Current lifecycle state. Mutated by PendingToolIntentsNotifier; never
  /// mutate directly — use copyWith.
  final ToolIntentStatus status;

  /// Set when status == failed. Human-readable error for retry button.
  final String? errorMessage;

  const ToolIntent({
    required this.id,
    required this.type,
    required this.payload,
    required this.confirmationClass,
    required this.previewSummary,
    required this.createdAt,
    this.status = ToolIntentStatus.pending,
    this.errorMessage,
  });

  /// Parse from the server's JSON shape returned by ai-proxy.
  factory ToolIntent.fromJson(Map<String, dynamic> json) {
    return ToolIntent(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      confirmationClass:
          _parseConfirmationClass(json['confirmationClass'] as String?),
      previewSummary: (json['previewSummary'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: ToolIntentStatus.pending,
    );
  }

  static ConfirmationClass _parseConfirmationClass(String? raw) {
    switch (raw) {
      case 'trivial':
        return ConfirmationClass.trivial;
      case 'reviewable':
        return ConfirmationClass.reviewable;
      case 'destructive':
        return ConfirmationClass.destructive;
      default:
        return ConfirmationClass.reviewable; // safe fallback
    }
  }

  ToolIntent copyWith({
    ToolIntentStatus? status,
    String? errorMessage,
    Map<String, dynamic>? payload,
    String? previewSummary,
  }) {
    return ToolIntent(
      id: id,
      type: type,
      payload: payload ?? this.payload,
      confirmationClass: confirmationClass,
      previewSummary: previewSummary ?? this.previewSummary,
      createdAt: createdAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// True if [createdAt] is more than 1 hour old.
  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(hours: 1);

  /// True if user can still act on this intent (not executed/rejected/expired).
  bool get isActionable {
    if (isExpired) return false;
    return status == ToolIntentStatus.pending ||
        status == ToolIntentStatus.failed;
  }
}
