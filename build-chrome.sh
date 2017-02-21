#!/bin/bash

PROJECT=out/Headless

VER=$1
SRC=${2:-/media/src/chromium/src}

pushd $SRC &> /dev/null

set -ve

git reset --hard

git rebase-update

if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

git checkout $VER

gclient sync

for f in "headless/lib/headless_crash_reporter_client.cc headless/public/headless_browser.cc"; do
  perl -pi -e 's/"HeadlessChrome"/"Chrome\/'$VER'"/' $f
done

ninja -C $PROJECT headless_shell chrome_sandbox
