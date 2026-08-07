/// @file lib/core/presentation/widgets/premium_loading_overlay.dart
/// @description Sistema centralizado de pantallas de carga personalizadas (Apple / Fitia Premium)
/// con modo oscuro profundo, resplandores neón, Glassmorphism, animaciones fluidas y Shimmers.

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

// ── 1. VARIANTES Y GESTIÓN DE ESTADO (RIVERPOD) ──────────────────────────────
enum LoadingVariant {
  loginSuccess,
  aiServiceWaiting,
  generic,
}

class LoadingOverlayState {
  final bool isLoading;
  final LoadingVariant variant;
  final String? userName;
  final List<String>? customTexts;
  final VoidCallback? onFinish;

  const LoadingOverlayState({
    this.isLoading = false,
    this.variant = LoadingVariant.generic,
    this.userName,
    this.customTexts,
    this.onFinish,
  });

  LoadingOverlayState copyWith({
    bool? isLoading,
    LoadingVariant? variant,
    String? userName,
    List<String>? customTexts,
    VoidCallback? onFinish,
  }) {
    return LoadingOverlayState(
      isLoading: isLoading ?? this.isLoading,
      variant: variant ?? this.variant,
      userName: userName ?? this.userName,
      customTexts: customTexts ?? this.customTexts,
      onFinish: onFinish ?? this.onFinish,
    );
  }
}

class LoadingOverlayNotifier extends StateNotifier<LoadingOverlayState> {
  LoadingOverlayNotifier() : super(const LoadingOverlayState());

  /// Dispara la pantalla de bienvenida con animación tipográfica de 1800ms
  void showLoginSplash({required String userName, VoidCallback? onFinish}) {
    state = LoadingOverlayState(
      isLoading: true,
      variant: LoadingVariant.loginSuccess,
      userName: userName,
      onFinish: onFinish,
    );
  }

  /// Dispara el overlay translúcido con carrusel de micro-textos y escáner neón para la IA
  void showAiOverlay({List<String>? texts}) {
    state = LoadingOverlayState(
      isLoading: true,
      variant: LoadingVariant.aiServiceWaiting,
      customTexts: texts ??
          const [
            'Calculando tu tasa metabólica basal...',
            'Mapeando fibras musculares y recuperación...',
            'Alineando macros con tus objetivos fitness...',
            'Optimizando sobrecarga progresiva...',
            'Sincronizando con catálogo Open Food Facts...',
          ],
    );
  }

  /// Dispara una carga genérica con spinner neón
  void showGeneric() {
    state = const LoadingOverlayState(isLoading: true, variant: LoadingVariant.generic);
  }

  /// Oculta cualquier overlay activo
  void hide() {
    state = state.copyWith(isLoading: false);
  }
}

final loadingOverlayProvider =
    StateNotifierProvider<LoadingOverlayNotifier, LoadingOverlayState>((ref) {
  return LoadingOverlayNotifier();
});

// ── 2. COMPONENTE PRINCIPAL (PREMIUM LOADING OVERLAY) ────────────────────────
class PremiumLoadingOverlay extends ConsumerWidget {
  const PremiumLoadingOverlay({
    super.key,
    required this.child,
    this.isLoading,
    this.variant,
  });

  final Widget child;
  final bool? isLoading;
  final LoadingVariant? variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayState = ref.watch(loadingOverlayProvider);
    final activeLoading = isLoading ?? overlayState.isLoading;
    final activeVariant = variant ?? overlayState.variant;

    return Stack(
      children: [
        // Contenido de la pantalla base
        child,

        // Overlay animado con curvas premium (easeOutBack / fastOutSlowIn)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.fastOutSlowIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                    reverseCurve: Curves.fastOutSlowIn,
                  ),
                ),
                child: child,
              ),
            );
          },
          child: activeLoading
              ? KeyedSubtree(
                  key: ValueKey<LoadingVariant>(activeVariant),
                  child: _buildVariantOverlay(context, activeVariant, overlayState),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildVariantOverlay(
    BuildContext context,
    LoadingVariant variant,
    LoadingOverlayState state,
  ) {
    switch (variant) {
      case LoadingVariant.loginSuccess:
        return _LoginSuccessSplash(
          userName: state.userName ?? 'Atleta',
          onFinish: state.onFinish,
        );
      case LoadingVariant.aiServiceWaiting:
        return _AiServiceOverlay(texts: state.customTexts);
      case LoadingVariant.generic:
        return const _GenericNeonSpinner();
    }
  }
}

// ── 3. VARIANTE 1: PANTALLA DE CARGA DE INICIO DE SESIÓN (LOGIN SUCCESS) ─────
class _LoginSuccessSplash extends StatefulWidget {
  const _LoginSuccessSplash({required this.userName, this.onFinish});
  final String userName;
  final VoidCallback? onFinish;

  @override
  State<_LoginSuccessSplash> createState() => _LoginSuccessSplashState();
}

class _LoginSuccessSplashState extends State<_LoginSuccessSplash> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    // Temporizador exacto de 1800ms antes del redireccionamiento limpio (FadeThrough)
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && widget.onFinish != null) {
        widget.onFinish!();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Resplandor neón radial de fondo
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.neonCyan.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.neonPurple.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Contenido tipográfico animado (FadeInUp + Scale)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutBack,
                builder: (context, val, child) {
                  return Opacity(
                    opacity: val.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 28 * (1.0 - val)),
                      child: Transform.scale(
                        scale: 0.88 + (0.12 * val),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icono central con aura
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.neonCyan.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppColors.neonCyan.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonCyan.withValues(alpha: 0.4),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.neonCyan,
                        size: 46,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Texto tipográfico principal con gradiente neón
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, AppColors.neonCyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        '¡Bienvenido, ${widget.userName}!',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preparando tu zona de entrenamiento inteligente...',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Barra indicadora de carga elegante
                    SizedBox(
                      width: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonCyan),
                          minHeight: 3.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 4. VARIANTE 2: PANTALLA DE ESPERA PARA IA CON CARRUSEL Y ESCÁNER NEÓN ────
class _AiServiceOverlay extends StatefulWidget {
  const _AiServiceOverlay({this.texts});
  final List<String>? texts;

  @override
  State<_AiServiceOverlay> createState() => _AiServiceOverlayState();
}

class _AiServiceOverlayState extends State<_AiServiceOverlay> {
  late final List<String> _carouselTexts;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _carouselTexts = widget.texts ??
        const [
          'Calculando tu tasa metabólica basal...',
          'Mapeando fibras musculares y recuperación...',
          'Alineando macros con tus objetivos fitness...',
          'Optimizando sobrecarga progresiva...',
          'Sincronizando con catálogo Open Food Facts...',
        ];

    _timer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _carouselTexts.length;
        });
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo Glassmorphism profundo.
          // RepaintBoundary: aísla el BackdropFilter (costosísimo) en su propia capa
          // para que las animaciones infinitas (escáner/pulso) NO lo obliguen a
          // re-blurear la pantalla en cada frame.
          RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: const Color(0xFF080614).withValues(alpha: 0.78),
              ),
            ),
          ),

          // Escáner Neón por toda la pantalla (Scanner Neon Pulse).
          // Aislado en su capa: su repintado (cada frame) no invalida el backdrop.
          const RepaintBoundary(child: _ScannerNeonPulse()),

          // Contenido central del procesador IA
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Carrusel de micro-textos: SOLO el texto cambiante (sin icono
                  // ni eyebrow). Transición de FUNDIDO limpio: antes usaba
                  // easeOutBack + deslizamiento vertical, así el texto saliente y
                  // el entrante se cruzaban en el centro y se "amontonaban". Ahora
                  // solo fade + un leve escalado, sin desplazamiento vertical.
                  // Altura holgada para textos de hasta 2 líneas sin recortes.
                  SizedBox(
                    height: 88,
                    child: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                                CurvedAnimation(parent: animation, curve: Curves.easeOut),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Align(
                          key: ValueKey<int>(_currentIndex),
                          alignment: Alignment.center,
                          // Degradado neón: "algunas letras en otro color".
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Colors.white,
                                AppColors.neonCyan,
                                AppColors.neonPurple,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(bounds),
                            child: Text(
                              _carouselTexts[_currentIndex],
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  // Indicador animado (puntos que laten) en lugar del icono.
                  const RepaintBoundary(child: _TypingDots()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tres puntos neón que laten en secuencia. Reemplaza al icono de la pantalla de
/// IA: da sensación de "procesando" sin usar iconos/emojis, solo movimiento.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<Color> _dotColors = [
    AppColors.neonCyan,
    AppColors.neonPurple,
    AppColors.neonPink,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Onda desfasada por punto: cada uno late en su turno.
            final t = (_controller.value + i * 0.22) % 1.0;
            final wave = 1.0 - (2.0 * t - 1.0).abs(); // triángulo 0→1→0
            final scale = 0.6 + 0.5 * wave;
            final alpha = 0.30 + 0.70 * wave;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColors[i].withValues(alpha: alpha),
                    boxShadow: [
                      BoxShadow(
                        color: _dotColors[i].withValues(alpha: 0.5 * wave),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ScannerNeonPulse extends StatefulWidget {
  const _ScannerNeonPulse();

  @override
  State<_ScannerNeonPulse> createState() => _ScannerNeonPulseState();
}

class _ScannerNeonPulseState extends State<_ScannerNeonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Align(
          alignment: Alignment(0, -1.0 + (_scanController.value * 2.0)),
          child: Container(
            width: double.infinity,
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.neonCyan.withValues(alpha: 0.8),
                  AppColors.neonPurple.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GenericNeonSpinner extends StatelessWidget {
  const _GenericNeonSpinner();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: AppColors.background.withValues(alpha: 0.65),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF161328).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonCyan),
                strokeWidth: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 5. VARIANTE 3: EFECTO ESQUELETO SHIMMER OPTIMIZADO (REPAINT BOUNDARY) ────
class PremiumShimmer extends StatefulWidget {
  const PremiumShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF18152D),
    this.highlightColor = const Color(0xFF2A244E),
  });

  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<PremiumShimmer> createState() => _PremiumShimmerState();
}

class _PremiumShimmerState extends State<PremiumShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final x = -1.0 + (_shimmerController.value * 3.0);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: [
                  widget.baseColor,
                  widget.highlightColor,
                  widget.baseColor,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(x - 1, 0),
                end: Alignment(x + 1, 0),
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ── 6. SKELETONS PRE-CONSTRUIDOS SIN LAYOUT JUMP ─────────────────────────────

/// Skeleton geométricamente IDÉNTICO a la cabecera colapsada de `MealCard`.
///
/// Espejo exacto del shell real (radio 26, `margin.bottom = 18`, `padding = 20`,
/// avatar 46, dos líneas de texto con gap 3, columna derecha kcal+macros y el
/// espacio del chevron 26+10). Al replicar footprint y márgenes, el swap
/// shimmer → tarjeta real NO produce layout jump ni reflow de la lista.
class MealCardShimmer extends StatelessWidget {
  const MealCardShimmer({super.key});

  static Widget _bar(double w, double h, double r) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PremiumShimmer(
      child: Container(
        // Sin height fija: el avatar (46) + padding (20·2) define la altura,
        // igual que la cabecera colapsada real (~86 px).
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF18152D),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bar(140, 16, 8),   // nombre de la comida
                  const SizedBox(height: 3), // = gap real nombre→hora
                  _bar(96, 12, 6),    // "🕒 hora • N alimentos"
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bar(64, 19, 8),      // kcal totales
                const SizedBox(height: 4),
                _bar(110, 11, 5),     // P/C/G
              ],
            ),
            const SizedBox(width: 10),
            _bar(26, 26, 8),          // espacio del chevron expand/collapse
          ],
        ),
      ),
    );
  }
}

/// Skeleton exacto para bloque/tarjeta de ejercicio en PageView (ExerciseCard)
class ExerciseCardShimmer extends StatelessWidget {
  const ExerciseCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumShimmer(
      child: Container(
        height: 210,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF18152D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: List.generate(
                3,
                (i) => Expanded(
                  child: Container(
                    height: 52,
                    margin: EdgeInsets.only(right: i < 2 ? 10 : 0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
