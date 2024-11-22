default: install
  bin/setup

install:
    bin/setup --skip-server
    yarn install

update:
    bundle update --bundler
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

watch-ci:
  gh run watch --repo=pedropombeiro/gitlab-dashboard

build-docker:
  docker build -t $(basename $(pwd)) .

lint:
  rake standard:fix
