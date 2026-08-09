import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Dünner Wrapper um `Scaffold`, der die Standard-Kombination aus
/// edge-to-edge-Body + schwebender `LiquidGlassNavigationBar` kapselt.
/// `app_shell.dart` bleibt der Ort, der Tabs/Routing hält — dieses Widget
/// nur für Screens, die EIGENSTÄNDIG (außerhalb der Tab-Shell) einen
/// konsistenten Glass-Scaffold brauchen (z.B. Modal-Screens mit eigener
/// Aktionsleiste).
class LiquidGlassScaffold extends StatelessWidget {
  const LiquidGlassScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.floatingBar,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: backgroundColor ?? colors.backgroundPrimary,
      appBar: appBar,
      body: body,
      bottomNavigationBar: floatingBar,
    );
  }
}
