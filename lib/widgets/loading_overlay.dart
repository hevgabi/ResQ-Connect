import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;
  final Color barrierColor;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.barrierColor = const Color(0x80000000),
  });

  /// Convenience static method to show as a standalone overlay
  static void show(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x80000000),
      builder: (_) => _LoadingDialog(message: message),
    );
  }

  static void hide(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Stack previously used the default StackFit.loose. When isLoading
    // switched to true, Flutter added Positioned.fill to the tree but the
    // layout pass hadn't run yet. Mouse-tracking hit tests fired in the gap
    // and reached the un-laid-out Positioned.fill → "RenderBox was not laid
    // out" (box.dart:2251, mouse_tracker.dart:199).
    //
    // StackFit.expand gives the Stack tight constraints equal to its parent
    // (the full-screen Navigator slot), so every child — including the
    // overlay — is immediately measurable the moment it enters the tree.
    // Positioned.fill is also removed: with StackFit.expand all non-
    // positioned children already fill the Stack, so a plain Container works.
    return Stack(
      fit: StackFit.expand,
      children: [child, if (isLoading) _buildOverlay()],
    );
  }

  Widget _buildOverlay() {
    return Container(
      color: barrierColor,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                // FIX: .withValues() is deprecated — use .withAlpha() instead.
                color: Colors.black.withAlpha(38),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
                strokeWidth: 3,
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  style: const TextStyle(
                    color: Color(0xFF546E7A),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  final String? message;

  const _LoadingDialog({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        margin: const EdgeInsets.symmetric(horizontal: 48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              // FIX: .withValues() is deprecated — use .withAlpha() instead.
              color: Colors.black.withAlpha(38),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
              strokeWidth: 3,
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: const TextStyle(
                  color: Color(0xFF546E7A),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
