# =============================================================================
# GymPro · fitness-service · Dockerfile (Monorepo Root Context)
# =============================================================================
FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920 AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY services/fitness-service/package*.json ./services/fitness-service/
WORKDIR /app/services/fitness-service
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920 AS builder
WORKDIR /app
COPY --from=deps /app/services/fitness-service/node_modules ./services/fitness-service/node_modules
COPY services/fitness-service ./services/fitness-service

FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920 AS production
LABEL org.opencontainers.image.title="GymPro Fitness Service"
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init
ENV NODE_ENV=production
ENV PORT=3004
WORKDIR /app

# Archivos compartidos (logger, constants, etc)
COPY packages_shared ./packages_shared

# Dependencias y código del microservicio
COPY --from=deps /app/services/fitness-service/node_modules /app/node_modules
COPY --from=builder /app/services/fitness-service/src ./services/fitness-service/src
COPY --from=builder /app/services/fitness-service/package.json ./services/fitness-service/package.json

USER node
EXPOSE 3004
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3004/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
WORKDIR /app/services/fitness-service
CMD ["node", "src/main.js"]
