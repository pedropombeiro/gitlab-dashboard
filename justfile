default: install open server

install:
    bundle install
    yarn install

update:
    bundle update
    yarn upgrade

server:
    bin/dev

open:
    open http://localhost:3000
