# Correos transaccionales + Isla Dinámica (Live Activities)

Implementación en dos fases: cola de correos en `fitness-service` y Live Activity
nativa en iOS con puente desde Flutter.

---

# Fase 1 — Correos transaccionales (fitness-service)

**Por qué `fitness-service`:** el disparador principal es de dominio fitness
("has completado {{rutina}}"). `auth-service` ya usa Resend para verificación/reset;
aquí se añade el módulo **con cola**, que es la pieza que faltaba en el monorepo.

## Arquitectura

```
[cualquier servicio] ──POST /internal/emails/enqueue──► [fitness-service]
                                                          │  (202 Accepted, ~ms)
                                                          ▼
                                                   BullMQ Queue (Redis)
                                                          │
                                                          ▼
                                                   emailWorker (concurrency 5)
                                                          │  reintentos exp. 2s→32s
                                                          ▼
                                                     Resend API
```

| Archivo | Rol |
|---|---|
| `services/email/emailTemplates.js` | 3 plantillas HTML "Neon Sport Dark" + render seguro |
| `services/email/emailProvider.js` | Adaptador Resend; errores tipados (retriable vs permanente) |
| `services/email/emailQueue.js` | Productor BullMQ (`enqueueEmail`) + degradación sin Redis |
| `services/email/emailWorker.js` | Consumidor con backoff y `UnrecoverableError` |
| `controllers/emailController.js` | Endpoint interno M2M |

## Contrato de API

**`POST /api/v1/internal/emails/enqueue`** · auth: `x-inter-service-secret` · **202 Accepted**

```jsonc
{
  "to": "socio@mail.com",
  "template": "workout_completed",     // workout_completed | workout_reminder | milestone_reached
  "vars": { "nombre": "Milton", "rutina": "Push Day",
            "duracionMin": 52, "ejercicios": 6, "seriesTotal": 18 },
  "delayMs": 0,                         // opcional: recordatorios programados
  "dedupeKey": "workout:u123:2026-07-20" // opcional: idempotencia (no duplica)
}
```
Respuesta: `{ "success": true, "data": { "aceptado": true, "queued": true, "jobId": "42" } }`

**`GET /api/v1/internal/emails/templates`** → catálogo de plantillas.

> `appUrl` se inyecta automáticamente desde `APP_DEEPLINK_URL`; no hace falta enviarlo.

## Decisiones de diseño

- **Compatibilidad de correo:** layout con `<table>` y **CSS inline** (Gmail elimina
  `<style>`, Outlook ignora flexbox/grid y `linear-gradient`). Los acentos neón se
  resuelven con colores planos y bordes.
- **Anti-XSS:** `renderTemplate` **escapa cada variable**. Verificado: un nombre con
  `<script>alert(1)</script>` se renderiza escapado, sin markup ejecutable.
- **Reintentos inteligentes:** email inválido o plantilla rota → `UnrecoverableError`
  (no reintenta, no gasta la cola). Timeout/5xx → 5 intentos con backoff exponencial.
- **Idempotencia:** `dedupeKey` se usa como `jobId` de BullMQ; reencolar el mismo hito
  no envía dos correos.
- **Degradación:** sin `REDIS_URL` la cola cae a envío directo best-effort; sin
  `RESEND_API_KEY` el proveedor simula y loguea (dev/CI sin credenciales).
- **Apagado limpio:** en `SIGTERM` se espera a los correos en vuelo antes de salir.

## Variables de entorno (nuevas)

```
RESEND_API_KEY=re_xxx            # ausente → modo simulación
EMAIL_FROM=noreply@gympro.app
EMAIL_FROM_NAME=GymPro
EMAIL_WORKER_CONCURRENCY=5
APP_DEEPLINK_URL=https://app.gympro.com
REDIS_URL=redis://...            # ausente → envío directo sin cola
```
Dependencias añadidas a `fitness-service`: **`bullmq`**, **`resend`** → `npm install`.

---

# Fase 2 — Isla Dinámica (Live Activities)

## ⚠️ Estado del proyecto iOS

Auditando el repo encontré que **el proyecto iOS está incompleto**: no existen
`Runner.xcodeproj`, `AppDelegate.swift` ni `Podfile` (solo `Info.plist`,
`Runner.entitlements` y el registrant generado). Consecuencias:

- Entrego **todo el código Swift y el puente**, y ya edité el `Info.plist`.
- **No es posible crear el target de la Widget Extension desde aquí**: eso vive en
  `project.pbxproj`, que no existe. Hay que hacerlo en Xcode (pasos abajo).
- Si el proyecto se regenera con `flutter create --platforms=ios .`, **conserva** el
  `Info.plist` actual (ya tiene `NSSupportsLiveActivities`) y añade `AppDelegate.swift`.

## Archivos entregados

| Archivo | Target |
|---|---|
| `ios/GymProLiveActivity/GymProWorkoutAttributes.swift` | **Runner + Extension** (ambos) |
| `ios/GymProLiveActivity/GymProLiveActivity.swift` | Extension |
| `ios/GymProLiveActivity/GymProLiveActivityBundle.swift` | Extension (`@main`) |
| `ios/Runner/LiveActivityBridge.swift` | Runner |
| `ios/Runner/AppDelegate.swift` | Runner |
| `lib/core/services/live_activity_service.dart` | Flutter |

## Pasos en Xcode (no automatizables)

1. `File → New → Target… → Widget Extension`. Nombre: **GymProLiveActivity**.
   Marca **Include Live Activity**; desmarca *Include Configuration Intent*.
2. Añade los 3 archivos de `ios/GymProLiveActivity/` al target nuevo.
   **`GymProWorkoutAttributes.swift` debe marcarse también en el target Runner**
   (File Inspector → Target Membership) — si no, el bridge no compila.
3. Si Xcode generó su propio archivo con `@main`, borra uno de los dos (solo puede
   haber un `@main` por extensión).
4. Verifica que el Info.plist de **ambos** targets tenga `NSSupportsLiveActivities = YES`
   (el de Runner ya lo tiene).
5. Deployment target de la extensión: **iOS 16.1+**.

## Contrato del MethodChannel

Canal: **`gympro/live_activity`**

| Método | Argumentos | Retorno |
|---|---|---|
| `isSupported` | — | `Bool` (respeta el ajuste del usuario) |
| `start` | `routineName`, `startedAtEpochMs`, `state{}` | `String?` activityId |
| `update` | `state{}` | `Bool` |
| `end` | `dismissImmediately: Bool` | `Bool` |

`state{}`: `currentExercise`, `nextExercise`, `setsDone`, `setsTotal`,
`isResting`, **`restEndsAtEpochMs`**, `accentHex`.

## Uso desde Flutter

```dart
final la = LiveActivityService.instance;

// Al iniciar la rutina
await la.start(
  routineName: 'Push Day — Pecho y Tríceps',
  state: WorkoutActivityState(
    currentExercise: 'Press de Banca',
    nextExercise: 'Aperturas con Mancuernas',
    setsDone: 0, setsTotal: 4, accentHex: '#FF007A',
  ),
);

// Al iniciar el descanso (UNA sola llamada; el reloj lo lleva iOS)
await la.update(state.copyWith(
  isResting: true,
  restEndsAt: DateTime.now().add(Duration(seconds: exercise.descansoSeg)),
), force: true);

// Al terminar
await la.end();
```

## Cómo se evita drenar la batería (lo importante)

1. **La cuenta atrás no se transmite.** Se envía la *fecha absoluta* de fin
   (`restEndsAt`) y SwiftUI la pinta con `Text(timerInterval:countsDown:)`: **iOS**
   decrementa el número, no la app. Una sesión de 60 min genera **~20 mensajes en vez
   de ~3.600**.
2. **Dedupe + throttle en Dart:** `update()` descarta estados idénticos y aplica un
   intervalo mínimo de 2 s (salvo `force: true` en cambios importantes).
3. **`pushType: nil`** — actualizaciones locales, sin APNs: cero tráfico de red.
4. **`staleDate`** (iOS 16.2+): si la app deja de reportar, el sistema marca la
   actividad como obsoleta en lugar de mostrar datos viejos indefinidamente.
5. Reutilización de la actividad viva en `start()` para no duplicar píldoras.

## Estados de la Isla Dinámica

- **minimal:** icono (reloj de arena si descansa / rayo si entrena).
- **compact:** icono + cuenta atrás **o** `series hechas/totales`.
- **expanded:** ejercicio actual (leading), descanso o series (trailing), barra de
  progreso (center), rutina y "Sigue: …" (bottom).
- **lock screen:** tarjeta completa con cronómetro total ascendente.

---

## Verificación realizada

- **Fase 1:** `node --check` en los 8 archivos + smoke test de render (variables
  inyectadas, `<script>` escapado, sin placeholders sueltos, 3 plantillas).
- **Fase 2:** `Info.plist` valida como XML y contiene `NSSupportsLiveActivities`;
  balance sintáctico OK en los 5 archivos Swift y en el servicio Dart.

**Pendiente (requiere entorno real):** `npm install` en fitness-service, y en macOS
con Xcode: crear el target, `flutter build ios` y probar la Live Activity en un
iPhone 14 Pro o superior (la Isla Dinámica no existe en el simulador de modelos previos).
