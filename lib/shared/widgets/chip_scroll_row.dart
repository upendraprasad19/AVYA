// lib/shared/widgets/chip_scroll_row.dart
//
// Diet plan observations batch (2026-11-15, founder): the Diet Plan screen's
// two chip groups (food type, diet strategy) take ONE horizontally scrolling
// row each, so the plan starts higher on a phone. Edit Profile keeps its
// wrapped chips (the chip widgets default to `scrollable: false`).
//
// The selected chip is brought into view when the row first builds and
// whenever the selection moves, so a choice at the far end of the row (Vegan)
// is never hidden off-screen. Dragging works with a mouse too (web desktop).
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

class ChipScrollRow extends StatefulWidget {
  const ChipScrollRow({
    super.key,
    required this.chips,
    required this.selectedIndex,
    this.spacing = 8,
  });

  /// One widget per chip, in order.
  final List<Widget> chips;

  /// The chip to keep visible; -1 for none.
  final int selectedIndex;
  final double spacing;

  @override
  State<ChipScrollRow> createState() => _ChipScrollRowState();
}

class _ChipScrollRowState extends State<ChipScrollRow> {
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = [for (var i = 0; i < widget.chips.length; i++) GlobalKey()];
    _reveal();
  }

  @override
  void didUpdateWidget(ChipScrollRow old) {
    super.didUpdateWidget(old);
    if (_keys.length != widget.chips.length) {
      _keys = [for (var i = 0; i < widget.chips.length; i++) GlobalKey()];
    }
    if (old.selectedIndex != widget.selectedIndex) _reveal();
  }

  void _reveal() {
    final i = widget.selectedIndex;
    if (i < 0 || i >= _keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i].currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.5, duration: const Duration(milliseconds: 180));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        scrollbars: false,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('chip_scroll_row'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < widget.chips.length; i++) ...[
              if (i > 0) SizedBox(width: widget.spacing),
              KeyedSubtree(key: _keys[i], child: widget.chips[i]),
            ],
          ],
        ),
      ),
    );
  }
}
