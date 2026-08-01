/// @file lib/main.dart
/// @description Punto de entrada principal de la aplicación móvil GymPro con Riverpod ProviderScope.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
// Generado por `flutterfire configure` — no editar a mano.
// Sí se commitea: las API keys de cliente de Firebase son identificadores
// públicos, no secretos; la seguridad la dan las Security Rules. (Los
// google-services.json / GoogleService-Info.plist sí están en .gitignore
// en este repo, así que un clon limpio necesita volver a ejecutar
// `flutterfire configure`.)
import 'firebase_options.dart';
import 'core/config/app_config.dart';
import 'core/services/firebase_background_handler.dart';
import 'core/services/notification_service.dart';
import 'core/services/toast_service.dart';
import 'core/services/notification_router.dart';
import 'core/security/security_guard.dart';
import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Contención global de logs en RELEASE (CWE-532 móvil) ────────────
  // `debugPrint` NO se elimina solo en release; cualquier debugPrint disperso
  // (payloads de push, tokens FCM, cuerpos de respuesta) llegaría a Logcat/
  // Consola en producción. Aquí se anula en release: los diagnósticos deben ir
  // por AppLogger (que redacta) o por el crash reporter, nunca a la consola.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // ── Firebase ────────────────────────────────────────────────────────
  // Se inicializa con `DefaultFirebaseOptions.currentPlatform` (generado
  // por `flutterfire configure` en lib/firebase_options.dart) en vez de
  // con `Firebase.initializeApp()` a secas.
  //
  // Diferencia: sin opciones explícitas, Firebase las busca en los
  // recursos nativos, que solo existen si el plugin de Gradle procesó
  // google-services.json. Con opciones explícitas funciona en las tres
  // plataformas — incluida web, donde no hay recursos nativos.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    // Registrar el manejador de notificaciones en segundo plano en el nivel de aislamiento principal
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Se sigue arrancando sin push: es una degradación aceptable, la app
    // funciona entera salvo las notificaciones remotas.
    debugPrint('⚠️ [main] Firebase no disponible en el entorno actual o falta configuración nativa: $e');
  }

  // Deja constancia de a qué backend apunta la app. Evita horas perdidas
  // depurando cambios del backend local mientras la app habla con Railway.
  if (kDebugMode) {
    final env = AppConfig.environmentSummary;
    debugPrint('🌐 [main] Backend: ${env['modo']} · host=${env['host']}');
    debugPrint('🌐 [main] ai-service: ${env['ai']}');
  }

  // Inicializar canales nativos de notificación local y listeners en primer plano
  await NotificationServiceImpl.instance.initialize();

  // ── RASP (root/jailbreak, emulador, debugger, Frida, tampering) ─────────────
  // Solo en release/profile. En debug NO se inicializa: (1) detectaría el propio
  // debugger conectado, y (2) freerasp 7.x valida la config al construirse y los
  // hashes centinela (PENDIENTE_*) no son válidos → excepción. La advertencia no
  // bloqueante se enruta al ToastService; las amenazas activas cierran la app.
  if (!kDebugMode) {
    await SecurityGuard.instance.initialize(
      onWarning: (message) => ToastService.showWarningToast(message: message),
    );
  }

  // Configurar barra de estado superior y navegación translúcida (el tema dinámico gobierna el brillo)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Contenedor de Riverpod EXPLÍCITO para compartirlo con código fuera del árbol
  // de widgets (NotificationRouter → GoRouter). Se pasa a UncontrolledProviderScope
  // para que la app y el router de push usen el MISMO contenedor.
  final container = ProviderContainer();
  NotificationRouter.attach(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GymProApp(),
    ),
  );
}

class GymProApp extends ConsumerStatefulWidget {
  const GymProApp({super.key});

  @override
  ConsumerState<GymProApp> createState() => _GymProAppState();
}

class _GymProAppState extends ConsumerState<GymProApp> {
  @override
  void initState() {
    super.initState();
    // Verificar sesión existente en el hardware seguro tan pronto como inicia la app
    Future.microtask(() => ref.read(authProvider.notifier).checkInitialStatus());
  }

  @override
  Widget build(BuildContext context) {
    // Escuchar cambio de estado de auth para redirigir sin page push
    final authState = ref.watch(authProvider);

    return ToastificationWrapper(
      child: MaterialApp(
        title: 'GymPro Mobile',
        debugShowCheckedModeBanner: false,
        navigatorKey: ToastService.navigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system, // ➔ Detecta y cambia en tiempo real según el OS
        // AuthRouter: Si autenticado → AppShell con navegación premium de cristal;
        // Si anónimo → LoginScreen con animación de entrada
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: authState.isAuthenticated
              ? const AppShell(key: ValueKey('shell'))
              : const LoginScreen(key: ValueKey('login')),
        ),
      ),
    );
  }
}

