# Endurecimiento de la API key de GCP (Firebase Android)

Proyecto Firebase/GCP: **gympro-cccd2** (project number `877957177840`)
Package Android: **com.gympro.mobile**
API key afectada: la "Android key (auto created by Firebase)" (misma que estaba en
`firebase_options.dart` / `google-services.json`).

La API key de Firebase **no es un secreto** (viaja en el APK). Lo que mitiga el
riesgo es restringirla por **aplicación (package + SHA-1)** y por **API**, además
de Firebase App Check. Este runbook cubre esos pasos.

---

## 1. Restricción de la API key (Google Cloud Console)

Consola: https://console.cloud.google.com/apis/credentials?project=gympro-cccd2
→ abrir la Android key → **Application restrictions** = *Android apps*, y
**API restrictions** = *Restrict key*.

### Application restrictions → Android apps
Una entrada por cada SHA-1, todas con package `com.gympro.mobile`:

| Entrada            | SHA-1                                                     | Estado |
|--------------------|----------------------------------------------------------|--------|
| Debug              | `A9:94:95:FD:1A:D4:EE:E1:6C:B1:51:E1:63:D6:2B:8D:35:E9:E5:12` | ✅ |
| Upload key         | `A5:E2:A2:9C:96:A7:E6:B0:A8:1A:20:83:E6:1F:2D:8D:A2:6E:C3:AD` | ✅ |
| Play App Signing   | (de Play Console tras subir el 1er AAB)                   | ⏳ |

### API restrictions → Restrict key
Marcar solo lo que se usa. Base para FCM:
- Firebase Installations API (`firebaseinstallations.googleapis.com`)
- Firebase Cloud Messaging API (`fcmregistrations.googleapis.com`)
- Firebase Remote Config API (`firebaseremoteconfig.googleapis.com`)

Añadir solo si se usa Firebase Auth:
- Identity Toolkit API (`identitytoolkit.googleapis.com`)
- Token Service API (`securetoken.googleapis.com`)

Guardar. La propagación tarda unos minutos.

---

## 2. Obtener los SHA-1

Nota JDK 25: `keytool -list -v` crashea en locale español
(`MissingFormatArgumentException '%2$s'`). Forzar inglés con
`-J-Duser.language=en -J-Duser.country=US`.

### Debug (desarrollo local)
```bash
keytool -J-Duser.language=en -J-Duser.country=US -list -v \
  -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android
```

### Upload key (nuestra llave de release)
Crear una sola vez (PKCS12 = una sola contraseña):
```bash
keytool -genkeypair -v -keystore ~/gympro-upload.jks -alias gympro-upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass 'TU_PASSWORD' -keypass 'TU_PASSWORD' \
  -dname "CN=GymPro, O=GymPro, C=MX"
```
Ver su SHA-1:
```bash
keytool -J-Duser.language=en -J-Duser.country=US -list -v \
  -keystore ~/gympro-upload.jks -alias gympro-upload -storepass 'TU_PASSWORD'
```
Guardar el `.jks` fuera del repo y respaldar la contraseña (sin ella no se
pueden publicar actualizaciones).

### Play App Signing (llave de Google)
Solo existe tras publicar en Play Console y subir el 1er AAB:
Play Console → app → **Prueba y lanzamiento → Integridad de la app → Firma de app**
→ copiar el SHA-1 del *Certificado de la clave de firma de la app*.

---

## 3. Cablear la firma de release (key.properties)

`apps/gym_mobile_app/android/key.properties` (gitignored). `build.gradle.kts`
lee `storeFile / storePassword / keyAlias / keyPassword`; si el archivo falta,
el release cae a debug (solo local, no publicable).

```properties
storeFile=/home/MictDev/gympro-upload.jks
keyAlias=gympro-upload
storePassword=TU_PASSWORD
keyPassword=TU_PASSWORD
```

En CI, el workflow `android-release.yml` genera este archivo desde los secretos
`ANDROID_KEY_PROPERTIES_BASE64` y `ANDROID_KEYSTORE_BASE64`.

---

## 4. Build del AAB — RESUELTO ✅

El AAB de release ya compila: `build/app/outputs/bundle/release/app-release.aab`.
Se resolvió alineando el toolchain (AGP 9/Gradle 9.1 estaban por delante del
ecosistema de plugins) y saliendo de dependencias muertas:

- `isar` 3.1.0 (discontinuado, sin `namespace`) → migrado a **isar_community 3.3.2**
  (imports `package:isar_community/isar.dart`, regenerar `.g.dart` con
  `dart run build_runner build`).
- `freerasp` 6.12 → **7.5.1** (SDK Android 18.x).
- Toolchain: **AGP 8.11.1 + Gradle 8.14 + Kotlin 2.2.20 + compileSdk 36**
  (mínimos que recomienda Flutter 3.44; siguen siendo AGP 8.x, sin la strictness
  de AGP 9 que rechazaba la regla consumer `-flattenpackagehierarchy` de freerasp).
- `android/app/build.gradle.kts`: `import java.util.Properties` (AGP 9 rompía
  `java.util.Properties()` en KTS).
- Fixes Dart: import `cupertino.dart` en `app_theme.dart`; `kReleaseMode` en el
  `show` de `foundation.dart` en `main.dart`.

Compilar con `flutter build appbundle` (Flutter usa el JBR 21; NO `./gradlew`
directo, que tomaría el JDK 25 del shell y Gradle 8.x no corre sobre 25).

### 4.1 freerasp appIntegrity — cert hash pendiente
`security_guard.dart` tiene `signingCertHashes: ['PENDIENTE_SHA256_BASE64_CERT_RELEASE']`.
En release, freerasp comparará contra el cert de **Play App Signing**; hay que
poner su **SHA-256 en base64** (se obtiene de Play Console tras subir el 1er AAB),
o la app se autocerrará al arrancar (`onAppIntegrity`).

---

## 5. Refuerzo adicional (recomendado)
- **Firebase App Check** (Play Integrity) en *enforce* para Auth/Firestore/Storage.
- Rotar la API key expuesta: crear una nueva ya restringida, publicar la app con
  ella, y borrar la vieja cuando el tráfico caiga a 0.
- Alertas de facturación por si hubo abuso mientras estuvo sin restringir.
