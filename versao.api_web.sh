#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# MIG — Versão API+WEB v0.2 (/home/paladin/projetos/mig)
# - API (Laravel + FrankenPHP) em /api (StripPrefix via Traefik)
# - WEB (Next.js/React) na raiz /
# - mig.localhost -> 127.0.0.2 (127.0.0.1 fica livre)
# Reqs: /etc/hosts com "127.0.0.2   mig.localhost"
# ============================================================

HOST_IP="127.0.0.2"
HOST_DOMAIN="mig.localhost"
PROXY_PORT="8089"
DASHBOARD_PORT="8099"

ROOT_DIR="/home/paladin/projetos/mig"
API_DIR="${ROOT_DIR}/api"
WEB_DIR="${ROOT_DIR}/web"
COMPOSE_FILE="${ROOT_DIR}/compose.yaml"

say() { echo -e "$1"; }

say "➡️  Checando pré-requisitos..."
command -v docker >/dev/null 2>&1 || { say "❌ Docker não encontrado."; exit 1; }
grep -qE "^\s*${HOST_IP}\s+${HOST_DOMAIN}\b" /etc/hosts || { say "❌ ${HOST_DOMAIN} não aponta para ${HOST_IP}"; exit 1; }

mkdir -p "${API_DIR}" "${WEB_DIR}"

# 1) Compose (backup + novo)
say "➡️  Atualizando docker compose (backup + novo compose.yaml)..."
[[ -f "${COMPOSE_FILE}" ]] && cp "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%F_%H%M%S)"

cat > "${COMPOSE_FILE}" <<'YAML'
services:
  traefik:
    image: traefik:v3.0
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --entrypoints.web.address=:80
    ports:
      - "127.0.0.2:8089:80"
      - "127.0.0.2:8099:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [proxy]

  whoami:
    image: traefik/whoami
    labels:
      - traefik.enable=true
      - traefik.http.routers.mig-who.rule=Host(`mig.localhost`) && PathPrefix(`/who`)
      - traefik.http.routers.mig-who.entrypoints=web
      - traefik.http.services.mig-who.loadbalancer.server.port=80
    networks: [proxy]

  db:
    image: mariadb:11.4
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: erp
      MYSQL_USER: erp
      MYSQL_PASSWORD: secret
    volumes: [ "dbdata:/var/lib/mysql" ]
    networks: [internal]

  redis:
    image: redis:7
    networks: [internal]

  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "127.0.0.2:8025:8025"
      - "127.0.0.2:1025:1025"
    networks: [internal]

  api:
    image: dunglas/frankenphp:1-php8.3
    working_dir: /app
    volumes:
      - ./api:/app
    environment:
      APP_ENV: local
      FRANKENPHP_CONFIG: |
        frankenphp {
          worker /public/index.php {
            max_concurrency 32
          }
        }
    labels:
      - traefik.enable=true
      - traefik.http.routers.mig-api.rule=Host(`mig.localhost`) && PathPrefix(`/api`)
      - traefik.http.routers.mig-api.entrypoints=web
      - traefik.http.routers.mig-api.middlewares=mig-stripprefix
      - traefik.http.middlewares.mig-stripprefix.stripprefix.prefixes=/api
      - traefik.http.services.mig-api.loadbalancer.server.port=80
    depends_on: [db, redis]
    networks: [proxy, internal]

  web:
    image: node:20
    working_dir: /app
    volumes:
      - ./web:/app
    environment:
      - PORT=3000
      - HOSTNAME=0.0.0.0
      - NEXT_TELEMETRY_DISABLED=1
    command: sh -c "npm i && npm run dev -- -H 0.0.0.0 -p 3000"
    labels:
      - traefik.enable=true
      - traefik.http.routers.mig-web.rule=Host(`mig.localhost`)
      - traefik.http.routers.mig-web.entrypoints=web
      - traefik.http.services.mig-web.loadbalancer.server.port=3000
    depends_on: [api]
    networks: [proxy, internal]

volumes:
  dbdata:

networks:
  proxy:
  internal:
YAML

say "✔️  compose.yaml pronto em ${COMPOSE_FILE}"

# 2) API (Laravel): cria se não existir
if [[ ! -f "${API_DIR}/composer.json" ]]; then
  say "➡️  Criando API Laravel em ${API_DIR}..."
  docker run --rm -u "$(id -u)":"$(id -g)" -v "${API_DIR}":/app -w /app composer:2 \
    composer create-project laravel/laravel .

  cat > "${API_DIR}/.env" <<EOF
APP_NAME=ERP
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://${HOST_DOMAIN}:${PROXY_PORT}

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=erp
DB_USERNAME=erp
DB_PASSWORD=secret

REDIS_HOST=redis

MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_FROM_ADDRESS="dev@example.test"
MAIL_FROM_NAME="ERP Dev"
EOF

  say "➡️  Gerando APP_KEY..."
  (cd "${ROOT_DIR}" && docker compose run --rm api php artisan key:generate)

  grep -q '/health' "${API_DIR}/routes/web.php" || \
    echo 'Route::get("/health", fn() => response()->json(["status"=>"ok"]));' >> "${API_DIR}/routes/web.php"
  say "✔️  API criada e configurada."
else
  say "ℹ️  API já existe — mantendo."
fi

# 3) WEB (Next.js): cria se não existir; se existir, cria page.tsx se faltar
if [[ ! -f "${WEB_DIR}/package.json" ]]; then
  say "➡️  Criando WEB Next.js em ${WEB_DIR}..."
  docker run --rm -u "$(id -u)":"$(id -g)" -it -v "${WEB_DIR}":/app -w /app node:20 \
    npx create-next-app@latest . --ts --eslint --app --tailwind --src-dir --no-gh --import-alias "@/*"

  # Garantir posse/gravação
  if [[ ! -w "${WEB_DIR}/src/app" ]]; then
    say "➡️  Ajustando permissões em ${WEB_DIR} (pode pedir sudo)..."
    sudo chown -R "$(id -un)":"$(id -gn)" "${WEB_DIR}" || true
  fi

  install -d -m 755 "${WEB_DIR}/src/app"
  cat > "${WEB_DIR}/src/app/page.tsx" <<'TSX'
'use client';
import { useEffect, useState } from 'react';

export default function Home() {
  const [status, setStatus] = useState<string>('...');

  useEffect(() => {
    fetch('/api/health', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => setStatus(d?.status ?? 'fail'))
      .catch(() => setStatus('fail'));
  }, []);

  return (
    <main className="p-6">
      <h1 className="text-2xl font-bold">ERP Moderno — mig</h1>
      <p className="mt-2">API health: <b>{status}</b></p>
    </main>
  );
}
TSX
  say "✔️  WEB criada e configurada."
else
  say "ℹ️  WEB já existe — mantendo."
  if [[ ! -f "${WEB_DIR}/src/app/page.tsx" ]]; then
    install -d -m 755 "${WEB_DIR}/src/app"
    [[ -w "${WEB_DIR}/src/app" ]] || sudo chown -R "$(id -un)":"$(id -gn)" "${WEB_DIR}" || true
    cat > "${WEB_DIR}/src/app/page.tsx" <<'TSX'
'use client';
import { useEffect, useState } from 'react';

export default function Home() {
  const [status, setStatus] = useState<string>('...');

  useEffect(() => {
    fetch('/api/health', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => setStatus(d?.status ?? 'fail'))
      .catch(() => setStatus('fail'));
  }, []);

  return (
    <main className="p-6">
      <h1 className="text-2xl font-bold">ERP Moderno — mig</h1>
      <p className="mt-2">API health: <b>{status}</b></p>
    </main>
  );
}
TSX
    say "✔️  page.tsx criado em projeto existente."
  fi
fi

# 4) Subir e testar
say "➡️  Subindo serviços..."
(cd "${ROOT_DIR}" && docker compose up -d)

say "➡️  Testando saúde da API via Traefik..."
API_HEALTH="$(curl -fsS "http://${HOST_DOMAIN}:${PROXY_PORT}/api/health" || true)"
if [[ -n "${API_HEALTH}" ]]; then
  say "✔️  /api/health OK → ${API_HEALTH}"
else
  say "⚠️  Falha ao consultar /api/health. Veja logs: 'cd ${ROOT_DIR} && docker compose logs -f api traefik'"
fi

echo
say "✅  Versão API+WEB v0.2 pronta."
say "   • WEB:      http://${HOST_DOMAIN}:${PROXY_PORT}"
say "   • API:      http://${HOST_DOMAIN}:${PROXY_PORT}/api/health"
say "   • Whoami:   http://${HOST_DOMAIN}:${PROXY_PORT}/who"
say "   • Dashboard (opcional): http://${HOST_IP}:${DASHBOARD_PORT}"
echo
say "Dicas:"
say " - Logs:   (cd ${ROOT_DIR} && docker compose logs -f traefik api web)"
say " - Status: (cd ${ROOT_DIR} && docker compose ps)"
say " - Parar:  (cd ${ROOT_DIR} && docker compose down)"
