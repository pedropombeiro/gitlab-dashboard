# Observability Setup Guide

This document describes how to set up and use OpenTelemetry-based observability for GitLab Dashboard, including distributed tracing, metrics, and logs correlation.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Local Development Setup](#local-development-setup)
- [Configuration](#configuration)
- [Viewing Telemetry](#viewing-telemetry)
- [Custom Instrumentation](#custom-instrumentation)
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
│  ┌──────────────┐          ┌──────────────────────┐                │
│  │   Rails App  │──OTLP───▶│   OTEL Collector     │                │
│  │   (web)      │          │   :4317/:4318        │                │
│  │   :3000      │          └──────────┬───────────┘                │
│  └──────────────┘                     │                            │
│         │                    ┌────────┼────────┐                   │
│         │                    ▼        ▼        ▼                   │
│         │            ┌───────────┐ ┌──────┐ ┌──────┐               │
│         │            │ Prometheus│ │Tempo │ │ Loki │               │
│         │            │   :9090   │ │:3200 │ │:3100 │               │
│         │            └─────┬─────┘ └──┬───┘ └──┬───┘               │
│         │                  │          │        │                   │
│         │                  └──────────┴────────┘                   │
│         │                            │                             │
│  ┌──────▼──────┐              ┌──────▼──────┐                      │
│  │   Redis     │              │   Grafana   │◀─── Browse here      │
│  │   :6379     │              │   :3001     │                      │
│  └─────────────┘              └─────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

- **OpenTelemetry Collector**: Receives telemetry from the Rails app and routes it to appropriate backends
- **Grafana Tempo**: Distributed tracing backend for storing and querying traces
- **Prometheus**: Time-series database for metrics storage
- **Grafana Loki**: Log aggregation system with trace correlation
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
   - Additional backend services (Tempo, Loki, OTEL Collector)

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

| Variable                      | Default                      | Description             |
| ----------------------------- | ---------------------------- | ----------------------- |
| `OTEL_SERVICE_NAME`           | `gitlab-dashboard`           | Service name in traces  |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | OTLP collector endpoint |
| `OTEL_TRACES_EXPORTER`        | `otlp`                       | Trace exporter type     |
| `OTEL_METRICS_EXPORTER`       | `otlp`                       | Metrics exporter type   |
| `OTEL_LOGS_EXPORTER`          | `otlp`                       | Logs exporter type      |

### Disabling OpenTelemetry

To run the application without OpenTelemetry instrumentation, simply don't set the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable. The initializer checks for this variable and skips configuration if it's not present.

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

## Production Deployment

### Option 1: Self-Hosted with Kamal

Add observability services as Kamal accessories in `config/deploy.yml`:

```yaml
accessories:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.115.0
    host: your-server.example.com
    port: 4318
    volumes:
      - /opt/otel/config.yml:/etc/otel-collector-config.yml:ro
    cmd: --config=/etc/otel-collector-config.yml

  tempo:
    image: grafana/tempo:2.6.1
    host: your-server.example.com
    volumes:
      - /opt/tempo:/var/tempo
      - /opt/tempo/config.yml:/etc/tempo.yml:ro
    cmd: -config.file=/etc/tempo.yml
```

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
3. **Verify collector**: Check OTEL Collector logs with `docker compose logs otel-collector`

### No Traces Appearing

1. **Generate traffic**: Make some requests to the application
2. **Wait for batching**: Traces are batched, may take a few seconds
3. **Check collector**: Verify data flow through the collector
4. **Check Tempo**: Ensure Tempo is receiving data (`docker compose logs tempo`)

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
