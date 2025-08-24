setup:
	docker compose up setup

start-test:
	python consumer_service.py

setup-local:
	uv venv
	uv sync
