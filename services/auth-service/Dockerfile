# =============================================================================
# GymPro · auth-service · Dockerfile (Monorepo Root Context)
# =============================================================================
FROM node:22-alpine AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY services/auth-service/package*.json ./services/auth-service/
WORKDIR /app/services/auth-service
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/services/auth-service/node_modules ./services/auth-service/node_modules
COPY services/auth-service ./services/auth-service

FROM node:22-alpine AS production
LABEL org.opencontainers.image.title="GymPro Auth Service"
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init
ENV NODE_ENV=production
ENV PORT=3001
WORKDIR /app

# Archivos compartidos (logger, constants, etc)
COPY packages_shared ./packages_shared

# Dependencias y código del microservicio
COPY --from=deps /app/services/auth-service/node_modules /app/node_modules
COPY --from=builder /app/services/auth-service/src ./services/auth-service/src
COPY --from=builder /app/services/auth-service/package.json ./services/auth-service/package.json

USER node
EXPOSE 3001
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
WORKDIR /app/services/auth-service
CMD ["node", "src/main.js"]
