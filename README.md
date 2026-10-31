# GitLab Dashboard

GitLab Dashboard is a Ruby-based application designed to provide an intuitive and comprehensive dashboard
for managing GitLab merge requests.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Container secrets](#container-secrets)
- [Observability](#observability)
- [License](#license)

## Features

- Visualize GitLab merge requests, review progress, and deployment progress.

## Installation

### Prerequisites

- Ruby version: 4.0.0 or higher
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

## Container secrets

The container image (`ghcr.io/pedropombeiro/gitlab-dashboard`) reads configuration from environment
variables, such as `DATABASE_URL`, `RAILS_MASTER_KEY`, `GITLAB_TOKEN`, and `HONEYBADGER_API_KEY`. To keep
secrets out of `docker inspect`, you can store any of these variables in a file instead. Set `NAME_FILE` to the
file's path, and the image exports the file contents as `NAME`. This is the same convention that the official
Postgres image uses, and it works with [Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/):

```yaml
services:
  webserver:
    image: ghcr.io/pedropombeiro/gitlab-dashboard
    environment:
      DATABASE_URL_FILE: /run/secrets/gitlab_dashboard_database_url
      RAILS_MASTER_KEY_FILE: /run/secrets/gitlab_dashboard_rails_master_key
    secrets:
      - gitlab_dashboard_database_url
      - gitlab_dashboard_rails_master_key
secrets:
  gitlab_dashboard_database_url:
    file: ../../secrets/gitlab_dashboard_database_url
  gitlab_dashboard_rails_master_key:
    file: ../../secrets/gitlab_dashboard_rails_master_key
```

The image's entrypoint, [`bin/with-file-env`](bin/with-file-env), loads the files before it runs the command,
so this works for the default command and for overridden commands such as `bin/jobs start`. It works like this:

- It strips trailing newlines from the file contents, as `$(cat file)` does.
- It unsets `NAME_FILE` after it exports `NAME`.
- It exits with an error if both `NAME` and `NAME_FILE` are set, even to an empty string. Unset one of them
  instead of setting it to an empty value.
- It exits with an error if the file can't be read, including when `NAME_FILE` is empty, or if the file contains
  a NUL byte.
- Error messages name the variable and the path, but never the value.

The container runs as UID 1000, so make sure that user can read the secret files. Any variable that ends in
`_FILE` follows this convention, so don't pass variables such as `SSL_CERT_FILE` to the container.

`docker exec` doesn't run the entrypoint. To load the secrets in a one-off command, run it through the wrapper:

```sh
docker exec -it <container> bin/with-file-env bin/rails console
```

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
