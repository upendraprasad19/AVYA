part of 'screen.dart';

extension _HealthSyncSubtitle on _ProfileScreenState {

  // ── Health Sync (moved into SETTINGS row, 2026-04-18) ───────────

  /// Concise subtitle rendered next to the Health Sync row in settings.
  /// Collapses the live BiometricSyncCard metrics into one line so the
  /// list stays dense.
  String _buildHealthSyncSubtitle(BiometricData b) {
    if (!b.isSyncEnabled) return 'Connect Google Fit / Health Connect';
    final parts = <String>[];
    if (b.stepsToday != null) parts.add('${b.stepsToday} steps');
    if (b.sleepHours != null) parts.add('${b.sleepHours!.toStringAsFixed(1)}h sleep');
    return parts.isEmpty ? 'Connected' : parts.join(' \u00B7 ');
  }
}
