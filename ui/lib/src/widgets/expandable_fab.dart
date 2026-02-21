import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Data for a single action button in the expandable FAB.
class ExpandableFabAction {
  const ExpandableFabAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// An expandable floating action button that reveals child actions
/// when tapped.
///
/// Shows a main FAB that rotates when expanded, revealing labeled
/// action buttons stacked above it.
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({required this.actions, super.key});

  final List<ExpandableFabAction> actions;

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Reserve space for expanded actions.
      width: 200,
      height: 56.0 + widget.actions.length * 48.0 + 16,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // Scrim to dismiss when tapping outside.
          if (_isOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          // Child action buttons.
          ..._buildActions(),
          // Main FAB.
          FloatingActionButton(
            onPressed: _toggle,
            child: AnimatedBuilder(
              animation: _expandAnimation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _expandAnimation.value * math.pi / 4,
                  child: child,
                );
              },
              child: const Icon(Icons.handyman),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    final children = <Widget>[];
    for (var i = 0; i < widget.actions.length; i++) {
      final action = widget.actions[i];
      // Stack from bottom: first action closest to
      // main FAB.
      final offset = (i + 1) * 48.0 + 8.0;
      children.add(
        AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, child) {
            return Positioned(
              right: 4,
              bottom: offset * _expandAnimation.value,
              child: Opacity(opacity: _expandAnimation.value, child: child),
            );
          },
          child: _ActionButton(
            icon: action.icon,
            label: action.label,
            onPressed: () {
              _close();
              action.onPressed();
            },
          ),
        ),
      );
    }
    return children;
  }
}

/// A small labeled action button shown when the FAB is expanded.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ],
    );
  }
}
