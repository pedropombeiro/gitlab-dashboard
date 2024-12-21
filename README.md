# GitLab Dashboard

GitLab Dashboard is a Ruby-based application designed to provide an intuitive and comprehensive dashboard
for managing GitLab merge requests.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
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

    or, if you have `just` installed:

    ```sh
    just install
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

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-branch`).
3. Commit your changes (`git commit -m 'Add new feature'`).
4. Push to the branch (`git push origin feature-branch`).
5. Open a Pull Request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
