import 'package:flutter/material.dart';

/// Simple drag handle for bottom sheets to provide a grab affordance.
class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({
    super.key,
    this.margin,
    this.color,
    this.width = 40,
    this.height = 4,
  });

  /// Optional spacing around the handle.
  final EdgeInsetsGeometry? margin;

  /// Override the handle color if needed.
  final Color? color;

  /// Width of the pill-shaped drag indicator.
  final double width;

  /// Height of the pill-shaped drag indicator.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.outlineVariant;

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: effectiveColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
