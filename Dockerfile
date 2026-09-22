# ---- Etapa 1: Build (instala dependencias) ----
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm ci --only=production

# ---- Etapa 2: Runtime (imagen final, sin npm) ----
FROM node:20-alpine

# Actualiza paquetes de Alpine (corrige libcrypto3/libssl3 - CVEs de OpenSSL)
RUN apk update && apk upgrade --no-cache

WORKDIR /usr/src/app

COPY --from=builder --chown=node:node /usr/src/app/node_modules ./node_modules
COPY --chown=node:node . .

# Elimina npm/npx/corepack: no se necesitan en runtime y ahí vivían
# las 20 vulnerabilidades que reportó Trivy (tar, minimatch, glob, etc.)
RUN rm -rf /usr/local/lib/node_modules/npm \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

USER node

EXPOSE 8080

CMD ["node", "index.js"]