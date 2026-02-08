# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitLab Dashboard is a Ruby on Rails 8.1 application that provides an intuitive interface for monitoring and managing GitLab merge requests. It fetches merge request data from GitLab's GraphQL API, processes it, and presents it through a responsive web interface with real-time updates using Hotwire (Turbo + Stimulus).

## Technology Stack

- **Backend**: Ruby on Rails 8.1, Ruby 3.0+
- **Database**: SQLite3 (development) / PostgreSQL (production), with separate databases for primary, queue (Solid Queue), cache (Solid Cache), and cable (Solid Cable)
- **Frontend**: Hotwire (Turbo + Stimulus), Bootstrap 5.3, Chart.js 4.5
- **Build Tools**: esbuild (JavaScript), Dart Sass (CSS), Propshaft (asset pipeline)
- **Job Processing**: Solid Queue (database-backed)

## Common Commands

### Setup & Installation

```bash
just install              # Full setup: mise install, bin/setup, lefthook, yarn install
bundle install            # Install Ruby dependencies
yarn install              # Install JavaScript dependencies
```

### Development

```bash
just serve               # Start development server (alias: just dev)
bin/dev                  # Start all development processes (web, CSS watch, JS watch)
just open                # Open application at https://localhost:3000
just toggle-cache        # Toggle Rails development cache (alias: just cache)
```

### Testing

```bash
just test                # Run all RSpec tests
just test spec/path      # Run specific test file or directory
bundle exec rspec        # Run RSpec directly
```

### Linting & Formatting

```bash
just fix                 # Run pre-commit hooks on all files (lefthook)
just lint                # Run pre-push hooks on all files (lefthook)
bin/rake standard        # Run Ruby linter (Standard)
yarn lint                # Run JavaScript linter (ESLint)
yarn lint:fix            # Auto-fix JavaScript linting issues
yarn format              # Format JavaScript/TypeScript with Prettier
yarn format:check        # Check formatting without writing
```

### Building

```bash
yarn build               # Production JavaScript build (minified)
yarn build:dev           # Development JavaScript build (with sourcemaps)
yarn typecheck           # Run TypeScript type checking
bin/rails dartsass:build # Build CSS
just clean               # Clean all build artifacts (alias: just clobber)
```

### Updating Dependencies

```bash
just update              # Update bundler, gems, and npm packages
bundle update            # Update Ruby gems
yarn up                  # Update npm packages
```

### Docker

```bash
just build-docker        # Build Docker image for linux/amd64
just create-dockerfile   # Regenerate Dockerfile with rails generate
```

### Other Utilities

```bash
just dump-schema         # Dump GitLab GraphQL schema for testing
just watch-ci            # Watch GitHub Actions CI runs
```

## High-Level Architecture

### Request Flow

1. **Browser** → HTTP/WebSocket → **Rails Controllers** (MergeRequestsController, ReviewersController)
2. **Controllers** → **Services** (FetchMergeRequestsService, ComputeMergeRequestChangesService)
3. **Services** → **GitlabClient** (GraphQL API integration)
4. **Background Jobs** (ScheduleCacheRefreshJob runs every 1 min, MergeRequestsFetchJob)

### Core Components

#### Services Layer

- **FetchMergeRequestsService** (app/services/fetch_merge_requests_service.rb): Fetches MR data from GitLab API with dynamic caching (1-30 min TTL based on pipeline status). Uses Ruby's Async library for parallel fetching.
- **ComputeMergeRequestChangesService** (app/services/compute_merge_request_changes_service.rb): Computes state transitions in merge requests.
- **GenerateNotificationsService** (app/services/generate_notifications_service.rb): Generates web push notifications based on label-based rules.
- **MergeRequestsCacheService** (app/services/merge_requests_cache_service.rb): Centralized cache management for MR data.

#### GitlabClient

**Location**: app/lib/gitlab_client.rb

Core integration layer with GitLab's GraphQL API featuring:

- Pre-compiled GraphQL queries for performance
- Automatic retry logic for network failures
- Response caching with configurable TTLs
- Async parallel query execution
- Support for both gitlab.com and self-hosted instances

#### Frontend (Hotwire)

**Stimulus Controllers** (app/javascript/controllers/):

- **auto_refresh_controller.js**: Polls for data updates, refreshes Turbo Frames based on schedule
- **merged_merge_requests_chart_controller.js**: Renders Chart.js visualizations
- **theme_selector_controller.js**: Manages light/dark theme switching
- **unread_badge_controller.js**: Manages notification badges
- **web_push_controller.js**: Manages push notification subscriptions

**Asset Build**:

- JavaScript: esbuild bundles from app/javascript/application.js to app/assets/builds/
- CSS: Dart Sass compiles SCSS with Bootstrap customization
- Asset delivery: Propshaft (modern, no sprockets)

### Caching Strategy

Multi-level caching with dynamic TTL:

- **1 minute**: MRs with auto-merge enabled and pending pipelines
- **5 minutes**: MRs with running pipelines
- **30 minutes**: All other MRs

Cache keys format:

- `authored_mr_lists:{author}:{type}` (author-specific)
- `reviewer:{username}` (reviewer-specific)
- `project_version:{project_path}` (project-specific)

### Background Jobs

- **ScheduleCacheRefreshJob**: Runs every 1 minute (dev & prod), triggers cache refresh
- **MergeRequestsFetchJob**: Fetches and caches MR data
- **SendMetricsJob**: Every 5 minutes (production only), sends metrics to Prometheus

## Configuration Files

### Key Configuration

- **config/merge_requests.yml**: Label mappings, colors, status mappings, notification rules, dashboard links
- **config/reviewers.yml**: Reviewer configuration (if used)
- **config/recurring.yml**: Scheduled job definitions with cron-style schedules
- **config/database.yml**: Multi-database setup (primary, queue, cache, cable)

### Environment Variables

- `GITLAB_TOKEN`: GitLab API authentication token (required)
- `GITLAB_URL`: GitLab instance URL (default: https://gitlab.com)
- `RAILS_MAX_THREADS`: Database connection pool size

## Development Workflow

### Local Development

1. The application runs with SSL in development (https://localhost:3000)
2. Self-signed certificates are in config/environments/development/ssl/
3. Procfile.dev manages three processes: web (Rails with SSL), css (Sass watch), js (esbuild watch)
4. Hotwire Livereload provides auto-reload on file changes
5. Spring preloader speeds up boot times

### Git Hooks (Lefthook)

**Pre-commit** (parallel):

- backend-linter: `bin/rake standard {staged_files}` (_.rb, _.erb)
- frontend-linter: `yarn lint:fix` (_.js, _.ts)
- prettier: `prettier --write {staged_files}` (_.js, _.ts, \*.json)

**Pre-push** (parallel):

- backend-linter: `bin/rake standard` (_.rb, _.erb)
- frontend-linter: `yarn lint` (\*.js)
- backend-specs: `bin/bundle exec rspec` ({app,spec}/\*_/_.rb, \*.erb)
- prettier: Check formatting (_.js, _.ts, \*.json)

### Testing

- **Framework**: RSpec with FactoryBot, Capybara, Selenium WebDriver
- **Test files**: spec/\*_/_\_spec.rb
- **Mocking**: WebMock for HTTP stubbing
- **Coverage**: Simplecov
- **Fixtures**: spec/support/fixtures/ (includes gitlab_graphql_schema.json)

## Directory Structure

```
app/
  controllers/          # Controllers with concerns (cache, MR status, reviewer ornaments, web push)
    admin/              # Admin dashboard
    api/                # API endpoints (charts, web push subscriptions)
    concerns/           # Shared controller logic
  dtos/                 # Data Transfer Objects (GroupReviewersDto, MergeRequestCollectionDto, UserDto)
  helpers/              # View helpers (color, humanize, MR parsing/pipeline, reviewers)
  javascript/           # Frontend JavaScript (Stimulus controllers, libs, types)
    controllers/        # Stimulus controllers
    lib/                # Shared JavaScript utilities
    types/              # TypeScript type definitions
  jobs/                 # Background jobs (ApplicationJob, MergeRequestsFetchJob, etc.)
  lib/                  # Application libraries (GitlabClient)
  models/               # ActiveRecord models (GitlabUser, WebPushSubscription)
  presenters/           # Presentation logic (MergeRequestPresenter, ReviewerPresenter, etc.)
  services/             # Business logic services
  views/                # ERB templates (admin, errors, layouts, merge_requests, pwa, reviewers, shared)
```

## Monitoring & Observability

- **Job Monitoring**: Mission Control Jobs at /jobs (Solid Queue dashboard)
- **Error Tracking**: Honeybadger (config/honeybadger.yml)
- **Metrics**: Prometheus Exporter (SendMetricsJob every 5 min)
- **Logging**: HTTPLog for API requests, Rails logger for application logs
- **Distributed Tracing**: OpenTelemetry → Tempo → Prometheus (see `.claude/docs/telemetry.md` for details)

## Renovate Bot

Renovate Bot is configured in .renovaterc.json with:

- Auto-merge for non-breaking updates (patch/minor)
- Grouped PRs for GitHub Actions, npm dependencies, Ruby gems
- Separate PRs for major version updates
- Auto-merge directly to branch for linters and test frameworks
