#!/bin/bash

SRC=${1:-/media/src/chromium/src}
VER=$2

FILES="headless/lib/headless_crash_reporter_client.cc headless/public/headless_browser.cc"

pushd $SRC &> /dev/null

set -ex

for f in $FILES; do
  git checkout $f
done

git rebase-update

if [ -z "$VER" ]; then
  VER=$(git tag -l|grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'|sort -r -V|head -1)
fi

PROJECT=out/headless_shell-$VER

git checkout $VER

gclient sync

for f in $FILES; do
  perl -pi -e 's/"HeadlessChrome"/"Chrome"/' $f
done

rm -rf $PROJECT

mkdir -p $PROJECT

echo 'import("//build/args/headless.gn")
is_debug=false
symbol_level=0
remove_webcore_debug_symbols=true' > $PROJECT/args.gn

gn gen $PROJECT

ninja -C $PROJECT headless_shell chrome_sandbox libosmesa.so

popd &> /dev/null
