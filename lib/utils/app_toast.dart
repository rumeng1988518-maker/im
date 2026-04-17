import 'dart:async';

import 'package:flutter/material.dart';

class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    final text = message.trim();
    if (text.isEmpty) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _hideTimer?.cancel();
    _currentEntry?.remove();

    final entry = OverlayEntry(
      builder: (_) => _ToastText(message: text),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _hideTimer = Timer(duration, () {
      _currentEntry?.remove();
      _currentEntry = null;
    });
  }
}

class _ToastText extends StatelessWidget {
  const _ToastText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 96),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
