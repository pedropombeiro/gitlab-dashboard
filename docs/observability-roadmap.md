# OpenTelemetry Roadmap

This document tracks planned improvements and enhancement ideas for the observability setup.

## Completed

- [x] Initial OpenTelemetry setup with OTLP exporter
- [x] Auto-instrumentation for Rails, ActiveRecord, ActiveJob, Faraday, Net::HTTP, Redis
- [x] Local development stack with Grafana, Tempo, Prometheus, Loki
- [x] Pre-configured Grafana dashboard for Rails metrics
- [x] Datasource provisioning with trace-to-logs correlation
- [x] Documentation in `docs/observability.md`

## Short-term (Next Iteration)

### Custom Instrumentation for GitLab API

- [x] Add custom spans to `GitlabClient#execute_query` for GraphQL operation tracking
- [x] Include query name as span attribute
- [x] Track GraphQL variables (sanitized) as span attributes
- [x] Add MR IDs and project names as span attributes where available
- [x] Instrument `fetch_project_version` with custom spans
- [x] Instrument async operations (`fetch_monthly_merged_merge_requests`, `fetch_issues`)

### Error and Retry Tracking

- [x] Track GitLab API rate limiting as span events
- [x] Record retry attempts in `execute_query` as span events
- [x] Add error details to spans on GraphQL failures

### Log Correlation

- [x] Add trace ID to Rails logger formatter
- [x] Configure log shipping to Loki with trace context (Promtail)
- [x] Verify trace-to-logs linking works in Grafana

## Medium-term

### Metrics Migration

Migrate business metrics from Honeybadger gauges to OpenTelemetry metrics:

- [ ] `gitlab_dashboard.users.total` - Total user count
- [ ] `gitlab_dashboard.users.active` - Active users count
- [ ] `gitlab_dashboard.push_subscriptions.total` - Web push subscriptions count
- [ ] `gitlab_dashboard.merge_requests.open` - Open MRs being tracked
- [ ] `gitlab_dashboard.cache.hit_rate` - Cache hit/miss ratio

### Alerting Rules

- [ ] Create Prometheus alerting rules for:
  - High error rate (>5% 5xx responses)
  - Slow GitLab API responses (p95 > 5s)
  - Background job failures
  - High queue latency
- [ ] Configure alert notifications (email, Slack, etc.)

### Enhanced Dashboards

- [ ] Create GitLab API performance dashboard
  - Request rate by endpoint
  - Latency percentiles
  - Error rate by error type
  - Rate limiting events
- [ ] Create Background Jobs dashboard
  - Job throughput by type
  - Queue depth over time
  - Job duration percentiles
  - Failure rates

### Service Level Objectives (SLOs)

- [ ] Define SLOs for key user journeys:
  - Dashboard load time < 2s (p95)
  - MR data freshness < 5 minutes
  - API availability > 99.5%
- [ ] Create SLO dashboard with error budget tracking

## Long-term / Ideas

### Production Deployment

- [ ] Document Kamal accessories configuration for production
- [ ] Evaluate managed observability backends:
  - Grafana Cloud (free tier)
  - Honeycomb
  - Datadog
- [ ] Set up production sampling strategy (10-20%)
- [ ] Configure secure OTLP export with TLS

### Advanced Tracing

- [ ] Browser-side tracing for Turbo/Stimulus
  - Track Turbo Frame loads
  - Track Turbo Stream updates
  - User interaction spans
- [ ] Implement baggage propagation for user context
- [ ] Add trace-based testing for critical paths

### Performance Optimization

- [ ] Profile OpenTelemetry overhead
- [ ] Optimize span creation for hot paths
- [ ] Implement adaptive sampling based on error rate
- [ ] Consider tail-based sampling for error traces

### Integration Enhancements

- [ ] Correlate Honeybadger errors with traces
- [ ] Export traces to Honeybadger Insights (if available)
- [ ] Add GitHub Actions workflow for observability stack testing

## Decided Against / Deferred

Document decisions not to implement certain features and rationale:

| Feature    | Reason | Date |
| ---------- | ------ | ---- |
| _None yet_ |        |      |

## Notes

- Keep Honeybadger for error tracking alongside OpenTelemetry (complementary tools)
- Current setup prioritizes learning and experimentation over production readiness
- Grafana stack chosen for unified visualization of all three signals

## Resources

- [OpenTelemetry Ruby Documentation](https://opentelemetry.io/docs/instrumentation/ruby/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [OpenTelemetry Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
