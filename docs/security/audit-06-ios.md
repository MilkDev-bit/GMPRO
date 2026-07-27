# Audit 06 — App iOS (OWASP MASVS / MASTG)

> Alcance: `apps/gym_mobile_app/ios` (Flutter/Dart + proyecto iOS nativo: target
> Runner en Swift + Widget Extension `GymProLiveActivity` de Live Activities).
> Basado en `audit-00-mapeo.md`. Fecha: 2026-07-24. Método: revisión estática con
> evidencia `archivo:línea`; sin compilar/instrumentar el IPA (sin dispositivo/
> Xcode) → verificación dinámica indicada como limitación.

## ¿Incluye app iOS?
**Sí.** Proyecto iOS completo: `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`,
Swift (`AppDelegate.swift`, `LiveActivityBridge.swift`) y una **App Extension** de
Live Activities (`ios/GymProLiveActivity/*.swift`). Se procede con MASVS.

## Tabla resumen

| ID | Categoría MASVS | Hallazgo | Severidad | Evidencia |
|----|-----------------|----------|-----------|-----------|
| IOS-1 | NETWORK | **Pines de certificado placeholder** (adapter Dart aplica a iOS) | **Alta** | `lib/core/config/app_config.dart:156-160` |
| IOS-2 | RESILIENCE | Config RASP iOS con placeholders (`bundleIds`/`teamId`) + kill activo débil en iOS | Media | `security_guard.dart:70-71,100-103` |
| IOS-3 | STORAGE | Isar sin cifrar con PII + sin clase de Data Protection explícita | Media | `isar_service.dart:38-40`; `local_user.dart:19-21` |
| IOS-4 | PLATFORM | Google Sign-In vía **URL scheme custom** (placeholder + esquema secuestrable) | Baja | `Info.plist:53-57` |
| IOS-5 | STORAGE/CRYPTO | Keychain correcto (device-only, grupo acotado) + Secure Enclave para Apple Sign-In | ✅ Correcto | `secure_storage_service.dart:20-27`; `Runner.entitlements:12-15` |
| IOS-6 | NETWORK | **ATS en default seguro** (sin `NSAllowsArbitraryLoads` ni excepciones) | ✅ Correcto | `Info.plist` (ausencia de `NSAppTransportSecurity`) |
| IOS-7 | PLATFORM | Permisos mínimos; sin App Group con datos sensibles; Live Activity sin PII | ✅ Correcto | `Info.plist:62`; `GymProWorkoutAttributes.swift:22-51` |
| IOS-8 | CODE | Sin secretos hardcodeados; firma de release real + ofuscación Dart | ✅ Correcto | `ios-release.yml:53-89` |

---

## MASVS-STORAGE — Almacenamiento

### IOS-5 (Correcto) — Keychain / Secure Enclave
- `flutter_secure_storage` iOS: `IOSOptions(accessibility:
  KeychainAccessibility.first_unlock_this_device)` (`secure_storage_service.dart:20-27`)
  → los tokens viven en el **Keychain**, disponibles tras el primer desbloqueo y
  **no se sincronizan a iCloud/backup** (`this_device`). Correcto para tokens.
- `Runner.entitlements:12-15`: `keychain-access-groups` acotado a
  `$(AppIdentifierPrefix)com.gympro.mobile` (prefijo de team, no comodín ni grupo
  compartido amplio) → aislamiento correcto del Keychain.
- **Apple Sign-In** (`Runner.entitlements:6-9`) usa el Secure Enclave del dispositivo
  para la credencial; las passkeys/WebAuthn se verifican en backend.
- **UserDefaults:** no se detecta almacenamiento de datos sensibles en UserDefaults
  ni un App Group compartido (ver IOS-7).

### IOS-3 (Media) — Isar sin cifrar + sin Data Protection explícita
La base local Isar se abre **sin `encryptionKey`** (`isar_service.dart:38-40`) y
`LocalUser` guarda PII (`email`, `nombre`, `apellidoPaterno`, `local_user.dart:19-21`).
En iOS el archivo hereda la protección de datos **por defecto**
(`NSFileProtectionCompleteUntilFirstUserAuthentication`), no `Complete`, y el
contenido queda **en claro**.
- **Impacto:** en un dispositivo con jailbreak o extracción forense tras el primer
  desbloqueo, la PII cacheada es legible. MASVS-STORAGE-1/2. (Mismo hallazgo que
  Android **AND-4**; en iOS se suma la ausencia de clase de protección explícita.)
- **Remediación:** cifrar Isar con clave en Keychain, o no cachear PII; y declarar
  `NSFileProtectionComplete` para el contenedor de datos sensibles.

## MASVS-CRYPTO — Criptografía
Sin claves criptográficas ni secretos embebidos en Swift/plist (grep = 0). La Firebase
apiKey (en `GoogleService-Info.plist`, **no versionado** — verificado) es un
identificador de cliente, no un secreto; su protección depende de Firebase Security
Rules + App Check (consola). El manejo de claves se apoya en Keychain/Secure Enclave
(IOS-5). Correcto.

## MASVS-NETWORK — Comunicación

### IOS-6 (Correcto) — ATS
No existe la clave `NSAppTransportSecurity` en `Info.plist` → **ATS en su default
seguro**: TLS obligatorio, sin `NSAllowsArbitraryLoads`, sin `NSExceptionDomains` ni
`NSAllowsLocalNetworking` (grep en todos los plist = 0). Todo el tráfico de producción
es https (`app_config.dart:59-75`).

### IOS-1 (Alta) — Pines de certificado placeholder
El certificate pinning se implementa en Dart con `dart:io HttpClient` +
`badCertificateCallback` (`ssl_pinning_adapter.dart`), que **aplica igual en iOS**, y
está adjuntado al Dio de API (`api_client.dart:39`). Pero `AppConfig.certificatePins`
contiene **valores de relleno** `{'AAAA…=','BBBB…='}` con "⚠ REEMPLAZAR"
(`app_config.dart:156-160`).
- **Impacto:** idéntico a Android **AND-2**: con pines falsos, en release el pinning o
  **rompe toda conexión** o se **desactiva** (kill-switch) quedando **sin anti-MITM**.
- **Remediación:** colocar los pines SPKI reales (leaf + backup) y mantener el
  kill-switch activo; validar contra un proxy MITM en un build real.

## MASVS-PLATFORM — Interacción con la plataforma

### IOS-7 (Correcto) — Permisos, App Groups y Live Activity
- **Usage descriptions mínimas:** solo `NSFaceIDUsageDescription` (`Info.plist:62`),
  coherente con el login biométrico. **No** se solicitan cámara, ubicación, contactos,
  fotos, micrófono, etc. → sin exceso de permisos.
- **Sin App Groups:** no hay entitlement `com.apple.security.application-groups` en
  ningún target; la Live Activity recibe datos vía **ActivityKit** (no por un
  contenedor compartido UserDefaults/Keychain), evitando fuga por App Group mal
  configurado.
- **Live Activity sin PII:** `GymProWorkoutAttributes.ContentState`
  (`GymProWorkoutAttributes.swift:22-51`) solo expone datos de entrenamiento
  (`currentExercise`, `nextExercise`, `setsDone/Total`, `restEndsAt`, `routineName`).
  Aunque se muestran en la **pantalla de bloqueo**, no contienen identificadores ni
  datos de salud sensibles. `LiveActivityBridge.swift` no maneja tokens/secretos.

### IOS-4 (Baja) — Google Sign-In por URL scheme custom
`Info.plist:53-57` registra un `CFBundleURLSchemes` para el callback de Google Sign-In
con **valor placeholder** (`com.googleusercontent.apps.1234567890-abc…`, "Reemplazar
con el REVERSE_CLIENT_ID").
- **Impacto:** (a) funcional — el login con Google no funcionará hasta reemplazarlo;
  (b) seguridad — los **URL schemes custom son secuestrables** (otra app puede
  registrar el mismo esquema e interceptar el callback OAuth). Riesgo bajo con
  PKCE/validación del `state`, pero inferior a Universal Links.
- **Remediación:** reemplazar por el REVERSE_CLIENT_ID real y, preferentemente, usar
  `ASWebAuthenticationSession` / Universal Links para el flujo OAuth en vez de un
  esquema custom.

## MASVS-RESILIENCE — Anti-tampering / Jailbreak

### IOS-2 (Media) — Config RASP iOS incompleta + respuesta activa débil
`security_guard.dart:70-71`: `iosConfig` con `bundleIds: ['com.gympro.app']`
(**placeholder** y **distinto** del bundle real `com.gympro.mobile`) y
`teamId: 'REEMPLAZAR_TEAMID'`.
- **Impacto:** la verificación de **integridad/binding de bundle** de freerasp/Talsec
  no funciona con `teamId` y `bundleId` incorrectos (falsos positivos o check inerte).
  La detección de **jailbreak/debugger/hooks** sí está cableada (`security_guard.dart:41-52`),
  pero la respuesta **activa** en iOS usa `SystemNavigator.pop()`, que en iOS **solo
  manda la app a segundo plano** (no la termina), como reconoce el propio comentario
  (`:100-102`) → mitigación de tampering más débil que en Android.
- **Remediación:** fijar `bundleIds=['com.gympro.mobile']` y el `teamId` real; para la
  respuesta activa en iOS, complementar `SystemNavigator.pop()` con invalidación de
  sesión/borrado de tokens del Keychain y bloqueo de operaciones sensibles (no
  depender de "cerrar" la app).

## MASVS-CODE — Calidad y ofuscación

### IOS-8 (Correcto)
- **Sin secretos hardcodeados** en Swift, Info.plist ni recursos (grep = 0);
  `GoogleService-Info.plist` no está versionado.
- **Firma de release real:** el pipeline usa keychain temporal + certificado de
  distribución (secretos de CI) y `ExportOptions.plist` con `method=app-store`
  (`ios-release.yml:53-89`; `ios/ExportOptions.plist:13-23`) — **a diferencia de
  Android (AND-1), iOS no firma con credenciales de debug**.
- **Ofuscación Dart** en el build: `flutter build ipa --release --obfuscate
  --split-debug-info` (`ios-release.yml:85-87`).

---

## Limitaciones
- No se compiló ni instrumentó el IPA (sin macOS/Xcode/dispositivo). Faltaría verificar
  en runtime: pinning contra proxy MITM, la clase de Data Protection efectiva del
  archivo Isar, la detección real de jailbreak, y que no se filtren datos por
  `pasteboard`/capturas de pantalla (no evaluado estáticamente).
- Eficacia de la Firebase apiKey depende de Security Rules + App Check (consola).

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Sustituir pines SPKI placeholder por reales (compartido con Android) | IOS-1 |
| 2 | Corregir RASP iOS: `bundleIds=com.gympro.mobile`, `teamId` real; endurecer respuesta activa | IOS-2 |
| 3 | Cifrar Isar / no cachear PII + `NSFileProtectionComplete` | IOS-3 |
| 4 | Reemplazar REVERSE_CLIENT_ID y migrar OAuth a Universal Links/ASWebAuthenticationSession | IOS-4 |

> Balance: la postura iOS es **más completa que la de Android** — ATS seguro por
> defecto, Keychain bien usado (device-only, grupo acotado), permisos mínimos, sin App
> Groups con datos sensibles, Live Activity sin PII, y **firma de release + ofuscación
> ya resueltas en CI**. Los pendientes reales son **compartidos con Android**
> (pines TLS reales, config RASP con identificadores reales, cifrado de Isar) más el
> detalle iOS del OAuth por URL scheme. IOS-1 es bloqueante de release.
