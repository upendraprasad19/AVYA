import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../barcode_scan_sheet.dart' show BarcodeBody;

/// BARCODE mode body for `LogFoodSheet`. Delegates to the reusable
/// `BarcodeBody` widget extracted from `barcode_scan_sheet.dart`. The
/// shared body handles: MobileScanner controller lifecycle, barcode
/// lookup via `BarcodeService`, result-editor (serving slider, macros,
/// meal-type pills) and the Hive write + sync fan-out on save.
///
/// Calling [onLogged] dismisses the parent sheet — typically the
/// `LogFoodSheet` host invokes `Navigator.maybePop` here.
class BarcodeModeBody extends ConsumerWidget {
  const BarcodeModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BarcodeBody(onLogged: onLogged);
  }
}
