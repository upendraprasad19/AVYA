// Web download for the plans Excel (.xls / SpreadsheetML). Debug-only — used by
// the year-sim export button so the founder can review every generated plan.
// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

void saveXls(String filename, String content) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/vnd.ms-excel');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
