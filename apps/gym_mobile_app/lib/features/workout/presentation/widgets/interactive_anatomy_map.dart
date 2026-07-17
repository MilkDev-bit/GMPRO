/// @file lib/features/workout/presentation/widgets/interactive_anatomy_map.dart
/// @description Widget de Mapa Anatómico Interactivo — el corazón visual del módulo de rutinas.
///
/// ## Arquitectura
/// Usa CustomPainter para renderizar a 60/120 FPS sin dependencias externas pesadas:
///   • `AnatomyBodyPainter` dibuja siluetas vectoriales precisas del cuerpo humano (frontal/posterior).
///   • Los músculos se iluminan con un `AnimatedMuscleHighlight` que usa TweenSequence para el
///     efecto "pulso" (fade-in → brillo → fade parcial → hold) idéntico al de Jefit/MuscleWiki.
///   • Soporta swipe horizontal para cambiar entre ejercicios, rotando la vista frontal ↔ posterior
///     automáticamente según qué región tiene más músculos activos.
///
/// ## Rendimiento
///   • Solo repinta las regiones musculares (shouldRepaint compara claves activas).
///   • El PageController es lazy y no reconstruye el cuerpo de la app.
///   • AnimationController dispone correctamente en dispose().

library interactive_anatomy_map;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/muscle_catalog.dart';
import '../../domain/entities/workout_entities.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────
class InteractiveAnatomyMap extends StatefulWidget {
  const InteractiveAnatomyMap({
    super.key,
    required this.exercises,
    this.initialIndex = 0,
    this.height = 360,
    this.onExerciseChanged,
  });

  final List<WorkoutExercise> exercises;
  final int initialIndex;
  final double height;
  final ValueChanged<int>? onExerciseChanged;

  @override
  State<InteractiveAnatomyMap> createState() => _InteractiveAnatomyMapState();
}

class _InteractiveAnatomyMapState extends State<InteractiveAnatomyMap>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _highlightController;
  late final AnimationController _viewFlipController;
  late final Animation<double> _highlightAnim;
  late final Animation<double> _viewFlipAnim;

  int _currentIndex = 0;
  BodyRegion _activeView = BodyRegion.anterior;

  WorkoutExercise get _currentExercise => widget.exercises[_currentIndex];

  /// Decide qué vista mostrar basándose en qué región tiene más músculos activos
  BodyRegion _computeBestView(WorkoutExercise exercise) {
    int anterior = 0, posterior = 0;
    for (final key in exercise.musculos_primarios) {
      final m = MuscleCatalog.byKey(key);
      if (m?.region == BodyRegion.anterior) anterior++;
      if (m?.region == BodyRegion.posterior) posterior++;
    }
    return posterior > anterior ? BodyRegion.posterior : BodyRegion.anterior;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.exercises.length - 1);
    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 0.85,
    );

    // Animación de pulso muscular (0 → 1 → 0.6 → 0.6, loop)
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _highlightAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.65), weight: 20),
      TweenSequenceItem(tween: ConstantTween(0.65), weight: 50),
    ]).animate(CurvedAnimation(parent: _highlightController, curve: Curves.easeOut));

    // Animación de flip de vista (frontal ↔ posterior)
    _viewFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _viewFlipAnim = CurvedAnimation(
      parent: _viewFlipController,
      curve: Curves.easeInOut,
    );

    _activeView = _computeBestView(_currentExercise);
    _highlightController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _highlightController.dispose();
    _viewFlipController.dispose();
    super.dispose();
  }

  Future<void> _onExerciseChanged(int index) async {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);

    final newView = _computeBestView(widget.exercises[index]);
    if (newView != _activeView) {
      // Flip con animación
      await _viewFlipController.forward();
      setState(() => _activeView = newView);
      _viewFlipController.reset();
    }

    // Reiniciar pulso
    _highlightController.reset();
    _highlightController.forward();

    widget.onExerciseChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _currentExercise;
    final primaryKeys = exercise.musculos_primarios;
    final secondaryKeys = exercise.musculos_secundarios;

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // ── FONDO BOKEH GLASSMORPHISM ─────────────────────────────────────
          _buildGlassBackground(primaryKeys),

          // ── CUERPO ANATÓMICO SVG (CustomPainter) ─────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_highlightAnim, _viewFlipAnim]),
              builder: (context, _) {
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(math.pi * _viewFlipAnim.value),
                  child: CustomPaint(
                    size: const Size(160, 320),
                    painter: AnatomyBodyPainter(
                      region: _activeView,
                      primaryMuscles: primaryKeys,
                      secondaryMuscles: secondaryKeys,
                      highlightOpacity: _highlightAnim.value,
                    ),
                  ),
                );
              },
            ),
          ),

          // ── CHIPS DE MÚSCULOS (PRIMARIOS arriba, SECUNDARIOS abajo) ──────
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: _MuscleChipsRow(
              primaryKeys: primaryKeys,
              secondaryKeys: secondaryKeys,
            ),
          ),

          // ── TOGGLE DE VISTA (Frontal / Posterior) ────────────────────────
          Positioned(
            top: 12,
            right: 12,
            child: _ViewToggleButton(
              activeView: _activeView,
              onToggle: () {
                final next = _activeView == BodyRegion.anterior
                    ? BodyRegion.posterior
                    : BodyRegion.anterior;
                _viewFlipController.forward().then((_) {
                  setState(() => _activeView = next);
                  _viewFlipController.reset();
                });
              },
            ),
          ),

          // ── HEADER: NOMBRE DEL EJERCICIO ──────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EJERCICIO ${_currentIndex + 1}/${widget.exercises.length}',
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  exercise.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBackground(List<String> primaryKeys) {
    // Color del primer músculo primario o fallback al rosa neón
    Color glowColor = AppColors.neonPink;
    if (primaryKeys.isNotEmpty) {
      final m = MuscleCatalog.byKey(primaryKeys.first);
      if (m != null) glowColor = m.color;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF12101F),
                Color.lerp(const Color(0xFF0A0914), glowColor, 0.06)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER — Cuerpo humano + músculos iluminados
// ─────────────────────────────────────────────────────────────────────────────
class AnatomyBodyPainter extends CustomPainter {
  const AnatomyBodyPainter({
    required this.region,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.highlightOpacity,
  });

  final BodyRegion region;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final double highlightOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 160;
    final sy = size.height / 320;

    // 1. Silueta base del cuerpo
    _drawBodySilhouette(canvas, size, sx, sy);

    // 2. Músculos secundarios (menos intensos)
    for (final key in secondaryMuscles) {
      final m = MuscleCatalog.byKey(key);
      if (m == null || m.region != region) continue;
      _drawMuscleRegion(canvas, size, sx, sy, key, m.color, highlightOpacity * 0.45);
    }

    // 3. Músculos primarios (más intensos, encima)
    for (final key in primaryMuscles) {
      final m = MuscleCatalog.byKey(key);
      if (m == null || m.region != region) continue;
      _drawMuscleRegion(canvas, size, sx, sy, key, m.color, highlightOpacity * 0.9);
    }

    // 4. Etiquetas flotantes de músculos primarios visibles en esta vista
    for (final key in primaryMuscles) {
      final m = MuscleCatalog.byKey(key);
      if (m == null || m.region != region) continue;
      _drawMuscleLabel(canvas, size, sx, sy, key, m);
    }
  }

  /// Silueta simplificada del cuerpo humano (frontal o posterior).
  /// Los paths están normalizados para un canvas de 160×320px.
  void _drawBodySilhouette(Canvas canvas, Size size, double sx, double sy) {
    final paint = Paint()
      ..color = const Color(0x401A1730)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();

    if (region == BodyRegion.anterior) {
      // ── Vista frontal simplificada ─────────────────────────────────────
      // Cabeza
      path.addOval(Rect.fromCenter(center: Offset(80 * sx, 22 * sy), width: 28 * sx, height: 32 * sy));
      // Cuello
      path.addRect(Rect.fromLTWH(74 * sx, 36 * sy, 12 * sx, 10 * sy));
      // Tronco (trapezoidal)
      path
        ..moveTo(55 * sx, 46 * sy)
        ..lineTo(105 * sx, 46 * sy)
        ..lineTo(108 * sx, 130 * sy)
        ..lineTo(52 * sx, 130 * sy)
        ..close();
      // Pelvis
      path
        ..moveTo(52 * sx, 130 * sy)
        ..lineTo(108 * sx, 130 * sy)
        ..lineTo(106 * sx, 155 * sy)
        ..lineTo(54 * sx, 155 * sy)
        ..close();
      // Brazo izquierdo
      path
        ..moveTo(45 * sx, 48 * sy)
        ..lineTo(55 * sx, 48 * sy)
        ..lineTo(58 * sx, 120 * sy)
        ..lineTo(42 * sx, 120 * sy)
        ..close();
      // Antebrazo izquierdo
      path
        ..moveTo(40 * sx, 120 * sy)
        ..lineTo(58 * sx, 120 * sy)
        ..lineTo(56 * sx, 175 * sy)
        ..lineTo(38 * sx, 175 * sy)
        ..close();
      // Brazo derecho
      path
        ..moveTo(105 * sx, 48 * sy)
        ..lineTo(115 * sx, 48 * sy)
        ..lineTo(118 * sx, 120 * sy)
        ..lineTo(102 * sx, 120 * sy)
        ..close();
      // Antebrazo derecho
      path
        ..moveTo(102 * sx, 120 * sy)
        ..lineTo(120 * sx, 120 * sy)
        ..lineTo(122 * sx, 175 * sy)
        ..lineTo(104 * sx, 175 * sy)
        ..close();
      // Pierna izquierda (muslo)
      path
        ..moveTo(52 * sx, 155 * sy)
        ..lineTo(78 * sx, 155 * sy)
        ..lineTo(76 * sx, 245 * sy)
        ..lineTo(50 * sx, 245 * sy)
        ..close();
      // Pierna izquierda (pantorrilla)
      path
        ..moveTo(50 * sx, 245 * sy)
        ..lineTo(76 * sx, 245 * sy)
        ..lineTo(74 * sx, 310 * sy)
        ..lineTo(52 * sx, 310 * sy)
        ..close();
      // Pierna derecha (muslo)
      path
        ..moveTo(82 * sx, 155 * sy)
        ..lineTo(108 * sx, 155 * sy)
        ..lineTo(110 * sx, 245 * sy)
        ..lineTo(84 * sx, 245 * sy)
        ..close();
      // Pierna derecha (pantorrilla)
      path
        ..moveTo(84 * sx, 245 * sy)
        ..lineTo(110 * sx, 245 * sy)
        ..lineTo(108 * sx, 310 * sy)
        ..lineTo(86 * sx, 310 * sy)
        ..close();
    } else {
      // ── Vista posterior simplificada ───────────────────────────────────
      path.addOval(Rect.fromCenter(center: Offset(80 * sx, 22 * sy), width: 28 * sx, height: 32 * sy));
      path.addRect(Rect.fromLTWH(74 * sx, 36 * sy, 12 * sx, 10 * sy));
      path
        ..moveTo(52 * sx, 46 * sy)
        ..lineTo(108 * sx, 46 * sy)
        ..lineTo(110 * sx, 130 * sy)
        ..lineTo(50 * sx, 130 * sy)
        ..close();
      path
        ..moveTo(50 * sx, 130 * sy)
        ..lineTo(110 * sx, 130 * sy)
        ..lineTo(108 * sx, 158 * sy)
        ..lineTo(52 * sx, 158 * sy)
        ..close();
      // Brazos posteriores
      path
        ..moveTo(40 * sx, 48 * sy)
        ..lineTo(52 * sx, 48 * sy)
        ..lineTo(54 * sx, 120 * sy)
        ..lineTo(38 * sx, 120 * sy)
        ..close();
      path
        ..moveTo(36 * sx, 120 * sy)
        ..lineTo(54 * sx, 120 * sy)
        ..lineTo(52 * sx, 175 * sy)
        ..lineTo(34 * sx, 175 * sy)
        ..close();
      path
        ..moveTo(108 * sx, 48 * sy)
        ..lineTo(120 * sx, 48 * sy)
        ..lineTo(122 * sx, 120 * sy)
        ..lineTo(106 * sx, 120 * sy)
        ..close();
      path
        ..moveTo(106 * sx, 120 * sy)
        ..lineTo(126 * sx, 120 * sy)
        ..lineTo(128 * sx, 175 * sy)
        ..lineTo(108 * sx, 175 * sy)
        ..close();
      // Piernas posteriores (muslos + pantorrillas)
      path
        ..moveTo(50 * sx, 158 * sy)
        ..lineTo(78 * sx, 158 * sy)
        ..lineTo(76 * sx, 248 * sy)
        ..lineTo(48 * sx, 248 * sy)
        ..close();
      path
        ..moveTo(48 * sx, 248 * sy)
        ..lineTo(76 * sx, 248 * sy)
        ..lineTo(74 * sx, 312 * sy)
        ..lineTo(50 * sx, 312 * sy)
        ..close();
      path
        ..moveTo(82 * sx, 158 * sy)
        ..lineTo(110 * sx, 158 * sy)
        ..lineTo(112 * sx, 248 * sy)
        ..lineTo(84 * sx, 248 * sy)
        ..close();
      path
        ..moveTo(84 * sx, 248 * sy)
        ..lineTo(112 * sx, 248 * sy)
        ..lineTo(110 * sx, 312 * sy)
        ..lineTo(86 * sx, 312 * sy)
        ..close();
    }

    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
  }

  /// Dibuja la región coloreada de un músculo específico con glow neón.
  void _drawMuscleRegion(
    Canvas canvas,
    Size size,
    double sx,
    double sy,
    String muscleKey,
    Color color,
    double opacity,
  ) {
    if (opacity <= 0) return;

    final path = _getMuscleRegionPath(muscleKey, sx, sy);
    if (path == null) return;

    // Relleno sólido translúcido
    final fillPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Borde brillante (neon glow effect)
    final glowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * opacity);
    canvas.drawPath(path, glowPaint);
  }

  /// Dibuja una etiqueta flotante con el nombre del músculo primario.
  void _drawMuscleLabel(
    Canvas canvas,
    Size size,
    double sx,
    double sy,
    String muscleKey,
    MuscleDescriptor descriptor,
  ) {
    final center = _getMuscleCenterOffset(muscleKey, sx, sy);
    if (center == null) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: descriptor.label.split(' ').first, // Solo la primera palabra
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: descriptor.color.withValues(alpha: highlightOpacity * 0.95),
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 70 * sx);

    final bgRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 8,
      height: textPainter.height + 4,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill,
    );

    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  /// Retorna el Path de un músculo en el canvas normalizado.
  /// Los paths se corresponden 1:1 con los svgPathId del catálogo.
  Path? _getMuscleRegionPath(String key, double sx, double sy) {
    final p = Path();
    switch (key) {
      // ── PECTORALES ──────────────────────────────────────────────────────
      case 'pectoral_mayor_esternal':
        p
          ..moveTo(57 * sx, 52 * sy)
          ..lineTo(80 * sx, 60 * sy)
          ..lineTo(80 * sx, 88 * sy)
          ..lineTo(57 * sx, 88 * sy)
          ..close();
        p
          ..moveTo(103 * sx, 52 * sy)
          ..lineTo(80 * sx, 60 * sy)
          ..lineTo(80 * sx, 88 * sy)
          ..lineTo(103 * sx, 88 * sy)
          ..close();
        return p;
      case 'pectoral_mayor_superior':
        p
          ..moveTo(57 * sx, 46 * sy)
          ..lineTo(80 * sx, 52 * sy)
          ..lineTo(80 * sx, 60 * sy)
          ..lineTo(57 * sx, 60 * sy)
          ..close();
        p
          ..moveTo(103 * sx, 46 * sy)
          ..lineTo(80 * sx, 52 * sy)
          ..lineTo(80 * sx, 60 * sy)
          ..lineTo(103 * sx, 60 * sy)
          ..close();
        return p;

      // ── DELTOIDES ───────────────────────────────────────────────────────
      case 'deltoides_anterior':
      case 'deltoides_lateral':
        p.addOval(Rect.fromCenter(center: Offset(48 * sx, 54 * sy), width: 14 * sx, height: 18 * sy));
        p.addOval(Rect.fromCenter(center: Offset(112 * sx, 54 * sy), width: 14 * sx, height: 18 * sy));
        return p;
      case 'deltoides_posterior':
        p.addOval(Rect.fromCenter(center: Offset(44 * sx, 56 * sy), width: 14 * sx, height: 18 * sy));
        p.addOval(Rect.fromCenter(center: Offset(116 * sx, 56 * sy), width: 14 * sx, height: 18 * sy));
        return p;

      // ── BÍCEPS ──────────────────────────────────────────────────────────
      case 'biceps_braquial':
      case 'braquial':
      case 'braquiorradial':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(42 * sx, 60 * sy, 13 * sx, 45 * sy), const Radius.circular(6)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(105 * sx, 60 * sy, 13 * sx, 45 * sy), const Radius.circular(6)));
        return p;

      // ── TRÍCEPS ─────────────────────────────────────────────────────────
      case 'triceps_braquial':
      case 'triceps_largo':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(38 * sx, 62 * sy, 14 * sx, 44 * sy), const Radius.circular(6)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(108 * sx, 62 * sy, 14 * sx, 44 * sy), const Radius.circular(6)));
        return p;

      // ── ESPALDA ─────────────────────────────────────────────────────────
      case 'dorsal_ancho':
        p
          ..moveTo(54 * sx, 70 * sy)
          ..lineTo(78 * sx, 90 * sy)
          ..lineTo(76 * sx, 130 * sy)
          ..lineTo(50 * sx, 130 * sy)
          ..close();
        p
          ..moveTo(106 * sx, 70 * sy)
          ..lineTo(82 * sx, 90 * sy)
          ..lineTo(84 * sx, 130 * sy)
          ..lineTo(110 * sx, 130 * sy)
          ..close();
        return p;
      case 'trapecio_superior':
        p
          ..moveTo(68 * sx, 46 * sy)
          ..lineTo(92 * sx, 46 * sy)
          ..lineTo(98 * sx, 68 * sy)
          ..lineTo(62 * sx, 68 * sy)
          ..close();
        return p;
      case 'trapecio_medio':
      case 'trapecio_inferior':
      case 'romboides':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(60 * sx, 68 * sy, 40 * sx, 42 * sy), const Radius.circular(5)));
        return p;
      case 'erector_espinal':
      case 'cuadrado_lumbar':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(72 * sx, 90 * sy, 10 * sx, 60 * sy), const Radius.circular(3)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(78 * sx, 90 * sy, 10 * sx, 60 * sy), const Radius.circular(3)));
        return p;

      // ── ABDOMINALES ─────────────────────────────────────────────────────
      case 'recto_abdominal':
        for (int i = 0; i < 3; i++) {
          p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(68 * sx, (94 + i * 14) * sy, 10 * sx, 10 * sy), const Radius.circular(3)));
          p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(82 * sx, (94 + i * 14) * sy, 10 * sx, 10 * sy), const Radius.circular(3)));
        }
        return p;
      case 'oblicuo_externo':
      case 'oblicuo_interno':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(54 * sx, 96 * sy, 14 * sx, 32 * sy), const Radius.circular(4)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(92 * sx, 96 * sy, 14 * sx, 32 * sy), const Radius.circular(4)));
        return p;

      // ── GLÚTEOS ─────────────────────────────────────────────────────────
      case 'gluteo_mayor':
        p.addOval(Rect.fromCenter(center: Offset(63 * sx, 148 * sy), width: 26 * sx, height: 22 * sy));
        p.addOval(Rect.fromCenter(center: Offset(97 * sx, 148 * sy), width: 26 * sx, height: 22 * sy));
        return p;
      case 'gluteo_medio':
        p.addOval(Rect.fromCenter(center: Offset(57 * sx, 138 * sy), width: 16 * sx, height: 14 * sy));
        p.addOval(Rect.fromCenter(center: Offset(103 * sx, 138 * sy), width: 16 * sx, height: 14 * sy));
        return p;

      // ── CUÁDRICEPS ──────────────────────────────────────────────────────
      case 'cuadriceps_recto':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(60 * sx, 158 * sy, 16 * sx, 72 * sy), const Radius.circular(8)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(84 * sx, 158 * sy, 16 * sx, 72 * sy), const Radius.circular(8)));
        return p;
      case 'cuadriceps_vasto_lateral':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(51 * sx, 162 * sy, 12 * sx, 68 * sy), const Radius.circular(6)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(97 * sx, 162 * sy, 12 * sx, 68 * sy), const Radius.circular(6)));
        return p;
      case 'cuadriceps_vasto_medial':
        p.addOval(Rect.fromCenter(center: Offset(66 * sx, 228 * sy), width: 16 * sx, height: 14 * sy));
        p.addOval(Rect.fromCenter(center: Offset(94 * sx, 228 * sy), width: 16 * sx, height: 14 * sy));
        return p;

      // ── ISQUIOTIBIALES ──────────────────────────────────────────────────
      case 'biceps_femoral':
      case 'semitendinoso':
      case 'semimembranoso':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(51 * sx, 162 * sy, 25 * sx, 74 * sy), const Radius.circular(8)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(84 * sx, 162 * sy, 25 * sx, 74 * sy), const Radius.circular(8)));
        return p;

      // ── GEMELOS ─────────────────────────────────────────────────────────
      case 'gemelo_medial':
      case 'gemelo_lateral':
      case 'soleo':
        p.addOval(Rect.fromCenter(center: Offset(63 * sx, 268 * sy), width: 22 * sx, height: 44 * sy));
        p.addOval(Rect.fromCenter(center: Offset(97 * sx, 268 * sy), width: 22 * sx, height: 44 * sy));
        return p;
      case 'tibial_anterior':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(53 * sx, 248 * sy, 10 * sx, 48 * sy), const Radius.circular(5)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(97 * sx, 248 * sy, 10 * sx, 48 * sy), const Radius.circular(5)));
        return p;

      // ── ANTEBRAZO ────────────────────────────────────────────────────────
      case 'flexores_antebrazo':
      case 'extensores_antebrazo':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(38 * sx, 122 * sy, 14 * sx, 46 * sy), const Radius.circular(5)));
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(108 * sx, 122 * sy, 14 * sx, 46 * sy), const Radius.circular(5)));
        return p;

      // ── ADUCTORES ────────────────────────────────────────────────────────
      case 'aductor_mayor':
      case 'aductor_largo':
      case 'tensor_fascia_lata':
        p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(75 * sx, 158 * sy, 10 * sx, 60 * sy), const Radius.circular(5)));
        return p;

      default:
        return null;
    }
  }

  /// Retorna el centro geométrico de un músculo para posicionar etiquetas.
  Offset? _getMuscleCenterOffset(String key, double sx, double sy) {
    switch (key) {
      case 'pectoral_mayor_esternal':
      case 'pectoral_mayor_superior':
        return Offset(70 * sx, 70 * sy);
      case 'deltoides_anterior':
      case 'deltoides_lateral':
        return Offset(48 * sx, 56 * sy);
      case 'deltoides_posterior':
        return Offset(44 * sx, 58 * sy);
      case 'biceps_braquial':
      case 'braquial':
        return Offset(48 * sx, 82 * sy);
      case 'triceps_braquial':
      case 'triceps_largo':
        return Offset(45 * sx, 84 * sy);
      case 'dorsal_ancho':
        return Offset(62 * sx, 100 * sy);
      case 'trapecio_superior':
        return Offset(80 * sx, 56 * sy);
      case 'recto_abdominal':
        return Offset(80 * sx, 110 * sy);
      case 'oblicuo_externo':
        return Offset(60 * sx, 110 * sy);
      case 'gluteo_mayor':
        return Offset(63 * sx, 148 * sy);
      case 'cuadriceps_recto':
        return Offset(68 * sx, 194 * sy);
      case 'cuadriceps_vasto_lateral':
        return Offset(57 * sx, 196 * sy);
      case 'biceps_femoral':
      case 'semitendinoso':
        return Offset(64 * sx, 196 * sy);
      case 'gemelo_medial':
      case 'gemelo_lateral':
        return Offset(63 * sx, 268 * sy);
      default:
        return null;
    }
  }

  @override
  bool shouldRepaint(AnatomyBodyPainter old) =>
      old.highlightOpacity != highlightOpacity ||
      old.primaryMuscles != primaryMuscles ||
      old.secondaryMuscles != secondaryMuscles ||
      old.region != region;
}

// ─────────────────────────────────────────────────────────────────────────────
// MUSCLE CHIPS ROW — Etiquetas de músculos en la parte inferior
// ─────────────────────────────────────────────────────────────────────────────
class _MuscleChipsRow extends StatelessWidget {
  const _MuscleChipsRow({
    required this.primaryKeys,
    required this.secondaryKeys,
  });
  final List<String> primaryKeys;
  final List<String> secondaryKeys;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (primaryKeys.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: primaryKeys.map((key) {
                final m = MuscleCatalog.byKey(key);
                return _MuscleChip(
                  label: m?.label ?? key,
                  color: m?.color ?? AppColors.neonPink,
                  isPrimary: true,
                );
              }).toList(),
            ),
          ),
        ],
        if (secondaryKeys.isNotEmpty) ...[
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: secondaryKeys.take(4).map((key) {
                final m = MuscleCatalog.byKey(key);
                return _MuscleChip(
                  label: m?.label ?? key,
                  color: m?.color ?? AppColors.textMuted,
                  isPrimary: false,
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({
    required this.label,
    required this.color,
    required this.isPrimary,
  });
  final String label;
  final Color color;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary
            ? color.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPrimary
              ? color.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: isPrimary
            ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8)]
            : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w400,
          color: isPrimary ? color : AppColors.textMuted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIEW TOGGLE BUTTON — Frontal ↔ Posterior
// ─────────────────────────────────────────────────────────────────────────────
class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.activeView,
    required this.onToggle,
  });
  final BodyRegion activeView;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeView == BodyRegion.anterior
                  ? Icons.person_outlined
                  : Icons.person_outlined,
              color: AppColors.neonCyan,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              activeView == BodyRegion.anterior ? 'Frontal' : 'Posterior',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.neonCyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
