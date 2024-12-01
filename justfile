default: install
    bin/setup

install:
    bin/setup --skip-server
    yarn install

update:
    bundle update --bundler
    bundle update
    yarn upgrade

alias cache := toggle-cache

toggle-cache:
    bin/rails dev:cache

alias clobber := clean

clean:
    bin/rails assets:clobber dartsass:clobber javascript:clobber

alias dev := serve

serve:
    bin/dev

open:
    open https://localhost:3000

test *args:
    bundle exec rspec {{args}}

watch-ci:
    gh run watch --repo=pedropombeiro/gitlab-dashboard

build-docker *args:
    docker buildx build --platform linux/amd64 -t $(basename $(pwd)) {{args}} .

create-dockerfile:
    bin/rails generate dockerfile \
      --alpine --cache --compose --jemalloc --link --no-ci --parallel --sqlite3 --yjit \
      --add-build linux-headers openssl-dev \
      --arg-base=GIT_REPO_COMMIT_SHA:null

lint:
    rake standard:fix
