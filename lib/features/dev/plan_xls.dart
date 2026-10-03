// Debug-only (year-sim Excel export, 2026-05-31). Serializes the captured
// per-phase plans (SimReport.capturedPhases) into a SpreadsheetML 2003 workbook
// (.xls) — a zero-dependency, multi-sheet, formatted format Excel opens natively
// (no `excel` package in pubspec). Founder wants to review every workout plan
// generated for amar across the sim to Lieutenant.
//
// `downloadPlansXls` triggers a browser download on web (where the sim runs) via
// a conditional import; on non-web it is a no-op (the builder is still callable
// e.g. from a test that writes the string to disk).
import 'xls_saver_stub.dart' if (dart.library.html) 'xls_saver_web.dart' as saver;

String _xmlEscape(Object? v) {
  final s = (v ?? '').toString();
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _cellStr(Object? v) =>
    '<Cell><Data ss:Type="String">${_xmlEscape(v)}</Data></Cell>';

String _cellNum(Object? v) {
  if (v == null) return '<Cell><Data ss:Type="String"></Data></Cell>';
  return '<Cell><Data ss:Type="Number">${_xmlEscape(v)}</Data></Cell>';
}

/// Sanitize a worksheet name: <=31 chars, none of : \ / ? * [ ].
String _sheetName(String raw) {
  var s = raw.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
  if (s.length > 31) s = s.substring(0, 31);
  return s.isEmpty ? 'Sheet' : s;
}

/// Builds a SpreadsheetML 2003 workbook string from captured phase plans.
String buildPlansSpreadsheetXml(List<Map<String, dynamic>> phases) {
  final b = StringBuffer();
  b.write('<?xml version="1.0"?>\n');
  b.write('<?mso-application progid="Excel.Sheet"?>\n');
  b.write('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"'
      ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">\n');
  b.write('<Styles>'
      '<Style ss:ID="hdr"><Font ss:Bold="1"/>'
      '<Interior ss:Color="#D4B270" ss:Pattern="Solid"/></Style>'
      '<Style ss:ID="sub"><Font ss:Bold="1"/></Style>'
      '</Styles>\n');

  // ── Summary sheet ──
  b.write('<Worksheet ss:Name="Summary"><Table>');
  b.write('<Row ss:StyleID="hdr">'
      '${_cellStr('Phase')}${_cellStr('Deployment')}${_cellStr('Name')}'
      '${_cellStr('Weeks')}${_cellStr('Rank earned')}${_cellStr('Captured (IST)')}'
      '${_cellStr('# Days')}${_cellStr('# Exercises')}</Row>');
  for (final p in phases) {
    final days = (p['days'] as List?) ?? const [];
    final exCount = days.fold<int>(
        0, (a, d) => a + (((d as Map)['exercises'] as List?)?.length ?? 0));
    b.write('<Row>'
        '${_cellNum(p['phase'])}${_cellNum(p['deployment'])}${_cellStr(p['name'])}'
        '${_cellStr(p['weeks'])}${_cellStr(p['rank'])}${_cellStr(p['captured_on'])}'
        '${_cellNum(days.length)}${_cellNum(exCount)}</Row>');
  }
  b.write('</Table></Worksheet>\n');

  // ── Per-phase sheets ──
  final usedNames = <String>{};
  for (final p in phases) {
    var name = _sheetName('P${p['phase']} ${p['name']}');
    var n = name;
    var i = 2;
    while (usedNames.contains(n)) {
      n = _sheetName('$name $i');
      i++;
    }
    usedNames.add(n);

    b.write('<Worksheet ss:Name="$n"><Table>');
    b.write('<Row ss:StyleID="sub">'
        '${_cellStr('${p['name']} — ${p['focus']}  (weeks ${p['weeks']}, rank ${p['rank']})')}'
        '</Row>');
    b.write('<Row ss:StyleID="hdr">'
        '${_cellStr('Day')}${_cellStr('Focus')}${_cellStr('Exercise')}'
        '${_cellStr('Sets')}${_cellStr('Reps')}${_cellStr('Suggested kg')}'
        '${_cellStr('Progression cue')}</Row>');
    for (final d in (p['days'] as List? ?? const [])) {
      final dm = d as Map;
      final exs = (dm['exercises'] as List?) ?? const [];
      if (exs.isEmpty) {
        b.write('<Row>${_cellStr(dm['name'])}${_cellStr(dm['focus'])}'
            '${_cellStr('(rest / no exercises)')}'
            '${_cellStr('')}${_cellStr('')}${_cellStr('')}${_cellStr('')}</Row>');
        continue;
      }
      var first = true;
      for (final e in exs) {
        final em = e as Map;
        b.write('<Row>'
            '${_cellStr(first ? dm['name'] : '')}'
            '${_cellStr(first ? dm['focus'] : '')}'
            '${_cellStr(em['name'])}'
            '${_cellNum(em['sets'])}'
            '${_cellStr(em['reps'])}'
            '${_cellNum(em['suggested_weight'])}'
            '${_cellStr(em['weight_cue'])}</Row>');
        first = false;
      }
    }
    b.write('</Table></Worksheet>\n');
  }

  b.write('</Workbook>\n');
  return b.toString();
}

/// Triggers a browser download of the plans workbook (web only; no-op elsewhere).
void downloadPlansXls(String filename, List<Map<String, dynamic>> phases) {
  saver.saveXls(filename, buildPlansSpreadsheetXml(phases));
}
