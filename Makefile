.PHONY: build run test lint clean generate docker

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -ldflags "-X main.version=$(VERSION)"

# ── Build ──────────────────────────────────────────────────────────
build:
	go build $(LDFLAGS) -o bin/vectorless-server ./cmd/server

run: build
	./bin/vectorless-server --config config.example.yaml

# ── Test / Lint ────────────────────────────────────────────────────
test:
	go test ./... -race -count=1

lint:
	golangci-lint run ./...

# ── Proto generation (requires buf CLI) ────────────────────────────
generate:
	buf generate

# ── Docker ─────────────────────────────────────────────────────────
docker:
	docker build -t vectorless-server:$(VERSION) .

docker-up:
	docker compose up -d

docker-down:
	docker compose down

# ── Clean ──────────────────────────────────────────────────────────
clean:
	rm -rf bin/
