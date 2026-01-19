import 'package:better_idle/src/widgets/game_app_bar.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A Scaffold with GameAppBar and AppNavigationDrawer built in.
///
/// Use this instead of [Scaffold] to automatically include the game's
/// standard app bar (with equipment button) and navigation drawer.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    required this.title,
    required this.body,
    super.key,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.floatingActionButtonAnimator,
    this.persistentFooterButtons,
    this.persistentFooterAlignment,
    this.endDrawer,
    this.endDrawerEnableOpenDragGesture,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.primary,
    this.drawerDragStartBehavior,
    this.extendBody,
    this.extendBodyBehindAppBar,
    this.drawerScrimColor,
    this.drawerEdgeDragWidth,
    this.drawerEnableOpenDragGesture,
    this.onDrawerChanged,
    this.onEndDrawerChanged,
    this.restorationId,
  });

  /// The title widget for the app bar.
  final Widget title;

  /// The primary content of the scaffold.
  final Widget body;

  /// Additional actions for the app bar (equipment button is added
  /// automatically).
  final List<Widget>? actions;

  /// A widget to display below the app bar (e.g., TabBar).
  final PreferredSizeWidget? bottom;

  // Pass-through Scaffold parameters
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final FloatingActionButtonAnimator? floatingActionButtonAnimator;
  final List<Widget>? persistentFooterButtons;
  final AlignmentDirectional? persistentFooterAlignment;
  final Widget? endDrawer;
  final bool? endDrawerEnableOpenDragGesture;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool? primary;
  final DragStartBehavior? drawerDragStartBehavior;
  final bool? extendBody;
  final bool? extendBodyBehindAppBar;
  final Color? drawerScrimColor;
  final double? drawerEdgeDragWidth;
  final bool? drawerEnableOpenDragGesture;
  final DrawerCallback? onDrawerChanged;
  final DrawerCallback? onEndDrawerChanged;
  final String? restorationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GameAppBar(title: title, actions: actions, bottom: bottom),
      drawer: const AppNavigationDrawer(),
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      floatingActionButtonAnimator: floatingActionButtonAnimator,
      persistentFooterButtons: persistentFooterButtons,
      persistentFooterAlignment:
          persistentFooterAlignment ?? AlignmentDirectional.centerEnd,
      endDrawer: endDrawer,
      endDrawerEnableOpenDragGesture: endDrawerEnableOpenDragGesture ?? true,
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      primary: primary ?? true,
      drawerDragStartBehavior:
          drawerDragStartBehavior ?? DragStartBehavior.start,
      extendBody: extendBody ?? false,
      extendBodyBehindAppBar: extendBodyBehindAppBar ?? false,
      drawerScrimColor: drawerScrimColor,
      drawerEdgeDragWidth: drawerEdgeDragWidth,
      drawerEnableOpenDragGesture: drawerEnableOpenDragGesture ?? true,
      onDrawerChanged: onDrawerChanged,
      onEndDrawerChanged: onEndDrawerChanged,
      restorationId: restorationId,
    );
  }
}
