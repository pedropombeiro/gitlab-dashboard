default: install
    bin/setup

install:
    mise install
    bin/setup --skip-server
    lefthook install
    yarn install

update:
    bin/spring stop
    bundle update --bundler
    bundle update
    bin/importmap update
    yarn upgrade

alias cache := toggle-cache

toggle-cache:
    bin/rails dev:cache

alias clobber := clean

clean:
    rm -rf app/assets/builds/*
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
      --arg-deploy=GIT_REPO_COMMIT_SHA:null

lint:
    rake standard
