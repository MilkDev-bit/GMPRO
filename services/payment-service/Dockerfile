# =============================================================================
# GymPro · payment-service · Dockerfile (Monorepo Root Context)
# =============================================================================
FROM node:22-alpine AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY services/payment-service/package*.json ./services/payment-service/
WORKDIR /app/services/payment-service
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/services/payment-service/node_modules ./services/payment-service/node_modules
COPY services/payment-service ./services/payment-service

FROM node:22-alpine AS production
LABEL org.opencontainers.image.title="GymPro Payment Service"
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init
ENV NODE_ENV=production
ENV PORT=3003
WORKDIR /app

# Archivos compartidos (logger, constants, etc)
COPY packages_shared ./packages_shared

# Dependencias y código del microservicio
COPY --from=deps /app/services/payment-service/node_modules /app/node_modules
COPY --from=builder /app/services/payment-service/src ./services/payment-service/src
COPY --from=builder /app/services/payment-service/package.json ./services/payment-service/package.json

USER node
EXPOSE 3003
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3003/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
WORKDIR /app/services/payment-service
CMD ["node", "src/main.js"]
