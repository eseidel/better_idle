import 'package:flutter/material.dart';

/// Wraps a button and shows a tooltip explaining why it's disabled.
///
/// When [message] is non-null, the child is wrapped in [IgnorePointer]
/// (so the disabled button doesn't eat the tap) and a [Tooltip] that
/// triggers on tap. When [message] is null, the child is returned as-is.
class DisabledButtonTooltip extends StatelessWidget {
  const DisabledButtonTooltip({
    required this.message,
    required this.child,
    super.key,
  });

  /// The tooltip message to show, or null if the button is enabled.
  final String? message;

  /// The button widget to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (message == null) return child;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: IgnorePointer(child: child),
    );
  }
}
