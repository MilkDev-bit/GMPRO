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

    // Animación de pulso muscular (0 → 1 → 0.6 → 0.6, loop)
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
  void didUpdateWidget(InteractiveAnatomyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _onExerciseChanged(widget.initialIndex.clamp(0, widget.exercises.length - 1));
    }
  }

  @override
  void dispose() {
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
      child: RepaintBoundary(
        child: Stack(
          children: [
            // ── FONDO BOKEH GLASSMORPHISM (Aislado en su capa de pintado) ───
            _buildGlassBackground(primaryKeys),

            // ── CUERPO ANATÓMICO SVG (CustomPainter en RepaintBoundary) ─────
            // Padding vertical: reserva espacio para el header (arriba) y los
            // chips de músculos (abajo) para que NO tapen la figura. El cuerpo se
            // dibuja más pequeño conservando la proporción 1:2 (ancho:alto).
            Padding(
              padding: const EdgeInsets.only(top: 54, bottom: 60),
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_highlightAnim, _viewFlipAnim]),
                  builder: (context, _) {
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(math.pi * _viewFlipAnim.value),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(158, 316),
                          painter: AnatomyBodyPainter(
                          region: _activeView,
                          primaryMuscles: primaryKeys,
                          secondaryMuscles: secondaryKeys,
                          highlightOpacity: _highlightAnim.value,
                        ),
                      ),
                    ),
                  );
                  },
                ),
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

    return RepaintBoundary(
      child: ClipRRect(
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

  // ── CACHÉS ESTÁTICAS DE GEOMETRÍA ──────────────────────────────────────────
  // El CustomPaint se dibuja SIEMPRE en un canvas de tamaño const (160×320), por
  // lo que la silueta, los paths musculares y el layout de las etiquetas son
  // INVARIANTES entre frames. Antes se reconstruían en CADA paint() (60–120 fps),
  // asignando decenas de Path/Paint/TextPainter por frame. Se memoizan una vez.
  static final Map<BodyRegion, Path> _silhouetteCache = {};
  static final Map<String, Path> _muscleRegionCache = {};
  static final Map<String, TextPainter> _labelCache = {};

  // Paints reutilizables (se mutan por dibujo; el pintado es de un solo hilo).
  // El relleno usa un degradado vertical (shader memoizado) para dar volumen
  // "esculpido" al cuerpo musculoso; se asigna en _drawBodySilhouette.
  static final Paint _silhouetteFill = Paint()..style = PaintingStyle.fill;
  static Shader? _bodyFillShader;
  static final Paint _silhouetteStroke = Paint()
    ..color = const Color(0x40FFFFFF) // blanco ~25% (contorno más visible)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  // Halo exterior tenue: hace que la silueta destaque sobre el fondo oscuro.
  static final Paint _silhouetteGlow = Paint()
    ..color = const Color(0x334FD6E0) // cian tenue
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  static final Paint _muscleFill = Paint()..style = PaintingStyle.fill;
  static final Paint _muscleGlow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _labelBg = Paint()..style = PaintingStyle.fill;

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

    // Nota: las etiquetas de músculos NO se pintan sobre el cuerpo (tapaban el
    // esquema). Los nombres se muestran en los chips inferiores (_MuscleChipsRow).
  }

  /// Silueta simplificada del cuerpo humano (frontal o posterior).
  /// Los paths están normalizados para un canvas de 160×320px.
  /// Memoizada por región: se construye una sola vez, no por frame.
  void _drawBodySilhouette(Canvas canvas, Size size, double sx, double sy) {
    final path = _silhouetteCache[region] ??= _computeSilhouettePath(sx, sy);
    // Degradado de volumen (claro arriba → oscuro abajo) para un look muscular 3D.
    // Relleno SEMISÓLIDO con degradado + un realce lateral: da masa y volumen
    // (antes era casi transparente y parecía un contorno/fantasma).
    _silhouetteFill.shader = _bodyFillShader ??= const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xE63A3560), Color(0xD9211C3D), Color(0xE6100D22)],
      stops: [0.0, 0.5, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawPath(path, _silhouetteGlow); // halo exterior (visibilidad)
    canvas.drawPath(path, _silhouetteFill);
    canvas.drawPath(path, _silhouetteStroke);
  }

  /// Construye (una vez) el Path de la silueta según la región activa.
  Path _computeSilhouettePath(double sx, double sy) {
    final path = Path();

    // Cuerpo MUSCULOSO con curvas bezier. Todas las subformas se acumulan en UN
    // solo Path y se rellenan con winding nonzero → los solapamientos se funden
    // sin costuras internas (hombros anchos, torso en V, bíceps, muslos y
    // pantorrillas con volumen). Coordenadas base 160×320 (mismos anclajes que
    // los paths musculares, para que se sobrepongan bien). La silueta es válida
    // para vista frontal y posterior (los músculos resaltados cambian, no el
    // contorno del cuerpo).
    void oval(double cx, double cy, double w, double h) => path.addOval(
        Rect.fromCenter(center: Offset(cx * sx, cy * sy), width: w * sx, height: h * sy));
    void capsule(double x, double y, double w, double h, double r) => path.addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy), Radius.circular(r * sx)));
    // curve: [x0,y0, (c1x,c1y,c2x,c2y,x1,y1)...] → subpath cerrado de cúbicas.
    void curve(List<double> p) {
      final sub = Path()..moveTo(p[0] * sx, p[1] * sy);
      for (int i = 2; i + 5 < p.length; i += 6) {
        sub.cubicTo(p[i] * sx, p[i + 1] * sy, p[i + 2] * sx, p[i + 3] * sy, p[i + 4] * sx, p[i + 5] * sy);
      }
      sub.close();
      path.addPath(sub, Offset.zero);
    }

    // Cabeza y cuello
    oval(80, 20, 30, 34);
    capsule(72, 33, 16, 16, 5);

    // Trapecios / hombros altos (unen cuello con deltoides)
    curve([
      66, 45, 74, 40, 86, 40, 94, 45,
      104, 48, 112, 52, 118, 60,
      100, 58, 60, 58, 42, 60,
      48, 52, 58, 48, 66, 45,
    ]);

    // Deltoides: hombros anchos y redondos
    oval(46, 58, 28, 28);
    oval(114, 58, 28, 28);

    // Torso en V: pecho ancho → cintura marcada (dorsales que se estrechan)
    curve([
      50, 56, 58, 60, 62, 60, 80, 62,
      98, 60, 102, 60, 110, 56,
      112, 82, 108, 106, 104, 130,
      94, 137, 66, 137, 56, 130,
      52, 106, 48, 82, 50, 56,
    ]);

    // Brazos: contorno ÚNICO y suave (bíceps → antebrazo → mano), no bloques.
    curve([
      54, 60, 44, 60, 36, 72, 36, 92,
      36, 118, 38, 140, 40, 166,
      41, 176, 46, 182, 48, 182,
      52, 182, 54, 174, 54, 166,
      53, 140, 52, 110, 54, 88,
      55, 74, 55, 66, 54, 60,
    ]);
    curve([
      106, 60, 116, 60, 124, 72, 124, 92,
      124, 118, 122, 140, 120, 166,
      119, 176, 114, 182, 112, 182,
      108, 182, 106, 174, 106, 166,
      107, 140, 108, 110, 106, 88,
      105, 74, 105, 66, 106, 60,
    ]);

    // Pelvis / cadera
    curve([
      56, 128, 64, 133, 96, 133, 104, 128,
      111, 140, 109, 153, 100, 160,
      90, 164, 70, 164, 60, 160,
      51, 153, 49, 140, 56, 128,
    ]);

    // Piernas: contorno ÚNICO y suave (muslo → rodilla → gemelo → pie), con
    // bultos de cuádriceps y gemelo, sin costuras (nada de óvalos sueltos).
    curve([
      80, 152, 81, 190, 80, 220, 78, 240,
      78, 262, 79, 286, 76, 306,
      76, 312, 74, 316, 72, 316,
      64, 320, 58, 318, 58, 314,
      56, 300, 54, 284, 55, 264,
      53, 250, 56, 244, 58, 240,
      50, 212, 49, 182, 52, 156,
      60, 150, 72, 150, 80, 152,
    ]);
    curve([
      80, 152, 79, 190, 80, 220, 82, 240,
      82, 262, 81, 286, 84, 306,
      84, 312, 86, 316, 88, 316,
      96, 320, 102, 318, 102, 314,
      104, 300, 106, 284, 105, 264,
      107, 250, 104, 244, 102, 240,
      110, 212, 111, 182, 108, 156,
      100, 150, 88, 150, 80, 152,
    ]);

    return path;
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

    // Path memoizado por clave (geometría fija en canvas const). null → sin dibujo.
    final path = _muscleRegionCache.putIfAbsent(
      muscleKey,
      () => _computeMuscleRegionPath(muscleKey, sx, sy) ?? Path(),
    );
    if (path.getBounds().isEmpty) return;

    // Relleno sólido translúcido (Paint reutilizable, solo se muta el color).
    _muscleFill.color = color.withValues(alpha: opacity * 0.75);
    canvas.drawPath(path, _muscleFill);

    // Borde brillante (neon glow effect) — Paint reutilizable, más marcado.
    _muscleGlow
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1.8
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * opacity);
    canvas.drawPath(path, _muscleGlow);
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

    // TextPainter memoizado: el layout (glifos) es fijo; solo la opacidad anima.
    // Antes se creaba + .layout() en CADA frame por cada músculo primario (caro).
    final textPainter = _labelCache.putIfAbsent(muscleKey, () {
      return TextPainter(
        text: TextSpan(
          text: descriptor.label.split(' ').first, // Solo la primera palabra
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: descriptor.color, // color base; la opacidad se aplica al pintar
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 70 * sx);
    });

    final labelAlpha = (highlightOpacity * 0.95).clamp(0.0, 1.0);
    if (labelAlpha <= 0) return;

    final bgRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 8,
      height: textPainter.height + 4,
    );
    final textOffset = center - Offset(textPainter.width / 2, textPainter.height / 2);

    _labelBg.color = const Color(0x8C000000); // negro @ 55% (la opacidad de fundido va en la capa)

    if (labelAlpha >= 0.99) {
      canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), _labelBg);
      textPainter.paint(canvas, textOffset);
    } else {
      // Fundido de la etiqueta completa vía capa de opacidad (sin re-layout).
      canvas.saveLayer(bgRect.inflate(6), Paint()..color = Color.fromRGBO(0, 0, 0, labelAlpha));
      canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), _labelBg);
      textPainter.paint(canvas, textOffset);
      canvas.restore();
    }
  }

  /// Construye (una vez, luego memoizado) el Path de un músculo en el canvas
  /// normalizado. Los paths se corresponden 1:1 con los svgPathId del catálogo.
  Path? _computeMuscleRegionPath(String key, double sx, double sy) {
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
                  : Icons.flip_camera_android_outlined,
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
