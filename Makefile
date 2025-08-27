PHONY: setup-logs start-test uv-venv rm-certs down

setup-logs:
	docker compose up tls
	docker compose up setup
	docker compose up -d

start-test:
	python consumer_service.py

uv-venv:
	uv venv
	uv sync

rm-certs:
	rm -r tls/certs/*

down:
	docker compose down -v
	rm -r tls/certs/*
