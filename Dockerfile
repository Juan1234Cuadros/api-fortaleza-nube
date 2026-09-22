# ---- Etapa 1: Build (instala dependencias) ----
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm ci --only=production

# ---- Etapa 2: Runtime (imagen final, sin npm) ----
FROM node:20-alpine

WORKDIR /usr/src/app

# Copiamos solo las dependencias ya instaladas y el código, no npm
COPY --from=builder --chown=node:node /usr/src/app/node_modules ./node_modules
COPY --chown=node:node . .

# Hardening: nunca ejecutar como root
USER node

EXPOSE 8080

CMD ["node", "index.js"]