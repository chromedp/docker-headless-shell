#!/bin/bash

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
TARGETS=()
TAGS=()
VERSION=
PUSH=0
IMAGE=docker.io/chromedp/headless-shell

OPTIND=1
while getopts "o:t:g:v:pi:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  t) TARGETS+=($OPTARG) ;;
  g) TAGS+=($OPTARG) ;;
  v) VERSION=$OPTARG ;;
  p) PUSH=1 ;;
  i) IMAGE=$OPTARG ;;
esac
done

set -e

# check out dir
if [ ! -d $OUT ]; then
  echo "$OUT does not exist!"
  exit 1
fi

# determine version
if [ -z "$VERSION" ]; then
  VERSION=$(ls $OUT/*.bz2|sort -r -V|head -1|sed -e 's/.*headless-shell-\([0-9\.]\+\).*/\1/')
fi

# determine targets
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=($(ls $OUT/*-${VERSION}-*.bz2|sed -e 's/.*headless-shell-[0-9\.]\+-\([a-z0-9]\+\).*/\1/'|xargs))
fi

# join_by ',' ${A[@]} ${B[@]}
join_by() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

echo "VERSION:  $VERSION [${TARGETS[@]}]"
echo "IMAGE:    $IMAGE [tags: $(join_by ' ' $VERSION ${TAGS[@]})]"

IMAGES=()
for TARGET in ${TARGETS[@]}; do
  NAME=localhost/$(basename $IMAGE):$VERSION-$TARGET
  IMAGES+=($NAME)

  if [ ! -z "$(buildah images --noheading --filter=reference=$NAME)" ]; then
    echo -e "\n\nSKIPPING BUILD FOR $NAME ($(date))"
    continue
  fi

  echo -e "\n\nBUILDING $NAME ($(date))"
  ARCHIVE=$OUT/headless-shell-$VERSION-$TARGET.tar.bz2
  if [ ! -f $ARCHIVE ]; then
    echo "ERROR: $ARCHIVE is missing!"
    exit 1
  fi
  (set -x;
    rm -rf $OUT/$VERSION-$TARGET
    mkdir -p $OUT/$VERSION-$TARGET
    tar -C $OUT/$VERSION-$TARGET -jxf $ARCHIVE

    buildah build \
      --platform linux/$TARGET \
      --build-arg VERSION="$VERSION-$TARGET" \
      --tag $NAME \
      $SRC
  )
done

REPO=$(sed -e 's%^docker\.io/%%' <<< "$IMAGE")
for TAG in $VERSION ${TAGS[@]}; do
  NAME=localhost/$(basename $IMAGE):$TAG

  # create manifest
  echo -e "\n\nCONFIGURING MANIFEST $NAME ($(date))"
  if `buildah manifest exists $NAME`; then
    for HASH in $(buildah manifest inspect $NAME|jq -r '.manifests[]|.digest'); do
      (set -x;
        buildah manifest remove $NAME $HASH
      )
    done
  else
    (set -x;
      buildah manifest create $NAME
    )
  fi

  # add images
  for IMG in ${IMAGES[@]}; do
    (set -x;
      buildah manifest add $NAME $IMG
    )
  done

  if [ $PUSH -eq 1 ]; then
    echo -e "\n\nPUSHING MANIFEST $NAME ($(date))"
    (set -x;
      buildah manifest push \
        --all \
        $NAME \
        docker://$REPO:$TAG
    )
  fi
done
