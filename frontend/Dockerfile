# Imagen del frontend Next.js de la plataforma de escenarios individuales
# (ver /home/santiago/.claude/plans/atomic-roaming-wadler.md). Base
# Debian (no alpine) para evitar problemas de compatibilidad glibc/musl
# con better-sqlite3 (addon nativo). Node 22 -- better-sqlite3 declara
# "engines": {"node": ">=22"}; con Node 20 el binario nativo compila
# igual (sin error) pero crashea (SIGSEGV) al usarse en runtime/build.
#
# Build desde la RAIZ del repo (no desde frontend/), para poder copiar
# balance_hidrico.sqlite:
#   docker build -f frontend/Dockerfile -t balancehidrico-frontend .

FROM node:22-bookworm-slim AS deps
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY frontend/ ./
# balance_hidrico.sqlite se necesita EN EL BUILD: getLocalidades()/
# getCultivos() corren en build-time porque "/" se prerenderiza como
# pagina estatica (ver npm run build).
COPY balance_hidrico.sqlite /balance_hidrico.sqlite
ENV BALANCE_HIDRICO_SQLITE=/balance_hidrico.sqlite
RUN npm run build

FROM node:22-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY balance_hidrico.sqlite /balance_hidrico.sqlite

ENV BALANCE_HIDRICO_SQLITE=/balance_hidrico.sqlite
ENV PORT=3000
EXPOSE 3000

CMD ["node", "server.js"]
