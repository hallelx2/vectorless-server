# ── Build stage ────────────────────────────────────────────────────
#
# Build context: the project root (vectorless-project/)
# Usage:  docker build -f vectorless-server/Dockerfile .
#
# The .dockerignore at project root strips bin/ (112MB), data/, docs/,
# testdata/, proto/, .git/ — only Go source reaches this stage.
#
FROM golang:1.25-alpine AS build

RUN apk add --no-cache ca-certificates

WORKDIR /src

# 1) Copy go.mod/go.sum for ALL three modules first.
#    This layer is cached as long as dependencies don't change —
#    source code changes won't re-download modules.
COPY vectorless-server/go.mod vectorless-server/go.sum ./vectorless-server/
COPY vectorless-engine/go.mod vectorless-engine/go.sum ./vectorless-engine/
COPY llmgate/go.mod            llmgate/go.sum            ./llmgate/

WORKDIR /src/vectorless-server
RUN go mod download

# 2) Copy ONLY the Go source directories needed for compilation.
#    Anything the .dockerignore didn't strip (data/, bin/) won't exist
#    in the context, but we also do targeted COPYs here for clarity.
WORKDIR /src
COPY vectorless-server/cmd/      ./vectorless-server/cmd/
COPY vectorless-server/internal/ ./vectorless-server/internal/
COPY vectorless-server/gen/      ./vectorless-server/gen/
COPY vectorless-engine/cmd/      ./vectorless-engine/cmd/
COPY vectorless-engine/pkg/      ./vectorless-engine/pkg/
COPY vectorless-engine/internal/ ./vectorless-engine/internal/
COPY llmgate/                    ./llmgate/

# 3) Build a fully-static binary. Flags:
#    -s -w    strip debug info + DWARF symbols (~30% smaller binary)
#    CGO=0    no C dependencies → runs on distroless/scratch
ARG VERSION=dev
WORKDIR /src/vectorless-server
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
      -trimpath \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o /bin/vectorless-server \
      ./cmd/server

# ── Runtime stage ──────────────────────────────────────────────────
#
# distroless/static:nonroot = ~2MB base. No shell, no package manager.
# Final image ≈ binary size + 2MB.
#
FROM gcr.io/distroless/static:nonroot

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /bin/vectorless-server /vectorless-server

USER nonroot:nonroot
ENTRYPOINT ["/vectorless-server"]
CMD ["--role", "server"]

EXPOSE 8080

LABEL org.opencontainers.image.title="vectorless-server"
LABEL org.opencontainers.image.description="Vectorless transport server — structure-preserving document retrieval (HTTP + gRPC)"
LABEL org.opencontainers.image.source="https://github.com/hallelx2/vectorless-server"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.vendor="Vectorless"
