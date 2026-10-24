// Non-web no-op for the plans Excel download (the sim + export run on web).
import 'package:flutter/foundation.dart';

void saveXls(String filename, String content) {
  debugPrint('[plan_xls] saveXls is web-only; $filename '
      '(${content.length} bytes) not written on this platform.');
}
