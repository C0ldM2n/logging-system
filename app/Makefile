.PHONY: setup-local start
export PYTHONPATH := src

setup-local:
	echo "Creating Poetry venv in ./.venv..."; \
	poetry install; \
	echo "Setup complete!"; \
	poetry env info

start:
	python src/main.py
