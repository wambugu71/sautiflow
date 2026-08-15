import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../services/app_theme_service.dart';

/// Standardized uppercase section header with expressive tracking.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const AppSectionHeader(
    this.title, {
    super.key,
    this.padding = const EdgeInsets.only(left: 4.0, bottom: 6.0, top: 12.0),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: context.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Standard rounded surface card container (20px radius with subtle border).
class AppCardContainer extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final Border? border;
  final CrossAxisAlignment crossAxisAlignment;

  const AppCardContainer({
    super.key,
    required this.children,
    this.padding,
    this.borderRadius,
    this.color,
    this.border,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? context.cardDark;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        border: border ?? Border.all(color: context.outlineColor),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    );
  }
}

/// Expressive shape-morph icon badge (pill, cookie, gem, etc.) with accent tinting.
class AppShapeIcon extends StatelessWidget {
  final IconData icon;
  final Shapes shape;
  final Color? color;
  final double size;
  final double iconSize;

  const AppShapeIcon(
    this.icon, {
    super.key,
    this.shape = Shapes.pill,
    this.color,
    this.size = 42.0,
    this.iconSize = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.primaryColor;
    return Center(
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}

/// Small status badge chip (used for format indicators, state labels, active values).
class AppStatusBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppStatusBadge({
    super.key,
    required this.text,
    this.color,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.primaryColor;
    final badge = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: accent.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}

/// Standard M3E switch tile with reactive styling.
class AppM3ESwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;

  const AppM3ESwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      leading: leading,
      trailing: M3ESwitch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// Standardized layout for sub-screens in SautiPlay with unified theme background,
/// responsive width constraint, and back navigation.
class AppSubScreenScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final double maxWidth;

  const AppSubScreenScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.bottomNavigationBar,
    this.maxWidth = 800.0,
  });

  @override
  Widget build(BuildContext context) {
    final bg = context.bgDark;
    final textPrimary = context.textPrimary;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: actions,
      ),
      bottomNavigationBar: bottomNavigationBar,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
