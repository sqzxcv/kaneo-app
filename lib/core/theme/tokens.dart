import 'package:flutter/material.dart';

/// The web app's theme variables (`kaneo/apps/web/src/index.css`), resolved to sRGB. Light values
/// come from `:root`, dark values from `.dark`. Read them with `context.colors`.
@immutable
class KaneoColors extends ThemeExtension<KaneoColors> {
  const KaneoColors({
    required this.accent,
    required this.accentForeground,
    required this.background,
    required this.border,
    required this.card,
    required this.cardForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.foreground,
    required this.info,
    required this.infoForeground,
    required this.input,
    required this.muted,
    required this.mutedForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.ring,
    required this.secondary,
    required this.secondaryForeground,
    required this.success,
    required this.successForeground,
    required this.warning,
    required this.warningForeground,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
    required this.code,
    required this.codeForeground,
    required this.codeHighlight,
    required this.boardLane,
    required this.boardCard,
    required this.boardCardBorder,
    required this.boardCardBorderHover,
    required this.boardCardSelected,
    required this.boardCardSelectedBorder,
    required this.boardCardFocus,
    required this.boardCardRing,
    required this.boardCardDone,
    required this.boardCardDoneBorder,
    required this.boardId,
    required this.boardIdDone,
    required this.boardTitle,
    required this.boardTitleDone,
    required this.chipBorder,
    required this.chipBorderHover,
    required this.chipHover,
    required this.chipBorderOpen,
    required this.chipOpen,
    required this.chipForeground,
    required this.chipMuted,
    required this.chipIcon,
    required this.priorityBar,
    required this.priorityBarEmpty,
    required this.priorityLow,
    required this.priorityMedium,
    required this.priorityHigh,
    required this.priorityUrgent,
    required this.dueOverdue,
    required this.avatar,
    required this.avatarSelected,
    required this.avatarDone,
    required this.avatarBorder,
    required this.avatarForeground,
    required this.avatarForegroundDone,
    required this.avatarUnassigned,
    required this.avatarUnassignedForeground,
  });

  final Color accent;
  final Color accentForeground;
  final Color background;
  final Color border;
  final Color card;
  final Color cardForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color foreground;
  final Color info;
  final Color infoForeground;
  final Color input;
  final Color muted;
  final Color mutedForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryForeground;
  final Color ring;
  final Color secondary;
  final Color secondaryForeground;
  final Color success;
  final Color successForeground;
  final Color warning;
  final Color warningForeground;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;
  final Color code;
  final Color codeForeground;
  final Color codeHighlight;
  final Color boardLane;
  final Color boardCard;
  final Color boardCardBorder;
  final Color boardCardBorderHover;
  final Color boardCardSelected;
  final Color boardCardSelectedBorder;
  final Color boardCardFocus;
  final Color boardCardRing;
  final Color boardCardDone;
  final Color boardCardDoneBorder;
  final Color boardId;
  final Color boardIdDone;
  final Color boardTitle;
  final Color boardTitleDone;
  final Color chipBorder;
  final Color chipBorderHover;
  final Color chipHover;
  final Color chipBorderOpen;
  final Color chipOpen;
  final Color chipForeground;
  final Color chipMuted;
  final Color chipIcon;
  final Color priorityBar;
  final Color priorityBarEmpty;
  final Color priorityLow;
  final Color priorityMedium;
  final Color priorityHigh;
  final Color priorityUrgent;
  final Color dueOverdue;
  final Color avatar;
  final Color avatarSelected;
  final Color avatarDone;
  final Color avatarBorder;
  final Color avatarForeground;
  final Color avatarForegroundDone;
  final Color avatarUnassigned;
  final Color avatarUnassignedForeground;

  static const light = KaneoColors(
    accent: Color(0x0A000000),
    accentForeground: Color(0xFF262626),
    background: Color(0xFFFFFFFF),
    border: Color(0x14000000),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF262626),
    destructive: Color(0xFFFB2C36),
    destructiveForeground: Color(0xFFC10007),
    foreground: Color(0xFF262626),
    info: Color(0xFF2B7FFF),
    infoForeground: Color(0xFF1447E6),
    input: Color(0x1A000000),
    muted: Color(0x0A000000),
    mutedForeground: Color(0xFF686868),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF262626),
    primary: Color(0xFF262626),
    primaryForeground: Color(0xFFFAFAFA),
    ring: Color(0xFFA1A1A1),
    secondary: Color(0x0A000000),
    secondaryForeground: Color(0xFF262626),
    success: Color(0xFF00BC7D),
    successForeground: Color(0xFF007A55),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFBB4D00),
    sidebar: Color(0xFFFAFAFA),
    sidebarForeground: Color(0xFF727272),
    sidebarPrimary: Color(0xFF262626),
    sidebarPrimaryForeground: Color(0xFFFAFAFA),
    sidebarAccent: Color(0x0A000000),
    sidebarAccentForeground: Color(0xFF262626),
    sidebarBorder: Color(0x0F000000),
    sidebarRing: Color(0xFFA1A1A1),
    code: Color(0xFFFFFFFF),
    codeForeground: Color(0xFF262626),
    codeHighlight: Color(0x0A000000),
    boardLane: Color(0x05000000),
    boardCard: Color(0xFFFFFFFF),
    boardCardBorder: Color(0x14000000),
    boardCardBorderHover: Color(0x2E000000),
    boardCardSelected: Color(0xFFF2F2F2),
    boardCardSelectedBorder: Color(0x38000000),
    boardCardFocus: Color(0xFF8A8A8A),
    boardCardRing: Color(0x408A8A8A),
    boardCardDone: Color(0x99FFFFFF),
    boardCardDoneBorder: Color(0x0F000000),
    boardId: Color(0xFF8A8A8A),
    boardIdDone: Color(0xFFA3A3A3),
    boardTitle: Color(0xFF171717),
    boardTitleDone: Color(0xFF737373),
    chipBorder: Color(0x17000000),
    chipBorderHover: Color(0x29000000),
    chipHover: Color(0x0A000000),
    chipBorderOpen: Color(0x33000000),
    chipOpen: Color(0x0F000000),
    chipForeground: Color(0xFF404040),
    chipMuted: Color(0xFF737373),
    chipIcon: Color(0xFF8A8A8A),
    priorityBar: Color(0xFF525252),
    priorityBarEmpty: Color(0x21000000),
    priorityLow: Color(0xFF2563EB),
    priorityMedium: Color(0xFFD97706),
    priorityHigh: Color(0xFFEA580C),
    priorityUrgent: Color(0xFFDC2626),
    dueOverdue: Color(0xFFDC2626),
    avatar: Color(0xFFE5E5E5),
    avatarSelected: Color(0xFFE0E0E0),
    avatarDone: Color(0xFFEDEDED),
    avatarBorder: Color(0x17000000),
    avatarForeground: Color(0xFF404040),
    avatarForegroundDone: Color(0xFF737373),
    avatarUnassigned: Color(0xFFF5F5F5),
    avatarUnassignedForeground: Color(0xFF8A8A8A),
  );

  static const dark = KaneoColors(
    accent: Color(0x0AFFFFFF),
    accentForeground: Color(0xFFF5F5F5),
    background: Color(0xFF141414),
    border: Color(0x0FFFFFFF),
    card: Color(0xFF191919),
    cardForeground: Color(0xFFF5F5F5),
    destructive: Color(0xFFFB414A),
    destructiveForeground: Color(0xFFFF6467),
    foreground: Color(0xFFF5F5F5),
    info: Color(0xFF2B7FFF),
    infoForeground: Color(0xFF51A2FF),
    input: Color(0x14FFFFFF),
    muted: Color(0x0AFFFFFF),
    mutedForeground: Color(0xFF818181),
    popover: Color(0xFF191919),
    popoverForeground: Color(0xFFF5F5F5),
    primary: Color(0xFFF5F5F5),
    primaryForeground: Color(0xFF262626),
    ring: Color(0xFF737373),
    secondary: Color(0x0AFFFFFF),
    secondaryForeground: Color(0xFFF5F5F5),
    success: Color(0xFF00BC7D),
    successForeground: Color(0xFF00D492),
    warning: Color(0xFFFE9A00),
    warningForeground: Color(0xFFFFB900),
    sidebar: Color(0xFF111111),
    sidebarForeground: Color(0xFFA3A3A3),
    sidebarPrimary: Color(0xFFF5F5F5),
    sidebarPrimaryForeground: Color(0xFF262626),
    sidebarAccent: Color(0x0AFFFFFF),
    sidebarAccentForeground: Color(0xFFF5F5F5),
    sidebarBorder: Color(0x0DFFFFFF),
    sidebarRing: Color(0xFFA1A1A1),
    code: Color(0xFF191919),
    codeForeground: Color(0xFFF5F5F5),
    codeHighlight: Color(0x0AFFFFFF),
    boardLane: Color(0x1F000000),
    boardCard: Color(0xFF1C1C1C),
    boardCardBorder: Color(0x00000000),
    boardCardBorderHover: Color(0x2EFFFFFF),
    boardCardSelected: Color(0xFF262626),
    boardCardSelectedBorder: Color(0x3DFFFFFF),
    boardCardFocus: Color(0xFFA3A3A3),
    boardCardRing: Color(0x33A3A3A3),
    boardCardDone: Color(0x03FFFFFF),
    boardCardDoneBorder: Color(0x0AFFFFFF),
    boardId: Color(0xFF707070),
    boardIdDone: Color(0xFF5C5C5C),
    boardTitle: Color(0xFFEDEDED),
    boardTitleDone: Color(0xFF707070),
    chipBorder: Color(0x17FFFFFF),
    chipBorderHover: Color(0x29FFFFFF),
    chipHover: Color(0x0AFFFFFF),
    chipBorderOpen: Color(0x33FFFFFF),
    chipOpen: Color(0x0FFFFFFF),
    chipForeground: Color(0xFFCFCFCF),
    chipMuted: Color(0xFF8F8F8F),
    chipIcon: Color(0xFF8A8A8A),
    priorityBar: Color(0xFFA3A3A3),
    priorityBarEmpty: Color(0x24FFFFFF),
    priorityLow: Color(0xFF60A5FA),
    priorityMedium: Color(0xFFFBBF24),
    priorityHigh: Color(0xFFFB923C),
    priorityUrgent: Color(0xFFE5484D),
    dueOverdue: Color(0xFFFF6467),
    avatar: Color(0xFF2E2E2E),
    avatarSelected: Color(0xFF383838),
    avatarDone: Color(0xFF222222),
    avatarBorder: Color(0x17FFFFFF),
    avatarForeground: Color(0xFFD4D4D4),
    avatarForegroundDone: Color(0xFF707070),
    avatarUnassigned: Color(0xFF262626),
    avatarUnassignedForeground: Color(0xFF8A8A8A),
  );

  @override
  KaneoColors copyWith({
    Color? accent,
    Color? accentForeground,
    Color? background,
    Color? border,
    Color? card,
    Color? cardForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? foreground,
    Color? info,
    Color? infoForeground,
    Color? input,
    Color? muted,
    Color? mutedForeground,
    Color? popover,
    Color? popoverForeground,
    Color? primary,
    Color? primaryForeground,
    Color? ring,
    Color? secondary,
    Color? secondaryForeground,
    Color? success,
    Color? successForeground,
    Color? warning,
    Color? warningForeground,
    Color? sidebar,
    Color? sidebarForeground,
    Color? sidebarPrimary,
    Color? sidebarPrimaryForeground,
    Color? sidebarAccent,
    Color? sidebarAccentForeground,
    Color? sidebarBorder,
    Color? sidebarRing,
    Color? code,
    Color? codeForeground,
    Color? codeHighlight,
    Color? boardLane,
    Color? boardCard,
    Color? boardCardBorder,
    Color? boardCardBorderHover,
    Color? boardCardSelected,
    Color? boardCardSelectedBorder,
    Color? boardCardFocus,
    Color? boardCardRing,
    Color? boardCardDone,
    Color? boardCardDoneBorder,
    Color? boardId,
    Color? boardIdDone,
    Color? boardTitle,
    Color? boardTitleDone,
    Color? chipBorder,
    Color? chipBorderHover,
    Color? chipHover,
    Color? chipBorderOpen,
    Color? chipOpen,
    Color? chipForeground,
    Color? chipMuted,
    Color? chipIcon,
    Color? priorityBar,
    Color? priorityBarEmpty,
    Color? priorityLow,
    Color? priorityMedium,
    Color? priorityHigh,
    Color? priorityUrgent,
    Color? dueOverdue,
    Color? avatar,
    Color? avatarSelected,
    Color? avatarDone,
    Color? avatarBorder,
    Color? avatarForeground,
    Color? avatarForegroundDone,
    Color? avatarUnassigned,
    Color? avatarUnassignedForeground,
  }) => KaneoColors(
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    background: background ?? this.background,
    border: border ?? this.border,
    card: card ?? this.card,
    cardForeground: cardForeground ?? this.cardForeground,
    destructive: destructive ?? this.destructive,
    destructiveForeground: destructiveForeground ?? this.destructiveForeground,
    foreground: foreground ?? this.foreground,
    info: info ?? this.info,
    infoForeground: infoForeground ?? this.infoForeground,
    input: input ?? this.input,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    popover: popover ?? this.popover,
    popoverForeground: popoverForeground ?? this.popoverForeground,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    ring: ring ?? this.ring,
    secondary: secondary ?? this.secondary,
    secondaryForeground: secondaryForeground ?? this.secondaryForeground,
    success: success ?? this.success,
    successForeground: successForeground ?? this.successForeground,
    warning: warning ?? this.warning,
    warningForeground: warningForeground ?? this.warningForeground,
    sidebar: sidebar ?? this.sidebar,
    sidebarForeground: sidebarForeground ?? this.sidebarForeground,
    sidebarPrimary: sidebarPrimary ?? this.sidebarPrimary,
    sidebarPrimaryForeground: sidebarPrimaryForeground ?? this.sidebarPrimaryForeground,
    sidebarAccent: sidebarAccent ?? this.sidebarAccent,
    sidebarAccentForeground: sidebarAccentForeground ?? this.sidebarAccentForeground,
    sidebarBorder: sidebarBorder ?? this.sidebarBorder,
    sidebarRing: sidebarRing ?? this.sidebarRing,
    code: code ?? this.code,
    codeForeground: codeForeground ?? this.codeForeground,
    codeHighlight: codeHighlight ?? this.codeHighlight,
    boardLane: boardLane ?? this.boardLane,
    boardCard: boardCard ?? this.boardCard,
    boardCardBorder: boardCardBorder ?? this.boardCardBorder,
    boardCardBorderHover: boardCardBorderHover ?? this.boardCardBorderHover,
    boardCardSelected: boardCardSelected ?? this.boardCardSelected,
    boardCardSelectedBorder: boardCardSelectedBorder ?? this.boardCardSelectedBorder,
    boardCardFocus: boardCardFocus ?? this.boardCardFocus,
    boardCardRing: boardCardRing ?? this.boardCardRing,
    boardCardDone: boardCardDone ?? this.boardCardDone,
    boardCardDoneBorder: boardCardDoneBorder ?? this.boardCardDoneBorder,
    boardId: boardId ?? this.boardId,
    boardIdDone: boardIdDone ?? this.boardIdDone,
    boardTitle: boardTitle ?? this.boardTitle,
    boardTitleDone: boardTitleDone ?? this.boardTitleDone,
    chipBorder: chipBorder ?? this.chipBorder,
    chipBorderHover: chipBorderHover ?? this.chipBorderHover,
    chipHover: chipHover ?? this.chipHover,
    chipBorderOpen: chipBorderOpen ?? this.chipBorderOpen,
    chipOpen: chipOpen ?? this.chipOpen,
    chipForeground: chipForeground ?? this.chipForeground,
    chipMuted: chipMuted ?? this.chipMuted,
    chipIcon: chipIcon ?? this.chipIcon,
    priorityBar: priorityBar ?? this.priorityBar,
    priorityBarEmpty: priorityBarEmpty ?? this.priorityBarEmpty,
    priorityLow: priorityLow ?? this.priorityLow,
    priorityMedium: priorityMedium ?? this.priorityMedium,
    priorityHigh: priorityHigh ?? this.priorityHigh,
    priorityUrgent: priorityUrgent ?? this.priorityUrgent,
    dueOverdue: dueOverdue ?? this.dueOverdue,
    avatar: avatar ?? this.avatar,
    avatarSelected: avatarSelected ?? this.avatarSelected,
    avatarDone: avatarDone ?? this.avatarDone,
    avatarBorder: avatarBorder ?? this.avatarBorder,
    avatarForeground: avatarForeground ?? this.avatarForeground,
    avatarForegroundDone: avatarForegroundDone ?? this.avatarForegroundDone,
    avatarUnassigned: avatarUnassigned ?? this.avatarUnassigned,
    avatarUnassignedForeground: avatarUnassignedForeground ?? this.avatarUnassignedForeground,
  );

  @override
  KaneoColors lerp(ThemeExtension<KaneoColors>? other, double t) {
    if (other is! KaneoColors) return this;
    return KaneoColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
      background: Color.lerp(background, other.background, t)!,
      border: Color.lerp(border, other.border, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      destructiveForeground: Color.lerp(destructiveForeground, other.destructiveForeground, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoForeground: Color.lerp(infoForeground, other.infoForeground, t)!,
      input: Color.lerp(input, other.input, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      popover: Color.lerp(popover, other.popover, t)!,
      popoverForeground: Color.lerp(popoverForeground, other.popoverForeground, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(primaryForeground, other.primaryForeground, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryForeground: Color.lerp(secondaryForeground, other.secondaryForeground, t)!,
      success: Color.lerp(success, other.success, t)!,
      successForeground: Color.lerp(successForeground, other.successForeground, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningForeground: Color.lerp(warningForeground, other.warningForeground, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarForeground: Color.lerp(sidebarForeground, other.sidebarForeground, t)!,
      sidebarPrimary: Color.lerp(sidebarPrimary, other.sidebarPrimary, t)!,
      sidebarPrimaryForeground: Color.lerp(
        sidebarPrimaryForeground,
        other.sidebarPrimaryForeground,
        t,
      )!,
      sidebarAccent: Color.lerp(sidebarAccent, other.sidebarAccent, t)!,
      sidebarAccentForeground: Color.lerp(
        sidebarAccentForeground,
        other.sidebarAccentForeground,
        t,
      )!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      sidebarRing: Color.lerp(sidebarRing, other.sidebarRing, t)!,
      code: Color.lerp(code, other.code, t)!,
      codeForeground: Color.lerp(codeForeground, other.codeForeground, t)!,
      codeHighlight: Color.lerp(codeHighlight, other.codeHighlight, t)!,
      boardLane: Color.lerp(boardLane, other.boardLane, t)!,
      boardCard: Color.lerp(boardCard, other.boardCard, t)!,
      boardCardBorder: Color.lerp(boardCardBorder, other.boardCardBorder, t)!,
      boardCardBorderHover: Color.lerp(boardCardBorderHover, other.boardCardBorderHover, t)!,
      boardCardSelected: Color.lerp(boardCardSelected, other.boardCardSelected, t)!,
      boardCardSelectedBorder: Color.lerp(
        boardCardSelectedBorder,
        other.boardCardSelectedBorder,
        t,
      )!,
      boardCardFocus: Color.lerp(boardCardFocus, other.boardCardFocus, t)!,
      boardCardRing: Color.lerp(boardCardRing, other.boardCardRing, t)!,
      boardCardDone: Color.lerp(boardCardDone, other.boardCardDone, t)!,
      boardCardDoneBorder: Color.lerp(boardCardDoneBorder, other.boardCardDoneBorder, t)!,
      boardId: Color.lerp(boardId, other.boardId, t)!,
      boardIdDone: Color.lerp(boardIdDone, other.boardIdDone, t)!,
      boardTitle: Color.lerp(boardTitle, other.boardTitle, t)!,
      boardTitleDone: Color.lerp(boardTitleDone, other.boardTitleDone, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      chipBorderHover: Color.lerp(chipBorderHover, other.chipBorderHover, t)!,
      chipHover: Color.lerp(chipHover, other.chipHover, t)!,
      chipBorderOpen: Color.lerp(chipBorderOpen, other.chipBorderOpen, t)!,
      chipOpen: Color.lerp(chipOpen, other.chipOpen, t)!,
      chipForeground: Color.lerp(chipForeground, other.chipForeground, t)!,
      chipMuted: Color.lerp(chipMuted, other.chipMuted, t)!,
      chipIcon: Color.lerp(chipIcon, other.chipIcon, t)!,
      priorityBar: Color.lerp(priorityBar, other.priorityBar, t)!,
      priorityBarEmpty: Color.lerp(priorityBarEmpty, other.priorityBarEmpty, t)!,
      priorityLow: Color.lerp(priorityLow, other.priorityLow, t)!,
      priorityMedium: Color.lerp(priorityMedium, other.priorityMedium, t)!,
      priorityHigh: Color.lerp(priorityHigh, other.priorityHigh, t)!,
      priorityUrgent: Color.lerp(priorityUrgent, other.priorityUrgent, t)!,
      dueOverdue: Color.lerp(dueOverdue, other.dueOverdue, t)!,
      avatar: Color.lerp(avatar, other.avatar, t)!,
      avatarSelected: Color.lerp(avatarSelected, other.avatarSelected, t)!,
      avatarDone: Color.lerp(avatarDone, other.avatarDone, t)!,
      avatarBorder: Color.lerp(avatarBorder, other.avatarBorder, t)!,
      avatarForeground: Color.lerp(avatarForeground, other.avatarForeground, t)!,
      avatarForegroundDone: Color.lerp(avatarForegroundDone, other.avatarForegroundDone, t)!,
      avatarUnassigned: Color.lerp(avatarUnassigned, other.avatarUnassigned, t)!,
      avatarUnassignedForeground: Color.lerp(
        avatarUnassignedForeground,
        other.avatarUnassignedForeground,
        t,
      )!,
    );
  }
}

/// The web app's `--radius` scale.
abstract final class KaneoRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;
}

/// The web app's font stacks. Geist ships in `assets/fonts`; other scripts, such as Chinese, fall
/// back to the system font.
abstract final class KaneoFonts {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';
}
