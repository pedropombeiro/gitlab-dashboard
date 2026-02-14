# GitLab Dashboard

GitLab Dashboard is a Ruby-based application designed to provide an intuitive and comprehensive dashboard
for managing GitLab merge requests.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Observability](#observability)
- [License](#license)

## Features

- Visualize GitLab merge requests, review progress, and deployment progress.

## Installation

### Prerequisites

- Ruby version: 3.0.0 or higher
- System dependencies: Ensure you have Git and Node.js installed

### Setup

1. Clone the repository:

   ```sh
   git clone https://github.com/pedropombeiro/gitlab-dashboard.git
   cd gitlab-dashboard
   ```

2. Install dependencies:

   ```sh
   bundle install
   npm install
   ```

   or, using mise:

   ```sh
   mise run install
   ```

3. Create and initialize the database:

   ```sh
   rails db:create
   rails db:migrate
   rails db:seed
   ```

## Usage

Run the application locally:

```sh
bin/dev
```

Access the application at `http://localhost:3000`.

## Observability

This project includes OpenTelemetry instrumentation for distributed tracing, metrics, and logs correlation.

### Quick Start (Local Development)

Start the full observability stack with Docker Compose:

```sh
docker compose up
```

This starts the application along with:

- **Grafana**: <http://localhost:3001> (admin/admin)
- **Prometheus**: <http://localhost:9090>
- **Tempo**: Trace storage (accessed via Grafana)
- **Loki**: Log aggregation (accessed via Grafana)

A pre-configured Rails dashboard is automatically available in Grafana.

For detailed setup instructions, configuration options, and production deployment, see [docs/observability.md](docs/observability.md).

For planned improvements and enhancement ideas, see [docs/observability-roadmap.md](docs/observability-roadmap.md).

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-branch`).
3. Commit your changes (`git commit -m 'Add new feature'`).
4. Push to the branch (`git push origin feature-branch`).
5. Open a Pull Request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
