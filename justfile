default: install
  bin/setup

install:
    bin/setup --skip-server
    yarn install

update:
    bundle update
    yarn upgrade

serve:
    bin/dev

open:
    open http://localhost:3000
