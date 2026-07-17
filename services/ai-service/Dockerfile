# =============================================================================
# GymPro · ai-service · Dockerfile (Monorepo Root Context)
# =============================================================================
FROM node:22-alpine AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY services/ai-service/package*.json ./services/ai-service/
WORKDIR /app/services/ai-service
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/services/ai-service/node_modules ./services/ai-service/node_modules
COPY services/ai-service ./services/ai-service

FROM node:22-alpine AS production
LABEL org.opencontainers.image.title="GymPro AI Service"
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init
ENV NODE_ENV=production
ENV PORT=3005
WORKDIR /app

# Archivos compartidos (logger, constants, etc)
COPY packages_shared ./packages_shared

# Dependencias y código del microservicio
COPY --from=deps /app/services/ai-service/node_modules /app/node_modules
COPY --from=builder /app/services/ai-service/src ./services/ai-service/src
COPY --from=builder /app/services/ai-service/package.json ./services/ai-service/package.json

USER node
EXPOSE 3005
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3005/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
WORKDIR /app/services/ai-service
CMD ["node", "src/main.js"]
