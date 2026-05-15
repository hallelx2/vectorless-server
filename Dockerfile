# ── Build stage ────────────────────────────────────────────────────
FROM golang:1.25-alpine AS build

RUN apk add --no-cache git ca-certificates

WORKDIR /src

# Copy go.mod/go.sum first for better layer caching.
COPY go.mod go.sum ./
RUN go mod download

# Copy the full source tree.
COPY . .

# Build the server binary. CGO is disabled for a fully static binary
# that runs on distroless.
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags "-X main.version=${VERSION}" \
    -o /bin/vectorless-server ./cmd/server

# ── Runtime stage ──────────────────────────────────────────────────
FROM gcr.io/distroless/static:nonroot

COPY --from=build /bin/vectorless-server /vectorless-server

# Default to server role. Override with "worker" for queue-only pods.
ENTRYPOINT ["/vectorless-server"]
CMD ["--config", "/etc/vectorless/config.yaml"]

EXPOSE 8080

# Labels for container registries.
LABEL org.opencontainers.image.source="https://github.com/hallelx2/vectorless-server"
LABEL org.opencontainers.image.description="Vectorless transport server — HTTP + gRPC"
LABEL org.opencontainers.image.licenses="Apache-2.0"
