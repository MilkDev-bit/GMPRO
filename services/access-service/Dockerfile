# =============================================================================
# GymPro · access-service · Dockerfile (Monorepo Root Context)
# =============================================================================
FROM node:22-alpine AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY services/access-service/package*.json ./services/access-service/
WORKDIR /app/services/access-service
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/services/access-service/node_modules ./services/access-service/node_modules
COPY services/access-service ./services/access-service

FROM node:22-alpine AS production
LABEL org.opencontainers.image.title="GymPro Access Service"
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init
ENV NODE_ENV=production
ENV PORT=3002
WORKDIR /app

# Archivos compartidos (logger, constants, etc)
COPY packages_shared ./packages_shared

# Dependencias y código del microservicio
COPY --from=deps /app/services/access-service/node_modules /app/node_modules
COPY --from=builder /app/services/access-service/src ./services/access-service/src
COPY --from=builder /app/services/access-service/package.json ./services/access-service/package.json

USER node
EXPOSE 3002
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3002/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
WORKDIR /app/services/access-service
CMD ["node", "src/main.js"]
