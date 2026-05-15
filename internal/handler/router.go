package handler

import (
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/hallelx2/vectorless-engine/pkg/db"
	"github.com/hallelx2/vectorless-engine/pkg/queue"
	"github.com/hallelx2/vectorless-engine/pkg/retrieval"
	"github.com/hallelx2/vectorless-engine/pkg/storage"

	"github.com/hallelx2/vectorless-server/internal/config"
	"github.com/hallelx2/vectorless-server/internal/middleware"
)

// Deps bundles the server's runtime dependencies for injection.
type Deps struct {
	Logger   *slog.Logger
	DB       *db.Pool
	Storage  storage.Storage
	Queue    queue.Queue
	Strategy retrieval.Strategy
	Version  string
	Config   config.Config
}

// Router builds the chi router with all v1 routes and the full
// middleware stack described in SERVER.md:
//
//  1. RequestID — generate or propagate X-Request-ID
//  2. RealIP — honour X-Forwarded-For behind a trusted proxy
//  3. Recovery — convert panics into 500s with a logged stack trace
//  4. AccessLog — structured access log (method, path, status, duration)
//  5. Metrics — Prometheus histograms + counters
//  6. Auth — skipped for /v1/health, /v1/version, /metrics
//  7. RateLimit — optional, token bucket per principal
//  8. The handler itself
func Router(d Deps) http.Handler {
	r := chi.NewRouter()

	// ── Middleware stack (order matters) ───────────────────────────
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recovery(d.Logger))
	r.Use(middleware.AccessLog(d.Logger))

	if d.Config.Metrics.Enabled {
		r.Use(middleware.Metrics)
	}

	// Auth: build the authenticator from config.
	var auth middleware.Authenticator
	switch d.Config.Auth.Mode {
	case "api_key":
		auth = middleware.NewStaticAPIKey(d.Config.Auth.APIKey)
	default:
		auth = middleware.NoAuth{}
	}
	r.Use(middleware.Auth(auth))

	// Rate limit (optional).
	if d.Config.RateLimit.Enabled {
		r.Use(middleware.RateLimit(d.Config.RateLimit.RequestsPerMinute))
	}

	// ── Handlers ──────────────────────────────────────────────────
	health := NewHealthHandler(d.Version)
	docs := NewDocumentsHandler(d.Logger, d.DB, d.Storage, d.Queue)
	query := NewQueryHandler(d.Logger, d.DB, d.Storage, d.Strategy)
	webhook := NewWebhookHandler(d.Logger, d.Queue)

	// ── Routes ────────────────────────────────────────────────────

	// Prometheus metrics endpoint (outside /v1 versioning).
	if d.Config.Metrics.Enabled {
		r.Handle("/metrics", promhttp.Handler())
	}

	r.Route("/v1", func(r chi.Router) {
		// Health / meta
		r.Get("/health", health.HandleHealth)
		r.Get("/version", health.HandleVersion)

		// Documents
		r.Route("/documents", func(r chi.Router) {
			r.Get("/", docs.HandleListDocuments)
			r.Post("/", docs.HandleIngestDocument)
			r.Get("/{id}", docs.HandleGetDocument)
			r.Delete("/{id}", docs.HandleDeleteDocument)
			r.Get("/{id}/tree", docs.HandleGetTree)
		})

		// Sections
		r.Get("/sections/{id}", docs.HandleGetSection)

		// Query
		r.Post("/query", query.HandleQuery)
	})

	// Internal: queue webhook (QStash).
	r.Post("/internal/jobs/{kind}", webhook.HandleQueueWebhook)

	return r
}
