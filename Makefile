PHONY: setup-logs rm-certs down

setup-logs:
	docker compose --profile setup run --rm -e MODE=tls setup
	docker compose up -d elasticsearch
	docker compose --profile setup run --rm -e MODE=setup setup
	docker compose up -d

rm-certs:
	rm -r tls/certs/*

down:
	docker compose down -v
	rm -r tls/certs/*
