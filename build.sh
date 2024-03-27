#!/bin/bash

# cp headless-shell.{service,timer} $HOME/.config/systemd/user
# sudo loginctl enable-linger $USER
# systemctl daemon-reload --user
# systemctl enable --user headless-shell.timer

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

OUT=$SRC/out
SRCDIR=
ATTEMPTS=10
JOBS=$((`nproc` + 2))
JOBFAIL=30
DRYRUN=
UPDATE=
CHANNELS=()
TARGETS=()
PUSH=
IMAGE=docker.io/chromedp/headless-shell
URL='https://hub.docker.com/layers/chromedp/headless-shell/%s/images/sha256-%s?context=explore'

OPTIND=1
while getopts "o:s:a:j:k:nuc:t:pi:l:" opt; do
case "$opt" in
  o) OUT=$OPTARG ;;
  s) SRCDIR=$OPTARG ;;
  a) ATTEMPTS=$OPTARG ;;
  j) JOBS=$OPTARG ;;
  k) JOBFAIL=$OPTARG ;;
  n) DRYRUN=-n ;;
  u) UPDATE=-u ;;
  c) CHANNELS+=($OPTARG) ;;
  t) TARGETS+=($OPTARG) ;;
  p) PUSH=-p ;;
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

# determine channels
if [ ${#CHANNELS[@]} -eq 0 ]; then
  CHANNELS=(stable beta dev)
fi

# determine targets
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(amd64 arm64)
fi

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

# determine versions
declare -A VERSIONS
for CHANNEL in ${CHANNELS[@]}; do
  VERSIONS[$CHANNEL]=$(verhist -platform win64 -channel "$CHANNEL" -latest)
done

# order channels low -> high
CHANNELS_ORDER=$(
  for i in ${!VERSIONS[@]}; do
    echo "${VERSIONS[$i]}:::$i"
  done | sort -V | awk -F::: '{print $2}' |xargs
)

# join_by ',' ${A[@]} ${B[@]}
join_by() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

channels() {
  local s=()
  for CHANNEL in $CHANNELS_ORDER; do
    s+=("$CHANNEL:${VERSIONS[$CHANNEL]}")
  done
  join_by ' ' ${s[@]}
}

# display builds
echo  "BUILDING: $(channels) [${TARGETS[@]}]"

echo -e "\n\nCLEANUP ($(date))"
$SRC/cleanup.sh \
  -o "$OUT" \
  -i "$IMAGE" \
  -c $(join_by ' -c ' ${CHANNELS[@]}) \
  -v $(join_by ' -v ' ${VERSIONS[@]})
echo "ENDED CLEANUP ($(date))"

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
  $SRC/build-headless-shell.sh \
    -o $OUT \
    -s $SRCDIR \
    -c $CHANNEL \
    -a $ATTEMPTS \
    -j $JOBS \
    -k $JOBFAIL \
    $DRYRUN \
    $UPDATE \
    -t $(join_by ' -t ' ${TARGETS[@]}) \
    -v $VERSION \
  && RET=$?
  if [ $RET -ne 0 ]; then
    echo "COULD NOT BUILD $CHANNEL $VERSION ($(date))"
  fi
  echo "ENDED BUILD FOR $CHANNEL $VERSION ($(date))"
done

# build images
for CHANNEL in $CHANNELS_ORDER; do
  VERSION=${VERSIONS[$CHANNEL]}
  TAGS=($CHANNEL)
  if [ "$CHANNEL" = "stable" ]; then
    TAGS+=(latest)
  fi
  echo -e "\n\nSTARTING IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
  $SRC/build-image.sh \
    -o $OUT \
    -t $(join_by ' -t ' ${TARGETS[@]}) \
    -g $(join_by ' -g ' ${TAGS[@]}) \
    -v "$VERSION" \
    -i "$IMAGE" \
    $PUSH
  echo "ENDED IMAGE BUILD FOR CHANNEL $CHANNEL $VERSION ($(date))"
done

echo "DONE ($(date))"

popd &> /dev/null
