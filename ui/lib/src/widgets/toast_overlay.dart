import 'dart:async';

import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class ToastOverlay extends StatefulWidget {
  const ToastOverlay({required this.child, required this.service, super.key});

  final Widget child;
  final ToastService service;

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  Changes? _currentData;
  String? _errorMessage;
  Timer? _hideTimer;
  StreamSubscription<Changes>? _toastSubscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _toastSubscription = widget.service.toastStream.listen(_showToast);
    _errorSubscription = widget.service.errorStream.listen(_showError);
  }

  @override
  void dispose() {
    _toastSubscription?.cancel();
    _errorSubscription?.cancel();
    _controller.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showToast(Changes data) {
    setState(() {
      final currentData = _currentData;
      if (currentData == null) {
        _currentData = data;
      } else {
        _currentData = currentData.merge(data);
      }
    });
    _resetHideTimer();
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _controller.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      _controller.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentData = null;
            _errorMessage = null;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentData = _currentData;
    final errorMessage = _errorMessage;
    final hasData = currentData != null && !currentData.isEmpty;
    final hasError = errorMessage != null;

    if (!hasData && !hasError) {
      return widget.child;
    }

    final bubbles = <Widget>[];

    // Add inventory change bubbles
    if (currentData != null) {
      for (final entry in currentData.inventoryChanges.entries) {
        bubbles.add(
          _buildBubble('${signedCountString(entry.value)} ${entry.key}'),
        );
      }

      // Add xp change bubbles
      for (final entry in currentData.skillXpChanges.entries) {
        bubbles.add(
          _buildBubble(
            '${signedCountString(entry.value)} ${entry.key.name} xp',
          ),
        );
      }

      // Add GP change bubble
      if (currentData.gpGained != 0) {
        bubbles.add(
          _buildBubble('${signedCountString(currentData.gpGained)} GP'),
        );
      }
    }

    // Add error bubble at the bottom
    if (errorMessage != null) {
      bubbles.add(_buildBubble(errorMessage, isError: true));
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 50,
          child: IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: _opacity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: bubbles,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(String text, {bool isError = false}) {
    return Material(
      color: Style.transparentColor,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: isError
              ? Style.toastBackgroundError
              : Style.toastBackgroundDefault,
        ),
        child: Text(
          text,
          style: const TextStyle(color: Style.textColorPrimary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
