# Audit 05 — App Android (OWASP MASVS / MASTG)

> Alcance: `apps/gym_mobile_app` (Flutter/Dart + capa nativa Android Kotlin/Gradle
> KTS). Basado en `audit-00-mapeo.md`. Fecha: 2026-07-24. Método: revisión estática
> con evidencia `archivo:línea`. No se compiló ni instrumentó el APK (sin
> dispositivo/emulador); las verificaciones dinámicas quedan indicadas como
> limitación.

## ¿Incluye app Android?
**Sí.** App Flutter con proyecto Android nativo completo
(`android/app/src/main/AndroidManifest.xml`, `build.gradle.kts`, capa
Kotlin/Swift). Se procede con MASVS.

## Tabla resumen

| ID | Categoría MASVS | Hallazgo | Severidad | Evidencia |
|----|-----------------|----------|-----------|-----------|
| AND-1 | RESILIENCE / CODE | **Build de release firmado con el keystore de DEBUG** | **Alta** | `android/app/build.gradle.kts:34-37` |
| AND-2 | NETWORK | **Pines de certificado son placeholders** (`AAAA=`/`BBBB=`) | **Alta** | `app_config.dart:156-160` |
| AND-3 | RESILIENCE | Config RASP con placeholders + `packageName` no coincide con `applicationId` | Media | `security_guard.dart:60-73` vs `build.gradle.kts:24` |
| AND-4 | STORAGE | Base de datos **Isar sin cifrar** almacena PII (email, nombre) | Media | `isar_service.dart:38-40`; `local_user.dart:19-21` |
| AND-5 | CODE | Sin **R8/minify/shrinkResources** ni `proguard-rules.pro` (capa nativa) | Media–Baja | `build.gradle.kts` (ausencia); Dart sí ofuscado en CI |
| AND-6 | STORAGE / PLATFORM | Secure storage cifrado + backup deshabilitado | ✅ Correcto | `secure_storage_service.dart:14-27`; manifest:10-12 |
| AND-7 | PLATFORM | Manifest: permisos mínimos, un solo componente exportado | ✅ Correcto | `AndroidManifest.xml:3-4,13-15` |
| AND-8 | NETWORK / AUTH | HTTPS en prod; autorización decidida en servidor | ✅ Correcto | `app_config.dart:59-75` |
| AND-9 | CRYPTO | Sin algoritmos débiles ni claves cripto hardcodeadas | ✅ Correcto | (Firebase apiKey es identificador de cliente, no secreto) |

---

## MASVS-STORAGE — Almacenamiento

### AND-4 (Media) — Isar sin cifrado con PII en reposo
`IsarService` abre la base local **sin `encryptionKey`**
(`isar_service.dart:38-40`: `Isar.open([LocalUserSchema, LocalRoutineSchema,
SyncActionSchema], directory: dir.path)`). `LocalUser` almacena **PII**: `remoteId`,
`nombre`, `apellidoPaterno`, `email`, `avatarUrl` (`local_user.dart:17-22`).
- **Impacto:** los datos quedan en archivos de la base en el almacenamiento interno
  **en claro**. Está mitigado por el sandbox de la app y `allowBackup=false`, pero en
  un dispositivo **rooteado** o por extracción forense se leen directamente. MASVS-STORAGE-1.
- **Remediación:** (a) no cachear PII en Isar (guardar solo lo no sensible y derivar
  el perfil desde memoria/secure storage), o (b) cifrar la base (clave de 256 bits
  generada y guardada en `flutter_secure_storage`/Keystore y pasada como
  `encryptionKey` a `Isar.open`). Clasificar `email`/`nombre` como sensibles.

### AND-6 (Correcto) — Secure storage + backup
- `flutter_secure_storage` con `AndroidOptions(encryptedSharedPreferences: true)`
  (respaldo por Android Keystore) e iOS `KeychainAccessibility.first_unlock_this_device`
  (no se sincroniza a iCloud) — `secure_storage_service.dart:14-27`. Tokens de acceso
  y refresh se guardan aquí, no en `SharedPreferences` plano.
- `allowBackup="false"`, `fullBackupContent="false"` y `dataExtractionRules`
  (`AndroidManifest.xml:10-12`) → impiden exfiltración vía `adb backup`/transfer.

## MASVS-CRYPTO — Criptografía

### AND-9 (Correcto)
- No hay algoritmos débiles ni claves criptográficas embebidas en `lib/`. La clave de
  cifrado en reposo del backend vive en el servidor (no en la app).
- **Firebase `apiKey`** (`firebase_options.dart:53`, `AIza…`) está embebida **por
  diseño**: es un identificador público del proyecto, no un secreto; su protección
  depende de las **Firebase Security Rules + App Check** (verificar que estén
  configuradas — no auditable desde el repo).
- El cifrado AES-256-GCM de los QR ocurre en el backend (access-service), no en la app.

## MASVS-NETWORK — Comunicación

### AND-2 (Alta) — Pines de certificado son placeholders
La arquitectura de pinning es **correcta** (SPKI SHA-256, `SecurityContext(
withTrustedRoots:false)`, `badCertificateCallback` que rechaza si el pin no coincide,
kill-switch, adjuntado al Dio de API en `api_client.dart:39`). **Pero los pines son
valores de relleno**: `app_config.dart:156-160` define
`{'AAAAAAAA…=', 'BBBBBBBB…='}` con comentarios "⚠ REEMPLAZAR con el hash real".
- **Impacto:** tal como está commiteado, en release con pinning activo **ninguna
  conexión validaría** (los pines falsos no coinciden con el cert real) → o la app no
  conecta, o alguien **desactiva el kill-switch** para que funcione, quedando **sin
  pinning** (anti-MITM inexistente). En ambos casos el control no protege.
- **Remediación:** generar los pines SPKI reales del leaf **y** de una clave de
  respaldo (`openssl … | openssl dgst -sha256 -binary | openssl enc -base64`),
  colocarlos en `certificatePins`, y mantener el kill-switch en `true`. Verificar en
  un build real que la conexión valida y que un cert MITM se rechaza.

### AND-8 (Correcto) — TLS
Todas las URLs de producción son **https** (`app_config.dart:59-75`); el `http://`
solo aplica al backend local de desarrollo, gateado por `useLocalBackend`. Sin
`usesCleartextTraffic` en el manifest (default seguro en API 28+).
> Endurecimiento sugerido: añadir `res/xml/network_security_config.xml` con
> `cleartextTrafficPermitted="false"` explícito (defensa en profundidad, cubre
> variantes de fabricante) — hoy solo existe `data_extraction_rules.xml`.

## MASVS-AUTH — Autenticación/Autorización
La app **no toma decisiones de autorización en el cliente**: el RBAC y la validación
de JWT ocurren en el backend (ver `audit-01`); el cliente solo adjunta el `Bearer`
(`auth_interceptor.dart:64-66`) y refresca vía cookie httpOnly. Tokens en secure
storage (AND-6). Correcto.

## MASVS-PLATFORM — Interacción con la plataforma

### AND-7 (Correcto) — Manifest
- **Permisos mínimos:** solo `INTERNET` y `ACCESS_NETWORK_STATE`
  (`AndroidManifest.xml:3-4`). Sin permisos peligrosos (ubicación, contactos,
  almacenamiento externo, cámara declarada en manifest, etc.).
- **Componentes:** únicamente `MainActivity` está `exported="true"` (obligatorio por
  el `LAUNCHER`), con `launchMode="singleTop"` y `taskAffinity=""` (mitiga task
  hijacking). **No hay** Services, Broadcast Receivers ni Content Providers exportados
  sin protección.
> Nota: no hay `intent-filter` de deep link/App Links en este manifest; si se
> habilitan Universal/App Links (mencionados en el diseño), deben añadirse con
> `android:autoVerify="true"` y validar el host.

## MASVS-CODE & RESILIENCE — Calidad, ofuscación, anti-tampering

### AND-1 (Alta) — Release firmado con keystore de DEBUG
`android/app/build.gradle.kts:34-37`: el `buildType release` usa
`signingConfig = signingConfigs.getByName("debug")` con el `TODO: Add your own
signing config`.
- **Impacto:** el certificado de debug es **público y conocido** → cualquiera puede
  re-firmar un APK/AAB modificado y hacerlo pasar por legítimo (rompe la integridad
  de la app y la verificación de firma). Además, un AAB firmado con debug **no se
  puede publicar** en Play y **invalida** el `signingCertHashes` de RASP (AND-3).
- **Remediación:** configurar un `signingConfig` de release con keystore propio
  (inyectado por CI vía secreto, como ya prevé `audit-01`), y usar Play App Signing.

### AND-3 (Media) — Config RASP con placeholders + package mismatch
`security_guard.dart:60-73`: `packageName: 'com.gympro.app'` (marcado "⚠ REEMPLAZAR"),
`signingCertHashes: ['REEMPLAZAR_SHA256_BASE64_DEL_CERT_DE_FIRMA=']`, iOS
`teamId: 'REEMPLAZAR_TEAMID'`. Además **no coincide** con el `applicationId` real
`com.gympro.mobile` (`build.gradle.kts:24`).
- **Impacto:** la detección de **repackaging/tampering** de freerasp/Talsec **no
  funciona** con hashes de firma falsos, y el `packageName` divergente puede provocar
  falsos positivos o desactivar el check. El resto de RASP (root/jailbreak, emulador,
  debugger, Frida/hooks → cierre) sí está bien cableado (`security_guard.dart:41-52,103`).
- **Remediación:** fijar `packageName`/`bundleIds` al identificador real
  (`com.gympro.mobile`), rellenar `signingCertHashes` con el SHA-256 (base64) del
  **cert de release** (coherente con AND-1) y el `teamId` iOS.

### AND-5 (Media–Baja) — Sin R8/minify en la capa nativa
El `buildType release` de `build.gradle.kts` **no habilita** `isMinifyEnabled`,
`isShrinkResources` ni referencia un `proguard-rules.pro` (no existe el archivo).
- **Matiz:** el **código Dart SÍ se ofusca** en el pipeline
  (`.github/workflows/android-release.yml:81-83`: `flutter build appbundle --release
  --obfuscate --split-debug-info=build/symbols`), y en una app Flutter la lógica vive
  mayormente en Dart, por lo que el riesgo residual es la **capa host Kotlin/Java**
  (delgada). Aun así, R8 aporta shrinking y ofuscación del bytecode nativo.
- **Remediación:** en el bloque `release` activar `isMinifyEnabled = true` y
  `isShrinkResources = true` con un `proguard-rules.pro` que preserve Flutter/plugins.

### Correcto (RESILIENCE)
- **RASP activo** (freerasp/Talsec) con política híbrida: pasiva para
  root/jailbreak, emulador, debugger y tienda no oficial; **activa** para
  hooks/Frida/tampering → `SystemNavigator.pop()` (`security_guard.dart:41-52,100-103`).
- **Detección de root/integridad** presente (a falta de la config de firma real, AND-3).
- **Ofuscación Dart** en CI (AND-5).

---

## Limitaciones
- No se compiló/instaló el APK ni se ejecutó MASTG dinámico (sin dispositivo). Faltaría
  verificar en runtime: efectividad real del pinning contra un proxy MITM, que la base
  Isar en `/data/data/<pkg>` está (o no) cifrada, y el comportamiento de RASP en un
  dispositivo rooteado.
- La eficacia de la Firebase apiKey depende de Security Rules + App Check (consola Firebase).

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Configurar `signingConfig` de release propio (no debug) | AND-1 |
| 2 | Sustituir los pines SPKI placeholder por los reales (leaf + backup) | AND-2 |
| 3 | Rellenar RASP: `packageName=com.gympro.mobile`, `signingCertHashes`, `teamId` | AND-3 |
| 4 | Cifrar Isar o dejar de cachear PII (email/nombre) | AND-4 |
| 5 | Habilitar R8 (`minify`+`shrinkResources`) + `proguard-rules.pro` | AND-5 |
| 6 | Añadir `network_security_config.xml` (cleartext=false explícito) | AND-8 |

> Balance: la app tiene una **arquitectura de seguridad madura** (secure storage
> cifrado, permisos mínimos, sin componentes exportados, RASP, pinning y ofuscación
> Dart). El problema es que **varios controles de release están sin finalizar**
> (placeholders): firma con debug (AND-1), pines falsos (AND-2) y hashes RASP de
> relleno (AND-3) **anulan en la práctica** las defensas de red e integridad hasta
> completarlos. Son bloqueantes de release, no rediseños.
