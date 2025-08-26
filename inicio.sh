#!/usr/bin/env bash
set -euo pipefail

# =========================
# MIG — Fundação v0.1
# - Cria ~/projetos/mig com:
#   compose.yaml (Traefik + whoami), Makefile, README.md, .editorconfig, .gitignore
# - Mapeia mig.localhost -> 127.0.0.2 no /etc/hosts (backup automático)
# - Sobe proxy em 127.0.0.2:8089 e dashboard (opcional) em 127.0.0.2:8099
# =========================

HOST_IP="127.0.0.2"
HOST_DOMAIN="mig.localhost"
PROXY_PORT="8089"
DASHBOARD_PORT="8099"
PROJECT_DIR="${HOME}/projetos/mig"

command -v docker >/dev/null 2>&1 || { echo "❌ Docker não encontrado no PATH."; exit 1; }

echo "➡️  Criando estrutura em: ${PROJECT_DIR}"
mkdir -p "${PROJECT_DIR}"/{api,web}

# ---------- /etc/hosts ----------
echo "➡️  Garantindo host ${HOST_DOMAIN} -> ${HOST_IP}"
if ! grep -qE "^\s*${HOST_IP}\s+${HOST_DOMAIN}\b" /etc/hosts; then
  sudo cp /etc/hosts "/etc/hosts.bak.$(date +%F_%H%M%S)"
  echo "${HOST_IP}   ${HOST_DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
  # Flush caches (quando aplicável)
  (sudo resolvectl flush-caches 2>/dev/null || sudo systemd-resolve --flush-caches 2>/dev/null || true)
else
  echo "✔️  Entrada já existe em /etc/hosts."
fi

# ---------- compose.yaml ----------
COMPOSE="${PROJECT_DIR}/compose.yaml"
if [[ ! -f "${COMPOSE}" ]]; then
  cat > "${COMPOSE}" <<'YAML'
services:
  traefik:
    image: traefik:v3.0
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --entrypoints.web.address=:80
    ports:
      - "127.0.0.2:8089:80"    # site/proxy do projeto (mig.localhost:8089)
      - "127.0.0.2:8099:8080"  # dashboard do Traefik (opcional)
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

networks:
  proxy:
YAML
  echo "✔️  compose.yaml criado."
else
  echo "ℹ️  compose.yaml já existe — mantido."
fi

# ---------- Makefile ----------
MAKEFILE="${PROJECT_DIR}/Makefile"
if [[ ! -f "${MAKEFILE}" ]]; then
  cat > "${MAKEFILE}" <<'MAKE'
SHELL := /bin/bash

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f traefik

ps:
	docker compose ps

restart:
	docker compose down && docker compose up -d
MAKE
  echo "✔️  Makefile criado."
else
  echo "ℹ️  Makefile já existe — mantido."
fi

# ---------- README.md ----------
README="${PROJECT_DIR}/README.md"
if [[ ! -f "${README}" ]]; then
  cat > "${README}" <<README
# MIG — Fundação v0.1

## Objetivo
Base mínima para evoluir API e Web por um único host: **${HOST_DOMAIN}** (loopback alternativo **${HOST_IP}**), mantendo **127.0.0.1** livre.

## Requisitos
- Docker / Docker Compose
- \`${HOST_DOMAIN}\` -> \`${HOST_IP}\` no /etc/hosts (este script faz isso pra você)

## Comandos
- \`make up\` — sobe proxy e rota de teste
- \`make logs\` — logs do Traefik
- \`make ps\` — status
- \`make down\` — derruba tudo

## Testes
- Whoami: http://${HOST_DOMAIN}:${PROXY_PORT}/who
- Dashboard (opcional): http://${HOST_DOMAIN}:${DASHBOARD_PORT}

## Próximos passos
- Plugar API (Laravel/Franken) em \`/api\` com StripPrefix
- Plugar Web (Next) na raiz \`/\`
README
  echo "✔️  README.md criado."
else
  echo "ℹ️  README.md já existe — mantido."
fi

# ---------- .editorconfig ----------
EC="${PROJECT_DIR}/.editorconfig"
if [[ ! -f "${EC}" ]]; then
  cat > "${EC}" <<'EC'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2
trim_trailing_whitespace = true
EC
  echo "✔️  .editorconfig criado."
else
  echo "ℹ️  .editorconfig já existe — mantido."
fi

# ---------- .gitignore ----------
GI="${PROJECT_DIR}/.gitignore"
if [[ ! -f "${GI}" ]]; then
  cat > "${GI}" <<'GI'
# Node / Next
node_modules/
.next/
out/

# Laravel / PHP
vendor/
storage/
.env
.env.*

# Docker
*.pid
*.log
GI
  echo "✔️  .gitignore criado."
else
  echo "ℹ️  .gitignore já existe — mantido."
fi

echo "➡️  Subindo serviços (Traefik + whoami)..."
(
  cd "${PROJECT_DIR}"
  docker compose up -d
)

echo "✅  Fundação v0.1 pronta."
echo "   • Whoami:     http://${HOST_DOMAIN}:${PROXY_PORT}/who"
echo "   • Dashboard:  http://${HOST_DOMAIN}:${DASHBOARD_PORT} (opcional)"
echo "   • Pasta:      ${PROJECT_DIR}"
