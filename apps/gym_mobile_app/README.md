# GymPro Mobile App — Clean Architecture & Native Authentication

Esta aplicación móvil implementa el cliente oficial de **GymPro** desarrollado con **Flutter 3.x** bajo el patrón de **Clean Architecture (Domain / Data / Presentation)** y gestión de estado con **Riverpod**.

---

## 🎨 Estética y Diseño Visual (`input_file_0.png` & `input_file_1.png`)
El diseño visual fusiona dos vertientes estéticas de alto rendimiento:
1. **Neon Sport Dark Mode (`input_file_0.png`)**: Fondo oscuro profundo (*Obsidian `#0A0914`*), acentos en neón púrpura eléctrico (`#9D00FF`), rosa vibrante (`#FF007A`) e iluminación dinámica con gradientes en los botones y encabezados de alta energía.
2. **Sleek Organic Cards (`input_file_1.png`)**: Tarjetas con bordes curvos amplios (`BorderRadius.circular(28)`), selectores en forma de píldora (*Capsule Buttons*) y jerarquía tipográfica limpia con la familia fuente moderna **Outfit / Inter**.

---

## 🔒 Tarea 4.1: Autenticación Nativa (`Apple Sign-In` & `Google Sign-In`)
El flujo de autenticación está diseñado para máxima seguridad y resiliencia ante errores de red o cancelaciones de usuario:

### Flujo Operativo:
1. **Interacción con el Sistema Operativo**:
   - `sign_in_with_apple`: Abre la ventana modal nativa del SO (Face ID / Touch ID) solicitando email y nombre.
   - `google_sign_in`: Invoca la hoja nativa de cuentas de Google configurada en Android/iOS.
2. **Captura y Validación Nativos**:
   - Se obtiene un `idToken` criptográficamente firmado por Apple (`IdentityToken`) o por los servidores de autenticación de Google.
3. **Manejo Robusto de Cancelación**:
   - Si el usuario cierra el diálogo nativo, el repositorio intercepta la excepción (`PlatformException` con código `CANCELED` o `SignInWithAppleAuthorizationExceptionCode.canceled`) y retorna un `UserCancelledFailure` limpio sin mostrar alertas intrusivas de error en el UI.
4. **Verificación Backend (`POST /api/v1/auth/oauth-login`)**:
   - El `idToken` nativo es enviado al `auth-service` de GymPro junto con el proveedor (`apple` o `google`) y el email validado.
   - El microservicio verifica la firma o localiza al usuario en el esquema `auth_service_db.usuarios` (creándolo automáticamente con rol `miembro` si es su primer ingreso).
5. **Almacenamiento Cifrado en Hardware**:
   - Al recibir la respuesta exitosa con el `accessToken` y `refreshToken` personalizados de GymPro, se guardan localmente usando `flutter_secure_storage` (respaldado por **iOS Keychain** con `kSecAttrAccessibleAfterFirstUnlock` y **Android Keystore / EncryptedSharedPreferences** con AES-256-GCM).

---

## 🏛️ Estructura del Proyecto

```text
lib/
├── main.dart
├── core/
│   ├── config/
│   │   └── app_config.dart          # Configuración de red y URLs de microservicios
│   ├── errors/
│   │   ├── exceptions.dart          # Excepciones nativas y de API
│   │   └── failures.dart            # Modelos de fallo tipados con dartz
│   ├── network/
│   │   ├── api_client.dart          # Dio intercepter + reintento automático + token refresh
│   │   └── auth_interceptor.dart    # Adjunta Bearer Token y maneja revocaciones (401)
│   ├── storage/
│   │   └── secure_storage_service.dart # Almacenamiento seguro en hardware
│   └── theme/
│       ├── app_colors.dart          # Paleta de colores Neón Sport
│       ├── app_typography.dart      # Estilos de texto Outfit / Inter
│       └── app_theme.dart           # ThemeData oscuro con curvas orgánicas
└── features/
    └── auth/
        ├── domain/
        │   ├── entities/auth_user.dart
        │   ├── repositories/auth_repository.dart
        │   └── usecases/
        │       ├── login_with_google_usecase.dart
        │       └── login_with_apple_usecase.dart
        ├── data/
        │   ├── datasources/
        │   │   ├── auth_local_data_source.dart
        │   │   └── auth_remote_data_source.dart
        │   ├── models/
        │   │   ├── oauth_credential_model.dart
        │   │   └── auth_response_model.dart
        │   └── repositories/auth_repository_impl.dart
        └── presentation/
            ├── providers/auth_provider.dart
            ├── screens/login_screen.dart
            └── widgets/
                ├── neon_glow_background.dart
                ├── social_login_button.dart
                └── auth_error_snackbar.dart
```
