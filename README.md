<div align="center">

# GymPro

**Ecosistema de gimnasio inteligente** — acceso biométrico por QR, rutinas y nutrición generadas por IA sobre bases científicas, y seguimiento de progreso en tiempo real.

[![Flutter](https://img.shields.io/badge/Flutter-3.13-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.3+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Node.js](https://img.shields.io/badge/Node.js-22-339933?logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![Supabase](https://img.shields.io/badge/Supabase-Postgres-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Railway](https://img.shields.io/badge/Deploy-Railway-0B0D0E?logo=railway&logoColor=white)](https://railway.app)
[![Riverpod](https://img.shields.io/badge/State-Riverpod-4B5563)](https://riverpod.dev)
[![Arquitectura](https://img.shields.io/badge/Arquitectura-Clean%20%2B%20Microservicios-6E56CF)](#arquitectura)

</div>

---

## Tabla de contenido

- [Sobre el proyecto](#sobre-el-proyecto)
- [Características](#características)
- [Arquitectura](#arquitectura)
- [Stack tecnológico](#stack-tecnológico)
- [Estructura del monorepo](#estructura-del-monorepo)
- [Puesta en marcha](#puesta-en-marcha)
- [Variables de entorno](#variables-de-entorno)
- [Scripts de datos (seeds)](#scripts-de-datos-seeds)
- [Seguridad](#seguridad)
- [Rendimiento](#rendimiento)
- [Roadmap](#roadmap)
- [Créditos y fuentes de datos](#créditos-y-fuentes-de-datos)
- [Licencia](#licencia)

---

## Sobre el proyecto

**GymPro** es una plataforma integral para gimnasios que conecta el mundo físico (torniquetes, lectores QR, impresoras) con una app móvil premium y un backend de microservicios. El socio entra al gimnasio con un **código QR dinámico cifrado**, recibe **rutinas y dietas personalizadas por IA** calibradas a sus datos reales, y sigue su **progreso** (peso, actividad, PRs) con reajuste automático para evitar estancamientos.

El proyecto está diseñado con foco en tres ejes: **rigor científico** (fórmulas de progresión y nutrición reales, no números al azar), **experiencia premium** (estética sobria, animaciones fluidas a 60/120 FPS, glassmorphism) y **eficiencia** (caché agresiva, tokens de IA optimizados, catálogos locales).

---

## Características

### Acceso y seguridad
- **Código QR dinámico** cifrado (rotación cada 30 s, sincronizable con reloj inteligente) para torniquetes.
- **Passkeys / WebAuthn** — inicio de sesión con Face ID o huella, sin contraseña.
- **Control de membresía en tiempo real** vía canales Realtime de Supabase (desbloqueo instantáneo tras el pago).

### Entrenamiento
- **Generador de rutinas con IA** por objetivo, nivel, días/semana y lesiones.
- **Mapa muscular anatómico** interactivo (CustomPainter, front/back) con resaltado por ejercicio.
- **Entrenamiento guiado** que pre-carga los pesos desde tu historial, detecta **PRs** (1RM estimado por Epley), cuenta el descanso con la Isla Dinámica y mantiene la pantalla despierta.
- **Motor de progresión** científico: progresión lineal, Greyskull LP, doble progresión, ejercicios cronometrados y de peso corporal, con **deloads** automáticos.
- **Biblioteca de ejercicios** con animaciones de la ejecución.

### Nutrición
- **Plan nutricional con IA** (macros por Atwater) ajustado a peso, estatura, edad y objetivo.
- **Recetas** paso a paso por comida, no solo ingredientes.
- **Selector de ingredientes** con buscador (catálogo local + Open Food Facts) para armar el plan con lo que tienes.
- **Registro de antojos/extras** fuera del plan que suman al consumo del día.
- **Diario diario** de calorías, macros e hidratación.

### Seguimiento y calibración
- **Peso corporal** con línea de meta y gráfica de tendencia.
- **Heatmap de actividad** estilo GitHub (últimos 12 meses).
- **Fuente de verdad única de peso**: al registrarlo se actualiza el perfil, y si tu peso se desvía del plan actual se te ofrece **reajustar dieta y rutina** para evitar descompensaciones.

### Pagos y notificaciones
- **Stripe** — portal de pagos, checkout, webhooks idempotentes, facturas PDF.
- **Notificaciones enriquecidas** (imágenes y botones de acción en segundo plano) y **Live Activities** en iOS.

---

## Arquitectura

Monorepo con una app Flutter multiplataforma y microservicios Node.js desacoplados, cada uno dueño de su esquema lógico aislado en Supabase (PostgreSQL) con políticas RLS.

```
                        ┌─────────────────────────────┐
                        │      App Flutter (móvil)     │
                        │  Clean Arch · Riverpod · UI   │
                        └───────────────┬───────────────┘
                                        │ HTTPS (JWT)
        ┌───────────────┬───────────────┼───────────────┬────────────────┐
        ▼               ▼               ▼               ▼                ▼
  ┌───────────┐  ┌───────────┐  ┌────────────┐  ┌────────────┐  ┌─────────────┐
  │   auth    │  │  access   │  │  payment   │  │  fitness   │  │     ai      │
  │  service  │  │  service  │  │  service   │  │  service   │  │  service    │
  │ passkeys  │  │ QR/torniq.│  │  Stripe    │  │ rutinas/   │  │ Gemini      │
  │  JWT      │  │  cifrado  │  │  webhooks  │  │ dieta/dato │  │ (structured)│
  └─────┬─────┘  └─────┬─────┘  └─────┬──────┘  └─────┬──────┘  └──────┬──────┘
        │              │              │               │  ▲             │
        └──────────────┴──────────────┴───────────────┘  │  M2M (x-inter-service-secret)
                                        │                 └──────────────┘
                             ┌──────────▼───────────┐
                             │  Supabase (Postgres) │  esquemas por servicio + RLS
                             │  + Storage + Realtime │
                             └──────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  reception-hardware-controller (Node/Python)  │  torniquetes · lectores QR · impresoras
        └──────────────────────────────────────────────┘
```

**Principios de diseño**
- Cada microservicio se conecta a Postgres con un rol de **mínimo privilegio** (`svc_*`) y RLS activa.
- Comunicación **máquina-a-máquina** entre servicios mediante secreto compartido (`x-inter-service-secret`).
- La IA **enriquece, no inventa**: los identificadores, imágenes y macros salen de catálogos verificados; el modelo solo aporta la parte creativa/normalizada.

---

## Stack tecnológico

| Capa | Tecnologías |
|---|---|
| **App móvil** | Flutter, Dart, Riverpod, Clean Architecture (feature-first), fl_chart, CustomPainter, cached_network_image |
| **Backend** | Node.js 22, Express, arquitectura de microservicios |
| **Base de datos** | Supabase (PostgreSQL), esquemas lógicos aislados, RLS, Storage, Realtime |
| **IA** | Google Gemini (structured output), pipelines de reconciliación de macros y músculos |
| **Pagos** | Stripe (checkout, billing portal, webhooks) |
| **Infra** | Railway (servicios), Redis (caché de planes + rate limiting), BullMQ (cola de correos), Resend |
| **Seguridad** | JWT, Passkeys/WebAuthn, Helmet, CORS controlado, validación estricta de payloads (Zod/Joi), sanitización anti-inyección |
| **Hardware** | Controlador local (Node/Python) para torniquetes, lectores QR e impresoras |

---

## Estructura del monorepo

```
GymPro/
├── apps/
│   └── gym_mobile_app/            # App Flutter (Clean Architecture, feature-first)
│       └── lib/
│           ├── core/              # tema, navegación, red, almacenamiento, widgets base
│           └── features/          # auth · qr_access · workout · nutrition · payment · subscription · home
├── services/
│   ├── auth-service/              # autenticación, passkeys, JWT
│   ├── access-service/            # generación de QR dinámico cifrado, control de accesos
│   ├── payment-service/           # Stripe: checkout, webhooks, facturación
│   ├── fitness-service/           # rutinas, dieta, progreso, catálogos (ejercicios/alimentos)
│   ├── ai-service/                # generación IA de rutinas y dietas (Gemini) + seeds
│   └── reception-hardware-controller/  # integración física (torniquetes, QR, impresoras)
├── packages_shared/               # utilidades compartidas (seguridad, logger, ...)
└── docs/
    ├── database/schemas/          # DDL canónico y migraciones
    └── guides/                    # runbooks y guías de puesta en marcha
```

---

## Puesta en marcha

### Requisitos previos
- **Flutter** 3.13+ y **Dart** 3.3+
- **Node.js** 22+
- Un proyecto de **Supabase** (PostgreSQL) y una instancia de **Redis**
- Claves de **Gemini** y **Stripe**

### App móvil

```bash
cd apps/gym_mobile_app
flutter pub get
flutter run --dart-define=USE_REMOTE_BACKEND=true --dart-define-from-file=env.json
```

### Microservicios

Cada servicio es autónomo:

```bash
cd services/<servicio>
npm install
npm run dev          # desarrollo
npm start            # producción
```

En producción, cada servicio se despliega de forma independiente en Railway con sus propias variables de entorno.

---

## Variables de entorno

Valores principales por servicio (consulta el `.env.example` de cada uno para la lista completa):

| Variable | Servicio(s) | Descripción |
|---|---|---|
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | todos | Proyecto Supabase |
| `FITNESS_DATABASE_URL` | fitness | Cadena de conexión Postgres (rol `svc_fitness`) |
| `FITNESS_SERVICE_INTERNAL_URL` | ai | URL interna del fitness-service (M2M) |
| `INTER_SERVICE_SECRET` | ai, fitness | Secreto compartido M2M (`x-inter-service-secret`) |
| `GEMINI_API_KEY` / `GEMINI_MODEL` | ai | Modelo de IA |
| `REDIS_URL` | varios | Caché de planes y rate limiting |
| `STRIPE_SECRET_KEY` / webhooks | payment | Pagos |
| `RESEND_API_KEY` | fitness/ai | Correos transaccionales |

> El controlador de la app apunta a los servicios vía `AppConfig` (URLs de Railway).

---

## Scripts de datos (seeds)

Precargan los catálogos una sola vez; el resultado queda en Supabase.

| Script | Servicio | Función |
|---|---|---|
| `seed-free-exercise-db.js` | ai-service | Cataloga ejercicios desde **free-exercise-db** (dominio público) + traducción con Gemini |
| `rehost-free-exercise-db.js` | ai-service | Genera GIFs de ejecución (2 frames) y los sube a Supabase Storage |
| `enrich-exercise-media.js` | ai-service | Empareja y puebla `gif_url` de los ejercicios por nombre |
| `seed-open-food-facts.js` | fitness-service | Siembra `catalogo_alimentos` con alimentos base en español (macros por 100 g) |

```bash
# Ejemplo: sembrar el catálogo de alimentos
FITNESS_DATABASE_URL="postgres://..." \
node services/fitness-service/scripts/seed-open-food-facts.js --dry-run
```

Consulta `docs/guides/` para los runbooks detallados.

---

## Seguridad

- **RLS activa** en las tablas de Supabase; cada microservicio usa un rol de **mínimo privilegio**.
- **Passkeys / WebAuthn** para autenticación sin contraseña.
- **Validación estricta de payloads** (Zod/Joi/express-validator) en cada endpoint para evitar crashes y datos malformados.
- **Sanitización anti-inyección** de todo texto libre del usuario (tratado como datos, nunca como instrucciones para el modelo).
- **Helmet, CORS controlado** y rate limiting por IP/usuario.
- **QR cifrado** con rotación de 30 s y verificación de expiración en el torniquete.
- **Comunicación M2M** entre servicios con secreto compartido.

---

## Rendimiento

- **60/120 FPS**: componentes gráficos pesados y animados aislados con `RepaintBoundary`; conversiones masivas de JSON en `Isolates` (`compute`).
- **Caché de planes IA** en Redis (por hash de perfil) para latencia baja y ahorro de tokens.
- **Optimización de tokens**: el modelo emite solo lo esencial (p. ej. alimentos como `nombre + gramos`); los macros se reconcilian desde los catálogos locales/Open Food Facts en **paralelo**.
- **Catálogos locales** (ejercicios y alimentos) para búsquedas instantáneas y offline-first, con Open Food Facts en vivo como cola larga.

---

## Roadmap

- [ ] Banner de reajuste por peso también en el plan de entrenamiento (paridad total).
- [ ] Cobertura de macros con `verify` → Open Food Facts para el 100 % de alimentos.
- [ ] Notificaciones programadas de pesaje semanal.
- [ ] Panel web de administración del gimnasio.
- [ ] Exportación de progreso (PDF/CSV).

---

## Créditos y fuentes de datos

- **[free-exercise-db](https://github.com/yuhonas/free-exercise-db)** — dataset de ejercicios de dominio público (Unlicense).
- **[Open Food Facts](https://world.openfoodfacts.org)** — base de datos abierta de alimentos.
- **[wger](https://wger.de)** — referencia inicial del catálogo de ejercicios.
- Fórmulas de progresión y 1RM basadas en literatura de fuerza (Epley, Greyskull LP, doble progresión).

---

## Licencia

Software propietario. Todos los derechos reservados © GymPro. Para uso, licenciamiento o colaboración, contacta al equipo del proyecto.

<div align="center">
<sub>Hecho con rigor y obsesión.</sub>
</div>
