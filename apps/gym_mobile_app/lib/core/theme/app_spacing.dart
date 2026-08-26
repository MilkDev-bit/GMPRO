/// @file lib/core/theme/app_spacing.dart
/// @description Sistema de espaciado y radios sobre una rejilla de 8pt (con medio
/// paso de 4pt). Es la base geométrica del layout tipo openGym: mismo ritmo
/// vertical en todas las tarjetas y pantallas. No define colores (esos viven en
/// app_colors.dart) — solo distancias y curvas.

import 'package:flutter/widgets.dart';

class AppSpacing {
  AppSpacing._();

  // ── Escala de 8pt (medio paso 4pt) ─────────────────────────────────────────
  static const double xs = 4; // micro-separaciones (icono↔texto)
  static const double sm = 8; // interior compacto
  static const double md = 12; // gap estándar entre elementos
  static const double lg = 16; // padding interior de tarjeta
  static const double xl = 20; // margen de pantalla (openGym usa 20)
  static const double xxl = 24; // separación entre secciones
  static const double xxxl = 32; // separación entre bloques grandes

  // ── Radios de esquina ───────────────────────────────────────────────────────
  static const double radiusSm = 12; // chips / pills
  static const double radiusMd = 16; // botones / tiles
  static const double radiusLg = 20; // tarjetas de sección
  static const double radiusXl = 28; // tarjetas destacadas / hojas

  // ── Constantes de layout ────────────────────────────────────────────────────
  /// Margen horizontal estándar de las pantallas (borde de contenido).
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: xl);

  /// Padding interior por defecto de una tarjeta de sección.
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// Altura mínima de zona táctil (Apple HIG / Material).
  static const double minTapTarget = 44;
}

/// Gaps verticales/horizontales listos para usar en Columns/Rows (evita repetir
/// `SizedBox(height: ...)` con números mágicos).
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key, this.horizontal = false});

  final double size;
  final bool horizontal;

  const Gap.xs({Key? key, bool horizontal = false})
      : this(AppSpacing.xs, key: key, horizontal: horizontal);
  const Gap.sm({Key? key, bool horizontal = false})
      : this(AppSpacing.sm, key: key, horizontal: horizontal);
  const Gap.md({Key? key, bool horizontal = false})
      : this(AppSpacing.md, key: key, horizontal: horizontal);
  const Gap.lg({Key? key, bool horizontal = false})
      : this(AppSpacing.lg, key: key, horizontal: horizontal);
  const Gap.xl({Key? key, bool horizontal = false})
      : this(AppSpacing.xl, key: key, horizontal: horizontal);
  const Gap.xxl({Key? key, bool horizontal = false})
      : this(AppSpacing.xxl, key: key, horizontal: horizontal);

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: horizontal ? size : null, height: horizontal ? null : size);
}
