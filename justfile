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

test:
    bundle exec rspec

watch-ci:
    gh run watch --repo=pedropombeiro/gitlab-dashboard

build-docker:
    docker buildx build --platform linux/amd64 -t $(basename $(pwd)) .

create-dockerfile:
    bin/rails generate dockerfile \
      --alpine --cache --ci --jemalloc --link --parallel --sqlite3 --thruster --yjit \
      --add-build linux-headers openssl-dev \
      --add-deploy git

lint:
    rake standard:fix
