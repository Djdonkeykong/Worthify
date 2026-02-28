import 'package:flutter/material.dart';

/// Reusable circular icon button that matches the onboarding back button style.
class WorthifyCircularIconButton extends StatelessWidget {
  const WorthifyCircularIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 40,
    this.iconSize = 20,
    this.tooltip,
    this.margin,
    this.semanticLabel,
    this.elevation = 0,
    this.iconOffset = Offset.zero,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;
  final EdgeInsetsGeometry? margin;
  final String? semanticLabel;
  final double elevation;
  final Offset iconOffset;

  @override
  Widget build(BuildContext context) {
    final Color effectiveBackground =
        backgroundColor ?? const Color(0xFFF3F4F6);
    final Color effectiveIconColor = iconColor ?? Colors.black;

    final Widget button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: effectiveBackground,
            shape: BoxShape.circle,
            boxShadow: elevation > 0
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: elevation,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Transform.translate(
            offset: iconOffset,
            child: Icon(
              icon,
              color: effectiveIconColor,
              size: iconSize,
            ),
          ),
        ),
      ),
    );

    Widget wrapped =
        tooltip != null ? Tooltip(message: tooltip!, child: button) : button;

    wrapped = Semantics(
      button: true,
      label: semanticLabel,
      child: wrapped,
    );

    if (margin != null) {
      wrapped = Padding(
        padding: margin!,
        child: wrapped,
      );
    }

    return wrapped;
  }
}
