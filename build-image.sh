#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

OUT=$SRC/out
TARGETS=()
TAGS=()
VERSION=
PUSH=0
IMAGE=docker.io/chromedp/headless-shell
DOCKER_USER=kenshaw
DOCKER_PASSFILE=$HOME/.config/headless-shell/token

DESC='Build per-arch container images from the packaged archives, and assemble
(and optionally push) a multi-arch manifest for each tag.'
OPTS=(
  'out|OUT|val|dir|output directory'
  'target|TARGETS|list|arch|target arch (repeatable; default: every arch with an archive for the version)'
  'tag|TAGS|list|tag|extra tag for the manifest (repeatable; the version is always tagged)'
  'version|VERSION|val|version|version to build (default: newest archive in the output directory)'
  'push|PUSH|flag|1|push manifests to the registry'
  'image|IMAGE|val|name|image name'
  'docker-user|DOCKER_USER|val|user|registry user'
  'docker-passfile|DOCKER_PASSFILE|val|file|file containing the registry password or token'
)
parse_opts "$@"

set -e

# check out dir
[ -d "$OUT" ] || die "$OUT does not exist!"

# determine version
[ -n "$VERSION" ] || VERSION=$(latest_archive_version "$OUT")

# determine targets
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=($(ls "$OUT"/*-"${VERSION}"-*.bz2|sed -e 's/.*headless-shell-[0-9.]\+-\([a-z0-9]\+\)\.tar\.bz2$/\1/'|xargs))
fi

echo "VERSION:  $VERSION [${TARGETS[*]}]"
echo "IMAGE:    $IMAGE [tags: $(join_by ' ' "$VERSION" "${TAGS[@]}")]"

IMAGES=()
for TARGET in "${TARGETS[@]}"; do
  NAME=localhost/$(basename "$IMAGE"):$VERSION-$TARGET
  IMAGES+=("$NAME")

  if [ -n "$(buildah images --noheading --filter=reference="$NAME")" ]; then
    echo -e "\n\nSKIPPING BUILD FOR $NAME ($(date))"
    continue
  fi

  echo -e "\n\nBUILDING $NAME ($(date))"
  ARCHIVE=$OUT/headless-shell-$VERSION-$TARGET.tar.bz2
  [ -f "$ARCHIVE" ] || die "$ARCHIVE is missing!"
  (set -x;
    rm -rf "$OUT/$VERSION-$TARGET"
    mkdir -p "$OUT/$VERSION-$TARGET"
    tar -C "$OUT/$VERSION-$TARGET" -jxf "$ARCHIVE"

    buildah build \
      --platform "linux/$TARGET" \
      --build-arg VERSION="$VERSION-$TARGET" \
      --tag "$NAME" \
      "$SRC"
  )
done

if [ "$PUSH" -eq 1 ]; then
  [ -r "$DOCKER_PASSFILE" ] || die "$DOCKER_PASSFILE is not readable"
  (set -x;
    buildah login docker.io \
      --username "$DOCKER_USER" \
      --password-stdin < "$DOCKER_PASSFILE"
  )
fi

# push latest last, so that it is the most recently pushed tag, and is listed
# first on the registry
ORDERED=("$VERSION")
for TAG in "${TAGS[@]}"; do
  [ "$TAG" = latest ] || ORDERED+=("$TAG")
done
for TAG in "${TAGS[@]}"; do
  [ "$TAG" != latest ] || ORDERED+=("$TAG")
done

REPO=$(sed -e 's%^docker\.io/%%' <<< "$IMAGE")
for TAG in "${ORDERED[@]}"; do
  NAME=localhost/$(basename "$IMAGE"):$TAG

  # create manifest
  echo -e "\n\nCONFIGURING MANIFEST $NAME ($(date))"
  if buildah manifest exists "$NAME"; then
    for HASH in $(buildah manifest inspect "$NAME"|jq -r '.manifests[]|.digest'); do
      (set -x;
        buildah manifest remove "$NAME" "$HASH"
      )
    done
  else
    (set -x;
      buildah manifest create "$NAME"
    )
  fi

  # add images
  for IMG in "${IMAGES[@]}"; do
    (set -x;
      buildah manifest add "$NAME" "$IMG"
    )
  done

  if [ "$PUSH" -eq 1 ]; then
    echo -e "\n\nPUSHING MANIFEST $NAME ($(date))"
    (set -x;
      buildah manifest push \
        --all \
        "$NAME" \
        "docker://$REPO:$TAG"
    )
  fi
done
