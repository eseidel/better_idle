import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/services/toast_service.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/pet_found_dialog.dart';
import 'package:ui/src/widgets/router.dart' show navigatorKey;
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_milestone_dialog.dart';
import 'package:ui/src/widgets/style.dart';
import 'package:ui/src/widgets/you_died_dialog.dart';

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
  StreamSubscription<Counts<MelvorId>>? _deathSubscription;
  StreamSubscription<MelvorId>? _petSubscription;
  StreamSubscription<Skill>? _skillMilestoneSubscription;
  bool _isDeathDialogShowing = false;
  bool _isPetDialogShowing = false;
  final _petQueue = <MelvorId>[];
  bool _isSkillMilestoneDialogShowing = false;
  final _skillMilestoneQueue = <Skill>[];

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
    _deathSubscription = widget.service.deathStream.listen(_showDeathDialog);
    _petSubscription = widget.service.petUnlockedStream.listen(
      _showPetFoundDialog,
    );
    _skillMilestoneSubscription = widget.service.skillMilestoneStream.listen(
      _showSkillMilestoneDialog,
    );
  }

  @override
  void dispose() {
    _toastSubscription?.cancel();
    _errorSubscription?.cancel();
    _deathSubscription?.cancel();
    _petSubscription?.cancel();
    _skillMilestoneSubscription?.cancel();
    _controller.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showDeathDialog(Counts<MelvorId> lostOnDeath) {
    if (_isDeathDialogShowing) return;
    // ToastOverlay sits above the Navigator (in MaterialApp.builder),
    // so we must use navigatorKey to get a context below the Navigator.
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    _isDeathDialogShowing = true;

    showDialog<void>(
      context: navContext,
      builder: (context) => YouDiedDialog(
        lostOnDeath: lostOnDeath,
        registries: navContext.state.registries,
      ),
    ).then((_) {
      if (mounted) {
        _isDeathDialogShowing = false;
      }
    });
  }

  void _showPetFoundDialog(MelvorId petId) {
    _petQueue.add(petId);
    _showNextPetDialog();
  }

  void _showNextPetDialog() {
    if (_isPetDialogShowing || _petQueue.isEmpty) return;
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    _isPetDialogShowing = true;

    final petId = _petQueue.removeAt(0);
    final registries = navContext.state.registries;
    final pet = registries.pets.byId(petId);

    showDialog<void>(
      context: navContext,
      builder: (context) => PetFoundDialog(
        pet: pet,
        modifierMetadata: registries.modifierMetadata,
      ),
    ).then((_) {
      if (mounted) {
        _isPetDialogShowing = false;
        _showNextPetDialog();
      }
    });
  }

  void _showSkillMilestoneDialog(Skill skill) {
    _skillMilestoneQueue.add(skill);
    _showNextSkillMilestoneDialog();
  }

  void _showNextSkillMilestoneDialog() {
    if (_isSkillMilestoneDialogShowing || _skillMilestoneQueue.isEmpty) return;
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;
    _isSkillMilestoneDialogShowing = true;

    final skill = _skillMilestoneQueue.removeAt(0);

    showDialog<void>(
      context: navContext,
      builder: (context) => SkillMilestoneDialog(skill: skill),
    ).then((_) {
      if (mounted) {
        _isSkillMilestoneDialogShowing = false;
        _showNextSkillMilestoneDialog();
      }
    });
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
        final item = context.state.registries.items.byId(entry.key);
        bubbles.add(_buildItemBubble(item, entry.value));
      }

      // Add xp change bubbles
      for (final entry in currentData.skillXpChanges.entries) {
        bubbles.add(_buildSkillXpBubble(entry.key, entry.value));
      }

      // Add currency change bubbles
      for (final entry in currentData.currenciesGained.entries) {
        bubbles.add(_buildCurrencyBubble(entry.key, entry.value));
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

  Widget _buildItemBubble(Item item, int count) {
    return Material(
      color: Style.transparentColor,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Style.toastBackgroundDefault,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ItemImage(item: item, size: 20),
            const SizedBox(width: 8),
            Text(
              signedCountString(count),
              style: const TextStyle(color: Style.textColorPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillXpBubble(Skill skill, int xp) {
    return Material(
      color: Style.transparentColor,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Style.toastBackgroundDefault,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkillImage(skill: skill, size: 20),
            const SizedBox(width: 8),
            Text(
              '${signedCountString(xp)} XP',
              style: const TextStyle(color: Style.textColorPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyBubble(Currency currency, int amount) {
    return Material(
      color: Style.transparentColor,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Style.toastBackgroundDefault,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedImage(assetPath: currency.assetPath, size: 20),
            const SizedBox(width: 8),
            Text(
              signedCountString(amount),
              style: const TextStyle(color: Style.textColorPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
