import 'dart:async';

import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';

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
  Timer? _hideTimer;
  StreamSubscription<Changes>? _subscription;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _subscription = widget.service.toastStream.listen(_showToast);
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
    _controller.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      _controller.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentData = null;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentData = _currentData;
    if (currentData == null || currentData.isEmpty) {
      return widget.child;
    }

    final bubbles = <Widget>[];

    // Add inventory change bubbles
    for (final entry in currentData.inventoryChanges.entries) {
      bubbles.add(
        _buildBubble('${signedCountString(entry.value)} ${entry.key}'),
      );
    }

    // Add xp change bubbles
    for (final entry in currentData.skillXpChanges.entries) {
      bubbles.add(
        _buildBubble('${signedCountString(entry.value)} ${entry.key.name} xp'),
      );
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

  Widget _buildBubble(String text) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.black87,
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
