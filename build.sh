#!/bin/bash

# cp headless-shell.{service,timer} $HOME/.config/systemd/user
# sudo loginctl enable-linger $USER
# systemctl daemon-reload --user
# systemctl enable --user headless-shell.timer

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
SRCDIR=
ATTEMPTS=10
CLEANUP=1
JOBS=$((`nproc` + 2))
JOBFAIL=30
DRYRUN=
UPDATE=
CHANNELS="stable beta dev"
TARGETS="amd64 arm64"
IMAGE=docker.io/chromedp/headless-shell
URL='https://hub.docker.com/layers/chromedp/headless-shell/%s/images/sha256-%s?context=explore'

OPTIND=1
while getopts "o:s:da:j:k:nuc:t:i:l:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  s) SRCDIR=$OPTARG ;;
  d) CLEANUP=0 ;;
  a) ATTEMPTS=$OPTARG ;;
  j) JOBS=$OPTARG ;;
  k) JOBFAIL=$OPTARG ;;
  n) DRYRUN=-n ;;
  u) UPDATE=-u ;;
  c) CHANNELS=$OPTARG ;;
  t) TARGETS=$OPTARG ;;
  i) IMAGE=$OPTARG ;;
  l) URL=$OPTARG ;;
esac
done

# determine source dir
if [ -z "$SRCDIR" ]; then
  if [ -d /media/src ]; then
    SRCDIR=/media/src
  else
    SRCDIR=$OUT
  fi
fi

set -e

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

# retrieve channel versions
declare -A VERSIONS
for CHANNEL in $CHANNELS; do
  VERSIONS[$CHANNEL]=$(verhist -platform win64 -channel "$CHANNEL" -latest)
done

# order channels low -> high
CHANNELS_ORDER=$(
  for i in ${!VERSIONS[@]}; do
    echo "${VERSIONS[$i]}:::$i"
  done | sort -V | awk -F::: '{print $2}'
)

# display channel builds
echo -n "BUILDING:"
i=0
for CHANNEL in $CHANNELS_ORDER; do
  if [ "$i" != "0" ]; then
    echo -n ","
  fi
  echo -n " $CHANNEL (${VERSIONS[$CHANNEL]})"
  i=$((i+1))
done
echo

#if [ "$CLEANUP" = "1" ]; then
#  echo "CLEANUP ($(date))"
#  $SRC/cleanup.sh -o "$OUT" -c "${CHANNELS[@]}" -v "${VERSIONS[@]}"
#  echo "ENDED CLEANUP ($(date))"
#fi

# build
for CHANNEL in $CHANNELS_ORDER; do
  VERSION=${VERSIONS[$CHANNEL]}

  # skip build if archive already exists
  if [[ -f $OUT/headless-shell-$VERSION-amd64.tar.bz2 && -f $OUT/headless-shell-$VERSION-arm64.tar.bz2 ]]; then
    echo -e "\n\nSKIPPING BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
    continue
  fi

  # build
  echo -e "\n\nSTARTING BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  RET=1
  ./build-headless-shell.sh \
    -o $OUT \
    -s $SRCDIR \
    -c $CHANNEL \
    -a $ATTEMPTS \
    -j $JOBS \
    -k $JOBFAIL \
    $DRYRUN \
    $UPDATE \
    -t "$TARGETS" \
    -v $VERSION \
  && RET=$?
  if [ $RET -ne 0 ]; then
    echo "COULD NOT BUILD $CHANNEL $VERSION ($(date))"
  fi
  echo "ENDED BUILD FOR $CHANNEL $VERSION ($(date))"
done

# publish binary (stable only)
#if [[ "$CHANNELS" =~ stable ]]; then
#  for TARGET in $TARGETS; do
#    ARCHIVE=$OUT/headless-shell-${VERSIONS[stable]}-$TARGET.tar.bz2
#    if [ ! -f $ARCHIVE ]; then
#      echo "MISSING $ARCHIVE, SKIPPING PUBLISH ($(date))"
#    else
#      if [ -f $ARCHIVE.published ]; then
#        echo "SKIPPING PUBLISH $ARCHIVE ($(date))"
#      else
#        echo "STARTING PUBLISH FOR $ARCHIVE ($(date))"
#        #ID=$(mmfile "$ARCHIVE"|jq -r '.file_infos[0].id')
#        #mmpost 'Built headless-shell `stable` (`'${VERSIONS[stable]}'`)' "$ID"
#        touch $ARCHIVE.published
#        echo -e "\nENDED PUBLISH ($(date))"
#      fi
#    fi
#  done
#fi

# update base image
BASEIMAGE=$(grep 'FROM' Dockerfile|awk '{print $2}')
echo -e "\n\nPULLING $BASEIMAGE [$TARGETS] ($(date))"
for TARGET in $TARGETS; do
  (set -x;
    buildah pull \
      --platform linux/$TARGET \
      $BASEIMAGE
  )
done

# build images
for CHANNEL in $CHANNELS_ORDER; do
  VERSION=${VERSIONS[$CHANNEL]}
  TAGS=($CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  echo -e "\n\nSTARTING IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  ./build-image.sh \
    -o $OUT \
    -t "$TARGETS" \
    -g "${TAGS[@]}" \
    -v "$VERSION" \
    -i "$IMAGE" \
    -p
  echo "ENDED IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

# push images
for CHANNEL in $CHANNELS_ORDER; do
#  VERSION=${VERSIONS[$CHANNEL]}
#  ARCHIVE=$OUT/headless-shell-$VERSION.tar.bz2
#  TAGS=($VERSION $CHANNEL)
#  if [ "$CHANNEL" = "stable" ]; then
#    TAGS+=(latest)
#  fi
#  if [ ! -f $ARCHIVE ]; then
#    echo "MISSING ARCHIVE FOR CHANNEL $CHANNEL $VERSION, SKIPPING PUSH"
#    continue
#  fi
#  if [ -f $ARCHIVE.pushed ]; then
#    echo "SKIPPING PUSH FOR CHANNEL $CHANNEL $VERSION"
#    continue
#  fi
#  echo "STARTING PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
#  for TAG in ${TAGS[@]}; do
#    (set -x;
#      podman push $IMAGE:$TAG
#    )
#  done
#  touch $ARCHIVE.pushed

  # notify
  HASH=$(podman inspect --format='{{index .RepoDigests 0}}' $IMAGE:$VERSION|awk -F: '{print $2}')
  LINK=$(printf "$URL" "$VERSION" "$HASH")
  TAGTEXT=""
  for TAG in ${TAGS[@]}; do
    TAGTEXT+='`'$TAG'`, '
  done
  #mmpost "Pushed $IMAGE ($(sed -e 's/, $//' <<< "$TAGTEXT")) to: [$IMAGE:$VERSION]($LINK)"

  echo -e "\nENDED PUSH FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

echo "DONE ($(date))"

popd &> /dev/null
