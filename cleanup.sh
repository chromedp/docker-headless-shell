#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
IMAGE=docker.io/chromedp/headless-shell
CHANNELS=()
VERSIONS=()
MTIME=90

OPTIND=1
while getopts "o:i:c:v:m:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  i) IMAGE=$OPTARG ;;
  c) CHANNELS+=($OPTARG) ;;
  v) VERSIONS+=($OPTARG) ;;
  m) MTIME=$OPTARG ;;
esac
done

set -e

if [ ${#CHANNELS[@]} -eq 0 ]; then
  CHANNELS=(stable)
fi

if [ ${#VERSIONS[@]} -eq 0 ]; then
  for CHANNEL in ${CHANNELS[@]}; do
    VERSIONS+=($(verhist -platform win64 -channel "$CHANNEL" -latest))
  done
fi

# join_by ',' ${A[@]} ${B[@]}
join_by() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

echo -e "KEEP: $(join_by ', ' latest ${CHANNELS[@]} ${VERSIONS[@]})"

# cleanup old directories and files
if [ -d $OUT ]; then
  REGEX=".*($(join_by '|' ${VERSIONS[@]})).*"
  (set -x;
    find $OUT \
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
      -mtime $MTIME \
      -not \
      -regex "$REGEX" \
      -exec echo REMOVING {} \; \
      -exec rm -rf {} \;
  )
fi

# remove containers
CONTAINERS=$(
  podman container ls \
    --filter=ancestor=$IMAGE \
    --filter=status=exited \
    --filter=status=created \
  --quiet
)
if [ ! -z "$CONTAINERS" ]; then
  (set -x;
    podman container rm --force $CONTAINERS
  )
fi

# remove images
IMAGES=$(
  podman images \
    --filter=reference=$IMAGE \
    --filter=reference=localhost/$(basename $IMAGE) \
    |sed 1d \
    |grep -Ev "($(join_by '|' latest ${CHANNELS[@]} ${VERSIONS[@]}))" \
    |awk '{print $3}'
)
if [ ! -z "$IMAGES" ]; then
  (set -x;
    podman rmi --force $IMAGES
  )
fi
