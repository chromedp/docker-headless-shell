#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

OUT=$SRC/out
SRCDIR=
ATTEMPTS=10
JOBS=$(($(nproc) + 2))
JOBFAIL=30
DRYRUN=
UPDATE=
CHANNELS=()
TARGETS=()
PUSH=
IMAGE=docker.io/chromedp/headless-shell

DESC='Build headless-shell for each channel, package it into container images, and
optionally push them. Channels default to stable, beta and dev; targets default
to amd64 and arm64.'
OPTS=(
  'out|OUT|val|dir|output directory'
  'src|SRCDIR|val|dir|directory containing chromium/src (default: /media/src if present, else the output directory)'
  'attempts|ATTEMPTS|val|n|ninja attempts per target'
  'jobs|JOBS|val|n|ninja jobs'
  'job-fail|JOBFAIL|val|n|ninja failures to tolerate (-k)'
  'dry-run|DRYRUN|flag|--dry-run|pass a dry run to ninja'
  'update|UPDATE|flag|--update|force an update of depot_tools and the chromium tree'
  'channel|CHANNELS|list|name|channel to build (repeatable; default: stable beta dev)'
  'target|TARGETS|list|arch|target arch to build (repeatable; default: amd64 arm64)'
  'push|PUSH|flag|--push|push images to the registry'
  'image|IMAGE|val|name|image name'
)
parse_opts "$@"

set -e

[ -n "$SRCDIR" ] || SRCDIR=$(default_srcdir "$OUT")
[ ${#CHANNELS[@]} -gt 0 ] || CHANNELS=(stable beta dev)
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(amd64 arm64)

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

# fail early, before the long build, if the host is not usable
need git jq curl verhist buildah podman
git lfs version &> /dev/null || die "git-lfs is not installed (needed by chromium's third_party/litert)"
podman info &> /dev/null || die "podman is not working: $(podman info 2>&1 | tail -n 1)"

# determine versions
declare -A VERSIONS
for CHANNEL in "${CHANNELS[@]}"; do
  VERSIONS[$CHANNEL]=$(latest_version "$CHANNEL")
done

# order channels low -> high
CHANNELS_ORDER=$(
  for i in "${!VERSIONS[@]}"; do
    echo "${VERSIONS[$i]}:::$i"
  done | sort -V | awk -F::: '{print $2}' |xargs
)

channels() {
  local s=()
  for CHANNEL in $CHANNELS_ORDER; do
    s+=("$CHANNEL:${VERSIONS[$CHANNEL]}")
  done
  join_by ' ' "${s[@]}"
}

echo "BUILDING: $(channels) [${TARGETS[*]}]"

# housekeeping must not stop the build
echo -e "\n\nCLEANUP ($(date))"
args_for CHANNEL_ARGS --channel "${CHANNELS[@]}"
args_for VERSION_ARGS --version "${VERSIONS[@]}"
"$SRC/cleanup.sh" \
  --out "$OUT" \
  --image "$IMAGE" \
  "${CHANNEL_ARGS[@]}" \
  "${VERSION_ARGS[@]}" \
  || echo "WARNING: CLEANUP FAILED ($(date))"
echo "ENDED CLEANUP ($(date))"

FAILED=()

# archives_exist VERSION: true if an archive exists for every target
archives_exist() {
  local t
  for t in "${TARGETS[@]}"; do
    [ -f "$OUT/headless-shell-$1-$t.tar.bz2" ] || return 1
  done
}

# build
args_for TARGET_ARGS --target "${TARGETS[@]}"
for CHANNEL in $CHANNELS_ORDER; do
  VERSION=${VERSIONS[$CHANNEL]}

  # skip build if archives already exist
  if archives_exist "$VERSION"; then
    echo -e "\n\nSKIPPING BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
    continue
  fi

  echo -e "\n\nSTARTING BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  if ! "$SRC/build-headless-shell.sh" \
    --out "$OUT" \
    --src "$SRCDIR" \
    --channel "$CHANNEL" \
    --attempts "$ATTEMPTS" \
    --jobs "$JOBS" \
    --job-fail "$JOBFAIL" \
    $DRYRUN \
    $UPDATE \
    "${TARGET_ARGS[@]}" \
    --version "$VERSION"; then
    echo "COULD NOT BUILD $CHANNEL $VERSION ($(date))"
    FAILED+=("build:$CHANNEL:$VERSION")
  fi
  echo "ENDED BUILD FOR $CHANNEL $VERSION ($(date))"
done

# build images
for CHANNEL in $CHANNELS_ORDER; do
  VERSION=${VERSIONS[$CHANNEL]}

  # a failed build for one channel must not block the others
  if ! archives_exist "$VERSION"; then
    echo -e "\n\nSKIPPING IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION: ARCHIVES MISSING ($(date))"
    continue
  fi

  TAGS=("$CHANNEL")
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  args_for TAG_ARGS --tag "${TAGS[@]}"

  echo -e "\n\nSTARTING IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  if ! "$SRC/build-image.sh" \
    --out "$OUT" \
    "${TARGET_ARGS[@]}" \
    "${TAG_ARGS[@]}" \
    --version "$VERSION" \
    --image "$IMAGE" \
    $PUSH; then
    echo "COULD NOT BUILD IMAGE FOR $CHANNEL $VERSION ($(date))"
    FAILED+=("image:$CHANNEL:$VERSION")
  fi
  echo "ENDED IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "\n\nFAILED: ${FAILED[*]} ($(date))"
  exit 1
fi

echo "DONE ($(date))"
