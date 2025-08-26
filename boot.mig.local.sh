#!/usr/bin/env bash
set -euo pipefail

HOST="mig.local"
IP="127.0.0.2"
PROXY=8089
DASH=8099
ROOT="/home/paladin/projetos/mig"
API="$ROOT/api"

say(){ echo -e "$*"; }

cd "$ROOT"

say "➡️  Gerando compose.yaml (Traefik + whoami + API FrankenPHP)..."
cat > compose.yaml <<'YAML'
services:
  traefik:
    image: traefik:v3.0
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
    ports:
      - "127.0.0.2:8089:80"
      - "127.0.0.2:8099:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    networks: [proxy]

  whoami:
    image: traefik/whoami
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.mig-who.rule=Host(`mig.local`) && PathPrefix(`/who`)
      - traefik.http.routers.mig-who.entrypoints=web
      - traefik.http.routers.mig-who.service=mig-who
      - traefik.http.services.mig-who.loadbalancer.server.port=80
      # Raiz provisória em whoami (remove quando o WEB estiver pronto)
      - traefik.http.routers.mig-root.rule=Host(`mig.local`) && Path(`/`)
      - traefik.http.routers.mig-root.entrypoints=web
      - traefik.http.routers.mig-root.service=mig-who
      - traefik.http.routers.mig-root.priority=1
    restart: unless-stopped
    networks: [proxy]

  api:
    image: dunglas/frankenphp:1-php8.3
    working_dir: /app
    volumes:
      - ./api:/app
    environment:
      SERVER_NAME: ":80"
      DOCUMENT_ROOT: "/app/public"
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.mig-api.rule=Host(`mig.local`) && (PathPrefix(`/api/`) || Path(`/api`))
      - traefik.http.routers.mig-api.entrypoints=web
      - traefik.http.routers.mig-api.middlewares=mig-stripprefix
      - traefik.http.middlewares.mig-stripprefix.stripprefix.prefixes=/api
      - traefik.http.routers.mig-api.service=mig-api
      - traefik.http.services.mig-api.loadbalancer.server.port=80
    restart: unless-stopped
    networks: [proxy]

networks:
  proxy:
YAML

# API Laravel — cria se faltar
if [ ! -f "$API/composer.json" ]; then
  say "➡️  Criando esqueleto Laravel em $API (via composer contêiner)..."
  mkdir -p "$API"
  docker run --rm -u "$(id -u)":"$(id -g)" -v "$API":/app -w /app composer:2 \
    composer create-project laravel/laravel .

  # .env básico (cache/session/file) e URL
  awk '1; END{print "APP_URL=http://mig.local:8089\nCACHE_DRIVER=file\nCACHE_STORE=file\nSESSION_DRIVER=file\nQUEUE_CONNECTION=sync"}' "$API/.env" | sort -u > /tmp/.env && mv /tmp/.env "$API/.env"

  # rota /health
  grep -q 'Route::get.\?/health' "$API/routes/web.php" || \
    printf "\nRoute::get('/health', fn() => response()->json(['status'=>'ok']));\n" >> "$API/routes/web.php"
fi

# health estático (bypass Laravel)
install -d -m 755 "$API/public"
cat > "$API/public/health.php" <<'PHP'
<?php header('Content-Type: application/json'); echo json_encode(['status'=>'ok-php']);
PHP

# permissões
docker run --rm -u root -v "$API":/app -w /app alpine:3.20 \
  sh -lc "chown -R 33:33 /app/storage /app/bootstrap/cache 2>/dev/null || true; chmod -R 775 /app/storage /app/bootstrap/cache 2>/dev/null || true" || true

say "➡️  Subindo serviços..."
docker compose up -d

# limpar caches Laravel (se existir vendor/artisan)
if [ -f "$API/artisan" ]; then
  docker compose exec api php artisan route:clear >/dev/null 2>&1 || true
  docker compose exec api php artisan config:clear >/dev/null 2>&1 || true
  docker compose exec api php artisan cache:clear  >/dev/null 2>&1 || true
  docker compose exec api php artisan optimize:clear >/dev/null 2>&1 || true
fi

# Testes
test_url(){
  local url="$1" expect="${2:-200}"
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
  if [ "$code" = "$expect" ]; then
    echo "✅ $url → $code"
  else
    echo "❌ $url → $code (esperado $expect)"; exit 1
  fi
}

say "➡️  Testando roteamento (Host $HOST)..."
test_url "http://$HOST:$PROXY/" 200
test_url "http://$HOST:$PROXY/who" 200
test_url "http://$HOST:$PROXY/api/health.php" 200

# dentro da rede do traefik → Laravel
docker exec -it $(docker compose ps -q traefik) sh -lc 'apk add --no-cache curl >/dev/null 2>&1 || true; curl -s -o /dev/null -w "%{http_code}" http://api/health' | grep -q '^200$' \
  && echo "✅ [traefik→api] /health interno → 200" \
  || { echo "❌ [traefik→api] /health interno falhou"; exit 1; }

test_url "http://$HOST:$PROXY/api/health" 200

echo "🎉 MIG ok em http://$HOST:$PROXY  (dashboard: http://$IP:$DASH)"
