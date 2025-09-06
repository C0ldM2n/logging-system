PHONY: setup-logs rm-certs down

setup-logs:
	docker compose run --rm tls
	docker compose up -d elasticsearch
	docker compose run --rm setup
	docker compose up

rm-certs:
	rm -r tls/certs/*

down:
	docker compose down -v
	rm -r tls/certs/*
