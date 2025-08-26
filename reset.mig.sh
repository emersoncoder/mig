#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/paladin/projetos/mig"
cd "$ROOT"

echo "➡️  Derrubando stack MIG..."
docker compose down --remove-orphans --volumes || true

echo "➡️  Removendo contêineres órfãos com prefixo 'mig-' (se houver)..."
ids=$(docker ps -aq --filter "name=^mig-(traefik|whoami|api|web|db|redis|mailpit)-" || true)
[ -n "${ids}" ] && docker rm -f ${ids} || true

echo "➡️  Removendo rede 'mig_proxy' (se sobrou)..."
docker network rm mig_proxy 2>/dev/null || true

echo "➡️  Checando alias 127.0.0.2..."
ip addr show lo | grep -q '127.0.0.2' || sudo ip addr add 127.0.0.2/32 dev lo

echo "➡️  Checando /etc/hosts (mig.local → 127.0.0.2)..."
grep -qE '^\s*127\.0\.0\.2\s+mig\.local\b' /etc/hosts || {
  echo "❌ /etc/hosts sem '127.0.0.2   mig.local' — adicione e rode de novo."
  exit 1
}

echo "✅ Reset concluído."
