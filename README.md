# MIG — Fundação v0.1

## Objetivo
Base mínima para evoluir API e Web por um único host: **mig.localhost** (loopback alternativo **127.0.0.2**), mantendo **127.0.0.1** livre.

## Requisitos
- Docker / Docker Compose
- `mig.localhost` -> `127.0.0.2` no /etc/hosts (este script faz isso pra você)

## Comandos
- `make up` — sobe proxy e rota de teste
- `make logs` — logs do Traefik
- `make ps` — status
- `make down` — derruba tudo

## Testes
- Whoami: http://mig.localhost:8089/who
- Dashboard (opcional): http://mig.localhost:8099

## Próximos passos
- Plugar API (Laravel/Franken) em `/api` com StripPrefix
- Plugar Web (Next) na raiz `/`
