# Observability Setup Guide

This document describes how to set up and use OpenTelemetry-based observability for GitLab Dashboard, including distributed tracing, metrics, and logs correlation.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Local Development Setup](#local-development-setup)
- [Configuration](#configuration)
- [Viewing Telemetry](#viewing-telemetry)
- [Custom Instrumentation](#custom-instrumentation)
- [Prometheus Exemplars](#prometheus-exemplars)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)

## Overview

GitLab Dashboard uses [OpenTelemetry](https://opentelemetry.io/) for observability, providing:

- **Distributed Tracing**: Track requests through the application, including database queries, external API calls, and background jobs
- **Metrics**: Monitor request rates, latencies, error rates, and custom application metrics
- **Logs Correlation**: Link log entries to specific traces for easier debugging

### What Gets Instrumented Automatically

| Component        | Instrumentation    | Data Captured                             |
| ---------------- | ------------------ | ----------------------------------------- |
| HTTP Requests    | Rack, ActionPack   | Request duration, status codes, endpoints |
| Views            | ActionView         | Template render time                      |
| Database         | ActiveRecord       | Query time, SQL (obfuscated)              |
| Background Jobs  | ActiveJob          | Job duration, queue time, errors          |
| GitLab API       | Faraday, Net::HTTP | External API call duration                |
| Redis            | Redis              | Cache/session operations                  |
| Async Operations | ConcurrentRuby     | Concurrent task tracking                  |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    docker compose environment                        │
│                                                                     │
│  ┌──────────────┐                                                   │
│  │   Rails App  │──OTLP───┐                                        │
│  │   (web)      │         │                                        │
│  │   :3000      │         │                                        │
│  └──────────────┘         │                                        │
│         │                 ▼                                        │
│         │          ┌─────────────┐   remote    ┌───────────┐       │
│         │          │    Tempo    │───write────▶│ Prometheus│       │
│         │          │ :3200/:4318 │  (metrics)  │   :9090   │       │
│         │          └──────┬──────┘             └─────┬─────┘       │
│         │                 │                          │             │
│  ┌──────▼──────┐   ┌──────▼──────┐            ┌──────▼──────┐      │
│  │   Redis     │   │   Promtail  │───────────▶│    Loki     │      │
│  │   :6379     │   │  (log ship) │            │   :3100     │      │
│  └─────────────┘   └─────────────┘            └──────┬──────┘      │
│                                                      │             │
│                                               ┌──────▼──────┐      │
│                                               │   Grafana   │◀─── Browse here
│                                               │   :3001     │      │
│                                               └─────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

- **Grafana Tempo**: Distributed tracing backend that receives OTLP traces directly from the app, stores them, and generates span metrics with exemplars
- **Prometheus**: Time-series database for metrics storage (receives span metrics from Tempo via remote_write)
- **Grafana Loki**: Log aggregation system with trace correlation
- **Promtail**: Log shipping agent that collects Rails logs and sends them to Loki
- **Grafana**: Unified visualization dashboard for all telemetry data

## Local Development Setup

### Prerequisites

- Docker and Docker Compose installed
- Application dependencies installed (`bundle install`)

### Starting the Observability Stack

1. Start all services including the observability stack:

   ```sh
   docker compose up
   ```

   This starts:
   - Rails application on `http://localhost:3000`
   - Grafana on `http://localhost:3001`
   - Prometheus on `http://localhost:9090`
   - Additional backend services (Tempo, Loki)

2. Access Grafana at `http://localhost:3001`
   - Default credentials: `admin` / `admin`
   - Anonymous access is enabled for viewing

3. Make some requests to the Rails application to generate telemetry data

### Stopping the Stack

```sh
docker compose down
```

To remove all data volumes (traces, metrics, logs):

```sh
docker compose down -v
```

## Configuration

### Environment Variables

| Variable                        | Default             | Description                                               |
| ------------------------------- | ------------------- | --------------------------------------------------------- |
| `OTEL_SERVICE_NAME`             | `gitlab-dashboard`  | Service name in traces                                    |
| `OTEL_EXPORTER_OTLP_ENDPOINT`   | `http://tempo:4318` | OTLP endpoint (Tempo receives traces directly)            |
| `OTEL_TRACES_EXPORTER`          | `otlp`              | Trace exporter type                                       |
| `OTEL_METRICS_EXPORTER`         | `none`              | Metrics exporter (disabled, Tempo generates span metrics) |
| `OTEL_LOGS_EXPORTER`            | `none`              | Logs exporter (disabled, Promtail ships logs)             |
| `OTEL_SEMCONV_STABILITY_OPT_IN` | (unset)             | HTTP semantic conventions selection                       |

### Disabling OpenTelemetry

To run the application without OpenTelemetry instrumentation, simply don't set the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable. The initializer checks for this variable and skips configuration if it's not present.

### HTTP Semantic Conventions

The Rack, Faraday, and Net::HTTP instrumentations use the `OTEL_SEMCONV_STABILITY_OPT_IN` environment variable to control HTTP semantic convention attributes.

Recommended setting:

```sh
OTEL_SEMCONV_STABILITY_OPT_IN=http
```

Valid values:

| Value         | Behavior                                                                  |
| ------------- | ------------------------------------------------------------------------- |
| (empty/unset) | Old attributes: `http.method`, `http.status_code`                         |
| `http`        | New stable attributes: `http.request.method`, `http.response.status_code` |
| `http/dup`    | Emits both old and new attributes (migration)                             |

### Sampling Configuration

By default, all traces are captured (100% sampling). For production, you may want to reduce this:

```sh
# Sample 10% of traces
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

## Viewing Telemetry

### Traces in Grafana

1. Open Grafana at `http://localhost:3001`
2. Navigate to **Explore** (compass icon in sidebar)
3. Select **Tempo** as the data source
4. Use the **Search** tab to find traces by:
   - Service name
   - Span name
   - Duration
   - Tags/attributes

### Pre-configured Dashboard

A Rails-specific dashboard is automatically provisioned:

1. Go to **Dashboards** in Grafana
2. Find **Rails OpenTelemetry Dashboard**
3. View panels for:
   - Request rate (requests/second)
   - Request latency (p50, p95)
   - Error rate
   - Database query latency
   - External API latency
   - Background job latency
   - Recent traces link

### Metrics in Prometheus

Access Prometheus directly at `http://localhost:9090` for raw metric queries.

Common queries:

```promql
# Request rate
rate(http_server_request_duration_seconds_count[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(http_server_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_server_request_duration_seconds_count{http_status_code=~"5.."}[5m])
```

### Correlating Logs with Traces

Loki is configured to extract trace IDs from logs. In Grafana:

1. View a trace in Tempo
2. Click on "Logs for this span" to see related logs
3. Or search Loki with `{service_name="gitlab-dashboard"} | trace_id="<trace-id>"`

## Custom Instrumentation

### Adding Custom Spans

To add custom spans for specific operations:

```ruby
# In any Ruby code
tracer = OpenTelemetry.tracer_provider.tracer('gitlab-dashboard')

tracer.in_span('custom_operation', attributes: { 'custom.attribute' => 'value' }) do |span|
  # Your code here
  span.add_event('something_happened', attributes: { 'detail' => 'info' })

  # Set span status on error
  span.status = OpenTelemetry::Trace::Status.error('Something went wrong')
end
```

### Adding Attributes to Current Span

```ruby
current_span = OpenTelemetry::Trace.current_span
current_span.set_attribute('user.id', current_user.id)
current_span.set_attribute('merge_request.id', mr.id)
```

### Custom Metrics

```ruby
meter = OpenTelemetry.meter_provider.meter('gitlab-dashboard')

# Counter
counter = meter.create_counter('custom_events_total', description: 'Count of custom events')
counter.add(1, attributes: { 'event_type' => 'example' })

# Histogram
histogram = meter.create_histogram('custom_duration_seconds', description: 'Duration of custom operation')
histogram.record(duration, attributes: { 'operation' => 'example' })
```

## Prometheus Exemplars

Exemplars link Prometheus metrics to specific trace samples, enabling you to jump from a metric spike directly to a representative trace. This is invaluable for debugging latency spikes, error rate increases, or understanding outliers.

### How Exemplars Work

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Exemplar Data Flow                              │
│                                                                         │
│  Rails App                   Tempo                    Prometheus        │
│  ─────────                   ─────                    ───────────       │
│  Spans with    ──OTLP──▶  metrics_generator ─remote─▶  Metrics with    │
│  trace context            (generates metrics   write   exemplars        │
│                            + exemplars from           (stored with      │
│                            incoming traces)            trace_id)        │
│                                                                         │
│                                         Grafana                         │
│                                         ───────                         │
│                                         Queries metrics ──────┐         │
│                                         with exemplars        │         │
│                                                ▼              │         │
│                                         Click exemplar ───────┘         │
│                                         dot to jump to                  │
│                                         Tempo trace                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Configuration

Exemplars are enabled via three components:

#### 1. Tempo Metrics Generator

Tempo's metrics_generator processes incoming traces and generates span metrics with exemplars:

```yaml
# config/observability/tempo.yml
metrics_generator:
  processor:
    span_metrics:
      dimensions:
        - http.method
        - http.status_code
        - http.route
        - graphql.operation.name
        - graphql.operation.type
        # ... additional dimensions
  registry:
    external_labels:
      source: tempo
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true # Enable exemplar generation
```

This approach is simpler than using an OTel Collector with a spanmetrics connector, as Tempo handles both trace storage and span metrics generation in one component.

#### 2. Prometheus Storage

Prometheus must have exemplar storage enabled (already configured in docker-compose.yml):

```yaml
# docker-compose.yml
prometheus:
  command:
    - "--enable-feature=exemplar-storage"
```

#### 3. Grafana Datasource

The Prometheus datasource links exemplars to Tempo traces:

```yaml
# config/observability/grafana/provisioning/datasources/datasources.yml
datasources:
  - name: Prometheus
    jsonData:
      exemplarTraceIdDestinations:
        - name: trace_id # Field name from spanmetrics
          datasourceUid: tempo # Links to Tempo datasource
```

### Viewing Exemplars in Grafana

1. **Open a panel** with histogram metrics (e.g., `otel_traces_spanmetrics_latency_bucket`)

2. **Enable exemplars** in the panel:
   - Edit the panel
   - In the Query options, toggle "Exemplars" to ON
   - Or add `$__exemplars()` to your PromQL query

3. **View exemplar dots**: Small dots appear on the graph at points where traces were sampled

4. **Click to trace**: Click any exemplar dot to jump directly to the corresponding trace in Tempo

### Metrics with Exemplars

The following metrics automatically include exemplars:

| Metric                              | Description               | Use Case                    |
| ----------------------------------- | ------------------------- | --------------------------- |
| `traces_spanmetrics_latency_bucket` | Request latency histogram | Find slow request traces    |
| `traces_spanmetrics_calls_total`    | Request count by status   | Find error traces (4xx/5xx) |

### Available Dimensions for Filtering

Exemplars inherit all configured spanmetrics dimensions, allowing you to filter for specific types of requests:

| Dimension                   | Example Values              | Description            |
| --------------------------- | --------------------------- | ---------------------- |
| `http.method`               | GET, POST, PUT              | HTTP method            |
| `http.status_code`          | 200, 404, 500               | Response status        |
| `http.route`                | /merge_requests, /reviewers | Rails route            |
| `graphql.operation.name`    | GetMergeRequests            | GraphQL operation      |
| `graphql.operation.type`    | query, mutation             | GraphQL type           |
| `graphql.variable.username` | john_doe                    | GitLab username filter |
| `graphql.variable.fullPath` | gitlab-org/gitlab           | Project path           |
| `rpc.service`               | gitlab                      | RPC service name       |
| `db.system`                 | sqlite                      | Database type          |
| `db.operation`              | SELECT, INSERT              | Database operation     |
| `project.web_url`           | https://gitlab.com/...      | GitLab project URL     |

### Example Queries

```promql
# Latency histogram with exemplars (99th percentile)
histogram_quantile(0.99,
  rate(traces_spanmetrics_latency_bucket{http_route="/merge_requests"}[5m])
)

# Error rate with exemplars
rate(traces_spanmetrics_calls_total{http_status_code=~"5.."}[5m])

# GraphQL operation latency
histogram_quantile(0.95,
  rate(traces_spanmetrics_latency_bucket{graphql_operation_name!=""}[5m])
)
```

### Troubleshooting Exemplars

| Issue                              | Solution                                                           |
| ---------------------------------- | ------------------------------------------------------------------ |
| No exemplar dots visible           | Enable "Exemplars" toggle in Grafana panel query options           |
| Exemplars not linking to traces    | Verify `trace_id` field name in Grafana datasource config          |
| Missing exemplars for some metrics | Exemplars only attach to histogram/counter observations from spans |
| Old traces not found               | Tempo retention may have expired; check Tempo config               |

## Production Deployment

### Option 1: Self-Hosted with Kamal

Add observability services as Kamal accessories in `config/deploy.yml`:

```yaml
accessories:
  tempo:
    image: grafana/tempo:2.6.1
    host: your-server.example.com
    port: 4318
    volumes:
      - /opt/tempo:/var/tempo
      - /opt/tempo/config.yml:/etc/tempo.yml:ro
    cmd: -config.file=/etc/tempo.yml

  prometheus:
    image: prom/prometheus:v2.55.1
    host: your-server.example.com
    port: 9090
    volumes:
      - /opt/prometheus:/prometheus
      - /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    cmd: |
      --config.file=/etc/prometheus/prometheus.yml
      --storage.tsdb.path=/prometheus
      --web.enable-remote-write-receiver
      --enable-feature=exemplar-storage
```

Note: The application sends traces directly to Tempo (no OTel Collector needed). Tempo generates span metrics with exemplars and pushes them to Prometheus via remote_write.

### Option 2: Managed Observability Backend

Use a managed service that accepts OTLP:

- **Grafana Cloud**: Free tier available
- **Honeycomb**: Excellent for tracing
- **Datadog**: Full APM suite

Configure the endpoint:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.your-provider.com
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer your-api-key
```

### Production Recommendations

1. **Sampling**: Use trace sampling (10-20%) to reduce costs
2. **Batching**: The OTLP exporter batches by default, which is good
3. **Timeouts**: Configure appropriate timeouts for the exporter
4. **Security**: Use TLS for OTLP endpoints in production

## Troubleshooting

### OpenTelemetry Not Working

1. **Check environment variable**: Ensure `OTEL_EXPORTER_OTLP_ENDPOINT` is set
2. **Check logs**: Look for "OpenTelemetry initialized" in Rails logs
3. **Verify Tempo**: Check Tempo logs with `docker compose logs tempo`

### No Traces Appearing

1. **Generate traffic**: Make some requests to the application
2. **Wait for batching**: Traces are batched, may take a few seconds
3. **Check Tempo**: Ensure Tempo is receiving data (`docker compose logs tempo`)

### Connection Errors

If you see OTLP connection errors:

1. Ensure all services are running: `docker compose ps`
2. Check network connectivity between services
3. Verify ports are not blocked

### Debug Logging

Enable verbose OTEL logging:

```sh
OTEL_LOG_LEVEL=debug
```

### Common Issues

| Issue                    | Solution                                           |
| ------------------------ | -------------------------------------------------- |
| "OTLP exporter error"    | Check collector is running and endpoint is correct |
| No metrics in Prometheus | Verify Prometheus is scraping the collector        |
| Traces not correlated    | Ensure trace context is propagated in HTTP headers |
| High memory usage        | Reduce sampling rate or batch size                 |
