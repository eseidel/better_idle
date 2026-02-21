import 'package:flutter/material.dart';

class Style {
  // Cell backgrounds
  static Color cellBackgroundColor = Colors.grey.shade800;
  static Color cellBackgroundColorLight = Colors.grey.shade200;
  static Color cellBackgroundColorDepleted = Colors.grey.shade700;
  static Color cellBackgroundColorLocked = Colors.grey.shade900;
  static Color cellBackgroundColorStunned = Colors.orange.shade900;

  // Cell borders
  static Color cellBorderColor = Colors.grey.shade600;
  static Color cellBorderColorActive = Colors.orange;
  static Color cellBorderColorSelected = Colors.blue;
  static Color cellBorderColorSuccess = Colors.green.shade700;

  // Text colors
  static const Color textColorPrimary = Colors.white;
  static const Color textColorSecondary = Colors.grey;
  static Color textColorMuted = Colors.grey.shade600;
  static Color textColorSuccess = Colors.green.shade700;
  static Color textColorError = Colors.red.shade700;
  static Color textColorWarning = Colors.orange;
  static Color textColorInfo = Colors.blue.shade700;

  // Badge colors
  static Color badgeBackgroundColor = Colors.grey.shade600;
  static const Color badgeTextColor = Colors.white;

  // Button colors
  static const Color buttonBackgroundSuccess = Colors.green;
  static const Color buttonBackgroundWarning = Colors.orange;
  static const Color buttonForegroundLight = Colors.white;
  static Color buttonBackgroundDisabled = Colors.grey.shade300;

  // Progress bar colors
  static Color progressBackgroundColor = Colors.grey.shade700;
  static Color progressForegroundColor = Colors.lightBlue;
  static Color progressForegroundColorSuccess = Colors.green;
  static Color progressForegroundColorWarning = Colors.orange;
  static Color progressForegroundColorError = Colors.red;
  static Color progressForegroundColorMuted = Colors.grey.shade600;

  // Semantic colors
  static const Color activeColor = Colors.orange;
  static Color activeColorLight = Colors.orange.withValues(alpha: 0.1);
  static const Color selectedColor = Colors.blue;
  static Color selectedColorLight = Colors.blue.withValues(alpha: 0.1);
  static const Color successColor = Colors.green;
  static const Color errorColor = Colors.red;
  static Color errorColorLight = Colors.red.withValues(alpha: 0.1);
  static const Color warningColor = Colors.orange;

  // Icon colors
  static const Color iconColorDefault = Colors.grey;
  static const Color iconColorSuccess = Colors.green;
  static const Color iconColorError = Colors.red;
  static const Color iconColorInfo = Colors.blue;
  static const Color iconColorWarning = Colors.orange;

  // Specific component colors
  static const Color toastBackgroundError = Color(
    0xFFD32F2F,
  ); // Colors.red[700]
  static const Color toastBackgroundDefault = Color(
    0xDD000000,
  ); // Colors.black87
  static const Color transparentColor = Colors.transparent;

  // Header/drawer colors
  static const Color drawerHeaderColor = Colors.blue;

  // Health bar colors
  static const Color healthBarColor = Colors.red;
  static const Color healColor = Colors.green;

  // XP badge colors
  static Color xpBadgeBackgroundColor = Colors.grey.shade700;
  static Color xpBadgeIconColor = Colors.grey.shade200;

  // Duration badge colors
  static Color durationBadgeBackgroundColor = Colors.grey.shade700;

  // Mastery pool colors
  static Color masteryPoolBorderColor = Colors.amber.shade700;
  static Color masteryPoolBackgroundColor = Colors.amber.shade100;

  // Rock type colors
  static Color rockTypeEssenceColor = Colors.green.shade200;
  static Color rockTypeOreColor = Colors.orange.shade200;

  // Combat/food slot colors
  static Color foodSlotFilledColor = Colors.green.shade500;
  static Color foodSlotEmptyColor = Colors.grey.shade600;

  // Category/area header color (used in fishing, thieving, smithing, etc.)
  static Color categoryHeaderColor = Colors.blueGrey.shade600;

  // Thieving specific colors
  static Color thievingNpcUnlockedColor = Colors.grey.shade200;
  static Color fishingAreaSelectedColor = Colors.blueGrey.shade700;

  // Shop colors
  static Color shopPurchasedColor = Colors.orange.shade700;
  static Color unmetRequirementColor = const Color(0xFFE56767);

  // Container/card backgrounds
  static Color containerBackgroundLight = Colors.grey.shade800;
  static Color containerBackgroundFilled = Colors.green.shade600;
  static Color containerBackgroundEmpty = Colors.grey.shade800;

  // Level text color
  static Color levelTextColor = Colors.grey.shade600;

  // Player HP bar color
  static const Color playerHpBarColor = Colors.green;

  // Monster HP bar color
  static const Color monsterHpBarColor = Colors.red;

  // Attack bar color
  static const Color attackBarColor = Colors.orange;

  // Progress bar text colors
  static const Color progressTextDark = Colors.black87;

  // Stunned text color
  static Color stunnedTextColor = Colors.red.shade800;

  // Currency/stat value text color (used in nav drawer for GP, SC, HP, Prayer)
  static const Color currencyValueColor = Colors.green;
}
