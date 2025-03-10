#!/bin/bash

set -ex

exec socat TCP4-LISTEN:9222,fork TCP4:127.0.0.1:9223 &

exec /headless-shell/headless-shell \
  --no-sandbox \
  --use-gl=angle \
  --use-angle=swiftshader \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9223 \
  $@
