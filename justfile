# Modern justfile for gitlab-dashboard
# Run `just --list` to see all available recipes
# ------------------------------------------------------------------------------
# Settings
# ------------------------------------------------------------------------------

set dotenv-load := true

# Auto-load .env files

set positional-arguments := true

# Enable $1, $2, etc. in recipes

set quiet := true

# Don't echo recipes before running
# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

project_name := `basename $(pwd)`

# ------------------------------------------------------------------------------
# Default & Setup
# ------------------------------------------------------------------------------

# Run full project setup
default: install

# Install all dependencies and configure the project
install:
    mise install
    bin/setup --skip-server
    lefthook install
    yarn install

# Update all dependencies (Ruby gems and JS packages)
update:
    bin/spring stop
    bundle update --all
    yarn up

# ------------------------------------------------------------------------------
# Development
# ------------------------------------------------------------------------------

# Start the development server
[group('dev')]
serve:
    bin/dev

alias dev := serve

# Open the app in the browser
[group('dev')]
open:
    open https://localhost:3000

# Toggle Rails development caching
[group('dev')]
toggle-cache:
    bin/rails dev:cache

alias cache := toggle-cache

# Open Rails console
[group('dev')]
console:
    bin/rails console

# Show all routes (optionally filter with PATTERN)
[group('dev')]
routes pattern='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ pattern }}" ]; then
        bin/rails routes -g "{{ pattern }}"
    else
        bin/rails routes
    fi

# Tail development logs (use `just logs production` for other envs)
[group('dev')]
logs env='development':
    tail -f log/{{ env }}.log

# ------------------------------------------------------------------------------
# Testing & Quality
# ------------------------------------------------------------------------------

# Run RSpec tests (pass additional args as needed)
[group('test')]
test *args:
    bundle exec rspec "$@"

# Run pre-commit hooks to fix files (optionally specify FILES)
[group('test')]
fix *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ $# -gt 0 ]; then
        lefthook run pre-commit --files "$@" --force
    else
        lefthook run pre-commit --all-files --force
    fi

# Run pre-push linting hooks (optionally specify FILES)
[group('test')]
lint *files:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ $# -gt 0 ]; then
        lefthook run pre-push --files "$@" --force
    else
        lefthook run pre-push --all-files --force
    fi

# Watch GitHub Actions CI run
[group('test')]
watch-ci:
    gh run watch --repo=pedropombeiro/gitlab-dashboard

# ------------------------------------------------------------------------------
# Build & Deploy
# ------------------------------------------------------------------------------

# Build Docker image for linux/amd64
[group('build')]
build-docker *args:
    docker buildx build --platform linux/amd64 -t {{ project_name }} "$@" .

# Regenerate Dockerfile using Rails generator
[group('build')]
create-dockerfile:
    bin/rails generate dockerfile \
        --alpine --cache --compose --jemalloc --link --no-ci --parallel --sqlite3 --yjit \
        --add-build linux-headers openssl-dev \
        --arg-deploy=GIT_REPO_COMMIT_SHA:null \
        --arg-deploy=GIT_RELEASE_TAG:null

# ------------------------------------------------------------------------------
# Maintenance
# ------------------------------------------------------------------------------

# Clean all build artifacts (requires confirmation)
[confirm("This will delete all build artifacts. Continue?")]
[group('maintenance')]
clean:
    rm -rf app/assets/builds/*
    bin/rails assets:clobber dartsass:clobber javascript:clobber

alias clobber := clean

# Dump GitLab GraphQL schema to local files
[group('maintenance')]
dump-schema:
    rails -e 'require("graphlient"); client = Graphlient::Client.new("https://gitlab.com/api/graphql", schema_path: "lib/assets/graphql/gitlab_graphql_schema.json"); client.schema.dump!'
    cp -f lib/assets/graphql/gitlab_graphql_schema.json spec/support/fixtures/gitlab_graphql_schema.json
