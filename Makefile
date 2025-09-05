PHONY: setup-logs rm-certs down

setup-logs:
	docker compose --profile setup up tls
	docker compose --profile setup up setup
	docker compose up -d

rm-certs:
	rm -r tls/certs/*

down:
	docker compose down -v
	rm -r tls/certs/*
