# syntax=docker/dockerfile:1@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t demo .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name demo demo

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
# ARG RUBY_VERSION=3.4.5
# FROM ruby:$RUBY_VERSION-alpine AS base
FROM ruby:3.4.8-alpine@sha256:68dc5bd75d0e27917f60c09f055b1c33faf94d0e9cee8592b35d4134e92d04b4 AS base

# Rails app lives here
WORKDIR /rails

# Update gems and bundler
RUN gem update --system --no-document && \
  gem install -N bundler

# Install base packages
# hadolint ignore=DL3018
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
    apk update && \
    apk add --no-cache curl jemalloc sqlite tzdata

# Set production environment
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production"

############################################################################

# Throw-away build stages to reduce size of final image
FROM base AS prebuild

# Install packages needed to build gems and node modules
# hadolint ignore=DL3018
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
  apk update && \
  apk add --no-cache build-base curl gyp linux-headers openssl-dev pkgconfig yaml-dev


############################################################################

FROM prebuild AS node

# Install JavaScript dependencies
ARG NODE_VERSION=25.2.1
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-musl.tar.gz | tar xz -C /tmp/ && \
    mkdir /usr/local/node && \
    cp -rp /tmp/node-v${NODE_VERSION}-linux-x64-musl/* /usr/local/node/ && \
    /usr/local/node/bin/npm install -g corepack && \
    /usr/local/node/bin/corepack enable && \
    rm -rf /tmp/node-v${NODE_VERSION}-linux-x64-musl

# Install node modules
COPY --link package.json yarn.lock .yarnrc.yml ./
RUN --mount=type=cache,id=bld-yarn-cache,target=/root/.yarn \
    YARN_CACHE_FOLDER=/root/.yarn yarn install --immutable


############################################################################

FROM prebuild AS build

# Install application gems
COPY --link Gemfile Gemfile.lock ./
RUN --mount=type=cache,id=bld-gem-cache,sharing=locked,target=/srv/vendor \
  bundle config set app_config .bundle && \
  bundle config set path /srv/vendor && \
  bundle install --jobs 4 --retry 3 && \
  bundle exec bootsnap precompile --gemfile && \
  bundle clean && \
  mkdir -p vendor && \
  bundle config set path vendor && \
  cp -ar /srv/vendor .

# Copy node modules
COPY --from=node /rails/node_modules /rails/node_modules
COPY --from=node /usr/local/node /usr/local/node
ENV PATH=/usr/local/node/bin:$PATH

# Copy application code
COPY --link . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
# hadolint ignore=DL3059
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

############################################################################

# Final stage for app image
FROM base

# Deployment build arguments
ARG GIT_REPO_COMMIT_SHA="null"
ARG GIT_RELEASE_TAG="null"

# Install packages needed for deployment
# hadolint ignore=DL3018
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
  apk update && \
  apk add --no-cache sqlite-libs

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
ARG UID=1000 \
    GID=1000
RUN addgroup --system --gid "$GID" rails && \
    adduser --system rails --uid "$UID" --ingroup rails --home /home/rails --shell /bin/sh rails && \
    chown -R rails:rails db log storage tmp && \
    echo ${GIT_REPO_COMMIT_SHA} >./REVISION && \
    echo ${GIT_RELEASE_TAG} >./.git-release-tag
USER rails:rails

# Deployment options
ENV LD_PRELOAD="libjemalloc.so.2" \
    MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true" \
    RUBY_YJIT_ENABLE="1"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
VOLUME /rails/storage
CMD ["./bin/thrust", "./bin/rails", "server"]
