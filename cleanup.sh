#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

OUT=$SRC/out
IMAGE=docker.io/chromedp/headless-shell
CHANNELS=()
VERSIONS=()
DAYS=90

DESC='Remove old archives and extracted directories from the output directory, and
remove stale containers and images. The given versions and channels are kept.'
OPTS=(
  'out|OUT|val|dir|output directory'
  'image|IMAGE|val|name|image name'
  'channel|CHANNELS|list|name|channel to keep (repeatable; default: stable)'
  'version|VERSIONS|list|version|version to keep (repeatable; default: latest of each channel)'
  'days|DAYS|val|n|remove files and directories older than n days'
)
parse_opts "$@"

set -e

[ ${#CHANNELS[@]} -gt 0 ] || CHANNELS=(stable)

if [ ${#VERSIONS[@]} -eq 0 ]; then
  for CHANNEL in "${CHANNELS[@]}"; do
    VERSIONS+=("$(latest_version "$CHANNEL")")
  done
fi

echo -e "KEEP: $(join_by ', ' latest "${CHANNELS[@]}" "${VERSIONS[@]}")"

# cleanup old directories and files
if [ -d "$OUT" ]; then
  REGEX=".*($(join_by '|' "${VERSIONS[@]}")).*"
  (set -x;
    find "$OUT" \
      -mindepth 1 \
      -maxdepth 1 \
      -regextype posix-extended \
      \( \
        -type d  \
        -regex '.*/[0-9]+(\.[0-9]+){3}-(amd64|arm64)$' \
        -or  \
        -type f \
        -regex '.*/headless-shell-[0-9]+(\.[0-9]+){3}-(amd64|arm64)\.tar\.bz2$' \
      \) \
      -mtime "+$DAYS" \
      -not \
      -regex "$REGEX" \
      -exec echo REMOVING {} \; \
      -exec rm -rf {} \;
  )
fi

# remove containers
CONTAINERS=$(
  podman container ls \
    --filter=ancestor="$IMAGE" \
    --filter=status=exited \
    --filter=status=created \
    --quiet
)
if [ -n "$CONTAINERS" ]; then
  (set -x;
    podman container rm --force $CONTAINERS
  )
fi

# remove images
IMAGES=$(
  podman images \
    --noheading \
    --filter=reference="$IMAGE" \
    --filter=reference="localhost/$(basename "$IMAGE")" \
    |grep -Ev "($(join_by '|' latest "${CHANNELS[@]}" "${VERSIONS[@]}"))" \
    |awk '{print $3}' \
    || true
)
if [ -n "$IMAGES" ]; then
  (set -x;
    podman rmi --force $IMAGES
  )
fi
