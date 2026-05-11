import 'package:flutter/material.dart';

class ConnectionButtonTheme extends ThemeExtension<ConnectionButtonTheme> {
  const ConnectionButtonTheme({
    this.idleColor,
    this.connectedColor,
  });

  final Color? idleColor;
  final Color? connectedColor;

  static const ConnectionButtonTheme light = ConnectionButtonTheme(
    idleColor: Color(0xFF4a4d8b),
    connectedColor: Color(0xFF44a334),
  );

  @override
  ThemeExtension<ConnectionButtonTheme> copyWith({
    Color? idleColor,
    Color? connectedColor,
  }) =>
      ConnectionButtonTheme(
        idleColor: idleColor ?? this.idleColor,
        connectedColor: connectedColor ?? this.connectedColor,
      );

  @override
  ThemeExtension<ConnectionButtonTheme> lerp(
    covariant ThemeExtension<ConnectionButtonTheme>? other,
    double t,
  ) {
    if (other is! ConnectionButtonTheme) {
      return this;
    }
    return ConnectionButtonTheme(
      idleColor: Color.lerp(idleColor, other.idleColor, t),
      connectedColor: Color.lerp(connectedColor, other.connectedColor, t),
    );
  }
}

class AiUiTheme extends ThemeExtension<AiUiTheme> {
  const AiUiTheme({
    required this.glassColor,
    required this.borderColor,
    required this.softBackgroundColor,
    required this.secondaryTextColor,
    required this.cardShadow,
    required this.primaryShadow,
  });

  final Color glassColor;
  final Color borderColor;
  final Color softBackgroundColor;
  final Color secondaryTextColor;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> primaryShadow;

  static final AiUiTheme dark = AiUiTheme(
    glassColor: const Color(0x9916161A), // 0xFF16161A.withOpacity(0.6)
    borderColor: const Color(0x14FFFFFF), // Colors.white.withOpacity(0.08)
    softBackgroundColor: const Color(0x0DFFFFFF), // Colors.white.withOpacity(0.05)
    secondaryTextColor: const Color(0x80FFFFFF), // Colors.white.withOpacity(0.5)
    cardShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
    primaryShadow: [
      BoxShadow(
        color: const Color(0xFF6366f1).withOpacity(0.2),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static final AiUiTheme light = AiUiTheme(
    glassColor: const Color(0xD9FFFFFF), // ~85% white
    borderColor: const Color(0x1A000000), // 10% black border
    softBackgroundColor: const Color(0xFFF1F5F9), // Slate 100/50 mix
    secondaryTextColor: const Color(0xFF475569), // Slate 600
    cardShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
    primaryShadow: [
      BoxShadow(
        color: const Color(0xFF3B82F6).withOpacity(0.15),
        blurRadius: 30,
        offset: const Offset(0, 10),
      ),
    ],
  );

  @override
  AiUiTheme copyWith({
    Color? glassColor,
    Color? borderColor,
    Color? softBackgroundColor,
    Color? secondaryTextColor,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? primaryShadow,
  }) {
    return AiUiTheme(
      glassColor: glassColor ?? this.glassColor,
      borderColor: borderColor ?? this.borderColor,
      softBackgroundColor: softBackgroundColor ?? this.softBackgroundColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      cardShadow: cardShadow ?? this.cardShadow,
      primaryShadow: primaryShadow ?? this.primaryShadow,
    );
  }

  @override
  AiUiTheme lerp(covariant ThemeExtension<AiUiTheme>? other, double t) {
    if (other is! AiUiTheme) return this;
    return AiUiTheme(
      glassColor: Color.lerp(glassColor, other.glassColor, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      softBackgroundColor: Color.lerp(softBackgroundColor, other.softBackgroundColor, t)!,
      secondaryTextColor: Color.lerp(secondaryTextColor, other.secondaryTextColor, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      primaryShadow: BoxShadow.lerpList(primaryShadow, other.primaryShadow, t)!,
    );
  }
}

extension AiUiThemeX on ThemeData {
  AiUiTheme get aiUi => extension<AiUiTheme>() ?? AiUiTheme.dark;
}
