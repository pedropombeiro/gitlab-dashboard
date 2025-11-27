# GitLab Dashboard Architecture

## Overview

GitLab Dashboard is a Ruby on Rails 8.1 application that provides an intuitive interface for monitoring and managing GitLab merge requests. The application fetches merge request data from GitLab's GraphQL API, processes it, and presents it through a responsive web interface with real-time updates.

## Technology Stack

### Backend

- **Framework**: Ruby on Rails 8.1
- **Language**: Ruby 3.0+
- **Web Server**: Puma
- **Database**: SQLite3 (multiple databases)
  - Primary database for application data
  - Queue database for background jobs (Solid Queue)
  - Cache database for Rails.cache (Solid Cache)
  - Cable database for ActionCable (Solid Cable)

### Frontend

- **JavaScript Framework**: Hotwire (Turbo + Stimulus)
- **UI Framework**: Bootstrap 5.3
- **Build Tools**:
  - esbuild (JavaScript bundling)
  - Dart Sass (CSS compilation)
- **Charting**: Chart.js 4.4
- **Components**:
  - FontAwesome icons
  - Popper.js for tooltips
  - local-time for timezone-aware timestamps

### Infrastructure

- **Job Processing**: Solid Queue (database-backed)
- **Caching**: Solid Cache (database-backed) + Redis
- **WebSockets**: Solid Cable (database-backed)
- **Deployment**: Kamal (Docker-based)
- **Monitoring**: Honeybadger, Prometheus
- **Security**: Rack::Attack for rate limiting

## Application Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Browser                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Turbo       │  │  Stimulus    │  │  Chart.js    │     │
│  │  Frames      │  │  Controllers │  │  Components  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↕ HTTP/WebSocket
┌─────────────────────────────────────────────────────────────┐
│                      Rails Application                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    Controllers                        │  │
│  │  • MergeRequestsController                           │  │
│  │  • ReviewersController                               │  │
│  │  • API::UserMergeRequestChartsController            │  │
│  │  • Admin::DashboardController                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                            ↕                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                      Services                         │  │
│  │  • FetchMergeRequestsService                         │  │
│  │  • ComputeMergeRequestChangesService                 │  │
│  │  • GenerateNotificationsService                      │  │
│  │  • MergeRequestsCacheService                         │  │
│  │  • LocationLookupService                             │  │
│  └──────────────────────────────────────────────────────┘  │
│                            ↕                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   GitlabClient                        │  │
│  │           (GraphQL API Integration)                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│                  Background Jobs Layer                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  • MergeRequestsFetchJob                             │  │
│  │  • ScheduleCacheRefreshJob (every 1 min)            │  │
│  │  • SendMetricsJob (every 5 min)                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│                    External Services                        │
│  • GitLab GraphQL API (gitlab.com or self-hosted)          │
│  • Honeybadger (error tracking)                             │
│  • Prometheus (metrics)                                     │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Controllers

#### MergeRequestsController

- **Purpose**: Main dashboard for viewing merge requests
- **Key Actions**:
  - `index`: Root page showing merge requests
  - `open_list`: List of open merge requests
  - `merged_list`: Recently merged merge requests
  - `merged_chart`: Chart visualization of merged MRs
- **Location**: app/controllers/merge_requests_controller.rb:8

#### ReviewersController

- **Purpose**: Display reviewer information and capacity
- **Key Actions**:
  - `index`: Reviewer dashboard
  - `list`: List of reviewers with their active review count
- **Location**: app/controllers/reviewers_controller.rb:5

#### API Controllers

- **UserMergeRequestChartsController**: Provides JSON data for merge request statistics
- **WebPushSubscriptionsController**: Handles web push notification subscriptions

### 2. Services

#### FetchMergeRequestsService

- **Purpose**: Fetches merge request data from GitLab API
- **Features**:
  - Caches responses based on pipeline status
  - Dynamic refresh scheduling (1-30 minutes based on activity)
  - Parallel fetching of reviewer and project information
  - Async operations using Ruby's Async library
- **Location**: app/services/fetch_merge_requests_service.rb:1

#### ComputeMergeRequestChangesService

- **Purpose**: Computes changes and state transitions in merge requests
- **Location**: app/services/compute_merge_request_changes_service.rb:1

#### GenerateNotificationsService

- **Purpose**: Generates web push notifications based on configurable rules
- **Features**: Label-based notification triggers
- **Location**: app/services/generate_notifications_service.rb:1

#### MergeRequestsCacheService

- **Purpose**: Centralized cache management for MR data
- **Location**: app/services/merge_requests_cache_service.rb:1

### 3. GitlabClient

The GitlabClient is the core integration layer with GitLab's GraphQL API.

**Key Features**:

- Pre-compiled GraphQL queries for performance
- Automatic retry logic for network failures
- Response caching with configurable TTLs
- Async parallel query execution
- Support for both gitlab.com and self-hosted instances

**Query Types**:

- User queries (current user, specific user)
- Merge request queries (open, merged, monthly stats)
- Reviewer queries (with active review counts)
- Project queries (issues, version info)
- Group queries (reviewer lists)

**Location**: app/lib/gitlab_client.rb:1

### 4. Models

#### GitlabUser

- **Purpose**: Stores GitLab user information
- **Fields**: User data, contact timestamps
- **Location**: app/models/gitlab_user.rb:1

#### WebPushSubscription

- **Purpose**: Manages web push notification subscriptions
- **Fields**: Endpoint, keys, notification timestamp
- **Location**: app/models/web_push_subscription.rb:1

### 5. Background Jobs

#### ScheduleCacheRefreshJob

- **Schedule**: Every 1 minute (development and production)
- **Purpose**: Triggers cache refresh for merge requests
- **Location**: app/jobs/schedule_cache_refresh_job.rb:1

#### MergeRequestsFetchJob

- **Purpose**: Fetches and caches merge request data
- **Triggered by**: ScheduleCacheRefreshJob
- **Location**: app/jobs/merge_requests_fetch_job.rb:1

#### SendMetricsJob

- **Schedule**: Every 5 minutes (production only)
- **Purpose**: Sends metrics to Prometheus
- **Location**: app/jobs/send_metrics_job.rb:1

## Data Flow

### Merge Request Viewing Flow

1. **User Request**
   - User navigates to `/mrs` or `/mrs/open_list`
   - Request hits MergeRequestsController

2. **Service Layer**
   - Controller invokes FetchMergeRequestsService
   - Service checks Rails.cache for cached data

3. **Cache Miss Path**
   - GitlabClient executes GraphQL query
   - Parallel async queries fetch:
     - Merge requests
     - Reviewer information
     - Project versions
     - Related issues
   - Response cached with dynamic TTL (1-30 minutes)

4. **Cache Hit Path**
   - Cached data returned immediately
   - Next refresh time included in response

5. **Response Processing**
   - DTOs (Data Transfer Objects) transform raw GraphQL responses
   - Helpers apply label mappings and status colors
   - View renders data with Turbo Frames

6. **Client-Side Updates**
   - Stimulus controllers initialize
   - Auto-refresh controller polls for updates
   - Chart controllers render visualizations

### Background Refresh Flow

1. **Scheduled Job**
   - ScheduleCacheRefreshJob runs every minute
   - Determines which caches need refresh

2. **Async Fetch**
   - MergeRequestsFetchJob queued
   - Fetches fresh data from GitLab
   - Updates cache

3. **Notification Generation**
   - ComputeMergeRequestChangesService detects changes
   - GenerateNotificationsService evaluates rules
   - Web push notifications sent if criteria met

4. **Client Update**
   - Turbo Streams update UI elements
   - Auto-refresh controller detects changes
   - UI updates without full page reload

## Caching Strategy

### Multi-Level Caching

1. **Rails.cache (Solid Cache)**
   - Primary cache storage
   - Database-backed for persistence
   - Used for:
     - Merge request lists (1-30 min TTL)
     - Reviewer information (configurable TTL)
     - Project versions (long TTL)
     - Issue data (configurable TTL)

2. **Dynamic TTL**
   - **1 minute**: MRs with auto-merge enabled and pending pipelines
   - **5 minutes**: MRs with running pipelines
   - **30 minutes**: All other MRs

3. **Cache Keys**
   - Author-specific: `authored_mr_lists:{author}:{type}`
   - Reviewer-specific: `reviewer:{username}`
   - Project-specific: `project_version:{project_path}`
   - Issue-specific: `project_issues:{issue_iids_hash}`

### Cache Invalidation

- Time-based expiration (no manual invalidation)
- Background jobs refresh before expiration
- Next refresh time communicated to frontend

## Frontend Architecture

### Hotwire Stack

#### Turbo

- **Turbo Drive**: SPA-like navigation without full page reloads
- **Turbo Frames**: Partial page updates
- **Turbo Streams**: Real-time updates via WebSocket

#### Stimulus Controllers

1. **AutoRefreshController**
   - Polls for data updates
   - Refreshes Turbo Frames based on schedule
   - Location: app/javascript/controllers/auto_refresh_controller.js:1

2. **MergedMergeRequestsChartController**
   - Renders Chart.js visualizations
   - Fetches monthly statistics
   - Location: app/javascript/controllers/merged_merge_requests_chart_controller.js:1

3. **ThemeSelectorController**
   - Manages light/dark theme switching
   - Persists preference to localStorage
   - Location: app/javascript/controllers/theme_selector_controller.js:1

4. **UnreadBadgeController**
   - Manages notification badges
   - Updates counts based on new changes
   - Location: app/javascript/controllers/unread_badge_controller.js:1

5. **WebPushController**
   - Manages push notification subscriptions
   - Handles permission requests
   - Location: app/javascript/controllers/web_push_controller.js:1

### Asset Pipeline

1. **JavaScript Build** (esbuild)
   - Entry point: app/javascript/application.js
   - Output: app/assets/builds/
   - Format: ESM modules
   - Includes sourcemaps for debugging

2. **CSS Build** (Dart Sass)
   - SCSS compilation
   - Bootstrap customization
   - Custom stylesheets

3. **Asset Delivery** (Propshaft)
   - Modern asset pipeline
   - No sprockets dependency
   - Direct file serving

## Configuration

### Key Configuration Files

1. **config/merge_requests.yml**
   - Label mappings and colors
   - Status mappings
   - Notification rules based on labels and states
   - Dashboard links

2. **config/reviewers.yml**
   - Reviewer configuration (if used)

3. **config/recurring.yml**
   - Scheduled job definitions
   - Cron-style schedules
   - Job priorities and queues

4. **config/database.yml**
   - Multi-database configuration
   - Separate databases for primary, queue, cache, cable

### Environment Variables

- `GITLAB_TOKEN`: GitLab API authentication token
- `GITLAB_URL`: GitLab instance URL (default: <https://gitlab.com>)
- `RAILS_MAX_THREADS`: Database connection pool size

## Deployment

### Docker-based Deployment (Kamal)

The application is deployed using Kamal, which manages:

- Docker container builds
- Rolling deployments
- Zero-downtime updates
- SSL/TLS termination (via Thruster)

### Development Environment

**Procfile.dev** manages three processes:

1. **web**: Rails server with SSL support (port 3000)
2. **css**: Dart Sass watch mode
3. **js**: esbuild watch mode

**Start command**: `bin/dev`

### Production Setup

- **Database**: SQLite with separate database files
- **Job Queue**: Solid Queue (database-backed)
- **Cache**: Solid Cache (database-backed)
- **WebSockets**: Solid Cable (database-backed)
- **Monitoring**: Mission Control Jobs dashboard at `/jobs`

## Security

### Rate Limiting

- Rack::Attack middleware configured
- Protects against abuse and DoS attacks

### Authentication

- GitLab token-based authentication
- Credentials stored in Rails encrypted credentials

### HTTPS

- SSL enabled in development
- Self-signed certificates in dev environment
- Thruster handles SSL in production

## Monitoring & Observability

### Error Tracking

- **Honeybadger**: Exception monitoring and alerting
- Configured via config/honeybadger.yml

### Metrics

- **Prometheus Exporter**: Custom metrics export
- SendMetricsJob runs every 5 minutes
- Application performance metrics

### Logging

- HTTPLog for API request/response logging
- Rails logger for application logs
- Structured logging in JSON format

### Job Monitoring

- **Mission Control Jobs**: Web UI for job queue
- Available at `/jobs`
- Real-time job status and history

## Testing

### Test Framework

- **RSpec**: Primary testing framework
- **FactoryBot**: Test data factories
- **Capybara**: Integration testing
- **Selenium WebDriver**: Browser automation
- **WebMock**: HTTP request stubbing
- **Simplecov**: Code coverage

### Test Utilities

- **shoulda-matchers**: RSpec matchers
- **test-prof**: Performance profiling
- **stub_env**: Environment variable stubbing
- **rails-controller-testing**: Controller test helpers

## Development Tools

- **Rubocop**: Code linting (Standard Ruby style)
- **Brakeman**: Security vulnerability scanning
- **Lefthook**: Git hooks management
- **Debugbar**: Development debugging panel
- **Hotwire Livereload**: Auto-reload on file changes
- **Spring**: Application preloader for faster boot

## Progressive Web App (PWA)

The application includes PWA support:

- Service worker for offline capabilities
- Web app manifest for installability
- Available routes:
  - `/manifest`: PWA manifest
  - `/service-worker`: Service worker script

## Future Considerations

### Scalability

- Current SQLite setup suitable for small-medium deployments
- For larger deployments, consider:
  - PostgreSQL for primary database
  - Redis for cache and job queue
  - Separate job processing servers

### Performance

- GraphQL query optimization
- Response pagination for large datasets
- CDN for static assets

### Features

- Real-time collaboration features
- Advanced filtering and search
- Customizable dashboards
- Team analytics
