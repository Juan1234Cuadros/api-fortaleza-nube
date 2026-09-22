# Guía de la actividad de recuperación

## Fase 1 — Verificación local del contenedor

```bash
# Construir la imagen
docker build -t api-fortaleza-nube .

# Confirmar que corre como usuario "node" y no root
docker run -d --name test-api -p 8080:8080 api-fortaleza-nube
docker exec test-api whoami        # debe imprimir: node

# Probar que responde
curl http://localhost:8080/
curl http://localhost:8080/datos

# Limpiar
docker rm -f test-api
```

Captura para tu entrega: salida de `docker exec test-api whoami` (=node) y la
respuesta JSON de `curl http://localhost:8080/`.

---

## Fase 2 — Pipeline DevSecOps

Archivos ya creados: `.github/workflows/deploy.yml`.

### Secrets que debes crear en GitHub
Repo → Settings → Secrets and variables → Actions → New repository secret:
- `EC2_HOST` → IP pública de tu instancia EC2
- `EC2_USER` → normalmente `ubuntu` o `ec2-user`
- `EC2_SSH_KEY` → contenido completo de tu `.pem` (clave privada)

### Cómo generar el "Pull Request fallido" que pide el punto de control
1. Crea una rama: `git checkout -b prueba-vulnerabilidad`
2. En `package.json`, baja la versión de una dependencia a una conocida como
   vulnerable, por ejemplo:
   ```json
   "express": "4.16.0"
   ```
3. Haz commit y push, abre el Pull Request contra `main`.
4. `npm audit` o Trivy deben fallar el check → captura de pantalla.
5. Corrige la versión (vuelve a `^4.17.1` o sube a una parchada), push de nuevo
   al mismo PR → el pipeline debe quedar en verde → segunda captura.
6. Haz merge del PR: se dispara el job `deploy` hacia EC2.

---

## Fase 3 — Orquestación y enrutamiento

Archivo ya creado: `docker-compose.yml` (api + Uptime Kuma + Dozzle en una red
bridge llamada `app-network`).

En la instancia EC2:

```bash
git clone <tu-repo>
cd api-fortaleza-nube
docker compose up -d
```

### Nginx Proxy Manager (NPM)
NPM normalmente se corre aparte (no dentro del mismo compose de la app) para
que sobreviva a los redeploys de la API:

```bash
mkdir npm && cd npm
cat > docker-compose.yml << 'EOF'
services:
  npm:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
docker compose up -d
```

Entra a `http://<IP-EC2>:81` (usuario/clave por defecto: `admin@example.com` /
`changeme`, te pedirá cambiarla).

### DuckDNS
1. Crea cuenta en https://www.duckdns.org
2. Genera 3 subdominios: `api-recuperacion`, `monitoreo-recuperacion`,
   `logs-recuperacion`, todos apuntando a la IP pública de tu EC2.
3. En NPM → **Proxy Hosts** → **Add Proxy Host** por cada uno:
   - `api-recuperacion.duckdns.org` → forward a `api-node:8080`
   - `monitoreo-recuperacion.duckdns.org` → forward a `uptime-kuma:3001`
   - `logs-recuperacion.duckdns.org` → forward a `dozzle:8080`
   - Como NPM corre en un compose distinto, debes conectarlo a la misma red:
     `docker network connect app-network npm-npm-1` (o el nombre real del
     contenedor de NPM).

### Certificados Let's Encrypt
En cada Proxy Host, pestaña **SSL** → **Request a new SSL Certificate** →
marca "Force SSL" y "HTTP/2 Support".

### Access Lists (restringir Dozzle y Uptime Kuma)
NPM → **Access Lists** → **Add Access List** → crea usuario/clave (Basic
Auth) o restringe por IP → asígnala en los Proxy Hosts de
`monitoreo-recuperacion` y `logs-recuperacion` (el de `api-recuperacion`
normalmente se deja público).

---

## Fase 4 — Observabilidad y simulacro de caída

### Monitor en Uptime Kuma
1. Entra a `https://monitoreo-recuperacion.duckdns.org`
2. **Add New Monitor**:
   - Monitor Type: `HTTP(s)`
   - URL: `http://api-node:8080/` (nombre del servicio dentro de la red
     Docker, no localhost)
   - Heartbeat Interval: `60` segundos

### Alertas a Telegram
1. Habla con `@BotFather` en Telegram, crea un bot, guarda el token.
2. Obtén tu `chat_id` (puedes usar `@userinfobot` o el endpoint
   `getUpdates` del bot).
3. En Uptime Kuma → **Settings** → **Notifications** → **Setup
   Notification** → tipo `Telegram` → pega Bot Token y Chat ID → pruébalo.
4. Asigna esa notificación al monitor de la API.

### Simulacro de caída
1. Desde el navegador visita:
   `https://api-recuperacion.duckdns.org/api/crash`
2. El contenedor `api-node` muere (`process.exit(1)`).
3. Uptime Kuma detecta el "down" en el siguiente heartbeat y dispara la
   alerta a Telegram → captura del mensaje recibido.
4. Entra a `https://logs-recuperacion.duckdns.org` (Dozzle), abre el log del
   contenedor `api-node` y busca la línea:
   `[FATAL ERROR] Fallo de segmento. El sistema se ha quedado sin memoria.`
   → captura mostrando esa traza justo antes de que el contenedor se
   reinicie (gracias a `restart: unless-stopped` en el compose).
