# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.6
FROM ruby:$RUBY_VERSION-alpine AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV BUNDLE_DEPLOYMENT="1" \
  BUNDLE_PATH="/usr/local/bundle" \
  BUNDLE_WITHOUT="development" \
  RAILS_ENV="production"

# Update gems and bundler
RUN gem update --system --no-document && \
  gem install -N bundler

# Install packages
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
  apk update && \
  apk add tzdata


# Throw-away build stages to reduce size of final image
FROM base AS prebuild

# Install packages needed to build gems and node modules
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
  apk update && \
  apk add build-base curl gyp linux-headers openssl-dev pkgconfig python3


FROM prebuild AS node

# Install JavaScript dependencies
ARG NODE_VERSION=23.1.0
ARG YARN_VERSION=1.22.19+sha1.4ba7fc5c6e704fce2066ecbfb0b0d8976fe62447
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-musl.tar.gz | tar xz -C /tmp/ && \
  mkdir /usr/local/node && \
  cp -rp /tmp/node-v${NODE_VERSION}-linux-x64-musl/* /usr/local/node/ && \
  npm install -g yarn@$YARN_VERSION && \
  rm -rf /tmp/node-v${NODE_VERSION}-linux-x64-musl

# Install node modules
COPY package.json yarn.lock ./
RUN --mount=type=cache,id=bld-yarn-cache,target=/root/.yarn \
  YARN_CACHE_FOLDER=/root/.yarn yarn install --frozen-lockfile


FROM prebuild AS build

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,id=bld-gem-cache,sharing=locked,target=/srv/vendor \
  bundle config set app_config .bundle && \
  bundle config set path /srv/vendor && \
  bundle install && \
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
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN --mount=type=cache,id=dev-apk-cache,sharing=locked,target=/var/cache/apk \
  apk update && \
  apk add curl git jemalloc sqlite-dev sqlite-libs

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN addgroup --system --gid 1000 rails && \
  adduser --system rails --uid 1000 --ingroup rails --home /home/rails --shell /bin/sh rails && \
  mkdir /data && \
  chown -R 1000:1000 db log storage tmp /data
USER 1000:1000

# Deployment options
ENV DATABASE_URL="sqlite3:///data/production.sqlite3" \
  LD_PRELOAD="libjemalloc.so.2" \
  MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true" \
  RUBY_YJIT_ENABLE="1"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 80
VOLUME /data
CMD ["bundle", "exec", "thrust", "./bin/rails", "server"]
