# ══════════════════════════════════════════════════════════════════════════════
# MICAFP-UnifiedShield Enterprise v9.0.0-enterprise — Dashboard Dockerfile
# §5.6 — Multi-stage build: Next.js builder → slim runner
# ══════════════════════════════════════════════════════════════════════════════

FROM node:22-slim AS builder
WORKDIR /app
COPY dashboard/ /app/dashboard/
COPY package.json /app/
WORKDIR /app/dashboard
RUN npm ci
RUN npx prisma generate
RUN npm run build

FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
COPY --from=builder /app/dashboard/.next /app/.next
COPY --from=builder /app/dashboard/public /app/public
COPY --from=builder /app/dashboard/package.json /app/package.json
COPY --from=builder /app/dashboard/node_modules /app/node_modules
EXPOSE 3000
CMD ["npm", "start"]
