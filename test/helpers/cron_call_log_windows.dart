// test/helpers/cron_call_log_windows.dart
//
// Pure readers for the OI-179 invariant (diagnose c9e2a7): an alert that reads
// the PRUNED table public.cron_call_log can only fire if its silence threshold
// is below BOTH its own lookback and the table's retention. Pure by design - no
// `expect`, no file access - so the mutation tests can feed fixture SQL.
//
// The class this guards (feedback_green_check_input_set_width): an alert whose
// input set is bounded by a pruner it does not know about. alert_cron_function_dead
// asked for 8 days of silence from a table pruned at 7, so it never fired.

import 'cron_job_body_reader.dart' show stripSqlLineComments;

typedef CronCallLogWindows = ({
  List<double> lookbackDays,
  List<double> thresholdDays,
});

double _unitToDays(int n, String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('minute')) return n / 1440.0;
  if (u.startsWith('hour')) return n / 24.0;
  return n.toDouble();
}

final RegExp _interval =
    RegExp(r"interval\s+'(\d+)\s+(minutes?|hours?|days?)'", caseSensitive: false);
final RegExp _silent = RegExp(r'\b(days|hours)_silent\s*>=\s*(\d+(?:\.\d+)?)');

/// The end of the sub-select that starts at [from]: the first `)` that closes a
/// paren opened BEFORE [from] (paren-balanced), or the end of [sql] when the
/// read is not inside a sub-select. Scanning for `GROUP BY` would miss the
/// composite ops_alerts_30min shapes, which end in `) c`.
int _subselectEnd(String sql, int from) {
  var depth = 0;
  for (var i = from; i < sql.length; i++) {
    final c = sql[i];
    if (c == "'") {
      // Skip a single-quoted literal ('' is an escaped quote): a paren inside
      // one must not move the depth, or it ends the scan early and hides a
      // later lookback (B-pass finding 3b).
      i++;
      while (i < sql.length) {
        if (sql[i] == "'") {
          if (i + 1 < sql.length && sql[i + 1] == "'") {
            i += 2;
            continue;
          }
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return sql.length;
}

/// Lookbacks (days) read inside every `FROM public.cron_call_log` sub-select of
/// [jobSql], and silence thresholds (days) read anywhere in the body.
///
/// Intervals OUTSIDE a cron_call_log sub-select (the 24 h dedup on `alerts`) are
/// deliberately not counted. A threshold column that appears twice
/// (alert_cron_silence has `hours_silent >= 2` and `>= 6`) contributes both
/// values; the caller compares the MAX.
CronCallLogWindows extractCronCallLogWindows(String jobSql) {
  final sql = stripSqlLineComments(jobSql);
  final lookbacks = <double>[];
  for (final m
      in RegExp(r'FROM\s+public\.cron_call_log\b', caseSensitive: false)
          .allMatches(sql)) {
    final end = _subselectEnd(sql, m.end);
    for (final i in _interval.allMatches(sql.substring(m.end, end))) {
      lookbacks.add(_unitToDays(int.parse(i.group(1)!), i.group(2)!));
    }
  }
  final thresholds = <double>[];
  for (final m in _silent.allMatches(sql)) {
    final v = double.parse(m.group(2)!);
    thresholds.add(m.group(1) == 'hours' ? v / 24.0 : v);
  }
  return (lookbackDays: lookbacks, thresholdDays: thresholds);
}

/// Retention (days) of `cleanup_cron_call_log`, read from the comment-stripped
/// text of its LIVE definition. Null when the interval cannot be found.
double? readRetentionDays(String migrationSql) {
  final sql = stripSqlLineComments(migrationSql);
  final fn = RegExp(
          r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?cleanup_cron_call_log\b(.*?)\$fn\$;',
          caseSensitive: false,
          dotAll: true)
      .firstMatch(sql);
  if (fn == null) return null;
  final m = RegExp(r"started_at\s*<\s*now\(\)\s*-\s*interval\s+'(\d+)\s+(minutes?|hours?|days?)'",
          caseSensitive: false)
      .firstMatch(fn.group(1)!);
  return m == null ? null : _unitToDays(int.parse(m.group(1)!), m.group(2)!);
}

/// Human-readable violations; empty means the alert can fire.
///
/// A lookback LARGER than retention is benign (it is only a cap, the table just
/// holds less), so it is not a violation. A threshold at or above the retention,
/// or at or above a stated lookback, is: the alert's input can never contain
/// evidence that old.
List<String> violations(CronCallLogWindows w, double retentionDays) {
  final out = <String>[];
  for (final t in w.thresholdDays) {
    if (t >= retentionDays) {
      out.add('threshold $t d >= retention $retentionDays d: unsatisfiable');
    }
    for (final l in w.lookbackDays) {
      if (t >= l) {
        out.add('threshold $t d >= lookback $l d: unsatisfiable');
      }
    }
  }
  return out;
}
