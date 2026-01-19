import 'package:better_idle/src/widgets/equipment_slots.dart';
import 'package:flutter/material.dart';

/// An AppBar that includes global game actions (equipment, etc.) in trailing.
///
/// Use this instead of [AppBar] to automatically include equipment button
/// and other global actions that should appear on every screen.
class GameAppBar extends AppBar {
  GameAppBar({
    required Widget title,
    super.key,
    super.leading,
    super.automaticallyImplyLeading,
    super.flexibleSpace,
    super.bottom,
    super.elevation,
    super.scrolledUnderElevation,
    super.notificationPredicate,
    super.shadowColor,
    super.surfaceTintColor,
    super.shape,
    super.backgroundColor,
    super.foregroundColor,
    super.iconTheme,
    super.actionsIconTheme,
    super.primary,
    super.centerTitle,
    super.excludeHeaderSemantics,
    super.titleSpacing,
    super.toolbarOpacity,
    super.bottomOpacity,
    super.toolbarHeight,
    super.leadingWidth,
    super.toolbarTextStyle,
    super.titleTextStyle,
    super.systemOverlayStyle,
    super.forceMaterialTransparency,
    super.clipBehavior,
    List<Widget>? actions,
  }) : super(title: title, actions: [...?actions, const _EquipmentButton()]);
}

class _EquipmentButton extends StatelessWidget {
  const _EquipmentButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.shield_outlined),
      tooltip: 'Equipment',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const EquipmentGridDialog(),
      ),
    );
  }
}
