# Audit 00 — Mapeo del proyecto GymPro

> Documento base de la auditoría AppSec. Fija el alcance real (qué existe / qué
> no) para las auditorías parciales siguientes (`audit-01…`). Fecha: 2026-07-24.

GymPro es un **monorepo** de una plataforma de gimnasio: backend de microservicios
Node.js sobre Supabase (Postgres) + Redis, una app móvil Flutter (Android/iOS), un
panel web de administración React, y un controlador de hardware de recepción
(IoT: lector QR, relé de torniquete, impresora térmica). Despliegue en Railway.

Tamaño aproximado: **~420 archivos versionados**; ~18.1k líneas JS (backend),
~23.4k líneas Dart (móvil), ~1.7k TS/TSX (panel), ~1.1k Python (hardware);
**6 servicios backend**, **14 archivos SQL** (esquemas + migraciones), **5
Dockerfiles**, **4 workflows CI/CD**.

---

## 1. Componentes presentes

| # | Componente | Tipo | Existe |
|---|------------|------|--------|
| 1 | 5 microservicios Node/Express | Backend / API | ✅ |
| 2 | `packages_shared/security` | Librería compartida (middleware seguridad) | ✅ |
| 3 | reception-hardware-controller | Edge / IoT (Node + Python) | ✅ |
| 4 | gym_mobile_app | App móvil Flutter (Android **e** iOS) | ✅ |
| 5 | admin-web | Frontend web (React SPA) | ✅ |
| 6 | Supabase Postgres + Redis | Datos / cache | ✅ |
| 7 | Docker + docker-compose | Contenedores (local/build) | ✅ |
| 8 | Railway (`railway/*.json`) | PaaS / config de despliegue | ✅ |
| 9 | GitHub Actions | CI/CD | ✅ |
| — | Terraform / CloudFormation / Pulumi | IaC declarativa | ❌ **no existe** |
| — | Kubernetes / Helm | Orquestación | ❌ **no existe** |
| — | Backend for Frontend / GraphQL gateway | — | ❌ **no existe** |

---

## 2. Detalle por componente (stack · gestor · ubicación)

### 2.1 Microservicios backend (Node.js)
- **Stack:** Node ≥ 22, Express, `@supabase/supabase-js` (service_role), Redis
  (`ioredis`), JWT (`jsonwebtoken`), `helmet`, `hpp`, `express-rate-limit` +
  `rate-limit-redis`, `express-validator`, `winston`. Tests con **Jest** (5/6).
- **Gestor:** npm (cada servicio tiene su `package.json` + `node_modules`).
- **Ubicación:** `services/<servicio>/src/{config,controllers,middlewares,models,routes,services}`.

| Servicio | Path | Rol | Dependencias notables |
|----------|------|-----|------------------------|
| **auth-service** | `services/auth-service` | Identidad: login, OAuth, JWT, refresh tokens con familias, WebAuthn | `bcrypt`, `@simplewebauthn/server`, `cookie-parser` |
| **payment-service** | `services/payment-service` | Cobros Stripe, webhooks, suscripciones, ofertas, ledger, recibos PDF | `stripe`(SDK vía config), `axios`, `pdfkit` |
| **access-service** | `services/access-service` | Control de acceso físico, QR nonces, sincronización biométrica | `jsonwebtoken`, `ioredis` |
| **fitness-service** | `services/fitness-service` | Rutinas, retención/crecimiento, emails, colas | `bullmq`, `resend` |
| **ai-service** | `services/ai-service` | Asistente IA (chat, nutrición, RAG, caché semántico) | `@supabase/supabase-js`, embeddings |
| **reception-hardware-controller** | `services/reception-hardware-controller` | Edge/IoT — **no es API HTTP**, es cliente de hardware | ver 2.2 |

### 2.2 Controlador de hardware de recepción (Edge/IoT)
- **Stack:** doble implementación — **Node** (`escpos`, `serialport`, `axios`) y
  **Python 3** (`pyserial`, `python-escpos`, `pyusb`, `evdev`, `requests`).
- **Gestor:** npm (`node/package.json`) y pip (`python/requirements.txt`).
- **Ubicación:** `services/reception-hardware-controller/{node,python}`.
- **Superficie:** puertos serie/USB (relé de torniquete, lector QR HID, impresora
  térmica 80mm); **cliente saliente** hacia access-service/payment-service con API Key.
  No expone puertos de red entrantes.

### 2.3 Librería compartida de seguridad
- **Ubicación:** `packages_shared/security/` — `corsConfig`, `helmetConfig`,
  `jwtVerify`, `rateLimiter`, `inputSanitizer`, `ssrfGuard`, `errorHandler`,
  `logger`. **Crítica:** un fallo aquí impacta a los 5 servicios a la vez.

### 2.4 App móvil (Flutter)
- **Stack:** Flutter/Dart; Riverpod, `go_router`, `dio`, **Isar** (offline-first),
  `flutter_secure_storage`, **freerasp** (RASP: root/jailbreak/Frida/tamper),
  Firebase (`firebase_core`, `firebase_messaging` FCM/APNs), `rive`, `lottie`.
- **Gestor:** pub (`pubspec.yaml`).
- **Ubicación:** `apps/gym_mobile_app/lib/{core,features}`; nativo en
  `android/` (Kotlin/Gradle KTS) e `ios/` (Swift — incl. **Live Activity**
  `ios/GymProLiveActivity/*.swift`).

### 2.5 Panel web de administración
- **Stack:** React 18 + Vite + TypeScript + TailwindCSS + React Router + Recharts.
- **Gestor:** npm (`apps/admin-web/package.json`).
- **Ubicación:** `apps/admin-web/src/{pages,components,lib,auth}`. Token en memoria
  (no localStorage); RBAC `staff`/`admin` (ingresos reservados a `admin`).

### 2.6 Datos
- **Supabase Postgres** con esquemas por servicio (`auth_service_db`,
  `payment_service_db`, …) y modelo **RLS deny-all** (solo `service_role` accede).
- **Redis** (blacklist JWT, rate limiting, caché, colas).
- **Ubicación SQL:** `docs/database/schemas/` (creación) y
  `docs/database/{migrations,schemas/migrations}/` (14 archivos .sql).

---

## 3. Archivos de configuración sensibles

| Categoría | Archivos | Notas de riesgo |
|-----------|----------|-----------------|
| **Secretos backend** | `services/*/.env` (reales, en disco) + `.env.bak.*` | ⚠ Presentes en el árbol de trabajo. **NO tracked** en git (verificado). `.gitignore` cubre `.env` y `*.env.bak.*`. Solo `.env.example` se versiona. |
| Gestión de secretos | `scripts/check-secrets.sh`, `scripts/sync-secrets.sh` | Revisar que no filtren secretos en logs/artefactos. |
| **Android** | `android/app/src/main/AndroidManifest.xml` (+ debug/profile), `android/app/build.gradle.kts`, `android/build.gradle.kts` | Permisos, exported components, deep links, firma, minify/obfuscation. |
| **iOS** | `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements` | ATS, URL schemes/Universal Links, entitlements, capacidades. |
| CI/CD firma app | `android/fastlane/{Appfile,Fastfile}`, `ios/fastlane/{Appfile,Fastfile}` | Manejo de keystore/certs/API keys de stores. |
| **Contenedores** | 5× `services/*/Dockerfile`, `docker-compose.yml` | Usuario no-root, imágenes base, secretos en build, puertos. |
| **PaaS** | `railway/{auth,access,payment,fitness,ai}.json` | Variables, health checks, réplicas. |
| **CI/CD** | `.github/workflows/{test,integration,android-release,ios-release}.yml` | Inyección de secretos (base64), permisos del token, `if: always()` cleanup. |
| Webhooks/pagos | `payment-service` config Stripe, `STRIPE_WEBHOOK_SECRET` | Verificación de firma HMAC (ya implementada en `webhookController`). |

> ✅ **Hallazgo temprano positivo:** ningún `google-services.json`,
> `GoogleService-Info.plist`, `*.jks`, `*.p8`, `key.properties` ni `.env` real
> aparece en `git ls-files`.
> ⚠ **A revisar en profundidad:** los `.env` y `.env.bak.*` reales existen en el
> working tree del desarrollador (contienen secretos); confirmar rotación e
> higiene y que los `.bak` no acaben en backups/artefactos.

---

## 4. Tamaño aproximado

| Métrica | Valor |
|---------|-------|
| Archivos versionados (git) | ~420 |
| Servicios backend | 6 (5 API Node + 1 controlador IoT) |
| Líneas JS backend (sin node_modules/coverage) | ~18,118 |
| Líneas Dart (`gym_mobile_app/lib`) | ~23,377 |
| Líneas TS/TSX (`admin-web/src`) | ~1,696 |
| Líneas Python (hardware) | ~1,077 |
| Archivos SQL (esquemas + migraciones) | 14 |
| Dockerfiles | 5 |
| Workflows CI/CD | 4 |
| Configs Railway | 5 |

---

## 5. Orden de auditoría sugerido (por riesgo/impacto)

Priorización: primero lo internet-expuesto que maneja identidad, dinero y PII;
luego el código compartido (radio de impacto amplio); después cliente e IoT.

1. **auth-service** — identidad: JWT (alg, claims), refresh tokens y detección de
   reuso, WebAuthn, bcrypt, blacklist. Máximo impacto (compromiso total de cuentas).
2. **payment-service** — fintech: firma de webhooks Stripe, idempotencia, ledger
   `historial_pagos`, canje de cupones, IDOR en `/admin`, PII en recibos PDF.
3. **packages_shared/security** — CORS, Helmet, `jwtVerify`, rate limiter,
   `inputSanitizer`, `ssrfGuard`. Un defecto aquí afecta a los 5 servicios.
4. **Supabase / Base de datos** — modelo RLS deny-all, uso correcto de
   `service_role`, funciones `SECURITY DEFINER`, migraciones; pentest BOLA/IDOR
   (ya hay `docs/security/rls_bola_pentest.mjs`).
5. **access-service** — control de acceso físico: QR nonces (replay), sincronización
   biométrica, autorización entre servicios (API Key/M2M).
6. **fitness-service** y **ai-service** — autorización de datos; en IA:
   inyección de prompts, aislamiento de datos personales en caché semántico, SSRF.
7. **admin-web** — XSS, manejo del token en memoria, gating RBAC real (no solo UI),
   exposición de endpoints, CSP.
8. **App móvil Flutter** — RASP (freerasp), `flutter_secure_storage`, certificate
   pinning, deep links/Universal Links, secretos embebidos, permisos nativos,
   Live Activity iOS.
9. **reception-hardware-controller** — edge/IoT: autenticación saliente (API Key),
   manejo de puertos serie/USB, validación de payloads, actualización.
10. **CI/CD y gestión de secretos** — workflows, inyección base64, permisos de
    token, limpieza `if: always()`, scripts `sync-secrets`/`check-secrets`.
11. **Contenedores / PaaS** — Dockerfiles (no-root, base mínima), `docker-compose`,
    configs Railway (variables, health checks, red).

### Componentes a OMITIR en las auditorías siguientes (no existen)
- **IaC declarativa** (Terraform/CloudFormation/Pulumi): no hay; la "infra como
  código" se limita a `docker-compose.yml` + `railway/*.json` (auditar como config,
  no como IaC).
- **Kubernetes/Helm:** no hay orquestación de contenedores.
- **API Gateway/BFF/GraphQL:** no existe capa de gateway; cada microservicio se
  expone directamente (revisar CORS/red por servicio en su lugar).

---

## 6. Convenciones para las auditorías parciales
- Nomenclatura: `audit-01-auth.md`, `audit-02-payment.md`, … siguiendo el orden §5.
- Cada auditoría parcial referenciará este mapa para su alcance.
- Antecedentes existentes reutilizables: `docs/security/BACKEND_SECURITY_AUDIT.md`,
  `docs/guides/*-audit.md` (auth, access, payment fintech, ai, ui/perf/theme),
  `docs/security/rls_bola_pentest.mjs`.
