# =============================================================================
# GymPro · auth-service · Dockerfile
# =============================================================================
# Build:   docker build -t gympro/auth-service .
# Run:     docker run --env-file .env -p 3001:3001 gympro/auth-service
#
# SEGURIDAD:
#   - Multi-stage build: el compilador/devDependencies NO llegan a producción
#   - Corre como usuario 'node' (UID 1001) — nunca como root (OWASP A5)
#   - Sin shell de root disponible en la imagen final
#   - Imagen base distroless-inspired: node:alpine (mínima superficie de ataque)
# =============================================================================


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1 — deps
# Instala SOLO las dependencias de producción en una capa separada.
# Esto permite que Docker reutilice esta capa si package.json no cambia.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-alpine AS deps

# dumb-init: PID 1 correcto, manejo de señales SIGTERM/SIGINT (graceful shutdown)
RUN apk add --no-cache dumb-init

WORKDIR /app

# Copiar manifiestos PRIMERO para aprovechar el cache de capas de Docker.
# Si solo cambia el código fuente (no package.json), esta capa se reutiliza.
COPY package.json package-lock.json ./

# --omit=dev: excluye devDependencies (jest, eslint, nodemon, etc.)
# --frozen-lockfile: falla si package-lock.json no está sincronizado
# --prefer-offline: usa cache local si existe (más rápido en CI)
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2 — builder (solo si hay paso de transpilación/build)
# Para Express puro en JS, este stage puede omitirse.
# Mantenerlo aquí como plantilla para cuando se agregue TypeScript.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Si el proyecto usa TypeScript, descomentar:
# RUN npm run build

# Ejecutar linting antes de construir (falla el build si hay errores)
# RUN npm run lint


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 3 — production (imagen final)
# Solo contiene: runtime node, dumb-init, node_modules de producción y src/.
# NO contiene: npm, devDependencies, archivos de test, .env, .git
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-alpine AS production

# Metadatos OCI estándar (visibles en Railway y registros de contenedores)
LABEL org.opencontainers.image.title="GymPro Auth Service"
LABEL org.opencontainers.image.description="Microservicio de autenticación e identidad"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.authors="GymPro Engineering"

# dumb-init desde el stage deps (ya compilado para alpine)
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init

# Variable de entorno de Node.js — CRÍTICO para rendimiento y seguridad
# Activa: optimizaciones V8, deshabilita devtools en producción, error stacks limpios
ENV NODE_ENV=production

# Puerto en el que escucha este servicio (Railway lo sobreescribe con $PORT)
ENV PORT=3001

WORKDIR /app

# Copiar node_modules de producción desde el stage 'deps'
COPY --from=deps /app/node_modules ./node_modules

# Copiar código fuente (excluye lo que esté en .dockerignore)
COPY --from=builder /app/src ./src
COPY --from=builder /app/package.json ./package.json

# ── Seguridad: cambiar al usuario 'node' incluido en node:alpine ──────────────
# El usuario 'node' tiene UID 1000 en la imagen oficial de Node.
# Nunca correr aplicaciones web como root en producción (OWASP A5).
USER node

# Puerto expuesto (documentación; Railway lo lee para routing automático)
EXPOSE 3001

# Health check: Railway y orquestadores lo usan para detectar pods no saludables
# --interval: cada 30s | --timeout: falla si no responde en 5s | --retries: 3 fallos = unhealthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# dumb-init como PID 1 garantiza:
#   1. Recolección correcta de procesos zombie
#   2. Propagación de señales SIGTERM → graceful shutdown de Express
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/main.js"]
