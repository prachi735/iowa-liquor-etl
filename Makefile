.PHONY: up down setup demo status test lint

PYTHON ?= python3

up:
	docker compose up -d --wait

down:
	docker compose down

setup:
	$(PYTHON) -m pipeline setup

demo: setup
	$(PYTHON) -m pipeline load tests/fixtures/sample_orders.csv
	$(PYTHON) -m pipeline transform
	$(PYTHON) -m pipeline status

status:
	$(PYTHON) -m pipeline status

test:
	$(PYTHON) -m pytest -v

lint:
	ruff check pipeline tests
