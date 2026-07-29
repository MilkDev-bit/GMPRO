# Remediación — Fase 1 (móvil · hallazgos CRÍTICOS / bloqueantes de release)

> Rama objetivo: `security/fase-1-movil-criticos`. Cubre AND-1, AND-2, AND-3,
> IOS-1, IOS-2 del `audit-final-consolidado.md`. Fecha: 2026-07-24.
> **Máxima cautela**: un error aquí puede dejar la app sin instalar o sin
> autenticar, por eso los cambios priorizan **no brickear** y **no inventar**
> valores de firma/pinning.

## ⚠ Dos limitaciones del entorno (leer primero)
1. **Sin toolchain Flutter/Gradle** en el entorno de trabajo → **no se pudo
   ejecutar `flutter analyze`, `flutter test` ni `gradle`**. La validación
   realizada es **estática** (balance de llaves/paréntesis, coherencia de
   valores, gitignore). El **build en dispositivo/CI y las pruebas MASTG quedan
   como "pendiente de validación manual en dispositivo"**.
2. **Git bloqueado** (el FS montado impide borrar `.git/*.lock`): los cambios
   están **aplicados en el working tree**; crear la rama y commitear se hace en
   una máquina normal:
   ```bash
   rm -f .git/index.lock .git/HEAD.lock 2>/dev/null
   git checkout -b security/fase-1-movil-criticos
   # … editar/confirmar los valores pendientes … luego el commit del final.
   ```

## Estado

| # | Hallazgo | Estado |
|---|----------|--------|
| AND-2 / IOS-1 | Certificate pinning (pines placeholder) | ✅ Código preparado + **anti-brick** · ⏳ **necesito los hashes reales** |
| AND-1 | Android firmado con keystore de debug | ✅ `build.gradle.kts` lee firma del CI · ⏳ **humano genera el keystore** |
| AND-3 / IOS-2 | RASP con placeholders | ✅ package/bundle confirmados y fijados · ⏳ `signingCertHashes` + `teamId` **pendientes** |

---

## 1. AND-2 / IOS-1 — Certificate pinning

**Ubicación:** `apps/gym_mobile_app/lib/core/config/app_config.dart` (constantes de
pines + kill-switch) y `.../lib/core/network/ssl_pinning_adapter.dart` (motor). El
adapter es **multiplataforma** (`dart:io HttpClient`), así que un mismo arreglo cubre
Android **e** iOS. Se adjunta al Dio de la API en `api_client.dart:39`.

**Qué se hizo (sin inventar hashes):**
- Los pines quedan como **constantes centinela explícitas** donde van los reales:
  `_pinPlaceholderA/B = 'REEMPLAZAR_PIN_A/B_SPKI_SHA256_BASE64'` dentro de
  `certificatePins`.
- Nuevo getter `AppConfig.hasConfiguredPins`: es `true` **solo si hay ≥1 pin REAL**
  (distinto del centinela y no vacío).
- **Anti-brick (clave):** el adapter ahora hace fail-open a TLS del SO si
  `!isSSLPinningEnabled || !hasConfiguredPins`. Es decir, **con los centinelas el
  pinning NO se aplica** (la app conecta normal); en cuanto pongas un hash real, el
  pinning se **activa solo** (fail-closed, rechaza MITM). Así, desplegar con pines de
  ejemplo **no deja a los usuarios sin conexión**.
- **Kill-switch verificado y activo:** sigue disponible el apagado de emergencia por
  build-time `--dart-define=SSL_PINNING_ENABLED=false` (para rotación catastrófica de
  claves). En debug/local también queda inactivo (backend `http`).

> ⚠ **Nota de seguridad:** mientras los pines sean centinela, **NO hay protección
> anti-MITM** (es el precio de no brickear). El pinning solo protege de verdad tras
> colocar los hashes reales → es **bloqueante de release**.

**�� QUÉ NECESITO DE TI (no puedo generarlo):** los **hashes SPKI reales** del dominio
de producción de GymPro — el del **leaf actual** y el de una **clave de RESPALDO**
(backup pre-generado offline para rotación segura). Genéralos así (por cada host de
prod, p. ej. `auth-service.up.railway.app`, o el dominio propio si migran):
```bash
openssl s_client -connect <host>:443 -servername <host> < /dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | openssl enc -base64
```
Pásame los 2 valores base64 y los coloco en `certificatePins` (o los pones tú en
`app_config.dart`, reemplazando `_pinPlaceholderA/B`). **No inventé ni generé
valores de ejemplo como si fueran reales.**

---

## 2. AND-1 — Firma de release Android

**Ubicación:** `apps/gym_mobile_app/android/app/build.gradle.kts`.

**Qué se hizo (sin generar keystore):**
- Se eliminó `signingConfig = signingConfigs.getByName("debug")` del `release`.
- Se añadió `signingConfigs.create("release")` que **carga las credenciales desde
  `android/key.properties`** (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`)
  — el **mismo archivo que el CI ya genera** desde el secreto
  `ANDROID_KEY_PROPERTIES_BASE64` (ver `android-release.yml:65`), con el keystore desde
  `ANDROID_KEYSTORE_BASE64`. `key.properties` y `*.jks` están **gitignored** (verificado)
  → nunca en el repo.
- **Fallback seguro:** si `key.properties` no existe (dev local), el `release` cae a
  `debug` con un `logger.warn` — así `flutter run --release` sigue funcionando y **el
  AAB de producción se firma SIEMPRE en el pipeline** con el keystore real.

> La clave privada de firma **no la gestiona este agente**: se genera fuera y se
> inyecta como secreto de CI (idealmente respaldada en un secret manager/HSM).

**🔷 PROCEDIMIENTO HUMANO (una vez) para el keystore de producción:**
```bash
# 1) Generar el keystore de RELEASE (guárdalo en un lugar seguro, NUNCA en git):
keytool -genkeypair -v -keystore gympro-release.jks \
  -alias gympro -keyalg RSA -keysize 2048 -validity 10000
#    → responde a los prompts y ANOTA storePassword, keyPassword y alias.

# 2) Crear el key.properties que consumirá Gradle (contenido):
cat > key.properties <<'EOF'
storeFile=upload-keystore.jks
storePassword=<TU_STORE_PASSWORD>
keyAlias=gympro
keyPassword=<TU_KEY_PASSWORD>
EOF
#    (el CI copia el .jks a android/app/upload-keystore.jks; por eso storeFile es ese nombre)

# 3) Cargar como SECRETOS de GitHub (Settings → Secrets and variables → Actions):
base64 -w0 gympro-release.jks     > keystore.b64   # → secreto ANDROID_KEYSTORE_BASE64
base64 -w0 key.properties         > keyprops.b64   # → secreto ANDROID_KEY_PROPERTIES_BASE64
#    (pega el contenido de cada .b64 en su secreto; borra los .b64 y el .jks del disco de trabajo)
```
El workflow ya decodifica esos dos secretos a `android/app/upload-keystore.jks` y
`android/key.properties`, y los borra al final (`if: always()` cleanup). No hay que
tocar el workflow.

**Validación:** ⏳ **pendiente de validación manual** — requiere un build de release
firmado en CI y verificar la firma del AAB (`apksigner verify --print-certs`, o
`bundletool`) y su aceptación por Play. No ejecutable en este entorno.

---

## 3. AND-3 / IOS-2 — RASP (freerasp/Talsec)

**Ubicación:** `apps/gym_mobile_app/lib/core/security/security_guard.dart`.

**Qué se CONFIRMÓ y fijó (con certeza, leyendo el repo):**
- `androidConfig.packageName` → **`com.gympro.mobile`** — confirmado por
  `build.gradle.kts` (`namespace`/`applicationId`), `android/fastlane/Appfile`
  (`package_name`) y las entitlements iOS.
- `iosConfig.bundleIds` → **`['com.gympro.mobile']`** — confirmado por
  `ios/ExportOptions.plist` (provisioningProfiles + comentario), `ios/fastlane/Appfile`
  (`app_identifier`) y `Runner.entitlements` (keychain-access-group).

**Qué queda PENDIENTE (no confirmable sin acceso externo — NO inventado):**
- `androidConfig.signingCertHashes` → **PENDIENTE, acoplado a AND-1**. Es el SHA-256
  (base64) del **certificado de firma de RELEASE**, que aún no existe (no hay keystore
  de producción). Dejado como centinela `'PENDIENTE_SHA256_BASE64_CERT_RELEASE'`.
  Tras generar el keystore (paso AND-1):
  ```bash
  keytool -list -v -keystore gympro-release.jks -alias gympro | grep 'SHA256:'
  #   toma el valor hex (AA:BB:...), pásalo a base64:
  echo -n 'AABBCC...'  | xxd -r -p | base64      # ← reemplaza los ':' quitados
  ```
- `iosConfig.teamId` → **PENDIENTE**. El Apple Developer **Team ID** (10 chars) no está
  en el repo (`ExportOptions.plist` lo tiene como `REEMPLAZAR_TEAM_ID`). Obtenlo en
  developer.apple.com → Membership, o del perfil de firma.

> ⚠ **Bloqueante de release:** con los centinelas de `signingCertHashes`/`teamId`, la
> **atestación de firma de Talsec FALLARÁ en un build de release** (podría disparar la
> respuesta anti-tamper sobre la app legítima). En **debug la RASP relaja** los checks
> (`isProd: kReleaseMode`), así que el desarrollo no se ve afectado. **NO publicar** un
> release hasta rellenar ambos valores.

**Validación:** ⏳ **pendiente de validación manual en dispositivo** — requiere un build
de release firmado + ejecución en dispositivo físico (rooteado/jailbroken y limpio)
para confirmar que la atestación pasa con los valores reales.

---

## Validación realizada (estática) y pendiente

| Ítem | Estático (hecho) | Automático build/device (pendiente) |
|------|------------------|--------------------------------------|
| Pinning (app_config, adapter) | ✅ balance de llaves; sin `AAAA=`/`BBBB=`; guard `hasConfiguredPins` | `flutter analyze`/`test`; MITM real con proxy |
| build.gradle.kts | ✅ balance; lee `key.properties`; gitignore verificado | `gradle assembleRelease` firmado + `apksigner verify` |
| RASP (security_guard) | ✅ balance; `com.gympro.mobile` en package/bundle; sin `com.gympro.app` | Build release + atestación en dispositivo |

> No hay tests unitarios/instrumentados existentes que cubran estos archivos
> (`apps/gym_mobile_app/test/` no incluye pinning/RASP/signing). Se recomienda añadir
> un test de `hasConfiguredPins` (que devuelva false con los centinelas) en Fase 2.

---

## 🔷 Resumen de lo que NECESITO DE TI para cerrar (nada inventado)
1. **Pines SPKI reales** (leaf + backup) del dominio de producción — comando arriba.
2. **Keystore de producción** generado por un humano y cargado como secretos de CI
   (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES_BASE64`) — procedimiento arriba.
3. **`signingCertHashes`** del cert de release (se obtiene del keystore del punto 2).
4. **Apple `teamId`** (10 chars) de tu cuenta de Apple Developer.

Con (1) el pinning queda activo; con (2)+(3)+(4) la firma Android y la RASP quedan
listas para release. Hasta entonces: la app **funciona en dev y no se brickea**, pero
**no debe publicarse** (pinning inactivo + RASP con centinelas).

## Comando de commit (tras aplicar los cambios)
```bash
git add apps/gym_mobile_app/lib/core/config/app_config.dart \
        apps/gym_mobile_app/lib/core/network/ssl_pinning_adapter.dart \
        apps/gym_mobile_app/lib/core/security/security_guard.dart \
        apps/gym_mobile_app/android/app/build.gradle.kts \
        docs/security/remediation-fase1-movil.md
git commit -m "fix(sec): AND-1/AND-2/AND-3/IOS-1/IOS-2 mobile release-blockers (anti-brick pinning, CI-based signing, RASP ids)"
```
