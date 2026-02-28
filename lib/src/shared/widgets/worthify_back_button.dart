import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'worthify_circular_icon_button.dart';

class WorthifyBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool showBackground;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final EdgeInsetsGeometry? margin;
  final bool enableHaptics;

  const WorthifyBackButton({
    super.key,
    this.onPressed,
    this.showBackground = true,
    this.backgroundColor,
    this.iconColor,
    this.size = 40,
    this.iconSize = 20,
    this.margin,
    this.enableHaptics = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color effectiveIconColor = iconColor ?? Colors.black;
    final VoidCallback tapHandler = () {
      if (enableHaptics) {
        HapticFeedback.mediumImpact();
      }
      (onPressed ?? () => Navigator.of(context).maybePop())();
    };

    if (!showBackground) {
      return IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.arrow_back, color: effectiveIconColor, size: iconSize),
        onPressed: tapHandler,
        tooltip: 'Back',
      );
    }

    return WorthifyCircularIconButton(
      icon: Icons.arrow_back,
      onPressed: tapHandler,
      backgroundColor: backgroundColor ?? const Color(0xFFF3F4F6),
      iconColor: effectiveIconColor,
      iconSize: iconSize,
      size: size,
      semanticLabel: 'Back',
      tooltip: 'Back',
      margin: margin ?? const EdgeInsets.all(8),
    );
  }
}
