# Telemetry Architecture

This document describes the OpenTelemetry-based observability setup for gitlab-dashboard.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      gitlab-dashboard App                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  OpenTelemetry SDK (auto-instrumentation)               │   │
│  │  - Rack, Faraday, Net::HTTP, Redis, ActiveRecord, etc.  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │ OTLP (HTTP :4318)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Tempo                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  metrics_generator (span_metrics)                        │   │
│  │  - Generates Prometheus metrics from traces              │   │
│  │  - Attaches exemplars for trace correlation              │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────┬─────────────────────────────────────┬────────────┘
               │ remote_write                        │ trace storage
               ▼                                     ▼
┌──────────────────────────┐            ┌────────────────────────┐
│       Prometheus         │            │    Tempo Storage       │
│  - Span metrics storage  │            │    (trace queries)     │
│  - Exemplar storage      │            │                        │
└──────────────────────────┘            └────────────────────────┘
               │                                     │
               └──────────────┬──────────────────────┘
                              ▼
                    ┌──────────────────┐
                    │     Grafana      │
                    │  - Dashboards    │
                    │  - Exemplar UI   │
                    └──────────────────┘
```

## Key Components

### Application Layer

**OpenTelemetry SDK** (`config/initializers/opentelemetry.rb`):

- Auto-instruments Rails, Rack, Faraday, Net::HTTP, Redis, ActiveRecord
- Uses **new semantic conventions** (semconv 1.21+) via `use_new_semconv: true`
- Exports traces via OTLP HTTP to Tempo

**Environment Variables**:

- `OTEL_SERVICE_NAME`: Service name in traces (default: `gitlab-dashboard`)
- `OTEL_EXPORTER_OTLP_ENDPOINT`: Tempo endpoint (e.g., `http://tempo:4318`)

### Tempo (Trace Backend)

**Configuration**: `config/observability/tempo.yml` (dev) / NAS repo (prod)

**metrics_generator**: Generates Prometheus metrics from incoming traces:

- `traces_spanmetrics_calls_total` - Request count by dimensions
- `traces_spanmetrics_latency_bucket` - Latency histogram
- `traces_spanmetrics_latency_count` - Latency count
- `traces_spanmetrics_latency_sum` - Latency sum

**Span Metrics Dimensions** (labels on generated metrics):

```yaml
dimensions:
  - http.request.method # GET, POST, etc.
  - http.response.status_code # 200, 404, 500, etc.
  - http.route # URL pattern
  - rpc.service # GraphQL service
  - graphql.operation.name # Query/mutation name
  - graphql.operation.type # query, mutation
  - graphql.variable.author # Author filter
  - graphql.variable.username # Username filter
  - graphql.variable.fullPath # Project path
  - db.system # Database type
  - db.operation.name # SQL operation
  - project.web_url # GitLab project URL
```

**Exemplars**: Enabled via `send_exemplars: true` - attaches trace IDs to metrics for click-through from Grafana to Tempo.

### Prometheus

**Configuration**: `config/observability/prometheus.yml`

**Key Features**:

- Receives span metrics via remote_write from Tempo
- Exemplar storage enabled (`--enable-feature=exemplar-storage`)
- Scrapes Tempo metrics endpoint

### Grafana

**Dashboards** (`config/observability/grafana/provisioning/dashboards/`):

- `rails-otel.json` - Main Rails OTel dashboard
- `gitlab-api-performance.json` - GitLab API performance

**Datasource Configuration**:

- Prometheus datasource with `exemplarTraceIdDestinations` linking `trace_id` to Tempo

## OTel Semantic Conventions

This project uses **OTel semconv 1.21+** (new/stable conventions):

| Old (deprecated)   | New (stable)                | Prometheus Label            |
| ------------------ | --------------------------- | --------------------------- |
| `http.method`      | `http.request.method`       | `http_request_method`       |
| `http.status_code` | `http.response.status_code` | `http_response_status_code` |
| `http.url`         | `url.full`                  | `url_full`                  |
| `http.target`      | `url.path` + `url.query`    | `url_path`, `url_query`     |

**Important**: All instrumentations must have `use_new_semconv: true` to emit new attributes.

## Custom Span Attributes

The app sets custom attributes in `app/lib/gitlab_client.rb`:

```ruby
# Rate limit info
span.set_attribute("http.ratelimit.limit", limit)
span.set_attribute("http.ratelimit.remaining", remaining)
span.set_attribute("http.ratelimit.reset_at", reset_at)

# GraphQL context
span.set_attribute("graphql.operation.name", operation_name)
span.set_attribute("graphql.operation.type", operation_type)
span.set_attribute("graphql.variable.username", username)
span.set_attribute("graphql.variable.fullPath", project_path)

# Project info
span.set_attribute("project.web_url", project_url)
```

## Development vs Production

| Component     | Development                        | Production (NAS)                   |
| ------------- | ---------------------------------- | ---------------------------------- |
| Tempo config  | `config/observability/tempo.yml`   | `compose/grafana/tempo/tempo.yaml` |
| Dashboards    | `config/observability/grafana/...` | `compose/grafana/grafana/...`      |
| OTLP endpoint | `http://tempo:4318`                | `http://tempo:4318`                |

**Both environments use the same architecture** - app sends directly to Tempo, which generates span metrics.

## Troubleshooting

### Dashboard panels showing no data

1. **Check metric names**: Tempo generates `traces_spanmetrics_*` (not `traces_span_metrics_*`)
2. **Check label names**: Must match Tempo dimensions (e.g., `http_response_status_code`, not `http_status_code`)
3. **Check semconv**: App must emit new attributes (`use_new_semconv: true`)

### Exemplars not showing

1. Verify Prometheus has `--enable-feature=exemplar-storage`
2. Verify Tempo has `send_exemplars: true` in metrics_generator
3. Verify Grafana datasource has `exemplarTraceIdDestinations` configured
4. Enable "Exemplars" toggle in Grafana panel options

### Traces not appearing in Tempo

1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` is set correctly
2. Check Tempo is receiving data: `tempo_distributor_spans_received_total`
3. Check app logs for OTLP export errors

## Related Files

- `config/initializers/opentelemetry.rb` - OTel SDK configuration
- `config/observability/tempo.yml` - Tempo configuration
- `config/observability/prometheus.yml` - Prometheus configuration
- `config/observability/grafana/provisioning/datasources/datasources.yml` - Grafana datasources
- `app/lib/gitlab_client.rb` - Custom span attributes
