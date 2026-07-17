# =============================================================================
# GymPro · payment-service · Dockerfile
# =============================================================================
FROM node:22-alpine AS deps
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --frozen-lockfile --prefer-offline

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

FROM node:22-alpine AS production
LABEL org.opencontainers.image.title="GymPro Payment Service"
LABEL org.opencontainers.image.description="Microservicio de pagos y suscripciones con Stripe"
LABEL org.opencontainers.image.version="1.0.0"

COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init

ENV NODE_ENV=production
ENV PORT=3003

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY --from=builder /app/package.json ./package.json

USER node
EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3003/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/main.js"]
