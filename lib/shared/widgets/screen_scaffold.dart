import 'package:flutter/material.dart';

/// Clean screen shell — custom header + body, dark/light adaptive.
class ScreenScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const ScreenScaffold(
    this.title,
    this.body, {
    super.key,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = ModalRoute.of(context)?.canPop == true;
    final textColor = theme.textTheme.titleLarge?.color ?? theme.colorScheme.onSurface;
    final surface = theme.colorScheme.surface;
    final borderColor = isDark ? const Color(0xFF3A3A52) : const Color(0xFFF3F4F6);
    final dividerColor = isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 8, 16, 8),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (canPop)
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Icon(Icons.chevron_left,
                              size: 22, color: textColor),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...?actions,
                  ],
                ),
              ),
            ),
            Container(height: 1, color: dividerColor),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: floatingActionButton,
            )
          : null,
    );
  }
}
