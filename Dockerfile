# ---- Fase 1: Contenerización segura ----

# Imagen base ligera y oficial
FROM node:20-alpine

# Directorio de trabajo dentro del contenedor
WORKDIR /usr/src/app

# Copiamos primero solo los manifiestos para aprovechar la cache de capas de Docker
COPY package*.json ./

# Instalamos SOLO dependencias de producción y limpiamos cache de npm
RUN npm ci --only=production && npm cache clean --force

# Copiamos el resto del código ya asignando la propiedad al usuario no-root
COPY --chown=node:node . .

# Hardening: nunca ejecutar como root.
# La imagen node:alpine ya trae creado el usuario/grupo "node" (uid 1000)
USER node

# Puerto en el que escucha la API (ver index.js -> process.env.PORT || 8080)
EXPOSE 8080

# Comando de arranque
CMD ["node", "index.js"]
