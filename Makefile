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
