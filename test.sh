#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

OUT=$SRC/out
TARGET=amd64
PORT=5000
VERSION=
IMAGE=docker.io/chromedp/headless-shell

DESC='Run a headless-shell image and check that it answers on the debugging port.'
OPTS=(
  'out|OUT|val|dir|output directory'
  'target|TARGET|val|arch|target arch'
  'port|PORT|val|port|host port to publish on'
  'version|VERSION|val|version|image version (default: newest archive in the output directory)'
  'image|IMAGE|val|name|image name'
)
parse_opts "$@"

set -e

[ -n "$VERSION" ] || VERSION=$(latest_archive_version "$OUT")

NAME=$(basename "$IMAGE")-$VERSION-$TARGET
(set -x;
  podman run \
    --name "$NAME" \
    --platform "linux/$TARGET" \
    --rm \
    --detach \
    --publish "$PORT:9222" \
    "$IMAGE:$VERSION"
)

# always stop the container, even if the check fails
trap 'podman stop "$NAME"' EXIT

sleep 3

curl -v --connect-timeout 20 --max-time 30 "http://localhost:$PORT/json/version"
